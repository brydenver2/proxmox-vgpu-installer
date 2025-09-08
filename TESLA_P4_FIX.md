# Tesla P4 vGPU Configuration Fix

This document explains the Tesla P4 fix that has been integrated into the Proxmox vGPU installer.

## Problem

Tesla P4 cards have an issue where `nvidia-vgpu-mgr.service` loads incorrect mdevctl types:

- **Driver 16.1 (535.104.06)**: Shows P40 profiles instead of P4 profiles
- **Driver 16.9 (535.230.02)**: Shows P40 profiles instead of P4 profiles
- **Driver 17.0 (550.54.10)**: Shows no vGPU profiles at all

## Solution

The installer now automatically detects Tesla P4 cards and applies a configuration fix by:

1. **Detection**: Automatically detects Tesla P4 GPUs (device ID `1bb3`)
2. **Download**: Downloads NVIDIA driver 16.4 (535.161.05) to extract the correct `vgpuConfig.xml`
3. **Application**: Copies the correct configuration to `/usr/share/nvidia/vgpu/vgpuConfig.xml`
4. **Restart**: Restarts `nvidia-vgpu-mgr.service` to load the new configuration
5. **Verification**: Verifies that P4 vGPU types are now available via `mdevctl types`

## How It Works

### Automatic Detection
The fix automatically detects Tesla P4 GPUs during the installation process:

```bash
# Tesla P4 detection occurs automatically during GPU scanning
# No manual intervention required
```

### Installation Integration
The Tesla P4 fix is applied automatically during Step 2 of the installation:

1. Driver is installed normally
2. NVIDIA services are started
3. **Tesla P4 fix is applied automatically** (new)
4. Installation completes

### User Messages
Users with Tesla P4 cards will see additional messages:

```
[+] Tesla P4 GPU detected - applying vGPU configuration fix
[+] Tesla P4 detected - downloading driver 16.4 for vgpuConfig.xml
[+] Tesla P4 vgpuConfig.xml extracted successfully
[+] Installing Tesla P4 vgpuConfig.xml to /usr/share/nvidia/vgpu/
[+] Tesla P4 vGPU configuration applied successfully
[-] Restarting nvidia-vgpu-mgr.service to load new configuration
[+] Tesla P4 vGPU types are now available:
    nvidia-222 ( 1 of  4GB)
    nvidia-223 ( 2 of  4GB) 
    nvidia-224 ( 4 of  4GB)
    nvidia-252 ( 1 of  8GB)
    nvidia-253 ( 2 of  8GB)
[+] Tesla P4 vGPU configuration fix completed successfully
```

## Driver Compatibility

The Tesla P4 fix works with:
- **Driver 16.1 (535.104.06)**: Fixes P40 → P4 profile issue
- **Driver 16.9 (535.230.02)**: Fixes P40 → P4 profile issue
- **Driver 17.0 (550.54.10)**: Fixes missing profiles issue
- **All other drivers**: No impact, fix only applies to Tesla P4 cards

## Technical Details

### Files Modified
- **Source**: NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run (driver 16.4)
- **Target**: `/usr/share/nvidia/vgpu/vgpuConfig.xml`
- **Backup**: Original config backed up with timestamp

### Error Handling
- Graceful fallback if download fails
- Clear error messages if fix cannot be applied
- No impact on non-Tesla P4 systems
- Temporary files automatically cleaned up

### Requirements
- `megatools` package (automatically installed by the main script)
- Internet connection for driver 16.4 download
- Sufficient disk space for temporary driver extraction (~200MB)

## Manual Verification

After installation, you can verify the Tesla P4 fix worked:

```bash
# Check vGPU types are available
mdevctl types

# Should show Tesla P4/GRID P4 profiles like:
# nvidia-222  ( 1 of  4GB)  Available instances: 4
# nvidia-223  ( 2 of  4GB)  Available instances: 2  
# nvidia-224  ( 4 of  4GB)  Available instances: 1
# etc.

# Check nvidia services status
systemctl status nvidia-vgpu-mgr.service
systemctl status nvidia-vgpud.service

# Verify configuration file exists
ls -la /usr/share/nvidia/vgpu/vgpuConfig.xml
```

## Troubleshooting

### No vGPU Types After Fix
1. Wait a few minutes and try `mdevctl types` again
2. Restart the service: `systemctl restart nvidia-vgpu-mgr.service`
3. Check service logs: `journalctl -u nvidia-vgpu-mgr.service`
4. Reboot the system if needed

### Fix Not Applied
1. Verify Tesla P4 detection: `lspci -nn | grep 1bb3`
2. Check if `megatools` is installed: `which megadl`
3. Check internet connectivity for driver download
4. Look for error messages in installation log

### Manual Fix Application
If the automatic fix fails, you can apply it manually:

1. Download driver 16.4 manually
2. Extract with: `./NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run -x`
3. Copy config: `cp NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm/vgpuConfig.xml /usr/share/nvidia/vgpu/`
4. Restart service: `systemctl restart nvidia-vgpu-mgr.service`

## Acknowledgments

This fix is based on the solution discovered by the Proxmox community:
- **Source**: [Proxmox Forum - vGPU Tesla P4 wrong mdevctl GPU](https://forum.proxmox.com/threads/vgpu-tesla-p4-wrong-mdevctl-gpu.143247/page-2)
- **Key insight**: vgpuConfig.xml from driver 16.4 contains the correct Tesla P4 profiles
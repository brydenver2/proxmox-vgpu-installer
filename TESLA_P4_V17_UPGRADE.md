# Tesla P4 v17 Driver Installation Workflow

## Problem

Tesla P4 cards experience kernel module compilation failures when installing v17.0 driver directly. This is a known issue where the v17 driver installation process fails during DKMS module compilation.

## Solution

The installer now includes an enhanced Tesla P4 v16→v17 upgrade workflow that:

1. **Automatically detects** Tesla P4 + v17.0 driver combinations
2. **Installs v16.1 base driver first** to establish a stable foundation
3. **Upgrades to v17.0** using the `--force-update` flag for better compatibility
4. **Provides enhanced error handling** with detailed fallback guidance

## How It Works

### Automatic Detection
When you select v17.0 driver on a Tesla P4 system, the installer automatically:
- Detects Tesla P4 hardware (device ID 1bb3)
- Recognizes v17.0 driver selection (550.54.10)
- Triggers the enhanced upgrade workflow

### Enhanced Installation Process
```
Step 1: Install v16.1 base driver (535.104.06)
        ↓
Step 2: Upgrade to v17.0 driver (550.54.10)
        ↓
Step 3: Apply Tesla P4 vGPU configuration fix
        ↓
Step 4: Enable services for reboot
```

### Error Recovery
If the upgrade fails:
- v16.1 base driver remains functional
- Detailed error logs in `/var/log/nvidia-installer.log`
- Fallback options and troubleshooting guidance provided

## Usage

### Normal Installation
Simply select v17.0 during normal installation:
```bash
./proxmox-installer.sh
# Select option 8: 17.0 (550.54.10)
```

### Test Upgrade Workflow
Test if your system would trigger the upgrade workflow:
```bash
./proxmox-installer.sh --tesla-p4-upgrade-test
```

### Manual Troubleshooting
Check Tesla P4 status and get guidance:
```bash
./proxmox-installer.sh --tesla-p4-status
./proxmox-installer.sh --tesla-p4-help
```

## Requirements

- Tesla P4 GPU (device ID 1bb3)
- **Kernel Compatibility:**
  - v17.0 driver (550.54.10): Requires kernel 6.7.x or older
  - For kernel 6.8+: Use v16.9 (535.230.02) instead
- Proper kernel headers: `apt install proxmox-headers-$(uname -r | cut -d'-' -f1,2)`
- Internet connection for driver downloads
- megatools package (automatically installed)

## Troubleshooting

### Kernel Module Compilation Errors

#### iommu_ops API Compatibility Error
If you see this error:
```
error: 'const struct bus_type' has no member named 'iommu_ops'
```

**Cause:** Kernel 6.8+ removed the `iommu_ops` member from `bus_type` struct, but NVIDIA v17.0 driver (550.54.10) expects the old API.

**Solutions:**
1. **Use compatible driver version (Recommended):**
   - Install v16.9 (535.230.02) instead - fully compatible with newer kernels
   - Run: `./proxmox-installer.sh` and select option 7

2. **Use compatible kernel version:**
   - Install kernel 6.5.x: `apt install proxmox-kernel-6.5`
   - Reboot and select 6.5 kernel in GRUB menu
   - Then install v17.0 driver

3. **Continue with v16.1 base driver:**
   - The v16.1 driver installed during the upgrade workflow should work
   - Tesla P4 vGPU profiles will be available

#### General Compilation Issues
1. Ensure kernel headers are installed
2. Check kernel version compatibility  
3. Review nvidia-installer.log for specific errors
4. Consider using v16.9 as alternative

### Network Download Issues
1. Check internet connectivity
2. Install megatools manually: `apt install megatools`
3. Verify firewall allows HTTPS downloads

### Service Restart Issues
1. Reboot system after installation (required)
2. Check service status: `systemctl status nvidia-vgpu-mgr`
3. Verify mdev types: `mdevctl types`

## Expected Results

After successful installation and reboot:
```bash
mdevctl types | grep -i "p4-"
```

Should show Tesla P4 profiles like:
```
nvidia-222    GRID P4-1Q    (1GB VRAM, 4 instances)
nvidia-223    GRID P4-2Q    (2GB VRAM, 2 instances)  
nvidia-224    GRID P4-4Q    (4GB VRAM, 1 instance)
```

## Benefits

- **Prevents compilation failures** common with direct v17 installation
- **Maintains stability** through incremental upgrade approach
- **Enhanced error handling** with clear recovery options
- **Automatic detection** requires no manual intervention
- **Preserves functionality** even if upgrade fails

This workflow addresses the specific Tesla P4 issue mentioned in GitHub issue #22.
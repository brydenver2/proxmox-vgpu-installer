# Tesla P4 vGPU Configuration Fix

This document explains the Tesla P4 fix that has been integrated into the Proxmox vGPU installer.

## Problem

Tesla P4 cards have an issue where `nvidia-vgpu-mgr.service` loads incorrect mdevctl types:

- **Driver 17.4 (550.127.06)**: Shows P40 profiles instead of P4 profiles
- **Driver 18.4 (570.172.07)**: Shows no vGPU profiles at all
- **Driver 16.1 (535.104.06)**: Shows P40 profiles instead of P4 profiles
- **Driver 16.9 (535.230.02)**: Shows P40 profiles instead of P4 profiles
- **Driver 17.0 (550.54.10)**: Shows no vGPU profiles at all

This happens because NVIDIA dropped Pascal support in v17.x+ drivers, and the vgpuConfig.xml file in newer drivers doesn't contain Tesla P4 profile definitions.

## Solution

The installer now implements a two-step fix per PoloLoco's guide:

### Step 1: Apply PoloLoco's Driver Patch
During driver installation, the driver must be patched with PoloLoco's vgpu-proxmox patches:
```bash
./NVIDIA-Linux-x86_64-550.144.02-vgpu-kvm.run --apply-patch ~/vgpu-proxmox/550.144.02.patch
```

### Step 2: Replace vgpuConfig.xml with v16.4 Version
After driver installation, the vgpuConfig.xml file must be overwritten with the v16.4 driver's XML file, which contains the correct Tesla P4 profile definitions:
```bash
cp /path/to/v16.4/vgpuConfig.xml /usr/share/nvidia/vgpu/vgpuConfig.xml
```

The installer automatically:
1. **Downloads vgpu-proxmox patches** from PoloLoco's GitLab repository
2. **Patches the driver** using the appropriate patch file
3. **Installs the patched driver**
4. **Downloads and extracts v16.4 driver** (535.161.05-vgpu-kvm.run)
5. **Replaces vgpuConfig.xml** with the v16.4 version containing Pascal profiles
6. **Verifies** that Tesla P4 device ID (1BB3) is present in the config

## GPU-Specific Requirements

### vgpu_unlock Configuration
The installer automatically configures `/etc/vgpu_unlock/config.toml` based on GPU type:

#### Native vGPU Cards (unlock = false)
Cards with native vGPU support don't need unlock and should use `unlock = false`:
- **Tesla cards with native support**: Tesla V100, Tesla P100, Tesla M60, etc.
- **GRID cards**: GRID A100, GRID K series, etc.
- **Quadro RTX 6000/8000**: Native vGPU support
- **Tesla P4**: Special case - marked as requiring unlock in database but needs `unlock = false`

#### Consumer Cards (unlock = true)
Consumer cards require vgpu_unlock and should use `unlock = true`:
- **GeForce GTX series**: GTX 1050, 1060, 1070, 1080, 1080 Ti, 1650, 1660, etc.
- **GeForce RTX series**: RTX 2060, 2070, 2080, 3060, 3070, 3080, 4090, etc.
- **Quadro without native support**: Quadro P series, etc.

The installer detects your GPU type and automatically sets the correct `unlock` value.

### IOMMU Configuration  
The installer now provides a choice for `iommu=pt` parameter:

- **User Choice**: During installation, you'll be asked whether to include `iommu=pt`
- **Without iommu=pt** (recommended): Better stability, especially for Tesla P4 and similar cards
- **With iommu=pt**: May improve performance in some scenarios, but can cause unexpected behavior
- **Proper IOMMU**: Always uses `amd_iommu=on` or `intel_iommu=on` as appropriate

## Enhanced Error Handling

The fix now includes comprehensive error handling:

### Simplified Approach (v1.2+)
- **No service restarts**: System reboot required instead of unreliable service restarts
- **No fallback configuration**: Only uses official NVIDIA vgpuConfig.xml from driver 16.4
- **Clear messaging**: Users are informed that reboot is required, not service management
- **Reduced complexity**: Eliminates complex verification and retry logic that was unreliable

### Legacy Features (Removed)
- **Multiple retry attempts**: Removed - single attempt with clear failure messaging
- **Service restart logic**: Removed - system reboot required instead  
- **Built-in fallback configuration**: Removed - only official NVIDIA config used
- **Complex verification loops**: Removed - verification happens after reboot

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
2. Tesla P4 fix is applied automatically (copies correct vgpuConfig.xml)
3. System reboot required for changes to take effect
4. After reboot, Tesla P4 profiles should be available

### User Messages
Users with Tesla P4 cards will see additional messages during installation:

**Successful Installation:**
```
[+] Tesla P4 GPU detected - applying vGPU configuration fix
[-] This fix replaces vgpuConfig.xml with the correct Tesla P4 configuration from driver 16.4
[-] Checking network connectivity for Tesla P4 fix...
[+] Network connectivity verified
[-] Attempting download using megadl (method 1/3)
[-] Download attempt 1 of 3...
[+] Successfully downloaded using megadl
[+] Tesla P4 driver MD5 checksum verified
[+] Tesla P4 vgpuConfig.xml extracted successfully
[+] Installing Tesla P4 vgpuConfig.xml to /usr/share/nvidia/vgpu/
[+] File copied successfully
[+] Tesla P4 vGPU configuration applied successfully
[+] Configuration contains Tesla P4 device ID (1BB3)
[+] Tesla P4 vGPU configuration fix completed
[-] REBOOT REQUIRED: System must be rebooted for changes to take effect
[-] After reboot, Tesla P4 should show P4 profiles instead of P40 profiles
[-] Verify with: mdevctl types | grep -i 'p4-'
```
```

**Download Failed:**
```
[+] Tesla P4 GPU detected - applying vGPU configuration fix
[-] This fix replaces vgpuConfig.xml with the correct Tesla P4 configuration from driver 16.4
[!] Failed to download Tesla P4 configuration
[-] Manual fix instructions:
[-] 1. Install v17.0 driver first using this installer
[-] 2. Download NVIDIA driver 16.4: NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run
[-] 3. Extract: ./NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run -x
[-] 4. Copy config: cp NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm/vgpuConfig.xml /usr/share/nvidia/vgpu/
[-] 5. Reboot system
[-] 6. Verify: mdevctl types | grep -i 'p4-'
```

### Command Line Options

The installer now supports Tesla P4-specific command line options:

```bash
# Check Tesla P4 status and diagnose P40/P4 profile issues
./proxmox-installer.sh --tesla-p4-status

# Show Tesla P4 troubleshooting guide
./proxmox-installer.sh --tesla-p4-help

# Run only the Tesla P4 fix (for existing installations)
./proxmox-installer.sh --tesla-p4-fix

# Comprehensive validation of Tesla P4 setup
./validate_tesla_p4.sh

# Show all available options
./proxmox-installer.sh --help
```

## Diagnosing Tesla P4 Issues

The enhanced Tesla P4 fix now provides multiple ways to diagnose and verify the installation:

### Comprehensive Validation
```bash
./validate_tesla_p4.sh
```

This standalone script performs a complete validation:
- Hardware detection (Tesla P4 device ID 1bb3)
- NVIDIA service status checking
- Configuration file validation
- vGPU profile analysis (P4 vs P40)
- Specific recommendations based on findings

### Quick Status Check
```bash
./proxmox-installer.sh --tesla-p4-status
```

This built-in diagnostic tool:
- Detects if Tesla P4 is present (device ID 1bb3)
- Checks if NVIDIA services are running
- Verifies vgpuConfig.xml contains Tesla P4 data
- Identifies if P4 or P40 profiles are showing
- Provides specific recommendations

### Manual Verification
After running the installer or Tesla P4 fix, verify the results:

```bash
# Check for P4 profiles (correct)
mdevctl types | grep -i "p4-"

# Check for P40 profiles (incorrect - indicates fix needed)
mdevctl types | grep -i "p40-"

# Check NVIDIA services
systemctl status nvidia-vgpu-mgr.service
```

**Expected Tesla P4 Output:**
```
nvidia-222    Available instances: 4    Name: GRID P4-1Q
nvidia-223    Available instances: 2    Name: GRID P4-2Q  
nvidia-224    Available instances: 1    Name: GRID P4-4Q
```

**Problematic Output (indicates fix needed):**
```
nvidia-156    Available instances: 12   Name: GRID P40-2B
nvidia-215    Available instances: 12   Name: GRID P40-2B4
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
The Tesla P4 fix now includes comprehensive error handling:

- **Network Connectivity**: Checks internet connection before attempting downloads
- **Download Failures**: Multiple retry attempts with different methods
- **Missing Dependencies**: Clear instructions for installing required packages
- **File Corruption**: MD5 checksum verification with warnings for mismatches
- **Extraction Failures**: Timeout handling and disk space checks
- **Service Failures**: Detailed logging of service restart attempts
- **Fallback Configuration**: Built-in config when official download fails
- **Graceful Degradation**: Manual instructions when all automated methods fail

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

# Check vgpu_unlock configuration
ls -la /etc/vgpu_unlock/config.toml
grep "unlock" /etc/vgpu_unlock/config.toml

# Should show: unlock = false (for native vGPU cards and Tesla P4)
# Should show: unlock = true (for consumer cards like GTX/RTX)

# Verify GRUB configuration
grep "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub

# May or may not contain iommu=pt depending on your choice during installation
```

### Comprehensive Validation
Use the validation script for complete verification:

```bash
# Run Tesla P4 specific validation
./validate_tesla_p4.sh

# This checks:
# - Tesla P4 hardware detection
# - NVIDIA services status  
# - vgpuConfig.xml configuration
# - vgpu_unlock config.toml settings
# - Available vGPU profiles
```

## Troubleshooting

### No vGPU Types After Fix
1. Reboot the system (required for configuration changes)
2. After reboot, try `mdevctl types` again
3. Check service logs: `journalctl -u nvidia-vgpu-mgr.service`
4. Verify configuration file: `ls -la /usr/share/nvidia/vgpu/vgpuConfig.xml`

### Fix Not Applied
1. Verify Tesla P4 detection: `lspci -nn | grep 1bb3`
2. Check if `megatools` is installed: `which megadl`
3. Check internet connectivity for driver download
4. Look for error messages in installation log

### vgpu_unlock Configuration Issues
If you're experiencing vGPU profile issues, check vgpu_unlock configuration:

1. **Verify config.toml exists**: `ls -la /etc/vgpu_unlock/config.toml`
2. **Check unlock setting**: `cat /etc/vgpu_unlock/config.toml`
   - Should show: `unlock = false` for native vGPU cards and Tesla P4
   - Should show: `unlock = true` for consumer cards (GTX, RTX)
   - **Important**: The file should ONLY contain the unlock setting line, no other content
3. **Manual fix if needed**:
   ```bash
   # Edit the configuration file
   sudo nano /etc/vgpu_unlock/config.toml
   
   # For native vGPU cards (Tesla V100, P100, M60, GRID, Tesla P4):
   # The file should contain ONLY this single line:
   unlock = false
   
   # For consumer cards (GTX, RTX):
   # The file should contain ONLY this single line:
   unlock = true
   ```
4. **Regenerate configuration**: Run `./proxmox-installer.sh` to recreate config files
5. **Restart services**: 
   ```bash
   systemctl restart nvidia-vgpud nvidia-vgpu-mgr
   sleep 30
   mdevctl types
   ```

### IOMMU Issues
The installer now allows you to choose whether to include `iommu=pt`:

1. **During Installation**: You'll be prompted to choose whether to include `iommu=pt`
2. **If you experience performance issues**: Try adding `iommu=pt`
   ```bash
   # Edit GRUB configuration
   sudo nano /etc/default/grub
   
   # Add iommu=pt to GRUB_CMDLINE_LINUX_DEFAULT
   # For AMD: GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"
   # For Intel: GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
   
   sudo update-grub
   sudo reboot
   ```
3. **If you experience unexpected behavior**: Try removing `iommu=pt`
   ```bash
   sudo sed -i 's/ iommu=pt//g' /etc/default/grub
   sudo update-grub
   sudo reboot
   ```
4. **Recommended**: Start without `iommu=pt` for better stability, add it only if needed

### Manual Fix Application
If the automatic fix fails, you can apply it manually:

1. Download driver 16.4 manually from alternative sources
2. Extract with: `./NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run -x`
3. Copy config: `cp NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm/vgpuConfig.xml /usr/share/nvidia/vgpu/`
4. Reboot system: `reboot`
5. Verify: `mdevctl types | grep -i 'p4-'`

## Acknowledgments

This fix is based on the solution discovered by the Proxmox community:
- **Source**: [Proxmox Forum - vGPU Tesla P4 wrong mdevctl GPU](https://forum.proxmox.com/threads/vgpu-tesla-p4-wrong-mdevctl-gpu.143247/page-2)
- **Key insight**: vgpuConfig.xml from driver 16.4 contains the correct Tesla P4 profiles
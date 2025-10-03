# vGPU Installer Troubleshooting Guide

## Enhanced Diagnostics

The Proxmox vGPU installer now includes comprehensive logging and diagnostic capabilities to help troubleshoot driver installation issues.

### Logging Options

- **Normal mode**: Basic progress messages with errors logged to `debug.log`
- **Verbose mode** (`--verbose`): Detailed diagnostic output and command execution logs
- **Debug mode** (`--debug`): All command output shown in real-time (implies verbose)

### Usage Examples

```bash
# Normal installation
./proxmox-installer.sh

# Verbose logging for troubleshooting
./proxmox-installer.sh --verbose

# Debug mode with full output
./proxmox-installer.sh --debug

# Run specific step with verbose logging
./proxmox-installer.sh --verbose --step 2
```

### Log File Information

All installation activities are logged to `debug.log` in the script directory. The log includes:

- Timestamp for each operation
- System information (kernel, GPU, services)
- Command execution details and exit codes
- Error messages with context
- Service status and driver verification results

### Common Issues and Solutions

#### 1. Driver Installation Fails

**Symptoms:**
- Installation exits with error during driver compilation
- NVIDIA modules not loaded after installation

**Diagnosis:**
```bash
# Run with verbose logging
./proxmox-installer.sh --verbose --step 2

# Check kernel headers
ls -la /lib/modules/$(uname -r)/build

# Check for compilation errors
grep -i "error\|failed" debug.log
```

#### 2. Services Won't Start

**Symptoms:**
- nvidia-vgpud or nvidia-vgpu-mgr services fail to start
- No vGPU types available

**Diagnosis:**
```bash
# Check service status
systemctl status nvidia-vgpud.service
systemctl status nvidia-vgpu-mgr.service

# Check service logs
journalctl -u nvidia-vgpud.service -n 50
journalctl -u nvidia-vgpu-mgr.service -n 50

# Check for driver issues
nvidia-smi
dmesg | grep nvidia
```

#### 3. IOMMU Issues

**Symptoms:**
- Warning about disabled IOMMU
- PCI passthrough not working

**Diagnosis:**
```bash
# Check IOMMU status
dmesg | grep -i iommu

# Verify GRUB configuration
grep iommu /etc/default/grub

# Check IOMMU groups
find /sys/kernel/iommu_groups/ -type l
```

#### 4. Tesla P4 Profile Issues

**Symptoms:**
- Tesla P4 shows P40 profiles instead of P4 profiles
- No vGPU types available for Tesla P4

**Solution:**
```bash
# Run Tesla P4 specific fix
./proxmox-installer.sh --tesla-p4-fix

# Check troubleshooting guide
./proxmox-installer.sh --tesla-p4-help
```

### Reading Log Files

The log file contains timestamped entries for all operations:

```bash
# View recent log entries
tail -f debug.log

# Search for errors
grep -i error debug.log

# Search for specific operations
grep -A 5 -B 5 "driver installation" debug.log
```

### Getting Help

1. **Always run with `--verbose` when reporting issues**
2. **Include the complete `debug.log` file** when seeking help
3. **Note your system specifications**: Proxmox version, GPU model, kernel version
4. **Check the vGPU Unlocking Discord**: https://discord.gg/5rQsSV3Byq

### System Requirements Validation

The installer now logs comprehensive system information:

- Kernel version and available headers
- GPU detection and compatibility
- IOMMU status
- Service states
- Available disk space and memory

This information is automatically captured in verbose mode to aid in troubleshooting.
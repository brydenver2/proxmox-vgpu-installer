# Manual Driver Installation Guide

## Overview

If you manually install NVIDIA vGPU drivers (v17.2, v17.3, etc.) that are not yet included in the installer menu, you'll need to complete the vGPU setup manually. This guide covers the essential post-installation steps.

## Essential Components for Tesla P4

Tesla P4 GPUs require additional components beyond the NVIDIA driver:

1. **vgpu_unlock-rs library** - Essential for vGPU functionality
2. **Correct vGPU configuration** - Tesla P4-specific XML configuration
3. **Systemd service configuration** - Proper LD_PRELOAD setup

## Complete Manual Setup for Tesla P4

### Step 1: Install vgpu_unlock-rs

```bash
# Navigate to /opt and clone vgpu_unlock-rs
cd /opt
sudo rm -rf vgpu_unlock-rs 2>/dev/null
sudo git clone https://github.com/mbilker/vgpu_unlock-rs.git
cd vgpu_unlock-rs

# Install Rust if not already installed
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
source ~/.cargo/env

# Build the library
cargo build --release
```

### Step 2: Create Required Directories and Files

```bash
# Create vGPU unlock configuration directory
sudo mkdir -p /etc/vgpu_unlock
sudo touch /etc/vgpu_unlock/profile_override.toml

# Create systemd service override directories
sudo mkdir -p /etc/systemd/system/nvidia-vgpud.service.d
sudo mkdir -p /etc/systemd/system/nvidia-vgpu-mgr.service.d
```

### Step 3: Configure Systemd Services

```bash
# Add vgpu_unlock-rs library to nvidia-vgpud service
sudo tee /etc/systemd/system/nvidia-vgpud.service.d/vgpu_unlock.conf << EOF
[Service]
Environment=LD_PRELOAD=/opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so
EOF

# Add vgpu_unlock-rs library to nvidia-vgpu-mgr service
sudo tee /etc/systemd/system/nvidia-vgpu-mgr.service.d/vgpu_unlock.conf << EOF
[Service]
Environment=LD_PRELOAD=/opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so
EOF
```

### Step 4: Configure Tesla P4 vGPU Profiles

```bash
# Download correct Tesla P4 configuration
cd /tmp
wget -q https://us.download.nvidia.com/tesla/470.161.03/NVIDIA-Linux-x86_64-470.161.03-vgpu-kvm.run
chmod +x NVIDIA-Linux-x86_64-470.161.03-vgpu-kvm.run
./NVIDIA-Linux-x86_64-470.161.03-vgpu-kvm.run --extract-only

# Backup current configuration and replace with Tesla P4 version
sudo cp /usr/share/nvidia/vgpu/vgpuConfig.xml /usr/share/nvidia/vgpu/vgpuConfig.xml.backup
sudo cp NVIDIA-Linux-x86_64-470.161.03-vgpu-kvm/vgpuConfig.xml /usr/share/nvidia/vgpu/

# Clean up
rm -rf NVIDIA-Linux-x86_64-470.161.03-vgpu-kvm*
```

### Step 5: Restart Services

```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Stop services in reverse order
sudo systemctl stop nvidia-vgpu-mgr.service
sudo systemctl stop nvidia-vgpud.service
sleep 5

# Start services in correct order
sudo systemctl start nvidia-vgpud.service
sleep 5
sudo systemctl start nvidia-vgpu-mgr.service
sleep 15
```

### Step 6: Verify Installation

```bash
# Check service status
sudo systemctl status nvidia-vgpu-mgr.service
sudo systemctl status nvidia-vgpud.service

# Verify Tesla P4 profiles are available
mdevctl types | grep -i "p4-"

# Should show profiles like:
# nvidia-222    GRID P4-1Q    (1GB VRAM)
# nvidia-223    GRID P4-2Q    (2GB VRAM)
# nvidia-224    GRID P4-4Q    (4GB VRAM)
```

## Common Issues and Solutions

### Issue: "LD_PRELOAD cannot be preloaded"

**Symptoms:**
```
ERROR: ld.so: object '/opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so' from LD_PRELOAD cannot be preloaded
```

**Solution:**
1. Verify vgpu_unlock-rs was built successfully:
   ```bash
   ls -la /opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so
   ```
2. If file doesn't exist, rebuild vgpu_unlock-rs (Step 1 above)

### Issue: No mdevctl types showing

**Causes:**
1. Missing vgpu_unlock-rs library
2. Incorrect vGPU configuration
3. Services not restarted properly

**Solution:**
Follow all steps above in order, ensuring each completes successfully.

### Issue: P40 profiles instead of P4 profiles

**Solution:**
Ensure you completed Step 4 (Tesla P4 configuration) and restarted services properly.

## Driver Version Compatibility

### v17.3+ Drivers

Most v17.3+ drivers should work with kernel 6.8+ without the iommu_ops error that affects v17.0. However, you still need the complete vGPU setup (vgpu_unlock-rs + configuration) for Tesla P4.

### Recommended Approach

For production systems, consider using the installer's tested driver versions:
- **v16.9 (535.230.02)** - Fully tested with kernel 6.8+
- **v17.6 (550.90.07)** - Latest tested version in installer

Use manual installation only when you need specific features from newer drivers.

## Integration with Installer

After manual driver installation, you can still use installer features:

```bash
# Apply Tesla P4 configuration fix
./proxmox-installer.sh --tesla-p4-fix

# Validate Tesla P4 setup
./validate_tesla_p4.sh

# Check Tesla P4 status
./proxmox-installer.sh --tesla-p4-status
```

This ensures your manual installation is properly configured for Tesla P4 vGPU functionality.
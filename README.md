# vGPU Proxmox Script
This is a little Bash script that configures a Proxmox 7 or 8 server to use Nvidia vGPU's. 
For further instructions see wvthoog's blogpost at https://wvthoog.nl/proxmox-7-vgpu-v3/

## FastAPI-DLS Licensing Information
- **FastAPI-DLS Version 2.x** is backwards compatible to v17.x and supports **v18.x** and **v19.x** driver releases
- For v18.x and v19.x drivers, [gridd-unlock-patcher](https://git.collinwebdesigns.de/vgpu/gridd-unlock-patcher) is required for proper licensing functionality
- The installer uses the latest FastAPI-DLS v2.x Docker image from `collinwebdesigns/fastapi-dls:latest`
- For more information, see the [FastAPI-DLS documentation](https://git.collinwebdesigns.de/oscar.krause/fastapi-dls)

## Driver Information
- 17.6 & 18.1 is download only and only for natively support vGPU, lookup on NVIDIA for supported GPU ([v18.x](https://docs.nvidia.com/vgpu/18.0/product-support-matrix/index.html) & [v17.x](https://docs.nvidia.com/vgpu/17.0/product-support-matrix/index.html))
- **Patch Availability**: Patches for non-native GPU support are provided via [polloloco/vgpu-proxmox](https://gitlab.com/polloloco/vgpu-proxmox)
  - Available patches: v16.0-v16.9, v17.0-v17.6, v18.0-v18.4, v19.0
  - No patches available: v16.10, v16.11, v19.1, v19.2 (as of October 2025)
  - Drivers without patches require natively supported GPUs
- **Note**: As of October 2025, specific patch files available:
  - v18.2 (570.148.06) – `570.148.06.patch`
  - v18.3 (570.158.02) – `570.158.02.patch`
  - v18.4 (570.172.07) – `570.172.07.patch`
  - v19.0 (580.65.05) – `580.65.05.patch`

## Kernel Compatibility Requirements

### v16.x Drivers (535.x series) - Mixed Kernel Compatibility
**Kernel compatibility varies by v16.x version:**

#### Early v16.x Versions (v16.0-v16.7) - Kernel 6.5 Required
- v16.0 to v16.7 drivers (535.54.06 to 535.183.04) were developed and tested against kernel 6.5.x
- These drivers contain DKMS modules that are not compatible with newer kernel APIs (6.6+, 6.8+)
- **Automatic kernel pinning**: The script automatically detects these versions and pins kernel to 6.5.x

#### Later v16.x Versions (v16.8+) - Modern Kernel Support
- **v16.8** (535.216.01) and **v16.9** (535.230.02) include updated compatibility for newer kernels
- According to NVIDIA official documentation, **v16.8+ supports Ubuntu 24.04** (kernel 6.8+)
- **No kernel pinning required**: These versions can use modern kernel versions
- **Pascal GPU Support**: v16.9 (535.230.02) is recommended for Pascal architecture and older GPUs

### v17.x Drivers (550.x series) - Flexible Kernel Support  
- v17.x drivers (550.54.10 to 550.163.02) support kernel 6.5.x and newer versions
- These drivers include updated DKMS modules compatible with modern kernel APIs
- **No kernel pinning required**: Script allows using latest available kernel

### v18.x Drivers (570.x series) - Latest Kernel Support
- v18.x drivers (570.124.03 to 570.172.07) support latest kernels including 6.8+
- Most recent driver architecture with full modern kernel compatibility
- **No kernel pinning required**: Script allows using latest available kernel
- **Patch Availability**: Patches available for v18.2 (570.148.06), v18.3 (570.158.02), and v18.4 (570.172.07) via polloloco/vgpu-proxmox

### v19.x Drivers (580.x series) - Next Generation Support
- v19.x drivers (580.65.05 and newer) support latest kernels including 6.8+
- Next generation driver architecture with enhanced features
- **No kernel pinning required**: Script allows using latest available kernel
- **Patch Availability**: Patch available for v19.0 (580.65.05) via polloloco/vgpu-proxmox; v19.1 (580.82.02) and v19.2 (580.95.02) do not have patches available as of October 2025

### Technical Details
The script automatically:
1. Installs `proxmox-kernel-6.5` and `proxmox-headers-6.5` packages for compatibility
2. Analyzes your selected driver version during step 2
3. Applies selective kernel pinning:
   - **v16.0-v16.7**: Pins kernel to 6.5.x for compatibility 
   - **v16.8-v16.11**: Allows modern kernels (supports Ubuntu 24.04+)
   - **v17.x, v18.x, and v19.x**: Allows any available kernel version
4. Uses `proxmox-boot-tool kernel pin` only when required

For more information, see the [NVIDIA vGPU documentation](https://docs.nvidia.com/grid/) and kernel compatibility matrices.
Changes in version 1.3 (PoloLoco Guide Integration)
### Significant Updates Following PoloLoco's vGPU Guide
	**Repository Integration**: Updated to use PoloLoco's official vgpu-proxmox repository (https://gitlab.com/polloloco/vgpu-proxmox.git)
	**Download System Overhaul**: Removed hardcoded mega.nz download links - users must now provide driver URLs from official sources
	**vGPU Override Configuration**: Added comprehensive vGPU override creation following PoloLoco's guide
	**Enhanced Pascal Support**: Improved Pascal card support with v16.5 vgpuConfig.xml for v16.8+ drivers
	**User-Prompted Downloads**: New prompt system for driver URLs from NVIDIA Licensing Portal or trusted sources
	**Command Line Options**: Added --create-overrides and --configure-pascal-vm options
	**Menu Integration**: New menu options for vGPU overrides (6) and Pascal VM configuration (7)
	**PoloLoco Compliance**: All changes follow PoloLoco's official recommendations and best practices

### Key Features Added
- **vGPU Profile Overrides**: Configure custom display settings, VRAM allocation, and VM-specific overrides
- **Pascal Card Detection**: Automatic detection of Pascal GPUs (Tesla P4, Tesla P40, GTX 10xx, Quadro P series)
- **v16.5 vgpuConfig.xml Handling**: Automatic copying of v16.5 configuration for Pascal cards with v16.8+ drivers
- **Official Source Compliance**: Encourages use of NVIDIA Licensing Portal and official sources
- **Enhanced Help System**: Updated help messages and troubleshooting guides

### Breaking Changes
- **No More Hardcoded URLs**: Users must provide their own driver download URLs
- **Repository Change**: Now uses PoloLoco's official repository instead of PTHyperdrive fork
- **Interactive Prompts**: Driver downloads now require user interaction for URL input

### Pascal GPU Support (Following PoloLoco's Guide)
- **Automatic Detection**: Supports Tesla P4, Tesla P40, GTX 10xx series, and Quadro P series
- **v16.8+ Compatibility**: Automatically applies v16.5 vgpuConfig.xml when using v16.8+ drivers with Pascal cards
- **Tesla P4 Enhanced**: Improved Tesla P4 support with proper profile detection
- **VM ROM Spoofing**: Configure existing VMs or create new VMs with V100 device ID spoofing
- **Multiple GPU Support**: Add multiple Pascal cards to a single VM with proper ROM spoofing
- **Community Guidelines**: Follows PoloLoco's recommendations for Pascal card usage

### Tesla P4 Specific Improvements
- **vgpu_unlock Configuration**: Automatically creates config.toml with `unlock = false` for P4 cards
- **IOMMU Optimization**: Removes problematic `iommu=pt` parameter for better P4 stability
- **Profile Detection**: Enhanced validation script specifically for Tesla P4 profile verification
- **Troubleshooting**: Comprehensive Tesla P4 troubleshooting guidance and validation tools

### vGPU Override Features
- **Profile Configuration**: Configure display settings (resolution, displays, max_pixels)
- **VRAM Allocation**: Set custom framebuffer and framebuffer_reservation values
- **VM-Specific Overrides**: Create per-VM configurations with Proxmox VM IDs
- **Common Presets**: Quick setup for 512MB, 1GB, 2GB VRAM configurations
- **TOML Configuration**: Creates proper /etc/vgpu_unlock/profile_override.toml files

## Changes
Changes in version 1.2
### Added driver versions 16
	16.0
	16.1
	16.2
	16.3
	16.4 / 16.5
	16.7
	16.8
	16.9 !!! USE THIS IF YOU ARE ON PASCAL OR OLDER !!!
	16.10 (535.247.02) (No patch available - as of October 2025)
	16.11 (535.261.04) (No patch available - as of October 2025)
### Added driver versions 17
	17.0
	17.1
	17.3
	17.4
	17.5
	17.6 (Only Native vGPU support)
### Added driver versions 18
	18.0
	18.1 (Only Native vGPU support)
	18.2 (570.148.06) (Patch available via polloloco/vgpu-proxmox)
	18.3 (570.158.02) (Patch available via polloloco/vgpu-proxmox)
	18.4 (570.172.07) (Patch available via polloloco/vgpu-proxmox)
### Added driver versions 19
	19.0 (580.65.05) (Patch available via polloloco/vgpu-proxmox)
	19.1 (580.82.02) (No patch available - as of October 2025)
	19.2 (580.95.02) (No patch available - as of October 2025)
- Added checks for multiple GPU's
- Added MD5 checksums on downloaded files
- Created database to check for PCI ID's to determine if a GPU is natively supported
- **NVIDIA vGPU 16.0 Compliant Multi-GPU Support**: All vGPU-capable GPUs can be used simultaneously for vGPU with proper compatibility validation:
  - Driver compatibility validation across all selected GPUs
  - Mixed GPU architecture warnings and compatibility checks
  - Conservative single-GPU mode recommended for first-time setups
  - Advanced multi-GPU mode with comprehensive validation
  - Proper licensing guidance for multi-GPU deployments
- Only non-vGPU capable or explicitly excluded GPUs are configured for passthrough using UDEV rules
- Always write config.txt to script directory
- **FastAPI-DLS v2.x Support**: Updated to support v17.x, v18.x, and v19.x drivers
  - v18.x and v19.x require [gridd-unlock-patcher](https://git.collinwebdesigns.de/vgpu/gridd-unlock-patcher)
  - Backward compatible with v17.x (no additional requirements)
  - See [FastAPI-DLS v2.x Integration Guide](docs/FASTAPI_DLS_V2.md) for details
- Use Docker for hosting FastAPI-DLS (licensing) or using this docker [fastapi-dls](https://github.com/GreenDamTan/fastapi-dls_mirror) container on any host or capable server
- Create Powershell (ps1) and Bash (sh) files to retrieve licenses from FastAPI-DLS

## Usage (v1.3 PoloLoco Guide Integration)

### Quick Start
```bash
# Run the installer with enhanced PoloLoco guide integration
sudo ./proxmox-installer.sh

# Create vGPU overrides following PoloLoco's guide
sudo ./proxmox-installer.sh --create-overrides

# Show enhanced help with PoloLoco integration info
./proxmox-installer.sh --help
```

### Driver Download Process (New in v1.3)
The script no longer provides hardcoded download links. You must obtain drivers from official sources:

1. **NVIDIA Licensing Portal** (Recommended): https://nvid.nvidia.com/dashboard/
2. **NVIDIA vGPU Software**: https://www.nvidia.com/en-us/drivers/vgpu-software-driver/
3. **Community Sources**: PoloLoco vGPU Discord, trusted community resources

When prompted, provide the download URL for your chosen driver version.

### vGPU Override Configuration
Following PoloLoco's guide, you can create custom vGPU configurations:

```bash
# Interactive override creation
sudo ./proxmox-installer.sh --create-overrides

# Or use menu option 6 during installation
sudo ./proxmox-installer.sh
# Select option 6: Create vGPU overrides (PoloLoco guide)
```

### Pascal Card Support (Enhanced)
For Pascal cards (Tesla P4, Tesla P40, GTX 10xx, Quadro P series) with v16.8+ drivers:
- The script automatically detects Pascal GPUs
- Downloads and applies v16.5 vgpuConfig.xml for compatibility
- Follows PoloLoco's recommendations for Pascal card usage
- Provides proper troubleshooting guidance

### Pascal VM Configuration (ROM Spoofing)
New in v1.3: Configure Pascal cards for Proxmox VMs with ROM spoofing for v17+ drivers:

```bash
# Configure Pascal VM with ROM spoofing
sudo ./proxmox-installer.sh --configure-pascal-vm

# Or use menu option 7 during installation
sudo ./proxmox-installer.sh
# Select option 7: Configure Pascal VM (ROM spoofing)
```

**Features:**
- **Configure Existing VMs**: Add Pascal ROM spoofing to existing Proxmox VMs
- **Create New VMs**: Create basic VMs with Pascal ROM spoofing pre-configured
- **Multiple GPU Support**: Add multiple Pascal cards to a single VM
- **V100 Device ID Spoofing**: Uses Tesla V100 device IDs to trick guest drivers
- **Automatic PCI Detection**: Scans and lists available NVIDIA GPUs
- **mdev Type Selection**: Choose appropriate vGPU profiles (nvidia-63 to nvidia-69)

**Example Configuration:**
```
hostpci0: 0000:04:00.0,device-id=0x1DB6,mdev=nvidia-66,sub-device-id=0x12BF,sub-vendor-id=0x10de,vendor-id=0x10de
hostpci1: 0000:82:00.0,device-id=0x1DB6,mdev=nvidia-66,sub-device-id=0x12BF,sub-vendor-id=0x10de,vendor-id=0x10de
```

**Usage Notes:**
- Required for Pascal cards with NVIDIA drivers v17+
- Automatically stops/starts VMs during configuration
- Creates basic VMs that require further setup (storage, OS installation)
- Compatible with existing Pascal GPU detection system

### Command Line Options (Updated)
```bash
./proxmox-installer.sh [OPTIONS]

Options:
  --debug               Enable debug mode with verbose output
  --verbose             Enable verbose logging for diagnostics  
  --step <number>       Jump to specific installation step
  --url <url>           Use custom driver download URL
  --file <file>         Use local driver file
  --tesla-p4-fix        Run Tesla P4 vGPU configuration fix only
  --tesla-p4-help       Show Tesla P4 troubleshooting guide
  --tesla-p4-status     Check Tesla P4 vGPU profile status
  --create-overrides    Create vGPU overrides following PoloLoco's guide
  --configure-pascal-vm Configure Pascal card ROM spoofing for Proxmox VMs
```

### Menu Options (Updated)
1. New vGPU installation
2. Upgrade vGPU installation  
3. Remove vGPU installation
4. Download vGPU drivers (now with user-provided URLs)
5. License vGPU
6. **Create vGPU overrides (PoloLoco guide)** ← New in v1.3
7. **Configure Pascal VM (ROM spoofing)** ← New in v1.3
8. Exit

### PoloLoco Guide Compliance
This script now fully follows PoloLoco's official vGPU guide:
- Uses official PoloLoco vgpu-proxmox repository
- Implements recommended Pascal card handling
- Provides official source guidance for driver downloads
- Supports vGPU override configuration as documented
- Maintains compatibility with existing functionality

## Multi-GPU vGPU Configuration

### NVIDIA vGPU 16.0 Compliance Features

The installer now provides **NVIDIA vGPU 16.0 compliant multi-GPU support** with the following features:

#### Driver Compatibility Validation
- Automatically validates that all selected GPUs are compatible with the same driver version
- Prevents mixed driver version deployments that violate NVIDIA requirements
- Provides clear warnings when driver incompatibilities are detected

#### GPU Selection Modes
1. **Single GPU Mode (Recommended)**: Conservative approach for first-time setups
2. **Multi-GPU Mode (Advanced)**: Allows selecting multiple compatible GPUs
3. **All GPU Mode (Expert)**: Uses all available vGPU-capable cards with validation

#### Architecture Compatibility Checks
- Warns users about potential issues when mixing different GPU architectures
- Provides detailed compatibility information during selection
- Ensures optimal vGPU performance and stability

#### Licensing Compliance
- Clear guidance on licensing requirements for multi-GPU deployments
- Each vGPU-enabled GPU requires proper NVIDIA vGPU licensing
- FastAPI-DLS v2.x configuration with multi-GPU considerations
- See [FastAPI-DLS v2.x Integration Guide](docs/FASTAPI_DLS_V2.md) for licensing details

#### System Resource Validation
- Warnings about power and cooling requirements for multi-GPU setups
- Ensures users understand system requirements before deployment

## 🚀 Contributing
All Credit belong to wvthoog for creating the V1.1 script

All Thanks to foxipan at this [repo](https://alist.homelabproject.cc/foxipan) for providing the required drivers/patches/custom

Many thank to everone on [vGPU Unlocking Discord](https://discord.gg/5rQsSV3Byq) for making vGPU easier for everone to get access, also this is the link for [vGPU-Patch](https://gitlab.com/polloloco/vgpu-proxmox)

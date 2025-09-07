# vGPU Proxmox Script
This is a little Bash script that configures a Proxmox 7 or 8 server to use Nvidia vGPU's. 
For further instructions see wvthoog's blogpost at https://wvthoog.nl/proxmox-7-vgpu-v3/

## WARNING !!!
- fastapi-dls is not working correctly with v18.x but working fine on v17.x, please consider this for extended use
- 17.6 & 18.1 is download only and only for natively support vGPU, lookup on NVIDIA for supported GPU ([v18.x](https://docs.nvidia.com/vgpu/18.0/product-support-matrix/index.html) & [v17.x](https://docs.nvidia.com/vgpu/17.0/product-support-matrix/index.html))

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
- v18.x drivers (570.124.03 to 570.133.10) support latest kernels including 6.8+
- Most recent driver architecture with full modern kernel compatibility
- **No kernel pinning required**: Script allows using latest available kernel

### Technical Details
The script automatically:
1. Installs `proxmox-kernel-6.5` and `proxmox-headers-6.5` packages for compatibility
2. Analyzes your selected driver version during step 2
3. Applies selective kernel pinning:
   - **v16.0-v16.7**: Pins kernel to 6.5.x for compatibility 
   - **v16.8-v16.9**: Allows modern kernels (supports Ubuntu 24.04+)
   - **v17.x and v18.x**: Allows any available kernel version
4. Uses `proxmox-boot-tool kernel pin` only when required

For more information, see the [NVIDIA vGPU documentation](https://docs.nvidia.com/grid/) and kernel compatibility matrices.
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
- Added checks for multiple GPU's
- Added MD5 checksums on downloaded files
- Created database to check for PCI ID's to determine if a GPU is natively supported
- If multiple GPU's are detected, pass through the rest using UDEV rules
- Always write config.txt to script directory
- Use Docker for hosting FastAPI-DLS (licensing) or using this docker [fastapi-dls](https://github.com/GreenDamTan/fastapi-dls_mirror) container on any host or capable server
- Create Powershell (ps1) and Bash (sh) files to retrieve licenses from FastAPI-DLS

## 🚀 Contributing
All Credit belong to wvthoog for creating the V1.1 script

All Thanks to foxipan at this [repo](https://alist.homelabproject.cc/foxipan) for providing the required drivers/patches/custom

Many thank to everone on [vGPU Unlocking Discord](https://discord.gg/5rQsSV3Byq) for making vGPU easier for everone to get access, also this is the link for [vGPU-Patch](https://gitlab.com/polloloco/vgpu-proxmox)

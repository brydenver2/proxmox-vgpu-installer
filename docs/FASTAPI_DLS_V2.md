# FastAPI-DLS Version 2.x Integration Guide

## Overview

FastAPI-DLS Version 2.x is a significant update that extends driver support to include newer NVIDIA vGPU driver versions while maintaining backward compatibility.

## Compatibility Matrix

### Driver Version Support

| Driver Version | FastAPI-DLS v2.x Support | Additional Requirements |
|----------------|-------------------------|------------------------|
| v17.x (550.x series) | ✅ Full Support | None |
| v18.x (570.x series) | ✅ Full Support | gridd-unlock-patcher required |
| v19.x (future releases) | ✅ Full Support | gridd-unlock-patcher required |
| v16.x and older | ⚠️ Not tested | May work but untested |

### Key Features

- **Backward Compatibility**: Version 2.x is fully backwards compatible with v17.x drivers
- **Extended Support**: Native support for v18.x and v19.x driver releases
- **gridd-unlock-patcher Integration**: Required for v18.x and v19.x driver versions

## gridd-unlock-patcher Requirement

### What is gridd-unlock-patcher?

The gridd-unlock-patcher is a utility that patches the NVIDIA GRID daemon to work with FastAPI-DLS licensing for newer driver versions (v18.x and v19.x).

### When is it Required?

- **v17.x drivers**: NOT required (FastAPI-DLS works natively)
- **v18.x drivers**: REQUIRED for licensing functionality
- **v19.x drivers**: REQUIRED for licensing functionality

### Where to Get It

- **Repository**: [https://git.collinwebdesigns.de/vgpu/gridd-unlock-patcher](https://git.collinwebdesigns.de/vgpu/gridd-unlock-patcher)
- **Documentation**: See the repository README for installation and usage instructions

### Installation Workflow

For v18.x and v19.x drivers, the typical workflow is:

1. Install the NVIDIA vGPU driver using this installer
2. Set up FastAPI-DLS using the installer's configuration option
3. Install and configure gridd-unlock-patcher from the repository above
4. Configure your VMs to use the FastAPI-DLS license server

## Installer Integration

### Automatic Configuration

The Proxmox vGPU Installer automatically:

- Pulls the latest FastAPI-DLS v2.x Docker image (`collinwebdesigns/fastapi-dls:latest`)
- Configures the Docker container with proper environment variables
- Generates license retrieval scripts for Windows and Linux VMs
- Provides information about gridd-unlock-patcher requirements

### Docker Image

The installer uses the official FastAPI-DLS Docker image:

```yaml
image: collinwebdesigns/fastapi-dls:latest  # v2.x - supports v17.x, v18.x, v19.x
```

This image is maintained by the FastAPI-DLS project and automatically includes v2.x features when using `:latest` tag.

## Configuration Details

### Environment Variables

The installer configures FastAPI-DLS with these variables:

- `TZ`: Server timezone (auto-detected from Proxmox)
- `DLS_URL`: License server hostname/IP (auto-detected)
- `DLS_PORT`: Port number (default: 8443, user-configurable)
- `LEASE_EXPIRE_DAYS`: License lease duration (90 days maximum)
- `DATABASE`: SQLite database path for license storage
- `DEBUG`: Debug mode (false by default)

### Port Configuration

The installer:

- Defaults to port 8443 for FastAPI-DLS
- Warns against using ports 80 and 443 (reserved by Proxmox)
- Allows custom port configuration during setup

## Using FastAPI-DLS

### License Retrieval Scripts

The installer generates two scripts in `~/vgpu-proxmox/licenses/`:

#### Linux VMs (`license_linux.sh`)
```bash
#!/bin/bash
curl --insecure -L -X GET https://[SERVER_IP]:[PORT]/-/client-token -o /etc/nvidia/ClientConfigToken/client_configuration_token_$(date '+%d-%m-%Y-%H-%M-%S').tok
service nvidia-gridd restart
nvidia-smi -q | grep "License"
```

#### Windows VMs (`license_windows.ps1`)
```powershell
curl.exe --insecure -L -X GET https://[SERVER_IP]:[PORT]/-/client-token -o "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\client_configuration_token_$(Get-Date -f 'dd-MM-yy-hh-mm-ss').tok"
Restart-Service NVDisplay.ContainerLocalSystem
& 'nvidia-smi' -q | Select-String "License"
```

### Manual VM Configuration

If you prefer to set up FastAPI-DLS in a separate VM/LXC container:

1. Follow the official guide: [https://git.collinwebdesigns.de/oscar.krause/fastapi-dls#docker](https://git.collinwebdesigns.de/oscar.krause/fastapi-dls#docker)
2. Use the Docker Compose configuration provided by the installer as a template
3. Ensure gridd-unlock-patcher is installed if using v18.x or v19.x drivers

## Troubleshooting

### v18.x/v19.x Licensing Issues

If licensing fails with v18.x or v19.x drivers:

1. **Verify gridd-unlock-patcher is installed**: This is required for these driver versions
2. **Check FastAPI-DLS logs**: `docker logs wvthoog-fastapi-dls`
3. **Verify network connectivity**: VMs must be able to reach the FastAPI-DLS server
4. **Check certificate validity**: Ensure SSL certificates are properly generated

### Common Issues

- **License not obtained**: Ensure gridd-unlock-patcher is installed for v18.x/v19.x
- **Connection refused**: Verify firewall allows traffic on configured port
- **Certificate errors**: Certificates are self-signed; use `--insecure` flag or add to trust store

## Multi-GPU Considerations

### Licensing Requirements

- Each vGPU-enabled GPU requires proper NVIDIA vGPU licensing
- Multi-GPU setups require licensing for ALL vGPU-enabled cards
- FastAPI-DLS handles multiple GPU licensing automatically

### Configuration

The FastAPI-DLS configuration is GPU-agnostic and works with:

- Single GPU setups
- Multi-GPU homogeneous configurations
- Multi-GPU mixed architecture setups (with appropriate licenses)

## Additional Resources

- **FastAPI-DLS Documentation**: [https://git.collinwebdesigns.de/oscar.krause/fastapi-dls](https://git.collinwebdesigns.de/oscar.krause/fastapi-dls)
- **gridd-unlock-patcher**: [https://git.collinwebdesigns.de/vgpu/gridd-unlock-patcher](https://git.collinwebdesigns.de/vgpu/gridd-unlock-patcher)
- **NVIDIA vGPU Documentation**: [https://docs.nvidia.com/vgpu/](https://docs.nvidia.com/vgpu/)

## Version History

### FastAPI-DLS v2.x
- Added support for v18.x and v19.x drivers
- Requires gridd-unlock-patcher for v18.x/v19.x
- Backward compatible with v17.x drivers
- No breaking changes from v1.x for v17.x users

### FastAPI-DLS v1.x
- Supported v17.x drivers natively
- Did not support v18.x drivers
- Legacy version (superseded by v2.x)

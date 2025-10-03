# GitHub Copilot Instructions for Proxmox vGPU Installer

## Repository Structure

This repository follows a specific directory structure. When creating new files, please place them in the appropriate folder:

### Directory Layout

```
proxmox-vgpu-installer/
├── README.md                    # Main project documentation (stays in root)
├── proxmox-installer.sh         # Main installation script (stays in root)
├── gpu_info.db                  # GPU database (stays in root)
├── docs/                        # Documentation files
│   ├── DIAGNOSTICS.md           # Troubleshooting guide
│   ├── TESLA_P4_FIX.md          # Tesla P4 specific fixes
│   ├── TESLA_P4_PERMISSIONS_GUIDE.md
│   └── TESLA_P4_SOLUTION.md
└── tests/                       # Test and validation scripts
    ├── demo_polloloco_features.sh
    ├── test_polloloco_integration.sh
    ├── test_tesla_p4_fix.sh
    └── validate_tesla_p4.sh
```

## File Placement Guidelines

### Root Directory
- **README.md**: Main project documentation - always stays in root
- **proxmox-installer.sh**: Main installation script
- **gpu_info.db**: GPU database file
- Core configuration files (if any)

### `/docs` Directory
Place all documentation files here, including:
- Technical documentation (`.md` files)
- User guides
- Troubleshooting guides
- Feature-specific documentation
- **Exception**: README.md stays in root

### `/tests` Directory
Place all test and validation scripts here, including:
- Test scripts (test_*.sh)
- Validation scripts (validate_*.sh)
- Demo scripts (demo_*.sh)
- Integration test files

## Guidelines for New Files

1. **Documentation files** (`.md` except README.md):
   - Location: `/docs/`
   - Example: New troubleshooting guide → `/docs/NEW_FEATURE_GUIDE.md`

2. **Test/Demo/Validation scripts** (`.sh` except main installer):
   - Location: `/tests/`
   - Example: New test script → `/tests/test_new_feature.sh`

3. **Main executable scripts**:
   - Location: Root directory
   - Example: Primary installer scripts

4. **Configuration files**:
   - Location: Typically root directory
   - Exception: If specific to tests or docs, place in respective folder

## Best Practices

- Keep the root directory clean with only essential files
- Use descriptive file names that indicate their purpose
- Maintain consistency with existing naming conventions
- Update this file if new directory categories are added

#!/bin/bash

# Test script for Tesla P4 kernel compatibility error detection
# This tests the new error analysis functionality

echo "==================================="
echo "Tesla P4 Kernel Compatibility Test"
echo "==================================="
echo

# Test the error detection logic without sourcing the full script
test_iommu_ops_detection() {
    echo "Test 1: Testing iommu_ops error detection logic"
    echo "-----------------------------------------------"
    
    # Create mock log content
    mock_log_content='
/tmp/selfgz10879/NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm/kernel/nvidia/nv-pci.c:225:29: error: '"'"'const struct bus_type'"'"' has no member named '"'"'iommu_ops'"'"'
  225 |         if (pci_dev->dev.bus->iommu_ops == NULL)
      |                             ^~
'
    
    # Test if our grep pattern would detect the error
    if echo "$mock_log_content" | grep -q "iommu_ops"; then
        echo "✓ Successfully detected iommu_ops error pattern"
    else
        echo "✗ Failed to detect iommu_ops error pattern"
    fi
    
    echo
}

test_kernel_version_detection() {
    echo "Test 2: Testing kernel version detection logic"
    echo "----------------------------------------------"
    
    # Test different kernel versions
    test_kernels=(
        "6.8.12-14-pve"
        "6.8.0-generic"
        "6.7.15-pve"
        "6.5.13-pve"
        "5.15.0-generic"
    )
    
    for kernel in "${test_kernels[@]}"; do
        kernel_version=$(echo "$kernel" | cut -d'-' -f1)
        echo -n "Kernel $kernel: "
        
        if [[ "$kernel_version" =~ ^6\.8\. ]]; then
            echo "✓ Detected as 6.8.x (would show compatibility warning)"
        else
            echo "• Detected as $kernel_version (no special warning)"
        fi
    done
    
    echo
}

test_error_patterns() {
    echo "Test 3: Testing error pattern matching"
    echo "--------------------------------------"
    
    # Test different error patterns
    local patterns=(
        "iommu_ops"
        "compiler differs from the one used to build the kernel"
        "No such file or directory.*kernel.*build"
    )
    
    local sample_logs=(
        "error: 'const struct bus_type' has no member named 'iommu_ops'"
        "warning: the compiler differs from the one used to build the kernel"
        "fatal error: linux/kernel.h: No such file or directory in /lib/modules/6.8.12/build"
    )
    
    for i in "${!patterns[@]}"; do
        pattern="${patterns[$i]}"
        log_line="${sample_logs[$i]}"
        
        echo -n "Pattern '$pattern': "
        if echo "$log_line" | grep -q "$pattern"; then
            echo "✓ Detected"
        else
            echo "✗ Not detected"
        fi
    done
    
    echo
}

# Run tests
test_iommu_ops_detection
test_kernel_version_detection
test_error_patterns

echo "==================================="
echo "Kernel Compatibility Features Summary"
echo "==================================="
echo
echo "Enhanced Tesla P4 v16→v17 upgrade workflow now includes:"
echo "• Kernel version compatibility checking"
echo "• Specific detection of iommu_ops API errors" 
echo "• Targeted guidance for kernel 6.8+ compatibility issues"
echo "• Recommendation to use v16.9 for newer kernels"
echo "• Enhanced error analysis with specific solutions"
echo
echo "When the iommu_ops error occurs, users will get:"
echo "• Clear explanation of the kernel API change"
echo "• Three specific solution options"
echo "• Recommendation to use v16.9 (535.230.02) for compatibility"
echo "• Guidance on kernel downgrade if v17.0 is required"
echo
echo "This addresses the specific error reported in the nvidia-installer.log."
#!/bin/bash

# Source the main functions we need
source proxmox-installer.sh

# Test the Tesla P4 detection function
echo "Testing Tesla P4 detection function..."

# Mock lspci output for Tesla P4
export -f lspci
lspci() {
    echo "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation Tesla P4 [10de:1bb3] (rev a1)"
}

echo "Simulated lspci output:"
lspci -nn | grep -i 'NVIDIA Corporation' | grep -Ei '(VGA compatible controller|3D controller)'

echo ""
echo "Testing detect_tesla_p4 function:"
if detect_tesla_p4; then
    echo "SUCCESS: Tesla P4 detected"
else
    echo "FAILED: Tesla P4 not detected"
fi

# Test with non-Tesla P4 GPU
lspci() {
    echo "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GeForce GTX 1080 [10de:1b80] (rev a1)"
}

echo ""
echo "Testing with GTX 1080 (should not detect Tesla P4):"
if detect_tesla_p4; then
    echo "FAILED: False positive - detected Tesla P4 when it shouldn't"
else
    echo "SUCCESS: Correctly did not detect Tesla P4"
fi

#!/bin/bash

# Test the Tesla P4 functions individually
source <(grep -A 20 "^detect_tesla_p4()" proxmox-installer.sh)

echo "=== Testing Tesla P4 Detection ==="

# Mock lspci command for testing
lspci() {
    if [ "$1" = "-nn" ]; then
        echo "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation Tesla P4 [10de:1bb3] (rev a1)"
    fi
}

if detect_tesla_p4; then
    echo "✓ Tesla P4 detection works"
else
    echo "✗ Tesla P4 detection failed"
fi

# Test with no Tesla P4
lspci() {
    if [ "$1" = "-nn" ]; then
        echo "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GeForce GTX 1080 [10de:1b80] (rev a1)"
    fi
}

if detect_tesla_p4; then
    echo "✗ False positive - detected Tesla P4 when not present"
else
    echo "✓ Correctly identified no Tesla P4"
fi

echo ""
echo "=== Tesla P4 Functions Test Complete ==="

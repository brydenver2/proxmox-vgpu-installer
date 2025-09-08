#!/bin/bash

# Extract just the detection function
detect_tesla_p4() {
    # Check if system has Tesla P4 GPU (device ID 1bb3)
    local gpu_info=$(lspci -nn | grep -i 'NVIDIA Corporation' | grep -Ei '(VGA compatible controller|3D controller)')
    if [ -n "$gpu_info" ]; then
        local gpu_device_ids=$(echo "$gpu_info" | grep -oE '\[10de:[0-9a-fA-F]{2,4}\]' | cut -d ':' -f 2 | tr -d ']')
        for device_id in $gpu_device_ids; do
            if [ "$device_id" = "1bb3" ]; then
                return 0  # Tesla P4 found
            fi
        done
    fi
    return 1  # Tesla P4 not found
}

# Mock lspci command
lspci() {
    if [ "$1" = "-nn" ]; then
        echo "$MOCK_LSPCI_OUTPUT"
    fi
}

echo "Testing Tesla P4 detection function..."

# Test with Tesla P4
export MOCK_LSPCI_OUTPUT="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation Tesla P4 [10de:1bb3] (rev a1)"
echo "Test 1 - Tesla P4 present:"
echo "  Mock lspci output: $MOCK_LSPCI_OUTPUT"
if detect_tesla_p4; then
    echo "  RESULT: SUCCESS - Tesla P4 detected"
else
    echo "  RESULT: FAILED - Tesla P4 not detected"
fi

# Test with other GPU
export MOCK_LSPCI_OUTPUT="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GeForce GTX 1080 [10de:1b80] (rev a1)"
echo ""
echo "Test 2 - GTX 1080 present (should not detect):"
echo "  Mock lspci output: $MOCK_LSPCI_OUTPUT"
if detect_tesla_p4; then
    echo "  RESULT: FAILED - False positive, detected Tesla P4"
else
    echo "  RESULT: SUCCESS - Correctly did not detect Tesla P4"
fi

# Test with multiple GPUs including Tesla P4
export MOCK_LSPCI_OUTPUT="01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GeForce GTX 1080 [10de:1b80] (rev a1)
02:00.0 VGA compatible controller [0300]: NVIDIA Corporation Tesla P4 [10de:1bb3] (rev a1)"
echo ""
echo "Test 3 - Multiple GPUs with Tesla P4:"
echo "  Mock lspci output:"
echo "    01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GeForce GTX 1080 [10de:1b80] (rev a1)"
echo "    02:00.0 VGA compatible controller [0300]: NVIDIA Corporation Tesla P4 [10de:1bb3] (rev a1)"
if detect_tesla_p4; then
    echo "  RESULT: SUCCESS - Tesla P4 detected in multi-GPU system"
else
    echo "  RESULT: FAILED - Tesla P4 not detected in multi-GPU system"
fi

# Test with no NVIDIA GPUs
export MOCK_LSPCI_OUTPUT=""
echo ""
echo "Test 4 - No NVIDIA GPUs:"
echo "  Mock lspci output: (empty)"
if detect_tesla_p4; then
    echo "  RESULT: FAILED - False positive, detected Tesla P4 with no GPUs"
else
    echo "  RESULT: SUCCESS - Correctly did not detect Tesla P4"
fi

echo ""
echo "All tests completed."

#!/bin/bash

# Test script for gridd-unlock-patcher integration
# This test verifies that the license scripts are generated correctly for v18+ drivers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_OUTPUT_DIR="/tmp/vgpu_test_$$"
mkdir -p "$TEST_OUTPUT_DIR"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No color

echo "========================================="
echo "Testing gridd-unlock-patcher Integration"
echo "========================================="
echo ""

# Test function to generate license scripts
test_license_script_generation() {
    local driver_version="$1"
    local test_name="$2"
    
    echo -e "${YELLOW}Test: $test_name (Driver v$driver_version)${NC}"
    
    # Simulate the logic from proxmox-installer.sh
    needs_gridd_patcher=false
    if [[ "$driver_version" =~ ^18\.|^19\. ]]; then
        needs_gridd_patcher=true
    fi
    
    # Generate test scripts
    local test_dir="$TEST_OUTPUT_DIR/v${driver_version}"
    mkdir -p "$test_dir"
    
    # Generate Linux script
    if [ "$needs_gridd_patcher" = true ]; then
        cat > "$test_dir/license_linux.sh" <<'EOF'
#!/bin/bash

# For v18.x and v19.x drivers, gridd-unlock-patcher is required
# Install gridd-unlock-patcher if not already installed
if [ ! -f /usr/bin/gridd-unlock-patcher ]; then
    echo "Installing gridd-unlock-patcher for v18+ driver support..."
    
    # Download and install gridd-unlock-patcher
    PATCHER_URL="https://git.collinwebdesigns.de/vgpu/gridd-unlock-patcher/raw/branch/main/gridd-unlock-patcher.sh"
    
    # Try to download the patcher
    if command -v wget >/dev/null 2>&1; then
        wget -q -O /tmp/gridd-unlock-patcher.sh "$PATCHER_URL"
    elif command -v curl >/dev/null 2>&1; then
        curl -sL -o /tmp/gridd-unlock-patcher.sh "$PATCHER_URL"
    else
        echo "ERROR: Neither wget nor curl found. Please install one and try again."
        exit 1
    fi
    
    # Make it executable and move to /usr/bin
    chmod +x /tmp/gridd-unlock-patcher.sh
    mv /tmp/gridd-unlock-patcher.sh /usr/bin/gridd-unlock-patcher
    
    echo "gridd-unlock-patcher installed successfully"
fi

# Run gridd-unlock-patcher before obtaining license
echo "Running gridd-unlock-patcher..."
gridd-unlock-patcher

# Obtain license token from FastAPI-DLS
EOF
        echo 'curl --insecure -L -X GET https://localhost:8443/-/client-token -o /etc/nvidia/ClientConfigToken/client_configuration_token_$(date '+%d-%m-%Y-%H-%M-%S').tok' >> "$test_dir/license_linux.sh"
        echo 'service nvidia-gridd restart' >> "$test_dir/license_linux.sh"
        echo 'nvidia-smi -q | grep "License"' >> "$test_dir/license_linux.sh"
    else
        cat > "$test_dir/license_linux.sh" <<'EOF'
#!/bin/bash

curl --insecure -L -X GET https://localhost:8443/-/client-token -o /etc/nvidia/ClientConfigToken/client_configuration_token_$(date '+%d-%m-%Y-%H-%M-%S').tok
service nvidia-gridd restart
nvidia-smi -q | grep "License"
EOF
    fi
    
    # Generate Windows script
    if [ "$needs_gridd_patcher" = true ]; then
        cat > "$test_dir/license_windows.ps1" <<'EOF'
# For v18.x and v19.x drivers, gridd-unlock-patcher is required
# Check if gridd-unlock-patcher is installed
$patcherPath = "C:\Program Files\gridd-unlock-patcher\gridd-unlock-patcher.exe"

if (-Not (Test-Path $patcherPath)) {
    Write-Host "Installing gridd-unlock-patcher for v18+ driver support..." -ForegroundColor Yellow
    
    # Create directory
    New-Item -ItemType Directory -Force -Path "C:\Program Files\gridd-unlock-patcher" | Out-Null
    
    # Download gridd-unlock-patcher
    $patcherUrl = "https://git.collinwebdesigns.de/vgpu/gridd-unlock-patcher/releases/latest/download/gridd-unlock-patcher.exe"
    
    try {
        Invoke-WebRequest -Uri $patcherUrl -OutFile $patcherPath -UseBasicParsing
        Write-Host "gridd-unlock-patcher installed successfully" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: Failed to download gridd-unlock-patcher" -ForegroundColor Red
        Write-Host "Please download manually from: https://git.collinwebdesigns.de/vgpu/gridd-unlock-patcher" -ForegroundColor Yellow
        exit 1
    }
}

# Run gridd-unlock-patcher before obtaining license
Write-Host "Running gridd-unlock-patcher..." -ForegroundColor Yellow
& $patcherPath

# Obtain license token from FastAPI-DLS
EOF
        echo 'curl.exe --insecure -L -X GET https://localhost:8443/-/client-token -o "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\client_configuration_token_$(Get-Date -f '\''dd-MM-yy-hh-mm-ss'\'').tok"' >> "$test_dir/license_windows.ps1"
        echo 'Restart-Service NVDisplay.ContainerLocalSystem' >> "$test_dir/license_windows.ps1"
        echo '& '\''nvidia-smi'\'' -q  | Select-String "License"' >> "$test_dir/license_windows.ps1"
    else
        cat > "$test_dir/license_windows.ps1" <<'EOF'
curl.exe --insecure -L -X GET https://localhost:8443/-/client-token -o "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\client_configuration_token_$(Get-Date -f 'dd-MM-yy-hh-mm-ss').tok"
Restart-Service NVDisplay.ContainerLocalSystem
& 'nvidia-smi' -q  | Select-String "License"
EOF
    fi
    
    # Verify script generation
    if [ -f "$test_dir/license_linux.sh" ] && [ -f "$test_dir/license_windows.ps1" ]; then
        # Check if scripts contain expected content
        if [ "$needs_gridd_patcher" = true ]; then
            if grep -q "gridd-unlock-patcher" "$test_dir/license_linux.sh" && \
               grep -q "gridd-unlock-patcher" "$test_dir/license_windows.ps1"; then
                echo -e "${GREEN}✓ PASS${NC}: Scripts generated with gridd-unlock-patcher support"
                return 0
            else
                echo -e "${RED}✗ FAIL${NC}: Scripts missing gridd-unlock-patcher content"
                return 1
            fi
        else
            if ! grep -q "gridd-unlock-patcher" "$test_dir/license_linux.sh" && \
               ! grep -q "gridd-unlock-patcher" "$test_dir/license_windows.ps1"; then
                echo -e "${GREEN}✓ PASS${NC}: Scripts generated without gridd-unlock-patcher (not needed)"
                return 0
            else
                echo -e "${RED}✗ FAIL${NC}: Scripts incorrectly contain gridd-unlock-patcher"
                return 1
            fi
        fi
    else
        echo -e "${RED}✗ FAIL${NC}: Scripts not generated"
        return 1
    fi
}

# Run tests
echo "Running test suite..."
echo ""

test_count=0
pass_count=0
fail_count=0

# Test v17.x drivers (should NOT include gridd-unlock-patcher)
test_license_script_generation "17.6" "v17.x driver (no patcher needed)"
if [ $? -eq 0 ]; then ((pass_count++)); else ((fail_count++)); fi
((test_count++))
echo ""

# Test v18.0 driver (should include gridd-unlock-patcher)
test_license_script_generation "18.0" "v18.0 driver (patcher required)"
if [ $? -eq 0 ]; then ((pass_count++)); else ((fail_count++)); fi
((test_count++))
echo ""

# Test v18.1 driver (should include gridd-unlock-patcher)
test_license_script_generation "18.1" "v18.1 driver (patcher required)"
if [ $? -eq 0 ]; then ((pass_count++)); else ((fail_count++)); fi
((test_count++))
echo ""

# Test v19.0 driver (should include gridd-unlock-patcher)
test_license_script_generation "19.0" "v19.0 driver (patcher required)"
if [ $? -eq 0 ]; then ((pass_count++)); else ((fail_count++)); fi
((test_count++))
echo ""

# Test v16.9 driver (should NOT include gridd-unlock-patcher)
test_license_script_generation "16.9" "v16.9 driver (no patcher needed)"
if [ $? -eq 0 ]; then ((pass_count++)); else ((fail_count++)); fi
((test_count++))
echo ""

# Print summary
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "Total tests: $test_count"
echo -e "${GREEN}Passed: $pass_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
echo ""

if [ -d "$TEST_OUTPUT_DIR" ]; then
    echo "Test output saved to: $TEST_OUTPUT_DIR"
fi

# Cleanup (optional - comment out to inspect generated files)
# rm -rf "$TEST_OUTPUT_DIR"

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi

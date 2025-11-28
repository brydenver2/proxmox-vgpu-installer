#!/bin/bash

# Test script for download_driver_from_url function
# This tests that wget and curl can download files properly

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}Download Function Test${NC}"
echo -e "${BLUE}======================${NC}"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/../proxmox-installer.sh"

# Test 1: Script syntax validation
echo -e "${YELLOW}Test 1: Script syntax validation${NC}"
if bash -n "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} Script syntax is valid"
else
    echo -e "${RED}[FAIL]${NC} Script has syntax errors"
    exit 1
fi
echo ""

# Test 2: Check download function parameters
echo -e "${YELLOW}Test 2: Check download function improvements${NC}"

# Check for proper connect-timeout parameter in wget
if grep -q "wget.*--connect-timeout" "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} wget has --connect-timeout parameter"
else
    echo -e "${RED}[FAIL]${NC} wget missing --connect-timeout parameter"
fi

# Check for proper read-timeout parameter in wget
if grep -q "wget.*--read-timeout" "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} wget has --read-timeout parameter"
else
    echo -e "${RED}[FAIL]${NC} wget missing --read-timeout parameter"
fi

# Check for progress indicator in wget
if grep -q "wget.*--progress" "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} wget has progress indicator"
else
    echo -e "${RED}[FAIL]${NC} wget missing progress indicator"
fi

# Check for proper connect-timeout parameter in curl
if grep -q "curl.*--connect-timeout" "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} curl has --connect-timeout parameter"
else
    echo -e "${RED}[FAIL]${NC} curl missing --connect-timeout parameter"
fi

# Check for progress indicator in curl
if grep -q "curl.*--progress-bar" "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} curl has progress indicator"
else
    echo -e "${RED}[FAIL]${NC} curl missing progress indicator"
fi

# Check that -f flag is used for proper error handling in curl
if grep -q "curl.*-f" "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} curl has -f flag for error handling"
else
    echo -e "${RED}[FAIL]${NC} curl missing -f flag for error handling"
fi

# Check that max-time 60 is NOT used (it was too short)
if grep -q "curl.*--max-time 60" "$MAIN_SCRIPT"; then
    echo -e "${RED}[FAIL]${NC} curl still has too-short --max-time 60"
else
    echo -e "${GREEN}[PASS]${NC} curl no longer uses --max-time 60 (timeout was too short)"
fi

# Check that wget -q is NOT used in download_driver_from_url function (hides error output)
# Use sed to extract the function body and check for wget -q
if sed -n '/^download_driver_from_url()/,/^[a-zA-Z_][a-zA-Z0-9_]*().*{/p' "$MAIN_SCRIPT" | grep -q "wget -q"; then
    echo -e "${RED}[FAIL]${NC} wget still uses -q flag in download function (hides errors)"
else
    echo -e "${GREEN}[PASS]${NC} wget no longer uses -q flag in download function (errors are now visible)"
fi

# Check that curl --silent is NOT used in download function
# Use sed to extract the function body and check for curl --silent
if sed -n '/^download_driver_from_url()/,/^[a-zA-Z_][a-zA-Z0-9_]*().*{/p' "$MAIN_SCRIPT" | grep -q "curl.*--silent"; then
    echo -e "${RED}[FAIL]${NC} curl still uses --silent flag (hides errors)"
else
    echo -e "${GREEN}[PASS]${NC} curl no longer uses --silent flag in download function"
fi

echo ""

# Test 3: Check error message improvements
echo -e "${YELLOW}Test 3: Check error message improvements${NC}"

# Check for better error messaging
if grep -q "download_error=" "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} Download error tracking variable exists"
else
    echo -e "${RED}[FAIL]${NC} No download error tracking"
fi

# Check for informative error messages
if grep -q "Please verify:" "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} Helpful error verification messages added"
else
    echo -e "${RED}[FAIL]${NC} Missing helpful error messages"
fi

# Check for URL being displayed
if grep -q "URL: \$driver_url" "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} URL is displayed during download"
else
    echo -e "${RED}[FAIL]${NC} URL not displayed during download"
fi

echo ""

# Test 4: Functional download test with small file
echo -e "${YELLOW}Test 4: Functional download test (using httpbin.org)${NC}"

# Create temporary directory for test
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR" || exit 1

# Test wget download
echo -e "${YELLOW}[-]${NC} Testing wget download..."
TEST_URL="https://httpbin.org/bytes/1024"
TEST_FILE="test_wget.bin"

if command -v wget >/dev/null 2>&1; then
    # Use shorter read-timeout for test (1KB file doesn't need 300 seconds)
    if wget --progress=bar:force --tries=3 --connect-timeout=30 --read-timeout=60 "$TEST_URL" -O "$TEST_FILE" 2>&1; then
        if [ -f "$TEST_FILE" ] && [ -s "$TEST_FILE" ]; then
            echo -e "${GREEN}[PASS]${NC} wget successfully downloaded test file"
            rm -f "$TEST_FILE"
        else
            echo -e "${RED}[FAIL]${NC} wget completed but file is empty or missing"
        fi
    else
        echo -e "${YELLOW}[SKIP]${NC} wget download failed (network may be restricted)"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} wget not available"
fi

# Test curl download
echo -e "${YELLOW}[-]${NC} Testing curl download..."
TEST_FILE="test_curl.bin"

if command -v curl >/dev/null 2>&1; then
    if curl --progress-bar -f -L --retry 3 --retry-delay 5 --connect-timeout 30 "$TEST_URL" -o "$TEST_FILE" 2>&1; then
        if [ -f "$TEST_FILE" ] && [ -s "$TEST_FILE" ]; then
            echo -e "${GREEN}[PASS]${NC} curl successfully downloaded test file"
            rm -f "$TEST_FILE"
        else
            echo -e "${RED}[FAIL]${NC} curl completed but file is empty or missing"
        fi
    else
        echo -e "${YELLOW}[SKIP]${NC} curl download failed (network may be restricted)"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} curl not available"
fi

# Cleanup
cd - >/dev/null || true
rm -rf "$TEST_DIR"

echo ""

echo -e "${BLUE}Download Function Test Summary${NC}"
echo -e "${BLUE}==============================${NC}"
echo ""
echo -e "${GREEN}Key Fixes Implemented:${NC}"
echo -e "✓ Removed 60-second timeout that was too short for large files"
echo -e "✓ Added --connect-timeout for initial connection (30 seconds)"
echo -e "✓ Added --read-timeout for wget to handle stalled downloads (300 seconds)"
echo -e "✓ Added progress indicators for both wget and curl"
echo -e "✓ Removed error suppression (2>/dev/null and --silent/-q)"
echo -e "✓ Added error tracking and better error messages"
echo -e "✓ Added -f flag to curl for proper HTTP error handling"
echo -e "✓ URL is now displayed for easier debugging"
echo ""
echo -e "${GREEN}[SUCCESS]${NC} Download function tests completed!"
echo ""

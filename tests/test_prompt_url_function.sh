#!/bin/bash

# Test script for prompt_for_driver_url function
# This tests that the function properly separates informational output (stderr)
# from the URL value (stdout) so that command substitution works correctly.
#
# Issue: The original function outputted all messages to stdout, so when
# called with command substitution like driver_url=$(prompt_for_driver_url ...),
# the variable would contain all the messages plus the URL, causing download
# failures with errors like "Invalid host name" and "curl: (3) bad range in URL"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}Testing prompt_for_driver_url Function${NC}"
echo -e "${BLUE}=======================================${NC}"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="${SCRIPT_DIR}/../proxmox-installer.sh"

PASS_COUNT=0
FAIL_COUNT=0

# Test 1: Script syntax validation
echo -e "${YELLOW}Test 1: Script syntax validation${NC}"
if bash -n "$MAIN_SCRIPT" 2>/dev/null; then
    echo -e "${GREEN}[PASS]${NC} Script syntax is valid"
    ((PASS_COUNT++))
else
    echo -e "${RED}[FAIL]${NC} Script has syntax errors"
    ((FAIL_COUNT++))
fi
echo ""

# Test 2: Check that informational messages in prompt_for_driver_url go to stderr
echo -e "${YELLOW}Test 2: Informational messages redirect to stderr${NC}"

# Extract the function content - find from function start to its closing brace
# Use awk to extract the function body more reliably
function_content=$(awk '/^prompt_for_driver_url\(\)/{found=1} found{print; if(/^}$/){exit}}' "$MAIN_SCRIPT")
stderr_count=$(echo "$function_content" | grep -c ">&2" 2>/dev/null || echo "0")

if [ "$stderr_count" -ge 15 ]; then
    echo -e "${GREEN}[PASS]${NC} Found $stderr_count stderr redirections (expected >= 15)"
    ((PASS_COUNT++))
else
    echo -e "${RED}[FAIL]${NC} Only found $stderr_count stderr redirections (expected >= 15)"
    ((FAIL_COUNT++))
fi
echo ""

# Test 3: Verify final URL output goes to stdout only
echo -e "${YELLOW}Test 3: Final URL output goes to stdout (not stderr)${NC}"

# The function should end with 'echo "$url"' without >&2
# Use single quotes and escape properly for the grep pattern
if echo "$function_content" | grep -E 'echo "\$url"$' | grep -qv '>&2'; then
    echo -e "${GREEN}[PASS]${NC} Final echo outputs URL to stdout only"
    ((PASS_COUNT++))
else
    echo -e "${RED}[FAIL]${NC} Final URL output may have stderr redirection"
    ((FAIL_COUNT++))
fi
echo ""

# Test 4: Verify "Using URL:" message goes to stderr
echo -e "${YELLOW}Test 4: 'Using URL:' message goes to stderr${NC}"

if grep -q 'Using URL.*>&2' "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} 'Using URL:' message properly redirects to stderr"
    ((PASS_COUNT++))
else
    echo -e "${RED}[FAIL]${NC} 'Using URL:' message does not redirect to stderr"
    ((FAIL_COUNT++))
fi
echo ""

# Test 5: Verify "Driver Download Required" message goes to stderr
echo -e "${YELLOW}Test 5: 'Driver Download Required' message goes to stderr${NC}"

if grep -q 'Driver Download Required.*>&2' "$MAIN_SCRIPT"; then
    echo -e "${GREEN}[PASS]${NC} 'Driver Download Required' message properly redirects to stderr"
    ((PASS_COUNT++))
else
    echo -e "${RED}[FAIL]${NC} 'Driver Download Required' message does not redirect to stderr"
    ((FAIL_COUNT++))
fi
echo ""

# Test 6: Verify error messages in the function go to stderr
echo -e "${YELLOW}Test 6: Error messages in prompt_for_driver_url go to stderr${NC}"

if echo "$function_content" | grep -q 'URL cannot be empty.*>&2'; then
    echo -e "${GREEN}[PASS]${NC} 'URL cannot be empty' message properly redirects to stderr"
    ((PASS_COUNT++))
else
    echo -e "${RED}[FAIL]${NC} 'URL cannot be empty' message does not redirect to stderr"
    ((FAIL_COUNT++))
fi
echo ""

# Test 7: Verify 'Please provide a valid HTTP/HTTPS URL' goes to stderr
echo -e "${YELLOW}Test 7: 'Please provide a valid HTTP/HTTPS URL' message goes to stderr${NC}"

if echo "$function_content" | grep -q 'valid HTTP/HTTPS URL.*>&2'; then
    echo -e "${GREEN}[PASS]${NC} 'Please provide a valid HTTP/HTTPS URL' message properly redirects to stderr"
    ((PASS_COUNT++))
else
    echo -e "${RED}[FAIL]${NC} 'Please provide a valid HTTP/HTTPS URL' message does not redirect to stderr"
    ((FAIL_COUNT++))
fi
echo ""

# Summary
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}============${NC}"
echo ""
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS]${NC} All tests passed!"
    echo ""
    echo "The prompt_for_driver_url function now properly separates:"
    echo "  • Informational messages → stderr (displayed to user)"
    echo "  • URL value → stdout (captured by command substitution)"
    echo ""
    echo "This fixes the issue where download commands received corrupted URLs"
    echo "containing informational messages, causing errors like:"
    echo "  • 'Invalid host name'"
    echo "  • 'curl: (3) bad range in URL position 4:'"
    exit 0
else
    echo -e "${RED}[FAILURE]${NC} Some tests failed!"
    exit 1
fi

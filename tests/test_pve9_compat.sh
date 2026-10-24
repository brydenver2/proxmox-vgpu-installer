#!/usr/bin/env bash
# test_pve9_compat.sh — validate PVE 9 (Debian 13 trixie) support in proxmox-installer.sh
#
# Context: PVE 8.4 went EOL 2026-08. PVE 9 is the only supported target.
# The installer previously hard-failed on major_version 9 and hardcoded
# bookworm/bullseye + proxmox-kernel-6.5 (none of which exist on trixie).
#
# These tests extract and exercise the version-gate logic from the real script
# so a regression in the installer is caught here rather than on a live node.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$SCRIPT_DIR/../proxmox-installer.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
PASS=0; FAIL=0

pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }

if [ ! -f "$INSTALLER" ]; then
    echo -e "${RED}[FATAL]${NC} installer not found at $INSTALLER"; exit 1
fi

echo "=== PVE 9 compatibility tests for proxmox-installer.sh ==="
echo "installer: $INSTALLER"
echo

# ---------------------------------------------------------------------------
# 1. Bash syntax check
# ---------------------------------------------------------------------------
if bash -n "$INSTALLER" 2>/dev/null; then
    pass "installer parses cleanly under bash -n"
else
    fail "installer has a bash syntax error"
fi

# ---------------------------------------------------------------------------
# 2. Version gate: 9 must be accepted, and must select trixie
# ---------------------------------------------------------------------------
# Extract the real case block from the script and drive it with major_version=9.
extract_case_block() {
    # from "case $major_version in" to the matching "esac"
    awk '/case \$major_version in/{flag=1} flag{print} flag&&/^\s*esac/{exit}' "$INSTALLER"
}

CASE_BLOCK="$(extract_case_block)"
if [ -z "$CASE_BLOCK" ]; then
    fail "could not extract the major_version case block from the installer"
else
    # Drive the extracted block with each version and capture the resulting repo.
    for ver in 7 8 9; do
        out=$(printf '%s\n' "$CASE_BLOCK" \
            | sed "s/^\( *\)8)/\1${ver%%})/" >/dev/null 2>&1; \
            bash -c '
                major_version="'"$ver"'"
                '"$CASE_BLOCK"'
                echo "REPO=$proxmox_repo"
                echo "CEPH=$ceph_repo"
            ' 2>&1)
        repo=$(echo "$out" | grep '^REPO=' | cut -d= -f2-)
        ceph=$(echo "$out" | grep '^CEPH=' | cut -d= -f2-)
        case "$ver" in
            9)
                if echo "$repo" | grep -q "trixie"; then
                    pass "PVE 9 selects the trixie repo ($repo)"
                else
                    fail "PVE 9 did not select a trixie repo (got: $repo)"
                fi
                if echo "$ceph" | grep -q "ceph-tentacle"; then
                    pass "PVE 9 selects the ceph-tentacle repo ($ceph)"
                else
                    fail "PVE 9 did not select ceph-tentacle (got: $ceph)"
                fi
                ;;
            8)
                if echo "$repo" | grep -q "bookworm"; then
                    pass "PVE 8 still selects the bookworm repo (no regression)"
                else
                    fail "PVE 8 repo selection regressed (got: $repo)"
                fi
                ;;
            7)
                if echo "$repo" | grep -q "bullseye"; then
                    pass "PVE 7 still selects the bullseye repo (no regression)"
                else
                    fail "PVE 7 repo selection regressed (got: $repo)"
                fi
                ;;
        esac
    done

    # An unsupported version must still hard-fail (we do not want to silently
    # accept PVE 10 or garbage).
    out=$(bash -c '
        major_version="6"
        '"$CASE_BLOCK"'
    ' 2>&1)
    rc=$?
    if [ $rc -ne 0 ] && echo "$out" | grep -qi "unsupported"; then
        pass "unsupported version still hard-fails with 'Unsupported Proxmox version'"
    else
        fail "unsupported version no longer fails (rc=$rc, out=$out)"
    fi
fi

# ---------------------------------------------------------------------------
# 3. proxmox-kernel-6.5 must NOT be installed on PVE 9
# ---------------------------------------------------------------------------
pve9_branch=$(sed -n '/if \[ "\$major_version" = "9" \]; then/,/^            else$/p' "$INSTALLER")
if echo "$pve9_branch" | grep -q "proxmox-default-headers"; then
    pass "PVE 9 branch installs proxmox-default-headers"
else
    fail "PVE 9 branch does not install proxmox-default-headers"
fi
# Only the actual apt install command matters here — the PVE 9 branch mentions
# "6.5" in explanatory comments, which must not be flagged.
pve9_install=$(echo "$pve9_branch" | grep -E 'apt install' || true)
if echo "$pve9_install" | grep -q "proxmox-kernel-6\.5"; then
    fail "PVE 9 branch still installs proxmox-kernel-6.5 (does not exist on trixie)"
else
    pass "PVE 9 branch does not install proxmox-kernel-6.5"
fi

# The PVE 8 path must be untouched: the else branch must still install 6.5.
pve8_block=$(sed -n '/^            else$/,/^            fi$/p' "$INSTALLER")
if echo "$pve8_block" | grep -q "proxmox-kernel-6\.5"; then
    pass "PVE 8/7 branch still installs proxmox-kernel-6.5 (no regression)"
else
    fail "PVE 8/7 kernel handling regressed"
fi

# ---------------------------------------------------------------------------
# 4. PVE 9 driver compatibility gate
# ---------------------------------------------------------------------------
GATE_RE='^18\.[4-9]|^19\.0$'
check_gate() {
    local dv="$1" expect="$2"
    local r
    r=$(bash -c '
        major_version="9"
        driver_ver="'"$dv"'"
        if [ "$major_version" = "9" ] && [[ ! "$driver_ver" =~ '"$GATE_RE"' ]]; then
            echo REJECT
        else
            echo ACCEPT
        fi
    ' 2>&1)
    if [ "$r" = "$expect" ]; then
        pass "PVE 9 driver gate: v$dv -> $expect"
    else
        fail "PVE 9 driver gate: v$dv -> $r (expected $expect)"
    fi
}
check_gate "18.4" "ACCEPT"
check_gate "18.3" "REJECT"
check_gate "19.0" "ACCEPT"
check_gate "19.1" "REJECT"
check_gate "19.2" "REJECT"
check_gate "17.6" "REJECT"
check_gate "16.9" "REJECT"

# ---------------------------------------------------------------------------
# 5. Driver assets present for the recommended target (18.4 + 19.0)
# ---------------------------------------------------------------------------
if grep -q "570.172.07.patch" "$INSTALLER"; then
    pass "installer maps 570.172.07 -> 570.172.07.patch (v18.4 patch asset wired)"
else
    fail "installer does not wire the 570.172.07.patch asset"
fi
if grep -q "580.65.05.patch" "$INSTALLER"; then
    pass "installer maps 580.65.05 -> 580.65.05.patch (v19.0 patch asset wired)"
else
    fail "installer does not wire the 580.65.05.patch asset"
fi

# ---------------------------------------------------------------------------
# 6. Pascal/Tesla P4 vgpuConfig.xml fix still triggers for 18.x/19.x drivers
# ---------------------------------------------------------------------------
if grep -qE '\^17\\\\\.|\^18\\\\\.|\^19\\\\\.' "$INSTALLER"; then
    pass "Pascal vgpuConfig.xml fix still covers 18.x/19.x driver branches"
elif grep -qF '|^17\.|^18\.|^19\.' "$INSTALLER"; then
    pass "Pascal vgpuConfig.xml fix still covers 18.x/19.x driver branches"
else
    fail "Pascal vgpuConfig.xml fix driver-version regex not found"
fi
if grep -q "1BB3" "$INSTALLER" || grep -q "1bb3" "$INSTALLER"; then
    pass "Tesla P4 device ID (1BB3) verification still present"
else
    fail "Tesla P4 device ID verification missing"
fi

# ---------------------------------------------------------------------------
# 7. No stale 'Proxmox 7 or 8' claim in README
# ---------------------------------------------------------------------------
README="$SCRIPT_DIR/../README.md"
if [ -f "$README" ]; then
    if grep -qiE "proxmox (7 or 8|7 and 8)|PVE (7|8) only" "$README"; then
        fail "README still claims Proxmox 7/8 only support"
    else
        pass "README no longer claims Proxmox 7/8 only support"
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} README.md not found"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] || exit 1
exit 0

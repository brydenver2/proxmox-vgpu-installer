#!/bin/bash

CONFIG_FILE="config.txt"

# Variables
LOG_FILE="debug.log"
DEBUG=false
VERBOSE=false
STEP="${STEP:-1}"
URL="${URL:-}"
FILE="${FILE:-}"
DRIVER_VERSION="${DRIVER_VERSION:-}"
SCRIPT_VERSION=1.3
VGPU_DIR="$(realpath "$(pwd)")"
VGPU_SUPPORT="${VGPU_SUPPORT:-}"
DRIVER_VERSION="${DRIVER_VERSION:-}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
ORANGE='\033[0;33m'
PURPLE='\033[0;35m'
GRAY='\033[0;37m'
NC='\033[0m' # No color

if [ -f "$VGPU_DIR/$CONFIG_FILE" ]; then
    source "$VGPU_DIR/$CONFIG_FILE"
fi

# Function to test file permissions and accessibility for NVIDIA services
test_nvidia_config_permissions() {
    local config_file="/usr/share/nvidia/vgpu/vgpuConfig.xml"
    
    echo -e "${YELLOW}[-]${NC} Testing NVIDIA configuration file permissions"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}[!]${NC} Configuration file does not exist: $config_file"
        return 1
    fi
    
    # Test basic file accessibility
    if [ -r "$config_file" ]; then
        echo -e "${GREEN}[+]${NC} Configuration file is readable"
    else
        echo -e "${RED}[!]${NC} Configuration file is not readable"
        return 1
    fi
    
    # Check file ownership and permissions
    local file_perms=$(ls -la "$config_file" 2>/dev/null)
    echo -e "${YELLOW}[-]${NC} File permissions: $file_perms"
    
    # Check if file has correct ownership (should be root:root or similar)
    local file_owner=$(stat -c "%U:%G" "$config_file" 2>/dev/null || echo "unknown")
    echo -e "${YELLOW}[-]${NC} File ownership: $file_owner"
    
    # Test if file can be read by checking its content
    local file_size=$(stat -c%s "$config_file" 2>/dev/null || echo "0")
    if [ "$file_size" -gt 0 ]; then
        echo -e "${GREEN}[+]${NC} Configuration file has content (${file_size} bytes)"
        
        # Test if file contains Pascal device IDs
        if grep -q "1BB3\|1bb3\|1B38\|1b38" "$config_file" 2>/dev/null; then
            echo -e "${GREEN}[+]${NC} Configuration contains Pascal device IDs"
        else
            echo -e "${YELLOW}[-]${NC} Configuration may not contain Pascal device IDs"
        fi
        
        # Check for P40 entries (should not be present)
        if grep -q "P40-\|1B38\|1b38" "$config_file" 2>/dev/null; then
            echo -e "${YELLOW}[-]${NC} Warning: Configuration contains P40 references"
        else
            echo -e "${GREEN}[+]${NC} No P40 references found in configuration"
        fi
    else
        echo -e "${RED}[!]${NC} Configuration file is empty"
        return 1
    fi
    
    # Check SELinux context if available
    if command -v ls >/dev/null 2>&1 && ls --help 2>&1 | grep -q "\-Z"; then
        local selinux_context=$(ls -Z "$config_file" 2>/dev/null | awk '{print $1}')
        if [ -n "$selinux_context" ]; then
            echo -e "${YELLOW}[-]${NC} SELinux context: $selinux_context"
        fi
    fi
    
    echo -e "${GREEN}[+]${NC} Configuration file permissions test completed"
    return 0
}

# Function to detect Pascal GPUs (all Pascal architecture cards)
detect_pascal_gpu() {
    # Check if system has Pascal GPU (includes Tesla P4/P40, GTX 10xx, Quadro P series)
    local gpu_info=$(lspci -nn | grep -i 'NVIDIA Corporation' | grep -Ei '(VGA compatible controller|3D controller)')
    if [ -n "$gpu_info" ]; then
        if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] Found NVIDIA GPU(s):${NC}"
            echo "$gpu_info" | sed 's/^/  /'
        fi
        
        local gpu_device_ids=$(echo "$gpu_info" | grep -oE '\[10de:[0-9a-fA-F]{2,4}\]' | cut -d ':' -f 2 | tr -d ']')
        if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] Extracted device IDs: $gpu_device_ids${NC}"
        fi
        
        # Pascal architecture device IDs (Tesla P4/P40, Tesla P100, GTX 10xx, Quadro P series)
        # Tesla P4: 1bb3, Tesla P40: 1b38, Tesla P100: 15f7, 15f8, 15f9
        # GTX 10xx series: 1b80-1be1, Quadro P series: 1b30-1bb9
        local pascal_ids="1bb3 1b38 15f7 15f8 15f9 1b80 1b81 1b82 1b83 1b84 1b87 1ba0 1ba1 1ba2 1bb0 1bb1 1bb4 1bb5 1bb6 1bb7 1bb8 1bb9 1bc7 1be0 1be1 1c02 1c03 1c04 1c06 1c07 1c09 1c20 1c21 1c22 1c23 1c30 1c31 1c35 1c60 1c61 1c62 1c70 1c81 1c82 1c8c 1c8d 1cb1 1cb2 1cb3 1cb6 1cba 1cbb 1cbc 1cbd 1cfa 1cfb"
        
        for device_id in $gpu_device_ids; do
            for pascal_id in $pascal_ids; do
                if [ "$device_id" = "$pascal_id" ]; then
                    if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ]; then
                        echo -e "${GRAY}[DEBUG] Pascal GPU detected (device ID: $device_id)${NC}"
                    fi
                    return 0  # Pascal GPU found
                fi
            done
        done
        
        if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] No Pascal GPUs found${NC}"
        fi
    else
        if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] No NVIDIA GPUs found${NC}"
        fi
    fi
    return 1  # Pascal GPU not found
}













# Function to display PSA for Pascal (and older) GPUs following PoloLoco's recommendations
display_pascal_psa() {
    echo ""
    echo -e "${RED}========================================================================${NC}"
    echo -e "${RED}                    PSA FOR PASCAL (AND OLDER) GPUs                   ${NC}"
    echo -e "${RED}                    Like Tesla P4, P40, GTX 1080, etc.               ${NC}"
    echo -e "${RED}========================================================================${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT RECOMMENDATIONS (Following PoloLoco's Guide):${NC}"
    echo ""
    echo -e "${GREEN}[RECOMMENDED]${NC} Use ${YELLOW}v16.9 (535.230.02)${NC} driver for Pascal cards:"
    echo -e "  • v16.9 is the last driver with full Pascal support"
    echo -e "  • Best compatibility and stability for Pascal architecture"
    echo -e "  • Native vGPU support without complex workarounds"
    echo -e "  • Recommended by PoloLoco and the vGPU community"
    echo ""
    echo -e "${YELLOW}[CAUTION]${NC} v16.8+ drivers (535.216.01+, 550.x, 570.x, 580.x series):"
    echo -e "  • May need v16.4 vgpuConfig.xml for optimal Pascal compatibility"
    echo -e "  • v16.8+ requires Pascal configuration workaround"
    echo -e "  • v17.x+: NVIDIA dropped Pascal support starting from v17.0"
    echo -e "  • May have reduced stability or compatibility issues"
    echo -e "  • Only use if you specifically need newer driver features"
    echo ""
    echo -e "${RED}[NOT RECOMMENDED]${NC} v18.x/v19.x drivers for Pascal cards:"
    echo -e "  • No native Pascal support"
    echo -e "  • Complex workarounds required"
    echo -e "  • Potential stability and performance issues"
    echo ""
    echo -e "${BLUE}Pascal GPU Support Summary:${NC}"
    echo -e "  • ${GREEN}✓ v16.0-v16.7 drivers${NC}: Native support (recommended: v16.9)"
    echo -e "  • ${YELLOW}⚠ v16.8+ drivers${NC}: Requires v16.4 vgpuConfig.xml workaround"
    echo -e "  • ${RED}✗ v18.x/v19.x drivers${NC}: Not recommended for Pascal cards"
    echo ""
    echo -e "${RED}========================================================================${NC}"
    echo ""
}

# Function to apply Pascal vGPU configuration fix following PoloLoco's guide
# This function replaces the vgpuConfig.xml with the v16.4 driver's XML file
# (NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run) which contains the correct
# Tesla P4 and other Pascal profile definitions
apply_pascal_vgpu_fix() {
    local driver_version="$1"
    
    # Check if we have Pascal GPU and are using v17.x+ driver
    if detect_pascal_gpu; then
        # Display PSA for Pascal GPUs following PoloLoco's recommendations
        display_pascal_psa
        
        echo -e "${YELLOW}[-]${NC} Pascal GPU detected with driver v$driver_version"
        
        # Check if we're using v16.8 or newer driver (v17.x, v18.x, v19.x)
        # These drivers require the v16.4 vgpuConfig.xml to be installed for Pascal support
        if [[ "$driver_version" =~ ^16\.([89]|1[01])$|^17\.|^18\.|^19\. ]]; then
            echo -e "${YELLOW}[-]${NC} Following PoloLoco's guide: Pascal cards with v17.x+ drivers need v16.4 vgpuConfig.xml"
            echo -e "${YELLOW}[-]${NC} This is REQUIRED because newer drivers dropped Pascal support"
            echo -e "${GREEN}[+]${NC} The vgpuConfig.xml file contains Tesla P4, P40, and other Pascal profile definitions"
            
            # v16.4 driver details - this is the 535.161.05 driver version
            local v164_driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run"
            local v164_driver_md5="bad6e09aeb58942750479f091bb9c4b6"
            
            # Prompt user for v16.4 driver download URL
            echo -e "${YELLOW}[-]${NC} For Pascal GPU compatibility, you need driver v16.4 for its vgpuConfig.xml"
            echo -e "${YELLOW}[-]${NC} This XML file defines the Tesla P4/P40 vGPU profiles"
            local driver_url
            driver_url=$(prompt_for_driver_url "$v164_driver_filename" "16.4")
            
            # Create temporary directory for Pascal fix
            local temp_dir="/tmp/pascal_fix"
            mkdir -p "$temp_dir"
            local original_dir=$(pwd)
            cd "$temp_dir" || {
                echo -e "${RED}[!]${NC} Failed to create temporary directory for Pascal fix"
                return 1
            }
            
            # Download v16.4 driver from user-provided URL
            if ! download_driver_from_url "$v164_driver_filename" "$driver_url" "$v164_driver_md5"; then
                echo -e "${RED}[!]${NC} Failed to download v16.4 driver for Pascal compatibility"
                cd "$original_dir" || true
                return 1
            fi
            
            # Extract the driver to get vgpuConfig.xml
            echo -e "${YELLOW}[-]${NC} Extracting v16.4 driver for vgpuConfig.xml"
            chmod +x "$v164_driver_filename"
            if ! timeout 60 ./"$v164_driver_filename" -x >/dev/null 2>&1; then
                echo -e "${RED}[!]${NC} Failed to extract v16.4 driver"
                cd "$original_dir" || true
                return 1
            fi
            
            # Check if vgpuConfig.xml was extracted
            local extracted_dir="${v164_driver_filename%.run}"
            if [ ! -f "$extracted_dir/vgpuConfig.xml" ]; then
                echo -e "${RED}[!]${NC} vgpuConfig.xml not found in extracted v16.4 driver"
                cd "$original_dir" || true
                return 1
            fi
            
            # Create nvidia vgpu directory if it doesn't exist
            echo -e "${YELLOW}[-]${NC} Ensuring /usr/share/nvidia/vgpu directory exists"
            if ! mkdir -p "/usr/share/nvidia/vgpu"; then
                echo -e "${RED}[!]${NC} Failed to create /usr/share/nvidia/vgpu directory"
                echo -e "${YELLOW}[-]${NC} This could be due to insufficient permissions (run as root)"
                cd "$original_dir" || true
                return 1
            fi
            
            # Backup existing config if it exists
            if [ -f "/usr/share/nvidia/vgpu/vgpuConfig.xml" ]; then
                local backup_file="/usr/share/nvidia/vgpu/vgpuConfig.xml.backup.$(date +%Y%m%d_%H%M%S)"
                echo -e "${YELLOW}[-]${NC} Backing up existing vgpuConfig.xml to $backup_file"
                cp "/usr/share/nvidia/vgpu/vgpuConfig.xml" "$backup_file" 2>/dev/null || true
            fi
            
            # Step 4 of PoloLoco's guide: Overwrite vgpuConfig.xml with v16.4 version
            echo -e "${GREEN}[+]${NC} Step 4: Overwriting vgpuConfig.xml with v16.4 driver's XML"
            echo -e "${GREEN}[+]${NC} This XML file contains the Tesla P4/P40 vGPU profile definitions"
            
            if cp "$extracted_dir/vgpuConfig.xml" "/usr/share/nvidia/vgpu/vgpuConfig.xml"; then
                echo -e "${GREEN}[+]${NC} vgpuConfig.xml successfully replaced with v16.4 version"
                
                # Set proper permissions
                chmod 644 "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null || true
                chown root:root "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null || true
                
                # Verify the copied configuration contains Pascal device IDs
                # Tesla P4 = 1BB3, Tesla P40 = 1B38
                if grep -q "1BB3\|1bb3" "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null; then
                    echo -e "${GREEN}[+]${NC} Verified: Configuration contains Tesla P4 device ID (1BB3)"
                fi
                if grep -q "1B38\|1b38" "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null; then
                    echo -e "${GREEN}[+]${NC} Verified: Configuration contains Tesla P40 device ID (1B38)"
                fi
                
                # Clean up temporary files
                cd "$original_dir" || true
                rm -rf "$temp_dir" 2>/dev/null || true
                
                echo ""
                echo -e "${GREEN}[+]${NC} ========== PASCAL vGPU CONFIGURATION COMPLETE =========="
                echo -e "${GREEN}[+]${NC} All steps completed per PoloLoco's guide:"
                echo -e "${GREEN}[+]${NC}   ✓ Step 1: Downloaded vgpu-proxmox patches from GitLab"
                echo -e "${GREEN}[+]${NC}   ✓ Step 2: Applied patch to driver before installation"
                echo -e "${GREEN}[+]${NC}   ✓ Step 3: Installed the PATCHED driver"
                echo -e "${GREEN}[+]${NC}   ✓ Step 4: Replaced vgpuConfig.xml with v16.4 version"
                echo -e "${GREEN}[+]${NC} ======================================================="
                echo ""
                echo -e "${YELLOW}[-]${NC} ${RED}REBOOT REQUIRED:${NC} System must be rebooted for changes to take effect"
                echo -e "${YELLOW}[-]${NC} After reboot, run 'mdevctl types' to verify Pascal profiles are available"
                echo -e "${YELLOW}[-]${NC} Tesla P4 should show GRID P4-* profiles (not P40 profiles)"
                
            else
                echo -e "${RED}[!]${NC} Failed to copy v16.4 vgpuConfig.xml to /usr/share/nvidia/vgpu/"
                echo -e "${RED}[!]${NC} Pascal vGPU fix could not be applied"
                cd "$original_dir" || true
                return 1
            fi
        else
            # Using v16.0-v16.7 driver with Pascal - should work normally  
            if [[ "$driver_version" =~ ^16\.[0-7]$ ]]; then
                echo -e "${GREEN}[+]${NC} Using v$driver_version driver with Pascal GPU - excellent choice!"
                echo -e "${YELLOW}[-]${NC} v16.0-v16.7 drivers have native Pascal support"
            else
                echo -e "${GREEN}[+]${NC} Using v$driver_version driver with Pascal GPU - good choice!"
                echo -e "${YELLOW}[-]${NC} v16.x drivers provide Pascal support"
                
                # Special message for v16.9 (recommended for Pascal)
                if [[ "$driver_version" =~ ^16\.9 ]]; then
                    echo -e "${GREEN}[+]${NC} ${YELLOW}v16.9 is the recommended driver for Pascal cards per PoloLoco's guide${NC}"
                    echo -e "${GREEN}[+]${NC} This provides the best compatibility and stability for Pascal architecture"
                fi
            fi
        fi
        
        echo ""
    else
        if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] No Pascal GPU detected, skipping Pascal fix${NC}"
        fi
    fi
}

# Function to prompt user for driver download URL
prompt_for_driver_url() {
    local driver_filename="$1"
    local driver_version="$2"
    
    # All informational output goes to stderr so only the URL is captured by command substitution
    echo "" >&2
    echo -e "${YELLOW}[!]${NC} Driver Download Required" >&2
    echo -e "${YELLOW}[-]${NC} Driver file: $driver_filename" >&2
    echo -e "${YELLOW}[-]${NC} Driver version: $driver_version" >&2
    echo "" >&2
    echo -e "${BLUE}Please provide a download URL for the NVIDIA vGPU driver.${NC}" >&2
    echo "" >&2
    echo -e "${YELLOW}Official Sources:${NC}" >&2
    echo -e "• NVIDIA Licensing Portal: https://nvid.nvidia.com/dashboard/" >&2
    echo -e "• NVIDIA vGPU Software: https://www.nvidia.com/en-us/drivers/vgpu-software-driver/" >&2
    echo "" >&2
    echo -e "${YELLOW}Community Sources (use at your own discretion):${NC}" >&2
    echo -e "• PoloLoco vGPU Discord: https://discord.gg/5rQsSV3Byq" >&2
    echo -e "• vGPU Unlocking Community resources" >&2
    echo "" >&2
    echo -e "${RED}Note:${NC} This script no longer provides hardcoded download links." >&2
    echo -e "${RED}Note:${NC} You must obtain drivers from official or trusted sources." >&2
    echo "" >&2
    
    local url=""
    while [ -z "$url" ]; do
        read -p "$(echo -e "${BLUE}[?]${NC} Enter download URL for $driver_filename: ")" url
        if [ -z "$url" ]; then
            echo -e "${RED}[!]${NC} URL cannot be empty. Please provide a valid download URL." >&2
        elif [[ ! "$url" =~ ^https?:// ]]; then
            echo -e "${RED}[!]${NC} Please provide a valid HTTP/HTTPS URL." >&2
            url=""
        fi
    done
    
    echo "" >&2
    echo -e "${GREEN}[+]${NC} Using URL: $url" >&2
    # Only output the URL to stdout (this is what gets captured by command substitution)
    echo "$url"
}

# Function to download driver from user-provided URL
download_driver_from_url() {
    local driver_filename="$1"
    local driver_url="$2"
    local expected_md5="$3"
    
    echo -e "${YELLOW}[-]${NC} Downloading $driver_filename from provided URL..."
    echo -e "${YELLOW}[-]${NC} URL: $driver_url"
    
    # Check if file already exists
    if [ -e "$driver_filename" ]; then
        mv "$driver_filename" "$driver_filename.bak"
        echo -e "${YELLOW}[-]${NC} Moved existing $driver_filename to $driver_filename.bak"
    fi
    
    # Try different download methods
    local download_success=false
    local download_error=""
    
    # Try with wget first
    if command -v wget >/dev/null 2>&1; then
        echo -e "${YELLOW}[-]${NC} Attempting download with wget..."
        echo -e "${YELLOW}[-]${NC} This may take several minutes for large driver files..."
        # Use --progress=bar:force to show progress, --connect-timeout for initial connection,
        # --read-timeout for stalled downloads, and remove -q to see output
        if wget --progress=bar:force --tries=3 --connect-timeout=30 --read-timeout=300 "$driver_url" -O "$driver_filename" 2>&1; then
            if [ -f "$driver_filename" ] && [ -s "$driver_filename" ]; then
                download_success=true
                echo -e "${GREEN}[+]${NC} Successfully downloaded using wget"
            else
                download_error="wget completed but file is empty or missing"
            fi
        else
            download_error="wget failed with exit code $?"
            # Clean up partial downloads
            rm -f "$driver_filename" 2>/dev/null
        fi
    fi
    
    # Try with curl if wget failed
    if [ "$download_success" = false ] && command -v curl >/dev/null 2>&1; then
        echo -e "${YELLOW}[-]${NC} Attempting download with curl..."
        echo -e "${YELLOW}[-]${NC} This may take several minutes for large driver files..."
        # Use --progress-bar to show progress, --connect-timeout for initial connection,
        # --retry-delay between retries, -f to fail on HTTP errors, and show errors
        if curl --progress-bar -f -L --retry 3 --retry-delay 5 --connect-timeout 30 "$driver_url" -o "$driver_filename" 2>&1; then
            if [ -f "$driver_filename" ] && [ -s "$driver_filename" ]; then
                download_success=true
                echo -e "${GREEN}[+]${NC} Successfully downloaded using curl"
            else
                download_error="curl completed but file is empty or missing"
            fi
        else
            download_error="curl failed with exit code $?"
            # Clean up partial downloads
            rm -f "$driver_filename" 2>/dev/null
        fi
    fi
    
    if [ "$download_success" = false ]; then
        echo -e "${RED}[!]${NC} Failed to download driver from provided URL"
        if [ -n "$download_error" ]; then
            echo -e "${RED}[!]${NC} Error: $download_error"
        fi
        echo -e "${YELLOW}[-]${NC} Please verify:"
        echo -e "${YELLOW}[-]${NC}   • The URL is correct and accessible"
        echo -e "${YELLOW}[-]${NC}   • Your internet connection is working"
        echo -e "${YELLOW}[-]${NC}   • The server is not blocking your request"
        echo -e "${YELLOW}[-]${NC} Note: Mega.nz URLs are not supported - please use direct HTTP/HTTPS URLs"
        return 1
    fi
    
    # Verify MD5 if provided
    if [ -n "$expected_md5" ]; then
        local downloaded_md5=$(md5sum "$driver_filename" 2>/dev/null | awk '{print $1}')
        if [ "$downloaded_md5" != "$expected_md5" ]; then
            echo -e "${YELLOW}[-]${NC} MD5 checksum mismatch for downloaded driver"
            echo -e "${YELLOW}[-]${NC} Expected: $expected_md5"
            echo -e "${YELLOW}[-]${NC} Got:      $downloaded_md5"
            echo -e "${YELLOW}[-]${NC} The file may be corrupted or from a different source"
            echo ""
            read -p "$(echo -e "${BLUE}[?]${NC} Continue anyway? (y/n): ")" choice
            if [ "$choice" != "y" ]; then
                echo "Download cancelled due to checksum mismatch."
                return 1
            fi
        else
            echo -e "${GREEN}[+]${NC} MD5 checksum verified successfully"
        fi
    fi
    
    return 0
}

# Function to display usage information
display_usage() {
    echo -e "Usage: $0 [--debug] [--verbose] [--step <step_number>] [--url <url>] [--file <file>] [--create-overrides] [--configure-pascal-vm]"
    echo -e ""
    echo -e "Options:"
    echo -e "  --debug               Enable debug mode with verbose output"
    echo -e "  --verbose             Enable verbose logging for diagnostics"
    echo -e "  --step <number>       Jump to specific installation step"
    echo -e "  --url <url>           Use custom driver download URL"
    echo -e "  --file <file>         Use local driver file"
    echo -e "  --create-overrides    Create vGPU overrides following PoloLoco's guide"
    echo -e "  --configure-pascal-vm Configure Pascal card ROM spoofing for Proxmox VMs"
    echo -e ""
    echo -e "New Features (PoloLoco Guide Integration):"
    echo -e "  • Removed hardcoded download links - users provide URLs"
    echo -e "  • Updated to use PoloLoco's official vgpu-proxmox repository"
    echo -e "  • Added vGPU override configuration functionality"
    echo -e "  • Enhanced Pascal card support following PoloLoco's recommendations"
    echo -e "  • Added Pascal VM ROM spoofing configuration for v17+ drivers"
    echo -e "  • Improved patch handling from official PoloLoco repository"
    echo -e ""
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            DEBUG=true
            VERBOSE=true  # Debug mode implies verbose
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --step)
            STEP="$2"
            shift 2
            ;;
        --url)
            URL="$2"
            echo "URL=$URL" >> "$VGPU_DIR/$CONFIG_FILE"
            shift 2
            ;;
        --file)
            FILE="$2"
            echo "FILE=$FILE" >> "$VGPU_DIR/$CONFIG_FILE"
            shift 2
            ;;


        --create-overrides)
            # Run vGPU override creation
            echo ""
            echo -e "${BLUE}vGPU Override Configuration (PoloLoco Guide)${NC}"
            echo -e "${BLUE}============================================${NC}"
            echo ""
            create_vgpu_overrides
            exit 0
            ;;
        --configure-pascal-vm)
            # Run Pascal VM configuration
            echo ""
            echo -e "${BLUE}Pascal VM Configuration (ROM Spoofing)${NC}"
            echo -e "${BLUE}======================================${NC}"
            echo ""
            configure_pascal_vm
            exit 0
            ;;
        *)
            # Unknown option
            display_usage
            ;;
    esac
done

# Function to write to log file
write_log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$VGPU_DIR/$LOG_FILE"
}

# Function to log system information for diagnostics
log_system_info() {
    local section="$1"
    write_log "=== SYSTEM INFO: $section ==="
    
    case "$section" in
        "initial")
            write_log "Script version: $SCRIPT_VERSION"
            write_log "Working directory: $VGPU_DIR"
            write_log "Log file: $VGPU_DIR/$LOG_FILE"
            write_log "Debug mode: $DEBUG"
            write_log "Verbose mode: $VERBOSE"
            write_log "Current user: $(whoami)"
            write_log "Current date: $(date)"
            write_log "Kernel version: $(uname -r)"
            write_log "Distribution: $(lsb_release -d 2>/dev/null || echo 'Unknown')"
            write_log "Architecture: $(uname -m)"
            write_log "Available memory: $(free -h | grep Mem | awk '{print $2}')"
            write_log "Available disk space: $(df -h $VGPU_DIR | tail -1 | awk '{print $4}')"
            ;;
        "gpu")
            write_log "GPU Information:"
            lspci -nn | grep -i nvidia >> "$VGPU_DIR/$LOG_FILE" 2>&1 || write_log "No NVIDIA GPUs found"
            lspci -nn | grep -Ei '(VGA compatible controller|3D controller)' >> "$VGPU_DIR/$LOG_FILE" 2>&1
            ;;
        "kernel")
            write_log "Kernel and module information:"
            write_log "Running kernel: $(uname -r)"
            write_log "Available kernels:"
            find /boot -name "vmlinuz-*" -exec basename {} \; | sort >> "$VGPU_DIR/$LOG_FILE" 2>&1 || write_log "Could not list kernels"
            write_log "Loaded NVIDIA modules:"
            lsmod | grep nvidia >> "$VGPU_DIR/$LOG_FILE" 2>&1 || write_log "No NVIDIA modules loaded"
            ;;
        "services")
            write_log "Service status information:"
            systemctl status nvidia-vgpud.service >> "$VGPU_DIR/$LOG_FILE" 2>&1 || write_log "nvidia-vgpud.service not found"
            systemctl status nvidia-vgpu-mgr.service >> "$VGPU_DIR/$LOG_FILE" 2>&1 || write_log "nvidia-vgpu-mgr.service not found"
            ;;
        "driver")
            write_log "Driver status information:"
            nvidia-smi >> "$VGPU_DIR/$LOG_FILE" 2>&1 || write_log "nvidia-smi not available or failed"
            nvidia-smi vgpu >> "$VGPU_DIR/$LOG_FILE" 2>&1 || write_log "nvidia-smi vgpu not available or failed"
            mdevctl types >> "$VGPU_DIR/$LOG_FILE" 2>&1 || write_log "mdevctl not available or no vGPU types found"
            ;;
        "iommu")
            write_log "IOMMU status:"
            dmesg | grep -i iommu >> "$VGPU_DIR/$LOG_FILE" 2>&1 || write_log "No IOMMU messages found"
            if [ -d "/sys/class/iommu" ]; then
                ls -la /sys/class/iommu/ >> "$VGPU_DIR/$LOG_FILE" 2>&1
            else
                write_log "IOMMU not available"
            fi
            ;;
    esac
    
    write_log "=== END SYSTEM INFO: $section ==="
}

# Function to run a command with specified description and log level
run_command() {
    local description="$1"
    local log_level="$2"
    local command="$3"
    local exit_on_error="${4:-true}"  # Default to exit on error
    local show_output="${5:-false}"   # Default to hide output unless verbose

    case "$log_level" in
        "info")
            echo -e "${GREEN}[+]${NC} ${description}"
            ;;
        "notification")
            echo -e "${YELLOW}[-]${NC} ${description}"
            ;;
        "error")
            echo -e "${RED}[!]${NC} ${description}"
            ;;
        *)
            echo -e "[?] ${description}"
            ;;
    esac

    # Log command being executed
    write_log "$log_level: $description"
    write_log "COMMAND: $command"

    # Show verbose output if requested or if debug/verbose mode is enabled
    if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ] || [ "$show_output" = "true" ]; then
        echo -e "${GRAY}[DEBUG] Executing: $command${NC}"
        eval "$command" 2>&1 | tee -a "$VGPU_DIR/$LOG_FILE"
        local exit_code=${PIPESTATUS[0]}
    else
        eval "$command" >> "$VGPU_DIR/$LOG_FILE" 2>&1
        local exit_code=$?
    fi

    # Log command result
    write_log "EXIT_CODE: $exit_code"
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[!]${NC} Command failed with exit code: $exit_code"
        write_log "ERROR: Command '$command' failed with exit code $exit_code"
        
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] Last 10 lines from log file:${NC}"
            tail -10 "$VGPU_DIR/$LOG_FILE" | sed 's/^/  /'
        fi
        
        if [ "$exit_on_error" = "true" ]; then
            echo -e "${RED}[!]${NC} Installation failed. Check $VGPU_DIR/$LOG_FILE for details."
            echo -e "${YELLOW}[-]${NC} Run with --verbose flag for more detailed output."
            exit $exit_code
        fi
    else
        write_log "SUCCESS: Command completed successfully"
    fi
    
    return $exit_code
}

# Check Proxmox version
pve_info=$(pveversion)
version=$(echo "$pve_info" | sed -n 's/^pve-manager\/\([0-9.]*\).*$/\1/p')
#version=7.4-15
#version=8.1.4
kernel=$(echo "$pve_info" | sed -n 's/^.*kernel: \([0-9.-]*pve\).*$/\1/p')
major_version=$(echo "$version" | sed 's/\([0-9]*\).*/\1/')

# Function to map filename to driver version and patch
map_filename_to_version() {
    local filename="$1"
    if [[ "$filename" =~ ^(NVIDIA-Linux-x86_64-535\.54\.06-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.104\.06-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.129\.03-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.161\.05-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.161\.05-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.183\.04-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.216\.01-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.230\.02-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.247\.02-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.261\.04-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.54\.10-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.54\.16-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.90\.05-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.127\.06-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.144\.02-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.163\.02-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.163\.10-vgpu-kvm\.run|NVIDIA-Linux-x86_64-570\.124\.03-vgpu-kvm\.run|NVIDIA-Linux-x86_64-570\.133\.10-vgpu-kvm\.run|NVIDIA-Linux-x86_64-570\.148\.06-vgpu-kvm\.run|NVIDIA-Linux-x86_64-570\.158\.02-vgpu-kvm\.run|NVIDIA-Linux-x86_64-570\.172\.07-vgpu-kvm\.run|NVIDIA-Linux-x86_64-580\.65\.05-vgpu-kvm\.run|NVIDIA-Linux-x86_64-580\.82\.02-vgpu-kvm\.run|NVIDIA-Linux-x86_64-580\.95\.02-vgpu-kvm\.run)$ ]]; then
        case "$filename" in
            NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run)
                driver_version="16.0"
                driver_patch="535.54.06.patch"
                md5="b892f75f8522264bc176f5a555acb176"
                ;;
            NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run)
                driver_version="16.1"
                driver_patch="535.104.06.patch"
                md5="1020ad5b89fa0570c27786128385ca48"
                ;;
            NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run)
                driver_version="16.2"
                driver_patch="535.129.03.patch"
                md5="0048208a62bacd2a7dd12fa736aa5cbb"
                ;;
            NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run)
                driver_version="16.4"
                driver_patch="535.161.05.patch"
                md5="bad6e09aeb58942750479f091bb9c4b6"
                ;;
            NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run)
                driver_version="16.5"
                driver_patch="535.161.05.patch"
                md5="bad6e09aeb58942750479f091bb9c4b6"
                ;;
            NVIDIA-Linux-x86_64-535.183.04-vgpu-kvm.run)
                driver_version="16.7"
                driver_patch="535.183.04.patch"
                md5="68961f01a2332b613fe518afd4bfbfb2"
                ;;
            NVIDIA-Linux-x86_64-535.216.01-vgpu-kvm.run)
                driver_version="16.8"
                driver_patch="535.216.01.patch"
                md5="18627628e749f893cd2c3635452006a46"
                ;;
            NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run)
                driver_version="16.9"
                driver_patch="535.230.02.patch"
                md5="3f6412723880aa5720b44cf0a9a13009"
                ;;
            NVIDIA-Linux-x86_64-535.247.02-vgpu-kvm.run)
                driver_version="16.10"
                driver_patch="NO_PATCH"
                md5=""
                ;;
            NVIDIA-Linux-x86_64-535.261.04-vgpu-kvm.run)
                driver_version="16.11"
                driver_patch="NO_PATCH"
                md5=""
                ;;
            NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run)
                driver_version="17.0"
                driver_patch="550.54.10.patch"
                md5="5f5e312cbd5bb64946e2a1328a98c08d"
                ;;
            NVIDIA-Linux-x86_64-550.54.16-vgpu-kvm.run)
                driver_version="17.1"
                driver_patch="550.54.16.patch"
                md5="4d78514599c16302a0111d355dbf11e3"
                ;;
            NVIDIA-Linux-x86_64-550.90.05-vgpu-kvm.run)
                driver_version="17.3"
                driver_patch="550.90.05.patch"
                md5="a3cddad85eee74dc15dbadcbe30dcf3a"
                ;;
            NVIDIA-Linux-x86_64-550.127.06-vgpu-kvm.run)
                driver_version="17.4"
                driver_patch="550.127.06.patch"
                md5="400b1b2841908ea36fd8f7fdbec18401"
                ;;
            NVIDIA-Linux-x86_64-550.144.02-vgpu-kvm.run)
                driver_version="17.5"
                driver_patch="550.144.02.patch"
                md5="37016ba868a0b4390c38aebbacfba09e"
                ;;
            NVIDIA-Linux-x86_64-550.163.02-vgpu-kvm.run)
                driver_version="17.6"
                driver_patch="550.163.02.patch"
                md5="093036d83baf879a4bb667b484597789"
                ;;
            NVIDIA-Linux-x86_64-550.163.10-vgpu-kvm.run)
                driver_version="17.6"
                driver_patch="550.163.02.patch"
                md5=""
                ;;
            NVIDIA-Linux-x86_64-570.124.03-vgpu-kvm.run)
                driver_version="18.0"
                driver_patch="570.124.03.patch"
                md5="1804b889e27b7f868afb5521d871b095"
                ;;
            NVIDIA-Linux-x86_64-570.133.10-vgpu-kvm.run)
                driver_version="18.1"
                driver_patch="570.133.10.patch"
                md5="f435eacdbe3c8002ccad14bd62c9bd2d"
                ;;
            NVIDIA-Linux-x86_64-570.148.06-vgpu-kvm.run)
                driver_version="18.2"
                driver_patch="570.148.06.patch"
                md5=""
                ;;
            NVIDIA-Linux-x86_64-570.158.02-vgpu-kvm.run)
                driver_version="18.3"
                driver_patch="570.158.02.patch"
                md5=""
                ;;
            NVIDIA-Linux-x86_64-570.172.07-vgpu-kvm.run)
                driver_version="18.4"
                driver_patch="570.172.07.patch"
                md5=""
                ;;
            NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run)
                driver_version="19.0"
                driver_patch="580.65.05.patch"
                md5=""
                ;;
            NVIDIA-Linux-x86_64-580.82.02-vgpu-kvm.run)
                driver_version="19.1"
                driver_patch="NO_PATCH"
                md5=""
                ;;
            NVIDIA-Linux-x86_64-580.95.02-vgpu-kvm.run)
                driver_version="19.2"
                driver_patch="NO_PATCH"
                md5=""
                ;;
        esac
        return 0  # Return true
    else
        return 1  # Return false
    fi
}

# License the vGPU
configure_fastapi_dls() {
    echo ""
    echo -e "${YELLOW}[!]${NC} NVIDIA vGPU Licensing Information:"
    echo "  - Each vGPU-enabled GPU requires proper NVIDIA vGPU licensing"
    echo "  - Multi-GPU setups require licensing for ALL vGPU-enabled cards"
    echo "  - FastAPI-DLS v2.x provides licensing server functionality"
    echo "  - Ensure sufficient licenses for your vGPU deployment"
    echo ""
    echo -e "${GREEN}[+]${NC} FastAPI-DLS v2.x Compatibility:"
    echo "  - Backwards compatible with v17.x drivers"
    echo "  - Supports v18.x and v19.x drivers with gridd-unlock-patcher"
    echo "  - Uses latest Docker image: collinwebdesigns/fastapi-dls:latest"
    echo ""
    echo -e "${YELLOW}[!]${NC} Note: For v18.x and v19.x drivers, ensure gridd-unlock-patcher is properly configured"
    echo "  - See: https://git.collinwebdesigns.de/vgpu/gridd-unlock-patcher"
    echo ""
    read -p "$(echo -e "${BLUE}[?]${NC} Do you want to setup vGPU licensing server? (y/n): ")" choice
    echo ""

    if [ "$choice" = "y" ]; then
        # Installing Docker-CE
        run_command "Installing Docker-CE" "info" "apt install ca-certificates curl -y; \
        curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc; \
        chmod a+r /etc/apt/keyrings/docker.asc; \
        echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null; \
        apt update; \
        apt install docker-ce docker-compose -y"

        # Docker pull FastAPI-DLS v2.x (supports v17.x, v18.x, v19.x drivers)
        run_command "Docker pull FastAPI-DLS" "info" "docker pull collinwebdesigns/fastapi-dls:latest; \
        working_dir=/opt/docker/fastapi-dls/cert; \
        mkdir -p \$working_dir; \
        cd \$working_dir; \
        openssl genrsa -out \$working_dir/instance.private.pem 2048; \
        openssl rsa -in \$working_dir/instance.private.pem -outform PEM -pubout -out \$working_dir/instance.public.pem; \
        echo -e '\n\n\n\n\n\n\n' | openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout \$working_dir/webserver.key -out \$working_dir/webserver.crt; \
        docker volume create dls-db"

        # Get the timezone of the Proxmox server
        timezone=$(timedatectl | grep 'Time zone' | awk '{print $3}')

        # Get the hostname of the Proxmox server
        hostname=$(hostname -i)

        fastapi_dir=~/fastapi-dls
        mkdir -p $fastapi_dir

        # Ask for desired port number here
        echo ""
        read -p "$(echo -e "${BLUE}[?]${NC} Enter the desired port number for FastAPI-DLS (default is 8443): ")" portnumber
        portnumber=${portnumber:-8443}
        echo -e "${RED}[!]${NC} Don't use port 80 or 443 since Proxmox is using those ports"
        echo ""

        echo -e "${GREEN}[+]${NC} Generate Docker YAML compose file"
        # Generate the Docker Compose YAML file for FastAPI-DLS v2.x
        # v2.x supports v17.x, v18.x, v19.x drivers (v18.x/v19.x require gridd-unlock-patcher)
        cat > "$fastapi_dir/docker-compose.yml" <<EOF
version: '3.9'

x-dls-variables: &dls-variables
  TZ: $timezone
  DLS_URL: $hostname
  DLS_PORT: $portnumber
  LEASE_EXPIRE_DAYS: 90  # 90 days is maximum
  DATABASE: sqlite:////app/database/db.sqlite
  DEBUG: "false"

services:
  wvthoog-fastapi-dls:
    image: collinwebdesigns/fastapi-dls:latest  # v2.x - supports v17.x, v18.x, v19.x
    restart: always
    container_name: wvthoog-fastapi-dls
    environment:
      <<: *dls-variables
    ports:
      - "$portnumber:443"
    volumes:
      - /opt/docker/fastapi-dls/cert:/app/cert
      - dls-db:/app/database
    logging:  # optional, for those who do not need logs
      driver: "json-file"
      options:
        max-file: "5"
        max-size: "10m"

volumes:
  dls-db:
EOF
        # Issue docker-compose
        run_command "Running Docker Compose" "info" "docker-compose -f \"$fastapi_dir/docker-compose.yml\" up -d"

        # Create directory where license script (Windows/Linux are stored)
        mkdir -p $VGPU_DIR/licenses

        echo -e "${GREEN}[+]${NC} Generate FastAPI-DLS Windows/Linux executables"
        
        # Check if driver version is 18 or higher (requires gridd-unlock-patcher)
        needs_gridd_patcher=false
        if [[ "$driver_version" =~ ^18\.|^19\. ]]; then
            needs_gridd_patcher=true
            echo -e "${YELLOW}[!]${NC} Driver v$driver_version requires gridd-unlock-patcher for licensing"
        fi
        
        # Create .sh file for Linux
        if [ "$needs_gridd_patcher" = true ]; then
            cat > "$VGPU_DIR/licenses/license_linux.sh" <<'EOF'
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
            cat >> "$VGPU_DIR/licenses/license_linux.sh" <<EOF
curl --insecure -L -X GET https://$hostname:$portnumber/-/client-token -o /etc/nvidia/ClientConfigToken/client_configuration_token_\$(date '+%d-%m-%Y-%H-%M-%S').tok
service nvidia-gridd restart
nvidia-smi -q | grep "License"
EOF
        else
            cat > "$VGPU_DIR/licenses/license_linux.sh" <<EOF
#!/bin/bash

curl --insecure -L -X GET https://$hostname:$portnumber/-/client-token -o /etc/nvidia/ClientConfigToken/client_configuration_token_\$(date '+%d-%m-%Y-%H-%M-%S').tok
service nvidia-gridd restart
nvidia-smi -q | grep "License"
EOF
        fi

        # Create .ps1 file for Windows
        if [ "$needs_gridd_patcher" = true ]; then
            cat > "$VGPU_DIR/licenses/license_windows.ps1" <<'EOF'
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
            cat >> "$VGPU_DIR/licenses/license_windows.ps1" <<EOF
curl.exe --insecure -L -X GET https://$hostname:$portnumber/-/client-token -o "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\client_configuration_token_\$(Get-Date -f 'dd-MM-yy-hh-mm-ss').tok"
Restart-Service NVDisplay.ContainerLocalSystem
& 'nvidia-smi' -q  | Select-String "License"
EOF
        else
            cat > "$VGPU_DIR/licenses/license_windows.ps1" <<EOF
curl.exe --insecure -L -X GET https://$hostname:$portnumber/-/client-token -o "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\client_configuration_token_\$(Get-Date -f 'dd-MM-yy-hh-mm-ss').tok"
Restart-Service NVDisplay.ContainerLocalSystem
& 'nvidia-smi' -q  | Select-String "License"
EOF
        fi

        echo -e "${GREEN}[+]${NC} license_windows.ps1 and license_linux.sh created and stored in: $VGPU_DIR/licenses"
        echo -e "${YELLOW}[-]${NC} Copy these files to your Windows or Linux VM's and execute"
        
        if [ "$needs_gridd_patcher" = true ]; then
            echo ""
            echo -e "${YELLOW}[!]${NC} IMPORTANT: v18+ Driver Requirements"
            echo "  - The generated scripts include gridd-unlock-patcher installation and execution"
            echo "  - gridd-unlock-patcher is REQUIRED for v18.x and v19.x drivers to work with FastAPI-DLS"
            echo "  - The patcher will be automatically downloaded and installed when you run the license scripts"
            echo "  - Linux: Script will install to /usr/bin/gridd-unlock-patcher"
            echo "  - Windows: Script will install to C:\\Program Files\\gridd-unlock-patcher\\gridd-unlock-patcher.exe"
            echo "  - For more information: https://git.collinwebdesigns.de/vgpu/gridd-unlock-patcher"
        fi
        
        echo ""
        echo "Exiting script."
        echo ""
        exit 0

        # Put the stuff below in here
    elif [ "$choice" = "n" ]; then
        echo ""
        echo "Exiting script."
        echo "Install the Docker container in a VM/LXC yourself."
        echo "By using this guide: https://git.collinwebdesigns.de/oscar.krause/fastapi-dls#docker"
        echo ""
        exit 0

        # Write instruction on how to setup Docker in a VM/LXC container
        # Echo .yml script and docker-compose instructions
    else
        echo -e "${RED}[!]${NC} Invalid choice. Please enter (y/n)."
        exit 1
    fi
}

# Function to configure Pascal VM with ROM spoofing
configure_pascal_vm() {
    echo ""
    echo -e "${BLUE}Pascal VM Configuration (ROM Spoofing)${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""
    echo -e "${YELLOW}[-]${NC} This function helps configure Pascal cards for Proxmox VMs"
    echo -e "${YELLOW}[-]${NC} Pascal cards with NVIDIA drivers v17+ require ROM spoofing to work properly"
    echo -e "${YELLOW}[-]${NC} This adds V100 device IDs to trick guest drivers into installing"
    echo ""
    
    # First, check if we have Pascal GPUs
    if ! detect_pascal_gpu; then
        echo -e "${YELLOW}[-]${NC} No Pascal GPUs detected in system"
        echo -e "${YELLOW}[-]${NC} This feature is specifically for Pascal architecture cards:"
        echo -e "${YELLOW}[-]${NC} • Tesla P4, Tesla P40"
        echo -e "${YELLOW}[-]${NC} • GTX 10xx series (1050, 1060, 1070, 1080, etc.)"
        echo -e "${YELLOW}[-]${NC} • Quadro P series"
        echo ""
        read -p "$(echo -e "${BLUE}[?]${NC} Continue anyway? (y/n): ")" continue_choice
        if [ "$continue_choice" != "y" ]; then
            echo -e "${YELLOW}[-]${NC} Exiting Pascal VM configuration"
            return 0
        fi
    else
        echo -e "${GREEN}[+]${NC} Pascal GPU detected - ROM spoofing may be needed for v17+ drivers"
    fi
    
    echo ""
    echo "Choose an option:"
    echo ""
    echo "1) Configure existing VM"
    echo "2) Create new basic VM with Pascal ROM spoofing"
    echo "3) Exit"
    echo ""
    read -p "Enter your choice: " vm_choice
    
    case $vm_choice in
        1)
            configure_existing_vm
            ;;
        2)
            create_new_pascal_vm
            ;;
        3)
            echo -e "${YELLOW}[-]${NC} Exiting Pascal VM configuration"
            return 0
            ;;
        *)
            echo -e "${RED}[!]${NC} Invalid choice. Please enter 1, 2, or 3."
            return 1
            ;;
    esac
}

# Function to configure existing VM with Pascal ROM spoofing
configure_existing_vm() {
    echo ""
    echo -e "${GREEN}[+]${NC} Configuring existing VM with Pascal ROM spoofing"
    echo ""
    
    # Get VM ID
    while true; do
        read -p "$(echo -e "${BLUE}[?]${NC} Enter VM ID to configure: ")" vm_id
        if [[ "$vm_id" =~ ^[0-9]+$ ]] && [ "$vm_id" -ge 100 ] && [ "$vm_id" -le 999999 ]; then
            # Check if VM exists
            if qm config "$vm_id" >/dev/null 2>&1; then
                echo -e "${GREEN}[+]${NC} Found VM $vm_id"
                break
            else
                echo -e "${RED}[!]${NC} VM $vm_id does not exist"
                read -p "$(echo -e "${BLUE}[?]${NC} Try again? (y/n): ")" retry
                if [ "$retry" != "y" ]; then
                    return 1
                fi
            fi
        else
            echo -e "${RED}[!]${NC} Invalid VM ID. Please enter a number between 100 and 999999"
        fi
    done
    
    # Get available GPU PCI addresses
    echo ""
    echo -e "${YELLOW}[-]${NC} Scanning for NVIDIA GPUs..."
    local gpu_list=$(lspci -nn | grep -i 'NVIDIA Corporation' | grep -Ei '(VGA compatible controller|3D controller)')
    
    if [ -z "$gpu_list" ]; then
        echo -e "${RED}[!]${NC} No NVIDIA GPUs found in system"
        return 1
    fi
    
    echo -e "${GREEN}[+]${NC} Available NVIDIA GPUs:"
    echo "$gpu_list" | nl -w2 -s') '
    echo ""
    
    # Get GPU selection
    local gpu_count=$(echo "$gpu_list" | wc -l)
    read -p "$(echo -e "${BLUE}[?]${NC} Select GPU number (1-$gpu_count): ")" gpu_selection
    
    if ! [[ "$gpu_selection" =~ ^[1-9][0-9]*$ ]] || [ "$gpu_selection" -gt "$gpu_count" ]; then
        echo -e "${RED}[!]${NC} Invalid GPU selection"
        return 1
    fi
    
    local selected_gpu=$(echo "$gpu_list" | sed -n "${gpu_selection}p")
    local pci_address=$(echo "$selected_gpu" | awk '{print $1}' | sed 's/^/0000:/')
    
    echo -e "${GREEN}[+]${NC} Selected GPU: $selected_gpu"
    echo -e "${GREEN}[+]${NC} PCI Address: $pci_address"
    
    # Get mdev type
    echo ""
    echo -e "${YELLOW}[-]${NC} Available mdev types (common Pascal profiles):"
    echo -e "${YELLOW}[-]${NC} • nvidia-63: GRID P40-1Q (1GB)"
    echo -e "${YELLOW}[-]${NC} • nvidia-64: GRID P40-2Q (2GB)" 
    echo -e "${YELLOW}[-]${NC} • nvidia-65: GRID P40-3Q (3GB)"
    echo -e "${YELLOW}[-]${NC} • nvidia-66: GRID P40-4Q (4GB)"
    echo -e "${YELLOW}[-]${NC} • nvidia-67: GRID P40-6Q (6GB)"
    echo -e "${YELLOW}[-]${NC} • nvidia-68: GRID P40-8Q (8GB)"
    echo -e "${YELLOW}[-]${NC} • nvidia-69: GRID P40-12Q (12GB)"
    echo ""
    echo -e "${YELLOW}[-]${NC} You can also run 'mdevctl types' to see all available types"
    echo ""
    
    read -p "$(echo -e "${BLUE}[?]${NC} Enter mdev type (e.g., nvidia-66): ")" mdev_type
    
    if [ -z "$mdev_type" ]; then
        echo -e "${RED}[!]${NC} mdev type cannot be empty"
        return 1
    fi
    
    # Find next available hostpci slot
    local existing_hostpci=$(qm config "$vm_id" | grep -o 'hostpci[0-9]*:' | sed 's/://' | sort -V | tail -1)
    local next_slot=0
    
    if [ -n "$existing_hostpci" ]; then
        local last_num=$(echo "$existing_hostpci" | sed 's/hostpci//')
        next_slot=$((last_num + 1))
    fi
    
    local hostpci_param="hostpci${next_slot}"
    
    # V100 device IDs for ROM spoofing
    local device_id="0x1DB6"        # Tesla V100 PCIe device ID
    local sub_device_id="0x12BF"    # Tesla V100 PCIe sub-device ID  
    local sub_vendor_id="0x10de"    # NVIDIA sub-vendor ID
    local vendor_id="0x10de"        # NVIDIA vendor ID
    
    # Build the hostpci configuration
    local hostpci_config="${pci_address},device-id=${device_id},mdev=${mdev_type},sub-device-id=${sub_device_id},sub-vendor-id=${sub_vendor_id},vendor-id=${vendor_id}"
    
    echo ""
    echo -e "${GREEN}[+]${NC} Configuration to add:"
    echo -e "${YELLOW}[-]${NC} Parameter: $hostpci_param"
    echo -e "${YELLOW}[-]${NC} Value: $hostpci_config"
    echo ""
    echo -e "${YELLOW}[-]${NC} This will add Pascal ROM spoofing using V100 device IDs:"
    echo -e "${YELLOW}[-]${NC} • Device ID: $device_id (Tesla V100 PCIe)"
    echo -e "${YELLOW}[-]${NC} • Sub-device ID: $sub_device_id"
    echo -e "${YELLOW}[-]${NC} • Vendor/Sub-vendor ID: $vendor_id (NVIDIA)"
    echo -e "${YELLOW}[-]${NC} • mdev Type: $mdev_type"
    echo ""
    
    read -p "$(echo -e "${BLUE}[?]${NC} Apply this configuration to VM $vm_id? (y/n): ")" confirm
    
    if [ "$confirm" = "y" ]; then
        echo -e "${GREEN}[+]${NC} Applying configuration..."
        
        # Stop VM if running
        local vm_status=$(qm status "$vm_id" | awk '{print $2}')
        local vm_was_running=false
        
        if [ "$vm_status" = "running" ]; then
            echo -e "${YELLOW}[-]${NC} VM is running, stopping it first..."
            qm stop "$vm_id"
            vm_was_running=true
            sleep 3
        fi
        
        # Apply the configuration
        if qm set "$vm_id" --"$hostpci_param" "$hostpci_config"; then
            echo -e "${GREEN}[+]${NC} Successfully configured VM $vm_id with Pascal ROM spoofing"
            echo -e "${GREEN}[+]${NC} Added $hostpci_param: $hostpci_config"
            
            # Optionally restart VM
            if [ "$vm_was_running" = true ]; then
                read -p "$(echo -e "${BLUE}[?]${NC} Restart VM $vm_id? (y/n): ")" restart_vm
                if [ "$restart_vm" = "y" ]; then
                    echo -e "${YELLOW}[-]${NC} Starting VM $vm_id..."
                    qm start "$vm_id"
                fi
            fi
            
            echo ""
            echo -e "${GREEN}[+]${NC} Configuration complete!"
            echo -e "${YELLOW}[-]${NC} The VM now has Pascal ROM spoofing configured"
            echo -e "${YELLOW}[-]${NC} Install NVIDIA guest drivers v16+ in the VM to use vGPU"
            
        else
            echo -e "${RED}[!]${NC} Failed to configure VM $vm_id"
            return 1
        fi
    else
        echo -e "${YELLOW}[-]${NC} Configuration cancelled"
    fi
}

# Function to create new basic VM with Pascal ROM spoofing
create_new_pascal_vm() {
    echo ""
    echo -e "${GREEN}[+]${NC} Creating new basic VM with Pascal ROM spoofing"
    echo ""
    
    # Get VM ID
    while true; do
        read -p "$(echo -e "${BLUE}[?]${NC} Enter new VM ID (100-999999): ")" vm_id
        if [[ "$vm_id" =~ ^[0-9]+$ ]] && [ "$vm_id" -ge 100 ] && [ "$vm_id" -le 999999 ]; then
            # Check if VM already exists
            if qm config "$vm_id" >/dev/null 2>&1; then
                echo -e "${RED}[!]${NC} VM $vm_id already exists"
                read -p "$(echo -e "${BLUE}[?]${NC} Try different ID? (y/n): ")" retry
                if [ "$retry" != "y" ]; then
                    return 1
                fi
            else
                break
            fi
        else
            echo -e "${RED}[!]${NC} Invalid VM ID. Please enter a number between 100 and 999999"
        fi
    done
    
    # Get VM name
    read -p "$(echo -e "${BLUE}[?]${NC} Enter VM name [Pascal-VM-$vm_id]: ")" vm_name
    if [ -z "$vm_name" ]; then
        vm_name="Pascal-VM-$vm_id"
    fi
    
    # Get available GPU PCI addresses
    echo ""
    echo -e "${YELLOW}[-]${NC} Scanning for NVIDIA GPUs..."
    local gpu_list=$(lspci -nn | grep -i 'NVIDIA Corporation' | grep -Ei '(VGA compatible controller|3D controller)')
    
    if [ -z "$gpu_list" ]; then
        echo -e "${RED}[!]${NC} No NVIDIA GPUs found in system"
        return 1
    fi
    
    echo -e "${GREEN}[+]${NC} Available NVIDIA GPUs:"
    echo "$gpu_list" | nl -w2 -s') '
    echo ""
    
    # Support multiple GPU selection
    read -p "$(echo -e "${BLUE}[?]${NC} Enter GPU numbers to add (e.g., '1' or '1,3' for multiple): ")" gpu_selections
    
    # Parse GPU selections
    IFS=',' read -ra ADDR <<< "$gpu_selections"
    declare -a selected_gpus
    declare -a selected_pci_addresses
    
    local gpu_count=$(echo "$gpu_list" | wc -l)
    
    for selection in "${ADDR[@]}"; do
        selection=$(echo "$selection" | tr -d ' ')  # Remove whitespace
        if [[ "$selection" =~ ^[1-9][0-9]*$ ]] && [ "$selection" -le "$gpu_count" ]; then
            local selected_gpu=$(echo "$gpu_list" | sed -n "${selection}p")
            local pci_address=$(echo "$selected_gpu" | awk '{print $1}' | sed 's/^/0000:/')
            selected_gpus+=("$selected_gpu")
            selected_pci_addresses+=("$pci_address")
        else
            echo -e "${RED}[!]${NC} Invalid GPU selection: $selection"
            return 1
        fi
    done
    
    if [ ${#selected_gpus[@]} -eq 0 ]; then
        echo -e "${RED}[!]${NC} No valid GPUs selected"
        return 1
    fi
    
    echo -e "${GREEN}[+]${NC} Selected GPUs:"
    for i in "${!selected_gpus[@]}"; do
        echo -e "${YELLOW}[-]${NC} GPU $((i+1)): ${selected_gpus[$i]}"
        echo -e "${YELLOW}[-]${NC} PCI: ${selected_pci_addresses[$i]}"
    done
    
    # Get mdev type for all GPUs
    echo ""
    echo -e "${YELLOW}[-]${NC} Available mdev types (common Pascal profiles):"
    echo -e "${YELLOW}[-]${NC} • nvidia-63: GRID P40-1Q (1GB)"
    echo -e "${YELLOW}[-]${NC} • nvidia-64: GRID P40-2Q (2GB)" 
    echo -e "${YELLOW}[-]${NC} • nvidia-65: GRID P40-3Q (3GB)"
    echo -e "${YELLOW}[-]${NC} • nvidia-66: GRID P40-4Q (4GB)"
    echo -e "${YELLOW}[-]${NC} • nvidia-67: GRID P40-6Q (6GB)"
    echo -e "${YELLOW}[-]${NC} • nvidia-68: GRID P40-8Q (8GB)"
    echo -e "${YELLOW}[-]${NC} • nvidia-69: GRID P40-12Q (12GB)"
    echo ""
    
    read -p "$(echo -e "${BLUE}[?]${NC} Enter mdev type for all GPUs (e.g., nvidia-66): ")" mdev_type
    
    if [ -z "$mdev_type" ]; then
        echo -e "${RED}[!]${NC} mdev type cannot be empty"
        return 1
    fi
    
    # V100 device IDs for ROM spoofing
    local device_id="0x1DB6"        # Tesla V100 PCIe device ID
    local sub_device_id="0x12BF"    # Tesla V100 PCIe sub-device ID  
    local sub_vendor_id="0x10de"    # NVIDIA sub-vendor ID
    local vendor_id="0x10de"        # NVIDIA vendor ID
    
    # Build hostpci configurations
    declare -a hostpci_configs
    for i in "${!selected_pci_addresses[@]}"; do
        local pci_address="${selected_pci_addresses[$i]}"
        local hostpci_config="${pci_address},device-id=${device_id},mdev=${mdev_type},sub-device-id=${sub_device_id},sub-vendor-id=${sub_vendor_id},vendor-id=${vendor_id}"
        hostpci_configs+=("$hostpci_config")
    done
    
    echo ""
    echo -e "${GREEN}[+]${NC} VM Configuration Summary:"
    echo -e "${YELLOW}[-]${NC} VM ID: $vm_id"
    echo -e "${YELLOW}[-]${NC} VM Name: $vm_name"
    echo -e "${YELLOW}[-]${NC} GPUs to add: ${#selected_gpus[@]}"
    echo -e "${YELLOW}[-]${NC} mdev Type: $mdev_type"
    echo ""
    echo -e "${YELLOW}[-]${NC} hostpci configurations:"
    for i in "${!hostpci_configs[@]}"; do
        echo -e "${YELLOW}[-]${NC} hostpci${i}: ${hostpci_configs[$i]}"
    done
    echo ""
    echo -e "${YELLOW}[-]${NC} ROM Spoofing (V100 IDs):"
    echo -e "${YELLOW}[-]${NC} • Device ID: $device_id (Tesla V100 PCIe)"
    echo -e "${YELLOW}[-]${NC} • Sub-device ID: $sub_device_id"
    echo -e "${YELLOW}[-]${NC} • Vendor/Sub-vendor ID: $vendor_id (NVIDIA)"
    echo ""
    
    read -p "$(echo -e "${BLUE}[?]${NC} Create VM with this configuration? (y/n): ")" confirm
    
    if [ "$confirm" = "y" ]; then
        echo -e "${GREEN}[+]${NC} Creating basic VM..."
        
        # Create basic VM with minimal configuration
        local vm_create_cmd="qm create $vm_id --name '$vm_name' --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0 --ostype l26"
        
        # Add hostpci parameters
        for i in "${!hostpci_configs[@]}"; do
            vm_create_cmd="$vm_create_cmd --hostpci${i} '${hostpci_configs[$i]}'"
        done
        
        if eval "$vm_create_cmd"; then
            echo -e "${GREEN}[+]${NC} Successfully created VM $vm_id with Pascal ROM spoofing"
            echo ""
            echo -e "${GREEN}[+]${NC} VM created with:"
            echo -e "${YELLOW}[-]${NC} • 2GB RAM (you may want to increase this)"
            echo -e "${YELLOW}[-]${NC} • 2 CPU cores"
            echo -e "${YELLOW}[-]${NC} • Network interface on vmbr0"
            echo -e "${YELLOW}[-]${NC} • ${#selected_gpus[@]} GPU(s) with Pascal ROM spoofing"
            echo ""
            echo -e "${YELLOW}[!]${NC} IMPORTANT: You still need to:"
            echo -e "${YELLOW}[-]${NC} • Add storage (hard disk) to the VM"
            echo -e "${YELLOW}[-]${NC} • Install an operating system"
            echo -e "${YELLOW}[-]${NC} • Install NVIDIA guest drivers v16+ in the VM"
            echo -e "${YELLOW}[-]${NC} • Configure the VM settings as needed"
            echo ""
            echo -e "${GREEN}[+]${NC} VM $vm_id is ready for further configuration in Proxmox web interface"
            
        else
            echo -e "${RED}[!]${NC} Failed to create VM $vm_id"
            return 1
        fi
    else
        echo -e "${YELLOW}[-]${NC} VM creation cancelled"
    fi
}

# Check for root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo or execute as root user."
    exit 1
fi

# Welcome message and disclaimer
echo -e ""
echo -e "${GREEN}        __________  __  __   ____           __        ____          "
echo -e "${YELLOW} _   __${GREEN}/ ____/ __ \/ / / /  /  _/___  _____/ /_____ _/ / /__  _____ "
echo -e "${YELLOW}| | / /${GREEN} / __/ /_/ / / / /   / // __ \/ ___/ __/ __ ' / / / _\/ ___/ "
echo -e "${YELLOW}| |/ /${GREEN} /_/ / ____/ /_/ /  _/ // / / (__  ) /_/ /_/ / / /  __/ /     "
echo -e "${YELLOW}|___/${GREEN}\____/_/    \____/  /___/_/ /_/____/\__/\__,_/_/_/\___/_/      ${NC}"
echo -e "${BLUE}by wvthoog.nl${NC}"
echo -e ""
echo -e "Welcome to the Nvidia vGPU installer version $SCRIPT_VERSION for Proxmox"
echo -e "This system is running Proxmox version ${version} with kernel ${kernel}"
echo -e ""
echo -e "${GREEN}New in v1.3 (PoloLoco Guide Integration):${NC}"
echo -e "• Removed hardcoded download links - user-provided URLs required"
echo -e "• Updated to use PoloLoco's official vgpu-proxmox repository"
echo -e "• Added vGPU override configuration following PoloLoco's guide"
echo -e "• Enhanced Pascal card support with v16.4 vgpuConfig.xml"
echo -e "• Following official PoloLoco recommendations for driver sources"

# Initialize logging and show diagnostics status
if [ "$VERBOSE" = "true" ]; then
    echo -e "${GREEN}[+]${NC} Verbose logging enabled - detailed diagnostics will be shown"
elif [ "$DEBUG" = "true" ]; then
    echo -e "${GREEN}[+]${NC} Debug mode enabled - all command output will be shown"
fi
echo -e "${YELLOW}[-]${NC} Logging to: $VGPU_DIR/$LOG_FILE"

# Initialize log file and capture initial system information
> "$VGPU_DIR/$LOG_FILE"  # Clear previous log
log_system_info "initial"
log_system_info "gpu"
log_system_info "kernel"

if [ "$VERBOSE" = "true" ]; then
    echo -e "${GRAY}[DEBUG] Initial system information logged${NC}"
fi

echo ""

# Function to create vgpu_unlock configuration based on GPU type
create_vgpu_unlock_config() {
    local config_file="/etc/vgpu_unlock/config.toml"
    local vgpu_support="${1:-Unknown}"  # Accept VGPU_SUPPORT as parameter, default to Unknown
    local unlock_setting="true"         # Default to unlock = true
    
    # Check for Tesla P4 cards (device ID 1bb3) - special case
    local tesla_p4_detected=false
    if lspci -nn | grep -i 'NVIDIA Corporation' | grep -q '1bb3'; then
        tesla_p4_detected=true
        echo -e "${GREEN}[+]${NC} Tesla P4 GPU detected"
    fi
    
    # Determine unlock setting based on GPU support type
    # Native vGPU cards (Tesla with native support, GRID) should have unlock = false
    # Consumer cards (GTX, RTX, Quadro without native support) should have unlock = true
    if [ "$vgpu_support" = "Native" ]; then
        unlock_setting="false"
        echo -e "${GREEN}[+]${NC} Native vGPU GPU detected - setting unlock = false"
    elif [ "$tesla_p4_detected" = true ]; then
        # Tesla P4 is a special case - it's marked as "Yes" in DB but needs unlock = false
        unlock_setting="false"
        echo -e "${GREEN}[+]${NC} Tesla P4 requires unlock = false (special case)"
    else
        # Consumer cards and other cases use unlock = true
        unlock_setting="true"
        echo -e "${GREEN}[+]${NC} Consumer GPU detected - setting unlock = true"
    fi
    
    echo -e "${GREEN}[+]${NC} Creating vgpu_unlock configuration file"
    
    # Create minimal config.toml file - only the unlock setting is required
    # Extra settings can cause issues with vgpu_unlock-rs
    echo "unlock = $unlock_setting" > "$config_file"
    
    # Set proper permissions
    chmod 644 "$config_file"
    chown root:root "$config_file" 2>/dev/null || true
    
    echo -e "${GREEN}[+]${NC} vgpu_unlock configuration created: $config_file (unlock = $unlock_setting)"
}

# Function to create vGPU overrides following PoloLoco's guide
create_vgpu_overrides() {
    echo ""
    echo -e "${BLUE}vGPU Override Configuration${NC}"
    echo -e "${BLUE}===========================${NC}"
    echo ""
    echo -e "${YELLOW}[-]${NC} This will help you create vGPU overrides following PoloLoco's guide"
    echo -e "${YELLOW}[-]${NC} Overrides allow customizing vGPU profiles for better performance"
    echo ""
    
    # Check if vgpu_unlock directory exists
    if [ ! -d "/etc/vgpu_unlock" ]; then
        echo -e "${GREEN}[+]${NC} Creating vGPU unlock configuration directory"
        mkdir -p /etc/vgpu_unlock
    fi
    
    local config_file="/etc/vgpu_unlock/profile_override.toml"
    
    # Ask if user wants to create/modify overrides
    read -p "$(echo -e "${BLUE}[?]${NC} Do you want to create/modify vGPU profile overrides? (y/n): ")" create_overrides
    if [ "$create_overrides" != "y" ]; then
        echo -e "${YELLOW}[-]${NC} Skipping vGPU override configuration"
        return 0
    fi
    
    echo ""
    echo -e "${YELLOW}[-]${NC} Available vGPU profiles (run 'mdevctl types' after driver installation):"
    echo -e "${YELLOW}[-]${NC} Common profiles include:"
    echo -e "${YELLOW}[-]${NC} • nvidia-259 (GRID RTX6000-4Q) - 4GB"
    echo -e "${YELLOW}[-]${NC} • nvidia-258 (GRID RTX6000-3Q) - 3GB" 
    echo -e "${YELLOW}[-]${NC} • nvidia-257 (GRID RTX6000-2Q) - 2GB"
    echo -e "${YELLOW}[-]${NC} • nvidia-256 (GRID RTX6000-1Q) - 1GB"
    echo ""
    
    read -p "$(echo -e "${BLUE}[?]${NC} Enter vGPU profile to configure (e.g., nvidia-259): ")" profile_name
    if [ -z "$profile_name" ]; then
        echo -e "${RED}[!]${NC} Profile name cannot be empty"
        return 1
    fi
    
    echo ""
    echo -e "${YELLOW}[-]${NC} Display configuration options:"
    read -p "$(echo -e "${BLUE}[?]${NC} Number of displays (default: 1): ")" num_displays
    num_displays=${num_displays:-1}
    
    read -p "$(echo -e "${BLUE}[?]${NC} Display width (default: 1920): ")" display_width
    display_width=${display_width:-1920}
    
    read -p "$(echo -e "${BLUE}[?]${NC} Display height (default: 1080): ")" display_height
    display_height=${display_height:-1080}
    
    # Calculate max_pixels
    local max_pixels=$((display_width * display_height))
    
    echo ""
    echo -e "${YELLOW}[-]${NC} VRAM configuration options:"
    echo -e "${YELLOW}[-]${NC} Common VRAM sizes:"
    echo -e "${YELLOW}[-]${NC} 1) 512MB"
    echo -e "${YELLOW}[-]${NC} 2) 1GB"
    echo -e "${YELLOW}[-]${NC} 3) 2GB"
    echo -e "${YELLOW}[-]${NC} 4) Custom"
    echo ""
    
    read -p "$(echo -e "${BLUE}[?]${NC} Select VRAM size (1-4): ")" vram_choice
    
    local framebuffer=""
    local framebuffer_reservation=""
    
    case $vram_choice in
        1)
            framebuffer="0x1A000000"
            framebuffer_reservation="0x6000000"
            echo -e "${GREEN}[+]${NC} Selected 512MB VRAM"
            ;;
        2)
            framebuffer="0x38000000"
            framebuffer_reservation="0x8000000"
            echo -e "${GREEN}[+]${NC} Selected 1GB VRAM"
            ;;
        3)
            framebuffer="0x78000000"
            framebuffer_reservation="0x8000000"
            echo -e "${GREEN}[+]${NC} Selected 2GB VRAM"
            ;;
        4)
            echo ""
            echo -e "${YELLOW}[-]${NC} For custom VRAM sizes, please refer to PoloLoco's guide"
            echo -e "${YELLOW}[-]${NC} framebuffer + framebuffer_reservation = total VRAM in bytes"
            read -p "$(echo -e "${BLUE}[?]${NC} Enter framebuffer value (hex, e.g., 0x78000000): ")" framebuffer
            read -p "$(echo -e "${BLUE}[?]${NC} Enter framebuffer_reservation value (hex, e.g., 0x8000000): ")" framebuffer_reservation
            ;;
        *)
            echo -e "${YELLOW}[-]${NC} Invalid choice, using 1GB default"
            framebuffer="0x38000000"
            framebuffer_reservation="0x8000000"
            ;;
    esac
    
    # Ask about VM-specific overrides
    echo ""
    read -p "$(echo -e "${BLUE}[?]${NC} Do you want to create VM-specific overrides? (y/n): ")" vm_specific
    local vm_id=""
    if [ "$vm_specific" = "y" ]; then
        read -p "$(echo -e "${BLUE}[?]${NC} Enter Proxmox VM ID (e.g., 100): ")" vm_id
    fi
    
    # Create or append to configuration file
    echo ""
    echo -e "${GREEN}[+]${NC} Creating vGPU override configuration..."
    
    # Backup existing config if it exists
    if [ -f "$config_file" ]; then
        local backup_file="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$config_file" "$backup_file"
        echo -e "${YELLOW}[-]${NC} Backed up existing config to $backup_file"
    fi
    
    # Create the configuration
    {
        echo "# vGPU Override Configuration"
        echo "# Generated by Proxmox vGPU Installer following PoloLoco's guide"
        echo "# $(date)"
        echo ""
        echo "[profile.${profile_name}]"
        echo "num_displays = $num_displays"
        echo "display_width = $display_width"
        echo "display_height = $display_height"
        echo "max_pixels = $max_pixels"
        
        if [ -n "$framebuffer" ] && [ -n "$framebuffer_reservation" ]; then
            echo "framebuffer = $framebuffer"
            echo "framebuffer_reservation = $framebuffer_reservation"
        fi
        
        if [ -n "$vm_id" ]; then
            echo ""
            echo "[vm.$vm_id]"
            echo "# VM-specific overrides for VM ID $vm_id"
            echo "# You can add specific overrides here that only apply to this VM"
            echo "# For example: frl_enabled = 0"
        fi
        
        echo ""
        echo "# For more configuration options, see:"
        echo "# https://gitlab.com/polloloco/vgpu-proxmox"
        echo "# https://github.com/mbilker/vgpu_unlock-rs"
        
    } > "$config_file"
    
    echo -e "${GREEN}[+]${NC} vGPU override configuration created: $config_file"
    echo ""
    echo -e "${YELLOW}[-]${NC} Configuration summary:"
    echo -e "${YELLOW}[-]${NC} • Profile: $profile_name"
    echo -e "${YELLOW}[-]${NC} • Displays: $num_displays"
    echo -e "${YELLOW}[-]${NC} • Resolution: ${display_width}x${display_height}"
    echo -e "${YELLOW}[-]${NC} • Max pixels: $max_pixels"
    if [ -n "$framebuffer" ]; then
        echo -e "${YELLOW}[-]${NC} • Framebuffer: $framebuffer"
        echo -e "${YELLOW}[-]${NC} • Framebuffer reservation: $framebuffer_reservation"
    fi
    if [ -n "$vm_id" ]; then
        echo -e "${YELLOW}[-]${NC} • VM-specific config for VM ID: $vm_id"
    fi
    echo ""
    echo -e "${GREEN}[+]${NC} vGPU overrides will take effect after driver installation and reboot"
    echo ""
}

# Main installation process
case $STEP in
    1)
    # Check for Pascal GPU early and display PSA following PoloLoco's recommendations
    if detect_pascal_gpu; then
        display_pascal_psa
        echo -e "${BLUE}Press any key to continue to the menu...${NC}"
        read -n 1 -s
        echo ""
    fi
    
    echo "Select an option:"
    echo ""
    echo "1) New vGPU installation"
    echo "2) Upgrade vGPU installation"
    echo "3) Remove vGPU installation"
    echo "4) Download vGPU drivers"
    echo "5) License vGPU"
    echo "6) Create vGPU overrides (PoloLoco guide)"
    echo "7) Configure Pascal VM (ROM spoofing)"
    echo "8) Exit"
    echo ""
    read -p "Enter your choice: " choice

    case $choice in
        1|2)
            echo ""
            echo "You are currently at step ${STEP} of the installation process"
            echo ""
            if [ "$choice" -eq 1 ]; then
                echo -e "${GREEN}Selected:${NC} New vGPU installation"
                # Check if config file exists, if not, create it
                if [ ! -f "$VGPU_DIR/$CONFIG_FILE" ]; then
                    echo "STEP=1" > "$VGPU_DIR/$CONFIG_FILE"
                fi
            elif [ "$choice" -eq 2 ]; then
                echo -e "${GREEN}Selected:${NC} Upgrade from previous vGPU installation"
            fi
            echo ""

            # Function to replace repository lines
            replace_repo_lines() {
                local old_repo="$1"
                local new_repo="$2"
                # Check /etc/apt/sources.list
                if grep -q "$old_repo" /etc/apt/sources.list; then
                    sed -i "s|$old_repo|$new_repo|" /etc/apt/sources.list
                fi
                # Check files under /etc/apt/sources.list.d/
                for file in /etc/apt/sources.list.d/*; do
                    if [ -f "$file" ]; then
                        if grep -q "$old_repo" "$file"; then
                            sed -i "s|$old_repo|$new_repo|" "$file"
                        fi
                    fi
                done
            }

            # Commands for new installation
            echo -e "${GREEN}[+]${NC} Making changes to APT for Proxmox version: ${RED}$major_version${NC}"
            case $major_version in
                8)
                    proxmox_repo="deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription"
                    ;;
                7)
                    proxmox_repo="deb http://download.proxmox.com/debian/pve bullseye pve-no-subscription"
                    ;;
                *)
                    echo -e "${RED}[!]${NC} Unsupported Proxmox version: ${YELLOW}$major_version${NC}"
                    exit 1
                    ;;
            esac

            # Replace repository lines
            replace_repo_lines "deb https://enterprise.proxmox.com/debian/pve bullseye pve-enterprise" "$proxmox_repo"
            replace_repo_lines "deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise" "$proxmox_repo"
            replace_repo_lines "deb https://enterprise.proxmox.com/debian/ceph-quincy bookworm enterprise" "deb http://download.proxmox.com/debian/ceph-quincy bookworm no-subscription"

            # Check if Proxmox repository entry exists in /etc/apt/sources.list
            if ! grep -q "$proxmox_repo" /etc/apt/sources.list; then
                echo -e "${GREEN}[+]${NC} Adding Proxmox repository entry to /etc/apt/sources.list${NC}"
                echo "$proxmox_repo" >> /etc/apt/sources.list
            fi

            # # Comment Proxmox enterprise repository
            # echo -e "${GREEN}[+]${NC} Commenting Proxmox enterprise repository"
            # sed -i 's/^/#/' /etc/apt/sources.list.d/pve-enterprise.list

            # # Replace ceph-quincy enterprise for non-subscribtion
            # echo -e "${GREEN}[+]${NC} Set Ceph to no-subscription"
            # sed -i 's#^enterprise #no-subscription#' /etc/apt/sources.list.d/ceph.list

            # APT update/upgrade
            write_log "Starting APT operations"
            run_command "Running APT Update" "info" "apt update" true true

            # Prompt the user for confirmation
            echo ""
            read -p "$(echo -e "${BLUE}[?]${NC} Do you want to proceed with APT Dist-Upgrade ? (y/n): ")" confirmation
            echo ""

            # Check user's choice
            if [ "$confirmation" == "y" ]; then
                #echo "running apt dist-upgrade"
                run_command "Running APT Dist-Upgrade (...this might take some time)" "info" "apt dist-upgrade -y" true true
            else
                echo -e "${YELLOW}[-]${NC} Skipping APT Dist-Upgrade"
                write_log "APT dist-upgrade skipped by user"
            fi          

            # APT installing packages
            # NVIDIA vGPU Driver Kernel Compatibility Requirements:
            # - v16.x drivers (535.x series): Only tested and certified with kernel 6.5.x
            #   These older drivers may fail to compile with newer kernels due to API changes
            # - v17.x drivers (550.x series): Support kernel 6.5.x and newer (6.6, 6.7, 6.8)
            # - v18.x drivers (570.x series): Support kernel 6.5.x and newer
            # - v19.x drivers (580.x series): Support kernel 6.5.x and newer
            # 
            # Installing kernel 6.5 to ensure compatibility with v16.x drivers if needed
            # Note: proxmox-headers-6.5 used instead of pve-headers which pulls latest (6.8+)
            
            # Get current kernel version for header installation
            current_kernel=$(uname -r)
            current_kernel_base=$(echo $current_kernel | cut -d'-' -f1,2)
            echo -e "${GREEN}[+]${NC} Current running kernel: $current_kernel"
            
            # Install both current kernel headers and 6.5 headers for compatibility
            write_log "Installing required packages for vGPU"
            run_command "Installing packages" "info" "apt install -y git build-essential dkms proxmox-kernel-6.5 proxmox-headers-6.5 mdevctl megatools" true true
            run_command "Installing headers for current kernel" "info" "apt install -y proxmox-headers-$current_kernel_base || apt install -y pve-headers-$current_kernel" false true

            echo -e "${YELLOW}[-]${NC} Kernel 6.5 installed. Kernel pinning will be determined based on selected driver version."
            echo -e "${YELLOW}[-]${NC} v16.x drivers (535.x series) require kernel 6.5 for stability"
            echo -e "${YELLOW}[-]${NC} v17.x, v18.x, and v19.x drivers can use newer kernels"

            # Running NVIDIA GPU checks
            query_gpu_info() {
            local gpu_device_id="$1"
            local query_result=$(sqlite3 gpu_info.db "SELECT * FROM gpu_info WHERE deviceid='$gpu_device_id';")
            echo "$query_result"
            }

            gpu_info=$(lspci -nn | grep -i 'NVIDIA Corporation' | grep -Ei '(VGA compatible controller|3D controller)')

            # Check if no NVIDIA GPU was found
            if [ -z "$gpu_info" ]; then
                read -p "$(echo -e "${RED}[!]${NC} No Nvidia GPU available in system, Continue? (y/n): ")" continue_choice
                if [ "$continue_choice" != "y" ]; then
                    echo "Exiting script."
                    exit 0
                fi

            # Check if only one NVIDIA GPU was found
            elif [ -n "$gpu_info" ] && [ $(echo "$gpu_info" | wc -l) -eq 1 ]; then
                # Extract device IDs from the output
                gpu_device_id=$(echo "$gpu_info" | grep -oE '\[10de:[0-9a-fA-F]{2,4}\]' | cut -d ':' -f 2 | tr -d ']')
                query_result=$(query_gpu_info "$gpu_device_id")

                if [[ -n "$query_result" ]]; then
                    vendor_id=$(echo "$query_result" | cut -d '|' -f 1)
                    description=$(echo "$query_result" | cut -d '|' -f 3)
                    vgpu=$(echo "$query_result" | cut -d '|' -f 4)
                    driver=$(echo "$query_result" | cut -d '|' -f 5 | tr ';' ',')
                    chip=$(echo "$query_result" | cut -d '|' -f 6)

                    if [[ -z "$chip" ]]; then
                        chip="Unknown"
                    fi

                    echo -e "${GREEN}[*]${NC} Found one Nvidia GPU in your system"
                    echo ""

                    # Write $driver to CONFIG_FILE. To be used to determine which driver to download in step 2

                    if [[ "$vgpu" == "No" ]]; then
                        echo "$description is not vGPU capable"
                        VGPU_SUPPORT="No"
                    elif [[ "$vgpu" == "Yes" ]]; then
                        echo "$description is vGPU capable through vgpu_unlock with driver version $driver"
                        VGPU_SUPPORT="Yes"
                        DRIVER_VERSION=$driver
                    elif [[ "$vgpu" == "Native" ]]; then
                        echo "$description supports native vGPU with driver version $driver"
                        VGPU_SUPPORT="Native"
                        DRIVER_VERSION=$driver
                    else
                        echo "$description of the $chip architecture and vGPU capability is unknown"
                        VGPU_SUPPORT="Unknown"
                    fi
                else
                    echo "Device ID: $gpu_device_id not found in the database."
                    VGPU_SUPPORT="Unknown"
                fi
                echo ""

            # If multiple NVIDIA GPU's were found
            else
                # Extract GPU devices from lspci -nn output
                gpu_devices=$(lspci -nn | grep -Ei '(VGA compatible controller|3D controller).*NVIDIA Corporation')

                # Declare associative array to store GPU PCI IDs and device IDs
                declare -A gpu_pci_groups

                # Iterate over each GPU device line
                while read -r device; do
                    pci_id=$(echo "$device" | awk '{print $1}')
                    pci_device_id=$(echo "$device" | grep -oE '\[10de:[0-9a-fA-F]{2,4}\]' | cut -d ':' -f 2 | tr -d ']')
                    gpu_pci_groups["$pci_id"]="$pci_device_id"
                done <<< "$gpu_devices"

                # Iterate over each VGA GPU device, query its info, and display it
                echo -e "${GREEN}[*]${NC} Found multiple Nvidia GPUs in your system"
                echo ""

                # Initialize VGPU_SUPPORT variable
                VGPU_SUPPORT="Unknown"

                index=1
                for pci_id in "${!gpu_pci_groups[@]}"; do
                    gpu_device_id=${gpu_pci_groups[$pci_id]}
                    query_result=$(query_gpu_info "$gpu_device_id")
                    
                    if [[ -n "$query_result" ]]; then
                        vendor_id=$(echo "$query_result" | cut -d '|' -f 1)
                        description=$(echo "$query_result" | cut -d '|' -f 3)
                        vgpu=$(echo "$query_result" | cut -d '|' -f 4)
                        driver=$(echo "$query_result" | cut -d '|' -f 5 | tr ';' ',')
                        chip=$(echo "$query_result" | cut -d '|' -f 6)

                        if [[ -z "$chip" ]]; then
                            chip="Unknown"
                        fi

                        #echo "Driver: $driver"                        
                        
                        case $vgpu in
                            No)
                                if [[ "$VGPU_SUPPORT" == "Unknown" ]]; then
                                    gpu_info="is not vGPU capable"
                                    VGPU_SUPPORT="No"
                                fi
                                ;;
                            Yes)
                                if [[ "$VGPU_SUPPORT" == "No" ]]; then
                                    gpu_info="is vGPU capable through vgpu_unlock with driver version $driver"
                                    VGPU_SUPPORT="Yes"
                                    echo "info1: $driver"  
                                elif [[ "$VGPU_SUPPORT" == "Unknown" ]]; then
                                    gpu_info="is vGPU capable through vgpu_unlock with driver version $driver"
                                    VGPU_SUPPORT="Yes"
                                    echo "info2: $driver"  
                                fi
                                ;;
                            Native)
                                if [[ "$VGPU_SUPPORT" == "No" ]]; then
                                    gpu_info="supports native vGPU with driver version $driver"
                                    VGPU_SUPPORT="Native"
                                elif [[ "$VGPU_SUPPORT" == "Yes" ]]; then
                                    gpu_info="supports native vGPU with driver version $driver"
                                    VGPU_SUPPORT="Native"
                                    # Implore the user to use the native vGPU card and pass through the other card(s)
                                elif [[ "$VGPU_SUPPORT" == "Unknown" ]]; then
                                    gpu_info="supports native vGPU with driver version $driver"
                                    VGPU_SUPPORT="Native"
                                fi
                                ;;
                            Unknown)
                                    gpu_info="is a unknown GPU"
                                    VGPU_SUPPORT="No"
                                ;;
                        esac

                        # Display GPU info
                        echo "$index: $description $gpu_info"
                    else
                        echo "$index: GPU Device ID: $gpu_device_id on PCI bus 0000:$pci_id (query result not found in database)"
                    fi
                    
                    ((index++))
                done

                echo ""

                # Identify vGPU-capable GPUs and allow multiple selections
                declare -a vgpu_capable_cards
                declare -a selected_vgpu_cards
                declare -a passthrough_cards
                
                # Collect vGPU-capable GPUs
                index=1
                for pci_id in "${!gpu_pci_groups[@]}"; do
                    gpu_device_id=${gpu_pci_groups[$pci_id]}
                    query_result=$(query_gpu_info "$gpu_device_id")
                    
                    if [[ -n "$query_result" ]]; then
                        vgpu=$(echo "$query_result" | cut -d '|' -f 4)
                        description=$(echo "$query_result" | cut -d '|' -f 3)
                        
                        if [[ "$vgpu" == "Yes" ]] || [[ "$vgpu" == "Native" ]]; then
                            vgpu_capable_cards+=("$index:$pci_id:$description:$vgpu")
                        else
                            # Non-vGPU capable cards go straight to passthrough candidates
                            passthrough_cards+=("$index:$pci_id:$description")
                        fi
                    else
                        # Unknown cards go to passthrough candidates
                        passthrough_cards+=("$index:$pci_id:Unknown GPU")
                    fi
                    ((index++))
                done

                # Handle vGPU-capable GPUs
                if [[ ${#vgpu_capable_cards[@]} -eq 0 ]]; then
                    echo -e "${RED}[!]${NC} No vGPU-capable cards found in your system"
                    echo "Exiting script."
                    exit 1
                elif [[ ${#vgpu_capable_cards[@]} -eq 1 ]]; then
                    # Single vGPU-capable card - automatically select it
                    card_info="${vgpu_capable_cards[0]}"
                    card_index=$(echo "$card_info" | cut -d ':' -f 1)
                    selected_pci_id=$(echo "$card_info" | cut -d ':' -f 2)
                    description=$(echo "$card_info" | cut -d ':' -f 3)
                    vgpu_type=$(echo "$card_info" | cut -d ':' -f 4)
                    
                    echo -e "${GREEN}[*]${NC} Using GPU $card_index: $description ($vgpu_type vGPU support) for vGPU"
                    selected_vgpu_cards+=("$selected_pci_id")
                    
                    # Set driver version from the selected card
                    gpu_device_id=${gpu_pci_groups[$selected_pci_id]}
                    query_result=$(query_gpu_info "$gpu_device_id")
                    driver=$(echo "$query_result" | cut -d '|' -f 5 | tr ';' ',')
                    DRIVER_VERSION=$driver
                else
                    # Multiple vGPU-capable cards - let user choose with NVIDIA compliance warnings
                    echo -e "${GREEN}[*]${NC} Found ${#vgpu_capable_cards[@]} vGPU-capable GPUs. You can enable vGPU on multiple cards simultaneously."
                    echo -e "${YELLOW}[!]${NC} NVIDIA vGPU 16.0 Compliance Notes:"
                    echo "  - All selected GPUs must be compatible with the same driver version"
                    echo "  - Mixed GPU architectures may cause compatibility issues"
                    echo "  - Each vGPU-enabled GPU requires proper NVIDIA vGPU licensing"
                    echo "  - Ensure adequate system power and cooling for multiple vGPU cards"
                    echo ""
                    
                    # Display GPUs with driver version info for compatibility checking
                    declare -A gpu_drivers
                    echo "Available vGPU-capable GPUs:"
                    for card_info in "${vgpu_capable_cards[@]}"; do
                        card_index=$(echo "$card_info" | cut -d ':' -f 1)
                        card_pci=$(echo "$card_info" | cut -d ':' -f 2)
                        description=$(echo "$card_info" | cut -d ':' -f 3)
                        vgpu_type=$(echo "$card_info" | cut -d ':' -f 4)
                        
                        # Get driver version for this card
                        gpu_device_id=${gpu_pci_groups[$card_pci]}
                        query_result=$(query_gpu_info "$gpu_device_id")
                        if [[ -n "$query_result" ]]; then
                            driver=$(echo "$query_result" | cut -d '|' -f 5 | tr ';' ',')
                            gpu_drivers[$card_index]="$driver"
                            echo "  $card_index: $description ($vgpu_type vGPU, Driver: $driver)"
                        else
                            echo "  $card_index: $description ($vgpu_type vGPU, Driver: Unknown)"
                        fi
                    done
                    echo ""
                    
                    echo -e "${BLUE}[?]${NC} Select GPUs for vGPU (enter numbers separated by spaces, e.g., '1 3 4'):"
                    echo -e "${BLUE}[?]${NC} For NVIDIA compliance, select GPUs with compatible driver versions"
                    echo -e "${BLUE}[?]${NC} Press '0' for single GPU mode (recommended for first-time setups)"
                    echo -e "${BLUE}[?]${NC} Or press Enter to use ALL vGPU-capable cards (advanced users only):"
                    read -p "$(echo -e "${BLUE}[?]${NC} Your selection: ")" selected_indexes
                    echo ""

                    # Process selection with NVIDIA compliance validation
                    if [[ "$selected_indexes" == "0" ]]; then
                        # Single GPU mode - let user select one GPU
                        echo -e "${GREEN}[*]${NC} Single GPU mode selected (NVIDIA recommended for initial setups)"
                        echo -e "${BLUE}[?]${NC} Select ONE GPU for vGPU:"
                        read -p "$(echo -e "${BLUE}[?]${NC} Enter GPU number: ")" single_gpu_idx
                        
                        # Validate and find the single selected card
                        card_found=false
                        for card_info in "${vgpu_capable_cards[@]}"; do
                            card_index=$(echo "$card_info" | cut -d ':' -f 1)
                            if [[ "$card_index" == "$single_gpu_idx" ]]; then
                                selected_pci_id=$(echo "$card_info" | cut -d ':' -f 2)
                                description=$(echo "$card_info" | cut -d ':' -f 3)
                                selected_vgpu_cards+=("$selected_pci_id")
                                echo -e "${GREEN}[*]${NC} Selected GPU $single_gpu_idx: $description for vGPU"
                                card_found=true
                                break
                            fi
                        done
                        if [[ "$card_found" == false ]]; then
                            echo -e "${RED}[!]${NC} Invalid selection: $single_gpu_idx"
                            exit 1
                        fi
                        
                    elif [[ -z "$selected_indexes" ]]; then
                        # Use all vGPU-capable cards (advanced mode)
                        echo -e "${YELLOW}[!]${NC} Advanced mode: Using ALL vGPU-capable cards"
                        echo -e "${YELLOW}[!]${NC} Ensure all GPUs are compatible and properly licensed"
                        
                        # Validate driver compatibility across all cards
                        declare -A driver_versions
                        for card_info in "${vgpu_capable_cards[@]}"; do
                            card_index=$(echo "$card_info" | cut -d ':' -f 1)
                            if [[ -n "${gpu_drivers[$card_index]}" ]]; then
                                driver_versions["${gpu_drivers[$card_index]}"]=1
                            fi
                        done
                        
                        if [[ ${#driver_versions[@]} -gt 1 ]]; then
                            echo -e "${YELLOW}[!]${NC} WARNING: Multiple driver versions detected across selected GPUs"
                            echo -e "${YELLOW}[!]${NC} This may cause NVIDIA vGPU compatibility issues"
                            read -p "$(echo -e "${BLUE}[?]${NC} Continue anyway? (y/N): ")" continue_mixed
                            if [[ "$continue_mixed" != "y" ]]; then
                                echo -e "${RED}[!]${NC} Aborted. Please select GPUs with compatible driver versions."
                                exit 1
                            fi
                        fi
                        
                        for card_info in "${vgpu_capable_cards[@]}"; do
                            card_index=$(echo "$card_info" | cut -d ':' -f 1)
                            selected_pci_id=$(echo "$card_info" | cut -d ':' -f 2)
                            description=$(echo "$card_info" | cut -d ':' -f 3)
                            selected_vgpu_cards+=("$selected_pci_id")
                            echo -e "${GREEN}[*]${NC} Selected GPU $card_index: $description for vGPU"
                        done
                        echo -e "${GREEN}[*]${NC} All ${#selected_vgpu_cards[@]} vGPU-capable GPUs selected"
                        
                    else
                        # Use selected cards with validation
                        IFS=' ' read -ra indexes <<< "$selected_indexes"
                        
                        # Validate driver compatibility across selected cards first
                        declare -A selected_driver_versions
                        for idx in "${indexes[@]}"; do
                            if [[ -n "${gpu_drivers[$idx]}" ]]; then
                                selected_driver_versions["${gpu_drivers[$idx]}"]=1
                            fi
                        done
                        
                        if [[ ${#selected_driver_versions[@]} -gt 1 ]]; then
                            echo -e "${YELLOW}[!]${NC} WARNING: Selected GPUs have different driver versions"
                            echo -e "${YELLOW}[!]${NC} This violates NVIDIA vGPU compatibility requirements"
                            read -p "$(echo -e "${BLUE}[?]${NC} Continue anyway? (y/N): ")" continue_mixed
                            if [[ "$continue_mixed" != "y" ]]; then
                                echo -e "${RED}[!]${NC} Aborted. Please select GPUs with the same driver version."
                                exit 1
                            fi
                        fi
                        
                        # Process valid selections
                        for idx in "${indexes[@]}"; do
                            # Validate and find the card
                            card_found=false
                            for card_info in "${vgpu_capable_cards[@]}"; do
                                card_index=$(echo "$card_info" | cut -d ':' -f 1)
                                if [[ "$card_index" == "$idx" ]]; then
                                    selected_pci_id=$(echo "$card_info" | cut -d ':' -f 2)
                                    description=$(echo "$card_info" | cut -d ':' -f 3)
                                    selected_vgpu_cards+=("$selected_pci_id")
                                    echo -e "${GREEN}[*]${NC} Selected GPU $idx: $description for vGPU"
                                    card_found=true
                                    break
                                fi
                            done
                            if [[ "$card_found" == false ]]; then
                                echo -e "${RED}[!]${NC} Invalid selection: $idx"
                                exit 1
                            fi
                        done
                        
                        if [[ ${#selected_vgpu_cards[@]} -gt 1 ]]; then
                            echo -e "${GREEN}[*]${NC} Multi-GPU vGPU configuration selected"
                            echo -e "${YELLOW}[!]${NC} Ensure adequate system resources and NVIDIA vGPU licensing"
                        fi
                    fi

                    # Set driver version with additional validation for multi-GPU setups
                    if [[ ${#selected_vgpu_cards[@]} -gt 0 ]]; then
                        gpu_device_id=${gpu_pci_groups[${selected_vgpu_cards[0]}]}
                        query_result=$(query_gpu_info "$gpu_device_id")
                        driver=$(echo "$query_result" | cut -d '|' -f 5 | tr ';' ',')
                        DRIVER_VERSION=$driver
                        
                        # For multi-GPU setups, verify all selected cards use the same driver
                        if [[ ${#selected_vgpu_cards[@]} -gt 1 ]]; then
                            echo -e "${GREEN}[*]${NC} Validating driver compatibility across ${#selected_vgpu_cards[@]} selected GPUs..."
                            for selected_pci in "${selected_vgpu_cards[@]:1}"; do  # Skip first card, already checked
                                check_device_id=${gpu_pci_groups[$selected_pci]}
                                check_query=$(query_gpu_info "$check_device_id")
                                if [[ -n "$check_query" ]]; then
                                    check_driver=$(echo "$check_query" | cut -d '|' -f 5 | tr ';' ',')
                                    if [[ "$check_driver" != "$driver" ]]; then
                                        echo -e "${RED}[!]${NC} Driver version mismatch detected!"
                                        echo -e "${RED}[!]${NC} Primary GPU requires driver: $driver"
                                        echo -e "${RED}[!]${NC} Secondary GPU requires driver: $check_driver"
                                        echo -e "${RED}[!]${NC} This violates NVIDIA vGPU 16.0 compatibility requirements."
                                        exit 1
                                    fi
                                fi
                            done
                            echo -e "${GREEN}[+]${NC} All selected GPUs are compatible with driver version: $driver"
                        fi
                    fi
                fi

                # Handle passthrough for remaining cards
                remaining_cards=()
                for pci_id in "${!gpu_pci_groups[@]}"; do
                    is_selected_vgpu=false
                    for selected_pci in "${selected_vgpu_cards[@]}"; do
                        if [[ "$pci_id" == "$selected_pci" ]]; then
                            is_selected_vgpu=true
                            break
                        fi
                    done
                    
                    if [[ "$is_selected_vgpu" == false ]]; then
                        remaining_cards+=("$pci_id")
                    fi
                done

                if [[ ${#remaining_cards[@]} -gt 0 ]]; then
                    echo ""
                    echo -e "${YELLOW}[-]${NC} Found ${#remaining_cards[@]} GPU(s) not selected for vGPU:"
                    for pci_id in "${remaining_cards[@]}"; do
                        gpu_device_id=${gpu_pci_groups[$pci_id]}
                        query_result=$(query_gpu_info "$gpu_device_id")
                        if [[ -n "$query_result" ]]; then
                            description=$(echo "$query_result" | cut -d '|' -f 3)
                            vgpu=$(echo "$query_result" | cut -d '|' -f 4)
                            echo "  - $description on PCI $pci_id ($vgpu vGPU capability)"
                        else
                            echo "  - Unknown GPU on PCI $pci_id"
                        fi
                    done
                    
                    echo ""
                    read -p "$(echo -e "${BLUE}[?]${NC} Enable passthrough for these remaining GPU(s)? (y/n): ")" enable_pass_through
                    echo ""
                    
                    if [[ "$enable_pass_through" == "y" ]]; then
                        echo -e "${YELLOW}[-]${NC} Enabling passthrough for remaining devices:"
                        echo ""
                        for pci_id in "${remaining_cards[@]}"; do
                            if [ ! -z "$(ls -A /sys/class/iommu)" ]; then
                                iommu_group_path="/sys/bus/pci/devices/0000:$pci_id/iommu_group/devices"
                                if [ -d "$iommu_group_path" ]; then
                                    for iommu_dev in "$iommu_group_path"/*; do
                                        if [ -e "$iommu_dev" ]; then
                                            iommu_dev_name=$(basename "$iommu_dev")
                                            echo "PCI ID: $iommu_dev_name"
                                            echo "ACTION==\"add\", SUBSYSTEM==\"pci\", KERNELS==\"$iommu_dev_name\", DRIVERS==\"*\", ATTR{driver_override}=\"vfio-pci\"" >> /etc/udev/rules.d/90-vfio-pci.rules
                                        fi
                                    done
                                fi
                            fi
                        done
                        echo ""
                    elif [[ "$enable_pass_through" == "n" ]]; then
                        echo -e "${YELLOW}[-]${NC} Skipping passthrough configuration for remaining cards"
                        echo -e "${YELLOW}[-]${NC} You can manually configure them later if needed"
                        echo ""
                    else
                        echo -e "${RED}[!]${NC} Invalid input. Please enter (y/n)."
                        exit 1
                    fi
                fi
            fi

            #echo "VGPU_SUPPORT: $VGPU_SUPPORT"

            update_grub() {
                # Checking CPU architecture
                echo -e "${GREEN}[+]${NC} Checking CPU architecture"
                vendor_id=$(cat /proc/cpuinfo | grep vendor_id | awk 'NR==1{print $3}')

                # Ask user about iommu=pt parameter
                echo ""
                echo -e "${BLUE}IOMMU Configuration${NC}"
                echo -e "${BLUE}===================${NC}"
                echo ""
                echo -e "${YELLOW}[-]${NC} The 'iommu=pt' parameter can affect system behavior:"
                echo -e "${YELLOW}[-]${NC} • Without iommu=pt: Better stability, recommended for most cases"
                echo -e "${YELLOW}[-]${NC} • With iommu=pt: May improve performance in some scenarios"
                echo -e "${YELLOW}[-]${NC} • Note: Can cause unexpected behavior with some hardware (e.g., Tesla P4)"
                echo ""
                echo -n -e "${YELLOW}[-]${NC} Do you want to include 'iommu=pt' in GRUB configuration? (y/n): "
                read -r include_iommu_pt
                echo ""

                if [ "$vendor_id" = "AuthenticAMD" ]; then
                    echo -e "${GREEN}[+]${NC} Your CPU vendor id: ${YELLOW}${vendor_id}${NC}"
                    
                    # Handle iommu=pt based on user choice
                    if [ "$include_iommu_pt" = "y" ] || [ "$include_iommu_pt" = "Y" ]; then
                        # Add iommu=pt if not present
                        if ! grep -q "iommu=pt" /etc/default/grub; then
                            sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/"$/ iommu=pt"/' /etc/default/grub
                            echo -e "${GREEN}[+]${NC} Added iommu=pt parameter to GRUB configuration"
                        else
                            echo -e "${YELLOW}[-]${NC} iommu=pt parameter already present in GRUB configuration"
                        fi
                    else
                        # Remove iommu=pt if present
                        if grep -q "iommu=pt" /etc/default/grub; then
                            echo -e "${YELLOW}[-]${NC} Removing iommu=pt parameter from GRUB configuration"
                            sed -i 's/ iommu=pt//g' /etc/default/grub
                        else
                            echo -e "${GREEN}[+]${NC} iommu=pt not present (recommended for stability)"
                        fi
                    fi
                    
                    # Check if the required AMD IOMMU option is already present
                    if grep -q "amd_iommu=on" /etc/default/grub; then
                        echo -e "${YELLOW}[-]${NC} AMD IOMMU option already set in GRUB_CMDLINE_LINUX_DEFAULT"
                    else
                        sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/"$/ amd_iommu=on"/' /etc/default/grub
                        echo -e "${GREEN}[+]${NC} AMD IOMMU option added to GRUB_CMDLINE_LINUX_DEFAULT"
                    fi
                elif [ "$vendor_id" = "GenuineIntel" ]; then
                    echo -e "${GREEN}[+]${NC} Your CPU vendor id: ${YELLOW}${vendor_id}${NC}"
                    
                    # Handle iommu=pt based on user choice
                    if [ "$include_iommu_pt" = "y" ] || [ "$include_iommu_pt" = "Y" ]; then
                        # Add iommu=pt if not present
                        if ! grep -q "iommu=pt" /etc/default/grub; then
                            sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/"$/ iommu=pt"/' /etc/default/grub
                            echo -e "${GREEN}[+]${NC} Added iommu=pt parameter to GRUB configuration"
                        else
                            echo -e "${YELLOW}[-]${NC} iommu=pt parameter already present in GRUB configuration"
                        fi
                    else
                        # Remove iommu=pt if present
                        if grep -q "iommu=pt" /etc/default/grub; then
                            echo -e "${YELLOW}[-]${NC} Removing iommu=pt parameter from GRUB configuration"
                            sed -i 's/ iommu=pt//g' /etc/default/grub
                        else
                            echo -e "${GREEN}[+]${NC} iommu=pt not present (recommended for stability)"
                        fi
                    fi
                    
                    # Check if the required Intel IOMMU option is already present
                    if grep -q "intel_iommu=on" /etc/default/grub; then
                        echo -e "${YELLOW}[-]${NC} Intel IOMMU option already set in GRUB_CMDLINE_LINUX_DEFAULT"
                    else
                        sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/"$/ intel_iommu=on"/' /etc/default/grub
                        echo -e "${GREEN}[+]${NC} Intel IOMMU option added to GRUB_CMDLINE_LINUX_DEFAULT"
                    fi
                else
                    echo -e "${RED}[!]${NC} Unknown CPU architecture. Unable to configure GRUB"
                    exit 1
                fi           
                # Update GRUB
                #echo "updating grub"
                run_command "Updating GRUB" "info" "update-grub"
            }

            if [ "$choice" -eq 1 ]; then
                # Check the value of VGPU_SUPPORT
                if [ "$VGPU_SUPPORT" = "No" ]; then
                    echo -e "${RED}[!]${NC} You don't have a vGPU capable card in your system"
                    echo "Exiting  script."
                    exit 1
                elif [ "$VGPU_SUPPORT" = "Yes" ]; then
                    # Download vgpu-proxmox from PoloLoco's official repository
                    rm -rf $VGPU_DIR/vgpu-proxmox 2>/dev/null 
                    #echo "downloading vgpu-proxmox"
                    run_command "Downloading vgpu-proxmox from PoloLoco's official repository" "info" "git clone https://gitlab.com/polloloco/vgpu-proxmox.git $VGPU_DIR/vgpu-proxmox"

                    # Download vgpu_unlock-rs
                    cd /opt
                    rm -rf vgpu_unlock-rs 2>/dev/null 
                    #echo "downloading vgpu_unlock-rs"
                    run_command "Downloading vgpu_unlock-rs" "info" "git clone https://github.com/mbilker/vgpu_unlock-rs.git"

                    # Download and source Rust
                    #echo "downloading rust"
                    run_command "Downloading Rust" "info" "curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal"
                    #echo "source rust"
                    run_command "Source Rust" "info" "source $HOME/.cargo/env"

                    # Building vgpu_unlock-rs
                    cd vgpu_unlock-rs/
                    #echo "building vgpu_unlock-rs"
                    run_command "Building vgpu_unlock-rs" "info" "cargo build --release"

                    # Creating vgpu directory and configuration files
                    echo -e "${GREEN}[+]${NC} Creating vGPU files and directories"
                    mkdir -p /etc/vgpu_unlock
                    
                    # Create vgpu_unlock configuration (GPU type aware)
                    create_vgpu_unlock_config "$VGPU_SUPPORT"
                    
                    # Create empty profile override file (can be customized later)
                    touch /etc/vgpu_unlock/profile_override.toml

                    # Creating systemd folders
                    echo -e "${GREEN}[+]${NC} Creating systemd folders"
                    mkdir -p /etc/systemd/system/{nvidia-vgpud.service.d,nvidia-vgpu-mgr.service.d}

                    # Adding vgpu_unlock-rs library
                    echo -e "${GREEN}[+]${NC} Adding vgpu_unlock-rs library"
                    echo -e "[Service]\nEnvironment=LD_PRELOAD=/opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so" > /etc/systemd/system/nvidia-vgpud.service.d/vgpu_unlock.conf
                    echo -e "[Service]\nEnvironment=LD_PRELOAD=/opt/vgpu_unlock-rs/target/release/libvgpu_unlock_rs.so" > /etc/systemd/system/nvidia-vgpu-mgr.service.d/vgpu_unlock.conf
                
                    # Systemd daemon-reload is needed for service overrides (not for service management)
                    run_command "Systemctl daemon-reload" "info" "systemctl daemon-reload"
                    update_grub

                elif [ "$VGPU_SUPPORT" = "Native" ]; then
                    # Execute steps for "Native" VGPU_SUPPORT
                    # For Pascal GPUs with "Native" support, we may still need patches for v17.x+ drivers
                    # Download vgpu-proxmox patches proactively in case user selects v17.x+ driver in Step 2
                    if detect_pascal_gpu; then
                        echo -e "${YELLOW}[-]${NC} Pascal GPU detected with Native support - downloading patches for potential v17.x+ driver usage"
                        rm -rf $VGPU_DIR/vgpu-proxmox 2>/dev/null 
                        run_command "Downloading vgpu-proxmox from PoloLoco's official repository" "info" "git clone https://gitlab.com/polloloco/vgpu-proxmox.git $VGPU_DIR/vgpu-proxmox"
                        write_log "NATIVE + Pascal GPU: Downloaded vgpu-proxmox patches for potential v17.x+ driver usage"
                    fi
                    update_grub
                fi
            # Removing previous installations of vgpu
            elif [ "$choice" -eq 2 ]; then
                #echo "removing nvidia driver"
                # Removing previous Nvidia driver
                if command -v nvidia-uninstall >/dev/null 2>&1; then
                    echo -e "${YELLOW}[-]${NC} NVIDIA driver found, removing for upgrade..."
                    run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s" false
                elif [ -x "/usr/bin/nvidia-uninstall" ] || [ -x "/usr/local/bin/nvidia-uninstall" ]; then
                    echo -e "${YELLOW}[-]${NC} NVIDIA driver found, removing for upgrade..."
                    run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s" false
                else
                    echo -e "${YELLOW}[-]${NC} No NVIDIA driver installation found, skipping driver removal for upgrade..."
                    write_log "UPGRADE SKIPPED: No NVIDIA driver found to remove"
                fi
                # Removing previous vgpu_unlock-rs
                run_command "Removing previous vgpu_unlock-rs" "notification" "rm -rf /opt/vgpu_unlock-rs/ 2>/dev/null"
                # Removing vgpu-proxmox
                run_command "Removing vgpu-proxmox" "notification" "rm -rf $VGPU_DIR/vgpu-proxmox 2>/dev/null"
                
                # Re-download vgpu-proxmox for upgrades if patching is needed (Pascal GPUs or VGPU_SUPPORT=Yes)
                # This ensures patches are available for Step 2 driver installation
                if [ "$VGPU_SUPPORT" = "Yes" ] || detect_pascal_gpu; then
                    echo -e "${YELLOW}[-]${NC} Re-downloading vgpu-proxmox patches for upgrade..."
                    run_command "Downloading vgpu-proxmox from PoloLoco's official repository" "info" "git clone https://gitlab.com/polloloco/vgpu-proxmox.git $VGPU_DIR/vgpu-proxmox"
                    write_log "UPGRADE: Downloaded vgpu-proxmox patches for Pascal GPU or VGPU_SUPPORT=Yes"
                fi
            fi

            # Check if the specified lines are present in /etc/modules
            if grep -Fxq "vfio" /etc/modules && grep -Fxq "vfio_iommu_type1" /etc/modules && grep -Fxq "vfio_pci" /etc/modules && grep -Fxq "vfio_virqfd" /etc/modules; then
                echo -e "${YELLOW}[-]${NC} Kernel modules already present"
            else
                echo -e "${GREEN}[+]${NC} Enabling kernel modules"
                echo -e "vfio\nvfio_iommu_type1\nvfio_pci\nvfio_virqfd" >> /etc/modules
            fi

            # Check if /etc/modprobe.d/blacklist.conf exists
            if [ -f "/etc/modprobe.d/blacklist.conf" ]; then
                # Check if "blacklist nouveau" is present in /etc/modprobe.d/blacklist.conf
                if grep -q "blacklist nouveau" /etc/modprobe.d/blacklist.conf; then
                    echo -e "${YELLOW}[-]${NC} Nouveau already blacklisted"
                else
                    echo -e "${GREEN}[+]${NC} Blacklisting nouveau"
                    echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf
                fi
            else
                echo -e "${GREEN}[+]${NC} Blacklisting nouveau"
                echo "blacklist nouveau" >> /etc/modprobe.d/blacklist.conf
            fi

            #echo "updating initramfs"
            run_command "Updating initramfs" "info" "update-initramfs -u -k all"

            echo ""
            echo "Step 1 completed. Reboot your machine to resume the installation."
            echo ""
            echo "After reboot, run the script again to install the Nvidia driver."
            echo ""

            read -p "$(echo -e "${BLUE}[?]${NC} Reboot your machine now? (y/n): ")" reboot_choice
            if [ "$reboot_choice" = "y" ]; then
                echo "STEP=2" > "$VGPU_DIR/$CONFIG_FILE"
                echo "VGPU_SUPPORT=$VGPU_SUPPORT" >> "$VGPU_DIR/$CONFIG_FILE"
                echo "DRIVER_VERSION=$DRIVER_VERSION" >> "$VGPU_DIR/$CONFIG_FILE"
                reboot
            else
                echo "Exiting script. Remember to reboot your machine later."
                echo "STEP=2" > "$VGPU_DIR/$CONFIG_FILE"
                echo "VGPU_SUPPORT=$VGPU_SUPPORT" >> "$VGPU_DIR/$CONFIG_FILE"
                echo "DRIVER_VERSION=$DRIVER_VERSION" >> "$VGPU_DIR/$CONFIG_FILE"
                exit 0
            fi
            ;;

        3)           
            echo ""
            echo "Clean vGPU installation"
            echo ""

            # Function to prompt for user confirmation
            confirm_action() {
                local message="$1"
                echo -en "${GREEN}[?]${NC} $message (y/n): "
                read confirmation
                if [ "$confirmation" = "y" ] || [ "$confirmation" = "Y" ]; then
                    return 0  # Return success
                else
                    return 1  # Return failure
                fi
            }

            # Removing previous Nvidia driver
            if confirm_action "Do you want to remove the previous Nvidia driver?"; then
                # Check if NVIDIA driver is actually installed
                if command -v nvidia-uninstall >/dev/null 2>&1; then
                    echo -e "${YELLOW}[-]${NC} NVIDIA driver found, proceeding with removal..."
                    run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s" false
                elif [ -x "/usr/bin/nvidia-uninstall" ] || [ -x "/usr/local/bin/nvidia-uninstall" ]; then
                    echo -e "${YELLOW}[-]${NC} NVIDIA driver found, proceeding with removal..."
                    run_command "Removing previous Nvidia driver" "notification" "nvidia-uninstall -s" false
                else
                    echo -e "${YELLOW}[-]${NC} No NVIDIA driver installation found, skipping driver removal..."
                    write_log "SKIPPED: No NVIDIA driver found to remove"
                fi
            fi

            # Removing previous vgpu_unlock-rs
            if confirm_action "Do you want to remove vgpu_unlock-rs?"; then
                #echo "removing previous vgpu_unlock-rs"
                run_command "Removing previous vgpu_unlock-rs" "notification" "rm -rf /opt/vgpu_unlock-rs"
            fi

            # Removing vgpu-proxmox
            if confirm_action "Do you want to remove vgpu-proxmox?"; then
                #echo "removing vgpu-proxmox"
                run_command "Removing vgpu-proxmox" "notification" "rm -rf $VGPU_DIR/vgpu-proxmox"
            fi

            # Removing FastAPI-DLS
            if confirm_action "Do you want to remove vGPU licensing?"; then
                run_command "Removing FastAPI-DLS" "notification" "docker rm -f -v wvthoog-fastapi-dls"
            fi
            
            echo ""
            
            exit 0
            ;;
        4)  
            echo ""
            echo "This will download the Nvidia vGPU drivers"         
            echo ""
            echo -e "${GREEN}[+]${NC} Downloading Nvidia vGPU drivers"

            # Offer to download vGPU driver versions based on Proxmox version
            if [[ "$major_version" == "8" ]]; then
                echo -e "${GREEN}[+]${NC} You are running Proxmox version $version"
                echo -e "${GREEN}[+]${NC} Highly recommended that you download driver 18.x, 17.x or 16.x"
            elif [[ "$major_version" == "7" ]]; then
                echo -e "${GREEN}[+]${NC} You are running Proxmox version $version"
                echo -e "${GREEN}[+]${NC} Highly recommended that you download driver 16.x"
            fi

            echo ""
            echo "Select vGPU driver version:"
            echo ""
            echo "1: 19.2 (580.95.02) (No patch available)"
            echo "2: 19.1 (580.82.02) (No patch available)"
            echo "3: 19.0 (580.65.05)"
            echo "4: 18.4 (570.172.07)"
            echo "5: 18.3 (570.158.02)"
            echo "6: 18.2 (570.148.06)"
            echo "7: 18.1 (570.133.10) (Only Native supported GPU)"
            echo "8: 18.0 (570.124.03)"
            echo "9: 17.6 (550.163.02)"
            echo "10: 17.6 (550.163.10) - newer hotfix version"
            echo "11: 17.5 (550.144.02)"
            echo "12: 17.4 (550.127.06)"
            echo "13: 17.3 (550.90.05)"
            echo "14: 17.1 (550.54.16)"
            echo "15: 17.0 (550.54.10)"
            echo "16: 16.11 (535.261.04) (No patch available)"
            echo "17: 16.10 (535.247.02) (No patch available)"
            echo "18: 16.9 (535.230.02)"
            echo "19: 16.8 (535.216.01)"
            echo "20: 16.7 (535.183.04)"
            echo "21: 16.5 (535.161.05)"
            echo "22: 16.4 (535.161.05)"
            echo "23: 16.2 (535.129.03)"
            echo "24: 16.1 (535.104.06)"
            echo "25: 16.0 (535.54.06)"
            echo ""

            read -p "Enter your choice: " driver_choice

            # Validate the chosen filename against the compatibility map
            case $driver_choice in
                1) driver_filename="NVIDIA-Linux-x86_64-580.95.02-vgpu-kvm.run" ;;
                2) driver_filename="NVIDIA-Linux-x86_64-580.82.02-vgpu-kvm.run" ;;
                3) driver_filename="NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run" ;;
                4) driver_filename="NVIDIA-Linux-x86_64-570.172.07-vgpu-kvm.run" ;;
                5) driver_filename="NVIDIA-Linux-x86_64-570.158.02-vgpu-kvm.run" ;;
                6) driver_filename="NVIDIA-Linux-x86_64-570.148.06-vgpu-kvm.run" ;;
                7) driver_filename="NVIDIA-Linux-x86_64-570.133.10-vgpu-kvm.run" ;;
                8) driver_filename="NVIDIA-Linux-x86_64-570.124.03-vgpu-kvm.run" ;;
                9) driver_filename="NVIDIA-Linux-x86_64-550.163.02-vgpu-kvm.run" ;;
                10) driver_filename="NVIDIA-Linux-x86_64-550.163.10-vgpu-kvm.run" ;;
                11) driver_filename="NVIDIA-Linux-x86_64-550.144.02-vgpu-kvm.run" ;;
                12) driver_filename="NVIDIA-Linux-x86_64-550.127.06-vgpu-kvm.run" ;;
                13) driver_filename="NVIDIA-Linux-x86_64-550.90.05-vgpu-kvm.run" ;;
                14) driver_filename="NVIDIA-Linux-x86_64-550.54.16-vgpu-kvm.run" ;;
                15) driver_filename="NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run" ;;
                16) driver_filename="NVIDIA-Linux-x86_64-535.261.04-vgpu-kvm.run" ;;
                17) driver_filename="NVIDIA-Linux-x86_64-535.247.02-vgpu-kvm.run" ;;
                18) driver_filename="NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run" ;;
                19) driver_filename="NVIDIA-Linux-x86_64-535.216.01-vgpu-kvm.run" ;;
                20) driver_filename="NVIDIA-Linux-x86_64-535.183.04-vgpu-kvm.run" ;;
                21) driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ;;
                22) driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ;;
                23) driver_filename="NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run" ;;
                24) driver_filename="NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" ;;
                25) driver_filename="NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" ;;
                *) 
                    echo "Invalid choice. Please enter a valid option."
                    exit 1
                    ;;
            esac

            # Check if the selected filename is compatible
            if ! map_filename_to_version "$driver_filename"; then
                echo "Invalid choice. No patches available for your vGPU driver version."
                exit 1
            fi

            # Set the driver version based on the filename
            map_filename_to_version "$driver_filename"

            # Todo: add bittorrent download option
       
            # Set the driver URL
            echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"

            # Prompt user for download URL instead of using hardcoded links
            driver_url=$(prompt_for_driver_url "$driver_filename" "$driver_version")
            
            # Download driver from user-provided URL
            if ! download_driver_from_url "$driver_filename" "$driver_url" "$md5"; then
                echo -e "${RED}[!]${NC} Failed to download driver. Exiting."
                exit 1
            fi

            exit 0
            ;;
        5)  
            echo ""
            echo "This will setup a FastAPI-DLS Nvidia vGPU licensing server on this Proxmox server"         
            echo ""

            configure_fastapi_dls
            
            exit 0
            ;;
        6)  
            echo ""
            echo "This will help you create vGPU overrides following PoloLoco's guide"         
            echo ""
            
            create_vgpu_overrides
            
            exit 0
            ;;
        7)  
            echo ""
            echo "This will help you configure Pascal VM with ROM spoofing"         
            echo ""
            
            configure_pascal_vm
            
            exit 0
            ;;
        8)
            echo ""
            echo "Exiting script."
            exit 0
            ;;
        *)
            echo ""
            echo "Invalid choice. Please enter 1, 2, 3, 4, 5, 6, 7 or 8."
            echo ""
            ;;
        esac
    ;;
    2)
        # Step 2: Commands for the second reboot of a new installation or upgrade
        echo ""
        echo "You are currently at step ${STEP} of the installation process"
        echo ""
        echo "Proceeding with the installation"
        echo ""

        # Check if IOMMU / DMAR is enabled
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] Checking IOMMU status...${NC}"
        fi
        log_system_info "iommu"
        
        if dmesg | grep -e IOMMU | grep -q "Detected AMD IOMMU"; then
            echo -e "${GREEN}[+]${NC} AMD IOMMU Enabled"
            write_log "IOMMU: AMD IOMMU detected and enabled"
        elif dmesg | grep -e DMAR | grep -q "IOMMU enabled"; then
            echo -e "${GREEN}[+]${NC} Intel IOMMU Enabled"
            write_log "IOMMU: Intel IOMMU detected and enabled"
        else
            vendor_id=$(cat /proc/cpuinfo | grep vendor_id | awk 'NR==1{print $3}')
            write_log "IOMMU: Not detected. CPU vendor: $vendor_id"
            if [ "$vendor_id" = "AuthenticAMD" ]; then
                echo -e "${RED}[!]${NC} AMD IOMMU Disabled"
                echo -e ""
                echo -e "Please make sure you have IOMMU enabled in the BIOS"
                echo -e "and make sure that this line is present in /etc/default/grub"
                echo -e "GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt""
                echo ""
            elif [ "$vendor_id" = "GenuineIntel" ]; then
                echo -e "${RED}[!]${NC} Intel IOMMU Disabled"
                echo -e ""
                echo -e "Please make sure you have VT-d enabled in the BIOS"
                echo -e "and make sure that this line is present in /etc/default/grub"
                echo -e "GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt""
                echo ""
            else
                echo -e "${RED}[!]${NC} Unknown CPU architecture."
                echo ""
                exit 1
            fi   
            echo -n -e "${RED}[!]${NC} IOMMU is disabled. Do you want to continue anyway? (y/n): "
            read -r continue_choice
            if [ "$continue_choice" != "y" ]; then
                echo "Exiting script."
                write_log "EXIT: User chose to exit due to disabled IOMMU"
                exit 0
            fi
            write_log "WARNING: User chose to continue despite disabled IOMMU"
        fi

        if [ -n "$URL" ]; then
            echo -e "${GREEN}[+]${NC} Downloading vGPU host driver using curl"
            # Extract filename from URL
            driver_filename=$(extract_filename_from_url "$URL")
            
            # Download the file using curl
            run_command "Downloading $driver_filename" "info" "curl -s -o $driver_filename -L $URL"
            
            if [[ "$driver_filename" == *.zip ]]; then
                # Extract the zip file
                unzip -q "$driver_filename"
                # Look for .run file inside
                run_file=$(find . -name '*.run' -type f -print -quit)
                if [ -n "$run_file" ]; then
                    # Map filename to driver version and patch
                    if map_filename_to_version "$run_file"; then
                        driver_filename="$run_file"
                    else
                        echo -e "${RED}[!]${NC} Unrecognized filename inside the zip file. Exiting."
                        exit 1
                    fi
                else
                    echo -e "${RED}[!]${NC} No .run file found inside the zip. Exiting."
                    exit 1
                fi
            fi
            
            # Check if it's a .run file
            if [[ "$driver_filename" =~ \.run$ ]]; then
                # Map filename to driver version and patch
                if map_filename_to_version "$driver_filename"; then
                    echo -e "${GREEN}[+]${NC} Compatible filename found: $driver_filename"
                else
                    echo -e "${RED}[!]${NC} Unrecognized filename: $driver_filename. Exiting."
                    exit 1
                fi
            else
                echo -e "${RED}[!]${NC} Invalid file format. Only .zip and .run files are supported. Exiting."
                exit 1
            fi

        elif [ -n "$FILE" ]; then
            echo -e "${GREEN}[+]${NC} Using $FILE as vGPU host driver"
            # Map filename to driver version and patch
            if map_filename_to_version "$FILE"; then
                # If the filename is recognized
                driver_filename="$FILE"
                echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"
            else
                # If the filename is not recognized
                echo -e "${RED}[!]${NC} No patches available for your vGPU driver version"
                exit 1
            fi
        else

            contains_version() {
                local version="$1"
                if [[ "$DRIVER_VERSION" == *"$version"* ]]; then
                    return 0
                else
                    return 1
                fi
            }

            # Offer to download vGPU driver versions based on Proxmox version and supported driver
            if [[ "$major_version" == "8" ]]; then
                echo -e "${YELLOW}[-]${NC} You are running Proxmox version $version"
                if contains_version "18" && contains_version "17" && contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver versions 18.x, 17.x and 16.x"
                elif contains_version "17" && contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver versions 17.x and 16.x"
                elif contains_version "18"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver version 18.x"
                elif contains_version "17"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver version 17.x"
                elif contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver version 16.x"
                elif contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver version 16.x"
                fi
            elif [[ "$major_version" == "7" ]]; then
                echo -e "${YELLOW}[-]${NC} You are running Proxmox version $version"
                if contains_version "17" && contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver versions 17.0 and 16.x"
                elif contains_version "16"; then
                    echo -e "${YELLOW}[-]${NC} Your Nvidia GPU is supported by driver version 16.x"
                fi
            fi

            echo ""
            echo "Select vGPU driver version:"
            echo ""
            echo "1: 19.2 (580.95.02) (No patch available)"
            echo "2: 19.1 (580.82.02) (No patch available)"
            echo "3: 19.0 (580.65.05)"
            echo "4: 18.4 (570.172.07)"
            echo "5: 18.3 (570.158.02)"
            echo "6: 18.2 (570.148.06)"
            echo "7: 18.1 (570.133.10) (Only Native supported GPU)"
            echo "8: 18.0 (570.124.03)"
            echo "9: 17.6 (550.163.02)"
            echo "10: 17.6 (550.163.10) - newer hotfix version"
            echo "11: 17.5 (550.144.02)"
            echo "12: 17.4 (550.127.06)"
            echo "13: 17.3 (550.90.05)"
            echo "14: 17.1 (550.54.16)"
            echo "15: 17.0 (550.54.10)"
            echo "16: 16.11 (535.261.04) (No patch available)"
            echo "17: 16.10 (535.247.02) (No patch available)"
            echo "18: 16.9 (535.230.02)"
            echo "19: 16.8 (535.216.01)"
            echo "20: 16.7 (535.183.04)"
            echo "21: 16.5 (535.161.05)"
            echo "22: 16.4 (535.161.05)"
            echo "23: 16.2 (535.129.03)"
            echo "24: 16.1 (535.104.06)"
            echo "25: 16.0 (535.54.06)"
            echo ""

            read -p "Enter your choice: " driver_choice

            echo ""

            # Validate the chosen filename against the compatibility map
            case $driver_choice in
                1) driver_filename="NVIDIA-Linux-x86_64-580.95.02-vgpu-kvm.run" ;;
                2) driver_filename="NVIDIA-Linux-x86_64-580.82.02-vgpu-kvm.run" ;;
                3) driver_filename="NVIDIA-Linux-x86_64-580.65.05-vgpu-kvm.run" ;;
                4) driver_filename="NVIDIA-Linux-x86_64-570.172.07-vgpu-kvm.run" ;;
                5) driver_filename="NVIDIA-Linux-x86_64-570.158.02-vgpu-kvm.run" ;;
                6) driver_filename="NVIDIA-Linux-x86_64-570.148.06-vgpu-kvm.run" ;;
                7) driver_filename="NVIDIA-Linux-x86_64-570.133.10-vgpu-kvm.run" ;;
                8) driver_filename="NVIDIA-Linux-x86_64-570.124.03-vgpu-kvm.run" ;;
                9) driver_filename="NVIDIA-Linux-x86_64-550.163.02-vgpu-kvm.run" ;;
                10) driver_filename="NVIDIA-Linux-x86_64-550.163.10-vgpu-kvm.run" ;;
                11) driver_filename="NVIDIA-Linux-x86_64-550.144.02-vgpu-kvm.run" ;;
                12) driver_filename="NVIDIA-Linux-x86_64-550.127.06-vgpu-kvm.run" ;;
                13) driver_filename="NVIDIA-Linux-x86_64-550.90.05-vgpu-kvm.run" ;;
                14) driver_filename="NVIDIA-Linux-x86_64-550.54.16-vgpu-kvm.run" ;;
                15) driver_filename="NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run" ;;
                16) driver_filename="NVIDIA-Linux-x86_64-535.261.04-vgpu-kvm.run" ;;
                17) driver_filename="NVIDIA-Linux-x86_64-535.247.02-vgpu-kvm.run" ;;
                18) driver_filename="NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run" ;;
                19) driver_filename="NVIDIA-Linux-x86_64-535.216.01-vgpu-kvm.run" ;;
                20) driver_filename="NVIDIA-Linux-x86_64-535.183.04-vgpu-kvm.run" ;;
                21) driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ;;
                22) driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ;;
                23) driver_filename="NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run" ;;
                24) driver_filename="NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" ;;
                25) driver_filename="NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" ;;
                *) 
                    echo "Invalid choice. Please enter a valid option."
                    exit 1
                    ;;
            esac

            # Check if the selected filename is compatible
            if ! map_filename_to_version "$driver_filename"; then
                echo "Invalid choice. No patches available for your vGPU driver version."
                exit 1
            fi

            # Set the driver version based on the filename
            map_filename_to_version "$driver_filename"
            
            # Apply selective kernel pinning based on driver version
            # Early v16.x drivers (v16.0-v16.7) require kernel 6.5 due to compatibility issues
            # v16.8+ and v17.x/v18.x drivers support newer kernels and don't require pinning
            apply_kernel_pinning() {
                local driver_ver="$1"
                
                # Check if driver version is v16.0 to v16.7 (requires kernel pinning)
                if [[ "$driver_ver" =~ ^16\.[0-7]$ ]]; then
                    echo -e "${YELLOW}[-]${NC} Driver version $driver_ver (535.x early series) requires kernel 6.5 for stability"
                    echo -e "${YELLOW}[-]${NC} Applying kernel pinning to prevent compatibility issues..."
                    echo -e "${YELLOW}[-]${NC} Consider upgrading to v16.8+ for modern kernel support"
                    
                    # Kernel version comparison function
                    kernel_version_compare() {
                        ver1=$1
                        ver2=$2
                        printf '%s\n' "$ver1" "$ver2" | sort -V -r | head -n 1
                    }
                    
                    # Get the kernel list and filter for 6.5 kernels
                    kernel_list=$(proxmox-boot-tool kernel list | grep "6.5")
                    
                    # Check if any 6.5 kernels are available
                    if [[ -n "$kernel_list" ]]; then
                        # Extract the highest 6.5 kernel version
                        highest_version=""
                        while read -r line; do
                            kernel_version=$(echo "$line" | awk '{print $1}')
                            if [[ -z "$highest_version" ]]; then
                                highest_version="$kernel_version"
                            else
                                highest_version=$(kernel_version_compare "$highest_version" "$kernel_version")
                            fi
                        done <<< "$kernel_list"
                        
                        # Pin the highest 6.5 kernel
                        run_command "Pinning kernel to $highest_version (required for early v16.x drivers)" "info" "proxmox-boot-tool kernel pin $highest_version"
                        echo -e "${GREEN}[+]${NC} Kernel successfully pinned to $highest_version"
                    else
                        echo -e "${RED}[!]${NC} No 6.5 kernels found. Early v16.x drivers may not work with newer kernels."
                        echo -e "${YELLOW}[-]${NC} Consider installing proxmox-kernel-6.5 package or upgrading to v16.8+."
                    fi
                elif [[ "$driver_ver" =~ ^16\.[89]$ ]]; then
                    echo -e "${GREEN}[+]${NC} Driver version $driver_ver supports modern kernels (Ubuntu 24.04+ compatible)"
                    echo -e "${YELLOW}[-]${NC} No kernel pinning required - can use latest available kernel"
                    echo -e "${YELLOW}[-]${NC} NVIDIA official documentation confirms v16.8+ Ubuntu 24.04 support"
                else
                    echo -e "${GREEN}[+]${NC} Driver version $driver_ver (550.x/570.x/580.x series) supports flexible kernel versions"
                    echo -e "${YELLOW}[-]${NC} No kernel pinning required - can use latest available kernel"
                fi
            }
            
            # Apply kernel pinning based on selected driver version
            apply_kernel_pinning "$driver_version"
            
            # Set the driver URL if not provided
            if [ -z "$URL" ]; then
                # Note: Hardcoded URLs have been removed per PoloLoco guide requirements
                # Users must provide their own download URLs from official or trusted sources
                echo -e "${YELLOW}[-]${NC} Following PoloLoco vGPU guide recommendations for driver sources"
                echo -e "${YELLOW}[-]${NC} Driver URLs must be provided by user from official sources"
            fi

            echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"

            # Prompt user for download URL instead of using hardcoded links
            driver_url=$(prompt_for_driver_url "$driver_filename" "$driver_version")
            
            # Download driver from user-provided URL
            if ! download_driver_from_url "$driver_filename" "$driver_url" "$md5"; then
                echo -e "${RED}[!]${NC} Failed to download driver. Exiting."
                exit 1
            fi
        fi

        # Make driver executable
        chmod +x $driver_filename
        write_log "Driver file made executable: $driver_filename"
        
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] Driver file permissions: $(ls -la $driver_filename)${NC}"
            echo -e "${GRAY}[DEBUG] Driver file size: $(du -h $driver_filename | cut -f1)${NC}"
        fi

        # Verify kernel headers are available for driver compilation
        verify_kernel_headers() {
            local current_kernel=$(uname -r)
            local kernel_build_dir="/lib/modules/$current_kernel/build"
            local kernel_source_dir="/lib/modules/$current_kernel/source"
            
            echo -e "${GREEN}[+]${NC} Verifying kernel headers for running kernel: $current_kernel"
            
            # Check if kernel build directory exists
            if [ ! -d "$kernel_build_dir" ]; then
                echo -e "${YELLOW}[-]${NC} Kernel build directory not found: $kernel_build_dir"
                echo -e "${YELLOW}[-]${NC} Attempting to install headers for current kernel..."
                
                # Try different header package patterns
                local kernel_base=$(echo $current_kernel | cut -d'-' -f1,2)
                if apt install -y "proxmox-headers-$kernel_base" 2>/dev/null; then
                    echo -e "${GREEN}[+]${NC} Successfully installed proxmox-headers-$kernel_base"
                elif apt install -y "pve-headers-$current_kernel" 2>/dev/null; then
                    echo -e "${GREEN}[+]${NC} Successfully installed pve-headers-$current_kernel"
                elif apt install -y pve-headers 2>/dev/null; then
                    echo -e "${GREEN}[+]${NC} Successfully installed latest pve-headers"
                else
                    echo -e "${RED}[!]${NC} Failed to install kernel headers automatically"
                    echo -e "${YELLOW}[-]${NC} You may need to install kernel headers manually:"
                    echo -e "${YELLOW}[-]${NC} apt install proxmox-headers-$kernel_base"
                    echo -e "${YELLOW}[-]${NC} or apt install pve-headers-$current_kernel"
                    return 1
                fi
            else
                echo -e "${GREEN}[+]${NC} Kernel build directory found: $kernel_build_dir"
            fi
            
            # Verify the build directory is accessible
            if [ -d "$kernel_build_dir" ] && [ -r "$kernel_build_dir/Makefile" ]; then
                echo -e "${GREEN}[+]${NC} Kernel headers verification successful"
                return 0
            else
                echo -e "${RED}[!]${NC} Kernel headers verification failed"
                echo -e "${YELLOW}[-]${NC} Build directory exists but Makefile not found or not readable"
                return 1
            fi
        }
        
        # Verify headers before driver installation
        if ! verify_kernel_headers; then
            echo -e "${RED}[!]${NC} Kernel headers verification failed. Driver installation may fail."
            read -p "$(echo -e "${BLUE}[?]${NC} Continue anyway? (y/n): ")" continue_without_headers
            if [ "$continue_without_headers" != "y" ]; then
                echo "Exiting script. Please install proper kernel headers and try again."
                exit 1
            fi
        fi

        # Special logic for Pascal GPU driver patching based on PoloLoco's guide
        # Pascal GPUs with v16.x drivers (natively supported) don't require patching
        # Pascal GPUs with v17.x+ drivers ALWAYS require patching regardless of native support
        original_vgpu_support="$VGPU_SUPPORT"
        if detect_pascal_gpu; then
            if [[ "$driver_version" =~ ^17\.|^18\.|^19\. ]]; then
                echo ""
                echo -e "${GREEN}[+]${NC} ========== PASCAL GPU + v$driver_version DRIVER DETECTED =========="
                echo -e "${YELLOW}[-]${NC} Following PoloLoco's guide for Pascal GPU vGPU configuration:"
                echo -e "${YELLOW}[-]${NC}   Step 1: Download vgpu-proxmox patches from GitLab"
                echo -e "${YELLOW}[-]${NC}   Step 2: Patch the driver BEFORE installation"
                echo -e "${YELLOW}[-]${NC}   Step 3: Install the PATCHED driver"
                echo -e "${YELLOW}[-]${NC}   Step 4: Overwrite vgpuConfig.xml with v16.4 driver's XML"
                echo -e "${GREEN}[+]${NC} ======================================================="
                echo ""
                VGPU_SUPPORT="Yes"  # Override to force patching
                write_log "Pascal GPU + v$driver_version: Overriding VGPU_SUPPORT from '$original_vgpu_support' to 'Yes' for required patching"
            elif [[ "$driver_version" =~ ^16\. ]]; then
                echo -e "${YELLOW}[-]${NC} Pascal GPU with v$driver_version driver detected: Using native support status ($original_vgpu_support)"
                echo -e "${YELLOW}[-]${NC} Pascal cards with v16.x drivers follow normal vGPU support rules"
                write_log "Pascal GPU + v$driver_version: Keeping original VGPU_SUPPORT '$original_vgpu_support' for v16.x driver"
            fi
        fi

        # Patch and install the driver only if vGPU is not native
        if [ "$VGPU_SUPPORT" = "Yes" ]; then
            write_log "Installing vGPU driver with patching for non-native vGPU support"
            
            # Check if patch is marked as not available
            if [ "$driver_patch" = "NO_PATCH" ]; then
                echo -e "${YELLOW}[-]${NC} No patch available for driver version $driver_version (as of October 2025)"
                echo -e "${YELLOW}[-]${NC} This driver version requires natively supported GPU hardware"
                echo -e "${YELLOW}[-]${NC} Continuing with original driver installation..."
                write_log "WARNING: No patch available for driver version $driver_version"
                write_log "Continuing with original driver installation"
                
                # Run the regular driver installer for non-native GPU without patch
                echo -e "${YELLOW}[-]${NC} Installing original vGPU driver (this may take several minutes)..."
                log_system_info "kernel"  # Log kernel state before installation
                run_command "Installing original driver" "info" "./$driver_filename --dkms -m=kernel -s" true true
            else
                # Ensure vgpu-proxmox patches are available - download if missing
                # This is critical for Pascal GPUs with v17.x+ drivers per PoloLoco's guide
                if [ ! -d "$VGPU_DIR/vgpu-proxmox" ]; then
                    echo -e "${GREEN}[+]${NC} Step 1: Downloading vgpu-proxmox patches from GitLab..."
                    echo -e "${YELLOW}[-]${NC} vgpu-proxmox patches not found at $VGPU_DIR/vgpu-proxmox"
                    write_log "vgpu-proxmox directory missing in Step 2 - downloading patches"
                    
                    # Download the patches repository
                    if git clone https://gitlab.com/polloloco/vgpu-proxmox.git "$VGPU_DIR/vgpu-proxmox" 2>&1; then
                        echo -e "${GREEN}[+]${NC} Successfully downloaded vgpu-proxmox patches from https://gitlab.com/polloloco/vgpu-proxmox.git"
                        write_log "Successfully cloned vgpu-proxmox from https://gitlab.com/polloloco/vgpu-proxmox.git"
                        
                        # List available patches
                        if [ "$VERBOSE" = "true" ]; then
                            echo -e "${GRAY}[DEBUG] Available patches in vgpu-proxmox:${NC}"
                            ls -la "$VGPU_DIR/vgpu-proxmox/"*.patch 2>/dev/null | head -10 | sed 's/^/  /'
                        fi
                    else
                        echo -e "${RED}[!]${NC} Failed to download vgpu-proxmox patches"
                        echo -e "${RED}[!]${NC} Please check your network connection or manually clone:"
                        echo -e "${RED}[!]${NC}   git clone https://gitlab.com/polloloco/vgpu-proxmox.git $VGPU_DIR/vgpu-proxmox"
                        write_log "ERROR: Failed to clone vgpu-proxmox from GitLab"
                    fi
                else
                    echo -e "${GREEN}[+]${NC} Step 1: vgpu-proxmox patches found at $VGPU_DIR/vgpu-proxmox"
                    write_log "vgpu-proxmox directory exists at $VGPU_DIR/vgpu-proxmox"
                fi
                
                # Verify the vgpu-proxmox directory now exists
                if [ ! -d "$VGPU_DIR/vgpu-proxmox" ]; then
                    echo -e "${RED}[!]${NC} vgpu-proxmox directory still not available after download attempt"
                    echo -e "${RED}[!]${NC} Cannot apply PoloLoco patches without the vgpu-proxmox repository"
                    echo -e "${YELLOW}[-]${NC} Continuing with original driver installation (patching skipped)..."
                    write_log "ERROR: vgpu-proxmox still missing - continuing with unpatched driver"
                    
                    # Run the regular driver installer without patching
                    echo -e "${YELLOW}[-]${NC} Installing original vGPU driver (this may take several minutes)..."
                    log_system_info "kernel"
                    run_command "Installing original driver" "info" "./$driver_filename --dkms -m=kernel -s" true true
                # Check if patch file exists
                elif [ -f "$VGPU_DIR/vgpu-proxmox/$driver_patch" ]; then
                    echo -e "${GREEN}[+]${NC} Step 2: Applying PoloLoco's vGPU patch to driver BEFORE installation"
                    echo -e "${GREEN}[+]${NC} Patch file: $VGPU_DIR/vgpu-proxmox/$driver_patch"
                    write_log "Patch file found: $VGPU_DIR/vgpu-proxmox/$driver_patch"
                    
                    # Add custom to original filename
                    custom_filename="${driver_filename%.run}-custom.run"

                    # Check if $custom_filename exists
                    if [ -e "$custom_filename" ]; then
                        mv "$custom_filename" "$custom_filename.bak"
                        echo -e "${YELLOW}[-]${NC} Moved $custom_filename to $custom_filename.bak"
                        write_log "Moved existing custom driver: $custom_filename to backup"
                    fi

                    if [ "$VERBOSE" = "true" ]; then
                        echo -e "${GRAY}[DEBUG] Patch file: $VGPU_DIR/vgpu-proxmox/$driver_patch${NC}"
                        echo -e "${GRAY}[DEBUG] Applying patch to create: $custom_filename${NC}"
                    fi
                    
                    # Apply the patch using PoloLoco's method - this creates the -custom.run file
                    echo -e "${GREEN}[+]${NC} Executing: ./$driver_filename --apply-patch $VGPU_DIR/vgpu-proxmox/$driver_patch"
                    run_command "Patching driver" "info" "./$driver_filename --apply-patch $VGPU_DIR/vgpu-proxmox/$driver_patch" true true
                    
                    if [ -f "$custom_filename" ]; then
                        echo -e "${GREEN}[+]${NC} Patched driver created successfully: $custom_filename"
                        write_log "Patched driver created: $custom_filename"
                        
                        if [ "$VERBOSE" = "true" ]; then
                            echo -e "${GRAY}[DEBUG] Patched driver size: $(du -h $custom_filename | cut -f1)${NC}"
                        fi
                        
                        # Step 3: Install the PATCHED driver
                        echo -e "${GREEN}[+]${NC} Step 3: Installing the PATCHED vGPU driver (this may take several minutes)..."
                        log_system_info "kernel"  # Log kernel state before installation
                        run_command "Installing patched driver" "info" "./$custom_filename --dkms -m=kernel -s" true true
                    else
                        echo -e "${RED}[!]${NC} Failed to create patched driver"
                        write_log "ERROR: Patched driver not created"
                        exit 1
                    fi
                else
                    # No patch file available - continue with original driver
                    echo -e "${YELLOW}[-]${NC} No patch file found for this driver version: $driver_patch"
                    echo -e "${YELLOW}[-]${NC} This driver may not require patching or patch is not available"
                    echo -e "${YELLOW}[-]${NC} Continuing with original driver installation..."
                    write_log "WARNING: No patch file found: $VGPU_DIR/vgpu-proxmox/$driver_patch"
                    write_log "Continuing with original driver installation"
                    
                    # Run the regular driver installer for non-native GPU without patch
                    echo -e "${YELLOW}[-]${NC} Installing original vGPU driver (this may take several minutes)..."
                    log_system_info "kernel"  # Log kernel state before installation
                    run_command "Installing original driver" "info" "./$driver_filename --dkms -m=kernel -s" true true
                fi
            fi
            
        elif [ "$VGPU_SUPPORT" = "Native" ] || [ "$VGPU_SUPPORT" = "Unknown" ]; then
            write_log "Installing native vGPU driver (no patching required)"
            
            # Run the regular driver installer
            echo -e "${YELLOW}[-]${NC} Installing native vGPU driver (this may take several minutes)..."
            log_system_info "kernel"  # Log kernel state before installation
            run_command "Installing native driver" "info" "./$driver_filename --dkms -m=kernel -s" true true
            
        else
            echo -e "${RED}[!]${NC} Unknown or unsupported GPU: $VGPU_SUPPORT"
            write_log "ERROR: Unknown GPU support type: $VGPU_SUPPORT"
            echo ""
            echo "Exiting script."
            echo ""
            exit 1
        fi

        echo -e "${GREEN}[+]${NC} Driver installed successfully."
        write_log "Driver installation completed successfully"
        
        # Restore original VGPU_SUPPORT value if it was overridden for Pascal GPU patching
        if [ -n "$original_vgpu_support" ] && [ "$original_vgpu_support" != "$VGPU_SUPPORT" ]; then
            echo -e "${YELLOW}[-]${NC} Restoring original vGPU support status: $original_vgpu_support"
            write_log "Restoring VGPU_SUPPORT from '$VGPU_SUPPORT' back to original '$original_vgpu_support'"
            VGPU_SUPPORT="$original_vgpu_support"
        fi
        
        # Log post-installation system state
        log_system_info "kernel"

        echo -e "${GREEN}[+]${NC} Nvidia driver version: $driver_filename"
        write_log "Driver verification starting"

        # Wait for services to fully initialize
        echo -e "${YELLOW}[-]${NC} Waiting for NVIDIA services to initialize..."
        sleep 5

        nvidia_smi_output=$(nvidia-smi vgpu 2>&1)
        write_log "nvidia-smi vgpu output: $nvidia_smi_output"

        # Extract version from FILE
        FILE_VERSION=$(echo "$driver_filename" | grep -oP '\d+\.\d+\.\d+')
        write_log "Expected driver version: $FILE_VERSION"

        if [[ "$nvidia_smi_output" == *"NVIDIA-SMI has failed because it couldn't communicate with the NVIDIA driver."* ]] || [[ "$nvidia_smi_output" == *"No supported devices in vGPU mode"* ]]; then
            echo -e "${RED}[!]${NC} Nvidia driver not properly loaded"
            write_log "ERROR: NVIDIA driver not properly loaded"
            
            if [ "$VERBOSE" = "true" ]; then
                echo -e "${GRAY}[DEBUG] Full nvidia-smi vgpu output:${NC}"
                echo "$nvidia_smi_output" | sed 's/^/  /'
                echo -e "${GRAY}[DEBUG] Checking for loaded NVIDIA modules:${NC}"
                lsmod | grep nvidia | sed 's/^/  /'
                echo -e "${GRAY}[DEBUG] Checking dmesg for NVIDIA messages:${NC}"
                dmesg | grep -i nvidia | tail -10 | sed 's/^/  /'
            fi
            
        elif [[ "$nvidia_smi_output" == *"Driver Version: $FILE_VERSION"* ]]; then
            echo -e "${GREEN}[+]${NC} Nvidia driver properly loaded, version matches $FILE_VERSION"
            write_log "SUCCESS: Driver properly loaded with matching version"
        else
            echo -e "${GREEN}[+]${NC} Nvidia driver properly loaded"
            write_log "SUCCESS: Driver appears to be loaded (version check inconclusive)"
            
            if [ "$VERBOSE" = "true" ]; then
                echo -e "${GRAY}[DEBUG] nvidia-smi vgpu output:${NC}"
                echo "$nvidia_smi_output" | head -10 | sed 's/^/  /'
            fi
        fi
        
        # Log final driver status
        log_system_info "driver"

        # Enable NVIDIA services but do not start them
        echo -e "${YELLOW}[-]${NC} Enabling NVIDIA vGPU services (will start after reboot)..."
        write_log "Enabling NVIDIA vGPU services for startup"
        
        run_command "Enable nvidia-vgpud.service" "info" "systemctl enable nvidia-vgpud.service" false
        run_command "Enable nvidia-vgpu-mgr.service" "info" "systemctl enable nvidia-vgpu-mgr.service" false
        
        echo -e "${YELLOW}[-]${NC} ${RED}REBOOT REQUIRED:${NC} NVIDIA services enabled but system must be rebooted"
        echo -e "${YELLOW}[-]${NC} Service restarts do not work properly - full system reboot is required"
        
        # Log service status for diagnostics
        log_system_info "services"
        
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] Checking service status (services not started yet - reboot required)...${NC}"
            echo -e "${GRAY}[DEBUG] nvidia-vgpud.service: enabled but not started${NC}"
            echo -e "${GRAY}[DEBUG] nvidia-vgpu-mgr.service: enabled but not started${NC}"
        fi

        # Apply Pascal vGPU configuration fix following PoloLoco's guide
        apply_pascal_vgpu_fix "$driver_version"

        # Check DRIVER_VERSION against specific driver filenames
        if [ "$driver_filename" == "NVIDIA-Linux-x86_64-570.133.10-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 570.133.10"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU18.1/NVIDIA-Linux-x86_64-570.133.20-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU18.1/572.83_grid_win10_win11_server2022_dch_64bit_international.exe"
            # Strong warning for Pascal GPU with v18.x driver
            if detect_pascal_gpu; then
                echo ""
                echo -e "${RED}[!!!] WARNING: PASCAL GPU WITH v18.x DRIVER [!!!]${NC}"
                echo -e "${RED}[!]${NC} v18.x drivers are NOT RECOMMENDED for Pascal cards per PoloLoco's PSA"
                echo -e "${RED}[!]${NC} Consider using v16.9 for optimal Pascal compatibility"
                echo -e "${YELLOW}[-]${NC} v18.x requires complex workarounds and may have stability issues"
                echo -e "${GREEN}[+]${NC} Pascal GPU detected: vGPU configuration will be applied following PoloLoco's guide"
                echo ""
            fi
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-570.124.03-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 570.124.03"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU18.0/NVIDIA-Linux-x86_64-570.124.06-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU18.0/572.60_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
            # Strong warning for Pascal GPU with v18.x driver
            if detect_pascal_gpu; then
                echo ""
                echo -e "${RED}[!!!] WARNING: PASCAL GPU WITH v18.x DRIVER [!!!]${NC}"
                echo -e "${RED}[!]${NC} v18.x drivers are NOT RECOMMENDED for Pascal cards per PoloLoco's PSA"
                echo -e "${RED}[!]${NC} Consider using v16.9 for optimal Pascal compatibility"
                echo -e "${YELLOW}[-]${NC} v18.x requires complex workarounds and may have stability issues"
                echo -e "${GREEN}[+]${NC} Pascal GPU detected: vGPU configuration will be applied following PoloLoco's guide"
                echo ""
            fi
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-550.163.02-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.163.02"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.6/NVIDIA-Linux-x86_64-550.163.01-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.6/553.74_grid_win10_win11_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-550.163.10-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.163.10 (hotfix)"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.6/NVIDIA-Linux-x86_64-550.163.01-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.6/553.74_grid_win10_win11_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-550.144.02-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.144.02"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.5/NVIDIA-Linux-x86_64-550.144.03-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.5/553.62_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-550.127.06-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.127.06"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.4/NVIDIA-Linux-x86_64-550.127.05-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.4/553.24_grid_win10_win11_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-550.90.05-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.90.05"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.3/NVIDIA-Linux-x86_64-550.90.07-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.3/552.74_grid_win10_win11_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-550.54.16-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.54.16"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.1/NVIDIA-Linux-x86_64-550.54.15-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.1/551.78_grid_win10_win11_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.54.10"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.0/NVIDIA-Linux-x86_64-550.54.14-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU17.0/551.61_grid_win10_win11_server2022_dch_64bit_international.exe"
            # Check for Pascal GPU and inform about the fix
            if detect_pascal_gpu; then
                echo ""
                echo -e "${YELLOW}[!] PASCAL GPU WITH v17.x DRIVER DETECTED [!]${NC}"
                echo -e "${YELLOW}[-]${NC} v17.x drivers require v16.4 vgpuConfig.xml workaround for Pascal cards"
                echo -e "${YELLOW}[-]${NC} Consider using v16.9 for better Pascal compatibility (see PSA above)"
                echo -e "${GREEN}[+]${NC} Pascal GPU detected: vGPU configuration has been applied following PoloLoco's guide"
                echo ""
            fi
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.230.02"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.9/NVIDIA-Linux-x86_64-535.230.02-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.9/539.19_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
            # Check for Pascal GPU and inform about the excellent choice
            if detect_pascal_gpu; then
                echo ""
                echo -e "${GREEN}[+++] EXCELLENT CHOICE FOR PASCAL GPUS! [+++]${NC}"
                echo -e "${GREEN}[+]${NC} v16.9 is the RECOMMENDED driver for Pascal cards per PoloLoco's PSA"
                echo -e "${GREEN}[+]${NC} This driver provides optimal stability and compatibility for Pascal architecture"
                echo -e "${GREEN}[+]${NC} Pascal GPU detected: vGPU configuration has been applied following PoloLoco's guide"
                echo ""
            fi
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.216.01-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.216.01"
            echo -e "${YELLOW}[-]${NC} Linux: 	https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.8/NVIDIA-Linux-x86_64-535.216.01-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.8/538.95_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.183.04-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.183.04"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.7/NVIDIA-Linux-x86_64-535.183.06-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.7/538.78_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.161.05"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.4/NVIDIA-Linux-x86_64-535.161.07-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.4/538.33_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.129.03"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.2/NVIDIA-Linux-x86_64-535.129.03-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.2/537.70_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.104.06"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.1/NVIDIA-Linux-x86_64-535.104.05-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.1/537.13_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
            # Check for Pascal GPU and inform about the fix
            if detect_pascal_gpu; then
                echo -e "${GREEN}[+]${NC} Pascal GPU detected: vGPU configuration has been applied following PoloLoco's guide"
            fi
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.54.06"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.0/NVIDIA-Linux-x86_64-535.54.03-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.0/536.25_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        else
            echo -e "${RED}[!]${NC} Unknown driver version: $driver_filename"
        fi

        echo ""
        echo -e "${GREEN}[+]${NC} Step 2 completed and installation process is now finished."
        echo -e "${YELLOW}[-]${NC} ${RED}IMPORTANT: REBOOT REQUIRED${NC}"
        echo -e "${YELLOW}[-]${NC} You must reboot the system for all changes to take effect"
        echo -e "${YELLOW}[-]${NC} Service restarts do not work properly - only a full reboot will enable vGPU functionality"
        write_log "Installation step 2 completed successfully - reboot required"
        echo ""
        
        # Pascal GPU specific messaging
        if detect_pascal_gpu; then
            echo -e "${GREEN}[+]${NC} Pascal GPU vGPU configuration has been applied following PoloLoco's guide"
            echo -e "${YELLOW}[-]${NC} After reboot, your Pascal GPU should show proper vGPU profiles"
            echo ""
        fi
        
        echo -e "${YELLOW}[-]${NC} After reboot:"
        echo "• List all available mdevs by typing: mdevctl types and choose the one that fits your needs and VRAM capabilities"
        echo "• Login to your Proxmox server over http/https. Click the VM and go to Hardware."
        echo "• Under Add choose PCI Device and assign the desired mdev type to your VM"
        echo ""
        
        # Show final diagnostics
        echo -e "${YELLOW}[-]${NC} Installation diagnostics logged to: $VGPU_DIR/$LOG_FILE"
        if [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] Final system state:${NC}"
            echo -e "${GRAY}[DEBUG] - NVIDIA services enabled but not started (reboot required)${NC}"
            echo -e "${GRAY}[DEBUG] - Driver status logged${NC}"
            echo -e "${GRAY}[DEBUG] - vGPU types will be available after reboot${NC}"
            
            echo -e "${GRAY}[DEBUG] Current state (before reboot):${NC}"
            echo -e "${GRAY}[DEBUG] - nvidia-vgpud.service: enabled but inactive (normal)${NC}"
            echo -e "${GRAY}[DEBUG] - nvidia-vgpu-mgr.service: enabled but inactive (normal)${NC}"
            echo -e "${GRAY}[DEBUG] - mdevctl types will show results after reboot${NC}"
        fi
        
        echo "Removing the config.txt file."
        write_log "Removing configuration file"
        echo ""

        rm -f "$VGPU_DIR/$CONFIG_FILE" 
        
        # Final log entry
        write_log "Installation completed - configuration file removed" 

        # Option to license the vGPU
        configure_fastapi_dls
        ;;
    *)
        echo "Invalid installation step. Please check the script."
        exit 1
        ;;
esac

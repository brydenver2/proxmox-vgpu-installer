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
SCRIPT_VERSION=1.2
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
        
        # Test if file contains Tesla P4 device ID
        if grep -q "1BB3\|1bb3" "$config_file" 2>/dev/null; then
            echo -e "${GREEN}[+]${NC} Configuration contains Tesla P4 device ID (1BB3)"
        else
            echo -e "${YELLOW}[-]${NC} Configuration may not contain Tesla P4 device ID"
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

# Function to detect Tesla P4 GPUs
detect_tesla_p4() {
    # Check if system has Tesla P4 GPU (device ID 1bb3)
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
        
        for device_id in $gpu_device_ids; do
            if [ "$device_id" = "1bb3" ]; then
                if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ]; then
                    echo -e "${GRAY}[DEBUG] Tesla P4 detected (device ID: 1bb3)${NC}"
                fi
                return 0  # Tesla P4 found
            fi
        done
        
        if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] No Tesla P4 found (looking for device ID 1bb3)${NC}"
        fi
    else
        if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] No NVIDIA GPUs found${NC}"
        fi
    fi
    return 1  # Tesla P4 not found
}

# Function to display Tesla P4 troubleshooting guide
show_tesla_p4_troubleshooting() {
    echo ""
    echo -e "${BLUE}[INFO]${NC} Tesla P4 Troubleshooting Guide"
    echo -e "${BLUE}======================================${NC}"
    echo ""
    echo -e "${YELLOW}Common Issues and Solutions:${NC}"
    echo ""
    echo -e "${YELLOW}1. Tesla P4 shows P40 profiles or no profiles:${NC}"
    echo -e "   • This is caused by incorrect vgpuConfig.xml"
    echo -e "   • The fix downloads driver 16.4 which has the correct config"
    echo -e "   • Solution: Run this installer which applies the fix automatically"
    echo ""
    echo -e "${YELLOW}2. Download fails with 'megadl not available':${NC}"
    echo -e "   • Install megatools: apt install megatools"
    echo -e "   • Or manually download driver 16.4"
    echo ""
    echo -e "${YELLOW}3. Download fails with network errors:${NC}"
    echo -e "   • Check connectivity: ping -c 3 google.com"
    echo -e "   • Check firewall settings"
    echo -e "   • Try downloading from different network"
    echo ""
    echo -e "${YELLOW}4. vGPU types still not visible after fix:${NC}"
    echo -e "   • Wait for system reboot and try: mdevctl types"
    echo -e "   • Check service status: systemctl status nvidia-vgpu-mgr.service"
    echo -e "   • Reboot system if needed"
    echo ""
    echo -e "${YELLOW}5. Tesla P4 + v17.0 driver installation failures:${NC}"
    echo -e "   • Tesla P4 cards need v16 driver installed first, then upgrade to v17"
    echo -e "   • This installer automatically handles this workflow when you select v17.0"
    echo -e "   • If kernel module compilation fails, check kernel headers are installed"
    echo -e "   • Use 'apt install proxmox-headers-\$(uname -r | cut -d'-' -f1,2)'"
    echo ""
    echo -e "${YELLOW}6. How to verify Tesla P4 profiles are working:${NC}"
    echo -e "   • Run: mdevctl types | grep -i 'p4-'"
    echo -e "   • Should show profiles like 'GRID P4-1Q', 'GRID P4-2Q', etc."
    echo -e "   • Should NOT show 'GRID P40-' profiles"
    echo -e "   • If you see P40 profiles, the fix needs to be applied"
    echo ""
    echo -e "${YELLOW}7. Manual fix steps if automatic fix fails:${NC}"
    echo -e "   • Download: wget -O NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run [URL]"
    echo -e "   • Extract: ./NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run -x"
    echo -e "   • Copy: cp NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm/vgpuConfig.xml /usr/share/nvidia/vgpu/"
    echo -e "   • Restart: Reboot system"
    echo ""
    echo -e "${YELLOW}Expected Tesla P4 vGPU Types:${NC}"
    echo -e "   • nvidia-222 (GRID P4-1Q) - 1GB VRAM, 4 instances"
    echo -e "   • nvidia-223 (GRID P4-2Q) - 2GB VRAM, 2 instances"
    echo -e "   • nvidia-224 (GRID P4-4Q) - 4GB VRAM, 1 instance"
    echo -e "   • nvidia-252 (GRID P4-1A) - 1GB VRAM, VirtualApps"
    echo -e "   • nvidia-253 (GRID P4-2A) - 2GB VRAM, VirtualApps"
    echo ""
    echo -e "${YELLOW}Additional Resources:${NC}"
    echo -e "   • Documentation: $VGPU_DIR/TESLA_P4_FIX.md"
    echo -e "   • Forum discussion: https://forum.proxmox.com/threads/vgpu-tesla-p4-wrong-mdevctl-gpu.143247/"
    echo -e "   • vGPU Unlocking Discord: https://discord.gg/5rQsSV3Byq"
    echo ""
}

# Function to check network connectivity
check_network_connectivity() {
    echo -e "${YELLOW}[-]${NC} Checking network connectivity for Tesla P4 fix..."
    
    # Test DNS resolution and basic connectivity
    if ! timeout 10 ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${YELLOW}[-]${NC} Network connectivity test failed"
        return 1
    fi
    
    # Test HTTPS connectivity
    if ! timeout 10 curl -s -I https://google.com >/dev/null 2>&1; then
        echo -e "${YELLOW}[-]${NC} HTTPS connectivity test failed"
        return 1
    fi
    
    echo -e "${GREEN}[+]${NC} Network connectivity verified"
    return 0
}



# Function to download and extract vgpuConfig.xml from driver 16.4
download_tesla_p4_config() {
    # Array of alternative download URLs for NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run
    local p4_driver_urls=(
        "https://mega.nz/file/RvsyyBaB#7fe_caaJkBHYC6rgFKtiZdZKkAvp7GNjCSa8ufzkG20"
        "https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.4/NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run"
        "https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.4/NVIDIA-Linux-x86_64-535.161.07-vgpu-kvm.run"
    )
    local p4_driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run"
    local p4_driver_md5="bad6e09aeb58942750479f091bb9c4b6"
    
    echo -e "${GREEN}[+]${NC} Tesla P4 detected - downloading driver 16.4 for vgpuConfig.xml"
    
    if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ]; then
        echo -e "${GRAY}[DEBUG] Original directory: $VGPU_DIR${NC}"
        echo -e "${GRAY}[DEBUG] Current directory: $(pwd)${NC}"
    fi
    
    # Create temporary directory for Tesla P4 fix
    local temp_dir="/tmp/tesla_p4_fix"
    mkdir -p "$temp_dir"
    cd "$temp_dir" || {
        echo -e "${RED}[!]${NC} Failed to create temporary directory for Tesla P4 fix"
        return 1
    }
    
    # Download 16.4 driver if not present
    if [ ! -f "$p4_driver_filename" ]; then
        echo -e "${YELLOW}[-]${NC} Downloading Tesla P4 configuration driver: $p4_driver_filename"
        
        # Check network connectivity first
        if ! check_network_connectivity; then
            echo -e "${RED}[!]${NC} Network connectivity check failed"
            echo -e "${YELLOW}[-]${NC} Please check your internet connection and try again"
            cd "$VGPU_DIR" || {
                echo -e "${YELLOW}[-]${NC} Warning: Could not return to original directory: $VGPU_DIR"
            }
            return 1
        fi
        
        # Try multiple download methods with retry logic
        local download_success=false
        local max_retries=3
        local retry_count=0
        local url_index=0
        local total_urls=${#p4_driver_urls[@]}
        
        # Try each URL with retries
        while [ $url_index -lt $total_urls ] && [ "$download_success" = false ]; do
            local current_url="${p4_driver_urls[$url_index]}"
            retry_count=0
            
            # Special handling for Mega.nz URLs (requires megadl)
            if [[ "$current_url" == *"mega.nz"* ]]; then
                if command -v megadl >/dev/null 2>&1; then
                    echo -e "${YELLOW}[-]${NC} Attempting download using megadl from Mega.nz (method $((url_index+1))/$total_urls)"
                    while [ $retry_count -lt $max_retries ] && [ "$download_success" = false ]; do
                        retry_count=$((retry_count + 1))
                        echo -e "${YELLOW}[-]${NC} Download attempt $retry_count of $max_retries..."
                        
                        if timeout 300 megadl "$current_url" 2>&1 | grep -v "ERROR\|failed" >/dev/null; then
                            if [ -f "$p4_driver_filename" ] && [ -s "$p4_driver_filename" ]; then
                                download_success=true
                                echo -e "${GREEN}[+]${NC} Successfully downloaded using megadl"
                                break
                            fi
                        fi
                        
                        if [ $retry_count -lt $max_retries ]; then
                            echo -e "${YELLOW}[-]${NC} Download failed, retrying in 5 seconds..."
                            sleep 5
                        fi
                    done
                else
                    echo -e "${YELLOW}[-]${NC} Skipping Mega.nz URL (method $((url_index+1))/$total_urls) - megadl not available"
                fi
            else
                # Try with wget/curl for standard HTTP URLs
                echo -e "${YELLOW}[-]${NC} Attempting download using HTTP (method $((url_index+1))/$total_urls)"
                while [ $retry_count -lt $max_retries ] && [ "$download_success" = false ]; do
                    retry_count=$((retry_count + 1))
                    echo -e "${YELLOW}[-]${NC} Download attempt $retry_count of $max_retries from: $(echo "$current_url" | cut -c1-60)..."
                    
                    if command -v wget >/dev/null 2>&1; then
                        if timeout 600 wget -q --tries=1 --timeout=60 "$current_url" -O "$p4_driver_filename" 2>/dev/null; then
                            if [ -f "$p4_driver_filename" ] && [ -s "$p4_driver_filename" ]; then
                                download_success=true
                                echo -e "${GREEN}[+]${NC} Successfully downloaded using wget"
                                break
                            fi
                        fi
                    elif command -v curl >/dev/null 2>&1; then
                        if timeout 600 curl -L --retry 1 --max-time 60 --silent "$current_url" -o "$p4_driver_filename" 2>/dev/null; then
                            if [ -f "$p4_driver_filename" ] && [ -s "$p4_driver_filename" ]; then
                                download_success=true
                                echo -e "${GREEN}[+]${NC} Successfully downloaded using curl"
                                break
                            fi
                        fi
                    fi
                    
                    if [ $retry_count -lt $max_retries ]; then
                        echo -e "${YELLOW}[-]${NC} Download failed, retrying in 5 seconds..."
                        sleep 5
                    fi
                done
            fi
            
            url_index=$((url_index + 1))
        done
        
        
        # Method: Check if we can use an already downloaded file in the main directory
        if [ "$download_success" = false ]; then
            echo -e "${YELLOW}[-]${NC} All download methods failed, checking for existing driver file..."
            
            # Check if we can use an already downloaded file in the main directory
            if [ -f "$VGPU_DIR/$p4_driver_filename" ]; then
                echo -e "${YELLOW}[-]${NC} Found existing driver file in main directory, using it"
                cp "$VGPU_DIR/$p4_driver_filename" "$p4_driver_filename"
                if [ -f "$p4_driver_filename" ]; then
                    download_success=true
                    echo -e "${GREEN}[+]${NC} Successfully copied existing driver file"
                fi
            fi
        fi
        
        # Final check if download succeeded
        if [ "$download_success" = false ] || [ ! -f "$p4_driver_filename" ]; then
            echo -e "${RED}[!]${NC} Failed to download Tesla P4 driver after multiple attempts from all sources"
            echo -e "${YELLOW}[-]${NC} Download failure details:"
            echo -e "${YELLOW}[-]${NC} - Mega.nz URL may be throttled or blocked"
            echo -e "${YELLOW}[-]${NC} - Google Storage URLs returned 403 Forbidden (not publicly accessible)"  
            echo -e "${YELLOW}[-]${NC} - Network connectivity verified but specific URLs are unavailable"
            echo -e "${YELLOW}[-]${NC} Troubleshooting steps:"
            echo -e "${YELLOW}[-]${NC} 1. Check internet connectivity: ping -c 3 google.com"
            echo -e "${YELLOW}[-]${NC} 2. Install megatools if missing: apt install megatools"
            echo -e "${YELLOW}[-]${NC} 3. Manually download driver 16.4 from alternative sources:"
            echo -e "${YELLOW}[-]${NC}    - Official NVIDIA: Check NVIDIA Enterprise download portal"
            echo -e "${YELLOW}[-]${NC}    - Community sources: Check vGPU Unlocking Discord for current links"
            echo -e "${YELLOW}[-]${NC} 4. Place downloaded file as: $VGPU_DIR/$p4_driver_filename"
            cd "$VGPU_DIR" || {
                echo -e "${YELLOW}[-]${NC} Warning: Could not return to original directory: $VGPU_DIR"
            }
            return 1
        fi
        
        # Check MD5 hash
        local downloaded_md5=$(md5sum "$p4_driver_filename" 2>/dev/null | awk '{print $1}')
        if [ "$downloaded_md5" != "$p4_driver_md5" ]; then
            echo -e "${YELLOW}[-]${NC} MD5 checksum mismatch for Tesla P4 driver"
            echo -e "${YELLOW}[-]${NC} Expected: $p4_driver_md5"
            echo -e "${YELLOW}[-]${NC} Got:      $downloaded_md5"
            echo -e "${YELLOW}[-]${NC} Continuing anyway, but file integrity may be compromised"
        else
            echo -e "${GREEN}[+]${NC} Tesla P4 driver MD5 checksum verified"
        fi
    else
        echo -e "${YELLOW}[-]${NC} Tesla P4 driver already present, using existing file"
    fi
    
    # Extract the driver
    echo -e "${YELLOW}[-]${NC} Extracting Tesla P4 driver for vgpuConfig.xml"
    chmod +x "$p4_driver_filename"
    if ! timeout 60 ./"$p4_driver_filename" -x >/dev/null 2>&1; then
        echo -e "${RED}[!]${NC} Failed to extract Tesla P4 driver"
        echo -e "${YELLOW}[-]${NC} This could be due to:"
        echo -e "${YELLOW}[-]${NC} 1. Corrupted download (try re-downloading)"
        echo -e "${YELLOW}[-]${NC} 2. Insufficient disk space in /tmp"
        echo -e "${YELLOW}[-]${NC} 3. Permission issues"
        cd "$VGPU_DIR" || {
            echo -e "${YELLOW}[-]${NC} Warning: Could not return to original directory: $VGPU_DIR"
        }
        return 1
    fi
    
    # Check if vgpuConfig.xml was extracted
    local extracted_dir="${p4_driver_filename%.run}"
    if [ -f "$extracted_dir/vgpuConfig.xml" ]; then
        echo -e "${GREEN}[+]${NC} Tesla P4 vgpuConfig.xml extracted successfully" >&2
        cd "$VGPU_DIR" || {
            echo -e "${YELLOW}[-]${NC} Warning: Could not return to original directory: $VGPU_DIR" >&2
        }
        echo "$temp_dir/$extracted_dir/vgpuConfig.xml"
        return 0
    else
        echo -e "${RED}[!]${NC} vgpuConfig.xml not found in extracted Tesla P4 driver" >&2
        echo -e "${YELLOW}[-]${NC} Expected location: $temp_dir/$extracted_dir/vgpuConfig.xml" >&2
        echo -e "${YELLOW}[-]${NC} Available files in extracted directory:" >&2
        ls -la "$extracted_dir/" 2>/dev/null | head -10 >&2
        cd "$VGPU_DIR" || {
            echo -e "${YELLOW}[-]${NC} Warning: Could not return to original directory: $VGPU_DIR" >&2
        }
        return 1
    fi
}

# Function to check if Tesla P4 needs v16→v17 upgrade workflow
needs_tesla_p4_upgrade_workflow() {
    local selected_driver="$1"
    
    # Check if Tesla P4 is present and specifically v17.0 driver is being installed
    if detect_tesla_p4 && [[ "$selected_driver" == "NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run" ]]; then
        return 0  # Yes, needs upgrade workflow
    fi
    return 1  # No upgrade workflow needed
}

# Function to analyze NVIDIA installation errors and provide specific guidance
analyze_nvidia_installation_error() {
    local log_file="/var/log/nvidia-installer.log"
    
    echo ""
    echo -e "${BLUE}Analyzing Installation Error${NC}"
    echo -e "${BLUE}============================${NC}"
    
    if [ ! -f "$log_file" ]; then
        echo -e "${YELLOW}[-]${NC} nvidia-installer.log not found at $log_file"
        provide_general_fallback_guidance
        return 1
    fi
    
    # Check for specific known errors
    if grep -q "iommu_ops" "$log_file" 2>/dev/null; then
        handle_iommu_ops_error
    elif grep -q "compiler differs from the one used to build the kernel" "$log_file" 2>/dev/null; then
        handle_compiler_mismatch_error
    elif grep -q "No such file or directory.*kernel.*build" "$log_file" 2>/dev/null; then
        handle_missing_kernel_headers_error
    else
        echo -e "${YELLOW}[-]${NC} Analyzing general compilation errors..."
        provide_general_fallback_guidance
    fi
}

# Function to handle iommu_ops kernel API compatibility error
handle_iommu_ops_error() {
    echo -e "${RED}[!]${NC} Detected kernel API compatibility issue: iommu_ops error"
    echo -e "${YELLOW}[-]${NC} The v17.0 driver is incompatible with your kernel version"
    echo ""
    echo -e "${BLUE}Specific Issue:${NC}"
    echo -e "${YELLOW}•${NC} Kernel 6.8+ removed 'iommu_ops' from 'bus_type' struct"
    echo -e "${YELLOW}•${NC} NVIDIA v17.0 driver (550.54.10) expects old kernel API"
    echo -e "${YELLOW}•${NC} This causes compilation failure during kernel module build"
    echo ""
    
    local current_kernel=$(uname -r)
    echo -e "${BLUE}Recommended Solutions:${NC}"
    echo -e "${GREEN}1. Use compatible driver version:${NC}"
    echo -e "   • Install v16.9 (535.230.02) instead - fully compatible with $current_kernel"
    echo -e "   • Run: ./proxmox-installer.sh and select option 7"
    echo ""
    echo -e "${GREEN}2. Use older kernel version:${NC}"
    echo -e "   • Install kernel 6.5.x which is compatible with v17.0"
    echo -e "   • Command: apt install proxmox-kernel-6.5"
    echo -e "   • Reboot and select 6.5 kernel in GRUB menu"
    echo ""
    echo -e "${GREEN}3. Continue with v16.1 base driver:${NC}"
    echo -e "   • The v16.1 driver is already installed and should work"
    echo -e "   • Tesla P4 vGPU profiles will be available"
    echo -e "   • Run: systemctl restart nvidia-vgpu-mgr && mdevctl types | grep P4"
    echo ""
    echo -e "${YELLOW}Note:${NC} This is a known limitation with v17.0 driver on newer kernels"
}

# Function to handle compiler mismatch errors
handle_compiler_mismatch_error() {
    echo -e "${YELLOW}[-]${NC} Detected compiler version mismatch"
    echo -e "${YELLOW}[-]${NC} The kernel was built with a different compiler version"
    echo ""
    echo -e "${BLUE}Solution:${NC}"
    echo -e "${YELLOW}•${NC} This is usually a warning and shouldn't prevent installation"
    echo -e "${YELLOW}•${NC} If compilation still fails, check for other errors in the log"
    echo -e "${YELLOW}•${NC} Consider updating system: apt update && apt upgrade"
}

# Function to handle missing kernel headers error
handle_missing_kernel_headers_error() {
    local current_kernel=$(uname -r)
    local kernel_base=$(echo "$current_kernel" | cut -d'-' -f1,2)
    
    echo -e "${RED}[!]${NC} Missing kernel headers detected"
    echo -e "${YELLOW}[-]${NC} Kernel headers are required for driver compilation"
    echo ""
    echo -e "${BLUE}Solution:${NC}"
    echo -e "${GREEN}Install kernel headers:${NC}"
    echo -e "   apt install proxmox-headers-$kernel_base"
    echo -e "   # or"
    echo -e "   apt install pve-headers-$current_kernel"
    echo ""
    echo -e "Then retry the installation."
}

# Function to provide general fallback guidance
provide_general_fallback_guidance() {
    echo -e "${YELLOW}[-]${NC} Check /var/log/nvidia-installer.log for detailed error information"
    echo ""
    echo -e "${BLUE}General Fallback Options:${NC}"
    echo -e "${YELLOW}1.${NC} Continue with v16.1 driver (functional for Tesla P4)"
    echo -e "${YELLOW}2.${NC} Check kernel compatibility with: uname -r"
    echo -e "${YELLOW}3.${NC} Ensure kernel headers are installed: apt install proxmox-headers-\$(uname -r | cut -d'-' -f1,2)"
    echo -e "${YELLOW}4.${NC} Try alternative driver version (v16.9 recommended for newer kernels)"
    echo -e "${YELLOW}5.${NC} Consider kernel downgrade to 6.5.x for v17.0 compatibility"
}

# Function to perform Tesla P4 v16→v17 upgrade workflow
perform_tesla_p4_upgrade_workflow() {
    local target_v17_driver="$1"
    local target_v17_version="$2"
    
    echo ""
    echo -e "${BLUE}Tesla P4 v16→v17 Upgrade Workflow${NC}"
    echo -e "${BLUE}==================================${NC}"
    echo ""
    echo -e "${YELLOW}[-]${NC} Tesla P4 detected with v17.0 driver selection"
    echo -e "${YELLOW}[-]${NC} Tesla P4 cards require v16 driver installation first, then upgrade to v17"
    echo -e "${YELLOW}[-]${NC} This prevents kernel module compilation failures during direct v17 installation"
    echo ""
    
    # Choose appropriate v16 driver for the upgrade path
    local base_v16_driver="NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run"  # v16.1 - stable base
    local base_v16_url="https://mega.nz/file/wy1WVCaZ#Yq2Pz_UOfydHy8nC_X_nloR4NIFC1iZFHqJN0EiAicU"
    local base_v16_md5="1020ad5b89fa0570c27786128385ca48"
    
    echo -e "${GREEN}[+]${NC} Step 1: Installing v16.1 base driver for Tesla P4"
    echo -e "${YELLOW}[-]${NC} Base driver: $base_v16_driver"
    
    # Download v16 driver if not present
    if [ ! -f "$base_v16_driver" ]; then
        echo -e "${YELLOW}[-]${NC} Downloading Tesla P4 base driver v16.1..."
        
        if ! command -v megadl >/dev/null 2>&1; then
            run_command "Installing megatools for Tesla P4 upgrade workflow" "info" "apt update && apt install -y megatools"
        fi
        
        if ! megadl "$base_v16_url"; then
            echo -e "${RED}[!]${NC} Failed to download v16.1 base driver for Tesla P4 upgrade workflow"
            echo -e "${YELLOW}[-]${NC} Please manually download: $base_v16_driver"
            echo -e "${YELLOW}[-]${NC} And place it in: $VGPU_DIR"
            return 1
        fi
        
        # Verify MD5
        local downloaded_md5=$(md5sum "$base_v16_driver" | awk '{print $1}')
        if [ "$downloaded_md5" != "$base_v16_md5" ]; then
            echo -e "${YELLOW}[-]${NC} MD5 checksum mismatch for v16.1 base driver"
            echo -e "${YELLOW}[-]${NC} Expected: $base_v16_md5"
            echo -e "${YELLOW}[-]${NC} Got: $downloaded_md5"
            echo -e "${YELLOW}[-]${NC} Continuing anyway..."
        else
            echo -e "${GREEN}[+]${NC} v16.1 base driver MD5 verified"
        fi
    else
        echo -e "${GREEN}[+]${NC} v16.1 base driver already present"
    fi
    
    # Install v16 base driver
    chmod +x "$base_v16_driver"
    echo -e "${YELLOW}[-]${NC} Installing v16.1 base driver (this prepares the system for v17 upgrade)..."
    
    # Enhanced error handling for v16 installation
    if ! run_command "Installing Tesla P4 v16.1 base driver" "info" "./$base_v16_driver --dkms -m=kernel -s" false; then
        echo -e "${RED}[!]${NC} Failed to install v16.1 base driver"
        echo -e "${YELLOW}[-]${NC} Tesla P4 v16→v17 upgrade workflow cannot continue"
        return 1
    fi
    
    echo -e "${GREEN}[+]${NC} v16.1 base driver installed successfully"
    echo ""
    
    # Wait for v16 installation to stabilize
    echo -e "${YELLOW}[-]${NC} Waiting for v16 driver to stabilize before v17 upgrade..."
    sleep 10
    
    # Now install v17 as an upgrade over v16
    echo -e "${GREEN}[+]${NC} Step 2: Upgrading to v17.0 driver"
    echo -e "${YELLOW}[-]${NC} Target driver: $target_v17_driver"
    
    # Make sure v17 driver is executable
    chmod +x "$target_v17_driver"
    
    # Install v17 driver with upgrade-specific flags
    echo -e "${YELLOW}[-]${NC} Installing v17.0 as upgrade over v16.1 (Tesla P4 upgrade workflow)..."
    
    # Check kernel compatibility before attempting v17 installation
    local current_kernel=$(uname -r)
    local kernel_version=$(echo "$current_kernel" | cut -d'-' -f1)
    
    echo -e "${YELLOW}[-]${NC} Checking kernel compatibility for v17.0 driver..."
    echo -e "${YELLOW}[-]${NC} Current kernel: $current_kernel"
    
    # Check for known problematic kernel versions
    if [[ "$kernel_version" =~ ^6\.8\. ]]; then
        echo -e "${YELLOW}[-]${NC} Warning: Kernel 6.8.x has known API compatibility issues with v17.0 driver"
        echo -e "${YELLOW}[-]${NC} The driver may fail to compile due to kernel API changes (iommu_ops removal)"
        echo -e "${YELLOW}[-]${NC} Attempting installation with enhanced error detection..."
    fi
    
    # Enhanced error handling for v17 upgrade with more detailed logging
    if ! run_command "Upgrading to Tesla P4 v17.0 driver" "info" "./$target_v17_driver --dkms -m=kernel -s --force-update" false; then
        echo -e "${RED}[!]${NC} Failed to upgrade to v17.0 driver"
        echo -e "${YELLOW}[-]${NC} Tesla P4 v16→v17 upgrade workflow failed during v17 installation"
        echo -e "${YELLOW}[-]${NC} The v16.1 base driver should still be functional"
        
        # Analyze the specific error from nvidia-installer.log
        analyze_nvidia_installation_error
        
        return 1
    fi
    
    echo -e "${GREEN}[+]${NC} Tesla P4 v16→v17 upgrade workflow completed successfully"
    echo -e "${GREEN}[+]${NC} v17.0 driver installed as upgrade over v16.1 base"
    echo ""
    
    return 0
}

# Function to apply Tesla P4 vGPU configuration fix
apply_tesla_p4_fix() {
    # Only apply fix if Tesla P4 is detected
    if detect_tesla_p4; then
        echo ""
        echo -e "${YELLOW}[-]${NC} Tesla P4 GPU detected - applying vGPU configuration fix"
        echo -e "${YELLOW}[-]${NC} This fix replaces vgpuConfig.xml with the correct Tesla P4 configuration from driver 16.4"
        
        # Get the vgpuConfig.xml from driver 16.4
        local config_path
        config_path=$(download_tesla_p4_config)
        local download_result=$?
        
        if [ $download_result -eq 0 ] && [ -f "$config_path" ]; then
            # Create nvidia vgpu directory if it doesn't exist
            echo -e "${YELLOW}[-]${NC} Ensuring /usr/share/nvidia/vgpu directory exists"
            if ! mkdir -p "/usr/share/nvidia/vgpu"; then
                echo -e "${RED}[!]${NC} Failed to create /usr/share/nvidia/vgpu directory"
                echo -e "${YELLOW}[-]${NC} This could be due to insufficient permissions (run as root)"
                return 1
            fi
            
            # Backup existing config if it exists
            if [ -f "/usr/share/nvidia/vgpu/vgpuConfig.xml" ]; then
                local backup_file="/usr/share/nvidia/vgpu/vgpuConfig.xml.backup.$(date +%Y%m%d_%H%M%S)"
                echo -e "${YELLOW}[-]${NC} Backing up existing vgpuConfig.xml to $backup_file"
                cp "/usr/share/nvidia/vgpu/vgpuConfig.xml" "$backup_file" 2>/dev/null || true
            fi
            
            # Copy Tesla P4 specific configuration
            echo -e "${GREEN}[+]${NC} Installing Tesla P4 vgpuConfig.xml to /usr/share/nvidia/vgpu/"
            
            if cp "$config_path" "/usr/share/nvidia/vgpu/vgpuConfig.xml"; then
                echo -e "${GREEN}[+]${NC} File copied successfully"
                
                # Set proper permissions
                chmod 644 "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null || true
                chown root:root "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null || true
                
                # Verify the copied configuration contains Tesla P4 data
                if grep -q "1BB3\|1bb3" "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null; then
                    echo -e "${GREEN}[+]${NC} Tesla P4 vGPU configuration applied successfully"
                    echo -e "${GREEN}[+]${NC} Configuration contains Tesla P4 device ID (1BB3)"
                else
                    echo -e "${YELLOW}[-]${NC} Warning: Configuration file may not contain Tesla P4 specific data"
                fi
                
                # Clean up temporary files
                rm -rf "/tmp/tesla_p4_fix" 2>/dev/null || true
                
                echo -e "${GREEN}[+]${NC} Tesla P4 vGPU configuration fix completed"
                echo -e "${YELLOW}[-]${NC} ${RED}REBOOT REQUIRED:${NC} System must be rebooted for changes to take effect"
                echo -e "${YELLOW}[-]${NC} After reboot, Tesla P4 should show P4 profiles instead of P40 profiles"
                echo -e "${YELLOW}[-]${NC} Verify with: mdevctl types | grep -i 'p4-'"
                
            else
                echo -e "${RED}[!]${NC} Failed to copy Tesla P4 vgpuConfig.xml to /usr/share/nvidia/vgpu/"
                echo -e "${RED}[!]${NC} Tesla P4 fix could not be applied"
                return 1
            fi
        else
            echo -e "${RED}[!]${NC} Failed to download Tesla P4 configuration"
            echo -e "${YELLOW}[-]${NC} Manual fix instructions:"
            echo -e "${YELLOW}[-]${NC} 1. Install v17.0 driver first using this installer"
            echo -e "${YELLOW}[-]${NC} 2. Download NVIDIA driver 16.4: NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run"
            echo -e "${YELLOW}[-]${NC} 3. Extract: ./NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run -x"
            echo -e "${YELLOW}[-]${NC} 4. Copy config: cp NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm/vgpuConfig.xml /usr/share/nvidia/vgpu/"
            echo -e "${YELLOW}[-]${NC} 5. Reboot system"
            echo -e "${YELLOW}[-]${NC} 6. Verify: mdevctl types | grep -i 'p4-'"
            
            return 1
        fi
        
        echo ""
    else
        if [ "$DEBUG" = "true" ] || [ "$VERBOSE" = "true" ]; then
            echo -e "${GRAY}[DEBUG] No Tesla P4 detected, skipping Tesla P4 fix${NC}"
        fi
    fi
}

# Function to display usage information
display_usage() {
    echo -e "Usage: $0 [--debug] [--verbose] [--step <step_number>] [--url <url>] [--file <file>] [--tesla-p4-fix] [--tesla-p4-help] [--tesla-p4-status] [--tesla-p4-upgrade-test]"
    echo -e ""
    echo -e "Options:"
    echo -e "  --debug               Enable debug mode with verbose output"
    echo -e "  --verbose             Enable verbose logging for diagnostics"
    echo -e "  --step <number>       Jump to specific installation step"
    echo -e "  --url <url>           Use custom driver download URL"
    echo -e "  --file <file>         Use local driver file"
    echo -e "  --tesla-p4-fix        Run Tesla P4 vGPU configuration fix only"
    echo -e "  --tesla-p4-help       Show Tesla P4 troubleshooting guide"
    echo -e "  --tesla-p4-status     Check Tesla P4 vGPU profile status"
    echo -e "  --tesla-p4-upgrade-test  Test Tesla P4 v16→v17 upgrade workflow"
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
        --tesla-p4-fix)
            # Run Tesla P4 fix only
            echo ""
            echo -e "${BLUE}Tesla P4 vGPU Configuration Fix${NC}"
            echo -e "${BLUE}================================${NC}"
            echo ""
            if detect_tesla_p4; then
                apply_tesla_p4_fix
            else
                echo -e "${YELLOW}[-]${NC} No Tesla P4 GPU detected in this system"
                echo -e "${YELLOW}[-]${NC} This fix is only applicable to systems with Tesla P4 GPUs (device ID 1bb3)"
            fi
            exit 0
            ;;
        --tesla-p4-status)
            # Check Tesla P4 status
            echo ""
            echo -e "${BLUE}Tesla P4 vGPU Status Check${NC}"
            echo -e "${BLUE}==========================${NC}"
            echo ""
            
            # Check if Tesla P4 is detected
            if detect_tesla_p4; then
                echo -e "${GREEN}[+]${NC} Tesla P4 GPU detected (device ID: 1bb3)"
                
                # Check if NVIDIA services are running
                if systemctl is-active nvidia-vgpu-mgr.service >/dev/null 2>&1; then
                    echo -e "${GREEN}[+]${NC} nvidia-vgpu-mgr.service is active"
                else
                    echo -e "${YELLOW}[-]${NC} nvidia-vgpu-mgr.service is not active"
                fi
                
                # Check vgpuConfig.xml
                if [ -f "/usr/share/nvidia/vgpu/vgpuConfig.xml" ]; then
                    echo -e "${GREEN}[+]${NC} vgpuConfig.xml found at /usr/share/nvidia/vgpu/"
                    if grep -q "1BB3\|1bb3" "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null; then
                        echo -e "${GREEN}[+]${NC} Configuration contains Tesla P4 device ID (1BB3)"
                    else
                        echo -e "${YELLOW}[-]${NC} Configuration may not contain Tesla P4 device ID"
                    fi
                else
                    echo -e "${YELLOW}[-]${NC} vgpuConfig.xml not found - NVIDIA driver may not be installed"
                fi
                
                # Check mdevctl output
                echo ""
                echo -e "${YELLOW}[-]${NC} Checking vGPU types..."
                if command -v mdevctl >/dev/null 2>&1; then
                    local mdev_output=$(mdevctl types 2>/dev/null || true)
                    if [ -n "$mdev_output" ]; then
                        local p4_found=false
                        local p40_found=false
                        
                        if echo "$mdev_output" | grep -q "GRID P4-"; then
                            p4_found=true
                            echo -e "${GREEN}[+]${NC} Tesla P4 profiles found:"
                            echo "$mdev_output" | grep -A1 -B1 "GRID P4-" | head -10 | sed 's/^/  /'
                        fi
                        
                        if echo "$mdev_output" | grep -q "GRID P40-"; then
                            p40_found=true
                            echo -e "${YELLOW}[-]${NC} P40 profiles detected (this may be the issue):"
                            echo "$mdev_output" | grep -A1 -B1 "GRID P40-" | head -5 | sed 's/^/  /'
                        fi
                        
                        if [ "$p4_found" = true ] && [ "$p40_found" = false ]; then
                            echo -e "${GREEN}[+]${NC} Status: Tesla P4 is working correctly - P4 profiles visible"
                        elif [ "$p40_found" = true ]; then
                            echo -e "${RED}[!]${NC} Status: Tesla P4 fix needed - P40 profiles are showing"
                            echo -e "${YELLOW}[-]${NC} Run: $0 --tesla-p4-fix to apply the fix"
                        else
                            echo -e "${YELLOW}[-]${NC} Status: No P4/P40 profiles found"
                        fi
                    else
                        echo -e "${YELLOW}[-]${NC} No vGPU types found - services may not be running"
                    fi
                else
                    echo -e "${YELLOW}[-]${NC} mdevctl command not found"
                fi
            else
                echo -e "${YELLOW}[-]${NC} No Tesla P4 GPU detected in this system"
                echo -e "${YELLOW}[-]${NC} This check is only for systems with Tesla P4 GPUs (device ID 1bb3)"
            fi
            echo ""
            exit 0
            ;;
        --tesla-p4-upgrade-test)
            # Test Tesla P4 v16→v17 upgrade workflow
            echo ""
            echo -e "${BLUE}Tesla P4 v16→v17 Upgrade Workflow Test${NC}"
            echo -e "${BLUE}======================================${NC}"
            echo ""
            if detect_tesla_p4; then
                echo -e "${GREEN}[+]${NC} Tesla P4 detected, testing upgrade workflow..."
                # Simulate v17.0 driver selection for testing
                test_driver="NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run"
                if needs_tesla_p4_upgrade_workflow "$test_driver"; then
                    echo -e "${GREEN}[+]${NC} Tesla P4 upgrade workflow condition met"
                    echo -e "${YELLOW}[-]${NC} This would trigger the v16→v17 upgrade process"
                    echo -e "${YELLOW}[-]${NC} In normal installation, this prevents kernel module compilation failures"
                else
                    echo -e "${YELLOW}[-]${NC} Tesla P4 upgrade workflow condition not met for test driver"
                fi
            else
                echo -e "${YELLOW}[-]${NC} No Tesla P4 GPU detected in this system"
                echo -e "${YELLOW}[-]${NC} This test is only for systems with Tesla P4 GPUs (device ID 1bb3)"
            fi
            echo ""
            exit 0
            ;;
        --tesla-p4-help)
            show_tesla_p4_troubleshooting
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
    if [[ "$filename" =~ ^(NVIDIA-Linux-x86_64-535\.54\.06-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.104\.06-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.129\.03-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.161\.05-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.161\.05-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.183\.04-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.216\.01-vgpu-kvm\.run|NVIDIA-Linux-x86_64-535\.230\.02-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.54\.10-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.54\.16-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.90\.05-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.127\.06-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.144\.02-vgpu-kvm\.run|NVIDIA-Linux-x86_64-550\.163\.02-vgpu-kvm\.run|NVIDIA-Linux-x86_64-570\.124\.03-vgpu-kvm\.run|NVIDIA-Linux-x86_64-570\.133\.10-vgpu-kvm\.run)$ ]]; then
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
                driver_patch="550.163.10.patch"
                md5="093036d83baf879a4bb667b484597789"
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
    echo "  - FastAPI-DLS provides licensing server functionality"
    echo "  - Ensure sufficient licenses for your vGPU deployment"
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

        # Docker pull FastAPI-DLS
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
        # Generate the Docker Compose YAML file
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
    image: collinwebdesigns/fastapi-dls:latest
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
        # Create .sh file for Linux
        cat > "$VGPU_DIR/licenses/license_linux.sh" <<EOF
#!/bin/bash

curl --insecure -L -X GET https://$hostname:$portnumber/-/client-token -o /etc/nvidia/ClientConfigToken/client_configuration_token_\$(date '+%d-%m-%Y-%H-%M-%S').tok
service nvidia-gridd restart
nvidia-smi -q | grep "License"
EOF

        # Create .ps1 file for Windows
        cat > "$VGPU_DIR/licenses/license_windows.ps1" <<EOF
curl.exe --insecure -L -X GET https://$hostname:$portnumber/-/client-token -o "C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\client_configuration_token_\$(Get-Date -f 'dd-MM-yy-hh-mm-ss').tok"
Restart-Service NVDisplay.ContainerLocalSystem
& 'nvidia-smi' -q  | Select-String "License"
EOF

        echo -e "${GREEN}[+]${NC} license_windows.ps1 and license_linux.sh created and stored in: $VGPU_DIR/licenses"
        echo -e "${YELLOW}[-]${NC} Copy these files to your Windows or Linux VM's and execute"
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

# Main installation process
case $STEP in
    1)
    echo "Select an option:"
    echo ""
    echo "1) New vGPU installation"
    echo "2) Upgrade vGPU installation"
    echo "3) Remove vGPU installation"
    echo "4) Download vGPU drivers"
    echo "5) License vGPU"
    echo "6) Exit"
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
            echo -e "${YELLOW}[-]${NC} v17.x and v18.x drivers can use newer kernels"

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

                if [ "$vendor_id" = "AuthenticAMD" ]; then
                    echo -e "${GREEN}[+]${NC} Your CPU vendor id: ${YELLOW}${vendor_id}"
                    # Check if the required options are already present in GRUB_CMDLINE_LINUX_DEFAULT
                    if grep -q "amd_iommu=on iommu=pt" /etc/default/grub; then
                        echo -e "${YELLOW}[-]${NC} AMD IOMMU options are already set in GRUB_CMDLINE_LINUX_DEFAULT"
                    else
                        sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/"$/ amd_iommu=on iommu=pt"/' /etc/default/grub
                        echo -e "${GREEN}[+]${NC} AMD IOMMU options added to GRUB_CMDLINE_LINUX_DEFAULT"
                    fi
                elif [ "$vendor_id" = "GenuineIntel" ]; then
                    echo -e "${GREEN}[+]${NC} Your CPU vendor id: ${YELLOW}${vendor_id}${NC}"
                    # Check if the required options are already present in GRUB_CMDLINE_LINUX_DEFAULT
                    if grep -q "intel_iommu=on iommu=pt" /etc/default/grub; then
                        echo -e "${YELLOW}[-]${NC} Intel IOMMU options are already set in GRUB_CMDLINE_LINUX_DEFAULT"
                    else
                        sed -i '/GRUB_CMDLINE_LINUX_DEFAULT/s/"$/ intel_iommu=on iommu=pt"/' /etc/default/grub
                        echo -e "${GREEN}[+]${NC} Intel IOMMU options added to GRUB_CMDLINE_LINUX_DEFAULT"
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
                    # Download vgpu-proxmox
                    rm -rf $VGPU_DIR/vgpu-proxmox 2>/dev/null 
                    #echo "downloading vgpu-proxmox"
                    run_command "Downloading vgpu-proxmox" "info" "git clone https://github.com/PTHyperdrive/vgpu-proxmox.git $VGPU_DIR/vgpu-proxmox"

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

                    # Creating vgpu directory and toml file
                    echo -e "${GREEN}[+]${NC} Creating vGPU files and directories"
                    mkdir -p /etc/vgpu_unlock
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
            echo "1: 18.1 (570.133.10) (Only Native supported GPU)"
            echo "2: 18.0 (570.124.03)"
            echo "3: 17.6 (550.163.10) (Only Native supported GPU)"
            echo "4: 17.5 (550.144.02)"
            echo "5: 17.4 (550.127.06)"
            echo "6: 17.3 (550.90.05)"
            echo "7: 17.1 (550.54.16)"
            echo "8: 17.0 (550.54.10)"
            echo "9: 16.9 (535.230.02)"
            echo "10: 16.8 (535.216.01)"
            echo "11: 16.7 (535.183.04)"
            echo "12: 16.5 (535.161.05)"
            echo "13: 16.4 (535.161.05)"
            echo "14: 16.2 (535.129.03)"
            echo "15: 16.1 (535.104.06)"
            echo "16: 16.0 (535.54.06)"
            echo ""

            read -p "Enter your choice: " driver_choice

            # Validate the chosen filename against the compatibility map
            case $driver_choice in
                1) driver_filename="NVIDIA-Linux-x86_64-570.133.10-vgpu-kvm.run" ;;
                2) driver_filename="NVIDIA-Linux-x86_64-570.124.03-vgpu-kvm.run" ;;
                3) driver_filename="NVIDIA-Linux-x86_64-550.163.10-vgpu-kvm.run" ;;
                4) driver_filename="NVIDIA-Linux-x86_64-550.144.02-vgpu-kvm.run" ;;
                5) driver_filename="NVIDIA-Linux-x86_64-550.127.06-vgpu-kvm.run" ;;
                6) driver_filename="NVIDIA-Linux-x86_64-550.90.05-vgpu-kvm.run" ;;
                7) driver_filename="NVIDIA-Linux-x86_64-550.54.16-vgpu-kvm.run" ;;
                8) driver_filename="NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run" ;;
                9) driver_filename="NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run" ;;
                10) driver_filename="NVIDIA-Linux-x86_64-535.216.01-vgpu-kvm.run" ;;
                11) driver_filename="NVIDIA-Linux-x86_64-535.183.04-vgpu-kvm.run" ;;
                12) driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ;;
                13) driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ;;
                14) driver_filename="NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run" ;;
                15) driver_filename="NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" ;;
                16) driver_filename="NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" ;;
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
            case "$driver_version" in
                18.1)
                    driver_url="https://mega.nz/file/0YpHTAxJ#_XMpdJ68w3sM72p87kYSiEQXFA5BbFZl_xvF_XZSd4k"
                    driver_custom="https://mega.nz/file/tNgBVTxb#MXSUN5E_yc3lXYhlhDb7LUzYdDpGAbqP1g1388iN55k"
                    ;;
                18.0)
                    driver_url="https://mega.nz/file/RUxgjLRZ#aDy-DWKJXg-rTrisraE2MKrKbl1jbX4-13L0W32fiHQ"
                    driver_custom="https://mega.nz/file/REhCHLhR#Enqhctae9n5-Db2g0aXhYPY4juhiHR-Cc0iP1nmXz9M"
                    ;;
                17.6)
                    driver_url="https://mega.nz/file/NAYAGYpL#en-eYfid3GYmHkGVCAUagc6P2rbdw1Y2E9-7hOW19m8"
                    driver_custom="none"
                    ;;
                17.5)
                    driver_url="https://mega.nz/file/sYQ10b4b#hfGVeRog1pmNyx63N_I-siFENBWZj3w_ZQDsjW4PzW4"
                    driver_custom="none"
                    ;;
                17.4)
                    driver_url="https://mega.nz/file/VJIVTBiB#nFOU3zkoWyk4Dq1eW-y2dWUQ-YuvxVh_PYXT3bzdfYE"
                    driver_custom="none"
                    ;;
                17.3)
                    driver_url="https://mega.nz/file/1dYWAaDJ#9lGnw1CccnIcH7n7UAZ5nfGt3yUXcen72nOUiztw-RU"
                    driver_custom="none"
                    ;;
                17.1)
                    driver_url="https://mega.nz/file/sAYwDS7S#eyIeE_GYk_A0hwhayj3nOpcybLV_KAokJwXifDMQtPQ"
                    driver_custom="none"
                    ;;
                17.0)
                    driver_url="https://mega.nz/file/JjtyXRiC#cTIIvOIxu8vf-RdhaJMGZAwSgYmqcVEKNNnRRJTwDFI"
                    driver_custom="none"
                    ;;
                16.9)
                    driver_url="https://mega.nz/file/JFYDETBa#IqaXaoqrPAmSZSjbAXCWvHtiUxU0n9O7RJF8Xu5HXIo"
                    driver_custom="none"
                    ;;
                16.8)
                    driver_url="https://mega.nz/file/gJBGSZxK#cqyK3KCsfB0mYL8QCsV6P5C9ABmUcV7bQgE9DQ4_8O4"
                    driver_custom="none"
                    ;;
                16.7)
                    driver_url="https://mega.nz/file/gIwxGSyJ#xDcaxkymYcNFUTzwZ_m1HWcTgQrMSofJLPYMU-YGLMo"
                    driver_custom="none"
                    ;;
                16.5)
                    driver_url="https://mega.nz/file/RvsyyBaB#7fe_caaJkBHYC6rgFKtiZdZKkAvp7GNjCSa8ufzkG20"
                    driver_custom="none"
                    ;;
                16.4)
                    driver_url="https://mega.nz/file/RvsyyBaB#7fe_caaJkBHYC6rgFKtiZdZKkAvp7GNjCSa8ufzkG20"
                    driver_custom="none"
                    ;;
                16.2)
                    driver_url="https://mega.nz/file/EyEXTbbY#J9FUQL1Mo4ZpNyDijStEH4bWn3AKwnSAgJEZcxUnOiQ"
                    driver_custom="none"
                    ;;
                16.1)
                    driver_url="https://mega.nz/file/wy1WVCaZ#Yq2Pz_UOfydHy8nC_X_nloR4NIFC1iZFHqJN0EiAicU"
                    driver_custom="none"
                    ;;
                16.0)
                    driver_url="https://mega.nz/file/xrNCCAaT#UuUjqRap6urvX4KA1m8-wMTCW5ZwuWKUj6zAB4-NPSo"
                    driver_custom="none"
                    ;;
            esac

            echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"

            # Check if $driver_filename exists
            if [ -e "$driver_filename" ]; then
                mv "$driver_filename" "$driver_filename.bak"
                echo -e "${YELLOW}[-]${NC} Moved $driver_filename to $driver_filename.bak"
            fi
                  
            # Download and install the selected vGPU driver version
            echo -e "${GREEN}[+]${NC} Downloading vGPU $driver_filename host driver using megadl"
            
            # Check if megadl is available
            if ! command -v megadl >/dev/null 2>&1; then
                echo -e "${RED}[!]${NC} megadl (megatools) not found. Installing megatools..."
                apt update && apt install -y megatools
                if ! command -v megadl >/dev/null 2>&1; then
                    echo -e "${RED}[!]${NC} Failed to install megatools. Please install manually: apt install megatools"
                    exit 1
                fi
            fi
            
            megadl "$driver_url"

            # Download and install the selected vGPU custom driver
            if [ "$driver_custom" = "none" ]; then
                echo "${YELLOW}[-]${NC}No available custom found for $driver_filename"
                echo "${YELLOW}[-]${NC}Continue Installing Driver"
            else
                echo -e "${GREEN}[+]${NC} Downloading vGPU custom $driver_filename host driver using megadl"
                megadl "$driver_custom"
            fi
            
            # Check if download is successful
            if [ $? -ne 0 ]; then
                echo "Download failed."
                exit 1
            fi

            # Check MD5 hash of the downloaded file
            downloaded_md5=$(md5sum "$driver_filename" | awk '{print $1}')
            if [ "$downloaded_md5" != "$md5" ]; then
                echo -e "${RED}[!]${NC} MD5 checksum mismatch. Downloaded file is corrupt."
                echo ""
                read -p "$(echo -e "${BLUE}[?]${NC} Do you want to continue? (y/n): ")" choice
                echo ""
                if [ "$choice" != "y" ]; then
                    echo "Exiting script."
                    exit 1
                fi
            else
                echo -e "${GREEN}[+]${NC} MD5 checksum matched. Downloaded file is valid."
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
            echo "Exiting script."
            exit 0
            ;;
        *)
            echo ""
            echo "Invalid choice. Please enter 1, 2, 3, 4, 5 or 6."
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
            
            # Special guidance for Tesla P4 users
            if detect_tesla_p4; then
                echo ""
                echo -e "${BLUE}Tesla P4 Special Installation Notes:${NC}"
                echo -e "${YELLOW}[-]${NC} Tesla P4 detected - enhanced installation workflow available"
                echo -e "${YELLOW}[-]${NC} For v17.0 driver: Automatic v16→v17 upgrade workflow prevents compilation failures"
                echo -e "${YELLOW}[-]${NC} For other drivers: Standard installation with Tesla P4 profile fix applied"
            fi

            echo ""
            echo "Select vGPU driver version:"
            echo ""
            echo "1: 18.1 (570.133.10) (Only Native supported GPU)"
            echo "2: 18.0 (570.124.03)"
            echo "3: 17.6 (550.163.10) (Only Native supported GPU)"
            echo "4: 17.5 (550.144.02)"
            echo "5: 17.4 (550.127.06)"
            echo "6: 17.3 (550.90.05)"
            echo "7: 17.1 (550.54.16)"
            echo "8: 17.0 (550.54.10)"
            echo "9: 16.9 (535.230.02)"
            echo "10: 16.8 (535.216.01)"
            echo "11: 16.7 (535.183.04)"
            echo "12: 16.5 (535.161.05)"
            echo "13: 16.4 (535.161.05)"
            echo "14: 16.2 (535.129.03)"
            echo "15: 16.1 (535.104.06)"
            echo "16: 16.0 (535.54.06)"
            echo ""

            read -p "Enter your choice: " driver_choice

            echo ""

            # Validate the chosen filename against the compatibility map
            case $driver_choice in
                1) driver_filename="NVIDIA-Linux-x86_64-570.133.10-vgpu-kvm.run" ;;
                2) driver_filename="NVIDIA-Linux-x86_64-570.124.03-vgpu-kvm.run" ;;
                3) driver_filename="NVIDIA-Linux-x86_64-550.163.10-vgpu-kvm.run" ;;
                4) driver_filename="NVIDIA-Linux-x86_64-550.144.02-vgpu-kvm.run" ;;
                5) driver_filename="NVIDIA-Linux-x86_64-550.127.06-vgpu-kvm.run" ;;
                6) driver_filename="NVIDIA-Linux-x86_64-550.90.05-vgpu-kvm.run" ;;
                7) driver_filename="NVIDIA-Linux-x86_64-550.54.16-vgpu-kvm.run" ;;
                8) driver_filename="NVIDIA-Linux-x86_64-550.54.10-vgpu-kvm.run" ;;
                9) driver_filename="NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run" ;;
                10) driver_filename="NVIDIA-Linux-x86_64-535.216.01-vgpu-kvm.run" ;;
                11) driver_filename="NVIDIA-Linux-x86_64-535.183.04-vgpu-kvm.run" ;;
                12) driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ;;
                13) driver_filename="NVIDIA-Linux-x86_64-535.161.05-vgpu-kvm.run" ;;
                14) driver_filename="NVIDIA-Linux-x86_64-535.129.03-vgpu-kvm.run" ;;
                15) driver_filename="NVIDIA-Linux-x86_64-535.104.06-vgpu-kvm.run" ;;
                16) driver_filename="NVIDIA-Linux-x86_64-535.54.06-vgpu-kvm.run" ;;
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
                    echo -e "${GREEN}[+]${NC} Driver version $driver_ver (550.x/570.x series) supports flexible kernel versions"
                    echo -e "${YELLOW}[-]${NC} No kernel pinning required - can use latest available kernel"
                fi
            }
            
            # Apply kernel pinning based on selected driver version
            apply_kernel_pinning "$driver_version"
            
            # Set the driver URL if not provided
            if [ -z "$URL" ]; then
                case "$driver_version" in
                    18.1)
                        driver_url="https://mega.nz/file/0YpHTAxJ#_XMpdJ68w3sM72p87kYSiEQXFA5BbFZl_xvF_XZSd4k"
                        driver_custom="https://mega.nz/file/tNgBVTxb#MXSUN5E_yc3lXYhlhDb7LUzYdDpGAbqP1g1388iN55k"
                        ;;
                    18.0)
                        driver_url="https://mega.nz/file/RUxgjLRZ#aDy-DWKJXg-rTrisraE2MKrKbl1jbX4-13L0W32fiHQ"
                        driver_custom="https://mega.nz/file/REhCHLhR#Enqhctae9n5-Db2g0aXhYPY4juhiHR-Cc0iP1nmXz9M"
                        ;;
                    17.6)
                        driver_url="https://mega.nz/file/NAYAGYpL#en-eYfid3GYmHkGVCAUagc6P2rbdw1Y2E9-7hOW19m8"
                        driver_custom="none"
                        ;;
                    17.5)
                        driver_url="https://mega.nz/file/sYQ10b4b#hfGVeRog1pmNyx63N_I-siFENBWZj3w_ZQDsjW4PzW4"
                        driver_custom="none"
                        ;;
                    17.4)
                        driver_url="https://mega.nz/file/VJIVTBiB#nFOU3zkoWyk4Dq1eW-y2dWUQ-YuvxVh_PYXT3bzdfYE"
                        driver_custom="none"
                        ;;
                    17.3)
                        driver_url="https://mega.nz/file/1dYWAaDJ#9lGnw1CccnIcH7n7UAZ5nfGt3yUXcen72nOUiztw-RU"
                        driver_custom="none"
                        ;;
                    17.1)
                        driver_url="https://mega.nz/file/sAYwDS7S#eyIeE_GYk_A0hwhayj3nOpcybLV_KAokJwXifDMQtPQ"
                        driver_custom="none"
                        ;;
                    17.0)
                        driver_url="https://mega.nz/file/JjtyXRiC#cTIIvOIxu8vf-RdhaJMGZAwSgYmqcVEKNNnRRJTwDFI"
                        driver_custom="none"
                        ;;
                    16.9)
                        driver_url="https://mega.nz/file/JFYDETBa#IqaXaoqrPAmSZSjbAXCWvHtiUxU0n9O7RJF8Xu5HXIo"
                        driver_custom="none"
                        ;;
                    16.8)
                        driver_url="https://mega.nz/file/gJBGSZxK#cqyK3KCsfB0mYL8QCsV6P5C9ABmUcV7bQgE9DQ4_8O4"
                        driver_custom="none"
                        ;;
                    16.7)
                        driver_url="https://mega.nz/file/gIwxGSyJ#xDcaxkymYcNFUTzwZ_m1HWcTgQrMSofJLPYMU-YGLMo"
                        driver_custom="none"
                        ;;
                    16.5)
                        driver_url="https://mega.nz/file/RvsyyBaB#7fe_caaJkBHYC6rgFKtiZdZKkAvp7GNjCSa8ufzkG20"
                        driver_custom="none"
                        ;;
                    16.4)
                        driver_url="https://mega.nz/file/RvsyyBaB#7fe_caaJkBHYC6rgFKtiZdZKkAvp7GNjCSa8ufzkG20"
                        driver_custom="none"
                        ;;
                    16.2)
                        driver_url="https://mega.nz/file/EyEXTbbY#J9FUQL1Mo4ZpNyDijStEH4bWn3AKwnSAgJEZcxUnOiQ"
                        driver_custom="none"
                        ;;
                    16.1)
                        driver_url="https://mega.nz/file/wy1WVCaZ#Yq2Pz_UOfydHy8nC_X_nloR4NIFC1iZFHqJN0EiAicU"
                        driver_custom="none"
                        ;;
                    16.0)
                        driver_url="https://mega.nz/file/xrNCCAaT#UuUjqRap6urvX4KA1m8-wMTCW5ZwuWKUj6zAB4-NPSo"
                        driver_custom="none"
                        ;;
                esac
            fi

            echo -e "${YELLOW}[-]${NC} Driver version: $driver_filename"

            # Check if $driver_filename exists
            if [ -e "$driver_filename" ]; then
                mv "$driver_filename" "$driver_filename.bak"
                echo -e "${YELLOW}[-]${NC} Moved $driver_filename to $driver_filename.bak"
            fi
                
            # Download and install the selected vGPU driver version
            echo -e "${GREEN}[+]${NC} Downloading vGPU $driver_filename host driver using megadl"
            
            # Check if megadl is available
            if ! command -v megadl >/dev/null 2>&1; then
                echo -e "${RED}[!]${NC} megadl (megatools) not found. Installing megatools..."
                apt update && apt install -y megatools
                if ! command -v megadl >/dev/null 2>&1; then
                    echo -e "${RED}[!]${NC} Failed to install megatools. Please install manually: apt install megatools"
                    exit 1
                fi
            fi
            
            megadl "$driver_url"
            
            if [ "$driver_custom" = "none" ]; then
                echo "${YELLOW}[-]${NC}No available custom found for $driver_filename"
                echo "${YELLOW}[-]${NC}Continue Installing Driver"
            else
                echo -e "${GREEN}[+]${NC} Downloading vGPU custom $driver_filename host driver using megadl"
                megadl "$driver_custom"
            fi
            # Check if download is successful
            if [ $? -ne 0 ]; then
                echo -e "${RED}[!]${NC} Download failed."
                exit 1
            fi

            # Check MD5 hash of the downloaded file
            downloaded_md5=$(md5sum "$driver_filename" | awk '{print $1}')
            if [ "$downloaded_md5" != "$md5" ]; then
                echo -e "${RED}[!]${NC}  MD5 checksum mismatch. Downloaded file is corrupt."
                echo ""
                read -p "$(echo -e "${BLUE}[?]${NC}Do you want to continue? (y/n): ")" choice
                echo ""
                if [ "$choice" != "y" ]; then
                    echo "Exiting script."
                    exit 1
                fi
            else
                echo -e "${GREEN}[+]${NC} MD5 checksum matched. Downloaded file is valid."
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

        # Check if Tesla P4 needs special v16→v17 upgrade workflow
        if needs_tesla_p4_upgrade_workflow "$driver_filename"; then
            echo ""
            echo -e "${BLUE}Tesla P4 Special Installation Workflow Detected${NC}"
            echo -e "${BLUE}===============================================${NC}"
            echo ""
            echo -e "${YELLOW}[-]${NC} Tesla P4 + v17.0 driver combination detected"
            echo -e "${YELLOW}[-]${NC} Using enhanced installation workflow to prevent kernel module compilation failures"
            
            # Perform the special Tesla P4 v16→v17 upgrade workflow
            if perform_tesla_p4_upgrade_workflow "$driver_filename" "$driver_version"; then
                echo -e "${GREEN}[+]${NC} Tesla P4 v16→v17 upgrade workflow completed successfully"
                write_log "Tesla P4 v16→v17 upgrade workflow completed successfully"
                
                # Skip normal driver installation since Tesla P4 workflow handled it
                echo -e "${YELLOW}[-]${NC} Skipping standard driver installation (Tesla P4 upgrade workflow completed)"
                
                # Jump to post-installation steps
                tesla_p4_workflow_completed=true
            else
                echo -e "${RED}[!]${NC} Tesla P4 v16→v17 upgrade workflow failed"
                echo -e "${YELLOW}[-]${NC} Falling back to standard installation (may fail with kernel module errors)"
                write_log "Tesla P4 v16→v17 upgrade workflow failed, falling back to standard installation"
                tesla_p4_workflow_completed=false
            fi
        else
            tesla_p4_workflow_completed=false
        fi

        # Patch and install the driver only if vGPU is not native and Tesla P4 workflow didn't complete
        if [ "$tesla_p4_workflow_completed" = "false" ] && [ "$VGPU_SUPPORT" = "Yes" ]; then
            write_log "Installing vGPU driver with patching for non-native vGPU support"
            
            # Check if patch file exists first
            if [ -f "$VGPU_DIR/vgpu-proxmox/$driver_patch" ]; then
                echo -e "${YELLOW}[-]${NC} Patch file found, applying vGPU patch to driver..."
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
                
                # Apply the patch
                run_command "Patching driver" "info" "./$driver_filename --apply-patch $VGPU_DIR/vgpu-proxmox/$driver_patch" true true
                
                if [ -f "$custom_filename" ]; then
                    echo -e "${GREEN}[+]${NC} Patched driver created successfully: $custom_filename"
                    write_log "Patched driver created: $custom_filename"
                    
                    if [ "$VERBOSE" = "true" ]; then
                        echo -e "${GRAY}[DEBUG] Patched driver size: $(du -h $custom_filename | cut -f1)${NC}"
                    fi
                    
                    # Run the patched driver installer
                    echo -e "${YELLOW}[-]${NC} Installing patched vGPU driver (this may take several minutes)..."
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
            
        elif [ "$tesla_p4_workflow_completed" = "false" ] && ([ "$VGPU_SUPPORT" = "Native" ] || [ "$VGPU_SUPPORT" = "Native" ] || [ "$VGPU_SUPPORT" = "Unknown" ]); then
            write_log "Installing native vGPU driver (no patching required)"
            
            # Run the regular driver installer
            echo -e "${YELLOW}[-]${NC} Installing native vGPU driver (this may take several minutes)..."
            log_system_info "kernel"  # Log kernel state before installation
            run_command "Installing native driver" "info" "./$driver_filename --dkms -m=kernel -s" true true
            
        elif [ "$tesla_p4_workflow_completed" = "false" ]; then
            echo -e "${RED}[!]${NC} Unknown or unsupported GPU: $VGPU_SUPPORT"
            write_log "ERROR: Unknown GPU support type: $VGPU_SUPPORT"
            echo ""
            echo "Exiting script."
            echo ""
            exit 1
        fi

        # If Tesla P4 workflow completed successfully, we can skip to post-installation
        if [ "$tesla_p4_workflow_completed" = "true" ]; then
            echo -e "${GREEN}[+]${NC} Tesla P4 driver installation completed via upgrade workflow"
            write_log "Tesla P4 driver installation completed via upgrade workflow"
        else
            echo -e "${GREEN}[+]${NC} Driver installed successfully."
            write_log "Driver installation completed successfully"
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

        # Apply Tesla P4 vGPU configuration fix if needed
        apply_tesla_p4_fix

        # Check DRIVER_VERSION against specific driver filenames
        if [ "$driver_filename" == "NVIDIA-Linux-x86_64-570.133.10-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 570.133.10"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU18.1/NVIDIA-Linux-x86_64-570.133.20-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU18.1/572.83_grid_win10_win11_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-570.124.03-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 570.124.03"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU18.0/NVIDIA-Linux-x86_64-570.124.06-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU18.0/572.60_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-550.163.02-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 550.163.02"
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
            # Check for Tesla P4 and inform about the fix
            if detect_tesla_p4; then
                echo -e "${GREEN}[+]${NC} Tesla P4 detected: vGPU configuration has been fixed to enable P4 vGPU types"
            fi
        elif [ "$driver_filename" == "NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run" ]; then
            echo -e "${GREEN}[+]${NC} In your VM download Nvidia guest driver for version: 535.230.02"
            echo -e "${YELLOW}[-]${NC} Linux: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.9/NVIDIA-Linux-x86_64-535.230.02-grid.run"
            echo -e "${YELLOW}[-]${NC} Windows: https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU16.9/539.19_grid_win10_win11_server2019_server2022_dch_64bit_international.exe"
            # Check for Tesla P4 and inform about the fix
            if detect_tesla_p4; then
                echo -e "${GREEN}[+]${NC} Tesla P4 detected: vGPU configuration has been fixed to show P4 profiles instead of P40 profiles"
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
            # Check for Tesla P4 and inform about the fix
            if detect_tesla_p4; then
                echo -e "${GREEN}[+]${NC} Tesla P4 detected: vGPU configuration has been fixed to show P4 profiles instead of P40 profiles"
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
        
        # Tesla P4 specific messaging
        if detect_tesla_p4; then
            echo -e "${GREEN}[+]${NC} Tesla P4 vGPU configuration has been applied"
            echo -e "${YELLOW}[-]${NC} After reboot, your Tesla P4 should show proper P4 vGPU profiles instead of P40 profiles"
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

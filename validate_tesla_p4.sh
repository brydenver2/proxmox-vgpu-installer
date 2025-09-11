#!/bin/bash

# Tesla P4 vGPU Validation Script
# This script helps users verify if their Tesla P4 fix is working correctly

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}Tesla P4 vGPU Validation Script${NC}"
echo -e "${BLUE}===============================${NC}"
echo ""

# Function to check Tesla P4 hardware
check_tesla_p4_hardware() {
    echo -e "${YELLOW}1. Checking for Tesla P4 hardware...${NC}"
    
    local gpu_info=$(lspci -nn | grep -i 'NVIDIA Corporation' | grep -Ei '(VGA compatible controller|3D controller)')
    if [ -n "$gpu_info" ]; then
        echo -e "   Found NVIDIA GPU(s):"
        echo "$gpu_info" | sed 's/^/   /'
        
        local gpu_device_ids=$(echo "$gpu_info" | grep -oE '\[10de:[0-9a-fA-F]{2,4}\]' | cut -d ':' -f 2 | tr -d ']')
        local tesla_p4_found=false
        
        for device_id in $gpu_device_ids; do
            if [ "$device_id" = "1bb3" ]; then
                tesla_p4_found=true
                echo -e "   ${GREEN}✓${NC} Tesla P4 detected (device ID: 1bb3)"
                break
            fi
        done
        
        if [ "$tesla_p4_found" = false ]; then
            echo -e "   ${YELLOW}!${NC} No Tesla P4 found (device IDs: $gpu_device_ids)"
            echo -e "   ${YELLOW}!${NC} This validation is specifically for Tesla P4 GPUs"
        fi
        
        return $([ "$tesla_p4_found" = true ] && echo 0 || echo 1)
    else
        echo -e "   ${RED}✗${NC} No NVIDIA GPUs detected"
        return 1
    fi
}

# Function to check NVIDIA services
check_nvidia_services() {
    echo ""
    echo -e "${YELLOW}2. Checking NVIDIA services...${NC}"
    
    local services_ok=true
    
    # Check nvidia-vgpud service
    if systemctl is-active nvidia-vgpud.service >/dev/null 2>&1; then
        echo -e "   ${GREEN}✓${NC} nvidia-vgpud.service is active"
    else
        echo -e "   ${RED}✗${NC} nvidia-vgpud.service is not active"
        services_ok=false
    fi
    
    # Check nvidia-vgpu-mgr service
    if systemctl is-active nvidia-vgpu-mgr.service >/dev/null 2>&1; then
        echo -e "   ${GREEN}✓${NC} nvidia-vgpu-mgr.service is active"
    else
        echo -e "   ${RED}✗${NC} nvidia-vgpu-mgr.service is not active"
        services_ok=false
    fi
    
    return $([ "$services_ok" = true ] && echo 0 || echo 1)
}

# Function to check vgpuConfig.xml
check_vgpu_config() {
    echo ""
    echo -e "${YELLOW}3. Checking vgpuConfig.xml...${NC}"
    
    if [ -f "/usr/share/nvidia/vgpu/vgpuConfig.xml" ]; then
        echo -e "   ${GREEN}✓${NC} vgpuConfig.xml found at /usr/share/nvidia/vgpu/"
        
        # Check file permissions and ownership
        local file_perms=$(ls -la "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null)
        echo -e "   ${YELLOW}ℹ${NC} File permissions: $(echo "$file_perms" | awk '{print $1, $3":"$4, $5"B"}')"
        
        # Check if file is readable
        if [ -r "/usr/share/nvidia/vgpu/vgpuConfig.xml" ]; then
            echo -e "   ${GREEN}✓${NC} Configuration file is readable"
            
            # Check file size
            local file_size=$(stat -c%s "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null || echo "0")
            if [ "$file_size" -gt 0 ]; then
                echo -e "   ${GREEN}✓${NC} Configuration file has content (${file_size} bytes)"
            else
                echo -e "   ${RED}✗${NC} Configuration file is empty"
                return 1
            fi
        else
            echo -e "   ${RED}✗${NC} Configuration file is not readable"
            echo -e "   ${YELLOW}!${NC} This could be a permissions issue preventing NVIDIA services from reading it"
            return 1
        fi
        
        # Check SELinux context if available
        if command -v ls >/dev/null 2>&1 && ls --help 2>&1 | grep -q "\-Z"; then
            local selinux_context=$(ls -Z "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null | awk '{print $1}')
            if [ -n "$selinux_context" ] && [ "$selinux_context" != "?" ]; then
                echo -e "   ${YELLOW}ℹ${NC} SELinux context: $selinux_context"
            fi
        fi
        
        # Check content for Tesla P4 device ID
        if grep -q "1BB3\|1bb3" "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null; then
            echo -e "   ${GREEN}✓${NC} Configuration contains Tesla P4 device ID (1BB3)"
        else
            echo -e "   ${YELLOW}!${NC} Configuration may not contain Tesla P4 device ID"
            echo -e "   ${YELLOW}!${NC} This could explain P40 profile issues"
            return 1
        fi
        
        # Check for P40 references (should not be present)
        if grep -q "P40-\|1B38\|1b38" "/usr/share/nvidia/vgpu/vgpuConfig.xml" 2>/dev/null; then
            echo -e "   ${YELLOW}!${NC} Warning: Configuration contains P40 references"
            echo -e "   ${YELLOW}!${NC} Tesla P4 fix may need to be applied"
        else
            echo -e "   ${GREEN}✓${NC} No P40 references found in configuration"
        fi
        
        return 0
    else
        echo -e "   ${RED}✗${NC} vgpuConfig.xml not found"
        echo -e "   ${RED}✗${NC} NVIDIA vGPU driver may not be installed"
        return 1
    fi
}

# Function to check vGPU profiles
check_vgpu_profiles() {
    echo ""
    echo -e "${YELLOW}4. Checking vGPU profiles...${NC}"
    
    if ! command -v mdevctl >/dev/null 2>&1; then
        echo -e "   ${RED}✗${NC} mdevctl command not found"
        return 1
    fi
    
    local mdev_output=$(mdevctl types 2>/dev/null || true)
    if [ -z "$mdev_output" ]; then
        echo -e "   ${RED}✗${NC} No vGPU types found"
        echo -e "   ${YELLOW}!${NC} Services may need time to initialize or restart"
        return 1
    fi
    
    local p4_found=false
    local p40_found=false
    
    # Check for P4 profiles (correct)
    if echo "$mdev_output" | grep -q "GRID P4-\|Name: GRID P4-"; then
        p4_found=true
        echo -e "   ${GREEN}✓${NC} Tesla P4 profiles found:"
        echo "$mdev_output" | grep -A1 -B1 "GRID P4-" | head -6 | sed 's/^/     /'
    fi
    
    # Check for P40 profiles (problematic)
    if echo "$mdev_output" | grep -q "GRID P40-\|Name: GRID P40-"; then
        p40_found=true
        echo -e "   ${RED}✗${NC} P40 profiles detected (this is the issue):"
        echo "$mdev_output" | grep -A1 -B1 "GRID P40-" | head -4 | sed 's/^/     /'
    fi
    
    # Final assessment
    if [ "$p4_found" = true ] && [ "$p40_found" = false ]; then
        echo -e "   ${GREEN}✓${NC} Tesla P4 is working correctly!"
        return 0
    elif [ "$p40_found" = true ]; then
        echo -e "   ${RED}✗${NC} Tesla P4 fix needed - P40 profiles are showing"
        return 1
    else
        echo -e "   ${YELLOW}!${NC} No P4 or P40 profiles found"
        return 1
    fi
}

# Function to provide recommendations
provide_recommendations() {
    local hardware_ok=$1
    local services_ok=$2
    local config_ok=$3
    local profiles_ok=$4
    
    echo ""
    echo -e "${BLUE}Recommendations:${NC}"
    echo ""
    
    if [ $hardware_ok -ne 0 ]; then
        echo -e "${YELLOW}•${NC} No Tesla P4 detected - this validation is specific to Tesla P4 GPUs"
        return
    fi
    
    if [ $services_ok -ne 0 ]; then
        echo -e "${YELLOW}•${NC} Start NVIDIA services:"
        echo "  systemctl start nvidia-vgpud.service"
        echo "  systemctl start nvidia-vgpu-mgr.service"
        echo ""
    fi
    
    if [ $config_ok -ne 0 ] || [ $profiles_ok -ne 0 ]; then
        echo -e "${YELLOW}•${NC} Apply Tesla P4 fix:"
        echo "  ./proxmox-installer.sh --tesla-p4-fix"
        echo ""
        echo -e "${YELLOW}•${NC} If configuration file exists but has permission issues:"
        echo "  sudo chown root:root /usr/share/nvidia/vgpu/vgpuConfig.xml"
        echo "  sudo chmod 644 /usr/share/nvidia/vgpu/vgpuConfig.xml"
        echo ""
        echo -e "${YELLOW}•${NC} If SELinux is blocking access (check with 'getenforce'):"
        echo "  sudo restorecon -v /usr/share/nvidia/vgpu/vgpuConfig.xml"
        echo ""
        echo -e "${YELLOW}•${NC} If still showing P40 profiles after fix, try enhanced service restart:"
        echo "  systemctl stop nvidia-vgpu-mgr nvidia-vgpud"
        echo "  sleep 10"
        echo "  systemctl start nvidia-vgpud"
        echo "  sleep 5"
        echo "  systemctl start nvidia-vgpu-mgr"
        echo "  sleep 20"
        echo "  mdevctl types"
        echo ""
        echo -e "${YELLOW}•${NC} If configuration file is correct but services won't reload:"
        echo "  modprobe -r nvidia_vgpu_vfio nvidia"
        echo "  sleep 5"
        echo "  modprobe nvidia"
        echo "  systemctl start nvidia-vgpud nvidia-vgpu-mgr"
        echo "  sleep 30"
        echo "  mdevctl types"
        echo ""
    fi
    
    if [ $hardware_ok -eq 0 ] && [ $services_ok -eq 0 ] && [ $config_ok -eq 0 ] && [ $profiles_ok -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Tesla P4 is configured correctly!"
        echo -e "${GREEN}✓${NC} You can now create vGPUs using the P4 profiles"
    fi
}

# Main validation
main() {
    check_tesla_p4_hardware
    hardware_result=$?
    
    check_nvidia_services
    services_result=$?
    
    check_vgpu_config
    config_result=$?
    
    check_vgpu_profiles
    profiles_result=$?
    
    provide_recommendations $hardware_result $services_result $config_result $profiles_result
    
    echo ""
    echo -e "${BLUE}Validation completed.${NC}"
    echo ""
}

# Run main function
main
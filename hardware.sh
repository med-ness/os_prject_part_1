#!/bin/bash
# ==============================================================================
# hardware.sh — Hardware information collector
#
# Each function below collects one type of hardware data.
# They are called individually for short reports, or all together
# via get_hardware() for the full report.
#
# Functions:
#   get_cpu()         → Full CPU details
#   get_cpu_short()   → Quick one-line CPU summary
#   get_gpu()         → GPU/graphics card info
#   get_ram()         → RAM and swap details
#   get_ram_short()   → Quick RAM summary
#   get_disk()        → Disk partitions and usage
#   get_disk_short()  → Quick root disk usage
#   get_network()     → IP addresses, MACs, routing table
#   get_motherboard() → Motherboard make/model
#   get_usb()         → Connected USB devices
#   check_cpu_alert() → Warns if CPU is over 80%
#   get_hardware()    → Calls all of the above (used for full report)
# ==============================================================================

# --- CPU: Full Details ---
# Uses 'lscpu' to show all processor information (model, cores, threads, etc.)
get_cpu() {
    print_section "CPU INFO"
    lscpu
}

# --- CPU: Short Summary ---
# Grabs only the most useful CPU fields for the short report
get_cpu_short() {
    echo "--- CPU ---"
    lscpu | grep -E "^(Model name|Architecture|CPU\(s\)|Thread|Core)"
}

# --- GPU: Graphics Card ---
# Uses 'lspci' to find any VGA/display/3D adapter connected to the system.
# If lspci is not installed, warns the user to install pciutils.
get_gpu() {
    print_section "GPU INFO"
    if command -v lspci &>/dev/null; then
        local gpu
        gpu=$(lspci | grep -iE "vga|3d|display")
        if [ -n "$gpu" ]; then
            echo "$gpu"
        else
            echo "No dedicated GPU detected."
        fi
    else
        print_warning "lspci not available. Install pciutils."
    fi
}

# --- RAM: Full Details ---
# Shows total/used/free RAM using 'free -h' (human-readable)
# Also reads /proc/meminfo for more precise values (MemAvailable, SwapFree, etc.)
get_ram() {
    print_section "RAM INFO"
    free -h
    echo ""
    # Extra details from the kernel's memory table
    grep -E "^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree)" /proc/meminfo
}

# --- RAM: Short Summary ---
# Just the total/used/free memory line — used in the short report
get_ram_short() {
    echo "--- RAM ---"
    free -h | grep Mem
}

# --- Disk: Full Details ---
# Shows two things:
#   1. Block devices (partitions, sizes, filesystem types) via lsblk
#   2. Disk usage per partition via df (filtered to hide tmpfs/udev noise)
get_disk() {
    print_section "DISK INFO"
    echo "[ Block Devices ]"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
    echo ""
    echo "[ Disk Usage ]"
    df -h --output=source,size,used,avail,pcent,target | grep -v "tmpfs\|udev"
}

# --- Disk: Short Summary ---
# Just shows usage of the root partition (/) — used in the short report
get_disk_short() {
    echo "--- Disk (/) ---"
    df -h / | tail -1
}

# --- Network: Full Details ---
# Shows three things:
#   1. IP addresses and network interfaces
#   2. MAC (hardware) addresses
#   3. The routing table (which gateway the system uses)
get_network() {
    print_section "NETWORK INFO"
    echo "[ IP Addresses & Interfaces ]"
    ip -brief addr show
    echo ""
    echo "[ MAC Addresses ]"
    ip link show | awk '/link\/ether/ {print $0}' | awk '{print $NF, "->", $2}'
    echo ""
    echo "[ Routing Table ]"
    ip route
}

# --- Motherboard: Make and Model ---
# Tries 'dmidecode' first (gives the most info, requires sudo).
# If not available, falls back to reading from /sys/class/dmi/id/ (no sudo needed).
get_motherboard() {
    print_section "MOTHERBOARD INFO"
    if command -v dmidecode &>/dev/null; then
        sudo dmidecode -t baseboard 2>/dev/null | grep -E "(Manufacturer|Product Name|Version|Serial)"
    else
        print_warning "dmidecode not available. Install dmidecode for motherboard info."
        # Fallback: read from the kernel's hardware info directory
        echo "Vendor  : $(cat /sys/class/dmi/id/board_vendor  2>/dev/null || echo 'N/A')"
        echo "Name    : $(cat /sys/class/dmi/id/board_name    2>/dev/null || echo 'N/A')"
        echo "Version : $(cat /sys/class/dmi/id/board_version 2>/dev/null || echo 'N/A')"
    fi
}

# --- USB: Connected Devices ---
# Lists all USB devices currently plugged in using 'lsusb'.
# Install usbutils if it's missing.
get_usb() {
    print_section "USB DEVICES"
    if command -v lsusb &>/dev/null; then
        lsusb
    else
        print_warning "lsusb not available. Install usbutils."
    fi
}

# --- CPU Alert: Check if CPU is too high ---
# Calls get_cpu_usage() (from utils.sh) and compares it to 80%.
# Used in the full report to warn if the system is under heavy load.
# Returns exit code 1 if CPU > 80%, 0 if normal.
check_cpu_alert() {
    local cpu_usage
    cpu_usage=$(get_cpu_usage)
    if [ "$cpu_usage" -gt 80 ]; then
        print_cpu_alert "CPU usage is HIGH: ${cpu_usage}%"
        return 1
    else
        print_info "CPU usage is normal: ${cpu_usage}%"
        return 0
    fi
}

# --- Full Hardware Audit ---
# Runs ALL hardware checks in order.
# This is what gets called when generating the full report.
get_hardware() {
    get_cpu
    get_gpu
    get_ram
    get_disk
    get_network
    get_motherboard
    get_usb
}
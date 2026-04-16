#!/bin/bash
# ==============================================================================
# software.sh — Software and system information collector
#
# Collects information about the operating system, installed packages,
# users, processes, services, and open network ports.
#
# Functions:
#   get_os()              → Full OS and kernel info
#   get_os_short()        → Quick OS summary for short report
#   get_packages()        → List all installed packages (supports apt/rpm/pacman)
#   get_packages_count()  → Just the number of installed packages
#   get_users()           → Who is logged in + last 10 login entries
#   get_processes()       → Top 20 processes by CPU usage
#   get_services()        → All currently running system services
#   get_ports()           → All open/listening network ports
#   get_software()        → Calls all of the above (used for full report)
# ==============================================================================

# --- OS: Full Details ---
# Shows the full kernel version (uname -a) and reads /etc/os-release
# which holds the distribution name and version (e.g. Ubuntu 22.04).
get_os() {
    print_section "OS INFO"
    echo "[ Kernel & System ]"
    uname -a
    echo ""
    echo "[ Distribution ]"
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    else
        print_warning "/etc/os-release not found."
    fi
}

# --- OS: Short Summary ---
# Only the kernel version, architecture, and distro name+version.
# Used in the short report to keep it compact.
get_os_short() {
    echo "--- OS ---"
    echo "Kernel  : $(uname -r)"
    echo "Arch    : $(uname -m)"
    if [ -f /etc/os-release ]; then
        grep -E "^(NAME|VERSION)=" /etc/os-release | tr -d '"'
    fi
}

# --- Installed Packages: Full List ---
# Detects which package manager is installed and lists every package.
# Supports: dpkg (Debian/Ubuntu), rpm (RedHat/Fedora), pacman (Arch).
get_packages() {
    print_section "INSTALLED PACKAGES"
    if command -v dpkg &>/dev/null; then
        echo "[ Package Manager: dpkg/apt ]"
        # Only list properly installed packages (status starts with "ii")
        dpkg -l | grep "^ii" | awk '{print $2, $3}' | column -t
    elif command -v rpm &>/dev/null; then
        echo "[ Package Manager: rpm ]"
        rpm -qa --qf "%{NAME} %{VERSION}\n" | sort
    elif command -v pacman &>/dev/null; then
        echo "[ Package Manager: pacman ]"
        pacman -Q
    else
        print_warning "No supported package manager found."
    fi
}

# --- Installed Packages: Count Only ---
# Prints only the total number of packages — used in the short report.
get_packages_count() {
    echo "--- Installed Packages ---"
    if command -v dpkg &>/dev/null; then
        local count
        count=$(dpkg -l | grep -c "^ii")
        echo "Total packages (dpkg): $count"
    elif command -v rpm &>/dev/null; then
        local count
        count=$(rpm -qa | wc -l)
        echo "Total packages (rpm): $count"
    elif command -v pacman &>/dev/null; then
        local count
        count=$(pacman -Q | wc -l)
        echo "Total packages (pacman): $count"
    else
        echo "Package count: N/A"
    fi
}

# --- Logged-In Users ---
# Shows who is currently logged into the system using 'who'.
# Also shows the last 10 login events using 'last' (login history).
get_users() {
    print_section "LOGGED-IN USERS"
    who
    echo ""
    echo "[ Last Logins ]"
    if command -v last &>/dev/null; then
        last -n 10
    else
        echo "Command 'last' not available on this system."
    fi
}

# --- Running Processes: Top 20 by CPU ---
# Lists all running processes, sorted by CPU usage (highest first).
# Only shows the top 20 to keep the report readable.
get_processes() {
    print_section "RUNNING PROCESSES (Top 20 by CPU)"
    # --sort=-%cpu means: sort by CPU column, descending (highest first)
    # awk keeps the header line (NR==1) + the next 20 data lines (NR<=21)
    ps aux --sort=-%cpu | awk 'NR==1 || NR<=21'
}

# --- Running Services ---
# Lists all services currently in a "running" state.
# Uses systemctl on modern systems (systemd).
# Falls back to 'service --status-all' on older non-systemd systems.
get_services() {
    print_section "RUNNING SERVICES"
    if command -v systemctl &>/dev/null; then
        systemctl list-units --type=service --state=running --no-pager
    else
        print_warning "systemctl not available."
        # Older systems: show only services with a '+' (running) status
        service --status-all 2>/dev/null | grep "+"
    fi
}

# --- Open Ports ---
# Lists all TCP/UDP ports that the system is currently listening on.
# Uses 'ss' (modern) or falls back to 'netstat' (older systems).
# -t = TCP, -u = UDP, -l = listening only, -n = show numbers not names
get_ports() {
    print_section "OPEN PORTS"
    if command -v ss &>/dev/null; then
        ss -tuln
    elif command -v netstat &>/dev/null; then
        netstat -tuln
    else
        print_warning "Neither ss nor netstat available."
    fi
}

# --- Full Software Audit ---
# Runs ALL software checks in order.
# This is what gets called when generating the full report.
get_software() {
    get_os
    get_packages
    get_users
    get_processes
    get_services
    get_ports
}
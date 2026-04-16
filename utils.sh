#!/bin/bash
# ==============================================================================
# utils.sh — Shared utilities used by all other modules
#
# This file does two things:
#   1. Defines color variables so printed messages look nice in the terminal
#   2. Defines helper functions used everywhere (print_info, print_error, etc.)
#      and a CPU usage calculator
#
# Every other .sh file depends on this — so it must be loaded first.
# ==============================================================================

# --- Terminal Color Codes ---
# These make the terminal output colored and readable.
# NC = "No Color" — resets the color back to normal after each message.
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
BOLD="\e[1m"
NC="\e[0m" # Reset — always put this at the end of a colored string

# --- Print Functions ---
# Each function prints a message with a colored label prefix.
# Example output:  [INFO] Script started

# Blue [INFO] — for general information
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Green [SUCCESS] — when something worked correctly
print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Yellow [WARNING] — for non-fatal warnings that the user should notice
print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Red [ERROR] — for errors; writes to stderr (>&2) so it can be separated from normal output
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Red+Bold [ALERT] — for critical alerts like high CPU usage
print_cpu_alert() {
    echo -e "${RED}${BOLD}[ALERT]${NC} $1"
}

# Cyan bold section header — used to separate sections in a report or menu
print_section() {
    echo -e "\n${CYAN}${BOLD}===== $1 =====${NC}"
}

# --- CPU Usage Calculator ---
# Reads /proc/stat twice with a 0.5 second gap, then calculates usage.
# This is more reliable than 'top' or 'vmstat' across all Linux distros.
# Returns: integer between 0 and 100 (CPU % used)
get_cpu_usage() {
    # Read total CPU time and idle time at moment 1
    local cpu1 cpu2 idle1 idle2 total1 total2
    read -r cpu1 < <(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat)
    sleep 0.5
    # Read again 0.5 seconds later (moment 2)
    read -r cpu2 < <(awk '/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5}' /proc/stat)

    total1=$(echo "$cpu1" | awk '{print $1}')
    idle1=$(echo  "$cpu1" | awk '{print $2}')
    total2=$(echo "$cpu2" | awk '{print $1}')
    idle2=$(echo  "$cpu2" | awk '{print $2}')

    # Calculate how much CPU was used during that 0.5s window
    local diff_total diff_idle usage
    diff_total=$(( total2 - total1 ))
    diff_idle=$(( idle2 - idle1 ))

    # Avoid division by zero if the CPU didn't tick at all
    if [ "$diff_total" -eq 0 ]; then
        echo 0
    else
        usage=$(( 100 * (diff_total - diff_idle) / diff_total ))
        echo "$usage"
    fi
}
#!/bin/bash
# ==============================================================================
# PEOPLE'S DEMOCRATIC REPUBLIC OF ALGERIA
# Ministry of Higher Education and Scientific Research
# National School of Cyber Security
# Foundation Training Department
# ==============================================================================
# MINI-PROJECT – PART N°1
# "Design and Implementation of an Automated Hardware & Software Audit System
#  with Reporting and Remote Monitoring Capabilities"
# ==============================================================================
#
# main.sh — Entry point of the audit tool
#
# This is the only file the user runs directly: bash main.sh
#
# What it does:
#   1. Finds the folder where all the scripts live (SCRIPT_DIR)
#   2. Loads all modules (utils, log, security, hardware, software, report, email, remote)
#   3. Rotates the log file if it's too large
#   4. If called with --auto (by cron), runs silently and exits
#   5. Otherwise, shows the interactive menu
#
# Module load order matters:
#   utils.sh must be first (other modules use its color/print functions)
#   log.sh must be second (other modules call log_msg)
# ==============================================================================


# --- Resolve the absolute path of this script's folder ---
# BASH_SOURCE[0] is the path to this file, even when sourced.
# We convert it to an absolute path so all modules load correctly
# regardless of where the user runs the script from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_DIR   # Export so all child scripts and modules can use it


# --- Load all modules ---
# Each module is a separate .sh file in the same folder.
# We source them (not execute) so their functions become available here.
# If a module is missing, we stop immediately with a clear error.
for module in utils.sh log.sh security.sh hardware.sh software.sh report.sh email.sh remote.sh; do
    module_path="$SCRIPT_DIR/$module"
    if [ -f "$module_path" ]; then
        # shellcheck source=/dev/null
        source "$module_path"
    else
        echo -e "\e[31m[ERROR]\e[0m Module not found: $module_path"
        exit 1
    fi
done


# --- Rotate logs on startup ---
# If audit.log has grown beyond the size limit, archive it and start fresh.
# This keeps the logs folder from filling up over time.
rotate_logs
log_msg "Audit tool started"


# --- Cron Setup Helper ---
# This function is called when the user picks option 6 from the menu.
# It creates a wrapper script and registers it in the system's crontab
# to run the audit automatically every day at 4:00 AM.
#
# WHY A WRAPPER SCRIPT?
# The project folder path has a space: "/os project/"
# Cron cannot handle spaces in paths even when quoted.
# Solution: create a small wrapper at /tmp/sysaudit_cron_wrapper.sh
# (no space in that path), which cron calls safely.
# The wrapper then cd's into the project folder and runs main.sh --auto.
setup_cron() {
    local cron_time="0 4 * * *"   # Every day at 4:00 AM
    local cron_log="$SCRIPT_DIR/logs/cron.log"

    # Make sure the logs directory exists before writing the wrapper
    mkdir -p "$SCRIPT_DIR/logs"

    # Write the wrapper script to /tmp (no spaces in that path)
    local wrapper="/tmp/sysaudit_cron_wrapper.sh"
    cat > "$wrapper" <<WRAPPER
#!/bin/bash
cd "$(printf '%s' "$SCRIPT_DIR")"
bash "$(printf '%s' "$SCRIPT_DIR")/main.sh" --auto >> "$(printf '%s' "$cron_log")" 2>&1
WRAPPER
    chmod +x "$wrapper"   # Make it executable

    # This is the actual crontab line that will be added
    local cron_entry="$cron_time $wrapper"

    # Show what's currently in the crontab before making changes
    echo ""
    print_info "Current crontab entries:"
    crontab -l 2>/dev/null || echo "(no crontab for $USER)"
    echo ""

    print_info "Adding cron job: every day at 4:00 AM"
    echo "  Wrapper : $wrapper"
    echo "  Schedule: $cron_time"
    echo "  Log     : $cron_log"
    echo ""
    read -r -p "$(echo -e "${CYAN}Confirm adding cron job? [y/N]: ${NC}")" confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # Before adding the new entry, remove all old audit cron lines.
        # This prevents duplicates if the user runs setup multiple times.
        (crontab -l 2>/dev/null | grep -v "sysaudit_cron_wrapper\|main\.sh --auto"; echo "$cron_entry") | crontab -
        if [ $? -eq 0 ]; then
            print_success "Cron job added successfully (runs every day at 4:00 AM)."
            print_info  "Wrapper script: $wrapper"
            print_info  "Cron log: $cron_log"
            log_msg "Cron job configured: $cron_entry"
        else
            print_error "Failed to add cron job."
        fi
    else
        print_warning "Cron setup cancelled."
    fi
}


# --- Automated (Cron) Mode ---
# When cron fires at 4:00 AM, it runs: bash main.sh --auto
# This block detects the --auto flag, runs silently (no menu), then exits.
# No user interaction — just generate the report and quit.
if [ "$1" = "--auto" ]; then
    log_msg "Running in automated (cron) mode"
    generate_full                          # Generate all 4 report formats
    generate_hash "$FULL_REPORT"           # Hash the .txt report for integrity
    log_msg "Automated full report generated in $REPORT_DIR"
    exit 0
fi


# --- Interactive Menu ---
# This loop shows the menu and waits for the user to pick an option.
# 'select' displays a numbered list; $REPLY holds the number the user typed.
# The loop restarts after each action so the user can do multiple things.
while true; do
    echo ""
    print_section "LINUX SYSTEM AUDIT TOOL"
    PS3="$(echo -e "\n${CYAN}Choose an option: ${NC}")"
    options=(
        "Generate Short Report"             # Option 1 — quick summary report
        "Generate Full Report"              # Option 2 — full hardware + software report
        "Send Report by Email"              # Option 3 — email a report to someone
        "Compare Last Two Reports"          # Option 4 — diff two reports to see changes
        "Verify Report Integrity (Hash Check)"  # Option 5 — check if a report was modified
        "Setup Cron Job (Auto-Schedule)"    # Option 6 — schedule daily auto-reports
        "Run Remote Audit"                  # Option 7 — audit another machine over SSH
        "Exit"                              # Option 8 — quit the tool
    )

    select choice in "${options[@]}"; do
        case "$REPLY" in
            1)  # Short report: quick overview of the most important system info
                generate_short
                log_msg "Short report generated in $REPORT_DIR"
                break
                ;;
            2)  # Full report: everything — hardware, software, processes, ports
                generate_full
                generate_hash "$FULL_REPORT"   # Always hash the full report
                log_msg "Full report generated in $REPORT_DIR"
                break
                ;;
            3)  # Send a report by email
                # Let the user override the default email address
                read -r -p "Recipient Email [default: mohamednessissen07@gmail.com]: " user_email
                if [ -n "$user_email" ]; then
                    export AUDIT_EMAIL="$user_email"
                else
                    export AUDIT_EMAIL="mohamednessissen07@gmail.com"
                fi

                # Ask whether to send short or full report
                read -r -p "Send [S]hort or [F]ull report? (s/f) [default: f]: " report_choice
                send_target=""

                if [[ "$report_choice" =~ ^[Ss]$ ]]; then
                    # If short report was never generated this session, generate it now
                    if [ -z "$SHORT_REPORT" ] || [ ! -f "$SHORT_REPORT" ]; then
                        print_info "Short report not found. Generating now..."
                        generate_short
                    fi
                    send_target="$SHORT_REPORT"
                else
                    # Default: send full report; generate it first if needed
                    if [ -z "$FULL_REPORT" ] || [ ! -f "$FULL_REPORT" ]; then
                        print_info "Full report not found. Generating now..."
                        generate_full
                    fi
                    send_target="$FULL_REPORT"
                fi

                send_email "$send_target"
                break
                ;;
            4)  # Compare two reports: shows what changed between them
                compare_reports
                log_msg "Report comparison performed"
                break
                ;;
            5)  # Verify a report's hash to detect tampering
                verify_hash
                log_msg "Report integrity check performed"
                break
                ;;
            6)  # Schedule the audit to run automatically at 4:00 AM
                setup_cron
                break
                ;;
            7)  # SSH into a remote machine, run the audit there, and download the results
                run_remote_audit
                break
                ;;
            8)  # Exit the tool cleanly
                print_warning "Exiting. Goodbye!"
                log_msg "Audit tool exited"
                exit 0
                ;;
            *)  # Catch invalid input
                print_error "Invalid option '$REPLY'. Please choose 1-${#options[@]}."
                ;;
        esac
    done
done
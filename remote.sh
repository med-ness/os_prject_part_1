#!/bin/bash
# ==============================================================================
# remote.sh — Run an audit on a remote machine over SSH
#
# This file provides one function: run_remote_audit()
#
# What it does step by step:
#   1. Asks the user for the remote machine's username and IP/hostname
#   2. Connects via SSH and creates a clean temp folder on the remote machine
#   3. Copies all .sh audit modules to the remote machine using scp
#   4. Runs main.sh --auto on the remote machine (generates the report there)
#   5. Downloads the generated reports back to your local machine
#      into: reports/remote/
#
# Requirements:
#   - SSH access to the remote machine (password or key-based)
#   - Bash available on the remote machine
#
# Note: The remote machine does NOT need to have the audit tool pre-installed.
#       We upload the scripts each time before running.
# ==============================================================================

# Where remote reports will be saved locally after being pulled back
# Falls back to ./reports/remote if REPORT_DIR is not set
LOCAL_REMOTE_DIR="${REPORT_DIR:-./reports}/remote"

# --- Run a Full Audit on a Remote Machine ---
run_remote_audit() {
    print_section "REMOTE AUDIT SYSTEM"

    # Step 0: Ask the user for the target machine details
    read -r -p "Enter Remote Target User [default: root]: " user_in
    read -r -p "Enter Remote Host IP/Domain: " host_in

    # Host is required — we can't connect without it
    if [ -z "$host_in" ]; then
        print_error "Remote Host cannot be empty. Aborting."
        return 1
    fi

    local r_user="${user_in:-root}"   # Default to root if no user given
    local r_host="$host_in"

    print_info "Connecting to $r_user@$r_host ..."

    # Step 1: Clean and create a temp folder on the remote machine
    # We use /tmp/audit_scripts because every Linux system has /tmp and it's writable
    ssh "$r_user@$r_host" "rm -rf /tmp/audit_scripts && mkdir -p /tmp/audit_scripts" || {
        print_error "Failed to connect or prepare remote directory. Ensure SSH key/password is correct."
        return 1
    }

    # Step 2: Copy all audit script files to the remote machine
    # scp -q = quiet mode (no progress output)
    # We copy all .sh files from the local project folder
    print_info "Pushing latest audit modules..."
    scp -q "$SCRIPT_DIR"/*.sh "$r_user@$r_host:/tmp/audit_scripts/" || {
        print_error "Failed to copy scripts to remote host."
        return 1
    }

    # Step 3: Run the audit on the remote machine in automated mode
    # --auto skips the interactive menu and generates a full report directly
    print_info "Running automated audit process on remote host..."
    ssh "$r_user@$r_host" "cd /tmp/audit_scripts && bash ./main.sh --auto" || {
        print_error "Remote audit execution failed."
        return 1
    }

    # Step 4: Pull the generated reports back to the local machine
    # We create matching subdirectories for each format
    mkdir -p "$LOCAL_REMOTE_DIR/txt" "$LOCAL_REMOTE_DIR/html" "$LOCAL_REMOTE_DIR/json" "$LOCAL_REMOTE_DIR/pdf"
    print_info "Retrieving full report components from remote host (1 password required)..."

    # We use a tar pipe to download all report files in one SSH connection.
    # On the remote side: we check two possible locations for the reports
    #   - /var/log/sys_audit/  (if the remote had root access)
    #   - /tmp/audit_scripts/reports/  (our temp folder fallback)
    # The tar output is piped directly into tar on the local side to extract.
    ssh "$r_user@$r_host" 'if [ -d /var/log/sys_audit/txt ]; then tar -cf - -C /var/log/sys_audit .; else tar -cf - -C /tmp/audit_scripts/reports .; fi' 2>/dev/null | tar -xf - -C "$LOCAL_REMOTE_DIR/" 2>/dev/null

    print_success "Remote reports pulled mapping to: $LOCAL_REMOTE_DIR"
    log_msg "Remote audit completed for: $r_host"
}
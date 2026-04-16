#!/bin/bash
# ==============================================================================
# log.sh — Logging system for the audit tool
#
# This file handles two things:
#   1. Writing log messages to a log file (audit.log)
#   2. Rotating the log file when it gets too large
#
# All other modules call log_msg() to record what they did.
# Logs are always written to an absolute path so cron jobs find them correctly.
# ==============================================================================

# --- Log File Setup ---
# We resolve the directory of this script at load time so the path is
# always absolute — this is critical when cron runs the tool from a
# different working directory.
_LOG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$_LOG_SCRIPT_DIR/logs"         # Absolute path to logs folder
LOG_FILE="$LOG_DIR/audit.log"           # Main log file
MAX_LOG_SIZE=100000                      # Rotate when file exceeds 100 KB
MAX_LOG_BACKUPS=5                        # Keep at most 5 old rotated log files

# Create the logs folder if it doesn't exist yet
mkdir -p "$LOG_DIR"

# --- log_msg: Write a timestamped message to the log file ---
# Usage:  log_msg "Your message here"
# Output: 2026-04-15 04:00:01 - Your message here
log_msg() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# --- rotate_logs: Keep the log file from growing too large ---
# Called once at startup (from main.sh).
# If audit.log is bigger than MAX_LOG_SIZE bytes:
#   - Renames it to audit.log.<timestamp>.old  (a backup)
#   - Creates a fresh empty audit.log
#   - Deletes the oldest backups if there are more than MAX_LOG_BACKUPS
rotate_logs() {
    # Nothing to rotate if the log file doesn't exist yet
    if [ ! -f "$LOG_FILE" ]; then
        return 0
    fi

    # Get the current size in bytes
    local size
    size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)

    if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
        # Save the old log with a timestamp so we don't lose it
        local backup="$LOG_FILE.$(date +%Y%m%d_%H%M%S).old"
        mv "$LOG_FILE" "$backup"
        touch "$LOG_FILE"   # Create a fresh empty log
        print_info "Log rotated: backup saved as $(basename "$backup")"
        log_msg "Log rotated — previous log: $backup"

        # Count how many old backups exist
        local old_count
        old_count=$(ls -1 "$LOG_DIR"/audit.log.*.old 2>/dev/null | wc -l)

        # If there are too many backups, delete the oldest ones
        if [ "$old_count" -gt "$MAX_LOG_BACKUPS" ]; then
            ls -1t "$LOG_DIR"/audit.log.*.old | tail -n +"$((MAX_LOG_BACKUPS + 1))" | xargs rm -f
            print_info "Old log backups trimmed (kept last $MAX_LOG_BACKUPS)."
        fi
    fi
}
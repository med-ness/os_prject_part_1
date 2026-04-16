#!/bin/bash
# ==============================================================================
# email.sh — Email sending functions for the audit tool
#
# This file provides two ways to send emails:
#   1. send_email()        → Sends a full report file as the email body
#   2. send_alert_email()  → Sends a short alert when CPU usage is too high
#
# Supported mail clients (checked in order):
#   - msmtp    (lightweight, good for automated use — preferred)
#   - mail     (standard mailutils, works on most systems)
#
# If neither is installed, the user is told how to install one.
#
# Internal helpers:
#   _check_mail_cmd() → Checks that at least one mail client is available
#   _do_send()        → Handles the actual sending (for both msmtp and mail)
# ==============================================================================

# --- Internal: Check that a mail command exists ---
# Returns 0 (OK) if msmtp or mail is found, returns 1 (error) if neither is.
# This is called before every send attempt to give a clear error message.
_check_mail_cmd() {
    if command -v msmtp &>/dev/null; then
        return 0
    elif command -v mail &>/dev/null; then
        return 0
    else
        print_error "No mail client found."
        print_info  "Install msmtp: sudo apt install msmtp"
        print_info  "Or install mailutils: sudo apt install mailutils"
        return 1
    fi
}

# --- Internal: Actually send the email ---
# This does the low-level work of formatting and sending the email.
#
# Arguments:
#   $1 = Subject line
#   $2 = Recipient email address
#   $3 = Body text (optional — if empty, reads from stdin)
#
# msmtp: needs a properly formatted email header block piped to it
# mail:  simpler — just pipe the body and pass the subject as a flag
_do_send() {
    local subject="$1"
    local recipient="$2"
    local raw_body="$3"      # Can be empty; in that case we read from stdin

    if command -v msmtp &>/dev/null; then
        {
            # msmtp requires a full email header before the body
            echo "From: System Audit <$recipient>"
            echo "Subject: $subject"
            echo "To: $recipient"
            echo ""   # Blank line separates headers from body (RFC 2822 standard)
            if [ -n "$raw_body" ]; then
                echo "$raw_body"
            else
                cat   # Read the body from stdin (used when piping a file in)
            fi
        } | msmtp "$recipient"
        return $?

    elif command -v mail &>/dev/null; then
        if [ -n "$raw_body" ]; then
            echo "$raw_body" | mail -s "$subject" "$recipient"
        else
            mail -s "$subject" "$recipient"   # Reads body from stdin
        fi
        return $?
    fi

    return 1   # Should never reach here since _check_mail_cmd ran first
}

# --- Send Report by Email ---
# Emails the content of a report file to a recipient.
# If no recipient is given, uses the AUDIT_EMAIL environment variable,
# or falls back to the default address below.
#
# Usage:
#   send_email "/path/to/report.txt"
#   send_email "/path/to/report.txt" "someone@example.com"
send_email() {
    local file="$1"
    # Check for recipient in this order: argument → $AUDIT_EMAIL → default
    local recipient="${2:-${AUDIT_EMAIL:-"mohamednessissen07@gmail.com"}}"

    # Make sure the report file actually exists
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        print_error "send_email: Invalid or missing report file."
        return 1
    fi

    _check_mail_cmd || return 1

    # Build the subject line with the hostname and current date/time
    local subject="System Audit Report - $(hostname) - $(date '+%Y-%m-%d %H:%M')"

    print_info "Dispatching email to $recipient ..."
    # Pipe the report file into _do_send (< "$file" = read from file as stdin)
    _do_send "$subject" "$recipient" "" < "$file"

    if [ $? -eq 0 ]; then
        print_success "Report sent successfully to $recipient"
        log_msg "Email sent: $file -> $recipient"
    else
        print_error "Failed to send email. Check your mail/msmtp configuration."
        log_msg "EMAIL FAILED: $file -> $recipient"
        return 1
    fi
}

# --- Send CPU Alert Email ---
# Sends a short urgent email when CPU usage exceeds 80%.
# Called automatically inside generate_full() if the alert threshold is hit.
#
# Usage: send_alert_email 92   (pass the CPU % as a number)
send_alert_email() {
    local cpu_value="$1"
    local recipient="${AUDIT_EMAIL:-"mohamednessissen07@gmail.com"}"

    if [ -z "$cpu_value" ]; then
        print_error "send_alert_email: No CPU value provided."
        return 1
    fi

    _check_mail_cmd || return 1

    local subject="[ALERT] High CPU Usage on $(hostname) - ${cpu_value}%"

    # Build a clear plain-text alert body
    local body
    body=$(cat <<EOF
SYSTEM ALERT
============
Hostname   : $(hostname)
Date/Time  : $(date '+%Y-%m-%d %H:%M:%S')
Alert Type : High CPU Usage

CPU Usage  : ${cpu_value}%
Threshold  : 80%

This is an automated alert from the System Audit Script.
EOF
)

    _do_send "$subject" "$recipient" "$body"

    if [ $? -eq 0 ]; then
        print_cpu_alert "Alert email sent to $recipient (CPU: ${cpu_value}%)"
        log_msg "ALERT EMAIL sent: CPU=${cpu_value}% -> $recipient"
    else
        print_error "Failed to send alert email."
        log_msg "ALERT EMAIL FAILED: CPU=${cpu_value}% -> $recipient"
        return 1
    fi
}
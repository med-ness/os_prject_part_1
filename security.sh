#!/bin/bash
# ==============================================================================
# security.sh — Report integrity and comparison tools
#
# This file handles three security-related features:
#   1. generate_hash()   → Creates a SHA-256 fingerprint of a report file.
#                          If the file is later changed, the hash won't match.
#   2. verify_hash()     → Checks that a report file hasn't been modified
#                          since it was generated.
#   3. compare_reports() → Shows what changed between two report files
#                          (like a git diff for your audit reports).
#
# Internal helper:
#   _select_report_file() → Lets the user pick a report from the list
#                           interactively (used by verify_hash and compare_reports).
# ==============================================================================

# --- Internal Helper: Let the user pick a report file ---
# Scans the reports/txt/ folder, shows a numbered list, and waits for
# the user to enter a number. Stores the chosen file path in the global
# variable SELECTED_REPORT_FILE so the caller can use it.
_select_report_file() {
    local report_dir="${REPORT_DIR:-./reports}/txt"
    local prompt="$1"
    SELECTED_REPORT_FILE=""

    # Make sure the reports folder exists
    if [ ! -d "$report_dir" ]; then
        print_error "Report directory not found: $report_dir"
        return 1
    fi

    # Collect all .txt files in the folder into an array
    local files=()
    shopt -s nullglob   # If no files match, the glob returns nothing (not the literal "*.txt")
    for f in "$report_dir"/*.txt; do
        files+=("$f")
    done
    shopt -u nullglob   # Turn nullglob back off

    if [ ${#files[@]} -eq 0 ]; then
        print_error "No reports found in $report_dir"
        return 1
    fi

    # Print the numbered list of files
    echo -e "\n${CYAN}$prompt${NC}"
    local i=1
    for f in "${files[@]}"; do
        echo "  $i) $(basename "$f")"
        ((i++))
    done

    # Wait for a valid number from the user
    local choice
    while true; do
        read -r -p "Select a file [1-${#files[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ]; then
            SELECTED_REPORT_FILE="${files[$((choice-1))]}"
            return 0
        fi
        print_error "Invalid selection. Please try again."
    done
}

# --- Hash Generation ---
# Creates a SHA-256 checksum of the given report file and saves it
# as <filename>.hash next to the report.
#
# SHA-256 produces a unique "fingerprint" of the file.
# If even one character changes later, the fingerprint will be different.
#
# Usage: generate_hash "/path/to/report.txt"
generate_hash() {
    local file="$1"

    # Make sure the file actually exists before trying to hash it
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        print_error "generate_hash: Invalid file."
        return 1
    fi

    # sha256sum writes:  <hash>  <filename>  →  saved to <filename>.hash
    sha256sum "$file" > "${file}.hash"
    print_success "Hash saved to ${file}.hash"
}

# --- Hash Verification ---
# Checks if a report file has been modified since it was hashed.
# If no file is given, it shows an interactive list for the user to pick one.
#
# How it works:
#   sha256sum -c reads the .hash file, re-hashes the report, and compares.
#   If they match → file is unchanged (PASSED).
#   If they differ → file was modified (FAILED).
#
# Usage: verify_hash "/path/to/report.txt"
#        verify_hash   (no argument = interactive mode)
verify_hash() {
    local file="$1"

    # If no file is given, let the user choose one interactively
    if [ -z "$file" ]; then
        _select_report_file "Select a report to verify:" || return 1
        file="$SELECTED_REPORT_FILE"
    fi

    local hash_file="${file}.hash"

    if [ ! -f "$file" ]; then
        print_error "verify_hash: Report file not found: $file"
        return 1
    fi

    if [ ! -f "$hash_file" ]; then
        print_error "verify_hash: Hash file not found: $hash_file"
        print_info "Recommendation: Generate a full report first to create a hash."
        return 1
    fi

    # Re-hash the file and compare against the saved hash
    if sha256sum -c "$hash_file" &>/dev/null; then
        print_success "Integrity check PASSED for $(basename "$file")"
        return 0
    else
        print_error "Integrity check FAILED for $(basename "$file") — file may have been modified!"
        return 1
    fi
}

# --- Report Comparison ---
# Compares two report files to show what changed between audits.
# Useful to detect if new packages were installed, ports opened, etc.
#
# How it works:
#   1. User picks the OLD report (baseline)
#   2. User picks the NEW report (latest)
#   3. 'diff' compares them line by line
#   4. Differences are saved to reports/txt/diff_<timestamp>.txt
#   5. A preview of the first 20 difference lines is shown
#
# Lines starting with '<' were removed, lines starting with '>' were added.
compare_reports() {
    local report_dir="${REPORT_DIR:-./reports}"
    local diff_file="$report_dir/txt/diff_$(date +%Y-%m-%d_%H-%M-%S).txt"
    mkdir -p "$report_dir/txt"

    print_info "Interactive Report Comparison"

    # Pick the old (reference) report
    _select_report_file "Select the OLD (baseline) report:" || return 1
    local old_file="$SELECTED_REPORT_FILE"

    # Pick the new (latest) report
    _select_report_file "Select the NEW (target) report:" || return 1
    local new_file="$SELECTED_REPORT_FILE"

    # Warn if the user picked the same file twice — the diff will be empty
    if [ "$old_file" == "$new_file" ]; then
        print_warning "Comparing a file to itself will result in no changes."
    fi

    print_info "Comparing reports:"
    echo "  OLD : $(basename "$old_file")"
    echo "  NEW : $(basename "$new_file")"
    echo "-------------------------------------------"

    # Run the diff and save the result
    diff "$old_file" "$new_file" > "$diff_file"

    if [ -s "$diff_file" ]; then
        # -s checks if the file is non-empty (changes were found)
        print_warning "Changes detected between reports!"
        echo "  Diff saved to: $diff_file"
        echo ""
        echo "--- Preview (first 20 lines) ---"
        head -20 "$diff_file"
    else
        # Empty diff file means the two reports are identical
        print_success "No changes detected between the selected reports."
        rm -f "$diff_file"   # No need to keep an empty diff file
    fi
}
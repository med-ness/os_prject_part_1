#!/bin/bash
# ==============================================================================
# report.sh — Report generation in 4 formats: TXT, HTML, JSON, PDF
#
# This file generates audit reports and saves them to organized subfolders:
#   reports/txt/   → plain text, easy to read in terminal
#   reports/html/  → styled web page, open in a browser
#   reports/json/  → structured data, easy to parse by other tools
#   reports/pdf/   → printable document (requires LibreOffice or wkhtmltopdf)
#
# Two types of reports:
#   generate_short() → Quick overview: OS, CPU, RAM, Disk, Package count
#   generate_full()  → Everything: full hardware + software audit
#
# After each full report, a .hash file is also created (via security.sh)
# to detect if the file was modified later.
# ==============================================================================

# --- Report Storage Location ---
# Always uses an absolute path so cron jobs write reports to the right place.
# Tries SCRIPT_DIR (exported by main.sh) first, then resolves itself as fallback.
_REPORT_SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
REPORT_DIR="$_REPORT_SCRIPT_DIR/reports"

# Create all format folders upfront so there's no missing-directory error later
mkdir -p "$REPORT_DIR/txt" "$REPORT_DIR/html" "$REPORT_DIR/json" "$REPORT_DIR/pdf"
export REPORT_DIR

# These variables hold the path of the most recently generated report.
# They are set (or updated) each time generate_short() or generate_full() runs.
SHORT_REPORT=""
FULL_REPORT=""

# --- escape_json: Make text safe for JSON ---
# Removes terminal color codes (ANSI escape sequences) from text,
# then wraps it in proper JSON string escaping using jq.
# Used before embedding report content inside a .json file.
escape_json() {
    printf "%s" "$1" | sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" | jq -R -s '.' | sed -e 's/^"//' -e 's/"$//'
}

# --- strip_ansi: Remove terminal color codes ---
# Color codes like \e[32m look fine in a terminal but appear as garbage
# in text files and PDFs. This filter strips them out.
# Used as a pipe:  some_command | strip_ansi
strip_ansi() {
    sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g"
}

# --- generate_text_pdf_html: Build a minimal HTML page for PDF conversion ---
# We can't convert plain text directly to PDF easily.
# Instead we wrap the text in a simple HTML page with monospace font,
# then convert that HTML to PDF using LibreOffice or wkhtmltopdf.
# This function takes the report text and outputs the HTML to stdout.
generate_text_pdf_html() {
    local CONTENT="$1"

    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<style>
    @page { margin: 1.5cm; }
    body { font-family: "Liberation Mono", Courier, monospace; color: #000; font-size: 10pt; line-height: 1.2; background: #fff; margin: 0; padding: 0; }
    pre { white-space: pre-wrap; word-wrap: break-word; margin: 0; padding: 0; font-family: inherit; }
</style>
</head>
<body>
<pre>$CONTENT</pre>
</body>
</html>
EOF
}

# --- Short Report Generator ---
# Generates a quick system summary and saves it in TXT, HTML, JSON, and PDF formats.
# Covers: OS info, CPU, RAM, Disk, installed package count, and CPU usage/alert.
# Files are saved as:  short_<timestamp>.<ext>  in reports/<format>/
generate_short() {
    local DATE HOST UPTIME
    DATE=$(date +"%Y-%m-%d_%H-%M-%S")
    HOST=$(hostname)
    UPTIME=$(uptime -p 2>/dev/null || uptime)
    
    mkdir -p "$REPORT_DIR/txt" "$REPORT_DIR/html" "$REPORT_DIR/json" "$REPORT_DIR/pdf"
    SHORT_REPORT_TXT="$REPORT_DIR/txt/short_${DATE}.txt"
    SHORT_REPORT_HTML="$REPORT_DIR/html/short_${DATE}.html"
    SHORT_REPORT_JSON="$REPORT_DIR/json/short_${DATE}.json"
    SHORT_REPORT="$SHORT_REPORT_TXT"

    print_info "Creating short reports (txt, html, json, pdf) in $REPORT_DIR ..."

    # Dashboard-like Extraction
    local k_model k_ram k_proc k_ports k_disk k_pkg os_kernel auditor
    k_model=$(lscpu 2>/dev/null | grep -i "^Model name" | cut -d':' -f2 | xargs | strip_ansi)
    [ -z "$k_model" ] && k_model="Unknown CPU"
    k_ram=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
    k_proc=$(ps aux 2>/dev/null | tail -n +2 | wc -l)
    k_ports=$(ss -tuln 2>/dev/null | grep -c "LISTEN")
    k_disk=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}')
    k_pkg=$( (dpkg-query -f '.\n' -W 2>/dev/null || rpm -qa 2>/dev/null || pacman -Q 2>/dev/null) | wc -l)
    os_kernel=$(uname -r)
    auditor="$USER"

    local os_info cpu_info ram_info disk_info pkg_info cpu_usage cpu_alert=""
    os_info="Kernel  : $(uname -r)\nArch    : $(uname -m)\n$(cat /etc/os-release | grep -E '^(NAME|VERSION)=')"
    cpu_info="$(lscpu | grep -E '^(Architecture|CPU\(s\):|Model name:|Thread\(s\) per core:|Core\(s\) per socket:|CPU\(s\) scaling MHz:)')"
    ram_info="$(free -h | grep Mem)"
    disk_info="$(df -h / | tail -1)"
    pkg_info="Total packages (dpkg): $( (dpkg-query -f '.\n' -W 2>/dev/null || rpm -qa 2>/dev/null || pacman -Q 2>/dev/null) | wc -l)"
    cpu_usage=$(get_cpu_usage)
    if [ "$cpu_usage" -gt 80 ]; then
        cpu_alert="WARNING: HIGH CPU USAGE: ${cpu_usage}%"
    fi

    local report_content
    report_content=$(cat <<EOF
========================================
        SYSTEM AUDIT - SHORT REPORT     
========================================
Date     : $(date '+%Y-%m-%d %H:%M:%S')
Hostname : $HOST
Uptime   : $UPTIME
========================================

--- OS ---
$os_info

--- CPU ---
$cpu_info

--- RAM ---
$ram_info

--- Disk (/) ---
$disk_info

--- Installed Packages ---
$pkg_info

--- CPU Usage ---
Current CPU Usage: ${cpu_usage}%
$cpu_alert

========================================
End of Short Report
========================================
EOF
)

    echo "$report_content" > "$SHORT_REPORT_TXT"

    {
        cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Short Audit - $HOST</title>
<style>
  :root { --bg-main: #0d1117; --bg-card: #161b22; --border-color: #30363d; --text-primary: #c9d1d9; --text-secondary: #8b949e; }
  body { background-color: var(--bg-main); color: var(--text-primary); font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif; margin: 0; padding: 20px 40px; }
  .header { display: flex; flex-direction: column; gap: 10px; margin-bottom: 20px; border-bottom: 1px solid var(--border-color); padding-bottom: 20px;}
  .header h1 { margin: 0; font-size: 24px; color: #fff;}
  .badge { background: #6e7681; border-radius: 2em; padding: 2px 10px; font-size: 12px; font-weight: bold; border: 1px solid rgba(110,118,129,0.4); display:inline-block; }
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-bottom: 30px;}
  .card { background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 8px; padding: 20px; display: flex; flex-direction: column; justify-content: center;}
  .card-icon { font-size: 20px; margin-bottom: 15px; }
  .card-value { font-size: 22px; font-weight: 600; color: #fff; margin-bottom: 5px; line-height: 1.2;}
  .card-label { font-size: 11px; text-transform: uppercase; color: var(--text-secondary); font-weight: 600; letter-spacing: 0.5px;}
  details { background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 6px; overflow: hidden; margin-bottom: 10px;}
  summary { padding: 15px 20px; cursor: pointer; font-weight: 600; color: #e6edf3; display: flex; align-items: center; border-bottom: 1px solid transparent;}
  summary::-webkit-details-marker { display: none; }
  details[open] summary { border-bottom: 1px solid var(--border-color); }
  details pre { margin: 0; padding: 20px; font-family: monospace; font-size: 13px; color: var(--text-secondary); overflow-x: auto;}
</style>
</head>
<body>
  <div class="header">
    <div style="color:var(--text-secondary); font-size:12px; font-weight:600; text-transform:uppercase;">🛡️ Security Audit Report</div>
    <h1>Linux System Audit</h1>
    <div style="font-size: 14px; color: var(--text-secondary);">SysAudit v1.0 <span class="badge">SHORT REPORT</span></div>
  </div>
  <div class="cards">
    <div class="card" style="grid-column: span 2;"><div class="card-icon">🖥️</div><div class="card-value">$k_model</div><div class="card-label">CPU MODEL</div></div>
    <div class="card"><div class="card-icon">🧠</div><div class="card-value">$k_ram</div><div class="card-label">TOTAL RAM</div></div>
    <div class="card"><div class="card-icon">💻</div><div class="card-value">${k_proc}</div><div class="card-label">PROCESSES</div></div>
    <div class="card"><div class="card-icon">💾</div><div class="card-value">$k_disk</div><div class="card-label">ROOT DISK USAGE</div></div>
  </div>
  <details open><summary>📋 Short Details</summary><pre>$report_content</pre></details>
</body>
</html>
EOF
    } > "$SHORT_REPORT_HTML"

    {
        cat <<EOF
{
  "report_type": "short", "date": "$(date '+%Y-%m-%d %H:%M:%S')", "hostname": "$HOST", "uptime": "$UPTIME",
  "content": "$(escape_json "$report_content")"
}
EOF
    } > "$SHORT_REPORT_JSON"

    SHORT_REPORT_PDF="$REPORT_DIR/pdf/short_${DATE}.pdf"
    local pdf_temp_html="$REPORT_DIR/html/short_${DATE}_pdf_temp.html"
    
    generate_text_pdf_html "$report_content" > "$pdf_temp_html"

    if command -v libreoffice &>/dev/null; then
        libreoffice --headless --convert-to pdf "$pdf_temp_html" --outdir "$REPORT_DIR/pdf" &>/dev/null
        mv "$REPORT_DIR/pdf/short_${DATE}_pdf_temp.pdf" "$SHORT_REPORT_PDF" 2>/dev/null
    elif command -v wkhtmltopdf &>/dev/null; then
        wkhtmltopdf -q "$pdf_temp_html" "$SHORT_REPORT_PDF" 2>/dev/null
    elif command -v pandoc &>/dev/null; then
        pandoc "$pdf_temp_html" -o "$SHORT_REPORT_PDF" 2>/dev/null
    elif command -v ps2pdf &>/dev/null && command -v enscript &>/dev/null; then
        enscript -B -M A4 "$SHORT_REPORT_TXT" -p - 2>/dev/null | ps2pdf - "$SHORT_REPORT_PDF" 2>/dev/null
    fi

    # Cleanup temp PDF-HTML if it exists
    [ -f "$pdf_temp_html" ] && rm "$pdf_temp_html"

    export SHORT_REPORT
}

# --- Full Report Generator ---
# Generates a complete, detailed audit of the system.
# Covers everything hardware.sh and software.sh collect:
#   hardware: CPU, GPU, RAM, Disk, Network, Motherboard, USB
#   software: OS, Packages, Users, Processes (top 20), Services, Open Ports
#
# Also checks CPU usage and sends an alert email if it's above 80%.
# Files are saved as:  full_<timestamp>.<ext>  in reports/<format>/
# The .txt file is also hashed after generation (by main.sh) for integrity.
generate_full() {
    local DATE HOST UPTIME
    DATE=$(date +"%Y-%m-%d_%H-%M-%S")
    HOST=$(hostname)
    UPTIME=$(uptime -p 2>/dev/null || uptime)
    
    mkdir -p "$REPORT_DIR/txt" "$REPORT_DIR/html" "$REPORT_DIR/json" "$REPORT_DIR/pdf"
    FULL_REPORT_TXT="$REPORT_DIR/txt/full_${DATE}.txt"
    FULL_REPORT_HTML="$REPORT_DIR/html/full_${DATE}.html"
    FULL_REPORT_JSON="$REPORT_DIR/json/full_${DATE}.json"
    FULL_REPORT="$FULL_REPORT_TXT"

    print_info "Creating full Dashboard reports in $REPORT_DIR (this may take a moment)..."

    # Dashboard Metrics
    local k_model k_ram k_proc k_ports k_disk k_pkg os_kernel auditor
    k_model=$(lscpu 2>/dev/null | grep -i "^Model name" | cut -d':' -f2 | xargs | strip_ansi)
    [ -z "$k_model" ] && k_model="Unknown CPU"
    k_ram=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
    k_proc=$(ps aux 2>/dev/null | tail -n +2 | wc -l)
    k_ports=$(ss -tuln 2>/dev/null | grep -c "LISTEN")
    k_disk=$(df -h / 2>/dev/null | awk 'NR==2 {print $5}')
    k_pkg=$( (dpkg-query -f '.\n' -W 2>/dev/null || rpm -qa 2>/dev/null || pacman -Q 2>/dev/null) | wc -l)
    os_kernel=$(uname -r)
    auditor="$USER"

    # Deep Data
    local hw_data sw_data cpu_usage cpu_alert="" alert_tag=""
    hw_data=$(get_hardware | strip_ansi)
    sw_data=$(get_software | strip_ansi)
    cpu_usage=$(get_cpu_usage)
    if [ "$cpu_usage" -gt 80 ]; then
        cpu_alert="ALERT: HIGH CPU USAGE: ${cpu_usage}%"
        alert_tag="alert"
        if declare -f send_alert_email > /dev/null; then
            send_alert_email "$cpu_usage"
        fi
    else
        cpu_alert="CPU usage is normal."
    fi

    local report_content
    report_content=$(cat <<EOF
========================================
        SYSTEM AUDIT - FULL REPORT      
========================================
Date     : $(date '+%Y-%m-%d %H:%M:%S')
Hostname : $HOST
Uptime   : $UPTIME
========================================

########################################
#          HARDWARE AUDIT              #
########################################
$hw_data

########################################
#          SOFTWARE AUDIT              #
########################################
$sw_data

===== CPU ALERT CHECK =====
Current CPU Usage: ${cpu_usage}%
$cpu_alert

========================================
End of Full Report
========================================
EOF
)

    echo "$report_content" > "$FULL_REPORT_TXT"

    {
        cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Full Security Audit - $HOST</title>
<style>
  :root { --bg-main: #0d1117; --bg-card: #161b22; --border-color: #30363d; --text-primary: #c9d1d9; --text-secondary: #8b949e; --accent: #58a6ff; }
  body { background-color: var(--bg-main); color: var(--text-primary); font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif; margin: 0; padding: 20px 40px; }
  .header { display: flex; flex-direction: column; gap: 10px; margin-bottom: 30px; border-bottom: 1px solid var(--border-color); padding-bottom: 20px;}
  .header h1 { margin: 0; font-size: 24px; color: #e6edf3;}
  .badge { background: #1f6feb; border-radius: 2em; padding: 2px 10px; font-size: 12px; font-weight: bold; border: 1px solid rgba(88,166,255,0.4); display:inline-block; margin-left:10px;}
  .meta-row { display: flex; gap: 40px; font-size: 13px; color: var(--text-secondary); margin-top: 15px;}
  .meta-col span { display: block; font-size:11px; letter-spacing:0.5px;}
  .meta-val { color: var(--text-primary); font-family: monospace; font-size: 14px; margin-top:3px;}
  .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 15px; margin-bottom: 30px;}
  .card { background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 8px; padding: 20px; display: flex; flex-direction: column; justify-content: center;}
  .card-icon { font-size: 20px; margin-bottom: 15px; }
  .card-value { font-size: 22px; font-weight: 600; color: #fff; margin-bottom: 5px; line-height: 1.2;}
  .card-label { font-size: 11px; text-transform: uppercase; color: var(--text-secondary); font-weight: 600; letter-spacing: 0.5px;}
  .section { margin-bottom: 20px; }
  details { background: var(--bg-card); border: 1px solid var(--border-color); border-radius: 6px; overflow: hidden; margin-bottom: 10px;}
  summary { padding: 15px 20px; cursor: pointer; font-weight: 600; color: #e6edf3; display: flex; align-items: center; border-bottom: 1px solid transparent;}
  summary::-webkit-details-marker { display: none; }
  details[open] summary { border-bottom: 1px solid var(--border-color); }
  details pre { margin: 0; padding: 20px; font-family: ui-monospace,SFMono-Regular,Consolas,"Liberation Mono",monospace; font-size: 13px; color: var(--text-secondary); overflow-x: auto;}
  .alert { border: 1px solid #f85149; }
</style>
</head>
<body>
  <div class="header">
    <div style="color:var(--text-secondary); font-size:12px; font-weight:600; text-transform:uppercase; letter-spacing:1px;">🛡️ Security Audit Report</div>
    <h1>Linux System Audit</h1>
    <div style="font-size: 14px; color: var(--text-secondary); display:flex; align-items:center;">
      Automated audit generated by SysAudit v1.0 <span class="badge">FULL REPORT</span>
    </div>
    <div class="meta-row">
      <div class="meta-col"><span>HOSTNAME</span><div class="meta-val">🟢 $HOST</div></div>
      <div class="meta-col"><span>GENERATED</span><div class="meta-val">$DATE</div></div>
      <div class="meta-col"><span>KERNEL</span><div class="meta-val">$os_kernel</div></div>
      <div class="meta-col"><span>AUDITOR</span><div class="meta-val">$auditor</div></div>
    </div>
  </div>
  <div class="cards">
    <div class="card" style="grid-column: span 2;"><div class="card-icon">🖥️</div><div class="card-value">$k_model</div><div class="card-label">CPU MODEL</div></div>
    <div class="card"><div class="card-icon">🧠</div><div class="card-value">$k_ram</div><div class="card-label">TOTAL RAM</div></div>
    <div class="card"><div class="card-icon">💻</div><div class="card-value">${k_proc}</div><div class="card-label">PROCESSES</div></div>
    <div class="card"><div class="card-icon">🌐</div><div class="card-value">$k_ports</div><div class="card-label">OPEN PORTS</div></div>
    <div class="card"><div class="card-icon">💾</div><div class="card-value">$k_disk</div><div class="card-label">ROOT DISK USAGE</div></div>
    <div class="card"><div class="card-icon">📦</div><div class="card-value">$k_pkg</div><div class="card-label">PACKAGES</div></div>
  </div>
  <div class="section">
    <details open><summary>🔧 Hardware Information</summary><pre>$report_content</pre></details>
  </div>
</body>
</html>
EOF
    } > "$FULL_REPORT_HTML"

    {
        cat <<EOF
{
  "report_type": "full", "date": "$(date '+%Y-%m-%d %H:%M:%S')", "hostname": "$HOST", "uptime": "$UPTIME",
  "content": "$(escape_json "$report_content")"
}
EOF
    } > "$FULL_REPORT_JSON"

    FULL_REPORT_PDF="$REPORT_DIR/pdf/full_${DATE}.pdf"
    local pdf_temp_html="$REPORT_DIR/html/full_${DATE}_pdf_temp.html"

    generate_text_pdf_html "$report_content" > "$pdf_temp_html"

    if command -v libreoffice &>/dev/null; then
        libreoffice --headless --convert-to pdf "$pdf_temp_html" --outdir "$REPORT_DIR/pdf" &>/dev/null
        mv "$REPORT_DIR/pdf/full_${DATE}_pdf_temp.pdf" "$FULL_REPORT_PDF" 2>/dev/null
    elif command -v wkhtmltopdf &>/dev/null; then
        wkhtmltopdf -q "$pdf_temp_html" "$FULL_REPORT_PDF" 2>/dev/null
    elif command -v pandoc &>/dev/null; then
        pandoc "$pdf_temp_html" -o "$FULL_REPORT_PDF" 2>/dev/null
    elif command -v ps2pdf &>/dev/null && command -v enscript &>/dev/null; then
        enscript -B -M A4 "$FULL_REPORT_TXT" -p - 2>/dev/null | ps2pdf - "$FULL_REPORT_PDF" 2>/dev/null
    fi

    # Cleanup temp PDF-HTML
    [ -f "$pdf_temp_html" ] && rm "$pdf_temp_html"

    export FULL_REPORT
}

# --- get_reports: Show the paths of the last generated reports ---
# Useful for debugging or confirming where the files were saved.
# Only meaningful after generate_short() or generate_full() has been run.
get_reports() {
    echo "Short: $SHORT_REPORT"
    echo "Full : $FULL_REPORT"
}
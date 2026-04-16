# 🛡️ Linux System Audit Tool — SysAudit v1.0

> **Mini-Project – Part N°1**
> Design and Implementation of an Automated Hardware & Software Audit System with Reporting and Remote Monitoring Capabilities
>
> *National School of Cyber Security — Foundation Training Department*

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Project Structure](#-project-structure)
- [Requirements](#-requirements)
- [Installation](#-installation)
- [Configuration](#-configuration)
- [How to Run the Script](#-how-to-run-the-script)
- [Menu Options](#-menu-options)
- [Output / Reports](#-output--reports)
- [Automated Scheduling (Cron)](#-automated-scheduling-cron)
- [Remote Audit](#-remote-audit)

---

## 🔍 Overview

**SysAudit** is a modular Bash-based tool that collects detailed hardware and software information from a Linux system and generates audit reports in four formats: **TXT**, **HTML**, **JSON**, and **PDF**.

Key features:
- 📊 Short & Full system audit reports
- 📧 Email delivery of reports
- 🔒 Report integrity verification via SHA-256 hashing
- 📂 Report comparison (diff) between two audit runs
- ⏰ Automated daily scheduling via cron
- 🌐 Remote auditing of other machines over SSH

---

## 📁 Project Structure

```
os project/
├── main.sh         # Entry point — run this file
├── utils.sh        # Shared color & print helpers
├── log.sh          # Logging & log rotation
├── hardware.sh     # Hardware data collection (CPU, RAM, Disk, GPU…)
├── software.sh     # Software data collection (OS, packages, users, ports…)
├── report.sh       # Report generation (TXT, HTML, JSON, PDF)
├── email.sh        # Email sending (report delivery & CPU alerts)
├── security.sh     # SHA-256 hashing and report integrity verification
├── remote.sh       # Remote audit via SSH
├── logs/           # Auto-created — contains audit.log
└── reports/        # Auto-created — contains generated reports
    ├── txt/
    ├── html/
    ├── json/
    └── pdf/
```

---

## ✅ Requirements

### Required (core functionality)

| Tool | Purpose | Install |
|------|---------|---------|
| `bash` ≥ 4.0 | Run the scripts | Pre-installed |
| `lscpu`, `free`, `df`, `ss` | Hardware/software data | Pre-installed (`util-linux`) |
| `jq` | JSON escaping in reports | `sudo apt install jq` |
| `sha256sum` | Report integrity hashing | Pre-installed (`coreutils`) |

### Optional (for PDF generation — at least one needed)

| Tool | Install |
|------|---------|
| `libreoffice` *(recommended)* | `sudo apt install libreoffice` |
| `wkhtmltopdf` | `sudo apt install wkhtmltopdf` |
| `pandoc` | `sudo apt install pandoc` |
| `enscript` + `ps2pdf` | `sudo apt install enscript ghostscript` |

### Optional (for email sending — at least one needed)

| Tool | Install |
|------|---------|
| `msmtp` *(recommended)* | `sudo apt install msmtp` |
| `mailutils` | `sudo apt install mailutils` |

### Optional (for remote auditing)

| Tool | Purpose |
|------|---------|
| `ssh` + `scp` | Connect and copy scripts to remote |

---

## ⚙️ Installation

### 1. Clone or Copy the Project

```bash
# Navigate to where you want the project
cd ~/Desktop

# If using git:
git clone <repository-url> "os project"

# Or simply ensure all .sh files are in the same folder
```

### 2. Make Scripts Executable

```bash
cd ~/Desktop/os\ project
chmod +x *.sh
```

### 3. Install Core Dependencies

```bash
# jq is the only non-pre-installed required dependency
sudo apt update
sudo apt install jq
```

### 4. Install a PDF Converter (Optional but Recommended)

```bash
sudo apt install libreoffice
```

### 5. Install a Mail Client (Optional — only needed for email features)

```bash
sudo apt install msmtp
# or
sudo apt install mailutils
```

---

## 🔧 Configuration

### Email Address

The default recipient email is hardcoded in `main.sh` and `email.sh`.  
To change it, open `main.sh` and find this line (~line 173):

```bash
export AUDIT_EMAIL="mohamednessissen07@gmail.com"
```

Replace it with your own email address.

> **Note:** When using option 3 (Send Report by Email) from the menu, you will also be prompted to enter a recipient email address interactively. You can leave it blank to use the default.

---

### msmtp Configuration (if using msmtp for email)

Create the config file at `~/.msmtprc`:

```
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        ~/.msmtp.log

account        default
host           smtp.gmail.com
port           587
from           your-email@gmail.com
user           your-email@gmail.com
password       your-app-password
```

Set correct permissions:

```bash
chmod 600 ~/.msmtprc
```

> **Gmail tip:** Use an [App Password](https://myaccount.google.com/apppasswords) instead of your real password if 2FA is enabled.

---

### Log Settings

Log behavior is configured at the top of `log.sh`:

```bash
MAX_LOG_SIZE=100000    # Rotate log when it exceeds 100 KB
MAX_LOG_BACKUPS=5      # Keep at most 5 archived log files
```

Logs are saved to: `<project-folder>/logs/audit.log`

---

## ▶️ How to Run the Script

### Interactive Mode (Recommended)

Navigate to the project folder and run `main.sh`:

```bash
cd ~/Desktop/os\ project
bash main.sh
```

This opens the interactive menu where you can choose what to do.

---

### Automated Mode (used by cron)

To generate a full report without any user interaction:

```bash
bash main.sh --auto
```

This skips the menu, generates a full report in all formats, hashes it, and exits.

---

### Running from Any Directory

Because the tool uses absolute paths internally, you can also run it from any working directory:

```bash
bash ~/Desktop/os\ project/main.sh
```

---

## 📌 Menu Options

When you run the tool interactively, you'll see this menu:

```
===== LINUX SYSTEM AUDIT TOOL =====

1) Generate Short Report
2) Generate Full Report
3) Send Report by Email
4) Compare Last Two Reports
5) Verify Report Integrity (Hash Check)
6) Setup Cron Job (Auto-Schedule)
7) Run Remote Audit
8) Exit
```

| Option | What it does |
|--------|-------------|
| **1** | Quick summary: OS, CPU, RAM, Disk, package count, CPU usage |
| **2** | Full audit: all hardware + software data, CPU alert if > 80% |
| **3** | Emails a short or full report to a recipient |
| **4** | Diffs the two most recent reports to show what changed |
| **5** | Verifies a report's SHA-256 hash to detect modifications |
| **6** | Registers a cron job to run `--auto` every day at 4:00 AM |
| **7** | SSH into a remote machine, run the audit there, pull results back |
| **8** | Exit the tool |

---

## 📂 Output / Reports

All reports are saved under `<project-folder>/reports/`:

```
reports/
├── txt/    → full_2026-04-15_04-00-00.txt   (plain text)
├── html/   → full_2026-04-15_04-00-00.html  (open in browser)
├── json/   → full_2026-04-15_04-00-00.json  (machine-readable)
└── pdf/    → full_2026-04-15_04-00-00.pdf   (printable)
```

- **Short reports** are prefixed with `short_`
- **Full reports** are prefixed with `full_`
- Each full `.txt` report also generates a `.hash` file for integrity checks

---

## ⏰ Automated Scheduling (Cron)

### Setup via Menu (Recommended)

1. Run the tool: `bash main.sh`
2. Choose option **6 — Setup Cron Job**
3. Confirm when prompted

This registers a cron job that runs at **4:00 AM every day**.

### How It Works

Because the project folder path contains a space (`os project/`), a small wrapper script is created at `/tmp/sysaudit_cron_wrapper.sh` to avoid cron's space-handling limitations. The wrapper safely `cd`s into the project and calls `main.sh --auto`.

Cron output is logged to: `<project-folder>/logs/cron.log`

### Verify the Cron Job

```bash
crontab -l
```

You should see a line like:

```
0 4 * * * /tmp/sysaudit_cron_wrapper.sh
```

### Remove the Cron Job

```bash
crontab -e
# Delete the line containing sysaudit_cron_wrapper
```

---

## 🌐 Remote Audit

Option **7** lets you audit another Linux machine over SSH.

### How It Works

1. You provide a **username** and **IP/hostname** of the remote machine
2. The tool uploads all `.sh` scripts to `/tmp/audit_scripts/` on the remote
3. Runs `main.sh --auto` remotely
4. Downloads the generated reports back to your machine under:
   ```
   reports/remote/
   ├── txt/
   ├── html/
   ├── json/
   └── pdf/
   ```

### Requirements

- SSH access to the remote machine (password or key-based)
- Bash available on the remote machine
- The remote machine does **not** need the tool pre-installed

### Example

```
Enter Remote Target User [default: root]: ubuntu
Enter Remote Host IP/Domain: 192.168.1.50
```

---

*Generated by SysAudit v1.0 — National School of Cyber Security*

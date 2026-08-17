#!/usr/bin/env bash
# uninstall.sh - Remove audiomxd-governor LaunchDaemon
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run as root: sudo ./uninstall.sh"
    exit 1
fi

PLIST_DST="/Library/LaunchDaemons/com.macfixes.audiomxd-governor.plist"
SCRIPT_DST="/usr/local/libexec/audiomxd-governor.py"

echo "[*] Uninstalling audiomxd-governor..."

# 1. Unload service
if [ -f "${PLIST_DST}" ]; then
    launchctl bootout system/com.macfixes.audiomxd-governor 2>/dev/null || true
    rm -f "${PLIST_DST}"
    echo "[+] Removed ${PLIST_DST}"
fi

# 2. Remove script
if [ -f "${SCRIPT_DST}" ]; then
    rm -f "${SCRIPT_DST}"
    echo "[+] Removed ${SCRIPT_DST}"
fi

# 3. Ensure audiomxd is resumed
pkill -CONT -f "/usr/libexec/audiomxd" 2>/dev/null || true

echo "[+] audiomxd-governor uninstalled successfully."

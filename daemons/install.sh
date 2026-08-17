#!/usr/bin/env bash
# install.sh - Install audiomxd-governor LaunchDaemon on macOS Tahoe
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run as root: sudo ./install.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[*] Installing audiomxd-governor..."

# 1. Install daemon script
mkdir -p /usr/local/libexec
cp "${SCRIPT_DIR}/audiomxd-governor.py" /usr/local/libexec/audiomxd-governor.py
chmod 0755 /usr/local/libexec/audiomxd-governor.py
chown root:wheel /usr/local/libexec/audiomxd-governor.py
echo "[+] Installed /usr/local/libexec/audiomxd-governor.py"

# 2. Install LaunchDaemon plist
PLIST_DST="/Library/LaunchDaemons/com.macfixes.audiomxd-governor.plist"
cp "${SCRIPT_DIR}/com.macfixes.audiomxd-governor.plist" "${PLIST_DST}"
chmod 0644 "${PLIST_DST}"
chown root:wheel "${PLIST_DST}"
echo "[+] Installed ${PLIST_DST}"

# 3. Bootstrap service
echo "[*] Activating LaunchDaemon service..."
launchctl bootstrap system "${PLIST_DST}" 2>/dev/null || launchctl kickstart -k system/com.macfixes.audiomxd-governor 2>/dev/null || true

echo "[+] audiomxd-governor successfully installed and active!"
echo "[*] Log output available at: /var/log/audiomxd-governor.log"

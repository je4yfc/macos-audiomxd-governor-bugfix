#!/usr/bin/env bash
# apply_flags.sh - Install persistent FeatureFlag override plists
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run as root: sudo ./apply_flags.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FF_DIR="/Library/Preferences/FeatureFlags/Domain"

echo "[*] Applying persistent FeatureFlag overrides to ${FF_DIR}..."
mkdir -p "${FF_DIR}"

cp "${SCRIPT_DIR}/BluetoothFeatures.plist" "${FF_DIR}/BluetoothFeatures.plist"
chmod 0644 "${FF_DIR}/BluetoothFeatures.plist"
chown root:wheel "${FF_DIR}/BluetoothFeatures.plist"
echo "[+] Installed ${FF_DIR}/BluetoothFeatures.plist"

cp "${SCRIPT_DIR}/MediaExperience.plist" "${FF_DIR}/MediaExperience.plist"
chmod 0644 "${FF_DIR}/MediaExperience.plist"
chown root:wheel "${FF_DIR}/MediaExperience.plist"
echo "[+] Installed ${FF_DIR}/MediaExperience.plist"

echo "[+] FeatureFlag overrides applied successfully. They will persist across reboots."

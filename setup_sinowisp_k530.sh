#!/usr/bin/env bash
# Installs sinowisp and prepares this system to read/write the
# Redragon K530 Draconic PRO (Sino Wealth SH68F90A, 258a:0049).
set -euo pipefail

DEVICE_KEY="redragon-k530-draconic-pro"
UDEV_RULE_FILE="/etc/udev/rules.d/99-sinowisp-k530.rules"
BACKUP_DIR="${HOME}/k530-pro-firmware-backups"

echo "==> Installing sinowisp via cargo"
cargo install sinowisp

echo "==> Writing udev rule: ${UDEV_RULE_FILE}"
sudo tee "${UDEV_RULE_FILE}" > /dev/null <<'EOF'
# Redragon K530 Draconic PRO (Sino Wealth SH68F90A) - normal operating mode
SUBSYSTEMS=="usb", ATTRS{idVendor}=="258a", ATTRS{idProduct}=="0049", TAG+="uaccess"
# Generic Sino Wealth ISP bootloader mode the keyboard reboots into during flashing
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0603", ATTRS{idProduct}=="1020", TAG+="uaccess"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="0603", ATTRS{idProduct}=="1021", TAG+="uaccess"
EOF

echo "==> Reloading udev rules"
sudo udevadm control --reload-rules
sudo udevadm trigger

echo
echo "==> Unplug and replug the keyboard now so the new udev rule applies, then press Enter."
read -r _

mkdir -p "${BACKUP_DIR}"
BACKUP_FILE="${BACKUP_DIR}/k530_pro_stock_$(date +%Y%m%d_%H%M%S).bin"

echo "==> Backing up stock firmware to ${BACKUP_FILE}"
sinowisp read -d "${DEVICE_KEY}" "${BACKUP_FILE}"

echo
echo "==> Done. Stock firmware backup saved at: ${BACKUP_FILE}"
echo "    Keep this file - it's your only way back to a known-good state."
echo
echo "To write a firmware image later:"
echo "    sinowisp write -d ${DEVICE_KEY} /path/to/firmware.bin"

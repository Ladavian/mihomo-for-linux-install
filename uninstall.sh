#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="${MIHOMO_SERVICE_NAME:-mihomo}"
INSTALL_DIR="${MIHOMO_INSTALL_DIR:-/opt/mihomo}"
BIN_PATH="${MIHOMO_BIN_PATH:-/usr/local/bin/mihomo}"
CONFIG_DIR="${MIHOMO_CONFIG_DIR:-/etc/mihomo}"
RUN_USER="${MIHOMO_USER:-mihomo}"
PURGE_CONFIG="${MIHOMO_PURGE_CONFIG:-0}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root. Example: sudo bash uninstall.sh" >&2
  exit 1
fi

systemctl stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
systemctl disable "${SERVICE_NAME}" >/dev/null 2>&1 || true
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload >/dev/null 2>&1 || true

rm -f "${BIN_PATH}"
rm -rf "${INSTALL_DIR}"

if [[ "${PURGE_CONFIG}" == "1" || "${1:-}" == "--purge" ]]; then
  rm -rf "${CONFIG_DIR}"
fi

if id "${RUN_USER}" >/dev/null 2>&1; then
  userdel "${RUN_USER}" >/dev/null 2>&1 || true
fi

echo "mihomo has been uninstalled."
if [[ -d "${CONFIG_DIR}" ]]; then
  echo "Config kept at ${CONFIG_DIR}. Run with --purge to remove it."
fi

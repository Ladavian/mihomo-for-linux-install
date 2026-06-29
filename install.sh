#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="mihomo"
REPO="MetaCubeX/mihomo"
SERVICE_NAME="mihomo"

INSTALL_DIR="${MIHOMO_INSTALL_DIR:-/opt/mihomo}"
BIN_PATH="${MIHOMO_BIN_PATH:-/usr/local/bin/mihomo}"
CONFIG_DIR="${MIHOMO_CONFIG_DIR:-/etc/mihomo}"
CONFIG_FILE="${MIHOMO_CONFIG_FILE:-${CONFIG_DIR}/config.yaml}"
RUN_USER="${MIHOMO_USER:-mihomo}"
VERSION="${MIHOMO_VERSION:-latest}"
SUB_URL="${MIHOMO_SUB_URL:-}"
DOWNLOAD_URL="${MIHOMO_DOWNLOAD_URL:-}"
GITHUB_PROXY="${MIHOMO_GITHUB_PROXY:-}"
ENABLE_TUN="${MIHOMO_ENABLE_TUN:-0}"
SKIP_LXC_CHECK="${MIHOMO_SKIP_LXC_CHECK:-0}"
START_SERVICE="${MIHOMO_START_SERVICE:-1}"
FORCE="${MIHOMO_FORCE:-0}"

RED=""
GREEN=""
YELLOW=""
BLUE=""
RESET=""

if [[ -t 1 ]]; then
  RED="$(printf '\033[31m')"
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  BLUE="$(printf '\033[34m')"
  RESET="$(printf '\033[0m')"
fi

log() {
  printf '%b[INFO]%b %s\n' "${BLUE}" "${RESET}" "$*" >&2
}

ok() {
  printf '%b[ OK ]%b %s\n' "${GREEN}" "${RESET}" "$*" >&2
}

warn() {
  printf '%b[WARN]%b %s\n' "${YELLOW}" "${RESET}" "$*" >&2
}

die() {
  printf '%b[FAIL]%b %s\n' "${RED}" "${RESET}" "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
mihomo LXC one-key installer

Usage:
  bash install.sh [options]

Options:
  --version <tag>       Install a specific release tag, for example v1.19.13.
  --sub-url <url>       Download config.yaml from a subscription/config URL.
  --download-url <url>  Use a custom mihomo release asset URL.
  --install-dir <dir>   Default: /opt/mihomo.
  --config-dir <dir>    Default: /etc/mihomo.
  --enable-tun          Enable tun mode in the generated default config and require LXC TUN support.
  --skip-lxc-check      Skip LXC/container/TUN capability checks.
  --no-start            Install only, do not start the systemd service.
  --force               Overwrite existing binary/config/service without prompts.
  -h, --help            Show this help.

Environment variables mirror the options:
  MIHOMO_VERSION, MIHOMO_SUB_URL, MIHOMO_DOWNLOAD_URL, MIHOMO_GITHUB_PROXY,
  MIHOMO_INSTALL_DIR, MIHOMO_CONFIG_DIR, MIHOMO_ENABLE_TUN,
  MIHOMO_SKIP_LXC_CHECK, MIHOMO_START_SERVICE, MIHOMO_FORCE.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:-}"
      shift 2
      ;;
    --sub-url)
      SUB_URL="${2:-}"
      shift 2
      ;;
    --download-url)
      DOWNLOAD_URL="${2:-}"
      shift 2
      ;;
    --install-dir)
      INSTALL_DIR="${2:-}"
      shift 2
      ;;
    --config-dir)
      CONFIG_DIR="${2:-}"
      CONFIG_FILE="${CONFIG_DIR}/config.yaml"
      shift 2
      ;;
    --enable-tun)
      ENABLE_TUN="1"
      shift
      ;;
    --skip-lxc-check)
      SKIP_LXC_CHECK="1"
      shift
      ;;
    --no-start)
      START_SERVICE="0"
      shift
      ;;
    --force)
      FORCE="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    die "Please run as root. Example: sudo bash install.sh"
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

detect_pkg_manager() {
  if command_exists apt-get; then
    echo "apt"
  elif command_exists dnf; then
    echo "dnf"
  elif command_exists yum; then
    echo "yum"
  elif command_exists pacman; then
    echo "pacman"
  elif command_exists zypper; then
    echo "zypper"
  elif command_exists apk; then
    echo "apk"
  else
    echo "unknown"
  fi
}

install_packages() {
  local pm="$1"
  shift
  local packages=("$@")

  case "${pm}" in
    apt)
      DEBIAN_FRONTEND=noninteractive apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
      ;;
    dnf)
      dnf install -y "${packages[@]}"
      ;;
    yum)
      yum install -y "${packages[@]}"
      ;;
    pacman)
      pacman -Sy --noconfirm --needed "${packages[@]}"
      ;;
    zypper)
      zypper --non-interactive install "${packages[@]}"
      ;;
    apk)
      apk add --no-cache "${packages[@]}"
      ;;
    *)
      die "Unsupported package manager. Please install dependencies manually: curl ca-certificates gzip tar iproute2 iptables systemd"
      ;;
  esac
}

ensure_dependencies() {
  log "Checking base packages required inside the LXC container"

  local pm
  pm="$(detect_pkg_manager)"
  local missing=()

  command_exists curl || missing+=("curl")
  command_exists gzip || missing+=("gzip")
  command_exists tar || missing+=("tar")
  command_exists ip || missing+=("iproute2")
  command_exists iptables || command_exists nft || missing+=("iptables")
  command_exists systemctl || missing+=("systemd")

  if [[ "${#missing[@]}" -eq 0 ]]; then
    ok "Base packages are already installed"
    return
  fi

  log "Installing missing packages: ${missing[*]}"

  case "${pm}" in
    apt)
      install_packages "${pm}" ca-certificates curl gzip tar iproute2 iptables systemd
      ;;
    dnf|yum)
      install_packages "${pm}" ca-certificates curl gzip tar iproute iptables systemd
      ;;
    pacman)
      install_packages "${pm}" ca-certificates curl gzip tar iproute2 iptables systemd
      ;;
    zypper)
      install_packages "${pm}" ca-certificates curl gzip tar iproute2 iptables systemd
      ;;
    apk)
      warn "Alpine LXC usually does not run systemd. Installing base tools, but the service may not work."
      install_packages "${pm}" ca-certificates curl gzip tar iproute2 iptables
      ;;
    *)
      install_packages "${pm}" "${missing[@]}"
      ;;
  esac

  command_exists curl || die "curl is still missing after dependency installation"
  command_exists gzip || die "gzip is still missing after dependency installation"
  command_exists tar || die "tar is still missing after dependency installation"
  command_exists systemctl || die "systemd/systemctl is required by this installer"
}

is_lxc_container() {
  if command_exists systemd-detect-virt; then
    systemd-detect-virt --container >/dev/null 2>&1 && return 0
  fi

  if [[ -r /proc/1/environ ]] && tr '\0' '\n' </proc/1/environ 2>/dev/null | grep -Eq 'container=(lxc|lxc-libvirt|podman|docker)'; then
    return 0
  fi

  if grep -qaE '/lxc/|/machine.slice/' /proc/1/cgroup 2>/dev/null; then
    return 0
  fi

  return 1
}

print_lxc_hint() {
  cat >&2 <<'EOF'

LXC host configuration hint:
  If this container is on Proxmox and you want mihomo TUN/transparent proxy mode,
  enable these on the host for the CT:

  pct set <CTID> -features nesting=1,keyctl=1
  pct set <CTID> -net0 name=eth0,bridge=vmbr0,firewall=1

  Add to /etc/pve/lxc/<CTID>.conf when /dev/net/tun is not available:
  lxc.cgroup2.devices.allow: c 10:200 rwm
  lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file

  Then restart the container.
EOF
}

check_tun_device() {
  [[ -c /dev/net/tun ]] || return 1

  if command_exists ip; then
    local test_dev="mihomo-check-$$"
    if ip tuntap add dev "${test_dev}" mode tun >/dev/null 2>&1; then
      ip link delete "${test_dev}" >/dev/null 2>&1 || true
      return 0
    fi
    return 1
  fi

  return 0
}

preflight_lxc() {
  [[ "${SKIP_LXC_CHECK}" == "1" ]] && return

  log "Checking LXC/container capabilities"

  if is_lxc_container; then
    ok "Container environment detected"
  else
    warn "This does not look like an LXC/container environment. Continuing anyway."
  fi

  if check_tun_device; then
    ok "TUN device is available"
  else
    if [[ "${ENABLE_TUN}" == "1" ]]; then
      print_lxc_hint
      die "TUN is required because --enable-tun was set"
    fi

    warn "TUN is not available. HTTP/SOCKS proxy mode can still work, but TUN mode will fail."
    print_lxc_hint
  fi
}

detect_arch() {
  local arch
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64)
      echo "amd64-compatible"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    armv7l|armv7)
      echo "armv7"
      ;;
    armv6l|armv6)
      echo "armv6"
      ;;
    i386|i686)
      echo "386"
      ;;
    *)
      die "Unsupported CPU architecture: ${arch}"
      ;;
  esac
}

github_api_url() {
  if [[ "${VERSION}" == "latest" ]]; then
    printf 'https://api.github.com/repos/%s/releases/latest' "${REPO}"
  else
    printf 'https://api.github.com/repos/%s/releases/tags/%s' "${REPO}" "${VERSION}"
  fi
}

resolve_version_tag() {
  if [[ "${VERSION}" != "latest" ]]; then
    printf '%s' "${VERSION}"
    return
  fi

  local latest_url effective tag
  latest_url="https://github.com/${REPO}/releases/latest"

  log "Resolving latest mihomo version from ${latest_url}" >&2
  effective="$(curl -fsSL -o /dev/null -w '%{url_effective}' "${latest_url}")" || die "Failed to resolve latest release page: ${latest_url}"
  tag="${effective##*/}"

  [[ "${tag}" == v* ]] || die "Could not resolve latest mihomo version from: ${effective}"
  printf '%s' "${tag}"
}

apply_github_proxy() {
  local url="$1"

  if [[ -n "${GITHUB_PROXY}" ]]; then
    printf '%s/%s' "${GITHUB_PROXY%/}" "${url}"
  else
    printf '%s' "${url}"
  fi
}

resolve_download_url() {
  if [[ -n "${DOWNLOAD_URL}" ]]; then
    printf '%s' "${DOWNLOAD_URL}"
    return
  fi

  local arch tag url
  arch="$(detect_arch)"
  tag="$(resolve_version_tag)"

  log "Using mihomo ${tag} release asset for linux-${arch}" >&2
  url="https://github.com/${REPO}/releases/download/${tag}/mihomo-linux-${arch}-${tag}.gz"
  apply_github_proxy "${url}"
}

resolve_download_url_from_api() {
  local arch api json url
  arch="$(detect_arch)"
  api="$(github_api_url)"

  log "Resolving mihomo release asset from GitHub API (${VERSION}, linux-${arch})"
  json="$(curl -fsSL "${api}")" || die "Failed to query GitHub release API: ${api}"

  url="$(
    {
      printf '%s\n' "${json}" |
        grep 'browser_download_url' |
        grep "linux-${arch}" |
        grep -E '\.gz"' |
        grep -Ev 'alpha|compatible-go120|sha256|checksums|\.deb|\.rpm' |
        head -n 1 |
        sed -E 's/.*"([^"]+)".*/\1/'
    } || true
  )"

  if [[ -z "${url}" && "${arch}" == "amd64-compatible" ]]; then
    url="$(
      {
        printf '%s\n' "${json}" |
          grep 'browser_download_url' |
          grep 'linux-amd64' |
          grep -E '\.gz"' |
          grep -Ev 'alpha|compatible-go120|sha256|checksums|\.deb|\.rpm' |
          head -n 1 |
          sed -E 's/.*"([^"]+)".*/\1/'
      } || true
    )"
  fi

  [[ -n "${url}" ]] || die "Could not find a suitable mihomo release asset for linux-${arch}"

  apply_github_proxy "${url}"
}

ensure_user() {
  if id "${RUN_USER}" >/dev/null 2>&1; then
    return
  fi

  if command_exists useradd; then
    useradd --system --no-create-home --home-dir "${CONFIG_DIR}" --shell /usr/sbin/nologin "${RUN_USER}"
  elif command_exists adduser; then
    adduser -S -D -H -h "${CONFIG_DIR}" -s /sbin/nologin "${RUN_USER}"
  else
    die "Could not create system user ${RUN_USER}: useradd/adduser not found"
  fi
}

confirm_overwrite() {
  local path="$1"

  [[ "${FORCE}" == "1" ]] && return
  [[ ! -e "${path}" ]] && return

  if [[ ! -t 0 ]]; then
    warn "${path} exists; keeping it. Use --force to overwrite."
    return 1
  fi

  read -r -p "${path} exists. Overwrite? [y/N] " answer
  [[ "${answer}" =~ ^[Yy]$ ]]
}

install_binary() {
  local url tmp_dir archive
  url="$(resolve_download_url)"
  tmp_dir="$(mktemp -d)"
  archive="${tmp_dir}/mihomo.gz"

  trap 'rm -rf "${tmp_dir}"' RETURN

  log "Downloading mihomo binary"
  curl -fL --retry 3 --retry-delay 2 -o "${archive}" "${url}" || die "Failed to download: ${url}"

  mkdir -p "${INSTALL_DIR}"
  gzip -dc "${archive}" >"${tmp_dir}/mihomo"
  chmod 0755 "${tmp_dir}/mihomo"

  install -m 0755 "${tmp_dir}/mihomo" "${INSTALL_DIR}/mihomo"
  ln -sfn "${INSTALL_DIR}/mihomo" "${BIN_PATH}"

  ok "Installed $(mihomo -v 2>/dev/null | head -n 1 || echo mihomo) to ${BIN_PATH}"
}

generate_secret() {
  if command_exists openssl; then
    openssl rand -hex 16
  else
    date +%s%N | sha256sum | awk '{print $1}' | cut -c 1-32
  fi
}

write_default_config() {
  mkdir -p "${CONFIG_DIR}"

  if [[ -n "${SUB_URL}" ]]; then
    if confirm_overwrite "${CONFIG_FILE}"; then
      log "Downloading config from subscription/config URL"
      curl -fL --retry 3 --retry-delay 2 -o "${CONFIG_FILE}" "${SUB_URL}" || die "Failed to download config from ${SUB_URL}"
      chown -R "${RUN_USER}:${RUN_USER}" "${CONFIG_DIR}" || true
      chmod 0640 "${CONFIG_FILE}"
      ok "Config installed to ${CONFIG_FILE}"
    fi
    return
  fi

  if ! confirm_overwrite "${CONFIG_FILE}"; then
    return
  fi

  local secret tun_enable
  secret="$(generate_secret)"
  tun_enable="false"
  [[ "${ENABLE_TUN}" == "1" ]] && tun_enable="true"

  cat >"${CONFIG_FILE}" <<EOF
mixed-port: 7890
allow-lan: true
bind-address: "*"
mode: rule
log-level: info
ipv6: false
external-controller: 0.0.0.0:9090
secret: "${secret}"

profile:
  store-selected: true
  store-fake-ip: true

dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - https://223.5.5.5/dns-query
    - https://1.12.12.12/dns-query
  fallback:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query

tun:
  enable: ${tun_enable}
  stack: system
  auto-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53

proxies: []
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - DIRECT

rules:
  - MATCH,DIRECT
EOF

  chown -R "${RUN_USER}:${RUN_USER}" "${CONFIG_DIR}" || true
  chmod 0750 "${CONFIG_DIR}"
  chmod 0640 "${CONFIG_FILE}"
  ok "Default config written to ${CONFIG_FILE}"
  warn "Default config has no proxy nodes. Use --sub-url or edit ${CONFIG_FILE} before production use."
}

write_service() {
  local service_file="/etc/systemd/system/${SERVICE_NAME}.service"

  cat >"${service_file}" <<EOF
[Unit]
Description=mihomo proxy service
Documentation=https://github.com/MetaCubeX/mihomo
After=network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_USER}
WorkingDirectory=${CONFIG_DIR}
ExecStart=${BIN_PATH} -d ${CONFIG_DIR}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null
  ok "systemd service installed: ${service_file}"
}

start_service() {
  [[ "${START_SERVICE}" == "1" ]] || {
    warn "Service start skipped by --no-start"
    return
  }

  log "Starting ${SERVICE_NAME}.service"
  systemctl restart "${SERVICE_NAME}"
  sleep 1

  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    ok "${SERVICE_NAME}.service is running"
  else
    systemctl status "${SERVICE_NAME}" --no-pager -l || true
    die "${SERVICE_NAME}.service failed to start"
  fi
}

print_summary() {
  cat <<EOF

Installed successfully.

Useful commands:
  systemctl status ${SERVICE_NAME} --no-pager -l
  journalctl -u ${SERVICE_NAME} -f
  mihomo -d ${CONFIG_DIR} -t

Files:
  Binary: ${BIN_PATH}
  Config: ${CONFIG_FILE}
  Service: /etc/systemd/system/${SERVICE_NAME}.service

External controller:
  http://<LXC-IP>:9090
EOF
}

main() {
  require_root
  ensure_dependencies
  preflight_lxc
  ensure_user
  install_binary
  write_default_config
  write_service
  start_service
  print_summary
}

main "$@"

#!/usr/bin/env bash
set -e

API="https://api.github.com/repos/MetaCubeX/mihomo/releases/latest"
INSTALL_DIR="/opt/mihomo"
CONFIG_DIR="/opt/config"
SERVICE="/etc/systemd/system/mihomo.service"

msg(){ echo -e "\033[1;32m[INFO]\033[0m $*"; }
err(){ echo -e "\033[1;31m[ERR ]\033[0m $*"; exit 1; }

[ "$EUID" -eq 0 ] || err "Run as root"

arch() {
 case "$(uname -m)" in
  x86_64) echo amd64;;
  aarch64|arm64) echo arm64;;
  armv7l) echo armv7;;
  *) err "Unsupported arch $(uname -m)";;
 esac
}

latest() {
 curl -fsSL "$API" | grep '"tag_name"' | head -1 | cut -d'"' -f4
}

deps(){
 apt-get update
 apt-get install -y curl wget gzip ca-certificates iproute2 iptables nftables procps
}

dirs(){
 mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
}

download(){
 VER=$(latest)
 ARCH=$(arch)
 URL="https://github.com/MetaCubeX/mihomo/releases/download/${VER}/mihomo-linux-${ARCH}-${VER}.gz"
 msg "Downloading $VER ($ARCH)"
 cd /tmp
 rm -f mihomo mihomo.gz
 curl -fL "$URL" -o mihomo.gz
 gunzip -f mihomo.gz
 [ -f "$INSTALL_DIR/mihomo" ] && cp "$INSTALL_DIR/mihomo" "$INSTALL_DIR/mihomo.bak"
 mv mihomo "$INSTALL_DIR/mihomo"
 chmod +x "$INSTALL_DIR/mihomo"
}

geo(){
 BASE=https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest
 for f in geoip.dat geosite.dat country.mmdb; do
   curl -fL "$BASE/$f" -o "$CONFIG_DIR/$f"
 done
}

config(){
 [ -f "$CONFIG_DIR/config.yaml" ] && return
cat >"$CONFIG_DIR/config.yaml"<<EOF
mixed-port: 7893
allow-lan: true
mode: rule
log-level: info
external-controller: 0.0.0.0:9090
secret: ""
dns:
  enable: true
EOF
}

service(){
cat >"$SERVICE"<<EOF
[Unit]
Description=Mihomo
After=network.target
[Service]
ExecStart=$INSTALL_DIR/mihomo -d $CONFIG_DIR
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
 systemctl daemon-reload
 systemctl enable mihomo
}

checkcfg(){ "$INSTALL_DIR/mihomo" -t -d "$CONFIG_DIR"; }

install_all(){
 deps; dirs; download; geo; config; service; checkcfg
 systemctl restart mihomo
 systemctl --no-pager status mihomo || true
}

case "$1" in
 install) install_all;;
 update) download; checkcfg; systemctl restart mihomo;;
 geo) geo;;
 start) systemctl start mihomo;;
 stop) systemctl stop mihomo;;
 restart) systemctl restart mihomo;;
 status) systemctl status mihomo;;
 check) checkcfg; echo OK;;
 uninstall) systemctl disable --now mihomo||true; rm -f "$SERVICE"; systemctl daemon-reload; rm -rf "$INSTALL_DIR";;
 *) echo "Usage: $0 {install|update|geo|start|stop|restart|status|check|uninstall}";;
esac

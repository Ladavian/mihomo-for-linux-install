# mihomo LXC 一键安装脚本

这个仓库提供一个面向 LXC 容器的 mihomo 安装脚本，适合放到 GitHub 后通过一行命令重复安装。脚本会在安装前检查容器基础依赖、systemd、LXC/TUN 能力，自动下载 MetaCubeX/mihomo release、写入 systemd 服务，并生成默认配置或拉取你的订阅配置。

参考了 [`nelvko/clash-for-linux-install`](https://github.com/nelvko/clash-for-linux-install) 的“一键入口 + 自动安装 + systemd 托管”思路，但脚本逻辑针对 LXC 做了预检查和提示。

## 快速使用

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Ladavian/mihomo-for-linux-install/main/install.sh)
```

使用订阅或远程配置安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Ladavian/mihomo-for-linux-install/main/install.sh) --sub-url "https://example.com/config.yaml"
```

启用 TUN 模式安装：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Ladavian/mihomo-for-linux-install/main/install.sh) --enable-tun --sub-url "https://example.com/config.yaml"
```

国内访问 GitHub release 较慢时，可以加代理前缀：

```bash
MIHOMO_GITHUB_PROXY="https://gh-proxy.com" bash <(curl -fsSL https://raw.githubusercontent.com/Ladavian/mihomo-for-linux-install/main/install.sh)
```

## LXC 安装前检查

脚本会自动检查并尽量补齐容器内基础依赖：

- `curl`
- `ca-certificates`
- `gzip`
- `tar`
- `iproute2`
- `iptables` 或 `nft`
- `systemd`

如果启用 TUN 模式，LXC 容器还需要 `/dev/net/tun` 和 `CAP_NET_ADMIN`。Proxmox 宿主机可参考：

```bash
pct set <CTID> -features nesting=1,keyctl=1
```

如果容器内没有 `/dev/net/tun`，在宿主机的 `/etc/pve/lxc/<CTID>.conf` 增加：

```ini
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
```

然后重启容器：

```bash
pct restart <CTID>
```

## 常用参数

```text
--version <tag>       安装指定 mihomo 版本，例如 v1.19.13
--sub-url <url>       从订阅/远程配置地址下载 config.yaml
--download-url <url>  使用自定义 mihomo 二进制下载地址
--install-dir <dir>   安装目录，默认 /opt/mihomo
--config-dir <dir>    配置目录，默认 /etc/mihomo
--enable-tun          生成配置时启用 tun，并强制检查 LXC TUN 能力
--skip-lxc-check      跳过 LXC/TUN 检查
--no-start            只安装，不启动服务
--force               覆盖已有配置和服务
```

同名环境变量也可使用，例如：

```bash
MIHOMO_VERSION=v1.19.13 MIHOMO_ENABLE_TUN=1 bash install.sh
```

## 安装后文件

```text
/usr/local/bin/mihomo              mihomo 命令
/opt/mihomo/mihomo                 实际二进制
/etc/mihomo/config.yaml            配置文件
/etc/systemd/system/mihomo.service systemd 服务
```

常用命令：

```bash
systemctl status mihomo --no-pager -l
journalctl -u mihomo -f
mihomo -d /etc/mihomo -t
systemctl restart mihomo
```

默认外部控制端口：

```text
http://<LXC-IP>:9090
```

## 卸载

保留配置卸载：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Ladavian/mihomo-for-linux-install/main/uninstall.sh)
```

连配置一起删除：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Ladavian/mihomo-for-linux-install/main/uninstall.sh) --purge
```

## 注意

默认生成的配置只有 `DIRECT`，不会自带代理节点。生产使用建议通过 `--sub-url` 写入你自己的 mihomo 配置，或安装后编辑 `/etc/mihomo/config.yaml`。

# OP-builds

ImmortalWrt 自编译固件（多设备单仓库，统一 `openwrt-25.12` 分支）。每条 workflow 只做编译与发布，配置按设备放在 `devices/` 下。

## 设备一览

| 设备 | 目录 | 目标 | Tag 前缀 | 产物 |
|---|---|---|---|---|
| Phicomm N1（S905D） | `devices/n1` | armsr/armv8 → openwrt_packit | `N1-` | `.img.xz` + 可选 `rootfs.tar.gz` |
| ASUS RT-ACRH17 / AC42U | `devices/ac42u` | ipq40xx/generic | `ACRH17-` | `.bin` |
| P&W R619AC 128M | `devices/r619ac` | ipq40xx/generic | `R619AC-` / `R619AC-MAIN-` | `.bin` |

源码统一 `immortalwrt/immortalwrt` 的 `openwrt-25.12` 分支；runner：N1 用 `ubuntu-24.04`，ipq40xx 用 `ubuntu-22.04`。

## 触发方式

Actions → 选择 workflow → Run workflow：

- **Build Amlogic (N1)**：`inject_mihomo`、`upload_rootfs`、`ssh_debug`
- **Build ipq40xx (ACRH17 / R619AC)**：`device`、`lan_mode`（client-static / main-router）、LAN 覆盖参数（留空用 `meta.json` 默认值）

## OTA（仅 N1）

`devices/n1/files/etc/config/amlogic` 已指向本仓库。luci-app-amlogic 的匹配规则（源码 `amlogic_check_firmware.sh`）是：

1. 在 releases 前 5 页里找**第一个 tag 名包含关键字**的版本 → 关键字 `N1-`，所以 `ACRH17-*` / `R619AC-*` 不会被选中；
2. 在该 release 的资产里，只认同时满足三个条件的文件：文件名含 `_<BOARD>_`（这里 `_n1_`）、含 `k<主版本.次版本>.`（这里 `k6.6.`）、以 `amlogic_firmware_suffix` 结尾（`.img.xz`）。

因此同仓库里其他机型的 `.bin`、`rootfs.tar.gz` 都不会被误当成 N1 固件。**代价是 N1 的产物命名不能改**：必须保留 `openwrt_s905d_n1_..._k6.6.xxx.img.xz` 这个形状。

## 目录约定

```
devices/<device>/
├── meta.json              # 源分支、config 路径、tag 前缀、保留数、默认 LAN
├── config                 # OpenWrt .config（无 BOM，完整文件，不用 fragment）
├── files/                 # 覆盖到 openwrt/files 的板级文件（可选）
├── network/*.tmpl         # LAN 配置模板（ipq40xx 用，@LAN_IP@ 等占位符）
└── scripts/               # diy.sh / 打包脚本 / 注入脚本
```

新增设备 = 加一个目录 + 在对应 workflow 的 `device` 选项里加一项。

## 发布与保留

- Tag 形如 `<PREFIX>-YYYYMMDD-HHMMSS`，按设备前缀区分。
- 旧版本自动清理，**按前缀过滤后**才计 `keep_latest`，不会误删别的设备。
- N1 保留 2 个，ipq40xx 保留 3 个（见各 `meta.json` 的 `keep_releases`）。

## 许可与致谢

构建脚本、打包脚本来自 [unifreq/openwrt_packit](https://github.com/unifreq/openwrt_packit)、[ophub](https://github.com/ophub)、[P3TERX](https://github.com/P3TERX) 等开源项目，遵循其原始许可。

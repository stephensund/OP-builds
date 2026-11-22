# 构建与维护说明

## 1. 源码分支

统一 `openwrt-25.12`，写在两个 workflow 的 `env.SOURCE_BRANCH`：

- `build-amlogic.yml`
- `build-ipq40xx.yml`

`devices/<device>/meta.json` 里的 `source.branch` 只作记录（workflow 不读它），改分支时两处一起改，避免文档与实现不一致。

换分支必须确认 `.config` 仍匹配新分支的符号，否则 `make defconfig` 会**静默丢弃**不认识的包。ipq40xx workflow 里已有 `Render config & audit dropped packages` 步骤，构建日志会直接列出被丢弃的包名；N1 也可照此加，或在本地比对：

```bash
grep -c '^CONFIG_PACKAGE_.*=y' devices/<d>/config   # 期望值
grep -c '^CONFIG_PACKAGE_.*=y' openwrt/.config      # make defconfig 之后
```

从 24.10 升到 25.12 时，ipq40xx 的内核由 6.6 变为 6.12，`kmod-cpufreq-ipq40xx` 这类带 SoC 后缀的模块最容易消失——被丢弃不等于构建失败，但会少功能，务必看审计日志。

## 2. 重新生成某设备的 .config

```bash
# 在 CI 环境或本地 Linux 里，克隆对应分支后：
make menuconfig
# 保存后取 openwrt/.config，覆盖 devices/<device>/config
```

注意：文件必须是 **UTF-8 无 BOM**。带 BOM 时 kconfig 会把它当成非法行首符号。
检查：`head -c 3 devices/n1/config | od -An -tx1` 应为 `23 20 3d`（`# =`），不是 `ef bb bf`。

不要把 menuconfig 生成的注释性 `# CONFIG_X is not set` 之外的自动内容手工改动；两份 iq40xx 配置只差 4 行（device profile、cpufreq 模块、注释），改一份时记得同步另一份。

## 3. 新增一台设备

1. `cp -r devices/ac42u devices/<new>`，改 `meta.json` 的 `name` / `profile` / `tag_prefix` / `lan_ip`。
2. 替换 `config` 里的 `CONFIG_TARGET_*_DEVICE_<profile>=y`。
3. 在 `build-ipq40xx.yml` 的 `device` choice 里加一项。
4. 首次构建后确认产物文件名与 tag 前缀。

## 4. 保留策略为什么不共用 keep_latest

`dev-drprasad/delete-older-releases` 的行为是：**先按 `delete_tag_pattern` 过滤，再排序取前 N 个保留**（见其 `index.js`）。
所以多设备共库时必须给每个设备独立前缀，否则 `keep_latest: 2` 会把另一台设备的固件一起清掉。

`R619AC-` 是 `R619AC-MAIN-` 的前缀，普通版用 `^R619AC-(?!MAIN)` 排除主路由固件。

该 action 已标记不再维护，但仍可用；若将来失效，可换成 `gh release list` + `gh release delete` 的手写步骤。

## 5. N1 的 Mihomo 注入

`devices/n1/scripts/inject-mihomo.sh` 会在 rootfs 里放入：

- `/etc/openclash/core/clash_meta`（Mihomo Alpha，arm64）
- `/etc/openclash/geoip.dat`、`/etc/openclash/geosite.dat`

下载失败时**不会**中断构建（与原 workflow 一致），只在日志里打 ⚠️ 并跳过。若希望失败即中断，把脚本里的 `MIHO_OK=0` 分支改成 `exit 1`。

## 6. N1 的 OTA 匹配规则（合并仓库必须理解的一条）

插件源码 `luci-app-amlogic/root/usr/share/amlogic/amlogic_check_firmware.sh` 里的实际逻辑：

```awk
href_pattern  = "/releases/download/[^\"]*_" board "_[^\"]*k" kver "\\.[0-9]+[^\"]*" suffix
block_pattern = ".*_" board "_.*k" kver "\\.[0-9]+.*" suffix
```

`board` 来自设备上的 `/etc/flippy-openwrt-release`（打包时写入 `BOARD=n1`），`kver` 来自 `uname -r` 取 `主.次`（6.6），`suffix` 来自 `amlogic_firmware_suffix`。

也就是说，OTA 只认**同时**满足这三条的文件：

1. 文件名含 `_n1_` → 其他机型的 `_ac42u_` / `_r619ac_` 天然不匹配；
2. 含 `k6.6.` → 换内核大版本后要同步改 `amlogic_kernel_branch`；
3. 以 `.img.xz` 结尾 → `rootfs.tar.gz` 和 `.bin` 天然不匹配。

Tag 是另一层过滤：脚本只翻 releases 前 5 页，取**第一个 tag 名包含 `amlogic_firmware_tag`** 的版本。当前设为 `N1-`，因此 `ACRH17-*` / `R619AC-*` 不会被选中。

两个推论：

- **N1 产物文件名不能改**（`openwrt_s905d_n1_<ver>_k6.6.xxx.img.xz` 这个形状被正则写死）；
- **tag 前缀不能去掉 `N1-`**，否则 OTA 直接找不到版本（会报 "No matching tags found"）。

实测现有产物：`openwrt_s905d_n1_R26.03.25_k6.6.120-flippy-94+.img.xz`，三条全部命中。

## 7. 本地验证工作流语法

```bash
# 需要 actionlint（单文件二进制）
actionlint -shellcheck= -pyflakes= .github/workflows/*.yml
```

## 8. 已知差异（迁移时保留原行为）

- N1 的 `mk_s905d_n1.sh` 依赖 openwrt_packit 自身的 `files/` 与 `make.env`：它被 packit **复制到打包目录后**执行，所以脚本里的 `${PWD}` 指向打包目录，与仓库布局无关。子目录路径可以正常使用。
- N1 的 `.config` 是 25.12 用的那份；ipq40xx 的两份是从 24.10 带过来的，第一次 25.12 构建后请看审计日志，把被丢弃的包删掉或找替代品。

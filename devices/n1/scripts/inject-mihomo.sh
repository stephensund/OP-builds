#!/bin/bash
# 把 Mihomo Alpha 内核 + GEOIP/GEOSITE 注入已编译好的 rootfs.tar.gz
# 用法：在仓库根目录执行  bash devices/n1/scripts/inject-mihomo.sh
# 依赖：GITHUB_TOKEN（gh api 取版本号）、curl、gunzip、tar
set -uo pipefail

ROOTFS_GLOB="openwrt/bin/targets/armsr/armv8"
ORIGINAL_ROOTFS=$(ls -1 ${ROOTFS_GLOB}/*rootfs.tar.gz 2>/dev/null | head -n 1)
if [ -z "${ORIGINAL_ROOTFS}" ] || [ ! -f "${ORIGINAL_ROOTFS}" ]; then
  echo "❌ 编译失败：未生成 rootfs.tar.gz"
  exit 1
fi
echo "原始 ROOTFS: ${ORIGINAL_ROOTFS}"

rm -rf rootfs_work mihomo_core geo_files
mkdir -p rootfs_work mihomo_core geo_files
tar -xzf "${ORIGINAL_ROOTFS}" -C rootfs_work

# ── 下载函数（gzip 压缩文件专用，下载后解压并删除 .gz） ──
download_with_retry() {
  local name="$1"
  local url="$2"
  local dest="$3"
  local max_retry=3
  local i=1

  while [ $i -le $max_retry ]; do
    echo "▶ [$name] 下载尝试 $i/$max_retry ..."

    if curl -fL "$url" -o "$dest.gz" 2>/dev/null; then
      # gunzip -c 输出到文件（保留原文件名在 gzip 头中）
      if gunzip -c "$dest.gz" > "$dest" 2>/dev/null; then
        rm -f "$dest.gz"
        if [ -s "$dest" ]; then
          echo "✅ [$name] 下载成功"
          chmod +x "$dest"
          return 0
        else
          echo "⚠️ [$name] 解压后文件为空"
        fi
      else
        echo "⚠️ [$name] 解压失败"
      fi
    else
      echo "⚠️ [$name] 下载失败（HTTP 错误）"
    fi

    i=$((i + 1))
    [ $i -le $max_retry ] && echo "   等待 2 秒后重试..." && sleep 2
  done

  echo "❌ [$name] 下载失败，已重试 $max_retry 次"
  return 1
}

# ── 下载函数（直落文件，无需解压，用于 .dat 等原始文件） ──
download_direct() {
  local name="$1"
  local url="$2"
  local dest="$3"
  local max_retry=3
  local i=1

  while [ $i -le $max_retry ]; do
    echo "▶ [$name] 下载尝试 $i/$max_retry ..."

    if curl -fL "$url" -o "$dest" 2>/dev/null; then
      if [ -s "$dest" ]; then
        echo "✅ [$name] 下载成功"
        return 0
      else
        echo "⚠️ [$name] 下载后文件为空"
      fi
    else
      echo "⚠️ [$name] 下载失败（HTTP 错误）"
    fi

    i=$((i + 1))
    [ $i -le $max_retry ] && echo "   等待 2 秒后重试..." && sleep 2
  done

  echo "❌ [$name] 下载失败，已重试 $max_retry 次"
  return 1
}

# ── 获取 Mihomo Alpha 版本号（带重试） ──
# 通过 GitHub API 提取 mihomo-linux-arm64-alpha-*.gz 的实际版本号
MAX_RETRY=3
i=1
MIHO_VERSION=""
while [ $i -le $MAX_RETRY ]; do
  echo "▶ [获取 Mihomo 版本号] 尝试 $i/$MAX_RETRY ..."
  # 使用 GitHub API（gh api 有 GITHUB_TOKEN 加持，不易被限速）
  MIHO_VERSION=$(gh api \
    --jq '.assets[].browser_download_url' \
    "repos/MetaCubeX/mihomo/releases/tags/Prerelease-Alpha" \
    | grep 'mihomo-linux-arm64-alpha-' | grep '\.gz$' \
    | head -n 1 \
    | grep -oP 'mihomo-linux-arm64-alpha-\K[a-f0-9]+(?=\.gz$)')
  if [ -n "$MIHO_VERSION" ]; then
    echo "✅ Mihomo Alpha 版本: $MIHO_VERSION"
    break
  fi
  i=$((i + 1))
  [ $i -le $MAX_RETRY ] && echo "   等待 2 秒后重试..." && sleep 2
done

if [ -z "$MIHO_VERSION" ]; then
  echo "❌ Mihomo 内核：无法获取版本号，已重试 $MAX_RETRY 次"
  exit 1
fi

CORE_URL="https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/mihomo-linux-arm64-alpha-${MIHO_VERSION}.gz"
echo "下载链接: $CORE_URL"

# ── 下载 Mihomo Alpha 内核 ──
if download_with_retry "Mihomo Alpha 内核" "$CORE_URL" "mihomo_core/mihomo"; then
  MIHO_OK=1
else
  MIHO_OK=0
fi

# ── 下载 GEOIP 数据库（直落文件，无需解压） ──
if download_direct "GEOIP 数据库" \
  "https://raw.githubusercontent.com/Loyalsoldier/geoip/release/geoip.dat" \
  "geo_files/geoip.dat"; then
  GEOIP_OK=1
else
  GEOIP_OK=0
fi

# ── 下载 GEOSITE 数据库（直落文件，无需解压） ──
if download_direct "GEOSITE 数据库" \
  "https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/geosite.dat" \
  "geo_files/geosite.dat"; then
  GEOSITE_OK=1
else
  GEOSITE_OK=0
fi

# ── 安装到 OpenClash 路径 ──
# 内核: /etc/openclash/core/clash_meta
# GEO:  /etc/openclash/
mkdir -p rootfs_work/etc/openclash/core

if [ "$MIHO_OK" -eq 1 ]; then
  cp -f mihomo_core/mihomo rootfs_work/etc/openclash/core/clash_meta
  chmod +x rootfs_work/etc/openclash/core/clash_meta
  echo "✅ Mihomo Alpha 内核已安装到 /etc/openclash/core/clash_meta"
else
  echo "⚠️ 跳过 Mihomo 内核安装（下载失败）"
fi

if [ "$GEOIP_OK" -eq 1 ]; then
  cp -f geo_files/geoip.dat rootfs_work/etc/openclash/geoip.dat
  echo "✅ GEOIP 数据库已安装到 /etc/openclash/geoip.dat"
else
  echo "⚠️ 跳过 GEOIP 安装（下载失败）"
fi

if [ "$GEOSITE_OK" -eq 1 ]; then
  cp -f geo_files/geosite.dat rootfs_work/etc/openclash/geosite.dat
  echo "✅ GEOSITE 数据库已安装到 /etc/openclash/geosite.dat"
else
  echo "⚠️ 跳过 GEOSITE 安装（下载失败）"
fi

# ── 重新打包 rootfs ──
echo "▶ 正在重新打包 rootfs..."
rm -f "$ORIGINAL_ROOTFS"
tar -czf "$ORIGINAL_ROOTFS" -C rootfs_work .

# ── 清理临时文件 ──
rm -rf rootfs_work mihomo_core geo_files
echo ""
echo "=== 注入结果汇总 ==="
echo "  Mihomo Alpha:  $([ "$MIHO_OK" -eq 1 ] && echo '✅ 已注入' || echo '❌ 失败')"
echo "  GEOIP:         $([ "$GEOIP_OK" -eq 1 ] && echo '✅ 已注入' || echo '❌ 失败')"
echo "  GEOSITE:       $([ "$GEOSITE_OK" -eq 1 ] && echo '✅ 已注入' || echo '❌ 失败')"
echo "===================="
if [ "$MIHO_OK" -eq 1 ] && [ "$GEOIP_OK" -eq 1 ] && [ "$GEOSITE_OK" -eq 1 ]; then
  echo "✅ Mihomo + GEO 注入完成"
fi
ls -lh "$ORIGINAL_ROOTFS"

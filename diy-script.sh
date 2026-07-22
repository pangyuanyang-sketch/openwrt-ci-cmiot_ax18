#!/bin/bash

# 修改默认IP
sed -i 's/192.168.1.1/192.168.30.1/g' package/base-files/files/bin/config_generate

# Git稀疏克隆，只克隆指定目录到本地
git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b "$branch" --single-branch --filter=blob:none --sparse "$repourl"
  repodir=$(echo "$repourl" | awk -F '/' '{print $(NF)}')
  cd "$repodir" && git sparse-checkout set "$@"
  mv -f "$@" ../package
  cd .. && rm -rf "$repodir"
}

# SSR Plus（已禁用，保留配置便于以后恢复）
# rm -rf feeds/luci/applications/luci-app-ssr-plus
# rm -rf feeds/packages/net/{xray-core,sing-box,chinadns-ng,dns2socks,geoview,shadowsocks-rust,shadowsocksr-libev,v2ray-plugin}
# git clone --depth=1 -b dev https://github.com/fw876/helloworld package/helloworld

# PassWall（已禁用，保留配置便于以后恢复）
# rm -rf feeds/luci/applications/luci-app-passwall
# git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall-packages
# git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-app-passwall

# Nikki 官方 feed（LiBwrt 源码未内置）
if ! grep -q '^src-git nikki ' feeds.conf.default; then
  echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf.default
fi

# Argon 使用 LuCI feed 自带版本，确保与当前 Ucode 模板引擎兼容

# iStore（已禁用，保留配置便于以后恢复）
# git_sparse_clone main https://github.com/linkease/istore-ui app-store-ui
# git_sparse_clone main https://github.com/linkease/istore luci

# 设置 Argon 为默认主题
mkdir -p package/base-files/files/etc/uci-defaults
cat > package/base-files/files/etc/uci-defaults/99-set-argon-theme <<'EOF'
#!/bin/sh
uci set luci.main.mediaurlbase='/luci-static/argon'
uci commit luci
exit 0
EOF
chmod +x package/base-files/files/etc/uci-defaults/99-set-argon-theme

# 修改本地时间格式
find package feeds -path '*/autocore/files/*/index.htm' -type f -exec sed -i 's/os.date()/os.date("%a %Y-%m-%d %H:%M:%S")/g' {} \;

# 修改版本为编译日期
if [ -f package/lean/default-settings/files/zzz-default-settings ]; then
  date_version=$(date +"%y.%m.%d")
  orig_version=$(grep "DISTRIB_REVISION=" package/lean/default-settings/files/zzz-default-settings | awk -F "'" '{print $2}')
  if [ -n "$orig_version" ]; then
    sed -i "s/${orig_version}/R${date_version} by Pang/g" package/lean/default-settings/files/zzz-default-settings
  fi
fi

# 修复 hostapd 报错
if [ -f "$GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch" ] && [ -d package/network/services/hostapd/patches ]; then
  cp -f "$GITHUB_WORKSPACE/scripts/011-fix-mbo-modules-build.patch" package/network/services/hostapd/patches/011-fix-mbo-modules-build.patch
fi

# 修复 armv8 设备 xfsprogs 报错
if [ -f feeds/packages/utils/xfsprogs/Makefile ]; then
  sed -i 's/TARGET_CFLAGS.*/TARGET_CFLAGS += -DHAVE_MAP_SYNC -D_LARGEFILE64_SOURCE/g' feeds/packages/utils/xfsprogs/Makefile
fi

# 修改 Makefile
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -r -i sed -i 's/..\/..\/luci.mk/$(TOPDIR)\/feeds\/luci\/luci.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -r -i sed -i 's/..\/..\/lang\/golang\/golang-package.mk/$(TOPDIR)\/feeds\/packages\/lang\/golang\/golang-package.mk/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -r -i sed -i 's/PKG_SOURCE_URL:=@GHREPO/PKG_SOURCE_URL:=https:\/\/github.com/g' {}
find package/*/ -maxdepth 2 -path "*/Makefile" | xargs -r -i sed -i 's/PKG_SOURCE_URL:=@GHCODELOAD/PKG_SOURCE_URL:=https:\/\/codeload.github.com/g' {}

./scripts/feeds update -a

# 25.12 的 Kconfig 会把两个 Mihomo provider 的 CONFLICTS 解析成循环依赖；
# Nikki 固件只使用稳定版 mihomo-meta，因此在生成包索引前排除 alpha 变体。
rm -rf feeds/nikki/mihomo-alpha package/feeds/nikki/mihomo-alpha
./scripts/feeds update -i nikki

./scripts/feeds install -a

# 内置 Mihomo 轻量 GeoIP 数据库；保留标准文件名，首次启动无需联网下载。
geoip_tmp_dir="$(mktemp -d)"
geoip_lite_url="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip-lite.metadb"
if ! curl -fL --retry 3 --retry-delay 2 -o "$geoip_tmp_dir/geoip-lite.metadb" "$geoip_lite_url" || \
   ! curl -fL --retry 3 --retry-delay 2 -o "$geoip_tmp_dir/geoip-lite.metadb.sha256sum" "$geoip_lite_url.sha256sum" || \
   ! (cd "$geoip_tmp_dir" && sha256sum -c geoip-lite.metadb.sha256sum); then
  echo "下载或校验 geoip-lite.metadb 失败" >&2
  rm -rf "$geoip_tmp_dir"
  exit 1
fi
install -Dm0644 "$geoip_tmp_dir/geoip-lite.metadb" files/etc/nikki/run/geoip.metadb
rm -rf "$geoip_tmp_dir"

# feeds 最终更新后再替换背景，避免自定义图片被覆盖
if [ -f "$GITHUB_WORKSPACE/images/bg1.jpg" ] && [ -d feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/img ]; then
  cp -f "$GITHUB_WORKSPACE/images/bg1.jpg" feeds/luci/themes/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg
fi

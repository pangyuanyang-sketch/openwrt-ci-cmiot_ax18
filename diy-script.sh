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

# 移除要替换的包
rm -rf feeds/luci/themes/luci-theme-argon
rm -rf feeds/luci/applications/luci-app-passwall
rm -rf feeds/luci/applications/luci-app-ssr-plus

# SSR Plus
git clone --depth=1 -b main https://github.com/fw876/helloworld package/helloworld

# PassWall
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages package/openwrt-passwall-packages
git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall package/luci-app-passwall

# Themes，只保留 Argon
git clone --depth=1 -b 18.06 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/jerrykuku/luci-app-argon-config package/luci-app-argon-config

# iStore
git_sparse_clone main https://github.com/linkease/istore-ui app-store-ui
git_sparse_clone main https://github.com/linkease/istore luci

if [ -f "$GITHUB_WORKSPACE/images/bg1.jpg" ] && [ -d package/luci-theme-argon/htdocs/luci-static/argon/img ]; then
  cp -f "$GITHUB_WORKSPACE/images/bg1.jpg" package/luci-theme-argon/htdocs/luci-static/argon/img/bg1.jpg
fi

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

# 取消主题默认设置
find package/luci-theme-*/* -type f -name '*luci-theme-*' -print -exec sed -i '/set luci.main.mediaurlbase/d' {} \;

./scripts/feeds update -a
./scripts/feeds install -a

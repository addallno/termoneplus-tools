#!/bin/bash
# 用 musl 交叉编译 dropbear（非 PIE 静态），替换 assets 中 NDK static-pie 版（Android 7 段错误）
# 产物: term/src/main/assets/tools/usr/bin/{dropbear,dropbearkey}
set -eux

DROPBEAR_VERSION="2026.94"
CROSS=armv7-unknown-linux-musleabihf-
TC_DIR=/opt/armv7-unknown-linux-musleabihf

# 1. musl 交叉工具链
curl -fSL --connect-timeout 30 --retry 3 --retry-delay 5 \
  -o /tmp/musl.tar.xz https://github.com/cross-tools/musl-cross/releases/download/20260515/armv7-unknown-linux-musleabihf.tar.xz
tar -xJf /tmp/musl.tar.xz -C /opt
export PATH="$TC_DIR/bin:$PATH"
${CROSS}gcc --version | head -1

# 2. dropbear 源码 + Android patch
curl -fSL --connect-timeout 30 --retry 3 --retry-delay 5 \
  -o /tmp/dropbear.tar.bz2 "https://dropbear.nl/mirror/releases/dropbear-${DROPBEAR_VERSION}.tar.bz2"
tar xjf /tmp/dropbear.tar.bz2 -C /tmp
python3 "patches/dropbear-android-user.py" "/tmp/dropbear-${DROPBEAR_VERSION}/src"
cd "/tmp/dropbear-${DROPBEAR_VERSION}"

# 3. musl 静态编译（非 PIE：musl 默认无 -pie）
./configure --host=${CROSS%-} \
  --disable-zlib --disable-pam --disable-shadow \
  CC="${CROSS}gcc" AR="${CROSS}ar" RANLIB="${CROSS}ranlib" STRIP="${CROSS}strip" \
  CFLAGS="-O2 -static" LDFLAGS="-static" \
  CPPFLAGS="-DDROPBEAR_SVR_PASSWORD_AUTH=0"
make -j2 dropbear dropbearkey

# 4. 确认非 PIE 静态
file dropbear dropbearkey
readelf -h dropbear | grep -E "Type|Machine"

# 5. 替换 assets 里的 static-pie 版本（回到 checkout 目录）
cd "$GITHUB_WORKSPACE"
cp "/tmp/dropbear-${DROPBEAR_VERSION}/dropbear"    "term/src/main/assets/tools/usr/bin/dropbear"
cp "/tmp/dropbear-${DROPBEAR_VERSION}/dropbearkey" "term/src/main/assets/tools/usr/bin/dropbearkey"
ls -la "term/src/main/assets/tools/usr/bin/dropbear" "term/src/main/assets/tools/usr/bin/dropbearkey"

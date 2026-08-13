#!/bin/bash
# 附加工具交叉编译：musl 全静态 armv7l（无 bionic 依赖，Android 4.4 直接可执行）
# 输出目录 /tmp/extra-tools/，由「组装工具 assets」step 拷入 assets/tools/usr/bin/
set -eux

CROSS=armv7-unknown-linux-musleabihf-
TC_DIR=/opt/armv7-unknown-linux-musleabihf
OUT=/tmp/extra-tools
mkdir -p "$OUT"

# ---------- 1. musl 交叉工具链（GitHub release，musl.cc 已被 GH Actions 封禁） ----------
curl -fSL --connect-timeout 30 --retry 3 --retry-delay 5 \
  -o /tmp/musl.tar.xz https://github.com/cross-tools/musl-cross/releases/download/20260515/armv7-unknown-linux-musleabihf.tar.xz
tar -xJf /tmp/musl.tar.xz -C /opt
export PATH="$TC_DIR/bin:$PATH"
${CROSS}gcc --version | head -1

# ---------- 2. OpenBSD netcat（依赖 libbsd → 交叉编译静态 libbsd） ----------
git clone --depth 1 https://github.com/adamallaf/openbsd-netcat /tmp/nc
sudo apt-get update -qq || true
sudo apt-get install -y -qq autoconf automake libtool pkg-config texinfo
git clone --depth 1 --branch 0.12.2 https://github.com/guillemj/libbsd /tmp/libbsd
cd /tmp/libbsd
./autogen
./configure --host="${CROSS%%-}" --prefix=/tmp/bsd \
  --disable-shared --enable-static --without-libmd
make -j2
make install
${CROSS}gcc -static -O2 -I/tmp/bsd/include -o "$OUT/nc" \
  /tmp/nc/netcat.c /tmp/nc/atomicio.c /tmp/nc/socks.c \
  -L/tmp/bsd/lib -lbsd

# ---------- 3. bash（--enable-static-link 静态链接） ----------
curl -fsSL -o /tmp/bash.tar.gz https://ftp.gnu.org/gnu/bash/bash-5.2.tar.gz
tar -xzf /tmp/bash.tar.gz -C /tmp
cd /tmp/bash-5.2
./configure --host="${CROSS%%-}" --disable-shared --enable-static-link \
  --without-bash-malloc --disable-nls --without-libintl-prefix \
  --without-libiconv-prefix --without-readline
make -j2
cp bash "$OUT/bash"

# ---------- 4. ncurses（供 nano/zsh 使用） ----------
curl -fsSL -o /tmp/ncurses.tar.gz https://ftp.gnu.org/gnu/ncurses/ncurses-6.4.tar.gz
tar -xzf /tmp/ncurses.tar.gz -C /tmp
cd /tmp/ncurses-6.4
./configure --host="${CROSS%%-}" --prefix=/tmp/ncurses-install \
  --enable-static --disable-shared --without-debug --without-ada \
  --without-cxx --without-manpages --without-tests --without-pkg-config
make -j2
make install

# ---------- 5. nano（依赖 ncurses） ----------
curl -fsSL -o /tmp/nano.tar.gz https://ftp.gnu.org/gnu/nano/nano-8.2.tar.gz
tar -xzf /tmp/nano.tar.gz -C /tmp
cd /tmp/nano-8.2
CPPFLAGS="-I/tmp/ncurses-install/include" \
LDFLAGS="-static -L/tmp/ncurses-install/lib" \
./configure --host="${CROSS%%-}" --enable-static --disable-shared \
  --disable-nls --without-iconv --disable-utf8
make -j2
cp src/nano "$OUT/nano"

# ---------- 6. zsh（依赖 ncurses，静态链接） ----------
curl -fsSL -o /tmp/zsh.tar.xz https://sourceforge.net/projects/zsh/files/zsh/5.9/zsh-5.9.tar.xz/download
tar -xJf /tmp/zsh.tar.xz -C /tmp
cd /tmp/zsh-5.9
CPPFLAGS="-I/tmp/ncurses-install/include" \
LDFLAGS="-static -L/tmp/ncurses-install/lib" \
./configure --host="${CROSS%%-}" --disable-dynamic --disable-gdbm \
  --without-tcsetpgrp
make -j2
cp Src/zsh "$OUT/zsh"

# ---------- 7. micropython（unix port minimal，无外部依赖） ----------
git clone --depth 1 --branch v1.23.0 https://github.com/micropython/micropython /tmp/micropython
cd /tmp/micropython
make -C mpy-cross -j2
make -C ports/unix VARIANT=minimal CROSS_COMPILE="$CROSS" LDFLAGS="-static" -j2
cp ports/unix/build-minimal/micropython "$OUT/micropython"

# ---------- 8. openssl 静态（供 curl 使用） ----------
curl -fsSL -o /tmp/openssl.tar.gz https://github.com/openssl/openssl/releases/download/openssl-3.3.0/openssl-3.3.0.tar.gz
tar -xzf /tmp/openssl.tar.gz -C /tmp
cd /tmp/openssl-3.3.0
./Configure linux-armv4 -static --cross-compile-prefix="$CROSS" \
  --prefix=/tmp/ssl-install no-shared no-asm no-tests no-docs \
  no-threads no-ssl3 no-zlib
make -j2
make install_sw

# ---------- 9. curl（静态 + openssl） ----------
curl -fsSL -o /tmp/curl.tar.gz https://curl.se/download/curl-8.9.1.tar.gz
tar -xzf /tmp/curl.tar.gz -C /tmp
cd /tmp/curl-8.9.1
CPPFLAGS="-I/tmp/ssl-install/include" \
LDFLAGS="-static -L/tmp/ssl-install/lib" \
LIBS="-lssl -lcrypto" \
./configure --host="${CROSS%%-}" --disable-shared --enable-static \
  --with-openssl=/tmp/ssl-install --without-ca-bundle --without-ca-path \
  --disable-ldap --disable-ldaps --disable-manual --disable-threaded-resolver
make -j2
cp src/curl "$OUT/curl"

ls -la "$OUT/"

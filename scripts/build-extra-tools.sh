#!/bin/bash
# 附加工具交叉编译：musl 全静态 armv7l（无 bionic 依赖，Android 4.4 直接可执行）
# 输出目录 /tmp/extra-tools/，由「组装工具 assets」step 拷入 assets/tools/usr/bin/
set -eux

CROSS=arm-linux-musleabihf-
TC_DIR=/opt/arm-linux-musleabihf-cross
OUT=/tmp/extra-tools
SYSROOT="$TC_DIR/arm-linux-musleabihf"
mkdir -p "$OUT"

# ---------- 1. musl 交叉工具链 ----------
curl -fsSL -o /tmp/musl.tgz https://musl.cc/arm-linux-musleabihf-cross.tgz
tar -xzf /tmp/musl.tgz -C /opt
export PATH="$TC_DIR/bin:$PATH"
${CROSS}gcc --version | head -1

# ---------- 2. OpenBSD netcat ----------
git clone --depth 1 https://github.com/tabos/openbsd-netcat /tmp/nc
${CROSS}gcc -static -O2 -o "$OUT/nc" /tmp/nc/netcat.c

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

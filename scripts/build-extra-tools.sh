#!/bin/bash
# 附加工具交叉编译：musl 全静态 armv7l（无 bionic 依赖，Android 4.4 直接可执行）
# 只编译 Termux4All 未内置的工具：nc、zsh、micropython、wget、micro
# bash/curl/nano/aria2c/nnn/sl/busybox 已由 Termux4All v0.83 提取进 assets（见 build.yml 组装步骤）
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

# ---------- 2. OpenBSD netcat（依赖 libbsd；libbsd 依赖 libmd 提供 MD5，musl 无 MD5） ----------
git clone --depth 1 https://github.com/adamallaf/openbsd-netcat /tmp/nc
sudo apt-get install -y -qq autoconf automake libtool pkg-config texinfo

# 2a. libmd（提供 MD5Init 等；libbsd 必需）
git clone --depth 1 --branch 1.2.0 https://github.com/guillemj/libmd /tmp/libmd
cd /tmp/libmd
./autogen
./configure --host="${CROSS%%-}" --prefix=/tmp/bsd --disable-shared --enable-static
make -j2
make install

# 2b. libbsd
git clone --depth 1 --branch 0.12.2 https://github.com/guillemj/libbsd /tmp/libbsd
cd /tmp/libbsd
./autogen
CPPFLAGS="-I/tmp/bsd/include" LDFLAGS="-L/tmp/bsd/lib" \
./configure --host="${CROSS%%-}" --prefix=/tmp/bsd \
  --disable-shared --enable-static --with-libmd
make -j2
make install

# b64_ntop 仅用于 SOCKS5 认证（musl/libbsd 条件下 libbsd 不提供该符号），stub 掉即可
cat > /tmp/ncbsd_b64stub.c <<'EOF'
#include <stddef.h>
#include <stdint.h>
int b64_ntop(const uint8_t *src, size_t srclength, char *target, size_t targsize) {
    (void)src; (void)srclength; (void)target; (void)targsize;
    return -1;
}
EOF

${CROSS}gcc -static -O2 -I/tmp/bsd/include \
  -Wno-incompatible-pointer-types -Wno-implicit-function-declaration \
  -include bsd/stdlib.h \
  -o "$OUT/nc" /tmp/nc/netcat.c /tmp/nc/atomicio.c /tmp/nc/socks.c /tmp/ncbsd_b64stub.c \
  -L/tmp/bsd/lib -lbsd -lmd

# ---------- 3. ncurses（供 zsh 使用） ----------
curl -fsSL -o /tmp/ncurses.tar.gz https://ftp.gnu.org/gnu/ncurses/ncurses-6.2.tar.gz
tar -xzf /tmp/ncurses.tar.gz -C /tmp
cd /tmp/ncurses-6.2
./configure --host="${CROSS%%-}" --prefix=/tmp/ncurses-install \
  --enable-static --disable-shared --without-debug --without-ada \
  --without-cxx --without-manpages --without-tests --without-pkg-config \
  --without-progs
make -j2
make install

# ---------- 4. zsh（依赖 ncurses，静态链接） ----------
curl -fsSL -o /tmp/zsh.tar.xz https://sourceforge.net/projects/zsh/files/zsh/5.9/zsh-5.9.tar.xz/download
tar -xJf /tmp/zsh.tar.xz -C /tmp
cd /tmp/zsh-5.9
# zsh 5.9 自带 boolcodes/numcodes/strcodes 有与 ncurses term.h(const) 冲突类型，禁用自含定义改用 ncurses 提供的
sed -i 's/#ifndef HAVE_BOOLCODES/#if 0/; s/#ifndef HAVE_NUMCODES/#if 0/' Src/Modules/termcap.c
CPPFLAGS="-I/tmp/ncurses-install/include" \
LDFLAGS="-static -L/tmp/ncurses-install/lib" \
./configure --host="${CROSS%%-}" --disable-dynamic --disable-gdbm \
  --without-tcsetpgrp
make -j2
cp Src/zsh "$OUT/zsh"

# ---------- 5. micropython（unix port minimal，无外部依赖） ----------
git clone --depth 1 --branch v1.23.0 https://github.com/micropython/micropython /tmp/micropython
cd /tmp/micropython
make -C mpy-cross -j2
make -C ports/unix VARIANT=minimal CROSS_COMPILE="$CROSS" LDFLAGS="-static" -j2
cp ports/unix/build-minimal/micropython "$OUT/micropython"

# ---------- 6. wget（GNU wget，--disable-* 减依赖后静态） ----------
curl -fsSL -o /tmp/wget.tar.gz https://ftp.gnu.org/gnu/wget/wget-1.24.5.tar.gz
tar -xzf /tmp/wget.tar.gz -C /tmp
cd /tmp/wget-1.24.5
./configure --host="${CROSS%%-}" --disable-shared --enable-static \
  --disable-nls --without-ssl --without-libpsl --disable-pcre \
  --disable-iri --without-libiconv-prefix --without-libintl-prefix
make -j2
cp src/wget "$OUT/wget"

# ---------- 7. micro（Go 编辑器，GOOS=android 交叉编译） ----------
cd /tmp
GO111MODULE=on GOOS=android GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go install github.com/zyedidia/micro/v2/cmd/micro@v2.0.13
cp /root/go/bin/micro "$OUT/micro" 2>/dev/null || cp "$(go env GOPATH)/bin/micro" "$OUT/micro"

ls -la "$OUT/"

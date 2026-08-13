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

# ---------- 5. micropython：使用本地现成静态版(assets 已内置)，无需 CI 编译 ----------
echo "micropython: 由用户本地提供，已在 assets 中内置，跳过编译"

# ---------- 6. wget：busybox 自带 http wget + curl(7.68, openssl, https) 已覆盖，不单独编 GNU wget ----------
echo "wget: 由 busybox 内置(libhttp) + curl(https) 覆盖，跳过编译"

# ---------- 7. micro（Go 编辑器，GOOS=android 交叉编译。go install @ver 会因 micro 自带 replace 指令被拒，须本地 build 主模块） ----------
git clone --depth 1 --branch v2.0.13 https://github.com/zyedidia/micro /tmp/micro
cd /tmp/micro
GO111MODULE=on GOFLAGS=-mod=mod GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go build -o "$OUT/micro" ./cmd/micro

# ---------- 8. jq（JSON 处理，依赖 oniguruma，全静态） ----------
# 8a. oniguruma 6.9.9
curl -fsSL -o /tmp/onig.tar.gz https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz
tar -xzf /tmp/onig.tar.gz -C /tmp
cd /tmp/onig-6.9.9 2>/dev/null || cd /tmp/oniguruma-6.9.9
./configure --host="${CROSS%%-}" --prefix=/tmp/onig-install --disable-shared --enable-static \
  CFLAGS="-Wno-error=incompatible-pointer-types"
perl -i -pe 's/int \(\*\)\(ANYARGS\)/int (*)(st_data_t, st_data_t, st_data_t)/ if /st_foreach/' src/st.h
make -j2
make install
# 8b. jq 1.7.1
curl -fsSL -o /tmp/jq.tar.gz https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-1.7.1.tar.gz
tar -xzf /tmp/jq.tar.gz -C /tmp
cd /tmp/jq-1.7.1
CFLAGS="-I/tmp/onig-install/include" \
LDFLAGS="-static -L/tmp/onig-install/lib" \
./configure --host="${CROSS%%-}" --disable-maintainer-mode --disable-shared \
  --with-oniguruma=/tmp/onig-install
make -j2
cp jq "$OUT/jq"

# ---------- 9. yq（YAML 处理，Go 编译） ----------
git clone --depth 1 --branch v4.44.3 https://github.com/mikefarah/yq /tmp/yq
cd /tmp/yq
GO111MODULE=on GOFLAGS=-mod=mod GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 \
  go build -o "$OUT/yq" .

ls -la "$OUT/"

#!/bin/bash
# 用 musl 交叉编译 fish shell 3.7.1（静态链接 ARM32）
# 依赖: ncursesw, pcre2（fish 自带）, musl libc
# 产物: term/src/main/assets/tools/usr/bin/fish
set -eux

FISH_VERSION="3.7.1"
NCURSES_VERSION="6.4"
CROSS=armv7-unknown-linux-musleabihf-
TC_DIR=/opt/armv7-unknown-linux-musleabihf
HOST_TAG=arm-linux-musleabihf
PREFIX=/opt/fish-deps

# 1. 确保 musl 交叉工具链可用（dropbear 步骤已下载）
if [ ! -f "$TC_DIR/bin/${CROSS}gcc" ]; then
  echo "ERROR: musl 交叉工具链未找到，请先运行 build-dropbear-musl.sh"
  exit 1
fi
export PATH="$TC_DIR/bin:$PATH"
${CROSS}gcc --version | head -1

# 2. 交叉编译 ncursesw（静态库）
echo "=== 编译 ncursesw ${NCURSES_VERSION} ==="
curl -fSL --connect-timeout 30 --retry 3 --retry-delay 5 \
  -o /tmp/ncurses.tar.gz "https://ftp.gnu.org/pub/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz"
tar xzf /tmp/ncurses.tar.gz -C /tmp
cd "/tmp/ncurses-${NCURSES_VERSION}"

./configure \
  --host=${HOST_TAG} \
  --prefix="$PREFIX" \
  --with-shared=no \
  --with-normal=yes \
  --with-debug=no \
  --enable-widec \
  --without-tests \
  --without-cxx-binding \
  --without-debug \
  --without-progs \
  --enable-pc-files \
  --with-pkg-config-libdir="$PREFIX/lib/pkgconfig" \
  CC="${CROSS}gcc" \
  CXX="${CROSS}g++" \
  AR="${CROSS}ar" \
  RANLIB="${CROSS}ranlib" \
  STRIP="${CROSS}strip" \
  CFLAGS="-O2 -static" \
  LDFLAGS="-static"
# 只安装库和头文件，跳过 progs（避免 host strip 处理 ARM 二进制）
make -j$(nproc) install.libs
make -j$(nproc) install.includes

# 验证 ncursesw 静态库和头文件
ls -la "$PREFIX/lib/libncursesw.a" 2>/dev/null || ls -la "$PREFIX/lib/"*ncurses* 2>/dev/null
ls -la "$PREFIX/include/ncursesw/curses.h" 2>/dev/null || ls -la "$PREFIX/include/curses.h" 2>/dev/null || { echo "ERROR: ncurses 头文件未安装"; exit 1; }

# 3. 下载 fish 源码
echo "=== 下载 fish ${FISH_VERSION} ==="
curl -fSL --connect-timeout 30 --retry 3 --retry-delay 5 \
  -o /tmp/fish.tar.xz "https://github.com/fish-shell/fish-shell/releases/download/${FISH_VERSION}/fish-${FISH_VERSION}.tar.xz"
tar -xJf /tmp/fish.tar.xz -C /tmp
cd "/tmp/fish-${FISH_VERSION}"

# 4. Patch CMakeLists.txt
# 移除静态链接检查
sed -i '/# Error out when linking statically/,/endif()/d' CMakeLists.txt
# 移除 lint 目标（需要 fish_indent，交叉编译可能失败）
sed -i '/add_custom_target(lint/,/^)/d' CMakeLists.txt
sed -i '/add_custom_target(lint-all/,/^)/d' CMakeLists.txt

# 5. CMake 交叉编译配置
cat > /tmp/cmake-toolchain-arm.cmake << 'TOOLCHAIN'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR armv7)
set(CMAKE_C_COMPILER armv7-unknown-linux-musleabihf-gcc)
set(CMAKE_CXX_COMPILER armv7-unknown-linux-musleabihf-g++)
set(CMAKE_FIND_ROOT_PATH "/opt/armv7-unknown-linux-musleabihf;/opt/fish-deps")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
TOOLCHAIN

# 6. 构建 fish
echo "=== 编译 fish ==="
mkdir -p build && cd build
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=/tmp/cmake-toolchain-arm.cmake \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_EXE_LINKER_FLAGS="-static -s" \
  -DBUILD_DOCS=OFF \
  -DCMAKE_INSTALL_PREFIX=/usr

cmake --build . -j$(nproc) 2>&1 | tail -20

# 7. 查找产物
FISH_BIN="$(pwd)/fish"
if [ ! -f "$FISH_BIN" ]; then
  echo "ERROR: fish 二进制未找到，尝试查找..."
  find . -name "fish" -type f 2>/dev/null
  find "/tmp/fish-${FISH_VERSION}/target" -name "fish" -type f 2>/dev/null
  exit 1
fi

# 8. 验证
echo "=== 验证 fish 二进制 ==="
file "$FISH_BIN"
readelf -h "$FISH_BIN" | grep -E "Type|Machine"
readelf -d "$FISH_BIN" 2>/dev/null | grep NEEDED && echo "WARNING: 动态链接!" || echo "OK: 静态链接"

# 9. strip
${CROSS}strip "$FISH_BIN" 2>/dev/null || true

# 10. 复制到 assets
cd "$GITHUB_WORKSPACE"
cp "$FISH_BIN" "term/src/main/assets/tools/usr/bin/fish"
chmod +x "term/src/main/assets/tools/usr/bin/fish"
ls -la "term/src/main/assets/tools/usr/bin/fish"
echo "fish 构建完成!"

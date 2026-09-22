#!/bin/bash
# 用 musl 交叉编译 fish shell 3.7.1（纯 C++，静态链接 ARM32）
# fish 3.7.x 不需要 Rust，用 cmake 即可构建
# 产物: term/src/main/assets/tools/usr/bin/fish
set -eux

FISH_VERSION="3.7.1"
CROSS=armv7-unknown-linux-musleabihf-
TC_DIR=/opt/armv7-unknown-linux-musleabihf

# 1. 确保 musl 交叉工具链可用（dropbear 步骤已下载）
if [ ! -f "$TC_DIR/bin/${CROSS}gcc" ]; then
  echo "ERROR: musl 交叉工具链未找到，请先运行 build-dropbear-musl.sh"
  exit 1
fi
export PATH="$TC_DIR/bin:$PATH"
${CROSS}gcc --version | head -1

# 2. 下载 fish 源码
curl -fSL --connect-timeout 30 --retry 3 --retry-delay 5 \
  -o /tmp/fish.tar.xz "https://github.com/fish-shell/fish-shell/releases/download/${FISH_VERSION}/fish-${FISH_VERSION}.tar.xz"
tar -xJf /tmp/fish.tar.xz -C /tmp
cd "/tmp/fish-${FISH_VERSION}"

# 3. CMake 交叉编译配置
cat > /tmp/cmake-toolchain-arm.cmake << 'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR armv7)
set(CMAKE_C_COMPILER armv7-unknown-linux-musleabihf-gcc)
set(CMAKE_CXX_COMPILER armv7-unknown-linux-musleabihf-g++)
set(CMAKE_FIND_ROOT_PATH /opt/armv7-unknown-linux-musleabihf)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
EOF

# 4. 构建（纯 C++，静态链接）
mkdir -p build && cd build
cmake .. \
  -DCMAKE_TOOLCHAIN_FILE=/tmp/cmake-toolchain-arm.cmake \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_EXE_LINKER_FLAGS="-static -s" \
  -DBUILD_DOCS=OFF \
  -DCMAKE_INSTALL_PREFIX=/usr

cmake --build . -j$(nproc)

# 5. 查找产物
FISH_BIN="$(pwd)/fish"
if [ ! -f "$FISH_BIN" ]; then
  echo "ERROR: fish 二进制未找到"
  find . -name "fish*" -type f 2>/dev/null
  exit 1
fi

# 6. 验证
file "$FISH_BIN"
readelf -h "$FISH_BIN" | grep -E "Type|Machine"

# 7. strip
${CROSS}strip "$FISH_BIN" 2>/dev/null || true

# 8. 复制到 assets
cd "$GITHUB_WORKSPACE"
cp "$FISH_BIN" "term/src/main/assets/tools/usr/bin/fish"
chmod +x "term/src/main/assets/tools/usr/bin/fish"
ls -la "term/src/main/assets/tools/usr/bin/fish"

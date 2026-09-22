#!/usr/bin/env bash
# tpack —— polaco1782/linux-static-binaries 单仓库工具管理器（类 apt）
# 用法: tpack <命令> [参数]
#   update              拉取远程索引（name+size），存本地缓存
#   list [模式]         列出仓库全部工具，可选 grep 过滤
#   search <模式>       搜索工具名（等价 list <模式>）
#   info <工具>         查看远程大小 / 本地安装状态
#   install <工具>...   安装（已装且 size 一致则跳过；装前比较）
#   update-tools <工具>...  强制重新下载覆盖
#   status              显示本地已装工具与远程 size 对比
#   remove <工具>...    删除本地文件并清状态
#   which <工具>        打印已安装工具的完整路径
# 环境变量:
#   TPACK_PREFIX  安装目录（默认 $HOME/bin）
#   TPACK_DIR     状态目录（默认 ~/.tpack）
#   TPACK_BASE   下载地址模板（默认仓库 raw URL）

set -u
REPO=polaco1782/linux-static-binaries
BRANCH=master
DIR=armv7l-eabihf
RAW=https://raw.githubusercontent.com/$REPO/$BRANCH/$DIR
API="https://api.github.com/repos/$REPO/contents/$DIR?per_page=1000"

# ---- 路径 ----
TPACK_PREFIX="${TPACK_PREFIX:-$HOME/bin}"
TPACK_DIR="${TPACK_DIR:-$HOME/.tpack}"
CACHE="$TPACK_DIR/index.tsv"
STATUS="$TPACK_DIR/installed.tsv"
mkdir -p "$TPACK_PREFIX" "$TPACK_DIR"

need() { command -v "$1" >/dev/null 2>&1 || { echo "tpack: 缺少依赖 $1" >&2; exit 1; }; }
need curl; need sha256sum

fetch_index() {
  echo "tpack: 拉取远程索引..."
  curl -fsSL "$API" -o "$TPACK_DIR/.index.json" || { echo "tpack: 拉取失败" >&2; return 1; }
  jq -r '.[] | "\(.name)\t\(.size)"' "$TPACK_DIR/.index.json" > "$CACHE" \
    || grep -oP '"name": *"\K[^"]+' "$TPACK_DIR/.index.json" | sort > "$CACHE"
  echo "tpack: 索引已更新 ($(wc -l < "$CACHE") 项)"
}

ensure_index() { [ -f "$CACHE" ] || fetch_index || return 1; }

# 查远程 size
remote_size() { awk -F'\t' -v n="$1" '$1==n {print $2}' "$CACHE" | head -1; }

# 查本地已装 size（从 STATUS）
local_size() { awk -F'\t' -v n="$1" '$1==n {print $2}' "$STATUS" 2>/dev/null | head -1; }

is_installed() { grep -qP "^$1\t" "$STATUS" 2>/dev/null; }

record() { printf "%s\t%s\t%s\t%s\n" "$1" "$2" "$3" "$(date +%Y-%m-%d)" >> "$STATUS"; }

cmd_list() {
  ensure_index || exit 1
  if [ $# -gt 0 ]; then
    grep -i "$1" "$CACHE" | sort
  else
    sort "$CACHE"
  fi
}

cmd_info() {
  ensure_index || exit 1
  local n="$1"
  local rs=$(remote_size "$n")
  if [ -z "$rs" ]; then echo "tpack: 仓库无此工具: $n"; exit 1; fi
  echo "工具: $n"
  echo "远程: $((rs/1024)) KB"
  if is_installed "$n"; then
    local ls=$(local_size "$n")
    local f="$TPACK_PREFIX/$n"
    local actual=$([ -f "$f" ] && stat -c%s "$f" || echo 0)
    echo "本地: $((ls/1024)) KB (记录) / $((actual/1024)) KB (实际)"
    [ "$rs" = "$ls" ] && [ "$rs" = "$actual" ] && echo "状态: 最新" || echo "状态: 可更新"
  else
    echo "本地: 未安装"
  fi
}

cmd_install() {
  [ $# -gt 0 ] || { echo "用法: tpack install <工具>..."; exit 1; }
  ensure_index || exit 1
  local installed=0 skipped=0 failed=0
  for n in "$@"; do
    local rs=$(remote_size "$n")
    if [ -z "$rs" ]; then echo "tpack: 跳过 (仓库无): $n"; failed=$((failed+1)); continue; fi
    local f="$TPACK_PREFIX/$n"
    local ls=$(local_size "$n")
    if [ -f "$f" ] && [ "$rs" = "$ls" ]; then
      echo "tpack: 已是最新, 跳过: $n"; skipped=$((skipped+1)); continue
    fi
    echo "tpack: 下载 $n ($((rs/1024)) KB)..."
    if curl -fsSL "$RAW/$n" -o "$f.tmp"; then
      chmod +x "$f.tmp"
      local actual=$(stat -c%s "$f.tmp")
      if [ "$actual" != "$rs" ]; then
        echo "tpack: 警告 $n: 大小不匹配 远程=$rs 实际=$actual"
      fi
      mv "$f.tmp" "$f"
      if is_installed "$n"; then
        sed -i "/^$n\t/d" "$STATUS"
      fi
      record "$n" "$actual" "$(sha256sum "$f" | cut -d' ' -f1)"
      echo "tpack: 已安装 $n -> $f"
      installed=$((installed+1))
    else
      echo "tpack: 下载失败: $n"; rm -f "$f.tmp"; failed=$((failed+1))
    fi
  done
  echo "tpack: 完成 — 新装 $installed, 跳过 $skipped, 失败 $failed"
}

cmd_update_tools() {
  [ $# -gt 0 ] || { echo "用法: tpack update-tools <工具>..."; exit 1; }
  ensure_index || exit 1
  local n
  for n in "$@"; do
    sed -i "/^$n\t/d" "$STATUS" 2>/dev/null
    rm -f "$TPACK_PREFIX/$n"
  done
  cmd_install "$@"
}

cmd_status() {
  [ -f "$STATUS" ] || { echo "tpack: 未安装任何工具"; exit 0; }
  ensure_index || exit 1
  echo "本地已安装工具 (与远程对比):"
  printf "%-20s %10s %10s  %s\n" 名称 远程KB 本地KB 状态
  while IFS=$'\t' read -r n ls hash date; do
    local rs=$(remote_size "$n")
    local f="$TPACK_PREFIX/$n"
    local actual=$([ -f "$f" ] && stat -c%s "$f" || echo 0)
    local state
    if [ -z "$rs" ]; then state="远程已移除"
    elif [ "$rs" != "$actual" ]; then state="可更新"
    else state="最新"; fi
    printf "%-20s %10d %10d  %s\n" "$n" "$((rs/1024))" "$((actual/1024))" "$state"
  done < "$STATUS" | sort
}

cmd_remove() {
  [ $# -gt 0 ] || { echo "用法: tpack remove <工具>..."; exit 1; }
  for n in "$@"; do
    rm -f "$TPACK_PREFIX/$n"
    sed -i "/^$n\t/d" "$STATUS" 2>/dev/null
    echo "tpack: 已移除 $n"
  done
}

cmd_which() {
  [ $# -gt 0 ] || { echo "用法: tpack which <工具>"; exit 1; }
  local n="$1"
  if is_installed "$n" && [ -f "$TPACK_PREFIX/$n" ]; then
    echo "$TPACK_PREFIX/$n"
  else
    echo "tpack: 未安装: $n"; exit 1
  fi
}

case "${1:-}" in
  update) fetch_index ;;
  list) shift; cmd_list "$@" ;;
  search) shift; cmd_list "$@" ;;
  info) [ $# -ge 2 ] && cmd_info "$2" || { echo "用法: tpack info <工具>"; exit 1; } ;;
  install) shift; cmd_install "$@" ;;
  update-tools) shift; cmd_update_tools "$@" ;;
  status) cmd_status ;;
  remove) shift; cmd_remove "$@" ;;
  which) shift; cmd_which "$@" ;;
  *) echo "用法: tpack <update|list|search|info|install|update-tools|status|remove|which> [参数]"; exit 1 ;;
esac

#!/usr/bin/env bash
#
# Mimir 未签名 IPA 打包脚本
#
# 设计目标：产出一个重签工具（轻松签 / 全能签 / Sideloadly 等）能直接吃下的
# **纯净未签名** IPA。
#
# 背景（2026-10-05）：此前 IPA 在重签工具里报「导入的 ipa 文件有错误」。
# 逐层解剖产物后定位到根因——打包前对 app 做了 ad-hoc 签名（`codesign --sign -`），
# 结果包内留下 `_CodeSignature/CodeResources`（资源清单），却缺少配套的
# `_CodeSignature/CodeSignature`（二进制签名文件），同时二进制里已经写入了
# `LC_CODE_SIGNATURE` 段。这种「半套签名」状态会让重签工具按已签名包解析、
# 校验时找不到签名文件而直接报错。
#
# 因此本脚本的原则是：**彻底不签名**。构建阶段已经 `CODE_SIGNING_ALLOWED=NO`，
# 这里再主动清理任何签名残留，交出的包交给重签工具从头签。
#
# 用法：scripts/package_ipa.sh <path/to/Mimir.app> [output.ipa]

set -euo pipefail

APP_PATH="${1:-}"
OUTPUT_IPA="${2:-Mimir-unsigned.ipa}"

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "usage: $0 <path/to/Mimir.app> [output.ipa]" >&2
  exit 1
fi

# 统一成绝对路径，后面要 cd 到临时目录打包
OUTPUT_IPA="$(cd "$(dirname "$OUTPUT_IPA")" && pwd)/$(basename "$OUTPUT_IPA")"

echo "==> App bundle: $APP_PATH"
du -sh "$APP_PATH"

# ---------------------------------------------------------------- 1. 平台与清单校验
echo "==> [1/5] 校验 Info.plist 与目标平台"

plutil -lint "$APP_PATH/Info.plist"
if [ -f "$APP_PATH/PlugIns/MimirWidgets.appex/Info.plist" ]; then
  plutil -lint "$APP_PATH/PlugIns/MimirWidgets.appex/Info.plist"
fi

PLATFORM="$(plutil -extract CFBundleSupportedPlatforms.0 raw -o - "$APP_PATH/Info.plist")"
if [ "$PLATFORM" != "iPhoneOS" ]; then
  echo "错误：CFBundleSupportedPlatforms 应为 iPhoneOS，实际为 $PLATFORM（是否误混入模拟器构件？）" >&2
  exit 1
fi

EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$APP_PATH/Info.plist")"
APP_BUNDLE_NAME="$(basename "$APP_PATH")"
if [ ! -f "$APP_PATH/$EXECUTABLE" ]; then
  echo "错误：Info.plist 里的 CFBundleExecutable（$EXECUTABLE）与实际二进制文件名不一致" >&2
  exit 1
fi

# 确保主 App、扩展与嵌入式 Framework 的可执行文件在 IPA 中保留执行位
while IFS= read -r -d '' plist; do
  bundle_dir="${plist%/Info.plist}"
  bundle_executable="$(plutil -extract CFBundleExecutable raw -o - "$plist" 2>/dev/null || true)"
  if [ -n "$bundle_executable" ] && [ -f "$bundle_dir/$bundle_executable" ]; then
    chmod +x "$bundle_dir/$bundle_executable"
  fi
done < <(find "$APP_PATH" -name Info.plist -type f -print0)

# 确认二进制是 arm64（真机架构）
if ! lipo -info "$APP_PATH/$EXECUTABLE" 2>/dev/null | grep -q "arm64"; then
  echo "错误：主二进制不含 arm64 架构（$(lipo -info "$APP_PATH/$EXECUTABLE" 2>&1)）" >&2
  exit 1
fi

# ---------------------------------------------------------------- 2. 清除签名残留
echo "==> [2/5] 清除签名残留（保证是纯净未签名包）"

# 2.1 删除签名目录（app 与所有扩展）
finds="$(find "$APP_PATH" -type d -name "_CodeSignature" 2>/dev/null || true)"
if [ -n "$finds" ]; then
  echo "$finds" | while read -r dir; do
    echo "    移除 $dir"
    rm -rf "$dir"
  done
fi

# 2.2 移除并验证所有 Mach-O 的嵌入式签名段，包括扩展与动态库
strip_signature() {
  local binary="$1"
  [ -f "$binary" ] || return 0
  if codesign --remove-signature "$binary" 2>/dev/null; then
    echo "    已移除嵌入式签名：$(basename "$binary")"
  fi
}

while IFS= read -r -d '' binary; do
  if file "$binary" | grep -q 'Mach-O'; then
    strip_signature "$binary"
    if otool -l "$binary" | grep -q 'cmd LC_CODE_SIGNATURE'; then
      echo "错误：$binary 仍包含 LC_CODE_SIGNATURE，拒绝打包" >&2
      exit 1
    fi
  fi
done < <(find "$APP_PATH" -type f -print0)

# ---------------------------------------------------------------- 3. 组装 Payload
echo "==> [3/5] 组装单层 Payload 结构"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/Payload"
cp -R "$APP_PATH" "$WORK_DIR/Payload/"

# 清掉会污染 zip 的 macOS 元数据（__MACOSX / .DS_Store / 扩展属性）
find "$WORK_DIR" -name ".DS_Store" -delete 2>/dev/null || true
find "$WORK_DIR" -name "__MACOSX" -prune -exec rm -rf {} + 2>/dev/null || true
xattr -cr "$WORK_DIR" 2>/dev/null || true

# ---------------------------------------------------------------- 4. 打包
echo "==> [4/5] 打包（-y 保留符号链接 / -X 不写扩展属性 / -q 静默）"

rm -f "$OUTPUT_IPA"
(
  cd "$WORK_DIR"
  zip -r -y -X -q "$OUTPUT_IPA" Payload
)

# ---------------------------------------------------------------- 5. 结构自检
echo "==> [5/5] 校验产物结构"

ls -lh "$OUTPUT_IPA"
unzip -t "$OUTPUT_IPA" >/dev/null
if ! zipinfo -l "$OUTPUT_IPA" "Payload/$APP_BUNDLE_NAME/$EXECUTABLE" | grep -Eq '^-rwx'; then
  echo "错误：IPA 内主程序缺少可执行权限，拒绝交付" >&2
  exit 1
fi

ENTRIES="$(unzip -Z1 "$OUTPUT_IPA")"

ROOTS="$(echo "$ENTRIES" | awk -F/ 'NF && $1 != "" {print $1}' | sort -u)"
if [ "$ROOTS" != "Payload" ]; then
  echo "错误：压缩包顶层不是唯一的 Payload 目录（实际：$ROOTS）" >&2
  exit 1
fi

if echo "$ENTRIES" | grep -q '__MACOSX'; then
  echo "错误：产物里含 __MACOSX 元数据目录" >&2
  exit 1
fi

if echo "$ENTRIES" | grep -q '_CodeSignature'; then
  echo "错误：产物里仍残留 _CodeSignature，重签工具会判定为损坏包" >&2
  exit 1
fi

for required in \
  "Payload/$APP_BUNDLE_NAME/Info.plist" \
  "Payload/$APP_BUNDLE_NAME/$EXECUTABLE"
do
  if ! echo "$ENTRIES" | grep -qx "$required"; then
    echo "错误：缺少必需条目 $required" >&2
    exit 1
  fi
done

# 扩展必须嵌套在 PlugIns 内，不能散落在 Payload 根层
STRAY="$(echo "$ENTRIES" | grep -E '^Payload/[^/]+\.appex' || true)"
if [ -n "$STRAY" ]; then
  echo "错误：发现有扩展散落在 Payload 根层：" >&2
  echo "$STRAY" >&2
  exit 1
fi

APPEX_COUNT="$(echo "$ENTRIES" | grep -c "^Payload/$APP_BUNDLE_NAME/PlugIns/.*\\.appex/Info\\.plist$" || true)"
echo "    嵌套扩展数量：$APPEX_COUNT"
echo "    条目总数：$(echo "$ENTRIES" | wc -l | tr -d ' ')"

echo "==> 完成（纯净未签名 IPA）：$OUTPUT_IPA"

#!/usr/bin/env bash
# 下载内置语音合成模型（Kokoro-82M CoreML，约 99MB）并放进 App 资源目录。
#
# 模型随构建一起打包进 .app，用户无需额外下载。
# 如果下载失败，构建仍然继续，App 会自动回退到系统语音合成。
set -euo pipefail

REPO="Jud/kokoro-coreml"
TAG="${KOKORO_MODEL_TAG:-models-2026-03-23}"
ASSET="kokoro-models.tar.gz"
DEST="DeepSeekClient/Resources/Models/kokoro"

if [ -d "$DEST/voices" ] && [ -d "$DEST/kokoro_frontend.mlmodelc" ]; then
  echo "Voice models already present at $DEST"
  exit 0
fi

URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
echo "Downloading voice models (${TAG}) from ${URL}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! curl -fL --retry 3 --retry-delay 2 -o "$WORK/models.tar.gz" "$URL"; then
  echo "warning: failed to download voice models; the app will fall back to system speech."
  exit 0
fi

mkdir -p "$WORK/extract"
if ! tar xzf "$WORK/models.tar.gz" -C "$WORK/extract"; then
  echo "warning: failed to extract voice models; falling back to system speech."
  exit 0
fi

FRONTEND="$(find "$WORK/extract" -maxdepth 3 -name 'kokoro_frontend.mlmodelc' -type d | head -1 || true)"
if [ -z "$FRONTEND" ]; then
  echo "warning: model bundle layout not recognised; falling back to system speech."
  ls -la "$WORK/extract"
  exit 0
fi

SOURCE_DIR="$(dirname "$FRONTEND")"
mkdir -p "$DEST"
cp -R "$SOURCE_DIR"/. "$DEST"/

echo "Voice models installed to $DEST"
du -sh "$DEST"
ls -1 "$DEST" | head -20

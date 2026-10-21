#!/bin/sh
# Builds sdkjs (with sdkjs-forms) and collects the files the editor engine loads
# in build/out/sdkjs (read by editors-android's libeditors). Runs in a Node image
# with the AndroidEditors checkout mounted at /src, e.g.:
#
#   docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e npm_config_cache=/tmp/npm \
#       -v "$PWD":/src -w /src node:20 build/scripts/sdkjs.sh
set -eu

ROOT="${ROOT:-/src}"
WORK_DIR="$ROOT/build/work/sdkjs"
OUT_DIR="$ROOT/build/out/sdkjs"

cd "$ROOT/sdkjs/build"
npm ci --no-audit --no-fund
BUILD_ROOT="$WORK_DIR" SDK_ADDONS="$ROOT/sdkjs-forms" SKIP_DEVELOP=1 npm run build

DEPLOY="$WORK_DIR/sdkjs"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/common/Native" "$OUT_DIR/common/libfont/engine" "$OUT_DIR/vendor"
for editor in word slide cell; do
    mkdir -p "$OUT_DIR/$editor"
    cp "$DEPLOY/$editor/sdk-all-min.js" "$DEPLOY/$editor/sdk-all.js" "$OUT_DIR/$editor/"
done
# Presentation themes (x2t's theme directory when saving)
cp -r "$DEPLOY/slide/themes" "$OUT_DIR/slide/"
cp "$DEPLOY"/common/Native/*.js "$OUT_DIR/common/Native/"
cp "$DEPLOY/common/libfont/engine/fonts_native.js" "$OUT_DIR/common/libfont/engine/"
# SmartArt definitions the editors offer (read by the engine instead of loading them over the web)
mkdir -p "$OUT_DIR/common/SmartArts/SmartArtDrawing" "$OUT_DIR/common/SmartArts/SmartArtData"
cp "$ROOT/sdkjs/common/SmartArts/SmartArtDrawing/SmartArtDrawings.bin" "$OUT_DIR/common/SmartArts/SmartArtDrawing/"
for name in Basic_Block_List Basic_Process Basic_Cycle Organization_Chart Basic_Venn Basic_Pyramid Vertical_Bullet_List Basic_Timeline; do
    cp "$ROOT/sdkjs/common/SmartArts/SmartArtData/$name.bin" "$OUT_DIR/common/SmartArts/SmartArtData/"
done
# Its third-party components, for the editors' licences page
cp "$ROOT/sdkjs/3DPARTY.md" "$OUT_DIR/"
# Not part of sdkjs' deploy, but loaded by DoctRenderer.config
cp "$ROOT/sdkjs/vendor/xregexp-all-min.js" "$OUT_DIR/vendor/"

echo "sdkjs for the engine:"
find "$OUT_DIR" -type f | sed "s#$OUT_DIR/##"

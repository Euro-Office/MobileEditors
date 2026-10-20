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
mkdir -p "$OUT_DIR/word" "$OUT_DIR/common/Native" "$OUT_DIR/common/libfont/engine" "$OUT_DIR/vendor"
cp "$DEPLOY/word/sdk-all-min.js" "$DEPLOY/word/sdk-all.js" "$OUT_DIR/word/"
cp "$DEPLOY"/common/Native/*.js "$OUT_DIR/common/Native/"
cp "$DEPLOY/common/libfont/engine/fonts_native.js" "$OUT_DIR/common/libfont/engine/"
# Not part of sdkjs' deploy, but loaded by DoctRenderer.config
cp "$ROOT/sdkjs/vendor/xregexp-all-min.js" "$OUT_DIR/vendor/"

echo "sdkjs for the engine:"
find "$OUT_DIR" -type f | sed "s#$OUT_DIR/##"

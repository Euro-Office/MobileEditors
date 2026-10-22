#!/bin/sh
# Cross-compiles core (x2t and the libraries it links) for one Android ABI.
# Runs inside the core-android-builder image with the MobileEditors checkout
# mounted at /src, e.g.:
#
#   docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/src -w /src \
#       ghcr.io/euro-office/core-android-builder build/scripts/core-android.sh arm64-v8a
#
# Results: build/out/core-android/<abi>/lib*.so (read by core's libx2t wrapper).
# Work files (3rd-party checkouts, CMake build tree) stay in build/work/.
set -eu

ABI="${1:-arm64-v8a}"
API_LEVEL="${ANDROID_API_LEVEL:-26}"
ROOT="${ROOT:-/src}"

case "$ABI" in
    arm64-v8a) TARGET=android-arm64 ;;
    x86_64)    TARGET=android-x64 ;;
    *) echo "Unsupported ABI: $ABI (arm64-v8a, x86_64)" >&2; exit 1 ;;
esac

WORK_DIR="$ROOT/build/work/$TARGET"
OUT_DIR="$ROOT/build/out/core-android/$ABI"

cmake -S "$ROOT/core" -B "$WORK_DIR/core" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM="android-$API_LEVEL" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Release \
    -DEO_CORE_3RD_PARTY_DIR="$WORK_DIR/3rd" \
    -DEO_CORE_OUTPUT_DIR="$WORK_DIR/package"

cmake --build "$WORK_DIR/core" --target x2tlib

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp "$WORK_DIR"/package/*.so "$OUT_DIR/"
find "$WORK_DIR/core" -name libx2t.so -exec cp {} "$OUT_DIR/" \;

# The NDK toolchain always adds -g; ship stripped copies (unstripped ones stay in the work dir)
"$ANDROID_NDK_ROOT"/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip --strip-unneeded "$OUT_DIR"/*.so

echo "Core libraries for $ABI:"
ls -1 "$OUT_DIR"

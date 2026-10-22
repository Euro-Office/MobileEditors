#!/bin/sh
# Builds the editor engine for the host, with its check tool eo-render, for the engine tests
# (editors-engine/tests): core's docbuilder, x2t and allfontsgen, a runtime directory with
# sdkjs and a font index, and the engine. Runs in core's build image (desktop flavor), as root
# because of vcpkg, from the MobileEditors root:
#
#   docker buildx build -f core/.docker/core.bake.Dockerfile --target core-base \
#       --build-arg PRODUCT=desktop --build-arg BUILD_ROOT=/package -t eo-core-base:desktop --load core
#   docker run --rm -v "$PWD":/src -w /src -v eo-vcpkg-cache:/nuget-cache eo-core-base:desktop \
#       build/scripts/engine-host.sh
#
# Needs sdkjs from scripts/sdkjs.sh (build/work/sdkjs/sdkjs). Results: build/work/host/package (the
# runtime directory and core's libraries) and build/work/host/engine/eo-render. Later runs are
# incremental. With CORE_PREBUILT=1, core's libraries and tools already in build/work/host are
# used as they are (CI keeps them, but not core's much larger build tree).
set -eu

ROOT="${ROOT:-/src}"
WORK="$ROOT/build/work/host"
PACKAGE="$WORK/package"

# core
if [ "${CORE_PREBUILT:-0}" = "1" ]; then
    echo "core: prebuilt in $PACKAGE"
elif [ ! -f "$WORK/core/build.ninja" ]; then
    cmake -S "$ROOT/core" -B "$WORK/core" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DVCPKG_MANIFEST_MODE=ON -DVCPKG_MANIFEST_DIR="$ROOT/core" \
        -DCMAKE_TOOLCHAIN_FILE=/opt/vcpkg/scripts/buildsystems/vcpkg.cmake \
        -DEO_CORE_3RD_PARTY_DIR="$WORK/3rd" \
        -DEO_CORE_OUTPUT_DIR="$PACKAGE" -DEO_CORE_TOOLS_DIR="$WORK/tools"
fi
[ "${CORE_PREBUILT:-0}" = "1" ] || cmake --build "$WORK/core" --target docbuilder x2t allfontsgen

# Runtime: sdkjs, DoctRenderer.config and the font index of core-fonts
SDKJS="$ROOT/build/work/sdkjs/sdkjs"
[ -f "$SDKJS/word/sdk-all.js" ] || { echo "sdkjs not found in $SDKJS (run scripts/sdkjs.sh)" >&2; exit 1; }
ln -sfn "$SDKJS" "$PACKAGE/sdkjs"
cat > "$PACKAGE/DoctRenderer.config" <<CONFIG
<Settings>
<file>./sdkjs/common/Native/native.js</file>
<file>./sdkjs/common/Native/jquery_native.js</file>
<file>$ROOT/sdkjs/vendor/xregexp-all-min.js</file>
<allfonts>./fonts/AllFonts.js</allfonts>
<sdkjs>./sdkjs</sdkjs>
</Settings>
CONFIG
# The blank document sdkjs' PDF editor starts from (Document::OpenPdf)
mkdir -p "$PACKAGE/empty"
cp "$ROOT/document-templates/new/en-US/new.docx" "$PACKAGE/empty/new.docx"
if [ ! -f "$PACKAGE/fonts/AllFonts.js" ]; then
    mkdir -p "$PACKAGE/fonts"
    LD_LIBRARY_PATH="$PACKAGE" "$WORK/tools/allfontsgen" --input="$ROOT/core-fonts" \
        --allfonts="$PACKAGE/fonts/AllFonts.js" --selection="$PACKAGE/fonts/font_selection.bin"
fi

# The engine and eo-render
if [ ! -f "$WORK/engine/build.ninja" ]; then
    cmake -S "$ROOT/editors-engine" -B "$WORK/engine" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCORE_SOURCE_DIR="$ROOT/core" -DCORE_LIBS_DIR="$PACKAGE" -DEO_ENGINE_TOOLS=ON
fi
cmake --build "$WORK/engine"
echo "eo-render: $WORK/engine/eo-render, runtime: $PACKAGE"

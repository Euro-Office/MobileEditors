#!/bin/sh
# Builds the iOS app (documents-app-ios) with the editors (editors-ios) on a Mac:
#
#   build/ios/build.sh                      # everything, for the simulator
#   EO_DESTINATION=device EO_DEVELOPMENT_TEAM=<team> build/ios/build.sh
#   EO_STEPS="runtime test" build/ios/build.sh
#
# Steps (EO_STEPS, in this order; default: all but test):
#   sdkjs      sdkjs for the engine: the sdkjs-native bake target (Docker), unless SDKJS_DIR is given
#   core       core with CMake: for macOS with JavaScriptCore (eo-render, allfontsgen, the macOS
#              slice) and for iOS (the simulator or devices); the first build of each also builds
#              its third-party libraries (Common/3dParty/build_3rdparty.py)
#   engine     editors-engine's eo-render for macOS, and EOEngine.xcframework with core's
#              xcframeworks (editors-ios' Engine/build.sh)
#   runtime    the runtime: core for macOS, eo-render, sdkjs, DoctRenderer.config, empty/ and
#              the font index of the fonts the app bundles
#   templates  the template gallery (documents-app-ios' tools/templates.sh, about 5 minutes);
#              needs EO_TEMPLATE_SOURCES (document-corpus' samples/), else the gallery stays empty
#   test       editors-ios' Swift tests on macOS (EditorsKit, and the engine on the runtime)
#   app        xcodebuild of the app
#
# Environment:
#   EO_IOS_WORK          build trees and results (default: build/work/ios)
#   EO_DESTINATION       simulator (default) or device
#   EO_CONFIGURATION     Debug (default) or Release
#   EO_CORE_SLICES       core builds (default: mac-jsc, and ios-sim or ios-dev for EO_DESTINATION)
#   SDKJS_DIR            sdkjs-native output to use instead of building it
#   EO_FONTS             fonts of core-fonts the app bundles (default: ASC.ttf caladea crosextra dejavu liberation)
#   EO_TEMPLATE_SOURCES  document-corpus' samples/, for the templates step
#   EO_DEVELOPMENT_TEAM, EO_CODE_SIGN_IDENTITY, EO_ALLOW_PROVISIONING_UPDATES=1
#                        signing for devices
#   EO_XCODEBUILD_ARGS   further xcodebuild arguments, e.g. CODE_SIGNING_ALLOWED=NO
#   EO_DRY_RUN=1         print the commands instead of running them
#   CORE_DIR, CORE_FONTS_DIR, SDKJS_SRC_DIR, EDITORS_ENGINE_DIR, EDITORS_IOS_DIR, APP_DIR,
#   DOCUMENT_TEMPLATES_DIR
#                        checkouts (default: the submodules; documents-app-ios next to them)
#
# Builds are incremental: core and sdkjs are skipped while their checkout is clean and at the
# commit of the last build, everything else is incremental (Ninja, Xcode) or cheap.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=${EO_IOS_WORK:-$ROOT/build/work/ios}
DESTINATION=${EO_DESTINATION:-simulator}
CONFIGURATION=${EO_CONFIGURATION:-Debug}
STEPS=${EO_STEPS:-sdkjs core engine runtime templates app}
FONTS=${EO_FONTS:-ASC.ttf caladea crosextra dejavu liberation}
DRY=${EO_DRY_RUN:-}

CORE_DIR=${CORE_DIR:-$ROOT/core}
CORE_FONTS_DIR=${CORE_FONTS_DIR:-$ROOT/core-fonts}
SDKJS_SRC_DIR=${SDKJS_SRC_DIR:-$ROOT/sdkjs}
EDITORS_ENGINE_DIR=${EDITORS_ENGINE_DIR:-$ROOT/editors-engine}
EDITORS_IOS_DIR=${EDITORS_IOS_DIR:-$ROOT/editors-ios}
APP_DIR=${APP_DIR:-$ROOT/documents-app-ios}
DOCUMENT_TEMPLATES_DIR=${DOCUMENT_TEMPLATES_DIR:-$ROOT/document-templates}

SDKJS=${SDKJS_DIR:-$WORK/sdkjs}
RUNTIME=$WORK/runtime
APP_FONTS=$WORK/fonts
TEMPLATES=$WORK/templates

case $DESTINATION in
    simulator) IOS_SLICE=ios-sim ;;
    device) IOS_SLICE=ios-dev ;;
    *) echo "EO_DESTINATION must be simulator or device" >&2; exit 1 ;;
esac
CORE_SLICES=${EO_CORE_SLICES:-mac-jsc $IOS_SLICE}

run() {
    echo "+ $*"
    [ -n "$DRY" ] || "$@"
}

step() {
    case " $STEPS " in *" $1 "*) echo "== $1"; return 0 ;; esac
    return 1
}

# The commit of a checkout, or "dirty" when it has changes (then nothing is skipped)
revision() {
    if [ -n "$(git -C "$1" status --porcelain --untracked-files=no 2>/dev/null || echo dirty)" ]; then
        echo dirty
    else
        git -C "$1" rev-parse HEAD
    fi
}

# name, revision: whether the last build of name was of this revision
up_to_date() {
    [ "$2" != dirty ] && [ "$(cat "$WORK/stamps/$1" 2>/dev/null)" = "$2" ]
}

stamp() {
    [ -n "$DRY" ] || { mkdir -p "$WORK/stamps"; echo "$2" > "$WORK/stamps/$1"; }
}

mkdir -p "$WORK"

if step sdkjs; then
    rev="$(revision "$SDKJS_SRC_DIR")-$(revision "$ROOT/sdkjs-forms")"
    case $rev in *dirty*) rev=dirty ;; esac
    if [ -n "${SDKJS_DIR:-}" ]; then
        echo "Using SDKJS_DIR=$SDKJS_DIR"
    elif up_to_date sdkjs "$rev" && [ -d "$SDKJS" ]; then
        echo "sdkjs is up to date"
    else
        run rm -rf "$SDKJS"
        (cd "$ROOT/build" && run docker buildx bake --allow=fs.read=.. sdkjs-native --set "*.output=type=local,dest=$SDKJS")
        stamp sdkjs "$rev"
    fi
fi

if step core; then
    rev=$(revision "$CORE_DIR")
    for slice in $CORE_SLICES; do
        case $slice in
            mac-jsc) third_party=mac; platform="-DUSE_JAVASCRIPT_CORE=1" ;;
            ios-dev) third_party=ios-arm64; platform="-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphoneos" ;;
            ios-sim) third_party=ios-sim-arm64; platform="-DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=iphonesimulator" ;;
            *) echo "Unknown core slice $slice (mac-jsc, ios-dev, ios-sim)" >&2; exit 1 ;;
        esac
        case $slice in ios-*) platform="$platform -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0" ;; esac
        if up_to_date "core-$slice" "$rev" && [ -d "$WORK/core-$slice-out" ]; then
            echo "core ($slice) is up to date"
            continue
        fi
        if [ ! -f "$WORK/core-$slice/CMakeCache.txt" ]; then
            # shellcheck disable=SC2086
            run cmake -S "$CORE_DIR" -B "$WORK/core-$slice" -G Ninja -DCMAKE_BUILD_TYPE=Release $platform \
                -DEO_CORE_3RD_PARTY_DIR="$WORK/3rdparty-$third_party" -DEO_CORE_OUTPUT_DIR="$WORK/core-$slice-out"
        fi
        run cmake --build "$WORK/core-$slice"
        stamp "core-$slice" "$rev"
    done
fi

if step engine; then
    run cmake -S "$EDITORS_ENGINE_DIR" -B "$WORK/engine-mac" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DCORE_SOURCE_DIR="$CORE_DIR" -DCORE_LIBS_DIR="$WORK/core-mac-jsc-out" -DEO_ENGINE_TOOLS=ON
    run cmake --build "$WORK/engine-mac"
    ios_libs=""
    for slice in $CORE_SLICES; do
        case $slice in
            ios-dev) ios_libs="$ios_libs CORE_LIBS_IOS=$WORK/core-ios-dev-out" ;;
            ios-sim) ios_libs="$ios_libs CORE_LIBS_IOS_SIM=$WORK/core-ios-sim-out" ;;
        esac
    done
    # Without EO_RUNTIME_DIR: build.sh would copy the runtime into the tests' resources (for devices)
    # shellcheck disable=SC2086
    run env -u EO_RUNTIME_DIR EDITORS_ENGINE_DIR="$EDITORS_ENGINE_DIR" CORE_SOURCE_DIR="$CORE_DIR" \
        CORE_LIBS_MAC="$WORK/core-mac-jsc-out" $ios_libs BUILD_DIR="$WORK/editors-ios-engine" \
        sh "$EDITORS_IOS_DIR/Engine/build.sh"
    # SwiftPM caches the manifest, which checks for the frameworks
    run touch "$EDITORS_IOS_DIR/Engine/Package.swift"
fi

if step runtime; then
    run rm -rf "$RUNTIME" "$APP_FONTS"
    run mkdir -p "$RUNTIME/empty" "$RUNTIME/fonts" "$APP_FONTS"
    run rsync -a "$WORK/core-mac-jsc-out/" "$RUNTIME/"
    run cp "$WORK/engine-mac/eo-render" "$WORK/engine-mac/libeoengine.dylib" "$RUNTIME/"
    run rsync -a "$SDKJS/" "$RUNTIME/sdkjs/"
    run cp "$DOCUMENT_TEMPLATES_DIR/new/en-US/new.docx" "$RUNTIME/empty/"
    # core's renderer loads these scripts before sdkjs
    echo "+ write $RUNTIME/DoctRenderer.config"
    [ -n "$DRY" ] || printf '%s\n' '<Settings>' \
        '<file>./sdkjs/common/Native/native.js</file>' \
        '<file>./sdkjs/common/Native/jquery_native.js</file>' \
        '<file>./sdkjs/vendor/xregexp-all-min.js</file>' \
        '<allfonts>./fonts/AllFonts.js</allfonts>' \
        '<sdkjs>./sdkjs</sdkjs>' \
        '</Settings>' > "$RUNTIME/DoctRenderer.config"
    # The fonts the app bundles (it makes their index on the device); the runtime's index is of them too
    for font in $FONTS; do
        run cp -R "$CORE_FONTS_DIR/$font" "$APP_FONTS/"
    done
    run env DYLD_LIBRARY_PATH="$RUNTIME" "$WORK/core-mac-jsc/allfontsgen/allfontsgen" --input="$APP_FONTS" \
        --allfonts="$RUNTIME/fonts/AllFonts.js" --selection="$RUNTIME/fonts/font_selection.bin"
fi

if step templates; then
    if [ -z "${EO_TEMPLATE_SOURCES:-}" ]; then
        echo "EO_TEMPLATE_SOURCES is not set: no templates"
        run mkdir -p "$TEMPLATES"
    elif ls "$TEMPLATES"/*.docx >/dev/null 2>&1; then
        echo "Templates exist (delete $TEMPLATES to make them again)"
    else
        run rm -rf "$TEMPLATES" "$TEMPLATES.tmp"
        run sh "$APP_DIR/tools/templates.sh" "$RUNTIME" "$EO_TEMPLATE_SOURCES" "$TEMPLATES.tmp"
        run mv "$TEMPLATES.tmp" "$TEMPLATES"
    fi
fi

if step test; then
    run swift test --package-path "$EDITORS_IOS_DIR"
    run env EO_RUNTIME_DIR="$RUNTIME" EO_SAMPLE_DOCX="$DOCUMENT_TEMPLATES_DIR/sample/sample.docx" \
        swift test --package-path "$EDITORS_IOS_DIR/Engine"
fi

if step app; then
    case $DESTINATION in
        simulator) set -- -destination 'generic/platform=iOS Simulator' ;;
        device)
            set -- -destination 'generic/platform=iOS' \
                ${EO_DEVELOPMENT_TEAM:+DEVELOPMENT_TEAM=$EO_DEVELOPMENT_TEAM} \
                ${EO_CODE_SIGN_IDENTITY:+CODE_SIGN_IDENTITY=$EO_CODE_SIGN_IDENTITY}
            [ "${EO_ALLOW_PROVISIONING_UPDATES:-}" != 1 ] || set -- "$@" -allowProvisioningUpdates
            ;;
    esac
    # shellcheck disable=SC2086
    run xcodebuild -project "$APP_DIR/Documents.xcodeproj" -scheme Documents -configuration "$CONFIGURATION" \
        -derivedDataPath "$WORK/DerivedData" "$@" \
        EO_RUNTIME_DIR="$RUNTIME" EO_FONTS_DIR="$APP_FONTS" \
        EO_DOCUMENT_TEMPLATES_DIR="$DOCUMENT_TEMPLATES_DIR/new" EO_TEMPLATES_DIR="$TEMPLATES" \
        ${EO_XCODEBUILD_ARGS:-} build
    case $DESTINATION in
        simulator) echo "App: $WORK/DerivedData/Build/Products/$CONFIGURATION-iphonesimulator/Documents.app" ;;
        device) echo "App: $WORK/DerivedData/Build/Products/$CONFIGURATION-iphoneos/Documents.app" ;;
    esac
fi

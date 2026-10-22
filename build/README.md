# Build

All builds run in Docker with `docker buildx bake`. Run the commands from this directory.

## Targets

| Target | What it does |
|---|---|
| `android-toolchain` | Ubuntu 24.04 with JDK 17, Android SDK (platform 36, build-tools 36.0.0), NDK 28.2.13676358 and CMake 3.22.1 |
| `core-android-builder` | `android-toolchain` plus the host tools for cross-compiling core and its 3rd-party deps (clang, ninja, autotools, perl) |
| `apk` (default) | Builds `documents-app-android` with the `editors-android` modules and writes the APKs to `build/out/` |
| `apk-native` | Like `apk`, plus the native core: libx2t and the editor engine, with the core libraries in `build/out/core-android/`, sdkjs from `build/out/sdkjs/` and fonts from `core-fonts` |
| `emulator` | Headless Android emulator (Android 14, x86_64) for `scripts/emulator-test.sh`; needs `/dev/kvm` |

## Usage

```sh
docker buildx bake --allow=fs.read=.. android-toolchain     # one-time, cached afterwards
docker buildx bake --allow=fs.read=.. apk                   # debug APKs in build/out/
GRADLE_TASK=:appmanager:assembleRelease docker buildx bake --allow=fs.read=.. apk   # needs the release secrets
```

`--allow=fs.read=..` lets bake read the sibling submodules (`../documents-app-android`, `../editors-android`); buildx asks for it because they are outside `build/`.

The Gradle cache is kept in a BuildKit cache mount, so later builds are incremental.

## Core for Android

`scripts/core-android.sh <abi>` cross-compiles core for `arm64-v8a` or `x86_64`. It runs CMake with the NDK toolchain file; core's `common.cmake` then calls `Common/3dParty/build_3rdparty.py --target=android-<arch>` to build boost, ICU, openssl and V8 for that ABI. Run it in the builder image from the repository root:

```sh
docker buildx bake --allow=fs.read=.. core-android-builder --load
for abi in arm64-v8a x86_64; do
  docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/src -w /src \
      ghcr.io/euro-office/core-android-builder build/scripts/core-android.sh $abi
done
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e npm_config_cache=/tmp/npm \
    -v "$PWD":/src -w /src node:20 build/scripts/sdkjs.sh
build/scripts/dictionaries.sh
cd build && docker buildx bake --allow=fs.read=.. apk-native
```

- Results go to `build/out/core-android/<abi>/` as stripped `lib*.so`. libx2t reads them from there (`PATH_LIB_BUILD_TOOLS` in `core/X2tConverter/build/Android/libx2t/gradle.properties`).
- Checkouts, the CMake tree and unstripped libraries stay in `build/work/android-<arch>/`. A first build per ABI takes a while, mostly for V8; later builds are incremental.
- `scripts/sdkjs.sh` builds sdkjs (with sdkjs-forms) and collects the files the editor engine loads in `build/out/sdkjs/`.
- `scripts/dictionaries.sh` collects the spell checking dictionaries in `build/out/dictionaries/`: English, which comes with the app, and `index.json` with the `dictionaries` commit this checkout pins. The app downloads other languages from that commit (raw.githubusercontent.com) when a document or the device language needs them. It needs git, so it runs outside Docker.
- `apk-native` needs both ABIs, because libx2t and the engine build for `arm64-v8a` and `x86_64`.

## Testing on an emulator

`scripts/emulator-test.sh` boots the `emulator` image headless, installs an x86_64 APK, opens a document in the document editor and saves a screenshot and the log in `build/work/emulator/`:

```sh
docker buildx bake --allow=fs.read=.. emulator --load
cd .. && docker run --rm --device /dev/kvm -v "$PWD":/src -w /src \
    ghcr.io/euro-office/android-emulator build/scripts/emulator-test.sh build/out/<x86_64 apk> [document]
```

With `-e KEEP=1` the emulator keeps running, for further `docker exec <container> adb ...` commands.

## Tests

| Tests | What | How |
|---|---|---|
| Engine | `editors-android/engine/tests`: scripts on document-templates' samples, run by the engine on the host (`eo-render`) | `scripts/engine-host.sh` in core's build image, then `editors-android/engine/tests/run.sh build/work/host/engine/eo-render build/work/host/package` in the same image with `LD_LIBRARY_PATH=/src/build/work/host/package` |
| Co-editing | `editors-android/engine/tools/coedit/check.mjs`: the host engine (as the app runs it) and a web editor edit the samples together through a Document Server, down to the saved document | A Document Server (CI: `ghcr.io/euro-office/documentserver:latest-dev`), then `check.mjs` with `RUN_ENGINE`, see editors-android/engine/README.md |
| Unit | JVM tests of libeditors and libgeditors | `docker buildx bake --allow=fs.read=.. unit-tests`; reports and the result (0 for success) in `build/out/unit-tests/` |
| UI | `build/tests/ui`: the app on an emulator opens, edits and saves documents; screen and saved file are checked | `scripts/ui-tests.sh <x86_64 apk>` in the emulator image (`BOOTED=1` to use a running emulator); screenshots and logs in `build/work/ui-tests/` |

The engine's host build is described in `scripts/engine-host.sh`. It needs sdkjs from `scripts/sdkjs.sh`.

## Notes

- Toolchain versions must match `documents-app-android/app_manager/gradle/libs.versions.toml` (`compileSdk`, `ndk`). Update the `ARG`s in `android.Dockerfile` when that file changes.
- Debug builds need no secrets. Without `google-services.json`, the Google Services plugin is skipped and Firebase stays uninitialised.
- `:libx2t` is only included with `-PwithNativeCore=true` (set by `apk-native`).

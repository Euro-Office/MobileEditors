# Build

All builds run in Docker with `docker buildx bake`. Run the commands from this directory.

## Targets

| Target | What it does |
|---|---|
| `android-toolchain` | Ubuntu 24.04 with JDK 17, Android SDK (platform 36, build-tools 36.0.0), NDK 28.2.13676358 and CMake 3.22.1 |
| `core-android-builder` | `android-toolchain` plus the host tools for cross-compiling core and its 3rd-party deps (clang, ninja, autotools, perl, patchelf) |
| `apk` (default) | Builds `documents-app-android` with the `editors-android` modules and writes the APKs to `build/out/` |
| `apk-native` | Like `apk`, plus the libx2t converter linked against the core libraries in `build/out/core-android/` |

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
cd build && docker buildx bake --allow=fs.read=.. apk-native
```

- Results go to `build/out/core-android/<abi>/` as stripped `lib*.so`. libx2t reads them from there (`PATH_LIB_BUILD_TOOLS` in `core/X2tConverter/build/Android/libx2t/gradle.properties`).
- Checkouts, the CMake tree and unstripped libraries stay in `build/work/android-<arch>/`. A first build per ABI takes a while, mostly for V8; later builds are incremental.
- `apk-native` needs both ABIs, because libx2t builds for `arm64-v8a` and `x86_64`.
- With a debug APK from `apk-native`, the placeholder editor screen offers "Convert to PDF (x2t test)" to check the native core on a device.

## Notes

- Toolchain versions must match `documents-app-android/app_manager/gradle/libs.versions.toml` (`compileSdk`, `ndk`). Update the `ARG`s in `android.Dockerfile` when that file changes.
- Debug builds need no secrets. Without `google-services.json`, the Google Services plugin is skipped and Firebase stays uninitialised.
- `:libx2t` is only included with `-PwithNativeCore=true` (set by `apk-native`).

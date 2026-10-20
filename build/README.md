# Build

All builds run in Docker with `docker buildx bake`. Run the commands from this directory.

## Targets

| Target | What it does | Status |
|---|---|---|
| `android-toolchain` | Ubuntu 24.04 with JDK 17, Android SDK (platform 36, build-tools 36.0.0), NDK 28.2.13676358 and CMake 3.22.1 | available |
| `apk` (default) | Builds `documents-app-android` with the `editors-android` modules and writes the APKs to `build/out/` | available |
| `v8-android` | V8 monolith for Android ABIs | planned (M0) |
| `core-android` | Cross-build of core (x2t, doctrenderer, graphics, PdfFile, …) for Android ABIs; enables `:libx2t` | planned (M0) |
| `sdkjs-native` | sdkjs (+ sdkjs-forms) bundles for the native engine, plus fonts, themes, dictionaries and templates as editor assets | planned (M0/M3) |

## Usage

```sh
docker buildx bake --allow=fs.read=.. android-toolchain     # one-time, cached afterwards
docker buildx bake --allow=fs.read=.. apk                   # debug APKs in build/out/
GRADLE_TASK=:appmanager:assembleRelease docker buildx bake --allow=fs.read=.. apk   # needs the release secrets
```

`--allow=fs.read=..` lets bake read the sibling submodules (`../documents-app-android`, `../editors-android`); buildx asks for it because they are outside `build/`.

The Gradle cache is kept in a BuildKit cache mount, so later builds are incremental.

## Notes

- Toolchain versions must match `documents-app-android/app_manager/gradle/libs.versions.toml` (`compileSdk`, `ndk`). Update the `ARG`s in `android.Dockerfile` when that file changes.
- Debug builds need no secrets. Without `google-services.json`, the Google Services plugin is skipped and Firebase stays uninitialised.
- `:libx2t` is only included with `-PwithNativeCore=true`, once the `core-android` target provides the native libraries.

# Build

All builds run in Docker with `docker buildx bake`. Run the commands from this directory.

As in DocumentServer and DesktopEditors, each repository says how it is built in its own module Dockerfile (`.docker/*.bake.Dockerfile`); `docker-bake.hcl` wires them together with `target:` contexts. The build context is the whole checkout (see `../.dockerignore`), so bake needs `--allow=fs.read=..`.

| Repository | Dockerfile | Delivers |
|---|---|---|
| core | `core/.docker/core-android.bake.Dockerfile` | core for Android per ABI: stripped `lib*.so` (x2t and what it links) |
| core | `core/.docker/core.bake.Dockerfile` | core for the host (desktop build), for the engine tests |
| sdkjs | `sdkjs/.docker/sdkjs.bake.Dockerfile` (`sdkjs-native`) | the sdkjs files the editor engine loads (with sdkjs-forms) |
| editors-engine | `editors-engine/.docker/editors-engine.bake.Dockerfile` | the engine on the host with `eo-render`, the engine tests |
| documents-app-android | `documents-app-android/.docker/app.bake.Dockerfile` | the app's toolchain, the APKs with the editors, the editors' unit tests and Lint |
| MobileEditors | `build/android.Dockerfile` | the NDK image all native code builds with, the dictionaries, the emulator |

## Targets

| Target | What it does |
|---|---|
| `apk` (default) | The app with the editors; the APKs go to `build/out/` |
| `unit-tests` | Unit tests and Android Lint of `libeditors` and `libgeditors`: reports, `gradle.log` and `result` (0 for success) in `build/out/unit-tests/` |
| `engine-tests` | The engine tests (`editors-engine/tests`) on the host: `tests.log`, `result` and the saved files in `build/out/engine-tests/` |
| `engine-host` | The engine on the host as an image (`ghcr.io/euro-office/editors-engine-host`, with `--load`): `eo-render` and its runtime in `/package/bin` |
| `emulator` | Headless Android emulator (Android 14, x86_64) for the UI tests; needs `/dev/kvm` |
| `core-android-arm64`, `core-android-x64` | core for Android (`arm64-v8a`, `x86_64`) |
| `core-host` | core's desktop build, for `engine-host` |
| `sdkjs-native` | sdkjs for the engine |
| `dictionaries` | The English dictionary, which comes with the app, and `index.json`: the `dictionaries` commit this checkout pins, from which the app downloads other languages (raw.githubusercontent.com) when a document or the device language needs them |
| `android-ndk` | Ubuntu 24.04 with NDK 28.2.13676358 and the host tools for core's third-party builds |
| `android-toolchain` | `android-ndk` plus JDK 17, Android SDK (platform 36, build-tools 36.0.0) and CMake 3.22.1 |

## Usage

```sh
export DICTIONARIES_COMMIT=$(git rev-parse HEAD:dictionaries)
# The first time: core for each ABI one after the other (each builds V8 for hours)
docker buildx bake --allow=fs.read=.. core-android-arm64
docker buildx bake --allow=fs.read=.. core-android-x64
docker buildx bake --allow=fs.read=.. apk                      # debug APKs in build/out/
docker buildx bake --allow=fs.read=.. unit-tests
docker buildx bake --allow=fs.read=.. engine-tests
GRADLE_TASK=:appmanager:assembleRelease docker buildx bake --allow=fs.read=.. apk   # needs the release secrets
```

`DICTIONARIES_COMMIT` is needed by the targets that build the app (`apk`, `unit-tests`).

Builds are incremental: the build trees of core (and its third-party libraries), the engine and Gradle stay in BuildKit cache mounts. **`docker builder prune` deletes them**, and core for Android then takes hours again.

To build the app in Android Studio instead, put the results where its Gradle build expects them:

```sh
docker buildx bake --allow=fs.read=.. core-android-arm64 --set '*.output=type=local,dest=out/core-android/arm64-v8a'
docker buildx bake --allow=fs.read=.. core-android-x64 --set '*.output=type=local,dest=out/core-android/x86_64'
docker buildx bake --allow=fs.read=.. sdkjs-native --set '*.output=type=local,dest=out/sdkjs'
docker buildx bake --allow=fs.read=.. dictionaries --set '*.output=type=local,dest=out/dictionaries'
```

and build `documents-app-android/app_manager` with `-PwithNativeCore=true`.

## The engine on the host

`engine-host` is also the development loop for the engine: build it after changing `editors-engine` (incrementally) and run `eo-render` or the tests from the checkout:

```sh
docker buildx bake --allow=fs.read=.. engine-host --load
cd .. && docker run --rm -v "$PWD":/src -w /src ghcr.io/euro-office/editors-engine-host \
    editors-engine/tests/run.sh /engine/eo-render /package/bin [test.js ...]
docker run -i --rm -v "$PWD":/src -w /src -e EO_REPL=1 ghcr.io/euro-office/editors-engine-host \
    eo-render /package/bin <document> build/work/repl 1
```

See `editors-engine/README.md` for `eo-render` and its REPL.

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
| Engine | `editors-engine/tests`: scripts on document-templates' samples, run by the engine on the host (`eo-render`) | `docker buildx bake --allow=fs.read=.. engine-tests` |
| Co-editing | `editors-engine/tools/coedit/check.mjs`: the host engine (as the app runs it) and a web editor edit the samples (and a PDF the engine tests saved) together through a Document Server, down to the saved document | A Document Server (CI: `ghcr.io/euro-office/documentserver:latest-dev`), then `check.mjs` with `RUN_ENGINE` running the `engine-host` image, see editors-engine/README.md |
| Unit | JVM tests and Lint of libeditors and libgeditors | `docker buildx bake --allow=fs.read=.. unit-tests` |
| UI | `build/tests/ui`: the app on an emulator opens, edits and saves documents; screen and saved file are checked | `scripts/ui-tests.sh <x86_64 apk>` in the emulator image (`BOOTED=1` to use a running emulator); screenshots and logs in `build/work/ui-tests/` |

## Releasing

The app's version is `VERSION` in the repository root: `0.1.0-alpha.1`, `0.1.0-beta.1`, `0.1.0-rc.1` or `0.1.0`. `scripts/version.sh` derives the version code from it (`MMmmppSS`, the stage `SS` is the alpha number, 30 + the beta number, 60 + the rc number or 99 for the final release), and CI passes both to the `apk` target (`VERSION_NAME`, `VERSION_CODE`), which hands them to the app's Gradle build (`-PappVersionName`, `-PappVersionCode`; without them the app keeps its own version).

Only MobileEditors is tagged: its tag pins every submodule. To release:

1. Set `VERSION` in a pull request and merge it.
2. Tag the merge commit: `git tag -a v0.1.0-alpha.1 -m "Release v0.1.0-alpha.1" && git push origin v0.1.0-alpha.1`.
3. CI builds and tests the tag. Once every job passed, the `release` job publishes a GitHub release with the `arm64-v8a` and `x86_64` APKs and their checksums, a prerelease for alpha, beta and rc versions.

There is no release key yet: the release has the debug APKs, each CI run signs them with a new debug key, so a release only installs over the previous one after uninstalling it.

## Notes

- The NDK version in `android.Dockerfile` (`android-ndk`) and the SDK versions in `documents-app-android/.docker/app.bake.Dockerfile` must match `documents-app-android/app_manager/gradle/libs.versions.toml` (`ndk`, `compileSdk`).
- Debug builds need no secrets. Without `google-services.json`, the Google Services plugin is skipped and Firebase stays uninitialised.
- `:libx2t` is only included with `-PwithNativeCore=true` (set by the `apk` and `unit-tests` targets).

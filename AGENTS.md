## What this repo is

MobileEditors is the orchestrator for the Euro-Office mobile apps with native document editors: the Android app now, the iOS app later. Like `DocumentServer` and `DesktopEditors`, it pins the shared submodules and holds the workspace-level build configuration.

Submodules:
- `core`, `core-fonts`, `sdkjs`, `sdkjs-forms`, `dictionaries`, `document-templates`: shared with DocumentServer and DesktopEditors.
- `documents-app-android`: the Android app shell (file manager, accounts, storages, sharing). It is a fork of ONLYOFFICE's open app.
- `editors-engine`: the editor engine both apps share: C++ that runs sdkjs in core's doctrenderer and draws pages with core's graphics engine, the JavaScript that drives sdkjs, and its tests and co-editing check.
- `editors-android`: the Android app's editors: the engine's JNI binding, the per-editor Kotlin APIs and the native editor UI.
- `editors-ios`: the iOS app's editors (not started yet).

Code both apps can use goes to `editors-engine`; only what is a platform's own goes to `editors-android` or `editors-ios`.

`web-apps` is intentionally not a submodule. The UI is native, so web-apps is never shipped. Use a separate checkout of `web-apps/apps/*/mobile` only as a reference for which sdkjs `asc_*` calls a feature needs.

> **Shared submodules**: `core`, `sdkjs`, `sdkjs-forms`, `core-fonts`, `dictionaries` and `document-templates` are also submodules of DocumentServer and DesktopEditors. A change merged to any of those repos affects all products.

## Architecture notes

### Submodule dependency chain

```
core-fonts → core (host AllFontsGen) → sdkjs (+ sdkjs-forms, native build) → editor assets ─┐
core (Android cross-build: x2t, doctrenderer, graphics, PdfFile, …) + v8 ─→ editors-engine → editors-android ─┼→ documents-app-android → APK
dictionaries, document-templates ──────────────────────────────────────────→ editor assets ─┘
```

### How the app finds the editors

`documents-app-android/app_manager/settings.gradle.kts` includes the editor Gradle modules by relative path, and includes each only if its directory exists:
- `:libx2t` → `core/X2tConverter/build/Android/libx2t`
- `:libeditors`, `:libdocs`, `:libcells`, `:libslides`, `:libgeditors`, `:libresources`, `:libgdocs`, `:libgcells`, `:libgslides` → `editors-android/<module>`
- `libeditors`' native build (`src/native/cpp/CMakeLists.txt`) includes `editors-engine` (`-DEDITORS_ENGINE_DIR`, the checkout's `editors-engine`)

The app talks to the editors only through a runtime contract, not through compile-time imports. The contract is defined in `documents-app-android/toolkit/libtoolkit/.../managers/utils/EditorsContract.kt`:
- 4 activity class names: `lib.editors.gdocs.ui.activities.DocsActivity`, `lib.editors.gcells.ui.activities.CellsActivity`, `lib.editors.gslides.ui.activities.SlidesActivity`, `lib.editors.gbase.ui.activities.PdfActivity`.
- Intent extras, result codes and the form-filling round trip.
- The `libshared` `MessengerService` IPC.

Keep these names and keys stable. The app shell must keep working unchanged.

### Editor engine

The engine (`editors-engine`) hosts **current** sdkjs in V8 through core's doctrenderer and drives it via its public `asc_*` API. Each app has its own typed binding on top (Android: Kotlin/JNI in `editors-android`). Pages are rendered with core's graphics engine (`CGraphicsEmbed`) into the platform's bitmaps. ONLYOFFICE's old native JS layer was deleted from sdkjs in commit `a55a492ff6` (Dec 2023). It is a reference and code donor only; do not restore it wholesale.

## Rules

- **Never** modify submodule contents directly from here without checking that submodule's own `AGENTS.md`.
- **Never** change the editor contract (`EditorsContract.kt` class names, extras, result codes) without changing both `documents-app-android` and `editors-android` together.
- **Never** change the engine's commands (`eoEngine.*`) or state in `editors-engine` without changing the apps' bindings (`editors-android`'s `EditorDocument`, later `editors-ios`) along.
- **Never** introduce workspace-wide dependencies that break the "no root package.json" rule in submodules.
- **Always** update this `AGENTS.md` when you change workspace-level developer workflows.
- **Never** update the refs of shared submodules (`core`, `sdkjs`, …) in a commit that also changes anything else. Bump them deliberately, in their own commits.

## Build

All builds run in Docker, so no local Android SDK or NDK is needed. As in DocumentServer, each repository is built by its own module Dockerfile (`core/.docker/core-android.bake.Dockerfile`, `sdkjs/.docker/sdkjs.bake.Dockerfile`, `editors-engine/.docker/editors-engine.bake.Dockerfile`, `documents-app-android/.docker/app.bake.Dockerfile`); `build/docker-bake.hcl` wires them together and `build/android.Dockerfile` has the shared NDK image, the dictionaries and the emulator:

```sh
cd build
export DICTIONARIES_COMMIT=$(git rev-parse HEAD:dictionaries)
docker buildx bake --allow=fs.read=.. apk            # the app with the editors, APKs in build/out/
docker buildx bake --allow=fs.read=.. unit-tests     # editors' unit tests and Lint
docker buildx bake --allow=fs.read=.. engine-tests   # engine tests on the host
```

See `build/README.md` for all targets, the engine's development loop and building in Android Studio. A first build of core for Android takes hours (V8): build `core-android-arm64` and `core-android-x64` one after the other. Their build trees stay in BuildKit cache mounts, which `docker builder prune` deletes.

The app's release secrets (`*.gpg`: keystore, auth strings) are not needed for debug builds. The app uses no Firebase: crash reports stay on the device (`CrashLog` in libtoolkit) until the user sends them. Release builds can take the signing key from `EO_KEYSTORE_FILE`, `EO_KEYSTORE_PASSWORD`, `EO_KEY_ALIAS` and `EO_KEY_PASSWORD`.

## CI

`.github/workflows/ci.yml` builds the APK and runs the engine, co-editing, unit and UI tests (see `build/README.md`). The co-editing tests run a Document Server from `ghcr.io/euro-office/documentserver:latest-dev`; while that package is private, the workflow's token needs read access to it. The jobs run the bake targets with BuildKit's GitHub Actions cache, so a change of `core` rebuilds core for Android (hours, mostly V8). The checkout needs all submodules: while repositories are private, the workflow needs a token with access to them.

## Commits

- Commit messages must follow the Conventional Commits v1.0.0 specification — e.g. feat(engine): render document tiles, fix(app): handle missing snapshot library.
- Every commit containing AI-assisted content must include an `Assisted-by:` trailer identifying the coding agent and the model(s) used:
    Pattern: Assisted-by: AGENT_NAME:MODEL_VERSION (e.g. Assisted-by: ClaudeCode:claude-opus-4-8)
    Add one `Assisted-by:` line per agent/model if more than one was used.

## Contribution policy

All contributions generated or assisted by an agent must fully comply with the **[AI Contribution Policy](https://github.com/Euro-Office/.github/blob/main/AI_POLICY.md)**, and with the contribution guidelines of the repository being changed.

### What an agent must always do

- Add an `Assisted-by: AGENT_NAME:MODEL_VERSION` git trailer to every commit containing AI-assisted content.
- Produce focused, scoped changes that address exactly one concern.
- Verify all dependencies against actual package registries before suggesting them.
- Warn the contributor if a pull request is growing too large, and suggest a logical split before it is opened.

### What an agent must never do

- Open issues, submit pull requests, post review comments, or push autonomously. Every contribution must be reviewed and submitted by a human.
- Add `Signed-off-by` tags to commits.
- Write PR descriptions, review comments, or issue reports on behalf of the contributor.

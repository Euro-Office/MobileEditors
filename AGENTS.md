## What this repo is

AndroidEditors is the orchestrator for the Euro-Office Android app with native document editors. Like `DocumentServer` and `DesktopEditors`, it pins the shared submodules and holds the workspace-level build configuration.

Submodules:
- `core`, `core-fonts`, `sdkjs`, `sdkjs-forms`, `dictionaries`, `document-templates`: shared with DocumentServer and DesktopEditors.
- `documents-app-android`: the Android app shell (file manager, accounts, storages, sharing). It is a fork of ONLYOFFICE's open app.
- `editors-android`: our editor code. It contains the C++ engine (JNI), the per-editor Kotlin APIs and the native editor UI.

`web-apps` is intentionally not a submodule. The UI is native, so web-apps is never shipped. Use a separate checkout of `web-apps/apps/*/mobile` only as a reference for which sdkjs `asc_*` calls a feature needs.

> **Shared submodules**: `core`, `sdkjs`, `sdkjs-forms`, `core-fonts`, `dictionaries` and `document-templates` are also submodules of DocumentServer and DesktopEditors. A change merged to any of those repos affects all products.

## Architecture notes

### Submodule dependency chain

```
core-fonts → core (host AllFontsGen) → sdkjs (+ sdkjs-forms, native build) → editor assets ─┐
core (Android cross-build: x2t, doctrenderer, graphics, PdfFile, …) + v8 ─→ editors-android ─┼→ documents-app-android → APK
dictionaries, document-templates ──────────────────────────────────────────→ editor assets ─┘
```

### How the app finds the editors

`documents-app-android/app_manager/settings.gradle.kts` includes the editor Gradle modules by relative path, and includes each only if its directory exists:
- `:libx2t` → `core/X2tConverter/build/Android/libx2t`
- `:libeditors`, `:libdocs`, `:libcells`, `:libslides`, `:libgeditors`, `:libresources`, `:libgdocs`, `:libgcells`, `:libgslides` → `editors-android/<module>`

The app talks to the editors only through a runtime contract, not through compile-time imports. The contract is defined in `documents-app-android/toolkit/libtoolkit/.../managers/utils/EditorsContract.kt`:
- 4 activity class names: `lib.editors.gdocs.ui.activities.DocsActivity`, `lib.editors.gcells.ui.activities.CellsActivity`, `lib.editors.gslides.ui.activities.SlidesActivity`, `lib.editors.gbase.ui.activities.PdfActivity`.
- Intent extras, result codes and the form-filling round trip.
- The `libshared` `MessengerService` IPC.

Keep these names and keys stable. The app shell must keep working unchanged.

### Editor engine

The engine hosts **current** sdkjs in V8 through core's doctrenderer and drives it via its public `asc_*` API. Our own typed Kotlin/JNI API sits on top. Pages are rendered with core's graphics engine (`CGraphicsEmbed`) into Android bitmaps. ONLYOFFICE's old native JS layer was deleted from sdkjs in commit `a55a492ff6` (Dec 2023). It is a reference and code donor only; do not restore it wholesale.

## Rules

- **Never** modify submodule contents directly from here without checking that submodule's own `AGENTS.md`.
- **Never** change the editor contract (`EditorsContract.kt` class names, extras, result codes) without changing both `documents-app-android` and `editors-android` together.
- **Never** introduce workspace-wide dependencies that break the "no root package.json" rule in submodules.
- **Always** update this `AGENTS.md` when you change workspace-level developer workflows.
- **Never** update the refs of shared submodules (`core`, `sdkjs`, …) in a commit that also changes anything else. Bump them deliberately, in their own commits.

## Build

All builds run in Docker, so no local Android SDK or NDK is needed:

```sh
cd build
docker buildx bake --allow=fs.read=.. android-toolchain   # JDK 17, Android SDK, NDK, CMake (one-time)
docker buildx bake --allow=fs.read=.. apk                 # builds documents-app-android with the editors-android modules
```

The APK is written to `build/out/`. See `build/README.md` for details and the planned native targets (`core-android`, `v8-android`, `sdkjs-native`).

The app's release secrets (`*.gpg`: keystore, auth strings, Google services) are not needed for debug builds. Without `google-services.json`, the Firebase plugins are skipped.

## CI

`.github/workflows/ci.yml` builds the APK and runs the engine, unit and UI tests (see `build/README.md`). Core for Android, sdkjs and the host core are cached by the commits of their submodules, so a change of `core` rebuilds core for Android (hours, mostly V8). The checkout needs all submodules: while repositories are private, the workflow needs a token with access to them.

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

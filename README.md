<!--
SPDX-FileCopyrightText: 2026 Euro-Office contributors
SPDX-License-Identifier: AGPL
-->

[![License](https://img.shields.io/badge/License-GNU%20AGPL%20V3-green.svg?style=flat)](https://www.gnu.org/licenses/agpl-3.0.en.html)

# Euro-Office Mobile
**Your sovereign office, on your phone**

This repository builds the Euro-Office mobile apps with native document, spreadsheet, presentation and PDF editors: the Android app now, the iOS app later. It pins the components as git submodules:

| Submodule | Purpose |
|---|---|
| `core` | Format conversion (x2t), JS engine host (doctrenderer), rendering, PDF/XPS/DjVu |
| `sdkjs`, `sdkjs-forms` | Document model, layout and editing logic |
| `core-fonts` | Bundled fonts |
| `dictionaries` | Spellcheck dictionaries |
| `document-templates` | Blank documents for "create new" |
| `documents-app-android` | The Android app shell: files, accounts, storages, sharing |
| `editors-engine` | The editor engine both apps share: C++ around sdkjs and core, its tests and co-editing check |
| `editors-android` | The Android app's editors: the engine's JNI binding, Kotlin APIs and UI |
| `editors-ios` | The iOS app's editors (not started yet) |

> Status: early development. The Android editors open, edit, save and co-edit documents, spreadsheets, presentations and PDFs; the iOS editors are not started.

## Getting started

```sh
git clone --recurse-submodules git@github.com:Euro-Office/MobileEditors.git
cd MobileEditors/build
docker buildx bake --allow=fs.read=.. android-toolchain
docker buildx bake --allow=fs.read=.. apk
```

See [build/README.md](build/README.md) for build details and [AGENTS.md](AGENTS.md) for the architecture.

## Get involved
Get involved! You can file issues, propose pull requests and more. We are looking forward to make the digital sovereign office space better than ever before!

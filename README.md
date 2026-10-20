<!--
SPDX-FileCopyrightText: 2026 Euro-Office contributors
SPDX-License-Identifier: AGPL
-->

[![License](https://img.shields.io/badge/License-GNU%20AGPL%20V3-green.svg?style=flat)](https://www.gnu.org/licenses/agpl-3.0.en.html)

# Euro-Office for Android
**Your sovereign office, on your phone**

This repository builds the Euro-Office Android app with native document, spreadsheet, presentation and PDF editors. It pins the components as git submodules:

| Submodule | Purpose |
|---|---|
| `core` | Format conversion (x2t), JS engine host (doctrenderer), rendering, PDF/XPS/DjVu |
| `sdkjs`, `sdkjs-forms` | Document model, layout and editing logic |
| `core-fonts` | Bundled fonts |
| `dictionaries` | Spellcheck dictionaries |
| `document-templates` | Blank documents for "create new" |
| `documents-app-android` | The Android app shell: files, accounts, storages, sharing |
| `editors-android` | The native editors: C++ engine, Kotlin APIs and UI |

> Status: early development. The editor modules are a skeleton; documents cannot be opened yet.

## Getting started

```sh
git clone --recurse-submodules git@github.com:Euro-Office/AndroidEditors.git
cd AndroidEditors/build
docker buildx bake --allow=fs.read=.. android-toolchain
docker buildx bake --allow=fs.read=.. apk
```

See [build/README.md](build/README.md) for build details and [AGENTS.md](AGENTS.md) for the architecture.

## Get involved
Get involved! You can file issues, propose pull requests and more. We are looking forward to make the digital sovereign office space better than ever before!

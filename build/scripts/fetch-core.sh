#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Euro-Office contributors
# SPDX-License-Identifier: AGPL-3.0-only

# Downloads the prebuilt core for the core checkout from the build cache, for
# docker-bake.hcl instead of building core: arm64-v8a and x86_64 (core for
# Android, for the apk) and host (core for Linux, for the engine tests). Prints
# a bake variable for each package it got, e.g.
#   CORE_ANDROID_ARM64=./core-prebuilt/arm64-v8a
# for "export $(build/scripts/fetch-core.sh arm64-v8a x86_64)" or
# $GITHUB_ENV. Prints nothing for a package the build cache doesn't have, or
# when core has local changes: then the bake builds that core.
# EO_CORE_CACHE=off|require works as in core/scripts/core_package.py;
# EO_CORE_CHANNELS=main takes only packages built on core's main (releases).
set -euo pipefail

build="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core="$build/../core"

for name in "$@"; do
    case "$name" in
        arm64-v8a) platform=android-arm64-v8a product=android var=CORE_ANDROID_ARM64 ;;
        x86_64)    platform=android-x86_64    product=android var=CORE_ANDROID_X64 ;;
        host)      platform=linux-amd64       product=desktop var=CORE_HOST ;;
        *)         echo "unknown core package $name (arm64-v8a, x86_64, host)" >&2; exit 1 ;;
    esac
    status=0
    python3 "$core/scripts/core_package.py" fetch --core "$core" --platform "$platform" \
        --product "$product" --dest "$build/core-prebuilt/$name" \
        ${EO_CORE_CHANNELS:+--channels "$EO_CORE_CHANNELS"} >&2 || status=$?
    case "$status" in
        0) echo "$var=./core-prebuilt/$name" ;;
        3) ;;
        *) exit "$status" ;;
    esac
done

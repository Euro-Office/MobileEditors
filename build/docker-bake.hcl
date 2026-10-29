# docker-bake.hcl — run from the build/ directory, e.g.
#   DICTIONARIES_COMMIT=$(git rev-parse HEAD:dictionaries) docker buildx bake --allow=fs.read=.. apk
#
# Each repository builds itself with its module Dockerfile (.docker/*.bake.Dockerfile); the
# targets here wire them together with target: contexts. The build context is the checkout.

variable "COMPANY_NAME" {
  default = "Euro-Office"
}

variable "COMPANY_NAME_LOW" {
  default = regex_replace(lower(COMPANY_NAME), "\\s+", "-")
}

variable "REGISTRY" {
  default = "ghcr.io/${COMPANY_NAME_LOW}"
}

variable "TAG" {
  default = "latest"
}

# Gradle task for the apk target, e.g. :appmanager:assembleRelease
variable "GRADLE_TASK" {
  default = ":appmanager:assembleDebug"
}

# The app version (build/scripts/version.sh), else the one the app's Gradle build sets
variable "VERSION_NAME" {
  default = ""
}

variable "VERSION_CODE" {
  default = ""
}

# The dictionaries commit MobileEditors pins (git rev-parse HEAD:dictionaries), for the index of
# the dictionaries the app downloads
variable "DICTIONARIES_COMMIT" {
  default = ""
}

group "default" {
  targets = ["apk"]
}

# ------------------------------------------------------------------------------
# Shared and MobileEditors' own images (android.Dockerfile)

target "android-ndk" {
  context    = ".."
  dockerfile = "./build/android.Dockerfile"
  target     = "android-ndk"
  tags       = ["${REGISTRY}/android-ndk:${TAG}"]
}

target "dictionaries" {
  context    = ".."
  dockerfile = "./build/android.Dockerfile"
  target     = "dictionaries"
  args = {
    DICTIONARIES_COMMIT = DICTIONARIES_COMMIT
  }
}

# Headless emulator for the UI tests (scripts/ui-tests.sh)
target "emulator" {
  context    = ".."
  dockerfile = "./build/android.Dockerfile"
  target     = "emulator"
  tags       = ["${REGISTRY}/android-emulator:${TAG}"]
  contexts = {
    android-toolchain = "target:android-toolchain"
  }
}

# ------------------------------------------------------------------------------
# core and sdkjs

# Core for Android, per ABI. Build them one after the other the first time: each builds V8
target "core-android-arm64" {
  context    = ".."
  dockerfile = "./core/.docker/core-android.bake.Dockerfile"
  target     = "core-android"
  args = {
    ANDROID_ABI = "arm64-v8a"
  }
  contexts = {
    android-ndk = "target:android-ndk"
  }
  # The remote cache of the third-party builds, when the environment has them
  secret = ["id=nextcloud_user,env=NEXTCLOUD_USER", "id=nextcloud_pass,env=NEXTCLOUD_PASS"]
}

target "core-android-x64" {
  inherits = ["core-android-arm64"]
  args = {
    ANDROID_ABI = "x86_64"
  }
}

# Core for the host, for the engine tests
target "core-host" {
  context    = ".."
  dockerfile = "./core/.docker/core.bake.Dockerfile"
  target     = "core"
  args = {
    PRODUCT    = "desktop"
    BUILD_ROOT = "/package"
  }
  # The remote cache of the third-party builds, when the environment has them
  secret = ["id=nextcloud_user,env=NEXTCLOUD_USER", "id=nextcloud_pass,env=NEXTCLOUD_PASS"]
}

target "sdkjs-native" {
  context    = ".."
  dockerfile = "./sdkjs/.docker/sdkjs.bake.Dockerfile"
  target     = "sdkjs-native"
}

# ------------------------------------------------------------------------------
# The editor engine (editors-engine) on the host: eo-render and the engine tests

target "engine-host" {
  context    = ".."
  dockerfile = "./editors-engine/.docker/editors-engine.bake.Dockerfile"
  target     = "engine-host"
  tags       = ["${REGISTRY}/editors-engine-host:${TAG}"]
  contexts = {
    core-host    = "target:core-host"
    sdkjs-native = "target:sdkjs-native"
  }
}

# The tests' log, result (0 for success) and saved files in out/engine-tests
target "engine-tests" {
  inherits = ["engine-host"]
  target   = "engine-tests"
  tags     = []
  output   = ["type=local,dest=out/engine-tests"]
}

# ------------------------------------------------------------------------------
# The app (documents-app-android) with the editors

target "android-toolchain" {
  context    = ".."
  dockerfile = "./documents-app-android/.docker/app.bake.Dockerfile"
  target     = "android-toolchain"
  tags       = ["${REGISTRY}/android-toolchain:${TAG}"]
  contexts = {
    android-ndk = "target:android-ndk"
  }
}

# The APKs in out/
target "apk" {
  context    = ".."
  dockerfile = "./documents-app-android/.docker/app.bake.Dockerfile"
  target     = "apk-editors"
  args = {
    GRADLE_TASK = VERSION_NAME == "" ? GRADLE_TASK : "${GRADLE_TASK} -PappVersionName=${VERSION_NAME} -PappVersionCode=${VERSION_CODE}"
  }
  contexts = {
    android-ndk        = "target:android-ndk"
    core-android-arm64 = "target:core-android-arm64"
    core-android-x64   = "target:core-android-x64"
    sdkjs-native       = "target:sdkjs-native"
    dictionaries       = "target:dictionaries"
  }
  output = ["type=local,dest=out"]
}

# Unit tests and Android Lint of editors-android (libeditors, libgeditors): reports and the
# result (0 for success) in out/unit-tests; the APK needs not be built
target "unit-tests" {
  inherits = ["apk"]
  target   = "editors-unit-tests"
  output   = ["type=local,dest=out/unit-tests"]
}

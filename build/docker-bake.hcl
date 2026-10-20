# docker-bake.hcl — run from the build/ directory

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

group "default" {
  targets = ["apk"]
}

target "android-toolchain" {
  context    = "."
  dockerfile = "android.Dockerfile"
  target     = "android-toolchain"
  tags       = ["${REGISTRY}/android-toolchain:${TAG}"]
}

target "core-android-builder" {
  context    = "."
  dockerfile = "android.Dockerfile"
  target     = "core-android-builder"
  tags       = ["${REGISTRY}/core-android-builder:${TAG}"]
}

target "apk" {
  context    = "."
  dockerfile = "android.Dockerfile"
  target     = "apk"
  contexts = {
    app               = "../documents-app-android"
    editors           = "../editors-android"
  }
  args = {
    GRADLE_TASK = GRADLE_TASK
  }
  output = ["type=local,dest=out"]
}

# Like apk, plus the libx2t converter with the core libraries from
# scripts/core-android.sh (build/out/core-android/<abi>)
target "apk-native" {
  inherits = ["apk"]
  target   = "apk-native"
  contexts = {
    app       = "../documents-app-android"
    editors   = "../editors-android"
    core      = "../core"
    core-libs = "out/core-android"
  }
}

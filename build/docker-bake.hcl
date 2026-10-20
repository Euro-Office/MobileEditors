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

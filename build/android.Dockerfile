# ==============================================================================
# Android build image and APK build for AndroidEditors.
# Consumed by build/docker-bake.hcl; not meant to be built standalone.
#
# REQUIRED CONTEXTS (apk targets):
# - app:     documents-app-android
# - editors: editors-android
# ==============================================================================

#### TOOLCHAIN ####
FROM ubuntu:24.04 AS android-toolchain

    ARG CMDLINE_TOOLS_VERSION=16111833
    # Keep in sync with documents-app-android/app_manager/gradle/libs.versions.toml
    ARG ANDROID_PLATFORM=android-36
    ARG ANDROID_BUILD_TOOLS=36.0.0
    ARG ANDROID_NDK=28.2.13676358
    ARG ANDROID_CMAKE=3.22.1

    ENV ANDROID_HOME=/opt/android-sdk
    ENV ANDROID_SDK_ROOT=${ANDROID_HOME}
    ENV ANDROID_NDK_HOME=${ANDROID_HOME}/ndk/${ANDROID_NDK}
    ENV PATH=${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools

    RUN apt-get update && \
        apt-get install -y --no-install-recommends \
            ca-certificates curl unzip git python3 openjdk-17-jdk-headless && \
        rm -rf /var/lib/apt/lists/*

    RUN mkdir -p ${ANDROID_HOME}/cmdline-tools && \
        curl -fsSL -o /tmp/cmdline-tools.zip \
            https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip && \
        unzip -q /tmp/cmdline-tools.zip -d ${ANDROID_HOME}/cmdline-tools && \
        mv ${ANDROID_HOME}/cmdline-tools/cmdline-tools ${ANDROID_HOME}/cmdline-tools/latest && \
        rm /tmp/cmdline-tools.zip

    RUN yes | sdkmanager --licenses > /dev/null && \
        sdkmanager --install \
            "platform-tools" \
            "platforms;${ANDROID_PLATFORM}" \
            "build-tools;${ANDROID_BUILD_TOOLS}" \
            "ndk;${ANDROID_NDK}" \
            "cmake;${ANDROID_CMAKE}" > /dev/null

    WORKDIR /src

#### APK ####
FROM android-toolchain AS apk-build

    ARG GRADLE_TASK=:appmanager:assembleDebug

    # Same relative layout as the AndroidEditors checkout, so settings.gradle.kts resolves ../../editors-android
    COPY --from=app . /src/documents-app-android
    COPY --from=editors . /src/editors-android

    RUN --mount=type=cache,target=/root/.gradle \
        cd /src/documents-app-android/app_manager && \
        ./gradlew --no-daemon ${GRADLE_TASK} && \
        mkdir -p /out && \
        find appmanager/build/outputs/apk -name '*.apk' -exec cp {} /out/ \;

FROM scratch AS apk
    COPY --from=apk-build /out/ /

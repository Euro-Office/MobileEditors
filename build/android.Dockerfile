# ==============================================================================
# Android build image and APK build for AndroidEditors.
# Consumed by build/docker-bake.hcl; not meant to be built standalone.
#
# REQUIRED CONTEXTS (apk targets):
# - app:       documents-app-android
# - editors:   editors-android
# apk-native additionally:
# - core:      core sources (for the libx2t JNI wrapper)
# - core-libs: build/out/core-android (see scripts/core-android.sh)
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
            "cmake;${ANDROID_CMAKE}" > /dev/null && \
        chmod -R a+rX ${ANDROID_HOME}  # builds may run as a non-root user

    WORKDIR /src

#### CORE BUILDER ####
# Host tools for cross-compiling core and its 3rd-party deps
# (core/Common/3dParty/build_3rdparty.py --target=android-*) with the NDK.
FROM android-toolchain AS core-android-builder

    RUN apt-get update && \
        apt-get install -y --no-install-recommends \
            build-essential clang lld ninja-build cmake pkg-config \
            autoconf automake libtool perl patch patchelf python-is-python3 xz-utils bzip2 file && \
        rm -rf /var/lib/apt/lists/*

    ENV ANDROID_NDK_ROOT=${ANDROID_NDK_HOME}

#### APK ####
FROM android-toolchain AS apk-build

    ARG GRADLE_TASK=:appmanager:assembleDebug

    # Same relative layout as the AndroidEditors checkout, so settings.gradle.kts resolves ../../editors-android
    COPY --from=app . /src/documents-app-android
    COPY --from=editors . /src/editors-android

    # ~/.android holds the debug keystore; keeping it gives all debug APKs the same signature
    RUN --mount=type=cache,target=/root/.gradle \
        --mount=type=cache,target=/root/.android \
        cd /src/documents-app-android/app_manager && \
        ./gradlew --no-daemon ${GRADLE_TASK} && \
        mkdir -p /out && \
        find appmanager/build/outputs/apk -name '*.apk' -exec cp {} /out/ \;

FROM scratch AS apk
    COPY --from=apk-build /out/ /

#### APK WITH NATIVE CORE ####
FROM android-toolchain AS apk-native-build

    ARG GRADLE_TASK=:appmanager:assembleDebug

    COPY --from=app . /src/documents-app-android
    COPY --from=editors . /src/editors-android
    COPY --from=core . /src/core
    COPY --from=core-libs . /src/build/out/core-android

    # ~/.android holds the debug keystore; keeping it gives all debug APKs the same signature
    RUN --mount=type=cache,target=/root/.gradle \
        --mount=type=cache,target=/root/.android \
        cd /src/documents-app-android/app_manager && \
        ./gradlew --no-daemon -PwithNativeCore=true ${GRADLE_TASK} && \
        mkdir -p /out && \
        find appmanager/build/outputs/apk -name '*.apk' -exec cp {} /out/ \;

FROM scratch AS apk-native
    COPY --from=apk-native-build /out/ /

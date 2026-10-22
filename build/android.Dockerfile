# ==============================================================================
# MobileEditors' own images, consumed by build/docker-bake.hcl (not meant to be
# built standalone). The repositories build themselves with their module
# Dockerfiles (core, sdkjs, editors-engine, documents-app-android); this file
# has what they share and what tests the assembled app.
#
# - android-ndk: the NDK and the host tools for native builds; core
#   (core-android) and the app (its JNI code, android-toolchain) build on it,
#   so all native code has the same NDK and C++ runtime
# - dictionaries: the bundled spell checking dictionary and the index of the
#   others (needs DICTIONARIES_COMMIT, the commit MobileEditors pins)
# - emulator: a headless Android emulator for the UI tests (needs the app's
#   android-toolchain as context)
# ==============================================================================

#### NDK ####
FROM ubuntu:24.04 AS android-ndk

    # Keep in sync with documents-app-android/app_manager/gradle/libs.versions.toml (ndk)
    ARG ANDROID_NDK_RELEASE=r28c
    ARG ANDROID_NDK_VERSION=28.2.13676358

    # Host tools of core's third-party builds (core/Common/3dParty/build_3rdparty.py)
    RUN apt-get update && \
        apt-get install -y --no-install-recommends \
            ca-certificates curl unzip git python3 python-is-python3 \
            build-essential clang lld ninja-build cmake pkg-config \
            autoconf automake libtool perl patch xz-utils bzip2 file && \
        rm -rf /var/lib/apt/lists/*

    RUN curl -fsSL -o /tmp/ndk.zip https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_RELEASE}-linux.zip && \
        unzip -q /tmp/ndk.zip -d /opt && \
        mv /opt/android-ndk-${ANDROID_NDK_RELEASE} /opt/android-ndk && \
        rm /tmp/ndk.zip && \
        grep -q "Pkg.Revision = ${ANDROID_NDK_VERSION}" /opt/android-ndk/source.properties

    ENV ANDROID_NDK_ROOT=/opt/android-ndk
    ENV ANDROID_NDK_VERSION=${ANDROID_NDK_VERSION}

#### DICTIONARIES ####
# The English dictionary, which comes with the app, and index.json: the dictionaries
# commit, where to download the others from at that commit and each one's languages (LCIDs)
FROM ubuntu:24.04 AS dictionaries-build

    ARG DICTIONARIES_COMMIT

    COPY dictionaries /dictionaries
    COPY .gitmodules /.gitmodules

    RUN <<EOF
        set -e
        [ -n "${DICTIONARIES_COMMIT}" ] || { echo "Set DICTIONARIES_COMMIT (git rev-parse HEAD:dictionaries)" >&2; exit 1; }
        REPOSITORY=$(sed -n '/submodule "dictionaries"/,/url/s#.*url = ##p' /.gitmodules)
        URL=$(echo "$REPOSITORY" | sed 's#\.git$##; s#^git@github.com:#https://github.com/#; s#^https://github.com/#https://raw.githubusercontent.com/#')
        mkdir -p /out/en_US
        cp /dictionaries/en_US/en_US.aff /dictionaries/en_US/en_US.dic /out/en_US/
        {
            printf '{"commit": "%s", "url": "%s", "languages": {' "${DICTIONARIES_COMMIT}" "$URL"
            first=1
            for dir in /dictionaries/*/; do
                name=$(basename "$dir")
                [ -f "$dir/$name.dic" ] && [ -f "$dir/$name.json" ] || continue
                codes=$(sed 's/.*\[\(.*\)\].*/\1/' "$dir/$name.json" | tr -d ' \n\r')
                [ $first -eq 1 ] || printf ', '
                printf '"%s": [%s]' "$name" "$codes"
                first=0
            done
            printf '}}\n'
        } > /out/index.json
EOF

FROM scratch AS dictionaries
    COPY --from=dictionaries-build /out/ /

#### EMULATOR ####
# Headless Android emulator for testing APKs (scripts/emulator-test.sh, ui-tests.sh), needs
# /dev/kvm. Google APIs images allow "adb root", to start the app's non-exported editor activities.
FROM android-toolchain AS emulator

    ARG SYSTEM_IMAGE="system-images;android-34;google_apis;x86_64"

    RUN apt-get update && \
        apt-get install -y --no-install-recommends libpulse0 libnss3 libxcomposite1 libxcursor1 \
            libxdamage1 libxi6 libxtst6 libgl1 libdbus-1-3 && \
        rm -rf /var/lib/apt/lists/*

    RUN yes | sdkmanager --licenses > /dev/null && \
        sdkmanager --install "emulator" "${SYSTEM_IMAGE}" > /dev/null && \
        echo no | avdmanager create avd -n test -k "${SYSTEM_IMAGE}" -d pixel_6 && \
        chmod -R a+rX ${ANDROID_HOME} /root && chmod a+rwx /root /root/.android

    ENV PATH=${PATH}:${ANDROID_HOME}/emulator

#!/bin/sh
# Opens a document in the app's document editor on a headless emulator and saves a
# screenshot and the log in build/work/emulator/. Runs in the emulator image from the
# AndroidEditors root, as root, with KVM:
#
#   docker run --rm --device /dev/kvm -v "$PWD":/src -w /src \
#       ghcr.io/euro-office/android-emulator build/scripts/emulator-test.sh build/out/<x86_64 apk> [document]
set -eu

APK="$1"
DOCUMENT="${2:-/src/document-templates/sample/sample.docx}"
WAIT_SECONDS="${WAIT_SECONDS:-90}"
OUT=/src/build/work/emulator
PACKAGE=com.onlyoffice.documents
FILES_DIR=/data/data/$PACKAGE/files
mkdir -p "$OUT"

emulator -avd test -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect \
    > "$OUT/emulator.log" 2>&1 &

adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done
# Root lets the shell start the app's non-exported editor activities
adb root > /dev/null
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done

adb install -r "$APK" > /dev/null
# Into the app's own storage, owned by the app
NAME=$(basename "$DOCUMENT")
adb push "$DOCUMENT" "/data/local/tmp/$NAME" > /dev/null
APP_UID=$(adb shell stat -c %u "/data/data/$PACKAGE" | tr -d '\r')
adb shell "mkdir -p $FILES_DIR && cp /data/local/tmp/$NAME $FILES_DIR/ && chown -R $APP_UID:$APP_UID $FILES_DIR && restorecon -R $FILES_DIR"

adb logcat -c
case "$NAME" in
    *.pptx|*.ppsx|*.potx|*.odp|*.otp|*.ppt) ACTIVITY=lib.editors.gslides.ui.activities.SlidesActivity ;;
    *.xlsx|*.xltx|*.ods|*.ots|*.csv|*.xls) ACTIVITY=lib.editors.gcells.ui.activities.CellsActivity ;;
    *.pdf|*.xps|*.djvu) ACTIVITY=lib.editors.gbase.ui.activities.PdfActivity ;;
    *) ACTIVITY=lib.editors.gdocs.ui.activities.DocsActivity ;;
esac
adb shell am start -n "$PACKAGE/$ACTIVITY" -d "file://$FILES_DIR/$NAME" > /dev/null

# Wait until the first page is rendered (or the app gave up)
elapsed=0
while [ "$elapsed" -lt "$WAIT_SECONDS" ]; do
    if adb logcat -d -s EditorViewer | grep -q "render page 1"; then sleep 3; break; fi
    if adb logcat -d | grep -q -E "FATAL EXCEPTION|Fatal signal"; then break; fi
    sleep 2
    elapsed=$((elapsed + 2))
done

adb exec-out screencap -p > "$OUT/screen.png"
adb logcat -d > "$OUT/logcat.txt"
adb logcat -d -s EditorViewer js DEBUG AndroidRuntime | tail -40
# KEEP=1 leaves the emulator running, e.g. for "docker exec <container> adb shell ..."
if [ "${KEEP:-0}" = "1" ]; then
    sleep infinity
fi
adb emu kill > /dev/null 2>&1 || true

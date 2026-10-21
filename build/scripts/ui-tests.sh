#!/bin/sh
# UI tests of the editors on a headless emulator: each test in build/tests/ui opens a document in
# the app, acts on it through adb and checks the screen and the saved file (see build/tests/ui/lib.sh).
# Runs in the emulator image from the AndroidEditors root, as root, with KVM:
#
#   docker run --rm --device /dev/kvm -v "$PWD":/src -w /src \
#       ghcr.io/euro-office/android-emulator build/scripts/ui-tests.sh build/out/<x86_64 apk> [test ...]
#
# With BOOTED=1 it uses an emulator that is already running (e.g. one kept by emulator-test.sh).
# Screenshots, saved files and the log go to build/work/ui-tests.
set -u

APK="$1"
shift
TESTS_DIR=/src/build/tests/ui
OUT=/src/build/work/ui-tests
mkdir -p "$OUT"
[ $# -gt 0 ] || set -- "$TESTS_DIR"/*.sh

if [ "${BOOTED:-0}" != "1" ]; then
    emulator -avd test -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect \
        > "$OUT/emulator.log" 2>&1 &
    adb wait-for-device
    until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done
fi
# Root lets the shell start the app's non-exported editor activities
adb root > /dev/null
adb wait-for-device
until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = "1" ]; do sleep 2; done
adb install -r "$APK" > /dev/null

. "$TESTS_DIR/lib.sh"

run_test() {
    FAILED=0
    . "$1"
    crashed && fail "the app crashed"
}

passed=0
failed=0
for test in "$@"; do
    name=$(basename "$test" .sh)
    [ "$name" = lib ] && continue
    echo "$name"
    run_test "$test"
    adb logcat -d > "$OUT/$name.log"
    if [ "$FAILED" -eq 0 ]; then
        echo "  ok"
        passed=$((passed + 1))
    else
        shot "$name-failed"
        failed=$((failed + 1))
    fi
done
adb shell am force-stop "$PACKAGE"

echo "$passed passed, $failed failed"
[ "${BOOTED:-0}" = "1" ] || adb emu kill > /dev/null 2>&1 || true
[ "$failed" -eq 0 ]

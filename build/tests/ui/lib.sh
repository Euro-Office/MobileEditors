# Helpers of the UI tests (sourced by ui-tests.sh for each test). A test opens a document, acts
# on the editor through adb and checks the screen (uiautomator) and the saved file; "fail" marks
# it failed. Screenshots go to $OUT.

PACKAGE=com.onlyoffice.documents
FILES_DIR=/data/data/$PACKAGE/files

fail() {
    echo "  failed: $*"
    FAILED=1
}

# Copies a document into the app's storage and opens it in its editor; waits until a page is drawn
open_document() {
    NAME=$(basename "$1")
    adb push "$1" "/data/local/tmp/$NAME" > /dev/null 2>&1
    APP_UID=$(adb shell stat -c %u "/data/data/$PACKAGE" | tr -d '\r')
    adb shell am force-stop $PACKAGE
    # Nothing left over in front (dialogs of other apps)
    adb shell input keyevent HOME
    adb shell "mkdir -p $FILES_DIR && cp /data/local/tmp/$NAME $FILES_DIR/ && chown -R $APP_UID:$APP_UID $FILES_DIR && restorecon -R $FILES_DIR" > /dev/null 2>&1
    case "$NAME" in
        *.pptx) ACTIVITY=lib.editors.gslides.ui.activities.SlidesActivity ;;
        *.xlsx) ACTIVITY=lib.editors.gcells.ui.activities.CellsActivity ;;
        *.pdf) ACTIVITY=lib.editors.gbase.ui.activities.PdfActivity ;;
        *) ACTIVITY=lib.editors.gdocs.ui.activities.DocsActivity ;;
    esac
    adb logcat -c
    adb shell am start -n "$PACKAGE/$ACTIVITY" -d "file://$FILES_DIR/$NAME" > /dev/null
    for _ in $(seq 1 45); do
        adb logcat -d -s EditorViewer | grep -q "render page" && { sleep 3; return 0; }
        crashed && return 1
        sleep 2
    done
    fail "$NAME wasn't shown"
    return 1
}

crashed() {
    adb logcat -d | grep -q -E "FATAL EXCEPTION|Fatal signal"
}

# The screen as uiautomator sees it (also the text blocks screen readers get), one node per line
screen() {
    adb shell uiautomator dump /sdcard/ui.xml > /dev/null 2>&1
    adb shell cat /sdcard/ui.xml | tr '>' '\n'
}

# The center of the first node with the attribute (content-desc="Bold", text="OK", ...)
center() {
    screen | grep -F "$1" | head -1 | grep -o 'bounds="\[[0-9]*,[0-9]*\]\[[0-9]*,[0-9]*\]"' |
        tr -d 'bounds="[' | tr ']' ' ' | awk -F'[ ,]' '{print int(($1+$3)/2), int(($2+$4)/2)}'
}

tap_node() {
    node=$1
    set -- $(center "$node")
    [ $# -eq 2 ] && adb shell input tap "$1" "$2" || fail "not on screen: $node"
}

tap_desc() { tap_node "content-desc=\"$1\""; }
tap_text() { tap_node "text=\"$1\""; }

# A toolbar button, scrolling the toolbar step by step to it if needed
tap_tool() {
    tool=$1
    set -- $(center 'content-desc="Find"')
    for _ in 1 2 3 4 5 6; do
        [ -n "$(center "content-desc=\"$tool\"")" ] && break
        [ $# -eq 2 ] && adb shell input swipe 700 "$2" 400 "$2" 400
        sleep 1
    done
    tap_desc "$tool"
}

# The node is on the screen (shown, or read by screen readers)
expect() {
    screen | grep -q -F "$1" || fail "expected on screen: $1"
}

shot() {
    adb exec-out screencap -p > "$OUT/$1.png"
}

# An editor is in front
editor_shown() {
    adb shell dumpsys activity activities | grep -E "topResumedActivity|mResumedActivity" | grep -q "lib.editors"
}

# Leaves the editor (back, maybe after closing the keyboard), which saves the document; then
# copies it to $OUT/<name>
close_and_pull() {
    for _ in 1 2 3; do
        adb shell input keyevent BACK
        sleep 3
        editor_shown || break
    done
    editor_shown && fail "the editor didn't close"
    adb pull "$FILES_DIR/$NAME" "$OUT/$NAME" > /dev/null 2>&1 || fail "can't read the saved $NAME"
}

# The saved Office file (in $OUT) has the text in one of its XML parts
file_contains() {
    unzip -p "$OUT/$NAME" '*.xml' 2>/dev/null | grep -q -F "$1" || fail "$NAME doesn't contain \"$1\""
}

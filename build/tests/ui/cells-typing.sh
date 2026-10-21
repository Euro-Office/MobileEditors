# A value typed on the sheet goes into the active cell and is saved
open_document /src/document-templates/sample/sample.xlsx || return
expect 'content-desc="Format"'
adb shell input keycombination KEYCODE_CTRL_LEFT KEYCODE_MOVE_HOME
adb shell input text "UiTestCell"
adb shell input keyevent ENTER
sleep 2
shot cells-typing
close_and_pull
file_contains "UiTestCell"

# Text typed into a document is saved
open_document /src/document-templates/sample/sample.docx || return
expect 'content-desc="Bold"'
# Into the body text, then type at the start of the document
adb shell input tap 540 1300
sleep 2
adb shell input keycombination KEYCODE_CTRL_LEFT KEYCODE_MOVE_HOME
adb shell input text "UiTestWord"
sleep 2
shot docs-typing
close_and_pull
file_contains "UiTestWord"

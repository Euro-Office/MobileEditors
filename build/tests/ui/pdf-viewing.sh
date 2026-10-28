# PDF pages are shown with thumbnails and their text for screen readers
open_document /src/document-templates/sample/sample.pdf || return
tap_tool "Pages"
sleep 3
shot pdf-viewing
expect 'content-desc="Page 1"'
expect 'content-desc="Page 1 of'

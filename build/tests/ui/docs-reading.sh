# Screen readers get the page and its paragraphs
open_document /src/document-templates/sample/sample.docx || return
screen > /dev/null
sleep 2
expect 'content-desc="Page 1 of'
expect 'text="Text Editors"'

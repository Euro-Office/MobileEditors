# A slide added in the strip is saved
open_document /src/document-templates/sample/sample.pptx || return
expect 'content-desc="Slide 1"'
before=$(unzip -l /src/document-templates/sample/sample.pptx | grep -c "ppt/slides/slide[0-9]*.xml")
# At the end of the slide strip, behind the thumbnails
tap_in_row 'content-desc="Slide 1"' "New slide"
sleep 3
# It asks for the new slide's layout
tap_desc "Title Slide"
sleep 3
shot slides-adding
close_and_pull
after=$(unzip -l "$OUT/$NAME" | grep -c "ppt/slides/slide[0-9]*.xml")
[ "$after" -gt "$before" ] || fail "slides: $before before, $after after adding one"

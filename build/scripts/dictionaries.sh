#!/bin/sh
# Collects the editors' spell checking dictionaries in build/out/dictionaries (read by
# editors-android's libeditors):
# - the English dictionary, which comes with the app
# - index.json: the dictionaries submodule commit this checkout pins, where to download the
#   other dictionaries from at that commit, and the languages (LCIDs) of each dictionary
#
# Runs where the MobileEditors checkout is (needs git), e.g.: build/scripts/dictionaries.sh
set -eu

ROOT="${ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
SOURCE="$ROOT/dictionaries"
OUT_DIR="$ROOT/build/out/dictionaries"

# The commit recorded in MobileEditors (not the submodule's working tree), and its repository
COMMIT=$(git -C "$ROOT" ls-tree HEAD dictionaries | awk '{print $3}')
REPOSITORY=$(git -C "$ROOT" config -f .gitmodules submodule.dictionaries.url | sed 's#\.git$##; s#^git@github.com:#https://github.com/#')
URL=$(echo "$REPOSITORY" | sed 's#^https://github.com/#https://raw.githubusercontent.com/#')
[ -n "$COMMIT" ] || { echo "dictionaries submodule not found" >&2; exit 1; }

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/en_US"
cp "$SOURCE/en_US/en_US.aff" "$SOURCE/en_US/en_US.dic" "$OUT_DIR/en_US/"

{
    printf '{"commit": "%s", "url": "%s", "languages": {' "$COMMIT" "$URL"
    first=1
    for dir in "$SOURCE"/*/; do
        name=$(basename "$dir")
        [ -f "$dir/$name.dic" ] && [ -f "$dir/$name.json" ] || continue
        codes=$(sed 's/.*\[\(.*\)\].*/\1/' "$dir/$name.json" | tr -d ' \n\r')
        [ $first -eq 1 ] || printf ', '
        printf '"%s": [%s]' "$name" "$codes"
        first=0
    done
    printf '}}\n'
} > "$OUT_DIR/index.json"

echo "dictionaries at $COMMIT ($URL):"
find "$OUT_DIR" -type f | sed "s#$OUT_DIR/##"

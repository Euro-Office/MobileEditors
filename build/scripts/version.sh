#!/usr/bin/env bash
# Prints the app version from VERSION as VERSION_NAME=… and VERSION_CODE=… lines (for
# $GITHUB_ENV or eval). The version code must only grow: MMmmppSS with the stage SS
# alpha.N -> N, beta.N -> 30+N, rc.N -> 60+N, the final release 99 (N 1-29),
# e.g. 0.1.0-alpha.1 -> 10001, 1.2.3 -> 1020399.
set -euo pipefail

name=$(tr -d '[:space:]' <"$(dirname "$0")/../../VERSION")
[[ $name =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-(alpha|beta|rc)\.([0-9]+))?$ ]] ||
  { echo "invalid VERSION: $name (expected e.g. 0.1.0-alpha.1 or 1.0.0)" >&2; exit 1; }
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}
stage=${BASH_REMATCH[5]} n=${BASH_REMATCH[6]}
((minor < 100 && patch < 100)) || { echo "minor and patch must be below 100: $name" >&2; exit 1; }
case $stage in
  "") s=99 ;;
  alpha) s=$n ;;
  beta) s=$((30 + n)) ;;
  rc) s=$((60 + n)) ;;
esac
[ -z "$stage" ] || ((n >= 1 && n <= 29)) || { echo "prerelease number must be 1-29: $name" >&2; exit 1; }
echo "VERSION_NAME=$name"
echo "VERSION_CODE=$((((major * 100 + minor) * 100 + patch) * 100 + s))"

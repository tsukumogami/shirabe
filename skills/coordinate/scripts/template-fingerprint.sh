#!/usr/bin/env bash
# template-fingerprint.sh -- print the structural fingerprint of a compiled
# koto template: the sha256 of template-fingerprint.jq's output, with no
# trailing newline. coord-log.sh (a run's fingerprint at resume and import) and
# scripts/check-template-compat.sh (the one CI records in the compat table)
# both call this, so the two can't hash the structure differently.
#
# Usage: template-fingerprint.sh <compiled.json>
#
# Exit 0 printed; 2 the compiled template can't be read; 64 usage.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 1 ] || { echo "usage: template-fingerprint.sh <compiled.json>" >&2; exit 64; }
STRUCTURE=$(jq -S -c -f "$HERE/template-fingerprint.jq" "$1") || exit 2
if command -v sha256sum >/dev/null 2>&1; then H=$(printf '%s' "$STRUCTURE" | sha256sum) || exit 2
else H=$(printf '%s' "$STRUCTURE" | shasum -a 256) || exit 2; fi
printf '%s\n' "${H%% *}"

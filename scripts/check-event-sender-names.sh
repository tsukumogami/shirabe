#!/usr/bin/env bash
# check-event-sender-names.sh -- only scripts/emit-event.sh may name the shared
# event sender.
#
# The helper is the one place that checks the off switch, the date before
# which nothing is sent and the sender's discovery rules
# (docs/designs/DESIGN-fleet-cost-emit.md). A second file that ran the sender
# itself would skip all three, so this fails when any tracked code file other
# than the helper and its test holds the sender's file name or the tail of its
# off-switch variable's name, anywhere in it, in any case. Matching the tail
# also catches a name assembled from parts around it.
#
# Code is everything tracked except documentation: Markdown is skipped, except
# under a koto-templates directory, where a template's states, gates and
# actions are code. docs/ is skipped whole.
#
# The two names are built from parts below, so this file doesn't hold them.
#
# Usage: check-event-sender-names.sh [<repo root>]
# Exit codes: 0 no other file names the sender; 1 one does (each is listed);
#             2 the file list could not be read.
set -uo pipefail

ROOT=${1:-$(cd "$(dirname "$0")/.." && pwd)}
A=event
B=sink
NAMES="$A-$B
$(printf '%s_%s' "$A" "$B" | tr '[:lower:]' '[:upper:]')"

FILES=$(git -C "$ROOT" ls-files) || { echo "check-event-sender-names: cannot list $ROOT's files" >&2; exit 2; }

found=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
        scripts/emit-event.sh | scripts/emit-event_test.sh) continue ;;
        docs/*) continue ;;
        */koto-templates/*.md | koto-templates/*.md) ;;
        *.md) continue ;;
    esac
    [ -f "$ROOT/$f" ] || continue
    if grep -qiF "$NAMES" -- "$ROOT/$f"; then
        echo "check-event-sender-names: $f names the event sender; only scripts/emit-event.sh may" >&2
        found=1
    fi
done <<EOF
$FILES
EOF

[ "$found" = 0 ] || exit 1
echo "check-event-sender-names: OK"

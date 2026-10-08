#!/usr/bin/env bash
# pause-read_test.sh -- pause-read.sh, the one evaluator of the record's
# pauses.
#
# Covers: a `time` pause in force before its minute and met at it; a `lifted`
# pause in force while its row stands; `merged` and `tag` conditions read
# live, met, unmet and unreadable (an unreadable condition holds); coverage by
# an `all` pause and by a unit's own pause, with the `<tag>: <title>` and
# `<owner/repo>#<n>` forms; a go-ahead letting its unit through an `all`
# pause and through its own pause; rows of other kinds ignored; and a file
# that isn't Standing rows (2).
#
# Runs offline on the gh-board stand-in.
# Usage: bash skills/coordinate/scripts/pause-read_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/pause-read-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
# The conditions are read through the gh-board stand-in.
mkdir -p "$T/bin" "$T/board"
ln -s "$HERE/testdata/gh-board" "$T/bin/gh"
export PATH="$T/bin:$PATH" GH_BOARD_DIR="$T/board"
PR_="$HERE/pause-read.sh"

row() { # row <id> <kind> <on> <until>
    jq -nc --arg s "$1" --arg k "$2" --arg o "$3" --arg u "$4" \
        '{standing: $s, kind: $k, on: $o, until: $u, what: "x", owner: "the human", relayed_by: "", set: "2026-10-01T19:37Z"}'
}
standing() { # standing <row>...: a file of Standing rows
    printf '%s\n' "$@" | jq -s '{standing: .}' > "$T/standing.json"
}
units() { printf '%s\n' "$@" | jq -R . | jq -s . > "$T/units.json"; }
read_() { bash "$PR_" --standing "$T/standing.json" --units "$T/units.json"; }

echo '{"state":"MERGED"}' > "$T/board/prview-30.out"
echo '{"state":"OPEN"}' > "$T/board/prview-31.out"
echo 'gh: Could not resolve to a PullRequest (HTTP 404)' > "$T/board/prview-99.err"; echo 1 > "$T/board/prview-99.rc"
echo '{"ref":"refs/tags/v1.0.0","object":{"sha":"abc"}}' > "$T/board/tag-v1.0.0.out"
echo 'gh: Not Found (HTTP 404)' > "$T/board/tag-v2.0.0.err"; echo 1 > "$T/board/tag-v2.0.0.rc"

echo "== time =="
standing "$(row s1 pause all "time 2026-10-07T14:00Z")"
units "Feature 2" "#12"
OUT=$(BL_NOW=2026-10-07T13:59Z read_)
eq "a time pause is in force before its minute" "in-force s1" "$(printf '%s' "$OUT" | jq -r '"\(.pauses[0].state) \(.all)"')"
eq "  ... and an all pause covers every unit" "s1 s1" "$(printf '%s' "$OUT" | jq -r '[.covers["Feature 2"], .covers["#12"]] | join(" ")')"
OUT=$(BL_NOW=2026-10-07T14:00Z read_)
eq "a time pause is met at its minute" "met null" "$(printf '%s' "$OUT" | jq -r '"\(.pauses[0].state) \(.all)"')"
eq "  ... and covers nothing" "null" "$(printf '%s' "$OUT" | jq -c '.covers["Feature 2"]')"

echo "== lifted and unit scope =="
standing "$(row s2 pause "Feature 9" lifted)" "$(row s3 pause "acme/widgets#12" lifted)"
units "Feature 9: a paused state" "Feature 2" "#12"
OUT=$(read_)
eq "a lifted pause is in force while its row stands" in-force "$(printf '%s' "$OUT" | jq -r '.pauses[0].state')"
eq "a unit's pause covers it in its <tag>: <title> form" s2 "$(printf '%s' "$OUT" | jq -r '.covers["Feature 9: a paused state"]')"
eq "  ... and no other unit" null "$(printf '%s' "$OUT" | jq -c '.covers["Feature 2"]')"
eq "an owner/repo#n pause covers the #n unit" s3 "$(printf '%s' "$OUT" | jq -r '.covers["#12"]')"
eq "no all pause stands" null "$(printf '%s' "$OUT" | jq -c '.all')"

echo "== merged and tag =="
standing "$(row s4 pause "Feature 2" "merged acme/widgets#30")" "$(row s5 pause "Feature 3" "merged acme/widgets#31")" \
    "$(row s6 pause "Feature 4" "tag acme/widgets v1.0.0")" "$(row s7 pause "Feature 5" "tag acme/widgets v2.0.0")" \
    "$(row s8 pause "Feature 6" "merged acme/widgets#99")"
units "Feature 2" "Feature 3" "Feature 4" "Feature 5" "Feature 6"
OUT=$(read_)
eq "merged met, merged unmet, tag met, tag missing, a missing pull request unreadable" \
    "met in-force met in-force unreadable" "$(printf '%s' "$OUT" | jq -r '[.pauses[].state] | join(" ")')"
eq "met pauses cover nothing; an unreadable one holds" "null s5 null s7 s8" \
    "$(printf '%s' "$OUT" | jq -r '[.covers["Feature 2", "Feature 3", "Feature 4", "Feature 5", "Feature 6"]] | map(. // "null") | join(" ")')"

echo "== go-ahead =="
standing "$(row s1 pause all lifted)" "$(row s2 pause "Feature 2" lifted)" "$(row s3 go-ahead "Feature 2" "")" \
    "$(row s4 answer "" "")"
units "Feature 2" "Feature 3"
OUT=$(read_)
eq "a go-ahead lets its unit through an all pause and its own" null "$(printf '%s' "$OUT" | jq -c '.covers["Feature 2"]')"
eq "  ... and no other unit" s1 "$(printf '%s' "$OUT" | jq -r '.covers["Feature 3"]')"
eq "the go-ahead is listed; the answer row is no pause" "s3 2" "$(printf '%s' "$OUT" | jq -r '"\(.go_aheads[0].standing) \(.pauses | length)"')"

echo "== refusals =="
echo '"not rows"' > "$T/bad.json"
bash "$PR_" --standing "$T/bad.json" >/dev/null 2>&1; eq "a file with no Standing rows is refused (2)" 2 $?
bash "$PR_" >/dev/null 2>&1; eq "no --standing is usage (64)" 64 $?

echo
echo "pause-read_test: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

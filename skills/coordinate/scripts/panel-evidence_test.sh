#!/usr/bin/env bash
# panel-evidence_test.sh -- panel-evidence.sh judges a worker's review round
# (the JSON review-round.sh stores): ok with its seats, malformed naming the
# first rule the round breaks, and never a pull request body.
#
# Covers: a well-formed round (a failing seat still ok); each malformed reason
# in its order; stdin and a file argument; a body with a Review panel table
# read as a round (shape) and refused without --round (usage); an unreadable
# file and usage.
#
# Usage: bash skills/coordinate/scripts/panel-evidence_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/panel-evidence-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
PE="$HERE/panel-evidence.sh"
H=0123456789abcdef0123456789abcdef01234567
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
field() { printf '%s' "$1" | jq -r "$2"; }

# round <head> [seat:model:run:verdict...]: a review_round.json.
round() {
    local h=$1 s
    shift
    for s in "$@"; do printf '%s\n' "$s"; done | jq -Rsc --arg h "$h" '
        {reviewed_head: $h,
         seats: [split("\n")[] | select(. != "") | split(":") | {seat: .[0], model: .[1], run: .[2], verdict: .[3]}]}'
}
rparse() { printf '%s' "$1" | bash "$PE" --round -; }
rreason() { field "$(rparse "$1")" '"\(.status) \(.reason) \(.row)"'; }
S1=architect:sonnet:agent-a1:pass S2=maintainer:sonnet:agent-a2:pass S3=pragmatic:sonnet:agent-a3:pass

echo "== ok =="
OUT=$(rparse "$(round "$H" "$S1" "$S2" "$S3")")
eq "a round of three seats parses ok" ok "$(field "$OUT" .status)"
eq "  ... with its reviewed head" "$H" "$(field "$OUT" .reviewed_head)"
eq "  ... three seats, three passes" "3 3" "$(field "$OUT" '"\(.count) \(.passes)"')"
eq "  ... seats in order" "architect maintainer pragmatic" "$(field "$OUT" '[.seats[].seat] | join(" ")')"
eq "  ... each with its model, run and verdict" "sonnet agent-a2 pass" "$(field "$OUT" '.seats[1] | "\(.model) \(.run) \(.verdict)"')"
OUT=$(rparse "$(round "$H" "$S1" "$S2" "${S3/pass/fail}")")
eq "a failing seat is still a well-formed round" "ok 2" "$(field "$OUT" '"\(.status) \(.passes)"')"

echo "== malformed, by rule =="
eq "not JSON: shape" "malformed shape 0" "$(rreason "not json")"
eq "an array: shape" "malformed shape 0" "$(rreason '[]')"
eq "no reviewed_head: shape" "malformed shape 0" "$(rreason '{"seats":[]}')"
eq "seats not an array: shape" "malformed shape 0" "$(rreason "{\"reviewed_head\":\"$H\",\"seats\":{}}")"
eq "a seat field not a string: shape" "malformed shape 0" "$(rreason "{\"reviewed_head\":\"$H\",\"seats\":[{\"seat\":\"a\",\"model\":\"m\",\"run\":\"agent-1\",\"verdict\":true}]}")"
eq "no seats: no-rows" "malformed no-rows 0" "$(rreason "$(round "$H")")"
eq "a control character: control" "malformed control 1" "$(rreason "$(round "$H" "$(printf 'architect:sonnet:agent-a1:pass\001')")")"
eq "an empty model: cells" "malformed cells 2" "$(rreason "$(round "$H" "$S1" maintainer::agent-a2:pass)")"
eq "a Run too short: run" "malformed run 1" "$(rreason "$(round "$H" architect:sonnet:a1:pass)")"
eq "a Run with a space: run" "malformed run 1" "$(rreason "$(round "$H" 'architect:sonnet:the same agent:pass')")"
eq "a verdict outside pass and fail: verdict" "malformed verdict 1" "$(rreason "$(round "$H" architect:sonnet:agent-a1:approve)")"
eq "a short reviewed head: head" "malformed head 1" "$(rreason "$(round "${H%0*}" "$S1")")"
eq "an uppercase reviewed head: head" "malformed head 1" "$(rreason "$(round ABCDEF0123456789ABCDEF0123456789ABCDEF01 "$S1")")"
eq "seat rules run before round rules" "malformed verdict 2" "$(rreason "$(round "$H" "$S1" architect:sonnet:agent-a1:ok)")"
eq "one Seat twice, without case: seat-repeated" "malformed seat-repeated 0" "$(rreason "$(round "$H" "$S1" Architect:sonnet:agent-a2:pass "$S3")")"
eq "one Run twice: run-repeated (the niwa#346 case)" "malformed run-repeated 0" "$(rreason "$(round "$H" "$S1" maintainer:sonnet:agent-a1:pass "$S3")")"

echo "== a body is not a round =="
TABLE=$(printf 'Part one.\n\n---\n\n## Review panel\n\n| Seat | Model | Run | Verdict | Reviewed head |\n|---|---|---|---|---|\n| architect | sonnet | agent-a1 | pass | %s |\n| maintainer | sonnet | agent-a2 | pass | %s |\n| pragmatic | sonnet | agent-a3 | pass | %s |\n' "$H" "$H" "$H")
eq "a body with a well-formed Review panel table, given as a round: shape" "malformed shape 0" "$(rreason "$TABLE")"
printf '%s\n' "$TABLE" > "$T/body"
bash "$PE" "$T/body" >/dev/null 2>&1; eq "a body without --round: exit 64, nothing parsed" 64 $?
bash "$PE" - < "$T/body" >/dev/null 2>&1; eq "a body on stdin without --round: exit 64" 64 $?

echo "== input =="
round "$H" "$S1" > "$T/round.json"
eq "--round reads a file argument" ok "$(field "$(bash "$PE" --round "$T/round.json")" .status)"
bash "$PE" --round "$T/missing" >/dev/null 2>&1; eq "--round on an unreadable file: exit 2" 2 $?
bash "$PE" --round >/dev/null 2>&1; eq "--round with no file: exit 64" 64 $?
bash "$PE" --bogus "$T/round.json" >/dev/null 2>&1; eq "another flag: exit 64" 64 $?
bash "$PE" --round --round "$T/round.json" >/dev/null 2>&1; eq "--round twice: exit 64" 64 $?
bash "$PE" >/dev/null 2>&1; eq "no argument: exit 64" 64 $?

echo
echo "panel-evidence: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

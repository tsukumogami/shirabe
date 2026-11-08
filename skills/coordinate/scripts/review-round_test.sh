#!/usr/bin/env bash
# review-round_test.sh -- review-round.sh records a worker's review round in
# its own session: a well-formed round is stored as review_round.json, a
# malformed one is refused with its rule and nothing is written, and a koto
# that can't store it is exit 2.
#
# Covers: a round stored and replaced; a failing seat still stored; a
# malformed round refused; stdin; an unreadable file; a failed add; usage.
#
# Usage: bash skills/coordinate/scripts/review-round_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }
T=$(mktemp -d "${TMPDIR:-/tmp}/review-round-test.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
RR="$HERE/review-round.sh"
export KOTO_STORE="$T/store" PATH="$HERE/testdata:$PATH"
mkdir -p "$KOTO_STORE"
H=0123456789abcdef0123456789abcdef01234567
G=89abcdef0123456789abcdef0123456789abcdef
PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

round() {
    jq -nc --arg h "$1" --arg v "${2:-pass}" '{reviewed_head: $h, seats: [
        {seat: "architect", model: "sonnet", run: "agent-a1", verdict: "pass"},
        {seat: "maintainer", model: "sonnet", run: "agent-a2", verdict: "pass"},
        {seat: "adversarial", model: "opus", run: "agent-a3", verdict: $v}]}'
}
stored() { cat "$KOTO_STORE/context/issue_7/review_round.json" 2>/dev/null; }

round "$H" > "$T/r1"
OUT=$(bash "$RR" record --session issue_7 "$T/r1" 2>&1); RC=$?
eq "a well-formed round: exit 0" 0 "$RC"
eq "  ... says what it recorded" "recorded 3 seats at $H" "$OUT"
eq "  ... stored as review_round.json, compacted" "$(jq -c . "$T/r1")" "$(stored)"

round "$G" > "$T/r2"
bash "$RR" record --session issue_7 "$T/r2" >/dev/null 2>&1
eq "a later round replaces the earlier one" "$G" "$(stored | jq -r .reviewed_head)"

round "$H" fail | bash "$RR" record --session issue_7 - >/dev/null 2>&1; RC=$?
eq "a round with a failing seat, from stdin: stored" "0 fail" "$RC $(stored | jq -r '.seats[2].verdict')"

jq -nc --arg h "$H" '{reviewed_head: $h, seats: [
    {seat: "architect", model: "sonnet", run: "agent-a1", verdict: "pass"},
    {seat: "maintainer", model: "sonnet", run: "agent-a1", verdict: "pass"}]}' > "$T/dup"
BEFORE=$(stored)
ERR=$(bash "$RR" record --session issue_7 "$T/dup" 2>&1 >/dev/null); RC=$?
eq "a repeated Run: exit 1" 1 "$RC"
eq "  ... naming the rule" "review-round: malformed run-repeated row 0" "$ERR"
eq "  ... and nothing is written" "$BEFORE" "$(stored)"

printf 'not json' | bash "$RR" record --session issue_7 - >/dev/null 2>&1
eq "not JSON: exit 1 (shape)" 1 $?

bash "$RR" record --session issue_7 "$T/missing" >/dev/null 2>&1
eq "an unreadable file: exit 2" 2 $?

KOTO_FAIL_ADD=review_round.json bash "$RR" record --session issue_7 "$T/r1" >/dev/null 2>&1
eq "a failed context add: exit 2" 2 $?

bash "$RR" record --session 'bad name' "$T/r1" >/dev/null 2>&1; eq "a session name outside the pattern: exit 64" 64 $?
bash "$RR" record "$T/r1" >/dev/null 2>&1; eq "no --session: exit 64" 64 $?
bash "$RR" store --session issue_7 "$T/r1" >/dev/null 2>&1; eq "another verb: exit 64" 64 $?
bash "$RR" >/dev/null 2>&1; eq "no argument: exit 64" 64 $?

# The round's review telemetry: once stored, the round goes to koto as a code
# review round (`koto review record <session> code-round`), numbered from the
# session's review_round_count, best effort.
review_calls() { grep "^review record $1 " "$KOTO_STORE/calls" 2>/dev/null; }
kept() { cat "$KOTO_STORE/review/$1/round-$2.json" 2>/dev/null; }
count() { cat "$KOTO_STORE/context/$1/review_round_count" 2>/dev/null; }
OUT=$(bash "$RR" record --session issue_8 "$T/r1" 2> "$T/err"); RC=$?
eq "telemetry: a stored round is sent as code-round 1 at its reviewed head" \
    "review record issue_8 code-round --round 1 --head $H --file" "$(review_calls issue_8 | sed 's/ --file .*/ --file/')"
eq "telemetry:   ... its seats as seat, model and verdict" \
    "$(jq -c '[.seats[] | {seat, model, verdict}]' "$T/r1")" "$(kept issue_8 1 | jq -c .)"
eq "telemetry:   ... the session's round count is 1" 1 "$(count issue_8)"
eq "telemetry:   ... exit 0 and the same line" "0 recorded 3 seats at $H" "$RC $OUT"
eq "telemetry:   ... nothing on stderr" "" "$(cat "$T/err")"
bash "$RR" record --session issue_8 "$T/r2" >/dev/null 2>&1
eq "telemetry: the next round is round 2" "2 2" "$(review_calls issue_8 | tail -n 1 | sed 's/.*--round \([0-9]*\) .*/\1/') $(count issue_8)"

OUT=$(KOTO_FAIL_REVIEW=1 bash "$RR" record --session issue_8 "$T/r1" 2> "$T/err"); RC=$?
eq "telemetry: a refused call: exit 0 and the same line" "0 recorded 3 seats at $H" "$RC $OUT"
eq "telemetry:   ... the round still stored" "$(jq -c . "$T/r1")" "$(cat "$KOTO_STORE/context/issue_8/review_round.json")"
eq "telemetry:   ... one notice on stderr" "1 review-round:" "$(wc -l < "$T/err" | tr -d ' ') $(cut -d' ' -f1 "$T/err")"
eq "telemetry:   ... and the round count unchanged" 2 "$(count issue_8)"

mkdir -p "$KOTO_STORE/context/issue_9"
printf 'junk\n' > "$KOTO_STORE/context/issue_9/review_round_count"
bash "$RR" record --session issue_9 "$T/r1" >/dev/null 2>&1
eq "telemetry: a round count that isn't a number counts as none: round 1" "1 1" \
    "$(review_calls issue_9 | sed 's/.*--round \([0-9]*\) .*/\1/') $(count issue_9)"

OUT=$(KOTO_FAIL_ADD=review_round_count bash "$RR" record --session issue_10 "$T/r1" 2> "$T/err"); RC=$?
eq "telemetry: a failed round count write: exit 0 and the same line" "0 recorded 3 seats at $H" "$RC $OUT"
eq "telemetry:   ... the call was made" 1 "$(review_calls issue_10 | wc -l | tr -d ' ')"
eq "telemetry:   ... one notice on stderr" "1 review-round:" "$(wc -l < "$T/err" | tr -d ' ') $(cut -d' ' -f1 "$T/err")"

bash "$RR" record --session issue_11 "$T/dup" >/dev/null 2>&1
eq "telemetry: a malformed round is never sent" "" "$(review_calls issue_11)"

OUT=$(KOTO_FAIL_REVIEW=session_terminal bash "$RR" record --session issue_12 "$T/r1" 2>&1); RC=$?
eq "telemetry: a finished session koto takes no review event on: exit 0, the line alone" \
    "0 recorded 3 seats at $H" "$RC $OUT"
eq "telemetry:   ... the round still stored and no round count" "$(jq -c . "$T/r1") " \
    "$(cat "$KOTO_STORE/context/issue_12/review_round.json") $(count issue_12)"

echo
echo "review-round: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

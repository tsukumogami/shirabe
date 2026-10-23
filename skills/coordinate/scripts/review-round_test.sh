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

echo
echo "review-round: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

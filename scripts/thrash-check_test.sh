#!/usr/bin/env bash
# thrash-check_test.sh -- scripts/thrash-check.sh against reports in
# context-size.sh's format, on stdin and from a file, and once against a
# report context-size.sh printed for a synthetic transcript.
#
# Covers: three boundaries within 30 turns, at exactly 30 and at 31; a later
# run of three among spread ones; fewer than three boundaries; context_tokens
# above, equal to and under hard_stop, and with no hard_stop; both reasons at
# once; every refusal (not key: value, unknown, repeated and missing keys,
# non-integer figures, a count that differs from the turns, turns out of
# order, a hard_stop without an integer window or none with one, a report
# over the size limit, a missing file); and that it never opens a transcript.
#
# Usage: bash scripts/thrash-check_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/thrash-check.sh"
READER="$HERE/context-size.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/thrash-check-test.XXXXXX") || exit 1
trap 'case "$T" in */thrash-check-test.*) rm -rf "$T" ;; esac' EXIT
T=$(cd "$T" && pwd -P) || exit 1
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "$2 :: rc=${rc-} out=${OUT-}"; fi; }

# report <context_tokens> <boundaries> <boundary_turns> <window> [hard_stop]
report() {
    printf 'context_tokens: %s\nboundaries: %s\nboundary_turns: %s\nwindow: %s\n' "$1" "$2" "$3" "$4"
    if [ -n "${5-}" ]; then
        printf 'hard_stop: %s\n' "$5"
    fi
}
run_stdin() { bash "$SCRIPT" <<<"$1"; }

echo "== three boundaries within 30 turns =="
OUT=$(run_stdin "$(report 100000 3 "361 365 380" 280000 350000)" 2>&1); rc=$?
check "exit 1" '[ "$rc" -eq 1 ]'
check "status: cant_continue" 'grep -qx "status: cant_continue" <<<"$OUT"'
check "reason names the three turns" 'grep -qx "reason: thrash 361 365 380" <<<"$OUT"'
check "no hard_stop reason" '! grep -q "reason: hard_stop" <<<"$OUT"'
OUT=$(run_stdin "$(report 100000 3 "100 110 130" 280000 350000)" 2>&1); rc=$?
check "a span of exactly 30 is thrash" '[ "$rc" -eq 1 ] && grep -qx "reason: thrash 100 110 130" <<<"$OUT"'
OUT=$(run_stdin "$(report 100000 3 "100 110 131" 280000 350000)" 2>&1); rc=$?
check "a span of 31 continues" '[ "$rc" -eq 0 ] && grep -qx "status: continue" <<<"$OUT"'
OUT=$(run_stdin "$(report 100000 3 "7 7 7" unset)" 2>&1); rc=$?
check "three at one turn is thrash" '[ "$rc" -eq 1 ] && grep -qx "reason: thrash 7 7 7" <<<"$OUT"'

echo "== spread boundaries, and a run of three among them =="
OUT=$(run_stdin "$(report 100000 3 "361 742 1100" 280000 350000)" 2>&1); rc=$?
check "spread wider than 30: exit 0" '[ "$rc" -eq 0 ]'
check "status: continue and nothing else" '[ "$OUT" = "status: continue" ]'
OUT=$(run_stdin "$(report 100000 6 "50 400 900 905 912 2000" 280000 350000)" 2>&1); rc=$?
check "a later run of three among spread ones is found and named" '[ "$rc" -eq 1 ] && grep -qx "reason: thrash 900 905 912" <<<"$OUT"'
OUT=$(run_stdin "$(report 100000 2 "5 6" 280000 350000)" 2>&1); rc=$?
check "two boundaries close together continue" '[ "$rc" -eq 0 ]'
OUT=$(run_stdin "$(report 100000 0 none 280000 350000)" 2>&1); rc=$?
check "no boundaries continue" '[ "$rc" -eq 0 ]'

echo "== the hard stop =="
OUT=$(run_stdin "$(report 350001 1 "400" 280000 350000)" 2>&1); rc=$?
check "above hard_stop: exit 1" '[ "$rc" -eq 1 ]'
check "reason names both figures" 'grep -qx "reason: hard_stop 350001 350000" <<<"$OUT"'
OUT=$(run_stdin "$(report 350000 1 "400" 280000 350000)" 2>&1); rc=$?
check "equal to hard_stop continues" '[ "$rc" -eq 0 ]'
OUT=$(run_stdin "$(report 900000 1 "400" unset)" 2>&1); rc=$?
check "no hard_stop line: size alone never stops it" '[ "$rc" -eq 0 ]'
OUT=$(run_stdin "$(report 900000 1 "400" invalid)" 2>&1); rc=$?
check "an invalid window: size alone never stops it" '[ "$rc" -eq 0 ]'
OUT=$(run_stdin "$(report 400000 3 "1 2 3" 280000 350000)" 2>&1); rc=$?
check "both reasons print" '[ "$rc" -eq 1 ] && grep -qx "reason: thrash 1 2 3" <<<"$OUT" && grep -qx "reason: hard_stop 400000 350000" <<<"$OUT"'

echo "== the report from a file, from -, in any order, with blank lines =="
report 350001 1 "400" 280000 350000 >"$T/r.txt"
OUT=$(bash "$SCRIPT" "$T/r.txt" 2>&1); rc=$?
check "file: exit 1 with the reason" '[ "$rc" -eq 1 ] && grep -qx "reason: hard_stop 350001 350000" <<<"$OUT"'
OUT=$(bash "$SCRIPT" - <"$T/r.txt" 2>&1); rc=$?
check "dash reads stdin" '[ "$rc" -eq 1 ]'
OUT=$(run_stdin "$(printf 'hard_stop: 350000\n\nwindow: 280000\nboundary_turns: 4\nboundaries: 1\n\ncontext_tokens: 10\n')" 2>&1); rc=$?
check "any order and blank lines" '[ "$rc" -eq 0 ]'
printf 'context_tokens: 10\nboundaries: 0\nboundary_turns: none\nwindow: unset' >"$T/nonl.txt"
OUT=$(bash "$SCRIPT" "$T/nonl.txt" 2>&1); rc=$?
check "a last line with no newline is read" '[ "$rc" -eq 0 ]'

echo "== a report context-size.sh printed =="
TR="$T/t.jsonl"
for i in 1 2 3; do
    printf '{"type":"assistant","isSidechain":false,"message":{"id":"m%s","model":"x","usage":{"input_tokens":1,"cache_read_input_tokens":100,"cache_creation_input_tokens":0}}}\n' "$i"
    printf '{"type":"system","subtype":"compact_boundary","isSidechain":false}\n'
done >"$TR"
printf '{"type":"assistant","isSidechain":false,"message":{"id":"m4","model":"x","usage":{"input_tokens":1,"cache_read_input_tokens":100,"cache_creation_input_tokens":0}}}\n' >>"$TR"
REP=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=280000 bash "$READER" "$TR" 2>&1)
OUT=$(run_stdin "$REP" 2>&1); rc=$?
check "the reader's own report parses and shows thrash" '[ "$rc" -eq 1 ] && grep -qx "reason: thrash 1 2 3" <<<"$OUT"'

echo "== refusals: exit 2, the line named, no status =="
refused() {
    OUT=$(run_stdin "$2" 2>&1); rc=$?
    check "$1" '[ "$rc" -eq 2 ] && ! grep -q "^status:" <<<"$OUT"'
}
refused "not key: value" "$(report 1 0 none unset; printf 'garbage\n')"
refused "no space after the colon" "$(printf 'context_tokens:1\nboundaries: 0\nboundary_turns: none\nwindow: unset\n')"
refused "unknown key" "$(report 1 0 none unset; printf 'extra: 1\n')"
refused "repeated key" "$(report 1 0 none unset; printf 'boundaries: 0\n')"
refused "missing context_tokens" "$(printf 'boundaries: 0\nboundary_turns: none\nwindow: unset\n')"
refused "missing window" "$(printf 'context_tokens: 1\nboundaries: 0\nboundary_turns: none\n')"
refused "non-integer context_tokens" "$(report 1.5 0 none unset)"
refused "negative context_tokens" "$(report -1 0 none unset)"
refused "leading zero" "$(report 010 0 none unset)"
refused "sixteen digits" "$(report 1234567890123456 0 none unset)"
refused "expression in a figure" "$(report '1+1' 0 none unset)"
refused "command text in a figure" "$(report '$(touch x)' 0 none unset)"
refused "trailing carriage return" "$(printf 'context_tokens: 1\r\nboundaries: 0\nboundary_turns: none\nwindow: unset\n')"
refused "non-integer turn" "$(report 1 2 "4 x" unset)"
refused "two spaces between turns" "$(report 1 2 "4  5" unset)"
refused "count differs from the turns" "$(report 1 3 "4 5" unset)"
refused "turns out of order" "$(report 1 3 "4 9 5" unset)"
refused "bad window word" "$(report 1 0 none huge)"
refused "hard_stop with no integer window" "$(report 1 0 none unset 350000)"
refused "integer window with no hard_stop" "$(report 1 0 none 280000)"
OUT=$(run_stdin "$(report 1 0 none unset; printf 'secret-%s: 1\n' VALUE)" 2>&1)
check "the refused line's text is not echoed" '! grep -q secret <<<"$OUT"'
check "the refusal names the line number" 'grep -q "line 5" <<<"$OUT"'
BIG=$(head -c 70000 /dev/zero | tr '\0' 'a')
refused "a report over 65,536 bytes" "$BIG"
refused "a leading zero in boundary_turns" "$(report 1 3 "010 020 045" unset)"
refused "no boundary_turns line" "$(printf 'context_tokens: 1\nboundaries: 0\nwindow: unset\n')"
# A report padded with newlines to past the cap, with a repeated key and a
# hard_stop beyond it: command substitution would drop the padding.
{
    report 400000 0 none 280000 350000
    head -c 65600 /dev/zero | tr '\0' '\n'
    printf 'boundaries: 0\n'
} >"$T/padded.txt"
OUT=$(bash "$SCRIPT" "$T/padded.txt" 2>&1); rc=$?
check "a newline-padded report over the cap exits 2" '[ "$rc" -eq 2 ] && grep -q "over 65536 bytes" <<<"$OUT"'
check "and prints no status" '! grep -q "^status:" <<<"$OUT"'
OUT=$(bash "$SCRIPT" - <"$T/padded.txt" 2>&1); rc=$?
check "the same on stdin" '[ "$rc" -eq 2 ] && grep -q "over 65536 bytes" <<<"$OUT"'
report 1 0 none unset >"$T/exact.txt"
head -c "$((65536 - $(wc -c <"$T/exact.txt")))" /dev/zero | tr '\0' '\n' >>"$T/exact.txt"
OUT=$(bash "$SCRIPT" "$T/exact.txt" 2>&1); rc=$?
check "a report of exactly 65,536 bytes is read" '[ "$rc" -eq 0 ] && [ "$(wc -c <"$T/exact.txt")" -eq 65536 ]'
{
    printf 'context_tokens: 35'
    printf '\000'
    printf '0001\nboundaries: 0\nboundary_turns: none\nwindow: 280000\nhard_stop: 350000\n'
} >"$T/nul.txt"
OUT=$(bash "$SCRIPT" "$T/nul.txt" 2>&1); rc=$?
check "a NUL byte in the report exits 2" '[ "$rc" -eq 2 ] && grep -q "NUL byte" <<<"$OUT"'
OUT=$(bash "$SCRIPT" "" 2>&1); rc=$?
check "an empty path argument exits 2" '[ "$rc" -eq 2 ] && grep -q "empty report path" <<<"$OUT"'
OUT=$(bash "$SCRIPT" "$T/missing.txt" 2>&1); rc=$?
check "a missing report file exits 2" '[ "$rc" -eq 2 ]'
OUT=$(bash "$SCRIPT" "$T" 2>&1); rc=$?
check "a directory exits 2" '[ "$rc" -eq 2 ]'
OUT=$(bash "$SCRIPT" a b 2>&1); rc=$?
check "two arguments exit 2" '[ "$rc" -eq 2 ]'

echo "== it never opens a transcript =="
OUT=$(bash "$SCRIPT" "$TR" 2>&1); rc=$?
check "a transcript given as the report is refused, not read as one" '[ "$rc" -eq 2 ] && ! grep -q "^status:" <<<"$OUT"'
check "the script names no transcript reader" '! grep -Eq "jq|jsonl|compact_boundary" "$SCRIPT"'

echo
printf 'thrash-check: %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

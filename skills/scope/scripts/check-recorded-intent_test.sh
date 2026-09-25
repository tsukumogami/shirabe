#!/usr/bin/env bash
# check-recorded-intent_test.sh -- every output check-recorded-intent.sh can
# produce.
#
# Usage: bash skills/scope/scripts/check-recorded-intent_test.sh
# Exit 0 when every case holds. Needs nothing but bash; runs on the 3.2 floor.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/check-recorded-intent.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/check-recorded-intent-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
NL='
'

expect() { # expect <label> <want-exit> <want-stdout> <args...>
    local label="$1" want_rc="$2" want_out="$3" out rc
    shift 3
    out=$(bash "$S" "$@" 2>/dev/null); rc=$?
    if [ "$rc" = "$want_rc" ] && [ "$out" = "$want_out" ]; then
        PASS=$((PASS + 1)); printf 'ok   %s\n' "$label"
    else
        FAIL=$((FAIL + 1)); printf 'FAIL %s\n     want exit=%s out=[%s], got exit=%s out=[%s]\n' "$label" "$want_rc" "$want_out" "$rc" "$out"
    fi
}

state() { printf '%s' "$2" >"$T/$1"; printf '%s' "$T/$1"; }

NOFILE="$T/absent.md"
STOP=$(state stop.md 'topic: demo
intent: stop
')
CONT=$(state cont.md 'topic: demo
intent: continue
')
NONE=$(state none.md 'topic: demo
intent: none
')
PRE=$(state pre.md 'topic: demo
exit: UNSET
')
BOGUS=$(state bogus.md 'intent: later
')
BEFORE=$(cat "$STOP")

echo "== no mismatch (exit 0, nothing on stdout) =="
expect "a bare invocation is never a mismatch"          0 "" --intent-flag "" --state-file "$STOP"
expect "a bare invocation against a bogus record"       0 "" --intent-flag "" --state-file "$BOGUS"
expect "no state file: nothing recorded to differ from" 0 "" --intent-flag continue --state-file "$NOFILE"
expect "an equal explicit intent proceeds (stop)"       0 "" --intent-flag stop --state-file "$STOP"
expect "an equal explicit intent proceeds (continue)"   0 "" --intent-flag continue --state-file "$CONT"

echo "== mismatch (exit 1, the reason and the recorded value) =="
expect "continue against a recorded stop"  1 "intent-mismatch${NL}recorded=stop"     --intent-flag continue --state-file "$STOP"
expect "stop against a recorded continue"  1 "intent-mismatch${NL}recorded=continue" --intent-flag stop --state-file "$CONT"
expect "continue against a recorded none"  1 "intent-mismatch${NL}recorded=none"     --intent-flag continue --state-file "$NONE"
expect "a pre-change state file records none, so an explicit intent differs" \
    1 "intent-mismatch${NL}recorded=none" --intent-flag stop --state-file "$PRE"

echo "== cannot tell (exit 2) =="
expect "a recorded intent outside the enum"   2 "" --intent-flag stop --state-file "$BOGUS"
expect "an INTENT_FLAG outside continue|stop" 2 "" --intent-flag none --state-file "$STOP"
expect "a missing --state-file"               2 "" --intent-flag stop
expect "a missing --intent-flag"              2 "" --state-file "$STOP"
expect "an unknown argument"                  2 "" --intent-flag stop --state-file "$STOP" --x

if [ "$(cat "$STOP")" = "$BEFORE" ]; then
    PASS=$((PASS + 1)); echo "ok   the state file is never written"
else
    FAIL=$((FAIL + 1)); echo "FAIL the state file changed"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]

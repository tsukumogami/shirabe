#!/usr/bin/env bash
# resolve-intent_test.sh -- every output resolve-intent.sh can produce.
#
# Usage: bash skills/scope/scripts/resolve-intent_test.sh
# Exit 0 when every case holds. Needs nothing but bash; runs on the 3.2 floor.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/resolve-intent.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/resolve-intent-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0

# expect <label> <want-exit> <want-stdout> <args...>
expect() {
    local label="$1" want_rc="$2" want_out="$3" out rc
    shift 3
    out=$(bash "$S" "$@" 2>/dev/null); rc=$?
    if [ "$rc" = "$want_rc" ] && [ "$out" = "$want_out" ]; then
        PASS=$((PASS + 1)); printf 'ok   %s\n' "$label"
    else
        FAIL=$((FAIL + 1)); printf 'FAIL %s\n     want exit=%s out=[%s], got exit=%s out=[%s]\n' "$label" "$want_rc" "$want_out" "$rc" "$out"
    fi
}

state() { # state <name> <content>
    printf '%s' "$2" >"$T/$1"
    printf '%s' "$T/$1"
}

NOFILE="$T/absent_state.md"
PRE=$(state pre.md 'topic: demo
last_updated: 2026-01-01T00:00:00Z
phase_pointer: phase-1
exit: UNSET
exit_artifacts: []
')
STOP=$(state stop.md 'topic: demo
intent: stop
exit: UNSET
')
CONT=$(state cont.md 'topic: demo
intent: continue
')
NONE=$(state none.md 'topic: demo
intent: none
')
QUOTED=$(state quoted.md 'intent: "stop"
')
COMMENT=$(state comment.md 'intent: continue   # recorded at Phase 0
')
CRLF=$(state crlf.md "$(printf 'intent: stop\r\n')")
NESTED=$(state nested.md 'parent_orchestration:
  intent: stop
')
EMPTY=$(state empty.md 'intent:
')
BOGUS=$(state bogus.md 'intent: sometimes
')
TWICE=$(state twice.md 'intent: stop
intent: continue
')
mkdir -p "$T/dir_state.md"

echo "== an explicit INTENT_FLAG wins =="
expect "flag continue, no state file"               0 continue --intent-flag continue --state-file "$NOFILE"
expect "flag stop, no state file"                   0 stop     --intent-flag stop --state-file "$NOFILE"
expect "flag continue over a recorded stop"         0 continue --intent-flag continue --state-file "$STOP"
expect "flag stop over a recorded none"             0 stop     --intent-flag stop --state-file "$NONE"
expect "an explicit flag equal to the recorded one" 0 stop     --intent-flag stop --state-file "$STOP"

echo "== no flag: the recorded intent, else none =="
expect "no flag, no state file"                     0 none     --intent-flag "" --state-file "$NOFILE"
expect "no flag, recorded stop"                     0 stop     --intent-flag "" --state-file "$STOP"
expect "no flag, recorded continue"                 0 continue --intent-flag "" --state-file "$CONT"
expect "no flag, recorded none"                     0 none     --intent-flag "" --state-file "$NONE"
expect "a state file from before the field existed reads as none" 0 none --intent-flag "" --state-file "$PRE"
expect "a quoted value"                             0 stop     --intent-flag "" --state-file "$QUOTED"
expect "a trailing comment"                         0 continue --intent-flag "" --state-file "$COMMENT"
expect "a CRLF line ending"                         0 stop     --intent-flag "" --state-file "$CRLF"
expect "an indented intent: belongs to a nested block, not the run" 0 none --intent-flag "" --state-file "$NESTED"
expect "the --opt=value form"                       0 stop     --intent-flag= --state-file="$STOP"

echo "== what cannot be resolved (exit 2, nothing on stdout) =="
expect "an empty recorded intent is a schema violation"  2 "" --intent-flag "" --state-file "$EMPTY"
expect "an out-of-enum recorded intent"                  2 "" --intent-flag "" --state-file "$BOGUS"
expect "intent: recorded twice"                          2 "" --intent-flag "" --state-file "$TWICE"
expect "a state file that is not a readable file"        2 "" --intent-flag "" --state-file "$T/dir_state.md"
expect "an INTENT_FLAG outside continue|stop (none)"     2 "" --intent-flag none --state-file "$NOFILE"
expect "an INTENT_FLAG outside continue|stop (bogus)"    2 "" --intent-flag bogus --state-file "$NOFILE"
expect "a missing --intent-flag"                         2 "" --state-file "$NOFILE"
expect "a missing --state-file"                          2 "" --intent-flag ""
expect "an unknown argument"                             2 "" --intent-flag "" --state-file "$NOFILE" --bogus
expect "--intent-flag given twice"                       2 "" --intent-flag stop --intent-flag stop --state-file "$NOFILE"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]

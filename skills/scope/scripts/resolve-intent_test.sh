#!/usr/bin/env bash
# resolve-intent_test.sh -- every output resolve-intent.sh can produce.
#
# Usage: bash skills/scope/scripts/resolve-intent_test.sh
# Exit 0 when every case holds. Every case runs against real koto in a store
# isolated by KOTO_SESSIONS_BASE: each fixture is a session holding key
# work/state.md and, for the replaced-run cases, work/prior-run.md. SKIPs
# (exit 0) without koto; the CI job asserts koto is present first.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/resolve-intent.sh"
command -v koto >/dev/null 2>&1 || { echo "SKIP: koto not on PATH -- no case ran"; exit 0; }
T="$(mktemp -d "${TMPDIR:-/tmp}/resolve-intent-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" KOTO_SESSIONS_BASE="$T/store"
mkdir -p "$HOME" "$KOTO_SESSIONS_BASE"
STORE_TEMPLATE="$HERE/../../../koto-templates/skill-session.md"

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

# putkey <session> <key> <content> -- open the session when it is not there
# yet and write the key.
putkey() {
    koto status "$1" >/dev/null 2>&1 || koto init "$1" --template "$STORE_TEMPLATE" >/dev/null 2>&1 || return 1
    printf '%s' "$3" | koto context add "$1" "$2" >/dev/null 2>&1
}
# state <name> <content> -- session scope-<name> with key work/state.md;
# prints the session name.
state() { putkey "scope-$1" work/state.md "$2"; printf 'scope-%s' "$1"; }
# prior <name> <content> -- key work/prior-run.md of scope-<name>.
prior() { putkey "scope-$1" work/prior-run.md "$2"; printf 'scope-%s' "$1"; }

NOFILE="scope-absent"
PRE=$(state pre 'topic: demo
last_updated: 2026-01-01T00:00:00Z
phase_pointer: 1
exit:
exit_artifacts: []
')
STOP=$(state stop 'topic: demo
intent: stop
exit:
')
CONT=$(state cont 'topic: demo
intent: continue
')
NONE=$(state none 'topic: demo
intent: none
')
QUOTED=$(state quoted 'intent: "stop"
')
COMMENT=$(state comment 'intent: continue   # recorded at Phase 0
')
CRLF=$(state crlf "$(printf 'intent: stop\r\n')")
NESTED=$(state nested 'child_snapshots:
  intent: stop
')
EMPTY=$(state empty 'intent:
')
BOGUS=$(state bogus 'intent: sometimes
')
TWICE=$(state twice 'intent: stop
intent: continue
')
# A session with other keys but no state and no prior run.
OTHER=$(putkey scope-other work/other.md 'x
'; printf scope-other)
# Replaced-run facts.
PR_FAIL=$(prior prfail 'outcome: error
exit: full-run
intent: stop
step: scope:push
')
PR_CLEAN=$(prior prclean 'outcome: landed
exit: full-run
intent: stop
')
PR_BOGUS=$(prior prbogus 'outcome: error
exit: full-run
intent: later
step: scope:pr-create
')
PR_STEP=$(prior prstep 'outcome: error
intent: stop
step: scope:elsewhere
')
BOTH=$(state both 'intent: continue
'; prior both 'intent: stop
step: scope:push
' >/dev/null)

echo "== an explicit INTENT_FLAG wins =="
expect "flag continue, no state file"               0 continue --intent-flag continue --session "$NOFILE"
expect "flag stop, no state file"                   0 stop     --intent-flag stop --session "$NOFILE"
expect "flag continue over a recorded stop"         0 continue --intent-flag continue --session "$STOP"
expect "flag stop over a recorded none"             0 stop     --intent-flag stop --session "$NONE"
expect "an explicit flag equal to the recorded one" 0 stop     --intent-flag stop --session "$STOP"

echo "== no flag: the recorded intent, else none =="
expect "no flag, no session at all"                     0 none     --intent-flag "" --session "$NOFILE"
expect "no flag, recorded stop"                     0 stop     --intent-flag "" --session "$STOP"
expect "no flag, recorded continue"                 0 continue --intent-flag "" --session "$CONT"
expect "no flag, recorded none"                     0 none     --intent-flag "" --session "$NONE"
expect "a state file from before the field existed reads as none" 0 none --intent-flag "" --session "$PRE"
expect "a quoted value"                             0 stop     --intent-flag "" --session "$QUOTED"
expect "a trailing comment"                         0 continue --intent-flag "" --session "$COMMENT"
expect "a CRLF line ending"                         0 stop     --intent-flag "" --session "$CRLF"
expect "an indented intent: belongs to a nested block, not the run" 0 none --intent-flag "" --session "$NESTED"
expect "a session with other keys only reads as none"  0 none     --intent-flag "" --session "$OTHER"
expect "the --opt=value form"                       0 stop     --intent-flag= --session=$STOP

echo "== no state: the replaced run's failed publish, else none =="
expect "a failed publish step carries its intent"       0 stop     --intent-flag "" --session "$PR_FAIL"
expect "a clean finish carries nothing"                 0 none     --intent-flag "" --session "$PR_CLEAN"
expect "a step outside its set carries nothing"         0 none     --intent-flag "" --session "$PR_STEP"
expect "an explicit flag still wins over a prior run"   0 continue --intent-flag continue --session "$PR_FAIL"
expect "work/state.md wins over work/prior-run.md"      0 continue --intent-flag "" --session "$BOTH"
expect "an out-of-set prior intent beside a publish step cannot be resolved" 2 "" --intent-flag "" --session "$PR_BOGUS"

echo "== what cannot be resolved (exit 2, nothing on stdout) =="
expect "an empty recorded intent is a schema violation"  2 "" --intent-flag "" --session "$EMPTY"
expect "an out-of-enum recorded intent"                  2 "" --intent-flag "" --session "$BOGUS"
expect "intent: recorded twice"                          2 "" --intent-flag "" --session "$TWICE"
expect "a session name outside the pattern"             2 "" --intent-flag "" --session "Bad_Name"
expect "an INTENT_FLAG outside continue|stop (none)"     2 "" --intent-flag none --session "$NOFILE"
expect "an INTENT_FLAG outside continue|stop (bogus)"    2 "" --intent-flag bogus --session "$NOFILE"
expect "a missing --intent-flag"                         2 "" --session "$NOFILE"
expect "a missing --session"                          2 "" --intent-flag ""
expect "an unknown argument"                             2 "" --intent-flag "" --session "$NOFILE" --bogus
expect "--intent-flag given twice"                       2 "" --intent-flag stop --intent-flag stop --session "$NOFILE"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]

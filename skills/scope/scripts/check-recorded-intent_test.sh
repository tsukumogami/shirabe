#!/usr/bin/env bash
# check-recorded-intent_test.sh -- every output check-recorded-intent.sh can
# produce.
#
# Usage: bash skills/scope/scripts/check-recorded-intent_test.sh
# Exit 0 when every case holds. Every case runs against real koto in a store
# isolated by KOTO_SESSIONS_BASE; each fixture is a session holding key
# work/state.md and, for the replaced-run cases, work/prior-run.md. SKIPs
# (exit 0) without koto; the CI job asserts koto is present first.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/check-recorded-intent.sh"
command -v koto >/dev/null 2>&1 || { echo "SKIP: koto not on PATH -- no case ran"; exit 0; }
T="$(mktemp -d "${TMPDIR:-/tmp}/check-recorded-intent-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" KOTO_SESSIONS_BASE="$T/store"
mkdir -p "$HOME" "$KOTO_SESSIONS_BASE"
STORE_TEMPLATE="$HERE/../../../koto-templates/skill-session.md"

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

putkey() { # putkey <session> <key> <content>
    koto status "$1" >/dev/null 2>&1 || koto init "$1" --template "$STORE_TEMPLATE" >/dev/null 2>&1 || return 1
    printf '%s' "$3" | koto context add "$1" "$2" >/dev/null 2>&1
}
state() { putkey "scope-$1" work/state.md "$2"; printf 'scope-%s' "$1"; }
prior() { putkey "scope-$1" work/prior-run.md "$2"; printf 'scope-%s' "$1"; }

NOFILE="scope-absent"
STOP=$(state stop 'topic: demo
intent: stop
')
CONT=$(state cont 'topic: demo
intent: continue
')
NONE=$(state none 'topic: demo
intent: none
')
PRE=$(state pre 'topic: demo
exit:
')
BOGUS=$(state bogus 'intent: later
')
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
intent: later
step: scope:pr-create
')
BEFORE=$(koto context get "$STOP" work/state.md)

echo "== no mismatch (exit 0, nothing on stdout) =="
expect "a bare invocation is never a mismatch"          0 "" --intent-flag "" --session "$STOP"
expect "a bare invocation against a bogus record"       0 "" --intent-flag "" --session "$BOGUS"
expect "no session: nothing recorded to differ from" 0 "" --intent-flag continue --session "$NOFILE"
expect "an equal explicit intent proceeds (stop)"       0 "" --intent-flag stop --session "$STOP"
expect "an equal explicit intent proceeds (continue)"   0 "" --intent-flag continue --session "$CONT"

expect "a clean finish records nothing to differ from"  0 "" --intent-flag continue --session "$PR_CLEAN"
expect "an equal explicit intent after a failed publish" 0 "" --intent-flag stop --session "$PR_FAIL"

echo "== mismatch (exit 1, the reason and the recorded value) =="
expect "continue against a recorded stop"  1 "intent-mismatch${NL}recorded=stop"     --intent-flag continue --session "$STOP"
expect "stop against a recorded continue"  1 "intent-mismatch${NL}recorded=continue" --intent-flag stop --session "$CONT"
expect "continue against a recorded none"  1 "intent-mismatch${NL}recorded=none"     --intent-flag continue --session "$NONE"
expect "a pre-change state file records none, so an explicit intent differs" \
    1 "intent-mismatch${NL}recorded=none" --intent-flag stop --session "$PRE"

expect "a failed publish records its intent (prior-run)" 1 "intent-mismatch${NL}recorded=stop" --intent-flag continue --session "$PR_FAIL"

echo "== cannot tell (exit 2) =="
expect "an out-of-set prior intent beside a publish step" 2 "" --intent-flag stop --session "$PR_BOGUS"
expect "a recorded intent outside the enum"   2 "" --intent-flag stop --session "$BOGUS"
expect "an INTENT_FLAG outside continue|stop" 2 "" --intent-flag none --session "$STOP"
expect "a missing --session"               2 "" --intent-flag stop
expect "a missing --intent-flag"              2 "" --session "$STOP"
expect "an unknown argument"                  2 "" --intent-flag stop --session "$STOP" --x

if [ "$(koto context get "$STOP" work/state.md)" = "$BEFORE" ]; then
    PASS=$((PASS + 1)); echo "ok   the state key is never written"
else
    FAIL=$((FAIL + 1)); echo "FAIL the state key changed"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]

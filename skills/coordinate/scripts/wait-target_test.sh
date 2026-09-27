#!/usr/bin/env bash
# wait-target_test.sh -- wait-target.sh and report-source.sh against stand-ins
# for koto (context and request store) and the record's script.
#
# Covered, for wait-target.sh select: a resolved leg picked over an older open
# one; an abandoned or missing leg counted as waiting; the oldest open leg
# when none has resolved; message-path, undispatched and malformed holdings
# skipped; a request koto can't read skipped rather than routed; `none` printed
# and written when nothing is watched (never an empty capture); the bounded
# wake watch run only when asked for, only with an open leg and no result, and
# only on a koto that has it, with its cursor kept; a refused record read. For
# leg: the leg printed and report_topic written; exit 1 with no leg. For
# report-source.sh: a leg report admitted, a message admitted for a
# message-path worker and refused for a leg-bound one or an unknown topic, and
# malformed inputs.
#
# Usage: bash skills/coordinate/scripts/wait-target_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs jq. bash 3.2.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/wait-target.sh"
R="$HERE/report-source.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/wait-target-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

BIN="$T/bin"
mkdir -p "$BIN"
export ST="$T/state"

cat >"$BIN/koto" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "context get") [ -f "$ST/ctx/$4" ] || exit 1; cat "$ST/ctx/$4" ;;
    "context exists") [ -f "$ST/ctx/$4" ] ;;
    "context add") cat "$6" >"$ST/ctx/$4" ;;
    "request get") [ -f "$ST/req/$3.json" ] || exit 1; cat "$ST/req/$3.json" ;;
    "request watch")
        [ "${KOTO_HAS_WATCH:-}" = 1 ] || exit 2
        [ "$3" = --help ] && exit 0
        echo "watch $*" >>"$ST/calls.log"
        printf '{"cli_contract":"1.0","session":"coord","woke":true,"cursor":"c42"}\n'
        ;;
    *) exit 64 ;;
esac
EOF
cat >"$T/record-holding.sh" <<'EOF'
#!/usr/bin/env bash
MODE=""; TOPIC=""
while [ $# -gt 0 ]; do
    case "$1" in
        --list) MODE=list; shift ;;
        --read) MODE=read; shift ;;
        --topic) TOPIC="$2"; shift 2 ;;
        --session) shift 2 ;;
        *) exit 64 ;;
    esac
done
[ "${RECORD_MODE:-}" = refuse ] && exit 10
case "$MODE" in
    list) cat "$ST/rows.json" ;;
    read) jq -ce --arg t "$TOPIC" '.[] | select(.worker == $t)' "$ST/rows.json" || exit 1 ;;
esac
EOF
chmod +x "$BIN/koto" "$T/record-holding.sh"
export PATH="$BIN:$PATH"
export DC_RECORD_HOLDING="$T/record-holding.sh"

reset() {
    rm -rf "$ST"
    mkdir -p "$ST/ctx" "$ST/req"
    : >"$ST/calls.log"
    printf '%s\n' "$1" >"$ST/rows.json"
    unset KOTO_HAS_WATCH RECORD_MODE
}
req() { printf '{"request_id":"%s","legs":{"%s":{"name":"%s","disposition":"%s"}}}\n' "$1" "$2" "$2" "$3" >"$ST/req/$1.json"; }
sel() { bash "$S" select --session coord "$@"; }
target() { jq -r "$1" "$ST/ctx/wait_target"; }

ROWS='[
 {"worker":"alpha","dispatch_status":"dispatched","return_path":"leg req_a:scope"},
 {"worker":"beta","dispatch_status":"dispatched","return_path":"message"},
 {"worker":"gamma","dispatch_status":"dispatched","return_path":"leg req_g:execute"},
 {"worker":"delta","dispatch_status":"dispatching","return_path":"leg req_d:scope"},
 {"worker":"eps","dispatch_status":"dispatched","return_path":"leg req_e;rm -rf:scope"}
]'

# --- select --------------------------------------------------------------------------------

reset "$ROWS"
req req_a scope open; req req_g execute resolved; req req_d scope resolved
eq  "select: a resolved leg over an older open one" req_g "$(sel)"
eq  "select: wait_target path" leg "$(target .path)"
eq  "select: wait_target topic" gamma "$(target .topic)"
eq  "select: wait_target leg" execute "$(target .leg)"
# Both captures (WAIT_REQ from select, WAIT_LEG from leg) must be characters
# koto admits in a capture.
safe() { if printf '%s' "$2" | grep -Eq '^[A-Za-z0-9 :/_.@-]+$'; then ok "$1"; else bad "$1" "$2"; fi; }
safe "capture: select's request id is capture-safe" "$(sel)"
safe "capture: leg's leg name is capture-safe" "$(bash "$S" leg --session coord)"
reset '[]'
safe "capture: none is capture-safe" "$(sel)"
reset "$ROWS"
req req_a scope open; req req_g execute resolved; req req_d scope resolved

reset "$ROWS"
req req_a scope open; req req_g execute abandoned
eq  "select: an abandoned leg counts as waiting" req_g "$(sel)"

reset "$ROWS"
req req_a scope open; req req_g execute missing-ignored
printf '{"request_id":"req_g","legs":{}}\n' >"$ST/req/req_g.json"
eq  "select: a leg missing from its request counts as waiting" req_g "$(sel)"

reset "$ROWS"
req req_a scope open; req req_g execute open
eq  "select: the oldest open leg when none resolved" req_a "$(sel)"

# delta is still dispatching; its leg has resolved, and it comes first. It
# must not be picked: only a dispatched worker is watched.
reset '[
 {"worker":"delta","dispatch_status":"dispatching","return_path":"leg req_d:scope"},
 {"worker":"alpha","dispatch_status":"dispatched","return_path":"leg req_a:scope"}
]'
req req_d scope resolved; req req_a scope open
eq  "select: skips a holding that isn't dispatched yet" req_a "$(sel)"

# A leg read once isn't read again.
reset "$ROWS"
req req_a scope open; req req_g execute resolved
eq  "taken: the resolved leg first" req_g "$(sel)"
eq  "taken: its disposition recorded" resolved "$(target .disposition)"
bash "$S" leg --session coord >/dev/null
eq  "taken: reading a resolved leg marks it taken" "req_g:execute" "$(cat "$ST/ctx/taken_legs")"
eq  "taken: the next pick skips it" req_a "$(sel)"
bash "$S" leg --session coord >/dev/null
eq  "taken: reading an open leg doesn't mark it" "req_g:execute" "$(cat "$ST/ctx/taken_legs")"
# The leg resolves after select picked it open: the next tick's leg run sees
# it resolved and marks it, so it's never read twice.
req req_a scope resolved
bash "$S" leg --session coord >/dev/null
eq  "taken: a leg that resolved after select is marked on the tick that takes it" "req_a:scope
req_g:execute" "$(cat "$ST/ctx/taken_legs")"
eq  "taken: and isn't picked again" none "$(sel)"

reset "$ROWS"
req req_g execute open
eq  "select: a request koto can't read is skipped, not routed" req_g "$(sel 2>/dev/null)"

reset '[{"worker":"beta","dispatch_status":"dispatched","return_path":"message"}]'
eq  "select: nothing to watch prints none" none "$(sel)"
eq  "select: nothing to watch writes path none" none "$(target .path)"

reset '[]'
eq  "select: an empty record prints none" none "$(sel)"

reset "$ROWS"
export RECORD_MODE=refuse
sel >/dev/null 2>&1; eq "select: a refused record read is exit 10" 10 "$?"

# --- the bounded wake watch ---------------------------------------------------------------------

reset "$ROWS"
req req_a scope open; req req_g execute open
sel --watch-secs 5 >/dev/null
eq  "watch: skipped on a koto without it" "" "$(cat "$ST/calls.log")"

reset "$ROWS"
req req_a scope open; req req_g execute open
export KOTO_HAS_WATCH=1
sel >/dev/null
eq  "watch: off by default" "" "$(cat "$ST/calls.log")"
sel --watch-secs 5 >/dev/null
eq  "watch: runs bounded, with no cursor yet" "watch request watch --session coord --timeout-secs 5" "$(cat "$ST/calls.log")"
eq  "watch: keeps the cursor" c42 "$(cat "$ST/ctx/wake_cursor")"
: >"$ST/calls.log"
sel --watch-secs 5 >/dev/null
eq  "watch: passes the cursor back" "watch request watch --session coord --timeout-secs 5 --since c42" "$(cat "$ST/calls.log")"

reset "$ROWS"
req req_a scope resolved
export KOTO_HAS_WATCH=1
sel --watch-secs 5 >/dev/null
eq  "watch: not run when a result is already waiting" "" "$(cat "$ST/calls.log")"

bash "$S" select --session coord --watch-secs x >/dev/null 2>&1; eq "usage: a non-numeric watch is 64" 64 "$?"
bash "$S" nope --session coord >/dev/null 2>&1; eq "usage: an unknown mode is 64" 64 "$?"

# --- leg ---------------------------------------------------------------------------------------------

reset "$ROWS"
req req_g execute resolved
sel >/dev/null
eq  "leg: prints the leg" execute "$(bash "$S" leg --session coord)"
eq  "leg: writes report_topic" gamma "$(cat "$ST/ctx/report_topic")"
printf '{"path":"none"}\n' >"$ST/ctx/wait_target"
bash "$S" leg --session coord >/dev/null 2>&1; eq "leg: no leg is exit 1" 1 "$?"
printf '{"path":"leg","topic":"gamma","request":"req_g","leg":"bad leg"}\n' >"$ST/ctx/wait_target"
bash "$S" leg --session coord >/dev/null 2>&1; eq "leg: a malformed leg is exit 2" 2 "$?"

# --- report-source.sh ----------------------------------------------------------------------------------

src() { printf '%s' "$1" >"$ST/ctx/report_topic"; printf '%s' "$2" >"$ST/ctx/report_source"; bash "$R" --session coord >/dev/null 2>&1; echo $?; }
reset "$ROWS"
printf '{"path":"leg","topic":"gamma","request":"req_g","leg":"execute"}\n' >"$ST/ctx/wait_target"
eq  "source: a leg report from the recorded leg the wait read is admitted" 0 "$(src gamma leg)"
printf '{"path":"leg","topic":"beta","request":"req_b","leg":"scope"}\n' >"$ST/ctx/wait_target"
eq  "source: a leg report for a message-path worker is refused, even when the wait names it" 1 "$(src beta leg)"
printf '{"path":"leg","topic":"gamma","request":"req_g","leg":"execute"}\n' >"$ST/ctx/wait_target"
printf '{"path":"leg","topic":"gamma","request":"req_other","leg":"execute"}\n' >"$ST/ctx/wait_target"
eq  "source: a leg report whose read leg isn't the recorded one is refused" 1 "$(src gamma leg)"
printf '{"path":"none"}\n' >"$ST/ctx/wait_target"
eq  "source: a leg report with no leg read is refused" 1 "$(src gamma leg)"
eq  "source: a message for a message-path worker is admitted" 0 "$(src beta message)"
eq  "source: a message for a leg-bound worker is refused" 1 "$(src gamma message)"
eq  "source: a message for an unknown topic is refused" 1 "$(src nobody message)"
eq  "source: an unknown source is 2" 2 "$(src beta email)"
eq  "source: a malformed topic is 2" 2 "$(src ../x message)"
export RECORD_MODE=refuse
eq  "source: a refused record read is 2" 2 "$(src beta message)"
unset RECORD_MODE
rm -f "$ST/ctx/report_source"
bash "$R" --session coord >/dev/null 2>&1; eq "source: no report_source is 2" 2 "$?"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

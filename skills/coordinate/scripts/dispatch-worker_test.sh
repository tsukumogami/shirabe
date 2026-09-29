#!/usr/bin/env bash
# dispatch-worker_test.sh -- dispatch-worker.sh and holding-recorded.sh against
# stand-ins for niwa, koto and the record's script, which log every call to one
# file so the order of the record write and the launch can be read back.
#
# Covered: the holding written before the launch and rewritten after; the
# launch's arguments and prompt; a leg opened for an entry point that has one
# and none for one that doesn't; a re-run on a dispatched topic launching
# nothing; a resumed `dispatching` row confirmed without a launch, or
# launched once when no session exists; a failed launch leaving
# dispatch-failed and an abandoned request; a failed launch whose session did
# appear confirmed; an unreadable listing leaving dispatching; the deadline; a
# topic a live session uses; the exact session match; a concurrent run
# refused by the lock; a mismatched topic; the record refusing a write;
# --rebrief; no session id, instance path or job id in the holding; and every
# exit code of holding-recorded.sh.
#
# Usage: bash skills/coordinate/scripts/dispatch-worker_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs jq. bash 3.2.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/dispatch-worker.sh"
G="$HERE/holding-recorded.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-worker-test.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { if printf '%s' "$2" | grep -Fq -- "$3"; then ok "$1"; else bad "$1" "missing [$3] in [$2]"; fi; }
lacks() { if printf '%s' "$2" | grep -Fq -- "$3"; then bad "$1" "unexpected [$3]"; else ok "$1"; fi; }

# --- stand-ins ------------------------------------------------------------------------
#
# State lives under $ST: ctx/<key> for the session's context, rows/<topic>.json
# for the record, sessions.json for niwa's listing, calls.log for every call.

BIN="$T/bin"
mkdir -p "$BIN"
export ST="$T/state"

cat >"$BIN/koto" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "context get")
        [ -f "$ST/ctx/$4" ] || exit 1
        cat "$ST/ctx/$4"
        ;;
    "request create")
        echo "koto request create $*" >>"$ST/calls.log"
        [ "${KOTO_CREATE_FAIL:-}" = 1 ] && exit 1
        printf '{"request_id":"req_1"}\n'
        ;;
    "request abandon-request")
        echo "koto request abandon-request $3" >>"$ST/calls.log"
        ;;
    "request list")
        if [ -f "$ST/open_requests.json" ]; then cat "$ST/open_requests.json"; else printf '{"requests":[]}\n'; fi
        ;;
    *) exit 64 ;;
esac
EOF

cat >"$BIN/niwa" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list)
        echo "niwa list" >>"$ST/calls.log"
        [ "${NIWA_LIST_FAIL:-}" = 1 ] && exit 1
        cat "$ST/sessions.json"
        ;;
    dispatch)
        shift
        printf 'niwa dispatch' >>"$ST/calls.log"
        for a in "$@"; do printf ' [%s]' "$a" >>"$ST/calls.log"; done
        echo >>"$ST/calls.log"
        printf '%s\n' "$1" >"$ST/prompt"
        case "${NIWA_MODE:-ok}" in
            ok)
                jq -c '. + [{"name":"x","path":"/p","session_name":"'"$NIWA_NAME"'"}]' "$ST/sessions.json" >"$ST/s.tmp" && mv "$ST/s.tmp" "$ST/sessions.json"
                printf 'Dispatched session 0\n  instance: /p\n  session name: %s\n' "$NIWA_NAME"
                ;;
            fail) exit 1 ;;
            fail-but-launched)
                jq -c '. + [{"name":"x","path":"/p","session_name":"'"$NIWA_NAME"'"}]' "$ST/sessions.json" >"$ST/s.tmp" && mv "$ST/s.tmp" "$ST/sessions.json"
                exit 1
                ;;
            hang) sleep 30 ;;
        esac
        ;;
    *) exit 64 ;;
esac
EOF

cat >"$T/record-holding.sh" <<'EOF'
#!/usr/bin/env bash
READ=0; TOPIC=""; ROWF=""; SESSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --read) READ=1; shift ;;
        --topic) TOPIC="$2"; shift 2 ;;
        --row-file) ROWF="$2"; shift 2 ;;
        --session) SESSION="$2"; shift 2 ;;
        *) exit 64 ;;
    esac
done
[ -n "$SESSION" ] || exit 64
if [ "$READ" = 1 ]; then
    [ "${RECORD_READ_MODE:-}" = refuse ] && exit 10
    [ "${RECORD_READ_MODE:-}" = fail ] && exit 2
    [ -f "$ST/rows/$TOPIC.json" ] || exit 1
    cat "$ST/rows/$TOPIC.json"
    exit 0
fi
echo "record write $TOPIC $(jq -r .dispatch_status "$ROWF")" >>"$ST/calls.log"
[ "${RECORD_WRITE_MODE:-}" = refuse ] && exit 10
[ "${RECORD_WRITE_MODE:-}" = full ] && exit 13
# changed: the record always changes under the write (exit 12); changed-once:
# only the first write sees it.
[ "${RECORD_WRITE_MODE:-}" = changed ] && exit 12
if [ "${RECORD_WRITE_MODE:-}" = changed-once ] && [ ! -e "$ST/changed-once" ]; then
    : >"$ST/changed-once"
    exit 12
fi
cp "$ROWF" "$ST/rows/$TOPIC.json"
# The real writer prints the record's URL on a successful write.
echo "https://github.com/acme/widgets/issues/1"
EOF
chmod +x "$BIN/koto" "$BIN/niwa" "$T/record-holding.sh"
export PATH="$BIN:$PATH"
export DC_RECORD_HOLDING="$T/record-holding.sh"

# --- the workspace -------------------------------------------------------------------

W="$T/ws"
mkdir -p "$W/.niwa" "$W/inst/.niwa"
: >"$W/.niwa/workspace.toml"
: >"$W/.niwa/instance.json"
: >"$W/inst/.niwa/instance.json"

INPUT_DELIVER='{
  "topic": "plugin-api", "repo": "acme/widgets", "entry_point": "deliver",
  "entry_args": ["plugin-api", "--no-merge"], "run_mode": "--auto", "phase": "executing",
  "authority": "You are working for the owner on acme/widgets.",
  "goal": "The plugin API ships.", "unit": "Feature 2: the plugin API",
  "checkpoints": ["The scoping PR is open.", "The PR is ready with CI green."],
  "acceptance": ["It loads a plugin."], "dispatcher_session": "coord-alpha"
}'
INPUT_SCOPE=$(printf '%s' "$INPUT_DELIVER" | jq -c '.entry_point = "scope" | .entry_args = ["plugin-api", "--intent=continue"]')

reset() {
    rm -rf "$ST"
    mkdir -p "$ST/ctx" "$ST/rows"
    printf '[]\n' >"$ST/sessions.json"
    : >"$ST/calls.log"
    printf '%s' "$1" >"$ST/ctx/brief_input.json"
    printf '%s' "${2:-plugin-api}" >"$ST/ctx/dispatch_topic"
    rm -rf "$W/.niwa/dispatch-briefs"
    export NIWA_MODE=ok NIWA_NAME=plugin_api-1a2b3c4d
    unset NIWA_LIST_FAIL KOTO_CREATE_FAIL RECORD_READ_MODE RECORD_WRITE_MODE DISPATCH_DEADLINE_SECS
}
run() { (cd "$W/inst" && bash "$S" --session coord "$@"); }
row() { jq -r ".$1" "$ST/rows/plugin-api.json"; }
calls() { cat "$ST/calls.log"; }

# --- a fresh dispatch: /deliver, which answers a leg ---------------------------------------

reset "$INPUT_DELIVER"
OUT=$(run 2>/dev/null); RC=$?
eq  "fresh: exit 0" 0 "$RC"
eq  "fresh: prints the session name" "session=plugin_api-1a2b3c4d" "$OUT"
LOG=$(calls)
FIRST_WRITE=$(grep -n 'record write plugin-api dispatching' "$ST/calls.log" | head -1 | cut -d: -f1)
LAUNCH=$(grep -n '^niwa dispatch' "$ST/calls.log" | head -1 | cut -d: -f1)
LAST_WRITE=$(grep -n 'record write plugin-api dispatched' "$ST/calls.log" | tail -1 | cut -d: -f1)
if [ -n "$FIRST_WRITE" ] && [ -n "$LAUNCH" ] && [ "$FIRST_WRITE" -lt "$LAUNCH" ]; then ok "fresh: holding written before the launch"; else bad "fresh: holding written before the launch" "$LOG"; fi
if [ -n "$LAST_WRITE" ] && [ "$LAST_WRITE" -gt "$LAUNCH" ]; then ok "fresh: rewritten dispatched after"; else bad "fresh: rewritten dispatched after" "$LOG"; fi
eq  "fresh: one launch" 1 "$(grep -c '^niwa dispatch' "$ST/calls.log")"
has "fresh: --name topic" "$LOG" "[--name] [plugin-api]"
has "fresh: --detach" "$LOG" "[--detach]"
has "fresh: a deliver leg opened, pinning the topic" "$LOG" '"name":"deliver","role":"deliver","template":"deliver.md","inputs":{"TOPIC":"plugin-api"}'
eq  "row: status" dispatched "$(row dispatch_status)"
eq  "row: return path" "leg req_1:deliver" "$(row return_path)"
eq  "row: worker is the topic" plugin-api "$(row worker)"
eq  "row: repo" acme/widgets "$(row repo)"
eq  "row: entry point" deliver "$(row entry_point)"
eq  "row: mode" "--auto --no-merge" "$(row mode)"
eq  "row: phase" executing "$(row phase)"
eq  "row: unit" "Feature 2: the plugin API" "$(row unit)"
eq  "row: branch empty" "" "$(row branch)"
eq  "row: pull request empty (the record's none yet)" "" "$(row pull_request)"
eq  "row: date" "$(date -u +%Y-%m-%d)" "$(row dispatched)"
ROWTXT=$(cat "$ST/rows/plugin-api.json")
lacks "row: no session name" "$ROWTXT" "plugin_api-1a2b3c4d"
lacks "row: no instance path" "$ROWTXT" "/p\""
P=$(cat "$ST/prompt")
has "prompt: authority" "$P" "You are working for the owner on acme/widgets."
has "prompt: invocation" "$P" '`/shirabe:deliver plugin-api --auto --no-merge --koto-leg=req_1:deliver`'
has "prompt: repository" "$P" "in acme/widgets"
has "prompt: stop checkpoint" "$P" "stop at: The PR is ready with CI green."
has "prompt: brief path" "$P" "$W/.niwa/dispatch-briefs/plugin-api.md"
[ -f "$W/.niwa/dispatch-briefs/plugin-api.md" ] && ok "brief: written" || bad "brief: written" ""

# --- a re-run on a dispatched topic ---------------------------------------------------------

: >"$ST/calls.log"
OUT=$(run 2>/dev/null); RC=$?
eq  "re-run: exit 0" 0 "$RC"
eq  "re-run: already-dispatched" already-dispatched "$OUT"
eq  "re-run: no launch, no write" "" "$(grep -E '^niwa dispatch|record write' "$ST/calls.log")"

# --- the leg path ------------------------------------------------------------------------------

reset "$INPUT_SCOPE"
OUT=$(run 2>/dev/null); RC=$?
eq  "leg: exit 0" 0 "$RC"
LOG=$(calls)
has "leg: one-leg request named scope" "$LOG" '"name":"scope","role":"scope","template":"scope.md","inputs":{"TOPIC":"plugin-api"}'
has "leg: coordinator of record" "$LOG" "--coordinator-of-record coordinate-plugin-api"
eq  "leg: return path in the record's form" "leg req_1:scope" "$(row return_path)"
has "leg: prompt carries --koto-leg" "$(cat "$ST/prompt")" "--koto-leg=req_1:scope"
has "leg: the brief shows the same invocation" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" '`/shirabe:scope plugin-api --auto --intent=continue --koto-leg=req_1:scope`'
CREATE=$(grep -n 'koto request create' "$ST/calls.log" | cut -d: -f1)
if [ "$CREATE" -lt "$(grep -n 'record write' "$ST/calls.log" | head -1 | cut -d: -f1)" ]; then ok "leg: opened before the write-ahead"; else bad "leg: opened before the write-ahead" "$LOG"; fi

reset "$INPUT_SCOPE"
printf '{"requests":[{"request_id":"req_left","coordinator_of_record":"coordinate-plugin-api","request_state":"open"},{"request_id":"req_other","coordinator_of_record":"coordinate-other","request_state":"open"}]}\n' >"$ST/open_requests.json"
run >/dev/null 2>&1
LOG=$(calls)
has "leg: a leftover request under the topic is abandoned first" "$LOG" "koto request abandon-request req_left"
lacks "leg: another topic's request is left alone" "$LOG" "abandon-request req_other"

reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.entry_point = "execute" | .entry_args = ["docs/plans/PLAN-plugin-api.md"]')"
run >/dev/null 2>&1
has "leg: execute admits both templates and pins the plan slug" "$(calls)" '"template":["execute.md","execute-coordinated.md"],"inputs":{"PLAN_SLUG":"plugin-api"}'

reset "$INPUT_SCOPE"
export KOTO_CREATE_FAIL=1
run >/dev/null 2>&1; RC=$?
eq  "leg: a failed create is exit 2" 2 "$RC"
eq  "leg: a failed create writes and launches nothing" "" "$(grep -E '^niwa dispatch|record write' "$ST/calls.log")"

# --- the message path ----------------------------------------------------------------------------

# /work-on answers its leg for an issue, pinning nothing.
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.entry_point = "work-on" | .entry_args = ["123"]')"
run >/dev/null 2>&1
has "work-on: an issue gets a leg that pins nothing" "$(calls)" '"name":"work-on","role":"work-on","template":"work-on.md","inputs":{}'
eq  "work-on: return path in the record's form" "leg req_1:work-on" "$(row return_path)"

# Given a PLAN path it never reaches its leg, so none is opened.
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.entry_point = "work-on" | .entry_args = ["docs/plans/PLAN-plugin-api.md"]')"
run >/dev/null 2>&1
lacks "work-on: a PLAN path opens no request" "$(calls)" "koto request create"
eq  "work-on: a PLAN path reports by message" message "$(row return_path)"
lacks "work-on: a PLAN path's invocation carries no leg" "$(cat "$ST/prompt")" "--koto-leg"

# An entry point with no leg reports by message.
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.entry_point = "explore" | .entry_args = ["plugin-api"]')"
run >/dev/null 2>&1
lacks "explore: no request opened" "$(calls)" "koto request create"
eq  "explore: return path" message "$(row return_path)"

# --- a resumed dispatching row -------------------------------------------------------------------

reset "$INPUT_DELIVER"
printf '%s' '{"dispatch_status":"dispatching","return_path":"message","worker":"plugin-api","repo":"acme/widgets","mode":"--auto --no-merge"}' >"$ST/rows/plugin-api.json"
printf '[{"name":"x","path":"/p","session_name":"plugin_api-1a2b3c4d"}]\n' >"$ST/sessions.json"
OUT=$(run 2>/dev/null); RC=$?
eq  "resume, launched: exit 0" 0 "$RC"
eq  "resume, launched: confirmed from the listing" "session=plugin_api-1a2b3c4d" "$OUT"
eq  "resume, launched: no launch" 0 "$(grep -c '^niwa dispatch' "$ST/calls.log")"
eq  "resume, launched: row dispatched" dispatched "$(row dispatch_status)"

reset "$INPUT_SCOPE"
printf '%s' '{"dispatch_status":"dispatching","return_path":"leg req_9:scope","worker":"plugin-api","repo":"acme/widgets","mode":"--auto --intent=continue"}' >"$ST/rows/plugin-api.json"
OUT=$(run 2>/dev/null); RC=$?
eq  "resume, not launched: exit 0" 0 "$RC"
eq  "resume, not launched: one launch" 1 "$(grep -c '^niwa dispatch' "$ST/calls.log")"
lacks "resume, not launched: reuses the recorded request" "$(calls)" "koto request create"
has "resume, not launched: prompt uses the recorded leg" "$(cat "$ST/prompt")" "--koto-leg=req_9:scope"

# --- failures --------------------------------------------------------------------------------------

reset "$INPUT_SCOPE"
export NIWA_MODE=fail
run >/dev/null 2>&1; RC=$?
eq  "failed launch: exit 4" 4 "$RC"
eq  "failed launch: row dispatch-failed" dispatch-failed "$(row dispatch_status)"
has "failed launch: request abandoned" "$(calls)" "koto request abandon-request req_1"

reset "$INPUT_DELIVER"
export NIWA_MODE=fail-but-launched
OUT=$(run 2>/dev/null); RC=$?
eq  "failed exit, session appeared: exit 0" 0 "$RC"
eq  "failed exit, session appeared: confirmed" dispatched "$(row dispatch_status)"

reset "$INPUT_DELIVER"
printf '%s' '{"dispatch_status":"dispatching","return_path":"message","worker":"plugin-api","repo":"acme/widgets","mode":"--auto --no-merge"}' >"$ST/rows/plugin-api.json"
export NIWA_LIST_FAIL=1
run >/dev/null 2>&1; RC=$?
eq  "unreadable listing on resume: exit 6" 6 "$RC"
eq  "unreadable listing on resume: stays dispatching" dispatching "$(row dispatch_status)"
eq  "unreadable listing on resume: no launch" 0 "$(grep -c '^niwa dispatch' "$ST/calls.log")"

reset "$INPUT_DELIVER"
export NIWA_MODE=hang DISPATCH_DEADLINE_SECS=1
START=$(date +%s)
run >/dev/null 2>&1; RC=$?
ELAPSED=$(( $(date +%s) - START ))
eq  "deadline: a hung launch fails as exit 4" 4 "$RC"
if [ "$ELAPSED" -lt 15 ]; then ok "deadline: returns promptly"; else bad "deadline: returns promptly" "${ELAPSED}s"; fi

# --- topic checks ------------------------------------------------------------------------------------

reset "$INPUT_DELIVER"
printf '[{"name":"x","path":"/p","session_name":"plugin_api-deadbeef"}]\n' >"$ST/sessions.json"
run >/dev/null 2>&1; RC=$?
eq  "live topic: exit 5" 5 "$RC"
eq  "live topic: nothing written or launched" "" "$(grep -E '^niwa dispatch|record write' "$ST/calls.log")"

reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.topic = "api" | .entry_args = ["api"]')" api
printf '[{"name":"x","path":"/p","session_name":"api_v2-deadbeef"}]\n' >"$ST/sessions.json"
export NIWA_NAME=api-1a2b3c4d
run >/dev/null 2>&1; RC=$?
eq  "exact match: api isn't api_v2's session" 0 "$RC"

reset "$INPUT_DELIVER" other-topic
run >/dev/null 2>&1; RC=$?
eq  "mismatched topic: exit 2" 2 "$RC"
eq  "mismatched topic: nothing done" "" "$(calls)"

reset "$INPUT_DELIVER"
mkdir -p "$W/.niwa/dispatch-briefs/.plugin-api.lock"
sleep 30 &
HOLDER=$!
printf '%s\n' "$HOLDER" >"$W/.niwa/dispatch-briefs/.plugin-api.lock/pid"
run >/dev/null 2>&1; RC=$?
eq  "lock held by a live run: exit 7" 7 "$RC"
eq  "lock held: nothing done" "" "$(grep -E '^niwa dispatch|record write' "$ST/calls.log")"
kill "$HOLDER" >/dev/null 2>&1
wait "$HOLDER" >/dev/null 2>&1
run >/dev/null 2>&1; RC=$?
eq  "stale lock (owner gone): taken over" 0 "$RC"
[ -e "$W/.niwa/dispatch-briefs/.plugin-api.lock" ] && bad "lock: released after the run" "" || ok "lock: released after the run"

reset "$INPUT_DELIVER"
export RECORD_WRITE_MODE=refuse
run >/dev/null 2>&1; RC=$?
eq  "record refuses the write-ahead: exit 8" 8 "$RC"
eq  "record refuses: no launch" 0 "$(grep -c '^niwa dispatch' "$ST/calls.log")"

# A full record (exit 13) is reported as one, not as a generic write failure.
reset "$INPUT_DELIVER"
export RECORD_WRITE_MODE=full
run >/dev/null 2>"$T/full.err"; RC=$?
eq  "a full record: the dispatch stops, exit 2" 2 "$RC"
grep -q "record-full" "$T/full.err" && ok "a full record: it says record-full" || bad "a full record: it says record-full" "$(cat "$T/full.err")"
eq  "a full record: no launch" 0 "$(grep -c "^niwa dispatch" "$ST/calls.log")"

# The record changing between the writer's read and its write (exit 12) is
# retried; a record that keeps changing is a failed write, before any launch.
reset "$INPUT_DELIVER"
export RECORD_WRITE_MODE=changed-once
run >/dev/null 2>&1; RC=$?
eq  "record changed once: the write is retried and the dispatch goes on" 0 "$RC"
eq  "record changed once: dispatched" dispatched "$(row dispatch_status)"
reset "$INPUT_DELIVER"
export RECORD_WRITE_MODE=changed
run >/dev/null 2>&1; RC=$?
eq  "record keeps changing: exit 2" 2 "$RC"
eq  "record keeps changing: three tries" 3 "$(grep -c 'record write plugin-api dispatching' "$ST/calls.log")"
eq  "record keeps changing: no launch" 0 "$(grep -c '^niwa dispatch' "$ST/calls.log")"

reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.checkpoints = ["Wait for approval."]')"
run >/dev/null 2>&1; RC=$?
eq  "refused brief: exit 1" 1 "$RC"
eq  "refused brief: nothing written or launched" "" "$(grep -E '^niwa dispatch|record write|koto request' "$ST/calls.log")"

# --- --rebrief -------------------------------------------------------------------------------------------

reset "$INPUT_DELIVER"
run >/dev/null 2>&1
jq -c '.dispatched = "2000-01-01"' "$ST/rows/plugin-api.json" >"$ST/r" && mv "$ST/r" "$ST/rows/plugin-api.json"
printf 'plugin-api' >"$ST/ctx/report_topic"
jq -c '.goal = "The plugin API ships, and the loader tolerates a missing manifest." | .repo = "evil/elsewhere"' "$ST/ctx/brief_input.json" >"$ST/b" && mv "$ST/b" "$ST/ctx/brief_input.json"
: >"$ST/calls.log"
OUT=$(run --rebrief 2>/dev/null); RC=$?
eq  "rebrief: exit 0" 0 "$RC"
has "rebrief: prints the brief" "$OUT" "brief=$W/.niwa/dispatch-briefs/plugin-api.md"
eq  "rebrief: no launch" 0 "$(grep -c '^niwa dispatch' "$ST/calls.log")"
B=$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")
has "rebrief: new goal" "$B" "tolerates a missing manifest"
has "rebrief: repository from the row, not the input" "$B" "in acme/widgets"
lacks "rebrief: the input's repository ignored" "$B" "evil/elsewhere"
eq  "rebrief: row still dispatched" dispatched "$(row dispatch_status)"
eq  "rebrief: row's date updated" "$(date -u +%Y-%m-%d)" "$(row dispatched)"

jq -c '.run_mode = "--interactive"' "$ST/ctx/brief_input.json" >"$ST/b" && mv "$ST/b" "$ST/ctx/brief_input.json"
run --rebrief >/dev/null 2>&1; RC=$?
eq  "rebrief: flags differing in the input: exit 0" 0 "$RC"
has "rebrief: the flags come from the holding, not the input" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" '`/shirabe:deliver plugin-api --auto --no-merge`'

reset "$INPUT_SCOPE"
run >/dev/null 2>&1
printf 'plugin-api' >"$ST/ctx/report_topic"
: >"$ST/calls.log"
run --rebrief >/dev/null 2>&1; RC=$?
eq  "rebrief, leg-bound: exit 0" 0 "$RC"
eq  "rebrief, leg-bound: the holding moves to the message path" message "$(row return_path)"
has "rebrief, leg-bound: the spent request is abandoned" "$(calls)" "koto request abandon-request req_1"
lacks "rebrief, leg-bound: the brief no longer names the leg" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" "--koto-leg"

# --- a lock left with no pid ---------------------------------------------------------------------------

reset "$INPUT_DELIVER"
mkdir -p "$W/.niwa/dispatch-briefs/.plugin-api.lock"
ERR=$(run 2>&1 >/dev/null); RC=$?
eq  "pid-less lock, fresh: exit 7" 7 "$RC"
has "pid-less lock, fresh: says no pid" "$ERR" "pid not yet written"
touch -t 200001010000 "$W/.niwa/dispatch-briefs/.plugin-api.lock"
run >/dev/null 2>&1; RC=$?
eq  "pid-less lock, over a minute old: taken over" 0 "$RC"

# --- the record's script missing -------------------------------------------------------------------------

reset "$INPUT_DELIVER"
ERR=$(cd "$W/inst" && DC_RECORD_HOLDING="$T/absent.sh" bash "$S" --session coord 2>&1 >/dev/null); RC=$?
eq  "no record script: exit 2" 2 "$RC"
has "no record script: says so" "$ERR" "record-holding.sh is not installed"
eq  "no record script: nothing launched" 0 "$(grep -c '^niwa dispatch' "$ST/calls.log")"

# --- holding-recorded.sh ----------------------------------------------------------------------------------

gate() { bash "$G" --session coord >/dev/null 2>&1; echo $?; }
reset "$INPUT_DELIVER"
eq  "gate: no holding is 1" 1 "$(gate)"
printf 'I claim plugin-api is recorded\n' >"$ST/ctx/holding_recorded"
eq  "gate: a context claim doesn't satisfy it" 1 "$(gate)"
printf '{"dispatch_status":"dispatching"}' >"$ST/rows/plugin-api.json"
eq  "gate: dispatching is 4" 4 "$(gate)"
printf '{"dispatch_status":"dispatch-failed"}' >"$ST/rows/plugin-api.json"
eq  "gate: dispatch-failed is 3" 3 "$(gate)"
printf '{"dispatch_status":"dispatched"}' >"$ST/rows/plugin-api.json"
eq  "gate: dispatched is 0" 0 "$(gate)"
printf 'other' >"$ST/ctx/dispatch_topic"
eq  "gate: reads dispatch_topic, not an earlier topic's row" 1 "$(gate)"
printf 'plugin-api' >"$ST/ctx/dispatch_topic"
export RECORD_READ_MODE=refuse
eq  "gate: a refused read is 2" 2 "$(gate)"
export RECORD_READ_MODE=fail
eq  "gate: a failed read is 2" 2 "$(gate)"
unset RECORD_READ_MODE
rm -f "$ST/ctx/dispatch_topic"
eq  "gate: no dispatch_topic is 2" 2 "$(gate)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

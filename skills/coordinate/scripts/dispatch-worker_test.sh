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
# refused by the lock; a mismatched topic; the record refusing a write, and a
# write ending in exit 13 (no verdict now) a plain failed write;
# --rebrief; a review-level bound in the prompt and the brief, kept out of
# the holding's mode and given once on a re-brief; --releg replacing a spent leg (and refusing an open one, a
# promoted one, a holding with a pull request); send_execution rewriting a
# scoping-ahead holding with a new leg and the execution's entry point,
# mode and phase; no session id, instance path or job id in the holding; the
# leg key written open at dispatch (and a dispatch stopped when it can't be),
# spent on a failed launch, replaced by --releg; a stranded unit dispatched
# under a new topic whose brief names the old branch and pushed head, the
# stranded row retired after, and the stranded topic itself refused;
# --releg-imported re-attaching an imported worker, finishing after a crash at
# each step with one binding, and refusing each case the design names with
# nothing left half-done; and every exit code of holding-recorded.sh. Each
# path that moves a worker to the message path (a re-brief, a leg-bound one
# included; a re-brief after a leg was found unwatchable, from the importing
# run; an execution sent to an entry point with no leg) renders a brief whose
# dispatcher_session is the run that rendered it, with the link command
# --dispatched-by filled in; an execution sent on a leg carries none.
# A confirmed launch sends one `dispatched` event whose arguments a stand-in
# for scripts/emit-event.sh records (from niwa's output on a launch, from the
# listing row on a resumed run, without a leg on the message path); a re-run,
# a re-brief and a failed launch send none; and a helper that exits non-zero
# or is missing leaves the exit code, stdout and stderr as they were. The
# scripts run from a copy of the skill laid out as the repository is, so no
# case reaches the repository's own helper.
#
# Usage: bash skills/coordinate/scripts/dispatch-worker_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs jq. bash 3.2.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-worker-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'case "$T" in */dispatch-worker-test.*) rm -rf "$T" ;; esac'

# The scripts run from a copy of the skill under $T/plugin, laid out as the
# repository is, so the dispatched event reaches the stand-in helper at
# $T/plugin/scripts/emit-event.sh (below), never the repository's.
DW="$T/plugin"
mkdir -p "$DW/skills/coordinate/scripts" "$DW/scripts"
cp "$HERE"/*.sh "$HERE"/*.jq "$DW/skills/coordinate/scripts/" || exit 1
cp -R "$HERE/../references" "$HERE/../koto-templates" "$DW/skills/coordinate/" || exit 1
S="$DW/skills/coordinate/scripts/dispatch-worker.sh"
G="$DW/skills/coordinate/scripts/holding-recorded.sh"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }
has() { if grep -Fq -- "$3" <<<"$2"; then ok "$1"; else bad "$1" "missing [$3] in [$2]"; fi; }
lacks() { if grep -Fq -- "$3" <<<"$2"; then bad "$1" "unexpected [$3]"; else ok "$1"; fi; }

# --- stand-ins ------------------------------------------------------------------------
#
# State lives under $ST: ctx/<key> for the session's context, rows/<topic>.json
# for the record, sessions.json for niwa's listing, calls.log for every call.

BIN="$T/bin"
mkdir -p "$BIN"
export ST="$T/state"

# A key with slashes (the legs/<request>/<leg> keys) is a file under
# directories. Leg-key writes aren't logged to calls.log, whose order the
# launch cases read; KOTO_LEG_PUT_FAIL=1 fails them.
cat >"$BIN/koto" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "context get")
        [ -f "$ST/ctx/$4" ] || exit 1
        cat "$ST/ctx/$4"
        ;;
    "context add")
        case "$4" in legs/*) [ "${KOTO_LEG_PUT_FAIL:-}" = 1 ] && exit 1 ;; esac
        mkdir -p "$(dirname "$ST/ctx/$4")"
        if [ "${5-}" = --from-file ]; then cat "$6" >"$ST/ctx/$4"; else cat >"$ST/ctx/$4"; fi
        ;;
    "context list")
        p=""; [ "${4-}" = --prefix ] && p=$5
        (cd "$ST/ctx" && find . -type f | sed 's#^\./##') | awk -v p="$p" 'index($0, p) == 1' | jq -R . | jq -sc .
        ;;
    "session list")
        if [ -f "$ST/koto_sessions.json" ]; then cat "$ST/koto_sessions.json"; else echo '[]'; fi
        ;;
    "request attach")
        echo "koto $*" >>"$ST/calls.log"
        [ "${KOTO_ATTACH_FAIL:-}" = 1 ] && { echo '{"error":"template-mismatch"}'; exit 1; }
        # --session <child> <request> <leg>
        jq -c --arg l "$6" --arg c "$4" '.legs[$l].bound_child = $c' "$ST/requests/$5.json" >"$ST/r.tmp" && mv "$ST/r.tmp" "$ST/requests/$5.json"
        ;;
    "request create")
        echo "koto request create $*" >>"$ST/calls.log"
        [ "${KOTO_CREATE_FAIL:-}" = 1 ] && exit 1
        n=$(( $(cat "$ST/req_n" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$ST/req_n"
        # Kept as the request's view when the case keeps requests (requests/).
        if [ -d "$ST/requests" ]; then
            jq -c --arg id "req_$n" '{request_id: $id, request_state: "open", legs: (.legs | map({key: .name, value: (. + {disposition: "open", bound_child: null})}) | from_entries)}' <<<"$4" >"$ST/requests/req_$n.json"
        fi
        printf '{"request_id":"req_%s"}\n' "$n"
        ;;
    "request get")
        echo "koto request get $3" >>"$ST/calls.log"
        # A request of its own under requests/ (the re-leg cases), else the
        # one shared answer.
        [ -f "$ST/requests/$3.json" ] && { cat "$ST/requests/$3.json"; exit 0; }
        [ -f "$ST/request_get.rc" ] && exit "$(cat "$ST/request_get.rc")"
        [ -f "$ST/request_get.json" ] || exit 2
        cat "$ST/request_get.json"
        ;;
    "session dir")
        printf '%s\n' "$ST/session"
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
        # NIWA_HELP picks the niwa being stood in for: `lineage` lists
        # --brief and --skill, `old` predates them, `fail` can't print help.
        # `grant` adds --grant and --parent-from to `lineage`.
        if [ "${2:-}" = --help ]; then
            case "${NIWA_HELP:-lineage}" in
                lineage) printf 'Flags:\n      --brief string\n      --detach\n      --name string\n      --skill string\n' ;;
                grant) printf 'Flags:\n      --brief string\n      --detach\n      --grant strings\n      --name string\n      --parent-from string\n      --skill string\n' ;;
                old) printf 'Flags:\n      --detach\n      --name string\n' ;;
                fail) exit 1 ;;
            esac
            exit 0
        fi
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
            # niwa's never-wider refusal, before any instance exists.
            refuse-wider)
                echo "niwa: error: authority close-issue (requested by --grant) is wider than the dispatcher's grant: the dispatcher holds merge-pr (dispatch d1)" >&2
                exit 1
                ;;
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

cat >"$T/state-holding.sh" <<'EOF'
#!/usr/bin/env bash
READ=0; LIST=0; RETIRE=0; TOPIC=""; ROWF=""; SESSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --read) READ=1; shift ;;
        --list) LIST=1; shift ;;
        --retire) RETIRE=1; shift ;;
        --topic) TOPIC="$2"; shift 2 ;;
        --row-file) ROWF="$2"; shift 2 ;;
        --session) SESSION="$2"; shift 2 ;;
        *) exit 64 ;;
    esac
done
[ -n "$SESSION" ] || exit 64
if [ "$LIST" = 1 ]; then
    [ "${RECORD_READ_MODE:-}" = refuse ] && exit 10
    [ "${RECORD_READ_MODE:-}" = fail ] && exit 2
    cat "$ST"/rows/*.json 2>/dev/null | jq -sc .
    exit 0
fi
if [ "$RETIRE" = 1 ]; then
    echo "record retire $TOPIC" >>"$ST/calls.log"
    [ "$(jq -r .dispatch_status "$ST/rows/$TOPIC.json" 2>/dev/null)" = stranded ] || exit 65
    rm -f "$ST/rows/$TOPIC.json"
    exit 0
fi
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
chmod +x "$BIN/koto" "$BIN/niwa" "$T/state-holding.sh"
export PATH="$BIN:$PATH"
export DC_RECORD_HOLDING="$T/state-holding.sh"
# state-stored-set.sh: the Run section names the coordinator's address,
# lane-coord, unless RECORD_ADDRESS sets another or is empty; the Work rows
# are RECORD_WORK's (a JSON array), none by default. Every call but --list is
# logged as `state-stored-set <args>`; RECORD_DONE_MODE=fail fails a --done.
cat >"$T/state-stored-set.sh" <<'EOF'
#!/usr/bin/env bash
[ "${RECORD_STATE_MODE:-}" = fail ] && exit 2
if [ "${1-}" != --list ]; then
    printf 'state-stored-set %s\n' "$*" >>"$ST/calls.log"
    [ "${RECORD_DONE_MODE:-}" = fail ] && { echo "state-stored-set: the record changed" >&2; exit 12; }
    exit 0
fi
jq -nc --arg a "${RECORD_ADDRESS-lane-coord}" --argjson w "${RECORD_WORK:-[]}" '{run: (if $a == "" then [] else [{key: "coordinator", value: $a, set_by: "lane-coord", set: "2026-09-26T08:00Z"}] end), standing: [], work: $w}'
EOF
chmod +x "$T/state-stored-set.sh"
export DC_RECORD_STATE="$T/state-stored-set.sh"
# The event helper's stand-in: each call's arguments, one per line and then
# `--`, appended to $ST/emit.calls; it prints on both streams and exits with
# $ST/emit.rc (0 without it), all of which the caller must ignore.
cat >"$DW/scripts/emit-event.sh" <<'EOF'
#!/usr/bin/env bash
{ printf '%s\n' "$@"; echo --; } >>"$ST/emit.calls"
echo "emit-event stand-in: stdout"
echo "emit-event stand-in: stderr" >&2
exit "$(cat "$ST/emit.rc" 2>/dev/null || echo 0)"
EOF

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
# What pick_facts listed (coord/pick.json): the unit must be a form pick reads
# as covering one of these.
PICK_ROADMAP='{"scope":"roadmap","name":"plugin-system","units":[
  {"unit":"Feature 1","number":1,"title":"the manifest"},{"unit":"Feature 2","number":2,"title":"the plugin API"}]}'
INPUT_SCOPE=$(printf '%s' "$INPUT_DELIVER" | jq -c '.entry_point = "scope" | .entry_args = ["plugin-api", "--intent=continue"]')

reset() {
    rm -rf "$ST"
    mkdir -p "$ST/ctx/coord" "$ST/rows"
    printf '[]\n' >"$ST/sessions.json"
    : >"$ST/calls.log"
    printf '%s' "$1" >"$ST/ctx/brief_input.json"
    printf '%s' "${2:-plugin-api}" >"$ST/ctx/dispatch_topic"
    printf '%s' "$PICK_ROADMAP" >"$ST/ctx/coord/pick.json"
    rm -rf "$W/.niwa/dispatch-briefs"
    export NIWA_MODE=ok NIWA_NAME=plugin_api-1a2b3c4d
    unset NIWA_LIST_FAIL KOTO_CREATE_FAIL RECORD_READ_MODE RECORD_WRITE_MODE DISPATCH_DEADLINE_SECS NIWA_HELP RECORD_ADDRESS RECORD_STATE_MODE RECORD_WORK RECORD_DONE_MODE KOTO_LEG_PUT_FAIL KOTO_ATTACH_FAIL
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
lacks "fresh: no rework row, no removal" "$(calls)" "state-stored-set --session"

# --- a milestone a changes-needed verdict sent back -----------------------------------------
# Its rework row is quoted into the brief and removed once the dispatch is
# confirmed; a failed removal is reported and the dispatch still succeeds.
REWORK_ROWS='[{"item":"Feature 2","kind":"rework","who":"verdict 1001","next":"Evidence clauses not held: 2. Changes needed: name the skipped plugin","wakes":"0","updated":"2026-09-26T07:00Z"},{"item":"Feature 1","kind":"rework","who":"verdict 1002","next":"Changes needed: other","wakes":"0","updated":"2026-09-26T07:00Z"}]'
reset "$INPUT_DELIVER"
printf '%s' "$PICK_ROADMAP" | jq -c '.units |= map(if .unit == "Feature 2" then .rework = "Evidence clauses not held: 2. Changes needed: name the skipped plugin" else . end)' >"$ST/ctx/coord/pick.json"
export RECORD_WORK="$REWORK_ROWS"
OUT=$(run 2>"$T/rw.err"); RC=$?
eq  "rework: dispatched" "0 session=$NIWA_NAME" "$RC $OUT"
has "rework: the brief quotes the verdict's report" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" "> Evidence clauses not held: 2. Changes needed: name the skipped plugin"
has "rework: the unit's rework row is removed" "$(calls)" "state-stored-set --session coord --done Feature 2 --kind rework"
lacks "rework: and no other unit's" "$(calls)" "--done Feature 1"
RM_AT=$(grep -n 'state-stored-set --session coord --done' "$ST/calls.log" | head -1 | cut -d: -f1)
LAST_WRITE=$(grep -n 'record write plugin-api dispatched' "$ST/calls.log" | tail -1 | cut -d: -f1)
if [ -n "$RM_AT" ] && [ -n "$LAST_WRITE" ] && [ "$RM_AT" -gt "$LAST_WRITE" ]; then ok "rework: removed after the holding reads dispatched"; else bad "rework: removed after the holding reads dispatched" "$(calls)"; fi
reset "$INPUT_DELIVER"
export RECORD_WORK="$REWORK_ROWS" RECORD_DONE_MODE=fail
OUT=$(run 2>"$T/rw.err"); RC=$?
eq  "rework: a failed removal still dispatches" "0 session=$NIWA_NAME" "$RC $OUT"
has "rework: and says how to remove the row" "$(cat "$T/rw.err")" 'remove it with state-stored-set.sh --session coord --done "Feature 2" --kind rework'
reset "$INPUT_DELIVER"
export RECORD_WORK="$REWORK_ROWS"
NIWA_MODE=fail; export NIWA_MODE
run >/dev/null 2>&1
lacks "rework: a failed launch removes nothing" "$(calls)" "state-stored-set --session"
# The fresh dispatch again, which the re-run below starts from.
reset "$INPUT_DELIVER"
run >/dev/null 2>&1

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

# --- the worker's lineage flags ------------------------------------------------------------

# A niwa that takes them gets the brief and the entry point's skill.
reset "$INPUT_SCOPE"
run >/dev/null 2>&1
LAUNCHED=$(grep '^niwa dispatch' "$ST/calls.log")
has "lineage: --skill names the entry point's skill" "$LAUNCHED" "[--skill] [shirabe:scope]"
has "lineage: --brief names the brief file" "$LAUNCHED" "[--brief] [$W/.niwa/dispatch-briefs/plugin-api.md]"
[ -f "$W/.niwa/dispatch-briefs/plugin-api.md" ] && ok "lineage: the brief exists at launch" || bad "lineage: the brief exists at launch" ""

# A niwa that predates them, or whose help can't be read, launches exactly as
# before.
for help in old fail; do
    reset "$INPUT_SCOPE"
    export NIWA_HELP=$help
    run >/dev/null 2>&1; RC=$?
    eq  "lineage ($help help): exit 0" 0 "$RC"
    LAUNCHED=$(grep '^niwa dispatch' "$ST/calls.log")
    lacks "lineage ($help help): no --brief" "$LAUNCHED" "[--brief]"
    lacks "lineage ($help help): no --skill" "$LAUNCHED" "[--skill]"
    case "$LAUNCHED" in
        *" [--name] [plugin-api] [--detach]") ok "lineage ($help help): the launch ends as before" ;;
        *) bad "lineage ($help help): the launch ends as before" "$LAUNCHED" ;;
    esac
done

# --- the worker's grant ------------------------------------------------------------------

BRIEF_FILE="$W/.niwa/dispatch-briefs/plugin-api.md"
named() { grep '^Named authority:' "$BRIEF_FILE"; }

# A worker the brief hands a merge: --grant merge-pr and nothing wider, the
# coordinator's own instance as --parent-from, and a brief that names exactly
# merge-pr.
reset "$(jq -c '.grant = ["merge-pr"]' <<<"$INPUT_DELIVER")"
export NIWA_HELP=grant
OUT=$(run 2>"$T/err"); RC=$?
eq  "grant: exit 0" "0 session=$NIWA_NAME" "$RC $OUT"
LAUNCHED=$(grep '^niwa dispatch' "$ST/calls.log")
has "grant: --grant merge-pr" "$LAUNCHED" "[--grant] [merge-pr]"
eq  "grant: one --grant" 1 "$(grep -o '\[--grant\]' <<<"$LAUNCHED" | wc -l | tr -d ' ')"
has "grant: --parent-from names the coordinator's own instance" "$LAUNCHED" "[--parent-from] [$W/inst]"
eq  "grant: the brief names merge-pr and nothing else" "Named authority: you hold merge-pr and nothing else. A merge, close or release that needs an authority you don't hold isn't yours to take: hand it back to the coordinator in a report, and don't reach the same result another way." "$(named)"
lacks "grant: the brief names no other authority" "$(cat "$BRIEF_FILE")" "close-issue"

# A worker the brief hands no landing step: no --grant at all, and a brief that
# says it holds none. An empty list reads the same.
for g in absent empty; do
    if [ "$g" = absent ]; then reset "$INPUT_DELIVER"; else reset "$(jq -c '.grant = []' <<<"$INPUT_DELIVER")"; fi
    export NIWA_HELP=grant
    run >/dev/null 2>&1; RC=$?
    eq  "no landing step ($g): exit 0" 0 "$RC"
    LAUNCHED=$(grep '^niwa dispatch' "$ST/calls.log")
    lacks "no landing step ($g): no --grant" "$LAUNCHED" "[--grant]"
    has "no landing step ($g): --parent-from still" "$LAUNCHED" "[--parent-from] [$W/inst]"
    has "no landing step ($g): the brief says it holds none" "$(named)" "Named authority: you hold no named authority."
done

# A niwa whose dispatch help lacks --grant: dispatched without one, and the
# brief says the worker holds none.
for help in lineage old; do
    reset "$(jq -c '.grant = ["merge-pr"]' <<<"$INPUT_DELIVER")"
    export NIWA_HELP=$help
    run >/dev/null 2>"$T/err"; RC=$?
    eq  "old niwa ($help): exit 0" 0 "$RC"
    LAUNCHED=$(grep '^niwa dispatch' "$ST/calls.log")
    lacks "old niwa ($help): no --grant" "$LAUNCHED" "[--grant]"
    lacks "old niwa ($help): no --parent-from" "$LAUNCHED" "[--parent-from]"
    has "old niwa ($help): the brief says it holds none" "$(named)" "Named authority: you hold no named authority."
    has "old niwa ($help): says why" "$(cat "$T/err")" "takes no --grant"
done

# A successor (entry point coordinate, grant `own`) gets this coordinator's
# own grant as niwa authority check reported it to posture-read.sh.
INPUT_SUCCESSOR=$(jq -c '.entry_point = "coordinate" | .entry_args = ["plugin-api"] | .run_mode = "" | .grant = "own"' <<<"$INPUT_DELIVER")
reset "$INPUT_SUCCESSOR"
export NIWA_HELP=grant
printf '%s' '{"token":"readable merge:permit close:permit teardown:confirm release:confirm","grant_check":{"lookup":"answered","state":"bound","binding":"mapping","level":"autonomous","grant":["merge-pr","close-issue"],"parent":{"instance":"ws+root-coord"}}}' >"$ST/ctx/coord/posture.json"
run >/dev/null 2>&1; RC=$?
eq  "successor: exit 0" 0 "$RC"
LAUNCHED=$(grep '^niwa dispatch' "$ST/calls.log")
has "successor: --grant close-issue" "$LAUNCHED" "[--grant] [close-issue]"
has "successor: --grant merge-pr" "$LAUNCHED" "[--grant] [merge-pr]"
lacks "successor: nothing it doesn't hold" "$LAUNCHED" "[cut-release]"
has "successor: the brief names its grant" "$(named)" "Named authority: you hold close-issue, merge-pr and nothing else."
# A coordinator niwa didn't dispatch holds nothing to pass on.
reset "$INPUT_SUCCESSOR"
export NIWA_HELP=grant
printf '%s' '{"grant_check":{"lookup":"answered","state":"not-dispatched","reason":"no-mapping","grant":[]}}' >"$ST/ctx/coord/posture.json"
run >/dev/null 2>&1; RC=$?
eq  "successor, root: exit 0" 0 "$RC"
lacks "successor, root: no --grant" "$(grep '^niwa dispatch' "$ST/calls.log")" "[--grant]"
has "successor, root: the brief says it holds none" "$(named)" "Named authority: you hold no named authority."
reset "$INPUT_SUCCESSOR"
export NIWA_HELP=grant
run >/dev/null 2>"$T/err"; RC=$?
eq  "successor, no posture: exit 0" 0 "$RC"
lacks "successor, no posture: no --grant" "$(grep '^niwa dispatch' "$ST/calls.log")" "[--grant]"
has "successor, no posture: says why" "$(cat "$T/err")" "coord/posture.json can't be read"

# `own` is for a successor only, and a grant names known authorities once
# each: anything else is refused with nothing written or launched.
for bad_grant in '"own"' '["merge"]' '["merge-pr","merge-pr"]' '"merge-pr"'; do
    reset "$(jq -c --argjson g "$bad_grant" '.grant = $g' <<<"$INPUT_DELIVER")"
    export NIWA_HELP=grant
    run >/dev/null 2>"$T/err"; RC=$?
    eq  "refused grant $bad_grant: exit 1" 1 "$RC"
    eq  "refused grant $bad_grant: nothing written or launched" "" "$(grep -E '^niwa dispatch|record write|request create' "$ST/calls.log")"
done

# A grant wider than the coordinator's own: niwa refuses it, and the refusal is
# reported, never retried.
reset "$(jq -c '.grant = ["merge-pr", "close-issue"]' <<<"$INPUT_DELIVER")"
export NIWA_HELP=grant NIWA_MODE=refuse-wider
run >/dev/null 2>"$T/err"; RC=$?
eq  "wider: exit 11" 11 "$RC"
eq  "wider: one launch, no retry" 1 "$(grep -c '^niwa dispatch' "$ST/calls.log")"
has "wider: niwa's refusal is passed on" "$(cat "$T/err")" "is wider than the dispatcher's grant:"
has "wider: reported as niwa's refusal" "$(cat "$T/err")" "report the refusal"
eq  "wider: row dispatch-failed" dispatch-failed "$(row dispatch_status)"
has "wider: the request is abandoned" "$(calls)" "koto request abandon-request req_1"
# Any other failure stays exit 4.
reset "$(jq -c '.grant = ["merge-pr"]' <<<"$INPUT_DELIVER")"
export NIWA_HELP=grant NIWA_MODE=fail
run >/dev/null 2>&1; RC=$?
eq  "grant, other failure: exit 4" 4 "$RC"

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

# So does a charter (shirabe#1290), and its brief records the dispatcher itself.
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.entry_point = "charter" | .entry_args = ["plugin-api"] | .run_mode = "--auto"')"
OUT=$(run 2>/dev/null); RC=$?
eq  "charter: dispatched" "0 session=$NIWA_NAME" "$RC $OUT"
lacks "charter: no request opened" "$(calls)" "koto request create"
eq  "charter: return path" message "$(row return_path)"
eq  "charter: one launch" 1 "$(grep -c '^niwa dispatch' "$ST/calls.log")"
lacks "charter: the invocation carries no leg" "$(cat "$ST/prompt")" "--koto-leg"
has "charter: the prompt runs charter" "$(cat "$ST/prompt")" "/shirabe:charter plugin-api --auto"
eq  "charter: the brief names the run that rendered it as its dispatcher" "dispatcher_session: coord" \
    "$(grep '^dispatcher_session:' "$W/.niwa/dispatch-briefs/plugin-api.md")"
has "charter: the brief records it with link-dispatcher.sh" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" "link-dispatcher.sh\" <session> --dispatched-by coord\`"

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

# --- the unit must be one pick can find ----------------------------------------------------------------
# A holding whose Unit cell pick can't read leaves its unit dispatchable twice,
# so such a unit is refused before anything is written.

nothing_written() { # nothing_written <label>
    eq  "$1: no record write" 0 "$(grep -c 'record write' "$ST/calls.log")"
    eq  "$1: no leg" 0 "$(grep -c 'request create' "$ST/calls.log")"
    eq  "$1: no launch" 0 "$(grep -c '^niwa dispatch' "$ST/calls.log")"
    [ -e "$W/.niwa/dispatch-briefs/plugin-api.md" ] && bad "$1: no brief" || ok "$1: no brief"
}
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "Feature 2 of ROADMAP-plugin-system"')"
ERR=$(run 2>&1 >/dev/null); RC=$?
eq  "unit: the old template's example form is refused" 1 "$RC"
has "unit: the refusal names the unit" "$ERR" "unit: [Feature 2 of ROADMAP-plugin-system] matches no unit pick listed"
has "unit: and the forms that would match" "$ERR" '"Feature 2", "Feature 2: the plugin API"'
nothing_written "unit"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "Feature 2: the plugin api"')"
run >/dev/null 2>&1; eq "unit: a title that differs, even in case, is refused" 1 "$?"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "Feature 9"')"
run >/dev/null 2>&1; eq "unit: a feature the roadmap doesn't list is refused" 1 "$?"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "Feature 2"')"
run >/dev/null 2>&1; eq "unit: the bare tag is taken" 0 "$?"
eq  "unit: and becomes the Unit cell" "Feature 2" "$(row unit)"
reset "$INPUT_DELIVER"
rm -f "$ST/ctx/coord/pick.json"
run >/dev/null 2>&1; eq "unit: no coord/pick.json to check against exits 2" 2 "$?"
nothing_written "unit, no pick facts"
# A unit pick marked paused: refused before anything is written.
reset "$INPUT_DELIVER"
printf '%s' "$PICK_ROADMAP" | jq -c '(.units[] | select(.unit == "Feature 2")).paused = "s4"' >"$ST/ctx/coord/pick.json"
ERR=$(run 2>&1 >/dev/null); RC=$?
eq  "pause: a new dispatch of a unit pick marked paused exits 10" 10 "$RC"
has "pause: naming the pause and the value to submit" "$ERR" "pause s4 holds this unit"
nothing_written "pause, unit"
# A roadmap moved to roadmap/v3: pick lists `Milestone N`, and a pause written
# on `Feature 2` before the move still holds `Milestone 2`. Each unit's
# `paused` is pause-read.sh's covers for it, as pick-facts.sh sets it.
jq -nc '{standing: [{standing: "s4", kind: "pause", on: "Feature 2", until: "lifted", what: "x", owner: "the human", relayed_by: "", set: "2026-10-01T19:37Z"}]}' >"$W/v3-standing.json"
jq -nc '["Milestone 1", "Milestone 2"]' >"$W/v3-units.json"
bash "$HERE/pause-read.sh" --standing "$W/v3-standing.json" --units "$W/v3-units.json" >"$W/v3-pauses.json"
PICK_V3=$(printf '%s' "$PICK_ROADMAP" | jq -c --slurpfile p "$W/v3-pauses.json" '.units |= map(.unit |= sub("^Feature "; "Milestone ") | .paused = $p[0].covers[.unit])')
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "Milestone 2: the plugin API"')"
printf '%s' "$PICK_V3" >"$ST/ctx/coord/pick.json"
ERR=$(run 2>&1 >/dev/null); RC=$?
eq  "pause: on v3, a pause written on Feature 2 refuses a new dispatch of Milestone 2 (10)" 10 "$RC"
has "pause: ... naming that pause" "$ERR" "pause s4 holds this unit"
nothing_written "pause, v3 unit"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "Milestone 1"')"
printf '%s' "$PICK_V3" >"$ST/ctx/coord/pick.json"
run >/dev/null 2>&1; eq "pause: ... and doesn't hold Milestone 1" 0 "$?"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "Feature 1"')"
printf '%s' "$PICK_ROADMAP" | jq -c '.paused_all = "s5" | .units[0].paused = "s5" | .units[1].paused = "s5"' >"$ST/ctx/coord/pick.json"
run >/dev/null 2>&1; eq "pause: under a pause on all any new dispatch exits 10" 10 "$?"
nothing_written "pause, all"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "Feature 1"')"
printf '%s' "$PICK_ROADMAP" | jq -c '(.units[] | select(.unit == "Feature 2")).paused = "s4"' >"$ST/ctx/coord/pick.json"
run >/dev/null 2>&1; eq "pause: another unit's pause doesn't hold this one" 0 "$?"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "Feature 1"')"
printf '%s' "$PICK_ROADMAP" | jq -c '.paused_all = "s5" | .units[0].paused = null | .units[1].paused = "s5"' >"$ST/ctx/coord/pick.json"
run >/dev/null 2>&1; eq "pause: under a pause on all, the unit a go-ahead let through (paused null) is dispatched" 0 "$?"
# A milestone whose verdict is owed is never dispatched, held or not.
reset "$INPUT_DELIVER"
printf '%s' "$PICK_ROADMAP" | jq -c '(.units[] | select(.unit == "Feature 2")).verdict_owed = true' >"$ST/ctx/coord/pick.json"
ERR=$(run 2>&1 >/dev/null); RC=$?
eq  "verdict owed: a new dispatch of a unit pick marked verdict_owed exits 10" 10 "$RC"
has "verdict owed: naming why and the value to submit" "$ERR" "a verdict is owed on this milestone"
nothing_written "verdict owed, unit"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "Feature 1"')"
printf '%s' "$PICK_ROADMAP" | jq -c '(.units[] | select(.unit == "Feature 2")).verdict_owed = true' >"$ST/ctx/coord/pick.json"
run >/dev/null 2>&1; eq "verdict owed: another unit's owed verdict doesn't hold this one" 0 "$?"
# The brief's reporting address is the record's Run coordinator, never the
# koto session name the input carries (shirabe#610).
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.reports_to = "someone-else"')"
run >/dev/null 2>&1; eq "address: a dispatch with the record's address goes through" 0 "$?"
has "address: the brief names the record's address" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" 'addressed to `lane-coord`, the address its record names'
lacks "address: never the input's own value" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" 'someone-else'
lacks "address: nor the koto session name" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" 'addressed to `coord-alpha`'
reset "$INPUT_DELIVER"; export RECORD_ADDRESS=""
ERR=$(run 2>&1 >/dev/null); RC=$?
eq  "address: a record naming no address refuses, exit 1" 1 "$RC"
has "address: naming the fix" "$ERR" "state-stored-set.sh --session coord --run coordinator <address>"
nothing_written "address, none"
reset "$INPUT_DELIVER"; export RECORD_STATE_MODE=fail
run >/dev/null 2>&1; eq "address: a Run section that can't be read exits 2" 2 "$?"
nothing_written "address, unreadable"
# A unit a person assigned at roadmap scope (shirabe#607): pick lists it with
# `assigned`, and its id is a form the brief check takes.
PICK_ASSIGNED='{"scope":"roadmap","name":"plugin-system","host":"acme/widgets","units":[
  {"unit":"Feature 1","number":1,"title":"the manifest"},
  {"unit":"acme/widgets#591","number":591,"title":"pick the review level up front","assigned":"s3"},
  {"unit":"release acme/widgets v0.25.0","number":null,"title":"","assigned":"s4"}]}'
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "acme/widgets#591" | .entry_point = "work-on" | .entry_args = ["591"]')"
printf '%s' "$PICK_ASSIGNED" >"$ST/ctx/coord/pick.json"
run >/dev/null 2>&1; eq "assigned: an issue a person assigned is dispatched at roadmap scope" 0 "$?"
eq  "assigned: and becomes the Unit cell" "acme/widgets#591" "$(row unit)"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "acme/widgets#591: pick the review level up front" | .entry_point = "work-on" | .entry_args = ["591"]')"
printf '%s' "$PICK_ASSIGNED" >"$ST/ctx/coord/pick.json"
run >/dev/null 2>&1; eq "assigned: its id with a title, a form pick doesn't read for it, is refused" 1 "$?"
# A release (shirabe#627): no leg, no run mode, the version positional.
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "release acme/widgets v0.25.0" | .entry_point = "release" | .entry_args = ["v0.25.0"] | .run_mode = ""')"
printf '%s' "$PICK_ASSIGNED" >"$ST/ctx/coord/pick.json"
run >/dev/null 2>&1; eq "release: an assigned release is dispatched" 0 "$?"
eq  "release: on the message path, with no leg" "message 0" "$(row return_path) $(grep -c 'request create' "$ST/calls.log")"
eq  "release: its holding names /release and no mode" "release|" "$(row entry_point)|$(row mode)"
eq  "release: the worker is launched" 1 "$(grep -c '^niwa dispatch' "$ST/calls.log")"
has "release: the prompt runs /shirabe:release with the version" "$(cat "$ST/prompt")" 'Run `/shirabe:release v0.25.0` in acme/widgets'
# A unit parked on a decision: refused like a pause, nothing written.
reset "$INPUT_DELIVER"
printf '%s' "$PICK_ROADMAP" | jq -c '(.units[] | select(.unit == "Feature 2")).awaiting = "4"' >"$ST/ctx/coord/pick.json"
ERR=$(run 2>&1 >/dev/null); RC=$?
eq  "park: a unit pick lists as awaiting a decision exits 10" 10 "$RC"
has "park: naming the entry and the value to submit" "$ERR" "decision 4 parks this unit until it is settled"
nothing_written "park"
reset "$INPUT_DELIVER"
printf '%s' "$PICK_ROADMAP" | jq -c '(.units[] | select(.unit == "Feature 2")).answered = {decision: "4", outcome: "go"}' >"$ST/ctx/coord/pick.json"
run >/dev/null 2>&1; eq "park: once answered it is dispatched" 0 "$?"
# A unit whose scoping alone landed: its scoping isn't dispatched again.
FUP='(.units[] | select(.unit == "Feature 2")).follow_up = {after: "acme/widgets#41", next: "/shirabe:execute docs/plans/PLAN-plugin-api.md"}'
for ep in deliver scope; do
    if [ "$ep" = deliver ]; then reset "$INPUT_DELIVER"; else reset "$INPUT_SCOPE"; fi
    printf '%s' "$PICK_ROADMAP" | jq -c "$FUP" >"$ST/ctx/coord/pick.json"
    ERR=$(run 2>&1 >/dev/null); RC=$?
    eq  "follow-up: a /shirabe:$ep brief for a unit whose scoping landed is refused" 1 "$RC"
    has "follow-up: naming its scoping and its execution" "$ERR" "scoping landed as acme/widgets#41; brief its execution (/shirabe:execute docs/plans/PLAN-plugin-api.md)"
    nothing_written "follow-up, $ep"
done
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.entry_point = "execute" | .entry_args = ["docs/plans/PLAN-plugin-api.md"] | .targets = ["acme/widgets"]')"
printf '%s' "$PICK_ROADMAP" | jq -c "$FUP" >"$ST/ctx/coord/pick.json"
run >/dev/null 2>&1; eq "follow-up: its execution is dispatched" 0 "$?"
# Discipline scope: an issue as #n, or as host#n with the host pick recorded.
PICK_DISCIPLINE='{"scope":"discipline","name":"ci-health","host":"acme/widgets","units":[{"unit":"#12","number":12,"title":"flaky upload"}]}'
for u in "#12" "acme/widgets#12"; do
    reset "$(printf '%s' "$INPUT_DELIVER" | jq -c --arg u "$u" '.unit = $u')"
    printf '%s' "$PICK_DISCIPLINE" >"$ST/ctx/coord/pick.json"
    run >/dev/null 2>&1
    eq "unit: discipline issue $u is taken" 0 "$?"
done
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "#13"')"
printf '%s' "$PICK_DISCIPLINE" >"$ST/ctx/coord/pick.json"
ERR=$(run 2>&1 >/dev/null); RC=$?
eq  "unit: an issue pick didn't list is refused" 1 "$RC"
has "unit: naming the issue's forms" "$ERR" '"#12", "acme/widgets#12"'
# A resumed dispatch: its holding already records the unit, so neither the
# unit nor coord/pick.json is checked again, and the run settles the row.
reset "$(printf '%s' "$INPUT_SCOPE" | jq -c '.unit = "Feature 2 of ROADMAP-plugin-system"')"
rm -f "$ST/ctx/coord/pick.json"
printf '%s' '{"dispatch_status":"dispatching","return_path":"leg req_9:scope","worker":"plugin-api","repo":"acme/widgets","mode":"--auto --intent=continue","unit":"Feature 2 of ROADMAP-plugin-system"}' >"$ST/rows/plugin-api.json"
run >/dev/null 2>&1; eq "unit: a resumed dispatch isn't refused on its recorded unit" 0 "$?"
eq  "unit: and its row is settled" dispatched "$(row dispatch_status)"

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

# There's no size budget: exit 13 is no verdict any more, so a write ending
# with it is a plain failed write, never reported as a full record.
reset "$INPUT_DELIVER"
export RECORD_WRITE_MODE=full
run >/dev/null 2>"$T/full.err"; RC=$?
eq  "an unknown write exit: the dispatch stops, exit 2" 2 "$RC"
grep -q "writing the holding for plugin-api failed" "$T/full.err" && ok "an unknown write exit: a plain failed write" || bad "an unknown write exit: a plain failed write" "$(cat "$T/full.err")"
grep -q "record-full" "$T/full.err" && bad "an unknown write exit: no record-full verdict" "$(cat "$T/full.err")" || ok "an unknown write exit: no record-full verdict"
eq  "an unknown write exit: no launch" 0 "$(grep -c "^niwa dispatch" "$ST/calls.log")"

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
rm -f "$ST/ctx/coord/pick.json"
OUT=$(run --rebrief 2>/dev/null); RC=$?
eq  "rebrief: exit 0, with no coord/pick.json to read" 0 "$RC"
has "rebrief: prints the brief" "$OUT" "brief=$W/.niwa/dispatch-briefs/plugin-api.md"
# The worker is on the message path, so the brief names the run that
# rendered it as its dispatcher, not the input's value, with the command
# that records it.
B=$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")
eq  "rebrief: dispatcher_session is the run that rendered it" 1 "$(grep -cx 'dispatcher_session: coord' <<<"$B")"
lacks "rebrief: not the input's dispatcher_session" "$B" "coord-alpha"
has "rebrief: the link command, --dispatched-by filled in" "$B" 'link-dispatcher.sh" <session> --dispatched-by coord`'
has "rebrief: render-result.sh is the report step" "$B" "render-result.sh"
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
has "rebrief, leg-bound: moved to the message path, it carries the link command" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" \
    'link-dispatcher.sh" <session> --dispatched-by coord`'

# A leg reconcile found unwatchable after an import (reconcile-legs.sh): the
# holding reports by message from then on, and the importing run re-briefs
# the worker, whose brief names that run as its dispatcher.
reset "$INPUT_DELIVER"
run >/dev/null 2>&1
jq -c '.return_path = "message"' "$ST/rows/plugin-api.json" >"$ST/r" && mv "$ST/r" "$ST/rows/plugin-api.json"
printf 'plugin-api' >"$ST/ctx/report_topic"
(cd "$W/inst" && bash "$S" --session coordinate-roadmap-plugin-system-20261024T090000Z --rebrief) >/dev/null 2>&1
eq  "unwatchable: the importing run re-briefs the worker" 0 "$?"
B=$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")
has "unwatchable: dispatcher_session is the importing run" "$B" "dispatcher_session: coordinate-roadmap-plugin-system-20261024T090000Z"
has "unwatchable: the link command names it" "$B" '--dispatched-by coordinate-roadmap-plugin-system-20261024T090000Z`'

# --- a review-level bound ---------------------------------------------------------------------------------
#
# The brief and the dispatch prompt name the same command, the bound's flags
# before --koto-leg; the holding's mode stays without them, so a re-brief,
# which rebuilds run_mode from that cell and keeps review_level, gives them
# once.

reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.review_level = {"floor": "standard", "ceiling": "full"}')"
run >/dev/null 2>&1; RC=$?
eq  "review level: dispatched, exit 0" 0 "$RC"
RL_INV='`/shirabe:deliver plugin-api --auto --no-merge --review-floor=standard --review-ceiling=full --koto-leg=req_1:deliver`'
has "review level: the prompt carries the bound before the leg" "$(cat "$ST/prompt")" "$RL_INV"
has "review level: the brief names the same command" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" "$RL_INV"
eq  "review level: the holding's mode leaves the bound out" "--auto --no-merge" "$(row mode)"
printf 'plugin-api' >"$ST/ctx/report_topic"
: >"$ST/calls.log"
run --rebrief >/dev/null 2>&1; RC=$?
eq  "review level: rebrief, exit 0" 0 "$RC"
B=$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")
has "review level: rebrief keeps the bound" "$B" '`/shirabe:deliver plugin-api --auto --no-merge --review-floor=standard --review-ceiling=full`'
eq  "review level: rebrief gives each flag once" 1 "$(printf '%s\n' "$B" | grep -o -- '--review-floor=' | wc -l | tr -d ' ')"
eq  "review level: rebrief, the holding's mode still leaves it out" "--auto --no-merge" "$(row mode)"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.review_level = {"floor": "full", "ceiling": "light"}')"
run >/dev/null 2>&1; RC=$?
eq  "review level: a floor above the ceiling is refused, exit 1" 1 "$RC"
eq  "review level: refused, nothing written or launched" "" "$(grep -E '^niwa dispatch|record write|koto request' "$ST/calls.log")"

# --- --releg: a leg spent before the worker reported -------------------------------------------------------

# A scope worker dispatched on leg req_1:scope; its leg is cancelled before
# it reports. --releg opens req_2 for the same holding, keeps the worker.
spent() { # spent <disposition> <result_source>: koto's view of req_1
    jq -nc --arg d "$1" --arg s "$2" '{request_id: "req_1", request_state: (if $d == "open" then "open" else "closed" end),
        legs: {scope: {name: "scope", disposition: $d, result: (if $s == "" then null else {status: "failure"} end),
               result_source: (if $s == "" then null else $s end)}}}' >"$ST/request_get.json"
}
reset "$INPUT_SCOPE"
run >/dev/null 2>&1
printf 'plugin-api' >"$ST/ctx/report_topic"
rm -f "$ST/ctx/coord/pick.json"
spent resolved explicit
printf '{"requests":[{"request_id":"req_1","coordinator_of_record":"coordinate-plugin-api","request_state":"open"}]}\n' >"$ST/open_requests.json"
: >"$ST/calls.log"
OUT=$(run --releg 2>"$ST/err"); RC=$?
eq  "releg: a cancelled leg is replaced, exit 0" 0 "$RC"
has "releg: prints the brief" "$OUT" "brief=$W/.niwa/dispatch-briefs/plugin-api.md"
has "releg: prints the new leg" "$OUT" "leg=req_2:scope"
has "releg: prints the worker's session to message" "$OUT" "session=$NIWA_NAME"
eq  "releg: the holding is on the new leg" "leg req_2:scope" "$(row return_path)"
eq  "releg: the holding stays dispatched" dispatched "$(row dispatch_status)"
eq  "releg: its entry point stays" scope "$(row entry_point)"
has "releg: the spent request is abandoned" "$(calls)" "koto request abandon-request req_1"
has "releg: the new leg pins the same inputs" "$(calls)" '"name":"scope","role":"scope","template":"scope.md","inputs":{"TOPIC":"plugin-api"}'
eq  "releg: no launch, the worker is kept" 0 "$(grep -c '^niwa dispatch' "$ST/calls.log")"
has "releg: the brief names the new leg" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" "--koto-leg=req_2:scope"
reset "$INPUT_SCOPE"; run >/dev/null 2>&1; printf 'plugin-api' >"$ST/ctx/report_topic"
spent resolved refused; : >"$ST/calls.log"
run --releg >/dev/null 2>&1; eq "releg: a leg refused at preflight is replaced" 0 "$?"
eq  "releg: refused: the holding is on the new leg" "leg req_2:scope" "$(row return_path)"
has "releg: refused: the new leg pins the same inputs" "$(calls)" '"inputs":{"TOPIC":"plugin-api"}'
reset "$INPUT_SCOPE"; run >/dev/null 2>&1; printf 'plugin-api' >"$ST/ctx/report_topic"
jq -nc '{request_id: "req_1", request_state: "closed", legs: {scope: {name: "scope", disposition: "open", bound_child: null, result: null, result_source: null}}}' >"$ST/request_get.json"
: >"$ST/calls.log"
run --releg >/dev/null 2>&1; eq "releg: a leg left open on a closed request is spent, and replaced" 0 "$?"
reset "$INPUT_SCOPE"; run >/dev/null 2>&1; printf 'plugin-api' >"$ST/ctx/report_topic"
jq -nc '{request_id: "req_1", request_state: "closed", legs: {scope: {name: "scope", disposition: "resolved", result: {status: "success"}, result_source: "explicit"}}}' >"$ST/request_get.json"
: >"$ST/calls.log"
run --releg >/dev/null 2>&1; eq "releg: a leg resolved by hand as a success isn't spent early: exit 9" 9 "$?"
eq  "releg: nothing written for it" "" "$(grep -E 'record write|koto request create' "$ST/calls.log")"
reset "$INPUT_SCOPE"; run >/dev/null 2>&1; printf 'plugin-api' >"$ST/ctx/report_topic"
rm -f "$ST/request_get.json"; : >"$ST/calls.log"
run --releg >/dev/null 2>&1; eq "releg: a leg koto no longer has (missing) is replaced" 0 "$?"
reset "$INPUT_SCOPE"; run >/dev/null 2>&1; printf 'plugin-api' >"$ST/ctx/report_topic"
spent open ""; : >"$ST/calls.log"
ERR=$(run --releg 2>&1 >/dev/null); RC=$?
eq  "releg: an open leg isn't spent: exit 9" 9 "$RC"
has "releg: and says so" "$ERR" "still open"
eq  "releg: nothing written or opened" "" "$(grep -E 'record write|koto request create|abandon' "$ST/calls.log")"
spent resolved promoted; : >"$ST/calls.log"
run --releg >/dev/null 2>&1; eq "releg: a promoted result is the worker's report: exit 9" 9 "$?"
eq  "releg: nothing written for a promoted result" "" "$(grep -E 'record write|koto request create' "$ST/calls.log")"
spent resolved explicit
jq -c '.pull_request = "[#9](https://github.com/acme/widgets/pull/9)"' "$ST/rows/plugin-api.json" >"$ST/r" && mv "$ST/r" "$ST/rows/plugin-api.json"
run --releg >/dev/null 2>&1; eq "releg: a holding with a pull request isn't spent early: exit 9" 9 "$?"
reset "$INPUT_DELIVER"; jq -c '.entry_point = "explore" | .entry_args = ["q"]' "$ST/ctx/brief_input.json" >"$ST/b" && mv "$ST/b" "$ST/ctx/brief_input.json"
run >/dev/null 2>&1; printf 'plugin-api' >"$ST/ctx/report_topic"
run --releg >/dev/null 2>&1; eq "releg: a message-path holding has no leg to replace: exit 9" 9 "$?"
run --releg --rebrief >/dev/null 2>&1; eq "releg and rebrief together: usage" 2 "$?"
reset "$INPUT_SCOPE"; run >/dev/null 2>&1; printf 'plugin-api' >"$ST/ctx/report_topic"
jq -c '.entry_point = "explore"' "$ST/rows/plugin-api.json" >"$ST/r" && mv "$ST/r" "$ST/rows/plugin-api.json"
spent resolved explicit; : >"$ST/calls.log"
run --releg >/dev/null 2>&1; eq "releg: an entry point that takes no leg has none to replace: exit 9" 9 "$?"
eq  "releg: and nothing written" "" "$(grep -E 'record write|koto request create' "$ST/calls.log")"

# --- send_execution: a scoping-ahead holding sent its execution ------------------------------------------

log_pick() { # log_pick <choice> <unit>: the session log's latest entry into pick and its evidence
    mkdir -p "$ST/session"
    { printf '{"schema_version":1,"workflow":"coord","created_at":"2026-09-26T10:00:00.000Z"}\n'
      jq -nc '{seq: 1, timestamp: "2026-09-26T10:01:00.000Z", type: "transitioned", payload: {from: "pick_facts", to: "pick"}}'
      jq -nc --arg c "$1" --arg u "$2" '{seq: 2, timestamp: "2026-09-26T10:02:00.000Z", type: "evidence_submitted", payload: {state: "pick", fields: {choice: $c, unit: $u}}}'
    } >"$ST/session/koto-coord.state.jsonl"
}
INPUT_EXEC=$(printf '%s' "$INPUT_DELIVER" | jq -c '.entry_point = "execute" | .entry_args = ["docs/plans/PLAN-plugin-api.md"] | .phase = "executing"')
reset "$(printf '%s' "$INPUT_SCOPE" | jq -c '.phase = "scoping-ahead"')"
run >/dev/null 2>&1
eq  "send_execution: the scoping holding starts scoping ahead" scoping-ahead "$(row phase)"
printf '%s' "$INPUT_EXEC" >"$ST/ctx/brief_input.json"
log_pick send_execution plugin-api
: >"$ST/calls.log"
OUT=$(run 2>"$ST/err"); RC=$?
eq  "send_execution: exit 0" 0 "$RC"
lacks "send_execution: never already-dispatched" "$OUT" "already-dispatched"
has "send_execution: prints the brief" "$OUT" "brief=$W/.niwa/dispatch-briefs/plugin-api.md"
eq  "send_execution: phase executing" executing "$(row phase)"
eq  "send_execution: entry point execute" execute "$(row entry_point)"
eq  "send_execution: mode from the execution's input" "--auto" "$(row mode)"
eq  "send_execution: a new leg for /execute" "leg req_2:execute" "$(row return_path)"
eq  "send_execution: the unit is kept" "Feature 2: the plugin API" "$(row unit)"
has "send_execution: the leg pins the plan slug" "$(calls)" '"inputs":{"PLAN_SLUG":"plugin-api"}'
eq  "send_execution: nothing launched" 0 "$(grep -c '^niwa dispatch' "$ST/calls.log")"
has "send_execution: the brief is the execution's" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" "/shirabe:execute docs/plans/PLAN-plugin-api.md"
lacks "send_execution: on a leg, the brief carries no link command" "$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")" "--dispatched-by"
# An execution whose entry point takes no leg here (/work-on given a PLAN)
# goes to the message path, and its brief carries the link command.
reset "$(printf '%s' "$INPUT_SCOPE" | jq -c '.phase = "scoping-ahead"')"; run >/dev/null 2>&1
printf '%s' "$INPUT_DELIVER" | jq -c '.entry_point = "work-on" | .entry_args = ["docs/plans/PLAN-plugin-api.md"] | .phase = "executing"' >"$ST/ctx/brief_input.json"
log_pick send_execution plugin-api; : >"$ST/calls.log"
run >/dev/null 2>"$ST/err"; eq "send_execution to the message path: exit 0" 0 "$?"
eq  "send_execution to the message path: the holding reports by message" message "$(row return_path)"
B=$(cat "$W/.niwa/dispatch-briefs/plugin-api.md")
eq  "send_execution to the message path: dispatcher_session is the run" 1 "$(grep -cx 'dispatcher_session: coord' <<<"$B")"
has "send_execution to the message path: the link command, --dispatched-by filled in" "$B" 'link-dispatcher.sh" <session> --dispatched-by coord`'
reset "$(printf '%s' "$INPUT_SCOPE" | jq -c '.phase = "scoping-ahead"')"; run >/dev/null 2>&1
printf '%s' "$INPUT_EXEC" >"$ST/ctx/brief_input.json"; log_pick dispatch plugin-api; : >"$ST/calls.log"
eq  "a pick that isn't send_execution: already-dispatched, nothing changed" already-dispatched "$(run 2>/dev/null)"
eq  "and the holding still scoping ahead" scoping-ahead "$(row phase)"
log_pick send_execution another-topic; : >"$ST/calls.log"
eq  "a send_execution pick for another unit: already-dispatched" already-dispatched "$(run 2>/dev/null)"
log_pick send_execution plugin-api
jq -nc '{request_id: "req_1", request_state: "open", legs: {scope: {name: "scope", disposition: "open", bound_child: "scope-plugin-api", result: null, result_source: null}}}' >"$ST/request_get.json"
: >"$ST/calls.log"
run >/dev/null 2>&1; eq "send_execution while the worker is still attached to its scoping leg: exit 9" 9 "$?"
eq  "and nothing written" "" "$(grep -E 'record write|koto request create|abandon' "$ST/calls.log")"
echo 1 >"$ST/request_get.rc"; : >"$ST/calls.log"
run >/dev/null 2>&1; eq "send_execution when the scoping leg can't be read: exit 2" 2 "$?"
eq  "and nothing written or abandoned" "" "$(grep -E 'record write|koto request create|abandon' "$ST/calls.log")"
rm -f "$ST/request_get.rc" "$ST/request_get.json"
printf '%s' "$INPUT_SCOPE" | jq -c '.phase = "scoping-ahead"' >"$ST/ctx/brief_input.json"; : >"$ST/calls.log"
run >/dev/null 2>&1; eq "send_execution with the scoping brief again: refused, exit 1" 1 "$?"
eq  "and nothing written" "" "$(grep -E 'record write|koto request create' "$ST/calls.log")"

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
has "no record script: says so" "$ERR" "state-holding.sh is not installed"
eq  "no record script: nothing launched" 0 "$(grep -c '^niwa dispatch' "$ST/calls.log")"

# --- the leg keys (PRD R13) ---------------------------------------------------------------------------------

lkey() { cat "$ST/ctx/legs/$1/$2" 2>/dev/null; }
reset "$INPUT_DELIVER"
run >/dev/null 2>&1
eq  "legkey: a dispatch on a leg writes its key, open, with the worker, the declaration and the unit" \
    '{"request":"req_1","leg":"deliver","topic":"plugin-api","state":"open","templates":["deliver.md"],"inputs":{"TOPIC":"plugin-api"},"unit":"Feature 2: the plugin API"}' \
    "$(lkey req_1 deliver)"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.unit = "Feature (2): the plugin API"')"
printf '%s' "$PICK_ROADMAP" | jq -c '.units[1].unit = "Feature (2)"' >"$ST/ctx/coord/pick.json"
run >/dev/null 2>&1
eq  "legkey: a unit whose tag is outside the cost capture's pattern is left off the key" null "$(lkey req_1 deliver | jq -c .unit)"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.entry_point = "explore" | .entry_args = ["plugin-api"]')"
run >/dev/null 2>&1
eq  "legkey: a message-path dispatch writes none" "" "$(ls "$ST/ctx/legs" 2>/dev/null)"
reset "$INPUT_DELIVER"
export KOTO_LEG_PUT_FAIL=1
run >/dev/null 2>&1; eq "legkey: a key that can't be written stops the dispatch: exit 2" 2 "$?"
eq  "  ... before any holding is written or worker launched" "" "$(grep -E 'record write|^niwa dispatch' "$ST/calls.log")"
unset KOTO_LEG_PUT_FAIL
reset "$INPUT_DELIVER"
NIWA_MODE=fail; export NIWA_MODE
run >/dev/null 2>&1
eq  "legkey: a failed launch's leg reads spent" spent "$(lkey req_1 deliver | jq -r .state)"
reset "$INPUT_SCOPE"
run >/dev/null 2>&1
printf 'plugin-api' >"$ST/ctx/report_topic"
rm -f "$ST/ctx/coord/pick.json"
spent resolved explicit
printf '{"requests":[{"request_id":"req_1","coordinator_of_record":"coordinate-plugin-api","request_state":"open"}]}\n' >"$ST/open_requests.json"
run --releg >/dev/null 2>&1
eq  "legkey: --releg marks the spent leg's key replaced" replaced "$(lkey req_1 scope | jq -r .state)"
eq  "  ... and writes the new leg's key open" "open plugin-api" "$(lkey req_2 scope | jq -r '"\(.state) \(.topic)"')"

# --- a stranded holding (PRD R15; shirabe#732) ---------------------------------------------------------------

PUSHED=cccccccccccccccccccccccccccccccccccccccc
stranded_row() {
    jq -nc --arg h "$PUSHED" '{unit: "Feature 2: the plugin API", entry_point: "deliver", mode: "--auto --no-merge", phase: "executing",
        dispatch_status: "stranded", return_path: "message", worker: "plugin-api", repo: "acme/widgets", branch: "feat/plugin-api",
        verified_head: "", dispatched: "2026-10-01", pull_request: "", pushed_head: $h}' >"$ST/rows/plugin-api.json"
}
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.topic = "relaunch"')" relaunch
stranded_row
export NIWA_NAME=relaunch-1a2b3c4d
OUT=$(run 2>"$T/st.err"); RC=$?
eq  "stranded: the unit is dispatched under a new topic" "0 session=relaunch-1a2b3c4d" "$RC $OUT"
has "stranded: the new brief names the old branch and last pushed head" "$(cat "$W/.niwa/dispatch-briefs/relaunch.md")" \
    "This unit was held by worker plugin-api, which was stranded: continue from its branch \`feat/plugin-api\`, last pushed head \`$PUSHED\`, rather than starting over."
[ -f "$ST/rows/plugin-api.json" ] && bad "stranded: the stranded row is retired" "$(cat "$ST/rows/plugin-api.json")" || ok "stranded: the stranded row is retired"
RET=$(grep -n 'record retire plugin-api' "$ST/calls.log" | cut -d: -f1)
DONE=$(grep -n 'record write relaunch dispatched' "$ST/calls.log" | tail -1 | cut -d: -f1)
if [ -n "$RET" ] && [ -n "$DONE" ] && [ "$RET" -gt "$DONE" ]; then ok "  ... after the new holding reads dispatched"; else bad "  ... after the new holding reads dispatched" "$(calls)"; fi
reset "$INPUT_DELIVER"
stranded_row
run >/dev/null 2>&1; eq "stranded: dispatching the stranded topic itself is exit 3" 3 "$?"
eq  "  ... and launches nothing" 0 "$(grep -c '^niwa dispatch' "$ST/calls.log")"
reset "$(printf '%s' "$INPUT_DELIVER" | jq -c '.topic = "relaunch" | .unit = "Feature 1"')" relaunch
stranded_row
run >/dev/null 2>&1
has "stranded: another unit's stranded row isn't named" "$(cat "$W/.niwa/dispatch-briefs/relaunch.md")" "None beyond what the documents you read record."
[ -f "$ST/rows/plugin-api.json" ] && ok "  ... or retired" || bad "  ... or retired" ""

# --- --releg-imported: a worker that moved here with the session (PRD R15) ------------------------------------

# The holding plugin-api reports on leg req_9:deliver, which this host's store
# never held (the stand-in answers 2 for it); the child deliver-plugin-api,
# bound to it on the old host, came here with the import and is bound to
# nothing.
child_log() { # child_log <template-file> <TOPIC>
    mkdir -p "$ST/session"
    jq -nc --arg t "$1" '{schema_version: 1, workflow: "deliver-plugin-api", template_source_file: $t}' >"$ST/session/koto-deliver-plugin-api.state.jsonl"
    jq -nc --arg v "$2" '{seq: 1, type: "workflow_initialized", payload: {variables: {TOPIC: $v, MODE: "auto"}}}' >>"$ST/session/koto-deliver-plugin-api.state.jsonl"
}
imp_setup() {
    reset "$INPUT_DELIVER"
    mkdir -p "$ST/requests" "$ST/ctx/legs/req_9"
    jq -nc '{unit: "Feature 2: the plugin API", entry_point: "deliver", mode: "--auto --no-merge", phase: "executing",
        dispatch_status: "dispatched", return_path: "leg req_9:deliver", worker: "plugin-api", repo: "acme/widgets",
        branch: "", verified_head: "", dispatched: "2026-10-01", pull_request: ""}' >"$ST/rows/plugin-api.json"
    jq -nc '{request: "req_9", leg: "deliver", topic: "plugin-api", state: "open", templates: ["deliver.md"],
        inputs: {TOPIC: "plugin-api"}, child: "deliver-plugin-api"}' >"$ST/ctx/legs/req_9/deliver"
    printf '[{"id":"deliver-plugin-api","parent_workflow":null}]\n' >"$ST/koto_sessions.json"
    child_log deliver.md plugin-api
    : >"$ST/calls.log"
}
attaches() { grep -c '^koto request attach' "$ST/calls.log"; }
untouched() { # untouched <name>: nothing opened, attached or written
    eq "$1" "" "$(grep -E 'record write|koto request create|koto request attach' "$ST/calls.log")"
}
imp_setup
OUT=$(run --releg-imported plugin-api 2>"$T/imp.err"); RC=$?
eq  "imported: exit 0" 0 "$RC"
eq  "imported: prints the new leg and the child" "leg=req_1:deliver child=deliver-plugin-api" "$(printf '%s' "$OUT" | tr '\n' ' ' | sed 's/ $//')"
has "imported: the new request declares the holding's leg, templates and pinned inputs" "$(calls)" \
    '"name":"deliver","role":"deliver","template":"deliver.md","inputs":{"TOPIC":"plugin-api"}'
has "  ... under the topic's coordinator" "$(calls)" "--coordinator-of-record coordinate-plugin-api"
has "imported: the child is attached to it" "$(calls)" "koto request attach --session deliver-plugin-api req_1 deliver"
eq  "imported: the holding's return path names the new leg" "leg req_1:deliver" "$(row return_path)"
eq  "imported: the old key reads relegged, naming the new request" "relegged req_1" "$(lkey req_9 deliver | jq -r '"\(.state) \(.new_request)"')"
eq  "imported: the new key is open, from the old request, with the child" "open req_9 deliver-plugin-api" \
    "$(lkey req_1 deliver | jq -r '"\(.state) \(.from) \(.child)"')"
eq  "  ... and no unit, the old key having none" null "$(lkey req_1 deliver | jq -c .unit)"
eq  "imported: no launch, no brief" "0 none" "$(grep -c '^niwa dispatch' "$ST/calls.log") $([ -f "$W/.niwa/dispatch-briefs/plugin-api.md" ] && echo some || echo none)"
: >"$ST/calls.log"
run --releg-imported plugin-api >/dev/null 2>&1; eq "imported: a re-run after it finished exits 0" 0 "$?"
eq  "  ... and attaches nothing again" 0 "$(attaches)"

# Killed after the request opened but before the key named it: the re-run
# abandons that stray request and opens its own.
imp_setup
# The listing names the leg being re-legged too, as a store that did hold it
# would: it is never abandoned.
printf '{"requests":[{"request_id":"req_7","coordinator_of_record":"coordinate-plugin-api","request_state":"open"},{"request_id":"req_9","coordinator_of_record":"coordinate-plugin-api","request_state":"open"}]}\n' >"$ST/open_requests.json"
jq -nc '{request_id: "req_7", request_state: "open", legs: {deliver: {name: "deliver", disposition: "open", bound_child: null}}}' >"$ST/requests/req_7.json"
run --releg-imported plugin-api >/dev/null 2>&1; eq "crash: killed before releg-pending, a re-run finishes: exit 0" 0 "$?"
has "  ... abandoning the request the interrupted run left" "$(calls)" "koto request abandon-request req_7"
lacks "  ... and never the request being re-legged" "$(calls)" "koto request abandon-request req_9"
eq  "  ... and attaching once, to its own" 1 "$(attaches)"

# Killed after the pending request was written: a re-run attaches it once.
imp_setup
jq -nc '{request_id: "req_1", request_state: "open", legs: {deliver: {name: "deliver", disposition: "open", bound_child: null}}}' >"$ST/requests/req_1.json"
echo 1 >"$ST/req_n"
jq -c '.state = "releg-pending" | .new_request = "req_1"' "$ST/ctx/legs/req_9/deliver" >"$T/k" && mv "$T/k" "$ST/ctx/legs/req_9/deliver"
run --releg-imported plugin-api >/dev/null 2>&1; eq "crash: killed after releg-pending, a re-run finishes: exit 0" 0 "$?"
eq  "  ... opening no second request" "" "$(grep 'koto request create' "$ST/calls.log")"
eq  "  ... and attaching once" 1 "$(attaches)"
eq  "  ... with the holding on the pending request" "leg req_1:deliver" "$(row return_path)"
# Killed after the attach: no second attach.
imp_setup
jq -nc '{request_id: "req_1", request_state: "open", legs: {deliver: {name: "deliver", disposition: "open", bound_child: "deliver-plugin-api"}}}' >"$ST/requests/req_1.json"
echo 1 >"$ST/req_n"
jq -c '.state = "releg-pending" | .new_request = "req_1"' "$ST/ctx/legs/req_9/deliver" >"$T/k" && mv "$T/k" "$ST/ctx/legs/req_9/deliver"
run --releg-imported plugin-api >/dev/null 2>&1; eq "crash: killed after the attach, a re-run finishes: exit 0" 0 "$?"
eq  "  ... with one binding" 0 "$(attaches)"
eq  "  ... and the old key relegged" relegged "$(lkey req_9 deliver | jq -r .state)"
# Killed after the holding moved, before the old key was marked.
imp_setup
jq -nc '{request_id: "req_1", request_state: "open", legs: {deliver: {name: "deliver", disposition: "open", bound_child: "deliver-plugin-api"}}}' >"$ST/requests/req_1.json"
jq -c '.state = "releg-pending" | .new_request = "req_1"' "$ST/ctx/legs/req_9/deliver" >"$T/k" && mv "$T/k" "$ST/ctx/legs/req_9/deliver"
mkdir -p "$ST/ctx/legs/req_1"
jq -c '.request = "req_1" | .state = "open" | .from = "req_9" | del(.new_request)' "$ST/ctx/legs/req_9/deliver" >"$ST/ctx/legs/req_1/deliver"
jq -c '.return_path = "leg req_1:deliver"' "$ST/rows/plugin-api.json" >"$T/r" && mv "$T/r" "$ST/rows/plugin-api.json"
run --releg-imported plugin-api >/dev/null 2>&1; eq "crash: killed before the old key's mark, a re-run marks it: exit 0" 0 "$?"
eq  "  ... relegged" relegged "$(lkey req_9 deliver | jq -r .state)"
untouched "  ... touching nothing else"

# Refusals: exit 9, nothing opened, attached or written.
imp_setup
jq -c '.topic = "someone-else"' "$ST/ctx/legs/req_9/deliver" >"$T/k" && mv "$T/k" "$ST/ctx/legs/req_9/deliver"
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: a key naming another worker than the holding's is 9" 9 "$?"
untouched "  ... nothing done"
imp_setup
jq -c 'del(.child)' "$ST/ctx/legs/req_9/deliver" >"$T/k" && mv "$T/k" "$ST/ctx/legs/req_9/deliver"
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: no recorded child is 9" 9 "$?"
untouched "  ... nothing done"
imp_setup
jq -c '.child = "../deliver-plugin-api"' "$ST/ctx/legs/req_9/deliver" >"$T/k" && mv "$T/k" "$ST/ctx/legs/req_9/deliver"
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: a child name off the session grammar is 9" 9 "$?"
untouched "  ... nothing done"
imp_setup
printf '[]\n' >"$ST/koto_sessions.json"
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: a child left on the old host is 9" 9 "$?"
untouched "  ... nothing done"
imp_setup
child_log scope.md plugin-api
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: a child on a template the leg doesn't admit is 9" 9 "$?"
untouched "  ... nothing done"
imp_setup
child_log deliver.md another-topic
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: a child whose TOPIC differs from the declaration is 9" 9 "$?"
untouched "  ... nothing done"
imp_setup
jq -nc '{request_id: "req_5", request_state: "open", legs: {deliver: {name: "deliver", disposition: "open", bound_child: "deliver-plugin-api"}}}' >"$ST/requests/req_5.json"
printf '{"requests":[{"request_id":"req_5","coordinator_of_record":"coordinate-other","request_state":"open"}]}\n' >"$ST/open_requests.json"
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: a child bound to another leg here is 9" 9 "$?"
untouched "  ... nothing done"
imp_setup
printf '{"requests":[{"request_id":"req_6","coordinator_of_record":"coordinate-other","request_state":"open"}]}\n' >"$ST/open_requests.json"
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: an open request whose binding can't be read stops the re-leg: 2" 2 "$?"
untouched "  ... nothing done"
imp_setup
jq -nc '{request_id: "req_9", request_state: "open", legs: {deliver: {name: "deliver", disposition: "open", bound_child: null}}}' >"$ST/requests/req_9.json"
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: a leg whose request this host holds is watched as before: 9" 9 "$?"
untouched "  ... nothing done"
imp_setup
rm -rf "$ST/ctx/legs"
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: a holding dispatched before leg keys is 9" 9 "$?"
untouched "  ... nothing done"
imp_setup
jq -c '.return_path = "message"' "$ST/rows/plugin-api.json" >"$T/r" && mv "$T/r" "$ST/rows/plugin-api.json"
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: a message-path holding is 9" 9 "$?"
untouched "  ... nothing done"
imp_setup
export KOTO_ATTACH_FAIL=1
run --releg-imported plugin-api >/dev/null 2>&1; eq "refused: koto refusing the attach is 9" 9 "$?"
has "  ... the new request is abandoned" "$(calls)" "koto request abandon-request req_1"
eq  "  ... the old key is open again, naming no pending request" "open null" "$(lkey req_9 deliver | jq -r '"\(.state) \(.new_request)"')"
eq  "  ... and the holding stays on its leg" "leg req_9:deliver" "$(row return_path)"
unset KOTO_ATTACH_FAIL
run --releg-imported plugin-api --rebrief >/dev/null 2>&1; eq "imported and rebrief together: usage" 2 "$?"
imp_setup
jq -c '.unit = "Feature 2: the plugin API"' "$ST/ctx/legs/req_9/deliver" >"$T/k" && mv "$T/k" "$ST/ctx/legs/req_9/deliver"
run --releg-imported plugin-api >/dev/null 2>&1
eq  "imported: an old key's unit is carried to the new key" '"Feature 2: the plugin API"' "$(lkey req_1 deliver | jq -c .unit)"

# --- the dispatched event ----------------------------------------------------------------------------------
# A confirmed launch sends one `dispatched` event through the stand-in helper,
# whose arguments are read back whole; nothing that launches no worker sends
# one; and a helper that fails or is missing changes nothing the run prints
# or returns.

CS=coordinate-roadmap-plugin-system-20261030T090000Z
crun() { (cd "$W/inst" && bash "$S" --session "$CS" "$@"); }
emits() { cat "$ST/emit.calls" 2>/dev/null; }

reset "$INPUT_DELIVER"
BEFORE=$(date -u +%s)
OUT=$(crun 2>/dev/null); RC=$?
AFTER=$(date -u +%s)
eq  "dispatched: the launch is confirmed" "0 session=plugin_api-1a2b3c4d" "$RC $OUT"
AT=$(sed -n 's/^unit\.requested_at=//p' "$ST/emit.calls" 2>/dev/null)
if [[ $AT =~ ^[0-9]+$ ]] && [ "$AT" -ge "$BEFORE" ] && [ "$AT" -le "$AFTER" ]; then
    ok "dispatched: requested_at is when this run opened the leg, in Unix seconds"
else
    bad "dispatched: requested_at is when this run opened the leg, in Unix seconds" "[$AT] not in [$BEFORE, $AFTER]"
fi
eq  "dispatched: one call, every field the run has, the koto dir the workspace root" \
    "$(printf '%s\n' event --scope unit-cost --kind dispatched --koto-dir "$W" \
        unit.request=req_1 "unit.requested_at=$AT" unit.leg=deliver unit.topic=plugin-api \
        unit.scope_slug=roadmap-plugin-system "unit.koto_session=$CS" unit.roadmap=ROADMAP-plugin-system \
        "unit.milestone=Feature 2" unit.entry_point=deliver unit.repo=acme/widgets unit.mode=auto:no-merge \
        unit.worker_session=0 --)" \
    "$(emits)"

# Confirmed from the listing on a resumed run: the listing row's dispatch_id,
# no requested_at (an earlier run opened the leg), no roadmap (pick isn't
# read), no milestone (an issue reference), no scope slug (the session name
# isn't a coordinator run's) and no worker session (no launch output).
reset "$INPUT_SCOPE"
printf '%s' '{"dispatch_status":"dispatching","return_path":"leg req_9:scope","worker":"plugin-api","repo":"acme/widgets","entry_point":"scope","mode":"--auto","unit":"acme/widgets#12"}' >"$ST/rows/plugin-api.json"
printf '[{"name":"x","path":"/p","session_name":"plugin_api-1a2b3c4d","dispatch_id":"3c803591-4c01-486f-a927-f96ec399d6a7"}]\n' >"$ST/sessions.json"
OUT=$(run 2>/dev/null); RC=$?
eq  "dispatched, resumed: confirmed from the listing" "0 session=plugin_api-1a2b3c4d" "$RC $OUT"
eq  "dispatched, resumed: the listing row's dispatch id, and only the fields the run has" \
    "$(printf '%s\n' event --scope unit-cost --kind dispatched --koto-dir "$W" \
        unit.request=req_9 unit.leg=scope unit.topic=plugin-api unit.koto_session=coord \
        unit.entry_point=scope unit.repo=acme/widgets unit.mode=auto \
        unit.worker_dispatch=3c803591-4c01-486f-a927-f96ec399d6a7 --)" \
    "$(emits)"

# A message-path worker has no request or leg to name.
reset "$INPUT_DELIVER"
printf '%s' '{"dispatch_status":"dispatching","return_path":"message","worker":"plugin-api","repo":"acme/widgets","entry_point":"deliver","mode":"","unit":"Feature 2: the plugin API"}' >"$ST/rows/plugin-api.json"
printf '[{"name":"x","path":"/p","session_name":"plugin_api-1a2b3c4d"}]\n' >"$ST/sessions.json"
run >/dev/null 2>&1
eq  "dispatched, message path: no request, leg, empty mode or absent dispatch id" \
    "$(printf '%s\n' event --scope unit-cost --kind dispatched --koto-dir "$W" \
        unit.topic=plugin-api unit.koto_session=coord "unit.milestone=Feature 2" \
        unit.entry_point=deliver unit.repo=acme/widgets --)" \
    "$(emits)"

# Paths that launch no worker send nothing.
reset "$INPUT_DELIVER"
crun >/dev/null 2>&1
rm -f "$ST/emit.calls"
OUT=$(crun 2>/dev/null)
eq  "no worker launched: already-dispatched sends nothing" "already-dispatched|" "$OUT|$(emits)"
printf 'plugin-api' >"$ST/ctx/report_topic"
OUT=$(crun --rebrief 2>/dev/null); RC=$?
eq  "no worker launched: --rebrief sends nothing" "0|" "$RC|$(emits)"
reset "$INPUT_SCOPE"
export NIWA_MODE=fail
crun >/dev/null 2>&1; RC=$?
eq  "no worker launched: a failed launch sends nothing" "4|" "$RC|$(emits)"

# A helper that exits non-zero, and one that is missing, leave the run's
# output, stderr and exit code as a helper that works leaves them.
reset "$INPUT_DELIVER"
OUT=$(crun 2>"$T/emit-ok.err"); RC=$?
WANT="$RC|$OUT|$(cat "$T/emit-ok.err")"
reset "$INPUT_DELIVER"
echo 3 >"$ST/emit.rc"
OUT=$(crun 2>"$T/emit-fail.err"); RC=$?
eq  "a helper that exits 3: the same exit, output and stderr" "$WANT" "$RC|$OUT|$(cat "$T/emit-fail.err")"
eq  "  ... and it was called" 1 "$(grep -c '^dispatched$' "$ST/emit.calls" 2>/dev/null)"
eq  "  ... the row still dispatched" dispatched "$(row dispatch_status)"
reset "$INPUT_DELIVER"
mv "$DW/scripts/emit-event.sh" "$T/emit-event.aside"
OUT=$(crun 2>"$T/emit-missing.err"); RC=$?
mv "$T/emit-event.aside" "$DW/scripts/emit-event.sh"
eq  "a missing helper: the same exit, output and stderr" "$WANT" "$RC|$OUT|$(cat "$T/emit-missing.err")"
eq  "  ... the row still dispatched" dispatched "$(row dispatch_status)"

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
printf '{"dispatch_status":"stranded"}' >"$ST/rows/plugin-api.json"
eq  "gate: stranded is 3" 3 "$(gate)"
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

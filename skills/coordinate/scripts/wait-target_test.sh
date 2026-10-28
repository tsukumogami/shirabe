#!/usr/bin/env bash
# wait-target_test.sh -- wait-target.sh and report-source.sh against stand-ins
# for koto (context and request store) and the record's script.
#
# Covered, for wait-target.sh select: a resolved leg picked over an older open
# one; an abandoned or missing leg counted as waiting; the oldest open leg
# when none has resolved; message-path, undispatched and malformed holdings
# skipped; a request koto can't read skipped rather than routed; `none` printed
# and written when nothing is watched (never an empty capture); a refused
# record read; an unknown flag refused. For
# leg: the leg printed and report_topic written; exit 1 with no leg. For the
# leg keys: select records a bound child's name once, and a leg with no key
# is passed over; the leg mode writes `taken` with the result, or `spent`,
# and keeps a key already marked. For report-source.sh: a leg report
# admitted, a message admitted for a message-path worker, for a leg-bound one
# whose leg is taken or unwatchable or whose request this host doesn't hold,
# and refused for a leg-bound one watched here or an unknown topic, and
# malformed inputs.
#
# Usage: bash skills/coordinate/scripts/wait-target_test.sh
# Exit codes: 0 all pass; 1 a failure. Needs jq. bash 3.2.
set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

HERE=$(cd "$(dirname "$0")" && pwd)
S="$HERE/wait-target.sh"
R="$HERE/report-source.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not on PATH"; exit 0; }

T=$(mktemp -d "${TMPDIR:-/tmp}/wait-target-test.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
ktg_on_exit 'case "$T" in */wait-target-test.*) rm -rf "$T" ;; esac'

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$2], got [$3]"; fi; }

BIN="$T/bin"
mkdir -p "$BIN"
export ST="$T/state"

# A key with slashes (legs/<request>/<leg>) is a file under directories; a
# request this host's store doesn't hold is marked <request>.gone, which koto
# answers with its exit 2.
cat >"$BIN/koto" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "context get") [ -f "$ST/ctx/$4" ] || exit 1; cat "$ST/ctx/$4" ;;
    "context exists") [ -f "$ST/ctx/$4" ] ;;
    "context add")
        mkdir -p "$(dirname "$ST/ctx/$4")"
        if [ "${5-}" = --from-file ]; then cat "$6" >"$ST/ctx/$4"; else cat >"$ST/ctx/$4"; fi
        echo "add $4" >>"$ST/calls.log" ;;
    "context list")
        p=""; [ "${4-}" = --prefix ] && p=$5
        (cd "$ST/ctx" && find . -type f | sed 's#^\./##') | awk -v p="$p" 'index($0, p) == 1' | jq -R . | jq -sc . ;;
    "request get")
        [ -f "$ST/req/$3.gone" ] && exit 2
        [ -f "$ST/req/$3.json" ] || exit 1; cat "$ST/req/$3.json" ;;
    *) exit 64 ;;
esac
EOF
cat >"$T/state-holding.sh" <<'EOF'
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
# The stored set's reader: the Standing rows the test wrote, or none.
cat >"$T/state-stored-set.sh" <<'EOF'
#!/usr/bin/env bash
if [ -f "$ST/state.json" ]; then cat "$ST/state.json"; else echo '{"run":[],"standing":[],"work":[]}'; fi
EOF
chmod +x "$BIN/koto" "$T/state-holding.sh" "$T/state-stored-set.sh"
export PATH="$BIN:$PATH"
export DC_RECORD_HOLDING="$T/state-holding.sh" DC_RECORD_STATE="$T/state-stored-set.sh"

reset() {
    rm -rf "$ST"
    mkdir -p "$ST/ctx" "$ST/req"
    : >"$ST/calls.log"
    printf '%s\n' "$1" >"$ST/rows.json"
    unset RECORD_MODE
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
safe() { if grep -Eq '^[A-Za-z0-9 :/_.@-]+$' <<<"$2"; then ok "$1"; else bad "$1" "$2"; fi; }
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

# A paused holding's leg is passed over and left untaken.
PROWS='[
 {"worker":"alpha","unit":"Feature 2","dispatch_status":"dispatched","return_path":"leg req_a:scope"},
 {"worker":"gamma","unit":"Feature 3","dispatch_status":"dispatched","return_path":"leg req_g:execute"}
]'
pause_state() { # pause_state <on>: one lifted pause on <on>
    jq -nc --arg o "$1" '{run: [], work: [], standing: [{standing: "s1", kind: "pause", on: $o, until: "lifted", what: "x", owner: "the human", relayed_by: "", set: "2026-10-01T19:37Z"}]}' >"$ST/state.json"
}
reset "$PROWS"
req req_a scope open; req req_g execute resolved
pause_state "Feature 3"
eq  "select: a paused holding's resolved leg is passed over for an unpaused open one" req_a "$(sel)"
eq  "select: wait_target names the topic passed over" '["gamma"]' "$(target '.passed_over | tojson')"
eq  "select: the passed-over leg isn't taken" "" "$(cat "$ST/ctx/taken_legs" 2>/dev/null)"
pause_state all
eq  "select: under a pause on all no leg is picked" none "$(sel)"
eq  "select: and both topics are named passed over" '["alpha","gamma"]' "$(target '.passed_over | tojson')"
rm -f "$ST/state.json"
eq  "select: after the resume the resolved leg is offered first" req_g "$(sel)"

bash "$S" select --session coord --watch-secs 5 >/dev/null 2>&1; eq "usage: an unknown flag is 64" 64 "$?"
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

# --- the leg keys (PRD R13) ------------------------------------------------------------------------------

key() { cat "$ST/ctx/legs/$1/$2" 2>/dev/null; }
mkkey() { mkdir -p "$ST/ctx/legs/$1"; jq -nc --arg r "$1" --arg l "$2" --arg t "$3" '{request: $r, leg: $l, topic: $t, state: "open", templates: ["scope.md"], inputs: {TOPIC: "x"}}' >"$ST/ctx/legs/$1/$2"; }
reset "$ROWS"
printf '{"request_id":"req_a","legs":{"scope":{"name":"scope","disposition":"open","bound_child":"scope-x"}}}\n' >"$ST/req/req_a.json"
req req_g execute open
mkkey req_a scope alpha; mkkey req_g execute gamma
sel >/dev/null
eq  "child: select records the bound child's name in the leg's key" scope-x "$(key req_a scope | jq -r .child)"
eq  "  ... and changes nothing else in it" open "$(key req_a scope | jq -r .state)"
eq  "  ... and a leg nobody attached to gets no child" null "$(key req_g execute | jq -r .child)"
eq  "  ... and leg_children lists the recorded leg" req_a:scope "$(cat "$ST/ctx/leg_children")"
: >"$ST/calls.log"
sel >/dev/null
eq  "child: the next select writes no key again" "" "$(grep 'add legs/' "$ST/calls.log")"
rm -rf "$ST/ctx/legs" "$ST/ctx/leg_children"
sel >/dev/null; eq "child: a leg with no key (opened before keys) is passed over without a failure" 0 "$?"
eq  "  ... and no key is made for it" "" "$(ls "$ST/ctx/legs" 2>/dev/null)"

reset "$ROWS"
printf '{"request_id":"req_g","legs":{"execute":{"name":"execute","disposition":"resolved","result_source":"promoted","result_final_state":"done","bound_child":"execute-p","result":{"status":"success","payload":{"outcome":"ready","pr":"https://github.com/acme/widgets/pull/9"}}}}}\n' >"$ST/req/req_g.json"
mkkey req_g execute gamma
sel >/dev/null
bash "$S" leg --session coord >/dev/null
eq  "taken: the leg mode marks a promoted result's key taken" taken "$(key req_g execute | jq -r .state)"
eq  "  ... with the result beside it, before take_report reads anything" \
    '{"status":"success","final_state":"done","source":"promoted","payload":{"outcome":"ready","pr":"https://github.com/acme/widgets/pull/9"}}' \
    "$(key req_g execute | jq -c .result)"
eq  "  ... and keeps the declaration" '{"TOPIC":"x"}' "$(key req_g execute | jq -c .inputs)"
reset "$ROWS"
req req_g execute abandoned
mkkey req_g execute gamma
sel >/dev/null; bash "$S" leg --session coord >/dev/null
eq  "spent: an abandoned leg's key reads spent" spent "$(key req_g execute | jq -r .state)"
reset "$ROWS"
req req_g execute abandoned
sel >/dev/null; bash "$S" leg --session coord >/dev/null
eq  "spent: a leg with no key gets one naming its worker" "gamma spent" "$(key req_g execute | jq -r '"\(.topic) \(.state)"')"
mkdir -p "$ST/ctx/legs/req_g"; jq -c '.state = "taken"' "$ST/ctx/legs/req_g/execute" >"$ST/x" && mv "$ST/x" "$ST/ctx/legs/req_g/execute"
bash "$S" leg --session coord >/dev/null
eq  "  ... and a key already marked keeps its state" taken "$(key req_g execute | jq -r .state)"

# --- report-source.sh ----------------------------------------------------------------------------------

src() { printf '%s' "$1" >"$ST/ctx/report_topic"; printf '%s' "$2" >"$ST/ctx/report_source"; bash "$R" --session coord >/dev/null 2>&1; echo $?; }
reset "$ROWS"
# req_g's execute leg, resolved with a result gamma's own session promoted, and
# the report wait_leg's edge builds from it.
printf '{"request_id":"req_g","legs":{"execute":{"name":"execute","disposition":"resolved","result_source":"promoted","result_final_state":"done","result":{"status":"success","payload":{"outcome":"ready","pr":"https://github.com/acme/widgets/pull/9"}}}}}\n' >"$ST/req/req_g.json"
LEGREPORT='leg result: status success; final state done; outcome ready; step ; reason ; pull request https://github.com/acme/widgets/pull/9'
printf '%s' "$LEGREPORT" >"$ST/ctx/worker_report"
printf '{"path":"leg","topic":"gamma","request":"req_g","leg":"execute"}\n' >"$ST/ctx/wait_target"
eq  "source: a leg report from the recorded leg the wait read is admitted" 0 "$(src gamma leg)"
# Values rendered as koto renders them into the edge: false as `false`, and a
# payload that isn't an object as empty fields.
printf '{"request_id":"req_g","legs":{"execute":{"name":"execute","disposition":"resolved","result_source":"promoted","result_final_state":"done","result":{"status":"success","payload":{"outcome":false,"step":3}}}}}\n' >"$ST/req/req_g.json"
printf '%s' 'leg result: status success; final state done; outcome false; step 3; reason ; pull request ' >"$ST/ctx/worker_report"
eq  "source: false and a number render as koto renders them" 0 "$(src gamma leg)"
printf '{"request_id":"req_g","legs":{"execute":{"name":"execute","disposition":"resolved","result_source":"promoted","result_final_state":"done","result":{"status":"success","payload":"a string"}}}}\n' >"$ST/req/req_g.json"
printf '%s' 'leg result: status success; final state done; outcome ; step ; reason ; pull request ' >"$ST/ctx/worker_report"
eq  "source: a payload that isn't an object renders as empty fields" 0 "$(src gamma leg)"
printf '{"request_id":"req_g","legs":{"execute":{"name":"execute","disposition":"resolved","result_source":"promoted","result_final_state":"done","result":{"status":"success","payload":{"outcome":"ready","pr":"https://github.com/acme/widgets/pull/9"}}}}}\n' >"$ST/req/req_g.json"
printf '%s' "${LEGREPORT%/9}/66" >"$ST/ctx/worker_report"
eq  "source: a leg report that isn't the leg's promoted result is refused as a spent leg" 3 "$(src gamma leg)"
printf '%s' "$LEGREPORT" >"$ST/ctx/worker_report"
jq -c '.legs.execute.result_source = "explicit"' "$ST/req/req_g.json" >"$ST/req/x" && mv "$ST/req/x" "$ST/req/req_g.json"
eq  "source: a leg whose result its session didn't promote is refused as a spent leg" 3 "$(src gamma leg)"
rm -f "$ST/req/req_g.json"
eq  "source: a request koto can't read is 2" 2 "$(src gamma leg)"
printf '{"path":"leg","topic":"beta","request":"req_b","leg":"scope"}\n' >"$ST/ctx/wait_target"
eq  "source: a leg report for a message-path worker goes to the human, even when the wait names it" 3 "$(src beta leg)"
printf '{"path":"leg","topic":"gamma","request":"req_other","leg":"execute"}\n' >"$ST/ctx/wait_target"
eq  "source: a leg report whose read leg isn't the recorded one goes to the human" 3 "$(src gamma leg)"
printf '{"path":"none"}\n' >"$ST/ctx/wait_target"
eq  "source: a leg report with no leg read goes to the human" 3 "$(src gamma leg)"
eq  "source: a leg report for a topic with no holding goes to the human" 3 "$(src nobody leg)"
eq  "source: a message for a message-path worker is admitted" 0 "$(src beta message)"
jq -c 'map(if .worker == "beta" then .dispatch_status = "stranded" else . end)' "$ST/rows.json" >"$ST/rows.x" && mv "$ST/rows.x" "$ST/rows.json"
eq  "source: a message for a stranded worker is refused" 1 "$(src beta message)"
eq  "source: so is its progress" 1 "$(src beta progress)"
jq -c 'map(if .worker == "beta" then .dispatch_status = "dispatched" else . end)' "$ST/rows.json" >"$ST/rows.x" && mv "$ST/rows.x" "$ST/rows.json"
req req_g execute open
eq  "source: a message for a leg-bound worker is refused" 1 "$(src gamma message)"
# PRD R16: once the leg is read or can't be watched from here, a message is
# the worker's only way to report, and it stands.
legkey() { mkdir -p "$ST/ctx/legs/$1"; jq -nc --arg r "$1" --arg l "$2" --arg s "$3" '{request: $r, leg: $l, topic: "gamma", state: $s}' >"$ST/ctx/legs/$1/$2"; }
legkey req_g execute taken
eq  "source: a message for a worker whose leg was taken is admitted" 0 "$(src gamma message)"
legkey req_g execute unwatchable
eq  "source: a message for a worker whose leg is unwatchable is admitted" 0 "$(src gamma message)"
legkey req_g execute open
eq  "source: a message for a worker whose leg is open here is refused" 1 "$(src gamma message)"
printf '{"request_id":"req_g","legs":{"execute":{"name":"execute","disposition":"resolved","result_source":"promoted","result":{"status":"success"}}}}\n' >"$ST/req/req_g.json"
eq  "source: a message for a worker whose leg holds its promoted result, the key not yet marked, is admitted" 0 "$(src gamma message)"
printf '{"request_id":"req_g","legs":{"execute":{"name":"execute","disposition":"resolved","result_source":"explicit","result":{"status":"failure"}}}}\n' >"$ST/req/req_g.json"
eq  "source: one whose leg was spent without its result is refused" 1 "$(src gamma message)"
req req_g execute open
: >"$ST/req/req_g.gone"
eq  "source: a message for a worker whose request this host doesn't hold is admitted" 0 "$(src gamma message)"
rm -f "$ST/req/req_g.gone" "$ST/req/req_g.json"
eq  "source: a message for a leg-bound worker whose request can't be read is 2" 2 "$(src gamma message)"
rm -rf "$ST/ctx/legs"
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

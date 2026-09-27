#!/usr/bin/env bash
# dispatch-path_engine_test.sh -- the dispatch path's states in real koto.
#
# The skeleton template is built from coordinate.md itself: the state blocks
# for dispatch, wait, leg_pick, wait_leg, take_report, teardown,
# teardown_inventory, promote and destroy are cut out of the shipped template
# unchanged, and every state they route to that isn't under test is a
# terminal stand-in, so a route is read off the state the run stops at. The
# scripts are the shipped ones; koto, its request store and coord-log.sh are
# real; niwa, gh and the record feature's record-holding.sh are stand-ins.
#
# Proves: dispatch doesn't leave on `sent` until the record shows the holding
# dispatched, and no override record can stand in for the gate; a leg-bound
# worker's promoted result reaches take_report and report_facts with the leg's
# outcome as the report, an open leg holds until back or rescan, an explicit
# result goes to surface, and a leg read once isn't read again; a message
# report for a message-path worker reaches report_facts, one for a leg-bound
# worker goes back to wait, and one with no text holds until withdrawn;
# teardown inventories only after the session is stopped, destroys only a
# durable instance, sends a unique one to promote, and no override record can
# stand in for the inventory's gate.
#
# Needs koto, git and jq; SKIPs (exit 0) without koto.
# Usage: bash skills/coordinate/scripts/dispatch-path_engine_test.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
for bin in koto jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "SKIP: $bin not on PATH -- the engine cases did not run"; exit 0; }
done
T=$(mktemp -d "${TMPDIR:-/tmp}/dispatch-path-engine.XXXXXX")
T=$(cd -P "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" GIT_CEILING_DIRECTORIES="$T"
mkdir -p "$HOME"
cd "$T" || exit 1
git config --file "$HOME/.gitconfig" user.email t@example.invalid
git config --file "$HOME/.gitconfig" user.name t

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n     %s\n' "$1" "${2-}"; }
eq()   { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "want [$2], got [$3]"; fi; }

# --- the plugin tree: the shipped scripts, and stand-ins ---------------------------------

PR="$T/plugin"
S="$PR/skills/coordinate/scripts"
mkdir -p "$S" "$PR/skills/coordinate/references" "$PR/skills/coordinate/koto-templates"
for f in dispatch-common.sh holding-recorded.sh wait-target.sh report-source.sh \
    teardown-inventory.sh teardown-verdict.sh coord-log.sh; do
    cp "$HERE/$f" "$S/$f"
done
cp "$HERE/../references/entry-points.tsv" "$PR/skills/coordinate/references/"
export ST="$T/state"
mkdir -p "$ST"
printf '[]\n' >"$ST/rows.json"

# record-holding.sh: the rows live in $ST/rows.json, keyed by worker.
cat >"$S/record-holding.sh" <<'EOF'
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
case "$MODE" in
    list) cat "$ST/rows.json" ;;
    read) jq -ce --arg t "$TOPIC" '.[] | select(.worker == $t)' "$ST/rows.json" || exit 1 ;;
    *) exit 64 ;;
esac
EOF
BIN="$T/bin"
mkdir -p "$BIN"
# niwa: `list --json` names each worker's instance.
cat >"$BIN/niwa" <<'EOF'
#!/usr/bin/env bash
[ "$1" = list ] || exit 64
cat "$ST/sessions.json"
EOF
# gh: no merged pull requests.
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN/niwa" "$BIN/gh" "$S"/*.sh
export PATH="$BIN:$PATH"

# A workspace root, so the scripts that look for one find it.
W="$T/ws"
mkdir -p "$W/.niwa"
: >"$W/.niwa/workspace.toml"
: >"$W/.niwa/instance.json"

# --- the skeleton template, cut from coordinate.md --------------------------------------------

SRC="$HERE/../koto-templates/coordinate.md"
UNDER="dispatch wait leg_pick wait_leg take_report teardown teardown_inventory promote destroy"
# block <state>: the state's YAML block, from its `  <state>:` line to the next
# state's.
block() {
    awk -v s="  $1:" '
        $0 == s { on = 1; print; next }
        on && /^  [a-z_]+:$/ { exit }
        on && /^---$/ { exit }
        on { print }
    ' "$SRC"
}
TPL="$PR/skills/coordinate/koto-templates/coordinate.md"
{
    cat <<'EOF'
---
name: coordinate
version: "1.0"
description: the dispatch path's states, cut from coordinate.md, for dispatch-path_engine_test.sh
initial_state: entry
variables:
  PLUGIN_ROOT:
    description: plugin root
    required: true
  DISCIPLINE:
    description: discipline
    default: ""
states:
  entry:
    accepts:
      go:
        type: enum
        values: [dispatch, wait]
        required: true
    transitions:
      - target: dispatch
        when:
          go: dispatch
      - target: wait
        when:
          go: wait
EOF
    for st in $UNDER; do
        block "$st"
        echo
    done
    for st in record failure report_facts surface pick_facts quiet_check decision_apply merged_facts rotation_close done_stopped; do
        printf '  %s:\n    terminal: true\n\n' "$st"
    done
    echo '---'
    for st in entry $UNDER record failure report_facts surface pick_facts quiet_check decision_apply merged_facts rotation_close done_stopped; do
        printf '## %s\nStand-in.\n\n' "$st"
    done
} >"$TPL"
koto template compile "$TPL" >/dev/null 2>"$T/compile.err" || { fail "the skeleton compiles" "$(cat "$T/compile.err")"; echo "$PASS passed, $FAIL failed"; exit 1; }
pass "the skeleton cut from coordinate.md compiles"

N=0
# start: a fresh session at the entry state; sets SESS.
start() {
    N=$((N + 1))
    SESS="coord-dp-$N"
    (cd "$W" && koto init "$SESS" --template "$TPL" --var PLUGIN_ROOT="$PR" >/dev/null 2>"$T/init.err") ||
        fail "session $SESS starts" "$(cat "$T/init.err")"
}
tick() { (cd "$W" && koto next "$SESS" --no-cleanup "$@" >"$T/next.json" 2>&1); }
at() { (cd "$W" && koto status "$SESS" 2>/dev/null) | jq -r '.current_state // .state // "gone"'; }
ctx() { koto context get "$SESS" "$1" 2>/dev/null; }
put() { printf '%s' "$2" >"$T/v"; koto context add "$SESS" "$1" --from-file "$T/v" >/dev/null; }
rows() { printf '%s\n' "$1" >"$ST/rows.json"; }

# --- dispatch ------------------------------------------------------------------------------------

start
put dispatch_topic w1
rows '[]'
tick --with-data '{"go":"dispatch"}'
tick --with-data '{"dispatched":"sent","topic":"w1"}'
eq  "dispatch: sent with no holding on the record holds" dispatch "$(at)"
(cd "$W" && koto overrides record "$SESS" --gate holding_recorded --rationale "claim" >/dev/null 2>&1)
tick --with-data '{"dispatched":"sent","topic":"w1"}'
eq  "dispatch: an override record can't stand in for the holding" dispatch "$(at)"
rows '[{"worker":"w1","dispatch_status":"dispatching","return_path":"message"}]'
tick --with-data '{"dispatched":"sent","topic":"w1"}'
eq  "dispatch: a holding still dispatching holds" dispatch "$(at)"
rows '[{"worker":"w1","dispatch_status":"dispatched","return_path":"message"}]'
tick --with-data '{"dispatched":"sent","topic":"w1"}'
eq  "dispatch: the holding dispatched lets sent leave" record "$(at)"

start
put dispatch_topic w1
tick --with-data '{"go":"dispatch"}'
tick --with-data '{"dispatched":"failed"}'
eq  "dispatch: failed goes to failure" failure "$(at)"

# --- the leg path ----------------------------------------------------------------------------------

# A stand-in /scope, attached to a worker's leg and driven to its terminal.
mkdir -p "$T/tpl"
cat >"$T/tpl/scope.md" <<'EOF'
---
name: scope
version: "1.0"
description: a stand-in /scope for dispatch-path_engine_test.sh
initial_state: work
variables:
  TOPIC:
    required: true
states:
  work:
    accepts:
      finish:
        type: enum
        values: [go]
        required: true
    transitions:
      - target: done
        when:
          finish: go
  done:
    terminal: true
    result:
      outcome: scoped
      pr: https://github.com/acme/widgets/pull/7
---
## work
Stand-in.
## done
Done.
EOF
REQ=$(koto request create --role scope --template scope.md --inputs '{"TOPIC":"w1"}' \
    --requested-by coord --coordinator-of-record coordinate-w1 | jq -r .request_id)
REQ2=$(koto request create --role scope --template scope.md --inputs '{"TOPIC":"w2"}' \
    --requested-by coord --coordinator-of-record coordinate-w2 | jq -r .request_id)
rows "[{\"worker\":\"w1\",\"dispatch_status\":\"dispatched\",\"return_path\":\"leg $REQ:scope\"},
       {\"worker\":\"w3\",\"dispatch_status\":\"dispatched\",\"return_path\":\"message\"}]"

start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"leg"}'
eq  "leg: an open leg holds at wait_leg" wait_leg "$(at)"
eq  "leg: the picked request is the worker's" "$REQ" "$(ctx wait_target | jq -r .request)"
tick --with-data '{"watch":"back"}'
eq  "leg: back returns to the hub while the leg is open" wait "$(at)"

(cd "$T" && koto init scope-w1 --template "$T/tpl/scope.md" --var TOPIC=w1 --koto-leg "$REQ:scope" >/dev/null 2>"$T/child.err") ||
    fail "the stand-in worker attaches to its leg" "$(cat "$T/child.err")"
(cd "$T" && koto next scope-w1 --with-data '{"finish":"go"}' >/dev/null 2>&1)
tick --with-data '{"event":"leg"}'
eq  "leg: a promoted result goes through take_report to report_facts" report_facts "$(at)"
case "$(ctx worker_report)" in
    *"outcome scoped"*"pull request https://github.com/acme/widgets/pull/7"*) pass "leg: the leg's outcome and pull request are the report" ;;
    *) fail "leg: the leg's outcome and pull request are the report" "$(ctx worker_report)" ;;
esac
eq  "leg: report_source is leg" leg "$(ctx report_source)"
eq  "leg: report_topic is the worker" w1 "$(ctx report_topic)"

start
tick --with-data '{"go":"wait"}'
put taken_legs "$REQ:scope"
tick --with-data '{"event":"leg"}'
eq  "leg: a leg taken once isn't read again" wait "$(at)"

koto request resolve "$REQ2" scope --with-data '{"status":"success","summary":"hand-made","payload":{"outcome":"scoped"}}' >/dev/null 2>&1
rows "[{\"worker\":\"w2\",\"dispatch_status\":\"dispatched\",\"return_path\":\"leg $REQ2:scope\"}]"
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"leg"}'
eq  "leg: an explicit result goes to surface, never to take_report" surface "$(at)"

# --- the message path ---------------------------------------------------------------------------------

rows "[{\"worker\":\"w1\",\"dispatch_status\":\"dispatched\",\"return_path\":\"leg $REQ:scope\"},
       {\"worker\":\"w3\",\"dispatch_status\":\"dispatched\",\"return_path\":\"message\"}]"
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"report","unit":"w3","report":"PR #9 is ready; CI is green."}'
eq  "message: a message-path worker's report reaches report_facts" report_facts "$(at)"
eq  "message: its text is the report" "PR #9 is ready; CI is green." "$(ctx worker_report)"

start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"report","unit":"w1","report":"done, trust me"}'
eq  "message: a message for a leg-bound worker goes back to wait" wait "$(at)"

start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"report","unit":"w3"}'
eq  "message: a report with no text holds" take_report "$(at)"
(cd "$W" && koto overrides record "$SESS" --gate report_present --rationale "claim" >/dev/null 2>&1)
tick
eq  "message: an override record can't stand in for the text" take_report "$(at)"
tick --with-data '{"withdrawn":"withdrawn"}'
eq  "message: withdrawn returns to the hub" wait "$(at)"

# --- teardown ------------------------------------------------------------------------------------------

O="$T/origin.git"
git init -q --bare "$O"
git clone -q "$O" "$T/seed" 2>/dev/null
printf 'a\n' >"$T/seed/a.txt"
git -C "$T/seed" add a.txt && git -C "$T/seed" commit -q -m init && git -C "$T/seed" branch -M main && git -C "$T/seed" push -q origin main
git --git-dir="$O" symbolic-ref HEAD refs/heads/main
mkdir -p "$T/inst-clean" "$T/inst-dirty"
git clone -q "$O" "$T/inst-clean/repo"
git clone -q "$O" "$T/inst-dirty/repo"
printf 'x\n' >>"$T/inst-dirty/repo/a.txt"
printf '[{"name":"a","path":"%s","session_name":"w5-1a2b3c4d"},{"name":"b","path":"%s","session_name":"w6-1a2b3c4d"}]\n' \
    "$T/inst-clean" "$T/inst-dirty" >"$ST/sessions.json"

start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"retire","unit":"w5"}'
eq  "teardown: retire arrives at teardown, before any inventory" teardown "$(at)"
eq  "teardown: teardown_topic is the worker" w5 "$(ctx teardown_topic)"
tick --with-data '{"teardown":"stopped"}'
eq  "teardown: a durable instance goes on to destroy" destroy "$(at)"
case "$(ctx teardown_verdict)" in
    *"instance $T/inst-clean"*) pass "teardown: the sealed verdict names the inventoried instance" ;;
    *) fail "teardown: the sealed verdict names the inventoried instance" "$(ctx teardown_verdict)" ;;
esac
tick --with-data '{"destroyed":"destroyed"}'
eq  "teardown: destroyed goes to record" record "$(at)"

start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"retire","unit":"w6"}'
tick --with-data '{"teardown":"stopped"}'
eq  "teardown: an instance with unique material goes to promote" promote "$(at)"

start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"retire","unit":"w6"}'
(cd "$W" && koto overrides record "$SESS" --gate inventory_durable --rationale "claim" >/dev/null 2>&1)
tick --with-data '{"teardown":"stopped"}'
eq  "teardown: an override record can't stand in for the inventory" promote "$(at)"

start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"retire","unit":"w5"}'
tick --with-data '{"teardown":"kept"}'
eq  "teardown: kept goes to record with no inventory" record "$(at)"

echo
echo "dispatch-path engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

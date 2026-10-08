#!/usr/bin/env bash
# dispatch-path_engine_test.sh -- the dispatch path's states in real koto.
#
# The skeleton template is built from coordinate.md itself: the state blocks
# for dispatch, wait, leg_pick, wait_leg, leg_spent, take_report, teardown,
# teardown_inventory, promote and destroy are cut out of the shipped template
# unchanged, and every state they route to that isn't under test is a
# terminal stand-in, so a route is read off the state the run stops at. The
# scripts are the shipped ones; koto, its request store and coord-log.sh are
# real; niwa, gh and the record feature's record-holding.sh are stand-ins.
#
# Proves: dispatch doesn't leave on `sent` until the record shows the holding
# dispatched, and no override record can stand in for the gate. A unit whose
# private target the entry point can't take is refused by dispatch-worker.sh
# before any leg, holding or launch, naming the entry point to use instead; so is
# a unit pick wouldn't read, naming the forms that would match, and a dispatch
# with no coord/pick.json in the session exits 2 with nothing written; a leg-bound
# worker's promoted result reaches take_report and report_facts with the leg's
# outcome as the report, an open leg holds until back or rescan, an explicit,
# abandoned or missing leg goes to leg_spent, and a leg read once isn't read
# again; a leg cancelled before its worker reported is replaced for the same
# holding by dispatch-worker.sh --releg, leg_spent's `replaced` goes to
# record, and the worker's later result arrives on the new leg (shirabe#506); a message
# report for a message-path worker reaches report_facts, one for a leg-bound
# worker goes back to wait, and one with no text holds until withdrawn; a
# leg-bound worker's progress message passes take_report as progress and
# leaves its leg open, and the leg's later result still arrives through
# wait_leg (shirabe#491);
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
# koto's recorded command environment hides this harness's stand-in variables
# from the commands koto runs; the knob keeps the old environment where the
# koto accepts it (scripts/lib/koto-legacy-env.sh; temporary, #483).
. "$HERE/../../../scripts/lib/koto-legacy-env.sh"
koto_legacy_env_enable
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
    teardown-inventory.sh github-refs.sh teardown-verdict.sh coord-log.sh dispatch-worker.sh render-brief.sh; do
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
        --row-file) MODE=write; ROWF="$2"; shift 2 ;;
        --session) shift 2 ;;
        *) exit 64 ;;
    esac
done
case "$MODE" in
    list) cat "$ST/rows.json" ;;
    write) jq -c --arg t "$TOPIC" --slurpfile r "$ROWF" '[.[] | select(.worker != $t)] + $r' "$ST/rows.json" >"$ST/rows.tmp" && mv "$ST/rows.tmp" "$ST/rows.json" ;;
    read) jq -ce --arg t "$TOPIC" '.[] | select(.worker == $t)' "$ST/rows.json" || exit 1 ;;
    *) exit 64 ;;
esac
EOF
BIN="$T/bin"
mkdir -p "$BIN"
# niwa: `list --json` names each worker's instance.
cat >"$BIN/niwa" <<'EOF'
#!/usr/bin/env bash
[ "$1" = list ] || { printf '%s\n' "$*" >>"$ST/niwa.log"; exit 64; }
cat "$ST/sessions.json"
EOF
# gh: no merged pull requests; a tree read answers from the local origin; a
# repository read answers its visibility (acme/vault is private).
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2 $3 $4" in
    "api --method GET repos/acme/vault") printf '{"visibility":"private"}\n'; exit 0 ;;
    "api --method GET repos/acme/widgets") printf '{"visibility":"public"}\n'; exit 0 ;;
esac
if [ "$1" = api ]; then
    sha=${2##*/trees/}; sha=${sha%%\?*}
    git --git-dir="$O" ls-tree -r "$sha" |
        jq -R -s '{truncated: false, tree: [split("\n")[] | select(length > 0) | split("\t") as $f | ($f[0] | split(" ")) as $m | {path: $f[1], type: $m[1], sha: $m[2]}]}'
fi
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
UNDER="dispatch wait leg_pick wait_leg leg_spent take_report teardown teardown_inventory promote destroy"
# Every state an UNDER state routes to that isn't under test, as a terminal.
ENDS="record failure report_facts surface pick_facts quiet_check decision_apply merged_facts rotation_close done_stopped roadmap_status
decision_answer decision_evidence decision_raise"
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
  ROADMAP:
    description: roadmap (wait's landed edge tests it)
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
    for st in $ENDS; do
        printf '  %s:\n    terminal: true\n\n' "$st"
    done
    echo '---'
    for st in entry $UNDER $ENDS; do
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
    # $KOTO_LEGACY_ENV_ARG: #483.
    (cd "$W" && koto init "$SESS" $KOTO_LEGACY_ENV_ARG --template "$TPL" --var PLUGIN_ROOT="$PR" >/dev/null 2>"$T/init.err") ||
        fail "session $SESS starts" "$(cat "$T/init.err")"
}
tick() { (cd "$W" && koto next "$SESS" --no-cleanup "$@" >"$T/next.json" 2>&1); }
at() { (cd "$W" && koto status "$SESS" 2>/dev/null) | jq -r '.current_state // .state // "gone"'; }
ctx() { koto context get "$SESS" "$1" 2>/dev/null; }
put() { printf '%s' "$2" >"$T/v"; koto context add "$SESS" "$1" --from-file "$T/v" >/dev/null; }
rows() { printf '%s\n' "$1" >"$ST/rows.json"; }
# requests <topic>: how many koto requests name the topic's coordinator, the
# coordinate-<topic> that dispatch-worker.sh opens a worker's leg under.
requests() { (cd "$W" && koto request list --coordinator-of-record "coordinate-$1") | jq '.requests | length'; }

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
tick --with-data '{"dispatched":"failed","topic":"w1"}'
eq  "dispatch: failed goes to failure" failure "$(at)"

# --- a unit whose target an entry point can't take ------------------------------------------------
#
# The shipped table restricts no entry point; a restricted copy (/deliver takes
# only public repositories and names /work-on instead) stands in for the next
# requirement. The unit lands in a private repository. dispatch-worker.sh runs
# for real against this session's context and koto's real request store: it
# refuses at its brief check, before a leg is opened, a holding written or a
# worker launched, and the dispatch state can't leave on `sent`.
RT="$T/restricted.tsv"
awk -F'\t' 'BEGIN { OFS = "\t" } /^#/ { next } NF < 5 { next }
    $1 == "deliver" { $6 = "public"; $7 = "work-on" } { print }' "$HERE/../references/entry-points.tsv" >"$RT"
cat >"$T/brief-private.json" <<'EOF'
{"topic": "w9", "repo": "acme/vault", "unit": "Feature 9: the vault export",
 "entry_point": "deliver", "entry_args": ["w9"], "run_mode": "--auto", "phase": "executing",
 "authority": "You are working for the owner on acme/vault.", "goal": "The export ships.",
 "checkpoints": ["The PR is ready with every CI job green."], "acceptance": ["CI is green per job."],
 "dispatcher_session": "coord-dp"}
EOF
start
put dispatch_topic w9
koto context add "$SESS" brief_input.json --from-file "$T/brief-private.json" >/dev/null
# What pick_facts listed: the brief's unit is a form pick reads.
put coord/pick.json '{"scope":"roadmap","name":"vault","units":[{"unit":"Feature 9","number":9,"title":"the vault export"}]}'
rows '[]'
: >"$ST/niwa.log"
printf '[]\n' >"$ST/sessions.json"
tick --with-data '{"go":"dispatch"}'
DW_ERR=$( (cd "$W" && DC_ENTRY_POINTS="$RT" bash "$S/dispatch-worker.sh" --session "$SESS") 2>&1 >/dev/null)
DW_RC=$?
eq  "private target: dispatch-worker.sh refuses the brief (exit 1)" 1 "$DW_RC"
case "$DW_ERR" in
    *"/shirabe:deliver takes only public repositories, and repo is private; dispatch it to /shirabe:work-on instead"*)
        pass "private target: the refusal names the requirement and the alternative" ;;
    *) fail "private target: the refusal names the requirement and the alternative" "$DW_ERR" ;;
esac
case "$DW_ERR" in *acme/vault*) fail "private target: the refusal names the private repository" "$DW_ERR" ;;
    *) pass "private target: the refusal never names the private repository" ;; esac
eq  "private target: no holding was written" '[]' "$(cat "$ST/rows.json")"
eq  "private target: no request (and so no leg) was opened" 0 "$(requests w9)"
eq  "private target: no worker was launched" "" "$(cat "$ST/niwa.log")"
tick --with-data '{"dispatched":"sent","topic":"w9"}'
eq  "private target: sent can't leave dispatch without the holding" dispatch "$(at)"
# The shipped table: the same unit passes the check.
(cd "$W" && bash "$S/render-brief.sh" --input "$T/brief-private.json" --stdout >/dev/null)
eq  "private target: the shipped table's /deliver takes it" 0 "$?"

# --- the unit pick reads -------------------------------------------------------------------------
#
# dispatch-worker.sh against this session's real context: a unit no form of
# which pick listed is refused before any leg, holding or launch, naming the
# forms; with no coord/pick.json in the session it exits 2, also with nothing
# written.
sed -e 's/"w9"/"w11"/g' -e 's/"Feature 9: the vault export"/"Feature 9 of ROADMAP-vault"/' -e 's|"acme/vault"|"acme/widgets"|' \
    "$T/brief-private.json" >"$T/brief-unit.json"
unit_dispatch() { # unit_dispatch <topic> <brief>: a fresh session at dispatch, then dispatch-worker.sh
    start
    put dispatch_topic "$1"
    koto context add "$SESS" brief_input.json --from-file "$2" >/dev/null
    rows '[]'
    : >"$ST/niwa.log"
    printf '[]\n' >"$ST/sessions.json"
    tick --with-data '{"go":"dispatch"}'
}
unit_dispatch w11 "$T/brief-unit.json"
put coord/pick.json '{"scope":"roadmap","name":"vault","host":"acme/widgets","units":[{"unit":"Feature 9","number":9,"title":"the vault export"}]}'
DW_ERR=$( (cd "$W" && bash "$S/dispatch-worker.sh" --session "$SESS") 2>&1 >/dev/null)
eq  "unit: a unit pick wouldn't read is refused (exit 1)" 1 "$?"
case "$DW_ERR" in
    *'unit: [Feature 9 of ROADMAP-vault] matches no unit pick listed'*'"Feature 9", "Feature 9: the vault export"'*)
        pass "unit: the refusal names the forms that would match" ;;
    *) fail "unit: the refusal names the forms that would match" "$DW_ERR" ;;
esac
eq  "unit: no holding was written" '[]' "$(cat "$ST/rows.json")"
eq  "unit: no request (and so no leg) was opened" 0 "$(requests w11)"
eq  "unit: no worker was launched" "" "$(cat "$ST/niwa.log")"
unit_dispatch w12 "$(sed 's/"w11"/"w12"/g' "$T/brief-unit.json" >"$T/brief-unit2.json"; printf '%s' "$T/brief-unit2.json")"
(cd "$W" && bash "$S/dispatch-worker.sh" --session "$SESS" >/dev/null 2>&1)
eq  "unit: with no coord/pick.json in the session, exit 2" 2 "$?"
eq  "unit: and nothing was written" '[]' "$(cat "$ST/rows.json")"
eq  "unit: no request was opened" 0 "$(requests w12)"
eq  "unit: nor launched" "" "$(cat "$ST/niwa.log")"
# The control: the same query sees the request a dispatch past the check
# opens (the stand-in launch then fails), so the zeros above can fail.
sed -e 's/"w11"/"w13"/g' -e 's/"Feature 9 of ROADMAP-vault"/"Feature 9"/' "$T/brief-unit.json" >"$T/brief-unit3.json"
unit_dispatch w13 "$T/brief-unit3.json"
put coord/pick.json '{"scope":"roadmap","name":"vault","host":"acme/widgets","units":[{"unit":"Feature 9","number":9,"title":"the vault export"}]}'
(cd "$W" && bash "$S/dispatch-worker.sh" --session "$SESS" >/dev/null 2>&1)
[ "$(requests w13)" -ge 1 ] && pass "unit: control: a unit pick reads gets past the check and its request is seen" \
    || fail "unit: control: a unit pick reads gets past the check and its request is seen" "$(requests w13)"

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
eq  "leg: an explicit result goes to leg_spent, never to take_report" leg_spent "$(at)"
eq  "leg: a consumed leg is marked for the next pick" yes "$(ctx leg_consumed)"

REQ4=$(koto request create --role scope --template scope.md --inputs '{"TOPIC":"w7"}' \
    --requested-by coord --coordinator-of-record coordinate-w7 | jq -r .request_id)
koto request abandon-request "$REQ4" --rationale "the worker is gone" >/dev/null 2>&1
rows "[{\"worker\":\"w7\",\"dispatch_status\":\"dispatched\",\"return_path\":\"leg $REQ4:scope\"}]"
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"leg"}'
eq  "leg: an abandoned leg goes to leg_spent" leg_spent "$(at)"

# A leg still open on a closed request can't resolve: it goes to surface once,
# and the next pick doesn't offer it again.
REQ6=$(koto request create --role scope --template scope.md --inputs '{"TOPIC":"w10"}' \
    --requested-by coord --coordinator-of-record coordinate-w10 | jq -r .request_id)
koto request close "$REQ6" >/dev/null 2>&1
rows "[{\"worker\":\"w10\",\"dispatch_status\":\"dispatched\",\"return_path\":\"leg $REQ6:scope\"}]"
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"leg"}'
eq  "leg: an open leg on a closed request goes to leg_spent" leg_spent "$(at)"
TARGET10=$(ctx wait_target)
start
tick --with-data '{"go":"wait"}'
put wait_target "$TARGET10"
put leg_consumed yes
tick --with-data '{"event":"leg"}'
eq  "leg: that leg isn't offered again" wait "$(at)"

# A leg the request doesn't have (the holding names the wrong leg) is missing.
rows "[{\"worker\":\"w1\",\"dispatch_status\":\"dispatched\",\"return_path\":\"leg $REQ:execute\"}]"
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"leg"}'
eq  "leg: a missing leg goes to leg_spent" leg_spent "$(at)"

# While a leg is open, an override record can't stand in for its result.
REQ5=$(koto request create --role scope --template scope.md --inputs '{"TOPIC":"w8"}' \
    --requested-by coord --coordinator-of-record coordinate-w8 | jq -r .request_id)
rows "[{\"worker\":\"w8\",\"dispatch_status\":\"dispatched\",\"return_path\":\"leg $REQ5:scope\"}]"
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"leg"}'
(cd "$W" && koto overrides record "$SESS" --gate leg_result --rationale "claim" >/dev/null 2>&1)
tick
eq  "leg: an override record can't stand in for an open leg's result" wait_leg "$(at)"

# The leg resolves between two ticks and the coordinator submits rescan: the
# gate takes the result on that evidence tick, where wait_leg's action doesn't
# run, so the mark has to come from the consuming edge.
(cd "$T" && koto init scope-w8 --template "$T/tpl/scope.md" --var TOPIC=w8 --koto-leg "$REQ5:scope" >/dev/null 2>&1)
(cd "$T" && koto next scope-w8 --with-data '{"finish":"go"}' >/dev/null 2>&1)
tick --with-data '{"watch":"rescan"}'
eq  "leg: a result taken on a rescan tick reaches report_facts" report_facts "$(at)"
eq  "leg: that edge marks the leg consumed" yes "$(ctx leg_consumed)"
TARGET8=$(ctx wait_target)
start
tick --with-data '{"go":"wait"}'
put wait_target "$TARGET8"
put leg_consumed yes
tick --with-data '{"event":"leg"}'
eq  "leg: a leg consumed on a rescan tick isn't read again" wait "$(at)"
case "$(ctx taken_legs)" in
    *"$REQ5:scope"*) pass "leg: the next pick marks it taken" ;;
    *) fail "leg: the next pick marks it taken" "$(ctx taken_legs)" ;;
esac

# --- a leg spent before the worker reported, replaced -----------------------------------------------
#
# A scope worker on w20's leg is cancelled before it reports. leg_spent: the
# coordinator puts the brief input back, runs dispatch-worker.sh --releg for
# real (koto's request store, the holding through the record stand-in), and
# submits replaced, which goes to record. The holding is on a new leg; the
# next wait picks it, and the worker's later result on it reaches
# report_facts.
REQ20=$(koto request create --role scope --template scope.md --inputs '{"TOPIC":"w20"}' \
    --requested-by coord --coordinator-of-record coordinate-w20 | jq -r .request_id)
# Cancelled by hand: an explicit result, which no session of the worker's
# promoted.
koto request resolve "$REQ20" scope --with-data '{"status":"failure","summary":"cancelled: the target moved","payload":{"outcome":"cancelled"}}' >/dev/null 2>&1
rows "[{\"worker\":\"w20\",\"unit\":\"Feature 9\",\"entry_point\":\"scope\",\"mode\":\"--auto --intent=continue\",\"phase\":\"scoping-ahead\",
       \"dispatch_status\":\"dispatched\",\"return_path\":\"leg $REQ20:scope\",\"repo\":\"acme/widgets\",\"branch\":\"\",
       \"verified_head\":\"\",\"dispatched\":\"2026-09-26\",\"pull_request\":\"\"}]"
printf '[{"name":"x","path":"/p","session_name":"w20-0123abcd"}]\n' >"$ST/sessions.json"
: >"$ST/niwa.log"
cat >"$T/brief-w20.json" <<'EOF'
{"topic": "w20", "repo": "acme/widgets", "unit": "Feature 9",
 "entry_point": "scope", "entry_args": ["w20"], "run_mode": "--auto --intent=continue", "phase": "scoping-ahead",
 "authority": "You are working for the owner on acme/widgets.", "goal": "Feature 9 is scoped.",
 "checkpoints": ["The scoping PR is open."], "acceptance": ["A PLAN exists."],
 "dispatcher_session": "coord-dp"}
EOF
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"leg"}'
eq  "releg: a cancelled leg goes to leg_spent" leg_spent "$(at)"
eq  "releg: report_topic names the worker" w20 "$(ctx report_topic)"
koto context add "$SESS" brief_input.json --from-file "$T/brief-w20.json" >/dev/null
( cd "$W" && bash "$S/dispatch-worker.sh" --session "$SESS" --releg >"$T/releg.out" 2>"$T/releg.err" )
eq  "releg: dispatch-worker.sh --releg replaces the leg (exit 0)" 0 "$?"
NEWRP=$(jq -r '.[] | select(.worker == "w20") | .return_path' "$ST/rows.json")
NEWREQ=${NEWRP#leg }; NEWREQ=${NEWREQ%%:*}
case "$NEWRP" in
    "leg $REQ20:scope") fail "releg: the holding is on a new leg" "$NEWRP" ;;
    "leg "*":scope") pass "releg: the holding is on a new leg" ;;
    *) fail "releg: the holding is on a new leg" "$NEWRP $(cat "$T/releg.err")" ;;
esac
grep -q "^leg=$NEWREQ:scope$" "$T/releg.out" && pass "releg: the new leg is printed for the brief" || fail "releg: the new leg is printed" "$(cat "$T/releg.out")"
eq  "releg: the worker is not launched again" "" "$(grep dispatch "$ST/niwa.log" 2>/dev/null)"
eq  "releg: the holding is the same, still dispatched" dispatched "$(jq -r '.[] | select(.worker == "w20") | .dispatch_status' "$ST/rows.json")"
tick --with-data '{"move":"replaced","topic":"w20"}'
eq  "releg: replaced goes to record" record "$(at)"
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"leg"}'
eq  "releg: the next wait reads the new leg" "$NEWREQ" "$(ctx wait_target | jq -r .request)"
(cd "$T" && koto init scope-w20 --template "$T/tpl/scope.md" --var TOPIC=w20 --koto-leg "$NEWREQ:scope" >/dev/null 2>"$T/child.err") ||
    fail "releg: the worker attaches to the new leg" "$(cat "$T/child.err")"
(cd "$T" && koto next scope-w20 --with-data '{"finish":"go"}' >/dev/null 2>&1)
tick --with-data '{"watch":"rescan"}'
eq  "releg: the worker's later result arrives on the new leg" report_facts "$(at)"
eq  "releg: the report is w20's" w20 "$(ctx report_topic)"
REQ21=$(koto request create --role scope --template scope.md --inputs '{"TOPIC":"w21"}' \
    --requested-by coord --coordinator-of-record coordinate-w21 | jq -r .request_id)
koto request abandon-request "$REQ21" --rationale "the worker is gone" >/dev/null 2>&1
rows "[{\"worker\":\"w21\",\"dispatch_status\":\"dispatched\",\"return_path\":\"leg $REQ21:scope\"}]"
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"leg"}'
tick --with-data '{"move":"surface"}'
eq  "leg_spent: surface goes to the human" surface "$(at)"

# --- progress from a leg-bound worker ----------------------------------------------------------------
REQ30=$(koto request create --role scope --template scope.md --inputs '{"TOPIC":"w30"}' \
    --requested-by coord --coordinator-of-record coordinate-w30 | jq -r .request_id)
rows "[{\"worker\":\"w30\",\"dispatch_status\":\"dispatched\",\"return_path\":\"leg $REQ30:scope\"}]"
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"progress","unit":"w30","report":"Checkpoint 1 reached."}'
eq  "progress, leg: a leg-bound worker's progress passes take_report" report_facts "$(at)"
eq  "progress, leg: as progress, not as its result" progress "$(ctx report_source)"
eq  "progress, leg: its leg is still open" open "$(koto request get "$REQ30" | jq -r '(.request // .) | .legs.scope.disposition')"
(cd "$T" && koto init scope-w30 --template "$T/tpl/scope.md" --var TOPIC=w30 --koto-leg "$REQ30:scope" >/dev/null 2>&1)
(cd "$T" && koto next scope-w30 --with-data '{"finish":"go"}' >/dev/null 2>&1)
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"leg"}'
eq  "progress, leg: the leg's later result arrives through wait_leg" report_facts "$(at)"
eq  "progress, leg: as the leg's result" leg "$(ctx report_source)"
start
rows '[]'
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"progress","unit":"nobody","report":"Checkpoint 1 reached."}'
eq  "progress: from a topic with no holding goes back to wait" wait "$(at)"

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
eq  "message: the hub clears the report's topic" "" "$(ctx report_topic)"

start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"report","unit":"w3","report":"   "}'
eq  "message: a report of only whitespace holds" take_report "$(at)"

# A report with no topic can't be checked against the record: it holds, no
# override record moves it, and withdrawn is its way back.
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"report","report":"done"}'
eq  "message: a report naming no worker holds" take_report "$(at)"
(cd "$W" && koto overrides record "$SESS" --gate report_source_ok --rationale "claim" >/dev/null 2>&1)
tick
eq  "message: an override record can't stand in for the source check" take_report "$(at)"
tick --with-data '{"withdrawn":"withdrawn"}'
eq  "message: withdrawn returns to the hub when the record can't be read for it" wait "$(at)"

# A report that can never be checked goes to the human rather than back.
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"report","report":"done"}'
tick --with-data '{"withdrawn":"unreadable"}'
eq  "message: a report that can never be checked goes to the human" surface "$(at)"

# The context keys a leg report rests on can be rewritten in the session; a
# report rewritten that way is refused because it isn't what koto holds for
# the leg.
rows "[{\"worker\":\"w1\",\"dispatch_status\":\"dispatched\",\"return_path\":\"leg $REQ:scope\"},
       {\"worker\":\"w3\",\"dispatch_status\":\"dispatched\",\"return_path\":\"message\"}]"
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"report","unit":"w3"}'
put report_topic w1
put report_source leg
put wait_target "{\"path\":\"leg\",\"topic\":\"w1\",\"request\":\"$REQ\",\"leg\":\"scope\",\"disposition\":\"resolved\"}"
put worker_report "leg result: status success; final state done; outcome scoped; step ; reason ; pull request https://github.com/acme/widgets/pull/666"
tick
eq  "message: a leg report rewritten in context is refused, and goes to the human" surface "$(at)"
eq  "message: that surface step still names the worker" w1 "$(ctx report_topic)"
eq  "message: and the rewritten report is cleared" "" "$(ctx worker_report)"

# --- teardown ------------------------------------------------------------------------------------------

export O="$T/origin.git"
git init -q --bare "$O"
# Clones name a github.com origin, as a worker's do; git rewrites it to the
# local bare repository.
GHURL=https://github.com/acme/widgets
git config --file "$HOME/.gitconfig" "url.$O.insteadOf" "$GHURL"
git config --file "$HOME/.gitconfig" --add "url.$O.insteadOf" "$GHURL.git"
git config --file "$HOME/.gitconfig" protocol.file.allow always
git clone -q "$O" "$T/seed" 2>/dev/null
printf 'a\n' >"$T/seed/a.txt"
git -C "$T/seed" add a.txt && git -C "$T/seed" commit -q -m init && git -C "$T/seed" branch -M main && git -C "$T/seed" push -q origin main
git --git-dir="$O" symbolic-ref HEAD refs/heads/main
mkdir -p "$T/inst-clean" "$T/inst-dirty"
git clone -q "$GHURL" "$T/inst-clean/repo"
git clone -q "$GHURL" "$T/inst-dirty/repo"
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
eq  "teardown: leaving teardown clears teardown_topic" "" "$(ctx teardown_topic)"

start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"retire","unit":"w5"}'
tick --with-data '{"teardown":"stopped"}'
tick --with-data '{"destroyed":"refused"}'
eq  "teardown: a refused verdict read goes to surface, destroying nothing" surface "$(at)"

# A worker with no instance can't be inventoried: the verdict is sealed as an
# error and goes to the human, rather than holding the run at the inventory.
start
tick --with-data '{"go":"wait"}'
tick --with-data '{"event":"retire","unit":"w9"}'
tick --with-data '{"teardown":"stopped"}'
eq  "teardown: no instance for the worker goes to surface" surface "$(at)"
case "$(ctx teardown_verdict)" in
    error*) pass "teardown: that verdict is sealed as an error" ;;
    *) fail "teardown: that verdict is sealed as an error" "$(ctx teardown_verdict)" ;;
esac

echo
echo "dispatch-path engine: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

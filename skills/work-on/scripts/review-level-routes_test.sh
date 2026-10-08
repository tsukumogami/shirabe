#!/usr/bin/env bash
# review-level-routes_test.sh -- the review level, routed through the shipped
# work-on.md by a real koto
# Part of the work-on skill
#
# review-level_test.sh pins review-level.sh on its own, against a stand-in and
# a scratch template. This suite drives the template that ships: real koto
# sessions of skills/work-on/koto-templates/work-on.md, walked from entry
# through analysis, the level choice, implementation and the level check to
# the panels the level names. Each case is one of the routing promises the
# level makes:
#
#   the declarations    the three variables, their pattern, the rebind flag,
#                       the level check's gates and the one veto criterion no
#                       route reads; the pattern is enforced at init
#   the choice          plan_ready with no level waits at review_level_choice
#                       and never reaches implementation; after `set` it does
#   light               light_review, then verification; never scrutiny,
#                       review or qa_validation
#   standard            scrutiny, review, verification; never qa_validation,
#                       also for a change of only .md files under skills/
#   full                scrutiny, review, qa_validation, verification
#   docs and task       record a level and reach verification as before
#   the floor           a light run below a standard floor holds before any
#                       panel, naming the rule; a raise lets it into scrutiny,
#                       and the ledger has floor_raise, then a standard check
#   a retry             a blocking light round returns to implementation with
#                       its seat in the verdict ledger; a fix past 40 changed
#                       lines then holds the light run until it is raised
#   a hand rebind       holds the check, naming both levels; made later, in
#                       review or light_review, it holds that state's passed
#                       routes until `set` puts the ledger's level back
#   unset               a session with no level at the check takes all three
#                       panels and its ledger has an `unset` line
#   clearing sites      every retry clearing loop that removes the panels'
#                       results removes light_results.json too, and none
#                       names review_level.jsonl
#
# The light retry runs the clearing block shipped in phase-4d-light.md, so an
# edit that breaks it fails here.
#
# Usage: review-level-routes_test.sh
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the engine cases skipped
#   1 -- one or more cases failed
#
# Without koto the file-only cases (the clearing sites) still run and the
# engine cases skip with a note: the macOS floor leg has no koto, and the Linux
# leg of check-work-on-scripts.yml installs it.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
PHASES="$SKILL_DIR/references/phases"
# koto validates a variable value against ^[a-zA-Z0-9._/:@ \-]*$; a checkout
# under a directory outside it is reached through a symlink below.
PLUGIN_ROOT=$(cd "$SKILL_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }
[ -f "$TEMPLATE" ] || { echo "FAIL: template not found at $TEMPLATE" >&2; exit 1; }

# ==============================================================================
echo "--- files: every retry clearing site"

# A clearing site is a `for KEY in ...` line that removes a panel's results.
SITES=$(grep -rn --include='*.md' '^for KEY in .*_results\.json' "$SKILL_DIR" 2>/dev/null)
N=$(printf '%s\n' "$SITES" | grep -c . | tr -d ' ')
# Seven blocks the agent runs. The eighth used to be verification's, before
# koto took that state's routing; implementation's clear_on_entry list stands
# in for it now and is checked below with the same rules.
[ "$N" -ge 7 ] && pass "found $N clearing sites" || fail "found only $N clearing sites: $SITES"
MISSING=$(printf '%s\n' "$SITES" | grep 'qa_results\.json' | grep -v 'light_results\.json')
[ -z "$MISSING" ] && pass "every site that clears qa_results.json also clears light_results.json" \
    || fail "sites without light_results.json: $MISSING"
for k in scrutiny_results.json review_results.json qa_results.json light_results.json; do
    WITHOUT=$(printf '%s\n' "$SITES" | grep -v "$k")
    [ -z "$WITHOUT" ] && pass "every site clears $k" || fail "sites without $k: $WITHOUT"
done
LEDGER_HITS=$(grep -rn 'context remove.*review_level\|^for KEY in .*review_level' "$SKILL_DIR" --include='*.md' --include='*.sh' 2>/dev/null \
    | grep -v '_test\.sh:')
[ -z "$LEDGER_HITS" ] && pass "no clearing site names review_level.jsonl" || fail "a clearing site names the ledger: $LEDGER_HITS"
printf '%s\n' "$SITES" | grep -q 'phase-4d-light\.md' && pass "the light panel has its own clearing block" \
    || fail "phase-4d-light.md has no clearing block"
# implementation's clear_on_entry: koto clears these whenever the run comes
# back to implementation, which is the only clearing on verification's exit-1
# edge, since koto takes that edge itself.
CLEAR_ON_ENTRY=$(awk '$0 == "  implementation:" { f = 1; next } f && /^  [a-z_]+:$/ { exit } f && /^    clear_on_entry:/ { print; exit }' "$TEMPLATE")
for k in scrutiny_results.json review_results.json qa_results.json light_results.json summary.md; do
    printf '%s\n' "$CLEAR_ON_ENTRY" | grep -q "$k" && pass "implementation's clear_on_entry clears $k" \
        || fail "implementation's clear_on_entry does not clear $k: [$CLEAR_ON_ENTRY]"
done
printf '%s\n' "$CLEAR_ON_ENTRY" | grep -q 'review_level' && fail "implementation's clear_on_entry names the ledger" \
    || pass "implementation's clear_on_entry leaves review_level.jsonl alone"

# ==============================================================================
command -v koto >/dev/null 2>&1 || {
    echo "SKIP: koto not on PATH -- engine cases did not run"
    echo
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
}

WORKDIR=$(mktemp -d)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

export HOME="$WORKDIR/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t

case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        PLUGIN_ROOT="$WORKDIR/plugin"
        ;;
esac
RL="$PLUGIN_ROOT/skills/work-on/scripts/review-level.sh"
PS="$PLUGIN_ROOT/skills/work-on/scripts/panel-scope.sh"

# ==============================================================================
echo "--- engine: the declarations"

COMPILED=$(koto template compile "$TEMPLATE" 2>"$WORKDIR/compile.err" | tail -n 1)
if [ -f "$COMPILED" ]; then
    pass "work-on.md compiles on $(koto version 2>/dev/null | head -n 1)"
else
    fail "work-on.md does not compile: $(cat "$WORKDIR/compile.err")"
    COMPILED=/dev/null
fi
for v in REVIEW_LEVEL REVIEW_FLOOR REVIEW_CEILING; do
    GOT=$(jq -r --arg v "$v" '.variables[$v] | "\(.required // false)|\(.pattern // "")"' "$COMPILED" 2>/dev/null)
    [ "$GOT" = 'false|^(light|standard|full)?$' ] && pass "$v is optional with the level pattern" \
        || fail "$v is declared [$GOT]"
done
GOT=$(jq -r '[.variables.REVIEW_LEVEL.rebind, .variables.REVIEW_FLOOR.rebind, .variables.REVIEW_CEILING.rebind]
             | map(. // false) | map(tostring) | join(",")' "$COMPILED" 2>/dev/null)
[ "$GOT" = "true,false,false" ] && pass "only REVIEW_LEVEL is rebindable" || fail "rebind flags are [$GOT]"
GOT=$(jq -r '.states.analysis.transitions[] | select(.when.plan_outcome == "plan_ready") | .target' "$COMPILED" 2>/dev/null)
[ "$GOT" = review_level_choice ] && pass "plan_ready targets review_level_choice" || fail "plan_ready targets [$GOT]"
GOT=$(jq -r '.states.issue_type_routing.transitions[] | select(.when.issue_type == "code") | .target' "$COMPILED" 2>/dev/null)
[ "$GOT" = review_level_check ] && pass "the code route targets review_level_check" || fail "the code route targets [$GOT]"
GOT=$(jq -r '.states.review_level_check.gates | [.level_floor.type, .level_fits_facts.type] | join(",")' "$COMPILED" 2>/dev/null)
[ "$GOT" = "command,decider-check" ] && pass "review_level_check has the level_floor command gate and the decider check" \
    || fail "review_level_check's gates are [$GOT]"
GOT=$(jq -r '.states.review_level_check.gates.level_fits_facts.decider_check
             | "\(.max_bytes)|\([.criteria[] | "\(.rule_id):\(.mode)"] | join(","))"' "$COMPILED" 2>/dev/null)
[ "$GOT" = "2048|level_fits_facts:veto" ] && pass "the decider check has one criterion, in veto, under a 2048-byte budget" \
    || fail "the decider check is [$GOT]"
GOT=$(jq -r '[.states[].transitions[]?.when // {} | keys[] | select(startswith("gates.level_fits_facts"))] | length' "$COMPILED" 2>/dev/null)
[ "$GOT" = 0 ] && pass "no route reads the decider check" || fail "$GOT when clauses read level_fits_facts"
GOT=$(jq -r '.states.review_level_check.default_action.command // ""' "$COMPILED" 2>/dev/null)
case "$GOT" in *"review-level.sh facts"*) pass "the level check's action gathers the facts" ;; *) fail "the level check's action is [$GOT]" ;; esac
GOT=$(jq -r '.states.review_level_choice.default_action.command // ""' "$COMPILED" 2>/dev/null)
case "$GOT" in *"review-level.sh init"*) pass "the level choice's action records the bound" ;; *) fail "the level choice's action is [$GOT]" ;; esac

# --- the repository the gates and actions read ---------------------------------

REPO="$WORKDIR/repo"
mkdir -p "$REPO"
(
    cd "$REPO" || exit 1
    git init -q -b main .
    mkdir -p docs skills/demo
    seq 1 60 > docs/notes.md
    seq 1 20 > skills/demo/SKILL.md
    git add -A
    git commit -q -m init
) >/dev/null 2>&1
cd "$REPO" || exit 1
MAIN=$(git rev-parse main)

NEXT_RESPONSE=""
NEXT_STATE=""
# tick <session> [<evidence>]: one `koto next`; NEXT_STATE is where it stopped.
LAST_SESSION=""
tick() {
    LAST_SESSION=$1
    if [ -n "${2:-}" ]; then
        NEXT_RESPONSE=$(koto next "$1" --with-data "$2" --no-cleanup 2>/dev/null)
    else
        NEXT_RESPONSE=$(koto next "$1" --no-cleanup 2>/dev/null)
    fi
    NEXT_STATE=$(koto status "$1" 2>/dev/null | jq -r '.current_state // empty')
}

visits() {
    # $1 session, $2 state: transitions into the state in koto's own log
    jq -s --arg st "$2" '[.[] | select(.type == "transitioned" and .payload.to == $st)] | length' \
        "$HOME/.koto/sessions/$1/koto-$1.state.jsonl" 2>/dev/null
}
ledger() { koto context get "$1" review_level.jsonl 2>/dev/null; }
events() { ledger "$1" | jq -r .event | tr '\n' ' ' | sed 's/ $//'; }
seed() { printf '{"passed": true, "round": 1}\n' | koto context add "$1" "$2" >/dev/null 2>&1; }
setlevel() {
    # $1 session, $2 level, then any set flags
    local s=$1 l=$2
    shift 2
    "$RL" set "$s" "$l" "$@" >/dev/null 2>"$WORKDIR/set.err" \
        || fail "$s: review-level.sh set $l failed: $(cat "$WORKDIR/set.err")"
}
# entered_verification <session>: the last transition in koto's own log went
# into or out of verification. koto runs that state itself on entry, and these
# fixtures commit no verification map, so a run that reaches it fails closed
# at done_blocked in the same tick.
entered_verification() {
    [ "$(jq -rs '[.[] | select(.type == "transitioned")] | last
                 | (.payload.to == "verification" or .payload.from == "verification")' \
        "$HOME/.koto/sessions/$1/koto-$1.state.jsonl" 2>/dev/null)" = true ]
}
expect_state() {
    # $1 label, $2 expected state
    if [ "$NEXT_STATE" = "$2" ]; then
        pass "$1: at $2"
    elif [ "$2" = verification ] && entered_verification "$LAST_SESSION"; then
        pass "$1: reached verification (and failed closed there: no map in the fixture)"
    else
        fail "$1: at [$NEXT_STATE], expected $2"
    fi
}
expect_visits() {
    # $1 session, $2 state, $3 expected count
    local n
    n=$(visits "$1" "$2")
    [ "$n" = "$3" ] && pass "$1: $3 transition(s) into $2" || fail "$1: $n transition(s) into $2, expected $3"
}

# new_case <session> <change>: a branch off main carrying one commit made by
# <change>, and a session walked to review_level_choice with impl_base at main.
new_case() {
    local s=$1
    git checkout -q main
    git checkout -q -b "case-$s"
    eval "$2"
    git add -A
    git commit -q -m "work for $s"
    koto init "$s" --template "$TEMPLATE" --var ARTIFACT_PREFIX=issue_42 --var ISSUE_NUMBER=42 \
        --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1 || { fail "$s: koto init failed"; return 1; }
    tick "$s" '{"mode":"issue_backed","issue_number":"42"}'
    tick "$s" '{"status":"override"}'
    # staleness_check routes on its own gate: no GitHub remote, so exit 3.
    tick "$s" '{"status":"override"}'
    printf '# Issue\n\n## Acceptance Criteria\n\n- [ ] it works\n' | koto context add "$s" context.md >/dev/null 2>&1
    printf 'plan\n' | koto context add "$s" plan.md >/dev/null 2>&1
    tick "$s" '{"plan_outcome":"plan_ready"}'
    printf '%s\n' "$MAIN" | koto context add "$s" impl_base >/dev/null 2>&1
    return 0
}

# choose_and_implement <session> <level> <type>: chooses the level, finishes
# implementation and answers the type question.
choose_and_implement() {
    setlevel "$1" "$2"
    tick "$1"
    [ "$NEXT_STATE" = implementation ] || { fail "$1: after set, at [$NEXT_STATE], not implementation"; return 1; }
    tick "$1" '{"implementation_status":"complete"}'
    [ "$NEXT_STATE" = issue_type_routing ] || { fail "$1: after implementation, at [$NEXT_STATE]"; return 1; }
    tick "$1" "{\"issue_type\":\"$3\"}"
    return 0
}

record_round() {
    # $1 session, $2 panel, $3 round JSON
    printf '%s\n' "$3" > "$WORKDIR/round.json"
    "$PS" --record "$2" "$1" "$WORKDIR/round.json" 2>"$WORKDIR/record.err" \
        || fail "$1: panel-scope.sh --record $2 failed: $(cat "$WORKDIR/record.err")"
}

# pass_<panel> <session>: records a clean round and ticks with nothing
# submitted; the panel's <panel>_verdict gate decides the pass.
pass_scrutiny() {
    record_round "$1" scrutiny '[{"seat":"completeness","findings":[]},{"seat":"justification","findings":[]},{"seat":"intent","findings":[]}]'
    tick "$1"
}
pass_review() {
    record_round "$1" review '[{"seat":"pragmatic","findings":[]},{"seat":"architect","findings":[]},{"seat":"maintainer","findings":[]}]'
    tick "$1"
}
pass_qa() {
    record_round "$1" qa '[{"seat":"tester","findings":[]}]'
    tick "$1"
}
pass_light() {
    record_round "$1" light '[{"seat":"reviewer","findings":[]}]'
    tick "$1"
}

SMALL='printf "one more line\n" >> docs/notes.md'

# ==============================================================================
echo "--- engine: the pattern is enforced at init"

OUT=$(koto init bad-level --template "$TEMPLATE" --var ARTIFACT_PREFIX=issue_42 \
    --var PLUGIN_ROOT="$PLUGIN_ROOT" --var REVIEW_LEVEL=heavy 2>&1)
case "$OUT" in *invalid_var*|*pattern*) pass "REVIEW_LEVEL=heavy is refused at init" ;; *) fail "init with REVIEW_LEVEL=heavy said [$OUT]" ;; esac
OUT=$(koto init bad-floor --template "$TEMPLATE" --var ARTIFACT_PREFIX=issue_42 \
    --var PLUGIN_ROOT="$PLUGIN_ROOT" --var REVIEW_FLOOR=medium 2>&1)
case "$OUT" in *invalid_var*|*pattern*) pass "REVIEW_FLOOR=medium is refused at init" ;; *) fail "init with REVIEW_FLOOR=medium said [$OUT]" ;; esac

# ==============================================================================
echo "--- engine: no level, no implementation"

S=choice
if new_case "$S" "$SMALL"; then
    expect_state "plan_ready with no level" review_level_choice
    tick "$S"
    expect_state "a tick with no level" review_level_choice
    expect_visits "$S" implementation 0
    [ "$(events "$S")" = bound ] && pass "the choice state recorded the bound and nothing else" \
        || fail "ledger events are [$(events "$S")]"
    setlevel "$S" light --reason x
    tick "$S"
    expect_state "the tick after set light --reason x" implementation
    [ "$(ledger "$S" | jq -r 'select(.event == "choose") | "\(.to)|\(.reason)"')" = "light|x" ] \
        && pass "the ledger records the choice and its reason" || fail "ledger is [$(ledger "$S")]"
fi

# ==============================================================================
echo "--- engine: light"

S=light
if new_case "$S" "$SMALL" && choose_and_implement "$S" light code; then
    expect_state "a light code run under every threshold" light_review
    GOT=$(koto context get "$S" light_scope.json 2>/dev/null | jq -r '[.decisions[] | "\(.seat):\(.decision)"] | join(",")')
    [ "$GOT" = "reviewer:full" ] && pass "the light panel plans its one seat" || fail "light_scope.json decisions are [$GOT]"
    pass_light "$S"
    expect_state "a passed light round" verification
    for st in scrutiny review qa_validation; do expect_visits "$S" "$st" 0; done
    expect_visits "$S" light_review 1
    [ "$(events "$S")" = "bound choose check" ] && pass "the ledger reads bound, choose, check" \
        || fail "ledger events are [$(events "$S")]"
fi

# ==============================================================================
echo "--- engine: standard"

S=standard
if new_case "$S" "$SMALL" && choose_and_implement "$S" standard code; then
    expect_state "a standard code run" scrutiny
    pass_scrutiny "$S"
    expect_state "a passed scrutiny round" review
    pass_review "$S"
    expect_state "a passed review at standard" verification
    expect_visits "$S" qa_validation 0
    expect_visits "$S" light_review 0
fi

S=standard-md
if new_case "$S" 'printf "more\n" >> skills/demo/SKILL.md' && choose_and_implement "$S" standard code; then
    expect_state "a standard run changing only .md under skills/" scrutiny
    pass_scrutiny "$S"
    pass_review "$S"
    expect_state "its passed review" verification
    expect_visits "$S" qa_validation 0
fi

# ==============================================================================
echo "--- engine: full"

S=full
if new_case "$S" "$SMALL" && choose_and_implement "$S" full code; then
    expect_state "a full code run" scrutiny
    pass_scrutiny "$S"
    pass_review "$S"
    expect_state "a passed review at full" qa_validation
    pass_qa "$S"
    expect_state "a passed QA round" verification
    for st in scrutiny review qa_validation; do expect_visits "$S" "$st" 1; done
    expect_visits "$S" light_review 0
fi

# ==============================================================================
echo "--- engine: docs and task"

S=docs
if new_case "$S" "$SMALL" && choose_and_implement "$S" light docs; then
    expect_state "a docs run" verification
    expect_visits "$S" review_level_check 0
    [ "$(ledger "$S" | jq -r 'select(.event == "choose") | .to')" = light ] && pass "the docs run recorded its level" \
        || fail "docs ledger is [$(ledger "$S")]"
fi
S=task
if new_case "$S" "$SMALL" && choose_and_implement "$S" standard task; then
    expect_state "a task run" verification
    expect_visits "$S" review_level_check 0
    [ "$(ledger "$S" | jq -r 'select(.event == "choose") | .to')" = standard ] && pass "the task run recorded its level" \
        || fail "task ledger is [$(ledger "$S")]"
fi

# ==============================================================================
echo "--- engine: a light run below a standard floor"

S=floor
if new_case "$S" 'mkdir -p scripts && seq 1 5 > scripts/tool.sh' && choose_and_implement "$S" light code; then
    expect_state "a light run that touched an executable path" review_level_check
    for st in light_review scrutiny review qa_validation; do expect_visits "$S" "$st" 0; done
    case "$NEXT_RESPONSE" in
        *"hold: level light is below the facts floor standard (rule class:executable)"*)
            pass "the hold names the floor and the rule" ;;
        *) fail "the held response doesn't name the rule: $(printf '%s' "$NEXT_RESPONSE" | cut -c1-400)" ;;
    esac
    tick "$S"
    expect_state "a second tick without a raise" review_level_check
    setlevel "$S" standard
    tick "$S"
    expect_state "the tick after the raise" scrutiny
    GOT=$(ledger "$S" | jq -r 'select(.event == "floor_raise" or .event == "check") | "\(.event):\(.to // .level)"' | tr '\n' ' ' | sed 's/ $//')
    case "$GOT" in
        *"floor_raise:standard check:standard") pass "the ledger holds floor_raise, then a check at standard" ;;
        *) fail "level events are [$GOT]" ;;
    esac
fi

# ==============================================================================
echo "--- engine: a light retry, then a fix past 40 lines"

LIGHT_BLOCK=$(awk '
    /^```bash$/  { inblk = 1; buf = ""; next }
    /^```$/ && inblk { if (index(buf, "koto context remove") > 0) { printf "%s", buf; exit } inblk = 0; buf = ""; next }
    inblk { buf = buf $0 "\n" }
' "$PHASES/phase-4d-light.md")
[ -n "$LIGHT_BLOCK" ] || fail "could not extract the retry block from phase-4d-light.md"

S=retry
if new_case "$S" "$SMALL" && choose_and_implement "$S" light code; then
    expect_state "the first light round" light_review
    record_round "$S" light '[{"seat":"reviewer","findings":[{"severity":"blocking","summary":"missing case","path":"docs/notes.md"}]}]'
    seed "$S" light_results.json
    # A tick with nothing submitted: light_verdict reports the block (exit 1)
    # and the state waits for the agent's retry or escalation.
    tick "$S"
    expect_state "a recorded blocking light round" light_review
    printf '%s\n' "$LIGHT_BLOCK" | sed "s|<WF>|$S|g" | bash >/dev/null 2>&1
    NEXT_STATE=$(koto status "$S" 2>/dev/null | jq -r '.current_state // empty')
    expect_state "the shipped light retry block" implementation
    koto context exists "$S" light_results.json 2>/dev/null \
        && fail "the retry left light_results.json in place" || pass "the retry cleared light_results.json"
    GOT=$(koto context get "$S" verdict_ledger.json 2>/dev/null | jq -r '.seats["light/reviewer"].verdict // empty')
    [ "$GOT" = blocking ] && pass "the light seat's blocking verdict is in the verdict ledger" || fail "light/reviewer is [$GOT]"
    koto context exists "$S" review_level.jsonl 2>/dev/null && pass "the retry left the level ledger alone" \
        || fail "the retry removed review_level.jsonl"
    seq 1 50 >> docs/notes.md
    git commit -q -am "fix: a bigger change"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"code"}'
    expect_state "the light run whose fix passed 40 lines" review_level_check
    case "$NEXT_RESPONSE" in
        *"below the facts floor standard (rule lines>40)"*) pass "the hold names the lines rule" ;;
        *) fail "the held response doesn't name lines>40: $(printf '%s' "$NEXT_RESPONSE" | cut -c1-400)" ;;
    esac
    expect_visits "$S" light_review 1
    setlevel "$S" standard
    tick "$S"
    expect_state "the raised run" scrutiny
fi

# ==============================================================================
echo "--- engine: a hand rebind"

S=rebind
if new_case "$S" "$SMALL"; then
    setlevel "$S" standard
    tick "$S"
    tick "$S" '{"implementation_status":"complete"}'
    koto init "$S" --template "$TEMPLATE" --attach-live --var PLUGIN_ROOT="$PLUGIN_ROOT" \
        --var REVIEW_LEVEL=full >/dev/null 2>&1 || fail "$S: the hand rebind was refused"
    tick "$S" '{"issue_type":"code"}'
    expect_state "a hand rebind to full over a ledger at standard" review_level_check
    case "$NEXT_RESPONSE" in
        *"REVIEW_LEVEL is full but the ledger's last level is standard"*) pass "the hold names both levels" ;;
        *) fail "the held response doesn't name both levels: $(printf '%s' "$NEXT_RESPONSE" | cut -c1-400)" ;;
    esac
    expect_visits "$S" scrutiny 0
    setlevel "$S" standard
    tick "$S"
    expect_state "after set puts the level back" scrutiny
fi

# An attach that doesn't pass REVIEW_LEVEL (a resume, say) resets it to empty.
# With a level in the ledger that is not the unset route: the check holds.
S=reset
if new_case "$S" "$SMALL"; then
    setlevel "$S" standard
    tick "$S"
    tick "$S" '{"implementation_status":"complete"}'
    koto init "$S" --template "$TEMPLATE" --attach-live --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1 \
        || fail "$S: the attach was refused"
    tick "$S" '{"issue_type":"code"}'
    expect_state "an emptied level over a ledger at standard" review_level_check
    case "$NEXT_RESPONSE" in
        *"REVIEW_LEVEL is empty but the ledger's last level is standard"*) pass "the hold names the ledger's level" ;;
        *) fail "the held response doesn't name the ledger's level: $(printf '%s' "$NEXT_RESPONSE" | cut -c1-400)" ;;
    esac
    setlevel "$S" standard
    tick "$S"
    expect_state "after set rebinds it" scrutiny
fi

# ==============================================================================
echo "--- engine: a hand rebind after the level check"

# The level check is passed once; review and light_review route on the level
# again. A hand rebind while the run sits in one of them must hold its passed
# routes (level_unchanged), not route on the new value.
hand_rebind() {
    # $1 session, $2 level
    koto init "$1" --template "$TEMPLATE" --attach-live --var PLUGIN_ROOT="$PLUGIN_ROOT" \
        --var REVIEW_LEVEL="$2" >/dev/null 2>&1 || fail "$1: the hand rebind to $2 was refused"
}

S=rebind-review
if new_case "$S" "$SMALL" && choose_and_implement "$S" full code; then
    expect_state "a full code run" scrutiny
    pass_scrutiny "$S"
    expect_state "its passed scrutiny" review
    hand_rebind "$S" standard
    pass_review "$S"
    expect_state "a passed review after a hand rebind from full to standard" review
    expect_visits "$S" verification 0
    expect_visits "$S" qa_validation 0
    case "$NEXT_RESPONSE" in
        *"REVIEW_LEVEL is standard but the ledger's last level is full"*) pass "the hold names both levels" ;;
        *) fail "the held response doesn't name both levels: $(printf '%s' "$NEXT_RESPONSE" | cut -c1-600)" ;;
    esac
    [ "$(events "$S")" = "bound choose check" ] && pass "the ledger is untouched by the hand rebind" \
        || fail "ledger events are [$(events "$S")]"
    tick "$S"
    expect_state "a tick with the rebind still in place" review
    setlevel "$S" full
    tick "$S"
    expect_state "after set puts the ledger's level back" qa_validation
    expect_visits "$S" verification 0
fi

S=rebind-light
if new_case "$S" "$SMALL" && choose_and_implement "$S" light code; then
    expect_state "a light code run" light_review
    hand_rebind "$S" standard
    pass_light "$S"
    expect_state "a passed light round after a hand rebind from light to standard" light_review
    expect_visits "$S" verification 0
    case "$NEXT_RESPONSE" in
        *"REVIEW_LEVEL is standard but the ledger's last level is light"*) pass "the hold names both levels" ;;
        *) fail "the held response doesn't name both levels: $(printf '%s' "$NEXT_RESPONSE" | cut -c1-600)" ;;
    esac
    setlevel "$S" light
    tick "$S"
    expect_state "after set puts the ledger's level back" verification
fi

# ==============================================================================
echo "--- engine: the level unset at the check"

S=unset
if new_case "$S" "$SMALL"; then
    setlevel "$S" light
    tick "$S"
    tick "$S" '{"implementation_status":"complete"}'
    # The state a session from an earlier template is in: no level, and no
    # level ledger. An attach that omits an optional rebind variable resets
    # it, which is how the variable is emptied here.
    koto init "$S" --template "$TEMPLATE" --attach-live --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1 \
        || fail "$S: clearing the level was refused"
    koto context remove "$S" review_level.jsonl >/dev/null 2>&1
    tick "$S" '{"issue_type":"code"}'
    expect_state "a code run with no level" scrutiny
    pass_scrutiny "$S"
    pass_review "$S"
    expect_state "its passed review" qa_validation
    pass_qa "$S"
    expect_state "its passed QA round" verification
    expect_visits "$S" light_review 0
    ledger "$S" | jq -e 'select(.event == "unset")' >/dev/null 2>&1 && pass "the ledger has an unset line" \
        || fail "no unset line: $(events "$S")"
fi

git checkout -q main
cd "$WORKDIR" || exit 1

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

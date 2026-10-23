#!/usr/bin/env bash
# scrutiny-decider-routes_test.sh -- the scrutiny decider batch, routed through
# the shipped work-on.md by a real koto
# Part of the work-on skill
#
# scrutiny_decider is a shadow decider-check on `scrutiny` that asks Jev
# whether every decision the run recorded gives a reason
# (work-on/scrutiny-decision-reasons). It can't change where the state goes,
# but a criterion the decider can't answer waits on the agent (koto 0.20.0).
# These cases drive real sessions of the template that ships, with the decider
# in shadow at a loopback port nothing listens on, so every consultation
# fails:
#
#   the declarations    one shadow criterion, keyed by its registry id, under
#                       a 2,560-byte budget, label `decisions`; no route reads it
#   a full round        a run with a recorded decision holds at scrutiny with
#                       the criterion under `awaiting` after a passing round,
#                       and an `unclear` answer lets it on to review
#   a carried round     after a review retry with no new commit every seat is
#                       kept, and the batch still holds until it is answered
#   no decision         an empty slice is not graded: the run passes scrutiny
#                       without holding
#   over budget         a 2,561-byte slice falls back for over_budget; a
#                       2,560-byte one is sent to the decider
#   the decider off     scrutiny passes as it did before the gate, and the log
#                       holds no decider_checked event for it
#
# The decider key is a placeholder set after any inherited one is unset, and
# the endpoint is loopback, so no real key reaches any process here.
#
# Usage: scrutiny-decider-routes_test.sh
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the engine cases skipped
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
# koto validates a variable value against ^[a-zA-Z0-9._/:@ \-]*$; a checkout
# under a directory outside it is reached through a symlink below.
PLUGIN_ROOT=$(cd "$SKILL_DIR/../.." && pwd)
# Round files name their runs (panel-scope.sh --record refuses one that doesn't).
. "$PLUGIN_ROOT/scripts/lib/panel-round-testlib.sh"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }
command -v koto >/dev/null 2>&1 || { echo "SKIP: koto not on PATH -- engine cases did not run"; exit 0; }
[ -f "$TEMPLATE" ] || { echo "FAIL: template not found at $TEMPLATE" >&2; exit 1; }

WORKDIR=$(mktemp -d) || exit 1
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

export HOME="$WORKDIR/home"
mkdir -p "$HOME"
# No inherited decider settings, and above all no inherited key: each case
# that wants a decider sets a placeholder and a loopback endpoint.
unset KOTO_DECIDER KOTO_DECIDER_API_KEY KOTO_DECIDER_ENDPOINT
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
# fix_determination reads the issue's labels with gh; the stand-in serves an
# unlabelled issue, so these runs are changes.
. "$PLUGIN_ROOT/scripts/lib/gh-issue-testlib.sh"
gh_issue_stand_in "$WORKDIR/gh-bin"
GATE=scrutiny_decider
CRIT=work-on/scrutiny-decision-reasons

# ==============================================================================
echo "--- engine: the declarations"

COMPILED=$(koto template compile "$TEMPLATE" 2>"$WORKDIR/compile.err" | tail -n 1)
if [ -f "$COMPILED" ]; then
    pass "work-on.md compiles on $(koto version 2>/dev/null | head -n 1)"
else
    fail "work-on.md does not compile: $(cat "$WORKDIR/compile.err")"
    COMPILED=/dev/null
fi
GOT=$(jq -r --arg g "$GATE" '.states.scrutiny.gates[$g].decider_check
             | "\(.max_bytes)|\(.label)|\([.criteria[] | "\(.rule_id):\(.mode)"] | join(","))"' "$COMPILED" 2>/dev/null)
[ "$GOT" = "2560|decisions|$CRIT:shadow" ] \
    && pass "scrutiny_decider has one shadow criterion keyed by its registry id, 2,560 bytes, label decisions" \
    || fail "scrutiny_decider is [$GOT]"
GOT=$(jq -r --arg g "$GATE" '.states.scrutiny.gates[$g].type' "$COMPILED" 2>/dev/null)
[ "$GOT" = decider-check ] && pass "scrutiny_decider is a decider-check" || fail "scrutiny_decider's type is [$GOT]"
GOT=$(jq -r --arg g "gates.$GATE" '[.states[].transitions[]?.when // {} | keys[] | select(startswith($g))] | length' \
    "$COMPILED" 2>/dev/null)
[ "$GOT" = 0 ] && pass "no route reads scrutiny_decider" || fail "$GOT when clauses read scrutiny_decider"
GOT=$(jq -r --arg g "$GATE" '[.states[] | select(.gates? and (.gates | has($g)))] | length' "$COMPILED" 2>/dev/null)
[ "$GOT" = 1 ] && pass "only scrutiny declares the batch" || fail "$GOT states declare scrutiny_decider"

# --- the repository the gates and actions read ---------------------------------

REPO="$WORKDIR/repo"
mkdir -p "$REPO"
(
    cd "$REPO" || exit 1
    git init -q -b main .
    mkdir -p docs
    seq 1 60 > docs/notes.md
    git add -A
    git commit -q -m init
) >/dev/null 2>&1
cd "$REPO" || exit 1
MAIN=$(git rev-parse main)

NEXT_RESPONSE=""
NEXT_STATE=""
tick() {
    if [ -n "${2:-}" ]; then
        NEXT_RESPONSE=$(koto next "$1" --with-data "$2" --no-cleanup 2>/dev/null)
    else
        NEXT_RESPONSE=$(koto next "$1" --no-cleanup 2>/dev/null)
    fi
    NEXT_STATE=$(koto status "$1" 2>/dev/null | jq -r '.current_state // empty')
}
expect_state() {
    # $1 label, $2 expected state
    [ "$NEXT_STATE" = "$2" ] && pass "$1: at $2" || fail "$1: at [$NEXT_STATE], expected $2"
}
slog() { printf '%s' "$HOME/.koto/sessions/$1/koto-$1.state.jsonl"; }
# cond <gate> <field>: a blocking condition's <field> as a string
cond() {
    printf '%s' "$NEXT_RESPONSE" | jq -r --arg g "$1" --arg f "$2" \
        '[.blocking_conditions[]? | select(.name == $g)][0] // {} | getpath($f | split(".")) // "" | tostring'
}
decider_on() {
    export KOTO_DECIDER=shadow KOTO_DECIDER_API_KEY=routes-test-placeholder \
        KOTO_DECIDER_ENDPOINT="http://127.0.0.1:9/v1/systemone"
}
decider_off() { unset KOTO_DECIDER KOTO_DECIDER_API_KEY KOTO_DECIDER_ENDPOINT; }
answer() {
    # $1 session, $2 gate, $3 criterion, $4 answer
    koto decider answer "$1" --gate "$2" --criterion "$3" --answer "$4" >/dev/null 2>"$WORKDIR/answer.err" \
        || fail "$1: koto decider answer $2 $4 failed: $(cat "$WORKDIR/answer.err")"
}
record_round() {
    # $1 session, $2 panel, $3 round JSON
    printf '%s\n' "$3" > "$WORKDIR/round.json"
    panel_round_runs "$1" "$2" "$WORKDIR/round.json"
    "$PS" --record "$2" "$1" "$WORKDIR/round.json" 2>"$WORKDIR/record.err" \
        || fail "$1: panel-scope.sh --record $2 failed: $(cat "$WORKDIR/record.err")"
}
CLEAN_SCRUTINY='[{"seat":"completeness","findings":[]},{"seat":"justification","findings":[]},{"seat":"intent","findings":[]}]'

# to_scrutiny <session> <decision-json|""> : a branch with one commit and a
# standard-level session walked to scrutiny, recording the decision (if any)
# in implementation. Under a decider the level check's own criterion falls
# back too, and the agent answers it.
to_scrutiny() {
    local s=$1
    git checkout -q main
    git checkout -q -b "case-$s"
    printf 'one more line\n' >> docs/notes.md
    git add -A
    git commit -q -m "work for $s"
    koto init "$s" --template "$TEMPLATE" --var ARTIFACT_PREFIX=issue_42 --var ISSUE_NUMBER=42 \
        --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1 || { fail "$s: koto init failed"; return 1; }
    tick "$s" '{"mode":"issue_backed","issue_number":"42"}'
    tick "$s" '{"status":"override"}'
    tick "$s" '{"status":"override"}'
    printf '# Issue\n\n## Acceptance Criteria\n\n- [ ] it works\n' | koto context add "$s" context.md >/dev/null 2>&1
    printf 'plan\n' | koto context add "$s" plan.md >/dev/null 2>&1
    tick "$s" '{"plan_outcome":"plan_ready"}'
    printf '%s\n' "$MAIN" | koto context add "$s" impl_base >/dev/null 2>&1
    "$RL" set "$s" standard >/dev/null 2>"$WORKDIR/set.err" || { fail "$s: set standard: $(cat "$WORKDIR/set.err")"; return 1; }
    # Into fix_determination, whose action binds UNIT_KIND; koto routes on it
    # from the next tick, to implementation.
    tick "$s"
    tick "$s"
    [ "$NEXT_STATE" = implementation ] || { fail "$s: at [$NEXT_STATE], not implementation"; return 1; }
    if [ -n "$2" ]; then
        koto decisions record "$s" --with-data "$2" >/dev/null 2>"$WORKDIR/dec.err" \
            || { fail "$s: koto decisions record failed: $(cat "$WORKDIR/dec.err")"; return 1; }
    fi
    tick "$s" '{"implementation_status":"complete"}'
    tick "$s" '{"issue_type":"code"}'
    pass_level_check "$s"
    [ "$NEXT_STATE" = scrutiny ] || { fail "$s: at [$NEXT_STATE], not scrutiny"; return 1; }
    return 0
}
pass_level_check() {
    if [ "$NEXT_STATE" = review_level_check ] && [ "$(cond level_fits_facts status)" = pending ]; then
        answer "$1" level_fits_facts level_fits_facts pass
        tick "$1"
    fi
}
# checked_outcomes <session>: the decider_checked outcomes for the batch
checked_outcomes() {
    jq -rs --arg g "$GATE" '[.[] | select(.type == "decider_checked" and .payload.gate == $g)
                             | .payload.outcome] | unique | join(",")' "$(slog "$1")" 2>/dev/null
}

DECISION='{"choice":"Read the log path the gate passes","rationale":"koto decisions list sees only the current state"}'

# ==============================================================================
echo "--- engine: a full round with a recorded decision"

S=full
decider_on
if to_scrutiny "$S" "$DECISION"; then
    GOT=$(koto context get "$S" scrutiny_scope.json 2>/dev/null | jq -r '.full')
    [ "$GOT" = true ] && pass "the first scrutiny round is full" || fail "scrutiny_scope.json full is [$GOT]"
    record_round "$S" scrutiny "$CLEAN_SCRUTINY"
    tick "$S"
    expect_state "a passed round with the batch unanswered" scrutiny
    [ "$(cond $GATE status)|$(cond $GATE output.awaiting)" = "pending|[\"$CRIT\"]" ] \
        && pass "the batch is pending with $CRIT under awaiting" \
        || fail "scrutiny_decider is [$(cond $GATE status)|$(cond $GATE output.awaiting)]"
    case "$(printf '%s' "$NEXT_RESPONSE" | jq -r '.directive // ""')" in
        *"koto decider answer $S --gate $GATE --criterion $CRIT --answer <pass|fail|unclear>"*)
            pass "the directive gives the answer command" ;;
        *) fail "the directive does not give the answer command" ;;
    esac
    answer "$S" "$GATE" "$CRIT" unclear
    tick "$S"
    expect_state "the tick after the agent answered unclear" review
    [ "$(checked_outcomes "$S")" = unanswered ] \
        && pass "the batch's only decider_checked outcome is unanswered: the answer is the agent's" \
        || fail "scrutiny_decider decider_checked outcomes are [$(checked_outcomes "$S")]"
fi
decider_off

# ==============================================================================
echo "--- engine: a carried round still waits on the batch"

S=carried
decider_on
if to_scrutiny "$S" "$DECISION"; then
    record_round "$S" scrutiny "$CLEAN_SCRUTINY"
    answer "$S" "$GATE" "$CRIT" pass
    tick "$S"
    expect_state "a passed, answered first round" review
    # A blocking review round sends the run back with no new commit, so the
    # next scrutiny round has nothing to run.
    record_round "$S" review '[{"seat":"pragmatic","findings":[{"severity":"blocking","summary":"rename x"}]},{"seat":"architect","findings":[]},{"seat":"maintainer","findings":[]}]'
    tick "$S"
    tick "$S" '{"review_outcome":"blocking_retry"}'
    expect_state "a review retry" implementation
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"code"}'
    pass_level_check "$S"
    expect_state "back at scrutiny" scrutiny
    GOT=$(koto context get "$S" scrutiny_scope.json 2>/dev/null \
        | jq -r '"\(.full)|\([.decisions[] | select(.decision != "keep")] | length)"')
    [ "$GOT" = "false|0" ] && pass "the round is carried: every seat kept, nothing to run" \
        || fail "scrutiny_scope.json is [$GOT]"
    [ "$(cond $GATE status)|$(cond $GATE output.awaiting)" = "pending|[\"$CRIT\"]" ] \
        && pass "the carried round holds with $CRIT under awaiting" \
        || fail "scrutiny_decider on the carried round is [$(cond $GATE status)|$(cond $GATE output.awaiting)]"
    answer "$S" "$GATE" "$CRIT" unclear
    tick "$S"
    expect_state "the carried round after the agent answered" review
fi
decider_off

# ==============================================================================
echo "--- engine: no recorded decision"

S=none
decider_on
if to_scrutiny "$S" ""; then
    record_round "$S" scrutiny "$CLEAN_SCRUTINY"
    tick "$S"
    expect_state "a run with no decision" review
    [ "$(checked_outcomes "$S")" = not_graded ] && pass "the empty slice is recorded as not_graded" \
        || fail "scrutiny_decider decider_checked outcomes are [$(checked_outcomes "$S")]"
fi
decider_off

# ==============================================================================
echo "--- engine: a 2,561-byte slice"

# "- choice: x\n  reason: <r>\n" is 23 bytes plus the reason.
REASON=$(printf '%*s' 2538 '' | tr ' ' r)
S=over
decider_on
if to_scrutiny "$S" "{\"choice\":\"x\",\"rationale\":\"$REASON\"}"; then
    N=$("$PLUGIN_ROOT/skills/work-on/scripts/decision-reasons.sh" slice "$(slog "$S")" | wc -c | tr -d ' ')
    [ "$N" = 2561 ] && pass "the slice is 2,561 bytes" || fail "the slice is $N bytes"
    record_round "$S" scrutiny "$CLEAN_SCRUTINY"
    tick "$S"
    expect_state "an over-budget batch" scrutiny
    GOT=$(jq -rs --arg g "$GATE" '[.[] | select(.type == "decider_fallback" and .payload.gate == $g)
                                   | .payload.reason] | unique | join(",")' "$(slog "$S")")
    [ "$GOT" = over_budget ] && pass "the batch falls back for over_budget" || fail "scrutiny_decider fallback reasons are [$GOT]"
    answer "$S" "$GATE" "$CRIT" pass
    tick "$S"
    expect_state "the over-budget batch after the agent answered" review
fi
decider_off

# At the budget exactly, koto asks the decider: the stub refuses the
# connection, so the batch falls back, but never for over_budget.
REASON=$(printf '%*s' 2537 '' | tr ' ' r)
S=at-budget
decider_on
if to_scrutiny "$S" "{\"choice\":\"x\",\"rationale\":\"$REASON\"}"; then
    N=$("$PLUGIN_ROOT/skills/work-on/scripts/decision-reasons.sh" slice "$(slog "$S")" | wc -c | tr -d ' ')
    [ "$N" = 2560 ] && pass "the slice is 2,560 bytes" || fail "the slice is $N bytes"
    record_round "$S" scrutiny "$CLEAN_SCRUTINY"
    tick "$S"
    GOT=$(jq -rs --arg g "$GATE" '[.[] | select(((.type // "") | startswith("decider_")) and .payload.gate? == $g)
                                   | "\(.type):\(.payload.reason // .payload.outcome // "")"] | unique | join(",")' "$(slog "$S")")
    case ",$GOT," in
        *over_budget*) fail "a 2,560-byte slice fell back for over_budget: [$GOT]" ;;
        ,,) fail "a 2,560-byte slice left no decider event for the batch" ;;
        *) pass "a 2,560-byte slice is sent to the decider, which can't answer: [$GOT]" ;;
    esac
fi
decider_off

# ==============================================================================
echo "--- engine: the decider off"

S=off
if to_scrutiny "$S" "$DECISION"; then
    record_round "$S" scrutiny "$CLEAN_SCRUTINY"
    tick "$S"
    expect_state "a passed round with no decider" review
    GOT=$(jq -rs --arg g "$GATE" '[.[] | select(((.type // "") | startswith("decider")) and .payload.gate == $g)] | length' "$(slog "$S")")
    [ "$GOT" = 0 ] && pass "the log holds no decider event for the batch" || fail "$GOT decider events for scrutiny_decider"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

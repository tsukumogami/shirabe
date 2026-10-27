#!/usr/bin/env bash
# red-first-routes_test.sh -- a fix run starts red, routed through the shipped
# work-on.md by a real koto
# Part of the work-on skill
#
# fix-kind_test.sh and red-first_test.sh pin the two scripts against a koto
# stand-in. This suite drives the template that ships, in the design's
# walkthrough repository: greet.sh prints `Hello, <name>!`, tests/run.sh runs
# every tests/*_test.sh, the verification map's default runs tests/run.sh, and
# issue 1, labelled `bug`, says `./greet.sh ''` should print
# `error: name required`. gh is a stand-in that serves the fixture's issues.
#
#   the declarations  UNIT_KIND (rebindable, change or fix) and FIX_REPORT;
#                     review_level_choice goes to fix_determination, which
#                     goes to implementation for a change and reproduce for a
#                     fix; reproduce leaves only on red_recorded; verification's
#                     exit 0 and verification_deferred go to pass_counting,
#                     which reaches finalization only on fix_green and
#                     tests_counted
#   a fix             issue 1: recorded as a fix from label:bug; held at
#                     reproduce with no red, never reaching implementation;
#                     after `red-first.sh red` the red's base is impl_base and
#                     its output tail holds the marker; after implementing and
#                     passing local verification it is held at pass_counting
#                     until `red-first.sh green` records exit 0 at HEAD, then
#                     reaches finalization
#   a change          issue 2, labelled `enhancement`: from fix_determination
#                     straight to implementation, never reproduce, no red or
#                     green record, and through pass_counting (by a deferral
#                     to hosted CI) to finalization with nothing to record
#   no withdrawal     fix-kind.sh withdraw on the fix exits 1 naming label:bug
#   a hand rebind     UNIT_KIND rebound to change at fix_determination holds
#                     the run there; `fix-kind.sh declare` puts it back
#   a step's report   issue 3 has no label and FIX_REPORT set: a fix from the
#                     step, whose red is refused for a passage from the issue
#                     body and recorded for one from the Fixes line
#   observations      a fix recorded by a before- and after-observation stays
#                     held at pass_counting, the gate saying observations wait
#                     for acceptance
#
# Usage: red-first-routes_test.sh
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the engine cases skipped
#   1 -- one or more cases failed

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
PLUGIN_ROOT=$(cd "$SKILL_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq  >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }
command -v koto >/dev/null 2>&1 || { echo "SKIP: koto not on PATH -- engine cases did not run"; exit 0; }
[ -f "$TEMPLATE" ] || { echo "FAIL: template not found at $TEMPLATE" >&2; exit 1; }

WORKDIR=$(mktemp -d) || exit 1
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

export HOME="$WORKDIR/home"
mkdir -p "$HOME"
unset KOTO_DECIDER KOTO_DECIDER_API_KEY KOTO_DECIDER_ENDPOINT
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
# koto validates a variable value against ^[a-zA-Z0-9._/:@+ \-]*$; a checkout
# under a directory outside it is reached through a symlink.
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@+\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        PLUGIN_ROOT="$WORKDIR/plugin"
        ;;
esac
FK="$PLUGIN_ROOT/skills/work-on/scripts/fix-kind.sh"
RF="$PLUGIN_ROOT/skills/work-on/scripts/red-first.sh"
RL="$PLUGIN_ROOT/skills/work-on/scripts/review-level.sh"

# gh: `issue view <n> ... --json ...` prints <issues>/<n>.json. The directory
# is written into the stand-in, since koto passes a gate or action command only
# an allowlisted environment.
GH_ISSUES="$WORKDIR/issues"
mkdir -p "$WORKDIR/bin" "$GH_ISSUES"
{
    echo '#!/usr/bin/env bash'
    echo '[ "$1 $2" = "issue view" ] || { echo "gh stand-in: unsupported $*" >&2; exit 1; }'
    printf 'f="%s/$3.json"\n' "$GH_ISSUES"
    echo '[ -f "$f" ] || { echo "gh stand-in: no issue $3" >&2; exit 1; }'
    echo 'cat "$f"'
} > "$WORKDIR/bin/gh"
chmod +x "$WORKDIR/bin/gh"
export PATH="$WORKDIR/bin:$PATH"

REPORT="Running \`./greet.sh ''\` prints \`Hello, !\` instead of \`error: name required\`."
MARKER="error: name required"
jq -n --arg b "$REPORT" '{body: $b, labels: [{name: "bug"}]}' > "$GH_ISSUES/1.json"
jq -n '{body: "Add a --shout flag that prints the greeting in capitals.", labels: [{name: "enhancement"}]}' > "$GH_ISSUES/2.json"
jq -n '{body: "Tidy up greet.sh.", labels: []}' > "$GH_ISSUES/3.json"
FIXES="greet.sh prints Hello for an empty name instead of error: name required"

# ==============================================================================
echo "--- the declarations"

COMPILED=$(koto template compile "$TEMPLATE" 2>"$WORKDIR/compile.err" | tail -n 1)
[ -f "$COMPILED" ] && pass "work-on.md compiles" || { fail "work-on.md does not compile: $(cat "$WORKDIR/compile.err")"; COMPILED=/dev/null; }
q() { jq -r "$1" "$COMPILED" 2>/dev/null; }
[ "$(q '"\(.variables.UNIT_KIND.rebind)|\(.variables.UNIT_KIND.pattern)"')" = 'true|^(change|fix)?$' ] \
    && pass "UNIT_KIND is rebindable, change or fix" || fail "UNIT_KIND is [$(q '.variables.UNIT_KIND')]"
[ "$(q '.variables.FIX_REPORT.rebind // false')" = false ] && pass "FIX_REPORT is not rebindable" || fail "FIX_REPORT is rebindable"
[ "$(q '[.states.review_level_choice.transitions[] | select(.when["vars.REVIEW_LEVEL"].is_set == true) | .target] | join(",")')" = fix_determination ] \
    && pass "a chosen level goes to fix_determination" || fail "a chosen level goes to [$(q '[.states.review_level_choice.transitions[].target] | join(",")')]"
[ "$(q '[.states.fix_determination.transitions[] | select(.when["gates.kind_unchanged.exit_code"] == 0) | "\(.when["vars.UNIT_KIND"])>\(.target)"] | join(",")')" = "change>implementation,fix>reproduce" ] \
    && pass "fix_determination: a change to implementation, a fix to reproduce" || fail "fix_determination routes [$(q '.states.fix_determination.transitions')]"
case "$(q '.states.fix_determination.default_action.command')" in *"fix-kind.sh\" resolve"*) pass "fix_determination's action is fix-kind.sh resolve" ;; *) fail "fix_determination's action is [$(q '.states.fix_determination.default_action.command')]" ;; esac
[ "$(q '[.states.reproduce.transitions[] | select(.target == "implementation") | .when | keys | join("+")] | join(",")')" = "gates.red_recorded.exit_code" ] \
    && pass "reproduce reaches implementation only on red_recorded" || fail "reproduce's edges to implementation are [$(q '.states.reproduce.transitions')]"
[ "$(q '[.states.verification.transitions[] | select(.when["gates.verification_verdict.exit_code"] == 0) | .target] | join(",")')" = pass_counting ] \
    && pass "verification's exit 0 goes to pass_counting" || fail "verification's exit 0 goes elsewhere"
[ "$(q '[.states.verification_deferred.transitions[] | select(.when["vars.VERIFICATION_DEFERRAL_REASON"].is_set == true) | .target] | join(",")')" = pass_counting ] \
    && pass "a deferral goes to pass_counting" || fail "a deferral goes elsewhere"
[ "$(q '[.states | to_entries[] | .key as $s | .value.transitions[]? | select(.target == "finalization") | $s] | unique | join(",")')" = pass_counting ] \
    && pass "only pass_counting reaches finalization" || fail "finalization is reached from [$(q '[.states | to_entries[] | .key as $s | .value.transitions[]? | select(.target == "finalization") | $s] | unique | join(",")')]"
[ "$(q '[.states.pass_counting.transitions[] | select(.target == "finalization") | .when | keys | join("+")] | join(",")')" = "gates.fix_green.exit_code+gates.tests_counted.exit_code" ] \
    && pass "pass_counting reaches finalization only on fix_green and tests_counted" || fail "pass_counting's edges are [$(q '.states.pass_counting.transitions')]"

# ==============================================================================
# The repository.
REPO="$WORKDIR/repo"
mkdir -p "$REPO/tests" "$REPO/.claude/shirabe-extensions"
cd "$REPO" || exit 1
git init -q -b main .
cat > greet.sh <<'EOF'
#!/bin/sh
echo "Hello, $1!"
EOF
cat > tests/run.sh <<'EOF'
#!/bin/sh
# Runs every tests/*_test.sh; non-zero when any fails.
rc=0
for t in tests/*_test.sh; do
    [ -e "$t" ] || continue
    sh "$t" || rc=1
done
exit $rc
EOF
cat > tests/greet_test.sh <<'EOF'
#!/bin/sh
out=$(./greet.sh World)
[ "$out" = "Hello, World!" ] || { echo "expected Hello, World! got $out"; exit 1; }
EOF
printf '# greet\n\n## Repo Visibility: Private\n' > CLAUDE.md
printf '%s\n' '{"schema":"shirabe-verification-map/v1","commands":{"tests":{"run":["sh","tests/run.sh"]}},"entries":[],"default":["tests"]}' \
    > .claude/shirabe-extensions/verification-map.json
chmod +x greet.sh tests/run.sh tests/greet_test.sh
git add -A
git commit -q -m init
MAIN=$(git rev-parse main)

RESP=""
STATE=""
tick() {
    if [ -n "${2:-}" ]; then
        RESP=$(koto next "$1" --with-data "$2" --no-cleanup 2>/dev/null)
    else
        RESP=$(koto next "$1" --no-cleanup 2>/dev/null)
    fi
    STATE=$(koto status "$1" 2>/dev/null | jq -r '.current_state // empty')
}
visits() {
    jq -s --arg st "$2" '[.[] | select(.type == "transitioned" and .payload.to == $st)] | length' \
        "$HOME/.koto/sessions/$1/koto-$1.state.jsonl" 2>/dev/null
}
expect_state() { [ "$STATE" = "$2" ] && pass "$1: at $2" || fail "$1: at [$STATE], expected $2"; }
# gate_stdout <gate>: what the gate printed in the last response.
gate_stdout() {
    printf '%s' "$RESP" | jq -r --arg g "$1" '.blocking_conditions[]? | select(.name == $g) | .failure.captured.stdout // ""'
}

# walk_to_choice <session> <issue> [<more init vars>...]: a branch off main
# and a session walked to review_level_choice.
walk_to_choice() {
    local s=$1 n=$2
    shift 2
    git checkout -q main
    git checkout -q -b "case-$s"
    koto init "$s" --template "$TEMPLATE" --var ARTIFACT_PREFIX="issue_$n" --var ISSUE_NUMBER="$n" \
        --var PLUGIN_ROOT="$PLUGIN_ROOT" "$@" >/dev/null 2>"$WORKDIR/init.err" \
        || { fail "$s: koto init failed: $(cat "$WORKDIR/init.err")"; return 1; }
    tick "$s" "{\"mode\":\"issue_backed\",\"issue_number\":\"$n\"}"
    tick "$s" '{"status":"override"}'
    tick "$s" '{"status":"override"}'
    printf '# Issue %s\n\n## Acceptance Criteria\n\n- [ ] it works\n' "$n" | koto context add "$s" context.md >/dev/null 2>&1
    printf 'plan\n' | koto context add "$s" plan.md >/dev/null 2>&1
    tick "$s" '{"plan_outcome":"plan_ready"}'
    [ "$STATE" = review_level_choice ] || { fail "$s: walked to [$STATE], not review_level_choice"; return 1; }
    "$RL" set "$s" light >/dev/null 2>"$WORKDIR/set.err" || { fail "$s: review-level.sh set failed: $(cat "$WORKDIR/set.err")"; return 1; }
    return 0
}

# settle_verification <session>: ticks while the run waits on verification.
settle_verification() {
    local i=0
    while [ "$STATE" = verification ] && [ "$i" -lt 12 ]; do
        tick "$1"
        i=$((i + 1))
    done
}

# ==============================================================================
echo "--- a fix: label:bug, held at reproduce, red on the base, held at pass_counting until green"

S=rf_fix
if walk_to_choice "$S" 1; then
    tick "$S"
    expect_state "after the level is set" fix_determination
    [ "$(koto context get "$S" fix_kind.jsonl 2>/dev/null | jq -r '"\(.kind)|\(.source)"')" = "fix|label:bug" ] \
        && pass "the unit is recorded as a fix with source label:bug" \
        || fail "fix_kind.jsonl is [$(koto context get "$S" fix_kind.jsonl 2>/dev/null)]"
    [ "$(koto context get "$S" fix_report.txt 2>/dev/null)" = "$REPORT" ] && pass "the issue body is stored as the report" \
        || fail "fix_report.txt is [$(koto context get "$S" fix_report.txt 2>/dev/null)]"
    tick "$S"
    expect_state "the next tick routes on UNIT_KIND" reproduce
    tick "$S"
    expect_state "with no red recorded, the run is held" reproduce
    case "$(gate_stdout red_recorded)" in *red-first/no-red*) pass "red_recorded holds with finding red-first/no-red" ;; *) fail "red_recorded printed [$(gate_stdout red_recorded)]" ;; esac
    [ "$(visits "$S" implementation)" = 0 ] && pass "implementation is never reached without a red" || fail "implementation was entered"

    "$FK" withdraw "$S" --reason "not a bug" > "$WORKDIR/withdraw.out" 2>&1
    RC=$?
    [ "$RC" = 1 ] && grep -q 'refused: .*(source label:bug)' "$WORKDIR/withdraw.out" \
        && pass "a withdrawal exits 1 with a refused: line naming label:bug" \
        || fail "withdraw exited $RC: $(cat "$WORKDIR/withdraw.out")"
    [ "$("$FK" kind "$S")" = fix ] && pass "after a withdrawal the unit is still a fix" || fail "the unit is [$("$FK" kind "$S")]"

    cat > tests/empty_name_test.sh <<'EOF'
#!/bin/sh
out=$(./greet.sh '' 2>&1)
[ "$out" = "error: name required" ] || { echo "expected error: name required, got $out"; exit 1; }
EOF
    git add tests/empty_name_test.sh
    git commit -q -m "test: reproduce the empty name"
    printf '%s' "Running \`./greet.sh ''\` prints \`Hello, !\` instead of \`error: name required\`" > "$WORKDIR/passage"
    "$RF" red "$S" --marker "$MARKER" --passage-file "$WORKDIR/passage" -- sh tests/run.sh > "$WORKDIR/red.out" 2>&1 \
        && pass "the red is recorded" || fail "red-first.sh red failed: $(cat "$WORKDIR/red.out")"
    REC=$(koto context get "$S" red_first.json 2>/dev/null)
    IMPL_BASE=$(koto context get "$S" impl_base 2>/dev/null | tr -d '[:space:]')
    [ -n "$IMPL_BASE" ] && [ "$(printf '%s' "$REC" | jq -r .red.base)" = "$IMPL_BASE" ] \
        && pass "the red's base equals impl_base" || fail "the red's base is [$(printf '%s' "$REC" | jq -r .red.base)], impl_base [$IMPL_BASE]"
    case "$(printf '%s' "$REC" | jq -r .red.output_tail)" in *"$MARKER"*) pass "the red's output tail holds the marker" ;; *) fail "the red's tail is [$(printf '%s' "$REC" | jq -r .red.output_tail)]" ;; esac
    [ "$(printf '%s' "$REC" | jq -r '.red.exit != 0')" = true ] && pass "the red's exit is non-zero" || fail "the red's exit is 0"
    tick "$S"
    expect_state "with a red recorded" implementation

    cat > greet.sh <<'EOF'
#!/bin/sh
[ -n "$1" ] || { echo "error: name required"; exit 1; }
echo "Hello, $1!"
EOF
    git commit -q -am "fix: refuse an empty name"
    tick "$S" '{"implementation_status":"complete"}'
    expect_state "after implementation" issue_type_routing
    tick "$S" '{"issue_type":"task"}'
    settle_verification "$S"
    expect_state "after local verification passed, the fix is held" pass_counting
    tick "$S"
    expect_state "with no green, still held" pass_counting
    case "$(gate_stdout fix_green)" in *"no green is recorded"*red-first/no-green*) pass "fix_green holds naming the missing green" ;; *) fail "fix_green printed [$(gate_stdout fix_green)]" ;; esac
    [ "$(visits "$S" finalization)" = 0 ] && pass "finalization is not reached without a green" || fail "finalization was entered"
    "$RF" green "$S" > "$WORKDIR/green.out" 2>&1 && pass "the green is recorded" || fail "red-first.sh green failed: $(cat "$WORKDIR/green.out")"
    [ "$(koto context get "$S" red_first.json 2>/dev/null | jq -r '"\(.green.head)|\(.green.exit)"')" = "$(git rev-parse HEAD)|0" ] \
        && pass "the green ran at HEAD and exited 0" || fail "the green is [$(koto context get "$S" red_first.json | jq -c .green)]"
    tick "$S"
    expect_state "with the green at HEAD" finalization
fi

# ==============================================================================
echo "--- a change: no fix label, straight to implementation, nothing owed"

S=rf_change
if walk_to_choice "$S" 2 --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI"; then
    tick "$S"
    expect_state "after the level is set" fix_determination
    [ "$(koto context get "$S" fix_kind.jsonl 2>/dev/null | jq -r .kind)" = change ] && pass "the unit is recorded as a change" \
        || fail "fix_kind.jsonl is [$(koto context get "$S" fix_kind.jsonl 2>/dev/null)]"
    tick "$S"
    expect_state "a change" implementation
    [ "$(visits "$S" reproduce)" = 0 ] && pass "a change never enters reproduce" || fail "a change entered reproduce"
    printf 'shout\n' > SHOUT.md
    git add SHOUT.md
    git commit -q -m "feat: shout"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"task"}'
    expect_state "a change through a deferral and pass_counting" finalization
    [ "$(visits "$S" pass_counting)" = 1 ] && pass "the change passed through pass_counting" || fail "pass_counting visits: $(visits "$S" pass_counting)"
    koto context exists "$S" red_first.json >/dev/null 2>&1 && fail "a change has a red_first.json" || pass "a change has no red or green record"
fi

# ==============================================================================
echo "--- a hand rebind at fix_determination holds the run"

S=rf_rebind
if walk_to_choice "$S" 1; then
    tick "$S"
    expect_state "after the level is set" fix_determination
    koto init "$S" --template "$TEMPLATE" --attach-live --var UNIT_KIND=change --var PLUGIN_ROOT="$PLUGIN_ROOT" \
        --var REVIEW_LEVEL=light >/dev/null 2>"$WORKDIR/attach.err" || fail "the hand rebind failed: $(cat "$WORKDIR/attach.err")"
    tick "$S"
    tick "$S"
    expect_state "after a hand rebind to change" fix_determination
    case "$(gate_stdout kind_unchanged)" in *"UNIT_KIND is change but the ledger records a fix (source label:bug)"*) pass "kind_unchanged names both" ;; *) fail "kind_unchanged printed [$(gate_stdout kind_unchanged)]" ;; esac
    [ "$(visits "$S" implementation)" = 0 ] && pass "the rebind doesn't reach implementation" || fail "implementation was entered"
    "$FK" declare "$S" --reason "put it back" >/dev/null 2>&1
    tick "$S"
    expect_state "after fix-kind.sh declare puts it back" reproduce
fi

# ==============================================================================
echo "--- a plan step's Fixes line is the report"

S=rf_step
if walk_to_choice "$S" 3 --var "FIX_REPORT=$FIXES"; then
    tick "$S"
    tick "$S"
    expect_state "a FIX_REPORT unit" reproduce
    [ "$(koto context get "$S" fix_kind.jsonl 2>/dev/null | jq -r '"\(.kind)|\(.source)"')" = "fix|step" ] \
        && pass "recorded as a fix with source step" || fail "fix_kind.jsonl is [$(koto context get "$S" fix_kind.jsonl 2>/dev/null)]"
    cat > tests/empty_name_test.sh <<'EOF'
#!/bin/sh
out=$(./greet.sh '' 2>&1)
[ "$out" = "error: name required" ] || { echo "expected error: name required, got $out"; exit 1; }
EOF
    git add tests/empty_name_test.sh
    git commit -q -m "test: reproduce the empty name"
    printf 'Tidy up greet.sh and print error: name required' > "$WORKDIR/issue-passage"
    "$RF" red "$S" --marker "$MARKER" --passage-file "$WORKDIR/issue-passage" -- sh tests/run.sh > "$WORKDIR/red.out" 2>&1
    grep -q 'refused: the passage is not verbatim' "$WORKDIR/red.out" \
        && pass "a passage from the issue body is refused" || fail "the issue passage gave: $(cat "$WORKDIR/red.out")"
    printf '%s' "$FIXES" > "$WORKDIR/step-passage"
    "$RF" red "$S" --marker "$MARKER" --passage-file "$WORKDIR/step-passage" -- sh tests/run.sh > "$WORKDIR/red.out" 2>&1 \
        && pass "a passage from the Fixes line is recorded" || fail "the step passage gave: $(cat "$WORKDIR/red.out")"
fi

# ==============================================================================
echo "--- observations wait for acceptance at pass_counting"

S=rf_obs
if walk_to_choice "$S" 1 --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI"; then
    tick "$S"
    tick "$S"
    expect_state "a fix" reproduce
    cat > "$WORKDIR/before.md" <<EOF
## Produced
Typed ./greet.sh '' at a terminal.

## Environment
The fixture repository.

## Seen
Hello, ! where the report expects error: name required.

## Why no check
Stands in for a terminal-only failure.

## Passage
Running \`./greet.sh ''\` prints \`Hello, !\` instead of \`error: name required\`

## Marker
error: name required
EOF
    "$RF" observe "$S" --phase before --file "$WORKDIR/before.md" >/dev/null 2>&1 && pass "a before-observation is recorded" || fail "observe before failed"
    tick "$S"
    expect_state "with a before-observation" implementation
    printf 'fixed\n' > FIXED.md
    git add FIXED.md
    git commit -q -m "fix: the empty name"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"task"}'
    expect_state "after the deferral" pass_counting
    printf '## Produced\nTyped it again.\n\n## Environment\nThe fixture.\n\n## Seen\nerror: name required\n' > "$WORKDIR/after.md"
    "$RF" observe "$S" --phase after --file "$WORKDIR/after.md" >/dev/null 2>&1 && pass "an after-observation is recorded" || fail "observe after failed"
    tick "$S"
    expect_state "an observation pair stays held" pass_counting
    case "$(gate_stdout fix_green)" in *"refused: observations wait for acceptance"*) pass "fix_green says observations wait for acceptance" ;; *) fail "fix_green printed [$(gate_stdout fix_green)]" ;; esac
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

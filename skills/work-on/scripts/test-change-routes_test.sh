#!/usr/bin/env bash
# test-change-routes_test.sh -- a pass that came with an edited test is held
# until the review panels have judged it at its content now, routed through
# the shipped work-on.md by a real koto
# Part of the work-on skill
#
# test-change_test.sh pins the script against a koto stand-in. This suite
# drives the template that ships, in the design's walkthrough repository:
# greet.sh prints `Hello, <name>!`, tests/greet_test.sh asserts
# `Hello, World!`, tests/run.sh runs every tests/*_test.sh, and the
# verification map's default runs tests/run.sh. gh is a stand-in serving the
# fixture's issues.
#
#   the declarations  fix_determination's action writes the ledger's header
#                     (test-change.sh init --entry) before fix-kind.sh
#                     resolve; pass_counting runs tests_counted
#                     (test-change.sh status) beside fix_green, `declined` goes
#                     back to implementation and exit 3 to done_blocked
#   an edited test    issue 2 drops the exclamation mark and edits the expected
#                     value, routed as a task so no panel runs: tests_counted
#                     holds with `tests/greet_test.sh due: no panel has judged
#                     it`, naming no seat or person; `declined` returns to
#                     implementation, routed as code the panels judge it
#                     corrects, and the run reaches finalization with no stop
#                     for a person and no acceptance line written
#   added tests only  a unit that only adds a test passes tests_counted with
#                     nothing judged and reaches finalization
#   a spent budget    a due test holds with exit 1 while a retry is left; with
#                     the panel retry budget spent tests_counted exits 3 and
#                     the run ends at done_blocked naming the budget
#   a test gap        a full code change whose QA packet cut the edited test's
#                     hunks, with no read of the file cited, is held at
#                     pass_counting as due for qa; the run commits a
#                     test-only fix, which makes the test due for every
#                     panel, submits `counting_status: test_gap` and returns to
#                     implementation with nothing written to the ledger, each
#                     panel plans a re-verifier for the due test alone
#                     (items-due) before verification runs again, and once
#                     every re-verifier judged it the run finalizes
#   end to end        the shipped pass_counting in a fixture: a panel round's
#                     corrects counts the edited test, a later commit to it
#                     holds it (`held: <test> due for scrutiny`), --plan plans
#                     the re-verifier with reason items-due, its packet carries
#                     the hunks and the run's note, and its corrects counts the
#                     unit again, each step printing its exit code
#   observations      the same fixture for a fix recorded by an observation
#                     pair: a panel round's shown lets check-green and status
#                     exit 0, a re-recorded after-observation holds both
#                     naming `observation`, --plan plans the re-verifier with
#                     the pair (items-due), and its shown counts the unit
#   a level raise    a fix raised from light to standard at
#                     review_level_check keeps UNIT_KIND at fix: fix-kind.sh
#                     agree still exits 0, and fix_green still holds without a
#                     green
#   the retired person-acceptance header
#                     a repository whose CLAUDE.md still declares the header
#                     that once required a person to accept: the header records
#                     no person requirement and tests_counted holds the edited
#                     test as due, naming no person
#   pr_precheck       its shipped block, in a fixture: an edit committed after
#                     counting holds tests_still_counted, and recount goes
#                     back to pass_counting; with nothing held it goes on
#   ci_pass_counting  the shipped ci_monitor (CI gates stubbed green) and
#                     ci_pass_counting blocks, in a fixture: a test edited by
#                     a CI fix is held after CI passes, and once a panel round
#                     judges it corrects a root goes through cascade_entry to
#                     done
#   test_gap after CI the same fixture with the real scrutiny block: a test the
#                     panels judged, edited again by a CI fix, is held at
#                     ci_pass_counting; `test_gap` returns to implementation,
#                     a test-only commit follows, scrutiny spawns only the
#                     re-verifier with the test due, and its corrects counts
#                     the unit at ci_pass_counting again; with a weakens the
#                     panel's last retry is spent, the run goes back to
#                     implementation, status exits 3 and the next weakens
#                     round ends the run at done_blocked
#
# Nothing here calls GitHub: the gh stand-in serves issues only.
#
# Usage: test-change-routes_test.sh
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
ktg_on_exit cleanup

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
TC="$PLUGIN_ROOT/skills/work-on/scripts/test-change.sh"
FK="$PLUGIN_ROOT/skills/work-on/scripts/fix-kind.sh"
RF="$PLUGIN_ROOT/skills/work-on/scripts/red-first.sh"
RL="$PLUGIN_ROOT/skills/work-on/scripts/review-level.sh"
PS="$PLUGIN_ROOT/skills/work-on/scripts/panel-scope.sh"
. "$PLUGIN_ROOT/scripts/lib/panel-round-testlib.sh"

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

jq -n --arg b "Running \`./greet.sh ''\` prints \`Hello, !\` instead of \`error: name required\`." \
    '{body: $b, labels: [{name: "bug"}]}' > "$GH_ISSUES/1.json"
jq -n '{body: "Drop the exclamation mark: ./greet.sh World should print Hello, World. Update the expected value in tests/greet_test.sh to match.", labels: []}' > "$GH_ISSUES/2.json"
jq -n '{body: "Add a test for a second name.", labels: []}' > "$GH_ISSUES/3.json"

# ==============================================================================
echo "--- the declarations"

COMPILED=$(koto template compile "$TEMPLATE" 2>"$WORKDIR/compile.err" | tail -n 1)
[ -f "$COMPILED" ] && pass "work-on.md compiles" || { fail "work-on.md does not compile: $(cat "$WORKDIR/compile.err")"; COMPILED=/dev/null; }
q() { jq -r "$1" "$COMPILED" 2>/dev/null; }
case "$(q '.states.fix_determination.default_action.command')" in
    *"test-change.sh\" init \"{{SESSION_NAME}}\" --entry"*"&& "*"fix-kind.sh\" resolve"*) pass "fix_determination's action writes the header, then resolves the kind" ;;
    *) fail "fix_determination's action is [$(q '.states.fix_determination.default_action.command')]" ;;
esac
case "$(q '.states.pass_counting.gates.tests_counted.command')" in
    *"test-change.sh\" status \"{{SESSION_NAME}}\""*) pass "tests_counted runs test-change.sh status" ;;
    *) fail "tests_counted is [$(q '.states.pass_counting.gates.tests_counted')]" ;;
esac
[ "$(q '[.states.pass_counting.transitions[] | select(.when.counting_status == "declined") | "\(.when["gates.tests_counted.exit_code"])>\(.target)"] | join(",")')" = "1>implementation" ] \
    && pass "declined goes back to implementation" || fail "the declined edges are [$(q '[.states.pass_counting.transitions[] | select(.when.counting_status == "declined")]')]"
[ "$(q '[.states.pass_counting.transitions[] | select(.when["gates.tests_counted.exit_code"] == 3) | "\(.when | keys | join("+"))>\(.target)"] | join(",")')" = "gates.tests_counted.exit_code>done_blocked" ] \
    && pass "exit 3, the retry budget spent, goes to done_blocked with no evidence" || fail "the exit-3 edges are [$(q '.states.pass_counting.transitions')]"
[ "$(q '[.states.pass_counting.transitions[] | select(.when.counting_status == "test_gap") | "\(.when["gates.tests_counted.exit_code"])/\(.when["gates.fix_green.exit_code"] // "-")>\(.target)"] | join(",")')" = "1/->implementation,0/1>implementation" ] \
    && pass "a test gap goes back to implementation from a held edit or a fix held on its green" \
    || fail "the test_gap edges are [$(q '[.states.pass_counting.transitions[] | select(.when.counting_status == "test_gap")]')]"
# A run with no hosted-of-record record has hosted_settled at 0 (the gate
# short-circuits), so that is the green edge this case reads; the edge for a
# record that isn't settled yet goes to hosted_record first.
[ "$(q '[.states.ci_monitor.transitions[] | select(.when["gates.ci_passing.exit_code"] == 0 and .when["gates.merge_state_clean.exit_code"] == 0 and .when["gates.hosted_settled.exit_code"] == 0) | .target] | join(",")')" = ci_pass_counting ] \
    && pass "green CI on a clean pull request goes to ci_pass_counting" || fail "ci_monitor's green edges are [$(q '.states.ci_monitor.transitions')]"
[ "$(q '.states.ci_pass_counting.gates.tests_counted.command')" = "$(q '.states.pass_counting.gates.tests_counted.command')" ] \
    && [ "$(q '.states.ci_pass_counting.gates.fix_green.command')" = "$(q '.states.pass_counting.gates.fix_green.command')" ] \
    && pass "ci_pass_counting runs pass_counting's two gates" || fail "ci_pass_counting's gates are [$(q '.states.ci_pass_counting.gates')]"
[ "$(q '[.states.ci_pass_counting.transitions[] | select(.when.counting_status == "declined") | .target] | join(",")')" = ci_monitor ] \
    && pass "declined at ci_pass_counting goes back to ci_monitor" || fail "the declined edges are [$(q '.states.ci_pass_counting.transitions')]"
[ "$(q '[.states.ci_pass_counting.transitions[] | select(.when.counting_status == "test_gap") | "\(.when["gates.tests_counted.exit_code"])/\(.when["gates.fix_green.exit_code"] // "-")>\(.target)"] | join(",")')" = "1/->implementation,0/1>implementation" ] \
    && pass "a test gap at ci_pass_counting goes back to implementation, as at pass_counting" \
    || fail "ci_pass_counting's test_gap edges are [$(q '[.states.ci_pass_counting.transitions[] | select(.when.counting_status == "test_gap")]')]"
[ "$(q '.states.ci_pass_counting.accepts.counting_status.values | join(",")')" = "green_failed,declined,test_gap,blocked" ] \
    && pass "ci_pass_counting accepts test_gap" || fail "ci_pass_counting accepts [$(q '.states.ci_pass_counting.accepts.counting_status.values')]"
[ "$(q '[.states | to_entries[] | . as $s | .value.transitions[]? | select(.when.counting_status == "test_gap") | $s.key] | unique | join(",")')" = "ci_pass_counting,pass_counting" ] \
    && pass "test_gap leaves only the two counting states" || fail "test_gap edges leave [$(q '[.states | to_entries[] | . as $s | .value.transitions[]? | select(.when.counting_status == "test_gap") | $s.key] | unique')]"
case "$(q '.states.pr_precheck.gates.tests_still_counted.command')" in
    *"test-change.sh\" status \"{{SESSION_NAME}}\""*) pass "pr_precheck re-runs test-change.sh status as tests_still_counted" ;;
    *) fail "tests_still_counted is [$(q '.states.pr_precheck.gates.tests_still_counted')]" ;;
esac
# The pull request edges go to pr_creation through probe_near, the
# rule-distance probe's pass-through state.
[ "$(q '[.states.pr_precheck.transitions[] | select(.target == "probe_near") | .when["gates.tests_still_counted.exit_code"]] | map(tostring) | join(",")')" = "0,0" ] \
    && pass "every pr_precheck edge toward pr_creation needs tests_still_counted to pass" || fail "pr_precheck's edges are [$(q '.states.pr_precheck.transitions')]"
grep -qE 'gh pr (edit|comment)' "$TC" && fail "test-change.sh calls gh pr edit or comment" || pass "test-change.sh writes nothing to a pull request"

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
slog() { printf '%s' "$HOME/.koto/sessions/$1/koto-$1.state.jsonl"; }
visits() {
    jq -s --arg st "$2" '[.[] | select(.type == "transitioned" and .payload.to == $st)] | length' "$(slog "$1")" 2>/dev/null
}
expect_state() { [ "$STATE" = "$2" ] && pass "$1: at $2" || fail "$1: at [$STATE], expected $2"; }
gate_stdout() {
    printf '%s' "$RESP" | jq -r --arg g "$1" '.blocking_conditions[]? | select(.name == $g) | .failure.captured.stdout // ""'
}
ledger() { koto context get "$1" test_change_ledger.jsonl 2>/dev/null; }

# walk_to_implementation <session> <issue> <level> [<more init vars>...]: a
# branch off main and a session through fix_determination to implementation
# (a change) or reproduce (a fix).
walk() {
    local s=$1 n=$2 level=$3
    shift 3
    git checkout -q "${WALK_FROM:-main}"
    git checkout -q -b "case-$s"
    koto init "$s" --template "$TEMPLATE" --var ARTIFACT_PREFIX="issue_$n" --var ISSUE_NUMBER="$n" \
        --var PLUGIN_ROOT="$PLUGIN_ROOT" "$@" >/dev/null 2>"$WORKDIR/init.err" \
        || { fail "$s: koto init failed: $(cat "$WORKDIR/init.err")"; return 1; }
    tick "$s" "{\"mode\":\"issue_backed\",\"issue_number\":\"$n\"}"
    tick "$s" '{"status":"override"}'
    tick "$s" '{"status":"override"}'
    printf '# Issue %s\n\n## Acceptance Criteria\n\n- [ ] greet prints the greeting the issue asks for\n' "$n" | koto context add "$s" context.md >/dev/null 2>&1
    printf 'plan\n' | koto context add "$s" plan.md >/dev/null 2>&1
    tick "$s" '{"plan_outcome":"plan_ready"}'
    [ "$STATE" = review_level_choice ] || { fail "$s: walked to [$STATE], not review_level_choice"; return 1; }
    "$RL" set "$s" "$level" >/dev/null 2>"$WORKDIR/set.err" || { fail "$s: review-level.sh set failed: $(cat "$WORKDIR/set.err")"; return 1; }
    tick "$s"
    [ "$STATE" = fix_determination ] || { fail "$s: at [$STATE], not fix_determination"; return 1; }
    tick "$s"
    return 0
}

settle_verification() {
    local i=0
    while [ "$STATE" = verification ] && [ "$i" -lt 12 ]; do
        tick "$1"
        i=$((i + 1))
    done
}

drop_mark() {
    printf '#!/bin/sh\necho "Hello, $1"\n' > greet.sh
    sed -i.bak 's/Hello, World!/Hello, World/g' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
}

# record_round <session> <panel> <round JSON>: records a round, each entry
# given the run its decision in <panel>_scope.json names.
record_round() {
    printf '%s\n' "$3" > "$WORKDIR/round.json"
    panel_round_runs "$1" "$2" "$WORKDIR/round.json"
    "$PS" --record "$2" "$1" "$WORKDIR/round.json" 2>"$WORKDIR/record.err" \
        || fail "$1: panel-scope.sh --record $2 failed: $(cat "$WORKDIR/record.err")"
}
JUDGED='"test_edits":[{"path":"tests/greet_test.sh","judgment":"corrects"}]'

# ==============================================================================
echo "--- an edited test no panel judged: held as due, then counted from the panels"

S=tc_edit
if walk "$S" 2 full; then
    expect_state "a change" implementation
    [ "$(ledger "$S" | head -n 1 | jq -r '"\(.event)|\(.author)"')" = "header|agent:$S" ] \
        && pass "fix_determination wrote the ledger's header with the run as author" \
        || fail "the ledger is [$(ledger "$S")]"
    drop_mark
    git commit -q -am "feat: drop the exclamation mark"
    "$TC" note "$S" --file tests/greet_test.sh --reason "the issue asks for the expected value to change" >/dev/null 2>&1 \
        && pass "the run records why it edited the test" || fail "test-change.sh note failed"
    tick "$S" '{"implementation_status":"complete"}'
    # Routed as a task, the edit skips the panels, so none has judged it.
    tick "$S" '{"issue_type":"task"}'
    settle_verification "$S"
    expect_state "after local verification passed, the edited test holds the unit" pass_counting
    case "$(gate_stdout tests_counted)" in
        *"held: tests/greet_test.sh due: no panel has judged it"*) pass "tests_counted holds the test as due: no panel has judged it" ;;
        *) fail "tests_counted printed [$(gate_stdout tests_counted)]" ;;
    esac
    case "$(gate_stdout tests_counted)" in
        *seat*|*person*) fail "tests_counted names a seat or a person: [$(gate_stdout tests_counted)]" ;;
        *) pass "tests_counted names no seat and no person" ;;
    esac
    [ "$(visits "$S" finalization)" = 0 ] && pass "finalization is not reached with an unjudged edit" || fail "finalization was entered"
    tick "$S" '{"counting_status":"declined"}'
    expect_state "declined for a due test goes back to implementation" implementation
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"code"}'
    expect_state "routed as code, the edit reaches the panels" scrutiny
    record_round "$S" scrutiny "[{\"seat\":\"completeness\",\"findings\":[],$JUDGED},{\"seat\":\"justification\",\"findings\":[],$JUDGED},{\"seat\":\"intent\",\"findings\":[],$JUDGED}]"
    tick "$S"
    record_round "$S" review "[{\"seat\":\"pragmatic\",\"findings\":[],$JUDGED},{\"seat\":\"architect\",\"findings\":[],$JUDGED},{\"seat\":\"maintainer\",\"findings\":[],$JUDGED}]"
    tick "$S"
    record_round "$S" qa "[{\"seat\":\"tester\",\"findings\":[],$JUDGED}]"
    tick "$S"
    settle_verification "$S"
    expect_state "with every panel's corrects, no person asked" finalization
    [ "$(ledger "$S" | jq -r 'select(.event == "seat" or .event == "accept" or .event == "decline" or .event == "refuse")' | wc -l | tr -d ' ')" = 0 ] \
        && pass "the ledger holds no seat, accept, decline or refuse line" || fail "the ledger is [$(ledger "$S")]"
fi

# ==============================================================================
echo "--- added tests only: counted with no acceptance"

S=tc_added
if walk "$S" 3 light --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI"; then
    expect_state "a change" implementation
    printf '#!/bin/sh\nout=$(./greet.sh Ada)\n[ "$out" = "Hello, Ada!" ] || exit 1\n' > tests/ada_test.sh
    git add tests/ada_test.sh
    git commit -q -m "test: a second name"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"task"}'
    expect_state "an added test" finalization
    [ "$(ledger "$S" | jq -r 'select(.event == "accept" or .event == "seat")' | wc -l | tr -d ' ')" = 0 ] \
        && pass "no seat was minted and no acceptance recorded" || fail "the ledger is [$(ledger "$S")]"
fi


# ==============================================================================
echo "--- a held test with the panel retry budget spent: done_blocked"

S=tc_spent
if walk "$S" 2 light --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI"; then
    drop_mark
    git commit -q -am "feat: drop the exclamation mark"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"task"}'
    expect_state "a due test with a retry left" pass_counting
    case "$(gate_stdout tests_counted)" in
        *"held: tests/greet_test.sh due: no panel has judged it"*) pass "with a retry left, tests_counted holds (exit 1)" ;;
        *) fail "tests_counted printed [$(gate_stdout tests_counted)]" ;;
    esac
    printf 'scrutiny 3\nscrutiny 2\nscrutiny 1\n' | koto context add "$S" panel_retries >/dev/null 2>&1
    tick "$S"
    expect_state "a due test with the panel retry budget spent" done_blocked
    case "$(koto context get "$S" failure_reason 2>/dev/null)" in
        *"retry budget is spent"*) pass "the failure reason names the spent retry budget" ;;
        *) fail "failure_reason is [$(koto context get "$S" failure_reason 2>/dev/null)]" ;;
    esac
fi

# ==============================================================================
echo "--- a test edit routed as a task twice: no panel ever reached, done_blocked"

S=tc_task_loop
if walk "$S" 2 light --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI"; then
    drop_mark
    git commit -q -am "feat: drop the exclamation mark"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"task"}'
    expect_state "routed as a task, the edited test is held" pass_counting
    tick "$S" '{"counting_status":"declined"}'
    expect_state "declined goes back to implementation" implementation
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"task"}'
    expect_state "routed as a task again, with still no panel on record" done_blocked
    case "$(koto context get "$S" failure_reason 2>/dev/null)" in
        *"still reached no panel"*) pass "the failure reason says no panel was reached" ;;
        *) fail "failure_reason is [$(koto context get "$S" failure_reason 2>/dev/null)]" ;;
    esac
fi

# ==============================================================================
echo "--- a level raise after fix_determination keeps the fix"

# unit_kind <session>: UNIT_KIND as the session's event log last set it.
unit_kind() {
    jq -rs '[.[] | (.payload.variables // .payload.rebound // .payload.vars // {}) | select(has("UNIT_KIND")) | .UNIT_KIND] | last // ""' "$(slog "$1")" 2>/dev/null
}

S=tc_raise
if walk "$S" 1 light; then
    expect_state "a fix" reproduce
    cat > tests/empty_name_test.sh <<'EOF'
#!/bin/sh
out=$(./greet.sh '' 2>&1)
[ "$out" = "error: name required" ] || { echo "expected error: name required, got $out"; exit 1; }
EOF
    git add tests/empty_name_test.sh
    git commit -q -m "test: reproduce the empty name"
    printf '%s' "Running \`./greet.sh ''\` prints \`Hello, !\` instead of \`error: name required\`" > "$WORKDIR/passage"
    "$RF" red "$S" --marker "error: name required" --passage-file "$WORKDIR/passage" -- sh tests/run.sh >/dev/null 2>&1 \
        || fail "the red was not recorded"
    tick "$S"
    expect_state "with a red" implementation
    mkdir -p scripts
    printf '#!/bin/sh\n[ -n "$1" ] || { echo "error: name required"; exit 1; }\necho "Hello, $1!"\n' > greet.sh
    seq 1 5 > scripts/tool.sh
    git add -A
    git commit -q -m "fix: refuse an empty name"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"code"}'
    expect_state "a light fix below its facts floor" review_level_check
    [ "$(unit_kind "$S")" = fix ] && pass "before the raise UNIT_KIND is fix" || fail "before the raise UNIT_KIND is [$(unit_kind "$S")]"
    "$RL" set "$S" standard >/dev/null 2>"$WORKDIR/set.err" && pass "the level is raised to standard at review_level_check" \
        || fail "the raise failed: $(cat "$WORKDIR/set.err")"
    K=$(unit_kind "$S")
    [ "$K" = fix ] && pass "after the raise UNIT_KIND is still fix" || fail "after the raise UNIT_KIND is [$K]"
    "$FK" agree "$S" "$K" >/dev/null 2>&1 && pass "fix-kind.sh agree still exits 0 after the raise" || fail "fix-kind.sh agree holds after the raise"
    "$RF" check-green "$S" > "$WORKDIR/g.out" 2>&1
    RC=$?
    [ "$RC" = 1 ] && grep -q 'no green is recorded' "$WORKDIR/g.out" \
        && pass "pass_counting's fix_green still requires the green after the raise" || fail "check-green exited $RC: $(cat "$WORKDIR/g.out")"
fi

# ==============================================================================
echo "--- a test gap found at pass_counting: back through implementation to a re-verifier"


S=tc_gap
if walk "$S" 2 full; then
    drop_mark
    git commit -q -am "feat: drop the exclamation mark"
    "$TC" note "$S" --file tests/greet_test.sh --reason "the issue asks for the expected value to change" >/dev/null 2>&1
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"code"}'
    expect_state "a full code change" scrutiny
    record_round "$S" scrutiny "[{\"seat\":\"completeness\",\"findings\":[],$JUDGED},{\"seat\":\"justification\",\"findings\":[],$JUDGED},{\"seat\":\"intent\",\"findings\":[],$JUDGED}]"
    tick "$S"
    record_round "$S" review "[{\"seat\":\"pragmatic\",\"findings\":[],$JUDGED},{\"seat\":\"architect\",\"findings\":[],$JUDGED},{\"seat\":\"maintainer\",\"findings\":[],$JUDGED}]"
    tick "$S"
    # QA's packet cut the test's hunks (a cap of one byte) and the tester
    # cited no read of the file, so QA's judgment doesn't count.
    export TEST_HUNKS_CAP=1
    record_round "$S" qa "[{\"seat\":\"tester\",\"findings\":[],$JUDGED}]"
    unset TEST_HUNKS_CAP
    tick "$S"
    settle_verification "$S"
    expect_state "after clean panels and a local pass, a test QA didn't read holds the unit" pass_counting
    [ "$(visits "$S" verification)" = 1 ] && pass "verification ran once" || fail "verification was entered $(visits "$S" verification) times"
    case "$(gate_stdout tests_counted)" in
        *"held: tests/greet_test.sh due for qa"*) pass "tests_counted holds the test as due for qa" ;;
        *) fail "tests_counted printed [$(gate_stdout tests_counted)]" ;;
    esac

    # The run finds its own test checks less than it should, and commits a
    # test-only fix.
    printf '[ "$(./greet.sh Ada)" = "Hello, Ada" ] || { echo "expected Hello, Ada"; exit 1; }\n' >> tests/greet_test.sh
    git commit -q -am "test: check a second name"
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1
    grep -q '^held: tests/greet_test.sh due for qa$' "$WORKDIR/s.out" && grep -q '^held: tests/greet_test.sh due for review$' "$WORKDIR/s.out" \
        && grep -q '^held: tests/greet_test.sh due for scrutiny$' "$WORKDIR/s.out" \
        && pass "the test-only fix makes the test due for every panel" || fail "status printed [$(cat "$WORKDIR/s.out")]"
    tick "$S" '{"counting_status":"test_gap","detail":"the edited test checks one name; a second name is left unchecked"}'
    expect_state "counting_status test_gap from a held edit" implementation
    [ "$(ledger "$S" | jq -r 'select(.event == "decline" or .event == "seat") | .event' | wc -l | tr -d ' ')" = 0 ] \
        && pass "a test gap writes no seat or decline line to the ledger" || fail "the ledger is [$(ledger "$S")]"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"code"}'
    expect_state "the lap after the test gap" scrutiny
    GOT=$(koto context get "$S" scrutiny_scope.json 2>/dev/null | jq -r '[.decisions[] | "\(.seat):\(.decision):\(.reason | split(":")[0] | select(. == "items-due") // "-"):\([.due_items[]?.item] | join("+"))"] | join(",")')
    [ "$GOT" = "completeness:keep:-:,justification:keep:-:,intent:keep:-:,reverifier:recheck:items-due:tests/greet_test.sh" ] \
        && pass "scrutiny plans a re-verifier for the due test alone" || fail "scrutiny_scope.json decisions are [$GOT]"
    [ "$(visits "$S" verification)" = 1 ] && pass "verification has not run again before the re-verifier" \
        || fail "verification was entered $(visits "$S" verification) times before the re-verifier"
    REJUDGED='[{"seat":"reverifier","findings":[],"answers":[],"test_edits":[{"path":"tests/greet_test.sh","judgment":"corrects"}]}]'
    record_round "$S" scrutiny "$REJUDGED"
    tick "$S"
    expect_state "review's judgment is at the old content too" review
    record_round "$S" review "$REJUDGED"
    tick "$S"
    expect_state "and QA's" qa_validation
    record_round "$S" qa "$REJUDGED"
    tick "$S"
    settle_verification "$S"
    expect_state "every panel's re-verifier judged the test at its content now: counted" finalization
    [ "$(visits "$S" verification)" = 2 ] && pass "verification ran again after the re-verifiers" \
        || fail "verification was entered $(visits "$S" verification) times"
fi

# ==============================================================================
# The header's name is built from two parts, so a search for it finds no
# reader anywhere in the plugin.
DECL="Test Change"
DECL="$DECL Acceptance"
echo "--- the retired person-acceptance header: read by nothing, held as any other"

git checkout -q main
git checkout -q -b person-main
printf '# greet\n\n## Repo Visibility: Private\n\n## %s: person\n' "$DECL" > CLAUDE.md
git commit -q -am "docs: an old person-required declaration"
S=tc_person
if WALK_FROM=person-main walk "$S" 2 light --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI"; then
    case "$(ledger "$S" | head -n 1)" in
        *person_required*) fail "the header records a person requirement: [$(ledger "$S" | head -n 1)]" ;;
        *) pass "the header records no person requirement" ;;
    esac
    drop_mark
    git commit -q -am "feat: drop the exclamation mark"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"task"}'
    expect_state "the edited test is held" pass_counting
    case "$(gate_stdout tests_counted)" in
        *person*) fail "tests_counted names a person: [$(gate_stdout tests_counted)]" ;;
        *"held: tests/greet_test.sh due: no panel has judged it"*) pass "tests_counted holds the test as due, as without the header" ;;
        *) fail "tests_counted printed [$(gate_stdout tests_counted)]" ;;
    esac
fi

# ==============================================================================
# The shipped pr_precheck, ci_monitor and ci_pass_counting blocks, run by a
# fixture that starts in front of them: no gh call, no pull request.

# extract_state <name>: the state's block from the template's frontmatter.
extract_state() {
    awk -v want="  $1:" '
        $0 == want { found = 1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found && /^---$/ { exit }
        found { print }
    ' "$TEMPLATE"
}
# stub_block <block> <gate=exit>...: the named gates' commands replaced.
stub_block() {
    local block="$1"; shift
    printf '%s\n' "$block" | awk -v stubs="$*" '
        BEGIN { n = split(stubs, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); ex[kv[1]] = kv[2] } }
        /^      [a-z_]+:$/ { gate = $1; sub(/:$/, "", gate) }
        /^        command:/ { if (gate in ex) { print "        command: \"exit " ex[gate] "\""; next } }
        # The rule-distance probe gates pass, as they do for a run in no arm;
        # probe_test.sh and probe-routes_test.sh exercise them.
        /^        command:/ { if (gate == "probe_ack" || gate == "probe_value_absent") { print "        command: \"exit 0\""; next } }
        { print }'
}
# fixture <file> <first-state> <blocks> <stub terminals...>
fixture() {
    local f=$1 first=$2 blocks=$3 t
    shift 3
    {
        printf '%s\n' '---' 'name: test-change-fixture' 'version: "1.0"' \
            'description: The shipped counting blocks after a passing check.' 'initial_state: start' \
            'variables:' \
            '  PLUGIN_ROOT:' '    description: plugin root' '    required: false' \
            '  SHARED_BRANCH:' '    description: shared branch' '    required: false' \
            'states:' '  start:' '    transitions:' "      - target: $first"
        printf '%s\n' "$blocks"
        printf '%s\n' '  cascade_entry:' '    transitions:' '      - target: done'
        for t in "$@"; do printf '%s\n' "  $t:" '    terminal: true'; done
        printf '%s\n' '  done:' '    terminal: true' '  done_blocked:' '    terminal: true' '    failure: true' \
            '    accepts:' '      failure_reason:' '        type: string' '---' '' '## start' '' 'Start.'
        for t in $(printf '%s\n' "$blocks" | awk '/^  [a-z_]+:$/ { sub(/:$/, ""); print $1 }') cascade_entry "$@" done done_blocked; do
            printf '%s\n' '' "## $t" '' 'Stub.'
        done
    } > "$f"
}
# fixture_session <session> <template>: a session on the current branch with
# impl_base, the rules copy and a change determination, and the ledger's header.
fixture_session() {
    koto init "$1" --template "$2" --var PLUGIN_ROOT="$PLUGIN_ROOT" >"$WORKDIR/init.err" 2>&1 \
        || { fail "$1: koto init failed: $(cat "$WORKDIR/init.err")"; return 1; }
    git rev-parse HEAD | koto context add "$1" impl_base >/dev/null 2>&1
    koto context add "$1" review_level_rules.tsv < "$PLUGIN_ROOT/skills/work-on/references/review-level-rules.tsv" >/dev/null 2>&1
    printf '{"ts":"t","event":"determine","kind":"change","source":"none"}\n' | koto context add "$1" fix_kind.jsonl >/dev/null 2>&1
    "$TC" init "$1" >/dev/null 2>"$WORKDIR/tcinit.err" || { fail "$1: test-change.sh init failed: $(cat "$WORKDIR/tcinit.err")"; return 1; }
}

echo "--- end to end: a test edited after the panels looked is held until a re-verifier judges it"

# The shipped pass_counting block in a fixture, with the real scripts on the
# way to it: a panel round recorded with panel-scope.sh --record, a later
# commit to the test, test-change.sh status, panel-scope.sh --plan and the
# re-verifier's round. Each step prints its exit code.
fixture "$WORKDIR/counting.md" pass_counting "$(extract_state pass_counting)" finalization implementation
git checkout -q main
git checkout -q -b case-e2e
S=tc_e2e
if fixture_session "$S" "$WORKDIR/counting.md"; then
    drop_mark
    git commit -q -am "feat: drop the exclamation mark"
    "$TC" note "$S" --file tests/greet_test.sh --reason "the issue asks for the expected value to change" >/dev/null 2>&1
    "$PS" --plan scrutiny "$S" >/dev/null 2>"$WORKDIR/plan.err"; RC=$?
    echo "  step: panel-scope.sh --plan scrutiny (first round) exit $RC"
    record_round "$S" scrutiny "[{\"seat\":\"completeness\",\"findings\":[],$JUDGED},{\"seat\":\"justification\",\"findings\":[],$JUDGED},{\"seat\":\"intent\",\"findings\":[],$JUDGED}]"
    echo "  step: panel-scope.sh --record scrutiny (every seat corrects) done"
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1; RC=$?
    echo "  step: test-change.sh status exit $RC"
    [ "$RC" = 0 ] && pass "with every seat's corrects at the test's content, status exits 0" || fail "status exited $RC: $(cat "$WORKDIR/s.out")"

    printf '# the empty name is not checked here\n' >> tests/greet_test.sh
    git commit -q -am "test: note what the test leaves out"
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1; RC=$?
    echo "  step: test-change.sh status after the test changed exit $RC"
    [ "$RC" = 1 ] && grep -q '^held: tests/greet_test.sh due for scrutiny$' "$WORKDIR/s.out" \
        && pass "a commit to the judged test holds it: status exits 1 with held: tests/greet_test.sh due" \
        || fail "status exited $RC: $(cat "$WORKDIR/s.out")"
    tick "$S"
    expect_state "the counting gate holds on the due test" pass_counting

    "$PS" --plan scrutiny "$S" > "$WORKDIR/scope.out" 2>"$WORKDIR/plan.err"; RC=$?
    echo "  step: panel-scope.sh --plan scrutiny exit $RC"
    GOT=$(jq -r '[.decisions[] | select(.decision != "keep") | "\(.seat):\(.reason | split(":")[0]):\([.due_items[]?.item] | join("+"))"] | join(",")' "$WORKDIR/scope.out" 2>/dev/null)
    [ "$RC" = 0 ] && [ "$GOT" = "reverifier:items-due:tests/greet_test.sh" ] \
        && pass "--plan plans the re-verifier alone, reason items-due, with the test due" \
        || fail "--plan exited $RC with spawned decisions [$GOT]: $(cat "$WORKDIR/plan.err")"
    PACKET_DIR="$WORKDIR/e2e-scratch"
    mkdir -m 700 "$PACKET_DIR"
    PKT=$("$PLUGIN_ROOT/scripts/review-packet.sh" recheck --session "$S" --panel scrutiny --seat reverifier --scratch "$PACKET_DIR" 2>"$WORKDIR/pkt.err"); RC=$?
    echo "  step: review-packet.sh recheck exit $RC"
    [ "$RC" = 0 ] && grep -q '^## Test changes$' "$PKT" && grep -q 'the issue asks for the expected value to change' "$PKT" \
        && grep -q '^+# the empty name is not checked here$' "$PKT" \
        && pass "the re-verifier's packet carries the test's hunks and the run's note" \
        || fail "recheck packet exited $RC: $(cat "$WORKDIR/pkt.err")"
    record_round "$S" scrutiny '[{"seat":"reverifier","findings":[],"answers":[],"test_edits":[{"path":"tests/greet_test.sh","judgment":"corrects"}]}]'
    echo "  step: panel-scope.sh --record scrutiny (the re-verifier's corrects) done"
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1; RC=$?
    echo "  step: test-change.sh status after the re-verifier exit $RC"
    [ "$RC" = 0 ] && pass "the re-verifier's corrects counts the unit: status exits 0" || fail "status exited $RC: $(cat "$WORKDIR/s.out")"
    tick "$S"
    expect_state "the counting gate passes" finalization
    [ "$(ledger "$S" | jq -r 'select(.event == "seat" or .event == "accept")' | wc -l | tr -d ' ')" = 0 ] \
        && pass "no seat was minted and no acceptance written" || fail "the ledger is [$(ledger "$S")]"
    printf 'not json' | koto context add "$S" verdict_ledger.json >/dev/null 2>&1
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1; RC=$?
    echo "  step: test-change.sh status with an unreadable verdict record exit $RC"
    [ "$RC" = 2 ] && pass "a verdict record that can't be read: status exits 2" || fail "status exited $RC: $(cat "$WORKDIR/s.out")"
fi

echo "--- end to end: an observation pair is judged by the panels and counted from their record"

# The same fixture for a fix whose red and green are observations: the pair is
# recorded with red-first.sh observe, a panel round judges it shown, and
# fix_green (red-first.sh check-green) and tests_counted (test-change.sh
# status) count it; re-recording the after-observation holds both naming
# `observation`, and the re-verifier's shown counts the unit again. No seat
# is minted and no acceptance written. Each step prints its exit code.
git checkout -q main
git checkout -q -b case-e2e-obs
S=tc_e2e_obs
if fixture_session "$S" "$WORKDIR/counting.md"; then
    printf '{"ts":"t","event":"determine","kind":"fix","source":"label:bug"}\n' | koto context add "$S" fix_kind.jsonl >/dev/null 2>&1
    jq -r .body "$GH_ISSUES/1.json" | koto context add "$S" fix_report.txt >/dev/null 2>&1
    cat > "$WORKDIR/obs-before.md" <<EOF
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
    "$RF" observe "$S" --phase before --file "$WORKDIR/obs-before.md" >/dev/null 2>"$WORKDIR/obs.err"; RC=$?
    echo "  step: red-first.sh observe before exit $RC"
    printf '#!/bin/sh\n[ -n "$1" ] || { echo "error: name required" >&2; exit 2; }\necho "Hello, $1!"\n' > greet.sh
    git commit -q -am "fix: refuse an empty name"
    printf '## Produced\nTyped it again.\n\n## Environment\nThe fixture.\n\n## Seen\nerror: name required\n' > "$WORKDIR/obs-after.md"
    "$RF" observe "$S" --phase after --file "$WORKDIR/obs-after.md" >/dev/null 2>>"$WORKDIR/obs.err"; RC2=$?
    echo "  step: red-first.sh observe after exit $RC2"
    [ "$RC" = 0 ] && [ "$RC2" = 0 ] && pass "the observation pair is recorded" || fail "observe exited $RC/$RC2: $(cat "$WORKDIR/obs.err")"

    "$RF" check-green "$S" > "$WORKDIR/g.out" 2>&1; RC=$?
    echo "  step: red-first.sh check-green before any panel exit $RC"
    "$PS" --plan scrutiny "$S" >/dev/null 2>"$WORKDIR/plan.err"; RC=$?
    echo "  step: panel-scope.sh --plan scrutiny (first round) exit $RC"
    SHOWN='"observations":{"judgment":"shown"}'
    record_round "$S" scrutiny "[{\"seat\":\"completeness\",\"findings\":[],$SHOWN},{\"seat\":\"justification\",\"findings\":[],$SHOWN},{\"seat\":\"intent\",\"findings\":[],$SHOWN}]"
    echo "  step: panel-scope.sh --record scrutiny (every seat shown) done"
    "$RF" check-green "$S" > "$WORKDIR/g.out" 2>&1; RC=$?
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1; RC2=$?
    echo "  step: check-green exit $RC, status exit $RC2"
    [ "$RC" = 0 ] && [ "$RC2" = 0 ] && pass "with the pair judged shown, check-green and status both exit 0" \
        || fail "check-green $RC [$(cat "$WORKDIR/g.out")], status $RC2 [$(cat "$WORKDIR/s.out")]"

    printf '## Produced\nTyped it once more.\n\n## Environment\nThe fixture.\n\n## Seen\nerror: name required, exit 2\n' > "$WORKDIR/obs-after.md"
    "$RF" observe "$S" --phase after --file "$WORKDIR/obs-after.md" >/dev/null 2>&1
    "$RF" check-green "$S" > "$WORKDIR/g.out" 2>&1; RC=$?
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1; RC2=$?
    echo "  step: after re-recording the after-observation: check-green exit $RC, status exit $RC2"
    [ "$RC" = 1 ] && grep -q 'observation due for scrutiny' "$WORKDIR/g.out" \
        && pass "a re-recorded after-observation: check-green exits 1 naming observation" \
        || fail "check-green exited $RC: $(cat "$WORKDIR/g.out")"
    [ "$RC2" = 1 ] && grep -q '^held: observation due for scrutiny$' "$WORKDIR/s.out" \
        && pass "a re-recorded after-observation: status exits 1 with held: observation due" \
        || fail "status exited $RC2: $(cat "$WORKDIR/s.out")"
    tick "$S"
    expect_state "the counting gates hold on the due pair" pass_counting

    "$PS" --plan scrutiny "$S" > "$WORKDIR/scope.out" 2>"$WORKDIR/plan.err"; RC=$?
    echo "  step: panel-scope.sh --plan scrutiny exit $RC"
    GOT=$(jq -r '[.decisions[] | select(.decision != "keep") | "\(.seat):\(.reason | split(":")[0]):\([.due_items[]?.item] | join("+"))"] | join(",")' "$WORKDIR/scope.out" 2>/dev/null)
    [ "$RC" = 0 ] && [ "$GOT" = "reverifier:items-due:observation" ] \
        && pass "--plan plans the re-verifier alone, reason items-due, with the pair due" \
        || fail "--plan exited $RC with spawned decisions [$GOT]: $(cat "$WORKDIR/plan.err")"
    PKT=$("$PLUGIN_ROOT/scripts/review-packet.sh" recheck --session "$S" --panel scrutiny --seat reverifier --scratch "$PACKET_DIR" 2>"$WORKDIR/pkt.err"); RC=$?
    echo "  step: review-packet.sh recheck exit $RC"
    [ "$RC" = 0 ] && grep -q '^## Observations$' "$PKT" && grep -q 'error: name required, exit 2' "$PKT" \
        && pass "the re-verifier's packet carries the pair as it is recorded now" \
        || fail "recheck packet exited $RC: $(cat "$WORKDIR/pkt.err")"
    record_round "$S" scrutiny "[{\"seat\":\"reverifier\",\"findings\":[],\"answers\":[],$SHOWN}]"
    echo "  step: panel-scope.sh --record scrutiny (the re-verifier's shown) done"
    "$RF" check-green "$S" > "$WORKDIR/g.out" 2>&1; RC=$?
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1; RC2=$?
    echo "  step: after the re-verifier: check-green exit $RC, status exit $RC2"
    [ "$RC" = 0 ] && [ "$RC2" = 0 ] && pass "the re-verifier's shown counts the pair: check-green and status exit 0" \
        || fail "check-green $RC [$(cat "$WORKDIR/g.out")], status $RC2 [$(cat "$WORKDIR/s.out")]"
    tick "$S"
    expect_state "both counting gates pass" finalization
    [ "$(ledger "$S" | jq -r 'select(.event == "seat" or .event == "accept")' | wc -l | tr -d ' ')" = 0 ] \
        && pass "no seat was minted and no acceptance written for the pair" || fail "the ledger is [$(ledger "$S")]"
fi

echo "--- pr_precheck re-runs status: a commit after counting is held before a pull request opens"

PRE_BLOCKS=$(stub_block "$(extract_state pr_precheck)" branch_docs_visibility=0)
fixture "$WORKDIR/precheck.md" pr_precheck "$PRE_BLOCKS" probe_near pass_counting check_exit
git checkout -q main
git checkout -q -b case-precheck
S=tc_precheck
if fixture_session "$S" "$WORKDIR/precheck.md"; then
    drop_mark
    git commit -q -am "feat: drop the exclamation mark after counting"
    tick "$S"
    expect_state "an edit made after counting holds pr_precheck" pr_precheck
    case "$(gate_stdout tests_still_counted)" in
        *"held: tests/greet_test.sh due: no panel has judged it"*) pass "tests_still_counted holds the test as due" ;;
        *) fail "tests_still_counted printed [$(gate_stdout tests_still_counted)]" ;;
    esac
    tick "$S" '{"precheck_status":"recount"}'
    expect_state "recount goes back to pass_counting" pass_counting
fi
git checkout -q main
git checkout -q -b case-precheck-clean
S=tc_precheck_clean
if fixture_session "$S" "$WORKDIR/precheck.md"; then
    tick "$S"
    expect_state "with nothing held, pr_precheck goes on" probe_near
fi

echo "--- ci_pass_counting: a test edited while fixing CI is held after CI passes until a panel judges it"

CI_BLOCKS="$(stub_block "$(extract_state ci_monitor)" ci_passing=0 merge_state_clean=0)
$(extract_state ci_pass_counting)"
fixture "$WORKDIR/ci.md" ci_monitor "$CI_BLOCKS" hosted_record implementation
git checkout -q main
git checkout -q -b case-ci
S=tc_ci
if fixture_session "$S" "$WORKDIR/ci.md"; then
    printf '#!/bin/sh\necho "Hello, $1"\n' > greet.sh
    sed -i.bak 's/Hello, World!/Hello, World/g' tests/greet_test.sh && rm -f tests/greet_test.sh.bak
    git commit -q -am "fix(ci): match the greeting the check expects"
    tick "$S"
    expect_state "after CI passed, the CI fix's test edit is held" ci_pass_counting
    [ "$(visits "$S" ci_monitor)" -ge 1 ] && pass "the run came through ci_monitor's green edge" || fail "ci_monitor was never entered"
    case "$(gate_stdout tests_counted)" in
        *"held: tests/greet_test.sh due: no panel has judged it"*) pass "ci_pass_counting's tests_counted holds the test as due" ;;
        *) fail "tests_counted printed [$(gate_stdout tests_counted)]" ;;
    esac
    "$PS" --plan scrutiny "$S" >/dev/null 2>"$WORKDIR/plan.err" || fail "--plan scrutiny failed: $(cat "$WORKDIR/plan.err")"
    record_round "$S" scrutiny "[{\"seat\":\"completeness\",\"findings\":[],$JUDGED},{\"seat\":\"justification\",\"findings\":[],$JUDGED},{\"seat\":\"intent\",\"findings\":[],$JUDGED}]"
    tick "$S"
    expect_state "judged by a panel, a root goes on through cascade_entry" done
    [ "$(visits "$S" cascade_entry)" = 1 ] && pass "a root went through cascade_entry" || fail "cascade_entry visits: $(visits "$S" cascade_entry)"

fi

echo "--- test_gap at ci_pass_counting: a test fixed after CI goes back through the panels"

# The shipped ci_monitor (CI gates stubbed green), ci_pass_counting and
# scrutiny blocks. implementation stands in for the real one: it clears the
# same panel keys on entry and goes to scrutiny on `complete`. review stands in
# for the rest of the lap (the other panels, verification, pass_counting,
# finalization, and pr_creation reusing the open pull request) and goes
# straight back to ci_monitor.
GAP_STUBS=$(printf '%s\n' \
    '  implementation:' \
    '    clear_on_entry: [scrutiny_results.json, review_results.json, qa_results.json, light_results.json, summary.md, scrutiny_scope.json, review_scope.json, qa_scope.json, light_scope.json]' \
    '    accepts:' '      implementation_status:' '        type: enum' '        values: [complete]' \
    '    transitions:' '      - target: scrutiny' '        when:' '          implementation_status: complete' \
    '  review:' '    transitions:' '      - target: ci_monitor')
GAP_BLOCKS="$(stub_block "$(extract_state ci_monitor)" ci_passing=0 merge_state_clean=0)
$(extract_state ci_pass_counting)
$(extract_state scrutiny)
$GAP_STUBS"
fixture "$WORKDIR/ci-gap.md" ci_monitor "$GAP_BLOCKS" hosted_record
FULL_SCRUTINY="[{\"seat\":\"completeness\",\"findings\":[],$JUDGED},{\"seat\":\"justification\",\"findings\":[],$JUDGED},{\"seat\":\"intent\",\"findings\":[],$JUDGED}]"

# ci_gap_hold <session>: a panel round judges the edited test, a CI fix edits it
# again, and the run is held at ci_pass_counting with the test due for
# scrutiny; then `test_gap` and a test-only commit, and the lap's scrutiny.
ci_gap_hold() {
    drop_mark
    git commit -q -am "feat: drop the exclamation mark"
    "$TC" note "$1" --file tests/greet_test.sh --reason "the issue asks for the expected value to change" >/dev/null 2>&1
    "$PS" --plan scrutiny "$1" >/dev/null 2>"$WORKDIR/plan.err" || fail "$1: --plan scrutiny failed: $(cat "$WORKDIR/plan.err")"
    record_round "$1" scrutiny "$FULL_SCRUTINY"
    printf '# the CI runner has no locale; the greeting is plain ASCII\n' >> tests/greet_test.sh
    git commit -q -am "fix(ci): note the runner's locale in the test"
    tick "$1"
    expect_state "$1: after CI passed, the CI fix's test edit is held" ci_pass_counting
    case "$(gate_stdout tests_counted)" in
        *"held: tests/greet_test.sh due for scrutiny"*) pass "$1: tests_counted holds the test as due for scrutiny" ;;
        *) fail "$1: tests_counted printed [$(gate_stdout tests_counted)]" ;;
    esac
    tick "$1" '{"counting_status":"test_gap","detail":"the test checks one name after the CI fix; a second name is left unchecked"}'
    expect_state "$1: counting_status test_gap at ci_pass_counting" implementation
    [ "$(visits "$1" ci_monitor)" = 1 ] && pass "$1: test_gap does not go back to ci_monitor" \
        || fail "$1: ci_monitor was entered $(visits "$1" ci_monitor) times"
    printf '[ "$(./greet.sh Ada)" = "Hello, Ada" ] || { echo "expected Hello, Ada"; exit 1; }\n' >> tests/greet_test.sh
    git commit -q -am "test: check a second name"
    tick "$1" '{"implementation_status":"complete"}'
    expect_state "$1: the lap after the test gap" scrutiny
    GOT=$(koto context get "$1" scrutiny_scope.json 2>/dev/null | jq -r '[.decisions[] | select(.decision != "keep") | "\(.seat):\(.reason | split(":")[0]):\([.due_items[]?.item] | join("+"))"] | join(",")')
    [ "$GOT" = "reverifier:items-due:tests/greet_test.sh" ] \
        && pass "$1: scrutiny spawns only the re-verifier, with the test due" || fail "$1: scrutiny's spawned decisions are [$GOT]"
}

git checkout -q main
git checkout -q -b case-ci-gap
S=tc_ci_gap
if fixture_session "$S" "$WORKDIR/ci-gap.md"; then
    ci_gap_hold "$S"
    record_round "$S" scrutiny '[{"seat":"reverifier","findings":[],"answers":[],"test_edits":[{"path":"tests/greet_test.sh","judgment":"corrects"}]}]'
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1; RC=$?
    [ "$RC" = 0 ] && pass "the re-verifier's corrects counts the unit: status exits 0" || fail "status exited $RC: $(cat "$WORKDIR/s.out")"
    tick "$S"
    expect_state "counted at ci_pass_counting again, a root goes on through cascade_entry" done
    [ "$(visits "$S" ci_pass_counting)" = 2 ] && pass "the run reached ci_pass_counting a second time" \
        || fail "ci_pass_counting was entered $(visits "$S" ci_pass_counting) times"
    [ "$(visits "$S" cascade_entry)" = 1 ] && pass "the second count passed: cascade_entry was entered" \
        || fail "cascade_entry visits: $(visits "$S" cascade_entry)"
fi

git checkout -q main
git checkout -q -b case-ci-gap-weakens
S=tc_ci_gap_weak
if fixture_session "$S" "$WORKDIR/ci-gap.md"; then
    # Two retries spent earlier in the run, the last with two blocking
    # findings: one retry is left, and a round with fewer is progress.
    printf 'scrutiny 3\nscrutiny 2\n' | koto context add "$S" panel_retries >/dev/null 2>&1
    ci_gap_hold "$S"
    WEAKENS='[{"seat":"reverifier","findings":[],"answers":[],"test_edits":[{"path":"tests/greet_test.sh","judgment":"weakens"}]}]'
    record_round "$S" scrutiny "$WEAKENS"
    tick "$S"
    expect_state "the re-verifier's weakens holds the panel" scrutiny
    "$PLUGIN_ROOT/skills/work-on/scripts/panel-retry-budget.sh" "$S" scrutiny > "$WORKDIR/b.out" 2>&1; RC=$?
    [ "$RC" = 0 ] && [ "$(koto context get "$S" panel_retries 2>/dev/null | wc -l | tr -d ' ')" = 3 ] \
        && pass "the weakens spends the panel's last retry: the retry count goes from 2 to 3" \
        || fail "panel-retry-budget.sh exited $RC [$(cat "$WORKDIR/b.out")], panel_retries is [$(koto context get "$S" panel_retries 2>/dev/null)]"
    tick "$S" '{"scrutiny_outcome":"blocking_retry"}'
    expect_state "blocking_retry after the weakens" implementation
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1; RC=$?
    [ "$RC" = 3 ] && grep -q 'budget spent' "$WORKDIR/s.out" \
        && pass "with the budget spent, the counting check exits 3" || fail "status exited $RC: $(cat "$WORKDIR/s.out")"
    printf '# a second rework of the test\n' >> tests/greet_test.sh
    git commit -q -am "test: rework the second-name check"
    tick "$S" '{"implementation_status":"complete"}'
    expect_state "the lap after the retry" scrutiny
    record_round "$S" scrutiny "$WEAKENS"
    "$PLUGIN_ROOT/skills/work-on/scripts/panel-retry-budget.sh" "$S" scrutiny > "$WORKDIR/b.out" 2>&1; RC=$?
    [ "$RC" != 0 ] && pass "a further weakens gets no retry" || fail "panel-retry-budget.sh granted a fourth retry: $(cat "$WORKDIR/b.out")"
    jq -n --arg r "$(sed -n 's/^verdict=escalate reason=//p' "$WORKDIR/b.out")" '{scrutiny_outcome: "blocking_escalate", failure_reason: $r}' > "$WORKDIR/ev.json"
    tick "$S" "@$WORKDIR/ev.json"
    expect_state "the budget spent, the run ends" done_blocked
    [ "$(visits "$S" ci_pass_counting)" = 1 ] && pass "the run never counted the weakened test" \
        || fail "ci_pass_counting was entered $(visits "$S" ci_pass_counting) times"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

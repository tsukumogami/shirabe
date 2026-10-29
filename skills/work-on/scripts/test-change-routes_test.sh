#!/usr/bin/env bash
# test-change-routes_test.sh -- a pass that came with an edited test is held
# until a minted acceptance seat accepts it, routed through the shipped
# work-on.md by a real koto
# Part of the work-on skill
#
# test-change_test.sh and acceptance-rule_test.sh pin the script and the rule
# against a koto stand-in. This suite drives the template that ships, in the
# design's walkthrough repository: greet.sh prints `Hello, <name>!`,
# tests/greet_test.sh asserts `Hello, World!`, tests/run.sh runs every
# tests/*_test.sh, and the verification map's default runs tests/run.sh. gh is
# a stand-in serving the fixture's issues. Its main branch declares no
# person-required acceptance, so only the person-required case, run from a
# branch that declares it, waits for a person.
#
#   the declarations  fix_determination's action writes the ledger's header
#                     (test-change.sh init --entry) before fix-kind.sh
#                     resolve; pass_counting runs tests_counted
#                     (test-change.sh status) beside fix_green, a decline goes
#                     back to implementation and exit 3 to done_blocked
#   an edited test    issue 2 drops the exclamation mark and edits the expected
#                     value: after local verification passes, tests_counted
#                     holds with `unaccepted tests/greet_test.sh`; the run's
#                     own accept exits 1 with rule author and an unminted
#                     reviewer's with rule unminted-seat; the seat the run
#                     mints accepts from another directory and status exits 0;
#                     a later commit to the test holds again with `changed
#                     since acceptance`; a second seat's accept lets the run
#                     reach finalization with no stop for a person
#   added tests only  a unit that only adds a test passes tests_counted with no
#                     acceptance and reaches finalization
#   declines          a seat's decline and `counting_status: declined` return
#                     the run to implementation; the third decline of the same
#                     test ends the run at done_blocked
#   a level raise     a fix raised from light to standard at
#                     review_level_check keeps UNIT_KIND at fix: fix-kind.sh
#                     agree still exits 0, and fix_green still holds without a
#                     green
#   person-required   a repository whose CLAUDE.md declares `## Test Change
#                     Acceptance: person`: the header records it, tests_counted
#                     names the held file and the person's command, seat
#                     exits 1, an agent's accept is refused person-required
#                     and a person's without a terminal no-terminal, and a
#                     person under a pseudo-terminal (python3) types the code
#                     back, is recorded at owner, and the run finalizes
#   pr_precheck       its shipped block, in a fixture: an edit committed after
#                     counting holds tests_still_counted, and recount goes
#                     back to pass_counting; with nothing held it goes on
#   ci_pass_counting  the shipped ci_monitor (CI gates stubbed green) and
#                     ci_pass_counting blocks, in a fixture: a test edited by
#                     a CI fix is held after CI passes, a seat's accept lets
#                     the root go through cascade_entry to done; then, after
#                     done, a same-authority overrule is refused not-higher,
#                     an unknown coordinator unknown-session, and a
#                     coordinator's overrule from another directory holds the
#                     retained run as overruled in status and record; a
#                     reviewer's later accept leaves it held, a second
#                     coordinator's counts it, and once that coordinator's
#                     session is cleaned up its acceptance stops counting
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
    && pass "a decline goes back to implementation" || fail "the declined edges are [$(q '[.states.pass_counting.transitions[] | select(.when.counting_status == "declined")]')]"
[ "$(q '[.states.pass_counting.transitions[] | select(.when["gates.tests_counted.exit_code"] == 3) | "\(.when | keys | join("+"))>\(.target)"] | join(",")')" = "gates.tests_counted.exit_code>done_blocked" ] \
    && pass "the decline limit goes to done_blocked with no evidence" || fail "the exit-3 edges are [$(q '.states.pass_counting.transitions')]"
[ "$(q '[.states.ci_monitor.transitions[] | select(.when["gates.ci_passing.exit_code"] == 0 and .when["gates.merge_state_clean.exit_code"] == 0) | .target] | join(",")')" = ci_pass_counting ] \
    && pass "green CI on a clean pull request goes to ci_pass_counting" || fail "ci_monitor's green edges are [$(q '.states.ci_monitor.transitions')]"
[ "$(q '.states.ci_pass_counting.gates.tests_counted.command')" = "$(q '.states.pass_counting.gates.tests_counted.command')" ] \
    && [ "$(q '.states.ci_pass_counting.gates.fix_green.command')" = "$(q '.states.pass_counting.gates.fix_green.command')" ] \
    && pass "ci_pass_counting runs pass_counting's two gates" || fail "ci_pass_counting's gates are [$(q '.states.ci_pass_counting.gates')]"
[ "$(q '[.states.ci_pass_counting.transitions[] | select(.when.counting_status == "declined") | .target] | join(",")')" = ci_monitor ] \
    && pass "a decline at ci_pass_counting goes back to ci_monitor" || fail "the declined edges are [$(q '.states.ci_pass_counting.transitions')]"
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

# ==============================================================================
echo "--- an edited test: held, refused for the run and an unminted name, accepted by a minted seat"

S=tc_edit
if walk "$S" 2 light; then
    expect_state "a change" implementation
    [ "$(ledger "$S" | head -n 1 | jq -r '"\(.event)|\(.author)"')" = "header|agent:$S" ] \
        && pass "fix_determination wrote the ledger's header with the run as author" \
        || fail "the ledger is [$(ledger "$S")]"
    drop_mark
    git commit -q -am "feat: drop the exclamation mark"
    "$TC" note "$S" --file tests/greet_test.sh --reason "the issue asks for the expected value to change" >/dev/null 2>&1 \
        && pass "the run records why it edited the test" || fail "test-change.sh note failed"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"task"}'
    settle_verification "$S"
    expect_state "after local verification passed, the edited test holds the unit" pass_counting
    case "$(gate_stdout tests_counted)" in
        *"held: unaccepted tests/greet_test.sh"*) pass "tests_counted holds with unaccepted tests/greet_test.sh" ;;
        *) fail "tests_counted printed [$(gate_stdout tests_counted)]" ;;
    esac
    [ "$(visits "$S" finalization)" = 0 ] && pass "finalization is not reached with an unaccepted edit" || fail "finalization was entered"

    "$TC" accept "$S" --as "agent:$S" --authority reviewer --all --reason "mine" > "$WORKDIR/a.out" 2>&1
    RC=$?
    [ "$RC" = 1 ] && grep -q 'rule author' "$WORKDIR/a.out" && pass "the run's own accept exits 1 with rule author" \
        || fail "the author's accept exited $RC: $(cat "$WORKDIR/a.out")"
    "$TC" accept "$S" --as agent:other --authority reviewer --all --reason "x" > "$WORKDIR/a.out" 2>&1
    RC=$?
    [ "$RC" = 1 ] && grep -q 'rule unminted-seat' "$WORKDIR/a.out" && pass "an unminted reviewer's accept exits 1 with rule unminted-seat" \
        || fail "the unminted accept exited $RC: $(cat "$WORKDIR/a.out")"
    tick "$S"
    expect_state "after two refusals" pass_counting

    SEAT=$("$TC" seat "$S" 2>/dev/null | head -n 1)
    [ "$SEAT" = "agent:$S/accept-1" ] && pass "seat prints agent:$S/accept-1" || fail "seat printed [$SEAT]"
    # The seat runs from its own directory: the session is addressed by name and
    # the ledger names the work tree.
    (cd "$WORKDIR" && "$TC" accept "$S" --as "$SEAT" --authority reviewer --all --reason "the issue asks for this value") > "$WORKDIR/a.out" 2>&1 \
        && pass "the minted seat's accept, from another directory, exits 0" || fail "the seat's accept failed: $(cat "$WORKDIR/a.out")"
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1 && pass "after the seat's accept, status exits 0" || fail "status: $(cat "$WORKDIR/s.out")"

    printf '# the empty name is not checked here\n' >> tests/greet_test.sh
    git commit -q -am "test: note what the test leaves out"
    tick "$S"
    expect_state "a later commit to the accepted test" pass_counting
    case "$(gate_stdout tests_counted)" in
        *"held: changed since acceptance tests/greet_test.sh"*) pass "tests_counted holds with changed since acceptance" ;;
        *) fail "tests_counted printed [$(gate_stdout tests_counted)]" ;;
    esac
    SEAT=$("$TC" seat "$S" 2>/dev/null | head -n 1)
    "$TC" accept "$S" --as "$SEAT" --authority reviewer --all --reason "a comment only" >/dev/null 2>&1 \
        && pass "the second seat accepts the new digest" || fail "the second seat's accept failed"
    tick "$S"
    expect_state "with every edit accepted, no person asked" finalization
    [ "$(ledger "$S" | jq -r 'select(.event == "refuse") | .rule_id' | paste -sd, -)" = "author,unminted-seat" ] \
        && pass "the ledger records both refusals" || fail "refusals: [$(ledger "$S" | jq -c 'select(.event == "refuse")')]"
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
echo "--- declines: back to implementation, then done_blocked on the third"

S=tc_decline
if walk "$S" 2 light --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=the fixture has no CI"; then
    drop_mark
    git commit -q -am "feat: drop the exclamation mark"
    for n in 1 2 3; do
        tick "$S" '{"implementation_status":"complete"}'
        tick "$S" '{"issue_type":"task"}'
        [ "$STATE" = pass_counting ] || { fail "decline $n: at [$STATE], not pass_counting"; break; }
        SEAT=$("$TC" seat "$S" 2>/dev/null | head -n 1)
        "$TC" decline "$S" --as "$SEAT" --authority reviewer --all --reason "loosens the assertion" >/dev/null 2>&1 \
            || fail "decline $n failed"
        if [ "$n" -lt 3 ]; then
            tick "$S"
            case "$(gate_stdout tests_counted)" in
                *"held: declined tests/greet_test.sh by $SEAT"*) pass "decline $n: tests_counted names the seat" ;;
                *) fail "decline $n: tests_counted printed [$(gate_stdout tests_counted)]" ;;
            esac
            tick "$S" '{"counting_status":"declined"}'
            expect_state "decline $n with counting_status declined" implementation
        fi
    done
    tick "$S"
    expect_state "the third decline of the same test" done_blocked
    case "$(koto context get "$S" failure_reason 2>/dev/null)" in
        *"declined the same test edits three times"*) pass "the failure reason names the declines" ;;
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
echo "--- a person-required repository: no seat, an agent refused, a person at a terminal counted"

git checkout -q main
git checkout -q -b person-main
printf '# greet\n\n## Repo Visibility: Private\n\n## Test Change Acceptance: person\n' > CLAUDE.md
git commit -q -am "docs: require a person to accept a test change"
S=tc_person
if WALK_FROM=person-main walk "$S" 2 light; then
    [ "$(ledger "$S" | head -n 1 | jq -r '"\(.person_required)|\(.person_required_source)"')" = "true|CLAUDE.md at impl_base: person" ] \
        && pass "the header records person_required true from CLAUDE.md at impl_base" \
        || fail "the header is [$(ledger "$S" | head -n 1)]"
    drop_mark
    git commit -q -am "feat: drop the exclamation mark"
    tick "$S" '{"implementation_status":"complete"}'
    tick "$S" '{"issue_type":"task"}'
    settle_verification "$S"
    expect_state "a person-required repository holds the edited test" pass_counting
    case "$(gate_stdout tests_counted)" in
        *"held: unaccepted tests/greet_test.sh"*"accept $S --as person:<your-name> --authority owner --files tests/greet_test.sh"*)
            pass "tests_counted names the held file and the exact command a person runs" ;;
        *) fail "tests_counted printed [$(gate_stdout tests_counted)]" ;;
    esac
    "$TC" seat "$S" > "$WORKDIR/seat.out" 2>&1
    RC=$?
    [ "$RC" = 1 ] && grep -q 'requires a person' "$WORKDIR/seat.out" && pass "no seat is commissioned: seat exits 1" \
        || fail "seat exited $RC: $(cat "$WORKDIR/seat.out")"
    "$TC" accept "$S" --as "agent:$S/accept-1" --authority reviewer --all --reason "x" > "$WORKDIR/a.out" 2>&1
    RC=$?
    [ "$RC" = 1 ] && grep -q 'rule person-required' "$WORKDIR/a.out" && pass "an agent's accept exits 1 with rule person-required" \
        || fail "the agent's accept exited $RC: $(cat "$WORKDIR/a.out")"
    "$TC" accept "$S" --as person:pat --authority owner --all --reason "test was wrong" > "$WORKDIR/a.out" 2>&1
    RC=$?
    [ "$RC" = 1 ] && grep -q 'rule no-terminal' "$WORKDIR/a.out" && pass "a person's accept without a terminal exits 1 with rule no-terminal" \
        || fail "the person's accept without a terminal exited $RC: $(cat "$WORKDIR/a.out")"
    tick "$S"
    expect_state "after the refusals" pass_counting
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import pty' 2>/dev/null; then
        cat > "$WORKDIR/term_drive.py" <<'PY'
import os, pty, re, select, sys, time
argv = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)
out, sent, deadline = b"", False, time.time() + 60
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.5)
    if fd not in r:
        continue
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    out += data
    if not sent:
        m = re.search(rb"Type the code ([0-9a-f]{6})", out)
        if m:
            os.write(fd, m.group(1) + b"\n")
            sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace"))
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 99)
PY
        python3 -I "$WORKDIR/term_drive.py" "$TC" accept "$S" --as person:pat --authority owner --all --reason "test was wrong" > "$WORKDIR/p.out" 2>&1
        RC=$?
        [ "$RC" = 0 ] && grep -q 'Type the code' "$WORKDIR/p.out" && grep -qF -- '-[ "$out" = "Hello, World!" ]' "$WORKDIR/p.out" \
            && pass "a person at a pseudo-terminal sees the hunk and the code, types it back, and exits 0" \
            || fail "the person's accept at a terminal exited $RC: $(cat "$WORKDIR/p.out")"
        "$TC" record "$S" > "$WORKDIR/r.out" 2>&1
        grep -q "accept accept-[0-9]* by person:pat (person at owner)" "$WORKDIR/r.out" && grep -q '^state: counted' "$WORKDIR/r.out" \
            && pass "record shows the unit counted, accepted by person:pat at owner" || fail "record printed: $(cat "$WORKDIR/r.out")"
        tick "$S"
        expect_state "the person's acceptance lets the resumed run finalize" finalization
    else
        echo "SKIP: python3 with pty not found; the pseudo-terminal person case did not run"
    fi
    [ "$(ledger "$S" | jq -r 'select(.event == "refuse") | .rule_id' | paste -sd, -)" = "person-required,no-terminal" ] \
        && pass "both refusals are recorded" || fail "refusals: [$(ledger "$S" | jq -c 'select(.event == "refuse")')]"
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
        *"held: unaccepted tests/greet_test.sh"*) pass "tests_still_counted holds with unaccepted tests/greet_test.sh" ;;
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

echo "--- ci_pass_counting: a test edited while fixing CI is held after CI passes; then an overrule after done"

CI_BLOCKS="$(stub_block "$(extract_state ci_monitor)" ci_passing=0 merge_state_clean=0)
$(extract_state ci_pass_counting)"
fixture "$WORKDIR/ci.md" ci_monitor "$CI_BLOCKS"
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
        *"held: unaccepted tests/greet_test.sh"*) pass "ci_pass_counting's tests_counted holds with unaccepted tests/greet_test.sh" ;;
        *) fail "tests_counted printed [$(gate_stdout tests_counted)]" ;;
    esac
    SEAT=$("$TC" seat "$S" 2>/dev/null | head -n 1)
    "$TC" accept "$S" --as "$SEAT" --authority reviewer --all --reason "the check expects this greeting" >/dev/null 2>&1 \
        && pass "the minted seat accepts the CI fix's edit" || fail "the seat's accept failed"
    tick "$S"
    expect_state "accepted, a root goes on through cascade_entry" done
    [ "$(visits "$S" cascade_entry)" = 1 ] && pass "a root went through cascade_entry" || fail "cascade_entry visits: $(visits "$S" cascade_entry)"

    # After done: a coordinator's overrule lands in the retained session.
    ACC=$(ledger "$S" | jq -r 'select(.event == "accept") | .id')
    koto init tc_coord --template "$WORKDIR/ci.md" --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1
    SEAT2=$("$TC" seat "$S" 2>/dev/null | head -n 1)
    "$TC" overrule "$S" --as "$SEAT2" --authority reviewer --acceptance "$ACC" --reason "same level" > "$WORKDIR/o.out" 2>&1
    RC=$?
    [ "$RC" = 1 ] && grep -q 'rule not-higher' "$WORKDIR/o.out" && pass "a same-authority overrule exits 1 with rule not-higher" \
        || fail "the same-authority overrule exited $RC: $(cat "$WORKDIR/o.out")"
    "$TC" overrule "$S" --as agent:no-such-session --authority coordinator --acceptance "$ACC" --reason "x" > "$WORKDIR/o.out" 2>&1
    RC=$?
    [ "$RC" = 1 ] && grep -q 'rule unknown-session' "$WORKDIR/o.out" && pass "a coordinator naming no session exits 1 with rule unknown-session" \
        || fail "the unknown coordinator's overrule exited $RC: $(cat "$WORKDIR/o.out")"
    (cd "$WORKDIR" && "$TC" overrule "$S" --as agent:tc_coord --authority coordinator --acceptance "$ACC" --reason "loosens the assertion") > "$WORKDIR/o.out" 2>&1 \
        && pass "a coordinator overrules the finished run's acceptance from another directory" || fail "the overrule failed: $(cat "$WORKDIR/o.out")"
    [ "$(koto status "$S" 2>/dev/null | jq -r '.current_state')" = done ] && pass "the run is still at done, retained" || fail "the run is at [$(koto status "$S" | jq -r .current_state)]"
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1
    RC=$?
    [ "$RC" = 1 ] && grep -q 'held: overruled tests/greet_test.sh by agent:tc_coord' "$WORKDIR/s.out" \
        && pass "status exits 1 with the unit overruled" || fail "status exited $RC: $(cat "$WORKDIR/s.out")"
    "$TC" record "$S" > "$WORKDIR/r.out" 2>&1
    grep -q '^state: held: overruled tests/greet_test.sh by agent:tc_coord' "$WORKDIR/r.out" \
        && pass "record shows the finished run held as overruled" || fail "record printed: $(cat "$WORKDIR/r.out")"
    SEAT3=$("$TC" seat "$S" 2>/dev/null | head -n 1)
    "$TC" accept "$S" --as "$SEAT3" --authority reviewer --all --reason "fine" >/dev/null 2>&1
    "$TC" status "$S" >/dev/null 2>&1 && fail "a reviewer's acceptance after the overrule counted the unit" \
        || pass "a reviewer's acceptance after the overrule leaves the unit held"
    # A second coordinator accepts at the overruling's authority; once its
    # session is cleaned up, its acceptance no longer counts at replay and
    # the unit is held again (the first coordinator's overrule still stands).
    koto init tc_coord2 --template "$WORKDIR/ci.md" --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1
    "$TC" accept "$S" --as agent:tc_coord2 --authority coordinator --all --reason "agreed after all" >/dev/null 2>&1
    "$TC" status "$S" >/dev/null 2>&1 && pass "a coordinator's acceptance counts it again" || fail "the coordinator's acceptance did not count"
    koto session cleanup tc_coord2 >/dev/null 2>&1
    "$TC" status "$S" > "$WORKDIR/s.out" 2>&1
    RC=$?
    [ "$RC" = 1 ] && grep -q 'held: overruled tests/greet_test.sh' "$WORKDIR/s.out" \
        && pass "with that coordinator's session cleaned up, its acceptance no longer counts at replay (status exits 1)" \
        || fail "status after the cleanup exited $RC: $(cat "$WORKDIR/s.out")"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

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
# a stand-in serving the fixture's issues. The repository declares no
# person-required acceptance, so nothing here waits for a person.
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
#
# Usage: test-change-routes_test.sh
#
# Exit codes:
#   0 -- all cases pass, or koto is absent and the engine cases skipped
#   1 -- one or more cases failed

set -uo pipefail

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
    git checkout -q main
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

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

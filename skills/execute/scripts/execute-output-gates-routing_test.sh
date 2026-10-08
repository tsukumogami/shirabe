#!/usr/bin/env bash
# execute-output-gates-routing_test.sh -- do the output gates in execute.md
# route the way the output-gates design says, and is every copied verdict gone?
# Part of the execute skill
#
# The design (docs/designs/DESIGN-output-gates.md, gate inventory rows 9 to 19)
# moves the answers the agent used to copy into gates koto reads:
#
#   orchestrator_setup  setup_owned_pr          which PR the run owns (routing)
#   pr_finalization     final_owned_pr          the same lookup (routing)
#                       owned_pr_body_conformant, settled_commits,
#                       settled_wip_clean, settled_docs_visibility
#                                               the output the state presents
#                       vars.PAUSE_BEFORE_FINALIZE
#                                               the pause, routed by koto
#   plan_completion     cascade_completed, cascade_skipped, cascade_partial
#                                               cascade_result.json (routing)
#                       ready_owned_pr          the lookup before gh pr ready
#   ci_monitor          monitor_owned_pr        the lookup (routing), beside
#                                               owned_ci_passing and
#                                               owned_merge_state_clean
#   worktree_sync       current_with_main       now check-branch-output.sh --synced
#
# This file checks three things:
#
#   1. The removed evidence values are gone (grep counts of 0), and
#      worktree_sync's gate calls check-branch-output.sh --synced.
#   2. Each route, driven through a real `koto next` against the SHIPPED state
#      blocks: each block is extracted from the template at run time, so an
#      edit to the template's routing reaches these cases. The gate scripts
#      are replaced by fakes under a fake PLUGIN_ROOT that exit with a code
#      the case writes to a file (koto runs gates in a cleared environment, so
#      a file, not a variable, carries the answer); ci_monitor's two gh
#      one-liners are replaced by fixed exits. The gate commands themselves
#      are the shipped ones.
#   3. The routing gates print no `::koto-finding::` line when they fail
#      (Decision 9): the four owned-PR lookups run as shipped against the real
#      check-pr-output.sh, and the three cascade gates, which koto evaluates
#      itself, carry no finding but koto's own fallback.
#
# Part 1 and the command half of part 3 need no engine. Part 2 skips, loudly,
# when koto is absent (the bash 3.2 floor leg has no koto).
#
# Usage: execute-output-gates-routing_test.sh
# Exit codes: 0 all pass (or the engine part skipped), 1 any failed, 2 the
# harness could not run.

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/execute.md"
REAL_ROOT=$(cd "$SKILL_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$TEMPLATE" ] || { echo "template not found: $TEMPLATE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/execute-output-gates-routing.XXXXXX")
WORKDIR=$(cd -P "$WORKDIR" && pwd -P)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# extract_state <name>: the state's block from the template's frontmatter.
extract_state() {
    awk -v want="  $1:" '
        $0 == want { found = 1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found && /^---$/ { exit }
        found { print }
    ' "$TEMPLATE"
}

# section <block> <key>: the lines of one 4-space key (accepts, transitions,
# gates) inside a state block.
section() {
    printf '%s\n' "$1" | awk -v k="    $2:" '
        $0 == k { f = 1; next }
        f && /^    [a-z_]+:/ { exit }
        f { print }'
}

# --- 1. the removed evidence values ------------------------------------------------------

echo "--- removed evidence values"

for st in orchestrator_setup pr_finalization plan_completion ci_monitor worktree_sync; do
    [ -n "$(extract_state "$st")" ] || { echo "$st not found in $TEMPLATE" >&2; exit 2; }
done

n=$(grep -c -E 'pr_adopt|status_read' "$TEMPLATE")
[ "$n" -eq 0 ] && pass "no state accepts pr_adopt or status_read (count $n)" \
    || fail "the template still names pr_adopt or status_read ($n)"

n=$(grep -c 'pause_decision' "$TEMPLATE")
[ "$n" -eq 0 ] && pass "pr_finalization accepts no pause_decision (count $n)" \
    || fail "the template still names pause_decision ($n)"

PC_ACCEPTS=$(section "$(extract_state plan_completion)" accepts)
n=$(printf '%s\n' "$PC_ACCEPTS" | grep -c 'cascade_status')
m=$(grep -c -E '^ +cascade_status: ' "$TEMPLATE")
[ "$n" -eq 0 ] && [ "$m" -eq 0 ] && pass "plan_completion accepts no cascade_status, and no edge names one (counts $n, $m)" \
    || fail "cascade_status is still accepted ($n) or routed on ($m)"
printf '%s\n' "$PC_ACCEPTS" | grep -q '^      cascade_detail:$' \
    && pass "plan_completion still accepts cascade_detail" \
    || fail "plan_completion no longer accepts cascade_detail"

CI_ACCEPTS=$(section "$(extract_state ci_monitor)" accepts)
n=$(printf '%s\n' "$CI_ACCEPTS" | grep -E '^        values:' | grep -c -E 'dirty_merge_state|passing')
m=$(grep -c -E 'ci_outcome: (passing|dirty_merge_state)' "$TEMPLATE")
[ "$n" -eq 0 ] && [ "$m" -eq 0 ] && pass "ci_monitor accepts no dirty_merge_state and no passing (counts $n, $m)" \
    || fail "ci_monitor still accepts dirty_merge_state or passing ($n, $m)"

n=$(grep -c 'check-branch-output.sh" --synced' "$TEMPLATE")
[ "$n" -eq 1 ] && pass "worktree_sync's current_with_main calls check-branch-output.sh --synced (count $n)" \
    || fail "check-branch-output.sh\" --synced appears $n times, want 1"

# --- 3. routing gates print no finding (the command gates) --------------------------------

echo "--- routing gates print no finding"

# gate_command <state> <gate>: the shipped command, unquoted from its YAML
# single-quoted scalar.
gate_command() {
    extract_state "$1" | awk -v g="      $2:" '
        $0 == g { f = 1; next }
        f && /^        command:/ {
            sub(/^        command: /, ""); s = $0
            if (s ~ /^'\''/) { s = substr(s, 2, length(s) - 2); gsub(/'\'''\''/, "'\''", s) }
            print s; exit
        }
        f && /^      [a-z_]+:$/ { exit }'
}

# render <cmd>: the gate command with the real plugin root and a test slug.
render() {
    local c="$1"
    c=${c//\{\{PLUGIN_ROOT\}\}/$REAL_ROOT}
    c=${c//\{\{PLAN_SLUG\}\}/no-such-plan-$$}
    printf '%s' "$c"
}

mkdir -p "$WORKDIR/repo" "$WORKDIR/stub"
(cd "$WORKDIR/repo" && git init -q . && git config user.email t@example.com && git config user.name t \
    && git commit -q --allow-empty -m "chore: init") >/dev/null 2>&1

# A stand-in owned-pr.sh, through check-pr-output.sh's documented seam: it
# answers with the exit code in FAKE_OWNED_RC and prints nothing.
cat > "$WORKDIR/stub/owned-pr.sh" <<'EOF'
#!/usr/bin/env bash
exit "${FAKE_OWNED_RC:-0}"
EOF
chmod +x "$WORKDIR/stub/owned-pr.sh"

for pair in orchestrator_setup:setup_owned_pr pr_finalization:final_owned_pr \
            plan_completion:ready_owned_pr ci_monitor:monitor_owned_pr; do
    st=${pair%%:*}; g=${pair#*:}
    cmd=$(gate_command "$st" "$g")
    case "$cmd" in
        *'check-pr-output.sh" --owned-pr '*) ;;
        *) fail "$g does not run check-pr-output.sh --owned-pr: [$cmd]"; continue ;;
    esac
    # 3 for owned-pr.sh's "several", 2 for a failed read, and the real script
    # with no session to read (a usage error, answered 2).
    for mode in 3 2 real; do
        if [ "$mode" = real ]; then
            OUT=$(cd "$WORKDIR/repo" && sh -c "$(render "$cmd")" 2>/dev/null)
        else
            OUT=$(cd "$WORKDIR/repo" && env CHECK_PR_OUTPUT_OWNED_PR="$WORKDIR/stub/owned-pr.sh" \
                FAKE_OWNED_RC="$mode" sh -c "$(render "$cmd")" 2>/dev/null)
        fi
        RC=$?
        if [ "$RC" -ne 0 ] && ! printf '%s' "$OUT" | grep -q '::koto-finding::'; then
            pass "$g failing (exit $RC, owned-pr.sh $mode) prints no finding"
        else
            fail "$g with owned-pr.sh $mode: exit $RC, stdout [$OUT]"
        fi
    done
done

# --- 2. the routes, through koto ----------------------------------------------------------

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- the routing cases did not run"
    echo
    echo "execute-output-gates-routing_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
fi

echo "--- routes"

# Sessions live under a temporary HOME, out of the developer's ~/.koto.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"
REPO="$WORKDIR/repo"
(cd "$REPO" && git checkout -q -b impl/x) >/dev/null 2>&1

# The fake plugin root. Each fake gate script exits with the number in
# $RC_DIR/<script><first-argument> (default 0); run-id.sh prints an id.
FAKE_ROOT="$WORKDIR/plugin"
RC_DIR="$WORKDIR/rc"
mkdir -p "$FAKE_ROOT/skills/work-on/scripts" "$FAKE_ROOT/skills/execute/scripts" "$RC_DIR"
for s in check-pr-output.sh check-branch-output.sh; do
    cat > "$FAKE_ROOT/skills/work-on/scripts/$s" <<EOF
#!/usr/bin/env bash
f="$RC_DIR/$s\$1"
rc=0
[ -f "\$f" ] && rc=\$(cat "\$f")
exit "\$rc"
EOF
done
cat > "$FAKE_ROOT/skills/execute/scripts/run-id.sh" <<'EOF'
#!/usr/bin/env bash
echo 00112233445566778899aabbccddeeff
EOF
chmod +x "$FAKE_ROOT"/skills/work-on/scripts/* "$FAKE_ROOT"/skills/execute/scripts/*

set_rc() { printf '%s\n' "$2" > "$RC_DIR/$1"; }
reset_rc() { rm -f "$RC_DIR"/*; }

# stub_block <block> <gate=exit>...: the gh one-liners replaced by fixed
# exits, keyed on the gate name above each command.
stub_block() {
    local block="$1"; shift
    printf '%s\n' "$block" | awk -v stubs="$*" '
        BEGIN { n = split(stubs, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); ex[kv[1]] = kv[2] } }
        /^      [a-z_]+:$/ { gate = $1; sub(/:$/, "", gate) }
        /^        command:/ && (gate in ex) { print "        command: \"exit " ex[gate] "\""; next }
        { print }'
}

# build <dir> <state> <gate=exit>...: a template whose `start` routes into the
# shipped <state>, every target it names a stub terminal.
build() {
    local dir="$1" state="$2"; shift 2
    local block targets t
    block=$(stub_block "$(extract_state "$state")" "$@")
    targets=$(printf '%s\n' "$block" | awk '/^      - target:/ { print $3 }' | sort -u)
    {
        printf '%s\n' '---' 'name: execute-output-gates-routing-fixture' 'version: "1.0"' \
            'description: Fixture driving one shipped execute state.' 'initial_state: start' \
            'variables:' \
            '  PLAN_DOC:' '    description: plan' '    required: false' \
            '  PLAN_SLUG:' '    description: slug' '    required: false' \
            '  PLUGIN_ROOT:' '    description: plugin root' '    required: false' \
            '  PAUSE_BEFORE_FINALIZE:' '    description: pause' '    required: false' \
            '    default: "false"' '    values: ["true", "false"]' \
            'states:' '  start:' '    transitions:' "      - target: $state"
        printf '%s\n' "$block"
        for t in $targets; do
            [ "$t" = "$state" ] && continue
            printf '%s\n' "  $t:" '    terminal: true'
            if [ "$t" = done_blocked ]; then
                printf '%s\n' '    failure: true' '    accepts:' '      failure_reason:' '        type: string'
            fi
        done
        printf '%s\n' '---' '' '## start' '' 'Start.' '' "## $state" '' 'The state under test.'
        for t in $targets; do
            [ "$t" = "$state" ] && continue
            printf '%s\n' '' "## $t" '' 'Stub.'
        done
    } > "$dir/fixture.md"
}

# seed <session> <key=value>...: context keys written between the two ticks.
seed() {
    local s="$1" kv; shift
    for kv in "$@"; do
        printf '%s' "${kv#*=}" | (cd "$REPO" && koto context add "$s" "${kv%%=*}") >/dev/null 2>&1
    done
}

# drive <state> <evidence-or-empty> <gate=exit>... : builds, inits and ticks
# the fixture; sets S (the session), STATE (the state the response reports)
# and RESP. PAUSE sets PAUSE_BEFORE_FINALIZE (default false). PRESEED (keys
# written before the first tick) and SEED (keys written after it) take
# space-separated key=value pairs. With evidence, or with SEED, a second tick
# follows the first.
N=0
drive() {
    local state="$1" data="$2"; shift 2
    N=$((N + 1))
    local dir="$WORKDIR/f$N"
    S="eo-$N"
    mkdir -p "$dir"
    build "$dir" "$state" "$@"
    (cd "$REPO" && koto init "$S" --template "$dir/fixture.md" --var PLUGIN_ROOT="$FAKE_ROOT" \
        --var PLAN_DOC=docs/plans/PLAN-x.md --var PLAN_SLUG=x \
        --var PAUSE_BEFORE_FINALIZE="${PAUSE:-false}") >"$dir/init.out" 2>&1 \
        || { STATE="init-failed: $(head -c 300 "$dir/init.out")"; RESP=""; return; }
    # shellcheck disable=SC2086
    [ -z "${PRESEED:-}" ] || seed "$S" $PRESEED
    RESP=$(cd "$REPO" && koto next "$S" --no-cleanup 2>/dev/null)
    # shellcheck disable=SC2086
    [ -z "${SEED:-}" ] || seed "$S" $SEED
    if [ -n "$data" ]; then
        RESP=$(cd "$REPO" && koto next "$S" --with-data "$data" --no-cleanup 2>/dev/null)
    elif [ -n "${SEED:-}" ]; then
        RESP=$(cd "$REPO" && koto next "$S" --no-cleanup 2>/dev/null)
    fi
    STATE=$(printf '%s' "$RESP" | jq -r '.state // "none"' 2>/dev/null)
}

expect() {
    if [ "$STATE" = "$2" ]; then pass "$1 -> $STATE"; else fail "$1: want $2, got $STATE ($(printf '%s' "$RESP" | head -c 300))"; fi
}

# expect_step <label> <step>: the run ended at done_blocked with that step.
expect_step() {
    local got
    got=$(cd "$REPO" && koto context get "$S" step 2>/dev/null)
    if [ "$STATE" = done_blocked ] && [ "$got" = "$2" ]; then
        pass "$1 -> done_blocked, step $2"
    else
        fail "$1: want done_blocked with step $2, got $STATE with step [$got] ($(printf '%s' "$RESP" | head -c 300))"
    fi
}

# holds <label> <state> [<gate>]: the run stayed in <state>, and the response
# names <gate> as a blocking condition when one is given.
holds() {
    if [ "$STATE" = "$2" ] && { [ -z "${3:-}" ] || printf '%s' "$RESP" | jq -e --arg g "$3" '[.blocking_conditions[]? | select(.name == $g)] | length > 0' >/dev/null 2>&1; }; then
        pass "$1 holds at $2${3:+ naming $3}"
    else
        fail "$1: want a hold at $2${3:+ naming $3}, got $STATE ($(printf '%s' "$RESP" | head -c 300))"
    fi
}

# orchestrator_setup: setup_owned_pr routes once the steps ran.
COMPLETED='{"status":"completed","detail":"steps ran"}'
reset_rc
drive orchestrator_setup "$COMPLETED"
expect "setup_owned_pr exit 0, status: completed" settled_branch_record
set_rc check-pr-output.sh--owned-pr 3
drive orchestrator_setup "$COMPLETED"
expect_step "setup_owned_pr exit 3, status: completed" execute:pr-adopt
set_rc check-pr-output.sh--owned-pr 2
drive orchestrator_setup "$COMPLETED"
expect_step "setup_owned_pr exit 2, status: completed" execute:status-read
set_rc check-pr-output.sh--owned-pr 3
drive orchestrator_setup ""
holds "setup_owned_pr exit 3 before the steps ran (no evidence)" orchestrator_setup
drive orchestrator_setup '{"status":"override","detail":"a person said go on"}'
expect "status: override (lookup exit 3)" settled_branch_record
reset_rc
drive orchestrator_setup '{"status":"blocked","detail":"the create failed"}'
expect_step "status: blocked" execute:orchestrator_setup

# pr_finalization: the lookup, the four output gates, then the pause.
reset_rc
for pair in 3:execute:pr-adopt 2:execute:status-read; do
    set_rc check-pr-output.sh--owned-pr "${pair%%:*}"
    drive pr_finalization ""
    expect_step "final_owned_pr exit ${pair%%:*}" "${pair#*:}"
done
reset_rc
PAUSE=true drive pr_finalization ""
expect "every gate passing, PAUSE_BEFORE_FINALIZE true" paused_for_review
PAUSE=false drive pr_finalization ""
expect "every gate passing, PAUSE_BEFORE_FINALIZE false" plan_completion
for key in check-pr-output.sh--pr-body:owned_pr_body_conformant check-branch-output.sh--commits:settled_commits \
           check-branch-output.sh--wip:settled_wip_clean check-branch-output.sh--docs-visibility:settled_docs_visibility; do
    for rc in 1 2; do
        for p in true false; do
            reset_rc; set_rc "${key%%:*}" "$rc"
            PAUSE=$p drive pr_finalization ""
            holds "${key#*:} exit $rc (PAUSE_BEFORE_FINALIZE $p)" pr_finalization "${key#*:}"
        done
    done
done
for rc in 1 2; do
    reset_rc; set_rc check-pr-output.sh--pr-body "$rc"
    drive pr_finalization '{"finalization_status":"update_failed"}'
    expect_step "finalization_status: update_failed with the body check at $rc" execute:pr_finalization
done
reset_rc; set_rc check-branch-output.sh--wip 1
drive pr_finalization '{"finalization_status":"update_failed"}'
holds "finalization_status: update_failed with the body check passing" pr_finalization

# plan_completion: the recorded verdict routes; partial and no record hold.
HEAD40=0123456789abcdef0123456789abcdef01234567
reset_rc
for v in completed skipped; do
    SEED="cascade_result.json={\"cascade_status\":\"$v\",\"steps\":[]} expected_head=$HEAD40" drive plan_completion ""
    expect "cascade_result.json $v" ci_monitor
    SEED="cascade_result.json={\"cascade_status\":\"$v\",\"steps\":[]}" drive plan_completion ""
    expect "cascade_result.json $v, no expected_head record" ci_monitor
done
SEED="cascade_result.json={\"cascade_status\":\"completed\",\"steps\":[]} expected_head=$HEAD40" \
    drive plan_completion '{"cascade_detail":"DESIGN to Current, PLAN deleted"}'
expect "cascade_result.json completed, with cascade_detail" ci_monitor
SEED="cascade_result.json={\"cascade_status\":\"partial\",\"steps\":[]} expected_head=$HEAD40" drive plan_completion ""
holds "cascade_result.json partial" plan_completion
PARTIAL_RESP=$RESP
SEED="cascade_result.json={\"cascade_status\":\"partial\",\"steps\":[]}" \
    drive plan_completion '{"cascade_detail":"submitted anyway"}'
holds "cascade_result.json partial, with cascade_detail" plan_completion
drive plan_completion ""
holds "no cascade_result.json (a run that stopped before its verdict)" plan_completion
# A verdict left in context before the state is entered is cleared on entry
# (clear_on_entry), so it can't route the run before the cascade runs.
PRESEED="cascade_result.json={\"cascade_status\":\"completed\",\"steps\":[]} expected_head=$HEAD40" drive plan_completion ""
holds "a cascade_result.json written before the state was entered" plan_completion
for pair in 3:execute:pr-adopt 2:execute:status-read; do
    set_rc check-pr-output.sh--owned-pr "${pair%%:*}"
    SEED="cascade_result.json={\"cascade_status\":\"completed\",\"steps\":[]}" drive plan_completion ""
    expect_step "ready_owned_pr exit ${pair%%:*}" "${pair#*:}"
done
reset_rc

# The three cascade gates print no finding: when they fail, the only findings
# are koto's own fallbacks.
if printf '%s' "$PARTIAL_RESP" | jq -e '
        [.blocking_conditions[]? | select(.name | test("^cascade_"))] as $c
        | ($c | length) > 0
          and ([$c[] | .failure.findings[]? | select(.message_source != "koto")] | length) == 0' >/dev/null 2>&1; then
    pass "the failing cascade gates carry no finding but koto's own"
else
    fail "a cascade gate carried a finding of its own: $(printf '%s' "$PARTIAL_RESP" | jq -c '[.blocking_conditions[]? | select(.name | test("^cascade_"))]' 2>/dev/null | head -c 400)"
fi

# ci_monitor: green, DIRTY and the lookup route with no evidence.
reset_rc
drive ci_monitor "" owned_ci_passing=0 owned_merge_state_clean=0
expect "both CI gates green, monitor_owned_pr 0, no evidence" merge_readiness
drive ci_monitor "" owned_ci_passing=1 owned_merge_state_clean=0
holds "owned_ci_passing 1, no evidence" ci_monitor owned_ci_passing
drive ci_monitor "" owned_ci_passing=0 owned_merge_state_clean=1
expect "owned_merge_state_clean 1, no evidence" escalate_dirty_merge_state
drive ci_monitor "" owned_ci_passing=1 owned_merge_state_clean=1
expect "owned_merge_state_clean 1 with red CI, no evidence" escalate_dirty_merge_state
for pair in 3:execute:pr-adopt 2:execute:status-read; do
    set_rc check-pr-output.sh--owned-pr "${pair%%:*}"
    drive ci_monitor "" owned_ci_passing=1 owned_merge_state_clean=1
    expect_step "monitor_owned_pr exit ${pair%%:*}" "${pair#*:}"
done
reset_rc
for v in failing_fixed pending; do
    drive ci_monitor "{\"ci_outcome\":\"$v\",\"rationale\":\"x\"}" owned_ci_passing=1 owned_merge_state_clean=0
    expect "ci_outcome: $v on red CI" merge_readiness
done
drive ci_monitor '{"ci_outcome":"failing_unresolvable","rationale":"upstream outage"}' owned_ci_passing=1 owned_merge_state_clean=0
expect_step "ci_outcome: failing_unresolvable on red CI" execute:ci

echo
echo "execute-output-gates-routing_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

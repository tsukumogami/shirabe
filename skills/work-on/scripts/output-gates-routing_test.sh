#!/usr/bin/env bash
# output-gates-routing_test.sh -- do the output gates in work-on.md route the
# way the output-gates design says, and is every copied verdict gone?
# Part of the work-on skill
#
# The design (docs/designs/DESIGN-output-gates.md, gate inventory rows 1 to 8)
# moves the checks the agent used to report into gates koto runs:
#
#   staleness_check  staleness_fresh        routes on its exit, no evidence
#   verification     verification_verdict   a poll: gate over the runner
#   finalization, deferral_approval, pre_pr_evidence
#                    commit_convention      every commit, not only the tip
#   pr_precheck      branch_docs_visibility, tests_still_counted
#   pr_creation      pr_body_conformant
#   scrutiny, review, qa_validation, light_review
#                    <panel>_verdict        the panel's pass, from the ledger
#   ci_pass_counting is_root                decides root or child, no evidence
#
# This file checks four things:
#
#   1. The removed evidence values are gone (grep counts of 0).
#   2. Each route, driven through a real `koto next` against the SHIPPED state
#      blocks: each block is extracted from the template at run time, so an
#      edit to the template's routing reaches these cases. The gate scripts
#      are replaced by fakes under a fake PLUGIN_ROOT that exit with a code
#      the case writes to a file (koto runs gates in a cleared environment, so
#      a file, not a variable, carries the answer); the gh one-liners are
#      replaced by fixed exits. The gate commands themselves are the shipped
#      ones.
#   3. The routing gates print no `::koto-finding::` line when they fail
#      (Decision 9), shown by running their shipped commands against the real
#      scripts and reading stdout.
#   4. No directive line about verification commands, the PR body rule or the
#      commit convention was dropped: the lines the build started from are
#      kept below and each must still be in the template.
#
# Parts 1, 3 and 4 need no engine. Part 2 skips, loudly, when koto is absent
# (the bash 3.2 floor leg has no koto).
#
# Usage: output-gates-routing_test.sh
# Exit codes: 0 all pass (or the engine part skipped), 1 any failed, 2 the
# harness could not run.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
REAL_ROOT=$(cd "$SKILL_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

[ -f "$TEMPLATE" ] || { echo "template not found: $TEMPLATE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/output-gates-routing.XXXXXX") || exit 1
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 1
cleanup() { case "${WORKDIR:-}" in */output-gates-routing.*) rm -rf "$WORKDIR" ;; esac; return 0; }
ktg_on_exit cleanup

# extract_state <name>: the state's block from the template's frontmatter.
extract_state() {
    awk -v want="  $1:" '
        $0 == want { found = 1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found && /^---$/ { exit }
        found { print }
    ' "$TEMPLATE"
}

# The directive body: everything after the frontmatter's closing ---.
body() { awk 'f >= 2 { print } /^---$/ { f++ }' "$1"; }

# --- 1. the removed evidence values ------------------------------------------------------

echo "--- removed evidence values"

STALENESS=$(extract_state staleness_check)
[ -n "$STALENESS" ] || { echo "staleness_check not found in $TEMPLATE" >&2; exit 2; }
STALE_TRANSITIONS=$(printf '%s\n' "$STALENESS" | awk '/^    transitions:/ { t = 1 } t')
n=$(printf '%s\n' "$STALE_TRANSITIONS" | grep -c -E 'staleness_signal: fresh|stale_requires_introspection|unavailable')
[ "$n" -eq 0 ] && pass "no staleness_check transition names fresh, stale_requires_introspection or unavailable (count $n)" \
    || fail "staleness_check transitions still name a removed value ($n)"

n=$(grep -c -E 'commands_run|verification_outcome' "$TEMPLATE")
[ "$n" -eq 0 ] && pass "no state accepts commands_run or verification_outcome (count $n)" \
    || fail "the template still names commands_run or verification_outcome ($n)"

n=$(grep -c 'session_role' "$TEMPLATE")
[ "$n" -eq 0 ] && pass "ci_monitor accepts no session_role (count $n)" \
    || fail "the template still names session_role ($n)"

n=$(grep -c 'ci_outcome: passing' "$TEMPLATE")
[ "$n" -eq 0 ] && pass "ci_monitor accepts no ci_outcome: passing (count $n)" \
    || fail "the template still names ci_outcome: passing ($n)"

# Gate 6: the panels' pass is the <panel>_verdict gate's, not the agent's.
# Counted over the four panel states' frontmatter blocks, and over the whole
# template for the outcome values, since no directive may offer them either.
PANEL_BLOCKS=$(for s in scrutiny review qa_validation light_review; do extract_state "$s"; done)
[ -n "$PANEL_BLOCKS" ] || { echo "panel states not found in $TEMPLATE" >&2; exit 2; }
n=$(grep -c -E '(scrutiny|review|qa|light)_outcome: passed' "$TEMPLATE")
[ "$n" -eq 0 ] && pass "no panel state accepts scrutiny_outcome, review_outcome, qa_outcome or light_outcome: passed (count $n)" \
    || fail "the template still names a *_outcome: passed ($n)"
n=$(printf '%s\n' "$PANEL_BLOCKS" | grep -c -E 'values: \[passed|_results\.exists|^      (scrutiny|review|qa|light)_results:$')
[ "$n" -eq 0 ] && pass "no panel state accepts passed or has a <panel>_results gate (count $n)" \
    || fail "a panel state still accepts passed or has a <panel>_results gate ($n)"
n=$(printf '%s\n' "$PANEL_BLOCKS" | grep -c 'type: context-exists')
[ "$n" -eq 0 ] && pass "no panel state has a context-exists gate (count $n)" \
    || fail "a panel state still has a context-exists gate ($n)"

# Each panel state keeps an override_default, on its verdict gate, in the
# exit-code form: a person's override stays the only way past the panel.
for pair in scrutiny:scrutiny review:review qa_validation:qa light_review:light; do
    st=${pair%%:*}; p=${pair#*:}
    if extract_state "$st" | awk -v g="      ${p}_verdict:" '
            $0 == g { f = 1; next }
            f && /^      [a-z_]+:$/ { exit }
            f && /^        override_default:$/ { o = 1; next }
            o && /^          exit_code: 0$/ { found = 1; exit }
            END { exit found ? 0 : 1 }'; then
        pass "$st keeps an override_default (exit_code: 0) on ${p}_verdict"
    else
        fail "$st has no override_default with exit_code: 0 on ${p}_verdict"
    fi
    cmd=$(extract_state "$st" | awk -v g="      ${p}_verdict:" '$0 == g { f = 1; next } f && /^        command:/ { print; exit }')
    case "$cmd" in
        *"panel-scope.sh\" --verdict $p \"{{SESSION_NAME}}\""*) pass "${p}_verdict runs panel-scope.sh --verdict $p" ;;
        *) fail "${p}_verdict command is [$cmd]" ;;
    esac
done

# --- 4. the directive lines the build started from ----------------------------------------
#
# Every directive line at the build's base that matched DIRECTIVE_RE: the
# verification procedure, the PR body and PR format rule, and the commit
# convention. BASE_COMMIT is that base; when the clone has it, the snapshot
# is checked against it too, so the list can't drift from what was there.

echo "--- directive lines kept"

BASE_COMMIT=246d366312dca18034a7b67bfe37917a8e252ed6
DIRECTIVE_RE='verification map|verification command|matched command|commands ran|test command|conventional commits|commit convention|PR body|pr-body|PR format|phase-6-pr'
cat > "$WORKDIR/base-lines" <<'EOF'
for the full procedure: read the project's verification map, classify the issue's
changed files against it, run each matched command (or the default test command when
Announce which commands ran and their results.
  must be surfaced in the PR body (see `references/phases/phase-6-pr.md`).
Conventional Commits, and the two referents. A failing one stops the run before
Otherwise, read `references/phases/phase-6-pr.md` for PR format, pre-PR
Read `references/phases/phase-6-pr.md` for CI monitoring.
EOF

if git -C "$REAL_ROOT" cat-file -e "$BASE_COMMIT:skills/work-on/koto-templates/work-on.md" 2>/dev/null; then
    git -C "$REAL_ROOT" show "$BASE_COMMIT:skills/work-on/koto-templates/work-on.md" > "$WORKDIR/base-template"
    body "$WORKDIR/base-template" | grep -iE "$DIRECTIVE_RE" > "$WORKDIR/base-from-git"
    if diff "$WORKDIR/base-lines" "$WORKDIR/base-from-git" >"$WORKDIR/snap.diff"; then
        pass "the kept-line snapshot matches the base template's matching lines"
    else
        fail "the kept-line snapshot differs from the base template's: $(cat "$WORKDIR/snap.diff")"
    fi
else
    echo "NOTE: base commit $BASE_COMMIT not in this clone; checking against the snapshot only"
fi

# The diff: each base line against the current body's lines, kept in base order.
body "$TEMPLATE" > "$WORKDIR/cur-body"
: > "$WORKDIR/kept"
while IFS= read -r line; do
    grep -Fxq -- "$line" "$WORKDIR/cur-body" && printf '%s\n' "$line" >> "$WORKDIR/kept"
done < "$WORKDIR/base-lines"
if diff "$WORKDIR/base-lines" "$WORKDIR/kept" >"$WORKDIR/kept.diff"; then
    pass "every base directive line about verification commands, the PR body or the commit convention is still present"
else
    fail "directive lines dropped: $(cat "$WORKDIR/kept.diff")"
fi

# --- 3. routing gates print no finding ---------------------------------------------------

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

STUB="$WORKDIR/stub"
mkdir -p "$STUB" "$WORKDIR/repo"
(cd "$WORKDIR/repo" && git init -q . && git config user.email t@example.com && git config user.name t \
    && git commit -q --allow-empty -m "chore: init") >/dev/null 2>&1

# gh for check-staleness.sh: FAKE_GH_MODE=fail fails every call; otherwise an
# issue created 60 days ago with no milestone, which the age check calls stale.
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
[ "${FAKE_GH_MODE:-}" = fail ] && { echo "HTTP 401: Bad credentials" >&2; exit 1; }
case "$1 $2" in
    "issue view")
        jq -nc '{number: 7, title: "t", body: "", milestone: null,
                 createdAt: ((now - 60 * 86400) | floor | todate)}' ;;
    "issue list") echo '[]' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$STUB/gh"

# render <cmd>: the gate command with the real plugin root and a test session,
# for an issue in this repository (ISSUE_REPO empty, as an unset variable
# resolves).
render() {
    local c="$1"
    c=${c//\{\{PLUGIN_ROOT\}\}/$REAL_ROOT}
    c=${c//\{\{SESSION_NAME\}\}/no-such-session-$$}
    c=${c//\{\{ISSUE_NUMBER\}\}/7}
    c=${c//\{\{ISSUE_REPO\}\}/}
    printf '%s' "$c"
}

IS_ROOT_CMD=$(gate_command ci_pass_counting is_root)
STALE_CMD=$(gate_command staleness_check staleness_fresh)
[ -n "$IS_ROOT_CMD" ] && [ -n "$STALE_CMD" ] || { echo "could not extract the routing gates' commands" >&2; exit 2; }

OUT=$(cd "$WORKDIR/repo" && sh -c "$(render "$IS_ROOT_CMD")" 2>/dev/null)
RC=$?
if [ "$RC" -ne 0 ] && ! grep -q '::koto-finding::' <<<"$OUT"; then
    pass "is_root failing (exit $RC, an unknown session) prints no finding"
else
    fail "is_root: exit $RC, stdout [$OUT]"
fi

for mode in stale fail; do
    OUT=$(cd "$WORKDIR/repo" && env PATH="$STUB:$PATH" FAKE_GH_MODE="$mode" sh -c "$(render "$STALE_CMD")" 2>/dev/null)
    RC=$?
    if [ "$RC" -ne 0 ] && [ -n "$OUT" ] && ! grep -q '::koto-finding::' <<<"$OUT"; then
        pass "staleness_fresh failing (exit $RC, gh $mode) prints its report and no finding"
    else
        fail "staleness_fresh with gh $mode: exit $RC, stdout [$(head -c 200 <<<"$OUT")]"
    fi
done

# --- 2. the routes, through koto ----------------------------------------------------------

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto not on PATH -- the routing cases did not run"
    echo
    echo "output-gates-routing_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
fi

echo "--- routes"

# Sessions live under a temporary HOME, out of the developer's $HOME/.koto.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"
REPO="$WORKDIR/repo"
(cd "$REPO" && git checkout -q -b feature/x) >/dev/null 2>&1

# The fake plugin root. Each fake gate script exits with the number in
# $RC_DIR/<script><first-argument> (default 0); session-role.sh prints the
# word in $RC_DIR/role (default root). `sleep` makes a script outlive the
# gate's timeout, for koto's -1.
FAKE_ROOT="$WORKDIR/plugin"
RC_DIR="$WORKDIR/rc"
mkdir -p "$FAKE_ROOT/skills/work-on/scripts" "$RC_DIR"
for s in check-staleness.sh run-verification.sh check-verification.sh check-branch-output.sh \
         check-pr-output.sh check-pre-pr-referents.sh panel-scope.sh has-commits.sh review-level.sh \
         test-change.sh red-first.sh; do
    cat > "$FAKE_ROOT/skills/work-on/scripts/$s" <<EOF
#!/usr/bin/env bash
f="$RC_DIR/$s\$1"
rc=0
[ -f "\$f" ] && rc=\$(cat "\$f")
[ "\$rc" = sleep ] && { sleep 5; exit 0; }
exit "\$rc"
EOF
done
cat > "$FAKE_ROOT/skills/work-on/scripts/session-role.sh" <<EOF
#!/usr/bin/env bash
if [ -f "$RC_DIR/role" ]; then cat "$RC_DIR/role"; else echo root; fi
EOF
chmod +x "$FAKE_ROOT"/skills/work-on/scripts/*

# set_rc <script><arg> <value>; reset_rc clears every answer back to 0.
set_rc() { printf '%s\n' "$2" > "$RC_DIR/$1"; }
reset_rc() { rm -f "$RC_DIR"/*; }

# stub_block <block> <gate=exit>... : the gh one-liners replaced by fixed exits,
# keyed on the gate name above each command. Also shortens the verification
# poll so a pending case returns in a second, and gives the gate named in
# TIMEOUT_GATE a one-second per-run timeout.
stub_block() {
    local block="$1"; shift
    printf '%s\n' "$block" | awk -v stubs="$*" -v st="${TIMEOUT_GATE:-}" '
        BEGIN { n = split(stubs, a, " "); for (i = 1; i <= n; i++) { split(a[i], kv, "="); ex[kv[1]] = kv[2] } }
        /^      [a-z_]+:$/ { gate = $1; sub(/:$/, "", gate) }
        /^        command:/ {
            if (gate in ex) { print "        command: \"exit " ex[gate] "\""; next }
            if (st != "" && gate == st) { print; print "        timeout: 1"; next }
        }
        /^          interval_secs:/ { print "          interval_secs: 1"; next }
        /^          timeout_secs:/  { print "          timeout_secs: 60"; next }
        /^          hold_secs:/     { print "          hold_secs: 1"; next }
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
        printf '%s\n' '---' 'name: output-gates-routing-fixture' 'version: "1.0"' \
            'description: Fixture driving one shipped work-on state.' 'initial_state: start' \
            'variables:' \
            '  ISSUE_NUMBER:' '    description: issue' '    required: false' \
            '  ISSUE_REPO:' '    description: issue repository' '    required: false' \
            '  PLUGIN_ROOT:' '    description: plugin root' '    required: false' \
            '  SHARED_BRANCH:' '    description: shared branch' '    required: false' \
            '  REVIEW_LEVEL:' '    description: review level' '    required: false' \
            '  VERIFICATION:' '    description: verification' '    required: false' \
            '    default: local' '    values: [local, hosted-ci]' \
            '  VERIFICATION_DEFERRAL_REASON:' '    description: deferral reason' '    required: false' \
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

# drive <state> <shared-branch> <evidence-or-empty> <gate=exit>... : builds,
# inits and ticks the fixture; sets STATE (the state the response reports) and
# RESP. With evidence, it is submitted on a second tick.
N=0
drive() {
    local state="$1" shared="$2" data="$3"; shift 3
    N=$((N + 1))
    local dir="$WORKDIR/f$N" s="og-$N"
    mkdir -p "$dir"
    build "$dir" "$state" "$@"
    if [ -n "$shared" ]; then
        (cd "$REPO" && koto init "$s" --template "$dir/fixture.md" --var PLUGIN_ROOT="$FAKE_ROOT" \
            --var ISSUE_NUMBER=7 --var SHARED_BRANCH="$shared") >"$dir/init.out" 2>&1
    else
        (cd "$REPO" && koto init "$s" --template "$dir/fixture.md" --var PLUGIN_ROOT="$FAKE_ROOT" \
            --var ISSUE_NUMBER=7) >"$dir/init.out" 2>&1
    fi || { STATE="init-failed: $(head -c 300 "$dir/init.out")"; RESP=""; return; }
    if [ -n "${SEED_SUMMARY:-}" ]; then
        printf '# Summary\n\n## Changes Made\n- x\n' | (cd "$REPO" && koto context add "$s" summary.md) >/dev/null 2>&1
    fi
    RESP=$(cd "$REPO" && koto next "$s" --no-cleanup 2>/dev/null)
    # MID_RC=<script><arg>=<value> changes one fake answer between the two
    # ticks, so the evidence meets a gate result the first tick didn't see.
    if [ -n "${MID_RC:-}" ]; then
        set_rc "${MID_RC%%=*}" "${MID_RC#*=}"
    fi
    if [ -n "$data" ]; then
        RESP=$(cd "$REPO" && koto next "$s" --with-data "$data" --no-cleanup 2>/dev/null)
    fi
    STATE=$(printf '%s' "$RESP" | jq -r '.state // "none"' 2>/dev/null)
}

expect() {
    if [ "$STATE" = "$2" ]; then pass "$1 -> $STATE"; else fail "$1: want $2, got $STATE ($(head -c 300 <<<"$RESP"))"; fi
}

# holds <label> <state> <gate>: the run stayed in <state> and the response
# names <gate> as a blocking condition.
holds() {
    if [ "$STATE" = "$2" ] && printf '%s' "$RESP" | jq -e --arg g "$3" '[.blocking_conditions[]? | select(.name == $g)] | length > 0' >/dev/null 2>&1; then
        pass "$1 holds at $2 naming $3"
    else
        fail "$1: want a hold at $2 naming $3, got $STATE ($(head -c 300 <<<"$RESP"))"
    fi
}

# staleness_check: the exit routes with no evidence; exit 2 takes override or blocked.
for pair in 0:analysis 1:introspection 3:analysis; do
    reset_rc; set_rc check-staleness.sh--issue "${pair%%:*}"
    drive staleness_check "" ""
    expect "staleness_fresh exit ${pair%%:*}, no evidence" "${pair#*:}"
done
reset_rc; set_rc check-staleness.sh--issue sleep
TIMEOUT_GATE=staleness_fresh drive staleness_check "" ""
expect "staleness_fresh exit -1 (timed out), no evidence" analysis
reset_rc; set_rc check-staleness.sh--issue 2
drive staleness_check "" ""
expect "staleness_fresh exit 2, no evidence (holds)" staleness_check
drive staleness_check "" '{"staleness_signal":"override","detail":"the user said skip it"}'
expect "staleness_signal: override on exit 2" analysis
drive staleness_check "" '{"staleness_signal":"blocked","detail":"usage error"}'
expect "staleness_signal: blocked on exit 2" done_blocked

# verification: the verdict routes; 75 waits, 2 holds; blocked is the one evidence.
# A pass is counted at pass_counting before finalization (red-first.md).
for pair in 0:pass_counting 1:implementation 3:done_blocked 4:done_blocked; do
    reset_rc; set_rc check-verification.sh--verdict "${pair%%:*}"
    drive verification "" ""
    expect "verification_verdict exit ${pair%%:*}, no evidence" "${pair#*:}"
done
reset_rc; set_rc check-verification.sh--verdict 75
drive verification "" ""
if [ "$STATE" = verification ] && printf '%s' "$RESP" | jq -e '[.blocking_conditions[]? | select(.name == "verification_verdict" and .status == "pending")] | length > 0' >/dev/null 2>&1; then
    pass "verification_verdict exit 75 leaves the state waiting (pending)"
else
    fail "verification_verdict exit 75: want a pending wait at verification, got $STATE ($(head -c 300 <<<"$RESP"))"
fi
drive verification "" '{"verification_status":"blocked","detail":"the runner cannot start"}'
expect "verification_status: blocked while pending" done_blocked
reset_rc; set_rc check-verification.sh--verdict 2
drive verification "" ""
holds "verification_verdict exit 2" verification verification_verdict
drive verification "" '{"verification_status":"blocked","detail":"the result is unreadable"}'
expect "verification_status: blocked on exit 2" done_blocked
reset_rc; set_rc run-verification.sh--start 2
drive verification "" ""
holds "a launcher that cannot start" verification __action__
# A run koto kills at the gate's per-run timeout reads -1, not the pending
# code: the state holds, and blocked is its way out.
reset_rc; set_rc check-verification.sh--verdict sleep
TIMEOUT_GATE=verification_verdict drive verification "" ""
holds "verification_verdict exit -1 (timed out), no evidence" verification verification_verdict
TIMEOUT_GATE=verification_verdict drive verification "" '{"verification_status":"blocked","detail":"the check keeps timing out"}'
expect "verification_status: blocked on exit -1" done_blocked

# ci_monitor: green CI goes on to ci_pass_counting, which counts the pass and
# routes on is_root; the two failing values route on red CI.
reset_rc
drive ci_monitor "" "" ci_passing=0 merge_state_clean=0
expect "green CI on a clean pull request" ci_pass_counting
drive ci_pass_counting "" ""
expect "a counted pass, is_root exit 0" cascade_entry
set_rc role child
drive ci_pass_counting "" ""
expect "a counted pass, is_root exit 1" done
# is_root exit 2, a role nobody decided: neither the cascade nor done.
reset_rc
drive ci_pass_counting "" "" is_root=2
holds "a counted pass, is_root exit 2" ci_pass_counting is_root
reset_rc; set_rc test-change.shstatus 1
drive ci_pass_counting "" ""
holds "tests_counted exit 1 after CI" ci_pass_counting tests_counted
drive ci_pass_counting "" '{"counting_status":"declined"}'
expect "counting_status: declined after CI" ci_monitor
reset_rc
drive ci_monitor "" "" ci_passing=0 merge_state_clean=1
expect "green CI on a DIRTY pull request" done_blocked
# A DIRTY pull request's new head gets no checks, and zero checks fails
# ci_passing (#1018): it still stops on the merge state instead of holding.
drive ci_monitor "" "" ci_passing=1 merge_state_clean=1
expect "red CI on a DIRTY pull request" done_blocked
drive ci_monitor "" "" ci_passing=1 merge_state_clean=0
holds "red CI, no evidence" ci_monitor ci_passing
drive ci_monitor "" '{"ci_outcome":"failing_fixed","rationale":"pushed a fix"}' ci_passing=1 merge_state_clean=0
expect "ci_outcome: failing_fixed on red CI" ci_monitor
if printf '%s' "$RESP" | jq -e '.advanced == true' >/dev/null 2>&1; then
    pass "failing_fixed re-enters ci_monitor (advanced)"
else
    fail "failing_fixed did not re-enter ci_monitor: $(head -c 200 <<<"$RESP")"
fi
drive ci_monitor "" '{"ci_outcome":"failing_unresolvable","rationale":"upstream outage"}' ci_passing=1 merge_state_clean=0
expect "ci_outcome: failing_unresolvable on red CI" done_blocked

# commit_convention: holds at finalization and deferral_approval, ends the run at pre_pr_evidence.
SEED_SUMMARY=1
for rc in 1 2; do
    reset_rc; set_rc check-branch-output.sh--commits "$rc"
    drive finalization "" '{"finalization_status":"ready_for_pr"}'
    holds "commit_convention exit $rc at finalization" finalization commit_convention
    drive deferral_approval "" '{"approval_decision":"approved","deferral_detail":"x"}'
    holds "commit_convention exit $rc on deferral_approval's approved edge" deferral_approval commit_convention
    drive pre_pr_evidence "" '{"pre_pr_status":"recorded","cleanup_done":"none_found","design_diagram":"not_applicable"}'
    expect "commit_convention exit $rc at pre_pr_evidence" done_blocked
done
reset_rc
drive finalization "" '{"finalization_status":"ready_for_pr"}'
expect "commit_convention exit 0 at finalization" pre_pr_evidence
drive deferral_approval "" '{"approval_decision":"approved","deferral_detail":"x"}'
expect "commit_convention exit 0 on the approved edge" pre_pr_evidence
drive pre_pr_evidence "" '{"pre_pr_status":"recorded","cleanup_done":"none_found","design_diagram":"not_applicable"}'
expect "commit_convention exit 0 at pre_pr_evidence" pr_precheck
SEED_SUMMARY=

# pr_precheck: the branch checks hold unless SHARED_BRANCH is set.
for key in check-branch-output.sh--docs-visibility:branch_docs_visibility; do
    for rc in 1 2; do
        reset_rc; set_rc "${key%%:*}" "$rc"
        drive pr_precheck "" "" on_feature_branch_pr=0
        holds "${key#*:} exit $rc" pr_precheck "${key#*:}"
        drive pr_precheck "docs/shared" "" on_feature_branch_pr=0
        expect "${key#*:} script exit $rc on a shared branch" pr_creation
    done
done
reset_rc
drive pr_precheck "" "" on_feature_branch_pr=0
expect "the branch check passes" pr_creation
# tests_still_counted: status re-run before a pull request opens.
set_rc test-change.shstatus 1
drive pr_precheck "" "" on_feature_branch_pr=0
holds "tests_still_counted exit 1" pr_precheck tests_still_counted
drive pr_precheck "" '{"precheck_status":"recount"}' on_feature_branch_pr=0
expect "precheck_status: recount while tests_still_counted holds" pass_counting
drive pr_precheck "" '{"precheck_status":"override"}' on_feature_branch_pr=1
holds "override does not pass a tests_still_counted hold" pr_precheck tests_still_counted
set_rc test-change.shstatus 3
drive pr_precheck "" '{"precheck_status":"recount"}' on_feature_branch_pr=0
expect "precheck_status: recount on the decline limit (exit 3)" pass_counting
reset_rc

# pr_creation: the body check holds the created edge.
for rc in 1 2; do
    reset_rc; set_rc check-pr-output.sh--pr-body "$rc"
    drive pr_creation "" '{"pr_status":"created","pr_url":"https://github.com/o/r/pull/1"}' closing_keyword=0
    holds "pr_body_conformant exit $rc" pr_creation pr_body_conformant
done
# closing_keyword exit 2 (usage) and 3 (check-closing-keyword.sh's repository
# lookup failed or ran out of time) hold too: neither ci_monitor nor
# done_blocked.
for rc in 2 3; do
    reset_rc
    drive pr_creation "" '{"pr_status":"created","pr_url":"https://github.com/o/r/pull/1"}' closing_keyword=$rc
    holds "closing_keyword exit $rc" pr_creation closing_keyword
done
reset_rc
drive pr_creation "" '{"pr_status":"created","pr_url":"https://github.com/o/r/pull/1"}' closing_keyword=0
expect "pr_body_conformant exit 0" ci_monitor
set_rc check-pr-output.sh--pr-body 1
drive pr_creation "docs/shared" '{"pr_status":"shared"}' closing_keyword=0
expect "pr_status: shared does not wait on the body check" done
# Without SHARED_BRANCH, `shared` is not a way past the PR gates.
drive pr_creation "" '{"pr_status":"shared"}' closing_keyword=1
if [ "$STATE" = done ]; then
    fail "pr_status: shared on a root run (SHARED_BRANCH unset) reached done past the PR gates"
elif [ "$STATE" = pr_creation ]; then
    pass "pr_status: shared on a root run (SHARED_BRANCH unset) stays at pr_creation"
else
    fail "pr_status: shared with SHARED_BRANCH unset: want pr_creation, got $STATE ($(head -c 300 <<<"$RESP"))"
fi

# The named check exit (DESIGN-validate-and-return.md): pr_creation,
# finalization and pr_precheck accept check_unsatisfiable only while their
# registry gate exits 1, route it to check_exit (a stub terminal here), and set
# failure_reason on that edge. With the gate at 0 or 2 the submission holds.
# drive names each session og-$N, which is how the failure_reason reads below
# find the session the case just drove.
SEED_SUMMARY=1
for spec in \
    "finalization|check-branch-output.sh--commits|commit_convention|finalization_status" \
    "pr_precheck|check-branch-output.sh--docs-visibility|branch_docs_visibility|precheck_status" \
    "pr_creation|check-pr-output.sh--pr-body|pr_body_conformant|pr_status"; do
    IFS='|' read -r st key gate field <<EOF
$spec
EOF
    data="{\"$field\":\"check_unsatisfiable\",\"check_exit_reason\":\"the rule is wrong for this change\"}"
    reset_rc; set_rc "$key" 1
    drive "$st" "" "$data" on_feature_branch_pr=0 closing_keyword=0
    expect "check_unsatisfiable at $st with $gate at 1" check_exit
    reason=$(cd "$REPO" && koto context get "og-$N" failure_reason 2>/dev/null)
    [ "$reason" = "check_exit at $st: $gate could not be satisfied: the rule is wrong for this change" ] \
        && pass "check_unsatisfiable at $st sets failure_reason naming the state, the gate and the reason" \
        || fail "check_unsatisfiable at $st: failure_reason [$reason]"
    reset_rc; set_rc "$key" 1
    drive "$st" "" "{\"$field\":\"check_unsatisfiable\",\"check_exit_reason\":\"\"}" \
        on_feature_branch_pr=0 closing_keyword=0
    expect "check_unsatisfiable at $st with an empty reason" check_exit
    reason=$(cd "$REPO" && koto context get "og-$N" failure_reason 2>/dev/null)
    case "$reason" in
        "check_exit at $st: $gate could not be satisfied: "*) pass "an empty reason at $st still names the state and the gate" ;;
        *) fail "empty reason at $st: failure_reason [$reason]" ;;
    esac
    # With the gate at 2 the submission holds the state. With it at 0,
    # finalization and pr_creation hold too (check_unsatisfiable matches no
    # passing edge); pr_precheck advances on its own before any evidence,
    # because its passing edge takes none, so there it goes to pr_creation.
    for rc in 0 2; do
        reset_rc; set_rc "$key" "$rc"
        if [ "$st" = pr_precheck ] && [ "$rc" = 0 ]; then
            drive "$st" "" "" on_feature_branch_pr=0 closing_keyword=0
            expect "pr_precheck with $gate at 0 passes before any exit can be taken" pr_creation
        else
            drive "$st" "" "$data" on_feature_branch_pr=0 closing_keyword=0
            expect "check_unsatisfiable at $st with $gate at $rc holds" "$st"
        fi
    done
done
SEED_SUMMARY=
reset_rc

# The exit's shape in the compiled template: every check_unsatisfiable edge
# goes to check_exit and nowhere else, check_exit's one edge goes to
# done_blocked, and the exit table every laddered gate carries names exactly
# the states that have a check_unsatisfiable edge, each with its status field.
COMPILED=$(koto template compile "$TEMPLATE" 2>/dev/null)
if [ -n "$COMPILED" ] && [ -f "$COMPILED" ]; then
    bad=$(jq -r '.states | to_entries[] | .key as $s | .value.transitions[]?
        | select((.when // {}) | to_entries | map(select(.value == "check_unsatisfiable")) | length > 0)
        | select(.target != "check_exit") | "\($s)->\(.target)"' "$COMPILED")
    [ -z "$bad" ] && pass "every check_unsatisfiable edge targets check_exit" || fail "check_unsatisfiable edges elsewhere: $bad"
    exits=$(jq -r '.states.check_exit.transitions | map(.target) | join(" ")' "$COMPILED")
    [ "$exits" = done_blocked ] && pass "check_exit's only edge is to done_blocked" || fail "check_exit targets [$exits]"
    have=$(jq -r '.states | to_entries[] | .key as $s | .value.transitions[]?
        | (.when // {}) | to_entries[] | select(.value == "check_unsatisfiable") | "\($s):\(.key)"' "$COMPILED" | sort -u | tr '\n' ' ')
    table=$(grep -o 'SHIRABE_GATE_EXITS="[^"]*"' "$TEMPLATE" | sort -u)
    [ "$(printf '%s\n' "$table" | wc -l | tr -d ' ')" = 1 ] \
        && pass "every laddered gate carries the same exit table" || fail "exit tables differ: $table"
    table=${table#SHIRABE_GATE_EXITS=\"}; table=${table%\"}
    want=$(printf '%s\n' $table | sort -u | tr '\n' ' ')
    [ "$have" = "$want" ] && pass "the exit table names exactly the states with a check_unsatisfiable edge ($want)" \
        || fail "exit table [$want] vs check_unsatisfiable edges [$have]"
else
    fail "could not compile $TEMPLATE for the exit's shape"
fi

# The ladder's context is on every gate that prints registry findings, and the
# three commit_convention copies stay identical (finalization-shape_test.sh
# compares them compiled).
for g in pr_body_conformant commit_convention branch_docs_visibility verification_verdict \
         scrutiny_verdict review_verdict qa_verdict light_verdict; do
    n=$(awk -v g="      $g:" '$0 == g { f = 1; next } f && /^        command:/ { print; f = 0 }' "$TEMPLATE" \
        | grep -c "SHIRABE_GATE_LOG=\"{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl\" SHIRABE_GATE_NAME=$g SHIRABE_GATE_EXITS=")
    want=1; [ "$g" = commit_convention ] && want=3
    [ "$n" = "$want" ] && pass "$g carries the ladder's context ($n)" || fail "$g: ladder context on $n command(s), want $want"
done
[ "$(awk '/^      commit_convention:$/ { f = 1; next } f && /^        command:/ { print; f = 0 }' "$TEMPLATE" | sort -u | wc -l | tr -d ' ')" = 1 ] \
    && pass "the three commit_convention commands are byte-identical" || fail "commit_convention commands differ"

# One real run of the ladder through koto: the shipped pr_creation state, a gate
# script that prints a PB4 finding through the real findings library and the
# real registry, and the session's own log. koto's recorded count and the rung
# the gate printed agree on every evaluation, and the exit is a state_entered
# record in koto's run journal.
LAD_ROOT="$WORKDIR/ladder-plugin"
mkdir -p "$LAD_ROOT/skills/work-on/scripts"
cat > "$LAD_ROOT/skills/work-on/scripts/check-pr-output.sh" <<EOF
#!/usr/bin/env bash
undecided() { echo "undecided: \$*" >&2; exit 2; }
# Indented so check-rule-registry.sh, which reads RULE_IDS lines that start a
# line, doesn't take this stub for a real gate script.
  RULE_IDS="pr-body/no-heading-in-part1"
. "$SKILL_DIR/../../scripts/lib/rule-findings.sh" || undecided "no library"
rf_require pr-body/no-heading-in-part1
rf_finding pr-body/no-heading-in-part1 "Part 1 has a heading"
rf_deliver
exit 1
EOF
chmod +x "$LAD_ROOT/skills/work-on/scripts/check-pr-output.sh"
N=$((N + 1)); LDIR="$WORKDIR/f$N"; LS="og-$N"; mkdir -p "$LDIR"
build "$LDIR" pr_creation closing_keyword=0
(cd "$REPO" && koto init "$LS" --template "$LDIR/fixture.md" --var PLUGIN_ROOT="$LAD_ROOT" --var ISSUE_NUMBER=7) >"$LDIR/init.out" 2>&1 \
    || fail "ladder run: koto init failed: $(head -c 300 "$LDIR/init.out")"
LLOG="$(cd "$REPO" && koto session dir "$LS")/koto-$LS.state.jsonl"
# tick <evidence-or-empty>: one koto next; LERR is the PR-body gate's stderr,
# LCOUNT the session count koto recorded for PB4 on that evaluation.
tick() {
    if [ -n "$1" ]; then
        RESP=$(cd "$REPO" && koto next "$LS" --with-data "$1" --no-cleanup 2>/dev/null)
    else
        RESP=$(cd "$REPO" && koto next "$LS" --no-cleanup 2>/dev/null)
    fi
    LERR=$(printf '%s' "$RESP" | jq -r '[.blocking_conditions[]? | select(.name == "pr_body_conformant") | .failure.captured.stderr][0] // ""')
    LCOUNT=$(jq -R -n -r '[inputs | fromjson? | select(.type == "gate_evaluated" and .payload.gate == "pr_body_conformant")
        | .payload.rule_counts["pr-body/no-heading-in-part1"].session] | last // 0' < "$LLOG")
}
CREATED='{"pr_status":"created","pr_url":"https://github.com/o/r/pull/1"}'
tick ""
[ "$LCOUNT" = 1 ] && ! grep -q '^::shirabe-rule::' <<<"$LERR" \
    && pass "ladder run: koto's count 1, summary only" || fail "ladder run tick 1: count $LCOUNT, stderr [$LERR]"
tick "$CREATED"
[ "$LCOUNT" = 2 ] && [ "$(grep -c '^::shirabe-rule::{"rule_id":"pr-body/no-heading-in-part1"' <<<"$LERR")" = 1 ] \
    && ! grep -q '^::shirabe-check-exit::' <<<"$LERR" \
    && pass "ladder run: koto's count 2, PB4's text released" || fail "ladder run tick 2: count $LCOUNT, stderr [$LERR]"
tick "$CREATED"
[ "$LCOUNT" = 3 ] && grep -q '^::shirabe-check-exit::{"rule_id":"pr-body/no-heading-in-part1","count":3,"state":"pr_creation","submit":{"pr_status":"check_unsatisfiable"' <<<"$LERR" \
    && pass "ladder run: koto's count 3, the exit offered" || fail "ladder run tick 3: count $LCOUNT, stderr [$LERR]"
tick '{"pr_status":"check_unsatisfiable","check_exit_reason":"PB4 cannot be met here"}'
STATE=$(printf '%s' "$RESP" | jq -r '.state // "none"')
expect "ladder run: taking the exit" check_exit
# koto's run journal: <base>/_run_journal.jsonl for a redirected store, and
# _run_journal.jsonl in the .koto directory under HOME for the default one
# (koto's docs/reference/run-journal.md).
# HOME is this suite's temporary home (above), so either way it is this run's.
LJOURNAL="${KOTO_SESSIONS_BASE:-$HOME/.koto}/_run_journal.jsonl"
if [ -f "$LJOURNAL" ] && jq -R -n -e --arg s "$LS" '[inputs | fromjson? | select(.kind == "state_entered" and .session == $s and .["koto.state"] == "check_exit")] | length == 1' < "$LJOURNAL" >/dev/null; then
    pass "ladder run: the run journal records the exit as state_entered check_exit"
else
    fail "ladder run: no state_entered check_exit in $LJOURNAL"
fi
# The panels (gate 6): <panel>_verdict decides the pass. Each case starts with
# <panel>_carried at 1, the path where seats ran, unless it says otherwise;
# the fake recorded, has_commits and level_unchanged gates pass.
#
# panel_routes <state> <panel> <outcome-field> <pass-target>
panel_routes() {
    local st="$1" p="$2" f="$3" target="$4" v
    local retry="{\"$f\":\"blocking_retry\"}"
    local escalate="{\"$f\":\"blocking_escalate\",\"failure_reason\":\"cannot fix\"}"

    reset_rc; set_rc panel-scope.sh--carried 1
    drive "$st" "" ""
    expect "$st: ${p}_verdict exit 0, no evidence" "$target"

    set_rc panel-scope.sh--verdict 1
    drive "$st" "" ""
    holds "$st: ${p}_verdict exit 1, no evidence" "$st" "${p}_verdict"
    drive "$st" "" "$retry"
    expect "$st: ${p}_verdict exit 1, blocking_retry" implementation
    drive "$st" "" "$escalate"
    expect "$st: ${p}_verdict exit 1, blocking_escalate" done_blocked

    set_rc panel-scope.sh--verdict 2
    drive "$st" "" ""
    holds "$st: ${p}_verdict exit 2, no evidence" "$st" "${p}_verdict"
    drive "$st" "" "$retry"
    holds "$st: ${p}_verdict exit 2, blocking_retry" "$st" "${p}_verdict"
    drive "$st" "" "$escalate"
    expect "$st: ${p}_verdict exit 2, blocking_escalate (a stop, never a pass)" done_blocked

    # At 0 the panel passed, and neither value may send it anywhere else. The
    # first tick holds at exit 2; the evidence then meets exit 0.
    for v in "$retry" "$escalate"; do
        set_rc panel-scope.sh--verdict 2
        MID_RC=panel-scope.sh--verdict=0 drive "$st" "" "$v"
        case "$STATE" in
            implementation|done_blocked)
                fail "$st: ${p}_verdict exit 0 took $v to $STATE" ;;
            *)
                if [ "$STATE" = "$target" ] || [ "$STATE" = "$st" ]; then
                    pass "$st: ${p}_verdict exit 0 refuses $v (went to $STATE)"
                else
                    fail "$st: ${p}_verdict exit 0 with $v: got $STATE ($(head -c 300 <<<"$RESP"))"
                fi ;;
        esac
    done
    # And with the passing route itself held (the round's record gate fails),
    # the value still finds no edge: the run stays in the panel state.
    for v in "$retry" "$escalate"; do
        reset_rc; set_rc panel-scope.sh--carried 1; set_rc panel-scope.sh--recorded 1
        drive "$st" "" "$v"
        if [ "$STATE" = "$st" ]; then
            pass "$st: ${p}_verdict exit 0 refuses $v with the pass held (stays at $st)"
        else
            fail "$st: ${p}_verdict exit 0 took $v to $STATE"
        fi
    done

    # The carried route is unchanged: every seat kept, nothing recorded this
    # round, and the panel advances whatever --verdict says.
    reset_rc; set_rc panel-scope.sh--verdict 2
    drive "$st" "" ""
    expect "$st: ${p}_carried exit 0 (verdict exit 2)" "$target"
}

panel_routes scrutiny      scrutiny scrutiny_outcome review
panel_routes review        review   review_outcome   qa_validation
panel_routes qa_validation qa       qa_outcome       verification
panel_routes light_review  light    light_outcome    verification

# The verdict route keeps the state's other gates: has_commits at scrutiny and
# light_review, recorded everywhere.
reset_rc; set_rc panel-scope.sh--carried 1; set_rc panel-scope.sh--recorded 1
drive scrutiny "" ""
holds "scrutiny: verdict 0 with scrutiny_recorded failing" scrutiny scrutiny_recorded
reset_rc; set_rc panel-scope.sh--carried 1
drive_has_commits() {
    # has-commits.sh's first argument is the session, which drive names og-<N>.
    local next=$((N + 1))
    set_rc "has-commits.shog-$next" 1
    drive "$1" "" ""
}
drive_has_commits scrutiny
holds "scrutiny: verdict 0 with has_commits failing" scrutiny has_commits
reset_rc; set_rc panel-scope.sh--carried 1
drive_has_commits light_review
holds "light_review: verdict 0 with has_commits failing" light_review has_commits

echo
echo "output-gates-routing_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

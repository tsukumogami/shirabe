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
#   finalization, deferral_approval
#                    commit_convention      every commit, not only the tip
#   pr_precheck      branch_docs_visibility, tests_still_counted
#   pr_creation      pr_body_conformant
#   scrutiny, review, qa_validation, light_review
#                    <panel>_verdict        the panel's pass, from the ledger
#   ci_pass_counting is_root                decides root or child, no evidence
#   verification     verification_route, route_reason_given
#                    the timed-out hold (exit 5) and the hosted-of-record
#                    route through verification_hosted, pr_creation's
#                    hosted_record_line, ci_monitor's hosted_settled and
#                    hosted_record
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
# A base line whose state was removed is retired rather than dropped: its
# guidance moved to another state's directive, and the line that carries it
# there must be present instead. Each entry is the base line, a tab, and a
# fixed string the current body must contain.
#   pre_pr_evidence's directive said the commit check ran there; the state is
#   gone and finalization's directive says what a commit_convention hold means.
RETIRED="Conventional Commits, and the two referents. A failing one stops the run before	has a subject that is not a Conventional Commits subject, or"
: > "$WORKDIR/kept"
while IFS= read -r line; do
    if grep -Fxq -- "$line" "$WORKDIR/cur-body"; then
        printf '%s\n' "$line" >> "$WORKDIR/kept"
        continue
    fi
    successor=$(printf '%s\n' "$RETIRED" | awk -F '\t' -v l="$line" '$1 == l { print $2; exit }')
    if [ -n "$successor" ] && grep -Fq -- "$successor" "$WORKDIR/cur-body"; then
        printf '%s\n' "$line" >> "$WORKDIR/kept"
        pass "retired base line [$line] is carried by [$successor]"
    fi
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
    c=${c//\{\{SHARED_BRANCH\}\}/}
    printf '%s' "$c"
}

IS_ROOT_CMD=$(gate_command ci_pass_counting is_root)
STALE_CMD=$(gate_command staleness_check staleness_fresh)
ROUTE_CMD=$(gate_command verification verification_route)
[ -n "$IS_ROOT_CMD" ] && [ -n "$STALE_CMD" ] && [ -n "$ROUTE_CMD" ] || { echo "could not extract the routing gates' commands" >&2; exit 2; }

OUT=$(cd "$WORKDIR/repo" && sh -c "$(render "$ROUTE_CMD")" 2>/dev/null)
RC=$?
if [ "$RC" -ne 0 ] && ! grep -q '::koto-finding::' <<<"$OUT"; then
    pass "verification_route closed (exit $RC, no stored result) prints no finding"
else
    fail "verification_route: exit $RC, stdout [$OUT]"
fi

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
FAKE_PENDING_REASON="hosted_record: check-skill:coordinate skill-gate (ubuntu-latest) still pending 120 minutes after the route was taken at 0123456789abcdef0123456789abcdef01234567"
mkdir -p "$FAKE_ROOT/skills/work-on/scripts" "$RC_DIR"
for s in check-staleness.sh run-verification.sh check-verification.sh check-branch-output.sh \
         check-pr-output.sh check-pre-pr-referents.sh panel-scope.sh has-commits.sh review-level.sh \
         test-change.sh red-first.sh verification-route.sh; do
    cat > "$FAKE_ROOT/skills/work-on/scripts/$s" <<EOF
#!/usr/bin/env bash
f="$RC_DIR/$s\$1"
rc=0
[ -f "\$f" ] && rc=\$(cat "\$f")
[ "\$rc" = sleep ] && { sleep 5; exit 0; }
exit "\$rc"
EOF
done
# verification-route.sh answers like the others, and its --read fake also
# writes failure_reason through koto when its answer is 3, as the real script
# does before it exits 3 (--session is its second argument, the session its
# third).
cat > "$FAKE_ROOT/skills/work-on/scripts/verification-route.sh" <<EOF
#!/usr/bin/env bash
f="$RC_DIR/verification-route.sh\$1"
rc=0
[ -f "\$f" ] && rc=\$(cat "\$f")
[ "\$rc" = sleep ] && { sleep 5; exit 0; }
if [ "\$1" = --read ] && [ "\$rc" = 3 ]; then
    printf '%s' "$FAKE_PENDING_REASON" | koto context add "\$3" failure_reason || exit 2
fi
exit "\$rc"
EOF
# panel-scope.sh answers like the others, except that with no answer set its
# --escalated exits 1: the light seat didn't escalate.
cat > "$FAKE_ROOT/skills/work-on/scripts/panel-scope.sh" <<EOF
#!/usr/bin/env bash
f="$RC_DIR/panel-scope.sh\$1"
case "\$1" in --escalated) rc=1 ;; *) rc=0 ;; esac
[ -f "\$f" ] && rc=\$(cat "\$f")
[ "\$rc" = sleep ] && { sleep 5; exit 0; }
exit "\$rc"
EOF
# review-level.sh answers like the others, except that with no answer set its
# `level` exits 11 and its `audit` 1: a light run's ledger level and a session
# that isn't audited, so light_review's passed routes are the ones under test.
cat > "$FAKE_ROOT/skills/work-on/scripts/review-level.sh" <<EOF
#!/usr/bin/env bash
f="$RC_DIR/review-level.sh\$1"
case "\$1" in level) rc=11 ;; audit) rc=1 ;; *) rc=0 ;; esac
[ -f "\$f" ] && rc=\$(cat "\$f")
[ "\$rc" = sleep ] && { sleep 5; exit 0; }
exit "\$rc"
EOF
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
            # The rule-distance probe gates pass, as they do for a run in no
            # arm; probe_test.sh and probe-routes_test.sh exercise them.
            if (gate == "probe_ack" || gate == "probe_value_absent") { print "        command: \"exit 0\""; next }
            if (st != "" && gate == st) { print; print "        timeout: 1"; next }
        }
        # The gate given the one-second timeout drops its own.
        /^        timeout:/ { if (st != "" && gate == st) next }
        /^          interval_secs:/ { print "          interval_secs: 1"; next }
        /^          timeout_secs:/  { print "          timeout_secs: 60"; next }
        /^          hold_secs:/     { print "          hold_secs: 1"; next }
        { print }'
}

# build <dir> <state> <gate=exit>...: a template whose `start` routes into the
# shipped <state>, every target it names a stub terminal.
build() {
    local dir="$1" state="$2"; shift 2
    build_chain "$dir" "$state" "$@"
}

# build_chain <dir> "<first> [<state>...]" <gate=exit>...: the same with
# several shipped states, so one session can walk from <first> through the
# others (verification -> verification_hosted, hosted_record -> ci_monitor,
# and so on); every target that none of them is becomes a stub terminal. The
# stubs apply to every block, by gate name.
build_chain() {
    local dir="$1" states="$2"; shift 2
    local state block targets t st
    state=${states%% *}
    block=$(for st in $states; do stub_block "$(extract_state "$st")" "$@"; done)
    targets=$(printf '%s\n' "$block" | awk '/^      - target:/ { print $3 }' | sort -u)
    for st in $states; do
        targets=$(printf '%s\n' "$targets" | grep -vx "$st")
    done
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
            '  PROBE_NEAR_RULE:' '    description: the probe_near capture pr_creation reads' '    required: false' \
            'states:' '  start:' '    transitions:' "      - target: $state"
        printf '%s\n' "$block"
        for t in $targets; do
            printf '%s\n' "  $t:" '    terminal: true'
            if [ "$t" = done_blocked ]; then
                printf '%s\n' '    failure: true' '    accepts:' '      failure_reason:' '        type: string'
            fi
        done
        printf '%s\n' '---' '' '## start' '' 'Start.'
        for st in $states; do
            printf '%s\n' '' "## $st" '' 'The state under test.'
        done
        for t in $targets; do
            printf '%s\n' '' "## $t" '' 'Stub.'
        done
    } > "$dir/fixture.md"
}

# drive <state> <shared-branch> <evidence-or-empty> <gate=exit>... : builds,
# inits and ticks the fixture; sets STATE (the state the response reports) and
# RESP. With evidence, it is submitted on a second tick.
#
# CHAIN="<state>..." adds shipped states after <state> (build_chain);
# DRIVE_VARS="NAME=value ..." adds --var pairs to the init (for example
# VERIFICATION=hosted-ci); SEED_RECORD=<json> stores the hosted_of_record key
# before the first tick.
N=0
drive() {
    local state="$1" shared="$2" data="$3"; shift 3
    N=$((N + 1))
    local dir="$WORKDIR/f$N" s="og-$N" v
    local vars="--var PLUGIN_ROOT=$FAKE_ROOT --var ISSUE_NUMBER=7"
    mkdir -p "$dir"
    if [ -n "${CHAIN:-}" ]; then
        build_chain "$dir" "$state $CHAIN" "$@"
    else
        build "$dir" "$state" "$@"
    fi
    for v in ${DRIVE_VARS:-}; do vars="$vars --var $v"; done
    if [ -n "$shared" ]; then
        # shellcheck disable=SC2086 # $vars is --var pairs; no value holds a space
        (cd "$REPO" && koto init "$s" --template "$dir/fixture.md" $vars \
            --var SHARED_BRANCH="$shared") >"$dir/init.out" 2>&1
    else
        # shellcheck disable=SC2086 # as above
        (cd "$REPO" && koto init "$s" --template "$dir/fixture.md" $vars) >"$dir/init.out" 2>&1
    fi || { STATE="init-failed: $(head -c 300 "$dir/init.out")"; RESP=""; return; }
    if [ -n "${SEED_SUMMARY:-}" ]; then
        printf '# Summary\n\n## Changes Made\n- x\n' | (cd "$REPO" && koto context add "$s" summary.md) >/dev/null 2>&1
    fi
    if [ -n "${SEED_RECORD:-}" ]; then
        printf '%s' "$SEED_RECORD" | (cd "$REPO" && koto context add "$s" hosted_of_record) >"$dir/seed.out" 2>&1 \
            || { STATE="seed-failed: $(head -c 300 "$dir/seed.out")"; RESP=""; return; }
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

# A re-run request, end to end with the real launcher and verdict scripts: the
# shipped verification and implementation states, a repository whose one
# command fails on its first run and sleeps on later ones, and a
# verification_rerun submission at implementation. The design assumes the
# request key that edge assigns is in context when verification's default
# action runs, in the same tick; this case is where that assumption is shown.
echo "--- rerun: a failed command re-runs once on request (real launcher)"

# The launcher's state lives under HOME (this suite's temporary home), never
# under a developer's own XDG_STATE_HOME.
unset XDG_STATE_HOME

# A plugin root holding the four real scripts. check-verification.sh sources
# scripts/lib/rule-findings.sh relative to its own directory, so scripts/ is
# the real one.
RR_ROOT="$WORKDIR/rr-plugin"
mkdir -p "$RR_ROOT/skills/work-on/scripts"
for s in run-verification.sh verification-eligibility.sh check-verification.sh verification-route.sh; do
    ln -s "$SCRIPT_DIR/$s" "$RR_ROOT/skills/work-on/scripts/$s"
done
ln -s "$REAL_ROOT/scripts" "$RR_ROOT/scripts"

# The repository: main carries the map and the command; feature/rr changes a
# path the map selects. The command's marker sits outside the work tree, so
# the tree stays clean for the launcher's dirty-tree check. No origin remote:
# the launcher falls back to the local main.
RR_REPO="$WORKDIR/rr-repo"
RR_MARK="$WORKDIR/rr-marker"
mkdir -p "$RR_REPO/bin" "$RR_REPO/src" "$RR_REPO/.claude/shirabe-extensions"
cat > "$RR_REPO/bin/flaky.sh" <<'EOF'
#!/bin/sh
# Fails on its first run. Every later run records its pid and sleeps, so the
# second attempt is still running when the case looks at it.
if [ -e "$1" ]; then
    echo $$ > "$1.pid"
    exec sleep 30
fi
: > "$1"
echo "first run fails"
exit 1
EOF
chmod +x "$RR_REPO/bin/flaky.sh"
jq -cn --arg m "$RR_MARK" '{schema: "shirabe-verification-map/v1",
    commands: {flaky: {run: ["bin/flaky.sh", $m], timeout_secs: 120, max_procs: 16}},
    entries: [{paths: ["src/**"], commands: ["flaky"]}], default: ["flaky"]}' \
    > "$RR_REPO/.claude/shirabe-extensions/verification-map.json"
echo base > "$RR_REPO/src/a.txt"
RR_OK=1
(cd "$RR_REPO" && git init -q -b main . && git config user.email t@example.com && git config user.name t \
    && git add -A && git commit -q -m "chore: init" && git checkout -q -b feature/rr \
    && echo change >> src/a.txt && git commit -q -am "feat: change a") >/dev/null 2>&1 \
    || { RR_OK=0; fail "rerun: could not build the repository"; }
RH=$(git -C "$RR_REPO" rev-parse HEAD 2>/dev/null)
RM=$(git -C "$RR_REPO" merge-base HEAD main 2>/dev/null)
RS="og-rerun-$$"
RR_HEADDIR="$HOME/.local/state/shirabe/verification/$RS/$RH"
RR_SUP=""

# rr_reap: stop the second attempt's supervisor (TERM, which stops its running
# command's group too), then KILL both process groups, so nothing this case
# started outlives the suite. Also run on exit, before the WORKDIR cleanup.
rr_reap() {
    local p n=0
    if [ -z "${RR_SUP:-}" ] && [ -n "${RR_HEADDIR:-}" ]; then
        RR_SUP=$(readlink "$RR_HEADDIR/lock" 2>/dev/null)
    fi
    case "${RR_SUP:-}" in
        ''|*[!0-9]*) ;;
        *)
            # Only a supervisor of ours: a recycled pid is left alone.
            case "$(ps -p "$RR_SUP" -o command= 2>/dev/null)" in
                *run-verification.sh*)
                    kill -TERM "$RR_SUP" 2>/dev/null
                    while kill -0 "$RR_SUP" 2>/dev/null && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done
                    kill -KILL -- "-$RR_SUP" 2>/dev/null ;;
            esac ;;
    esac
    p=$(cat "$RR_MARK.pid" 2>/dev/null)
    case "$p" in ''|*[!0-9]*) ;; *) kill -KILL -- "-$p" 2>/dev/null ;; esac
    RR_SUP=""
    rm -f "$RR_MARK.pid"
    return 0
}
ktg_on_exit 'rr_reap; cleanup'

# The fixture: start -> the shipped verification block, the shipped
# implementation block, a changed_paths_record stub that goes straight back to
# verification, and a stub terminal for every other target the two name.
RR_DIR="$WORKDIR/rr-fixture"
mkdir -p "$RR_DIR"
RR_VER=$(stub_block "$(extract_state verification)")
RR_IMPL=$(stub_block "$(extract_state implementation)")
RR_TARGETS=$(printf '%s\n%s\n' "$RR_VER" "$RR_IMPL" | awk '/^      - target:/ { print $3 }' | sort -u)
{
    printf '%s\n' '---' 'name: output-gates-routing-rerun-fixture' 'version: "1.0"' \
        'description: Fixture driving a verification re-run through the shipped states.' 'initial_state: start' \
        'variables:' \
        '  ISSUE_NUMBER:' '    description: issue' '    required: false' \
        '  ISSUE_REPO:' '    description: issue repository' '    required: false' \
        '  PLUGIN_ROOT:' '    description: plugin root' '    required: false' \
        '  SHARED_BRANCH:' '    description: shared branch' '    required: false' \
        '  REVIEW_LEVEL:' '    description: review level' '    required: false' \
        '  VERIFICATION:' '    description: verification' '    required: false' \
        '    default: local' '    values: [local, hosted-ci]' \
        '  VERIFICATION_DEFERRAL_REASON:' '    description: deferral reason' '    required: false' \
        '  PROBE_NEAR_RULE:' '    description: the probe_near capture pr_creation reads' '    required: false' \
        'states:' '  start:' '    transitions:' '      - target: verification'
    printf '%s\n' "$RR_VER"
    printf '%s\n' "$RR_IMPL"
    printf '%s\n' '  changed_paths_record:' '    transitions:' '      - target: verification'
    for t in $RR_TARGETS; do
        case "$t" in verification|implementation|changed_paths_record) continue ;; esac
        printf '%s\n' "  $t:" '    terminal: true'
        if [ "$t" = done_blocked ]; then
            printf '%s\n' '    failure: true' '    accepts:' '      failure_reason:' '        type: string'
        fi
    done
    printf '%s\n' '---' '' '## start' '' 'Start.' '' '## verification' '' 'The state under test.' \
        '' '## implementation' '' 'The state under test.' '' '## changed_paths_record' '' 'Stub.'
    for t in $RR_TARGETS; do
        case "$t" in verification|implementation|changed_paths_record) continue ;; esac
        printf '%s\n' '' "## $t" '' 'Stub.'
    done
} > "$RR_DIR/fixture.md"

if [ "$RR_OK" -eq 1 ]; then
    (cd "$RR_REPO" && koto init "$RS" --template "$RR_DIR/fixture.md" --var PLUGIN_ROOT="$RR_ROOT" \
        --var ISSUE_NUMBER=7) >"$RR_DIR/init.out" 2>&1 \
        || { RR_OK=0; fail "rerun: koto init failed: $(head -c 300 "$RR_DIR/init.out")"; }
fi

# Tick until the failed first attempt routes to implementation (exit 1). The
# command fails at once and the poll is stubbed to one second, so a few ticks
# are plenty.
RR_STATE=""
if [ "$RR_OK" -eq 1 ]; then
    rr_i=0
    while [ "$rr_i" -lt 8 ] && [ "$RR_STATE" != implementation ]; do
        RR_RESP=$(cd "$RR_REPO" && koto next "$RS" --no-cleanup 2>/dev/null)
        RR_STATE=$(printf '%s' "$RR_RESP" | jq -r '.state // "none"' 2>/dev/null)
        rr_i=$((rr_i + 1))
    done
    if [ "$RR_STATE" = implementation ]; then
        pass "rerun: the failed first attempt routes to implementation (after $rr_i ticks)"
    else
        RR_OK=0
        fail "rerun: the first attempt never reached implementation: got $RR_STATE ($(head -c 300 <<<"$RR_RESP"))"
    fi
fi

# rr_why: the plain reason a post-submission assertion failed, when the state
# on disk shows the request never reached --start in the tick that assigned it.
rr_why() {
    if (cd "$RR_REPO" && koto context exists "$RS" verification_rerun_request) >/dev/null 2>&1; then
        printf '%s' "; the request key did not reach verification's default action in the same tick (it is still in context)"
    elif [ ! -e "$RR_HEADDIR/attempts/1/result.json" ] && [ -e "$RR_HEADDIR/result.json" ]; then
        printf '%s' "; the request key did not reach verification's default action in the same tick, or it was dropped there: attempt 1 was not archived"
    fi
}

if [ "$RR_OK" -eq 1 ]; then
    RR_REASON='flaky "net" test'
    RR_DATA=$(jq -cn --arg r "$RR_REASON" '{implementation_status: "verification_rerun", rationale: $r}')
    RR_RESP=$(cd "$RR_REPO" && koto next "$RS" --with-data "$RR_DATA" --no-cleanup 2>/dev/null)

    RR_CUR=$(cd "$RR_REPO" && koto status "$RS" 2>/dev/null | jq -r '.current_state // empty' 2>/dev/null)
    [ "$RR_CUR" = verification ] \
        && pass "rerun: one tick goes implementation -> changed_paths_record -> verification" \
        || fail "rerun: current_state is [$RR_CUR], want verification$(rr_why) ($(head -c 300 <<<"$RR_RESP"))"

    if (cd "$RR_REPO" && koto context exists "$RS" verification_rerun_request) >/dev/null 2>&1; then
        fail "rerun: verification_rerun_request is still in context: the request key did not reach verification's default action in the same tick"
    else
        pass "rerun: --start consumed verification_rerun_request (the key is gone)"
    fi

    RR_LEDGER=$(cd "$RR_REPO" && koto context get "$RS" verification_attempts 2>/dev/null)
    rr_n=$(printf '%s\n' "$RR_LEDGER" | grep -c .)
    if [ "$rr_n" = 1 ] && printf '%s\n' "$RR_LEDGER" | jq -e --arg h "$RH" --arg m "$RM" --arg r "$RR_REASON" \
            '.attempt == 1 and .folder == 1 and .head == $h and .merge_base == $m and .reason == $r' >/dev/null 2>&1; then
        pass "rerun: verification_attempts holds one line for attempt 1 (folder 1, head, merge-base, the reason)"
    else
        fail "rerun: verification_attempts ($rr_n line(s)): [$(head -c 300 <<<"$RR_LEDGER")]$(rr_why)"
    fi

    # The PR body's re-run record, against this real session's ledger: the
    # real check-pr-output.sh --rerun-record reads verification_attempts
    # through koto, and a gh stand-in serves the body, first without attempt
    # 1's re-run line, then with it.
    mkdir -p "$RR_DIR/bin"
    cat > "$RR_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
jq -Rsc '{body: .}' "$RR_GH_BODY"
EOF
    chmod +x "$RR_DIR/bin/gh"
    printf '%s\n' "A change." "" "---" "" "## Verification" "" "Ran the verification map's commands." \
        "" "Fixes #7" > "$RR_DIR/body-without.md"
    printf '%s\n' "A change." "" "---" "" "## Verification" "" "Ran the verification map's commands." \
        "Re-run attempt 1 at \`$(printf '%s' "$RH" | cut -c1-7)\`: \`flaky\` failed; reason \`$RR_REASON\`." \
        "" "Fixes #7" > "$RR_DIR/body-with.md"
    (cd "$RR_REPO" && PATH="$RR_DIR/bin:$PATH" RR_GH_BODY="$RR_DIR/body-without.md" \
        "$SCRIPT_DIR/check-pr-output.sh" --rerun-record --session "$RS") >/dev/null 2>"$RR_DIR/rerun-record.err"
    rr_rc=$?
    if [ "$rr_rc" -eq 1 ] && grep -qF "no re-run line for attempt 1 at $(printf '%s' "$RH" | cut -c1-12)" "$RR_DIR/rerun-record.err"; then
        pass "rerun: check-pr-output.sh --rerun-record refuses a body without attempt 1's re-run line (1), naming attempt 1"
    else
        fail "rerun: --rerun-record on a body without the line: exit $rr_rc, stderr [$(cat "$RR_DIR/rerun-record.err")]"
    fi
    (cd "$RR_REPO" && PATH="$RR_DIR/bin:$PATH" RR_GH_BODY="$RR_DIR/body-with.md" \
        "$SCRIPT_DIR/check-pr-output.sh" --rerun-record --session "$RS") >/dev/null 2>"$RR_DIR/rerun-record.err"
    rr_rc=$?
    if [ "$rr_rc" -eq 0 ]; then
        pass "rerun: check-pr-output.sh --rerun-record accepts the body with attempt 1's re-run line (0)"
    else
        fail "rerun: --rerun-record on a body with the line: exit $rr_rc, stderr [$(cat "$RR_DIR/rerun-record.err")]"
    fi

    if [ -f "$RR_HEADDIR/attempts/1/result.json" ] && [ -f "$RR_HEADDIR/attempts/1/run.json" ] \
            && grep -q 'first run fails' "$RR_HEADDIR/attempts/1/0-flaky.log" 2>/dev/null; then
        pass "rerun: attempt 1's result.json, run.json and log are in attempts/1/"
    else
        fail "rerun: attempts/1/ under $RR_HEADDIR holds [$(ls "$RR_HEADDIR/attempts/1" 2>/dev/null | tr '\n' ' ')]$(rr_why)"
    fi

    # The supervisor for attempt 2: the lock names it once --start returns; its
    # log and the command's second run follow within a moment.
    rr_n=0
    while [ "$rr_n" -lt 50 ]; do
        RR_SUP=$(readlink "$RR_HEADDIR/lock" 2>/dev/null)
        [ -n "$RR_SUP" ] && [ -e "$RR_HEADDIR/attempts/2/0-flaky.log" ] && [ -s "$RR_MARK.pid" ] && break
        sleep 0.1; rr_n=$((rr_n + 1))
    done
    if [ -n "$RR_SUP" ] && kill -0 "$RR_SUP" 2>/dev/null && [ -e "$RR_HEADDIR/attempts/2/0-flaky.log" ]; then
        pass "rerun: a supervisor for attempt 2 is running (pid $RR_SUP) and logging to attempts/2/"
    else
        fail "rerun: no live supervisor for attempt 2 (lock [$RR_SUP], attempts/2/ holds [$(ls "$RR_HEADDIR/attempts/2" 2>/dev/null | tr '\n' ' ')])$(rr_why)"
    fi
    [ -s "$RR_MARK.pid" ] && pass "rerun: attempt 2 ran the command again (its second run)" \
        || fail "rerun: the command did not run a second time$(rr_why)"
fi
rr_reap

# A re-run at the timed-out hold, end to end with the real launcher and
# verdict scripts: the same fixture, a repository whose one command sleeps past
# its twenty-second limit on every run, in a row that declares a hosted job, so
# the verdict holds at 5 with the route open. A verification_status: rerun
# there is a self-loop; this case shows its request key reaches the default
# action in the same tick, as the implementation edge's does above.
# The limit is twenty seconds, not five, because the case looks for attempt 2's
# supervisor after the rerun tick returns, and that tick runs on after --start
# has launched it: about 2.5 s on an idle host, past 5 s on a loaded one (the
# bash 3.2 floor job runs this file alongside the rest of the gate). A limit
# shorter than the tick lets the supervisor time its command out and release
# the lock before the case can see it.
echo "--- rerun: a timed-out check re-runs from the hold (real launcher)"
R5_REPO="$WORKDIR/rr5-repo"
R5_MARK="$WORKDIR/rr5-marker"
mkdir -p "$R5_REPO/bin" "$R5_REPO/src" "$R5_REPO/.claude/shirabe-extensions"
cat > "$R5_REPO/bin/slow.sh" <<'EOF'
#!/bin/sh
# Every run records its pid and sleeps past the row's timeout.
echo $$ > "$1.pid"
exec sleep 60
EOF
chmod +x "$R5_REPO/bin/slow.sh"
jq -cn --arg m "$R5_MARK" '{schema: "shirabe-verification-map/v1",
    commands: {slow: {run: ["bin/slow.sh", $m], timeout_secs: 20, max_procs: 16,
                      hosted: [{workflow: ".github/workflows/ci.yml", job: "test", runs: "slow"}]}},
    entries: [{paths: ["src/**"], commands: ["slow"]}], default: ["slow"]}' \
    > "$R5_REPO/.claude/shirabe-extensions/verification-map.json"
echo base > "$R5_REPO/src/a.txt"
R5_OK=1
(cd "$R5_REPO" && git init -q -b main . && git config user.email t@example.com && git config user.name t \
    && git add -A && git commit -q -m "chore: init" && git checkout -q -b feature/rr5 \
    && echo change >> src/a.txt && git commit -q -am "feat: change a") >/dev/null 2>&1 \
    || { R5_OK=0; fail "rerun at the hold: could not build the repository"; }
R5H=$(git -C "$R5_REPO" rev-parse HEAD 2>/dev/null)
R5M=$(git -C "$R5_REPO" merge-base HEAD main 2>/dev/null)
R5S="og-rerun5-$$"
# The exit hook's rr_reap reaps this case from here on.
RR_HEADDIR="$HOME/.local/state/shirabe/verification/$R5S/$R5H"
RR_MARK=$R5_MARK
RR_SUP=""

if [ "$R5_OK" -eq 1 ]; then
    (cd "$R5_REPO" && koto init "$R5S" --template "$RR_DIR/fixture.md" --var PLUGIN_ROOT="$RR_ROOT" \
        --var ISSUE_NUMBER=7) >"$RR_DIR/init5.out" 2>&1 \
        || { R5_OK=0; fail "rerun at the hold: koto init failed: $(head -c 300 "$RR_DIR/init5.out")"; }
fi

# Tick until the verdict is recorded: the first attempt times out and the gate
# holds at 5. Every tick holds at least the fixture's one-second hold_secs, so
# sixty ticks wait the twenty-second limit out on any host.
if [ "$R5_OK" -eq 1 ]; then
    r5_i=0
    while [ "$r5_i" -lt 60 ]; do
        R5_RESP=$(cd "$R5_REPO" && koto next "$R5S" --no-cleanup 2>/dev/null)
        r5_i=$((r5_i + 1))
        (cd "$R5_REPO" && koto context exists "$R5S" verification_results.json) >/dev/null 2>&1 && break
    done
    R5_STATE=$(jq -r '.state // "none"' <<<"$R5_RESP")
    if [ "$R5_STATE" = verification ] \
            && jq -e '.status == "done" and .commands[0].outcome == "timed-out-limit"' "$RR_HEADDIR/result.json" >/dev/null \
            && (cd "$R5_REPO" && koto context exists "$R5S" verification_results.json) >/dev/null 2>&1; then
        pass "rerun at the hold: the timed-out first attempt holds at verification (after $r5_i ticks)"
    else
        R5_OK=0
        fail "rerun at the hold: the first attempt never held: state $R5_STATE ($(head -c 300 <<<"$R5_RESP"))"
    fi
fi

if [ "$R5_OK" -eq 1 ]; then
    R5_REASON='the host was loaded'
    R5_DATA=$(jq -cn --arg r "$R5_REASON" '{verification_status: "rerun", detail: $r}')
    R5_RESP=$(cd "$R5_REPO" && koto next "$R5S" --with-data "$R5_DATA" --no-cleanup 2>/dev/null)

    # Attempt 2's supervisor first, while its command is inside its limit: the
    # lock names it once --start returns, and its log follows.
    r5_n=0
    while [ "$r5_n" -lt 50 ]; do
        RR_SUP=$(readlink "$RR_HEADDIR/lock" 2>/dev/null)
        [ -n "$RR_SUP" ] && [ -e "$RR_HEADDIR/attempts/2/0-slow.log" ] && break
        sleep 0.1; r5_n=$((r5_n + 1))
    done
    if [ -n "$RR_SUP" ] && kill -0 "$RR_SUP" 2>/dev/null && [ -e "$RR_HEADDIR/attempts/2/0-slow.log" ]; then
        pass "rerun at the hold: a supervisor for attempt 2 is running (pid $RR_SUP) and logging to attempts/2/"
    else
        fail "rerun at the hold: no live supervisor for attempt 2 (lock [$RR_SUP], attempts/2/ holds [$(ls "$RR_HEADDIR/attempts/2" 2>/dev/null | tr '\n' ' ')])"
    fi

    R5_CUR=$(cd "$R5_REPO" && koto status "$R5S" 2>/dev/null | jq -r '.current_state // empty')
    [ "$R5_CUR" = verification ] \
        && pass "rerun at the hold: the self-loop leaves the session at verification" \
        || fail "rerun at the hold: current_state is [$R5_CUR], want verification ($(head -c 300 <<<"$R5_RESP"))"

    if (cd "$R5_REPO" && koto context exists "$R5S" verification_rerun_request) >/dev/null 2>&1; then
        fail "rerun at the hold: verification_rerun_request is still in context: the self-loop's assignment did not reach verification's default action in the same tick"
    else
        pass "rerun at the hold: --start consumed verification_rerun_request (the key is gone)"
    fi

    R5_LEDGER=$(cd "$R5_REPO" && koto context get "$R5S" verification_attempts 2>/dev/null)
    r5_n=$(printf '%s\n' "$R5_LEDGER" | grep -c .)
    if [ "$r5_n" = 1 ] && jq -e --arg h "$R5H" --arg m "$R5M" --arg r "$R5_REASON" \
            '.attempt == 1 and .folder == 1 and .exit == 5 and .head == $h and .merge_base == $m and .reason == $r' \
            <<<"$R5_LEDGER" >/dev/null; then
        pass "rerun at the hold: verification_attempts holds one line for attempt 1 (exit 5, head, merge-base, the reason)"
    else
        fail "rerun at the hold: verification_attempts ($r5_n line(s)): [$(head -c 300 <<<"$R5_LEDGER")]"
    fi

    [ -f "$RR_HEADDIR/attempts/1/result.json" ] && [ -f "$RR_HEADDIR/attempts/1/run.json" ] \
        && pass "rerun at the hold: attempt 1's result.json and run.json are in attempts/1/" \
        || fail "rerun at the hold: attempts/1/ holds [$(ls "$RR_HEADDIR/attempts/1" 2>/dev/null | tr '\n' ' ')]"
fi
rr_reap

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

# commit_convention: holds at finalization and deferral_approval, and on exit 0
# both go straight to pr_precheck. No later state checks the commits again.
SEED_SUMMARY=1
for rc in 1 2; do
    reset_rc; set_rc check-branch-output.sh--commits "$rc"
    drive finalization "" '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
    holds "commit_convention exit $rc at finalization" finalization commit_convention
    drive deferral_approval "" '{"approval_decision":"approved","deferral_detail":"x","cleanup_done":"none_found","design_diagram":"not_applicable"}'
    holds "commit_convention exit $rc on deferral_approval's approved edge" deferral_approval commit_convention
done
reset_rc
drive finalization "" '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
expect "commit_convention exit 0 at finalization" pr_precheck
drive deferral_approval "" '{"approval_decision":"approved","deferral_detail":"x","cleanup_done":"none_found","design_diagram":"not_applicable"}'
expect "commit_convention exit 0 on the approved edge" pr_precheck
SEED_SUMMARY=

# pr_precheck: the branch checks hold unless SHARED_BRANCH is set.
for key in check-branch-output.sh--docs-visibility:branch_docs_visibility; do
    for rc in 1 2; do
        reset_rc; set_rc "${key%%:*}" "$rc"
        drive pr_precheck "" "" on_feature_branch_pr=0
        holds "${key#*:} exit $rc" pr_precheck "${key#*:}"
        drive pr_precheck "docs/shared" "" on_feature_branch_pr=0
        expect "${key#*:} script exit $rc on a shared branch" probe_near
    done
done
reset_rc
drive pr_precheck "" "" on_feature_branch_pr=0
expect "the branch check passes" probe_near
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
    # because its passing edge takes none, so there it goes on toward
    # pr_creation (through probe_near, a stub terminal here).
    for rc in 0 2; do
        reset_rc; set_rc "$key" "$rc"
        if [ "$st" = pr_precheck ] && [ "$rc" = 0 ]; then
            drive "$st" "" "" on_feature_branch_pr=0 closing_keyword=0
            expect "pr_precheck with $gate at 0 passes before any exit can be taken" probe_near
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
# two commit_convention copies, at finalization and deferral_approval, stay
# identical (finalization-shape_test.sh compares them compiled).
for g in pr_body_conformant commit_convention branch_docs_visibility verification_verdict \
         scrutiny_verdict review_verdict qa_verdict light_verdict; do
    n=$(awk -v g="      $g:" '$0 == g { f = 1; next } f && /^        command:/ { print; f = 0 }' "$TEMPLATE" \
        | grep -c "SHIRABE_GATE_LOG=\"{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl\" SHIRABE_GATE_NAME=$g SHIRABE_GATE_EXITS=")
    want=1; [ "$g" = commit_convention ] && want=2
    [ "$n" = "$want" ] && pass "$g carries the ladder's context ($n)" || fail "$g: ladder context on $n command(s), want $want"
done
[ "$(awk '/^      commit_convention:$/ { f = 1; next } f && /^        command:/ { print; f = 0 }' "$TEMPLATE" | sort -u | wc -l | tr -d ' ')" = 1 ] \
    && pass "the two commit_convention commands are byte-identical" || fail "commit_convention commands differ"

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

# The hosted-of-record route: verification's timed-out hold (exit 5),
# verification_hosted, pr_creation's draft gate, ci_monitor's settled gate and
# hosted_record. verification-route.sh and check-pr-output.sh are fakes that
# answer from $RC_DIR; the gates that test for the hosted_of_record key run
# the real `koto context exists` against the case's own session.
ROUTE_HEAD=0123456789abcdef0123456789abcdef01234567
ROUTE_REC='{"head":"'$ROUTE_HEAD'","taken_at":"2026-11-20T10:00:00Z","reason":"the host was loaded","checks":[{"id":"check-skill:coordinate","jobs":[{"workflow":".github/workflows/check-skill-gate.yml","job":"skill-gate (ubuntu-latest)","run_id":null,"conclusion":null,"attempt":null}]}]}'
ROUTE_FILLED='{"head":"'$ROUTE_HEAD'","taken_at":"2026-11-20T10:00:00Z","reason":"the host was loaded","checks":[{"id":"check-skill:coordinate","jobs":[{"workflow":".github/workflows/check-skill-gate.yml","job":"skill-gate (ubuntu-latest)","run_id":4242,"conclusion":"success","attempt":1}]}]}'

# ctx <key>: the key in the session the last drive made.
ctx() { (cd "$REPO" && koto context get "og-$N" "$1" 2>/dev/null); }
# walked: the states the last drive's session entered, in order.
walked() {
    local log
    log="$(cd "$REPO" && koto session dir "og-$N")/koto-og-$N.state.jsonl"
    jq -r 'select(.type == "transitioned") | .payload.to' "$log" | tr '\n' ' '
}
# tick_more <evidence-or-empty>: one more tick of the last drive's session.
tick_more() {
    if [ -n "$1" ]; then
        RESP=$(cd "$REPO" && koto next "og-$N" --with-data "$1" --no-cleanup 2>/dev/null)
    else
        RESP=$(cd "$REPO" && koto next "og-$N" --no-cleanup 2>/dev/null)
    fi
    STATE=$(printf '%s' "$RESP" | jq -r '.state // "none"' 2>/dev/null)
}
TAKE='{"verification_status":"hosted_of_record","detail":"x"}'

echo "--- the hosted-of-record route"

# The hold. With the verdict at 5 nothing moves the run without a value.
reset_rc; set_rc check-verification.sh--verdict 5
drive verification "" ""
holds "verdict 5 (a check timed out, none failed), no evidence" verification verification_verdict
# The check-skill:coordinate shape (timed-out-limit, 121 of 127 suites
# reached, nothing failed, the diff inside skills/coordinate): the verdict
# is 5 and the route gate 0, so the reason takes the route.
drive verification "" "$TAKE"
expect "verdict 5, route 0, hosted_of_record with a reason" verification_hosted
[ "$(ctx hosted_route_reason)" = x ] && pass "hosted_of_record writes its reason to hosted_route_reason" \
    || fail "hosted_route_reason is [$(ctx hosted_route_reason)], want [x]"
for d in '""' '"   "' '"\t \n "'; do
    drive verification "" "{\"verification_status\":\"hosted_of_record\",\"detail\":$d}"
    expect "hosted_of_record with detail $d is refused" verification
done
drive verification "" '{"verification_status":"hosted_of_record"}'
expect "hosted_of_record with no detail is refused" verification
set_rc verification-route.sh--open 1
drive verification "" "$TAKE"
expect "hosted_of_record with the route gate at 1 is refused" verification
set_rc verification-route.sh--open 2
drive verification "" "$TAKE"
expect "hosted_of_record with the route gate at 2 is refused" verification
reset_rc; set_rc check-verification.sh--verdict 5
drive verification "" '{"verification_status":"fix"}'
expect "fix at the hold" implementation
drive verification "" '{"verification_status":"blocked","detail":"no time for the hosted run"}'
expect "blocked at the hold" done_blocked
[ "$(ctx failure_reason)" = "verification blocked at the timed-out hold: no time for the hosted run" ] \
    && pass "blocked at the hold names the hold in failure_reason" || fail "failure_reason [$(ctx failure_reason)]"
# fix and hosted_of_record belong to the hold: refused while the verdict
# waits (75) or holds (2).
for rc in 75 2; do
    reset_rc; set_rc check-verification.sh--verdict "$rc"
    drive verification "" "$TAKE"
    expect "hosted_of_record at verdict $rc is refused" verification
    drive verification "" '{"verification_status":"fix"}'
    expect "fix at verdict $rc is refused" verification
done

# rerun at the hold: a self-loop that writes verification_rerun_request from
# detail, with a non-blank reason and without the route gate. The launcher
# here is a fake, so the key stays for the case to read. 75 + rerun takes the
# same lap (the order where --archive ran first); 2 has no rerun edge.
# rerun_looped <label>: the last drive walked verification twice and holds
# the request key; rerun_refused <label>: it entered verification once and
# wrote no key.
rerun_looped() {
    case "$(walked)" in
        *"verification verification"*)
            if [ "$STATE" = verification ] && [ "$(ctx verification_rerun_request)" = "$2" ]; then
                pass "$1: back to verification, verification_rerun_request [$2]"
            else
                fail "$1: state $STATE, verification_rerun_request [$(ctx verification_rerun_request)]"
            fi ;;
        *) fail "$1: walked [$(walked)], want a verification self-loop ($(head -c 300 <<<"$RESP"))" ;;
    esac
}
# The key's absence is `koto context exists` exiting nonzero: `context get` on
# a missing key prints an error object on standard output, not nothing.
rerun_refused() {
    case "$(walked)" in
        *"verification verification"*) fail "$1: walked [$(walked)], want no self-loop" ;;
        *)
            if [ "$STATE" = verification ] \
                    && ! (cd "$REPO" && koto context exists "og-$N" verification_rerun_request) >/dev/null 2>&1; then
                pass "$1 is refused: no self-loop and no verification_rerun_request"
            else
                fail "$1: state $STATE, verification_rerun_request [$(ctx verification_rerun_request)]"
            fi ;;
    esac
}
reset_rc; set_rc check-verification.sh--verdict 5
drive verification "" '{"verification_status":"rerun","detail":"the host was loaded"}'
rerun_looped "rerun with a reason at the hold" "the host was loaded"
for d in '""' '"   "'; do
    drive verification "" "{\"verification_status\":\"rerun\",\"detail\":$d}"
    rerun_refused "rerun with detail $d at the hold"
done
drive verification "" '{"verification_status":"rerun"}'
rerun_refused "rerun with no detail at the hold"
set_rc verification-route.sh--open 1
drive verification "" '{"verification_status":"rerun","detail":"flaky"}'
rerun_looped "rerun at the hold with the route gate at 1 (a rerun never needs the route)" flaky
reset_rc; set_rc check-verification.sh--verdict 75
drive verification "" '{"verification_status":"rerun","detail":"archived by hand"}'
rerun_looped "rerun at verdict 75, after --archive at the hold" "archived by hand"
drive verification "" '{"verification_status":"rerun","detail":"  "}'
rerun_refused "rerun with an all-space reason at verdict 75"
reset_rc; set_rc check-verification.sh--verdict 2
drive verification "" '{"verification_status":"rerun","detail":"flaky"}'
rerun_refused "rerun at verdict 2"

# A child of /execute (SHARED_BRANCH set: a single-pr shared-branch child, or
# a coordinated work item on its node branch) takes the route the same way:
# the hold at 5, hosted_of_record with a reason on to verification_hosted and
# pass_counting, an empty reason refused. /execute reads the record for the
# PR it owns.
for shared in impl/plan-x impl/plan-x-node-a; do
    reset_rc; set_rc check-verification.sh--verdict 5
    drive verification "$shared" ""
    holds "SHARED_BRANCH=$shared, verdict 5, no evidence" verification verification_verdict
    CHAIN=verification_hosted drive verification "$shared" "$TAKE"
    expect "SHARED_BRANCH=$shared takes the route as a standalone run does" pass_counting
    drive verification "$shared" '{"verification_status":"hosted_of_record","detail":"  "}'
    expect "SHARED_BRANCH=$shared, hosted_of_record with an empty reason is refused" verification
done

# One session, started with the default VERIFICATION=local, takes the route
# and goes on: no re-init between verification and pass_counting.
reset_rc; set_rc check-verification.sh--verdict 5
CHAIN=verification_hosted drive verification "" "$TAKE"
expect "a local session takes the route with no re-init" pass_counting
case "$(walked)" in
    *"verification verification_hosted pass_counting"*) pass "the session walked verification, verification_hosted, pass_counting" ;;
    *) fail "the session walked [$(walked)]" ;;
esac
# A record the check refuses returns the run to the hold, which offers the
# route again, and a reason from the earlier visit doesn't carry over.
set_rc verification-route.sh--check-record 1
CHAIN=verification_hosted drive verification "" "$TAKE"
holds "check-record 1 returns to verification, at 5 again," verification verification_verdict
tick_more '{"verification_status":"hosted_of_record","detail":" "}'
expect "back at the hold, an all-space reason is refused (the earlier visit's reason doesn't count)" verification
set_rc verification-route.sh--check-record 0
tick_more '{"verification_status":"hosted_of_record","detail":"y"}'
expect "back at the hold, the route is offered again" pass_counting

# verification_hosted on its own: 0 on, 1 back, 2 holds.
reset_rc
drive verification_hosted "" ""
expect "hosted_record_valid exit 0" pass_counting
set_rc verification-route.sh--check-record 1
drive verification_hosted "" ""
expect "hosted_record_valid exit 1" verification
set_rc verification-route.sh--check-record 2
drive verification_hosted "" ""
holds "hosted_record_valid exit 2" verification_hosted hosted_record_valid
drive verification_hosted "" '{"hosted_status":"blocked","detail":"koto cannot read the key"}'
expect "hosted_status: blocked on exit 2" done_blocked
reset_rc; set_rc verification-route.sh--record 1; set_rc verification-route.sh--check-record 2
drive verification_hosted "" ""
holds "a record the action refuses" verification_hosted __action__
drive verification_hosted "" '{"hosted_status":"blocked","detail":"the route closed"}'
expect "hosted_status: blocked after the action refused" done_blocked

# A hosted-ci session never enters verification: the edges back go to
# verification_deferred.
reset_rc; set_rc verification-route.sh--check-record 1
DRIVE_VARS=VERIFICATION=hosted-ci drive verification_hosted "" ""
expect "hosted-ci: hosted_record_valid exit 1" verification_deferred
reset_rc; set_rc verification-route.sh--read 1
DRIVE_VARS=VERIFICATION=hosted-ci drive hosted_record "" ""
expect "hosted-ci: hosted_read exit 1" verification_deferred

# pr_creation: with a record, the created edge needs the draft and its lines.
CREATED='{"pr_status":"created","pr_url":"https://github.com/o/r/pull/1"}'
for rc in 1 2; do
    reset_rc; set_rc check-pr-output.sh--hosted-record "$rc"
    SEED_RECORD=$ROUTE_REC drive pr_creation "" "$CREATED" closing_keyword=0
    holds "a record, hosted_record_line exit $rc" pr_creation hosted_record_line
done
reset_rc
SEED_RECORD=$ROUTE_REC drive pr_creation "" "$CREATED" closing_keyword=0
expect "a record, hosted_record_line exit 0" ci_monitor
# No record: the gate never starts the script, so its answer doesn't matter.
set_rc check-pr-output.sh--hosted-record 1
drive pr_creation "" "$CREATED" closing_keyword=0
expect "no record: pr_creation passes as before (the script's 1 never read)" ci_monitor

# ci_monitor: green CI with a record that isn't settled goes to the read.
for rec in "$ROUTE_REC" "$ROUTE_FILLED"; do
    reset_rc; set_rc verification-route.sh--settled 1
    SEED_RECORD=$rec drive ci_monitor "" "" ci_passing=0 merge_state_clean=0
    expect "green CI, a record ($(printf '%s' "$rec" | jq -r '.checks[0].jobs[0].run_id // "unread"')), hosted_settled exit 1" hosted_record
done
reset_rc
SEED_RECORD=$ROUTE_FILLED drive ci_monitor "" "" ci_passing=0 merge_state_clean=0
expect "green CI, a settled record" ci_pass_counting
set_rc verification-route.sh--settled 1
drive ci_monitor "" "" ci_passing=0 merge_state_clean=0
expect "green CI, no record (the script's 1 never read)" ci_pass_counting
set_rc verification-route.sh--settled 2
SEED_RECORD=$ROUTE_REC drive ci_monitor "" "" ci_passing=0 merge_state_clean=0
holds "green CI, a record that can't be read" ci_monitor hosted_settled
reset_rc; set_rc verification-route.sh--settled 1
SEED_RECORD=$ROUTE_REC drive ci_monitor "" "" ci_passing=0 merge_state_clean=1
expect "a DIRTY pull request with a record still stops" done_blocked

# hosted_record, walked on to ci_monitor and ci_pass_counting.
reset_rc; set_rc verification-route.sh--ready 1
SEED_RECORD=$ROUTE_REC CHAIN=ci_monitor drive hosted_record "" "" ci_passing=0 merge_state_clean=0
holds "read 0, ready 1 (still a draft)" hosted_record hosted_ready
reset_rc
SEED_RECORD=$ROUTE_FILLED CHAIN=ci_monitor drive hosted_record "" "" ci_passing=0 merge_state_clean=0
expect "read 0, ready 0, then settled 0 at ci_monitor" ci_pass_counting
case "$(walked)" in
    *"hosted_record ci_monitor ci_pass_counting"*) pass "the read returned to ci_monitor before ci_pass_counting" ;;
    *) fail "the session walked [$(walked)]" ;;
esac
reset_rc; set_rc verification-route.sh--read 75
SEED_RECORD=$ROUTE_REC CHAIN=ci_monitor drive hosted_record "" "" ci_passing=0 merge_state_clean=0
if [ "$STATE" = hosted_record ] && printf '%s' "$RESP" | jq -e '[.blocking_conditions[]? | select(.name == "hosted_read" and .status == "pending")] | length > 0' >/dev/null 2>&1; then
    pass "read 75 waits at hosted_record (pending)"
else
    fail "read 75: want a pending wait at hosted_record, got $STATE ($(head -c 300 <<<"$RESP"))"
fi
tick_more ""
case "$STATE" in
    hosted_record) pass "read 75 again still waits, short of ci_pass_counting and done" ;;
    *) fail "read 75 reached $STATE" ;;
esac
tick_more '{"hosted_status":"blocked","detail":"the hosted run never started"}'
expect "hosted_status: blocked while the read waits" done_blocked
reset_rc; set_rc verification-route.sh--read 3
SEED_RECORD=$ROUTE_REC drive hosted_record "" ""
expect "read 3 (pending past 120 minutes)" done_blocked
[ "$(ctx failure_reason)" = "$FAKE_PENDING_REASON" ] \
    && pass "read 3 keeps the script's failure_reason" || fail "failure_reason [$(ctx failure_reason)]"
for rc in 2 -1; do
    reset_rc
    if [ "$rc" = -1 ]; then set_rc verification-route.sh--read sleep; else set_rc verification-route.sh--read "$rc"; fi
    SEED_RECORD=$ROUTE_REC TIMEOUT_GATE=hosted_read drive hosted_record "" ""
    holds "read $rc" hosted_record hosted_read
    SEED_RECORD=$ROUTE_REC TIMEOUT_GATE=hosted_read drive hosted_record "" '{"hosted_status":"blocked","detail":"cannot read"}'
    expect "hosted_status: blocked on read $rc" done_blocked
done
# A refused read returns to verification, where the reused result holds at
# 5 again, offers the route again and still takes blocked.
reset_rc; set_rc verification-route.sh--read 1; set_rc check-verification.sh--verdict 5
SEED_RECORD=$ROUTE_REC CHAIN=verification drive hosted_record "" ""
holds "read 1 returns to verification, at 5," verification verification_verdict
SEED_RECORD=$ROUTE_REC CHAIN=verification drive hosted_record "" "$TAKE"
expect "back at the hold after read 1, hosted_of_record" verification_hosted
SEED_RECORD=$ROUTE_REC CHAIN=verification drive hosted_record "" '{"verification_status":"blocked","detail":"giving up"}'
expect "back at the hold after read 1, blocked" done_blocked
# A commit after the route: settled 1, then the read refuses on the head,
# and the new head enters verification afresh (its verdict still pending).
reset_rc; set_rc verification-route.sh--settled 1; set_rc verification-route.sh--read 1
set_rc check-verification.sh--verdict 75
SEED_RECORD=$ROUTE_REC CHAIN="hosted_record verification" drive ci_monitor "" "" ci_passing=0 merge_state_clean=0
expect "a moved head (settled 1, read 1)" verification
case "$(walked)" in
    *"ci_monitor hosted_record verification"*) pass "the moved head went through the read to verification" ;;
    *) fail "the session walked [$(walked)]" ;;
esac
reset_rc

echo
echo "output-gates-routing_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

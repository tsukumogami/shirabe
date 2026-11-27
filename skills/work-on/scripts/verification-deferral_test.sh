#!/usr/bin/env bash
# verification-deferral_test.sh -- does a /work-on run that defers verification
# to hosted CI (VERIFICATION=hosted-ci, #1012) skip the verification map, still
# reach finalization and PR creation with its pull request in its result, and
# record the deferral in its PR body, while a run that doesn't defer routes
# exactly as it did before?
# Part of the work-on skill
#
# work-on.md splits every edge into `verification` on VERIFICATION: `local`
# keeps the edge, and a twin with `hosted-ci` goes to
# `verification_deferred`, which runs no command and goes on, through
# pass_counting, to finalization with the reason in context as
# `verification_deferral`, or to done_blocked
# when no reason was given. pr_creation's verification_deferral_recorded gate
# holds the created edge until check-pr-output.sh --deferral-record finds the
# deferral in the body; on a local run it passes without running anything.
#
# This file checks:
#
#   1. Static, no engine: every edge into verification carries
#      `vars.VERIFICATION: local` and has a twin into verification_deferred,
#      from the same state, on the same conditions with `hosted-ci`; the two
#      variables are not rebindable; verification_deferred has no action and
#      no gates; and pr_creation's created edge needs the record gate. The
#      partial delivery's DELIVERY (closes or partial, default closes) and
#      DELIVERY_REASON (the deferral reason's pattern) are declared the same
#      way, optional and not rebindable (#1736).
#   2. The record gate's shipped command, no engine: a local run never starts
#      the script; a hosted-ci run passes the reason to
#      check-pr-output.sh --deferral-record and routes on its exit.
#   3. Engine: fixtures built from the SHIPPED state blocks, extracted at run
#      time, with every gate script replaced by a fake under a fake
#      PLUGIN_ROOT that logs its calls:
#        - qa_validation, light_review and review (at standard) with
#          hosted-ci and a reason reach finalization through
#          verification_deferred and pass_counting (whose fix_green runs),
#          the reason is in context, and run-verification.sh is never called;
#        - the same states with the default `local` enter verification, whose
#          action calls run-verification.sh --start, and reach finalization on
#          its verdict;
#        - issue_type_routing's docs and task edges the same way, both ways,
#          from a fixture whose start gates the two context keys the
#          issue_type decider reads (koto compiles a decider input only when
#          a context-exists gate checks its key); and a deferred docs run with
#          no commits holds there;
#        - hosted-ci with no reason ends at done_blocked, saying why, and
#          never calls run-verification.sh;
#        - koto refuses a VERIFICATION outside its values and a reason that is
#          a bare flag;
#        - a child on /execute's shared branch (SHARED_BRANCH set) defers
#          and records its reason the same way, and its `pr_status: shared`
#          reaches done whatever the record gate answers (#1017);
#        - on a `work-on` leg, pr_creation holds a deferred run's
#          `pr_status: created` while the body lacks the record, then reaches
#          done with the pull request in the leg's payload once it has it; a
#          local run never calls --deferral-record.
#
# VERIFICATION=auto, the default, adds a third twin to every such edge, into
# verification_plan, whose verification_route_plan gate (run-verification.sh
# --plan, a fake here) routes in the same tick: 0 to verification_deferred,
# which writes the hosted resolution's own reason, and 1, 2 or -1 to
# verification. The suite checks those edges statically, drives them through
# koto from each panel and from issue_type_routing, checks that an explicit
# local or hosted-ci never runs --plan, checks the record gate's auto branch
# (--resolved first, then the hosted reason), and drives ci_monitor's
# hosted_twins: a twin gone (--twins exit 1) sends an auto run back through
# verification with verification_twin_gone written; local and hosted-ci runs
# never start --twins. The resolution itself is verification-plan_test.sh's.
#
# The engine part skips, loudly, when koto is not on PATH (the bash 3.2 floor
# leg has no koto), and its leg cases skip when koto lacks --koto-leg.
#
# Usage: verification-deferral_test.sh
# Exit codes: 0 all pass (or the engine part skipped), 1 any failed, 2 the
# harness could not run.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
eq() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1: want [$2], got [$3]"; fi; }

[ -f "$TEMPLATE" ] || { echo "template not found: $TEMPLATE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/verification-deferral.XXXXXX") || exit 1
WORKDIR=$(cd -P "$WORKDIR" && pwd -P) || exit 1
cleanup() { case "${WORKDIR:-}" in */verification-deferral.*) rm -rf "$WORKDIR" ;; esac; return 0; }
ktg_on_exit cleanup

REASON="host is in a measurement window until 02:40Z"

# extract_state <name>: the state's block from the template's frontmatter.
extract_state() {
    awk -v want="  $1:" '
        $0 == want { found = 1; print; next }
        found && /^  [a-zA-Z_][a-zA-Z0-9_]*:$/ { exit }
        found && /^---$/ { exit }
        found { print }
    ' "$TEMPLATE"
}

# extract_var <name>: the variable's declaration from the variables block.
extract_var() {
    awk -v want="  $1:" '
        /^variables:$/ { on = 1; next }
        on && /^states:$/ { exit }
        on && $0 == want { found = 1; print; next }
        found && /^  [A-Z][A-Z0-9_]*:$/ { exit }
        found { print }
    ' "$TEMPLATE"
}

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

# edges: one line per transition in the frontmatter,
# `<state>|<target>|<when lines joined by ";">`.
edges() {
    awk '
        function flush() {
            if (tgt != "") print st "|" tgt "|" cond
            tgt = ""; cond = ""; inwhen = 0
        }
        /^states:$/ { s = 1; next }
        !s { next }
        /^---$/ { flush(); exit }
        /^  [a-z_][a-z_0-9]*:$/ { flush(); st = $1; sub(/:$/, "", st); next }
        /^    [a-z_]+:/ { flush(); next }
        /^      - target: / { flush(); tgt = $3; next }
        tgt != "" && /^        when:$/ { inwhen = 1; next }
        tgt != "" && /^        [a-z_]+:/ { inwhen = 0; next }
        tgt != "" && inwhen && /^          [^#]/ { l = $0; sub(/^ +/, "", l); cond = cond l ";"; next }
        END { flush() }
    ' "$TEMPLATE"
}

# --- 1. static -----------------------------------------------------------------------

echo "--- the shipped template"

EDGES=$(edges)
# A loop inside verification (its re-run at the timed-out hold) isn't a way in,
# and a hosted-ci run never reaches that hold, so only edges from other states
# count and need a twin. verification_plan is where an auto run's twins go, and
# its own edges route on its gate; ci_monitor's edge in is the twin re-check,
# which only an auto run resolved to hosted CI takes. Both are checked below.
INTO=$(printf '%s\n' "$EDGES" | awk -F'|' '$1 != "verification" && $1 != "verification_plan" && $1 != "ci_monitor" && $2 == "verification"')
TWINS=$(printf '%s\n' "$EDGES" | awk -F'|' '$1 != "verification_plan" && $2 == "verification_deferred"')
AUTOS=$(printf '%s\n' "$EDGES" | awk -F'|' '$2 == "verification_plan"')
N_INTO=$(printf '%s\n' "$INTO" | grep -c .)
N_TWINS=$(printf '%s\n' "$TWINS" | grep -c .)
N_AUTOS=$(printf '%s\n' "$AUTOS" | grep -c .)
if [ "$N_INTO" -ge 8 ]; then
    pass "found $N_INTO edges into verification"
else
    fail "expected at least 8 edges into verification (docs, task, two each from light_review, review and qa_validation), found $N_INTO"
fi
eq "every edge into verification has one twin into verification_deferred" "$N_INTO" "$N_TWINS"
eq "every edge into verification has one twin into verification_plan" "$N_INTO" "$N_AUTOS"

BAD=$(printf '%s\n' "$INTO" | grep -v 'vars.VERIFICATION: local;' || true)
if [ -z "$BAD" ]; then
    pass "every edge into verification requires vars.VERIFICATION: local"
else
    fail "edges into verification without vars.VERIFICATION: local: [$BAD]"
fi
BAD=$(printf '%s\n' "$TWINS" | grep -v 'vars.VERIFICATION: hosted-ci;' || true)
if [ -z "$BAD" ]; then
    pass "every edge into verification_deferred requires vars.VERIFICATION: hosted-ci"
else
    fail "edges into verification_deferred without vars.VERIFICATION: hosted-ci: [$BAD]"
fi

# Each twin is its edge with only the target and the VERIFICATION value changed.
WANT=$(printf '%s\n' "$INTO" | sed -e 's/|verification|/|verification_deferred|/' \
    -e 's/vars\.VERIFICATION: local;/vars.VERIFICATION: hosted-ci;/' | sort)
GOT=$(printf '%s\n' "$TWINS" | sort)
if [ "$WANT" = "$GOT" ]; then
    pass "each twin carries its edge's state and conditions, with hosted-ci for local"
else
    fail "twins differ from their edges: want [$WANT], got [$GOT]"
fi
WANT=$(printf '%s\n' "$INTO" | sed -e 's/|verification|/|verification_plan|/' \
    -e 's/vars\.VERIFICATION: local;/vars.VERIFICATION: auto;/' | sort)
GOT=$(printf '%s\n' "$AUTOS" | sort)
if [ "$WANT" = "$GOT" ]; then
    pass "each auto twin carries its edge's state and conditions, with auto for local, into verification_plan"
else
    fail "auto twins differ from their edges: want [$WANT], got [$GOT]"
fi
for src in issue_type_routing light_review review qa_validation; do
    n=$(printf '%s\n' "$TWINS" | awk -F'|' -v s="$src" '$1 == s' | grep -c .)
    if [ "$n" -ge 1 ]; then pass "$src has $n edge(s) into verification_deferred"; else fail "$src has no edge into verification_deferred"; fi
done

# verification_plan routes on its gate alone, in the tick that arrives: 0 to
# verification_deferred, and 1, 2 and -1 (anything it could not decide) to
# local verification.
PLAN_EDGES=$(printf '%s\n' "$EDGES" | awk -F'|' '$1 == "verification_plan" { print $2 "|" $3 }' | sort)
WANT_PLAN=$(printf '%s\n' \
    "verification_deferred|gates.verification_route_plan.exit_code: 0;" \
    "verification|gates.verification_route_plan.exit_code: 1;" \
    "verification|gates.verification_route_plan.exit_code: 2;" \
    "verification|gates.verification_route_plan.exit_code: -1;" | sort)
eq "verification_plan routes 0 to verification_deferred and 1, 2, -1 to verification" "$WANT_PLAN" "$PLAN_EDGES"
PLAN_BLOCK=$(extract_state verification_plan)
if grep -qE '^    (default_action|accepts):' <<<"$PLAN_BLOCK"; then
    fail "verification_plan declares an action or accepts evidence; it must only route"
else
    pass "verification_plan has no action and takes no evidence"
fi
case "$(gate_command verification_plan verification_route_plan)" in
    *'/run-verification.sh" --plan --session "{{SESSION_NAME}}" --shared-branch "{{SHARED_BRANCH}}"') pass "verification_route_plan runs run-verification.sh --plan" ;;
    *) fail "verification_route_plan's command: [$(gate_command verification_plan verification_route_plan)]" ;;
esac

# ci_monitor's green edge needs the twin re-check, and its failure is the one
# edge from ci_monitor into verification, which writes verification_twin_gone.
GREEN=$(printf '%s\n' "$EDGES" | awk -F'|' '$1 == "ci_monitor" && $2 == "ci_pass_counting"')
case "$GREEN" in
    *"gates.hosted_twins.exit_code: 0;"*) pass "ci_monitor's green edge needs hosted_twins" ;;
    *) fail "ci_monitor's green edge does not need hosted_twins: [$GREEN]" ;;
esac
BACK=$(printf '%s\n' "$EDGES" | awk -F'|' '$1 == "ci_monitor" && $2 == "verification"')
case "$BACK" in
    *"gates.ci_passing.exit_code: 0;"*"gates.hosted_twins.exit_code: 1;"*) pass "ci_monitor's twin edge goes to verification on green CI with a twin gone" ;;
    *) fail "ci_monitor's edge into verification: [$BACK]" ;;
esac
MONITOR=$(extract_state ci_monitor)
case "$MONITOR" in
    *'
          verification_twin_gone: "'*) pass "ci_monitor's twin edge writes verification_twin_gone" ;;
    *) fail "ci_monitor's twin edge does not write verification_twin_gone" ;;
esac
case "$(gate_command ci_monitor hosted_twins)" in
    'test "{{VERIFICATION}}" = auto || exit 0; '*'run-verification.sh" --twins --session "{{SESSION_NAME}}"') pass "hosted_twins runs --twins for an auto run only" ;;
    *) fail "hosted_twins's command: [$(gate_command ci_monitor hosted_twins)]" ;;
esac

V_BLOCK=$(extract_var VERIFICATION)
R_BLOCK=$(extract_var VERIFICATION_DEFERRAL_REASON)
grep -q '^    default: auto$' <<<"$V_BLOCK" && pass "VERIFICATION defaults to auto" \
    || fail "VERIFICATION does not default to auto: [$V_BLOCK]"
grep -q '^    values: \[auto, local, hosted-ci\]$' <<<"$V_BLOCK" && pass "VERIFICATION takes auto, local or hosted-ci" \
    || fail "VERIFICATION's values are not [auto, local, hosted-ci]: [$V_BLOCK]"
[ -n "$R_BLOCK" ] && pass "VERIFICATION_DEFERRAL_REASON is declared" || fail "VERIFICATION_DEFERRAL_REASON is not declared"
for b in "$V_BLOCK" "$R_BLOCK"; do
    if grep -q 'rebind:' <<<"$b"; then
        fail "a deferral variable is rebindable: [$(head -n 1 <<<"$b")]"
    else
        pass "$(head -n 1 <<<"$b" | tr -d ' :') is fixed at init (no rebind)"
    fi
done

# A partial delivery (#1736) is declared at init the same way: DELIVERY and
# its reason, neither rebindable, the reason under the deferral reason's
# pattern.
D_BLOCK=$(extract_var DELIVERY)
DR_BLOCK=$(extract_var DELIVERY_REASON)
[ -n "$D_BLOCK" ] && pass "DELIVERY is declared" || fail "DELIVERY is not declared"
[ -n "$DR_BLOCK" ] && pass "DELIVERY_REASON is declared" || fail "DELIVERY_REASON is not declared"
grep -q '^    default: closes$' <<<"$D_BLOCK" && pass "DELIVERY defaults to closes" \
    || fail "DELIVERY does not default to closes: [$D_BLOCK]"
grep -q '^    values: \[closes, partial\]$' <<<"$D_BLOCK" && pass "DELIVERY takes closes or partial" \
    || fail "DELIVERY's values are not [closes, partial]: [$D_BLOCK]"
for b in "$D_BLOCK" "$DR_BLOCK"; do
    grep -q '^    required: false$' <<<"$b" && pass "$(head -n 1 <<<"$b" | tr -d ' :') is not required" \
        || fail "a delivery variable is required: [$(head -n 1 <<<"$b")]"
    if grep -q 'rebind:' <<<"$b"; then
        fail "a delivery variable is rebindable: [$(head -n 1 <<<"$b")]"
    else
        pass "$(head -n 1 <<<"$b" | tr -d ' :') is fixed at init (no rebind)"
    fi
done
R_PATTERN=$(grep '^    pattern: ' <<<"$R_BLOCK")
DR_PATTERN=$(grep '^    pattern: ' <<<"$DR_BLOCK")
if [ -n "$DR_PATTERN" ] && [ "$DR_PATTERN" = "$R_PATTERN" ]; then
    pass "DELIVERY_REASON has VERIFICATION_DEFERRAL_REASON's pattern ($DR_PATTERN)"
else
    fail "DELIVERY_REASON's pattern [$DR_PATTERN] is not VERIFICATION_DEFERRAL_REASON's [$R_PATTERN]"
fi

DEFERRED=$(extract_state verification_deferred)
[ -n "$DEFERRED" ] || { echo "verification_deferred not found in $TEMPLATE" >&2; exit 2; }
if grep -qE '^    (default_action|gates):' <<<"$DEFERRED"; then
    fail "verification_deferred declares an action or gates; it must run nothing"
else
    pass "verification_deferred has no action and no gates"
fi
# shellcheck disable=SC2016 # the {{...}} is koto's, matched literally
grep -q '^          verification_deferral: "{{VERIFICATION_DEFERRAL_REASON}}"$' <<<"$DEFERRED" \
    && pass "verification_deferred writes the reason to context" \
    || fail "verification_deferred does not write verification_deferral"
# An auto run's hosted resolution writes its own reason, the one
# run-verification.sh prints and pr_creation's record gate looks for.
SCRIPT_REASON=$(sed -n 's/^HOSTED_REASON="\(.*\)"$/\1/p' "$SCRIPT_DIR/run-verification.sh")
[ -n "$SCRIPT_REASON" ] || fail "run-verification.sh declares no HOSTED_REASON"
grep -qF "          verification_deferral: \"$SCRIPT_REASON\"" <<<"$DEFERRED" \
    && pass "verification_deferred writes an auto run's reason, run-verification.sh's HOSTED_REASON" \
    || fail "verification_deferred does not write [$SCRIPT_REASON] for an auto run"
case "$(gate_command pr_creation verification_deferral_recorded)" in
    *"--deferral-record --reason \"$SCRIPT_REASON\""*) pass "the record gate checks an auto run's body for the same reason" ;;
    *) fail "the record gate does not check for [$SCRIPT_REASON]" ;;
esac
AUTO_EDGE=$(printf '%s\n' "$EDGES" | awk -F'|' '$1 == "verification_deferred" && $3 ~ /vars.VERIFICATION: auto;/')
[ -n "$AUTO_EDGE" ] && pass "verification_deferred has an edge for an auto run" \
    || fail "verification_deferred has no edge on vars.VERIFICATION: auto"

CREATED_EDGE=$(printf '%s\n' "$EDGES" | awk -F'|' '$1 == "pr_creation" && $2 == "ci_monitor"')
case "$CREATED_EDGE" in
    *"gates.verification_deferral_recorded.exit_code: 0;"*)
        pass "pr_creation's created edge needs verification_deferral_recorded" ;;
    *) fail "pr_creation's created edge does not need the record gate: [$CREATED_EDGE]" ;;
esac

# --- 2. the record gate's command ----------------------------------------------------

echo "--- the record gate"

FAKE_ROOT="$WORKDIR/plugin"
RC_DIR="$WORKDIR/rc"
LOG="$WORKDIR/calls.log"
mkdir -p "$FAKE_ROOT/skills/work-on/scripts" "$RC_DIR"
: > "$LOG"
# Each fake logs `<script> <args>`, prints $RC_DIR/<script><first-argument>.out
# when there is one, and exits with the number in
# $RC_DIR/<script><first-argument>, else $RC_DIR/<script>, else 0.
for s in panel-scope.sh review-level.sh has-commits.sh run-verification.sh check-verification.sh \
         check-pr-output.sh find-anchor-plan.sh red-first.sh test-change.sh; do
    cat > "$FAKE_ROOT/skills/work-on/scripts/$s" <<EOF
#!/usr/bin/env bash
printf '%s\n' "$s \$*" >> "$LOG"
if [ -f "$RC_DIR/$s\${1-}.out" ]; then cat "$RC_DIR/$s\${1-}.out"; fi
rc=0
if [ -f "$RC_DIR/$s\${1-}" ]; then rc=\$(cat "$RC_DIR/$s\${1-}")
elif [ -f "$RC_DIR/$s" ]; then rc=\$(cat "$RC_DIR/$s"); fi
exit "\$rc"
EOF
done
# panel-scope.sh's --escalated defaults to 1 when no answer is set: the light
# seat didn't escalate.
cat > "$FAKE_ROOT/skills/work-on/scripts/panel-scope.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "panel-scope.sh \$*" >> "$LOG"
case "\${1-}" in --escalated) rc=1 ;; *) rc=0 ;; esac
if [ -f "$RC_DIR/panel-scope.sh\${1-}" ]; then rc=\$(cat "$RC_DIR/panel-scope.sh\${1-}")
elif [ -f "$RC_DIR/panel-scope.sh" ]; then rc=\$(cat "$RC_DIR/panel-scope.sh"); fi
exit "\$rc"
EOF
# review-level.sh's `level` defaults to 11 and its `audit` to 1 when no answer
# is set: a light run that isn't audited, so light_review's passed routes are
# the ones these cases take.
cat > "$FAKE_ROOT/skills/work-on/scripts/review-level.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "review-level.sh \$*" >> "$LOG"
case "\${1-}" in level) rc=11 ;; audit) rc=1 ;; *) rc=0 ;; esac
if [ -f "$RC_DIR/review-level.sh\${1-}" ]; then rc=\$(cat "$RC_DIR/review-level.sh\${1-}")
elif [ -f "$RC_DIR/review-level.sh" ]; then rc=\$(cat "$RC_DIR/review-level.sh"); fi
exit "\$rc"
EOF
cat > "$FAKE_ROOT/skills/work-on/scripts/session-role.sh" <<'EOF'
#!/usr/bin/env bash
echo root
EOF
chmod +x "$FAKE_ROOT"/skills/work-on/scripts/*
set_rc() { printf '%s\n' "$2" > "$RC_DIR/$1"; }
set_out() { printf '%s\n' "$2" > "$RC_DIR/$1.out"; }
reset_rc() { rm -f "$RC_DIR"/*; }
calls() { grep -c -- "^$1" "$LOG" 2>/dev/null || true; }

RECORD_CMD=$(gate_command pr_creation verification_deferral_recorded)
[ -n "$RECORD_CMD" ] || { echo "could not extract verification_deferral_recorded's command" >&2; exit 2; }
# render <verification> <reason>: the command as koto would hand it to sh.
render() {
    local c="$RECORD_CMD"
    c=${c//\{\{PLUGIN_ROOT\}\}/$FAKE_ROOT}
    c=${c//\{\{VERIFICATION_DEFERRAL_REASON\}\}/$2}
    c=${c//\{\{VERIFICATION\}\}/$1}
    printf '%s' "$c"
}

reset_rc; : > "$LOG"
set_rc check-pr-output.sh--deferral-record 1
sh -c "$(render local "")" >/dev/null 2>&1
eq "local: the record gate passes" 0 "$?"
eq "local: the record gate never starts check-pr-output.sh" 0 "$(calls check-pr-output.sh)"

reset_rc; : > "$LOG"
sh -c "$(render hosted-ci "$REASON")" >/dev/null 2>&1
eq "hosted-ci, body records it: the record gate passes" 0 "$?"
eq "hosted-ci: the gate passes the reason to --deferral-record" \
    "check-pr-output.sh --deferral-record --reason $REASON" "$(cat "$LOG")"

reset_rc; : > "$LOG"
set_rc check-pr-output.sh--deferral-record 1
sh -c "$(render hosted-ci "$REASON")" >/dev/null 2>&1
eq "hosted-ci, body lacks it: the record gate fails" 1 "$?"

# auto: --resolved says whether verification_plan resolved the run to hosted
# CI; only then is the body checked, for the hosted resolution's own reason.
reset_rc; : > "$LOG"
set_out run-verification.sh--resolved hosted-ci
sh -c "$(render auto "")" >/dev/null 2>&1
eq "auto resolved to hosted-ci, body records it: the record gate passes" 0 "$?"
eq "auto resolved to hosted-ci: the gate asks --resolved, then checks the hosted reason" \
    "run-verification.sh --resolved --session {{SESSION_NAME}}
check-pr-output.sh --deferral-record --reason $SCRIPT_REASON" "$(cat "$LOG")"
set_rc check-pr-output.sh--deferral-record 1
sh -c "$(render auto "")" >/dev/null 2>&1
eq "auto resolved to hosted-ci, body lacks it: the record gate fails" 1 "$?"

reset_rc; : > "$LOG"
set_out run-verification.sh--resolved local
set_rc check-pr-output.sh--deferral-record 1
sh -c "$(render auto "")" >/dev/null 2>&1
eq "auto resolved to local: the record gate passes" 0 "$?"
eq "auto resolved to local: check-pr-output.sh is never started" 0 "$(calls check-pr-output.sh)"

reset_rc; : > "$LOG"
set_rc run-verification.sh--resolved 2
sh -c "$(render auto "")" >/dev/null 2>&1
eq "auto, --resolved can't answer: the record gate holds at 2" 2 "$?"
eq "auto, --resolved can't answer: check-pr-output.sh is never started" 0 "$(calls check-pr-output.sh)"

# --- 3. engine -----------------------------------------------------------------------

if ! command -v koto >/dev/null 2>&1; then
    echo
    echo "SKIP: koto not on PATH -- the engine cases did not run"
    echo
    echo "verification-deferral_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
fi

echo "--- the routes"

# Sessions and requests live under a temporary HOME, out of the developer's
# $HOME/.koto.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"
# No decider for any case here, whatever the host has set: issue_type_routing's
# issue_type then takes the submitted answer, and no case reaches the network.
unset KOTO_DECIDER KOTO_DECIDER_API_KEY KOTO_DECIDER_ENDPOINT
REPO="$WORKDIR/repo"
mkdir -p "$REPO"
(cd "$REPO" && git init -q . && git config user.email t@example.com && git config user.name t \
    && git commit -q --allow-empty -m "chore: init" && git checkout -q -b feature/x) >/dev/null 2>&1 \
    || { echo "could not create the fixture repository" >&2; exit 2; }

# stub_block <block> <gate=exit>...: the named gates' commands replaced by
# fixed exits, keyed on the gate name above each command.
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

# build <file> <name> <initial> <shipped states> <gate=exit>...: a fixture
# whose `start` routes into <initial> (taking `go` evidence when <initial> is
# pr_creation, so the leg cases can tick into it), holding the shipped blocks
# of <shipped states> with the named gates stubbed, the shipped variables the
# blocks read, and a stub terminal for every other target.
build() {
    local file="$1" name="$2" initial="$3" shipped="$4"; shift 4
    local s blocks="" t stubs=""
    for s in $shipped; do
        case "$s" in done|done_already_complete|done_blocked) continue ;; esac
        blocks="$blocks$(stub_block "$(extract_state "$s")" "$@")
"
    done
    for t in $(printf '%s\n' "$blocks" | awk '/^      - target:/ { print $3 }' | sort -u); do
        case " $shipped " in *" $t "*) ;; *) stubs="$stubs $t" ;; esac
    done
    {
        printf '%s\n' '---' "name: $name" 'version: "1.0"' \
            'description: Fixture driving the verification deferral through shipped work-on states.' \
            'initial_state: start' 'variables:' \
            '  ISSUE_NUMBER:' '    description: issue' '    required: false' \
            '  ISSUE_REPO:' '    description: issue repository' '    required: false' \
            '  PLUGIN_ROOT:' '    description: plugin root' '    required: false' \
            '  SHARED_BRANCH:' '    description: shared branch' '    required: false' \
            '  PLAN_DOC:' '    description: plan' '    required: false' \
            '  REVIEW_LEVEL:' '    description: review level' '    required: false' \
            '    pattern: ^(light|standard|full)?$'
        extract_var VERIFICATION
        extract_var VERIFICATION_DEFERRAL_REASON
        # issue_type_routing's code_route gate passes the type hint.
        extract_var ISSUE_TYPE
        printf '%s\n' '  PROBE_NEAR_RULE:' '    description: the probe_near capture pr_creation reads' '    required: false'
        printf '%s\n' 'states:' '  start:'
        if [ "$initial" = pr_creation ]; then
            printf '%s\n' '    accepts:' '      go:' '        type: enum' '        values: [pr]' \
                '        required: true' '    transitions:' '      - target: pr_creation' \
                '        when:' '          go: pr'
        elif [ "$initial" = issue_type_routing ]; then
            # issue_type's decider reads context.md and changed_paths.txt, and
            # koto compiles a decider input only when some context-exists gate
            # in the template checks its key. In work-on.md context_injection
            # and changed_paths_record hold those gates; here start does, with
            # gate names of its own and the keys the decider names, so the
            # shipped issue_type_routing block goes in unchanged.
            printf '%s\n' '    gates:' '      issue_context:' '        type: context-exists' \
                '        key: context.md' '      changed_paths:' '        type: context-exists' \
                '        key: changed_paths.txt' '    transitions:' '      - target: issue_type_routing' \
                '        when:' '          gates.issue_context.exists: true' \
                '          gates.changed_paths.exists: true'
        else
            printf '%s\n' '    transitions:' "      - target: $initial"
        fi
        printf '%s' "$blocks"
        for s in "done" done_already_complete done_blocked; do
            case " $shipped " in *" $s "*) extract_state "$s" ;; esac
        done
        for t in $stubs; do
            printf '%s\n' "  $t:" '    terminal: true'
        done
        printf '%s\n' '---' '' '## start' '' 'Start.'
        for s in $shipped $stubs; do
            printf '%s\n' '' "## $s" '' 'Stub.'
        done
    } > "$file"
}

N=0
# run_entry <source state> <var>...: builds a fixture from the shipped
# <source state>, verification, verification_deferred, pass_counting and
# done_blocked (its fix_green and tests_counted gates fakes that pass, as for
# a change with no edited test), inits it with the given --var arguments and ticks once. Sets S, STATE and
# RESP; the fakes' calls are in $LOG.
run_entry() {
    local src="$1"; shift
    N=$((N + 1))
    local dir="$WORKDIR/e$N"
    S="vd-$N"
    mkdir -p "$dir"
    build "$dir/fixture.md" verification-deferral-fixture "$src" \
        "$src verification_plan verification verification_deferred pass_counting done_blocked"
    : > "$LOG"
    if ! (cd "$REPO" && koto init "$S" --template "$dir/fixture.md" --var PLUGIN_ROOT="$FAKE_ROOT" "$@") \
        >"$dir/init.out" 2>&1; then
        STATE="init-failed: $(head -c 300 "$dir/init.out")"; RESP=""; return
    fi
    RESP=$(cd "$REPO" && koto next "$S" --no-cleanup 2>&1)
    STATE=$( (cd "$REPO" && koto status "$S" 2>/dev/null) | jq -r '.current_state // "none"')
}
ctx() { (cd "$REPO" && koto context get "$S" "$1" 2>/dev/null); }

reset_rc
for src in qa_validation light_review review; do
    extra=""
    [ "$src" = review ] && extra="--var REVIEW_LEVEL=standard"
    # shellcheck disable=SC2086 # $extra is empty or one --var pair
    run_entry "$src" $extra --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=$REASON"
    eq "$src, hosted-ci with a reason: reaches finalization" finalization "$STATE"
    eq "$src, hosted-ci: the reason is in context as verification_deferral" "$REASON" "$(ctx verification_deferral)"
    eq "$src, hosted-ci: run-verification.sh is never called" 0 "$(calls run-verification.sh)"
    eq "$src, hosted-ci: check-verification.sh is never called" 0 "$(calls check-verification.sh)"
    if [ "$(calls "red-first.sh check-green")" -ge 1 ]; then
        pass "$src, hosted-ci: the deferral is counted at pass_counting"
    else
        fail "$src, hosted-ci: pass_counting's fix_green never ran"
    fi

    # shellcheck disable=SC2086
    run_entry "$src" $extra --var VERIFICATION=local
    eq "$src, local: reaches finalization through verification" finalization "$STATE"
    n=$(calls "run-verification.sh --start")
    if [ "$n" -ge 1 ]; then
        pass "$src, local: verification's action starts the map"
    else
        fail "$src, local: run-verification.sh --start was not called"
    fi
    eq "$src, local: the auto resolution never runs" 0 "$(calls "run-verification.sh --plan")"
    if (cd "$REPO" && koto context exists "$S" verification_deferral) >/dev/null 2>&1; then
        fail "$src, local: verification_deferral is in context"
    else
        pass "$src, local: nothing records a deferral"
    fi

    # The default, auto, resolved to hosted CI: verification_deferred in the
    # same tick, with the hosted resolution's reason, and no map started.
    set_rc run-verification.sh--plan 0
    # shellcheck disable=SC2086
    run_entry "$src" $extra
    eq "$src, auto resolved to hosted-ci: reaches finalization in one tick" finalization "$STATE"
    eq "$src, auto resolved to hosted-ci: verification_route_plan ran --plan" 1 "$(calls "run-verification.sh --plan --session $S --shared-branch ")"
    eq "$src, auto resolved to hosted-ci: the hosted reason is in context as verification_deferral" \
        "$SCRIPT_REASON" "$(ctx verification_deferral)"
    eq "$src, auto resolved to hosted-ci: the map is never started" 0 "$(calls "run-verification.sh --start")"
    eq "$src, auto resolved to hosted-ci: check-verification.sh is never called" 0 "$(calls check-verification.sh)"

    # auto resolved to local (1), or undecided (2): local verification.
    for rc in 1 2; do
        set_rc run-verification.sh--plan "$rc"
        # shellcheck disable=SC2086
        run_entry "$src" $extra --var VERIFICATION=auto
        eq "$src, auto, --plan exit $rc: reaches finalization through verification" finalization "$STATE"
        if [ "$(calls "run-verification.sh --start")" -ge 1 ]; then
            pass "$src, auto, --plan exit $rc: verification's action starts the map"
        else
            fail "$src, auto, --plan exit $rc: run-verification.sh --start was not called"
        fi
        if (cd "$REPO" && koto context exists "$S" verification_deferral) >/dev/null 2>&1; then
            fail "$src, auto, --plan exit $rc: verification_deferral is in context"
        else
            pass "$src, auto, --plan exit $rc: nothing records a deferral"
        fi
    done
    reset_rc
done

# run_routing <issue_type> <var>...: builds a fixture from the shipped
# issue_type_routing, verification, verification_deferred, pass_counting and
# done_blocked,
# inits it with the given --var arguments, adds the two keys issue_type's
# decider reads, ticks into issue_type_routing and submits <issue_type>. Sets
# S, ROUTED (the state after the first tick) and STATE; the fakes' calls are
# in $LOG.
run_routing() {
    local type="$1"; shift
    N=$((N + 1))
    local dir="$WORKDIR/r$N"
    S="vd-route-$N"
    mkdir -p "$dir"
    build "$dir/fixture.md" verification-deferral-fixture issue_type_routing \
        "issue_type_routing verification_plan verification verification_deferred pass_counting done_blocked"
    : > "$LOG"
    if ! (cd "$REPO" && koto init "$S" --template "$dir/fixture.md" --var PLUGIN_ROOT="$FAKE_ROOT" "$@") \
        >"$dir/init.out" 2>&1; then
        ROUTED=""; STATE="init-failed: $(head -c 300 "$dir/init.out")"; return
    fi
    printf '# Issue\n' | (cd "$REPO" && koto context add "$S" context.md) >/dev/null 2>&1
    printf 'M\tguide.md\n' | (cd "$REPO" && koto context add "$S" changed_paths.txt) >/dev/null 2>&1
    (cd "$REPO" && koto next "$S" --no-cleanup) >"$dir/tick1.out" 2>&1
    ROUTED=$( (cd "$REPO" && koto status "$S" 2>/dev/null) | jq -r '.current_state // "none"')
    (cd "$REPO" && koto next "$S" --no-cleanup --with-data "{\"issue_type\":\"$type\"}") >"$dir/tick2.out" 2>&1
    STATE=$( (cd "$REPO" && koto status "$S" 2>/dev/null) | jq -r '.current_state // "none"')
}

# The docs and task edges out of issue_type_routing, driven through koto like
# the panels' edges above. docs also needs has_commits, which the fake passes.
# verification_deferral is written only by verification_deferred's
# context_assignments, so finding it shows the run passed through that state.
reset_rc
for type in docs task; do
    run_routing "$type" --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=$REASON"
    eq "$type, hosted-ci: the fixture waits at issue_type_routing for the type" issue_type_routing "$ROUTED"
    eq "$type, hosted-ci with a reason: reaches finalization" finalization "$STATE"
    eq "$type, hosted-ci: the reason is in context as verification_deferral" "$REASON" "$(ctx verification_deferral)"
    eq "$type, hosted-ci: run-verification.sh is never called" 0 "$(calls run-verification.sh)"
    eq "$type, hosted-ci: check-verification.sh is never called" 0 "$(calls check-verification.sh)"

    run_routing "$type" --var VERIFICATION=local
    eq "$type, local: reaches finalization through verification" finalization "$STATE"
    n=$(calls "run-verification.sh --start")
    if [ "$n" -ge 1 ]; then
        pass "$type, local: verification's action starts the map"
    else
        fail "$type, local: run-verification.sh --start was not called"
    fi
    eq "$type, local: the auto resolution never runs" 0 "$(calls "run-verification.sh --plan")"
    if (cd "$REPO" && koto context exists "$S" verification_deferral) >/dev/null 2>&1; then
        fail "$type, local: verification_deferral is in context"
    else
        pass "$type, local: nothing records a deferral"
    fi

    set_rc run-verification.sh--plan 0
    run_routing "$type"
    eq "$type, auto resolved to hosted-ci: reaches finalization" finalization "$STATE"
    eq "$type, auto resolved to hosted-ci: the hosted reason is in context" "$SCRIPT_REASON" "$(ctx verification_deferral)"
    eq "$type, auto resolved to hosted-ci: the map is never started" 0 "$(calls "run-verification.sh --start")"
    set_rc run-verification.sh--plan 1
    run_routing "$type"
    eq "$type, auto resolved to local: reaches finalization through verification" finalization "$STATE"
    if [ "$(calls "run-verification.sh --start")" -ge 1 ]; then
        pass "$type, auto resolved to local: verification's action starts the map"
    else
        fail "$type, auto resolved to local: run-verification.sh --start was not called"
    fi
    reset_rc
done

# The docs twin keeps has_commits: with no commit a deferred docs run holds at
# issue_type_routing, as a local one does, and still runs nothing.
set_rc has-commits.sh 1
run_routing docs --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=$REASON"
eq "docs, hosted-ci, no commits: holds at issue_type_routing" issue_type_routing "$STATE"
eq "docs, hosted-ci, no commits: run-verification.sh is never called" 0 "$(calls run-verification.sh)"
reset_rc

run_entry qa_validation --var VERIFICATION=hosted-ci
eq "hosted-ci with no reason: ends at done_blocked" done_blocked "$STATE"
case "$(ctx failure_reason)" in
    *"without VERIFICATION_DEFERRAL_REASON"*) pass "hosted-ci with no reason: failure_reason says why" ;;
    *) fail "hosted-ci with no reason: failure_reason is [$(ctx failure_reason)]" ;;
esac
eq "hosted-ci with no reason: run-verification.sh is never called" 0 "$(calls run-verification.sh)"

# An auto run with a VERIFICATION_DEFERRAL_REASON still writes the hosted
# resolution's reason: the stated one is for hosted-ci only.
set_rc run-verification.sh--plan 0
run_entry qa_validation --var VERIFICATION=auto --var "VERIFICATION_DEFERRAL_REASON=$REASON"
eq "auto with a stated reason, resolved to hosted-ci: reaches finalization" finalization "$STATE"
eq "auto with a stated reason: the hosted resolution's reason is recorded" "$SCRIPT_REASON" "$(ctx verification_deferral)"
reset_rc

run_entry qa_validation --var VERIFICATION=sometimes
case "$STATE" in init-failed*) pass "koto refuses VERIFICATION=sometimes" ;; *) fail "VERIFICATION=sometimes was accepted ($STATE)" ;; esac
run_entry qa_validation --var VERIFICATION=hosted-ci --var VERIFICATION_DEFERRAL_REASON=--verification-reason
case "$STATE" in init-failed*) pass "koto refuses a bare flag as the reason" ;; *) fail "a bare flag was accepted as the reason ($STATE)" ;; esac

# --- a child on /execute's shared branch (#1017) ---------------------------------------
#
# /execute gives every child task VERIFICATION, VERIFICATION_DEFERRAL_REASON
# and SHARED_BRANCH. The shared branch changes nothing on the way in: the
# child defers and records the reason like a standalone run. On the way out it
# opens no pull request: `pr_status: shared` goes to done without the record
# gate, so the reason reaches the shared PR only through /execute's
# pr_finalization (skills/execute/scripts/shared-deferral-record_test.sh).

echo "--- a deferred child on a shared branch"

reset_rc
run_entry qa_validation --var SHARED_BRANCH=impl/shared --var VERIFICATION=hosted-ci \
    --var "VERIFICATION_DEFERRAL_REASON=$REASON"
eq "shared branch, hosted-ci: reaches finalization" finalization "$STATE"
eq "shared branch, hosted-ci: the reason is in context as verification_deferral" "$REASON" "$(ctx verification_deferral)"
eq "shared branch, hosted-ci: run-verification.sh is never called" 0 "$(calls run-verification.sh)"

N=$((N + 1))
DIR="$WORKDIR/s$N"
S="vd-shared-$N"
mkdir -p "$DIR"
build "$DIR/fixture.md" verification-deferral-fixture pr_creation \
    "pr_creation done done_blocked" closing_keyword=0
reset_rc
set_rc check-pr-output.sh--deferral-record 1
if (cd "$REPO" && koto init "$S" --template "$DIR/fixture.md" --var PLUGIN_ROOT="$FAKE_ROOT" \
    --var SHARED_BRANCH=impl/shared --var VERIFICATION=hosted-ci \
    --var "VERIFICATION_DEFERRAL_REASON=$REASON") >"$DIR/init.out" 2>&1; then
    : > "$LOG"
    (cd "$REPO" && koto next "$S" --no-cleanup --with-data '{"go":"pr"}') >"$DIR/tick1.out" 2>&1
    (cd "$REPO" && koto next "$S" --no-cleanup --with-data '{"pr_status":"shared"}') >"$DIR/tick2.out" 2>&1
    STATE=$( (cd "$REPO" && koto status "$S" 2>/dev/null) | jq -r '.current_state // "none"')
    # The record gate answers 1 (no record in any body) and the child still
    # ends: the shared edge doesn't read it, which is why the shared PR needs
    # a check of its own.
    eq "shared branch, hosted-ci, no record anywhere: pr_status shared ends the child at done" "done" "$STATE"
else
    fail "shared branch pr_creation fixture: koto init: $(head -c 300 "$DIR/init.out")"
fi
reset_rc

# --- ci_monitor's twin re-check --------------------------------------------------------
#
# An auto run that resolved to hosted CI meets hosted_twins on ci_monitor's
# green edge. A twin gone from the default branch's map (--twins exit 1)
# sends it to local verification in the same tick, writing
# verification_twin_gone; every other run takes the green edge as before.

echo "--- ci_monitor's twin re-check"

# run_monitor <var>...: a fixture from the shipped ci_monitor onward, CI green
# and the pull request clean, ticked once. Sets S and STATE.
run_monitor() {
    N=$((N + 1))
    local dir="$WORKDIR/m$N"
    S="vd-mon-$N"
    mkdir -p "$dir"
    build "$dir/fixture.md" verification-deferral-fixture ci_monitor \
        "ci_monitor verification_plan verification verification_deferred pass_counting done_blocked" \
        ci_passing=0 merge_state_clean=0
    : > "$LOG"
    if ! (cd "$REPO" && koto init "$S" --template "$dir/fixture.md" --var PLUGIN_ROOT="$FAKE_ROOT" "$@") \
        >"$dir/init.out" 2>&1; then
        STATE="init-failed: $(head -c 300 "$dir/init.out")"; return
    fi
    (cd "$REPO" && koto next "$S" --no-cleanup) >"$dir/tick.out" 2>&1
    STATE=$( (cd "$REPO" && koto status "$S" 2>/dev/null) | jq -r '.current_state // "none"')
}

reset_rc
set_rc run-verification.sh--twins 1
run_monitor
eq "auto, a twin gone at ci_monitor: back through local verification to finalization in one tick" finalization "$STATE"
eq "auto, a twin gone: --twins ran" 1 "$(calls "run-verification.sh --twins")"
if [ "$(calls "run-verification.sh --start")" -ge 1 ]; then
    pass "auto, a twin gone: verification's action starts the map"
else
    fail "auto, a twin gone: run-verification.sh --start was not called"
fi
case "$(ctx verification_twin_gone)" in
    *"verifies locally"*) pass "auto, a twin gone: verification_twin_gone is in context" ;;
    *) fail "auto, a twin gone: verification_twin_gone is [$(ctx verification_twin_gone)]" ;;
esac

set_rc run-verification.sh--twins 0
run_monitor
eq "auto, every twin still there: the green edge goes to ci_pass_counting" ci_pass_counting "$STATE"
eq "auto, every twin still there: the map is never started" 0 "$(calls "run-verification.sh --start")"

set_rc run-verification.sh--twins 2
run_monitor
eq "auto, --twins can't answer: the green path holds at ci_monitor" ci_monitor "$STATE"

set_rc run-verification.sh--twins 1
run_monitor --var VERIFICATION=local
eq "local, --twins would fail: the green edge goes to ci_pass_counting" ci_pass_counting "$STATE"
eq "local: --twins is never started" 0 "$(calls "run-verification.sh --twins")"
run_monitor --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=$REASON"
eq "hosted-ci, --twins would fail: the green edge goes to ci_pass_counting" ci_pass_counting "$STATE"
eq "hosted-ci: --twins is never started" 0 "$(calls "run-verification.sh --twins")"
reset_rc

# --- the leg -------------------------------------------------------------------------

if ! koto init --help 2>/dev/null | grep -q -- '--koto-leg'; then
    echo
    echo "SKIP: koto has no --koto-leg -- the leg cases did not run"
    echo
    echo "verification-deferral_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
fi

echo "--- a deferred run's pull request"

URL=https://github.com/o/r/pull/7
CREATED="{\"pr_status\":\"created\",\"pr_url\":\"$URL\"}"

# open_leg <var>...: a fixture named work-on.md (koto admits a session to a
# leg by its template's file name) from the shipped pr_creation onward,
# opened on a new request's `work-on` leg. Sets S, REQ and DIR.
open_leg() {
    N=$((N + 1))
    DIR="$WORKDIR/l$N"
    S="vd-leg-$N"
    mkdir -p "$DIR"
    build "$DIR/work-on.md" work-on pr_creation \
        "pr_creation ci_monitor ci_pass_counting cascade_entry done done_already_complete done_blocked" \
        closing_keyword=0 ci_passing=0 merge_state_clean=0
    REQ=$(cd "$REPO" && koto request create \
        --with-data '{"legs":[{"name":"work-on","role":"work-on","template":"work-on.md","inputs":{}}]}' \
        --requested-by test --coordinator-of-record test 2>"$DIR/req.err" | jq -r '.request_id // empty')
    [ -n "$REQ" ] || { fail "case $N: koto request create: $(head -c 300 "$DIR/req.err")"; return 1; }
    (cd "$REPO" && koto init "$S" --template "$DIR/work-on.md" --var PLUGIN_ROOT="$FAKE_ROOT" \
        --var ISSUE_NUMBER=7 "$@" --koto-leg "$REQ:work-on") >"$DIR/init.out" 2>&1 \
        || { fail "case $N: koto init: $(head -c 300 "$DIR/init.out")"; return 1; }
}
tick() { (cd "$REPO" && koto next "$S" --no-cleanup "$@") >"$DIR/tick.out" 2>&1; }
state() { (cd "$REPO" && koto status "$S" 2>/dev/null) | jq -r '.current_state // "none"'; }
leg() { (cd "$REPO" && koto request get "$REQ" 2>/dev/null) | jq -c "(.request // .) | .legs[\"work-on\"]$1"; }

reset_rc
set_rc find-anchor-plan.sh 1
set_rc check-pr-output.sh--deferral-record 1
if open_leg --var VERIFICATION=hosted-ci --var "VERIFICATION_DEFERRAL_REASON=$REASON"; then
    : > "$LOG"
    tick --with-data '{"go":"pr"}'
    tick --with-data "$CREATED"
    eq "deferred, body without the record: pr_status created holds at pr_creation" pr_creation "$(state)"
    # The gate runs on every evaluation of pr_creation, the entering tick
    # included, so it was asked at least once.
    n=$(calls "check-pr-output.sh --deferral-record --reason $REASON")
    if [ "$n" -ge 1 ]; then
        pass "deferred: the gate asked check-pr-output.sh about this run's reason"
    else
        fail "deferred: check-pr-output.sh --deferral-record --reason was not called: [$(cat "$LOG")]"
    fi
    set_rc check-pr-output.sh--deferral-record 0
    tick --with-data "$CREATED"
    eq "deferred, body with the record: the run ends at done" "done" "$(state)"
    eq "deferred: the leg records done" '"done"' "$(leg .result_final_state)"
    eq "deferred: the leg's status is success" '"success"' "$(leg .result.status)"
    eq "deferred: the leg's payload carries the pull request" "\"$URL\"" "$(leg .result.payload.pr)"
fi

reset_rc
set_rc find-anchor-plan.sh 1
set_rc check-pr-output.sh--deferral-record 1
if open_leg --var VERIFICATION=local; then
    : > "$LOG"
    tick --with-data '{"go":"pr"}'
    tick --with-data "$CREATED"
    eq "local: created with CI green ends at done" "done" "$(state)"
    eq "local: --deferral-record is never called" 0 "$(calls "check-pr-output.sh --deferral-record")"
    eq "local: the leg's payload carries the pull request" "\"$URL\"" "$(leg .result.payload.pr)"
fi

# auto, resolved to hosted CI: the body must record the hosted resolution's
# reason, as a hosted-ci run's must record its stated one.
reset_rc
set_rc find-anchor-plan.sh 1
set_out run-verification.sh--resolved hosted-ci
set_rc check-pr-output.sh--deferral-record 1
if open_leg; then
    : > "$LOG"
    tick --with-data '{"go":"pr"}'
    tick --with-data "$CREATED"
    eq "auto resolved to hosted-ci, body without the record: pr_status created holds at pr_creation" pr_creation "$(state)"
    if [ "$(calls "check-pr-output.sh --deferral-record --reason $SCRIPT_REASON")" -ge 1 ]; then
        pass "auto resolved to hosted-ci: the gate asked about the hosted resolution's reason"
    else
        fail "auto resolved to hosted-ci: --deferral-record --reason [$SCRIPT_REASON] was not called: [$(cat "$LOG")]"
    fi
    set_rc check-pr-output.sh--deferral-record 0
    tick --with-data "$CREATED"
    eq "auto resolved to hosted-ci, body with the record: the run ends at done" "done" "$(state)"
fi

# auto, resolved to local: no record is asked for.
reset_rc
set_rc find-anchor-plan.sh 1
set_out run-verification.sh--resolved local
set_rc check-pr-output.sh--deferral-record 1
if open_leg; then
    : > "$LOG"
    tick --with-data '{"go":"pr"}'
    tick --with-data "$CREATED"
    eq "auto resolved to local: created with CI green ends at done" "done" "$(state)"
    eq "auto resolved to local: --deferral-record is never called" 0 "$(calls "check-pr-output.sh --deferral-record")"
fi
reset_rc

echo
echo "verification-deferral_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

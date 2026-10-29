#!/usr/bin/env bash
# offload-canary-routes_test.sh -- does work-on.md send each run through the
# live offload canary the way DESIGN-offload-live-canary.md says,
# driven through real `koto next` calls?
#
#   A. The shipped template, walked from `koto init` through analysis to
#      review_level_choice, against a scratch plugin root whose registry marks
#      pr-body/no-heading-in-part1 eligible: the first tick's entry evidence
#      still reaches entry; a withheld run enters offload_arm_withheld once and
#      a preloaded run offload_arm_preloaded once, read from koto's run journal
#      (the state_entered events koto exports); an off, a
#      shared-branch and a failed-assignment run (script missing, not
#      executable, or failing) enter neither and still reach
#      review_level_choice; a bad switch value and an attach with a different
#      one are refused; a rewound run keeps its group.
#   B. The shipped pr_creation directive, rendered after the shipped canary
#      states in a fixture template: the preloaded, off, shared and failed runs
#      render it byte for byte alike, and a withheld run's directive, the
#      phase-6-pr.md it points to and the conformance text it names carry
#      neither PB4's first anchor nor the rule id.
#
# The engine parts skip, loudly, when koto is absent (the bash 3.2 floor leg
# has no koto).
#
# Usage: offload-canary-routes_test.sh
# Exit codes: 0 all pass (or the engine parts skipped), 1 any failed, 2 the
# harness could not run.

set -u
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
REAL_ROOT=$(cd "$SKILL_DIR/../.." && pwd)
RULE=pr-body/no-heading-in-part1

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
finish() {
    echo
    echo "offload-canary-routes_test: $PASS_COUNT passed, $FAIL_COUNT failed"
    [ "$FAIL_COUNT" -eq 0 ]
    exit $?
}

[ -f "$TEMPLATE" ] || { echo "template not found: $TEMPLATE" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq is required to run this suite" >&2; exit 2; }

# --- the marker state names are this template's alone ------------------------------

others=$(grep -rlE '^  (offload_canary|offload_arm_withheld|offload_arm_preloaded):$' "$REAL_ROOT/skills" \
    --include='*.md' | grep -v "koto-templates/work-on.md$" | grep -v 'mermaid' || true)
[ -z "$others" ] && pass "no template but work-on.md defines the canary's state names" \
    || fail "other templates define the canary's state names: $others"

if ! command -v koto >/dev/null 2>&1; then
    echo "SKIP: koto is not on PATH; the engine parts did not run"
    finish
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/offload-canary-routes.XXXXXX") || exit 1
T=$(cd -P "$T" && pwd -P) || exit 1
cleanup() { case "${T:-}" in */offload-canary-routes.*) rm -rf "$T" ;; esac; return 0; }
ktg_on_exit cleanup

export KOTO_SESSIONS_BASE="$T/sessions"
export XDG_CONFIG_HOME="$T/xdg"
mkdir -p "$KOTO_SESSIONS_BASE" "$XDG_CONFIG_HOME/shirabe"
echo on > "$XDG_CONFIG_HOME/shirabe/offload-canary"
JOURNAL="$KOTO_SESSIONS_BASE/_run_journal.jsonl"

REPO="$T/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init

# make_root <dir> <script: real|missing|noexec|failing>: a plugin root with the
# real scripts the walk to review_level_choice runs, whose registry marks the
# rule eligible, and whose offload-canary.sh is as named.
make_root() {
    mkdir -p "$1/references" "$1/skills/work-on"
    cp -R "$REAL_ROOT/scripts" "$1/scripts"
    cp -R "$SCRIPT_DIR" "$1/skills/work-on/scripts"
    cp "$REAL_ROOT/references/pr-body-conformance.md" "$1/references/pr-body-conformance.md"
    jq --arg id "$RULE" '(.rules[] | select(.id == $id) | .withhold) = "eligible"' \
        "$REAL_ROOT/references/rule-registry.json" > "$1/references/rule-registry.json"
    local c="$1/skills/work-on/scripts/offload-canary.sh"
    case "$2" in
        real) ;;
        noexec) chmod 644 "$c" ;;
        failing) printf '#!/bin/sh\nexit 7\n' > "$c"; chmod 755 "$c" ;;
        missing) rm -f "$c" ;;
    esac
}
ROOT="$T/root"; make_root "$ROOT" real

# entered <session> <state>: how many state_entered events the journal holds.
entered() {
    [ -f "$JOURNAL" ] || { echo 0; return; }
    jq -c --arg s "$1" --arg st "$2" 'select(.kind == "state_entered" and .session == $s and ."koto.state" == $st)' \
        "$JOURNAL" | grep -c .
}

S=0
# start <template> <root> [--var K=V]...: init a session and tick once; the
# session name in SESS, the response in RESP.
start() {
    local tpl=$1 root=$2; shift 2
    S=$((S + 1)); SESS="canary-$S"
    (cd "$REPO" && koto init "$SESS" --template "$tpl" --var PLUGIN_ROOT="$root" \
        --var ARTIFACT_PREFIX="task_canary_$S" "$@" >/dev/null 2>"$T/init.err") || { RESP=""; return 1; }
    RESP=$(cd "$REPO" && koto next "$SESS" --no-cleanup 2>/dev/null)
}
state_of() { printf '%s' "$RESP" | jq -r '.state // empty'; }
submit() { RESP=$(cd "$REPO" && koto next "$SESS" --no-cleanup --with-data "$1" 2>/dev/null); }

# walk <root> [--var K=V]...: init the shipped template and walk it to
# analysis's plan_ready, the edge into the canary, the way
# finalization-shape_test.sh does: the context overrides skip the gates that
# read a real issue, and staleness_check routes on its own unavailable check.
# ENTRY_NEXT holds the state the first tick's entry evidence reached.
walk() {
    local root=$1; shift
    S=$((S + 1)); SESS="canary-$S"
    (cd "$REPO" && koto init "$SESS" --template "$TEMPLATE" --var PLUGIN_ROOT="$root" \
        --var ISSUE_NUMBER=42 --var ARTIFACT_PREFIX="issue_42_$S" "$@" >/dev/null 2>"$T/init.err") \
        || { RESP=""; return 1; }
    submit '{"mode":"issue_backed","issue_number":"42"}'
    ENTRY_NEXT=$(state_of)
    submit '{"status":"override"}'
    submit '{"status":"override"}'
    printf 'plan\n' | koto context add "$SESS" plan.md >/dev/null 2>&1
    submit '{"plan_outcome":"plan_ready"}'
}

# --- A. the shipped template ---------------------------------------------------------

WS=""; PS=""; tries=0
while { [ -z "$WS" ] || [ -z "$PS" ]; } && [ $tries -lt 40 ]; do
    walk "$ROOT" || break
    if [ "$(entered "$SESS" offload_arm_withheld)" -eq 1 ]; then [ -n "$WS" ] || { WS=$SESS; WSTATE=$(state_of); }; fi
    if [ "$(entered "$SESS" offload_arm_preloaded)" -eq 1 ]; then [ -n "$PS" ] || { PS=$SESS; PSTATE=$(state_of); }; fi
    tries=$((tries + 1))
done
[ "$ENTRY_NEXT" = context_injection ] && pass "the first tick's entry evidence still reaches entry and routes on" \
    || fail "the first tick's entry evidence landed at [$ENTRY_NEXT]"
if [ -n "$WS" ] && [ -n "$PS" ]; then
    pass "runs land in both groups within $tries walks"
else
    fail "after $tries walks: withheld [$WS] preloaded [$PS], last state [$(state_of)]; init: $(cat "$T/init.err")"
    finish
fi
[ "$(entered "$WS" offload_arm_preloaded)" -eq 0 ] && [ "$(entered "$PS" offload_arm_withheld)" -eq 0 ] \
    && pass "a withheld run never enters the preloaded marker, and the reverse" \
    || fail "a run entered both marker states"
[ "$WSTATE" = review_level_choice ] && [ "$PSTATE" = review_level_choice ] \
    && pass "both runs go on to review_level_choice" || fail "a canary run stopped at [$WSTATE]/[$PSTATE]"

neither() { # neither <label>: the last walked session took no group and reached review_level_choice
    if [ "$(entered "$SESS" offload_arm_withheld)" -eq 0 ] && [ "$(entered "$SESS" offload_arm_preloaded)" -eq 0 ] \
        && [ "$(entered "$SESS" offload_canary)" -eq 1 ] && [ "$(state_of)" = review_level_choice ]; then
        pass "$1: through offload_canary, no marker state, and the run is at review_level_choice"
    else
        fail "$1: state [$(state_of)], markers $(entered "$SESS" offload_arm_withheld)/$(entered "$SESS" offload_arm_preloaded)"
    fi
}
walk "$ROOT" --var OFFLOAD_CANARY=off; neither "OFFLOAD_CANARY=off"
walk "$ROOT" --var SHARED_BRANCH=impl/plan; neither "a shared branch"
for kind in missing noexec failing; do
    R="$T/root-$kind"; make_root "$R" "$kind"
    walk "$R"; neither "an assignment script that is $kind"
done

if walk "$ROOT" --var OFFLOAD_CANARY=maybe; then
    fail "OFFLOAD_CANARY=maybe was accepted"
else
    pass "koto init refuses OFFLOAD_CANARY=maybe"
fi
if (cd "$REPO" && koto init "$WS" --template "$TEMPLATE" --var PLUGIN_ROOT="$ROOT" \
        --var ISSUE_NUMBER=42 --var ARTIFACT_PREFIX=issue_42_ws --var OFFLOAD_CANARY=off --attach-live >/dev/null 2>&1); then
    fail "an attach with a different OFFLOAD_CANARY was accepted"
else
    pass "an attach with a different OFFLOAD_CANARY is refused, so a run keeps its group"
fi

# A rewound withheld run keeps its group. koto rewind steps back one state, to
# probe_draw now that the probe's states sit between the canary and
# review_level_choice; the next tick runs on from there and never enters the
# other marker, and the recorded group is unchanged.
(cd "$REPO" && koto rewind "$WS" >/dev/null 2>&1)
SESS=$WS
RESP=$(cd "$REPO" && koto next "$WS" --no-cleanup 2>/dev/null)
WSDIR=$(cd "$REPO" && koto session dir "$WS" 2>/dev/null)
if [ "$(state_of)" = review_level_choice ] && [ "$(entered "$WS" probe_draw)" -ge 2 ] \
    && [ "$(entered "$WS" offload_arm_preloaded)" -eq 0 ] \
    && [ "$(cat "$WSDIR/pr-rules/sample" 2>/dev/null)" = withheld ]; then
    pass "a rewound withheld run keeps its group: back through probe_draw, never the other marker"
else
    fail "rewind: state [$(state_of)], probe_draw $(entered "$WS" probe_draw), markers $(entered "$WS" offload_arm_withheld)/$(entered "$WS" offload_arm_preloaded), sample [$(cat "$WSDIR/pr-rules/sample" 2>/dev/null)]"
fi

# --- B. the pr_creation directive --------------------------------------------------------

# extract_state <name>: the state's block from the template's frontmatter.
extract_state() {
    awk -v want="  $1:" '
        /^states:/ { s = 1; next }
        s && $0 == want { on = 1; print; next }
        on && /^  [a-z_]+:$/ { exit }
        on && /^---$/ { exit }
        on && /^  # / { exit }
        on { print }' "$TEMPLATE"
}
# section <name>: the state's directive body, after its heading.
section() {
    awk -v want="## $1" '$0 == want { on = 1; next } on && /^## / { exit } on { print }' "$TEMPLATE"
}

# The fixture starts at offload_canary, unlike the shipped template (which
# starts at entry and reaches it from analysis), so the shipped canary states
# can be run straight into a stub state that renders the shipped pr_creation
# body. The stub is named review_level_choice because that is where the
# extracted states route.
BODY=$(section pr_creation)
FIX="$T/fixture.md"
{
    echo "---"
    echo "name: offload-canary-fixture"
    echo "version: \"1.0\""
    echo "description: the shipped canary states before the shipped pr_creation directive"
    echo "initial_state: offload_canary"
    echo "variables:"
    for v in PLUGIN_ROOT ARTIFACT_PREFIX SHARED_BRANCH BRANCH ISSUE_NUMBER PROBE_NEAR_RULE; do
        echo "  $v:"
        echo "    description: fixture"
        echo "    required: false"
    done
    for v in OFFLOAD_CANARY PROBE; do
        echo "  $v:"
        echo "    description: fixture"
        echo "    required: false"
        echo "    default: \"on\""
        echo "    values: [\"on\", \"off\"]"
    done
    echo "states:"
    # The canary's states route on through the rule-distance probe's, which
    # this host hasn't opted in to, so every run passes through them unarmed.
    for st in offload_canary offload_arm_withheld offload_arm_preloaded probe_draw \
        probe_arm_near probe_arm_far probe_arm_far_redeliver; do
        extract_state $st
    done
    echo "  review_level_choice:"
    echo "    accepts:"
    echo "      ok:"
    echo "        type: enum"
    echo "        values: [\"yes\"]"
    echo "        required: true"
    echo "    transitions:"
    echo "      - target: done"
    echo "        when:"
    echo "          ok: \"yes\""
    echo "  done:"
    echo "    terminal: true"
    echo "---"
    echo
    echo "## offload_canary"; echo; echo "Assigning."; echo
    echo "## offload_arm_withheld"; echo; echo "Withheld."; echo
    echo "## offload_arm_preloaded"; echo; echo "Preloaded."; echo
    for st in probe_draw probe_arm_near probe_arm_far probe_arm_far_redeliver; do
        echo "## $st"; echo; echo "Probe."; echo
    done
    echo "## review_level_choice"
    printf '%s\n' "$BODY"
    echo
    echo "## done"; echo; echo "Done."
} > "$FIX"
if ! koto template compile "$FIX" >/dev/null 2>"$T/compile.err"; then
    fail "the fixture built from the shipped states does not compile: $(cat "$T/compile.err")"
    finish
fi

# directive <root> [--var K=V]...: sets D to the rendered stub directive, the
# plugin root replaced by a placeholder so runs from different roots compare.
# It sets a variable rather than printing, because start's session counter
# must survive the call, which a command substitution would throw away.
directive() {
    local root=$1; shift
    if start "$FIX" "$root" --var BRANCH=feature/x "$@"; then
        D=$(printf '%s' "$RESP" | jq -r '.directive // ""' | sed "s#$root#ROOT#g")
    else
        D="INIT-FAILED: $(cat "$T/init.err")"
    fi
}
FWS=""; FPS=""; WDIR=""; PDIR=""; tries=0
while { [ -z "$FWS" ] || [ -z "$FPS" ]; } && [ $tries -lt 40 ]; do
    directive "$ROOT"
    if [ "$(entered "$SESS" offload_arm_withheld)" -eq 1 ]; then [ -n "$FWS" ] || { FWS=$SESS; WDIR=$D; }; fi
    if [ "$(entered "$SESS" offload_arm_preloaded)" -eq 1 ]; then [ -n "$FPS" ] || { FPS=$SESS; PDIR=$D; }; fi
    tries=$((tries + 1))
done
directive "$ROOT" --var OFFLOAD_CANARY=off; OFF=$D
directive "$ROOT" --var SHARED_BRANCH=impl/plan; SHARED=$D
directive "$T/root-failing"; FAILED=$D
directive "$T/root-missing"; MISSING=$D

grep -qF 'ROOT/references/pr-body-conformance.md' <<<"$OFF" \
    && pass "a canary-off run's pr_creation directive names the real conformance text" \
    || fail "the off directive does not name the real conformance text: $OFF"
same=1
for d in "$PDIR" "$SHARED" "$FAILED" "$MISSING"; do [ "$d" = "$OFF" ] || same=0; done
[ $same -eq 1 ] && pass "preloaded, shared, failed and missing-script runs render pr_creation byte for byte as a canary-off run" \
    || fail "a pr_creation directive differs from the canary-off one"

RENDERED=$(printf '%s' "$WDIR" | grep -oE "$KOTO_SESSIONS_BASE/[^ \`]*/pr-rules/pr-body-conformance\.md")
RENDERED=${RENDERED%%$'\n'*}
FIRST=$(jq -r --arg id "$RULE" '.rules[] | select(.id == $id) | .text.first' "$REAL_ROOT/references/rule-registry.json")
if [ -n "$RENDERED" ] && [ -f "$RENDERED" ]; then
    pass "a withheld run's pr_creation directive names its session's rendering"
    leak=0
    for f in "$RENDERED" "$SKILL_DIR/references/phases/phase-6-pr.md"; do
        grep -qF -- "$FIRST" "$f" && leak=1
        grep -qF -- "$RULE" "$f" && leak=1
    done
    grep -qF -- "$FIRST" <<<"$WDIR" && leak=1
    grep -qF -- "$RULE" <<<"$WDIR" && leak=1
    [ $leak -eq 0 ] && pass "the withheld directive, phase-6-pr.md and the rendering carry neither PB4's first anchor nor $RULE" \
        || fail "PB4 leaks into the withheld run's instructions"
else
    fail "the withheld directive names no rendering: $WDIR"
fi

finish

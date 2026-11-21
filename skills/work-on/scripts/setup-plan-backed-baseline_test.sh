#!/usr/bin/env bash
# setup-plan-backed-baseline_test.sh -- setup_plan_backed lets a plan-backed
# run reach analysis without baseline.md only on a shared branch
# Part of the work-on skill
#
# Issue 1916: setup_plan_backed checks baseline_exists (the baseline.md
# context key), but only its completed edge read the gate. A run off a shared
# branch could submit status override with no baseline.md and reach analysis,
# and the state also kept an unconditional edge to analysis. This suite pins
# the fixed shape:
#
#   (a) override with no baseline.md holds at setup_plan_backed, and the
#       response names baseline_exists as the blocking condition;
#   (b) completed with no baseline.md holds the same way;
#   (c) once baseline.md is recorded, override and completed both reach
#       analysis;
#   (d) with SHARED_BRANCH set the state is skipped on arrival, straight to
#       analysis, with no baseline.md and nothing submitted;
#   (e) in the compiled template the state has no unconditional edge, and
#       every edge to analysis taken off a shared branch requires
#       gates.baseline_exists.exists: true. Counts and the skip_if are checked
#       too, so the structural check cannot pass on an empty edge list.
#
# Cases (a) to (d) drive the shipped work-on.md through real koto runs in git
# fixtures with a bare origin; (e) compiles it and reads the result with jq.
# Without koto, jq or git on PATH the suite prints a SKIP line and runs
# nothing. Every run isolates HOME under a temp directory.
#
# Usage: bash skills/work-on/scripts/setup-plan-backed-baseline_test.sh
#
# Exit codes:
#   0 -- every case passed, or the suite was skipped
#   1 -- one or more cases failed

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
TEMPLATE="$SCRIPT_DIR/../koto-templates/work-on.md"
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

if ! command -v git >/dev/null 2>&1 || ! command -v koto >/dev/null 2>&1 \
    || ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: koto, jq or git not on PATH -- no case ran"
    exit 0
fi

WORKDIR=$(mktemp -d) || exit 1
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
ktg_on_exit cleanup

export HOME="$WORKDIR/home"
export XDG_STATE_HOME="$WORKDIR/state"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
git config --global user.email t@example.com
git config --global user.name t
git config --global init.defaultBranch main
git config --global advice.detachedHead false

# koto validates --var values against ^[a-zA-Z0-9._/:@ \-]*$; a checkout path
# may hold other characters (a plus sign, say), so the plugin root is reached
# through a clean symlink when it does. analysis runs
# record-changed-paths.sh from this root on entry, so it must be the real one.
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        PLUGIN_ROOT="$WORKDIR/plugin"
        ;;
esac

# --- fixtures and helpers ------------------------------------------------------
#
# fixture <name>: a bare origin with a seeded main, and a `repo` clone on
# branch impl/<name>, so on_feature_branch passes and analysis's action finds
# a merge-base with origin.

FX=""
fixture() {
    FX="$WORKDIR/fx-$1"
    mkdir -p "$FX"
    (
        cd "$FX" || exit 1
        git init -q --bare origin.git
        git clone -q origin.git seed 2>/dev/null
        cd seed || exit 1
        printf 'readme\n' > README.md
        git add -A && git commit -q -m init && git push -q origin main
        cd .. && git clone -q origin.git repo 2>/dev/null
        cd repo && git checkout -q -b "impl/$1"
    ) >/dev/null 2>&1
}

RESP=""
STATE=""
# tick <name> [<data>]: one koto next in the current fixture's repo.
tick() {
    if [ -n "${2:-}" ]; then
        RESP=$(cd "$FX/repo" && koto next "$1" --with-data "$2" --no-cleanup 2>/dev/null)
    else
        RESP=$(cd "$FX/repo" && koto next "$1" --no-cleanup 2>/dev/null)
    fi
    STATE=$(printf '%s' "$RESP" | jq -r '.state // empty' 2>/dev/null)
}

ctx() { (cd "$FX/repo" && koto context "$@") 2>/dev/null; }

# blocked_on <gate>: the last response names <gate> as a blocking condition.
blocked_on() {
    printf '%s' "$RESP" | jq -e --arg n "$1" '[.blocking_conditions[]?.name] | index($n) != null' >/dev/null 2>&1
}

# to_setup <name> [<shared branch>]: init, then the plan-backed github path to
# setup_plan_backed. No ISSUE_SOURCE var, so entry's skip_if does not fire;
# context.md is recorded so plan_context_injection's github edge is taken.
to_setup() {
    if [ -n "${2:-}" ]; then
        (cd "$FX/repo" && koto init "$1" --template "$TEMPLATE" --var ARTIFACT_PREFIX=issue_7 --var ISSUE_NUMBER=7 --var SHARED_BRANCH="$2" --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1)
    else
        (cd "$FX/repo" && koto init "$1" --template "$TEMPLATE" --var ARTIFACT_PREFIX=issue_7 --var ISSUE_NUMBER=7 --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1)
    fi
    tick "$1" '{"mode":"plan_backed","issue_source":"github"}'
    printf 'context\n' | ctx add "$1" context.md
    tick "$1" '{"status":"completed","issue_source":"github"}'
}

# --- (a) override with no baseline.md, off a shared branch -----------------------

fixture a
to_setup a
A_HELD=0
if [ "$STATE" != setup_plan_backed ]; then
    fail "(a) precondition: did not reach setup_plan_backed [$STATE]; baseline_exists not checked"
else
    tick a '{"status":"override"}'
    if [ "$STATE" = setup_plan_backed ] && blocked_on baseline_exists; then
        A_HELD=1
        pass "(a) status override with no baseline.md holds at setup_plan_backed naming baseline_exists"
    else
        fail "setup_plan_backed: status override with no baseline.md reached [$STATE]; baseline_exists did not hold the state"
    fi
fi

# --- (b) completed with no baseline.md, on a feature branch -----------------------

fixture b
to_setup b
if [ "$STATE" != setup_plan_backed ]; then
    fail "(b) precondition: did not reach setup_plan_backed [$STATE]; baseline_exists not checked"
else
    tick b '{"status":"completed"}'
    if [ "$STATE" = setup_plan_backed ] && blocked_on baseline_exists; then
        pass "(b) status completed with no baseline.md holds at setup_plan_backed naming baseline_exists"
    else
        fail "(b) setup_plan_backed: status completed with no baseline.md reached [$STATE]; baseline_exists did not hold the state"
    fi
fi

# --- (c) baseline.md recorded, then override or completed --------------------------
#
# The override half continues the run (a) held, which is the way out a held run
# takes: record baseline.md, then submit again. When (a) did not hold, that run
# is already past the state, so a fresh one stands in for it.

if [ "$A_HELD" -eq 1 ]; then
    FX="$WORKDIR/fx-a"
    C_NAME=a
    C_LABEL="the held run from (a)"
else
    fixture c-ovr
    to_setup c-ovr
    C_NAME=c-ovr
    C_LABEL="a fresh run, since (a) did not hold"
fi
if [ "$C_NAME" = c-ovr ] && [ "$STATE" != setup_plan_backed ]; then
    fail "(c) precondition: did not reach setup_plan_backed [$STATE]"
else
    printf 'baseline\n' | ctx add "$C_NAME" baseline.md
    tick "$C_NAME" '{"status":"override"}'
    if [ "$STATE" = analysis ]; then
        pass "(c) baseline.md recorded, then status override reaches analysis ($C_LABEL)"
    else
        fail "(c) baseline.md recorded, then status override reached [$STATE] ($C_LABEL)"
    fi
fi

fixture c
to_setup c
if [ "$STATE" != setup_plan_backed ]; then
    fail "(c) precondition: did not reach setup_plan_backed [$STATE]"
else
    printf 'baseline\n' | ctx add c baseline.md
    tick c '{"status":"completed"}'
    if [ "$STATE" = analysis ]; then
        pass "(c) baseline.md recorded, then status completed reaches analysis"
    else
        fail "(c) baseline.md recorded, then status completed reached [$STATE]"
    fi
fi

# --- (d) SHARED_BRANCH set: the state is skipped on arrival -------------------------

fixture d
to_setup d impl/d
if [ "$STATE" = analysis ]; then
    pass "(d) SHARED_BRANCH set: setup_plan_backed is skipped to analysis with no baseline.md"
else
    fail "(d) SHARED_BRANCH set: the run stopped at [$STATE] instead of analysis"
fi

# --- (e) structural: the compiled template ------------------------------------------

COMPILED=$(koto template compile "$TEMPLATE" 2>/dev/null | tail -1)
if [ -z "$COMPILED" ] || [ ! -f "$COMPILED" ]; then
    fail "(e) could not compile $TEMPLATE; baseline_exists edges not checked"
else
    n=$(jq -r '.states.setup_plan_backed.transitions | length' "$COMPILED" 2>/dev/null)
    if [ -z "$n" ] || [ "$n" = null ] || [ "$n" -eq 0 ]; then
        fail "(e) setup_plan_backed has no transitions in the compiled template [$n]; baseline_exists edges not checked"
    else
        uncond=$(jq -r '[.states.setup_plan_backed.transitions[]
            | select(.when == null or .when == {}) | .target] | join(" ")' "$COMPILED" 2>/dev/null)
        if [ -z "$uncond" ]; then
            pass "(e) setup_plan_backed has no unconditional edge"
        else
            fail "setup_plan_backed has an unconditional edge (to [$uncond]); baseline_exists can be bypassed"
        fi

        ungated=$(jq -r '[.states.setup_plan_backed.transitions[]
            | select(.target == "analysis")
            | select((.when // {})["vars.SHARED_BRANCH"].is_set == false)
            | select((.when // {})["gates.baseline_exists.exists"] != true)
            | ((.when // {}).status // "no status")] | join(" ")' "$COMPILED" 2>/dev/null)
        if [ -z "$ungated" ]; then
            pass "(e) every edge to analysis off a shared branch requires gates.baseline_exists.exists: true"
        else
            fail "setup_plan_backed edges to analysis without baseline_exists: [$ungated]"
        fi

        # Non-vacuity: the edges the check above walked are exactly the
        # completed and override ones, and the shared-branch edge is alone.
        unset_statuses=$(jq -r '[.states.setup_plan_backed.transitions[]
            | select(.target == "analysis")
            | select((.when // {})["vars.SHARED_BRANCH"].is_set == false)
            | ((.when // {}).status // "no status")] | sort | join(" ")' "$COMPILED" 2>/dev/null)
        if [ "$unset_statuses" = "completed override" ]; then
            pass "(e) exactly two edges to analysis off a shared branch: completed and override"
        else
            fail "(e) edges to analysis off a shared branch are [$unset_statuses], want [completed override]; the baseline_exists check would be vacuous"
        fi
        shared=$(jq -r '[.states.setup_plan_backed.transitions[]
            | select(.target == "analysis")
            | select((.when // {}) == {"vars.SHARED_BRANCH": {"is_set": true}})] | length' "$COMPILED" 2>/dev/null)
        if [ "$shared" = 1 ]; then
            pass "(e) exactly one edge to analysis on a shared branch, keyed on SHARED_BRANCH alone"
        else
            fail "(e) shared-branch edges to analysis: [$shared], want 1; the edge exempt from baseline_exists changed"
        fi
        if jq -e '.states.setup_plan_backed.skip_if == {"vars.SHARED_BRANCH": {"is_set": true}}' "$COMPILED" >/dev/null 2>&1; then
            pass "(e) the skip_if is unchanged: vars.SHARED_BRANCH is_set true"
        else
            fail "(e) setup_plan_backed's skip_if changed: $(jq -c '.states.setup_plan_backed.skip_if' "$COMPILED" 2>/dev/null); the baseline_exists exemption is no longer SHARED_BRANCH alone"
        fi
    fi
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

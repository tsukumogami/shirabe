#!/usr/bin/env bash
# finalization-shape_test.sh — a malformed summary or pre-PR record holds the run
# at finalization instead of ending it at pre_pr_evidence.
#
# summary.md and pre_pr.md are written at `finalization`, and pre_pr_evidence
# checks them and sends a failure to done_blocked, so a record the agent could
# have fixed in one edit cost a full re-entry. The same gates
# (summary_shape, the two referent checks, and commit_convention, the walk over
# every commit since impl_base) now sit on finalization's ready_for_pr edge and
# on deferral_approval's approved edge, where a failure matches no edge and the
# state holds with the failing gate named (case 9 for the commit walk).
#
# The cases drive the SHIPPED template, walked from entry to finalization the
# way retry-clearing_test.sh walks it:
#
#   a correct record advances to pre_pr_evidence            (case 1)
#   a missing heading holds, names summary_shape, and a fix in place advances
#                                                           (case 2)
#   a wrong pre_pr.md key form, a referent naming nothing (a commit from
#   another branch, a diagram path never written), or no pre_pr.md, holds and
#   names its gate                                          (cases 3, 4)
#   an approved deferral holds on a bad shape; the escape edges stay open
#                                                           (cases 5, 6)
#   the early gates are identical to the backstop's, every copy of a referent
#   gate runs the existence check, and the backstop still routes a failure to
#   done_blocked                                            (cases 7, 8)
#
# pre-pr-evidence_test.sh drives the backstop itself.
#
# Usage: finalization-shape_test.sh
# Exit codes: 0 all pass, or koto/git/jq absent and the run skipped; 1 any failed.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"
PLUGIN_ROOT=$(cd "$SKILL_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

command -v koto >/dev/null 2>&1 || { echo "SKIP: koto not on PATH -- no case ran"; exit 0; }
command -v git  >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }
command -v jq   >/dev/null 2>&1 || { echo "SKIP: jq not on PATH -- no case ran"; exit 0; }
[ -f "$TEMPLATE" ] || { echo "FAIL: template not found at $TEMPLATE" >&2; exit 1; }

WORKDIR=$(mktemp -d)
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
trap cleanup EXIT

# Keep every session out of the developer's real $HOME/.koto, and the
# verification runner's results out of the developer's state directory.
export HOME="$WORKDIR/home"
export XDG_STATE_HOME="$WORKDIR/state"
mkdir -p "$HOME"

# koto rejects a variable value outside ^[a-zA-Z0-9._/:@ \-]*$, so a checkout
# under such a path is reached through a symlink (as in retry-clearing_test.sh).
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        PLUGIN_ROOT="$WORKDIR/plugin"
        ;;
esac

# scrutiny gates on commits since impl_base, the commit analysis records as the
# run's start. The fixture's `feat: work` commit stands for the run's own
# implementation, so each walk records impl_base as the commit before it (see
# to_finalization). The referent gates need real objects: HEAD for a good
# cleanup_commit, a commit on another branch for a bad one.
#
# `verification` runs the verification map committed at the merge-base with
# main, so the init commit carries one whose only command is `true`.
REPO="$WORKDIR/repo"
mkdir -p "$REPO"
(
    cd "$REPO" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    mkdir -p .claude/shirabe-extensions
    printf '%s\n' '{"schema": "shirabe-verification-map/v1", "commands": {"ok": {"run": ["true"]}}, "entries": [], "default": ["ok"]}' \
        > .claude/shirabe-extensions/verification-map.json
    git add .claude
    git commit -q -m init
    git checkout -q -b other
    git commit -q --allow-empty -m "side work"
    git checkout -q main
    git checkout -q -b impl/finalization-shape
    echo work > f.txt
    git add f.txt
    git commit -q -m "feat: work"
) >/dev/null 2>&1
cd "$REPO" || exit 1
HEAD_SHA=$(git rev-parse HEAD)
BASE_SHA=$(git rev-parse HEAD~1)
OTHER_SHA=$(git rev-parse other)

NEXT_RESPONSE=""
NEXT_STATE=""
submit() {
    NEXT_RESPONSE=$(koto next "$1" --with-data "$2" 2>/dev/null)
    NEXT_STATE=$(printf '%s' "$NEXT_RESPONSE" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
}
put() { printf '%s\n' "$3" | koto context add "$1" "$2" >/dev/null 2>&1; }
names_gate() { printf '%s' "$NEXT_RESPONSE" | grep -q "\"name\":\"$1\""; }

# pass_panel <session> <panel> <seat>...: records a clean round for every seat
# and ticks with nothing submitted. A panel's pass is its <panel>_verdict gate,
# read from the verdict ledger; there is no passed value to submit.
pass_panel() {
    local s="$1" p="$2" seat
    shift 2
    for seat in "$@"; do printf '{"seat":"%s","findings":[]}\n' "$seat"; done | jq -s . > "$WORKDIR/round.json"
    "$PLUGIN_ROOT/skills/work-on/scripts/panel-scope.sh" --record "$p" "$s" "$WORKDIR/round.json" >/dev/null \
        || fail "$s: panel-scope.sh --record $p failed"
    NEXT_RESPONSE=$(koto next "$s" 2>/dev/null)
    NEXT_STATE=$(printf '%s' "$NEXT_RESPONSE" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
}

# The verification state starts the map's commands on entry and its poll gate
# waits for the result, re-checking every 15 seconds. Starting the runner for
# the session before the tick that enters the state, and waiting for its
# result, lets that tick settle at once.
prestart_verification() {
    local rv="$PLUGIN_ROOT/skills/work-on/scripts/run-verification.sh" f i=0
    "$rv" --start --session "$1" >/dev/null 2>&1
    f=$("$rv" --locate --session "$1" 2>/dev/null | sed -n 3p)
    while [ -n "$f" ] && [ ! -f "$f" ] && [ "$i" -lt 200 ]; do sleep 0.1; i=$((i + 1)); done
}

# Walk a fresh session to finalization. The overrides skip gates that read a
# real GitHub issue and a real baseline.
to_finalization() {
    koto init "$1" --template "$TEMPLATE" \
        --var ARTIFACT_PREFIX=issue_42 \
        --var ISSUE_NUMBER=42 \
        --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1
    submit "$1" '{"mode":"issue_backed","issue_number":"42"}'
    submit "$1" '{"status":"override"}'
    # staleness_check routes on its own gate: the fixture has no GitHub
    # remote, so the check is unavailable (exit 3) and the run is at analysis.
    submit "$1" '{"status":"override"}'
    put "$1" plan.md plan
    submit "$1" '{"plan_outcome":"plan_ready"}'
    # analysis recorded HEAD, which already carries the fixture's work commit;
    # the run's base is the commit before it.
    put "$1" impl_base "$BASE_SHA"
    # The full review level keeps all three panels on the path.
    "$PLUGIN_ROOT/skills/work-on/scripts/review-level.sh" set "$1" full >/dev/null 2>&1
    koto next "$1" --no-cleanup >/dev/null 2>&1
    submit "$1" '{"implementation_status":"complete"}'
    [ "$NEXT_STATE" = issue_type_routing ] && submit "$1" '{"issue_type":"code"}'
    pass_panel "$1" scrutiny completeness justification intent
    pass_panel "$1" review pragmatic architect maintainer
    prestart_verification "$1"
    pass_panel "$1" qa tester
    [ "$NEXT_STATE" = finalization ] || { fail "$1: could not reach finalization; landed at [$NEXT_STATE]"; return 1; }
}

GOOD_SUMMARY='# Summary

## What Was Implemented
A thing.

## Changes Made
- `f.txt`: added'
NO_HEADING_SUMMARY='# Summary

## What Was Implemented
A thing, and a list of files under a heading the gate does not read.

## Changes
- `f.txt`: added'
GOOD_PREPR="cleanup_commit: $HEAD_SHA
design_diagram: not-applicable: no design document is touched"

echo "--- Case 1: a correct record advances"
if to_finalization ok; then
    put ok summary.md "$GOOD_SUMMARY"
    put ok pre_pr.md "$GOOD_PREPR"
    submit ok '{"finalization_status":"ready_for_pr"}'
    if [ "$NEXT_STATE" = pre_pr_evidence ]; then
        pass "a correct summary and pre_pr.md advance to pre_pr_evidence"
    else
        fail "correct record: expected pre_pr_evidence, got [$NEXT_STATE]"
    fi
fi

echo "--- Case 2: a missing heading holds, and is fixed in place"
if to_finalization heading; then
    put heading summary.md "$NO_HEADING_SUMMARY"
    put heading pre_pr.md "$GOOD_PREPR"
    submit heading '{"finalization_status":"ready_for_pr"}'
    if [ "$NEXT_STATE" = finalization ]; then
        pass "a summary without '## Changes Made' holds at finalization"
    else
        fail "missing heading: expected to hold at finalization, got [$NEXT_STATE]"
    fi
    if names_gate summary_shape; then
        pass "the held submission names summary_shape"
    else
        fail "missing heading: expected summary_shape named; got: $(printf '%s' "$NEXT_RESPONSE" | cut -c1-200)"
    fi
    put heading summary.md "$GOOD_SUMMARY"
    submit heading '{"finalization_status":"ready_for_pr"}'
    if [ "$NEXT_STATE" = pre_pr_evidence ]; then
        pass "after the fix in place, the same submission advances"
    else
        fail "fix in place: expected pre_pr_evidence, got [$NEXT_STATE]"
    fi
fi

echo "--- Case 3/4: a wrong pre_pr.md key form holds"
# The underscored enum is what pre_pr_evidence accepts as evidence, and exactly
# what a run writes into pre_pr.md by mistake.
if to_finalization diagram; then
    put diagram summary.md "$GOOD_SUMMARY"
    put diagram pre_pr.md "cleanup_commit: $HEAD_SHA
design_diagram: not_applicable"
    submit diagram '{"finalization_status":"ready_for_pr"}'
    if [ "$NEXT_STATE" = finalization ] && names_gate diagram_referent; then
        pass "design_diagram: not_applicable holds at finalization, naming diagram_referent"
    else
        fail "enum form in pre_pr.md: expected a hold naming diagram_referent, got [$NEXT_STATE]"
    fi
fi
if to_finalization cleanup; then
    put cleanup summary.md "$GOOD_SUMMARY"
    put cleanup pre_pr.md 'cleanup_commit: done
design_diagram: not-applicable: no design document is touched'
    submit cleanup '{"finalization_status":"ready_for_pr"}'
    if [ "$NEXT_STATE" = finalization ] && names_gate cleanup_referent; then
        pass "cleanup_commit: done holds at finalization, naming cleanup_referent"
    else
        fail "placeholder cleanup_commit: expected a hold naming cleanup_referent, got [$NEXT_STATE]"
    fi
fi

# shirabe#422: shaped right, naming nothing. A sha from another branch, and a
# docs/ path that was never written, hold here with the gate named.
if to_finalization offbranch; then
    put offbranch summary.md "$GOOD_SUMMARY"
    put offbranch pre_pr.md "cleanup_commit: $OTHER_SHA
design_diagram: not-applicable: no design document is touched"
    submit offbranch '{"finalization_status":"ready_for_pr"}'
    if [ "$NEXT_STATE" = finalization ] && names_gate cleanup_referent; then
        pass "a cleanup_commit from another branch holds at finalization, naming cleanup_referent"
    else
        fail "off-branch cleanup_commit: expected a hold naming cleanup_referent, got [$NEXT_STATE]"
    fi
    put offbranch pre_pr.md "$GOOD_PREPR"
    submit offbranch '{"finalization_status":"ready_for_pr"}'
    if [ "$NEXT_STATE" = pre_pr_evidence ]; then
        pass "after HEAD is recorded in place, the same submission advances"
    else
        fail "off-branch fix in place: expected pre_pr_evidence, got [$NEXT_STATE]"
    fi
fi
if to_finalization nodoc; then
    put nodoc summary.md "$GOOD_SUMMARY"
    put nodoc pre_pr.md "cleanup_commit: $HEAD_SHA
design_diagram: docs/designs/DESIGN-missing.md"
    submit nodoc '{"finalization_status":"ready_for_pr"}'
    if [ "$NEXT_STATE" = finalization ] && names_gate diagram_referent; then
        pass "a design_diagram path that does not exist holds at finalization, naming diagram_referent"
    else
        fail "missing diagram path: expected a hold naming diagram_referent, got [$NEXT_STATE]"
    fi
fi

# The run #411 was filed from: a good summary and no pre_pr.md at all. The
# referent gates fail closed on an absent key, so this holds.
if to_finalization absent; then
    put absent summary.md "$GOOD_SUMMARY"
    submit absent '{"finalization_status":"ready_for_pr"}'
    if [ "$NEXT_STATE" = finalization ] && names_gate cleanup_referent && names_gate diagram_referent; then
        pass "no pre_pr.md holds at finalization, naming cleanup_referent and diagram_referent"
    else
        fail "absent pre_pr.md: expected a hold naming both referent gates, got [$NEXT_STATE]"
    fi
fi

echo "--- Case 5/6: the deferral path"
if to_finalization defer; then
    put defer summary.md "$NO_HEADING_SUMMARY"
    # deferral_requested is the escape edge and stays ungated: a run that cannot
    # produce the shape still reaches a human.
    submit defer '{"finalization_status":"deferral_requested"}'
    if [ "$NEXT_STATE" = deferral_approval ]; then
        pass "deferral_requested reaches deferral_approval with a malformed summary and no pre_pr.md"
        put defer pre_pr.md "$GOOD_PREPR"
        submit defer '{"approval_decision":"approved","deferral_detail":"x"}'
        if [ "$NEXT_STATE" = deferral_approval ] && names_gate summary_shape; then
            pass "approved holds at deferral_approval on a missing heading, naming summary_shape"
        else
            fail "approved with missing heading: expected a hold naming summary_shape, got [$NEXT_STATE]"
        fi
        put defer summary.md "$GOOD_SUMMARY"
        submit defer '{"approval_decision":"approved","deferral_detail":"x"}'
        if [ "$NEXT_STATE" = pre_pr_evidence ]; then
            pass "approved advances once the summary is fixed in place"
        else
            fail "approved after fix: expected pre_pr_evidence, got [$NEXT_STATE]"
        fi
    else
        fail "deferral_requested: expected deferral_approval, got [$NEXT_STATE]"
    fi
fi
if to_finalization reject; then
    submit reject '{"finalization_status":"deferral_requested"}'
    submit reject '{"approval_decision":"rejected","deferral_detail":"x"}'
    if [ "$NEXT_STATE" = done_blocked ]; then
        pass "rejected still reaches done_blocked with neither artifact written"
    else
        fail "rejected: expected done_blocked, got [$NEXT_STATE]"
    fi
fi

echo "--- Case 7/8: the early gates match the backstop, which still routes to done_blocked"
COMPILED=$(koto template compile "$TEMPLATE" 2>/dev/null)
if [ -z "$COMPILED" ] || [ ! -f "$COMPILED" ]; then
    fail "could not compile $TEMPLATE"
else
    for g in summary_shape cleanup_referent diagram_referent commit_convention; do
        want=$(jq -c --arg g "$g" '.states.pre_pr_evidence.gates[$g]' "$COMPILED")
        for s in finalization deferral_approval; do
            got=$(jq -c --arg g "$g" --arg s "$s" '.states[$s].gates[$g]' "$COMPILED")
            if [ "$want" != null ] && [ "$got" = "$want" ]; then
                pass "$s.$g is identical to pre_pr_evidence.$g"
            else
                fail "$s.$g drifted from pre_pr_evidence.$g: [$got] vs [$want]"
            fi
        done
    done
    # The backstop: pre_pr_evidence still routes each copied gate's failure to
    # done_blocked.
    # summary_shape is a context-matches gate and fails as matches: false; the
    # referent gates are command gates and fail as exit_code: 1.
    for spec in "summary_shape matches false" "cleanup_referent exit_code 1" "diagram_referent exit_code 1" \
                "commit_convention exit_code 1" "commit_convention exit_code 2"; do
        set -- $spec
        n=$(jq --arg k "gates.$1.$2" --argjson v "$3" '[.states.pre_pr_evidence.transitions[]
                  | select(.target == "done_blocked")
                  | select(.when[$k] == $v)] | length' "$COMPILED")
        if [ "$n" = 1 ]; then
            pass "pre_pr_evidence still sends $1 $2: $3 to done_blocked"
        else
            fail "pre_pr_evidence's $1 backstop edge changed (found $n)"
        fi
    done
    # shirabe#422: no copy of a referent gate may fall back to a shape check.
    # Each of the three states runs the existence check.
    for s in finalization deferral_approval pre_pr_evidence; do
        for g in cleanup_referent diagram_referent; do
            ok=$(jq -r --arg g "$g" --arg s "$s" '.states[$s].gates[$g]
                  | (.type == "command") and ((.command // "") | test("check-pre-pr-referents[.]sh"))' "$COMPILED")
            if [ "$ok" = true ]; then
                pass "$s.$g runs check-pre-pr-referents.sh"
            else
                fail "$s.$g does not run check-pre-pr-referents.sh as a command gate"
            fi
        done
    done
fi

# Last, because it adds a commit to the shared fixture branch: the commit gate
# reads every commit since impl_base through check-branch-output.sh, so a
# non-conventional commit after the reviewed one holds finalization, naming
# commit_convention, and rewording it in place advances.
echo "--- Case 9: a non-conventional commit holds at finalization"
if to_finalization commits; then
    put commits summary.md "$GOOD_SUMMARY"
    put commits pre_pr.md "$GOOD_PREPR"
    git commit -q --allow-empty -m "fixed the thing"
    submit commits '{"finalization_status":"ready_for_pr"}'
    if [ "$NEXT_STATE" = finalization ] && names_gate commit_convention; then
        pass "a non-conventional commit since impl_base holds at finalization, naming commit_convention"
    else
        fail "non-conventional commit: expected a hold naming commit_convention, got [$NEXT_STATE]"
    fi
    git commit -q --amend --allow-empty -m "fix: the thing"
    submit commits '{"finalization_status":"ready_for_pr"}'
    if [ "$NEXT_STATE" = pre_pr_evidence ]; then
        pass "after the commit is reworded in place, the same submission advances"
    else
        fail "reworded commit: expected pre_pr_evidence, got [$NEXT_STATE]"
    fi
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

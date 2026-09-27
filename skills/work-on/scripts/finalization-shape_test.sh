#!/usr/bin/env bash
# finalization-shape_test.sh — a malformed summary or pre-PR record holds the run
# at finalization instead of ending it at pre_pr_evidence.
#
# summary.md and pre_pr.md are written at `finalization`, and pre_pr_evidence
# checks their shape and sends a failure to done_blocked. For a child of
# /execute that terminal also disposes of the child's log (koto#240), so a shape
# the agent could have fixed in one edit cost a full re-entry. The same three
# shape gates now sit on finalization's ready_for_pr edge and on
# deferral_approval's approved edge, where a failure matches no edge and the
# state holds with the failing gate named.
#
# The cases drive the SHIPPED template, walked from entry to finalization the
# way retry-clearing_test.sh walks it:
#
#   a correct record advances to pre_pr_evidence            (case 1)
#   a missing heading holds, names summary_shape, and a fix in place advances
#                                                           (case 2)
#   a wrong pre_pr.md key form holds and names its gate     (cases 3, 4)
#   an approved deferral holds on a bad shape; the escape edges stay open
#                                                           (cases 5, 6)
#   the early gates carry the backstop's patterns, and the backstop still
#   routes a shape failure to done_blocked                  (cases 7, 8)
#
# pre-pr-evidence_test.sh drives the backstop itself and is unchanged.
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

# Keep every session out of the developer's real ~/.koto.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"

# koto rejects a variable value outside ^[a-zA-Z0-9._/:@ \-]*$, so a checkout
# under such a path is reached through a symlink (as in retry-clearing_test.sh).
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        PLUGIN_ROOT="$WORKDIR/plugin"
        ;;
esac

# scrutiny gates on commits over main, so the base branch has to be main.
REPO="$WORKDIR/repo"
mkdir -p "$REPO"
(
    cd "$REPO" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    git commit -q --allow-empty -m init
    git checkout -q -b impl/finalization-shape
    echo work > f.txt
    git add f.txt
    git commit -q -m "feat: work"
) >/dev/null 2>&1
cd "$REPO" || exit 1

NEXT_RESPONSE=""
NEXT_STATE=""
submit() {
    NEXT_RESPONSE=$(koto next "$1" --with-data "$2" 2>/dev/null)
    NEXT_STATE=$(printf '%s' "$NEXT_RESPONSE" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
}
put() { printf '%s\n' "$3" | koto context add "$1" "$2" >/dev/null 2>&1; }
names_gate() { printf '%s' "$NEXT_RESPONSE" | grep -q "\"name\":\"$1\""; }

# Walk a fresh session to finalization. The overrides skip gates that read a
# real GitHub issue and a real baseline.
to_finalization() {
    koto init "$1" --template "$TEMPLATE" \
        --var ARTIFACT_PREFIX=issue_42 \
        --var ISSUE_NUMBER=42 \
        --var PLUGIN_ROOT="$PLUGIN_ROOT" >/dev/null 2>&1
    submit "$1" '{"mode":"issue_backed","issue_number":"42"}'
    submit "$1" '{"status":"override"}'
    submit "$1" '{"status":"override"}'
    submit "$1" '{"staleness_signal":"override"}'
    put "$1" plan.md plan
    submit "$1" '{"plan_outcome":"plan_ready"}'
    submit "$1" '{"implementation_status":"complete"}'
    [ "$NEXT_STATE" = issue_type_routing ] && submit "$1" '{"issue_type":"code"}'
    put "$1" scrutiny_results.json '{}'
    submit "$1" '{"scrutiny_outcome":"passed"}'
    put "$1" review_results.json '{}'
    submit "$1" '{"review_outcome":"passed"}'
    put "$1" qa_results.json '{}'
    submit "$1" '{"qa_outcome":"passed"}'
    submit "$1" '{"verification_outcome":"passed","commands_run":"none"}'
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
GOOD_PREPR='cleanup_commit: 4f2a91c8d3b6e5a7f0c1d2e3a4b5c6d7e8f9a0b1
design_diagram: not-applicable: no design document is touched'

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
    put diagram pre_pr.md 'cleanup_commit: 4f2a91c8d3b6e5a7f0c1d2e3a4b5c6d7e8f9a0b1
design_diagram: not_applicable'
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

echo "--- Case 7/8: the early gates match the backstop, which is unchanged"
COMPILED=$(koto template compile "$TEMPLATE" 2>/dev/null)
if [ -z "$COMPILED" ] || [ ! -f "$COMPILED" ]; then
    fail "could not compile $TEMPLATE"
else
    for g in summary_shape cleanup_referent diagram_referent; do
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
    # The backstop: pre_pr_evidence still routes a shape failure to done_blocked.
    n=$(jq '[.states.pre_pr_evidence.transitions[]
              | select(.target == "done_blocked")
              | select(.when["gates.summary_shape.matches"] == false)] | length' "$COMPILED")
    if [ "$n" = 1 ]; then
        pass "pre_pr_evidence still sends summary_shape false to done_blocked"
    else
        fail "pre_pr_evidence's summary_shape backstop edge changed (found $n)"
    fi
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

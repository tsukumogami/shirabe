#!/usr/bin/env bash
# finalization-shape_test.sh — a malformed summary or pre-PR record holds the run
# at finalization, fixed in place, and a good one goes straight to pr_precheck.
#
# summary.md and pre_pr.md are written at `finalization`. The gates that check
# them (summary_shape, the two referent checks, and commit_convention, the walk
# over every commit since impl_base) sit on finalization's ready_for_pr edge and
# on deferral_approval's approved edge, where a failure matches no edge and the
# state holds with the failing gate named (case 9 for the commit walk). A later
# state, pre_pr_evidence, used to run the same gates again and end the run at
# done_blocked; it is gone, and both edges go to pr_precheck.
#
# The cases drive the SHIPPED template, walked from entry to finalization the
# way retry-clearing_test.sh walks it:
#
#   a correct record advances to pr_precheck                (case 1)
#   a missing heading holds, names summary_shape, and a fix in place advances
#                                                           (case 2)
#   a wrong pre_pr.md key form, a referent naming nothing (a commit from
#   another branch, a diagram path never written), or no pre_pr.md, holds and
#   names its gate                                          (cases 3, 4)
#   an approved deferral holds on a bad shape; the escape edges stay open
#                                                           (cases 5, 6)
#   finalization's and deferral_approval's copies of the gates are identical,
#   every copy of a referent gate runs the existence check, each state has
#   four edges to pr_precheck, one per pair of the two judgment enums, every
#   one requiring all five gates, an approval without the enums holds, and
#   no pre_pr_evidence state is left                       (cases 5-8)
#
# pre-pr-evidence_test.sh drives finalization alone, in a fixture, through the
# placeholder and referent forms.
#
# Usage: finalization-shape_test.sh
# Exit codes: 0 all pass, or koto/git/jq absent and the run skipped; 1 any failed.

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

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

WORKDIR=$(mktemp -d) || exit 1
cleanup() { [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"; return 0; }
ktg_on_exit cleanup

# Keep every session out of the developer's real $HOME/.koto, and the
# verification runner's results out of the developer's state directory.
export HOME="$WORKDIR/home"
export XDG_STATE_HOME="$WORKDIR/state"
mkdir -p "$HOME"
# deferral_approval's answer_cited gate holds approved until an answer is
# cited; cite_deferral provides one, and df_setup puts the shirabe it needs on
# PATH. Without that shirabe the deferral cases fail, saying so.
. "$SCRIPT_DIR/fixtures/decide-first/testlib.sh"
df_setup "$WORKDIR" || echo "the deferral cases will fail: no shirabe with question precedent"

# koto rejects a variable value outside ^[a-zA-Z0-9._/:@ \-]*$, so a checkout
# under such a path is reached through a symlink (as in retry-clearing_test.sh).
case "$PLUGIN_ROOT" in
    *[!a-zA-Z0-9._/:@\ -]*)
        ln -s "$PLUGIN_ROOT" "$WORKDIR/plugin"
        PLUGIN_ROOT="$WORKDIR/plugin"
        ;;
esac
# fix_determination reads the issue's labels with gh; the stand-in serves an
# unlabelled issue, so these runs are changes.
. "$PLUGIN_ROOT/scripts/lib/gh-issue-testlib.sh"
gh_issue_stand_in "$WORKDIR/gh-bin"

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
names_gate() { grep -q "\"name\":\"$1\"" <<<"$NEXT_RESPONSE"; }
# reached_precheck <session> <from>: the run moved from <from> into pr_precheck,
# once. pr_precheck reads the branch on entry and advances on its own when its
# gates pass, so the response's state may already be past it; the state log
# records the arrival either way.
reached_precheck() {
    [ "$(jq -s --arg f "$2" '[.[] | select(.type == "transitioned" and .payload.from == $f and .payload.to == "pr_precheck")] | length' \
        "$HOME/.koto/sessions/$1/koto-$1.state.jsonl" 2>/dev/null)" = 1 ]
}
# Round files name their runs (panel-scope.sh --record refuses one that doesn't).
. "$PLUGIN_ROOT/scripts/lib/panel-round-testlib.sh"

# pass_panel <session> <panel> <seat>...: records a clean round for every seat
# and ticks with nothing submitted. A panel's pass is its <panel>_verdict gate,
# read from the verdict ledger; there is no passed value to submit.
pass_panel() {
    local s="$1" p="$2" seat
    shift 2
    for seat in "$@"; do printf '{"seat":"%s","findings":[]}\n' "$seat"; done | jq -s . > "$WORKDIR/round.json"
    panel_round_runs "$s" "$p" "$WORKDIR/round.json"
    "$PLUGIN_ROOT/skills/work-on/scripts/panel-scope.sh" --record "$p" "$s" "$WORKDIR/round.json" >/dev/null \
        || fail "$s: panel-scope.sh --record $p failed"
    NEXT_RESPONSE=$(koto next "$s" 2>/dev/null)
    NEXT_STATE=$(printf '%s' "$NEXT_RESPONSE" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
}

# The verification state starts the map's commands on entry and its poll gate
# waits for the result, re-checking every 15 seconds. Starting the runner for
# the session before the tick that enters the state, and waiting for its
# result, lets that tick settle at once.
#
# On a loaded host the run could stop at verification (shirabe#866). A single
# tick holds on the gate for up to 480 seconds re-checking, so a merely slow
# result isn't enough to strand it; the likelier path is the gate's command
# itself, check-verification.sh, running past koto's per-command limit under
# load (shirabe#840 saw that limit trip this poll), which leaves the run at
# verification for that tick. So the prestart's wait for the result is bounded
# by wall time rather than by 200 short sleeps, and settle_verification below
# ticks again while the run is still there. VERIFY_WAIT_SECS is the budget for
# each wait: generous, since a quiet host never comes near it.
VERIFY_WAIT_SECS=${VERIFY_WAIT_SECS:-180}
prestart_verification() {
    local rv="$PLUGIN_ROOT/skills/work-on/scripts/run-verification.sh" f end=$((SECONDS + VERIFY_WAIT_SECS))
    "$rv" --start --session "$1" >/dev/null 2>&1
    f=$("$rv" --locate --session "$1" 2>/dev/null | sed -n 3p)
    while [ -n "$f" ] && [ ! -f "$f" ] && [ "$SECONDS" -lt "$end" ]; do sleep 0.2; done
}

# settle_verification <session>: while the run is still at verification after
# the tick that entered it (NEXT_STATE, as pass_panel left it), tick again
# until it moves on or the budget runs out. Each tick evaluates the gate
# afresh, so a gate command cut short under load gets another try.
settle_verification() {
    local end=$((SECONDS + VERIFY_WAIT_SECS))
    while [ "$NEXT_STATE" = verification ] && [ "$SECONDS" -lt "$end" ]; do
        sleep 1
        NEXT_RESPONSE=$(koto next "$1" 2>/dev/null)
        NEXT_STATE=$(printf '%s' "$NEXT_RESPONSE" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
    done
}

# to_finalization <session> [late]: walk a fresh session to finalization. The
# overrides skip gates that read a real GitHub issue and a real baseline.
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
    # analysis recorded HEAD, which already carries the fixture's work commit;
    # the run's base is the commit before it. Set before plan_ready, whose
    # tick runs fix_determination's action, which reads it.
    put "$1" impl_base "$BASE_SHA"
    # plan_ready runs through fix_determination, whose action records the
    # bound and the kind and whose kind_route gate routes on it in the same
    # tick, to implementation.
    submit "$1" '{"plan_outcome":"plan_ready"}'
    # A raise to full, which the level check keeps: all three panels on the path.
    "$PLUGIN_ROOT/skills/work-on/scripts/review-level.sh" set "$1" full >/dev/null 2>&1
    submit "$1" '{"implementation_status":"complete"}'
    [ "$NEXT_STATE" = issue_type_routing ] && submit "$1" '{"issue_type":"code"}'
    pass_panel "$1" scrutiny completeness justification intent
    pass_panel "$1" review pragmatic architect maintainer
    # late: skip the prestart, so the tick that enters verification starts the
    # runner and waits on the gate for the result itself.
    [ "${2:-}" = late ] || prestart_verification "$1"
    pass_panel "$1" qa tester
    settle_verification "$1"
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
    submit ok '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
    if reached_precheck ok finalization; then
        pass "a correct summary and pre_pr.md advance to pr_precheck"
    else
        fail "correct record: expected pr_precheck, got [$NEXT_STATE]"
    fi
fi

echo "--- Case 2: a missing heading holds, and is fixed in place"
if to_finalization heading; then
    put heading summary.md "$NO_HEADING_SUMMARY"
    put heading pre_pr.md "$GOOD_PREPR"
    submit heading '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
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
    submit heading '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
    if reached_precheck heading finalization; then
        pass "after the fix in place, the same submission advances to pr_precheck"
    else
        fail "fix in place: expected pr_precheck, got [$NEXT_STATE]"
    fi
fi

echo "--- Case 3/4: a wrong pre_pr.md key form holds"
# The underscored enum is what finalization accepts as evidence
# (design_diagram: not_applicable), and exactly what a run writes into pre_pr.md
# by mistake.
if to_finalization diagram; then
    put diagram summary.md "$GOOD_SUMMARY"
    put diagram pre_pr.md "cleanup_commit: $HEAD_SHA
design_diagram: not_applicable"
    submit diagram '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
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
    submit cleanup '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
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
    submit offbranch '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
    if [ "$NEXT_STATE" = finalization ] && names_gate cleanup_referent; then
        pass "a cleanup_commit from another branch holds at finalization, naming cleanup_referent"
    else
        fail "off-branch cleanup_commit: expected a hold naming cleanup_referent, got [$NEXT_STATE]"
    fi
    put offbranch pre_pr.md "$GOOD_PREPR"
    submit offbranch '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
    if reached_precheck offbranch finalization; then
        pass "after HEAD is recorded in place, the same submission advances to pr_precheck"
    else
        fail "off-branch fix in place: expected pr_precheck, got [$NEXT_STATE]"
    fi
fi
if to_finalization nodoc; then
    put nodoc summary.md "$GOOD_SUMMARY"
    put nodoc pre_pr.md "cleanup_commit: $HEAD_SHA
design_diagram: docs/designs/DESIGN-missing.md"
    submit nodoc '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
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
    submit absent '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
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
        cite_deferral defer || fail "defer: no answer could be cited for the deferral"
        put defer pre_pr.md "$GOOD_PREPR"
        submit defer '{"approval_decision":"approved","deferral_detail":"x","cleanup_done":"none_found","design_diagram":"not_applicable"}'
        if [ "$NEXT_STATE" = deferral_approval ] && names_gate summary_shape; then
            pass "approved holds at deferral_approval on a missing heading, naming summary_shape"
        else
            fail "approved with missing heading: expected a hold naming summary_shape, got [$NEXT_STATE]"
        fi
        put defer summary.md "$GOOD_SUMMARY"
        submit defer '{"approval_decision":"approved","deferral_detail":"x","cleanup_done":"none_found","design_diagram":"not_applicable"}'
        if reached_precheck defer deferral_approval; then
            pass "approved advances to pr_precheck once the summary is fixed in place"
        else
            fail "approved after fix: expected pr_precheck, got [$NEXT_STATE]"
        fi
    else
        fail "deferral_requested: expected deferral_approval, got [$NEXT_STATE]"
    fi
fi
# An approval without the two judgment enums matches no edge and holds, with
# every record in order. Its own session: koto keeps the evidence of every
# submission in a visit, so after an earlier approved that carried the enums
# a later one without them would still have them.
if to_finalization noenum; then
    put noenum summary.md "$GOOD_SUMMARY"
    put noenum pre_pr.md "$GOOD_PREPR"
    submit noenum '{"finalization_status":"deferral_requested"}'
    cite_deferral noenum || fail "noenum: no answer could be cited for the deferral"
    submit noenum '{"approval_decision":"approved","deferral_detail":"x"}'
    if [ "$NEXT_STATE" = deferral_approval ]; then
        pass "approved without cleanup_done and design_diagram holds at deferral_approval"
    else
        fail "approved without the enums: expected a hold at deferral_approval, got [$NEXT_STATE]"
    fi
    submit noenum '{"approval_decision":"approved","deferral_detail":"x","cleanup_done":"removed","design_diagram":"not_applicable"}'
    if reached_precheck noenum deferral_approval; then
        pass "the same approval with both enums advances to pr_precheck"
    else
        fail "approved with the enums: expected pr_precheck, got [$NEXT_STATE]"
    fi
fi
if to_finalization reject; then
    submit reject '{"finalization_status":"deferral_requested"}'
    cite_deferral reject || fail "reject: no answer could be cited for the deferral"
    submit reject '{"approval_decision":"rejected","deferral_detail":"x"}'
    if [ "$NEXT_STATE" = done_blocked ]; then
        pass "rejected still reaches done_blocked with neither artifact written"
    else
        fail "rejected: expected done_blocked, got [$NEXT_STATE]"
    fi
fi
# With no prestart (shirabe#866) the entering tick starts the runner and holds
# on the gate for the result; whether it settles there or the run is still at
# verification for settle_verification, the walk must reach finalization.
if to_finalization late-result late; then
    pass "a run whose result comes after the entering tick starts still reaches finalization"
fi

echo "--- Case 7/8: the two copies of the gates match, and both edges require them"
COMPILED=$(koto template compile "$TEMPLATE" 2>/dev/null)
if [ -z "$COMPILED" ] || [ ! -f "$COMPILED" ]; then
    fail "could not compile $TEMPLATE"
else
    # pre_pr_evidence ran the same gates again and was removed; nothing may
    # bring it back or route to it.
    if [ "$(jq '.states | has("pre_pr_evidence")' "$COMPILED")" = false ]; then
        pass "the compiled template has no pre_pr_evidence state"
    else
        fail "the compiled template still has a pre_pr_evidence state"
    fi
    n=$(jq '[.states[].transitions[]? | select(.target == "pre_pr_evidence")] | length' "$COMPILED")
    [ "$n" = 0 ] && pass "no edge targets pre_pr_evidence" || fail "$n edges still target pre_pr_evidence"
    # finalization and deferral_approval each carry a copy of the four gates;
    # the two copies must stay identical.
    for g in summary_shape cleanup_referent diagram_referent commit_convention; do
        want=$(jq -c --arg g "$g" '.states.finalization.gates[$g]' "$COMPILED")
        got=$(jq -c --arg g "$g" '.states.deferral_approval.gates[$g]' "$COMPILED")
        if [ "$want" != null ] && [ "$got" = "$want" ]; then
            pass "deferral_approval.$g is identical to finalization.$g"
        else
            fail "deferral_approval.$g drifted from finalization.$g: [$got] vs [$want]"
        fi
    done
    # Both advancing routes go to pr_precheck and require every gate to pass:
    # with no later state checking the records, an edge that dropped one would
    # let a failure through. koto tests an evidence field only for a value, so
    # requiring both judgment enums takes one edge per pair of values: four
    # edges, the four pairs once each, every one with all five gates. An edge
    # to pr_precheck that names neither enum would let a submission without
    # them through, so none may exist.
    PAIRS="none_found|not_applicable,none_found|updated,removed|not_applicable,removed|updated"
    for spec in "finalization finalization_status ready_for_pr" "deferral_approval approval_decision approved"; do
        set -- $spec
        edges=$(jq -c --arg s "$1" '[.states[$s].transitions[] | select(.target == "pr_precheck")]' "$COMPILED")
        n=$(jq 'length' <<<"$edges")
        [ "$n" = 4 ] && pass "$1 has four edges to pr_precheck" || fail "$1 has $n edges to pr_precheck, want 4"
        got=$(jq -r '[.[] | "\(.when.cleanup_done)|\(.when.design_diagram)"] | sort | join(",")' <<<"$edges")
        [ "$got" = "$PAIRS" ] && pass "$1's pr_precheck edges cover the four cleanup_done/design_diagram pairs once each" \
            || fail "$1's pr_precheck edges cover [$got], want [$PAIRS]"
        ok=$(jq -r --arg k "$2" --arg v "$3" 'all(.[]; .when[$k] == $v
                    and .when["gates.summary_exists.exists"] == true
                    and .when["gates.summary_shape.matches"] == true
                    and .when["gates.cleanup_referent.exit_code"] == 0
                    and .when["gates.diagram_referent.exit_code"] == 0
                    and .when["gates.commit_convention.exit_code"] == 0)' <<<"$edges")
        if [ "$ok" = true ]; then
            pass "every $1 edge to pr_precheck takes $3 and requires all five gates"
        else
            fail "$1's pr_precheck edges changed: $edges"
        fi
    done
    # Both states take the two judgment calls pre_pr_evidence used to.
    for s in finalization deferral_approval; do
        for f in "cleanup_done removed,none_found" "design_diagram updated,not_applicable"; do
            set -- $f
            got=$(jq -r --arg s "$s" --arg f "$1" '.states[$s].accepts[$f] | "\(.field_type)|\(.values | join(","))"' "$COMPILED")
            [ "$got" = "enum|$2" ] && pass "$s accepts $1 as enum $2" || fail "$s's $1 is [$got]"
        done
    done
    # shirabe#422: no copy of a referent gate may fall back to a shape check.
    # Each of the two states runs the existence check.
    for s in finalization deferral_approval; do
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
    submit commits '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
    if [ "$NEXT_STATE" = finalization ] && names_gate commit_convention; then
        pass "a non-conventional commit since impl_base holds at finalization, naming commit_convention"
    else
        fail "non-conventional commit: expected a hold naming commit_convention, got [$NEXT_STATE]"
    fi
    git commit -q --amend --allow-empty -m "fix: the thing"
    submit commits '{"finalization_status":"ready_for_pr","cleanup_done":"none_found","design_diagram":"not_applicable"}'
    if reached_precheck commits finalization; then
        pass "after the commit is reworded in place, the same submission advances to pr_precheck"
    else
        fail "reworded commit: expected pr_precheck, got [$NEXT_STATE]"
    fi
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

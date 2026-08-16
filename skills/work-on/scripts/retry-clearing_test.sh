#!/usr/bin/env bash
# retry-clearing_test.sh — the retry clearing blocks, end to end
# Part of the work-on skill
#
# Six of /work-on's twelve `context-exists` gates can be entered twice, and on
# the second entry each finds the previous round's artifact still under its key.
# The gate asks whether the key is present and nothing else, so the phase
# advances on a verdict about code that has since changed. Each retry path now
# removes the keys its re-entry will re-read, and confirms each is gone with
# `koto context exists` — the same `store.ctx_exists` the gate evaluator calls,
# so the check is the gate's own condition rather than a proxy for it.
#
# This harness asserts the repair on four fronts:
#
#   the gate refuses a re-entry once the key is cleared   (cases 1, 3, 5, 7)
#   the first pass is untouched                           (cases 2, 4, 6, 8)
#   a retry clears every key its re-entry will read       (cases 9, 10, 11)
#   a failed clearing is loud, and does not brick the run (cases 12, 13, 14)
#
# It runs the SHIPPED TEXT rather than a copy: every block is extracted from its
# phase file at run time, so an edit that breaks one fails here. A copy pasted
# into this file would keep passing after the shipped text drifted, which is the
# same defect class this whole change exists to close.
#
# Usage: retry-clearing_test.sh
#
# Exit codes:
#   0 — all cases pass, or koto is absent and the run skipped
#   1 — one or more cases failed
#
# A missing koto exits 0 with a loud SKIP rather than failing. The suite runs on
# two legs and only one has koto: the Linux leg of check-work-on-scripts.yml
# installs it through the project tool manifest, so the assertions genuinely run
# there; the macOS leg is the bash 3.2 floor check and exists to test portability
# of the shell itself. Failing on absence would red the floor leg for a reason
# that has nothing to do with what that leg checks. The Linux leg's explicit
# install step is what keeps a silent skip from hiding a koto that vanished from
# CI — the install fails first.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PHASES="$SKILL_DIR/references/phases"
TEMPLATE="$SKILL_DIR/koto-templates/work-on.md"

PASS_COUNT=0
FAIL_COUNT=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v koto >/dev/null 2>&1 || { echo "SKIP: koto not on PATH -- no case ran"; exit 0; }
command -v git  >/dev/null 2>&1 || { echo "SKIP: git not on PATH -- no case ran"; exit 0; }
[ -f "$TEMPLATE" ] || { echo "FAIL: template not found at $TEMPLATE" >&2; exit 1; }

WORKDIR=$(mktemp -d)
cleanup() {
    # The broken-store cases leave a directory read-only; restore it so rm can
    # finish, or the harness leaks a temp tree on every run.
    if [ -n "${LOCKED_DIR:-}" ] && [ -d "${LOCKED_DIR:-}" ]; then
        chmod -R u+w "$LOCKED_DIR" 2>/dev/null
    fi
    [ -n "${WORKDIR:-}" ] && rm -rf "$WORKDIR"
    return 0
}
trap cleanup EXIT

# koto resolves its session store through the home directory, so pointing HOME
# at the temp tree keeps every session this harness creates out of the
# developer's real ~/.koto. Without it a failing run leaves sessions behind that
# the next run then finds.
export HOME="$WORKDIR/home"
mkdir -p "$HOME"

# --- extract the shipped blocks ----------------------------------------------

# Print the first ```bash fenced block in $1 that contains the substring $2.
extract_block() {
    awk -v marker="$2" '
        /^```bash$/  { inblk = 1; buf = ""; next }
        /^```$/ && inblk {
            if (index(buf, marker) > 0) { printf "%s", buf; exit }
            inblk = 0; buf = ""; next
        }
        inblk { buf = buf $0 "\n" }
    ' "$1"
}

SCRUTINY_BLOCK=$(extract_block "$PHASES/phase-4a-scrutiny.md"      "koto context remove")
REVIEW_BLOCK=$(  extract_block "$PHASES/phase-4b-review.md"        "koto context remove")
QA_BLOCK=$(      extract_block "$PHASES/phase-4c-qa.md"            "koto context remove")
ANALYSIS_BLOCK=$(extract_block "$PHASES/phase-3-analysis.md"       "koto context remove")
IMPL_BLOCK=$(    extract_block "$PHASES/phase-4-implementation.md" "koto context remove")
FINAL_BLOCK=$(   extract_block "$PHASES/phase-5-finalization.md"   "koto context remove")
# `verification` has no phase reference file -- its directive lives in the
# template -- so its clearing block is extracted from there.
VERIFY_BLOCK=$(  extract_block "$TEMPLATE"                         "koto context remove")

for pair in \
    "SCRUTINY_BLOCK:phase-4a-scrutiny.md" \
    "REVIEW_BLOCK:phase-4b-review.md" \
    "QA_BLOCK:phase-4c-qa.md" \
    "ANALYSIS_BLOCK:phase-3-analysis.md" \
    "IMPL_BLOCK:phase-4-implementation.md" \
    "FINAL_BLOCK:phase-5-finalization.md" \
    "VERIFY_BLOCK:koto-templates/work-on.md"
do
    var=${pair%%:*}
    src=${pair#*:}
    eval "val=\${$var}"
    if [ -z "$val" ]; then
        fail "could not extract a clearing block from $src (no bash block contains 'koto context remove')"
        echo; echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"; exit 1
    fi
done

# Render a block for execution: substitute the `<WF>` placeholder the phase files
# use for the workflow name with the session this case drives.
render() { printf '%s\n' "$1" | sed "s|<WF>|$2|g"; }

# --- the repository the command gates read ------------------------------------
#
# `implementation` gates on `git log --oneline main..HEAD`, so the base branch has
# to be main. A repo initialized with git's own default would leave has_commits
# failing and every walk stuck short of the panels.
REPO="$WORKDIR/repo"
mkdir -p "$REPO"
(
    cd "$REPO" || exit 1
    git init -q -b main .
    git config user.email t@example.com
    git config user.name t
    git commit -q --allow-empty -m init
    git checkout -q -b impl/retry-clearing
    echo work > f.txt
    git add f.txt
    git commit -q -m "feat: work"
) >/dev/null 2>&1
cd "$REPO" || exit 1

# --- driving a session --------------------------------------------------------

new_session() {
    koto init "$1" --template "$TEMPLATE" \
        --var ARTIFACT_PREFIX=issue_42 \
        --var ISSUE_NUMBER=42 >/dev/null 2>&1
}

seed() { printf 'round-1 artifact\n' | koto context add "$1" "$2" >/dev/null 2>&1; }

# `koto next` reports the resulting state in its JSON response and keeps
# reporting it after a terminal transition; `koto status` answers "workflow not
# found" once a workflow is terminal, so the submission response is the surface
# to read.
NEXT_RESPONSE=""
NEXT_STATE=""
submit() {
    # Sets the globals rather than printing them. A `state=$(submit ...)` would
    # run this in a subshell, so NEXT_RESPONSE would not survive the call and the
    # gate-name assertions below would read an empty string.
    NEXT_RESPONSE=$(koto next "$1" --with-data "$2" 2>/dev/null)
    NEXT_STATE=$(printf '%s' "$NEXT_RESPONSE" | sed -n 's/.*"state":"\([^"]*\)".*/\1/p')
}

# Walk a fresh session to `analysis`. The three overrides skip gates that read a
# real GitHub issue and a real baseline, neither of which this harness has or
# needs: every case here is about what happens from analysis onward.
to_analysis() {
    new_session "$1"
    submit "$1" '{"mode":"issue_backed","issue_number":"42"}'
    submit "$1" '{"status":"override"}'
    submit "$1" '{"status":"override"}'
    submit "$1" '{"staleness_signal":"override"}'
}

to_implementation() {
    to_analysis "$1"
    seed "$1" plan.md
    submit "$1" '{"plan_outcome":"plan_ready","issue_type":"code"}'
}

to_scrutiny() {
    to_implementation "$1"
    submit "$1" '{"implementation_status":"complete","issue_type":"code"}'
}

to_review() {
    to_scrutiny "$1"
    seed "$1" scrutiny_results.json
    submit "$1" '{"scrutiny_outcome":"passed"}'
}

to_qa() {
    to_review "$1"
    seed "$1" review_results.json
    submit "$1" '{"review_outcome":"passed"}'
}

to_verification() {
    to_qa "$1"
    seed "$1" qa_results.json
    submit "$1" '{"qa_outcome":"passed"}'
}

to_finalization() {
    to_verification "$1"
    submit "$1" '{"verification_outcome":"passed","commands_run":"none"}'
}

# --- Case 1 — each panel gate holds when its key is cleared -------------------
#
# The core assertion. With the key removed, the phase's advancing outcome must
# not advance, and koto must name the gate so an operator is not left guessing.

echo "--- Case 1: a cleared panel key holds its phase"

check_panel_holds() {
    # $1 session  $2 walk-fn  $3 state  $4 key  $5 outcome-field  $6 gate-name
    "$2" "$1"
    koto context remove "$1" "$4" >/dev/null 2>&1
    submit "$1" "{\"$5\":\"passed\"}"
    if [ "$NEXT_STATE" = "$3" ]; then
        pass "$3: key $4 cleared + $5 passed -> state holds"
    else
        fail "$3: key $4 cleared + $5 passed -> expected to hold, got [$NEXT_STATE]"
    fi
    if printf '%s' "$NEXT_RESPONSE" | grep -q "\"name\":\"$6\""; then
        pass "$3: the blocked submission names $6 as the failing condition"
    else
        fail "$3: expected the response to name $6; got: $(printf '%s' "$NEXT_RESPONSE" | cut -c1-160)"
    fi
}

check_panel_holds hold-scrutiny to_scrutiny scrutiny      scrutiny_results.json scrutiny_outcome scrutiny_results
check_panel_holds hold-review   to_review   review        review_results.json   review_outcome   review_results
check_panel_holds hold-qa       to_qa       qa_validation qa_results.json       qa_outcome       qa_results

# --- Case 2 — first-pass parity for the panels --------------------------------
#
# The mirror of case 1. With the key present the phase advances exactly as it
# does today; a change that made every panel refuse would pass case 1 alone.

echo "--- Case 2: a present panel key still advances (first-pass parity)"

check_panel_advances() {
    # $1 session  $2 walk-fn  $3 key  $4 outcome-field  $5 expected-next-state
    "$2" "$1"
    seed "$1" "$3"
    submit "$1" "{\"$4\":\"passed\"}"
    if [ "$NEXT_STATE" = "$5" ]; then
        pass "key $3 present + $4 passed -> advances to $5"
    else
        fail "key $3 present + $4 passed -> expected $5, got [$NEXT_STATE]"
    fi
}

check_panel_advances adv-scrutiny to_scrutiny scrutiny_results.json scrutiny_outcome review
check_panel_advances adv-review   to_review   review_results.json   review_outcome   qa_validation
check_panel_advances adv-qa       to_qa       qa_results.json       qa_outcome       verification

# --- Case 3/4 — the analysis gate, both directions ----------------------------

echo "--- Case 3/4: the plan_artifact gate"

to_analysis plan-hold
seed plan-hold plan.md
koto context remove plan-hold plan.md >/dev/null 2>&1
submit plan-hold '{"plan_outcome":"plan_ready","issue_type":"code"}'
if [ "$NEXT_STATE" = "analysis" ]; then
    pass "analysis: plan.md cleared + plan_ready -> state holds"
else
    fail "analysis: plan.md cleared + plan_ready -> expected to hold, got [$NEXT_STATE]"
fi
if printf '%s' "$NEXT_RESPONSE" | grep -q '"name":"plan_artifact"'; then
    pass "analysis: the blocked submission names plan_artifact"
else
    fail "analysis: expected the response to name plan_artifact"
fi

to_analysis plan-adv
seed plan-adv plan.md
submit plan-adv '{"plan_outcome":"plan_ready","issue_type":"code"}'
if [ "$NEXT_STATE" = "implementation" ]; then
    pass "analysis: plan.md present + plan_ready -> advances to implementation"
else
    fail "analysis: plan.md present + plan_ready -> expected implementation, got [$NEXT_STATE]"
fi

# --- Case 5/6 — the two summary gates -----------------------------------------
#
# `deferral_approval` is the one worth driving rather than reasoning about.
# Exactly one transition targets it and nothing routes back in, so the state is
# entered once and looks safe — but `finalization` upstream sits on a cycle, so
# that single entry can carry a summary written before the fixes.

echo "--- Case 5/6: the two summary_exists gates"

to_finalization sum-hold
seed sum-hold summary.md
koto context remove sum-hold summary.md >/dev/null 2>&1
submit sum-hold '{"finalization_status":"ready_for_pr"}'
if [ "$NEXT_STATE" = "finalization" ]; then
    pass "finalization: summary.md cleared + ready_for_pr -> state holds"
else
    fail "finalization: summary.md cleared + ready_for_pr -> expected to hold, got [$NEXT_STATE]"
fi

to_finalization defer-hold
seed defer-hold summary.md
submit defer-hold '{"finalization_status":"deferral_requested"}'
if [ "$NEXT_STATE" = "deferral_approval" ]; then
    koto context remove defer-hold summary.md >/dev/null 2>&1
    submit defer-hold '{"approval_decision":"approved"}'
    if [ "$NEXT_STATE" = "deferral_approval" ]; then
        pass "deferral_approval: summary.md cleared + approved -> state holds"
    else
        fail "deferral_approval: summary.md cleared + approved -> expected to hold, got [$NEXT_STATE]"
    fi
    # The mirror, so the case above cannot pass by way of a malformed submission
    # that the state would have refused whatever the key's status.
    seed defer-hold summary.md
    submit defer-hold '{"approval_decision":"approved"}'
    if [ "$NEXT_STATE" = "pr_creation" ]; then
        pass "deferral_approval: summary.md present + approved -> advances to pr_creation"
    else
        fail "deferral_approval: summary.md present + approved -> expected pr_creation, got [$NEXT_STATE]"
    fi
    # And the rejected exit stays reachable with the key absent -- deferral_approval's
    # own route to a terminal state, the analogue of the escalate exits elsewhere.
    to_finalization defer-reject
    seed defer-reject summary.md
    submit defer-reject '{"finalization_status":"deferral_requested"}'
    koto context remove defer-reject summary.md >/dev/null 2>&1
    submit defer-reject '{"approval_decision":"rejected","deferral_detail":"x"}'
    if [ "$NEXT_STATE" = "done_blocked" ]; then
        pass "deferral_approval: rejected reaches done_blocked with summary.md absent"
    else
        fail "deferral_approval: rejected expected done_blocked, got [$NEXT_STATE]"
    fi
else
    fail "could not reach deferral_approval to test its gate; landed at [$NEXT_STATE]"
fi

to_finalization sum-adv
seed sum-adv summary.md
submit sum-adv '{"finalization_status":"ready_for_pr"}'
if [ "$NEXT_STATE" != "finalization" ] && [ -n "$NEXT_STATE" ]; then
    pass "finalization: summary.md present + ready_for_pr -> advances to $NEXT_STATE"
else
    fail "finalization: summary.md present + ready_for_pr -> expected to advance, got [$NEXT_STATE]"
fi

# --- Case 7 — the shipped panel block clears all three keys --------------------
#
# Driven from each entry point rather than from one, because the traversal claim
# is about every panel at or above the raiser and a retry raised at `scrutiny`
# exercises a different span than one raised at `qa_validation`.

echo "--- Case 7: a shipped panel block clears all three keys, from each entry point"

check_traversal() {
    # $1 session  $2 walk-fn  $3 block-var-name
    "$2" "$1"
    seed "$1" scrutiny_results.json
    seed "$1" review_results.json
    seed "$1" qa_results.json
    # summary.md too: a retry raised at a panel returns to implementation and the
    # run walks forward through verification into finalization, whose gate would
    # otherwise be satisfied by a summary written before this round's fixes. On a
    # second cycle -- finalization issues_found, then a panel raising again --
    # that summary really is present.
    seed "$1" summary.md
    eval "blk=\${$3}"
    out=$(render "$blk" "$1" | bash 2>/dev/null)
    rc=$?
    left=""
    for k in scrutiny_results.json review_results.json qa_results.json summary.md; do
        if koto context exists "$1" "$k" >/dev/null 2>&1; then
            left="$left $k"
        fi
    done
    if [ "$rc" -eq 0 ] && [ -z "$left" ]; then
        pass "$1: the shipped block removed every key the re-entry re-reads (exit 0)"
    else
        fail "$1: block exit $rc, keys still present:${left:- none}"
    fi
    # plan.md must NOT be cleared here: the plan is still the thing being
    # implemented, and analysis is not on this traversal. An over-broad key list
    # would strand the run at analysis if it were ever re-entered.
    if koto context exists "$1" plan.md >/dev/null 2>&1; then
        pass "$1: plan.md is left alone -- the retry does not invalidate the plan"
    else
        fail "$1: plan.md was cleared by a panel retry; the plan is still valid here"
    fi
}

# The `summary.md` entry in the panel blocks is deliberate belt and braces, not a
# live requirement, and the design says so. This pins the graph fact that makes
# that true: the only route from `finalization` back to a panel is through
# `implementation` -- the `issues_found` edge, which clears summary.md itself.
# If a future edge routed finalization back to a panel directly, the entry would
# become load-bearing and the design's wording would be wrong; this fails first.
check_no_direct_finalization_to_panel() {
    to_finalization graph-check
    seed graph-check summary.md
    submit graph-check '{"finalization_status":"deferral_requested"}'
    if [ "$NEXT_STATE" = "deferral_approval" ]; then
        submit graph-check '{"approval_decision":"approved"}'
        case "$NEXT_STATE" in
            scrutiny|review|qa_validation)
                fail "deferral_approval reaches a panel directly -- summary.md in the panel blocks is now load-bearing and the DESIGN says it is not"
                ;;
            *)
                pass "deferral_approval does not reach a panel (went to ${NEXT_STATE:-terminal})"
                ;;
        esac
    else
        fail "expected deferral_approval from a deferral_requested, got [$NEXT_STATE]"
    fi
}
check_no_direct_finalization_to_panel

check_traversal trav-scrutiny to_scrutiny SCRUTINY_BLOCK
check_traversal trav-review   to_review   REVIEW_BLOCK
check_traversal trav-qa       to_qa       QA_BLOCK

# --- Case 8 — after the block runs, no panel advances on `passed` --------------
#
# Case 7 checks the keys are gone. This checks the consequence: the panels the
# retry re-enters refuse the advancing outcome. Without it, a block that removed
# the keys from a store the gate does not read would pass case 7.

echo "--- Case 8: after a retry block, the re-entered panels refuse to advance"

to_qa consequence
seed consequence scrutiny_results.json
seed consequence review_results.json
seed consequence qa_results.json
render "$QA_BLOCK" consequence | bash >/dev/null 2>&1
# The block's own `koto next` submitted blocking_retry, so the session is back
# at implementation. Walk forward and try to pass each panel on its stale key.
submit consequence '{"implementation_status":"complete","issue_type":"code"}'
if [ "$NEXT_STATE" = "scrutiny" ]; then
    submit consequence '{"scrutiny_outcome":"passed"}'
    if [ "$NEXT_STATE" = "scrutiny" ]; then
        pass "after a qa retry, scrutiny refuses passed -- though scrutiny raised nothing"
    else
        fail "after a qa retry, scrutiny advanced to [$NEXT_STATE] on a cleared key"
    fi
else
    fail "expected the retry to return to implementation then scrutiny; landed at [$NEXT_STATE]"
fi

# --- Case 9 — both edges into analysis clear plan.md ---------------------------
#
# Driven separately rather than one argued from the other: they are different
# edges in different phase files, and one can ship without the other.

echo "--- Case 9: both edges into analysis clear plan.md"

check_analysis_edge() {
    # $1 session  $2 walk-fn  $3 block-var  $4 label
    "$2" "$1"
    seed "$1" plan.md
    # The panel keys and the summary too. Both edges return to `analysis`, and a
    # plan_ready from there goes to `implementation` and on through every panel,
    # so the traversal is a superset of a panel retry's -- not just plan.md. An
    # earlier version cleared only plan.md and left all four of these stale.
    seed "$1" scrutiny_results.json
    seed "$1" review_results.json
    seed "$1" qa_results.json
    seed "$1" summary.md
    eval "blk=\${$3}"
    render "$blk" "$1" | bash >/dev/null 2>&1

    left=""
    for k in plan.md scrutiny_results.json review_results.json qa_results.json summary.md; do
        if koto context exists "$1" "$k" >/dev/null 2>&1; then
            left="$left $k"
        fi
    done
    if [ -z "$left" ]; then
        pass "$4: every key the traversal re-reads is cleared, plan.md included"
    else
        fail "$4: keys survive the clearing step:$left"
    fi
}

check_analysis_edge edge-self to_analysis       ANALYSIS_BLOCK "analysis self-loop (scope_changed_retry)"
check_analysis_edge edge-impl to_implementation IMPL_BLOCK     "implementation (scope_expanded_retry)"

# The consequence at the analysis gate itself.
submit edge-impl '{"plan_outcome":"plan_ready","issue_type":"code"}'
if [ "$NEXT_STATE" = "analysis" ]; then
    pass "implementation (scope_expanded_retry): analysis then refuses plan_ready"
else
    fail "implementation (scope_expanded_retry): analysis advanced to [$NEXT_STATE]"
fi

# And the consequence further down the traversal: write a fresh plan, walk to
# implementation and on to scrutiny, and try to pass it on the round-1 verdict.
# Without the panel keys in the analysis blocks' lists, this advances.
seed edge-impl plan.md
submit edge-impl '{"plan_outcome":"plan_ready","issue_type":"code"}'
if [ "$NEXT_STATE" = "implementation" ]; then
    submit edge-impl '{"implementation_status":"complete","issue_type":"code"}'
    if [ "$NEXT_STATE" = "scrutiny" ]; then
        submit edge-impl '{"scrutiny_outcome":"passed"}'
        if [ "$NEXT_STATE" = "scrutiny" ]; then
            pass "scope_expanded_retry: scrutiny refuses passed on the round-1 verdict"
        else
            fail "scope_expanded_retry: scrutiny advanced to [$NEXT_STATE] on a round-1 verdict"
        fi
    else
        fail "scope_expanded_retry: expected scrutiny after a fresh plan, got [$NEXT_STATE]"
    fi
else
    fail "scope_expanded_retry: expected implementation on a fresh plan, got [$NEXT_STATE]"
fi

# --- Case 10 — issues_found clears summary.md ---------------------------------

echo "--- Case 10: issues_found clears summary.md"

to_finalization final-clear
seed final-clear summary.md
render "$FINAL_BLOCK" final-clear | bash >/dev/null 2>&1
if koto context exists final-clear summary.md >/dev/null 2>&1; then
    fail "finalization (issues_found): summary.md survived the shipped block"
else
    pass "finalization (issues_found): summary.md cleared by the shipped block"
fi

# --- Case 10b — every retry edge covers the traversal it starts ----------------
#
# The defect this case exists for: an earlier version of these blocks cleared the
# raising phase's own key and nothing else. That is right for the key the phase
# writes and wrong for the traversal the retry begins, because every retry routes
# back to `implementation` and a code-typed run walks forward from there through
# all three panels, verification, and finalization.
#
# Two edges were reached that way and advanced on a round-1 verdict with no
# round-2 artifact written: `verification_outcome: failed` (which had no clearing
# step at all) and `finalization_status: issues_found` (which cleared only
# summary.md). Each is driven end to end here rather than asserted from the graph.

echo "--- Case 10b: the verification and finalization edges cover their traversal"

check_edge_traversal() {
    # $1 session  $2 block-var  $3 human label  $4 walk-fn (state the edge leaves from)
    "$4" "$1"
    seed "$1" scrutiny_results.json
    seed "$1" review_results.json
    seed "$1" qa_results.json
    seed "$1" summary.md
    eval "blk=\${$2}"
    render "$blk" "$1" | bash >/dev/null 2>&1

    left=""
    for k in scrutiny_results.json review_results.json qa_results.json summary.md; do
        if koto context exists "$1" "$k" >/dev/null 2>&1; then
            left="$left $k"
        fi
    done
    if [ -z "$left" ]; then
        pass "$3: every key the traversal re-reads is cleared"
    else
        fail "$3: keys survive the clearing step:$left"
    fi

    # And the consequence, driven: walk back to scrutiny and try to pass it on
    # the verdict that was there before. Clearing the keys is only interesting
    # because of this.
    submit "$1" '{"implementation_status":"complete","issue_type":"code"}'
    if [ "$NEXT_STATE" = "scrutiny" ]; then
        submit "$1" '{"scrutiny_outcome":"passed"}'
        if [ "$NEXT_STATE" = "scrutiny" ]; then
            pass "$3: scrutiny refuses passed on the round-1 verdict after the retry"
        else
            fail "$3: scrutiny advanced to [$NEXT_STATE] on a round-1 verdict"
        fi
    else
        fail "$3: expected the retry to reach implementation then scrutiny, got [$NEXT_STATE]"
    fi
}

# Each block is driven from the state its edge actually leaves from -- the
# verification block from `verification`, the finalization block from
# `finalization`. Driving one from the wrong state would submit an outcome that
# state does not accept, and the case would fail for a reason that has nothing to
# do with clearing.
check_edge_traversal edge-verify VERIFY_BLOCK "verification failed"        to_verification
check_edge_traversal edge-issues FINAL_BLOCK  "finalization issues_found"  to_finalization

# --- Case 11 — idempotence on a key no phase has written ----------------------
#
# The blocks carry no `exists` guard, which is only safe because removal is
# idempotent. If that stopped holding, every first-time retry would exit 1.

echo "--- Case 11: the block exits 0 when its keys were never written"

to_scrutiny never-written
render "$SCRUTINY_BLOCK" never-written | bash >/dev/null 2>&1
if [ $? -eq 0 ]; then
    pass "the shipped block exits 0 with none of its keys ever written"
else
    fail "the shipped block should be idempotent on absent keys; exit $?"
fi

# --- Case 12/13/14 — a broken store ------------------------------------------
#
# The store is made unwritable so `koto context remove` fails with the key still
# in place. Three things must hold: the block exits non-zero; the diagnostic
# survives the `2>/dev/null` operators type to escape koto's migration noise; and
# the escalate exit is still reachable, so a broken store does not brick the run.

echo "--- Case 12/13/14: a broken context store"

to_scrutiny broken
seed broken scrutiny_results.json
seed broken review_results.json
seed broken qa_results.json

CTX_DIR=$(find "$HOME/.koto" -type d -name ctx 2>/dev/null | grep broken | head -1)
if [ -z "$CTX_DIR" ]; then
    CTX_DIR=$(find "$HOME" -type d -path '*broken*' -name ctx 2>/dev/null | head -1)
fi

if [ -z "$CTX_DIR" ] || [ ! -d "$CTX_DIR" ]; then
    fail "could not locate the ctx directory for session 'broken' -- the broken-store cases did not run"
else
    LOCKED_DIR="$CTX_DIR"
    chmod a-w "$CTX_DIR"

    # stderr to /dev/null on purpose: the diagnostic has to be on stdout.
    out=$(render "$SCRUTINY_BLOCK" broken 2>/dev/null | bash 2>/dev/null)
    rc=$?

    if [ "$rc" -ne 0 ]; then
        pass "broken store: the shipped block exits non-zero ($rc)"
    else
        fail "broken store: the block exited 0 -- a failed removal presented as success"
    fi

    if printf '%s' "$out" | grep -q 'scrutiny_results.json'; then
        pass "broken store: the diagnostic reaches stdout and names the key"
    else
        fail "broken store: expected the key on stdout with stderr discarded; got: [$out]"
    fi

    if printf '%s' "$out" | grep -q 'blocking_escalate'; then
        pass "broken store: the diagnostic names blocking_escalate as the way out"
    else
        fail "broken store: the diagnostic must name the escalate outcome; got: [$out]"
    fi

    if printf '%s' "$out" | grep -q 'Do NOT submit'; then
        pass "broken store: the diagnostic names the outcome not to submit"
    else
        fail "broken store: the diagnostic must say which outcome not to submit; got: [$out]"
    fi

    # The run must still reach a terminal state. This is the requirement a
    # clearing step that hard-fails the phase would violate: the operator would
    # be left with a workflow that can go nowhere on a store it cannot write.
    submit broken '{"scrutiny_outcome":"blocking_escalate","failure_reason":"store unwritable"}'
    if [ "$NEXT_STATE" = "done_blocked" ]; then
        pass "broken store: blocking_escalate still reaches done_blocked"
    else
        fail "broken store: blocking_escalate should still reach done_blocked, got [$NEXT_STATE]"
    fi

    chmod u+w "$CTX_DIR" 2>/dev/null
fi

# --- Case 14c — the store unreadable, not merely unwritable --------------------
#
# The cases above lock the ctx directory against WRITES, where `exists` can still
# read it and reports the key PRESENT, so the check fires. Unreadable is the other
# half, and it is the case that killed an earlier version of this block.
#
# `ctx_exists` collapses "absent" and "unreadable" into false, so on an unreadable
# store `exists` reports ABSENT while the key is still on disk. A block that
# trusted `exists` alone would exit 0 believing the removal worked. The refusal
# that follows is real but NOT durable: koto buffers the refused evidence and
# re-evaluates it, so the moment the permission problem clears, the gate reads the
# surviving key and the workflow advances on the previous round's artifact. The
# defect this whole change exists to close, reachable through a transient outage.
#
# That is why the block stops on EITHER signal -- `remove` reporting failure, or
# `exists` still reporting present. `exists` catches a remove that lied about
# succeeding; `remove`'s status catches an `exists` blinded by an unreadable
# store. Neither alone is enough, which is the point of the assertions below.

echo "--- Case 14c: an unreadable store is caught, and the refusal is durable"

to_scrutiny unreadable
seed unreadable scrutiny_results.json

UCTX=$(find "$HOME" -type d -path '*unreadable*' -name ctx 2>/dev/null | head -1)
if [ -z "$UCTX" ] || [ ! -d "$UCTX" ]; then
    fail "could not locate the ctx directory for session 'unreadable' -- case 14c did not run"
else
    LOCKED_DIR="$UCTX"
    chmod a-rx "$UCTX"
    out=$(render "$SCRUTINY_BLOCK" unreadable 2>/dev/null | bash 2>/dev/null)
    block_rc=$?
    chmod u+rwx "$UCTX" 2>/dev/null

    if [ -f "$UCTX/scrutiny_results.json" ]; then
        pass "unreadable store: the key really is still on disk, so the case tests what it claims"
    else
        fail "unreadable store: expected the key to survive; the case proves nothing without it"
    fi

    # The load-bearing assertion. `exists` reports absent here, so a block
    # trusting it alone exits 0 and lets the agent submit the advancing outcome.
    if [ "$block_rc" -ne 0 ]; then
        pass "unreadable store: the block exits non-zero ($block_rc) on remove's status, not exists'"
    else
        fail "unreadable store: block exited 0 -- it trusted exists, which cannot see the surviving key"
    fi

    if printf '%s' "$out" | grep -q 'scrutiny_results.json'; then
        pass "unreadable store: the diagnostic reaches stdout and names the key"
    else
        fail "unreadable store: expected a diagnostic naming the key; got: [$out]"
    fi

    # And the reason it must be caught here: prove the refusal would NOT have
    # held on its own. Submit the advancing outcome while unreadable, restore
    # permissions, and make no further submission. If the workflow has moved on,
    # the gate alone was never a durable defence.
    to_scrutiny buffered
    seed buffered scrutiny_results.json
    BCTX=$(find "$HOME" -type d -path '*buffered*' -name ctx 2>/dev/null | head -1)
    if [ -n "$BCTX" ] && [ -d "$BCTX" ]; then
        LOCKED_DIR="$BCTX"
        chmod a-rx "$BCTX"
        koto next buffered --with-data '{"scrutiny_outcome":"passed"}' >/dev/null 2>&1
        chmod u+rwx "$BCTX" 2>/dev/null
        settled=$(koto next buffered 2>/dev/null | grep -o '"state":"[^"]*"' | tail -1 | cut -d'"' -f4)
        if [ "$settled" = "review" ]; then
            pass "the gate alone is not a durable defence: buffered evidence advances to review once readable (which is why the block must catch this itself)"
        else
            fail "expected the buffered submission to advance to review once readable, got [$settled] -- if koto changed, revisit why the block checks remove's status"
        fi
    else
        fail "could not locate the ctx directory for session 'buffered'"
    fi
fi

# The other three escalate exits, on a store that is writable -- the transitions
# carry no gate reference, and this is the check that keeps that true.
echo "--- Case 14b: the remaining escalate exits stay reachable"

to_analysis esc-analysis
submit esc-analysis '{"plan_outcome":"scope_changed_escalate"}'
if [ "$NEXT_STATE" = "done_blocked" ]; then
    pass "analysis: scope_changed_escalate reaches done_blocked with plan.md absent"
else
    fail "analysis: scope_changed_escalate expected done_blocked, got [$NEXT_STATE]"
fi

to_analysis esc-missing
submit esc-missing '{"plan_outcome":"blocked_missing_context"}'
if [ "$NEXT_STATE" = "done_blocked" ]; then
    pass "analysis: blocked_missing_context reaches done_blocked with plan.md absent"
else
    fail "analysis: blocked_missing_context expected done_blocked, got [$NEXT_STATE]"
fi

to_implementation esc-impl
submit esc-impl '{"implementation_status":"partial_tests_failing_escalate","rationale":"x"}'
if [ "$NEXT_STATE" = "done_blocked" ]; then
    pass "implementation: partial_tests_failing_escalate reaches done_blocked"
else
    fail "implementation: partial_tests_failing_escalate expected done_blocked, got [$NEXT_STATE]"
fi

to_finalization esc-defer
submit esc-defer '{"finalization_status":"deferral_requested"}'
if [ "$NEXT_STATE" = "deferral_approval" ]; then
    pass "finalization: deferral_requested reaches deferral_approval with summary.md absent"
else
    fail "finalization: deferral_requested expected deferral_approval, got [$NEXT_STATE]"
fi

# --- Case 15 — the three panel blocks are one block ---------------------------
#
# The blocks are duplicated across three files rather than referenced once, so
# nothing but this assertion keeps them from drifting. Only the first line may
# differ: it carries the phase's own outcome field, which the diagnostic must
# name.

echo "--- Case 15: the three panel blocks are identical below their first line"

tail_of() { printf '%s\n' "$1" | sed '1d'; }

s_tail=$(tail_of "$SCRUTINY_BLOCK")
r_tail=$(tail_of "$REVIEW_BLOCK")
q_tail=$(tail_of "$QA_BLOCK")

if [ "$s_tail" = "$r_tail" ] && [ "$s_tail" = "$q_tail" ]; then
    pass "the three panel blocks are byte-identical below their first line"
else
    fail "the three panel blocks have drifted below their first line"
    printf '%s\n' "$s_tail" > "$WORKDIR/s.txt"
    printf '%s\n' "$r_tail" > "$WORKDIR/r.txt"
    printf '%s\n' "$q_tail" > "$WORKDIR/q.txt"
    diff "$WORKDIR/s.txt" "$WORKDIR/r.txt" | head -20
    diff "$WORKDIR/s.txt" "$WORKDIR/q.txt" | head -20
fi

# Each first line must actually name its own phase's field, or the identity
# assertion above could be satisfied by three copies of one file.
case "$(printf '%s\n' "$SCRUTINY_BLOCK" | head -1)" in
    *scrutiny_outcome*) pass "phase-4a's block names scrutiny_outcome" ;;
    *) fail "phase-4a's block should name scrutiny_outcome on its first line" ;;
esac
case "$(printf '%s\n' "$REVIEW_BLOCK" | head -1)" in
    *review_outcome*) pass "phase-4b's block names review_outcome" ;;
    *) fail "phase-4b's block should name review_outcome on its first line" ;;
esac
case "$(printf '%s\n' "$QA_BLOCK" | head -1)" in
    *qa_outcome*) pass "phase-4c's block names qa_outcome" ;;
    *) fail "phase-4c's block should name qa_outcome on its first line" ;;
esac

# --- Case 16 — no block guards its removal with `exists` ----------------------
#
# `ctx_exists` reports false for a store it cannot read as well as for a key that
# is not there, so a guard would skip a key whose artifact is really still in
# place. The design rules the guard out; this keeps it out.

echo "--- Case 16: no block guards its removal with an exists check"

for pair in \
    "SCRUTINY_BLOCK:phase-4a-scrutiny.md" \
    "REVIEW_BLOCK:phase-4b-review.md" \
    "QA_BLOCK:phase-4c-qa.md" \
    "ANALYSIS_BLOCK:phase-3-analysis.md" \
    "IMPL_BLOCK:phase-4-implementation.md" \
    "FINAL_BLOCK:phase-5-finalization.md" \
    "VERIFY_BLOCK:koto-templates/work-on.md"
do
    var=${pair%%:*}
    src=${pair#*:}
    eval "blk=\${$var}"
    # The `exists` call must come after the `remove`, never before it.
    first=$(printf '%s\n' "$blk" | grep -n 'koto context remove' | head -1 | cut -d: -f1)
    guard=$(printf '%s\n' "$blk" | grep -n 'koto context exists' | head -1 | cut -d: -f1)
    if [ -n "$first" ] && [ -n "$guard" ] && [ "$guard" -gt "$first" ]; then
        pass "$src: the exists check follows the remove, and does not guard it"
    else
        fail "$src: expected remove (line ${first:-?}) before exists (line ${guard:-?})"
    fi
done

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

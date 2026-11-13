#!/usr/bin/env bash
#
# loopback-resume_test.sh - a second review round must not re-run the first
# round's loop-back
#
# When /review-plan returns a loop-back verdict, its loopback key
# (work/review_loopback.md) stays in the plan session after the loop-back has
# run, so Phases 3 and 4 can read its correction hints; only the next verdict
# replaces it. A resume check that routes on that key existing, alone, sends
# a run that comes back for its second review round straight into the first
# round's loop-back again, instead of reviewing the rebuilt plan.
#
# The rule each resume check must state instead compares two numbers: R, the
# loopback key's `round`, and N, `review_rounds` in work/analysis.md (0 when
# absent). R == N + 1 means the loop-back is pending and runs; R <= N means it
# already ran and the next review round (N + 1) runs, removing nothing;
# R > N + 1 is an inconsistent state that stops and reports.
#
# This suite reads the prose, not an agent's behaviour (the evals cover that):
#   1. plan Phase 6 Resume Check states the round rule
#   2. review-plan's own Resume Logic states the round rule
#   3. review-plan Phase 6's loopback key lifecycle note states the round rule
#      and no longer decides "already ran" by the manifest
#   4. plan Phase 1 step 1.4 carries review_rounds from the loopback key's
#      round, since a loop-back to Phase 1 removes the old analysis key
#   5. the loop_target 1 note carries the loopback key's round, not
#      "that value plus one"
#
# Usage (from the repository root, as check-skill.sh runs it):
#   bash skills/review-plan/scripts/loopback-resume_test.sh
#
# Exit codes:
#   0 - all checks passed
#   1 - one or more checks failed
#   2 - the suite could not run (a file it reads is missing)

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd -P) || exit 2
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd -P) || exit 2

PLAN_REVIEW="skills/plan/references/phases/phase-6-review.md"
PLAN_ANALYSIS="skills/plan/references/phases/phase-1-analysis.md"
REVIEW_SKILL="skills/review-plan/SKILL.md"
REVIEW_LOOPBACK="skills/review-plan/references/phases/phase-6-loop-back.md"

for f in "$PLAN_REVIEW" "$PLAN_ANALYSIS" "$REVIEW_SKILL" "$REVIEW_LOOPBACK"; do
    if [ ! -f "$REPO_ROOT/$f" ]; then
        echo "ERROR: missing $REPO_ROOT/$f" >&2
        exit 2
    fi
done

PASS_COUNT=0
FAIL_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS: $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL: $1"
}

# The three conditions, tolerant of spacing. The leading class keeps a word
# ending in R (such as "OR") from counting.
EQ_RE='(^|[^A-Za-z0-9_])R[[:space:]]*==[[:space:]]*N[[:space:]]*\+[[:space:]]*1'
LE_RE='(^|[^A-Za-z0-9_])R[[:space:]]*<=[[:space:]]*N'
GT_RE='(^|[^A-Za-z0-9_])R[[:space:]]*>[[:space:]]*N[[:space:]]*\+[[:space:]]*1'
ANY_RE='(^|[^A-Za-z0-9_])R[[:space:]]*(==|<=|>)'
# A line that routes on the loopback key existing.
ROUTE_RE='review_loopback\.md`?[[:space:]]+exists'
NEXT_ROUND_RE='round[[:space:]]+N[[:space:]]*\+[[:space:]]*1'

# section <file> <start-regex> <end-regex>
# Prints each line from the first start match up to, not including, the next
# end match, as <line number>:<text>. An end match inside a fenced code block
# does not end the section, so a template's own headings stay in it.
section() {
    awk -v start="$2" -v stop="$3" '
        on && !fence && $0 ~ stop { exit }
        !on && $0 ~ start { on = 1; print NR ":" $0; next }
        on { print NR ":" $0 }
        on && /^[ \t]*```/ { fence = !fence }
    ' "$1"
}

# check_conditions <label> <text>
# The three round conditions are stated, each with its outcome.
check_conditions() {
    local label="$1" text="$2" lines
    if lines=$(grep -E "$EQ_RE" <<<"$text"); then
        if grep -qi 'execute' <<<"$lines"; then
            pass "$label states R == N + 1 executes the loop-back"
        else
            fail "$label states R == N + 1 without executing the loop-back: $lines"
        fi
    else
        fail "$label does not state R == N + 1"
    fi
    if grep -qE "$LE_RE" <<<"$text"; then
        if grep -qiE "$NEXT_ROUND_RE" <<<"$text"; then
            pass "$label states R <= N runs round N + 1"
        else
            fail "$label states R <= N but not that round N + 1 runs"
        fi
    else
        fail "$label does not state R <= N"
    fi
    if lines=$(grep -E "$GT_RE" <<<"$text"); then
        if grep -qi 'stop' <<<"$lines"; then
            pass "$label states R > N + 1 stops"
        else
            fail "$label states R > N + 1 without stopping: $lines"
        fi
    else
        fail "$label does not state R > N + 1"
    fi
}

# check_rule <label> <text>
# No line routes on the loopback key existing without a round condition, and
# the three conditions are stated.
check_rule() {
    local label="$1" text="$2" line alone=0
    while IFS= read -r line; do
        if [[ $line =~ $ROUTE_RE ]] && ! [[ $line =~ $ANY_RE ]]; then
            fail "$label routes on the loopback key alone: $line"
            alone=1
        fi
    done <<<"$text"
    if [ "$alone" -eq 0 ]; then
        pass "$label does not route on the loopback key alone"
    fi
    check_conditions "$label" "$text"
}

# require_section <label> <text>: fails when the section was not found.
require_section() {
    if [ -z "$2" ]; then
        fail "$1 not found"
        return 1
    fi
    return 0
}

# --- 1. plan Phase 6 Resume Check -------------------------------------------
label="$PLAN_REVIEW Resume Check"
text=$(section "$REPO_ROOT/$PLAN_REVIEW" '^## Resume Check' '^## ')
if require_section "$label" "$text"; then
    check_rule "$label" "$text"
fi

# --- 2. review-plan Resume Logic --------------------------------------------
label="$REVIEW_SKILL Resume Logic"
text=$(section "$REPO_ROOT/$REVIEW_SKILL" '^## Resume Logic' '^## ')
if require_section "$label" "$text"; then
    check_rule "$label" "$text"
fi

# --- 3. loopback key lifecycle note -----------------------------------------
label="$REVIEW_LOOPBACK lifecycle note"
text=$(section "$REPO_ROOT/$REVIEW_LOOPBACK" 'Loopback key lifecycle' '^---')
if require_section "$label" "$text"; then
    check_conditions "$label" "$text"
    if grep -qiF -e 'manifest key exists' -e 'manifest key is gone' \
        -e 'because the manifest is absent' -e 'whether the manifest still exists' <<<"$text"; then
        fail "phase-6-loop-back.md lifecycle note decides \"already ran\" by the manifest"
    else
        pass "phase-6-loop-back.md lifecycle note does not decide \"already ran\" by the manifest"
    fi
fi

# --- 4. plan Phase 1 step 1.4 carries the counter ---------------------------
label="$PLAN_ANALYSIS step 1.4"
text=$(section "$REPO_ROOT/$PLAN_ANALYSIS" '^### 1.4 Write Artifact' '^## ')
if require_section "$label" "$text"; then
    if grep -qF 'work/review_loopback.md' <<<"$text" && grep -qF 'review_rounds' <<<"$text"; then
        pass "phase-1-analysis.md step 1.4 carries review_rounds across a loop-back"
    else
        fail "phase-1-analysis.md step 1.4 does not carry review_rounds across a loop-back"
    fi
fi

# --- 5. loop_target 1 note --------------------------------------------------
label="$REVIEW_LOOPBACK loop_target 1 note"
text=$(section "$REPO_ROOT/$REVIEW_LOOPBACK" '^### loop_target: 1[^0-9]' '^### ')
if require_section "$label" "$text"; then
    if grep -qi 'plus one' <<<"$text" || ! grep -qF '`round`' <<<"$text"; then
        fail "loop_target 1 note does not carry the loopback key's round"
    else
        pass "loop_target 1 note carries the loopback key's round"
    fi
fi

echo ""
echo "loopback-resume_test: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

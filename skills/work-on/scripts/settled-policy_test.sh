#!/usr/bin/env bash
# settled-policy_test.sh -- do /work-on's files still state each settled policy
# the way its decision record says?
#
# Each case below pins one decision under docs/decisions/ against the files
# that carry it, so a later edit that brings the old statement back fails here
# rather than in a run. The checks read the shipped files directly; no engine
# is needed, so every case runs on the bash 3.2 floor too.
#
#   force-push-after-rebase -- a branch that is behind catches up by merging
#     main in, never by rebasing, and pushes without force.
#   retry-caps -- each loop's cap is stated once, in its state's directive,
#     marked temporary, and no file tells an unattended run to ask the user.
#   ci-fix-ends-run-unverified -- no directive loads finishing-obligations.md
#     (the routing itself is driven in ci-monitor-role_test.sh).
#   cross-issue-context-no-consumer -- a child reads earlier siblings'
#     summary.md through koto at analysis, once each; no current-context.md.
#   worktree-discipline-vs-drift-state, no-cleanup-on-child-ticks -- phase 2.5
#     drops its pointer to the worktree reference and its retention exception.
#
# Usage: settled-policy_test.sh
# Exit codes: 0 all pass, 1 any failed.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
ROOT=$(cd "$SKILL_DIR/../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

# The files a case searches: /work-on's own prose and templates, and the shared
# worktree reference its PR carries. Test files are left out, since they name
# the forbidden forms in order to look for them, and so are the evals, which
# are scenario prompts and fixtures rather than instructions the skill ships.
policy_files() {
    find "$SKILL_DIR" -type f \( -name '*.md' -o -name '*.sh' -o -name '*.tsv' \) \
        ! -name '*_test.sh' ! -path '*/evals/*'
    echo "$ROOT/references/worktree-discipline.md"
}

# absent <label> <extended-regex>: no policy file matches the pattern.
absent() {
    local label=$1 pattern=$2 hits
    hits=$(policy_files | while IFS= read -r f; do
        grep -nE -- "$pattern" "$f" 2>/dev/null | sed "s|^|${f#"$ROOT"/}:|"
    done)
    if [ -z "$hits" ]; then pass "$label"; else fail "$label"; echo "$hits"; fi
}

# present <label> <file> <fixed-string>: the file states the settled form.
present() {
    local label=$1 file=$2 text=$3
    if grep -qF -- "$text" "$ROOT/$file"; then pass "$label"; else fail "$label ($file)"; fi
}

# --- force-push-after-rebase ------------------------------------------------

absent "no force push anywhere in /work-on" \
    'force-with-lease|push[^|;&]*[[:space:]](--force|-f)([[:space:]]|$)'
absent "no rebase command anywhere in /work-on" \
    'git rebase'
present "phase-6 catches up by merging main in" \
    skills/work-on/references/phases/phase-6-pr.md 'git merge --no-edit origin/main'
present "phase-6 pushes without force" \
    skills/work-on/references/phases/phase-6-pr.md 'never with a force option'
present "worktree discipline catches up by merging" \
    references/worktree-discipline.md 'git merge origin/<tracking-branch>'

# --- retry-caps --------------------------------------------------------------
# Each loop's cap is stated once, in its state's directive, and nothing else in
# /work-on restates a number or tells an unattended run to ask the user.

TEMPLATE_REL=skills/work-on/koto-templates/work-on.md

# directive_of <state>: the template body section for a state, heading to heading.
directive_of() {
    awk -v s="## $1" '
        $0 == s { on = 1; next }
        on && /^## / { exit }
        on { print }
    ' "$ROOT/$TEMPLATE_REL"
}

# cap_in <state> <fixed-string>: the state's directive carries the cap and says
# the prose is temporary.
cap_in() {
    local state=$1 text=$2 body joined
    body=$(directive_of "$state")
    # Prose wraps anywhere, so the phrases are matched on the joined text.
    joined=$(printf '%s\n' "$body" | tr '\n' ' ')
    if printf '%s\n' "$joined" | grep -qF -- "$text" \
        && printf '%s\n' "$joined" | grep -qF -- "until koto enforces it from its attempt counts, with the same number"; then
        pass "$state states its cap once, as temporary"
    else
        fail "$state directive lacks its cap ($text) or the temporary note"
    fi
    if [ "$(printf '%s\n' "$body" | grep -c '^Retry cap:')" -eq 1 ]; then
        pass "$state states one cap"
    else
        fail "$state states the cap more than once, or not at all"
    fi
}

cap_in analysis '`scope_changed_retry` up to 3 times'
cap_in implementation '`partial_tests_failing_retry` up to 3 times'
cap_in pr_creation '`creation_failed_retry` up to 3 times'
cap_in scrutiny '2 blocking retries per run, shared by scrutiny, review and qa_validation'
cap_in review '2 blocking retries per run, shared by scrutiny, review and qa_validation'
cap_in qa_validation '2 blocking retries per run, shared by scrutiny, review and qa_validation'
cap_in ci_monitor 'Retry cap: 3 fix pushes'

absent "no phase or reference file restates a retry number" \
    'up to 3\)|\(up to [0-9]|[0-9]\+ retry cycles|[0-9]-[0-9] iterations|capped at [0-9] cycles'
absent "no /work-on file tells the run to ask the user about CI" \
    '[Ii]f (stuck|a check).*ask the user'

# --- ci-fix-ends-run-unverified ----------------------------------------------
# A CI fix goes back to ci_monitor, and the state's fallback edge fails the run;
# ci-monitor-role_test.sh drives that routing through koto. The same change
# unloads finishing-obligations.md: no directive sends the agent to it, since
# it is an authoring reference for maintainers, not something a run acts on.

if grep -nF 'finishing-obligations.md' "$ROOT/$TEMPLATE_REL" "$SKILL_DIR/SKILL.md" \
    "$SKILL_DIR"/references/phases/*.md; then
    fail "a work-on directive, SKILL.md or phase file points at finishing-obligations.md"
else
    pass "no work-on directive points at finishing-obligations.md"
fi

# --- cross-issue-context-no-consumer (/work-on's reader) ----------------------
# A child reads its earlier siblings' summary.md through koto, once each, at
# analysis; nothing builds or reads a current-context.md file.

PHASE3=skills/work-on/references/phases/phase-3-analysis.md
present "analysis reads each earlier child's summary through koto" \
    "$PHASE3" 'koto context get <child> summary.md'
present "analysis finds the siblings through koto" \
    "$PHASE3" 'koto workflows --children'
if tr '\n' ' ' <"$ROOT/$PHASE3" | grep -qF 'never poll or re-read a summary in a loop'; then
    pass "analysis says each summary is read once, never in a loop"
else
    fail "analysis does not say each summary is read once, never in a loop"
fi
if directive_of analysis | tr '\n' ' ' | grep -qF 'summary.md` through `koto context get`'; then
    pass "the analysis directive names the summary read"
else
    fail "the analysis directive does not name the summary read"
fi
absent "no /work-on file builds or reads current-context.md" 'current-context\.md'

# --- worktree-discipline-vs-drift-state, no-cleanup-on-child-ticks ----------
# Phase 2.5, which /execute's orchestrator reads, no longer loads the worktree
# discipline reference, and states the retention rule the way the retention
# reference does: every tick, root or child.

PHASE25=skills/work-on/references/phases/phase-2.5-worktree-discipline.md
# The pointer was a path to read (`${CLAUDE_PLUGIN_ROOT}/references/...`); the
# file's own name and its sample rationale mention the reference without one.
if grep -qF '/references/worktree-discipline.md' "$ROOT/$PHASE25"; then
    fail "phase 2.5 still points at references/worktree-discipline.md"
else
    pass "phase 2.5 does not load references/worktree-discipline.md"
fi
if grep -qF 'must not' "$ROOT/$PHASE25"; then
    fail "phase 2.5 still says some /work-on ticks must not carry --no-cleanup"
else
    pass "phase 2.5 carries no exception to the every-tick retention rule"
fi

echo
echo "passed: $PASS_COUNT, failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]

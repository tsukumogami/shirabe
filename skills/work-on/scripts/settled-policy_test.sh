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
    skills/work-on/references/phases/phase-6-pr.md 'git merge origin/main'
present "phase-6 pushes without force" \
    skills/work-on/references/phases/phase-6-pr.md 'never with a force option'
present "worktree discipline catches up by merging" \
    references/worktree-discipline.md 'git merge origin/<tracking-branch>'

echo
echo "passed: $PASS_COUNT, failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]

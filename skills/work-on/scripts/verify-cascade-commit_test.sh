#!/usr/bin/env bash
# verify-cascade-commit_test.sh — the case that matters is Case 4.
#
# Every other case here guards a boundary. Case 4 is the reason the script
# exists: a chain document transitioned on disk and never staged into the
# finalization commit. A verification that reads the working tree passes that
# state, which is precisely how the cascade's own post-verify passes it. If
# Case 4 ever goes green against a tree-reading implementation, this file has
# stopped testing anything.
#
# Usage: verify-cascade-commit_test.sh
# Exit codes: 0 all pass, 1 any failed.

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
VERIFY="$SCRIPT_DIR/verify-cascade-commit.sh"

PASS_COUNT=0
FAIL_COUNT=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass() { echo -e "${GREEN}PASS${NC}: $*"; PASS_COUNT=$((PASS_COUNT+1)); }
fail() { echo -e "${RED}FAIL${NC}: $*"; FAIL_COUNT=$((FAIL_COUNT+1)); }

TMPS=()
cleanup() { for d in "${TMPS[@]:-}"; do [[ -n "$d" ]] && rm -rf "$d"; done; }
trap cleanup EXIT

PLAN=docs/plans/PLAN-x.md
PRD=docs/prds/PRD-x.md
DESIGN=docs/designs/DESIGN-x.md
DESIGN_CURRENT=docs/designs/current/DESIGN-x.md

doc() {
    # doc <status> [<upstream>] — a minimal frontmatter document.
    printf -- '---\nstatus: %s\n' "$1"
    [[ -n "${2:-}" ]] && printf -- 'upstream: %s\n' "$2"
    printf -- '---\n\n# body\n'
}

# new_repo — a repo mid-run: the chain exists, nothing cascaded yet.
new_repo() {
    local d; d=$(mktemp -d); TMPS+=("$d")
    (
        cd "$d" || exit 1
        git init -q .
        git config user.email t@example.invalid
        git config user.name t
        mkdir -p docs/plans docs/prds docs/designs docs/designs/current
        doc Active "$DESIGN" > "$PLAN"
        doc Accepted "$PRD" > "$DESIGN"
        doc Accepted > "$PRD"
        git add -A
        git commit -qm "seed"
    ) >/dev/null 2>&1
    echo "$d"
}

# cascade <dir> <mode> — perform the finalization commit.
#   full     — every document transitioned AND staged. The correct cascade.
#   unstaged — every document transitioned on disk, but only the PLAN deletion
#              is staged. The staging defect: the tree looks finished.
cascade() {
    local d="$1" mode="$2"
    (
        cd "$d" || exit 1
        rm "$PLAN"
        doc Done > "$PRD"
        git mv "$DESIGN" "$DESIGN_CURRENT" 2>/dev/null || mv "$DESIGN" "$DESIGN_CURRENT"
        doc Current "$PRD" > "$DESIGN_CURRENT"
        if [[ "$mode" == "full" ]]; then
            git add -A
        else
            git add -- "$PLAN"
        fi
        git commit -qm "chore: finalize chain"
    ) >/dev/null 2>&1
}

# expect <label> <expected-exit> <dir> [<plan-path>]
expect() {
    # ${4-...} rather than ${4:-...}: Case 8 passes an EMPTY plan path on
    # purpose, and the colon form would substitute the default for it and test
    # the wrong thing.
    local label="$1" want="$2" dir="$3" plan="${4-$PLAN}"
    local got
    (cd "$dir" && bash "$VERIFY" "$plan" >/dev/null 2>&1); got=$?
    if [[ "$got" == "$want" ]]; then pass "$label (exit $got)"
    else fail "$label: expected exit $want, got $got"; fi
}

# Case 1 — the correct cascade verifies.
T=$(new_repo); cascade "$T" full
expect "a fully staged cascade verifies" 0 "$T"

# Case 2 — the PLAN is still on disk.
T=$(new_repo)
expect "an undeleted PLAN is distinguished" 2 "$T"

# Case 3 — the PLAN was removed but never committed. The tree looks finished.
T=$(new_repo)
(cd "$T" && rm "$PLAN") >/dev/null 2>&1
expect "an uncommitted deletion is distinguished" 3 "$T"

# ---------------------------------------------------------------------------
# Case 4 — THE CASE THIS FILE EXISTS FOR.
#
# Every document is at its terminal posture ON DISK. The PLAN is gone and its
# deletion is committed. Only the staging is missing, so the finalization commit
# does not contain the PRD or the DESIGN. A verification that reads the working
# tree sees a finished cascade; reading the commit's own paths is what catches
# it, and the exit code says which of the five things went wrong.
# ---------------------------------------------------------------------------
T=$(new_repo); cascade "$T" unstaged
expect "a document transitioned on disk but absent from the commit is caught" 5 "$T"

# Case 4b — and the tree really does look finished, so Case 4 is not passing
# for some incidental reason. If this assertion fails, Case 4 proves nothing.
if [[ -f "$T/$DESIGN_CURRENT" ]] && [[ ! -e "$T/$PLAN" ]] &&
   grep -q "status: Done" "$T/$PRD" && grep -q "status: Current" "$T/$DESIGN_CURRENT"; then
    pass "the unstaged tree is indistinguishable from a finished one on disk"
else
    fail "the unstaged fixture is not in the state Case 4 claims to test"
fi

# Case 5 — a document left at its pre-terminal status.
T=$(new_repo)
(
    cd "$T" || exit 1
    rm "$PLAN"
    git mv "$DESIGN" "$DESIGN_CURRENT"
    doc Current "$PRD" > "$DESIGN_CURRENT"
    git add -A && git commit -qm "partial"
) >/dev/null 2>&1
expect "a document left at its pre-terminal status is distinguished" 4 "$T"

# Case 6 — R4: an anchor with no upstream chain. The cascade commits and pushes
# its own deletion alone. Facts 1 and 2 carry the run; there is no chain to
# check, and that must verify rather than read as an empty failure.
T=$(new_repo)
(
    cd "$T" || exit 1
    doc Active > "$PLAN"
    git add -A && git commit -qm "unchained plan"
    rm "$PLAN"
    git add -A && git commit -qm "chore: delete plan"
) >/dev/null 2>&1
expect "an anchor with no upstream chain verifies on its own deletion" 0 "$T"

# Case 7 — outside a git repository, undecided rather than failed or passed.
T=$(mktemp -d); TMPS+=("$T")
expect "a non-repository cannot be decided" 6 "$T"

# Case 8 — no argument.
T=$(new_repo)
expect "a missing plan argument cannot be decided" 6 "$T" ""

echo
echo "verify-cascade-commit_test.sh: $PASS_COUNT passed, $FAIL_COUNT failed"
[[ "$FAIL_COUNT" -eq 0 ]]

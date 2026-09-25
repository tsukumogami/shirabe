#!/usr/bin/env bash
# node-cut_test.sh — a node branch comes from the default branch, in its own
# worktree, and is never re-cut
# Part of the execute skill
#
# Each case runs node-cut.sh against a real git repository whose origin is a
# local bare repository, checked out on a coordination branch that carries the
# PLAN (as the coordination checkout does).
#
# Cases:
#   a slug or node id outside its pattern       exit 64, no worktree
#   a fresh cut                                 impl/<slug>-<node-id> in its
#     own worktree; merge-base with the default tip is that tip; no
#     coordination-branch commit is an ancestor; the PLAN is not in its tree
#   a re-run                                    reuses the worktree; the branch
#     tip is unchanged even after the default branch moved (no re-cut, no
#     rebase)
#   a branch that exists without a worktree     attached as it stands
#   a node in another repository (--repo-dir)   cut in that clone
#
# Usage: node-cut_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
CUT="$SCRIPT_DIR/node-cut.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

REPO="$CT_WORK/coord"
ct_repo "$REPO"
ct_plan "$REPO"
(cd "$REPO" && git add docs && git commit -q -m "docs: plan")
COORD_COMMIT=$(git -C "$REPO" rev-parse HEAD)
TIP=$(git -C "$REPO" rev-parse origin/main)

kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# --- usage ------------------------------------------------------------------------

for args in "T pr-x" "t Pr-x" "t 1x" "t" "t pr-x --nope y"; do
    # shellcheck disable=SC2086
    out=$(cd "$REPO" && bash "$CUT" $args 2>/dev/null); rc=$?
    if [ "$rc" -eq 64 ] && [ -z "$out" ]; then
        pass "usage [$args] exits 64 with nothing printed"
    else
        fail "usage [$args]: rc=$rc out=[$out]"
    fi
done
if git -C "$REPO" worktree list | grep -q 'impl/'; then
    fail "a usage error created a worktree"
else
    pass "no usage error created a worktree"
fi

# --- a fresh cut ------------------------------------------------------------------

OUT=$(cd "$REPO" && bash "$CUT" t pr-repo-a-core 2>"$CT_WORK/cut.err"); rc=$?
WT=$(kv "$OUT" worktree)
BR=$(kv "$OUT" branch)
BASE=$(kv "$OUT" base)
if [ "$rc" -eq 0 ] && [ "$(kv "$OUT" cut)" = new ] && [ "$BR" = impl/t-pr-repo-a-core ] && [ -d "$WT" ]; then
    pass "a fresh cut makes impl/t-pr-repo-a-core in its own worktree"
else
    fail "a fresh cut: rc=$rc out=[$OUT]"
    cat "$CT_WORK/cut.err"
fi
[ "$BASE" = "$TIP" ] && pass "the recorded base is the default-branch tip" || fail "base [$BASE], tip [$TIP]"
if [ "$(git -C "$REPO" merge-base "$BR" "$TIP")" = "$TIP" ]; then
    pass "git merge-base <node-branch> <default-tip-at-cut> is that tip"
else
    fail "the node branch's merge-base with the default tip is not the tip"
fi
if git -C "$REPO" merge-base --is-ancestor "$COORD_COMMIT" "$BR"; then
    fail "a coordination-branch commit is an ancestor of the node branch"
else
    pass "no coordination-branch commit is an ancestor of the node branch"
fi
if [ -z "$(git -C "$REPO" ls-tree -r --name-only "$BR" -- docs/plans/PLAN-t.md)" ]; then
    pass "the node branch's tree carries no PLAN"
else
    fail "the node branch carries the PLAN"
fi
[ "$(git -C "$WT" symbolic-ref --short HEAD)" = "$BR" ] && pass "the worktree has the node branch checked out" \
    || fail "the worktree is not on $BR"
[ "$(git -C "$REPO" symbolic-ref --short HEAD)" = "$CT_CB" ] && pass "the coordination checkout stays on its branch" \
    || fail "the coordination checkout moved"
case "$WT" in "$REPO"/*) case "$WT" in "$REPO"/.git/*) pass "the worktree lives outside the work tree" ;; *) fail "the worktree [$WT] is inside the work tree" ;; esac ;; *) pass "the worktree lives outside the work tree" ;; esac

# --- a re-run: reused, never re-cut or rebased --------------------------------------

(cd "$WT" && git commit -q --allow-empty -m "node work")
NODE_TIP=$(git -C "$REPO" rev-parse "$BR")
# Move the default branch on the remote.
(
    cd "$CT_WORK" && git clone -q "$REPO.origin.git" mover && cd mover \
        && git commit -q --allow-empty -m "main moved" && git push -q origin main
) >/dev/null 2>&1
OUT=$(cd "$REPO" && bash "$CUT" t pr-repo-a-core 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && [ "$(kv "$OUT" cut)" = reused ] && [ "$(kv "$OUT" worktree)" = "$WT" ]; then
    pass "a re-run reuses the existing worktree"
else
    fail "a re-run: rc=$rc out=[$OUT]"
fi
[ "$(git -C "$REPO" rev-parse "$BR")" = "$NODE_TIP" ] && pass "a re-run leaves the branch tip alone after main moved" \
    || fail "a re-run moved the branch tip"

# --- a branch without a worktree ------------------------------------------------------

git -C "$REPO" worktree remove --force "$WT"
OUT=$(cd "$REPO" && bash "$CUT" t pr-repo-a-core 2>/dev/null); rc=$?
if [ "$rc" -eq 0 ] && [ "$(kv "$OUT" cut)" = attached ] && [ "$(git -C "$REPO" rev-parse "$BR")" = "$NODE_TIP" ]; then
    pass "a branch that exists without a worktree is attached as it stands"
else
    fail "attach: rc=$rc out=[$OUT] tip=$(git -C "$REPO" rev-parse "$BR")"
fi

# --- another repository -----------------------------------------------------------------

OTHER="$CT_WORK/other"
ct_repo "$OTHER"
OTIP=$(git -C "$OTHER" rev-parse origin/main)
OUT=$(cd "$REPO" && bash "$CUT" t pr-repo-b-default --repo-dir "$OTHER" 2>/dev/null); rc=$?
OWT=$(kv "$OUT" worktree)
if [ "$rc" -eq 0 ] && [ "$(git -C "$OWT" rev-parse HEAD)" = "$OTIP" ] \
    && git -C "$OTHER" show-ref --verify --quiet refs/heads/impl/t-pr-repo-b-default \
    && ! git -C "$REPO" show-ref --verify --quiet refs/heads/impl/t-pr-repo-b-default; then
    pass "a node in another repository is cut in that repository's clone"
else
    fail "--repo-dir: rc=$rc out=[$OUT]"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

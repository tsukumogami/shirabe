#!/usr/bin/env bash
# worktree-isolation_test.sh — a coordinated PLAN with nodes outside the
# repository whose worktree the session is isolated in stops before any node
# is cut; everything else passes
# Part of the execute skill
#
# Each case runs worktree-isolation.sh in a real git checkout whose origin
# names a GitHub repository (no remote is ever contacted), either in the main
# checkout or in a linked worktree made with `git worktree add`, the shape a
# harness's worktree isolation leaves. --session cases use the koto context
# stub from coord-test-helpers.sh.
#
# Cases:
#   a linked worktree of acme/repo-a, PLAN nodes in repo-a and repo-b
#                                  exit 1, isolation=isolated, the worktree,
#                                  worktree_repo=acme/repo-a,
#                                  other_repos=acme/repo-b, and a message
#                                  naming both repositories and what to do
#   nodes in repo-b only           other_repos=acme/repo-b, isolated
#   a single-repo coordinated PLAN in that worktree
#                                  passes, why=one-repository
#   the same name in other case    passes, why=one-repository
#   the two-repo PLAN from the main checkout (not isolated)
#                                  passes, why=not-a-worktree
#   a single-pr PLAN in the worktree
#                                  passes, why=not-coordinated
#   --session, isolated            exit 0; isolation_verdict=isolated,
#                                  worktree_repo, other_repos recorded
#   --session, pass                isolation_verdict=pass; the keys an
#                                  earlier isolated verdict wrote removed
#   --session, a failed write      exit 66
#   outside any git repository     exit 65, no verdict
#   usage                          exit 64
#
# Usage: worktree-isolation_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
CHECK="$SCRIPT_DIR/worktree-isolation.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

kv() { printf '%s\n' "$1" | sed -n "s/^$2=//p"; }

# make_checkout <name> <origin-url> [two-repo|remote|single-pr] -- a main
# checkout at $CT_WORK/<name> whose origin names <origin-url>, carrying the
# PLAN on its branch, and a linked worktree of it at $CT_WORK/<name>-wt.
make_checkout() {
    local d="$CT_WORK/$1"
    git init -q "$d"
    git -C "$d" remote add origin "$2"
    case "${3:-}" in
        single-pr)
            ct_plan "$d"
            sed -i.bak 's#^execution_mode: coordinated$#execution_mode: single-pr#' "$d/docs/plans/PLAN-t.md"
            rm -f "$d/docs/plans/PLAN-t.md.bak"
            ;;
        *) ct_plan "$d" "${3:-}" ;;
    esac
    git -C "$d" add docs
    git -C "$d" commit -q -m "docs: plan"
    git -C "$d" worktree add -q -b session/wt "$d-wt" >/dev/null 2>&1
}

run_check() { # run_check <dir> [flags...]
    local d="$1"; shift
    OUT=$(cd "$d" && bash "$CHECK" --plan docs/plans/PLAN-t.md "$@" 2>"$CT_WORK/stderr")
    RC=$?
}

# --- isolated, with nodes elsewhere ---------------------------------------------------

make_checkout two https://github.com/acme/repo-a.git two-repo
WT=$(cd "$CT_WORK/two-wt" && pwd -P)
run_check "$CT_WORK/two-wt"
if [ "$RC" -eq 1 ] && [ "$(kv "$OUT" isolation)" = isolated ] && [ "$(kv "$OUT" worktree)" = "$WT" ] \
    && [ "$(kv "$OUT" worktree_repo)" = acme/repo-a ] && [ "$(kv "$OUT" other_repos)" = acme/repo-b ]; then
    pass "isolated in repo-a's worktree with a node in repo-b: exit 1, both repositories named"
else
    fail "two-repo isolated: rc=$RC out=[$OUT] stderr=[$(cat "$CT_WORK/stderr")]"
fi
MSG=$(kv "$OUT" message)
case "$MSG" in
    *"before any node was cut"*"worktree of acme/repo-a ($WT)"*"nodes in acme/repo-b"*"Run this again from a session that isn't isolated in one repository's worktree"*)
        pass "the message names the worktree's repository, the other repository, and what to do" ;;
    *) fail "message: [$MSG]" ;;
esac

make_checkout remote https://github.com/acme/repo-a.git remote
run_check "$CT_WORK/remote-wt"
[ "$RC" -eq 1 ] && [ "$(kv "$OUT" other_repos)" = acme/repo-b ] \
    && pass "every node in another repository: isolated, other_repos=acme/repo-b" \
    || fail "remote-only: rc=$RC out=[$OUT]"

# --- passes ---------------------------------------------------------------------------

make_checkout one https://github.com/acme/repo-a.git
run_check "$CT_WORK/one-wt"
[ "$RC" -eq 0 ] && [ "$OUT" = "$(printf 'isolation=pass\nwhy=one-repository')" ] \
    && pass "a single-repo coordinated PLAN in that repository's worktree passes" \
    || fail "one-repo: rc=$RC out=[$OUT]"

make_checkout upper git@github.com:Acme/Repo-A.git
run_check "$CT_WORK/upper-wt"
[ "$RC" -eq 0 ] && [ "$(kv "$OUT" why)" = one-repository ] \
    && pass "repository names compare without regard to case" \
    || fail "case: rc=$RC out=[$OUT]"

run_check "$CT_WORK/two"
[ "$RC" -eq 0 ] && [ "$OUT" = "$(printf 'isolation=pass\nwhy=not-a-worktree')" ] \
    && pass "the two-repo PLAN from the main checkout (a session that isn't isolated) passes" \
    || fail "main checkout: rc=$RC out=[$OUT]"

make_checkout single https://github.com/acme/repo-a.git single-pr
run_check "$CT_WORK/single-wt"
[ "$RC" -eq 0 ] && [ "$(kv "$OUT" why)" = not-coordinated ] \
    && pass "a single-pr PLAN passes without reading nodes" \
    || fail "single-pr: rc=$RC out=[$OUT]"

# --- --session ------------------------------------------------------------------------

S=deliver-t
val() { cat "$CASE/ctx/$S/$1" 2>/dev/null; }

ct_case session-isolated
run_check "$CT_WORK/two-wt" --session "$S"
if [ "$RC" -eq 0 ] && [ "$(val isolation_verdict)" = isolated ] && [ "$(val worktree_repo)" = acme/repo-a ] \
    && [ "$(val other_repos)" = acme/repo-b ] && [ "$(kv "$OUT" isolation)" = isolated ]; then
    pass "--session records isolated with both repositories, exit 0"
else
    fail "session isolated: rc=$RC verdict=[$(val isolation_verdict)] wt=[$(val worktree_repo)] others=[$(val other_repos)]"
fi

run_check "$CT_WORK/one-wt" --session "$S"
if [ "$RC" -eq 0 ] && [ "$(val isolation_verdict)" = pass ] && [ ! -e "$CASE/ctx/$S/worktree_repo" ] \
    && [ ! -e "$CASE/ctx/$S/other_repos" ]; then
    pass "--session on a pass records pass and removes the earlier verdict's keys"
else
    fail "session pass: rc=$RC verdict=[$(val isolation_verdict)] keys=[$(ls "$CASE/ctx/$S" | tr '\n' ' ')]"
fi

ct_case session-write-fails
export KOTO_FAIL_ADD=isolation_verdict
run_check "$CT_WORK/two-wt" --session "$S"
unset KOTO_FAIL_ADD
[ "$RC" -eq 66 ] && pass "a failed koto write exits 66" || fail "write fails: rc=$RC out=[$OUT]"

# --- undecided and usage ---------------------------------------------------------------

mkdir -p "$CT_WORK/nogit/docs/plans"
cp "$CT_WORK/two/docs/plans/PLAN-t.md" "$CT_WORK/nogit/docs/plans/"
ct_case nogit
run_check "$CT_WORK/nogit" --session "$S"
[ "$RC" -eq 65 ] && [ ! -e "$CASE/ctx/$S/isolation_verdict" ] \
    && pass "outside a git repository: exit 65, no verdict" \
    || fail "nogit: rc=$RC verdict=[$(val isolation_verdict)]"

for args in "" "--plan" "--plan a --plan b" "--plan a --session" "--plan a --session -x" "--plan a --nope"; do
    # shellcheck disable=SC2086
    (cd "$CT_WORK/two-wt" && bash "$CHECK" $args >/dev/null 2>&1)
    rc=$?
    [ "$rc" -eq 64 ] && pass "usage [$args]: exit 64" || fail "usage [$args]: rc=$rc"
done

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

#!/usr/bin/env bash
# repo-visibility_test.sh — the Coordination-PR Visibility Rule, one node at a
# time, read live
# Part of the execute skill
#
# repo-visibility.sh reads each repository's `visibility` from `gh api
# repos/<r>` (the eval gh shim's repository model, see coord-test-helpers.sh),
# the read the merge gate's own resolver makes. The home repository is
# acme/repo-a and the node's is acme/repo-b.
#
# Cases:
#   the four visibility pairs, home over node:
#     public over public     allowed (exit 0)
#     private over public    allowed: a private coordination PR may index a
#                            public node
#     private over private   allowed
#     public over private    refused (exit 77), the message naming the node id
#                            and the public home, what to change, and never
#                            the private repository
#   `internal` reads as private
#   a failed read of either repository    exit 72, printing no visibility
#   the home alone                        home=public or home=private, 72 on a
#                                         failed read
#   usage errors                          exit 64, no gh call
#
# Usage: repo-visibility_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
VIS="$SCRIPT_DIR/repo-visibility.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

# pair <case> <home vis> <node vis> -- run the node check. Sets OUT, ERR, RC.
pair() {
    ct_case "$1"
    CT_VIS_A="$2"
    CT_VIS_B="$3"
    ct_write_db
    OUT=$(bash "$VIS" --home-repo acme/repo-a --repo acme/repo-b --node pr-core 2>"$CASE/stderr")
    RC=$?
    ERR=$(cat "$CASE/stderr")
}

expect_allowed() { # expect_allowed <label> <home> <node>
    if [ "$RC" -eq 0 ] && [ "$OUT" = "home=$2
node=$3" ]; then
        pass "$1: allowed, home=$2 node=$3"
    else
        fail "$1: rc=$RC out=[$OUT] err=[$ERR]"
    fi
}

# --- the four pairs ---------------------------------------------------------------

pair pub-pub public public
expect_allowed "public over public" public public

pair priv-pub private public
expect_allowed "private over public" private public

pair priv-priv private private
expect_allowed "private over private" private private

pair pub-priv public private
if [ "$RC" -eq 77 ]; then
    pass "public over private: refused with 77"
else
    fail "public over private: rc=$RC out=[$OUT] err=[$ERR]"
fi
case "$ERR" in
    *"node pr-core lands in a private repository"*"public repository acme/repo-a"*"Move the node into acme/repo-a"*"PLAN in a private repository"*)
        pass "the refusal names the combination and what to change" ;;
    *) fail "the refusal's message: [$ERR]" ;;
esac
case "$ERR$OUT" in
    *repo-b*) fail "the refusal named the private repository: [$ERR]" ;;
    *) pass "the refusal never names the private repository" ;;
esac

pair internal-node public internal
if [ "$RC" -eq 77 ] && [ "$OUT" = "home=public
node=private" ]; then
    pass "an internal node reads as private, and under a public home is refused"
else
    fail "internal node: rc=$RC out=[$OUT]"
fi
pair internal-home internal private
expect_allowed "an internal home reads as private, and may index a private node" private private

# --- failed reads -----------------------------------------------------------------

pair home-unread none public
if [ "$RC" -eq 72 ] && [ -z "$OUT" ]; then
    pass "a failed read of the home repository exits 72 and prints no visibility"
else
    fail "home unread: rc=$RC out=[$OUT]"
fi
pair node-unread public none
if [ "$RC" -eq 72 ] && [ -z "$OUT" ]; then
    pass "a failed read of the node's repository exits 72 and prints no visibility"
else
    fail "node unread: rc=$RC out=[$OUT]"
fi
case "$ERR" in
    *"could not read the visibility of node pr-core's repository"*) pass "the failed read names the node, not the repository" ;;
    *) fail "node unread message: [$ERR]" ;;
esac

# --- the home alone ---------------------------------------------------------------

for v in public private; do
    ct_case "home-$v"
    CT_VIS_A="$v"
    ct_write_db
    OUT=$(bash "$VIS" --home-repo acme/repo-a 2>/dev/null); RC=$?
    [ "$RC" -eq 0 ] && [ "$OUT" = "home=$v" ] && pass "the home alone prints home=$v" || fail "home alone $v: rc=$RC out=[$OUT]"
done
ct_case home-alone-unread
CT_VIS_A=none
ct_write_db
OUT=$(bash "$VIS" --home-repo acme/repo-a 2>/dev/null); RC=$?
[ "$RC" -eq 72 ] && [ -z "$OUT" ] && pass "the home alone, unread, exits 72 with nothing printed" || fail "home alone unread: rc=$RC out=[$OUT]"

# --- usage ------------------------------------------------------------------------

ct_case usage
ct_write_db
for args in "" "--home-repo" "--home-repo a/b/c" "--home-repo acme/repo-a --repo acme/repo-b" \
            "--home-repo acme/repo-a --node pr-core" "--home-repo acme/repo-a --repo acme/repo-b --node Bad" \
            "--home-repo acme/repo-a --home-repo acme/repo-a" "--home-repo acme/repo-a extra"; do
    # shellcheck disable=SC2086
    bash "$VIS" $args >/dev/null 2>&1; rc=$?
    [ "$rc" -eq 64 ] && pass "usage [$args] exits 64" || fail "usage [$args]: rc=$rc"
done
if [ -s "$GH_CALL_LOG" ]; then fail "a usage error called gh: $(cat "$GH_CALL_LOG")"; else pass "no usage error called gh"; fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

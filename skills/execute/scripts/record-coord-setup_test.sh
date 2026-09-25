#!/usr/bin/env bash
# record-coord-setup_test.sh — coord_setup's record: the write set, the home
# repository, the coordination branch, and the PLAN's absolute path
# Part of the execute skill
#
# Each case runs record-coord-setup.sh in a real coordination checkout (a
# local bare origin, so the owner/repo comes from the eval gh shim's
# `gh repo view`) with the koto stub (see coord-test-helpers.sh).
#
# Cases:
#   one repository, two groups     repos=acme/repo-a (one entry), home_repo,
#                                  coord_branch, plan_abs; repos written last
#   two repositories               repos sorted and comma-joined
#   home_repo outside repos        exit 66, nothing written
#   a detached HEAD                exit 65
#   the default branch             exit 67
#   a re-run with the same values  a no-op
#   a different recorded value     exit 68, the record unchanged
#   usage                          exit 64
#
# Usage: record-coord-setup_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SETUP="$SCRIPT_DIR/record-coord-setup.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

S=execute-t
val() { cat "$CASE/ctx/$S/$1" 2>/dev/null; }

setup_case() { # setup_case <name> [two-repo] -- a checkout on the coordination branch
    ct_case "$1"
    ct_write_db
    REPO="$CT_WORK/$1-repo"
    ct_repo "$REPO"
    ct_plan "$REPO" "${2:-}"
    mkdir -p "$CASE/ctx/$S"
}
run_setup() {
    OUT=$(cd "$REPO" && bash "$SETUP" --session "$S" --plan docs/plans/PLAN-t.md 2>"$CASE/stderr")
    RC=$?
}

setup_case one-repo
run_setup
PLAN_ABS="$(cd "$REPO/docs/plans" && pwd -P)/PLAN-t.md"
if [ "$RC" -eq 0 ] && [ "$(val repos)" = acme/repo-a ] && [ "$(val home_repo)" = acme/repo-a ] \
    && [ "$(val coord_branch)" = "$CT_CB" ] && [ "$(val plan_abs)" = "$PLAN_ABS" ]; then
    pass "one repository, two groups: repos, home_repo, coord_branch, plan_abs recorded"
else
    fail "one-repo: rc=$RC repos=[$(val repos)] home=[$(val home_repo)] cb=[$(val coord_branch)] abs=[$(val plan_abs)]"
    tail -3 "$CASE/stderr"
fi
LAST=$(grep '^context add' "$CASE/koto-calls.log" | tail -1)
[ "$LAST" = "context add $S repos" ] && pass "repos is written last" || fail "last write [$LAST]"

run_setup
[ "$RC" -eq 0 ] && pass "a re-run with the same values is a no-op" || fail "re-run: rc=$RC"

printf '%s' "acme/repo-a,acme/repo-z" > "$CASE/ctx/$S/repos"
run_setup
if [ "$RC" -eq 68 ] && [ "$(val repos)" = "acme/repo-a,acme/repo-z" ]; then
    pass "a different recorded write set refuses (68) and stays as it was"
else
    fail "changed record: rc=$RC repos=[$(val repos)]"
fi

setup_case two-repo two-repo
run_setup
[ "$RC" -eq 0 ] && [ "$(val repos)" = "acme/repo-a,acme/repo-b" ] \
    && pass "two repositories: repos sorted and comma-joined" || fail "two-repo: rc=$RC repos=[$(val repos)]"

setup_case outside
jq '.default_repo = "acme/elsewhere"' "$CASE/scenario/gh/db.json" > "$CASE/db" && mv "$CASE/db" "$CASE/scenario/gh/db.json"
run_setup
if [ "$RC" -eq 66 ] && [ -z "$(ls "$CASE/ctx/$S")" ]; then
    pass "a home repository outside the write set exits 66 with nothing written"
else
    fail "outside: rc=$RC"
fi

setup_case detached
(cd "$REPO" && git checkout -q --detach)
run_setup
[ "$RC" -eq 65 ] && pass "a detached HEAD exits 65" || fail "detached: rc=$RC"

setup_case default-branch
(cd "$REPO" && git checkout -q main)
run_setup
[ "$RC" -eq 67 ] && pass "the default branch exits 67" || fail "default: rc=$RC"

setup_case usage
(cd "$REPO" && bash "$SETUP" --session "$S" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 64 ] && pass "a missing --plan exits 64" || fail "usage: rc=$rc"
(cd "$REPO" && bash "$SETUP" --session '-x' --plan docs/plans/PLAN-t.md >/dev/null 2>&1); rc=$?
[ "$rc" -eq 64 ] && pass "a bad session name exits 64" || fail "usage session: rc=$rc"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

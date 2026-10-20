#!/usr/bin/env bash
# record-coord-setup_test.sh — coord_setup's record: the write set, the home
# repository, the coordination branch, the PLAN's absolute path, and the run
# record it seals
# Part of the execute skill
#
# Each case runs record-coord-setup.sh in a real coordination checkout (a
# local bare origin, so the owner/repo comes from the eval gh shim's
# `gh repo view`) with the koto stub (see coord-test-helpers.sh). Every case's
# GitHub model holds the coordination PR, #10 on the coordination branch.
#
# Cases:
#   one repository, two groups     repos=acme/repo-a (one entry), home_repo,
#                                  coord_branch, plan_abs; repos written last
#   a new run                      run/setup sealed: the node list in PLAN
#                                  order, store github, coordination_pr 10,
#                                  repos, mode, /scope's run lines; run_id
#                                  minted; a carried run_id kept
#   --store session                sealed as session; a later --store github
#                                  stops store-mismatch with the store's
#                                  bytes unchanged; a later invocation with no
#                                  --store reads the sealed value
#   the ownership lookup           no coordination PR: coordination-pr-missing;
#                                  two: coordination-pr-ambiguous; nothing
#                                  written either way; one already MERGED is
#                                  accepted (and on a later invocation); one
#                                  closed unmerged, handed, stops
#                                  coordination-pr-closed (the lookup alone
#                                  drops it: coordination-pr-missing)
#   --coordination-pr              #10 recorded; a PR by another author, on
#                                  another branch, without the marker, or
#                                  other than the lookup's:
#                                  coordination-pr-mismatch, nothing written
#   a later invocation             no ownership lookup (no pr list, no api
#                                  user); the recorded PR closed unmerged:
#                                  coordination-pr-closed; a --coordination-pr
#                                  other than the recorded one: mismatch
#   inert flags                    --follow-up, --follow-up-remove and
#                                  --adopt-run print ignored= and change
#                                  nothing else
#   two repositories               repos sorted and comma-joined
#   home_repo outside repos        recorded: a coordination PR whose
#                                  repository holds no node (repos names only
#                                  the node repositories, home_repo the
#                                  checkout's), and a re-run is a no-op
#   an invalid home_repo           exit 66, nothing written
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
URL10="https://github.com/acme/repo-a/pull/10"
SEEDED_ID=00112233445566778899aabbccddeeff
val() { cat "$CASE/ctx/$S/$1" 2>/dev/null; }
setup_val() { val run/setup | jq -c "$1"; }
db_edit() { jq "$1" "$CASE/scenario/gh/db.json" > "$CASE/db" && mv "$CASE/db" "$CASE/scenario/gh/db.json"; }
store_sum() {
    (cd "$CASE/ctx" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s\n' "$f"; cat "$f"; printf '\n'
    done) | cksum
}
written() { ls "$CASE/ctx/$S" 2>/dev/null | grep -vx run_id; }

setup_case() { # setup_case <name> [two-repo] -- a checkout on the coordination branch
    ct_case "$1"
    ct_write_db
    REPO="$CT_WORK/$1-repo"
    ct_repo "$REPO"
    ct_plan "$REPO" "${2:-}"
    mkdir -p "$CASE/ctx/$S"
}
run_setup() { # run_setup [flags...]
    OUT=$(cd "$REPO" && bash "$SETUP" --session "$S" --plan docs/plans/PLAN-t.md "$@" 2>"$CASE/stderr")
    RC=$?
}
# stopped <label> <code> -- exit 71, stop=<code>, nothing written.
stopped() {
    if [ "$RC" -eq 71 ] && [ "$OUT" = "stop=$2" ] && [ -z "$(written)" ]; then
        pass "$1: stop=$2, nothing written"
    else
        fail "$1: rc=$RC out=[$OUT] written=[$(written | tr '\n' ' ')] stderr=[$(tail -1 "$CASE/stderr")]"
    fi
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
printf '%s\n' "$OUT" | grep -qx "record=new" && printf '%s\n' "$OUT" | grep -qx "coordination_pr=$URL10" \
    && printf '%s\n' "$OUT" | grep -qx "store=github" \
    && pass "a new run reports record=new, store=github and the coordination PR" || fail "one-repo output: [$OUT]"

run_setup
[ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -qx "record=existing" \
    && pass "a re-run with the same values is a no-op" || fail "re-run: rc=$RC out=[$OUT]"

printf '%s' "acme/repo-a,acme/repo-z" > "$CASE/ctx/$S/repos"
run_setup
if [ "$RC" -eq 68 ] && [ "$(val repos)" = "acme/repo-a,acme/repo-z" ]; then
    pass "a different recorded write set refuses (68) and stays as it was"
else
    fail "changed record: rc=$RC repos=[$(val repos)]"
fi

# --- the seal ------------------------------------------------------------------------

setup_case seal
rm -f "$CASE/ctx/$S/run_id"
db_edit '(.prs[] | select(.number == 10) | .body) |= ("topic=t\nintent=deliver\nowner=x\ntopic=other\n\n" + . + "\nexit=late\n")'
run_setup
WANT_NODES=$(ct_nodes_of "$REPO/docs/plans/PLAN-t.md")
if [ "$RC" -eq 0 ] && [ "$(setup_val .nodes)" = "$(printf '%s' "$WANT_NODES" | jq -cS .)" ] \
    && [ "$(setup_val '.nodes | map(.name)')" = '["pr-repo-a-core","pr-repo-a-cli"]' ]; then
    pass "a new run seals the PLAN's node list in plan-to-tasks order"
else
    fail "seal nodes: rc=$RC nodes=[$(setup_val .nodes)] stderr=[$(tail -1 "$CASE/stderr")]"
fi
[ "$(setup_val '[.store, .coordination_pr, .repos, .mode]')" = '["github",10,["acme/repo-a"],"coordinated"]' ] \
    && pass "the seal holds store github, coordination_pr 10, repos, mode coordinated" \
    || fail "seal fields: [$(setup_val '[.store, .coordination_pr, .repos, .mode]')]"
[ "$(setup_val .run_lines)" = '{"intent":"deliver","topic":"t"}' ] \
    && pass "/scope's run lines above the first heading, the first of each key, are sealed" \
    || fail "run lines: [$(setup_val .run_lines)]"
[[ $(val run_id) =~ ^[0-9a-f]{32}$ ]] && pass "a new run's setup mints run_id" || fail "run_id: [$(val run_id)]"
ORDER=$(grep '^context add' "$CASE/koto-calls.log" | awk '{print $4}' | tr '\n' ' ')
case "$ORDER" in
    "run_id run/setup plan_abs coord_branch home_repo repos ") pass "run_id, then run/setup, then the fixed keys, repos last" ;;
    *) fail "the write order was [$ORDER]" ;;
esac

setup_case carried-id
run_setup
[ "$RC" -eq 0 ] && [ "$(val run_id)" = "$SEEDED_ID" ] && pass "a carried run_id is kept (mint returns it)" \
    || fail "carried id: rc=$RC run_id=[$(val run_id)]"

setup_case store
run_setup --store session
[ "$RC" -eq 0 ] && [ "$(setup_val .store)" = '"session"' ] && printf '%s\n' "$OUT" | grep -qx store=session \
    && pass "--store session is sealed as session" || fail "store session: rc=$RC store=[$(setup_val .store)]"
SUM0=$(store_sum)
run_setup --store github
if [ "$RC" -eq 71 ] && [ "$OUT" = "stop=store-mismatch" ] && [ "$(store_sum)" = "$SUM0" ]; then
    pass "a later --store github over a sealed session stops store-mismatch, no key changed"
else
    fail "store-mismatch: rc=$RC out=[$OUT]"
fi
run_setup
[ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -qx store=session \
    && pass "a later invocation with no --store reads the sealed value" || fail "no --store later: rc=$RC out=[$OUT]"
run_setup --store ""
[ "$RC" -eq 0 ] && pass "an empty --store (the template's unset variable) is no --store" || fail "empty --store: rc=$RC"

setup_case store-default
run_setup --store ""
SUM0=$(store_sum)
run_setup --store session
[ "$RC" -eq 71 ] && [ "$OUT" = "stop=store-mismatch" ] && [ "$(store_sum)" = "$SUM0" ] \
    && pass "a run sealed github refuses a later --store session" || fail "github then session: rc=$RC out=[$OUT]"

# --- the ownership lookup ------------------------------------------------------------

setup_case missing
db_edit '(.prs[] | select(.number == 10) | .headRefName) = "docs/elsewhere"'
run_setup
stopped "no coordination PR on the branch" coordination-pr-missing

setup_case ambiguous
ct_pr "$CT_REPO" 13 "$CT_CB" 'body="> This is a **coordination PR** too."'
ct_write_db
run_setup
stopped "two owned coordination PRs on the branch" coordination-pr-ambiguous

setup_case handed
run_setup --coordination-pr "$URL10"
[ "$RC" -eq 0 ] && [ "$(setup_val .coordination_pr)" = 10 ] \
    && pass "--coordination-pr naming the lookup's PR is recorded" || fail "handed: rc=$RC [$(tail -1 "$CASE/stderr")]"

setup_case handed-foreign-author
db_edit '(.prs[] | select(.number == 10) | .author) = "someone-else"'
run_setup --coordination-pr "$URL10"
stopped "a handed PR by another author" coordination-pr-mismatch

setup_case handed-other-branch
db_edit '(.prs[] | select(.number == 10) | .headRefName) = "docs/elsewhere"'
run_setup --coordination-pr "$URL10"
stopped "a handed PR on another branch" coordination-pr-mismatch

setup_case handed-no-marker
db_edit '(.prs[] | select(.number == 10) | .body) = "a plain body"'
run_setup --coordination-pr "$URL10"
stopped "a handed PR without the marker" coordination-pr-mismatch

setup_case handed-differs
ct_pr "$CT_REPO" 14 docs/other
ct_write_db
run_setup --coordination-pr "https://github.com/acme/repo-a/pull/14"
stopped "a handed PR other than the lookup's" coordination-pr-mismatch
run_setup --coordination-pr "https://github.com/acme/repo-b/pull/10"
stopped "a handed PR with the lookup's number in another repository" coordination-pr-mismatch

# --- a later invocation --------------------------------------------------------------

setup_case later
run_setup
: > "$GH_CALL_LOG"
run_setup
if [ "$RC" -eq 0 ] && ! grep -Eq '^(pr list|api user)' "$GH_CALL_LOG"; then
    pass "a later invocation reads the number from the record, with no ownership lookup"
else
    fail "later lookup: rc=$RC calls=[$(tr '\n' ';' < "$GH_CALL_LOG")]"
fi
run_setup --coordination-pr "https://github.com/acme/repo-a/pull/14"
[ "$RC" -eq 71 ] && [ "$OUT" = stop=coordination-pr-mismatch ] \
    && pass "a later --coordination-pr other than the recorded PR stops coordination-pr-mismatch" \
    || fail "later mismatch: rc=$RC out=[$OUT]"
run_setup --coordination-pr "$URL10"
[ "$RC" -eq 0 ] && pass "a later --coordination-pr naming the recorded PR passes" || fail "later same: rc=$RC"

setup_case later-closed
run_setup
SUM0=$(store_sum)
# The shim's live model, seeded on the first call above.
jq '(.prs[] | select(.number == 10) | .state) = "CLOSED"' "$GH_CALL_LOG.d/db.json" > "$CASE/db" \
    && mv "$CASE/db" "$GH_CALL_LOG.d/db.json"
run_setup
[ "$RC" -eq 71 ] && [ "$OUT" = stop=coordination-pr-closed ] && [ "$(store_sum)" = "$SUM0" ] \
    && pass "a recorded coordination PR closed unmerged stops coordination-pr-closed" \
    || fail "closed: rc=$RC out=[$OUT]"

# --- a coordination PR no longer open, at setup ------------------------------------

setup_case setup-merged
CT_COORD_STATE=MERGED
ct_write_db
run_setup --coordination-pr "$URL10"
if [ "$RC" -eq 0 ] && [ "$(setup_val .coordination_pr)" = 10 ] && printf '%s\n' "$OUT" | grep -qx record=new; then
    pass "a coordination PR already MERGED at setup is accepted and recorded (the loop ends it done:merged)"
else
    fail "setup-merged: rc=$RC out=[$OUT] stderr=[$(tail -1 "$CASE/stderr")]"
fi
run_setup
[ "$RC" -eq 0 ] && pass "a later invocation over a MERGED recorded coordination PR is accepted" \
    || fail "later merged: rc=$RC out=[$OUT]"

setup_case setup-closed
CT_COORD_STATE=CLOSED
ct_write_db
# The ownership lookup drops a PR closed unmerged (owned-pr.sh --state all),
# so with nothing handed there is no coordination PR to find.
run_setup
stopped "a coordination PR closed unmerged, nothing handed: the lookup finds none" coordination-pr-missing
run_setup --coordination-pr "$URL10"
stopped "the same PR handed with --coordination-pr" coordination-pr-closed
db_edit '(.prs[] | select(.number == 10) | .body) = "a plain body"'
rm -rf "$GH_CALL_LOG.d"
run_setup --coordination-pr "$URL10"
stopped "a handed closed PR without the marker is not this run's" coordination-pr-mismatch

# --- the inert flags -----------------------------------------------------------------

setup_case inert
run_setup --follow-up "pr-repo-a-core=https://github.com/acme/repo-a/pull/30" --follow-up-remove true \
    --adopt-run 0123456789abcdef0123456789abcdef
INERT_SETUP=$(val run/setup)
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -qx ignored=follow-up && printf '%s\n' "$OUT" | grep -qx ignored=remove \
    && printf '%s\n' "$OUT" | grep -qx ignored=adopt-run && [ -z "$(ls "$CASE/ctx/$S/run" | grep -vx setup)" ]; then
    pass "--follow-up, --follow-up-remove and --adopt-run are reported ignored= and write nothing of their own"
else
    fail "inert: rc=$RC out=[$OUT] run/=[$(ls "$CASE/ctx/$S/run" 2>/dev/null | tr '\n' ' ')]"
fi
setup_case inert-control
run_setup --follow-up "" --follow-up-remove "" --adopt-run ""
[ "$RC" -eq 0 ] && [ "$(val run/setup)" = "$INERT_SETUP" ] && ! printf '%s\n' "$OUT" | grep -q '^ignored=' \
    && pass "the same run without them seals the same record and reports nothing ignored" \
    || fail "inert control: rc=$RC out=[$OUT]"

# --- the write set -------------------------------------------------------------------

setup_case two-repo two-repo
run_setup
[ "$RC" -eq 0 ] && [ "$(val repos)" = "acme/repo-a,acme/repo-b" ] \
    && pass "two repositories: repos sorted and comma-joined" || fail "two-repo: rc=$RC repos=[$(val repos)]"

# The coordination PR lives in a planning repository that holds none of the
# PLAN's nodes: every node names acme/repo-a, the checkout is acme/plans.
setup_case outside
db_edit '.default_repo = "acme/plans" | .repos["acme/plans"] = .repos["acme/repo-a"]
    | (.prs[] | select(.number == 10) | .repo) = "acme/plans"'
run_setup
if [ "$RC" -eq 0 ] && [ "$(val repos)" = acme/repo-a ] && [ "$(val home_repo)" = acme/plans ] \
    && [ "$(val coord_branch)" = "$CT_CB" ] && [ -n "$(val plan_abs)" ] \
    && printf '%s\n' "$OUT" | grep -qx "coordination_pr=https://github.com/acme/plans/pull/10"; then
    pass "a home repository outside the write set is recorded: repos=acme/repo-a, home_repo=acme/plans"
else
    fail "outside: rc=$RC repos=[$(val repos)] home=[$(val home_repo)] stderr=[$(tail -1 "$CASE/stderr")]"
fi
run_setup
[ "$RC" -eq 0 ] && pass "a re-run with the home outside the write set is a no-op" || fail "outside re-run: rc=$RC"

setup_case bad-home
db_edit '.default_repo = "acme/../x"'
run_setup
if [ "$RC" -eq 66 ] && [ -z "$(written)" ]; then
    pass "a home repository outside owner/repo exits 66 with nothing written"
else
    fail "bad-home: rc=$RC"
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
for bad in "--store s3" "--coordination-pr https://x/y" "--follow-up core" "--follow-up-remove yes" "--adopt-run XYZ"; do
    # shellcheck disable=SC2086
    (cd "$REPO" && bash "$SETUP" --session "$S" --plan docs/plans/PLAN-t.md $bad >/dev/null 2>&1); rc=$?
    [ "$rc" -eq 64 ] && pass "[$bad] exits 64" || fail "usage [$bad]: rc=$rc"
done
[ -z "$(written)" ] && pass "no usage error wrote anything" || fail "a usage error wrote [$(written)]"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

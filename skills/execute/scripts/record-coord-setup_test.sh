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
# Each case starts from a fresh session (no run_id: one would be a carried
# id, which says a run had started).
#
# Cases:
#   one repository, two groups     repos=acme/repo-a (one entry), home_repo,
#                                  coord_branch, plan_abs; repos written last
#   a new run                      run/setup sealed: the node list in PLAN
#                                  order, store github, coordination_pr 10,
#                                  repos, mode, /scope's run lines; then
#                                  run_id minted (a failed seal mints none; a
#                                  record left without one gets one next time);
#                                  then the trail: trail/self (the checkout,
#                                  the session, its koto id, the run_id) and
#                                  the coordination PR (role coordination)
#                                  with its index entry at acme's shared
#                                  address, before the fixed keys; a failed
#                                  index or trail write exits 70 naming the
#                                  PR, repos unwritten
#   nothing started                record=new on both stores, no stop
#   session-absent                 on session, a carried run_id, a rendered
#                                  run= line, an index line, or an owned PR on
#                                  a PLAN node's branch, each alone, stops
#                                  naming the import, with no GitHub write; so
#                                  does the body's store=session with no
#                                  --store; a --store other than the body's
#                                  store= line stops store-mismatch
#   recovery on github             --adopt-run (first: over a merged
#                                  foreign-marked PR, an unmarked one and one
#                                  already marked: only the first two edited,
#                                  every body then marked, run_id the adopted
#                                  id over a carried one, run/adopted's login
#                                  and time, the merged one's merged_head);
#                                  --adopt-run over a record refused before
#                                  any PR read; a stamp that fails names its
#                                  PR not stampable and a re-run edits no PR
#                                  twice; identity from the run line (live
#                                  heads, never the body's; the PLAN's nodes;
#                                  cascade not-run; store github; trail/self
#                                  with the recovered run_id, the coordination
#                                  and node PRs in the trail and re-indexed
#                                  under the new session's id; then the
#                                  loop's merge: setup's head read, the
#                                  readiness reads and the merge at the live
#                                  head, in that order in the log), unanimous
#                                  markers, and minted (a follow-up line
#                                  alone, whose node has no node line: it is
#                                  dropped, follow-up-dropped:<url>); another
#                                  run's marker, none, or no identity stops
#                                  recovery-unproven naming each, writing no
#                                  run_id; a PR another author opened and a
#                                  node outside the PLAN are named, with no
#                                  --adopt-run hint and no read of the
#                                  stranger
#   pre-feature and the index      a session holding only its run_id over an
#                                  old-format body recovers once (carried,
#                                  self row dropped), then record=existing
#                                  with no recovery marker; /scope's empty
#                                  index recovers an empty map, or stops
#                                  coordination-index-missing beside an owned
#                                  node PR; the PLAN gone stops
#                                  recovery-plan-gone (or
#                                  coordination-index-missing with no index
#                                  line), and with nothing started is the
#                                  usage error; a held record with the PLAN
#                                  (and its directory) gone passes, repos from
#                                  run/setup; a 60,001-byte body stops
#                                  coordination-body-full, a line outside the
#                                  grammar recovery-unproven
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
#   empty optional values          the same as leaving the flags out
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

setup_case() { # setup_case <name> [two-repo|three] -- a checkout on the coordination branch
    ct_case "$1"
    # A fresh session: no run_id. One here would be a carried id, which says
    # a run had started.
    rm -f "$CASE/ctx/$S/run_id"
    ct_write_db
    REPO="$CT_WORK/$1-repo"
    ct_repo "$REPO"
    ct_plan "$REPO" "${2:-}"
    mkdir -p "$CASE/ctx/$S"
}
seed_id() { printf '%s' "${1:-$SEEDED_ID}" > "$CASE/ctx/$S/run_id"; }
# no_remote_write <label> -- the case's gh log holds no body edit, comment or
# merge.
no_remote_write() {
    if grep -Eq '^pr (edit|comment|merge) ' "$GH_CALL_LOG" 2>/dev/null; then
        fail "$1: a remote write was made: $(grep -E '^pr (edit|comment|merge) ' "$GH_CALL_LOG" | head -1)"
    else
        pass "$1: no body edit, comment or merge"
    fi
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
grep -qx "record=new" <<<"$OUT" && grep -qx "coordination_pr=$URL10" <<<"$OUT" \
    && grep -qx "store=github" <<<"$OUT" \
    && pass "a new run reports record=new, store=github and the coordination PR" || fail "one-repo output: [$OUT]"

run_setup
[ "$RC" -eq 0 ] && grep -qx "record=existing" <<<"$OUT" \
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
ORDER=$(grep "^context add $S " "$CASE/koto-calls.log" | awk '{print $4}' | tr '\n' ' ')
case "$ORDER" in
    "run/setup run_id trail/self trail/pr/acme.repo-a.10 plan_abs coord_branch home_repo repos ")
        pass "run/setup, then run_id, then the trail, then the fixed keys, repos last" ;;
    *) fail "the write order was [$ORDER]" ;;
esac
# The run's trail: its address and the coordination PR, indexed.
SEAL_RID=$(val run_id)
REPO_P=$(cd "$REPO" && pwd -P)
[ "$(val trail/self | jq -c '{workspace, session, run_id}')" = "$(jq -nc --arg w "$REPO_P" --arg s "$S" --arg r "$SEAL_RID" '{workspace: $w, session: $s, run_id: $r}')" ] \
    && [ -n "$(val trail/self | jq -r .session_id)" ] \
    && pass "a new run's trail/self names the coordination checkout, the session, its koto id and the minted run_id" \
    || fail "trail/self: [$(val trail/self)]"
[ "$(val trail/pr/acme.repo-a.10 | jq -c '{repo, number, role, state}')" = '{"repo":"acme/repo-a","number":10,"role":"coordination","state":"open"}' ] \
    && pass "the coordination PR is in the root's trail, role coordination, state open" \
    || fail "trail/pr: [$(val trail/pr/acme.repo-a.10)]"
ENTRY=$(cat "$CASE/ctx/pr.acme.repo-a.10/run/$SEAL_RID" 2>/dev/null)
[ "$(jq -c '{workspace, session, mode, topic}' <<<"$ENTRY")" = "$(jq -nc --arg w "$REPO_P" --arg s "$S" '{workspace: $w, session: $s, mode: "coordinated", topic: "t"}')" ] \
    && grep -q "^init pr.acme.repo-a.10 .*--attach-live" "$CASE/koto-calls.log" \
    && pass "the coordination PR's index session, opened at its owner's shared address, names the root" \
    || fail "index entry: [$ENTRY]"

# A failed index write stops setup, naming the PR, before the fixed keys.
setup_case seal-index-fails
export KOTO_FAIL_INIT=pr.acme.repo-a.10; run_setup; unset KOTO_FAIL_INIT
[ "$RC" -eq 70 ] && grep -q "acme/repo-a#10 (coordination)" "$CASE/stderr" && [ -z "$(val repos)" ] \
    && pass "a failed index write exits 70 naming the PR, and repos is not written, so coord_setup's gates hold" \
    || fail "index fails: rc=$RC repos=[$(val repos)] stderr=[$(tail -2 "$CASE/stderr" | tr '\n' ' ')]"
setup_case seal-trail-fails
export KOTO_FAIL_ADD=trail/pr/acme.repo-a.10; run_setup; unset KOTO_FAIL_ADD
[ "$RC" -eq 70 ] && grep -q "acme/repo-a#10 (coordination)" "$CASE/stderr" && [ -z "$(val repos)" ] \
    && pass "a failed trail write exits 70 naming the PR, and repos is not written" \
    || fail "trail fails: rc=$RC repos=[$(val repos)] stderr=[$(tail -2 "$CASE/stderr" | tr '\n' ' ')]"

# A seal that fails leaves no run_id behind, so the next start is not read as
# a started run.
setup_case seal-fails
export KOTO_FAIL_ADD=run/setup; run_setup
[ "$RC" -eq 70 ] && [ ! -f "$CASE/ctx/$S/run_id" ] && pass "a seal that fails exits 70 and mints no run_id" \
    || fail "failed seal: rc=$RC run_id=[$(val run_id)]"
unset KOTO_FAIL_ADD
run_setup
[ "$RC" -eq 0 ] && grep -qx record=new <<<"$OUT" && pass "the next start after a failed seal is a new run again" \
    || fail "after a failed seal: rc=$RC out=[$OUT]"

# A crash between the seal and the mint is repaired by the next invocation.
setup_case mint-repair
run_setup
rm -f "$CASE/ctx/$S/run_id"
run_setup
[ "$RC" -eq 0 ] && grep -qx record=existing <<<"$OUT" && [[ $(val run_id) =~ ^[0-9a-f]{32}$ ]] \
    && pass "a record with no run_id gets one minted on the next invocation" \
    || fail "mint repair: rc=$RC run_id=[$(val run_id)]"

setup_case store
run_setup --store session
[ "$RC" -eq 0 ] && [ "$(setup_val .store)" = '"session"' ] && grep -qx store=session <<<"$OUT" \
    && pass "--store session is sealed as session" || fail "store session: rc=$RC store=[$(setup_val .store)]"
SUM0=$(store_sum)
run_setup --store github
if [ "$RC" -eq 71 ] && [ "$OUT" = "stop=store-mismatch" ] && [ "$(store_sum)" = "$SUM0" ]; then
    pass "a later --store github over a sealed session stops store-mismatch, no key changed"
else
    fail "store-mismatch: rc=$RC out=[$OUT]"
fi
run_setup
[ "$RC" -eq 0 ] && grep -qx store=session <<<"$OUT" \
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
if [ "$RC" -eq 0 ] && [ "$(setup_val .coordination_pr)" = 10 ] && grep -qx record=new <<<"$OUT"; then
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

# --- empty optional values ---------------------------------------------------------
#
# The template passes its rebind variables verbatim, so an empty value is a
# flag left out. (The follow-up cases are record-coord-follow-up_test.sh's.)

setup_case empty-control
run_setup
CONTROL_SETUP=$(val run/setup)
setup_case empty-flags
run_setup --follow-up "" --follow-up-remove "" --adopt-run ""
[ "$RC" -eq 0 ] && [ "$(val run/setup)" = "$CONTROL_SETUP" ] && ! grep -q '^follow-up' <<<"$OUT" \
    && pass "empty --follow-up, --follow-up-remove and --adopt-run seal the record a run without them does" \
    || fail "empty flags: rc=$RC out=[$OUT]"

# --- recovery: whether a run had started ------------------------------------------

RID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
OTHER_ID=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
ADOPT_ID=cccccccccccccccccccccccccccccccc
BR_CORE="impl/$CT_SLUG-$CT_CORE"
BR_CLI="impl/$CT_SLUG-$CT_CLI"
URL11="https://github.com/acme/repo-a/pull/11"
URL12="https://github.com/acme/repo-a/pull/12"
# node_prs <core-body-json> <cli-body-json> -- the two node PRs, #11 and #12,
# on their branches, each with head CT_HEAD.
node_prs() {
    ct_pr "$CT_REPO" 11 "$BR_CORE" "body=$1"
    ct_pr "$CT_REPO" 12 "$BR_CLI" "body=$2"
}
PLAIN_BODY='"Implements the node.\n\n---\n\nCoordinated node.\n"'
# recovered_ok <label> <source> -- exit 0, record=recovered, recovered=URL10,
# and run/recovered naming the coordination PR and <source>.
recovered_ok() {
    if [ "$RC" -eq 0 ] && grep -qx record=recovered <<<"$OUT" && grep -qx "recovered=$URL10" <<<"$OUT" \
        && [ "$(val run/recovered)" = "{\"pr\":\"$URL10\",\"source\":\"$2\"}" ] && [ "$(val recovered)" = "$URL10" ]; then
        pass "$1: recovered, source $2, recovered=$URL10"
    else
        fail "$1: rc=$RC out=[$OUT] run/recovered=[$(val run/recovered)] stderr=[$(tail -3 "$CASE/stderr" | tr '\n' ' ')]"
    fi
}

# A first start with nothing started seals a new record on both stores.
for st in github session; do
    setup_case "fresh-$st"
    run_setup --store "$st"
    [ "$RC" -eq 0 ] && grep -qx record=new <<<"$OUT" && [ "$(setup_val .store)" = "\"$st\"" ] \
        && ! grep -q '^recovered=' <<<"$OUT" \
        && pass "a first start with nothing started on --store $st seals a new record, no stop" \
        || fail "fresh $st: rc=$RC out=[$OUT]"
done

# On session, each started signal alone stops session-absent, naming the
# import, with no GitHub write.
absent() { # absent <label> [flags...]
    local label="$1"; shift
    run_setup "$@"
    if [ "$RC" -eq 71 ] && [ "$OUT" = stop=session-absent ] && [ -z "$(written)" ] \
        && grep -q 'skill-session.sh import execute' "$CASE/stderr"; then
        pass "$label: stop=session-absent naming the import, nothing written"
    else
        fail "$label: rc=$RC out=[$OUT] written=[$(written | tr '\n' ' ')] stderr=[$(tail -1 "$CASE/stderr")]"
    fi
    no_remote_write "$label"
}
setup_case absent-carried
seed_id
absent "session, a carried run_id" --store session
setup_case absent-run-line
ct_rendered_body "$CASE/body.md" "$RID" session
ct_write_db "$CASE/body.md"
absent "session, a rendered run= line" --store session
setup_case absent-index
ct_index_line "$CT_CORE" "$CT_REPO" 11
ct_write_db
absent "session, an index line" --store session
setup_case absent-owned
ct_pr "$CT_REPO" 11 "$BR_CORE"
ct_write_db
absent "session, an owned PR on a PLAN node's branch" --store session
setup_case absent-body-store
ct_rendered_body "$CASE/body.md" "$RID" session
ct_write_db "$CASE/body.md"
absent "the body's store=session with no --store"
setup_case body-store-mismatch
ct_rendered_body "$CASE/body.md" "$RID" session
ct_write_db "$CASE/body.md"
run_setup --store github
stopped "a --store other than the body's store= line" store-mismatch

# --- recovery on github ---------------------------------------------------------------

# A merged node PR first: its body takes the stamp, and its merge commit is
# recorded as merged_head.
setup_case adopt three
seed_id "$OTHER_ID"
ct_index_line "$CT_CORE" "$CT_REPO" 11
ct_index_line "$CT_CLI" "$CT_REPO" 12
ct_index_line pr-repo-a-docs "$CT_REPO" 13
node_prs "$(ct_marked_body "$OTHER_ID")" "$PLAIN_BODY"
ct_pr "$CT_REPO" 13 "impl/$CT_SLUG-pr-repo-a-docs" "body=$(ct_marked_body "$ADOPT_ID")"
CT_PRS=$(printf '%s' "$CT_PRS" | jq -c '(.[] | select(.number == 11)) |= (.state = "MERGED" | .merge_sha = "5555555555555555555555555555555555555555")')
ct_write_db
run_setup --adopt-run "$ADOPT_ID"
recovered_ok "--adopt-run over a foreign-marked merged PR, an unmarked one and one already marked" adopted
EDITS=$(grep -E '^pr edit ' "$GH_CALL_LOG" | awk '{print $3}' | LC_ALL=C sort | tr '\n' ' ')
[ "$EDITS" = "11 12 " ] && pass "adopt edits only the PRs whose marker isn't the id (#11, #12), not #13" \
    || fail "adopt edits: [$EDITS]"
DB_NOW="$GH_CALL_LOG.d/db.json"
MARKS=$(jq -r '[.prs[] | select(.number >= 11) | .body | split("\n") | map(select(test("shirabe-run"))) | join(";")] | join(" ")' "$DB_NOW")
WANT_MARK="<!-- shirabe-run: $ADOPT_ID -->"
[ "$MARKS" = "$WANT_MARK $WANT_MARK $WANT_MARK" ] && pass "every node PR's body carries only the adopted id's marker, the merged one's included" \
    || fail "marks after adopt: [$MARKS]"
[ "$(val run_id)" = "$ADOPT_ID" ] && pass "--adopt-run outranks a carried run_id: the adopted id is the session's" \
    || fail "run_id after adopt: [$(val run_id)]"
if val run/adopted | jq -e --arg id "$ADOPT_ID" '.id == $id and .login == "eval-user"
        and (.at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))' >/dev/null; then
    pass "run/adopted records the id, the login and the time"
else
    fail "run/adopted: [$(val run/adopted)]"
fi
[ "$(val run/node/pr-repo-a-core | jq -r .merged_head)" = 5555555555555555555555555555555555555555 ] \
    && [ "$(val run/node/pr-repo-a-cli | jq -r 'has("merged_head")')" = false ] \
    && pass "the merged node's live merge commit is its merged_head; an open one has none" \
    || fail "merged heads: core=[$(val run/node/pr-repo-a-core)] cli=[$(val run/node/pr-repo-a-cli)]"
: > "$GH_CALL_LOG"
run_setup --adopt-run "$ADOPT_ID"
[ "$RC" -eq 71 ] && [ "$OUT" = stop=adopt-run-refused ] && ! grep -Eq '^(pr|api) ' "$GH_CALL_LOG" \
    && pass "--adopt-run on a session holding its record: adopt-run-refused, before any PR or API read" \
    || fail "adopt over a record: rc=$RC out=[$OUT] calls=[$(tr '\n' ';' < "$GH_CALL_LOG")]"

# A stamp that fails stops, naming the PR as not stampable. The index's nodes
# are stamped in node-name order, so #12 (pr-repo-a-cli) is stamped before
# the edit of #11 fails.
setup_case adopt-fails
ct_index_line "$CT_CORE" "$CT_REPO" 11
ct_index_line "$CT_CLI" "$CT_REPO" 12
node_prs "$(ct_marked_body "$OTHER_ID")" "$(ct_marked_body "$OTHER_ID")"
ct_write_db
printf '%s\n' '[ "$1 $2 $3" = "pr edit 11" ] && exit 1' 'exit 0' > "$CASE/hook.sh"
export CT_GH_HOOK="$CASE/hook.sh"
run_setup --adopt-run "$ADOPT_ID"
unset CT_GH_HOOK
if [ "$RC" -eq 71 ] && [ "$OUT" = stop=recovery-unproven ] && grep -q "$URL11.*not stampable" "$CASE/stderr" \
    && [ -z "$(written)" ] && [ ! -f "$CASE/ctx/$S/run_id" ]; then
    pass "a stamp that fails stops recovery-unproven naming #11 as not stampable, no record written"
else
    fail "adopt fails: rc=$RC out=[$OUT] written=[$(written | tr '\n' ' ')] stderr=[$(tail -1 "$CASE/stderr")]"
fi
run_setup --adopt-run "$ADOPT_ID"
recovered_ok "a re-run with the same --adopt-run" adopted
EDITS=$(grep -cE '^pr edit 12 ' "$GH_CALL_LOG")
[ "$EDITS" -eq 1 ] && pass "the re-run makes no second edit of #12, stamped before the failure" \
    || fail "edits of #12 across both runs: $EDITS"

# The rendered run line names the run, and every node PR carries its marker.
setup_case run-line
ct_rendered_body "$CASE/body.md" "$RID" github "$CT_CORE=11" "$CT_CLI=12"
node_prs "$(ct_marked_body "$RID")" "$(ct_marked_body "$RID")"
ct_write_db "$CASE/body.md"
grep -q "head=$CT_OTHER" "$CASE/body.md" && pass "the rendered body shows a head the model never had" \
    || fail "the rendered body carries no head=$CT_OTHER"
run_setup
recovered_ok "a rendered run line matching every node PR's marker" run-line
WANT_NODES=$(ct_nodes_of "$REPO/docs/plans/PLAN-t.md")
if [ "$(val run/node/pr-repo-a-core | jq -c .)" = "{\"head\":\"$CT_HEAD\",\"pr\":11,\"repo\":\"acme/repo-a\"}" ] \
    && [ "$(val run/node/pr-repo-a-cli | jq -r .head)" = "$CT_HEAD" ]; then
    pass "each node's head is the live headRefOid, never the body's head="
else
    fail "recovered heads: core=[$(val run/node/pr-repo-a-core)] cli=[$(val run/node/pr-repo-a-cli)]"
fi
[ "$(setup_val .nodes)" = "$(printf '%s' "$WANT_NODES" | jq -cS .)" ] && [ "$(val run/cascade)" = '{"verdict":"not-run"}' ] \
    && [ "$(setup_val '[.store, .coordination_pr, .repos, .mode, .run_lines]')" = '["github",10,["acme/repo-a"],"coordinated",{"topic":"t"}]' ] \
    && pass "the node list comes from the PLAN, the cascade is not-run, the store github" \
    || fail "recovered setup: [$(val run/setup)] cascade=[$(val run/cascade)]"
[ "$(val run_id)" = "$RID" ] && pass "the run line's id becomes the session's run_id" || fail "run_id: [$(val run_id)]"
# The recovered root's trail: its address again (a new session id), and each
# PR it rebuilt, re-indexed under the run's id so a lookup reaches this
# session rather than the lost one.
REPO_P=$(cd "$REPO" && pwd -P)
TRAIL_ROLES=$(for k in acme.repo-a.10 acme.repo-a.11 acme.repo-a.12; do val "trail/pr/$k" | jq -r '"\(.number):\(.role):\(.state)"'; done | tr '\n' ' ')
if [ "$(val trail/self | jq -c '{workspace, run_id}')" = "$(jq -nc --arg w "$REPO_P" --arg r "$RID" '{workspace: $w, run_id: $r}')" ] \
    && [ "$TRAIL_ROLES" = "10:coordination:open 11:node:open 12:node:open " ] \
    && [ -f "$CASE/ctx/pr.acme.repo-a.11/run/$RID" ] && [ -f "$CASE/ctx/pr.acme.repo-a.12/run/$RID" ] \
    && [ "$(jq -r .session_id "$CASE/ctx/pr.acme.repo-a.11/run/$RID")" = "$(val trail/self | jq -r .session_id)" ]; then
    pass "a recovery writes trail/self with the recovered run_id, and records and re-indexes the coordination and node PRs"
else
    fail "recovered trail: self=[$(val trail/self)] roles=[$TRAIL_ROLES]"
fi
grep -q "pr view 11 --repo acme/repo-a --json url,state,headRefOid,mergeCommit,body" "$GH_CALL_LOG" \
    && pass "each node PR is read live once" || fail "no live read of #11: [$(tr '\n' ';' < "$GH_CALL_LOG")]"
no_remote_write "recovery by the run line"

# Recovery, then the loop's merge: setup's live read of #11's head comes
# before the loop's readiness reads of #11, and both before the merge call,
# which passes the live head (never the body's) to --match-head-commit.
setup_case recover-merge
ct_rendered_body "$CASE/body.md" "$RID" github "$CT_CORE=11"
ct_pr "$CT_REPO" 11 "$BR_CORE" "body=$(ct_marked_body "$RID")"
ct_write_db "$CASE/body.md"
run_setup
recovered_ok "recovery before a merge" run-line
NEXT_OUT=$(cd "$REPO" && bash "$SCRIPT_DIR/coordinated-next.sh" --session "$S" --plan docs/plans/PLAN-t.md --slug "$CT_SLUG" \
    --repos "$(val repos)" --home-repo "$(val home_repo)" --coord-branch "$CT_CB" --merge true --run-id "$RID" 2>"$CASE/next.err")
mkdir -p "$CASE/tmp"
MERGE_OUT=$(cd "$REPO" && TMPDIR="$CASE/tmp" bash "$SCRIPT_DIR/coord-merge.sh" --session "$S" --slug "$CT_SLUG" \
    --home-repo "$(val home_repo)" --coord-branch "$CT_CB" --node "$CT_CORE" 2>"$CASE/merge.err")
ORDER_LOG=$(ct_order)
SETUP_AT=$(grep -n -m1 "^gh pr view 11 --repo acme/repo-a --json url,state,headRefOid,mergeCommit,body" <<<"$ORDER_LOG" | cut -d: -f1)
MERGE_AT=$(grep -n -m1 "^gh pr merge 11 " <<<"$ORDER_LOG" | cut -d: -f1)
READ_AT=$(awk -v s="${SETUP_AT:-0}" 'NR > s && /^gh pr (view|checks) 11 / { print NR; exit }' <<<"$ORDER_LOG")
MERGE_LINE=$(grep -m1 "^gh pr merge 11 " <<<"$ORDER_LOG")
if [ "$NEXT_OUT" = "merge:$CT_CORE" ] && [ -n "$SETUP_AT" ] && [ -n "$READ_AT" ] && [ -n "$MERGE_AT" ] \
    && [ "$SETUP_AT" -lt "$READ_AT" ] && [ "$READ_AT" -lt "$MERGE_AT" ] \
    && grep -q -- "--match-head-commit $CT_HEAD" <<<"$MERGE_LINE" && ! grep -q "$CT_OTHER" <<<"$MERGE_LINE"; then
    pass "setup's live head read, then the readiness reads, then the merge at the live head, in that order"
else
    fail "recover-merge: next=[$NEXT_OUT] setup@$SETUP_AT read@$READ_AT merge@$MERGE_AT merge=[$MERGE_LINE] out=[$MERGE_OUT] err=[$(tail -1 "$CASE/merge.err")]"
fi

# Unanimous markers name the run when nothing else does.
setup_case markers
ct_index_line "$CT_CORE" "$CT_REPO" 11
ct_index_line "$CT_CLI" "$CT_REPO" 12
node_prs "$(ct_marked_body "$RID")" "$(ct_marked_body "$RID")"
ct_write_db
run_setup
recovered_ok "no run line, both node PRs marked alike" markers
[ "$(val run_id)" = "$RID" ] && pass "the markers' id becomes the session's run_id" || fail "markers run_id: [$(val run_id)]"

# A follow-up line alone counts as started; with no node line and no
# identity, the id is minted, and the follow-up, whose node has no node line,
# is dropped and reported.
setup_case follow-up-only
CT_INDEX="- $CT_CORE/follow-up-14 | $CT_REPO:docs/plans/PLAN-t.md#14 | open
"
ct_write_db
run_setup
recovered_ok "a follow-up line alone, nothing else started" minted
[[ $(val run_id) =~ ^[0-9a-f]{32}$ ]] && pass "an empty map with no identity mints the run_id" || fail "minted run_id: [$(val run_id)]"
[ -z "$(ls "$CASE/ctx/$S/run" | grep -v -e '^setup$' -e '^cascade$' -e '^recovered$')" ] \
    && grep -qx "follow-up-dropped:https://github.com/acme/repo-a/pull/14" <<<"$OUT" \
    && grep -q "dropped the follow-up .*: its node $CT_CORE is no node PR" "$CASE/stderr" \
    && ! grep -q 'not recovered yet' "$CASE/stderr" \
    && pass "the follow-up line is read, dropped with follow-up-dropped:<url>, and no run/follow-up key is written" \
    || fail "follow-up-only: out=[$OUT] keys=[$(ls -R "$CASE/ctx/$S/run" | tr '\n' ' ')] stderr=[$(tail -2 "$CASE/stderr")]"

# Markers that don't prove the run.
setup_case unproven-one
ct_rendered_body "$CASE/body.md" "$RID" github "$CT_CORE=11" "$CT_CLI=12"
node_prs "$(ct_marked_body "$OTHER_ID")" "$(ct_marked_body "$RID")"
ct_write_db "$CASE/body.md"
run_setup
stopped "one node PR with another run's marker" recovery-unproven
grep -q "$CT_CORE ($URL11): another run's marker" "$CASE/stderr" && ! grep -q "$CT_CLI (" "$CASE/stderr" \
    && grep -q -- '--adopt-run' "$CASE/stderr" \
    && pass "the stop names that node, its reason and URL, and suggests --adopt-run" \
    || fail "unproven-one stderr: [$(cat "$CASE/stderr")]"
[ ! -f "$CASE/ctx/$S/run_id" ] && pass "a recovery-unproven stop writes no run_id" || fail "run_id written: [$(val run_id)]"
setup_case unproven-two
ct_rendered_body "$CASE/body.md" "$RID" github "$CT_CORE=11" "$CT_CLI=12"
node_prs "$(ct_marked_body "$OTHER_ID")" "$PLAIN_BODY"
ct_write_db "$CASE/body.md"
run_setup
stopped "a foreign-marked and an unmarked node PR" recovery-unproven
grep -q "$CT_CORE ($URL11): another run's marker" "$CASE/stderr" && grep -q "$CT_CLI ($URL12): no marker" "$CASE/stderr" \
    && pass "both are named, each with its reason" || fail "unproven-two stderr: [$(cat "$CASE/stderr")]"
no_remote_write "recovery-unproven"
setup_case no-identity
ct_index_line "$CT_CORE" "$CT_REPO" 11
ct_index_line "$CT_CLI" "$CT_REPO" 12
node_prs "$(ct_marked_body "$OTHER_ID")" "$(ct_marked_body "$RID")"
ct_write_db
run_setup
stopped "node PRs with no identity (no carried id, no run line, markers disagree)" recovery-unproven
[ ! -f "$CASE/ctx/$S/run_id" ] && grep -q "$CT_CORE ($URL11): no identity" "$CASE/stderr" \
    && grep -q "$CT_CLI ($URL12): no identity" "$CASE/stderr" \
    && pass "every node PR is named, and no run_id is minted" || fail "no identity: [$(cat "$CASE/stderr")]"

# Ownership, which --adopt-run never bypasses.
setup_case not-owned
ct_index_line "$CT_CORE" "$CT_REPO" 11
ct_index_line "$CT_CLI" "$CT_REPO" 12
node_prs "$(ct_marked_body "$RID")" "$(ct_marked_body "$RID")"
CT_PRS=$(printf '%s' "$CT_PRS" | jq -c '(.[] | select(.number == 12) | .author) = "someone-else"')
ct_write_db
run_setup --adopt-run "$ADOPT_ID"
stopped "an index node whose PR another author opened, even with --adopt-run" recovery-unproven
grep -q "$CT_CLI (acme/repo-a#12): not owned on $BR_CLI" "$CASE/stderr" && ! grep -q -- 'invoke again with --adopt-run' "$CASE/stderr" \
    && pass "the stop names it not owned, and suggests no --adopt-run" || fail "not-owned stderr: [$(cat "$CASE/stderr")]"
no_remote_write "an unowned index node with --adopt-run"
setup_case outside-plan
ct_index_line "$CT_CORE" "$CT_REPO" 11
ct_index_line pr-stranger eval-org/stranger 7
node_prs "$(ct_marked_body "$RID")" "$PLAIN_BODY"
ct_write_db
run_setup
stopped "an index node outside the PLAN" recovery-unproven
grep -q "pr-stranger (eval-org/stranger#7): outside the PLAN" "$CASE/stderr" && ! grep -q stranger "$GH_CALL_LOG" \
    && pass "it is named outside the PLAN, with no GitHub read of it" || fail "outside: [$(cat "$CASE/stderr")]"

# --- recovery: the carried id, the index, the PLAN ---------------------------------

# A pre-feature run: the session holds only its run_id, the body is the old
# format (a coordination self row, index lines, no separator).
setup_case pre-feature
seed_id
ct_index_line coordination "$CT_REPO" 10
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_OTHER"
ct_index_line "$CT_CLI" "$CT_REPO" 12
node_prs "$(ct_marked_body "$SEEDED_ID")" "$(ct_marked_body "$SEEDED_ID")"
ct_write_db
run_setup
recovered_ok "a pre-feature run with its run_id and an old-format body" carried
[ "$(val run_id)" = "$SEEDED_ID" ] && [ "$(setup_val .store)" = '"github"' ] \
    && [ "$(ls "$CASE/ctx/$S/run/node" | tr '\n' ' ')" = "pr-repo-a-cli pr-repo-a-core " ] \
    && pass "its run_id is kept, the store is github, and the self row is no node" \
    || fail "pre-feature: run_id=[$(val run_id)] nodes=[$(ls "$CASE/ctx/$S/run/node" | tr '\n' ' ')]"
: > "$CASE/koto-calls.log"
run_setup
if [ "$RC" -eq 0 ] && grep -qx record=existing <<<"$OUT" && ! grep -q '^recovered=' <<<"$OUT" \
    && ! ct_ctx_writes | grep -q 'run/recovered'; then
    pass "the next invocation is record=existing and writes no recovery marker"
else
    fail "after recovery: rc=$RC out=[$OUT] writes=[$(ct_ctx_writes | tr '\n' ';')]"
fi

# /scope's body: a PR Index heading with no entry.
setup_case scope-empty
seed_id
run_setup
recovered_ok "/scope's body with a carried id and no owned node PR: an empty map" carried
[ ! -d "$CASE/ctx/$S/run/node" ] && pass "the empty map records no node" || fail "nodes: [$(ls "$CASE/ctx/$S/run/node")]"
setup_case index-missing
seed_id
ct_pr "$CT_REPO" 11 "$BR_CORE" "body=$(ct_marked_body "$SEEDED_ID")"
ct_write_db
run_setup
stopped "/scope's body, an owned PR on $BR_CORE" coordination-index-missing
grep -q "$CT_CORE" "$CASE/stderr" && pass "the stop names the node with the owned PR" || fail "index-missing: [$(cat "$CASE/stderr")]"

# The PLAN gone, with no record.
setup_case plan-gone
seed_id
ct_index_line "$CT_CORE" "$CT_REPO" 11
ct_write_db
rm -f "$REPO/docs/plans/PLAN-t.md"
run_setup
stopped "the PLAN gone, no record, an index line" recovery-plan-gone
setup_case plan-gone-no-index
seed_id
rm -f "$REPO/docs/plans/PLAN-t.md"
run_setup
stopped "the PLAN gone, no record, no index line" coordination-index-missing
setup_case plan-gone-new
rm -f "$REPO/docs/plans/PLAN-t.md"
run_setup
[ "$RC" -eq 64 ] && [ -z "$(written)" ] && grep -q 'no PLAN at' "$CASE/stderr" \
    && pass "the PLAN gone and nothing started is the usage error it always was" || fail "no PLAN, new: rc=$RC"

# The PLAN gone, the record held: repos from run/setup, plan_abs computed.
setup_case plan-gone-record
run_setup
ABS0=$(val plan_abs)
rm -f "$REPO/docs/plans/PLAN-t.md"
run_setup
[ "$RC" -eq 0 ] && grep -qx record=existing <<<"$OUT" && grep -qx "repos=acme/repo-a" <<<"$OUT" \
    && grep -qx "plan_abs=$ABS0" <<<"$OUT" \
    && pass "with the record held and the PLAN gone: exit 0, repos from run/setup, plan_abs computed" \
    || fail "plan gone with a record: rc=$RC out=[$OUT] stderr=[$(tail -1 "$CASE/stderr")]"
rmdir "$REPO/docs/plans"
run_setup
[ "$RC" -eq 0 ] && grep -qx "plan_abs=$ABS0" <<<"$OUT" \
    && pass "and with the PLAN's directory gone too, plan_abs is still the same path" \
    || fail "plan dir gone: rc=$RC out=[$OUT] stderr=[$(tail -1 "$CASE/stderr")]"

# A body over the cap, and an index line outside the grammar.
setup_case body-full
seed_id
awk 'BEGIN { s = "> This is a **coordination PR** for a coordinated effort.\n\n## PR Index\n\n"; while (length(s) < 60001) s = s "x"; printf "%s", substr(s, 1, 60001) }' > "$CASE/big.md"
ct_write_db "$CASE/big.md"
run_setup
stopped "a 60,001-byte body" coordination-body-full
setup_case bad-line
seed_id
CT_INDEX="- $CT_CORE | $CT_REPO:docs/plans/PLAN-t.md#11 | pending
"
ct_write_db
run_setup
stopped "an index line outside the entry grammar" recovery-unproven

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
    && grep -qx "coordination_pr=https://github.com/acme/plans/pull/10" <<<"$OUT"; then
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
for bad in "--store s3" "--coordination-pr https://x/y" "--follow-up core" "--follow-up-remove yes" "--adopt-run XYZ" \
    "--follow-up-remove true"; do
    # shellcheck disable=SC2086
    (cd "$REPO" && bash "$SETUP" --session "$S" --plan docs/plans/PLAN-t.md $bad >/dev/null 2>&1); rc=$?
    [ "$rc" -eq 64 ] && pass "[$bad] exits 64" || fail "usage [$bad]: rc=$rc"
done
[ -z "$(written)" ] && pass "no usage error wrote anything" || fail "a usage error wrote [$(written)]"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

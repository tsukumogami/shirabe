#!/usr/bin/env bash
# record-coord-follow-up_test.sh — coord_setup's follow-ups: --follow-up
# recorded, refused and removed, and recovery keeping or dropping the
# follow-up lines it reads
# Part of the execute skill
#
# Each case runs record-coord-setup.sh in a real coordination checkout with
# the koto stub and the eval gh shim's repository model (see
# coord-test-helpers.sh), as record-coord-setup_test.sh does; this suite holds
# the follow-up cases so that one stays readable. Every case's GitHub model
# holds the coordination PR, #10, and node core's PR, #11; a follow-up is a PR
# on fix/<n> (ct_follow_up_pr).
#
# Cases:
#   record-open        a held record and #21 open: run/follow-up/<core>/21
#                      {repo, pr, head: the live head, removed false},
#                      follow-up=recorded:<url>, then one body post (pr edit
#                      10) after the key's koto write, its follow-up line
#                      right after core's
#   record-merged      #22 MERGED: recorded with its live head, and the render
#                      observes its merge commit as merged_head
#   re-record          #21's head moved: recording it again updates the head
#   space-form         `--follow-up "<node> <url>"`, the form the template
#                      hands setup from FOLLOW_UP, records the same key; the
#                      `<node>=<url>` form exits 64 with no koto or gh call
#   refusals           each exits 71 with only stop=<code>, changes no key, and
#                      posts nothing: follow-up-node (a node with no recorded
#                      PR, a gate node, an unknown node, the coordination PR's
#                      URL, a node PR's URL, a follow-up recorded under another
#                      node, a new run, which seals nothing, and --remove of an
#                      unrecorded follow-up); follow-up-repo; follow-up-base;
#                      follow-up-author (another author, and a fork);
#                      follow-up-closed
#   remove-closed      #21 recorded, then closed: --follow-up-remove true marks
#                      it removed with no read of #21, and the posted body no
#                      longer names it
#   two-follow-ups     #21 and #22 on core render as two lines named by number,
#                      after core's, and coordination-gate-refs.sh lists core,
#                      #21 and #22
#   recovery           a rendered body naming core and seven follow-ups: #21
#                      (open, no marker) and #22 (MERGED) kept with live heads
#                      and #22's merged_head; #23 (another author), #24
#                      (closed), #25 (a fork), #26 (a node with no index line)
#                      and #27 (an id naming another number) each dropped with
#                      follow-up-dropped:<url>; still record=recovered; a
#                      failed read of a follow-up exits 72 with nothing written
#   the run's record   a coordinated run walked end to end: the coordination
#                      PR in acme-plans/coord, two node PRs in acme/repo-a and
#                      acme/repo-b (node-cut.sh from a clone of each, then
#                      node-push.sh), a follow-up on the first node. Setup
#                      writes trail/self (the coordination checkout, the
#                      run_id); run-record-lookup.sh from each of the four
#                      PRs, run from a directory of its own, names execute-t,
#                      the run_id and the same four PRs with their roles and
#                      states; --steps lists each work item's
#                      work-on-<slug>-<node>-<item> session, its node's
#                      worktree and the PLAN at plan_abs as committed at its
#                      hand-off (two SHAs, the owner having refined the PLAN
#                      between the nodes), the snapshot's text that commit's;
#                      the follow-up, closed and removed, stays in the trail
#                      as closed with its index entry kept, and its lookup
#                      still reaches the run
#
# Usage: record-coord-follow-up_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
SETUP="$SCRIPT_DIR/record-coord-setup.sh"
REPO_ROOT=$(CDPATH='' cd "$SCRIPT_DIR/../../.." && pwd)

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

S=execute-t
RID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
URL10="https://github.com/acme/repo-a/pull/10"
URL11="https://github.com/acme/repo-a/pull/11"
fu_url() { printf 'https://github.com/acme/repo-a/pull/%s' "$1"; }
BR_CORE="impl/$CT_SLUG-$CT_CORE"
MERGE_SHA=5555555555555555555555555555555555555555

val() { cat "$CASE/ctx/$S/$1" 2>/dev/null; }
store_sum() {
    (cd "$CASE/ctx" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
        printf '%s\n' "$f"; cat "$f"; printf '\n'
    done) | cksum
}
written() { ls "$CASE/ctx/$S" 2>/dev/null | grep -vx run_id; }
# live_edit <jq> -- change the model the shim already copied (the PRs as the
# run left them).
live_edit() {
    jq "$1" "$GH_CALL_LOG.d/db.json" > "$CASE/db" && mv "$CASE/db" "$GH_CALL_LOG.d/db.json"
}
# posted_body -- the coordination PR's body as the model holds it now.
posted_body() { jq -r '.prs[] | select(.number == 10) | .body' "$GH_CALL_LOG.d/db.json"; }

setup_case() { # setup_case <name> [gated] -- a checkout on the coordination branch, no record
    ct_case "$1"
    rm -f "$CASE/ctx/$S/run_id"
    REPO="$CT_WORK/$1-repo"
    ct_repo "$REPO"
    ct_plan "$REPO" "${2:-}"
    mkdir -p "$CASE/ctx/$S"
}
# held_case <name> [gated] -- a session holding its record: run/setup, core's
# node PR #11 recorded and open, and its run_id.
held_case() {
    setup_case "$@"
    ct_record_setup github 10 "$(ct_nodes_of "$REPO/docs/plans/PLAN-t.md")"
    ct_record_node "$CT_CORE" "$CT_REPO" 11
    printf '%s' "$RID" > "$CASE/ctx/$S/run_id"
    ct_pr "$CT_REPO" 11 "$BR_CORE" "body=$(ct_marked_body "$RID")"
}
run_setup() { # run_setup [flags...]
    OUT=$(cd "$REPO" && bash "$SETUP" --session "$S" --plan docs/plans/PLAN-t.md "$@" 2>"$CASE/stderr")
    RC=$?
}
follow_up() { run_setup --follow-up "$CT_CORE $(fu_url "$1")" "${@:2}"; }

# refused <label> <code> [flags...] -- run setup on a snapshot of the case,
# and check exit 71, the one stop line, an unchanged store, no body post and
# no koto context write.
refused() {
    local label="$1" code="$2" before
    shift 2
    before=$(store_sum)
    : > "$CASE/koto-calls.log"
    : > "$GH_CALL_LOG"
    run_setup "$@"
    if [ "$RC" -eq 71 ] && [ "$OUT" = "stop=$code" ] && [ "$(store_sum)" = "$before" ] \
        && ! grep -q '^pr edit ' "$GH_CALL_LOG" && [ -z "$(ct_ctx_writes)" ]; then
        pass "$label: stop=$code, nothing written, nothing posted"
    else
        fail "$label: rc=$RC out=[$OUT] writes=[$(ct_ctx_writes | tr '\n' ';')] stderr=[$(tail -1 "$CASE/stderr")]"
    fi
}

# --- recording ------------------------------------------------------------------------

held_case record-open
ct_follow_up_pr "$CT_REPO" 21
ct_write_db
follow_up 21
KEY="run/follow-up/$CT_CORE/21"
if [ "$RC" -eq 0 ] && grep -qx "follow-up=recorded:$(fu_url 21)" <<<"$OUT" && grep -qx body=posted <<<"$OUT" \
    && grep -qx record=existing <<<"$OUT" \
    && [ "$(val "$KEY" | jq -c .)" = "{\"head\":\"$CT_HEAD\",\"pr\":21,\"removed\":false,\"repo\":\"acme/repo-a\"}" ]; then
    pass "an open follow-up is recorded with its live head, and the body is posted"
else
    fail "record-open: rc=$RC out=[$OUT] key=[$(val "$KEY")] stderr=[$(tail -2 "$CASE/stderr" | tr '\n' ' ')]"
fi
[ "$(ct_calls | grep -c '^pr edit 10 --repo acme/repo-a --body-file')" -eq 1 ] \
    && pass "recording a follow-up posts the coordination PR's body once" \
    || fail "body posts: [$(ct_calls | grep '^pr edit' | tr '\n' ';')]"
ADD_AT=$(ct_order | grep -n -m1 "^koto context add $S $KEY" | cut -d: -f1)
POST_AT=$(ct_order | grep -n -m1 '^gh pr edit 10 ' | cut -d: -f1)
[ -n "$ADD_AT" ] && [ -n "$POST_AT" ] && [ "$ADD_AT" -lt "$POST_AT" ] \
    && pass "the body post comes after the koto write of the follow-up's key" \
    || fail "order: add@$ADD_AT post@$POST_AT"
WANT_LINE="- $CT_CORE/follow-up-21 | acme/repo-a:docs/plans/PLAN-t.md#21 | open | head=$CT_HEAD"
AFTER_CORE=$(posted_body | awk -v n="- $CT_CORE |" 'index($0, n) == 1 { getline; print; exit }')
[ "$AFTER_CORE" = "$WANT_LINE" ] && pass "the posted body names the follow-up on the line after its node's" \
    || fail "the line after core's: [$AFTER_CORE]"

# Recording it again, after its head moved, updates the head.
live_edit '(.prs[] | select(.number == 21) | .headRefOid) = "'"$CT_OTHER"'"'
follow_up 21
[ "$RC" -eq 0 ] && [ "$(val "$KEY" | jq -r '[.head, .removed] | join(" ")')" = "$CT_OTHER false" ] \
    && pass "recording a follow-up again updates its head" \
    || fail "re-record: rc=$RC key=[$(val "$KEY")]"

# The form the template hands setup: FOLLOW_UP carries `<node> <url>`, since
# koto's own value allowlist has no `=`. It records the same key.
live_edit '(.prs[] | select(.number == 21) | .headRefOid) = "'"$CT_HEAD"'"'
run_setup --follow-up "$CT_CORE $(fu_url 21)"
if [ "$RC" -eq 0 ] && grep -qx "follow-up=recorded:$(fu_url 21)" <<<"$OUT" \
    && [ "$(val "$KEY" | jq -r '[.head, .removed] | join(" ")')" = "$CT_HEAD false" ]; then
    pass "--follow-up \"<node> <url>\", as the template passes FOLLOW_UP, records the follow-up"
else
    fail "space form: rc=$RC out=[$OUT] key=[$(val "$KEY")] stderr=[$(tail -2 "$CASE/stderr" | tr '\n' ' ')]"
fi

# The `=` form is the user's, which execute-open.sh turns into the space form;
# setup takes only the space form, so `<node>=<url>` is a usage error before
# any koto or gh call.
: > "$CASE/koto-calls.log"
: > "$GH_CALL_LOG"
run_setup --follow-up "$CT_CORE=$(fu_url 21)"
if [ "$RC" -eq 64 ] && ! [ -s "$CASE/koto-calls.log" ] && ! [ -s "$GH_CALL_LOG" ]; then
    pass "--follow-up \"<node>=<url>\" exits 64 with no koto or gh call"
else
    fail "= form: rc=$RC koto=[$(tr '\n' ';' < "$CASE/koto-calls.log")] gh=[$(tr '\n' ';' < "$GH_CALL_LOG")]"
fi

held_case record-merged
ct_follow_up_pr "$CT_REPO" 22 'state="MERGED"' "merge_sha=\"$MERGE_SHA\""
ct_write_db
follow_up 22
KEY="run/follow-up/$CT_CORE/22"
if [ "$RC" -eq 0 ] && [ "$(val "$KEY" | jq -r '[.head, .merged_head, .removed] | join(" ")')" = "$CT_HEAD $MERGE_SHA false" ] \
    && grep -qx "observed=$CT_CORE/follow-up-22:$MERGE_SHA" <<<"$OUT"; then
    pass "a MERGED follow-up is recorded with its live head, and the render records its merge commit"
else
    fail "record-merged: rc=$RC out=[$OUT] key=[$(val "$KEY")]"
fi

# --- the five refusals ------------------------------------------------------------------

held_case refuse-node gated
ct_pr "$CT_REPO" 12 "impl/$CT_SLUG-$CT_CLI"
ct_follow_up_pr "$CT_REPO" 21
ct_write_db
refused "a node with no recorded PR" follow-up-node --follow-up "$CT_CLI $(fu_url 21)"
refused "a gate node" follow-up-node --follow-up "publish-core $(fu_url 21)"
refused "a node outside the run" follow-up-node --follow-up "nope $(fu_url 21)"
refused "the coordination PR's URL" follow-up-node --follow-up "$CT_CORE $URL10"
refused "the node's own PR" follow-up-node --follow-up "$CT_CORE $URL11"
refused "--remove of a follow-up never recorded" follow-up-node --follow-up "$CT_CORE $(fu_url 21)" --follow-up-remove true
ct_record_node "$CT_CLI" "$CT_REPO" 12
ct_record_follow_up "$CT_CLI" "$CT_REPO" 21
refused "a follow-up already recorded under another node" follow-up-node --follow-up "$CT_CORE $(fu_url 21)"

setup_case refuse-new
ct_follow_up_pr "$CT_REPO" 21
ct_write_db
refused "a new run, which has no node PR" follow-up-node --follow-up "$CT_CORE $(fu_url 21)"
[ -z "$(written)" ] && pass "the new run's refusal sealed no run/setup" || fail "a new run's refusal wrote [$(written | tr '\n' ' ')]"

held_case refuse-repo
ct_pr acme/repo-b 21 fix/21
ct_write_db
refused "a follow-up in another repository than its node's" follow-up-repo \
    --follow-up "$CT_CORE https://github.com/acme/repo-b/pull/21"

held_case refuse-base
ct_follow_up_pr "$CT_REPO" 21 'baseRefName="release"'
ct_write_db
refused "a follow-up based on another branch" follow-up-base --follow-up "$CT_CORE $(fu_url 21)"

held_case refuse-author
ct_follow_up_pr "$CT_REPO" 21 'author="someone-else"'
ct_follow_up_pr "$CT_REPO" 22 'isCrossRepository=true'
ct_write_db
refused "a follow-up another author opened" follow-up-author --follow-up "$CT_CORE $(fu_url 21)"
refused "a follow-up from a fork" follow-up-author --follow-up "$CT_CORE $(fu_url 22)"

held_case refuse-closed
ct_follow_up_pr "$CT_REPO" 21 'state="CLOSED"'
ct_write_db
refused "a follow-up closed unmerged" follow-up-closed --follow-up "$CT_CORE $(fu_url 21)"
grep -q -- "--remove" "$CASE/stderr" && pass "the closed stop names --remove" || fail "closed stderr: [$(cat "$CASE/stderr")]"

# --- removal -------------------------------------------------------------------------------

held_case remove-closed
ct_follow_up_pr "$CT_REPO" 21
ct_write_db
follow_up 21
grep -q "follow-up-21" <<<"$(posted_body)" && pass "before removal the body names the follow-up" \
    || fail "the body never named follow-up-21"
live_edit '(.prs[] | select(.number == 21) | .state) = "CLOSED"'
: > "$GH_CALL_LOG"
follow_up 21 --follow-up-remove true
KEY="run/follow-up/$CT_CORE/21"
if [ "$RC" -eq 0 ] && grep -qx "follow-up=removed:$(fu_url 21)" <<<"$OUT" && [ "$(val "$KEY" | jq -r .removed)" = true ] \
    && ! ct_calls | grep -q '^pr view 21 ' && grep -qx body=posted <<<"$OUT" \
    && ! grep -q "follow-up-21" <<<"$(posted_body)"; then
    pass "--follow-up-remove marks a closed follow-up removed, reads it not at all, and the body drops its line"
else
    fail "remove-closed: rc=$RC out=[$OUT] key=[$(val "$KEY")] calls=[$(ct_calls | grep 'pr view' | tr '\n' ';')]"
fi

# --- two follow-ups on one node ----------------------------------------------------------

held_case two-follow-ups
ct_follow_up_pr "$CT_REPO" 21
ct_follow_up_pr "$CT_REPO" 22
ct_write_db
follow_up 22
follow_up 21
IDX=$(posted_body | awk '/^- / { sub(/ \|.*/, ""); printf "%s ", $0 }')
[ "$RC" -eq 0 ] && [ "$IDX" = "- $CT_CORE - $CT_CORE/follow-up-21 - $CT_CORE/follow-up-22 " ] \
    && pass "two follow-ups on one node render as two lines named by number, after the node" \
    || fail "two follow-ups index: [$IDX]"
REFS=$(posted_body | bash "$REPO_ROOT/scripts/coordination-gate-refs.sh" acme/repo-a 10 | tr '\n' ' ')
[ "$REFS" = "acme/repo-a:docs/plans/PLAN-t.md#11 acme/repo-a:docs/plans/PLAN-t.md#21 acme/repo-a:docs/plans/PLAN-t.md#22 " ] \
    && pass "coordination-gate-refs.sh lists the node and both follow-ups" || fail "gate refs: [$REFS]"

# --- recovery ----------------------------------------------------------------------------------

# recovery_case <name> -- a session with no record over a rendered body: the
# run line names RID, core's #11 carries its marker, and seven follow-up
# lines follow core's (head CT_OTHER, which no model PR has).
recovery_case() {
    setup_case "$1"
    ct_rendered_body "$CASE/body.md" "$RID" github "$CT_CORE=11"
    awk -v core="- $CT_CORE |" -v c="$CT_CORE" -v cli="$CT_CLI" -v h="$CT_OTHER" '
        { print }
        index($0, core) == 1 {
            for (n = 21; n <= 25; n++)
                printf "- %s/follow-up-%d | acme/repo-a:docs/plans/PLAN-t.md#%d | open | head=%s\n", c, n, n, h
            printf "- %s/follow-up-26 | acme/repo-a:docs/plans/PLAN-t.md#26 | open | head=%s\n", cli, h
            printf "- %s/follow-up-28 | acme/repo-a:docs/plans/PLAN-t.md#27 | open | head=%s\n", c, h
        }' "$CASE/body.md" > "$CASE/body.fu.md"
    ct_pr "$CT_REPO" 11 "$BR_CORE" "body=$(ct_marked_body "$RID")"
    ct_follow_up_pr "$CT_REPO" 21
    ct_follow_up_pr "$CT_REPO" 22 'state="MERGED"' "merge_sha=\"$MERGE_SHA\""
    ct_follow_up_pr "$CT_REPO" 23 'author="someone-else"'
    ct_follow_up_pr "$CT_REPO" 24 'state="CLOSED"'
    ct_follow_up_pr "$CT_REPO" 25 'isCrossRepository=true'
    ct_follow_up_pr "$CT_REPO" 26
    ct_follow_up_pr "$CT_REPO" 27
    ct_write_db "$CASE/body.fu.md"
}

recovery_case recovery
run_setup
FU="$CASE/ctx/$S/run/follow-up/$CT_CORE"
if [ "$RC" -eq 0 ] && grep -qx record=recovered <<<"$OUT" && [ "$(ls "$FU" 2>/dev/null | tr '\n' ' ')" = "21 22 " ] \
    && [ ! -d "$CASE/ctx/$S/run/follow-up/$CT_CLI" ]; then
    pass "recovery keeps #21 and #22 and records no other follow-up"
else
    fail "recovery: rc=$RC out=[$OUT] kept=[$(ls -R "$CASE/ctx/$S/run/follow-up" 2>/dev/null | tr '\n' ' ')] stderr=[$(tail -3 "$CASE/stderr" | tr '\n' ' ')]"
fi
[ "$(val "run/follow-up/$CT_CORE/21" | jq -c .)" = "{\"head\":\"$CT_HEAD\",\"pr\":21,\"removed\":false,\"repo\":\"acme/repo-a\"}" ] \
    && pass "a kept open follow-up, with no marker, holds its live head, never the body's" \
    || fail "#21: [$(val "run/follow-up/$CT_CORE/21")]"
[ "$(val "run/follow-up/$CT_CORE/22" | jq -r '[.head, .merged_head] | join(" ")')" = "$CT_HEAD $MERGE_SHA" ] \
    && pass "a kept MERGED follow-up holds its live head and merge commit" \
    || fail "#22: [$(val "run/follow-up/$CT_CORE/22")]"
DROPS=$(grep '^follow-up-dropped:' <<<"$OUT" | tr '\n' ' ')
# In the order cb_parse returns them: by node, then by number.
WANT_DROPS="follow-up-dropped:$(fu_url 26) follow-up-dropped:$(fu_url 23) follow-up-dropped:$(fu_url 24) follow-up-dropped:$(fu_url 25) follow-up-dropped:$(fu_url 27) "
[ "$DROPS" = "$WANT_DROPS" ] && pass "another author, a closed one, a fork, a mismatched id and a node with no index line are each dropped and reported" \
    || fail "drops: [$DROPS]"
grep -q "its id names follow-up-28 and its ref #27" "$CASE/stderr" && grep -q "it is closed unmerged" "$CASE/stderr" \
    && pass "each drop's reason goes to stderr" || fail "drop reasons: [$(grep dropped "$CASE/stderr" | tr '\n' ';')]"
grep -q "$CT_OTHER" <<<"$(cat "$CASE"/ctx/$S/run/follow-up/*/* 2>/dev/null)" \
    && fail "a head the body names was recorded" || pass "no follow-up head the body names is recorded"

recovery_case recovery-read-fails
export GH_SHIM_FAIL='^pr view 21 '
run_setup
unset GH_SHIM_FAIL
[ "$RC" -eq 72 ] && [ -z "$(written)" ] && [ ! -f "$CASE/ctx/$S/run_id" ] \
    && pass "a follow-up read that fails exits 72 with nothing written, never dropping it" \
    || fail "read fails: rc=$RC written=[$(written | tr '\n' ' ')]"

# --- a coordinated run's record: every PR leads to one root -----------------------------

# The layout: the coordination checkout is acme-plans/coord (its PR #10, the
# model's default_repo), the PLAN's two nodes land in acme/repo-a and
# acme/repo-b, each cut from a clone of its own, and #60 in acme/repo-a is a
# follow-up on the first node. The run goes the way execute-coordinated.md's
# directives drive it: setup in the coordination checkout; for each node, the
# dispatch step's record of each work item (run-trail.sh plan, from plan_abs,
# and step, with the node's worktree as its workspace) right before the item
# would be handed off, then node-push.sh node in the node's worktree; between
# the nodes the owner commits a refined PLAN; then the follow-up recorded
# through setup. Every lookup runs from a directory of its own.
LOOKUP="$REPO_ROOT/scripts/run-record-lookup.sh"
TRAIL="$REPO_ROOT/scripts/run-trail.sh"
PLAN_TO_TASKS="$SCRIPT_DIR/../../plan/scripts/plan-to-tasks.sh"
HOME_R=acme-plans/coord
ct_case walk
rm -f "$CASE/ctx/$S/run_id"
WALK="$CT_WORK/walk"
mkdir -p "$WALK/elsewhere"
ct_repo "$WALK/home"
ct_plan "$WALK/home" two-repo
(cd "$WALK/home" && git add docs && git commit -q -m "docs: plan" && git push -q origin "$CT_CB")
HOMEDIR=$(cd "$WALK/home" && pwd -P)
for r in a b; do
    ct_repo "$WALK/clone-$r"
    (cd "$WALK/clone-$r" && git checkout -q main)
done
ct_follow_up_pr acme/repo-a 60
ct_write_db
jq --arg h "$HOME_R" '.repos[$h] = .repos["acme/repo-a"] | .default_repo = $h
    | .prs |= map(if .number == 10 then .repo = $h else . end)' "$CASE/scenario/gh/db.json" > "$CASE/db" \
    && mv "$CASE/db" "$CASE/scenario/gh/db.json"

(cd "$HOMEDIR" && bash "$SETUP" --session "$S" --plan docs/plans/PLAN-t.md >"$CASE/setup.out" 2>"$CASE/stderr")
RC=$?
RUN_W=$(val run_id)
SELF=$(val trail/self)
if [ "$RC" -eq 0 ] && grep -qx record=new "$CASE/setup.out" && [ "$(val home_repo)" = "$HOME_R" ] \
    && [ "$(jq -c '{workspace, session, run_id}' <<<"$SELF")" = "$(jq -nc --arg w "$HOMEDIR" --arg s "$S" --arg r "$RUN_W" '{workspace: $w, session: $s, run_id: $r}')" ]; then
    pass "a new coordinated run's setup writes trail/self: the coordination checkout, the session and the minted run_id"
else
    fail "walk setup: rc=$RC self=[$SELF] run_id=[$RUN_W] stderr=[$(tail -2 "$CASE/stderr" | tr '\n' ' ')]"
fi

PLAN_ABS=$(val plan_abs)
TASKS=$(bash "$PLAN_TO_TASKS" "$PLAN_ABS" 2>/dev/null)
NODE_ROWS=$(jq -r '.[] | select(.vars.NODE_KIND == "pr") | [.name, .vars.REPO, .vars.ISSUES] | @tsv' <<<"$TASKS")
: > "$WALK/steps.want"
: > "$WALK/node-prs"
WALK_OK=1
while IFS=$'\t' read -r node repo issues; do
    [ -n "$node" ] || continue
    WT=$(cd "$HOMEDIR" && bash "$SCRIPT_DIR/node-cut.sh" "$CT_SLUG" "$node" --repo-dir "$WALK/clone-${repo#acme/repo-}" 2>>"$CASE/cut.err" \
        | sed -n 's/^worktree=//p')
    [ -n "$WT" ] && [ -d "$WT" ] || { fail "node-cut.sh made no worktree for $node: $(cat "$CASE/cut.err")"; WALK_OK=0; break; }
    WT=$(cd "$WT" && pwd -P)
    for item in $(tr ',' ' ' <<<"$issues"); do
        child="work-on-$CT_SLUG-$node-$item"
        # The dispatch step's record, from the coordination checkout.
        (cd "$HOMEDIR" && bash "$TRAIL" plan --session "$S" --step "$child" --plan "$PLAN_ABS" </dev/null \
            && bash "$TRAIL" step --session "$S" --step "$child" --child "$child" --child-workspace "$WT" </dev/null) \
            2>>"$CASE/trail.err" || { fail "the dispatch record of $child: $(tail -1 "$CASE/trail.err")"; WALK_OK=0; }
        jq -nc --arg s "$child" --arg w "$WT" --arg sha "$(git -C "$HOMEDIR" rev-parse HEAD)" \
            '{step: $s, session: $s, workspace: $w, sha: $sha}' >> "$WALK/steps.want"
    done
    (cd "$WT" && echo "$node" > "$node.txt" && git add "$node.txt" && git commit -q -m "feat: $node")
    OUTP=$(cd "$WT" && bash "$SCRIPT_DIR/node-push.sh" node --session "$S" --slug "$CT_SLUG" --node "$node" --repo "$repo" \
        --issues "$issues" --home-repo "$HOME_R" --coord-branch "$CT_CB" --plan "$PLAN_ABS" --run-id "$RUN_W" 2>>"$CASE/push.err") \
        || { fail "node-push.sh node $node: $(tail -3 "$CASE/push.err")"; WALK_OK=0; break; }
    url=$(sed -n 's/^pr=//p' <<<"$OUTP")
    printf '%s\t%s\t%s\n' "$node" "$repo" "${url##*/}" >> "$WALK/node-prs"
    # The owner refines the PLAN before the next node's work items.
    (cd "$HOMEDIR" && printf '\nRefined after %s.\n' "$node" >> docs/plans/PLAN-t.md \
        && git commit -q -am "docs(plan): refine after $node")
done <<<"$NODE_ROWS"
[ "$WALK_OK" -eq 1 ] && [ "$(wc -l < "$WALK/node-prs" | tr -d ' ')" -eq 2 ] \
    && [ "$(cut -f2 "$WALK/node-prs" | tr '\n' ' ')" = "acme/repo-a acme/repo-b " ] \
    && pass "the run pushes two nodes, one in each repository, recording each work item before its hand-off" \
    || fail "the walk's nodes: [$(tr '\n' ';' < "$WALK/node-prs")]"
NODE_A=$(sed -n 1p "$WALK/node-prs" | cut -f1)
PR_A=$(sed -n 1p "$WALK/node-prs" | cut -f3)
PR_B=$(sed -n 2p "$WALK/node-prs" | cut -f3)

FU60="https://github.com/acme/repo-a/pull/60"
(cd "$HOMEDIR" && bash "$SETUP" --session "$S" --plan docs/plans/PLAN-t.md --follow-up "$NODE_A $FU60" >"$CASE/fu.out" 2>"$CASE/stderr")
RC=$?
[ "$RC" -eq 0 ] && grep -qx "follow-up=recorded:$FU60" "$CASE/fu.out" \
    && pass "the follow-up on the first node is recorded through setup" \
    || fail "walk follow-up: rc=$RC out=[$(cat "$CASE/fu.out")] stderr=[$(tail -2 "$CASE/stderr" | tr '\n' ' ')]"

walk_lookup() { # walk_lookup <owner/repo> <n> [--steps]: from a directory of its own
    OUT=$(cd "$WALK/elsewhere" && bash "$LOOKUP" "$@" </dev/null 2>"$CASE/lookup.err")
    RC=$?
}
want_prs() { # want_prs <follow-up state>
    jq -nc --arg h "$HOME_R" --argjson a "$PR_A" --argjson b "$PR_B" --arg fs "$1" '[
        {repo: $h, number: 10, role: "coordination", state: "open"},
        {repo: "acme/repo-a", number: $a, role: "node", state: "open"},
        {repo: "acme/repo-a", number: 60, role: "follow-up", state: $fs},
        {repo: "acme/repo-b", number: $b, role: "node", state: "open"}] | sort_by(.repo, .number)'
}
WANT_ROOT=$(jq -nc --arg w "$HOMEDIR" --arg s "$S" '{workspace: $w, session: $s}')
for pr in "$HOME_R 10" "acme/repo-a $PR_A" "acme/repo-b $PR_B" "acme/repo-a 60"; do
    # shellcheck disable=SC2086
    walk_lookup $pr
    if [ "$RC" -eq 0 ] && [ "$(jq -c .record_root <<<"$OUT")" = "$WANT_ROOT" ] && [ "$(jq -r .run_id <<<"$OUT")" = "$RUN_W" ] \
        && [ "$(jq -c .prs <<<"$OUT")" = "$(want_prs open)" ] && [ "$(jq -r '.complete and .unique' <<<"$OUT")" = true ]; then
        pass "the lookup from ${pr% *}#${pr#* } names $S, the run_id, and all four PRs with their roles and states"
    else
        fail "lookup ${pr}: rc=$RC out=[$(jq -c . <<<"$OUT" 2>/dev/null)] stderr=[$(cat "$CASE/lookup.err")]"
    fi
done

walk_lookup acme/repo-b "$PR_B" --steps
GOT_STEPS=$(jq -c '[.steps[] | {step, session, workspace, sha: .plan.sha}] | sort_by(.step)' <<<"$OUT" 2>/dev/null)
WANT_STEPS=$(jq -sc 'sort_by(.step)' "$WALK/steps.want")
SHAS=$(jq -r '[.[].sha] | unique | length' <<<"$WANT_STEPS")
if [ "$RC" -eq 0 ] && [ "$GOT_STEPS" = "$WANT_STEPS" ] && [ "$SHAS" -eq 2 ] \
    && [ "$(jq -r '[.steps[].superseded | length] | add' <<<"$OUT")" -eq 0 ]; then
    pass "--steps lists one step per work item: its work-on session, its node's worktree, and the PLAN at plan_abs as of its hand-off"
else
    fail "walk --steps: rc=$RC got=[$GOT_STEPS] want=[$WANT_STEPS]"
fi
TEXT_KEY=$(jq -r '.steps[0].plan.text_key' <<<"$OUT")
FIRST_SHA=$(jq -r '.steps[0].plan.sha' <<<"$OUT")
[ "$(cat "$CASE/ctx/$S/$TEXT_KEY" 2>/dev/null)" = "$(git -C "$HOMEDIR" show "$FIRST_SHA:docs/plans/PLAN-t.md")" ] \
    && pass "a work item's PLAN snapshot is the PLAN's text at the commit it records" \
    || fail "snapshot text at $TEXT_KEY differs from $FIRST_SHA's PLAN"

# The follow-up closed and removed: the trail keeps it as closed, its index
# entry stays, and a lookup from it still reaches the run.
live_edit '(.prs[] | select(.repo == "acme/repo-a" and .number == 60) | .state) = "CLOSED"'
(cd "$HOMEDIR" && bash "$SETUP" --session "$S" --plan docs/plans/PLAN-t.md --follow-up "$NODE_A $FU60" \
    --follow-up-remove true >"$CASE/fu.out" 2>"$CASE/stderr")
RC=$?
walk_lookup acme/repo-a 60
if [ "$RC" -eq 0 ] && grep -qx "follow-up=removed:$FU60" "$CASE/fu.out" \
    && [ -f "$CASE/ctx/pr.acme.repo-a.60/run/$RUN_W" ] \
    && [ "$(jq -c .record_root <<<"$OUT")" = "$WANT_ROOT" ] && [ "$(jq -c .prs <<<"$OUT")" = "$(want_prs closed)" ]; then
    pass "a removed follow-up stays in the root's trail as closed, its index entry kept, and its lookup still reaches the run"
else
    fail "removed follow-up: rc=$RC out=[$(jq -c . <<<"$OUT" 2>/dev/null)] stderr=[$(cat "$CASE/lookup.err") $(tail -1 "$CASE/stderr")]"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

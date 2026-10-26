#!/usr/bin/env bash
# node-push_test.sh — a node's push, its draft PR, and its head= record
# Part of the execute skill
#
# node-push.sh is the one writer of a node's and the cascade's pushed head, in
# the run record (run/node/<node>, run/cascade); the coordination PR's body is
# then rendered from that record by coord-render.sh, the one place a `head=`
# field is built. Each case runs it in a real git worktree
# (node-cut.sh) whose origin is a local bare repository, against the eval gh
# shim's repository model, a shirabe stub, and the koto context stub, with a
# sealed run record naming the coordination PR (see coord-test-helpers.sh).
#
# The run record:
#   a fresh push records run/node/<node> {repo, pr, head=<the pushed sha>};
#   a second push records the new head; a push keeps a recorded merged_head;
#   a push the remote rejects exits 68 and records nothing; a failed body post
#   is body=stale (exit 0) and still leaves the head recorded; a record write
#   that fails exits 70 and posts nothing; a fresh push also records the
#   node PR in the run's trail (trail/pr/<owner>.<repo>.<n>, role node) and
#   writes its index entry (pr.<owner>.<repo>.<n>, run/<run_id> naming the
#   root at its trail/self address), in that order after run/node; a failed
#   index write exits 70 naming the PR and posts nothing, and a root with no
#   trail/self is refused (70) rather than given the node worktree's address;
#   adoption reads the record, not the body: a recorded
#   PR with no owned PR to adopt, or other than the owned one, exits 73;
#   coordination mode records run/cascade {verdict: pushed, head}; order mode
#   records nothing; a session with no record, or a recorded coordination PR
#   that is not open, exits 73.
#
# Cases:
#   usage errors                                 exit 64, no push, no gh write
#     (a node push without --plan, a --plan that is no file, and --plan in
#     the coordination mode among them)
#   a detached HEAD, the wrong branch, the default branch   65, 66, 67
#   a fresh node push                            the branch reaches origin; one
#     draft PR titled feat(<slug>): <node-id> with the fixed fields (node id,
#     work items, coordination link) through --body-file; the rendered body's
#     index line carries head=<the pushed sha>, after --coordination-body
#     validation; a node PR opened posts a body, after the koto write of the
#     head it shows (the request log)
#   the node PR's title and body                 the body's first part is each
#     work item's goal (an outline's Goal, else the table's summary row, else
#     the title), then one top-level ---, the fixed fields, and under include
#     the one Run record line last, never a marker; owned-pr.sh --run-id
#     finds the PR by its index entry, and another run's lookup refuses it;
#     under omit the body carries nothing of the run; body and title pass --pr-body (the
#     stub, and the real validator when one is on PATH); a node changing only
#     docs/ and root Markdown is docs(<slug>), one changing a skill's
#     Markdown is feat; a refused body exits 74 with no pr create or edit
#   a second push                                the owned PR is adopted (no
#     second pr create) and the node's line is replaced, not duplicated; a
#     node pushed posts a body, after the koto write of its new head
#   the verification deferral                    a work item's child holding
#     verification_deferral, or the run's hosted-ci reason: the new node PR's
#     second part carries phase-6-pr.md's ## Verification section, one
#     Reason: line per reason, the shared one once, and work-on's own
#     --deferral-record check passes it; no deferral: no section and no PR
#     body read; an open node PR whose body lacks a child's deferral: exit
#     80, nothing pushed, written or recorded, naming each missing part, and
#     the push goes through once the body records it; hosted-ci with no
#     reason or a failed key read: 72, nothing pushed; a bad --verification,
#     or one in the order mode: 64
#   an indexed node with no owned PR to adopt    exit 73, no pr create
#   a failing body validation                    body=stale (exit 0), no pr
#                                                edit, the posted body unchanged
#   no coordination PR                           exit 73
#   the merge order, on a PLAN with two PR nodes and a gate between them
#     the `## Merge Order` section is the rendered block from run/setup's node
#     list: every node, the gate included, after its predecessors, with its
#     waits_on; a second push renders the same section; the block follows
#     run/setup, not a PLAN edited since, and survives the PLAN's deletion
#   a PLAN with no node named --node             exit 76, nothing pushed, no
#                                                gh write
#   order mode                                   renders the body (pr= and
#     body= lines) with no push, no PR created, and nothing recorded; a second
#     render is unchanged; it takes no --plan (64), and a PLAN deleted before
#     the render keeps the block; usage errors exit 64
#   coordination mode                            pushes the coordination branch,
#     records run/cascade, and renders the body with no self row
#   a record naming a private repository under a public home
#                                                77 after the push and the
#                                                record write, nothing posted
#   each node against its own target, home acme/repo-a over node acme/repo-b:
#     public over public, private over private   pushed; the node PR links
#                                                the coordination PR
#     private over public                        pushed and indexed; the public
#                                                node PR carries no link into
#                                                the private coordination PR
#     public over private                        exit 77, nothing pushed, no gh
#                                                write, the message naming the
#                                                node and not the repository
#     a failed visibility read (node or home)    exit 72, nothing pushed
#     another run's PR on a private node's branch under a public home
#                                                still 77: the check runs before
#                                                the ownership read, whose
#                                                diagnostics name the repository
#     a public node under a private home whose commits carry a private/ path
#     or a Repo Visibility: Private line         exit 78, nothing pushed; no
#                                                scan for any other pair
#     the same pair, a work item's goal in the PLAN naming a private/ path,
#     or a deferral reason the node PR would record naming one
#                                                exit 78, nothing pushed
#   a node in another repository than the coordination PR's, pushed from the
#   coordination checkout:
#     a worktree cut there (no --repo-dir)       exit 79, nothing pushed, no
#                                                gh write, the message naming
#                                                neither repository
#     a separate clone whose origin is the home's exit 79, nothing pushed
#     a worktree cut there, pushing through a remote naming another URL
#                                                exit 79
#     a clone whose origin spells the home's URL another way (ssh, https,
#     case, .git, a trailing slash)              exit 79
#     both origins written through one insteadOf rule   exit 79
#     a clone of the home under a checkout whose origin has a pushurl
#                                                exit 79
#     a clone of the home under a checkout that fetches from a mirror and
#     pushes to the home                         exit 79
#     a --plan outside any git repository        exit 79, nothing pushed
#     the node's own clone (control)             pushed
#   coord_url_key                                one key per repository
#   the push is `git push <remote> HEAD:refs/heads/<branch>`, never forced
#
# Usage: node-push_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PUSH="$SCRIPT_DIR/node-push.sh"
CUT="$SCRIPT_DIR/node-cut.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

# A real shirabe, read before the helpers put their stub ahead of PATH: the
# node PR body case runs it when it is there and knows --pr-body.
REAL_SHIRABE="${SHIRABE_BIN:-$(command -v shirabe 2>/dev/null || true)}"

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

S=execute-t
# np_case <name> -- a fresh case whose session holds a sealed run record
# naming the coordination PR #10, over both model repositories (some nodes
# below land in acme/repo-b).
np_case() {
    ct_case "$1"
    CT_RECORD_REPOS="acme/repo-a,acme/repo-b"
    ct_record_setup
}
rec_node() { cat "$CASE/ctx/$S/run/node/$1" 2>/dev/null; }

# The push itself, read from the script: the explicit refspec, never a force.
PUSH_LINES=$(grep -v '^[[:space:]]*#' "$PUSH" | grep 'git push')
if [ "$(printf '%s\n' "$PUSH_LINES" | grep -c .)" -eq 1 ] \
    && grep -qF 'git push "$REMOTE" "HEAD:refs/heads/$BRANCH"' <<<"$PUSH_LINES" \
    && ! grep -Eq -- '--force|-f( |$)|\+HEAD' <<<"$PUSH_LINES"; then
    pass "the one push is git push <remote> HEAD:refs/heads/<branch>, never forced"
else
    fail "the push lines are: $PUSH_LINES"
fi

# fresh_repo <case> [plan variant] -- a coordination checkout and a cut node
# worktree. Sets REPO, PLAN (the PLAN in the coordination checkout, which the
# node branch doesn't carry), and WT.
fresh_repo() {
    REPO="$CT_WORK/$1-repo"
    PLAN="$REPO/docs/plans/PLAN-t.md"
    ct_repo "$REPO"
    ct_plan "$REPO" "${2:-}"
    (cd "$REPO" && git add docs && git commit -q -m "docs: plan")
    WT=$(cd "$REPO" && bash "$CUT" t "$CT_CORE" 2>/dev/null | sed -n 's/^worktree=//p')
    # An empty WT would leave every `cd "$WT"` below in the checkout running
    # the test, and commit fixture files there.
    [ -n "$WT" ] && [ -d "$WT" ] || { echo "FAIL: node-cut.sh made no worktree for case $1" >&2; exit 1; }
    (cd "$WT" && echo work > work.txt && git add work.txt && git commit -q -m "feat: work")
}

push_node() { # push_node [extra args]
    OUT=$(cd "$WT" && bash "$PUSH" node --session "$S" --slug t --node "$CT_CORE" --repo "$CT_REPO" --issues 1,2 \
        --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" "$@" 2>"$CASE/stderr")
    RC=$?
}

db_body() { jq -r '.prs[] | select(.number == 10) | .body' "$GH_CALL_LOG.d/db.json"; }
# merge_order_section -- the posted body's `## Merge Order` section, heading
# through the line before the next heading.
merge_order_section() {
    db_body | awk '/^## /{ s = ($0 ~ /^## Merge Order/) } s'
}
db_pr() { jq -c --argjson n "$1" '.prs[] | select(.number == $n)' "$GH_CALL_LOG.d/db.json"; }

# --- usage ------------------------------------------------------------------------

np_case usage
ct_write_db
fresh_repo usage
for args in "" "branch --slug t" "node --session $S --slug T --node $CT_CORE --repo $CT_REPO --issues 1 --home-repo $CT_REPO --coord-branch $CT_CB" \
            "node --session $S --slug t --node coordination --repo $CT_REPO --issues 1 --home-repo $CT_REPO --coord-branch $CT_CB" \
            "node --session $S --slug t --node $CT_CORE --repo $CT_REPO --issues '#1' --home-repo $CT_REPO --coord-branch $CT_CB" \
            "coordination --session $S --slug t --node $CT_CORE --home-repo $CT_REPO --coord-branch $CT_CB" \
            "node --session $S --slug t --node $CT_CORE --repo $CT_REPO --issues 1 --home-repo $CT_REPO --coord-branch $CT_CB" \
            "node --session $S --slug t --node $CT_CORE --repo $CT_REPO --issues 1 --home-repo $CT_REPO --coord-branch $CT_CB --plan $CT_WORK/no-such-plan.md" \
            "coordination --session $S --slug t --home-repo $CT_REPO --coord-branch $CT_CB --plan $PLAN"; do
    # shellcheck disable=SC2086
    (cd "$WT" && bash "$PUSH" $args >/dev/null 2>&1); rc=$?
    [ "$rc" -eq 64 ] && pass "usage [$args] exits 64" || fail "usage [$args]: rc=$rc"
done
(cd "$WT" && bash "$PUSH" node --slug t --node "$CT_CORE" --repo "$CT_REPO" --issues 1 --home-repo "$CT_REPO" \
    --coord-branch "$CT_CB" --plan "$PLAN" >/dev/null 2>&1); rc=$?
[ "$rc" -eq 64 ] && pass "a node push without --session exits 64" || fail "no --session: rc=$rc"
if [ -n "$(git -C "$REPO" ls-remote origin "refs/heads/impl/*")" ]; then
    fail "a usage error pushed"
else
    pass "no usage error pushed"
fi

# --- branch refusals --------------------------------------------------------------

np_case refusals
ct_write_db
fresh_repo refusals
(cd "$WT" && git checkout -q --detach)
push_node
[ "$RC" -eq 65 ] && pass "a detached HEAD exits 65" || fail "detached HEAD: rc=$RC"
(cd "$WT" && git checkout -q "impl/t-$CT_CORE" && git checkout -q -b other)
push_node
[ "$RC" -eq 66 ] && pass "the wrong branch exits 66" || fail "wrong branch: rc=$RC"
(cd "$REPO" && git checkout -q main 2>/dev/null)
OUT=$(cd "$REPO" && bash "$PUSH" coordination --session "$S" --slug t --home-repo "$CT_REPO" --coord-branch main 2>/dev/null); RC=$?
[ "$RC" -eq 67 ] && pass "the default branch exits 67" || fail "default branch: rc=$RC"
if ct_calls | grep -Eq '^pr (create|edit)'; then fail "a refusal wrote to GitHub"; else pass "no refusal wrote to GitHub"; fi

# --- a fresh node push ------------------------------------------------------------

np_case fresh
ct_write_db
fresh_repo fresh
push_node
SHA=$(git -C "$WT" rev-parse HEAD)
REMOTE_SHA=$(git -C "$REPO" ls-remote origin "refs/heads/impl/t-$CT_CORE" | cut -f1)
if [ "$RC" -eq 0 ] && [ "$REMOTE_SHA" = "$SHA" ]; then
    pass "a fresh node push reaches origin at HEAD"
else
    fail "a fresh push: rc=$RC remote=[$REMOTE_SHA] head=[$SHA]"
    tail -5 "$CASE/stderr"
fi
CREATES=$(ct_calls | grep -c '^pr create')
CREATE=$(ct_calls | grep '^pr create')
if [ "$CREATES" -eq 1 ] && grep -q -- '--draft' <<<"$CREATE" \
    && grep -q -- "--title feat(t): $CT_CORE" <<<"$CREATE" \
    && grep -q -- '--body-file' <<<"$CREATE" \
    && grep -q -- '--base main' <<<"$CREATE" && grep -q -- "--head impl/t-$CT_CORE" <<<"$CREATE"; then
    pass "one draft PR titled feat(t): $CT_CORE against main, body through --body-file"
else
    fail "the pr create calls: [$CREATE]"
fi
NEW=$(db_pr 50)
NBODY=$(printf '%s' "$NEW" | jq -r '.body')
case "$NBODY" in
    *"$CT_CORE"*"Work items: 1,2"*"Coordination PR: https://github.com/acme/repo-a/pull/10"*)
        pass "the node PR's body is the fixed template: node id, work items, coordination link" ;;
    *) fail "the node PR body: [$NBODY]" ;;
esac
LINE="- $CT_CORE | $CT_REPO:docs/plans/PLAN-t.md#50 | open | head=$SHA"
if db_body | grep -qxF -- "$LINE"; then
    pass "the node's index line carries head=<the pushed sha>"
else
    fail "the index line is missing; body: $(db_body | grep '^- ')"
fi
[ "$(printf '%s\n' "$OUT" | sed -n 's/^head=//p')" = "$SHA" ] && pass "node-push.sh prints head=<sha>" || fail "output: [$OUT]"
WANT_REC=$(jq -cnS --arg r "$CT_REPO" --arg h "$SHA" '{repo: $r, pr: 50, head: $h}')
[ "$(rec_node "$CT_CORE")" = "$WANT_REC" ] \
    && pass "the run record holds run/node/<node> {repo, pr, head=<the pushed sha>}" \
    || fail "run/node after the push: [$(rec_node "$CT_CORE")]"
ADD_AT=$(grep -n "^context add $S run/node/$CT_CORE" "$CASE/koto-calls.log" | head -1 | cut -d: -f1)
[ -n "$ADD_AT" ] && pass "the head was written through the run record's writer" || fail "no run/node write in the koto log"
# The node PR in the run's trail and its index entry, in the same call.
TRAIL_AT=$(grep -n "^context add $S trail/pr/acme.repo-a.50" "$CASE/koto-calls.log" | head -1 | cut -d: -f1)
INDEX_AT=$(grep -n "^context add pr.acme.repo-a.50 run/00112233445566778899aabbccddeeff" "$CASE/koto-calls.log" | head -1 | cut -d: -f1)
if [ "$(jq -c '{repo, number, role, state}' "$CASE/ctx/$S/trail/pr/acme.repo-a.50" 2>/dev/null)" = '{"repo":"acme/repo-a","number":50,"role":"node","state":"open"}' ] \
    && [ "$(jq -r '"\(.session) \(.mode) \(.topic)"' "$CASE/ctx/pr.acme.repo-a.50/run/00112233445566778899aabbccddeeff" 2>/dev/null)" = "$S coordinated t" ] \
    && [ "$(jq -r .workspace "$CASE/ctx/pr.acme.repo-a.50/run/00112233445566778899aabbccddeeff")" = "$(jq -r .workspace "$CASE/ctx/$S/trail/self")" ] \
    && [ -n "$TRAIL_AT" ] && [ -n "$INDEX_AT" ] && [ "$ADD_AT" -lt "$TRAIL_AT" ] && [ "$TRAIL_AT" -lt "$INDEX_AT" ]; then
    pass "the node PR is in the root's trail (role node) and its index entry names the root at its trail/self address, after run/node"
else
    fail "node trail: trail=[$(cat "$CASE/ctx/$S/trail/pr/acme.repo-a.50" 2>/dev/null)] at $ADD_AT/$TRAIL_AT/$INDEX_AT"
fi
if grep -q -- '--coordination-body' "$CASE/shirabe-calls.log" && [ "$(ct_calls | grep -c '^pr edit 10')" -eq 1 ]; then
    pass "the new body was validated, then posted with one pr edit"
else
    fail "validation or edit missing: shirabe=[$(cat "$CASE/shirabe-calls.log")]"
fi
[ "$(printf '%s\n' "$OUT" | tail -1)" = "body=posted" ] && pass "node-push.sh prints the render's body=posted last" \
    || fail "the render's line: [$OUT]"
# order_after <koto-line> -- the koto write comes before the body post.
order_after() {
    local add edit
    add=$(awk -v k="$1" '$0 == k && !n { n = NR } END { print n }' "$CASE/order.log")
    edit=$(awk '/^gh pr edit 10 / && !n { n = NR } END { print n }' "$CASE/order.log")
    [ -n "$add" ] && [ -n "$edit" ] && [ "$add" -lt "$edit" ]
}
if order_after "koto context add $S run/node/$CT_CORE"; then
    pass "a node PR opened posts a body, after the koto write of the head it shows"
else
    fail "the request log's order: $(grep -n "run/node/$CT_CORE\|pr edit 10" "$CASE/order.log")"
fi

# --- a second push: adopt, replace the line ---------------------------------------

(cd "$WT" && git commit -q --allow-empty -m "fix: more")
: > "$CASE/order.log"
push_node
SHA2=$(git -C "$WT" rev-parse HEAD)
if [ "$(printf '%s\n' "$OUT" | tail -1)" = "body=posted" ] && order_after "koto context add $S run/node/$CT_CORE"; then
    pass "a node pushed again posts a body, after the koto write of its new head"
else
    fail "the second push's post: [$OUT] $(grep -n "run/node/$CT_CORE\|pr edit 10" "$CASE/order.log")"
fi
if [ "$RC" -eq 0 ] && [ "$(ct_calls | grep -c '^pr create')" -eq 1 ]; then
    pass "a second push adopts the owned PR (no second pr create)"
else
    fail "a second push: rc=$RC creates=$(ct_calls | grep -c '^pr create')"
fi
if [ "$(db_body | grep -c "^- $CT_CORE |")" -eq 1 ] && db_body | grep -q "head=$SHA2"; then
    pass "the node's line is replaced with the new head, not duplicated"
else
    fail "index after the second push: $(db_body | grep '^- ')"
fi
[ "$(rec_node "$CT_CORE" | jq -r '"\(.pr) \(.head)"')" = "50 $SHA2" ] \
    && pass "a second push records the new head against the same PR" \
    || fail "run/node after the second push: [$(rec_node "$CT_CORE")]"

# A merged head the observer recorded survives a later push (push merges).
printf '%s' "{\"run/node/$CT_CORE\":{\"merged_head\":\"$SHA2\"}}" > "$CASE/observe.json"
bash "$SCRIPT_DIR/run-record.sh" observe --session "$S" --json "$CASE/observe.json" >/dev/null 2>&1
(cd "$WT" && git commit -q --allow-empty -m "fix: again")
push_node
SHA3=$(git -C "$WT" rev-parse HEAD)
[ "$RC" -eq 0 ] && [ "$(rec_node "$CT_CORE" | jq -r '"\(.head) \(.merged_head)"')" = "$SHA3 $SHA2" ] \
    && pass "a push keeps a recorded merged_head" || fail "merged_head after a push: [$(rec_node "$CT_CORE")]"

# --- a recorded node with nothing owned to adopt -----------------------------------

# --- the verification deferral ------------------------------------------------------
#
# A node's work items are work-on-t-<node>-<item>; one holding
# verification_deferral deferred. The koto stub's store holds each child's
# keys beside the run's session.

REASON="host is in a measurement window until 02:40Z"
REASON2="runner pool is down until Monday"
defer_child() { # defer_child <item> <reason>
    mkdir -p "$CASE/ctx/work-on-t-$CT_CORE-$1"
    printf '%s' "$2" > "$CASE/ctx/work-on-t-$CT_CORE-$1/verification_deferral"
}
remote_head() { git -C "$REPO" ls-remote origin "refs/heads/impl/t-$CT_CORE" | cut -f1; }
# part2 -- the new node PR's body after its one top-level ---.
part2() { db_pr 50 | jq -r '.body' | awk 'f; /^---[[:space:]]*$/ { f = 1 }'; }
# set_body <pr> <file> -- a person's gh pr edit of a node PR, in the model.
set_body() {
    jq --argjson n "$1" --rawfile b "$2" '(.prs[] | select(.number == $n) | .body) = $b' \
        "$GH_CALL_LOG.d/db.json" > "$CASE/db.tmp" && mv "$CASE/db.tmp" "$GH_CALL_LOG.d/db.json"
}

np_case defer-child
ct_write_db
fresh_repo defer-child
defer_child 2 "$REASON2"
push_node
P2=$(part2)
if [ "$RC" -eq 0 ] && [ "$(remote_head)" = "$(git -C "$WT" rev-parse HEAD)" ]; then
    pass "a node whose second work item deferred is pushed"
else
    fail "defer-child push: rc=$RC; $(tail -3 "$CASE/stderr")"
fi
if grep -qx '## Verification' <<<"$P2" \
    && grep -qx 'Local verification did not run: it was deferred to hosted CI.' <<<"$P2" \
    && grep -qxF "Reason: $REASON2" <<<"$P2" \
    && grep -qx 'Hosted CI is the build of record for this change.' <<<"$P2"; then
    pass "the new node PR's second part records the child's deferral in phase-6-pr.md's words"
else
    fail "the node PR's second part: [$P2]"
fi
if bash "$SCRIPT_DIR/../../work-on/scripts/check-pr-output.sh" --deferral-record --reason "$REASON2" \
        --owned --repo "$CT_REPO" --head "impl/t-$CT_CORE" --state open >/dev/null 2>"$CASE/check.err"; then
    pass "work-on's own --deferral-record check passes the body node-push.sh wrote"
else
    fail "check-pr-output.sh refused the written body: $(cat "$CASE/check.err")"
fi
[ "$(grep -c '^Reason: ' <<<"$P2")" -eq 1 ] && pass "one child's reason: one Reason: line" \
    || fail "Reason: lines: [$(grep '^Reason: ' <<<"$P2")]"

# An --issues that leaves a work item out can't hide that item's deferral:
# the node's work items in the PLAN are read too.
np_case defer-subset
ct_write_db
fresh_repo defer-subset
defer_child 2 "$REASON2"
push_node_issues() { # push_node_issues <issues>
    OUT=$(cd "$WT" && bash "$PUSH" node --session "$S" --slug t --node "$CT_CORE" --repo "$CT_REPO" --issues "$1" \
        --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" 2>"$CASE/stderr")
    RC=$?
}
push_node_issues 1
if [ "$RC" -eq 0 ] && part2 | grep -qxF "Reason: $REASON2"; then
    pass "--issues 1 on a node whose PLAN items are 1,2: item 2's deferral is still recorded"
else
    fail "defer-subset: rc=$RC part2=[$(part2)]"
fi

np_case defer-run
ct_write_db
fresh_repo defer-run
defer_child 1 "$REASON"
defer_child 2 "$REASON2"
push_node --verification hosted-ci --reason "$REASON"
P2=$(part2)
if [ "$RC" -eq 0 ] && [ "$(grep '^Reason: ' <<<"$P2")" = "$(printf 'Reason: %s\nReason: %s' "$REASON" "$REASON2")" ]; then
    pass "the run's reason and a second child's: one Reason: line each, the shared one once"
else
    fail "defer-run: rc=$RC part2=[$P2]"
fi

np_case defer-run-only
ct_write_db
fresh_repo defer-run-only
push_node --verification hosted-ci --reason "$REASON"
if [ "$RC" -eq 0 ] && part2 | grep -qxF "Reason: $REASON"; then
    pass "the run deferred and no child session holds the key: the run's reason is recorded"
else
    fail "defer-run-only: rc=$RC part2=[$(part2)]"
fi

np_case defer-none
ct_write_db
fresh_repo defer-none
push_node --verification local --reason ""
NBODY=$(db_pr 50 | jq -r '.body')
if [ "$RC" -eq 0 ] && ! grep -qi 'verification' <<<"$NBODY"; then
    pass "a node with no deferral: the body carries no Verification section"
else
    fail "defer-none: rc=$RC body=[$(db_pr 50 | jq -r '.body')]"
fi
if ct_calls | grep -Eq '^pr view .*--json body$'; then
    fail "a node with no deferral read a node PR's body: $(ct_calls | grep -E '^pr view .*--json body$')"
else
    pass "a node with no deferral makes no deferral-record body read"
fi

# The hold: a node PR already open (pushed before its second work item
# deferred) gets no push until its body records the deferral.
np_case defer-adopt
ct_write_db
fresh_repo defer-adopt
push_node
FIRST=$(remote_head)
defer_child 2 "$REASON2"
(cd "$WT" && git commit -q --allow-empty -m "feat: second item")
: > "$GH_CALL_LOG"
push_node
if [ "$RC" -eq 80 ] && [ "$(remote_head)" = "$FIRST" ] \
    && ! ct_calls | grep -Eq '^pr (create|edit|ready|merge)' \
    && [ "$(rec_node "$CT_CORE" | jq -r .head)" = "$FIRST" ]; then
    pass "an open node PR whose body lacks a child's deferral: exit 80, nothing pushed, written or recorded"
else
    fail "defer-adopt hold: rc=$RC remote=[$(remote_head)] first=[$FIRST] calls=[$(ct_calls | grep '^pr ')]"
fi
grep -q 'does not say that local verification did not run' "$CASE/stderr" \
    && grep -qF "exactly: Reason: $REASON2" "$CASE/stderr" \
    && pass "the hold names each part the body misses" || fail "hold stderr: [$(cat "$CASE/stderr")]"
db_pr 50 | jq -r '.body' > "$CASE/body.md"
printf '\n## Verification\n\nLocal verification did not run: it was deferred to hosted CI.\nReason: %s\nHosted CI is the build of record for this change.\n' \
    "$REASON2" >> "$CASE/body.md"
set_body 50 "$CASE/body.md"
push_node
if [ "$RC" -eq 0 ] && [ "$(remote_head)" = "$(git -C "$WT" rev-parse HEAD)" ]; then
    pass "once the body records it, the same push goes through"
else
    fail "defer-adopt after the record: rc=$RC; $(tail -3 "$CASE/stderr")"
fi

# Under omit the work items' keys are the record: a new node PR's body
# carries no Verification section, and an open one is never held for it.
CT_CONTENT=omit np_case defer-omit
ct_write_db
fresh_repo defer-omit
defer_child 2 "$REASON2"
push_node
OMIT_BODY=$(db_pr 50 | jq -r '.body')
if [ "$RC" -eq 0 ] && ! grep -q -e '## Verification' -e '^Reason:' <<<"$OMIT_BODY"; then
    pass "omit: a deferral leaves no Verification section in the new node PR's body"
else
    fail "defer-omit: rc=$RC body=[$(db_pr 50 | jq -r '.body')]"
fi
(cd "$WT" && git commit -q --allow-empty -m "feat: second item")
push_node
if [ "$RC" -eq 0 ]; then
    pass "omit: an open node PR is not held for a deferral its body doesn't record"
else
    fail "defer-omit second push: rc=$RC; $(tail -3 "$CASE/stderr")"
fi

np_case defer-unreadable
ct_write_db
fresh_repo defer-unreadable
push_node --verification hosted-ci --reason ""
if [ "$RC" -eq 72 ] && [ -z "$(remote_head)" ] && ! ct_calls | grep -q '^pr create'; then
    pass "hosted-ci with no reason can't be read: exit 72, nothing pushed"
else
    fail "defer-unreadable: rc=$RC remote=[$(remote_head)]"
fi
defer_child 1 "$REASON"
export KOTO_FAIL_EXISTS=verification_deferral
push_node
if [ "$RC" -eq 72 ] && [ -z "$(remote_head)" ]; then
    pass "a child's key read that fails: exit 72, nothing pushed"
else
    fail "defer-unreadable koto: rc=$RC"
fi
unset KOTO_FAIL_EXISTS
(cd "$WT" && bash "$PUSH" node --session "$S" --slug t --node "$CT_CORE" --repo "$CT_REPO" --issues 1 \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" --verification sometimes >/dev/null 2>&1); rc=$?
[ "$rc" -eq 64 ] && pass "--verification outside local and hosted-ci: 64" || fail "--verification sometimes: rc=$rc"
(cd "$WT" && bash "$PUSH" order --session "$S" --slug t --home-repo "$CT_REPO" --coord-branch "$CT_CB" \
    --verification hosted-ci >/dev/null 2>&1); rc=$?
[ "$rc" -eq 64 ] && pass "--verification in the order mode: 64" || fail "order --verification: rc=$rc"

np_case adopt-missing
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'author="someone-else"'
ct_write_db
fresh_repo adopt-missing
push_node
if [ "$RC" -eq 73 ] && ! ct_calls | grep -q '^pr create' && ! ct_calls | grep -q '^pr edit'; then
    pass "a recorded node whose PR is not owned exits 73 with no pr create or edit"
else
    fail "adopt-missing: rc=$RC"
fi

np_case adopt-other
ct_record_node "$CT_CORE" "$CT_REPO" 12 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
fresh_repo adopt-other
push_node
if [ "$RC" -eq 73 ] && ! ct_calls | grep -q '^pr edit' && [ "$(rec_node "$CT_CORE" | jq -r .pr)" = 12 ]; then
    pass "a record naming a PR other than the owned one exits 73, the record unchanged"
else
    fail "adopt-other: rc=$RC record=[$(rec_node "$CT_CORE")]"
fi

np_case index-only
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
fresh_repo index-only
push_node
[ "$RC" -eq 0 ] && [ "$(rec_node "$CT_CORE" | jq -r .pr)" = 11 ] \
    && pass "adoption reads the run record, not the body: the owned PR is adopted and recorded" \
    || fail "index-only: rc=$RC record=[$(rec_node "$CT_CORE")]"

# --- a push or a record write that fails ----------------------------------------------

np_case push-rejected
ct_write_db
fresh_repo push-rejected
printf '#!/bin/sh\nexit 1\n' > "$REPO.origin.git/hooks/pre-receive"
chmod +x "$REPO.origin.git/hooks/pre-receive"
push_node
if [ "$RC" -eq 68 ] && [ -z "$(rec_node "$CT_CORE")" ] && ! ct_calls | grep -Eq '^pr (create|edit)'; then
    pass "a push the remote rejects exits 68 and records no head"
else
    fail "push-rejected: rc=$RC record=[$(rec_node "$CT_CORE")]"
fi

np_case edit-fails
ct_write_db
fresh_repo edit-fails
GH_SHIM_FAIL='^pr edit 10 ' push_node
ESHA=$(git -C "$WT" rev-parse HEAD)
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | tail -1)" = "body=stale" ] \
    && [ "$(rec_node "$CT_CORE" | jq -r .head)" = "$ESHA" ]; then
    pass "a body post that fails reports body=stale (exit 0) and leaves the pushed head recorded"
else
    fail "edit-fails: rc=$RC out=[$OUT] record=[$(rec_node "$CT_CORE")]"
fi
(cd "$WT" && git commit -q --allow-empty -m "fix: after the failed post")
push_node
[ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | tail -1)" = "body=posted" ] \
    && pass "the next push posts the body" || fail "after a failed post: rc=$RC out=[$OUT]"

np_case record-fails
ct_write_db
fresh_repo record-fails
export KOTO_FAIL_ADD="run/node/$CT_CORE"
push_node
unset KOTO_FAIL_ADD
if [ "$RC" -eq 70 ] && ! ct_calls | grep -q '^pr edit'; then
    pass "a run record write that fails exits 70 and posts nothing"
else
    fail "record-fails: rc=$RC edits=$(ct_calls | grep -c '^pr edit')"
fi

# The node PR's index entry is written in the same call: a failed index write
# is exit 70 naming the PR, never a silent success, and nothing is posted.
np_case index-fails
ct_write_db
fresh_repo index-fails
export KOTO_FAIL_ADD="run/00112233445566778899aabbccddeeff"
push_node
unset KOTO_FAIL_ADD
if [ "$RC" -eq 70 ] && grep -q "index entry of the node PR https://github.com/acme/repo-a/pull/50" "$CASE/stderr" \
    && ! ct_calls | grep -q '^pr edit'; then
    pass "a failed index write exits 70 naming the node PR, and posts nothing"
else
    fail "index-fails: rc=$RC stderr=[$(tail -2 "$CASE/stderr" | tr '\n' ' ')]"
fi
np_case self-missing
ct_write_db
fresh_repo self-missing
rm -f "$CASE/ctx/$S/trail/self"
push_node
if [ "$RC" -eq 70 ] && [ ! -e "$CASE/ctx/$S/trail/self" ] && grep -q "pull/50" "$CASE/stderr"; then
    pass "a root with no trail/self: the index is refused (70), and no address is written from the node's worktree"
else
    fail "self-missing: rc=$RC self=[$(cat "$CASE/ctx/$S/trail/self" 2>/dev/null)]"
fi

# --- a failing validation -----------------------------------------------------------

np_case body-invalid
ct_write_db
fresh_repo body-invalid
BEFORE=$(jq -r '.prs[] | select(.number == 10) | .body' "$CASE/scenario/gh/db.json")
export CT_BODY_FAIL=1
push_node
unset CT_BODY_FAIL
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | tail -1)" = "body=stale" ] && ! ct_calls | grep -q '^pr edit' \
    && [ "$(db_body)" = "$BEFORE" ] && [ -n "$(rec_node "$CT_CORE")" ]; then
    pass "a failing --coordination-body validation is body=stale: no edit, the posted body untouched, the head recorded"
else
    fail "body-invalid: rc=$RC out=[$OUT] edits=$(ct_calls | grep -c '^pr edit')"
fi

# --- no coordination PR -------------------------------------------------------------

ct_case no-coord
ct_write_db
fresh_repo no-coord
push_node
[ "$RC" -eq 73 ] && [ -z "$(git -C "$REPO" ls-remote origin "refs/heads/impl/*")" ] \
    && pass "a session with no run record (no coordination PR recorded) exits 73, nothing pushed" || fail "no-coord: rc=$RC"

np_case coord-closed
CT_COORD_STATE=CLOSED
ct_write_db
fresh_repo coord-closed
push_node
[ "$RC" -eq 73 ] && pass "a recorded coordination PR that is not open exits 73" || fail "coord-closed: rc=$RC"

# --- the run's index entry, and the record reference ------------------------------------

MINE=00112233445566778899aabbccddeeff
OTHER=fedcba9876543210fedcba9876543210
REFLINE="Run record: execute-t (run $MINE)"
NO_RUN='shirabe''-run|^(topic|exit|outcome|intent|mode|store|run)=|^## PR Index|^## Merge Order|^Run record:|execute-t|00112233445566778899aabbccddeeff|^record:|unpinned'

np_case index-fresh
ct_write_db
fresh_repo index-fresh
push_node --run-id "$MINE"
NBODY=$(db_pr 50 | jq -r '.body')
if [ "$RC" -eq 0 ] && [ "$(grep -c '^Run record:' <<<"$NBODY")" -eq 1 ] && grep -qxF "$REFLINE" <<<"$NBODY" \
    && ! grep -q 'shirabe''-run' <<<"$NBODY" && grep -q "Work items: 1,2" <<<"$NBODY"; then
    pass "include: the node PR it opens carries one Run record line, and no marker"
else
    fail "index-fresh: rc=$RC body [$NBODY]"
fi
if [ -f "$CASE/ctx/pr.acme.repo-a.50/run/$MINE" ]; then
    pass "the node PR is this run's by its index entry"
else
    fail "index-fresh: no index entry for the node PR"
fi
if [ "$(ct_calls | grep -c '^pr create')" -eq 1 ]; then
    (cd "$WT" && git commit -q --allow-empty -m "fix: more")
    push_node --run-id "$MINE"
    if [ "$RC" -eq 0 ] && [ "$(ct_calls | grep -c '^pr create')" -eq 1 ]; then
        pass "--run-id: a second push by the same run adopts the PR its index entry names"
    else
        fail "index second push: rc=$RC creates=$(ct_calls | grep -c '^pr create')"
    fi
fi

CT_CONTENT=omit np_case index-omit
ct_write_db
fresh_repo index-omit
push_node --run-id "$MINE"
NBODY=$(db_pr 50 | jq -r '.body')
if [ "$RC" -eq 0 ] && grep -q "Work items: 1,2" <<<"$NBODY" && ! grep -Eq "$NO_RUN" <<<"$NBODY"; then
    pass "omit: the node PR it opens carries nothing of the run"
else
    fail "index-omit: rc=$RC body [$NBODY]"
fi

np_case index-foreign
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE"
ct_write_db
mkdir -p "$SHIRABE_RUN_RECORD_TEST_ROOT/acme" "$CASE/ctx/pr.acme.repo-a.11/run"
printf '{"workspace":"/w","session":"execute-t","session_id":"sid-9","mode":"coordinated","topic":"t","written_at":"2020-01-01T00:00:00Z"}' \
    > "$CASE/ctx/pr.acme.repo-a.11/run/$OTHER"
fresh_repo index-foreign
push_node --run-id "$MINE"
if [ "$RC" -eq 73 ] && ! ct_calls | grep -q '^pr create' && ! ct_calls | grep -q '^pr edit'; then
    pass "--run-id: a PR another run recorded on the node branch is not adopted (73), nothing created or edited"
else
    fail "index-foreign: rc=$RC creates=$(ct_calls | grep -c '^pr create')"
fi
if [ -z "$(git -C "$REPO" ls-remote origin "refs/heads/impl/t-$CT_CORE")" ]; then
    pass "--run-id: nothing is pushed onto a branch whose PR another run recorded"
else
    fail "index-foreign: the node branch was pushed onto another run's PR"
fi

np_case marker-dropped
ct_write_db
# An older coordination body carries a marker line after its merge-order
# block; the render keeps nothing of it.
jq --arg m "<!-- shirabe""-run: $MINE -->" '(.prs[] | select(.number == 10) | .body) += "\n" + $m + "\n"' \
    "$CASE/scenario/gh/db.json" > "$CASE/db.tmp" && mv "$CASE/db.tmp" "$CASE/scenario/gh/db.json"
fresh_repo marker-dropped
push_node --run-id "$MINE"
if [ "$RC" -eq 0 ] && ! db_body | grep -q 'shirabe''-run' \
    && db_body | grep -q "^- $CT_CORE | .*head="; then
    pass "the coordination PR's render drops an older body's marker line"
else
    fail "marker-dropped: rc=$RC; body [$(db_body)]"
fi

np_case runid-usage
ct_write_db
fresh_repo runid-usage
push_node --run-id NOTANID
[ "$RC" -eq 64 ] && pass "a malformed --run-id is a usage error" || fail "bad --run-id: rc=$RC"

# --- the node PR's title and body -------------------------------------------------------
#
# A new node PR's body is two parts: the work items' goals from the PLAN, one
# top-level `---`, then the fixed fields (and, under include, the one Run
# record line). It is checked
# with `shirabe validate --pr-body` and the title before `gh pr create`.

# separators <file> -- the count of bare `---` lines outside fences.
separators() { awk '/^[[:space:]]*(```|~~~)/ { f = !f; next } !f && /^---[[:space:]]*$/ { n++ } END { print n + 0 }' "$1"; }
# part1 <file> -- the text above the first `---`.
part1() { awk '/^---[[:space:]]*$/ { exit } { print }' "$1"; }
created_title() { ct_calls | grep '^pr create' | tail -1 | sed -n 's/.*--title \(.*\) --body-file.*/\1/p'; }

np_case pr-body
ct_write_db
fresh_repo pr-body
# Summary rows under the two items' entity rows, as an issue-carrying PLAN
# writes them; plan-to-tasks.sh reads past them.
awk '{ print }
     index($0, "| [#1: ") == 1 { print "| _Parse the input into tokens._ | | |" }
     index($0, "| [#2: ") == 1 { print "| _Cover the parser with table tests._ | | |" }' "$PLAN" > "$PLAN.new" \
    && mv "$PLAN.new" "$PLAN"
push_node --run-id "$MINE"
db_pr 50 | jq -r '.body' > "$CASE/node-body.md"
if [ "$RC" -eq 0 ] && [ "$(separators "$CASE/node-body.md")" -eq 1 ] \
    && [ "$(part1 "$CASE/node-body.md" | grep -c .)" -eq 2 ] \
    && [ "$(part1 "$CASE/node-body.md" | sed -n 1p)" = "Parse the input into tokens." ] \
    && part1 "$CASE/node-body.md" | grep -qxF "Cover the parser with table tests."; then
    pass "the node PR body's first part is each work item's goal from the PLAN, above one top-level ---"
else
    fail "pr-body: rc=$RC body [$(cat "$CASE/node-body.md")] $(tail -2 "$CASE/stderr")"
fi
case "$(awk '/^---[[:space:]]*$/ { s = 1; next } s' "$CASE/node-body.md")" in
    *"Coordinated node \`$CT_CORE\` of \`t\`."*"Work items: 1,2"*"Coordination PR: https://github.com/acme/repo-a/pull/10"*)
        pass "the fixed fields sit below the separator" ;;
    *) fail "the second part: [$(cat "$CASE/node-body.md")]" ;;
esac
if [ "$(grep -v '^[[:space:]]*$' "$CASE/node-body.md" | tail -1)" = "$REFLINE" ] \
    && ! grep -q 'shirabe''-run' "$CASE/node-body.md"; then
    pass "include: the Run record line is the body's last line, and there is no marker"
else
    fail "the record line: [$(cat "$CASE/node-body.md")]"
fi
OWNED=$(bash "$SCRIPT_DIR/owned-pr.sh" --repo "$CT_REPO" --head "impl/t-$CT_CORE" --state open --run-id "$MINE" 2>"$CASE/owned.err"); ORC=$?
if [ "$ORC" -eq 0 ] && [ "$OWNED" = "https://github.com/$CT_REPO/pull/50" ]; then
    pass "owned-pr.sh --run-id finds the node PR by its index entry"
else
    fail "the ownership lookup: rc=$ORC out=[$OWNED] $(cat "$CASE/owned.err")"
fi
OWNED=$(bash "$SCRIPT_DIR/owned-pr.sh" --repo "$CT_REPO" --head "impl/t-$CT_CORE" --state open --run-id "$OTHER" 2>/dev/null); ORC=$?
[ "$ORC" -eq 5 ] && pass "another run's lookup refuses the node PR (5): its index entry names this run" \
    || fail "another run's lookup: rc=$ORC out=[$OWNED]"
TITLE=$(created_title)
if [ "$TITLE" = "feat(t): $CT_CORE" ] \
    && grep -Eq -- "^validate --pr-body [^ ]+/node-body\.md --pr-title feat\(t\): $CT_CORE\$" "$CASE/shirabe-calls.log"; then
    pass "a code node is titled feat(t): <node-id>, and the body and title were validated with --pr-body"
else
    fail "code node: title [$TITLE] shirabe [$(cat "$CASE/shirabe-calls.log")]"
fi
if [ -n "$REAL_SHIRABE" ] && [ -x "$REAL_SHIRABE" ] \
    && "$REAL_SHIRABE" validate --help 2>/dev/null | grep -q -- '--pr-body'; then
    if "$REAL_SHIRABE" validate --pr-body "$CASE/node-body.md" --pr-title "$TITLE" >"$CASE/real.out" 2>&1; then
        pass "the real shirabe validate --pr-body passes the rendered node PR body and title"
    else
        fail "the real validator refused the node PR body: $(cat "$CASE/real.out")"
    fi
else
    echo "SKIP: no shirabe with --pr-body on PATH; the real-validator check did not run"
fi

# An outline's **Goal**: (here read past the table path, which ignores the
# section; the outline path reaches the same reader), spanning two lines.
np_case pr-body-outline
ct_write_db
fresh_repo pr-body-outline
cat >> "$PLAN" <<'OUTLINES'

## Issue Outlines

### Issue 1: feat parser

**Goal**: Read the input
into tokens.

**Acceptance Criteria**:
- [ ] tokens

### Issue 2: test parser

**Goal**: Test the tokens.
OUTLINES
OUT=$(cd "$WT" && bash "$PUSH" node --session "$S" --slug t --node "$CT_CORE" --repo "$CT_REPO" --issues 2,1 \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" 2>"$CASE/stderr"); RC=$?
db_pr 50 | jq -r '.body' > "$CASE/node-body.md"
if [ "$RC" -eq 0 ] && [ "$(part1 "$CASE/node-body.md" | grep -v '^$' | tr '\n' '|')" = "Test the tokens.|Read the input into tokens.|" ]; then
    pass "an outline's Goal, joined onto one line, is the item's paragraph, in --issues order"
else
    fail "pr-body-outline: rc=$RC body [$(cat "$CASE/node-body.md")] $(tail -2 "$CASE/stderr")"
fi

# No goal and no summary: the items' titles, still above one separator.
np_case pr-body-titles
ct_write_db
fresh_repo pr-body-titles
push_node
db_pr 50 | jq -r '.body' > "$CASE/node-body.md"
if [ "$RC" -eq 0 ] && [ "$(separators "$CASE/node-body.md")" -eq 1 ] \
    && part1 "$CASE/node-body.md" | grep -qxF "Work item 1: feat parser." \
    && part1 "$CASE/node-body.md" | grep -qxF "Work item 2: test parser."; then
    pass "items with no goal or summary are described by their titles"
else
    fail "pr-body-titles: rc=$RC body [$(cat "$CASE/node-body.md")]"
fi

# docs_node <case> <path>... -- a fresh repo whose node commit changes only
# the given paths (the default work.txt commit is dropped), then a push.
docs_node() {
    local c="$1" p
    shift
    np_case "$c"
    ct_write_db
    fresh_repo "$c"
    (cd "$WT" && git reset -q --hard HEAD~1)
    for p in "$@"; do
        (cd "$WT" && mkdir -p "$(dirname "$p")" && echo text > "$p" && git add "$p")
    done
    (cd "$WT" && git commit -q -m "docs: add")
    push_node
}

docs_node docs-only docs/decisions/DECISION-x.md README.md
if [ "$RC" -eq 0 ] && [ "$(created_title)" = "docs(t): $CT_CORE" ]; then
    pass "a node that changes only docs/ and root Markdown is titled docs(t): <node-id>"
else
    fail "docs-only: rc=$RC title [$(created_title)] $(tail -2 "$CASE/stderr")"
fi
docs_node docs-skill docs/decisions/DECISION-x.md skills/x/SKILL.md
if [ "$RC" -eq 0 ] && [ "$(created_title)" = "feat(t): $CT_CORE" ]; then
    pass "Markdown outside docs/ and the root (a skill) keeps the node feat"
else
    fail "docs-skill: rc=$RC title [$(created_title)]"
fi

# A refused body or title: no PR is created, and the coordination PR is
# untouched.
np_case pr-body-invalid
ct_write_db
fresh_repo pr-body-invalid
BEFORE=$(jq -r '.prs[] | select(.number == 10) | .body' "$CASE/scenario/gh/db.json")
export CT_PR_BODY_FAIL=1
push_node
unset CT_PR_BODY_FAIL
if [ "$RC" -eq 74 ] && ! ct_calls | grep -q '^pr create' && ! ct_calls | grep -q '^pr edit' \
    && [ "$(db_body)" = "$BEFORE" ] && grep -q -- '--pr-body' "$CASE/stderr"; then
    pass "a failing --pr-body validation exits 74 before gh pr create, with no edit"
else
    fail "pr-body-invalid: rc=$RC calls [$(ct_calls | grep '^pr ')] $(tail -2 "$CASE/stderr")"
fi

# --- the merge order ------------------------------------------------------------------
#
# The gated PLAN: pr-repo-a-core, then the gate publish-core, then pr-repo-a-cli,
# which waits on both. The seeded body's block lists two nodes with a merge
# state; the push must replace it whole.

ct_case merge-order
CT_RECORD_REPOS="acme/repo-a,acme/repo-b"
fresh_repo merge-order gated
ct_record_setup github 10 "$(ct_nodes_of "$PLAN")"
ct_write_db
push_node
# The expected section is a golden file the Rust validator's tests also read
# and check with the real parser (this suite runs against a shirabe stub), so a
# render that stops putting the node id first on each line fails a test.
WANT=$(cat "$SCRIPT_DIR/testdata/merge-order-gated.txt")
GOT=$(merge_order_section)
if [ "$RC" -eq 0 ] && [ "$GOT" = "$WANT" ]; then
    pass "the merge-order section is the rendered block: both PR nodes and the gate, each after its predecessors"
else
    fail "the merge-order section after a push (rc=$RC):"
    printf '%s\n' "$GOT"
    tail -3 "$CASE/stderr"
fi
if [ "$(db_body | grep -c '^```merge-order')" -eq 1 ] && ! db_body | grep -q '| open$'; then
    pass "the body holds one merge-order block, and the seeded lines with a merge state are gone"
else
    fail "the body after the push: $(db_body)"
fi
if db_body | grep -qxF -- "- $CT_CORE | $CT_REPO:docs/plans/PLAN-t.md#50 | open | head=$(git -C "$WT" rev-parse HEAD)"; then
    pass "the index line is still written alongside the merge order"
else
    fail "the index after the merge-order push: $(db_body | grep '^- ')"
fi

# A second push renders the same section.
(cd "$WT" && git commit -q --allow-empty -m "fix: again")
push_node
[ "$RC" -eq 0 ] && [ "$(merge_order_section)" = "$WANT" ] \
    && pass "a second push renders the same merge-order section" \
    || fail "the section after a second push (rc=$RC): $(merge_order_section)"

# The block follows the node list run/setup sealed, not the PLAN: a PLAN
# edited after setup (the gate dropped) leaves it as it was, and so does the
# PLAN's deletion (order mode reads no PLAN).
grep -v '_Gate:' "$PLAN" > "$PLAN.new" && mv "$PLAN.new" "$PLAN"
(cd "$WT" && git commit -q --allow-empty -m "fix: once more")
push_node
if [ "$RC" -eq 0 ] && [ "$(merge_order_section)" = "$WANT" ]; then
    pass "the block follows run/setup's waits_on, not a PLAN edited since"
else
    fail "the section after the PLAN changed (rc=$RC): $(merge_order_section)"
fi
rm -f "$PLAN"
gh shim-mark-merged "$CT_REPO" 50
OUT=$(cd "$REPO" && bash "$PUSH" order --session "$S" --slug t --home-repo "$CT_REPO" --coord-branch "$CT_CB" 2>"$CASE/stderr"); RC=$?
if [ "$RC" -eq 0 ] && [ "$(merge_order_section)" = "$WANT" ] && db_body | grep -q "^- $CT_CORE | .* | merged | "; then
    pass "the block survives the PLAN's deletion (and the merge shows in the index)"
else
    fail "after the PLAN's deletion (rc=$RC, out=[$OUT]): $(merge_order_section)"
fi

# --- a PLAN with no such node -----------------------------------------------------------

np_case plan-no-node
ct_write_db
fresh_repo plan-no-node two-repo
push_node
if [ "$RC" -eq 76 ] && [ -z "$(git -C "$REPO" ls-remote origin "refs/heads/impl/*")" ] \
    && ! ct_calls | grep -Eq '^pr (create|edit)'; then
    pass "a PLAN with no node named --node exits 76 before the push, with no gh write"
else
    fail "plan-no-node: rc=$RC; $(tail -3 "$CASE/stderr")"
fi
echo "not a plan" > "$PLAN"
push_node
if [ "$RC" -eq 76 ] && [ -z "$(git -C "$REPO" ls-remote origin "refs/heads/impl/*")" ]; then
    pass "a PLAN plan-to-tasks.sh can't read exits 76 before the push"
else
    fail "unreadable PLAN: rc=$RC"
fi

# --- order mode -------------------------------------------------------------------------
#
# Run in the coordination checkout before the cascade: renders the block from
# the PLAN and edits the body, with no push and no index line.

ct_case order
CT_RECORD_REPOS="acme/repo-a,acme/repo-b"
fresh_repo order gated
ct_record_setup github 10 "$(ct_nodes_of "$PLAN")"
ct_write_db
order_run() { # order_run [extra args]
    OUT=$(cd "$REPO" && bash "$PUSH" order --session "$S" --slug t --home-repo "$CT_REPO" --coord-branch "$CT_CB" "$@" 2>"$CASE/stderr")
    RC=$?
}
order_run
if [ "$RC" -eq 0 ] && [ "$(merge_order_section)" = "$WANT" ] && [ "$OUT" = "pr=https://github.com/acme/repo-a/pull/10
body=posted" ]; then
    pass "order mode renders the body from run/setup and prints pr= and body="
else
    fail "order mode (rc=$RC, out=[$OUT]): $(merge_order_section); $(tail -3 "$CASE/stderr")"
fi
if [ -z "$(git -C "$REPO" ls-remote origin "refs/heads/*" | grep -v 'refs/heads/main$')" ] \
    && ! ct_calls | grep -q '^pr create' && [ "$(ct_calls | grep -c '^pr edit 10')" -eq 1 ] \
    && [ -z "$(ls "$CASE/ctx/$S/run" | grep -vx setup)" ]; then
    pass "order mode pushes nothing, creates no PR, and records nothing"
else
    fail "order mode side effects: $(ct_calls)"
fi
order_run
[ "$RC" -eq 0 ] && [ "$(merge_order_section)" = "$WANT" ] && [ "$(printf '%s\n' "$OUT" | tail -1)" = "body=unchanged" ] \
    && [ "$(ct_calls | grep -c '^pr edit 10')" -eq 1 ] \
    && pass "a second order render is unchanged and posts nothing" \
    || fail "a second order render (rc=$RC, out=[$OUT]): $(merge_order_section)"
rm -f "$PLAN"
order_run
[ "$RC" -eq 0 ] && [ "$(merge_order_section)" = "$WANT" ] \
    && pass "order mode with the PLAN deleted keeps the block" \
    || fail "order mode with no PLAN (rc=$RC): $(merge_order_section)"
for args in "--plan $CT_WORK/any-plan.md" "--node $CT_CORE" "--remote origin" "--issues 1"; do
    # shellcheck disable=SC2086
    order_run $args
    [ "$RC" -eq 64 ] && pass "order mode usage [$args] exits 64" || fail "order mode usage [$args]: rc=$RC"
done

# --- coordination mode ------------------------------------------------------------------

np_case coordination
ct_record_node "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_write_db
fresh_repo coordination
(cd "$REPO" && git rm -q docs/plans/PLAN-t.md && git commit -q -m "chore: cascade")
OUT=$(cd "$REPO" && bash "$PUSH" coordination --session "$S" --slug t --home-repo "$CT_REPO" --coord-branch "$CT_CB" 2>"$CASE/stderr"); RC=$?
CSHA=$(git -C "$REPO" rev-parse HEAD)
MERGED_AT=$(rec_node "$CT_CORE" | jq -r '.merged_head // ""')
if [ "$RC" -eq 0 ] && [ "$(git -C "$REPO" ls-remote origin "refs/heads/$CT_CB" | cut -f1)" = "$CSHA" ] \
    && [ "$(printf '%s\n' "$OUT" | tail -1)" = "body=posted" ] \
    && ! db_body | grep -q '^- coordination |' && ! db_body | grep -Eq '#10([^0-9]|$)' \
    && [ -n "$MERGED_AT" ] && db_body | grep -qxF -- "- $CT_CORE | $CT_REPO:docs/plans/PLAN-t.md#11 | merged | head=$MERGED_AT"; then
    pass "coordination mode pushes the coordination branch and renders the body with no self row"
else
    fail "coordination mode: rc=$RC out=[$OUT]; $(db_body | grep '^- '); $(tail -3 "$CASE/stderr")"
fi
ct_calls | grep -q '^pr create' && fail "coordination mode created a PR" || pass "coordination mode creates no PR"
[ "$(cat "$CASE/ctx/$S/run/cascade" 2>/dev/null)" = "{\"head\":\"$CSHA\",\"verdict\":\"pushed\"}" ] \
    && pass "coordination mode records run/cascade {verdict: pushed, head=<the pushed sha>}" \
    || fail "run/cascade after the coordination push: [$(cat "$CASE/ctx/$S/run/cascade" 2>/dev/null)]"
WANT_DEFAULT=$(printf '## Merge Order\n\n```merge-order\n%s\n%s\n%s | pr | after: -\n%s | pr | after: %s\n```' \
    "# Rendered by /execute from the node list the run sealed at setup; not read by the merge gate." \
    "# One node per line, after its predecessors: <node-id> | pr|gate | after: <node-ids>" \
    "$CT_CORE" "$CT_CLI" "$CT_CORE")
[ "$(merge_order_section)" = "$WANT_DEFAULT" ] \
    && pass "coordination mode, after the cascade deleted the PLAN, renders the merge order from run/setup" \
    || fail "coordination mode's merge-order section: $(merge_order_section)"

# --- a record naming a private repository under a public home ---------------------------
#
# The node itself lands in the public home, so the check before the push
# passes; another node's record names a private repository, which the render
# refuses after the push and the record write.

np_case vis-after-push
ct_record_node "$CT_CLI" acme/repo-b 7 "$CT_HEAD"
ct_pr acme/repo-b 7 "impl/t-$CT_CLI"
CT_VIS_B=private
ct_write_db
CT_VIS_B=public
fresh_repo vis-after-push
push_node
if [ "$RC" -eq 77 ] && [ -n "$(git -C "$REPO" ls-remote origin "refs/heads/impl/t-$CT_CORE")" ] \
    && [ -n "$(rec_node "$CT_CORE")" ] && ! ct_calls | grep -q '^pr edit 10' \
    && grep -q 'push happened' "$CASE/stderr" && ! grep -q 'acme/repo-b' "$CASE/stderr"; then
    pass "a record naming a private repository under a public home: 77 after the push and the record, nothing posted, the repository unnamed"
else
    fail "vis-after-push: rc=$RC; $(tail -3 "$CASE/stderr")"
fi

# --- each node against its own target ---------------------------------------------
#
# The home (the coordination PR's repository) is acme/repo-a and the node lands
# in acme/repo-b; the visibilities come from the shim's repository model.

# node_clone <case> -- a clone of acme/repo-b (its own bare origin) and the
# node cut there with --repo-dir, one commit on it. Sets NREPO and WT.
node_clone() {
    NREPO="$CT_WORK/$1-node"
    ct_repo "$NREPO"
    (cd "$NREPO" && git checkout -q main)
    cut_in "$NREPO" "$1"
}

# cut_in <clone> <case> -- cut the node in <clone> with --repo-dir and commit
# one file on it. Sets WT. Stops the suite when no worktree was made, so a
# failed cut can never commit into the checkout running the test.
cut_in() {
    WT=$(cd "$REPO" && bash "$CUT" t "$CT_CORE" --repo-dir "$1" 2>/dev/null | sed -n 's/^worktree=//p')
    [ -n "$WT" ] && [ -d "$WT" ] || { echo "FAIL: node-cut.sh made no worktree in $1 for case $2" >&2; exit 1; }
    (cd "$WT" && echo work > work.txt && git add work.txt && git commit -q -m "feat: work")
}

# vis_push <case> <home vis> <node vis> [line] -- a fresh node push into
# acme/repo-b, from a worktree of its own clone; with a line, one more commit
# adds it to notes.txt first. VIS_PRS, when set, is ct_pr arguments for a PR
# already on the node branch.
vis_push() {
    np_case "$1"
    CT_VIS_A="$2"
    CT_VIS_B="$3"
    [ -n "${VIS_PRS:-}" ] && ct_pr acme/repo-b 60 "impl/t-$CT_CORE" "$VIS_PRS"
    ct_write_db
    fresh_repo "$1"
    node_clone "$1"
    if [ -n "${4:-}" ]; then
        (cd "$WT" && printf '%s\n' "$4" > notes.txt && git add notes.txt && git commit -q -m "docs: notes")
    fi
    OUT=$(cd "$WT" && bash "$PUSH" node --session "$S" --slug t --node "$CT_CORE" --repo acme/repo-b --issues 1,2 \
        --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" 2>"$CASE/stderr")
    RC=$?
    NBODY=$(jq -r '.prs[] | select(.repo == "acme/repo-b") | .body' "$GH_CALL_LOG.d/db.json" 2>/dev/null)
}
pushed() { [ -n "$(git -C "$NREPO" ls-remote origin "refs/heads/impl/t-$CT_CORE")" ]; }

vis_push vis-pub-pub public public
if [ "$RC" -eq 0 ] && pushed && grep -qxF "Coordination PR: https://github.com/acme/repo-a/pull/10" <<<"$NBODY"; then
    pass "public home, public node: pushed, and the node PR links the coordination PR"
else
    fail "public over public: rc=$RC body=[$NBODY] $(tail -2 "$CASE/stderr")"
fi

vis_push vis-priv-pub private public
if [ "$RC" -eq 0 ] && pushed && grep -q "Work items: 1,2" <<<"$NBODY"; then
    pass "private home, public node: pushed, and the node PR opened"
else
    fail "private over public: rc=$RC body=[$NBODY] $(tail -2 "$CASE/stderr")"
fi
case "$NBODY" in
    *"Coordination PR"*|*"acme/repo-a"*) fail "the public node's PR points into the private home: [$NBODY]" ;;
    *) pass "the public node's PR carries no link into the private coordination PR" ;;
esac
db_body | grep -q -- "- $CT_CORE | acme/repo-b:docs/plans/PLAN-t.md#" \
    && pass "the private coordination PR indexes the public node" \
    || fail "private over public: the index line is missing"

vis_push vis-priv-priv private private
if [ "$RC" -eq 0 ] && pushed && grep -qxF "Coordination PR: https://github.com/acme/repo-a/pull/10" <<<"$NBODY"; then
    pass "private home, private node: pushed, and the node PR links the coordination PR"
else
    fail "private over private: rc=$RC body=[$NBODY] $(tail -2 "$CASE/stderr")"
fi

vis_push vis-pub-priv public private
if [ "$RC" -eq 77 ] && ! pushed; then
    pass "public home, private node: refused with 77, nothing pushed"
else
    fail "public over private: rc=$RC pushed=$(pushed && echo yes || echo no)"
fi
if ct_calls | grep -Eq '^pr (create|edit)'; then fail "the refusal wrote to GitHub"; else pass "the refusal wrote nothing to GitHub"; fi
grep -q "node $CT_CORE lands in a private repository" "$CASE/stderr" && ! grep -q repo-b "$CASE/stderr" \
    && pass "the refusal names the node, never the private repository" \
    || fail "the refusal's message: $(cat "$CASE/stderr")"

vis_push vis-unread public none
if [ "$RC" -eq 72 ] && ! pushed; then
    pass "a failed visibility read exits 72, nothing pushed"
else
    fail "a failed read: rc=$RC pushed=$(pushed && echo yes || echo no)"
fi
if ct_calls | grep -Eq '^pr (create|edit)'; then fail "a failed read wrote to GitHub"; else pass "a failed read wrote nothing to GitHub"; fi
vis_push vis-home-unread none public
[ "$RC" -eq 72 ] && ! pushed && pass "a failed read of the home's visibility exits 72, nothing pushed" \
    || fail "home unread: rc=$RC"

# The node PR's description comes from the private PLAN, so it is scanned
# with the commits: a goal naming a private/ path stops the push.
np_case vis-goal
CT_VIS_A=private
CT_VIS_B=public
ct_write_db
fresh_repo vis-goal
awk '{ print } index($0, "| [#1: ") == 1 { print "| _Mirror private/tools into the parser._ | | |" }' "$PLAN" > "$PLAN.new" \
    && mv "$PLAN.new" "$PLAN"
node_clone vis-goal
OUT=$(cd "$WT" && bash "$PUSH" node --session "$S" --slug t --node "$CT_CORE" --repo acme/repo-b --issues 1,2 \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" 2>"$CASE/stderr"); RC=$?
if [ "$RC" -eq 78 ] && ! pushed && ! ct_calls | grep -Eq '^pr (create|edit)'; then
    pass "a work item's goal naming a private/ path, public node under a private home: 78, nothing pushed"
else
    fail "vis-goal: rc=$RC pushed=$(pushed && echo yes || echo no) $(tail -1 "$CASE/stderr")"
fi

# A deferral reason the new node PR would record is published with it, so it
# is scanned too.
np_case vis-reason
CT_VIS_A=private
CT_VIS_B=public
ct_write_db
fresh_repo vis-reason
node_clone vis-reason
OUT=$(cd "$WT" && bash "$PUSH" node --session "$S" --slug t --node "$CT_CORE" --repo acme/repo-b --issues 1,2 \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" \
    --verification hosted-ci --reason "see private/plans/notes.md" 2>"$CASE/stderr"); RC=$?
if [ "$RC" -eq 78 ] && ! pushed && ! ct_calls | grep -Eq '^pr (create|edit)'; then
    pass "a deferral reason naming a private/ path, public node under a private home: 78, nothing pushed"
else
    fail "vis-reason: rc=$RC pushed=$(pushed && echo yes || echo no) $(tail -1 "$CASE/stderr")"
fi

# The visibility check runs before the ownership read, whose diagnostics name
# the node's repository: another author's PR on a private node's branch under
# a public home is still the 77 refusal, and nothing names the repository.
VIS_PRS='author="someone-else"'
vis_push vis-order public private
unset VIS_PRS
if [ "$RC" -eq 77 ] && ! grep -q "acme/repo-b" "$CASE/stderr"; then
    pass "the visibility refusal comes before the ownership read, and names no private repository"
else
    fail "check order: rc=$RC stderr=[$(cat "$CASE/stderr")]"
fi

# A public node driven from a private home: what it would publish is scanned
# for the public-content markers.
vis_push vis-scan-hit private public "see private/plans/notes.md for the rationale"
if [ "$RC" -eq 78 ] && ! pushed && grep -q "carry private-repository content" "$CASE/stderr"; then
    pass "a public node under a private home whose commits name a private/ path is refused (78), nothing pushed"
else
    fail "scan hit: rc=$RC pushed=$(pushed && echo yes || echo no) $(tail -2 "$CASE/stderr")"
fi
if ct_calls | grep -Eq '^pr (create|edit)'; then fail "the scan refusal wrote to GitHub"; else pass "the scan refusal wrote nothing to GitHub"; fi
vis_push vis-scan-decl private public "## Repo Visibility: Private"
[ "$RC" -eq 78 ] && ! pushed && pass "a Repo Visibility: Private line is refused too" || fail "scan decl: rc=$RC"
vis_push vis-scan-public-home public public "see private/plans/notes.md"
[ "$RC" -eq 0 ] && pass "the scan runs only for a public node under a private home" || fail "public home, no scan: rc=$RC"
vis_push vis-scan-priv-node private private "see private/plans/notes.md"
[ "$RC" -eq 0 ] && pass "a private node under a private home isn't scanned" || fail "private node, no scan: rc=$RC"

# --- a node pushed from the coordination checkout ---------------------------------
#
# The node lands in acme/repo-b; the coordination PR is in acme/repo-a.

# home_push -- push the node from $WT with --repo acme/repo-b.
home_push() {
    OUT=$(cd "$WT" && bash "$PUSH" node --session "$S" --slug t --node "$CT_CORE" --repo acme/repo-b --issues 1,2 \
        --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" 2>"$CASE/stderr")
    RC=$?
}
# home_has_node_branch -- the home's origin holds the node branch.
home_has_node_branch() { [ -n "$(git -C "$REPO" ls-remote origin "refs/heads/impl/t-$CT_CORE")" ]; }
gh_wrote() { ct_calls | grep -Eq '^pr (create|edit|ready|merge|close)'; }

np_case home-worktree
ct_write_db
fresh_repo home-worktree
home_push
if [ "$RC" -eq 79 ] && ! home_has_node_branch && ! gh_wrote \
    && grep -q "cut it with node-cut.sh --repo-dir" "$CASE/stderr" && ! grep -q 'acme/' "$CASE/stderr"; then
    pass "a node in another repository, cut in the coordination checkout: exit 79, nothing pushed or written, no repository named"
else
    fail "home worktree: rc=$RC pushed=$(home_has_node_branch && echo yes || echo no) stderr=[$(tail -1 "$CASE/stderr")]"
fi

np_case home-url
ct_write_db
fresh_repo home-url
NREPO="$CT_WORK/home-url-reclone"
git clone -q "$REPO.origin.git" "$NREPO"
cut_in "$NREPO" home-url
home_push
if [ "$RC" -eq 79 ] && ! home_has_node_branch && ! gh_wrote; then
    pass "a separate clone whose origin is the coordination checkout's: exit 79, nothing pushed"
else
    fail "home url: rc=$RC pushed=$(home_has_node_branch && echo yes || echo no) stderr=[$(tail -1 "$CASE/stderr")]"
fi

# The same worktree, pushing through a remote that names neither the home's
# origin nor any URL the home uses (an unrelated bare repository): the branch
# was still cut from the coordination checkout's default branch, so the git
# directory alone refuses it.
np_case home-worktree-alt-remote
ct_write_db
fresh_repo home-worktree-alt-remote
git init -q --bare "$CT_WORK/alt-remote.git"
(cd "$REPO" && git remote add alt "$CT_WORK/alt-remote.git")
OUT=$(cd "$WT" && bash "$PUSH" node --session "$S" --slug t --node "$CT_CORE" --repo acme/repo-b --issues 1,2 \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" --remote alt 2>"$CASE/stderr")
RC=$?
if [ "$RC" -eq 79 ] && [ -z "$(git ls-remote "$CT_WORK/alt-remote.git" "refs/heads/impl/*")" ]; then
    pass "a worktree of the coordination checkout pushing through another remote: exit 79, nothing pushed"
else
    fail "alt remote: rc=$RC stderr=[$(tail -1 "$CASE/stderr")]"
fi

# The home's origin spelled another way: the same repository over ssh in the
# coordination checkout, over https in the node clone.
np_case home-url-spelling
ct_write_db
fresh_repo home-url-spelling
(cd "$REPO" && git remote set-url origin git@git.invalid:Acme/repo-a.git)
NREPO="$CT_WORK/home-url-spelling-clone"
ct_repo "$NREPO"
(cd "$NREPO" && git checkout -q main)
cut_in "$NREPO" home-url-spelling
# Set after the cut, which fetches from the clone's origin.
(cd "$NREPO" && git remote set-url origin https://git.invalid/acme/repo-a/)
home_push
if [ "$RC" -eq 79 ] && ! gh_wrote; then
    pass "the home's origin over ssh and the node clone's over https: the same repository, exit 79"
else
    fail "url spelling: rc=$RC stderr=[$(tail -1 "$CASE/stderr")]"
fi

# One insteadOf rule shared by both checkouts: the coordination checkout's
# origin and the separate clone's are written gh:acme/repo-a, which both
# resolve to the home's bare origin, so the push would land there.
np_case home-insteadof
ct_write_db
fresh_repo home-insteadof
git config --global url."$REPO.origin.git".insteadOf gh:acme/repo-a
(cd "$REPO" && git remote set-url origin gh:acme/repo-a)
NREPO="$CT_WORK/home-insteadof-clone"
git clone -q "$REPO.origin.git" "$NREPO"
(cd "$NREPO" && git remote set-url origin gh:acme/repo-a)
cut_in "$NREPO" home-insteadof
home_push
if [ "$RC" -eq 79 ] && ! home_has_node_branch && ! gh_wrote; then
    pass "a clone of the home whose origin and the checkout's share an insteadOf rule: exit 79, nothing pushed"
else
    fail "insteadOf: rc=$RC pushed=$(home_has_node_branch && echo yes || echo no) stderr=[$(tail -1 "$CASE/stderr")]"
fi
git config --global --unset url."$REPO.origin.git".insteadOf

# The coordination checkout's origin with a separate pushurl (its pushes go
# to a fork): a clone of the home itself, the repository home_repo names,
# is still refused.
np_case home-pushurl
ct_write_db
fresh_repo home-pushurl
git init -q --bare "$CT_WORK/home-fork.git"
(cd "$REPO" && git config remote.origin.pushurl "$CT_WORK/home-fork.git")
NREPO="$CT_WORK/home-pushurl-clone"
git clone -q "$REPO.origin.git" "$NREPO"
cut_in "$NREPO" home-pushurl
home_push
if [ "$RC" -eq 79 ] && ! home_has_node_branch && ! gh_wrote; then
    pass "a clone of the home under a checkout whose origin pushes elsewhere: exit 79, nothing pushed"
else
    fail "pushurl: rc=$RC pushed=$(home_has_node_branch && echo yes || echo no) stderr=[$(tail -1 "$CASE/stderr")]"
fi

# The other way round: the checkout fetches from a mirror and pushes to the
# home. A clone of the home is refused on the push URL.
np_case home-mirror
ct_write_db
fresh_repo home-mirror
git clone -q --bare "$REPO.origin.git" "$CT_WORK/home-mirror.git"
(cd "$REPO" && git remote set-url origin "$CT_WORK/home-mirror.git" \
    && git config remote.origin.pushurl "$REPO.origin.git")
NREPO="$CT_WORK/home-mirror-clone"
git clone -q "$REPO.origin.git" "$NREPO"
cut_in "$NREPO" home-mirror
home_push
if [ "$RC" -eq 79 ] && [ -z "$(git ls-remote "$REPO.origin.git" "refs/heads/impl/*")" ] && ! gh_wrote; then
    pass "a clone of the home under a checkout that fetches from a mirror and pushes to the home: exit 79, nothing pushed"
else
    fail "mirror: rc=$RC stderr=[$(tail -1 "$CASE/stderr")]"
fi

# A --plan outside any git repository: the coordination checkout can't be
# read, which refuses rather than passing.
np_case plan-outside-git
ct_write_db
fresh_repo plan-outside-git
node_clone plan-outside-git
mkdir -p "$CT_WORK/no-git/docs/plans"
cp "$PLAN" "$CT_WORK/no-git/docs/plans/PLAN-t.md"
PLAN="$CT_WORK/no-git/docs/plans/PLAN-t.md"
home_push
if [ "$RC" -eq 79 ] && [ -z "$(git -C "$NREPO" ls-remote origin "refs/heads/impl/t-$CT_CORE")" ] \
    && grep -q "could not read the git directories" "$CASE/stderr"; then
    pass "a --plan outside any git repository: exit 79, nothing pushed"
else
    fail "plan outside git: rc=$RC stderr=[$(tail -1 "$CASE/stderr")]"
fi

# coord_url_key: one key for the spellings of one repository, and a local
# path left as it is.
url_keys=$(
    PROG=t COORD_SELF_DIR="$SCRIPT_DIR"
    . "$SCRIPT_DIR/coord-common.sh"
    for u in https://github.com/Acme/Repo-A.git https://github.com/acme/repo-a/ git@github.com:acme/repo-a.git \
             ssh://git@github.com:22/acme/repo-a https://github.com/acme/repo-b /tmp/x.origin.git; do
        printf '%s\n' "$(coord_url_key "$u")"
    done
)
want_keys='github.com/acme/repo-a
github.com/acme/repo-a
github.com/acme/repo-a
github.com/acme/repo-a
github.com/acme/repo-b
/tmp/x.origin.git'
[ "$url_keys" = "$want_keys" ] && pass "coord_url_key: https, ssh and scp forms of one repository share a key; a path is kept" \
    || fail "coord_url_key: [$url_keys]"

np_case own-clone
ct_write_db
fresh_repo own-clone
node_clone own-clone
home_push
if [ "$RC" -eq 0 ] && [ -n "$(git -C "$NREPO" ls-remote origin "refs/heads/impl/t-$CT_CORE")" ] && ! home_has_node_branch; then
    pass "the node's own clone (control): pushed to acme/repo-b's origin, never the home's"
else
    fail "own clone: rc=$RC stderr=[$(tail -1 "$CASE/stderr")]"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

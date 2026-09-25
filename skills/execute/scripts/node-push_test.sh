#!/usr/bin/env bash
# node-push_test.sh — a node's push, its draft PR, and its head= record
# Part of the execute skill
#
# node-push.sh is the one writer of `head=` fields on the coordination PR's
# index. Each case runs it in a real git worktree (node-cut.sh) whose origin is
# a local bare repository, against the eval gh shim's repository model and a
# shirabe stub (see coord-test-helpers.sh).
#
# Cases:
#   usage errors                                 exit 64, no push, no gh write
#   a detached HEAD, the wrong branch, the default branch   65, 66, 67
#   a fresh node push                            the branch reaches origin; one
#     draft PR titled feat(<slug>): <node-id> with the fixed body (node id,
#     work items, coordination link) through --body-file; the node's index
#     line written with head=<the pushed sha>, after --coordination-body
#     validation of the new body
#   a wip/ file committed on the node branch     swept: the pushed head carries
#                                                no wip/ file
#   a second push                                the owned PR is adopted (no
#     second pr create) and the node's line is replaced, not duplicated
#   an indexed node with no owned PR to adopt    exit 73, no pr create
#   a failing body validation                    exit 74, no pr edit, the posted
#                                                body unchanged
#   no coordination PR                           exit 73
#   coordination mode                            pushes the coordination branch
#     and records the coordination PR's own line with head=
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

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

# The push itself, read from the script: the explicit refspec, never a force.
PUSH_LINES=$(grep -v '^[[:space:]]*#' "$PUSH" | grep 'git push')
if [ "$(printf '%s\n' "$PUSH_LINES" | grep -c .)" -eq 1 ] \
    && printf '%s' "$PUSH_LINES" | grep -qF 'git push "$REMOTE" "HEAD:refs/heads/$BRANCH"' \
    && ! printf '%s' "$PUSH_LINES" | grep -Eq -- '--force|-f( |$)|\+HEAD'; then
    pass "the one push is git push <remote> HEAD:refs/heads/<branch>, never forced"
else
    fail "the push lines are: $PUSH_LINES"
fi

# fresh_repo <case> -- a coordination checkout and a cut node worktree. Sets
# REPO and WT.
fresh_repo() {
    REPO="$CT_WORK/$1-repo"
    ct_repo "$REPO"
    ct_plan "$REPO"
    (cd "$REPO" && git add docs && git commit -q -m "docs: plan")
    WT=$(cd "$REPO" && bash "$CUT" t "$CT_CORE" 2>/dev/null | sed -n 's/^worktree=//p')
    (cd "$WT" && echo work > work.txt && git add work.txt && git commit -q -m "feat: work")
}

push_node() { # push_node [extra args]
    OUT=$(cd "$WT" && bash "$PUSH" node --slug t --node "$CT_CORE" --repo "$CT_REPO" --issues 1,2 \
        --home-repo "$CT_REPO" --coord-branch "$CT_CB" "$@" 2>"$CASE/stderr")
    RC=$?
}

db_body() { jq -r '.prs[] | select(.number == 10) | .body' "$GH_CALL_LOG.d/db.json"; }
db_pr() { jq -c --argjson n "$1" '.prs[] | select(.number == $n)' "$GH_CALL_LOG.d/db.json"; }

# --- usage ------------------------------------------------------------------------

ct_case usage
ct_write_db
fresh_repo usage
for args in "" "branch --slug t" "node --slug T --node $CT_CORE --repo $CT_REPO --issues 1 --home-repo $CT_REPO --coord-branch $CT_CB" \
            "node --slug t --node coordination --repo $CT_REPO --issues 1 --home-repo $CT_REPO --coord-branch $CT_CB" \
            "node --slug t --node $CT_CORE --repo $CT_REPO --issues '#1' --home-repo $CT_REPO --coord-branch $CT_CB" \
            "coordination --slug t --node $CT_CORE --home-repo $CT_REPO --coord-branch $CT_CB"; do
    # shellcheck disable=SC2086
    (cd "$WT" && bash "$PUSH" $args >/dev/null 2>&1); rc=$?
    [ "$rc" -eq 64 ] && pass "usage [$args] exits 64" || fail "usage [$args]: rc=$rc"
done
if [ -n "$(git -C "$REPO" ls-remote origin "refs/heads/impl/*")" ]; then
    fail "a usage error pushed"
else
    pass "no usage error pushed"
fi

# --- branch refusals --------------------------------------------------------------

ct_case refusals
ct_write_db
fresh_repo refusals
(cd "$WT" && git checkout -q --detach)
push_node
[ "$RC" -eq 65 ] && pass "a detached HEAD exits 65" || fail "detached HEAD: rc=$RC"
(cd "$WT" && git checkout -q "impl/t-$CT_CORE" && git checkout -q -b other)
push_node
[ "$RC" -eq 66 ] && pass "the wrong branch exits 66" || fail "wrong branch: rc=$RC"
(cd "$REPO" && git checkout -q main 2>/dev/null)
OUT=$(cd "$REPO" && bash "$PUSH" coordination --slug t --home-repo "$CT_REPO" --coord-branch main 2>/dev/null); RC=$?
[ "$RC" -eq 67 ] && pass "the default branch exits 67" || fail "default branch: rc=$RC"
if ct_calls | grep -Eq '^pr (create|edit)'; then fail "a refusal wrote to GitHub"; else pass "no refusal wrote to GitHub"; fi

# --- a fresh node push ------------------------------------------------------------

ct_case fresh
ct_write_db
fresh_repo fresh
(cd "$WT" && mkdir -p wip && echo scratch > wip/notes.md && git add wip && git commit -q -m "wip: notes")
push_node
SHA=$(git -C "$WT" rev-parse HEAD)
REMOTE_SHA=$(git -C "$REPO" ls-remote origin "refs/heads/impl/t-$CT_CORE" | cut -f1)
if [ "$RC" -eq 0 ] && [ "$REMOTE_SHA" = "$SHA" ]; then
    pass "a fresh node push reaches origin at HEAD"
else
    fail "a fresh push: rc=$RC remote=[$REMOTE_SHA] head=[$SHA]"
    tail -5 "$CASE/stderr"
fi
if [ -z "$(git -C "$REPO" ls-tree -r --name-only "$REMOTE_SHA" -- wip/)" ]; then
    pass "the wip/ sweep ran: git ls-files wip/ on the pushed head is empty"
else
    fail "the pushed head still carries wip/"
fi
CREATES=$(ct_calls | grep -c '^pr create')
CREATE=$(ct_calls | grep '^pr create')
if [ "$CREATES" -eq 1 ] && printf '%s' "$CREATE" | grep -q -- '--draft' \
    && printf '%s' "$CREATE" | grep -q -- "--title feat(t): $CT_CORE" \
    && printf '%s' "$CREATE" | grep -q -- '--body-file' \
    && printf '%s' "$CREATE" | grep -q -- '--base main' && printf '%s' "$CREATE" | grep -q -- "--head impl/t-$CT_CORE"; then
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
if grep -q -- '--coordination-body' "$CASE/shirabe-calls.log" && [ "$(ct_calls | grep -c '^pr edit 10')" -eq 1 ]; then
    pass "the new body was validated, then posted with one pr edit"
else
    fail "validation or edit missing: shirabe=[$(cat "$CASE/shirabe-calls.log")]"
fi

# --- a second push: adopt, replace the line ---------------------------------------

(cd "$WT" && git commit -q --allow-empty -m "fix: more")
push_node
SHA2=$(git -C "$WT" rev-parse HEAD)
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

# --- an indexed node with nothing owned to adopt -----------------------------------

ct_case adopt-missing
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'author="someone-else"'
ct_write_db
fresh_repo adopt-missing
push_node
if [ "$RC" -eq 73 ] && ! ct_calls | grep -q '^pr create' && ! ct_calls | grep -q '^pr edit'; then
    pass "an indexed node whose PR is not owned exits 73 with no pr create or edit"
else
    fail "adopt-missing: rc=$RC"
fi

# --- a failing validation -----------------------------------------------------------

ct_case body-invalid
ct_write_db
fresh_repo body-invalid
BEFORE=$(jq -r '.prs[] | select(.number == 10) | .body' "$CASE/scenario/gh/db.json")
export CT_BODY_FAIL=1
push_node
unset CT_BODY_FAIL
if [ "$RC" -eq 74 ] && ! ct_calls | grep -q '^pr edit' && [ "$(db_body)" = "$BEFORE" ]; then
    pass "a failing --coordination-body validation exits 74 and leaves the posted body untouched"
else
    fail "body-invalid: rc=$RC edits=$(ct_calls | grep -c '^pr edit')"
fi

# --- no coordination PR -------------------------------------------------------------

ct_case no-coord
ct_write_db
fresh_repo no-coord
OUT=$(cd "$WT" && bash "$PUSH" node --slug t --node "$CT_CORE" --repo "$CT_REPO" --issues 1 \
    --home-repo "$CT_REPO" --coord-branch docs/elsewhere 2>/dev/null); RC=$?
[ "$RC" -eq 73 ] && pass "no owned coordination PR exits 73" || fail "no-coord: rc=$RC"

# --- coordination mode ------------------------------------------------------------------

ct_case coordination
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_write_db
fresh_repo coordination
(cd "$REPO" && git rm -q docs/plans/PLAN-t.md && git commit -q -m "chore: cascade")
OUT=$(cd "$REPO" && bash "$PUSH" coordination --slug t --home-repo "$CT_REPO" --coord-branch "$CT_CB" 2>"$CASE/stderr"); RC=$?
CSHA=$(git -C "$REPO" rev-parse HEAD)
if [ "$RC" -eq 0 ] && [ "$(git -C "$REPO" ls-remote origin "refs/heads/$CT_CB" | cut -f1)" = "$CSHA" ] \
    && db_body | grep -qxF -- "- coordination | $CT_REPO:docs/plans/PLAN-t.md#10 | open | head=$CSHA" \
    && db_body | grep -qxF -- "- $CT_CORE | $CT_REPO:docs/plans/PLAN-t.md#11 | open | head=$CT_HEAD"; then
    pass "coordination mode pushes the coordination branch and records its own head= line"
else
    fail "coordination mode: rc=$RC; $(tail -3 "$CASE/stderr")"
fi
ct_calls | grep -q '^pr create' && fail "coordination mode created a PR" || pass "coordination mode creates no PR"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

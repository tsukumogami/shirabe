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
#     (a node push without --plan, a --plan that is no file, and --plan in
#     the coordination mode among them)
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
#   the merge order, on a PLAN with two PR nodes and a gate between them
#     the `## Merge Order` section is replaced by the rendered block: every
#     node, the gate included, after its predecessors, with its waits_on;
#     a second push renders the same section; a PLAN whose waits_on changed
#     re-renders it whole
#   a PLAN with no node named --node             exit 76, nothing pushed, no
#                                                gh write
#   order mode                                   renders the block into the
#     coordination body with no push, no PR created, and the index untouched;
#     a second render is the same; an unreadable PLAN exits 76 with no edit;
#     usage errors exit 64
#   coordination mode                            pushes the coordination branch
#     and records the coordination PR's own line with head=, leaving the
#     merge-order section as it was
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
    OUT=$(cd "$WT" && bash "$PUSH" node --slug t --node "$CT_CORE" --repo "$CT_REPO" --issues 1,2 \
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

ct_case usage
ct_write_db
fresh_repo usage
for args in "" "branch --slug t" "node --slug T --node $CT_CORE --repo $CT_REPO --issues 1 --home-repo $CT_REPO --coord-branch $CT_CB" \
            "node --slug t --node coordination --repo $CT_REPO --issues 1 --home-repo $CT_REPO --coord-branch $CT_CB" \
            "node --slug t --node $CT_CORE --repo $CT_REPO --issues '#1' --home-repo $CT_REPO --coord-branch $CT_CB" \
            "coordination --slug t --node $CT_CORE --home-repo $CT_REPO --coord-branch $CT_CB" \
            "node --slug t --node $CT_CORE --repo $CT_REPO --issues 1 --home-repo $CT_REPO --coord-branch $CT_CB" \
            "node --slug t --node $CT_CORE --repo $CT_REPO --issues 1 --home-repo $CT_REPO --coord-branch $CT_CB --plan $CT_WORK/no-such-plan.md" \
            "coordination --slug t --home-repo $CT_REPO --coord-branch $CT_CB --plan $PLAN"; do
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
    --home-repo "$CT_REPO" --coord-branch docs/elsewhere --plan "$PLAN" 2>/dev/null); RC=$?
[ "$RC" -eq 73 ] && pass "no owned coordination PR exits 73" || fail "no-coord: rc=$RC"

# --- the merge order ------------------------------------------------------------------
#
# The gated PLAN: pr-repo-a-core, then the gate publish-core, then pr-repo-a-cli,
# which waits on both. The seeded body's block lists two nodes with a merge
# state; the push must replace it whole.

ct_case merge-order
ct_write_db
fresh_repo merge-order gated
push_node
WANT=$(cat <<'EOF'
## Merge Order

```merge-order
# Rendered by /execute from the PLAN's waits_on graph; not read by the merge gate.
# One node per line, after its predecessors: <node-id> | pr|gate | after: <node-ids>
pr-repo-a-core | pr | after: -
gate-publish-core | gate | after: pr-repo-a-core
pr-repo-a-cli | pr | after: pr-repo-a-core, gate-publish-core
```
EOF
)
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

# The PLAN's waits_on changes (the gate is dropped): the block is re-rendered whole.
grep -v '_Gate:' "$PLAN" > "$PLAN.new" && mv "$PLAN.new" "$PLAN"
(cd "$WT" && git commit -q --allow-empty -m "fix: once more")
push_node
WANT2=$(printf '%s\n' "$WANT" | grep -v '^gate-publish-core |' | sed 's/^pr-repo-a-cli | pr | after: .*/pr-repo-a-cli | pr | after: pr-repo-a-core/')
if [ "$RC" -eq 0 ] && [ "$(merge_order_section)" = "$WANT2" ]; then
    pass "a PLAN whose waits_on changed re-renders the whole block"
else
    fail "the section after the PLAN changed (rc=$RC): $(merge_order_section)"
fi

# --- a PLAN with no such node -----------------------------------------------------------

ct_case plan-no-node
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
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_write_db
fresh_repo order gated
INDEX_BEFORE=$(jq -r '.prs[] | select(.number == 10) | .body' "$CASE/scenario/gh/db.json" | grep '^- ')
order_run() { # order_run [extra args]
    OUT=$(cd "$REPO" && bash "$PUSH" order --slug t --home-repo "$CT_REPO" --coord-branch "$CT_CB" "$@" 2>"$CASE/stderr")
    RC=$?
}
order_run --plan "$PLAN"
if [ "$RC" -eq 0 ] && [ "$(merge_order_section)" = "$WANT" ] && [ "$OUT" = "pr=https://github.com/acme/repo-a/pull/10" ]; then
    pass "order mode renders the PLAN's merge order into the coordination body and prints pr="
else
    fail "order mode (rc=$RC, out=[$OUT]): $(merge_order_section); $(tail -3 "$CASE/stderr")"
fi
if [ -z "$(git -C "$REPO" ls-remote origin "refs/heads/*" | grep -v 'refs/heads/main$')" ] \
    && ! ct_calls | grep -q '^pr create' && [ "$(ct_calls | grep -c '^pr edit 10')" -eq 1 ] \
    && [ "$(db_body | grep '^- ')" = "$INDEX_BEFORE" ]; then
    pass "order mode pushes nothing, creates no PR, and leaves the PR index as it was"
else
    fail "order mode side effects: $(ct_calls)"
fi
order_run --plan "$PLAN"
[ "$RC" -eq 0 ] && [ "$(merge_order_section)" = "$WANT" ] \
    && pass "a second order render leaves the section as it was" \
    || fail "a second order render (rc=$RC): $(merge_order_section)"
EDITS=$(ct_calls | grep -c '^pr edit 10')
echo "not a plan" > "$CT_WORK/bad-plan.md"
order_run --plan "$CT_WORK/bad-plan.md"
if [ "$RC" -eq 76 ] && [ "$(ct_calls | grep -c '^pr edit 10')" -eq "$EDITS" ]; then
    pass "order mode on a PLAN plan-to-tasks.sh can't read exits 76 with no edit"
else
    fail "order mode, unreadable PLAN: rc=$RC"
fi
for args in "" "--plan $PLAN --node $CT_CORE" "--plan $PLAN --remote origin" "--plan $CT_WORK/no-such-plan.md"; do
    # shellcheck disable=SC2086
    order_run $args
    [ "$RC" -eq 64 ] && pass "order mode usage [$args] exits 64" || fail "order mode usage [$args]: rc=$RC"
done

# --- coordination mode ------------------------------------------------------------------

ct_case coordination
ct_index_line "$CT_CORE" "$CT_REPO" 11 "$CT_HEAD"
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" 'state="MERGED"'
ct_write_db
fresh_repo coordination
(cd "$REPO" && git rm -q docs/plans/PLAN-t.md && git commit -q -m "chore: cascade")
ORDER_BEFORE=$(jq -r '.prs[] | select(.number == 10) | .body' "$CASE/scenario/gh/db.json" \
    | awk '/^## /{ s = ($0 ~ /^## Merge Order/) } s')
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
[ -n "$ORDER_BEFORE" ] && [ "$(merge_order_section)" = "$ORDER_BEFORE" ] \
    && pass "coordination mode, after the cascade deleted the PLAN, leaves the merge-order section as it was" \
    || fail "coordination mode changed the merge-order section: $(merge_order_section)"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

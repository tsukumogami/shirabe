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
#     a second render is the same; an unreadable PLAN, or one that isn't
#     coordinated, exits 76 with no edit; usage errors exit 64
#   coordination mode                            pushes the coordination branch
#     and records the coordination PR's own line with head=, leaving the
#     merge-order section as it was
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

# --- the run marker -----------------------------------------------------------------------

MINE=0123456789abcdef0123456789abcdef
OTHER=fedcba9876543210fedcba9876543210

ct_case marker-fresh
ct_write_db
fresh_repo marker-fresh
push_node --run-id "$MINE"
NBODY=$(db_pr 50 | jq -r '.body')
if [ "$RC" -eq 0 ] && printf '%s\n' "$NBODY" | grep -qxF "<!-- shirabe-run: $MINE -->" \
    && printf '%s' "$NBODY" | grep -q "Work items: 1,2"; then
    pass "--run-id: the node PR it opens carries the run's marker line"
else
    fail "marker-fresh: rc=$RC body [$NBODY]"
fi
if ct_calls | grep '^pr list' | grep -q . && [ "$(ct_calls | grep -c '^pr create')" -eq 1 ]; then
    (cd "$WT" && git commit -q --allow-empty -m "fix: more")
    push_node --run-id "$MINE"
    if [ "$RC" -eq 0 ] && [ "$(ct_calls | grep -c '^pr create')" -eq 1 ]; then
        pass "--run-id: a second push by the same run adopts its own marked PR"
    else
        fail "marker second push: rc=$RC creates=$(ct_calls | grep -c '^pr create')"
    fi
fi

ct_case marker-foreign
ct_pr "$CT_REPO" 11 "impl/t-$CT_CORE" "body=\"x\\n<!-- shirabe-run: $OTHER -->\""
ct_write_db
fresh_repo marker-foreign
push_node --run-id "$MINE"
if [ "$RC" -eq 73 ] && ! ct_calls | grep -q '^pr create' && ! ct_calls | grep -q '^pr edit'; then
    pass "--run-id: another run's PR on the node branch is not adopted (73), nothing created or edited"
else
    fail "marker-foreign: rc=$RC creates=$(ct_calls | grep -c '^pr create')"
fi
if [ -z "$(git -C "$REPO" ls-remote origin "refs/heads/impl/t-$CT_CORE")" ]; then
    pass "--run-id: nothing is pushed onto a branch whose PR another run opened"
else
    fail "marker-foreign: the node branch was pushed onto another run's PR"
fi

ct_case marker-kept
ct_write_db
# The coordination PR carries a run marker after its merge-order block, as a
# stamped body would; the index rewrite must keep that line.
jq --arg m "<!-- shirabe-run: $MINE -->" '(.prs[] | select(.number == 10) | .body) += "\n" + $m + "\n"' \
    "$CASE/scenario/gh/db.json" > "$CASE/db.tmp" && mv "$CASE/db.tmp" "$CASE/scenario/gh/db.json"
fresh_repo marker-kept
push_node --run-id "$MINE"
if [ "$RC" -eq 0 ] && db_body | grep -qxF "<!-- shirabe-run: $MINE -->" \
    && db_body | grep -q "^- $CT_CORE | .*head="; then
    pass "the coordination PR's index rewrite keeps its run marker line"
else
    fail "marker-kept: rc=$RC; body [$(db_body)]"
fi

ct_case marker-usage
ct_write_db
fresh_repo marker-usage
push_node --run-id NOTANID
[ "$RC" -eq 64 ] && pass "a malformed --run-id is a usage error" || fail "bad --run-id: rc=$RC"

# --- the merge order ------------------------------------------------------------------
#
# The gated PLAN: pr-repo-a-core, then the gate publish-core, then pr-repo-a-cli,
# which waits on both. The seeded body's block lists two nodes with a merge
# state; the push must replace it whole.

ct_case merge-order
ct_write_db
fresh_repo merge-order gated
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
# A PLAN that parses but isn't coordinated: its tasks carry no NODE_KIND, and
# rendering them as PR nodes would put a wrong order on the record.
cat > "$CT_WORK/multi-pr-plan.md" <<'PLAN'
---
schema: plan/v1
status: Active
execution_mode: multi-pr
milestone: "t"
issue_count: 2
---

# PLAN: t

## Status

Active

## Implementation Issues

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: feat parser](https://example.com/1) | None | testable |
| [#2: test parser](https://example.com/2) | [#1](https://example.com/1) | testable |
PLAN
order_run --plan "$CT_WORK/multi-pr-plan.md"
if [ "$RC" -eq 76 ] && [ "$(ct_calls | grep -c '^pr edit 10')" -eq "$EDITS" ]; then
    pass "order mode on a PLAN that isn't coordinated exits 76 with no edit"
else
    fail "order mode, multi-pr PLAN: rc=$RC"
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
    ct_case "$1"
    CT_VIS_A="$2"
    CT_VIS_B="$3"
    [ -n "${VIS_PRS:-}" ] && ct_pr acme/repo-b 60 "impl/t-$CT_CORE" "$VIS_PRS"
    ct_write_db
    fresh_repo "$1"
    node_clone "$1"
    if [ -n "${4:-}" ]; then
        (cd "$WT" && printf '%s\n' "$4" > notes.txt && git add notes.txt && git commit -q -m "docs: notes")
    fi
    OUT=$(cd "$WT" && bash "$PUSH" node --slug t --node "$CT_CORE" --repo acme/repo-b --issues 1,2 \
        --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" 2>"$CASE/stderr")
    RC=$?
    NBODY=$(jq -r '.prs[] | select(.repo == "acme/repo-b") | .body' "$GH_CALL_LOG.d/db.json" 2>/dev/null)
}
pushed() { [ -n "$(git -C "$NREPO" ls-remote origin "refs/heads/impl/t-$CT_CORE")" ]; }

vis_push vis-pub-pub public public
if [ "$RC" -eq 0 ] && pushed && printf '%s' "$NBODY" | grep -qxF "Coordination PR: https://github.com/acme/repo-a/pull/10"; then
    pass "public home, public node: pushed, and the node PR links the coordination PR"
else
    fail "public over public: rc=$RC body=[$NBODY] $(tail -2 "$CASE/stderr")"
fi

vis_push vis-priv-pub private public
if [ "$RC" -eq 0 ] && pushed && printf '%s' "$NBODY" | grep -q "Work items: 1,2"; then
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
if [ "$RC" -eq 0 ] && pushed && printf '%s' "$NBODY" | grep -qxF "Coordination PR: https://github.com/acme/repo-a/pull/10"; then
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
    OUT=$(cd "$WT" && bash "$PUSH" node --slug t --node "$CT_CORE" --repo acme/repo-b --issues 1,2 \
        --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" 2>"$CASE/stderr")
    RC=$?
}
# home_has_node_branch -- the home's origin holds the node branch.
home_has_node_branch() { [ -n "$(git -C "$REPO" ls-remote origin "refs/heads/impl/t-$CT_CORE")" ]; }
gh_wrote() { ct_calls | grep -Eq '^pr (create|edit|ready|merge|close)'; }

ct_case home-worktree
ct_write_db
fresh_repo home-worktree
home_push
if [ "$RC" -eq 79 ] && ! home_has_node_branch && ! gh_wrote \
    && grep -q "cut it with node-cut.sh --repo-dir" "$CASE/stderr" && ! grep -q 'acme/' "$CASE/stderr"; then
    pass "a node in another repository, cut in the coordination checkout: exit 79, nothing pushed or written, no repository named"
else
    fail "home worktree: rc=$RC pushed=$(home_has_node_branch && echo yes || echo no) stderr=[$(tail -1 "$CASE/stderr")]"
fi

ct_case home-url
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
ct_case home-worktree-alt-remote
ct_write_db
fresh_repo home-worktree-alt-remote
git init -q --bare "$CT_WORK/alt-remote.git"
(cd "$REPO" && git remote add alt "$CT_WORK/alt-remote.git")
OUT=$(cd "$WT" && bash "$PUSH" node --slug t --node "$CT_CORE" --repo acme/repo-b --issues 1,2 \
    --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" --remote alt 2>"$CASE/stderr")
RC=$?
if [ "$RC" -eq 79 ] && [ -z "$(git ls-remote "$CT_WORK/alt-remote.git" "refs/heads/impl/*")" ]; then
    pass "a worktree of the coordination checkout pushing through another remote: exit 79, nothing pushed"
else
    fail "alt remote: rc=$RC stderr=[$(tail -1 "$CASE/stderr")]"
fi

# The home's origin spelled another way: the same repository over ssh in the
# coordination checkout, over https in the node clone.
ct_case home-url-spelling
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
ct_case home-insteadof
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
ct_case home-pushurl
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
ct_case home-mirror
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
ct_case plan-outside-git
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

ct_case own-clone
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

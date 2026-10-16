#!/usr/bin/env bash
# coordinated-home-outside_test.sh — a coordinated run whose coordination PR
# lives in a repository that holds none of the PLAN's nodes
# Part of the execute skill
#
# The layout: a private planning repository (acme/repo-a) holds the
# coordination branch, the PLAN, and the coordination PR (#10); every node of
# the PLAN lands in a public repository (acme/repo-b). The case walks the run
# from coord_setup to the coordination PR's merge with the real scripts, the
# way execute-coordinated.md's directives call them: record-coord-setup.sh,
# then coordinated-next.sh in a loop, performing each action it prints
# (node-cut.sh and node-push.sh for a dispatch, `gh pr ready` for an evaluate,
# coord-merge.sh for a merge, node-push.sh order and coordination around the
# cascade). GitHub is the eval gh shim's repository model and koto the context
# stub (see coord-test-helpers.sh); both repositories' origins are local bare
# repositories.
#
# Cases:
#   coord_setup           records repos=acme/repo-b and home_repo=acme/repo-a
#   the loop              dispatches, readies, and merges both nodes in node
#                         order, runs the cascade, readies and merges the
#                         coordination PR, and ends done:merged within a bound
#                         on steps; the action sequence is asserted whole
#   the home's writes     every GitHub write naming acme/repo-a is an edit,
#                         ready, or merge of the coordination PR #10, and no PR
#                         is created there; every other write names acme/repo-b
#   the home's branches   the home origin gains only the coordination branch,
#                         never a node branch; the node origin gains both node
#                         branches and never the coordination branch
#   the index             the coordination entry names acme/repo-a, the node
#                         entries acme/repo-b
#   visibility            neither public node PR links the private
#                         coordination PR
#
# Usage: coordinated-home-outside_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
PLAN_TO_TASKS="$SCRIPT_DIR/../../plan/scripts/plan-to-tasks.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

S=execute-t
RUN=00112233445566778899aabbccddeeff
HOME_REPO=acme/repo-a
NODE_REPO=acme/repo-b

ct_case walk
CT_VIS_A=private
CT_VIS_B=public
ct_write_db
DB="$GH_CALL_LOG.d/db.json"

# The coordination checkout: acme/repo-a (the model's default_repo), on the
# coordination branch, with a PLAN whose nodes all name acme/repo-b.
HOMEDIR="$CT_WORK/home-checkout"
ct_repo "$HOMEDIR"
ct_plan "$HOMEDIR" remote
(cd "$HOMEDIR" && git add docs && git commit -q -m "docs: plan" && git push -q origin "$CT_CB")
PLAN="$HOMEDIR/docs/plans/PLAN-t.md"
# A clone of the node repository.
NODEDIR="$CT_WORK/node-clone"
ct_repo "$NODEDIR"
(cd "$NODEDIR" && git checkout -q main)

ctx() { cat "$CASE/ctx/$S/$1" 2>/dev/null; }

# --- coord_setup ------------------------------------------------------------------

(cd "$HOMEDIR" && bash "$SCRIPT_DIR/record-coord-setup.sh" --session "$S" --plan docs/plans/PLAN-t.md \
    >"$CASE/setup.out" 2>"$CASE/setup.err")
RC=$?
if [ "$RC" -eq 0 ] && [ "$(ctx repos)" = "$NODE_REPO" ] && [ "$(ctx home_repo)" = "$HOME_REPO" ]; then
    pass "coord_setup records repos=$NODE_REPO and home_repo=$HOME_REPO"
else
    fail "coord_setup: rc=$RC repos=[$(ctx repos)] home=[$(ctx home_repo)] err=[$(cat "$CASE/setup.err")]"
    echo
    echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
    exit 1
fi
REPOS=$(ctx repos)

# --- the loop ---------------------------------------------------------------------

TASKS=$(bash "$PLAN_TO_TASKS" "$PLAN" 2>/dev/null)
node_issues() { printf '%s' "$TASKS" | jq -r --arg n "$1" '.[] | select(.name == $n) | .vars.ISSUES'; }
index_number() { # index_number <node> -- the PR number the coordination PR's index names
    jq -r '.prs[] | select(.repo == "acme/repo-a" and .number == 10) | .body' "$DB" \
        | sed -n "s/^- $1 | [^:]*:[^#]*#\\([0-9]*\\) .*/\\1/p" | head -1
}

ACTIONS=""
step=0
while [ "$step" -lt 20 ]; do
    step=$((step + 1))
    ATTEMPTS=$(ctx merge_attempts)
    set -- --plan docs/plans/PLAN-t.md --slug "$CT_SLUG" --repos "$REPOS" --home-repo "$(ctx home_repo)" \
        --coord-branch "$(ctx coord_branch)" --merge true --run-id "$RUN"
    [ -n "$ATTEMPTS" ] && set -- "$@" --attempts "$ATTEMPTS"
    # The PLAN path is relative to the coordination checkout; once the cascade
    # deleted it, the index is the node list.
    ACTION=$(cd "$HOMEDIR" && bash "$SCRIPT_DIR/coordinated-next.sh" "$@" 2>>"$CASE/next.err")
    ACTIONS="$ACTIONS$ACTION "
    case "$ACTION" in
        dispatch:*)
            node="${ACTION#dispatch:}"
            WT=$(cd "$HOMEDIR" && bash "$SCRIPT_DIR/node-cut.sh" "$CT_SLUG" "$node" --repo-dir "$NODEDIR" 2>>"$CASE/cut.err" \
                | sed -n 's/^worktree=//p')
            [ -n "$WT" ] && [ -d "$WT" ] || { fail "node-cut.sh made no worktree for $node: $(cat "$CASE/cut.err")"; break; }
            (cd "$WT" && echo "$node" > "$node.txt" && git add "$node.txt" && git commit -q -m "feat: $node")
            (cd "$WT" && bash "$SCRIPT_DIR/node-push.sh" node --slug "$CT_SLUG" --node "$node" --repo "$NODE_REPO" \
                --issues "$(node_issues "$node")" --home-repo "$(ctx home_repo)" --coord-branch "$(ctx coord_branch)" \
                --plan "$(ctx plan_abs)" --run-id "$RUN" >>"$CASE/push.out" 2>>"$CASE/push.err") \
                || { fail "node-push.sh node $node: $(tail -3 "$CASE/push.err")"; break; }
            ;;
        evaluate:*)
            node="${ACTION#evaluate:}"
            n=$(index_number "$node")
            gh pr ready "$n" --repo "$NODE_REPO" >/dev/null || { fail "gh pr ready $n"; break; }
            ;;
        merge:*)
            node="${ACTION#merge:}"
            out=$(cd "$HOMEDIR" && bash "$SCRIPT_DIR/coord-merge.sh" --session "$S" --slug "$CT_SLUG" \
                --home-repo "$(ctx home_repo)" --coord-branch "$(ctx coord_branch)" --node "$node" 2>>"$CASE/merge.err")
            printf '%s\n' "$out" | grep -qx merged || { fail "coord-merge.sh $node: [$out] $(tail -2 "$CASE/merge.err")"; break; }
            ;;
        cascade)
            (cd "$HOMEDIR" && bash "$SCRIPT_DIR/node-push.sh" order --slug "$CT_SLUG" --home-repo "$(ctx home_repo)" \
                --coord-branch "$(ctx coord_branch)" --plan "$(ctx plan_abs)" --run-id "$RUN" >/dev/null 2>>"$CASE/push.err") \
                || { fail "node-push.sh order: $(tail -3 "$CASE/push.err")"; break; }
            # The finalization cascade's own commit and push, standing in for
            # run-cascade.sh --push (a plain push of the coordination branch
            # from this checkout, with its own tests): what this case needs is
            # the PLAN gone from the coordination branch and the branch pushed
            # to the home origin, not the cascade's document transitions.
            (cd "$HOMEDIR" && git rm -q docs/plans/PLAN-t.md && git commit -q -m "chore: finalize" && git push -q origin "$CT_CB")
            (cd "$HOMEDIR" && bash "$SCRIPT_DIR/node-push.sh" coordination --slug "$CT_SLUG" --home-repo "$(ctx home_repo)" \
                --coord-branch "$(ctx coord_branch)" --run-id "$RUN" >/dev/null 2>>"$CASE/push.err") \
                || { fail "node-push.sh coordination: $(tail -3 "$CASE/push.err")"; break; }
            # GitHub now reports the pushed commit as the coordination PR's
            # head. The shim's model can't see a push, so the case moves it.
            sha=$(git -C "$HOMEDIR" rev-parse HEAD)
            jq --arg sha "$sha" '(.prs[] | select(.repo == "acme/repo-a" and .number == 10) | .headRefOid) = $sha' \
                "$DB" > "$DB.tmp" && mv "$DB.tmp" "$DB"
            ;;
        evaluate-coordination)
            gh pr ready 10 --repo "$(ctx home_repo)" >/dev/null || { fail "gh pr ready 10"; break; }
            ;;
        merge-coordination)
            out=$(cd "$HOMEDIR" && bash "$SCRIPT_DIR/coord-merge.sh" --session "$S" --slug "$CT_SLUG" \
                --home-repo "$(ctx home_repo)" --coord-branch "$(ctx coord_branch)" --node coordination 2>>"$CASE/merge.err")
            printf '%s\n' "$out" | grep -qx merged || { fail "coord-merge.sh coordination: [$out] $(tail -2 "$CASE/merge.err")"; break; }
            ;;
        *) break ;;
    esac
done

WANT="dispatch:pr-repo-b-core evaluate:pr-repo-b-core merge:pr-repo-b-core dispatch:pr-repo-b-cli evaluate:pr-repo-b-cli merge:pr-repo-b-cli cascade evaluate-coordination merge-coordination done:merged "
if [ "$ACTIONS" = "$WANT" ]; then
    pass "the loop drives both nodes and then the coordination PR to done:merged"
else
    fail "the loop's actions: [$ACTIONS], expected [$WANT]"
    tail -5 "$CASE/next.err" 2>/dev/null | sed 's/^/    /'
fi
STATES=$(jq -r '[.prs[] | "\(.repo)#\(.number)=\(.state)"] | join(" ")' "$DB")
if [ "$(jq '[.prs[] | select(.state == "MERGED")] | length' "$DB")" -eq 3 ] \
    && [ "$(jq -r '.prs[] | select(.repo == "acme/repo-a" and .number == 10) | .state' "$DB")" = MERGED ]; then
    pass "the coordination PR and both node PRs are MERGED"
else
    fail "PR states: $STATES"
fi

# --- the home repository's writes ---------------------------------------------------

WRITES=$(grep -E '^pr (create|edit|ready|merge|close)' "$GH_CALL_LOG" || true)
HOME_WRITES=$(printf '%s\n' "$WRITES" | grep -F -- "--repo $HOME_REPO" || true)
if [ -z "$HOME_WRITES" ]; then
    fail "no write reached the home repository; the coordination PR was never edited"
elif printf '%s\n' "$HOME_WRITES" | grep -Eqv '^pr (edit|ready|merge) 10 '; then
    fail "a write to the home repository other than the coordination PR's: $(printf '%s\n' "$HOME_WRITES" | grep -Ev '^pr (edit|ready|merge) 10 ' | head -1)"
else
    pass "every write to $HOME_REPO is an edit, ready, or merge of the coordination PR ($(printf '%s\n' "$HOME_WRITES" | grep -c .) calls)"
fi
for verb in edit ready merge; do
    if printf '%s\n' "$HOME_WRITES" | grep -Eq "^pr $verb 10 "; then
        pass "the coordination PR was reached by pr $verb"
    else
        fail "the coordination PR was never reached by pr $verb"
    fi
done
if [ "$(jq '[.prs[] | select(.repo == "acme/repo-a")] | length' "$DB")" -eq 1 ]; then
    pass "no PR was created in $HOME_REPO"
else
    fail "PRs in $HOME_REPO: $(jq -c '[.prs[] | select(.repo == "acme/repo-a") | .number]' "$DB")"
fi
OTHER=$(printf '%s\n' "$WRITES" | grep -v -F -- "--repo $HOME_REPO" | grep -v -F -- "--repo $NODE_REPO" | grep . || true)
[ -z "$OTHER" ] && pass "every other write names $NODE_REPO" || fail "a write naming neither repository: $OTHER"

# A public node PR under a private coordination PR carries no link into it.
LINKED=$(jq -r '[.prs[] | select(.repo == "acme/repo-b") | select(.body | test("acme/repo-a/pull/10|acme/repo-a#10"))] | length' "$DB")
NODE_PRS=$(jq '[.prs[] | select(.repo == "acme/repo-b")] | length' "$DB")
if [ "$NODE_PRS" -eq 2 ] && [ "$LINKED" -eq 0 ]; then
    pass "neither public node PR links the private coordination PR"
else
    fail "node PRs: $NODE_PRS, linking the coordination PR: $LINKED"
fi

# --- branches ---------------------------------------------------------------------

HOME_REFS=$(git ls-remote --heads "$HOMEDIR.origin.git" | awk '{print $2}' | sort | tr '\n' ' ')
NODE_REFS=$(git ls-remote --heads "$NODEDIR.origin.git" | awk '{print $2}' | sort | tr '\n' ' ')
[ "$HOME_REFS" = "refs/heads/$CT_CB refs/heads/main " ] \
    && pass "the home origin holds only main and the coordination branch" || fail "home origin refs: [$HOME_REFS]"
[ "$NODE_REFS" = "refs/heads/impl/t-pr-repo-b-cli refs/heads/impl/t-pr-repo-b-core refs/heads/main " ] \
    && pass "the node origin holds main and both node branches, never the coordination branch" \
    || fail "node origin refs: [$NODE_REFS]"

# --- the index --------------------------------------------------------------------

BODY=$(jq -r '.prs[] | select(.repo == "acme/repo-a" and .number == 10) | .body' "$DB")
if printf '%s\n' "$BODY" | grep -Eq '^- coordination \| acme/repo-a:[^#]*#10 \| ' \
    && [ "$(printf '%s\n' "$BODY" | grep -Ec '^- pr-repo-b-(core|cli) \| acme/repo-b:')" -eq 2 ]; then
    pass "the index names acme/repo-a for the coordination entry and acme/repo-b for both nodes"
else
    fail "the index: $(printf '%s\n' "$BODY" | grep '^- ')"
fi

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

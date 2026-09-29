#!/usr/bin/env bash
# coordinated-visibility_test.sh — each coordinated node checked against its
# own target: a PLAN in a private repository lands a public node and a private
# node, and one in a public repository can't dispatch a private node
# Part of the execute skill
#
# Walks the coord_loop directive's actions with the real scripts, the way the
# agent performs them: coordinated-next.sh prints the next action, and the walk
# runs exactly that action (repo-visibility.sh and node-cut.sh and node-push.sh
# for dispatch:<node>, `gh pr ready` for evaluate:<node>, coord-merge.sh for
# merge:<node>), until the node PRs are merged; then coord-merge.sh merges the
# coordination PR through the merge-last gate. GitHub is the eval gh shim's
# repository model, git is real, and koto and shirabe are the stubs in
# coord-test-helpers.sh.
#
# The PLAN is the two-repo one: a root node in acme/repo-a, the home, and
# one in acme/repo-b.
#
# Cases:
#   a private home, a private node (repo-a) and a public node (repo-b)
#     both nodes pass the visibility check, are pushed, indexed, and merged;
#     the public node's PR carries no link into the private coordination PR,
#     the private node's PR does; the coordination PR's merge gate runs with
#     --visibility private over both nodes, and the coordination PR merges
#   a public home, the same PLAN, repo-b private
#     the private node's dispatch is refused by repo-visibility.sh (exit 77)
#     before any work: no branch pushed for it, no PR opened in repo-b
#
# Usage: coordinated-visibility_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail

SCRIPT_DIR=$(CDPATH='' cd "$(dirname "$0")" && pwd)
NEXT="$SCRIPT_DIR/coordinated-next.sh"
VIS="$SCRIPT_DIR/repo-visibility.sh"
CUT="$SCRIPT_DIR/node-cut.sh"
PUSH="$SCRIPT_DIR/node-push.sh"
MERGE="$SCRIPT_DIR/coord-merge.sh"
TASKS="$SCRIPT_DIR/../../plan/scripts/plan-to-tasks.sh"

PASS_COUNT=0
FAIL_COUNT=0
pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

command -v git >/dev/null 2>&1 || { echo "FAIL: git is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required" >&2; exit 1; }

# shellcheck source=coord-test-helpers.sh
. "$SCRIPT_DIR/coord-test-helpers.sh"

S=execute-t
db() { jq -c "$1" "$GH_CALL_LOG.d/db.json"; }
node_repo() { bash "$TASKS" "$PLAN" 2>/dev/null | jq -r --arg n "$1" '.[] | select(.name == $n) | .vars.REPO'; }

# setup <case> <home vis> <repo-b vis> -- the home checkout (acme/repo-a, the
# two-repo PLAN on the coordination branch) and a clone of acme/repo-b.
setup() {
    ct_case "$1"
    CT_VIS_A="$2"
    CT_VIS_B="$3"
    CT_COORD_DRAFT=false
    ct_write_db
    HOME_CO="$CT_WORK/$1-a"
    ct_repo "$HOME_CO"
    ct_plan "$HOME_CO" two-repo
    (cd "$HOME_CO" && git add docs && git commit -q -m "docs: plan")
    PLAN="$HOME_CO/docs/plans/PLAN-t.md"
    B_CO="$CT_WORK/$1-b"
    ct_repo "$B_CO"
    (cd "$B_CO" && git checkout -q main)
    mkdir -p "$CASE/ctx/$S"
    : > "$CASE/walk.log"
}

next() {
    bash "$NEXT" --plan "$PLAN" --slug t --repos acme/repo-a,acme/repo-b --home-repo acme/repo-a \
        --coord-branch "$CT_CB" --merge true 2>>"$CASE/walk.log"
}

# dispatch <node> -- the dispatch action. Returns the visibility check's exit.
dispatch() {
    local node="$1" repo dir wt rc
    repo=$(node_repo "$node")
    bash "$VIS" --home-repo acme/repo-a --repo "$repo" --node "$node" >>"$CASE/walk.log" 2>&1
    rc=$?
    [ "$rc" -eq 0 ] || return "$rc"
    if [ "$repo" = acme/repo-a ]; then dir="$HOME_CO"; else dir="$B_CO"; fi
    wt=$(cd "$HOME_CO" && bash "$CUT" t "$node" --repo-dir "$dir" 2>>"$CASE/walk.log" | sed -n 's/^worktree=//p')
    [ -n "$wt" ] && [ -d "$wt" ] || { echo "no worktree for $node" >>"$CASE/walk.log"; return 1; }
    (cd "$wt" && echo "$node" > "$node.txt" && git add "$node.txt" && git commit -q -m "feat: $node")
    (cd "$wt" && bash "$PUSH" node --slug t --node "$node" --repo "$repo" --issues 1 \
        --home-repo acme/repo-a --coord-branch "$CT_CB" --plan "$PLAN") >>"$CASE/walk.log" 2>&1
}

# walk -- perform actions until the next one is cascade (or a stop). Prints the
# last line.
walk() {
    local line i n
    for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
        line=$(next)
        echo "next: $line" >>"$CASE/walk.log"
        case "$line" in
            dispatch:*) dispatch "${line#dispatch:}" || { printf 'refused:%s:%s\n' "${line#dispatch:}" "$?"; return; } ;;
            evaluate:*)
                n=$(db ".prs[] | select(.headRefName == \"impl/t-${line#evaluate:}\") | \"\(.number) \(.repo)\"" | tr -d '"')
                gh pr ready "${n%% *}" --repo "${n#* }" >/dev/null 2>>"$CASE/walk.log"
                ;;
            merge:*) bash "$MERGE" --session "$S" --slug t --home-repo acme/repo-a --coord-branch "$CT_CB" \
                        --node "${line#merge:}" >>"$CASE/walk.log" 2>&1 ;;
            *) printf '%s\n' "$line"; return ;;
        esac
    done
    printf 'no-end\n'
}

# --- a private home: a private node and a public node --------------------------------

setup private-home private public
END=$(walk)
if [ "$END" = cascade ]; then
    pass "private home: the walk reaches the cascade with every node merged"
else
    fail "private home: the walk ended at [$END]"; tail -15 "$CASE/walk.log"
fi
A_PR=$(db '.prs[] | select(.repo == "acme/repo-a" and (.headRefName | startswith("impl/t-")))')
B_PR=$(db '.prs[] | select(.repo == "acme/repo-b" and (.headRefName | startswith("impl/t-")))')
[ "$(printf '%s' "$A_PR" | jq -r .state)" = MERGED ] && pass "the private node (repo-a) landed" || fail "repo-a node: $A_PR"
[ "$(printf '%s' "$B_PR" | jq -r .state)" = MERGED ] && pass "the public node (repo-b) landed" || fail "repo-b node: $B_PR"
case "$(printf '%s' "$B_PR" | jq -r .body)" in
    *"Coordination PR"*|*"acme/repo-a"*) fail "the public node's PR points into the private home: $(printf '%s' "$B_PR" | jq -r .body)" ;;
    *) pass "the public node's PR carries no link into the private coordination PR" ;;
esac
case "$(printf '%s' "$A_PR" | jq -r .body)" in
    *"Coordination PR: https://github.com/acme/repo-a/pull/10"*) pass "the private node's PR links its coordination PR" ;;
    *) fail "the private node's PR body: $(printf '%s' "$A_PR" | jq -r .body)" ;;
esac
# The cascade's last step records the coordination PR's own head (the
# cascade's document edits need the shirabe binary and are left out; the
# pushed commit stands in for them). The shim's PR #10 then carries it, as
# GitHub would after the push.
(cd "$HOME_CO" && git commit -q --allow-empty -m "chore: cascade" \
    && bash "$PUSH" coordination --slug t --home-repo acme/repo-a --coord-branch "$CT_CB") >>"$CASE/walk.log" 2>&1
CSHA=$(git -C "$HOME_CO" rev-parse HEAD)
jq --arg sha "$CSHA" '(.prs[] | select(.number == 10 and .repo == "acme/repo-a") | .headRefOid) = $sha' \
    "$GH_CALL_LOG.d/db.json" > "$CASE/db.tmp" && mv "$CASE/db.tmp" "$GH_CALL_LOG.d/db.json"
bash "$MERGE" --session "$S" --slug t --home-repo acme/repo-a --coord-branch "$CT_CB" --node coordination \
    >"$CASE/coord.out" 2>"$CASE/coord.err"
GATE=$(grep -- '--merge-gate' "$CASE/shirabe-calls.log")
case "$GATE" in
    *"--visibility private"*"acme/repo-a:"*"acme/repo-b:"*|*"--visibility private"*"acme/repo-b:"*"acme/repo-a:"*)
        pass "the coordination PR's gate runs with --visibility private over both nodes" ;;
    *) fail "the gate call: [$GATE]" ;;
esac
[ "$(db '.prs[] | select(.number == 10 and .repo == "acme/repo-a") | .state')" = '"MERGED"' ] \
    && pass "the private coordination PR merged last" || fail "coordination: $(cat "$CASE/coord.out" "$CASE/coord.err")"

# --- a public home: the private node is refused at dispatch --------------------------

setup public-home public private
END=$(walk)
case "$END" in
    refused:*:77) pass "public home: the private node's dispatch is refused with 77 [$END]" ;;
    *) fail "public home: the walk ended at [$END]"; tail -15 "$CASE/walk.log" ;;
esac
if [ -z "$(git -C "$B_CO" ls-remote origin 'refs/heads/impl/*')" ] \
    && [ -z "$(db '.prs[] | select(.repo == "acme/repo-b")')" ]; then
    pass "public home: nothing pushed and no PR opened in the private repository"
else
    fail "public home: repo-b was written to"
fi
grep -q "lands in a private repository" "$CASE/walk.log" && ! grep "refused" "$CASE/walk.log" | grep -q "acme/repo-b" \
    && pass "the refusal names the node, never the private repository" \
    || fail "the refusal: $(grep refused "$CASE/walk.log")"

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

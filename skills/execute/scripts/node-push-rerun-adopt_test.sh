#!/usr/bin/env bash
# node-push-rerun-adopt_test.sh -- does node-push.sh hold an open node PR it
# adopts when that PR's body has no re-run line for a work item's verification
# re-run, and let the same push through once the line is there?
# Part of the execute skill
#
# The node's first push opens PR #50 before any work item holds a
# verification_attempts ledger, so its body has no Verification section. A
# second work item then re-runs a failed verification command. The next push
# adopts the open PR and finds its body missing that re-run line:
#
#   - it exits 82, naming the missing line, and nothing is pushed, recorded or
#     created: the remote branch keeps the first head, run/node/<node> keeps
#     the first head with no reruns, and no gh pr create, edit, ready or merge
#     runs;
#   - once a person adds the line to the PR body's Verification section, the
#     same push goes through, and run/node/<node> records the line as reruns.
#
# Usage: node-push-rerun-adopt_test.sh
# Exit codes: 0 all pass, 1 a failure

set -uo pipefail
. "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1

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

S=execute-t
# np_case <name> -- a fresh case holding a sealed run record naming the
# coordination PR #10, over both model repositories.
np_case() {
    ct_case "$1"
    CT_RECORD_REPOS="acme/repo-a,acme/repo-b"
    ct_record_setup
}
rec_node() { cat "$CASE/ctx/$S/run/node/$1" 2>/dev/null; }

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
    OUT=$(cd "$REPO" && bash "$PUSH" node --session "$S" --worktree "$WT" --slug t --node "$CT_CORE" --repo "$CT_REPO" --issues 1,2 \
        --home-repo "$CT_REPO" --coord-branch "$CT_CB" --plan "$PLAN" "$@" 2>"$CASE/stderr")
    RC=$?
}

db_pr() { jq -c --argjson n "$1" '.prs[] | select(.number == $n)' "$GH_CALL_LOG.d/db.json"; }
remote_head() { git -C "$REPO" ls-remote origin "refs/heads/impl/t-$CT_CORE" | cut -f1; }
# set_body <pr> <file> -- a person's gh pr edit of a node PR, in the model.
set_body() {
    jq --argjson n "$1" --rawfile b "$2" '(.prs[] | select(.number == $n) | .body) = $b' \
        "$GH_CALL_LOG.d/db.json" > "$CASE/db.tmp" && mv "$CASE/db.tmp" "$GH_CALL_LOG.d/db.json"
}

# --- an adopted PR missing a re-run line ---------------------------------------------
#
# node-push.sh checks deferrals before re-runs, so this case writes no
# verification_deferral and passes no --verification: a deferral would exit 80
# first. The re-run check reads an owned open PR, so the first push runs before
# the ledger exists and opens PR #50 with no Verification section.

np_case rerun-adopt
ct_write_db
fresh_repo rerun-adopt
push_node
[ "$RC" -eq 0 ] || fail "rerun-adopt first push: rc=$RC; $(tail -3 "$CASE/stderr")"
FIRST=$(remote_head)
(cd "$WT" && git commit -q --allow-empty -m "feat: second item")
RR_HEAD=$(git -C "$WT" rev-parse HEAD)
mkdir -p "$CASE/ctx/work-on-t-$CT_CORE-2"
jq -cn --arg h "$RR_HEAD" '{attempt: 1, folder: 1, head: $h, merge_base: $h, exit: 1, status: "done",
    reason: "flaky network test", archived_at: "2026-01-01T00:00:00Z",
    commands: [{id: "unit", exit_status: 1, timed_out: false, duration_secs: 3, log: "attempts/1/0-unit.log"}]}' \
    > "$CASE/ctx/work-on-t-$CT_CORE-2/verification_attempts"
RR_LINE=$(printf 'Re-run attempt 1 at `%s`: `unit` failed; reason `flaky network test`.' "$(printf '%s' "$RR_HEAD" | cut -c1-12)")
: > "$GH_CALL_LOG"
push_node
[ "$RC" -eq 82 ] && pass "an adopted PR whose body lacks the re-run line holds the push: 82" \
    || fail "rerun-adopt hold: rc=$RC; $(tail -3 "$CASE/stderr")"
[ "$(remote_head)" = "$FIRST" ] && pass "the held push leaves the remote branch at the first head" \
    || fail "rerun-adopt remote moved: rc=$RC remote=[$(remote_head)]; $(tail -3 "$CASE/stderr")"
CALLS=$(ct_calls)
case $'\n'"$CALLS" in
    *$'\n''pr create'*|*$'\n''pr edit'*|*$'\n''pr ready'*|*$'\n''pr merge'*)
        fail "the held push wrote to a PR: rc=$RC; $(grep -m1 -E '^pr (create|edit|ready|merge)' <<<"$CALLS"); $(tail -3 "$CASE/stderr")" ;;
    *) pass "the held push creates, edits, readies and merges no PR" ;;
esac
[ "$(rec_node "$CT_CORE" | jq -c '[.head,.reruns]')" = "$(jq -cn --arg h "$FIRST" '[$h,[]]')" ] \
    && pass "run/node/<node> keeps the first head with no reruns" \
    || fail "rerun-adopt record: rc=$RC record=[$(rec_node "$CT_CORE")]; $(tail -3 "$CASE/stderr")"
if grep -qF "carries a verification re-run that" "$CASE/stderr" \
    && grep -qF "doesn't record; nothing was pushed" "$CASE/stderr" \
    && grep -qF "has no re-run line for" "$CASE/stderr"; then
    pass "the hold says the PR body doesn't record the re-run and names the missing line"
else
    fail "rerun-adopt message: rc=$RC; $(tail -3 "$CASE/stderr")"
fi

# The positive control: a person adds the re-run line to PR #50's Verification
# section, and the same push goes through and records the line.
db_pr 50 | jq -r '.body' > "$CASE/body.md"
printf '\n## Verification\n\nA failed verification command was re-run at the same head:\n\n%s\n' "$RR_LINE" >> "$CASE/body.md"
set_body 50 "$CASE/body.md"
: > "$GH_CALL_LOG"
push_node
[ "$RC" -eq 0 ] && pass "with the re-run line in the body, the same push goes through" \
    || fail "rerun-adopt control: rc=$RC; $(tail -3 "$CASE/stderr")"
[ "$(remote_head)" = "$(git -C "$WT" rev-parse HEAD)" ] && pass "the control push moves the remote branch to the node's head" \
    || fail "rerun-adopt control remote: rc=$RC remote=[$(remote_head)]; $(tail -3 "$CASE/stderr")"
[ "$(rec_node "$CT_CORE" | jq -c '.reruns')" = "$(jq -cn --arg l "$RR_LINE" '[$l]')" ] \
    && pass "run/node/<node> records the re-run line as reruns" \
    || fail "rerun-adopt control record: rc=$RC record=[$(rec_node "$CT_CORE")]; $(tail -3 "$CASE/stderr")"
CALLS=$(ct_calls)
case $'\n'"$CALLS" in
    *$'\n''pr create'*) fail "the control push created a PR: $(grep -m1 '^pr create' <<<"$CALLS")" ;;
    *) pass "the control push adopts PR #50 and creates none" ;;
esac

echo
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
exit 0

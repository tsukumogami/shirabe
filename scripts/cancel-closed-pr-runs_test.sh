#!/usr/bin/env bash
# cancel-closed-pr-runs_test.sh -- test harness for
# scripts/cancel-closed-pr-runs.sh.
#
# Usage: bash scripts/cancel-closed-pr-runs_test.sh
#
# Each case runs the script against a stub gh, first on PATH, that serves the
# runs a case writes for each status and the PR's commits, and records every
# run it is asked to cancel. The floor workflows come from
# scripts/check-macos-floor-setup.sh over its own clean fixtures, where
# floor-a.yml and floor-b.yml are the floor workflows. Every guard has a case
# with one run the guard must keep and one run that must still be cancelled,
# so a guard that dropped everything would fail too. Requires jq, mikefarah
# yq v4 and python3, like the script.
#
# Exit codes:
#   0 -- all cases pass
#   1 -- one or more cases failed

set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$SCRIPT_DIR/cancel-closed-pr-runs.sh"
FIXTURES="$SCRIPT_DIR/check-macos-floor-setup/fixtures/clean"

PASS_COUNT=0
FAIL_COUNT=0
pass() { printf 'PASS: %s\n' "$*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

T=$(mktemp -d "${TMPDIR:-/tmp}/cancel-closed-pr-runs-test.XXXXXX") || exit 1
cleanup() { [ -n "${T:-}" ] && rm -rf "$T"; return 0; }
trap cleanup EXIT

mkdir "$T/bin" || exit 1
cat >"$T/bin/gh" <<'EOF'
#!/usr/bin/env bash
# The stub gh: answers the three calls cancel-closed-pr-runs.sh makes from
# the files under $STUB_DIR.
printf '%s\n' "$*" >>"$STUB_DIR/calls"
case "$*" in
    *"/pulls/"*"/commits"*)
        if [ -n "${STUB_COMMITS_FAIL:-}" ]; then
            echo "gh: stub refusal (HTTP $STUB_COMMITS_FAIL)" >&2; exit 1
        fi
        cat "$STUB_DIR/commits"
        ;;
    *"/actions/runs/"*"/cancel"*)
        id="$*"
        id=${id##*actions/runs/}
        id=${id%%/cancel*}
        if [ -f "$STUB_DIR/cancel-fails-$id" ]; then
            echo "gh: stub refusal (HTTP $(cat "$STUB_DIR/cancel-fails-$id"))" >&2; exit 1
        fi
        echo "$id" >>"$STUB_DIR/cancelled"
        ;;
    *"/actions/runs"*)
        if [ -n "${STUB_LIST_FAIL:-}" ]; then
            echo "gh: stub refusal (HTTP $STUB_LIST_FAIL)" >&2; exit 1
        fi
        status=""
        for a in "$@"; do
            case "$a" in status=*) status=${a#status=} ;; esac
        done
        [ -f "$STUB_DIR/runs-$status" ] && cat "$STUB_DIR/runs-$status"
        ;;
    *) echo "gh stub: unhandled: $*" >&2; exit 1 ;;
esac
exit 0
EOF
chmod +x "$T/bin/gh" || exit 1

PR_SHA=1111111111111111111111111111111111111111
OLD_SHA=2222222222222222222222222222222222222222
OTHER_SHA=3333333333333333333333333333333333333333
# The PR's head when it closed, which its commits list leaves out (as it does
# past 250 commits).
HEAD_SHA=4444444444444444444444444444444444444444

N=0
CASE=""
fresh() { # a new stub directory in $CASE, holding the PR's two commits
    N=$((N + 1))
    CASE="$T/case$N"
    mkdir "$CASE" && printf '%s\n%s\n' "$OLD_SHA" "$PR_SHA" >"$CASE/commits"
}

# run_json <id> [key=value...]: one run as the API lists it, a run the script
# should cancel unless a key=value overrides one of its fields. prs is a JSON
# array of PR numbers.
run_json() {
    local id=$1; shift
    local event=pull_request branch=feature/x path=.github/workflows/floor-a.yml
    local sha=$PR_SHA prs='[7]' status=queued repo=owner/repo kv
    for kv in "$@"; do
        case "$kv" in
            event=*) event=${kv#event=} ;;
            branch=*) branch=${kv#branch=} ;;
            path=*) path=${kv#path=} ;;
            sha=*) sha=${kv#sha=} ;;
            prs=*) prs=${kv#prs=} ;;
            status=*) status=${kv#status=} ;;
            repo=*) repo=${kv#repo=} ;;
        esac
    done
    jq -n -c --argjson id "$id" --arg event "$event" --arg branch "$branch" \
        --arg path "$path" --arg sha "$sha" --argjson prs "$prs" \
        --arg status "$status" --arg repo "$repo" \
        '{id: $id, event: $event, head_branch: $branch, path: $path, head_sha: $sha,
          status: $status, head_repository: {full_name: $repo},
          pull_requests: [$prs[] | {number: .}],
          html_url: "https://github.com/\($repo)/actions/runs/\($id)"}'
}

# add <status> <run_json args...>: list a run under the status it is queried by.
add() {
    local status=$1; shift
    run_json "$@" >>"$CASE/runs-$status"
}

RC=0
OUT=""
run() { # run [VAR=value...]: the script, over $CASE, with the PR's environment
    RC=0
    OUT=$(env PATH="$T/bin:$PATH" STUB_DIR="$CASE" \
        CHECK_MACOS_FLOOR_SETUP_DIR="$FIXTURES" \
        GITHUB_REPOSITORY=owner/repo GITHUB_RUN_ID=999 PR_NUMBER=7 \
        PR_HEAD_REF=feature/x PR_HEAD_SHA=$HEAD_SHA PR_HEAD_REPO=owner/repo DEFAULT_BRANCH=main \
        "$@" bash "$SCRIPT" 2>&1) || RC=$?
}
has() { grep -qF -- "$1" <<<"$OUT"; }
cancelled() { # the ids cancelled, sorted, on one line
    if [ -f "$CASE/cancelled" ]; then sort -n "$CASE/cancelled" | tr '\n' ' ' | sed 's/ $//'; fi
}

# guard <description> <run_json args for the run the guard keeps...>: run 1
# must be cancelled and run 2, the one the guard is about, must not be.
guard() {
    local what=$1; shift
    fresh
    add queued 1
    add queued 2 "$@"
    run
    if [ "$RC" -eq 0 ] && [ "$(cancelled)" = "1" ]; then
        pass "$what"
    else
        fail "$what (rc=$RC, cancelled: $(cancelled)): $OUT"
    fi
}

fresh
add queued 1
add in_progress 2 path=.github/workflows/floor-b.yml
add waiting 3 sha=$OLD_SHA
add pending 4
add requested 5
run
if [ "$RC" -eq 0 ] && [ "$(cancelled)" = "1 2 3 4 5" ] && has "cancelled 5 run(s)" \
    && has 'Floor workflows: ["floor-a.yml", "floor-b.yml"]'; then
    pass "queued, in-progress, waiting, pending and requested runs of every floor workflow are cancelled"
else
    fail "clean (rc=$RC, cancelled: $(cancelled)): $OUT"
fi

fresh
add queued 1 sha=$HEAD_SHA
run
if [ "$RC" -eq 0 ] && [ "$(cancelled)" = "1" ]; then
    pass "a run at the PR's closing head is cancelled even when the commits list leaves it out"
else
    fail "closing head (rc=$RC, cancelled: $(cancelled)): $OUT"
fi

fresh
add queued 1
run
if [ "$RC" -eq 0 ] && [ "$(grep -c -- '--paginate' "$CASE/calls")" -eq 6 ] \
    && [ "$(grep -c '/actions/runs ' "$CASE/calls")" -eq 5 ]; then
    pass "the commits listing and all five status listings are paginated"
else
    fail "pagination (rc=$RC, calls: $(cat "$CASE/calls")): $OUT"
fi

fresh
add queued 1 prs='[]'
run
if [ "$RC" -eq 0 ] && [ "$(cancelled)" = "1" ]; then
    pass "a merged PR's run, whose pull_requests list is empty, is cancelled"
else
    fail "empty pull_requests (rc=$RC, cancelled: $(cancelled)): $OUT"
fi

fresh
add queued 1
add in_progress 1 status=in_progress
run
if [ "$RC" -eq 0 ] && [ "$(cancelled)" = "1" ]; then
    pass "a run listed under two statuses is cancelled once"
else
    fail "duplicate run (rc=$RC, cancelled: $(cancelled)): $OUT"
fi

guard "a push run is never cancelled" event=push
guard "a schedule run is never cancelled" event=schedule
guard "a workflow_dispatch run is never cancelled" event=workflow_dispatch
guard "a run on main is never cancelled" branch=main

fresh
add queued 1 branch=feature/x
add queued 2 branch=trunk
run DEFAULT_BRANCH=trunk
if [ "$RC" -eq 0 ] && [ "$(cancelled)" = "1" ]; then
    pass "a run on a default branch other than main is never cancelled"
else
    fail "default branch trunk (rc=$RC, cancelled: $(cancelled)): $OUT"
fi

fresh
add queued 1 branch=trunk
run DEFAULT_BRANCH=trunk PR_HEAD_REF=trunk
if [ "$RC" -eq 0 ] && has "runs there are never cancelled" && [ ! -f "$CASE/calls" ]; then
    pass "a PR whose head branch is the default branch cancels nothing, before any API call"
else
    fail "head branch is the default branch (rc=$RC): $OUT"
fi
guard "a run on another branch is never cancelled" branch=feature/y
guard "a macos-floor.yml run is never cancelled" path=.github/workflows/macos-floor.yml
guard "a run of a workflow that isn't a floor workflow is never cancelled" path=.github/workflows/lint.yml
guard "a run whose pull_requests names another PR is never cancelled" 'prs=[8]'
guard "a run whose pull_requests names this PR and another is never cancelled" 'prs=[7,8]'
guard "a run at a commit that isn't this PR's (a reused branch name) is never cancelled" sha=$OTHER_SHA
guard "a run from another repository's branch of the same name is never cancelled" repo=fork/repo
guard "a finished run is never cancelled" status=completed

fresh
add queued 1
add queued 999
run
if [ "$RC" -eq 0 ] && [ "$(cancelled)" = "1" ]; then
    pass "the script's own run is never cancelled"
else
    fail "own run (rc=$RC, cancelled: $(cancelled)): $OUT"
fi

fresh
add queued 1
run PR_HEAD_REPO=fork/repo
if [ "$RC" -eq 0 ] && has "is from the fork fork/repo" && [ ! -f "$CASE/calls" ]; then
    pass "a fork PR is skipped with a log line, green, before any API call"
else
    fail "fork PR (rc=$RC, calls: $(cat "$CASE/calls" 2>/dev/null)): $OUT"
fi

fresh
add queued 1
run PR_HEAD_REPO=
if [ "$RC" -eq 0 ] && has "is from the fork (deleted)" && [ ! -f "$CASE/calls" ]; then
    pass "a PR from a deleted fork is skipped as a fork, green"
else
    fail "deleted fork (rc=$RC): $OUT"
fi

fresh
add queued 1 branch=main
run PR_HEAD_REF=main
if [ "$RC" -eq 0 ] && has "runs there are never cancelled" && [ ! -f "$CASE/calls" ]; then
    pass "a PR whose head branch is main cancels nothing, before any API call"
else
    fail "head branch main (rc=$RC): $OUT"
fi

fresh
add queued 1
add queued 2
add queued 3
echo 409 >"$CASE/cancel-fails-1"
echo 403 >"$CASE/cancel-fails-2"
run
if [ "$RC" -eq 0 ] && [ "$(cancelled)" = "3" ] && has "::warning::run 1 was not cancelled" \
    && has "::warning::run 2 was not cancelled" && has "cancelled 1 run(s), 2 not cancelled, 0 failed"; then
    pass "a cancel answered 409 or 403 is a logged warning, not a failure, and the rest still go"
else
    fail "409/403 cancel (rc=$RC, cancelled: $(cancelled)): $OUT"
fi

fresh
add queued 1
add queued 2
echo 500 >"$CASE/cancel-fails-1"
run
if [ "$RC" -eq 1 ] && [ "$(cancelled)" = "2" ] && has "cancelling run 1 failed"; then
    pass "a cancel that fails another way exits 1, after trying the rest"
else
    fail "500 cancel (rc=$RC, cancelled: $(cancelled)): $OUT"
fi

fresh
add queued 1
run STUB_LIST_FAIL=403
if [ "$RC" -eq 0 ] && has "::warning::could not list the queued runs (refused)" && [ ! -f "$CASE/cancelled" ]; then
    pass "a listing answered 403 is a logged warning, green, and cancels nothing"
else
    fail "403 listing (rc=$RC): $OUT"
fi

fresh
add queued 1
run STUB_LIST_FAIL=502
if [ "$RC" -eq 1 ] && has "could not list the queued runs" && [ ! -f "$CASE/cancelled" ]; then
    pass "a listing that fails another way exits 1 and cancels nothing"
else
    fail "502 listing (rc=$RC): $OUT"
fi

fresh
add queued 1
run STUB_COMMITS_FAIL=500
if [ "$RC" -eq 1 ] && has "could not list PR #7's commits" && [ ! -f "$CASE/cancelled" ]; then
    pass "failing to list the PR's commits exits 1 and cancels nothing"
else
    fail "commits listing (rc=$RC): $OUT"
fi

fresh
run
if [ "$RC" -eq 0 ] && has "cancelled 0 run(s)"; then
    pass "nothing unfinished is nothing to cancel, green"
else
    fail "no runs (rc=$RC): $OUT"
fi

fresh
add queued 1
run PR_NUMBER=
if [ "$RC" -eq 2 ] && has "PR_NUMBER is not set" && [ ! -f "$CASE/calls" ]; then
    pass "an incomplete environment exits 2 before any API call"
else
    fail "missing env (rc=$RC): $OUT"
fi

fresh
add queued 1
run CHECK_MACOS_FLOOR_SETUP_DIR="$T/no-such-dir"
if [ "$RC" -eq 2 ] && has "could not list the floor workflows" && [ ! -f "$CASE/calls" ]; then
    pass "floor workflows that can't be listed exit 2 before any API call"
else
    fail "no workflows (rc=$RC): $OUT"
fi

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

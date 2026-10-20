#!/usr/bin/env bash
# cancel-closed-pr-runs.sh -- cancel a closed pull request's unfinished runs of
# the macOS floor workflows.
#
# Pull requests merge without waiting for their macOS legs, and once one
# merges or closes nothing new is pushed to it, so the per-PR cancel-in-progress
# groups (shirabe#941) never reach its runs: their queued macOS jobs keep their
# place in the hosted queue (shirabe#944). cancel-closed-pr-macos-runs.yml runs
# this when a pull request closes, merged or not. A merged PR's macOS result is
# given up on purpose: macos-floor.yml, run daily and on the commit a release is
# cut from, is the post-merge macOS check.
#
# The workflows it covers are the floor workflows
# scripts/check-macos-floor-setup.sh --workflows lists, the same parse that
# gives macos-floor.yml its suites, so a new floor workflow is covered without
# an edit here. It lists the runs of the PR's head branch in every unfinished
# status and cancels a run only when all of these hold:
#
#   - its event is pull_request (never a push, schedule or workflow_dispatch);
#   - its head branch is the PR's, and not the default branch or main;
#   - its head repository is this repository;
#   - its workflow is a floor workflow, and not macos-floor.yml;
#   - its pull_requests list names no PR but this one (the list is empty once
#     a merged PR's branch is gone, so it can't be required to name this one);
#   - its head commit is the PR's head when it closed or one of the commits
#     the PR lists, so a later PR that reuses the branch name never has its
#     runs cancelled. The list stops at 250 commits, and a head that a force
#     push replaced isn't in it; those runs are left alone, which is the safe
#     side, and the cancel-in-progress groups cancel a replaced head's runs on
#     the push that replaces it;
#   - it is not this run.
#
# A fork PR's token is read-only, so for a head repository other than this one
# it logs that it skips and exits 0. A cancel answered 409 (the run finished
# meanwhile) or 403 (the token may not cancel) is logged as a warning and is
# not a failure, so a race or a token that can't cancel never turns a closed
# PR's checks red. A listing answered 403 is the same token problem seen
# earlier, and is a warning for the same reason: the warning shows on the
# run's summary page, which is where a misconfigured token is noticed. Any
# other API failure exits 1, so a broken cancel is visible.
#
# Usage: scripts/cancel-closed-pr-runs.sh
#
# Environment (the runner sets the GITHUB_ ones; cancel-closed-pr-macos-runs.yml
# sets the rest from the event and its token):
#   GITHUB_REPOSITORY   owner/repo the PR was opened against
#   GITHUB_RUN_ID       this run's id, never cancelled
#   GH_TOKEN            the job's token, for gh
#   PR_NUMBER           the closed PR's number
#   PR_HEAD_REF         its head branch
#   PR_HEAD_SHA         its head commit when it closed
#   PR_HEAD_REPO        its head repository, owner/repo; empty when the fork
#                       it came from was deleted
#   DEFAULT_BRANCH      the repository's default branch
#   CHECK_MACOS_FLOOR_SETUP_DIR
#                       passed through to check-macos-floor-setup.sh (the
#                       tests); default .github/workflows
#
# Requires gh (with GH_TOKEN), jq, and what check-macos-floor-setup.sh
# requires: mikefarah yq v4 and python3.
#
# Exit codes:
#   0 -- every matching run was cancelled, or there was nothing to cancel, or
#        the PR is from a fork, or the token may not list or cancel runs
#   1 -- an API call failed for another reason
#   2 -- the environment is incomplete, or the floor workflows could not be
#        listed

# No -e: every API call's status is read by hand, since a 403 or 409 is a
# warning rather than a failure.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "cancel-closed-pr-runs: $*" >&2; exit 2; }

for var in GITHUB_REPOSITORY GITHUB_RUN_ID PR_NUMBER PR_HEAD_REF PR_HEAD_SHA DEFAULT_BRANCH; do
    [ -n "${!var:-}" ] || die "$var is not set"
done
case "$PR_NUMBER" in ''|*[!0-9]*) die "PR_NUMBER is not a number: $PR_NUMBER" ;; esac
case "$GITHUB_RUN_ID" in ''|*[!0-9]*) die "GITHUB_RUN_ID is not a number: $GITHUB_RUN_ID" ;; esac
case "$PR_HEAD_SHA" in *[!0-9a-f]*) die "PR_HEAD_SHA is not a commit: $PR_HEAD_SHA" ;; esac
command -v gh >/dev/null 2>&1 || die "gh is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

if [ "${PR_HEAD_REPO:-}" != "$GITHUB_REPOSITORY" ]; then
    echo "PR #$PR_NUMBER is from the fork ${PR_HEAD_REPO:-(deleted)}, and a fork PR's token is read-only; nothing to cancel."
    exit 0
fi
if [ "$PR_HEAD_REF" = "$DEFAULT_BRANCH" ] || [ "$PR_HEAD_REF" = main ]; then
    echo "PR #$PR_NUMBER's head branch is $PR_HEAD_REF; runs there are never cancelled."
    exit 0
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/cancel-closed-pr-runs.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$T"' EXIT

workflows=$("$SCRIPT_DIR/check-macos-floor-setup.sh" --workflows) \
    || die "could not list the floor workflows"
echo "Floor workflows: $workflows"

# api <out> <args...>: gh api into <out>. Returns 0 on success, 3 when the
# token is refused (403) or the run already finished (409), 1 otherwise; the
# error goes to stderr either way.
api() {
    local out=$1; shift
    if gh api "$@" >"$out" 2>"$T/err"; then
        return 0
    fi
    cat "$T/err" >&2
    if grep -q 'HTTP 40[39]' "$T/err"; then
        return 3
    fi
    return 1
}

rc=0
api "$T/shas" --paginate "repos/$GITHUB_REPOSITORY/pulls/$PR_NUMBER/commits" --jq '.[].sha' || rc=$?
case $rc in
    0) echo "$PR_HEAD_SHA" >>"$T/shas" ;;
    3) echo "::warning::could not list PR #$PR_NUMBER's commits (refused); nothing cancelled"; exit 0 ;;
    *) echo "cancel-closed-pr-runs: could not list PR #$PR_NUMBER's commits" >&2; exit 1 ;;
esac

: >"$T/runs"
for status in queued in_progress waiting pending requested; do
    rc=0
    api "$T/page" --paginate -X GET "repos/$GITHUB_REPOSITORY/actions/runs" \
        -f event=pull_request -f branch="$PR_HEAD_REF" -f status="$status" -f per_page=100 \
        --jq '.workflow_runs[]' || rc=$?
    case $rc in
        0) cat "$T/page" >>"$T/runs" ;;
        3) echo "::warning::could not list the $status runs (refused); nothing cancelled"; exit 0 ;;
        *) echo "cancel-closed-pr-runs: could not list the $status runs of $PR_HEAD_REF" >&2; exit 1 ;;
    esac
done

if ! jq -s -c \
    --arg ref "$PR_HEAD_REF" --arg repo "$GITHUB_REPOSITORY" --arg default "$DEFAULT_BRANCH" \
    --argjson pr "$PR_NUMBER" --argjson self "$GITHUB_RUN_ID" \
    --argjson workflows "$workflows" \
    --rawfile shas "$T/shas" '
    ($shas | split("\n") | map(select(. != ""))) as $commits
    | unique_by(.id)[]
    | select(.status != "completed")
    | select(.event == "pull_request")
    | select(.head_branch == $ref and .head_branch != $default and .head_branch != "main")
    | select(.head_repository.full_name == $repo)
    | select(.path as $p | any($workflows[]; ".github/workflows/" + . == $p))
    | select(.path != ".github/workflows/macos-floor.yml")
    | select([.pull_requests[]?.number] | all(. == $pr))
    | select(.head_sha as $s | any($commits[]; . == $s))
    | select(.id != $self)
    | {id, path, status, head_sha, html_url}' "$T/runs" >"$T/cancel"; then
    echo "cancel-closed-pr-runs: could not read the runs listed" >&2
    exit 1
fi

cancelled=0
skipped=0
failed=0
while IFS= read -r run; do
    id=$(jq -r .id <<<"$run")
    what=$(jq -r '"\(.path | ltrimstr(".github/workflows/")) \(.status) at \(.head_sha[0:7]): \(.html_url)"' <<<"$run")
    rc=0
    api "$T/out" -X POST "repos/$GITHUB_REPOSITORY/actions/runs/$id/cancel" || rc=$?
    case $rc in
        0) echo "Cancelled run $id, $what"; cancelled=$((cancelled + 1)) ;;
        3) echo "::warning::run $id was not cancelled (finished meanwhile, or refused), $what"; skipped=$((skipped + 1)) ;;
        *) echo "cancel-closed-pr-runs: cancelling run $id failed, $what" >&2; failed=$((failed + 1)) ;;
    esac
done <"$T/cancel"

echo "PR #$PR_NUMBER: cancelled $cancelled run(s), $skipped not cancelled, $failed failed."
[ "$failed" -eq 0 ] || exit 1
exit 0

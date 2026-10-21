#!/usr/bin/env bash
# macos-floor-watchdog.sh -- notice a day with no completed macOS floor run
# on main, flag it on a tracking issue, and dispatch a floor run to replace it.
#
# macos-floor.yml runs on main from a daily schedule, and GitHub fires
# schedules late or, under load, not at all: this repository's scheduled runs
# have started between 49 minutes and over seven hours after their cron
# (shirabe#993). A red floor run files an issue on its own, but a run that
# never happens files nothing, so macos-floor-watchdog.yml runs this on a cron
# of its own and on every push to main.
#
# It reads the floor runs on main and takes the newest one titled
# "macOS floor on main" (the scheduled run, and a dispatch on main) that
# finished with a verdict, success or failure. A cancelled, timed-out or
# never-started run is not a verdict. When that run finished less than
# STALE_HOURS ago the floor is current: an open tracking issue gets a comment
# naming the run and is closed, and nothing else happens. Otherwise:
#
#   - It dispatches one floor run on main, unless a floor run on main is
#     queued or running (that run is the replacement, so it waits for it), or
#     a floor run on main was created in the last 24 hours (so it dispatches
#     at most once a day, and a run it dispatched that was cancelled is not
#     replaced before then).
#   - It files an issue titled "CI: the macOS floor run is missing" (the red
#     run's issue is macos-floor.yml's own), or comments on the open one,
#     naming the last completed run, how long ago it finished, the unfinished
#     run if any, and the dispatch if it made one. Each flag carries a hidden
#     marker naming the last completed run, so a gap already flagged is not
#     flagged again on the next fire; a dispatch is always reported.
#
# WATCHDOG_DRY_RUN=1 lists and decides, and prints what it would do without
# dispatching or touching an issue; the pull request check runs it that way.
#
# Usage: scripts/macos-floor-watchdog.sh
#
# Environment:
#   GITHUB_REPOSITORY   owner/repo (the runner sets it)
#   GH_TOKEN            the job's token, for gh: actions: write to list and
#                       dispatch runs, issues: write for the tracking issue
#   STALE_HOURS         hours since the last completed run before a day
#                       counts as missed; default 36 (a day, plus the latest
#                       start seen from GitHub's scheduler, plus the run)
#   WATCHDOG_DRY_RUN    1 to decide and print without writing; default 0
#   WATCHDOG_NOW        the current time in epoch seconds (the tests)
#
# Requires gh (with GH_TOKEN) and jq.
#
# Exit codes:
#   0 -- the floor is current, or the gap was flagged
#   1 -- an API call failed
#   2 -- the environment is incomplete

set -uo pipefail

die() { echo "macos-floor-watchdog: $*" >&2; exit 2; }
fail() { echo "macos-floor-watchdog: $*" >&2; exit 1; }

FLOOR_WORKFLOW=macos-floor.yml
# macos-floor.yml's run-name, "macOS floor on <ref>", for a scheduled run and
# a dispatch with ref=main. Rewording that run-name without this would leave
# the watchdog seeing no verdict and dispatching every day.
FLOOR_TITLE="macOS floor on main"
MISSING_TITLE="CI: the macOS floor run is missing"
STALE_HOURS=${STALE_HOURS:-36}
DRY_RUN=${WATCHDOG_DRY_RUN:-0}
NOW=${WATCHDOG_NOW:-$(date -u +%s)}

[ -n "${GITHUB_REPOSITORY:-}" ] || die "GITHUB_REPOSITORY is not set"
case "$STALE_HOURS" in ''|*[!0-9]*) die "STALE_HOURS is not a number: $STALE_HOURS" ;; esac
case "$NOW" in ''|*[!0-9]*) die "WATCHDOG_NOW is not a number: $NOW" ;; esac
case "$DRY_RUN" in 0|1) ;; *) die "WATCHDOG_DRY_RUN is not 0 or 1: $DRY_RUN" ;; esac
command -v gh >/dev/null 2>&1 || die "gh is required"
command -v jq >/dev/null 2>&1 || die "jq is required"

T=$(mktemp -d "${TMPDIR:-/tmp}/macos-floor-watchdog.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$T"' EXIT

R=$GITHUB_REPOSITORY
SERVER=${GITHUB_SERVER_URL:-https://github.com}

# The newest 100 floor runs on main: a daily run and the release dispatches
# are a few a day, so the last completed one is well inside them. A run's
# updated_at stands for when it finished, since the API gives no completed_at.
# Only a run titled "macOS floor on main" is a verdict on main; a release
# dispatch, titled after its commit, still counts as unfinished and as created,
# so it holds a dispatch back while it runs.
gh api -X GET "repos/$R/actions/workflows/$FLOOR_WORKFLOW/runs" \
    -f branch=main -f per_page=100 --jq '.workflow_runs' >"$T/runs" \
    || fail "could not list the $FLOOR_WORKFLOW runs on main"

if ! jq -c --arg title "$FLOOR_TITLE" --argjson now "$NOW" '
    def ts: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    {
      last: ([.[] | select(.display_title == $title and .status == "completed"
                and (.conclusion == "success" or .conclusion == "failure"))]
             | sort_by(.updated_at | ts) | last
             | if . == null then null
               else {id, conclusion, html_url, finished: .updated_at,
                     age_h: (($now - (.updated_at | ts)) / 3600 | floor)} end),
      unfinished: [.[] | select(.status != "completed") | {id, status, html_url, display_title}],
      recent: [.[] | select(($now - (.created_at | ts)) < 86400) | {id, created_at}]
    }' "$T/runs" >"$T/state"; then
    fail "could not read the $FLOOR_WORKFLOW runs listed"
fi

last_id=$(jq -r '.last.id // "none"' "$T/state")
last_age=$(jq -r '.last.age_h // empty' "$T/state")
last_desc=$(jq -r 'if .last == null then "none found"
    else "\(.last.html_url) (\(.last.conclusion), finished \(.last.finished), \(.last.age_h)h ago)" end' "$T/state")
unfinished=$(jq -r '.unfinished[] | "- \(.display_title), \(.status): \(.html_url)"' "$T/state")
recent=$(jq -r '.recent | length' "$T/state")
echo "Last completed floor run on main: $last_desc"

# open_issue: the number of the open issue titled exactly MISSING_TITLE, or
# nothing. It lists the open issues rather than searching them: the search
# index lags, so a watchdog run right after the one that filed the issue
# would not find it and would file a second.
open_issue() {
    gh api --paginate -X GET "repos/$R/issues" -f state=open -f per_page=100 \
        --jq '.[] | select(.pull_request == null) | {number, title}' >"$T/issues" || return 1
    jq -r -s --arg t "$MISSING_TITLE" '[.[] | select(.title == $t)] | min_by(.number).number // empty' "$T/issues"
}

number=$(open_issue) || fail "could not list the open issues"

if [ -n "$last_age" ] && [ "$last_age" -lt "$STALE_HOURS" ]; then
    echo "The floor is current: the last completed run finished ${last_age}h ago, under ${STALE_HOURS}h."
    [ -n "$number" ] || exit 0
    if [ "$DRY_RUN" = 1 ]; then
        echo "Dry run: would comment on #$number and close it."
        exit 0
    fi
    printf 'A macOS floor run on main completed: %s. Closing; a later gap opens a new issue.\n' \
        "$last_desc" >"$T/body"
    gh api -X POST "repos/$R/issues/$number/comments" -F body=@"$T/body" >/dev/null \
        || fail "could not comment on #$number"
    gh api -X PATCH "repos/$R/issues/$number" -f state=closed -f state_reason=completed >/dev/null \
        || fail "could not close #$number"
    echo "Commented on #$number and closed it."
    exit 0
fi

echo "::warning::No macOS floor run on main has completed in the last ${STALE_HOURS}h (last: $last_desc)."

dispatch=""
if [ -n "$unfinished" ]; then
    dispatch_note="Not dispatching: a floor run on main is queued or running."
elif [ "$recent" -gt 0 ]; then
    dispatch_note="Not dispatching: a floor run on main was created in the last 24 hours."
elif [ "$DRY_RUN" = 1 ]; then
    dispatch_note="Dry run: would dispatch a floor run on main."
else
    gh api -X POST "repos/$R/actions/workflows/$FLOOR_WORKFLOW/dispatches" \
        -f ref=main -f 'inputs[ref]=main' >/dev/null \
        || fail "could not dispatch $FLOOR_WORKFLOW on main"
    dispatch=1
    dispatch_note="Dispatched a floor run on main: $SERVER/$R/actions/workflows/$FLOOR_WORKFLOW"
fi
echo "$dispatch_note"

marker="<!-- macos-floor-watchdog: last-completed=$last_id -->"
{
    printf 'No macOS floor run on `main` has completed in the last %s hours.\n\n' "$STALE_HOURS"
    printf 'Last completed run: %s\n\n' "$last_desc"
    if [ -n "$unfinished" ]; then
        printf 'Unfinished floor runs on `main`:\n\n%s\n\n' "$unfinished"
    fi
    printf '%s\n\n' "$dispatch_note"
    printf 'Pull requests merge without waiting for their macOS legs, so the daily floor run is the check after merge. '
    printf 'GitHub fires the schedule late, or drops it under load; this watchdog runs every few hours and on every push to `main`.\n\n'
    printf '%s\n' "$marker"
} >"$T/body"

if [ -n "$number" ]; then
    if [ -z "$dispatch" ]; then
        gh api --paginate "repos/$R/issues/$number/comments" --jq '.[].body' >"$T/comments" \
            || fail "could not read #$number's comments"
        gh api "repos/$R/issues/$number" --jq '.body // ""' >>"$T/comments" \
            || fail "could not read #$number"
        if grep -qF -- "$marker" "$T/comments"; then
            echo "#$number already flags this gap (last completed run $last_id)."
            exit 0
        fi
    fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "Dry run: would comment on #$number."
        exit 0
    fi
    gh api -X POST "repos/$R/issues/$number/comments" -F body=@"$T/body" >/dev/null \
        || fail "could not comment on #$number"
    echo "Commented on #$number."
else
    if [ "$DRY_RUN" = 1 ]; then
        echo "Dry run: would file \"$MISSING_TITLE\"."
        exit 0
    fi
    printf '\nLater fires comment here while this issue is open, and the first completed run closes it.\n' >>"$T/body"
    gh api -X POST "repos/$R/issues" -f title="$MISSING_TITLE" -F body=@"$T/body" --jq '.html_url' \
        || fail "could not file \"$MISSING_TITLE\""
fi
exit 0

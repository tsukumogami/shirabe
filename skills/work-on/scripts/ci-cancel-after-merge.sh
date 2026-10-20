#!/usr/bin/env bash
# ci-cancel-after-merge.sh -- for /work-on: may a MERGED pull request's cancelled
# macOS floor checks count as resolved?
# Part of the work-on skill
#
# When a pull request closes, MERGED included,
# .github/workflows/cancel-closed-pr-macos-runs.yml cancels its unfinished runs
# of the macOS floor workflows (#950). macOS jobs don't gate a merge, and
# macos-floor.yml on main is the post-merge macOS check, so a MERGED pull
# request can end up with checks in gh's `cancel` bucket that nothing failed.
# ci_monitor's `ci_passing` gate counts a cancel as not green, so a run still
# watching CI when its pull request MERGED could only end at done_blocked
# (#952).
#
# koto runs this as the fallback of `ci_passing` in work-on.md, reached only
# when the gate's own filter says not green; the agent never runs it. It
# passes only when every one of these holds:
#
#   - the repository has an executable scripts/check-macos-floor-setup.sh,
#     the parse close-cancel and macos-floor.yml read their workflow lists
#     from. A repository without one (tsuku, koto, niwa) gets a quiet exit 1,
#     before any network call: its behaviour is unchanged.
#   - GitHub reports the pull request MERGED. `gh pr list --head` lists open
#     pull requests only, so a number from it means open, and exit 1.
#   - every check outside the pass and skipping buckets is in the cancel
#     bucket, and there is at least one. A pending or failed check blocks.
#   - each such check's link is an Actions run of this pull request's own
#     repository, and that run's workflow path is .github/workflows/<file>
#     with <file> in `check-macos-floor-setup.sh --workflows`. An external
#     status, another repository's run, or any other workflow blocks.
#     close-cancel cancels whole runs, so a Linux job of a floor workflow
#     still running at the merge counts too; a failed one still blocks.
#
# On a pass it records the cancelled checks, one `<name>\t<workflow>\t<link>`
# line each under a header line, in koto context as
# `ci_cancelled_after_merge.txt`, so what the run records names them. A
# failed write is exit 1, so a pass is never unrecorded.
#
# Nothing on stdout. Diagnostics go to stderr: none on the exits where the
# fallback doesn't apply (no floor script, the pull request not MERGED), and
# one line naming the first blocking check on a MERGED pull request, which is
# what the agent reads before choosing failing_unresolvable.
#
# Usage: ci-cancel-after-merge.sh <koto-session-name>
#
# Exit codes:
#   0 -- MERGED, and every non-green check is a cancelled floor-workflow run;
#        the note is recorded
#   1 -- anything else, including a missing session argument. ci_monitor's
#        edges match exit 0 and 1 only, so this script never exits otherwise.
#
# Bash 3.2: no associative arrays, no mapfile.
set -uo pipefail

no() {
    [ -z "${1:-}" ] || echo "ci-cancel-after-merge: $1" >&2
    exit 1
}

SESSION="${1:-}"
[ -n "$SESSION" ] || no "usage: ci-cancel-after-merge.sh <koto-session-name>"

TOP=$(git rev-parse --show-toplevel) || no
FLOOR="$TOP/scripts/check-macos-floor-setup.sh"
[ -x "$FLOOR" ] || no

BRANCH=$(git rev-parse --abbrev-ref HEAD) || no
OPEN=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number // empty') || no
[ -z "$OPEN" ] || no

# The current-branch lookup, the one the gate's own `gh pr checks` falls back
# to, finds a MERGED pull request.
PR=$(gh pr view --json number,state,url --jq '[.number, .state, .url] | @tsv') || no
IFS=$'\t' read -r NUMBER STATE URL <<<"$PR"
[ "$STATE" = MERGED ] || no
[ -n "$NUMBER" ] && [ -n "$URL" ] || no "could not read the pull request's number and URL"
REPO_URL="${URL%/pull/*}"
REPO="${REPO_URL#*://*/}"

CHECKS=$(gh pr checks "$NUMBER" --json bucket,name,workflow,link \
    --jq '.[] | select(.bucket != "pass" and .bucket != "skipping") | [.bucket, .name, .workflow, .link] | map(. // "" | tostring) | join("\u001f")') \
    || no "could not read the checks of #$NUMBER"
[ -n "$CHECKS" ] || no

# Fields are joined with the unit separator, not a tab: a tab is IFS
# whitespace, so an empty field (an external status has no workflow) would
# collapse and shift the ones after it.
US=$'\x1f'
RUNS=""
while IFS="$US" read -r bucket name workflow link; do
    [ "$bucket" = cancel ] || no "#$NUMBER is MERGED, but check \"$name\" is $bucket, not cancelled"
    case "$link" in
        "$REPO_URL"/actions/runs/*) ;;
        *) no "#$NUMBER is MERGED, but cancelled check \"$name\" is not an Actions run of $REPO: ${link:-no link}" ;;
    esac
    run="${link#"$REPO_URL"/actions/runs/}"
    run="${run%%/*}"
    case "$run" in
        ''|*[!0-9]*) no "#$NUMBER is MERGED, but cancelled check \"$name\" has no run id in its link: $link" ;;
    esac
    RUNS="$RUNS$run"$'\n'
done <<<"$CHECKS"

WORKFLOWS=$("$FLOOR" --workflows) || no "check-macos-floor-setup.sh --workflows failed"
LIST=$(jq -r '.[]' <<<"$WORKFLOWS") || no "check-macos-floor-setup.sh --workflows printed no JSON array"

while read -r run; do
    [ -n "$run" ] || continue
    path=$(gh api "repos/$REPO/actions/runs/$run" --jq .path </dev/null) || no "could not read run $run of $REPO"
    file="${path#.github/workflows/}"
    case "$file" in
        "$path"|*/*|'') no "#$NUMBER is MERGED, but run $run's workflow $path is not a floor workflow" ;;
    esac
    grep -qxF -- "$file" <<<"$LIST" \
        || no "#$NUMBER is MERGED, but run $run's workflow $file is not a floor workflow"
done <<<"$(sort -u <<<"$RUNS")"

{
    echo "#$NUMBER is MERGED; these macOS floor checks were cancelled and count as resolved:"
    while IFS="$US" read -r _ name workflow link; do
        printf '%s\t%s\t%s\n' "$name" "$workflow" "$link"
    done <<<"$CHECKS"
} | koto context add "$SESSION" ci_cancelled_after_merge.txt >/dev/null \
    || no "could not record ci_cancelled_after_merge.txt in koto context"

exit 0

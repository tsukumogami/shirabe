#!/usr/bin/env bash
# merge-order-entry.sh -- agent-run at surface: the block that goes under the
# merge-order table for the pull request the land check just judged, built
# from the check's own detail so the person who merges gets the evidence and
# the squash message, not a summary of them
# (docs/designs/current/DESIGN-coordinate-merge-policy.md, Decisions 4 to 6).
#
# Usage: merge-order-entry.sh --session S [--repo R]
#
# It reads the land check's verdict (the LAND capture sealed at the latest
# entry into land: `permit`, `deny`, `confirm` or `held <pr> <sha>`) and its
# detail, context key coord/land.json, and prints markdown:
#
#   **[#<pr>](https://github.com/<repo>/pull/<pr>)**, <why it is handed over>
#
#   - Review: <passes> of <seats> seats pass (<seat>, ...) at <reviewed
#     head>, recorded in the worker's run session <session> | carried in
#     the worker's report from its run session <session> (whichever the
#     land check read)
#   - Holds: none | <hold> until <condition> (<state>), ...
#   - Pauses: <id> on <scope> until <condition> (<state>), ...; let
#     through by go-ahead <id>     (only when the record holds a pause; a
#     pull request a pause holds is never handed over, so one printed here
#     is through by a go-ahead or by its condition met:
#     docs/designs/current/DESIGN-coordinate-paused-state.md, Decision 5)
#   - Squash message:
#
#     ```text
#     <title>
#
#     <Part 1 as plain text>
#     ```
#
# It refuses detail that isn't the sealed verdict's (coord/land.json's pull
# request and verdict must match it): the check rewrites both on each visit,
# so the block is for the pull request the latest land visit judged. Print it
# at that pull request's own surface visit; a table of several pull requests
# gets each block from its own visit. A detail whose verdict differs from the
# sealed one only in the posture word (permit, deny or confirm; a check run
# again read the posture afresh) is not refused: the block is worded for the
# sealed verdict, and stderr says what the detail read. Each refusal of the
# detail names the way back without leaving surface: land-check.sh --session
# S --pr N run again, then this script.
#
# The repository is the one the record's Holdings row for #<pr> links;
# --repo overrides it, for tests. The output is what you paste; don't reword
# it.
#
# Exit codes: 0 printed; 2 the capture or the detail couldn't be read, the
# detail isn't the sealed verdict's, or the verdict isn't one a merge is
# handed over on; 64 usage.
set -uo pipefail

PROG=merge-order-entry
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/board-lib.sh"

usage() { sed -n '/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
SESSION= REPO=
while [ $# -gt 0 ]; do
    case "$1" in
        --session) [ $# -ge 2 ] || usage; SESSION=$2; shift 2 ;;
        --repo) [ $# -ge 2 ] || usage; REPO=$2; shift 2 ;;
        *) usage ;;
    esac
done
bl_session_ok "$SESSION" || usage
[ -z "$REPO" ] || bl_repo_ok "$REPO" || usage

CAP=$(bl_capture "$SESSION" LAND land) || { echo "$PROG: no land verdict sealed at the latest entry into land" >&2; exit 2; }
set -f; set -- $CAP; set +f
case "${1-}" in
    permit) WHY="ready; the workspace permits the merge" ;;
    deny) WHY="ready; the workspace reserves the merge for you" ;;
    confirm) WHY="ready; the merge is behind your confirmation" ;;
    held) WHY="held; it waits on the hold below" ;;
    *) echo "$PROG: the land verdict reads [$CAP], not one a merge is handed over on" >&2; exit 2 ;;
esac
PR=$2
bl_pr_ok "$PR" || { echo "$PROG: the land verdict names no pull request" >&2; exit 2; }
if [ -z "$REPO" ]; then
    REPO=$(bl_unit_repo "$SESSION" "$PR") || { echo "$PROG: can't tell #$PR's repository from the record" >&2; exit 2; }
fi

DETAIL=$("$KOTO" context get "$SESSION" coord/land.json) || { echo "$PROG: coord/land.json couldn't be read" >&2; exit 2; }
# Every refusal of the detail names the way back, which never leaves surface:
# the check run again rewrites the detail for the sealed verdict's pull request.
RECOVER="to recover, run $HERE/land-check.sh --session $SESSION --pr $PR here at surface, then merge-order-entry.sh again"
# The detail must be this verdict's: the land check writes both on each visit.
printf '%s' "$DETAIL" | jq -e --arg pr "$PR" '.pr == $pr' >/dev/null \
    || { echo "$PROG: coord/land.json is not the detail of the sealed verdict ($1 #$PR): it is another pull request's; $RECOVER" >&2; exit 2; }
posture_word() { case "$1" in permit|deny|confirm) return 0 ;; esac; return 1; }
DV=$(printf '%s' "$DETAIL" | jq -r '.verdict | strings')
if [ "$DV" != "$1" ]; then
    # A later read of the posture can differ from the sealed one, and only the
    # word changes: the block keeps the sealed verdict's wording.
    if posture_word "$1" && posture_word "$DV"; then
        echo "$PROG: coord/land.json reads $DV where the sealed verdict is $1; the block is worded for the sealed $1" >&2
    else
        echo "$PROG: coord/land.json is not the detail of the sealed verdict ($1 #$PR): it reads [${DV}]; $RECOVER" >&2
        exit 2
    fi
fi
printf '%s' "$DETAIL" | jq -e '.evidence.status == "ok" and (.message | type) == "string"' >/dev/null \
    || { echo "$PROG: coord/land.json carries no evidence or message; the land check didn't reach them; $RECOVER" >&2; exit 2; }

printf '%s' "$DETAIL" | jq -r --arg pr "$PR" --arg repo "$REPO" --arg why "$WHY" '
    "**[#\($pr)](https://github.com/\($repo)/pull/\($pr))**, \($why)\n",
    "- Review: \(.evidence.passes) of \(.evidence.count) seats pass (\([.evidence.seats[].seat] | join(", "))) at \(.evidence.reviewed_head), "
      + (if .evidence.source == "session" then "recorded in the worker'"'"'s run session \(.evidence.session)"
         else "carried in the worker'"'"'s report from its run session \(.evidence.session)" end),
    "- Holds: " + (if ((.holds // []) | length) == 0 then "none"
                   else [.holds[] | "\(.hold) until \(.until) (\(.state))"] | join(", ") end),
    (if ((.pauses.pauses // []) | length) == 0 then empty
     else "- Pauses: " + ([.pauses.pauses[] | "\(.standing) on \(.on) until \(.until) (\(.state))"] | join(", "))
          + ((.pauses.through // {})[.pauses.unit] // null | if . == null then "" else "; let through by go-ahead \(.)" end) end),
    "- Squash message:",
    "",
    "  ```text",
    (.message | split("\n")[] | if . == "" then "" else "  " + . end),
    "  ```"'

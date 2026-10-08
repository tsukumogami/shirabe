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
#     head>, in the pull request body's Review panel section
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
# It refuses detail that isn't the sealed verdict's (coord/land.json's
# verdict and pull request must match it): the check rewrites both on each
# visit, so the block is for the pull request the latest land visit judged.
# Print it at that pull request's own surface visit; a table of several
# pull requests gets each block from its own visit.
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
# The detail must be this verdict's: the land check writes both on each visit.
printf '%s' "$DETAIL" | jq -e --arg v "$1" --arg pr "$PR" '.verdict == $v and .pr == $pr' >/dev/null \
    || { echo "$PROG: coord/land.json is not the detail of the sealed verdict ($1 #$PR)" >&2; exit 2; }
printf '%s' "$DETAIL" | jq -e '.evidence.status == "ok" and (.message | type) == "string"' >/dev/null \
    || { echo "$PROG: coord/land.json carries no evidence or message; the land check didn't reach them" >&2; exit 2; }

printf '%s' "$DETAIL" | jq -r --arg pr "$PR" --arg repo "$REPO" --arg why "$WHY" '
    "**[#\($pr)](https://github.com/\($repo)/pull/\($pr))**, \($why)\n",
    "- Review: \(.evidence.passes) of \(.evidence.count) seats pass (\([.evidence.seats[].seat] | join(", "))) at \(.evidence.reviewed_head), in the pull request body'"'"'s Review panel section",
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

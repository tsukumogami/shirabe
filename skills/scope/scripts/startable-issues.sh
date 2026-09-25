#!/usr/bin/env bash
# startable-issues.sh -- the work items of a multi-pr PLAN that can start now.
#
# A work item can start when nothing else in the PLAN blocks it: its entry in
# /plan's task graph has an empty waits_on. The graph comes from
# skills/plan/scripts/plan-to-tasks.sh, the one parser of a PLAN's dependency
# structure, so this script never re-derives a dependency itself. It only keeps
# the roots, in the order plan-to-tasks.sh emits them (PLAN order), and puts a
# title beside each.
#
# Titles are read from the PLAN's own cells and never from GitHub: this script
# makes no gh call. They are opaque data on the way to an exit report, so every
# control character in one (CR, LF, tab, and the rest of 0x00-0x1F and 0x7F) is
# replaced by a space, runs of spaces are squeezed, and the ends are trimmed. A
# title can therefore never start a line of its own in the report, and a title
# carrying `outcome=merged` stays inside its `#<N> <title>` line.
#
# Where the number and title come from:
#
#   issues table   a `| [#<N>: <title>](...) | <deps> | ... |` row of
#                  `## Implementation Issues`; the entry is `issue-<N>`.
#   outlines       an issueless PLAN (tracking_level: none), whose entries
#                  follow the `### Issue <N>: <title>` headings of
#                  `## Issue Outlines` one for one, in order.
#
# Usage:
#   startable-issues.sh <plan-path>
#
# Output: one `#<N> <title>` line per startable work item, in PLAN order.
#
# Exit codes:
#   0   printed (possibly nothing, for a PLAN whose every item waits)
#   1   the PLAN could not be read, or plan-to-tasks.sh failed
#   64  usage error
#
# Requires: bash 3.2+, jq, and what plan-to-tasks.sh requires.
set -uo pipefail

PROG=startable-issues
HERE=$(cd "$(dirname "$0")" && pwd)
PLAN_TO_TASKS="$HERE/../../plan/scripts/plan-to-tasks.sh"

[ "$#" -eq 1 ] || { echo "usage: startable-issues.sh <plan-path>" >&2; exit 64; }
PLAN="$1"
case "$PLAN" in
    -*) echo "$PROG: the plan path may not start with -" >&2; exit 64 ;;
esac
[ -f "$PLAN" ] && [ -r "$PLAN" ] || { echo "$PROG: cannot read $PLAN" >&2; exit 1; }

TASKS=$(bash "$PLAN_TO_TASKS" "$PLAN" 2>/dev/null) \
    || { echo "$PROG: plan-to-tasks.sh could not read $PLAN" >&2; exit 1; }

# clean <text> -- control characters to spaces, squeezed and trimmed.
clean() {
    printf '%s' "$1" | LC_ALL=C tr '\000-\037\177' ' ' | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'
}

# The table's titles, keyed by number: "<N>\t<title>" per row. The title is
# the text between `#<N>: ` and the closing `](` of the first cell's link, or
# the rest of the first cell when it is not a link.
table_titles() {
    awk '
        /^##[[:space:]]+Implementation[[:space:]]+Issues/ { s = 1; next }
        s && /^##[[:space:]]/ { exit }
        s && /^\|/ {
            n = split($0, cells, "|")
            if (n < 2) next
            c = cells[2]
            if (match(c, /#[0-9]+/) == 0) next
            num = substr(c, RSTART + 1, RLENGTH - 1)
            rest = substr(c, RSTART + RLENGTH)
            sub(/^:[[:space:]]*/, "", rest)
            if (index(rest, "](") > 0) rest = substr(rest, 1, index(rest, "](") - 1)
            sub(/^[[:space:]]+/, "", rest); sub(/[[:space:]]+$/, "", rest)
            printf "%s\t%s\n", num, rest
        }
    ' "$PLAN"
}

# The outline headings, in order: "<N>\t<title>".
outline_titles() {
    awk '
        /^##[[:space:]]+Issue[[:space:]]+Outlines/ { s = 1; next }
        s && /^##[[:space:]]/ { exit }
        s && /^###[[:space:]]+Issue[[:space:]]+[0-9]+/ {
            line = $0
            sub(/^###[[:space:]]+Issue[[:space:]]+/, "", line)
            num = line; sub(/[^0-9].*$/, "", num)
            title = substr(line, length(num) + 1)
            sub(/^:[[:space:]]*/, "", title)
            printf "%s\t%s\n", num, title
        }
    ' "$PLAN"
}

TABLE=$(table_titles)
OUTLINES=$(outline_titles)

# Each entry's position, name, and whether it can start, in emitted order.
ROOTS=$(printf '%s' "$TASKS" | jq -r 'to_entries[] | select((.value.waits_on // []) | length == 0) | "\(.key)\t\(.value.name)"') \
    || { echo "$PROG: plan-to-tasks.sh printed something other than a task list" >&2; exit 1; }

TAB=$(printf '\t')
printf '%s\n' "$ROOTS" | while IFS="$TAB" read -r idx name; do
    [ -n "$name" ] || continue
    case "$name" in
        issue-*)
            num="${name#issue-}"
            title=$(printf '%s\n' "$TABLE" | awk -F '\t' -v n="$num" '$1 == n { sub(/^[^\t]*\t/, ""); print; exit }')
            ;;
        *)
            row=$(printf '%s\n' "$OUTLINES" | sed -n "$((idx + 1))p")
            num="${row%%"$TAB"*}"
            title="${row#*"$TAB"}"
            ;;
    esac
    case "$num" in
        ''|*[!0-9]*) continue ;;
    esac
    printf '#%s %s\n' "$num" "$(clean "$title")"
done

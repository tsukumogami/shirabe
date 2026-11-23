#!/usr/bin/env bash
# context-size.sh -- a session's own context size, read from its transcript
# right after a compaction, with its compaction boundaries and the window in
# force.
#
# Usage:
#   scripts/context-size.sh <transcript.jsonl>
#
# Output, on stdout, one `key: value` line each, so a session can send it to
# a supervisor as text:
#
#   context_tokens: 141822
#   boundaries: 2
#   boundary_turns: 361 742
#   window: 280000
#   hard_stop: 350000
#
#   context_tokens  the input total (input_tokens plus cache_read_input_tokens
#                   plus cache_creation_input_tokens) of the newest assistant
#                   message after the latest compact_boundary record, or in
#                   the whole transcript when it has no boundary.
#   boundaries      how many compact_boundary records the transcript holds.
#   boundary_turns  the assistant turn at which each boundary fell: the number
#                   of assistant turns before it. `none` with no boundary.
#   window          CLAUDE_CODE_AUTO_COMPACT_WINDOW when it is a positive
#                   integer of at most nine digits, `invalid` when it is set
#                   to anything else (the empty string included), `unset`
#                   when it isn't set.
#   hard_stop       1.25 times the window, rounded down; printed only when
#                   the window is an integer.
#
# An assistant turn is one message id. Claude Code writes one record per
# content block, so several records can share an id; they count as one turn,
# and the figure comes from that id's last record. A record is a turn only
# when it is the main chain's (isSidechain not true), names a model other
# than `<synthetic>` (a synthetic record has no model call behind it), and
# carries a string message id and usage counts that are whole numbers below
# 10^15 (a missing count reads as 0) whose total is also below 10^15, so the
# report never holds a figure thrash-check.sh would refuse.
# Sidechain records are never boundaries either.
#
# It reads only record types, those flags and the usage integers. It prints
# no transcript text, not even a message id, and its error lines name only
# the path it was given. A line that isn't a JSON object, such as a
# half-written last line, is skipped. It reads nothing from the working
# directory, so it gives the same report from any directory, the workspace
# root included.
#
# Exit codes:
#   0  the report is printed
#   1  refused, with the path and cause named and no figure printed: no
#      argument or more than one, a missing path, a directory, anything other
#      than a regular file (a FIFO, a device), an unreadable or empty file,
#      or no qualifying assistant message after the latest boundary
#   2  an environment fault: jq is not on PATH, or jq failed
#
# bash 3.2.

set -uo pipefail

PROG=context-size.sh

refuse() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 1
}

fault() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 2
}

# Control characters in the path become `?`, so a name can't move the cursor
# or forge a line of its own.
clean() {
    printf '%s' "$1" | LC_ALL=C tr '[:cntrl:]' '?'
}

if [ "$#" -ne 1 ]; then
    refuse "usage: context-size.sh <transcript.jsonl>"
fi
path=$1
shown=$(clean "$path")

[ -n "$path" ] || refuse "no transcript path given"
if [ ! -e "$path" ]; then
    refuse "$shown: no such transcript"
fi
if [ -d "$path" ]; then
    refuse "$shown: is a directory, not a transcript"
fi
if [ ! -f "$path" ]; then
    refuse "$shown: not a regular file"
fi
if [ ! -r "$path" ]; then
    refuse "$shown: not readable"
fi
if [ ! -s "$path" ]; then
    refuse "$shown: empty transcript"
fi

if ! command -v jq >/dev/null 2>&1; then
    fault "no JSON reader: jq is not on PATH"
fi

# One pass over the transcript. The program emits integers only: the newest
# figure after the latest boundary (or the word null when there is none), the
# boundary count, then each boundary's turn.
# shellcheck disable=SC2016
PROGRAM='
def whole: type == "number" and . >= 0 and . == floor and . < 1e15;
def count: if . == null or . == 0 then 0 elif whole then . else null end;
def usage_total:
  (.input_tokens | count) as $a
  | (.cache_read_input_tokens | count) as $b
  | (.cache_creation_input_tokens | count) as $c
  | if $a == null or $b == null or $c == null then null
    else ($a + $b + $c) | (if . < 1e15 then . else null end) end;
reduce (inputs | fromjson? | select(type == "object")) as $r
  ({turns: 0, ids: {}, bounds: [], last: null};
   if ($r.isSidechain == true) then .
   elif $r.type == "system" and $r.subtype == "compact_boundary" then
     .bounds += [.turns] | .last = null
   elif $r.type == "assistant"
        and ($r.message | type) == "object"
        and ($r.message.id | type) == "string"
        and ($r.message.model | type) == "string"
        and $r.message.model != "<synthetic>"
        and ($r.message.usage | type) == "object"
        and ($r.message.usage | usage_total) != null then
     ($r.message.id) as $id
     | (if .ids[$id] then . else .turns += 1 | .ids[$id] = true end)
     | .last = ($r.message.usage | usage_total)
   else . end)
| [(if .last == null then "null" else (.last | tostring) end),
   (.bounds | length | tostring)] + (.bounds | map(tostring))
| join(" ")
'

if ! out=$(jq -n -R -r "$PROGRAM" <"$path" 2>/dev/null); then
    fault "jq could not read $shown"
fi

# shellcheck disable=SC2086
set -- $out
[ "$#" -ge 2 ] || fault "jq gave no report for $shown"
last=$1
nb=$2
shift 2

case "$last" in
null) refuse "$shown: no assistant usage after the latest compaction boundary" ;;
esac
if [[ ! $last =~ ^[0-9]+$ ]] || [[ ! $nb =~ ^[0-9]+$ ]] || [ "$#" -ne "$nb" ]; then
    fault "jq gave a malformed report for $shown"
fi

if [ "$nb" -eq 0 ]; then
    turns=none
else
    turns="$*"
fi

window=unset
hard_stop=""
if [ -n "${CLAUDE_CODE_AUTO_COMPACT_WINDOW+set}" ]; then
    w=$CLAUDE_CODE_AUTO_COMPACT_WINDOW
    if [[ $w =~ ^[1-9][0-9]{0,8}$ ]]; then
        window=$w
        hard_stop=$((w * 5 / 4))
    else
        window=invalid
    fi
fi

printf 'context_tokens: %s\n' "$last"
printf 'boundaries: %s\n' "$nb"
printf 'boundary_turns: %s\n' "$turns"
printf 'window: %s\n' "$window"
if [ -n "$hard_stop" ]; then
    printf 'hard_stop: %s\n' "$hard_stop"
fi
exit 0

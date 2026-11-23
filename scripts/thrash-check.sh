#!/usr/bin/env bash
# thrash-check.sh -- whether a session can still continue, from the report its
# own context-size.sh printed. It reads that report and never a transcript, so
# a supervisor on another host runs it on what the session sent.
#
# Usage:
#   scripts/thrash-check.sh [<report-file>]     the report on stdin when no
#                                               file is named, or with `-`
#
# The report is context-size.sh's output: the lines context_tokens,
# boundaries, boundary_turns and window, plus hard_stop when the window is an
# integer, each once, in any order. Empty lines are skipped.
#
# A session can't continue when:
#   - three of its compaction boundaries fall within 30 assistant turns: some
#     boundary_turns entry and the one two after it differ by 30 or less
#     (reason: thrash, with those three turns);
#   - context_tokens is above hard_stop (reason: hard_stop, with both figures).
# Both reasons print when both hold. With no hard_stop line only the first
# applies.
#
# Output, on stdout:
#   status: continue                                    exit 0
#   status: cant_continue                               exit 1
#   reason: thrash <turn> <turn> <turn>
#   reason: hard_stop <context_tokens> <hard_stop>
#
# It parses integers only: every figure is 0 or a positive whole number of at
# most fifteen digits with no sign or leading zero, and boundary_turns is
# `none` or such numbers separated by single spaces. A report line it can't
# use is refused with its line number and cause, never its text.
#
# Exit codes:
#   0  the session can continue
#   1  the session can't continue, with each reason named
#   2  the report is refused, with no status printed: an unreadable or
#      missing file, a line not of the form `key: value`, an unknown or
#      repeated key, a missing key, a figure that isn't an integer, a
#      boundaries count that differs from the number of boundary_turns,
#      turns out of order, a hard_stop with a window that isn't an integer
#      or none with one that is, or a report over 65,536 bytes
#
# bash 3.2.

set -uo pipefail
# Byte lengths and ASCII-only patterns.
export LC_ALL=C

PROG=thrash-check.sh
MAX_BYTES=65536
SPAN=30

refuse() {
    printf '%s: %s\n' "$PROG" "$1" >&2
    exit 2
}

is_int() {
    [[ $1 =~ ^(0|[1-9][0-9]{0,14})$ ]]
}

if [ "$#" -gt 1 ]; then
    refuse "usage: thrash-check.sh [<report-file>]"
fi
src=${1:--}
if [ "$src" != "-" ]; then
    [ -e "$src" ] || refuse "no such report file"
    [ -f "$src" ] || refuse "the report is not a regular file"
    [ -r "$src" ] || refuse "the report file is not readable"
    report=$(head -c "$((MAX_BYTES + 1))" -- "$src") || refuse "the report file could not be read"
else
    report=$(head -c "$((MAX_BYTES + 1))") || refuse "the report could not be read from stdin"
fi
if [ "${#report}" -gt "$MAX_BYTES" ]; then
    refuse "the report is over $MAX_BYTES bytes"
fi

ctx="" nb="" turns="" window="" hard=""
seen=" "
n=0
while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [ -n "$line" ] || continue
    if [[ ! $line =~ ^([a-z_]+):\ (.*)$ ]]; then
        refuse "line $n: not a key: value line"
    fi
    key=${BASH_REMATCH[1]}
    val=${BASH_REMATCH[2]}
    case "$key" in
    context_tokens | boundaries | boundary_turns | window | hard_stop) ;;
    *) refuse "line $n: unknown key" ;;
    esac
    case "$seen" in
    *" $key "*) refuse "line $n: $key appears twice" ;;
    esac
    seen="$seen$key "
    case "$key" in
    context_tokens)
        is_int "$val" || refuse "line $n: context_tokens is not an integer"
        ctx=$val
        ;;
    boundaries)
        is_int "$val" || refuse "line $n: boundaries is not an integer"
        nb=$val
        ;;
    boundary_turns)
        if [ "$val" != "none" ] && [[ ! $val =~ ^(0|[1-9][0-9]{0,14})(\ (0|[1-9][0-9]{0,14}))*$ ]]; then
            refuse "line $n: boundary_turns is not none or integers separated by single spaces"
        fi
        turns=$val
        ;;
    window)
        if [ "$val" != "invalid" ] && [ "$val" != "unset" ] && ! is_int "$val"; then
            refuse "line $n: window is not an integer, invalid or unset"
        fi
        window=$val
        ;;
    hard_stop)
        is_int "$val" || refuse "line $n: hard_stop is not an integer"
        hard=$val
        ;;
    esac
done <<<"$report"

for key in context_tokens boundaries boundary_turns window; do
    case "$seen" in
    *" $key "*) ;;
    *) refuse "the report has no $key line" ;;
    esac
done
if is_int "$window"; then
    [ -n "$hard" ] || refuse "the window is an integer but the report has no hard_stop line"
elif [ -n "$hard" ]; then
    refuse "the report has a hard_stop line but the window is not an integer"
fi

if [ "$turns" = "none" ]; then
    set --
else
    # shellcheck disable=SC2086
    set -- $turns
fi
[ "$#" -eq "$nb" ] || refuse "boundaries says $nb but boundary_turns lists $#"

# t0 and t1 are the two turns before t, so each pass sees one run of three
# boundaries in a row.
thrash=""
t0="" t1=""
for t in "$@"; do
    if [ -n "$t1" ] && [ "$t" -lt "$t1" ]; then
        refuse "boundary_turns is out of order"
    fi
    if [ -z "$thrash" ] && [ -n "$t0" ] && [ $((t - t0)) -le "$SPAN" ]; then
        thrash="$t0 $t1 $t"
    fi
    t0=$t1
    t1=$t
done

over=""
if [ -n "$hard" ] && [ "$ctx" -gt "$hard" ]; then
    over="$ctx $hard"
fi

if [ -z "$thrash" ] && [ -z "$over" ]; then
    printf 'status: continue\n'
    exit 0
fi
printf 'status: cant_continue\n'
[ -z "$thrash" ] || printf 'reason: thrash %s\n' "$thrash"
[ -z "$over" ] || printf 'reason: hard_stop %s\n' "$over"
exit 1

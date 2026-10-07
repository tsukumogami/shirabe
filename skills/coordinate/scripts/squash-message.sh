#!/usr/bin/env bash
# squash-message.sh -- build a pull request's squash commit message from its
# title and Part 1 (docs/designs/current/DESIGN-coordinate-merge-policy.md,
# Decision 4).
#
# Usage: squash-message.sh --title T <body-file|->
#
# Part 1 is everything above the body's first top-level `---` line outside a
# code fence; fence lines are dropped and their contents kept. Markdown goes:
# heading markers, blockquote markers, list markers, task boxes, table rules
# (a row's cells are joined with ", "), images (their alt text stays), bold,
# italic, code ticks and HTML comments; a link becomes `text (url)`. Runs of
# blank lines collapse to one.
#
# Prints the message on stdout: the title, a blank line, then Part 1 as plain
# text, ending in one newline. Refuses (exit 1, the reason on stderr) when
# Part 1 is empty or the message carries an attribution line, a session
# trailer or a claude.ai or anthropic.com link.
#
# Exit codes: 0 printed; 1 refused; 2 the body couldn't be read; 64 usage.
set -uo pipefail

usage() { sed -n '/^# Usage:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 64; }
TITLE= SRC=
while [ $# -gt 0 ]; do
    case "$1" in
        --title) [ $# -ge 2 ] || usage; TITLE=$2; shift 2 ;;
        -) SRC=/dev/stdin; shift ;;
        -*) usage ;;
        *) [ -z "$SRC" ] || usage; SRC=$1; shift ;;
    esac
done
[ -n "$TITLE" ] && [ -n "$SRC" ] || usage
case "$TITLE" in *"
"*) echo "squash-message: refused: the title spans lines" >&2; exit 1 ;; esac
[ "$SRC" = /dev/stdin ] || [ -r "$SRC" ] || { echo "squash-message: can't read $SRC" >&2; exit 2; }

PART1=$(jq -Rsr '
  (gsub("\r\n"; "\n") | split("\n"))
  | reduce .[] as $l ({fence: false, done: false, out: []};
      if .done then .
      elif ($l | test("^[ \t]*```")) then .fence = (.fence | not)
      elif (.fence | not) and ($l | test("^[ \t]*---[ \t]*$")) then .done = true
      else .out += [$l] end)
  | .out[]
  | sub("[ \t]+$"; "")
  | sub("^[ ]{0,3}#{1,6}[ \t]+"; "")
  | sub("^[ \t]*>[ ]?"; "")
  | sub("^[ \t]*([-*+]|[0-9]+[.)])[ \t]+"; "")
  | sub("^[ \t]*\\[[ xX]\\][ \t]+"; "")
  | select((test("^[ \t]*\\|?[ \t:|-]+\\|?[ \t]*$") and test("-") and test("\\|")) | not)
  | if test("^[ \t]*\\|") then
      sub("^[ \t]*\\|"; "") | sub("\\|[ \t]*$"; "") | split("|")
      | map(sub("^[ \t]+"; "") | sub("[ \t]+$"; "")) | map(select(. != "")) | join(", ")
    else . end
  | gsub("!\\[(?<a>[^\\]]*)\\]\\([^)]*\\)"; "\(.a)")
  | gsub("\\[(?<t>[^\\]]+)\\]\\((?<u>[^)]+)\\)"; "\(.t) (\(.u))")
  | gsub("(?<m>\\*\\*|__)(?<x>.+?)\\k<m>"; "\(.x)")
  | gsub("(?<![\\w*])\\*(?!\\s)(?<x>.+?)(?<!\\s)\\*(?![\\w*])"; "\(.x)")
  | gsub("`"; "")
  | gsub("<!--.*?-->"; "")
  | sub("[ \t]+$"; "")' "$SRC") || { echo "squash-message: the body couldn't be parsed" >&2; exit 2; }

# Collapse blank runs and trim the ends.
PART1=$(printf '%s\n' "$PART1" | awk 'NF { if (seen && blank) print ""; print; seen = 1; blank = 0; next } { blank = 1 }')
[ -n "$PART1" ] || { echo "squash-message: refused: Part 1 is empty" >&2; exit 1; }

MSG=$(printf '%s\n\n%s\n' "$TITLE" "$PART1")
BAD=$(printf '%s' "$MSG" | grep -Eio 'co-authored-by|generated with \[?claude|claude-session|https?://(www\.)?claude\.ai|anthropic\.com' | head -1)
[ -z "$BAD" ] || { echo "squash-message: refused: attribution or link in the message: $BAD" >&2; exit 1; }
printf '%s\n' "$MSG"

#!/usr/bin/env bash
#
# check-inline-evidence.sh - refuse a koto command in agent-facing text that
# passes --with-data an inline value instead of a file
#
# Agents run the koto commands a skill shows them, and under the workspace's
# rules they put a token-stripping prefix in front (`env -u GH_TOKEN koto
# ...`, `GH_TOKEN= koto ...`). Claude Code's worktree-isolation check reads a
# quoted argument after `env` as the program `env` runs, so
#     env -u GH_TOKEN koto next issue_1 --with-data '{"mode": "issue_backed"}'
# is refused ("what it runs cannot be shown not to be git"), and with
# `GH_TOKEN=` it is refused whenever the JSON holds certain words. The file
# form, `--with-data @<file>`, gives the check nothing quoted to misread and
# hands koto the same bytes.
#
# Skill text shows bare `koto` commands and the agent adds the prefix itself,
# so this check doesn't wait for a prefix to be written: a line that names
# `koto` and gives `--with-data` (or `--with-data=`) a value starting with a
# quote or `$` is refused, with or without anything in front of `koto`. That
# covers '{...}', "{\"...\"}", "$DATA" and "$(jq ...)". A value starting with
# `@` passes, and so does a mention of the flag with no value after it
# ("with or without --with-data").
#
# What is scanned is the text an agent reads and copies commands from: every
# *.md under skills/ (outside evals/, whose fixtures are data), references/
# and koto-templates/. Scripts are not: the guard sees the command an agent
# types, which for a script is its path and its own arguments, never the koto
# argv inside it. Design records under docs/ are not either; no skill loads
# them.
#
# Not seen, and left to review: a command split over lines with `\` where
# `koto` and `--with-data` land on different lines, and inline JSON handed to
# koto through a variable set on an earlier line.
#
# Usage:
#   scripts/check-inline-evidence.sh            the repository's own tree
#   scripts/check-inline-evidence.sh ROOT       the same paths under ROOT
#
# Each site is printed as path:line: text. Exit 0 when there is none, 1 when
# there is one or more, 2 on a usage error.
#
# Runs on bash 3.2: no associative arrays, no mapfile.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  -h|--help) sed -n '2,/^$/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
esac

if [ "$#" -gt 1 ]; then
  echo "usage: check-inline-evidence.sh [ROOT]" >&2
  exit 2
fi
ROOT="${1:-$SCRIPT_DIR/..}"
if [ ! -d "$ROOT" ]; then
  echo "check-inline-evidence.sh: no such directory: $ROOT" >&2
  exit 2
fi
ROOT="$(cd "$ROOT" && pwd)"

DIRS=""
for d in skills references koto-templates; do
  [ -d "$ROOT/$d" ] && DIRS="$DIRS $ROOT/$d"
done
[ -n "$DIRS" ] || exit 0

# shellcheck disable=SC2086  # DIRS is a list of paths without spaces in them
LIST=$(find $DIRS -type f -name '*.md' -not -path '*/evals/*' | LC_ALL=C sort)
[ -n "$LIST" ] || exit 0

# The single quote reaches awk as a variable, so the program needs no escape
# for it that one awk reads and another doesn't.
SITES=$(printf '%s\n' "$LIST" | tr '\n' '\0' | xargs -0 awk -v q="'" '
  BEGIN { inline = "--with-data([ \t]+|=)[" q "\"$]" }
  /(^|[^A-Za-z0-9_-])koto[ \t]/ && $0 ~ inline {
    line = $0
    sub(/^[ \t]+/, "", line)
    printf "%s:%d: %s\n", FILENAME, FNR, line
  }')

if [ -n "$SITES" ]; then
  printf '%s\n' "$SITES" | sed "s|^$ROOT/||"
  n=$(printf '%s\n' "$SITES" | wc -l | tr -d ' ')
  echo "check-inline-evidence: $n site(s) pass koto evidence inline; write it to a file and pass --with-data @<file> (see this script's header)" >&2
  exit 1
fi
exit 0

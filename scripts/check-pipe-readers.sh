#!/usr/bin/env bash
#
# check-pipe-readers.sh - refuse a shell value piped into a reader that stops
# early
#
# `printf '%s' "$OUT" | grep -q PATTERN` looks like a test of $OUT, and under
# `set -o pipefail` it is a race. grep -q exits on its first match; if printf
# has not finished writing by then, its next write fails (SIGPIPE, or EPIPE
# and an "echo: write error" where SIGPIPE is ignored), and pipefail makes
# that the pipeline's status. A match reads as no match, and `!` in front of
# it turns a real failure into a pass. A value larger than a pipe's buffer
# (64 KiB on Linux and macOS) loses the race every time; a small one loses it
# now and then, which is how shirabe#833, #846 and #849 surfaced.
#
# The fix is to give the reader the value without a pipe:
#     grep -q PATTERN <<<"$OUT"          head -c 300 <<<"$OUT"
#     case "$OUT" in *literal*) ...      [[ $OUT =~ $re ]]
#
# What is refused, on each logical line (a line ending in `\` is joined to the
# next) that is not a comment:
#   - a writer: printf, echo or cat, as a command word;
#   - piped straight into a reader that can stop before the end of its input:
#     grep given -q, -l, -L or -m (alone or in a flag cluster), --quiet,
#     --silent, --files-with-matches, --files-without-match or --max-count,
#     or head.
# The rule applies whether or not the file sets pipefail: a function is
# sourced into shells that do, and a script gains it later.
#
# Not seen, and left to review: a writer whose arguments hold a `|`, `;`, `&&`
# or a command substitution (`echo "$(cmd)" | grep -q x`); a line that ends
# in `|` with the reader on the next; a reader behind a prefix
# (`LC_ALL=C grep -q`, `command grep`, `/usr/bin/grep`) or reached through a
# variable or a function; a writer in a `{ ...; }` group; a grep whose quiet
# flag comes after a pattern holding `|`, `;`, `&` or `)`; and writers other
# than the three (git, jq, sed and the like). A quiet flag's spelling inside
# a quoted pattern (`grep -c "a -m"`) can be read as the flag; that errs
# toward a finding.
#
# Usage:
#   scripts/check-pipe-readers.sh             every tracked *.sh in the repository
#   scripts/check-pipe-readers.sh PATH...     these files, or the files under
#                                             these directories
#
# Each site is printed as path:line: text. Exit 0 when there is none, 1 when
# there is one or more, 2 on a usage error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

case "${1:-}" in
  -h|--help) sed -n '2,/^$/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
esac

files() {
  local p
  if [ "$#" -eq 0 ]; then
    git -C "$REPO_ROOT" ls-files -z -- '*.sh' | while IFS= read -r -d '' p; do
      printf '%s\n' "$REPO_ROOT/$p"
    done
    return
  fi
  for p in "$@"; do
    if [ -d "$p" ]; then
      find "$p" -type f -name '*.sh' | LC_ALL=C sort
    elif [ -f "$p" ]; then
      printf '%s\n' "$p"
    else
      echo "check-pipe-readers.sh: no such file or directory: $p" >&2
      return 2
    fi
  done
}

LIST=$(files "$@") || exit 2
[ -n "$LIST" ] || exit 0

# One awk over every file. A writer is a command word: at the start of the
# line or after ; & | ( { ! or a backtick, past any then, do, else, if, elif,
# while, until or !, so `echo` inside a message is not one. Its arguments run
# to the pipe and hold no |, ;, && or command substitution: past one of those
# the pipe belongs to another command. A grep's flags are looked for up to
# the first |, ;, & or ), so the -eq of a test after `grep -c` is not one.
SITES=$(printf '%s\n' "$LIST" | tr '\n' '\0' | xargs -0 awk '
  FNR == 1 { held = ""; start = 0 }
  {
    line = $0
    if (held != "") { line = held " " line } else { start = FNR }
    if (line ~ /\\$/) { held = substr(line, 1, length(line) - 1); next }
    held = ""
    if (line ~ /^[ \t]*#/) next
    if (line ~ /(^|[;&|(){!`])[ \t]*((then|do|else|if|elif|while|until)[ \t]+)*(![ \t]*)?(printf|echo|cat)([ \t]([^|;&$`]|&[0-9-]|\$[^(|])*)?\|[ \t]*(head([ \t)]|$)|grep[ \t]([^|;&)]*[ \t])?(-[A-Za-z]*[qlLm]|--(quiet|silent|files-with(out)?-match(es)?|max-count)))/) {
      sub(/^[ \t]+/, "", line)
      printf "%s:%d: %s\n", FILENAME, start, line
    }
  }')

if [ -n "$SITES" ]; then
  printf '%s\n' "$SITES" | sed "s|^$REPO_ROOT/||"
  n=$(printf '%s\n' "$SITES" | wc -l | tr -d ' ')
  echo "check-pipe-readers: $n site(s) pipe a value into a reader that stops early; give the reader a here-string or use case (see this script's header)" >&2
  exit 1
fi
exit 0

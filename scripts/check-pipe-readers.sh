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
#     or head, with or without variable assignments in front of it
#     (`LC_ALL=C grep -q`).
# Also refused (shirabe#906), whatever the writer: a reader that stops early
# (the same grep flags, head, or a lone `read`) as the third or a later stage
# of a pipeline, `... | sed ... | grep -q`, `... | grep ... | head -1 | cut`.
# When it exits, the stage before it takes SIGPIPE in the same way. Capture
# the middle stage first and match with a here-string, take the first line of
# a captured value with `${m%%$'\n'*}`, or let one command that reads a file
# or here-string do both: `sed -n '/re/{s///p;q;}' <<<"$v"`,
# `grep -m1 re file`.
#
# A here-string is a temporary file in bash 3.2, and one that can't be made
# skips the command, which then reads as a no match. Where that must not
# happen, keep the pipe and read the reader's own status instead: the one
# shape left alone is a pipeline that is the whole line, ends in the reader,
# and is followed on the very next line by `rc=${PIPESTATUS[<the reader's
# index>]}` (skills/coordinate/scripts/phrasing-lib.sh). That status is the
# reader's, whatever the cut-off stage got. A list around the pipeline (`||`,
# `&&`, `;`, `if`, `!`), another index, or any line in between, a comment
# included, keeps the finding.
# The rules apply whether or not the file sets pipefail: a function is
# sourced into shells that do, and a script gains it later.
#
# Not seen, and left to review: a writer whose arguments hold a `|`, `;`, `&&`
# or a command substitution (`echo "$(cmd)" | grep -q x`); a line that ends
# in `|` with the reader on the next; a reader in the second stage behind a
# program rather than printf, echo or cat (`git ls-remote | head -1`,
# `tail | grep -m1 x | cut`), which this sweep drains where it found one but
# the check leaves to review; a pipeline with no word followed by an argument
# anywhere in it (`a|b|head`), which reads as a case pattern list; a `#`
# comment at the end of a line, read as code (that errs toward a finding);
# a reader behind an assignment whose value holds a space (`X="a b" grep -q`),
# behind a command prefix (`command grep`, `env X=1 grep`, `/usr/bin/grep`)
# or reached through a variable or a function; a writer in a `{ ...; }` group; a grep whose quiet
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
#
# The second rule looks at the shape of each pipeline rather than at its
# writer. strip() blanks what the shell would not read as syntax: the inside
# of a single-quoted string, and the literal text of a double-quoted one (a
# $(...) inside double quotes is kept, since its pipes are real). `||` is set
# aside, the line is cut into pipelines at ; & ( ) and the set-aside `||`, and
# each pipeline into stages at |. A reader that can stop early, starting the
# third stage or a later one, is refused. A pipeline with no word followed by
# an argument anywhere in it (a case pattern list such as jq|grep|head) is
# skipped.
SITES=$(printf '%s\n' "$LIST" | tr '\n' '\0' | xargs -0 awk '
  function strip(t,   out, i, n, c, top, stack) {
    out = ""; n = length(t); stack = "n"
    for (i = 1; i <= n; i++) {
      c = substr(t, i, 1); top = substr(stack, length(stack), 1)
      if (top == "s") {
        if (c == "\047") { stack = substr(stack, 1, length(stack) - 1); out = out c } else out = out "x"
        continue
      }
      if (top == "d") {
        if (c == "\\") { out = out "xx"; i++; continue }
        if (c == "\"") { stack = substr(stack, 1, length(stack) - 1); out = out c; continue }
        if (c == "$" && substr(t, i + 1, 1) == "(") { stack = stack "c"; out = out "$("; i++; continue }
        out = out "x"; continue
      }
      if (c == "\\") { out = out substr(t, i, 2); i++; continue }
      if (c == "\047") { stack = stack "s"; out = out c; continue }
      if (c == "\"") { stack = stack "d"; out = out c; continue }
      if (c == "(" && top == "c") { stack = stack "c"; out = out c; continue }
      if (c == "$" && substr(t, i + 1, 1) == "(") { stack = stack "c"; out = out "$("; i++; continue }
      if (c == ")" && top == "c") { stack = substr(stack, 1, length(stack) - 1); out = out c; continue }
      out = out c
    }
    return out
  }
  function late_reader(t,   s, segs, nseg, j, stages, nst, k) {
    late_idx = -1
    s = strip(t)
    gsub(/[|][|]/, "\001", s)
    nseg = split(s, segs, "[;&()\001]")
    for (j = 1; j <= nseg; j++) {
      # A case pattern list (jq|grep|head|read) has no word followed by an
      # argument in any of its parts; a pipeline of commands does.
      if (segs[j] !~ /[^ \t|][ \t]+[^ \t|]/) continue
      nst = split(segs[j], stages, "|")
      for (k = 3; k <= nst; k++)
        if (stages[k] ~ /^[ \t]*([A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+)*(head([ \t]|$)|read([ \t]|$)|grep[ \t]([^<>]*[ \t])?(-[A-Za-z]*[qlLm]|--(quiet|silent|files-with(out)?-match(es)?|max-count)))/) {
          # PIPESTATUS counts from 0; the reader is stage k. Only a pipeline
          # that is the whole line, ending in the reader, can be excused.
          if (k == nst && nseg == 1 && segs[j] !~ /^[ \t]*(if|elif|while|until|!)[ \t]/) late_idx = k - 1
          return 1
        }
    }
    return 0
  }
  # A site of the second rule waits one line. When the pipeline is the whole
  # line, ends in the reader, and the very next line reads its own status,
  # PIPESTATUS[<its index>], pipefail decides nothing and the site is dropped.
  # Any other index or shape, or any line in between (a comment too), keeps it.
  function flush_pending() { if (pending != "") print pending; pending = "" }
  FNR == 1 { flush_pending(); held = ""; start = 0 }
  {
    line = $0
    if (held != "") { line = held " " line } else { start = FNR }
    if (line ~ /\\$/) { held = substr(line, 1, length(line) - 1); next }
    held = ""
    if (line ~ /^[ \t]*#/) { flush_pending(); next }
    if (pending != "") {
      if (pending_idx >= 0 && index(line, "PIPESTATUS[" pending_idx "]") > 0) pending = ""; else flush_pending()
    }
    if (line ~ /(^|[;&|(){!`])[ \t]*((then|do|else|if|elif|while|until)[ \t]+)*(![ \t]*)?(printf|echo|cat)([ \t]([^|;&$`]|&[0-9-]|\$[^(|])*)?\|[ \t]*([A-Za-z_][A-Za-z0-9_]*=[^ \t|;&]*[ \t]+)*(head([ \t)]|$)|grep[ \t]([^|;&)]*[ \t])?(-[A-Za-z]*[qlLm]|--(quiet|silent|files-with(out)?-match(es)?|max-count)))/) {
      sub(/^[ \t]+/, "", line)
      printf "%s:%d: %s\n", FILENAME, start, line
    } else if (late_reader(line)) {
      sub(/^[ \t]+/, "", line)
      pending = sprintf("%s:%d: %s", FILENAME, start, line); pending_idx = late_idx
    }
  }
  END { flush_pending() }')

if [ -n "$SITES" ]; then
  printf '%s\n' "$SITES" | sed "s|^$REPO_ROOT/||"
  n=$(printf '%s\n' "$SITES" | wc -l | tr -d ' ')
  echo "check-pipe-readers: $n site(s) pipe a value into a reader that stops early; give the reader a here-string or use case (see this script's header)" >&2
  exit 1
fi
exit 0

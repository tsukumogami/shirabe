#!/usr/bin/env bash
#
# check-mktemp-guards.sh - refuse an unchecked mktemp whose value a later
# cd, rm, mv, git or write acts on
#
# `T=$(mktemp -d)` leaves T empty when mktemp fails (a missing or unwritable
# TMPDIR, a full disk), and a script that doesn't notice goes on with "".
# What follows decides the damage. `cd ""` succeeds in bash and stays where
# it is, so `T=$(cd "$T" && pwd -P)` turns T into the caller's directory and
# a cleanup's `rm -rf "$T"` removes it (shirabe#924); `cd "$T" && git init &&
# git commit` commits in the caller's repository, as does `git -C "$T"`
# (shirabe#925); `rm -f "$T" "$T".*` becomes `rm -f .*` (shirabe#922); and
# `: > "$T/list"` writes at the filesystem root (shirabe#926).
#
# The fix is to stop when mktemp fails, before anything uses the value:
#     T=$(mktemp -d "${TMPDIR:-/tmp}/name.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
#     if ! T=$(mktemp -d); then ...; fi
#
# What is refused, on each logical line (a line ending in `\` is joined to the
# next) that is not a comment: an assignment whose value is a command
# substitution that runs mktemp (`X=$(mktemp ...)`, `local X=$(mktemp ...)`,
# `X=$(umask 077 && mktemp ...)`, or the backtick form), with no `||` straight
# after it (no `;`, `&` or `|` in between, so `X=$(mktemp); a || b` is
# refused) on the same logical line, and not the condition of an `if`, `while` or
# `until`, when the same file also passes $X to `cd`, `pushd` or `git -C`, or
# names a path under or built from it (`"$X/f"`, `"$X".*`, `${X}.tmp`) in an
# `rm`, `rmdir` or `mv`, a redirection (`>`, `>>`, `2>`), or a `mkdir`, `cp`,
# `touch`, `tee`, `ln` or `install`. A plain `rm -rf "$X"` is not a use: on
# an empty value it removes nothing.
#
# An assignment in a file that sets errexit (`set -e`, `set -euo pipefail`,
# `set -o errexit`) passes, since a failing mktemp then stops the script,
# unless it is `local X=$(mktemp ...)` or `export`/`readonly`/`declare X=...`,
# whose status is the builtin's and never fails.
#
# Not seen, and left to review: errexit that doesn't apply where the mktemp
# runs (a function called inside `$(...)`, after `||` or `&&`, or as an `if`
# condition, where bash ignores -e); a value passed on through another name
# (`D=$T`) or a function's output (`root=$(mk_tmp)`); a use reached through
# eval; a write by a program's own flag (`sort -o "$T/f"`, `curl -o`); and a
# check on a later line (`[ -n "$T" ] || exit 1`), or a `|`, `;` or `&` in the
# mktemp's own arguments before its `||`, which err toward a finding.
#
# Usage:
#   scripts/check-mktemp-guards.sh             every tracked *.sh in the repository
#   scripts/check-mktemp-guards.sh PATH...     these files, or the files under
#                                              these directories
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
      echo "check-mktemp-guards.sh: no such file or directory: $p" >&2
      return 2
    fi
  done
}

LIST=$(files "$@") || exit 2
[ -n "$LIST" ] || exit 0

# One awk over every file, which holds a file's logical lines until its end:
# whether an assignment is refused depends on the file's errexit and on uses
# that can come before it (a cleanup function defined above the mktemp). The
# patterns avoid \b, {n} and other forms mawk (Ubuntu's awk) and macOS awk
# don't share.
SITES=$(printf '%s\n' "$LIST" | tr '\n' '\0' | xargs -0 awk '
  function flush(   i, j, name, rest, pre, v, use, n) {
    for (i = 1; i <= na; i++) {
      name = aname[i]
      if (achecked[i]) continue
      if (errexit && !amasked[i]) continue
      v = "[$][{]?" name "([^A-Za-z0-9_]|$)"
      # A path under the value or named from it: "$X/f", $X/*, "$X".*, ${X}.tmp.
      under = "[$][{]?" name "[}]?\"?[/.]"
      use = 0
      for (j = 1; j <= nl; j++) {
        # On the line of the assignment, only what follows it.
        text = (j == aline[i]) ? aafter[i] : ltext[j]
        # Each use is one pattern; a new kind of use is one more line here,
        # with refused and fine rows for it in check-mktemp-guards.cases.
        if (text ~ ("(^|[^A-Za-z0-9_])(cd|pushd)[ \t]+(-[LP][ \t]+)?\"?" v) ||
            text ~ ("(^|[^A-Za-z0-9_.-])(rm|rmdir|mv)[ \t][^;|&]*" under) ||
            text ~ ("(^|[^A-Za-z0-9_])git[ \t]+-C[ \t]+\"?" v) ||
            text ~ ("[0-9&]?>>?[ \t]*\"?" under) ||
            text ~ ("(^|[^A-Za-z0-9_.-])(mkdir|cp|touch|tee|ln|install)[ \t][^;|&]*" under)) { use = 1; break }
      }
      if (use) {
        rest = ltext[aline[i]]
        sub(/^[ \t]+/, "", rest)
        printf "%s:%d: %s\n", file, lstart[aline[i]], rest
      }
    }
  }
  FNR == 1 {
    if (file != "") flush()
    file = FILENAME; held = ""; nl = 0; na = 0; errexit = 0
  }
  {
    line = $0
    if (held != "") { line = held " " line } else { start = FNR }
    if (line ~ /\\$/) { held = substr(line, 1, length(line) - 1); next }
    held = ""
    if (line ~ /^[ \t]*#/) next
    nl++; ltext[nl] = line; lstart[nl] = start
    if (line ~ /(^|[;&|])[ \t]*set[ \t]+-[A-Za-z]*e/ || line ~ /(^|[;&|])[ \t]*set[ \t]+-o[ \t]+errexit/) errexit = 1
    s = line
    while (match(s, /[A-Za-z_][A-Za-z0-9_]*="?([$][(][ \t]*(umask[ \t]+[0-7]+[ \t]*(&&|;)[ \t]*)?|`)mktemp([ \t)`]|$)/)) {
      pre = substr(s, 1, RSTART - 1)
      m = substr(s, RSTART, RLENGTH)
      after = substr(s, RSTART + RLENGTH)
      s = after
      # Only an assignment in command position: not inside a word or a string.
      if (pre !~ /(^|[;&|({!][ \t]*|(then|do|else|if|elif|while|until|local|export|readonly|declare([ \t]+-[A-Za-z]+)*)[ \t]+)[ \t]*$/) continue
      na++
      aname[na] = substr(m, 1, index(m, "=") - 1)
      aline[na] = nl
      aafter[na] = after
      amasked[na] = (pre ~ /(local|export|readonly|declare([ \t]+-[A-Za-z]+)*)[ \t]+$/)
      # Checked by a || that follows the substitution with no ;, & or single
      # | before it: `T=$(mktemp); a || b` is not a check on the mktemp.
      achecked[na] = (after ~ /^[^;&|]*[|][|]/ || pre ~ /(^|[;&|({!][ \t]*)(if|while|until)[ \t]+(![ \t]+)?$/)
    }
  }
  END { if (file != "") flush() }')

if [ -n "$SITES" ]; then
  printf '%s\n' "$SITES" | sed "s|^$REPO_ROOT/||"
  n=$(printf '%s\n' "$SITES" | wc -l | tr -d ' ')
  echo "check-mktemp-guards: $n site(s) use a mktemp result that was never checked; stop when mktemp fails (see this script's header)" >&2
  exit 1
fi
exit 0

#!/usr/bin/env bash
#
# check-koto-test-guard.sh - refuse a test suite that names koto without
# sourcing scripts/lib/koto-test-guard.sh first
#
# A suite that runs koto with the caller's environment can write its sessions
# to the caller's store or cloud bucket (shirabe#1288). The guard clears the
# variables that point koto there and stops the suite unless koto's session
# directory is under scratch; this check keeps every suite on it.
#
# A file is in scope when it is a *_test.sh and a line of it that is not a
# comment names koto as a word (`koto next`, `command -v koto`,
# `koto-open.sh`): one that runs koto through a script it calls counts too,
# since that script runs the same koto. In scope, the file must hold the
# guard line, at the start of a line and exactly in this shape, with the path
# relative to the suite's directory:
#
#     . "$(dirname "$0")/../../../scripts/lib/koto-test-guard.sh" || exit 1
#
# naming a koto-test-guard.sh that exists at that path, on a line before the
# first line that names koto. Not seen, and left to review: a suite that runs
# koto only through a script whose name doesn't say so, and one that never
# writes the word.
#
# A suite that holds the guard line must not set its own EXIT trap, which
# replaces the guard's and leaves its directory under TMPDIR; it hands its
# cleanup to the guard's ktg_on_exit instead. Refused: a `trap` that names
# EXIT, SIGEXIT or 0 among its signals, as any command of a line that starts
# at its first column, outside a heredoc: `trap cleanup EXIT`,
# `T=$(mktemp -d) || exit 1; trap 'rm -rf "$T"' EXIT`,
# `[ -n "$T" ] && trap ...`, `if ...; then trap ...; fi`, a quoted command
# over several lines. Left alone: an indented `trap`, such as a subshell's
# own; one in a quoted string or a comment; and `trap - EXIT`, which drops
# every exit cleanup on purpose (a KEEP_T-style switch that keeps the
# scratch directories for a look) rather than replacing the guard's.
#
# Usage:
#   scripts/check-koto-test-guard.sh             every tracked *_test.sh in the repository
#   scripts/check-koto-test-guard.sh PATH...     these files, or the *_test.sh under
#                                                these directories
#
# Each refused suite is printed as path:line: reason, at the line of its first
# koto. Exit 0 when there is none, 1 when there is one or more, 2 on a usage
# error.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

case "${1:-}" in
  -h|--help) sed -n '2,/^$/{s/^# \{0,1\}//;p;}' "$0"; exit 0 ;;
esac

GUARD_RE='^\. "\$\(dirname "\$0"\)/(([.][.]/)*(scripts/)?lib/)?koto-test-guard\.sh" \|\| exit 1$'

# Prints the line of the file's first EXIT trap, as the header describes it.
# unq() drops the quoted parts of a line and a trailing comment, and sets
# OPEN when the line ends inside a quote, so a quoted command over several
# lines is read whole. sets_exit() splits what is left into its commands.
TRAP_AWK='
function unq(s,   i, c, p, q, out) {
    q = ""; out = ""; p = " "
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (q == "") {
            if (c == "\\") { i++; p = "x"; continue }
            if (c == "#" && p ~ /[ \t;&|(]/) break
            if (c == "\047" || c == "\"") { q = c; out = out " "; p = "x"; continue }
            out = out c; p = c
        } else if (c == q) q = ""
        else if (q == "\"" && c == "\\") i++
    }
    OPEN = (q != ""); QUOTE = q
    return out
}
function sets_exit(t,   segs, n, k, s, w, m, i) {
    n = split(t, segs, /;|&&|\|\|/)
    for (k = 1; k <= n; k++) {
        s = segs[k]
        sub(/^[ \t]+/, "", s)
        while (sub(/^(then|do|else|!|\{)[ \t]+/, "", s)) {}
        if (s !~ /^trap([ \t]|$)/) continue
        m = split(s, w, /[ \t|&]+/)
        if (w[2] == "-" || w[2] == "-p" || w[2] == "-l") continue
        for (i = 2; i <= m; i++) if (w[i] ~ /^(EXIT|SIGEXIT|0)$/) return 1
    }
    return 0
}
hd != "" { l = $0; if (hdtab) sub(/^\t+/, "", l); if (l == hd) hd = ""; next }
/^[[:space:]]*#/ { next }
{
    start = NR; top = ($0 !~ /^[[:space:]]/); raw = $0; t = unq($0)
    while (OPEN && (getline more) > 0) {
        p = index(more, QUOTE)
        if (p == 0) continue
        t = t " " unq(substr(more, p + 1))
    }
    if (top && sets_exit(t)) { print start; exit }
    if (match(raw, /<<-?[ \t]*["\047]?[A-Za-z_][A-Za-z0-9_]*/) && substr(raw, RSTART - 1, 1) != "<" &&
        index(substr(raw, 1, RSTART), "((") == 0) {
        m = substr(raw, RSTART, RLENGTH); hdtab = (m ~ /^<<-/)
        sub(/^<<-?[ \t]*["\047]?/, "", m); hd = m
    }
}'

# check <file>: print the file's finding, if any; return 1 when there is one.
check() {
    local f=$1 first guard rel trap_at
    guard=$(grep -n -m1 -E "$GUARD_RE" "$f" | cut -d: -f1)
    # The guard line names koto-test-guard.sh, which is not a use of koto.
    first=$(awk '!/^[[:space:]]*#/ && !/^\. .*\/koto-test-guard\.sh" \|\| exit 1$/ &&
        /(^|[^A-Za-z0-9_])koto([^A-Za-z0-9_]|$)/ { print NR; exit }' "$f")
    if [ -n "$first" ]; then
        if [ -z "$guard" ]; then
            printf '%s:%s: names koto without sourcing scripts/lib/koto-test-guard.sh first\n' "$f" "$first"
            return 1
        fi
        if [ "$guard" -ge "$first" ]; then
            printf '%s:%s: names koto before the koto-test-guard.sh line (line %s)\n' "$f" "$first" "$guard"
            return 1
        fi
    fi
    [ -n "$guard" ] || return 0
    rel=$(sed -n "${guard}p" "$f" | sed -E 's/^\. "\$\(dirname "\$0"\)\/(.*)" \|\| exit 1$/\1/')
    if [ ! -f "$(dirname "$f")/$rel" ]; then
        printf '%s:%s: the koto-test-guard.sh line names %s, which is not there\n' "$f" "$guard" "$rel"
        return 1
    fi
    trap_at=$(awk "$TRAP_AWK" "$f")
    if [ -n "$trap_at" ]; then
        printf '%s:%s: sets its own EXIT trap, which replaces koto-test-guard.sh'"'"'s; hand the command to ktg_on_exit\n' "$f" "$trap_at"
        return 1
    fi
    return 0
}

FILES=()
if [ "$#" -eq 0 ]; then
    while IFS= read -r f; do
        FILES+=("$REPO_ROOT/$f")
    done < <(git -C "$REPO_ROOT" ls-files '*_test.sh')
else
    for p in "$@"; do
        if [ -d "$p" ]; then
            while IFS= read -r f; do
                FILES+=("$f")
            done < <(find "$p" -type f -name '*_test.sh' | LC_ALL=C sort)
        elif [ -f "$p" ]; then
            FILES+=("$p")
        else
            echo "check-koto-test-guard: no such file or directory: $p" >&2
            exit 2
        fi
    done
fi

FOUND=0
for f in ${FILES[@]+"${FILES[@]}"}; do
    out=$(check "$f") && continue
    printf '%s\n' "${out#"$REPO_ROOT"/}"
    FOUND=$((FOUND + 1))
done

if [ "$FOUND" -gt 0 ]; then
    echo "check-koto-test-guard: $FOUND suite(s) name koto without the guard or replace its EXIT trap; see scripts/lib/koto-test-guard.sh" >&2
    exit 1
fi
exit 0

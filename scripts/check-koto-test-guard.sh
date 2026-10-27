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

# check <file>: print the file's finding, if any; return 1 when there is one.
check() {
    local f=$1 first guard rel
    # The guard line names koto-test-guard.sh, which is not a use of koto.
    first=$(awk '!/^[[:space:]]*#/ && !/^\. .*\/koto-test-guard\.sh" \|\| exit 1$/ &&
        /(^|[^A-Za-z0-9_])koto([^A-Za-z0-9_]|$)/ { print NR; exit }' "$f")
    [ -n "$first" ] || return 0
    guard=$(grep -n -m1 -E "$GUARD_RE" "$f" | cut -d: -f1)
    if [ -z "$guard" ]; then
        printf '%s:%s: names koto without sourcing scripts/lib/koto-test-guard.sh first\n' "$f" "$first"
        return 1
    fi
    if [ "$guard" -ge "$first" ]; then
        printf '%s:%s: names koto before the koto-test-guard.sh line (line %s)\n' "$f" "$first" "$guard"
        return 1
    fi
    rel=$(sed -n "${guard}p" "$f" | sed -E 's/^\. "\$\(dirname "\$0"\)\/(.*)" \|\| exit 1$/\1/')
    if [ ! -f "$(dirname "$f")/$rel" ]; then
        printf '%s:%s: the koto-test-guard.sh line names %s, which is not there\n' "$f" "$guard" "$rel"
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
    echo "check-koto-test-guard: $FOUND suite(s) name koto without the guard; see scripts/lib/koto-test-guard.sh" >&2
    exit 1
fi
exit 0

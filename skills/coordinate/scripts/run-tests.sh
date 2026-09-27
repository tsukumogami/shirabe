#!/usr/bin/env bash
# run-tests.sh -- run /coordinate's script tests offline.
#
# Every *_test.sh beside this script runs with the GitHub tokens unset and
# with a PATH built from nothing but the tools skills/coordinate/requires.tsv
# declares and the POSIX utilities every script assumes (the COMMON list
# below). `gh` and `koto` on that PATH are stubs that refuse to run, so a test
# that reached the real GitHub or the real koto instead of its own stand-ins
# fails loudly rather than passing on a network read, and a script that calls
# an undeclared tool fails with "command not found". Engine suites
# (*_engine_test.sh), which drive real koto on purpose, get the real koto;
# they are selected with --engine.
#
# Usage: bash skills/coordinate/scripts/run-tests.sh [--engine]
# Exit codes: 0 every suite passed; 1 a suite failed.
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ENGINE=0
[ "${1-}" = --engine ] && ENGINE=1

T=$(mktemp -d "${TMPDIR:-/tmp}/coordinate-tests.XXXXXX")
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/stubs"
for tool in gh koto; do
    printf '#!/bin/sh\necho "offline: a test reached the real %s; use a stand-in" >&2\nexit 97\n' "$tool" > "$T/stubs/$tool"
    chmod +x "$T/stubs/$tool"
done
[ "$ENGINE" = 1 ] && rm -f "$T/stubs/koto"

# The restricted PATH: declared tools plus the POSIX utilities.
COMMON="bash sh env cat sed awk grep head tail tr cut wc sort uniq diff cmp mktemp rm
mkdir cp mv ln chmod date basename dirname printf test true false dd od xargs tee
touch ls base64 sha256sum shasum sleep find expr id uname readlink realpath"
mkdir -p "$T/path"
DECLARED=$(awk -F'\t' '!/^#/ && NF > 1 { print $1 }' "$HERE/../requires.tsv" | sort -u)
for tool in $COMMON $DECLARED; do
    [ -e "$T/stubs/$tool" ] && continue
    [ "$tool" = koto ] && [ "$ENGINE" = 0 ] && continue
    p=$(command -v "$tool" 2>/dev/null) || continue
    case "$p" in /*) ln -sf "$p" "$T/path/$tool" ;; esac
done

rc=0
n=0
for t in "$HERE"/*_test.sh; do
    [ -e "$t" ] || continue
    case "$t" in
        *_engine_test.sh) [ "$ENGINE" = 1 ] || continue ;;
        *) [ "$ENGINE" = 1 ] && continue ;;
    esac
    n=$((n + 1))
    echo "== $(basename "$t")"
    if ! env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN \
        PATH="$T/stubs:$T/path" "$T/path/bash" "$t"; then
        rc=1
    fi
done
echo "run-tests: $n suites"
exit $rc

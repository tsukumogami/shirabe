#!/usr/bin/env bash
# run-suites.sh -- run shell suites in turn and fail when any of them failed.
#
# The plain steps of .github/workflows/check-koto-entry-floor.yml call this
# with their suite lists, so the rule below lives in one place. Every suite
# runs, whatever the ones before it did, so one run reports every failing
# suite. A suite fails when it exits non-zero, or when its output says
# "command not found": a missing command prints that to stderr and the suite
# carries on, so a case built on it can pass having checked nothing
# (shirabe#1330). skills/coordinate/scripts/run-tests.sh holds /coordinate's
# suites to the same rule.
#
# Usage: bash scripts/run-suites.sh <suite>...
# Exit codes: 0 every suite passed; 1 a suite failed; 2 usage.
set -uo pipefail

if [ "$#" -eq 0 ]; then
    echo "usage: run-suites.sh <suite>..." >&2
    exit 2
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/run-suites.XXXXXX") || { echo "run-suites: no temporary directory" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

failed=
for t in "$@"; do
    echo "== $t"
    bash "$t" >"$T/out" 2>&1
    st=$?
    cat "$T/out"
    bad=0
    if [ $st -ne 0 ]; then
        echo "run-suites: $t exited $st"
        bad=1
    fi
    if grep -q 'command not found' "$T/out"; then
        echo "run-suites: $t ran a command that isn't on PATH:"
        grep 'command not found' "$T/out" | sed 's/^/    /'
        bad=1
    fi
    [ $bad -eq 0 ] || failed="$failed $t"
done
echo "run-suites: $# suites"
if [ -n "$failed" ]; then
    echo "run-suites: failed:$failed"
    exit 1
fi

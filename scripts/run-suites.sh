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
# With SUITE_SLICE=i/n set (a CI matrix job), only slice i of the named suites
# runs, chosen by scripts/lib/suite-slice.sh and balanced by the cost table
# SUITE_SLICE_COSTS names, if any; the n slices together run every suite once,
# and the closing count line names the slice. Unset or empty, every suite runs.
#
# Usage: bash scripts/run-suites.sh <suite>...
# Exit codes: 0 every suite passed; 1 a suite failed; 2 usage, or a
# SUITE_SLICE or cost table the selector refuses.
set -uo pipefail

if [ "$#" -eq 0 ]; then
    echo "usage: run-suites.sh <suite>..." >&2
    exit 2
fi

HERE=$(cd "$(dirname "$0")" && pwd)
TOTAL=$#
# This job's slice of the named suites, one per line; the whole list when no
# slice is set.
SELECTED=$(printf '%s\n' "$@" | bash "$HERE/lib/suite-slice.sh" run-suites.sh) || exit $?

T=$(mktemp -d "${TMPDIR:-/tmp}/run-suites.XXXXXX") || { echo "run-suites: no temporary directory" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

failed=
n=0
# One suite path per line; split on newlines only, with globbing off for the
# split so a path is taken as written. The list is expanded once, when the
# loop starts, so the body puts IFS and globbing back at once.
OLD_IFS=$IFS
IFS='
'
set -f
for t in $SELECTED; do
    IFS=$OLD_IFS
    set +f
    n=$((n + 1))
    echo "== $t"
    # The slice is this runner's: a suite that is itself a runner sees none,
    # so nothing is sliced twice.
    env -u SUITE_SLICE -u SUITE_SLICE_COSTS bash "$t" >"$T/out" 2>&1
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
IFS=$OLD_IFS
set +f
if [ -n "${SUITE_SLICE:-}" ]; then
    echo "run-suites: $n of $TOTAL suites (slice $SUITE_SLICE)"
else
    echo "run-suites: $n suites"
fi
if [ -n "$failed" ]; then
    echo "run-suites: failed:$failed"
    exit 1
fi

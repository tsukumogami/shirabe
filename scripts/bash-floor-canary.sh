#!/usr/bin/env bash
#
# bash-floor-canary.sh - the #283 regression, kept as a fixture
#
# THIS SCRIPT IS EXPECTED TO FAIL UNDER BASH 3.2 AND TO PASS UNDER BASH 4+.
# That asymmetry is the point: it is what scripts/check-bash-floor_test.sh
# asserts, and it is how the floor runner proves it can still see the class of
# bug that motivated it. It is not part of any suite, and CI never runs it
# directly - only through the runner's own test.
#
# The bug: #283 had plan-to-tasks.sh read one record per line with the fields
# joined by U+0001, and split them back apart with `IFS=$'\001' read`. Under
# bash 4+ that yields three fields. Under bash 3.2 it does not split at all:
# the whole record lands in the first variable, separators and all, and the
# other two come back empty. No error, no diagnostic - and because a terminal
# renders U+0001 as nothing, the first variable just looks like the fields run
# together. The next thing that fails is a slug three functions away.
#
# Usage: bash scripts/bash-floor-canary.sh
#
# Exit codes:
#   0 - U+0001 field splitting works here (bash 4+)
#   1 - it does not (bash 3.2, the floor)

set -euo pipefail

record=$(printf '1\001plan-to-tasks\001Make the floor checkable')

number=""
slug=""
title=""
IFS=$'\001' read -r number slug title <<< "$record"

if [ "$number" = "1" ] && [ "$slug" = "plan-to-tasks" ] && [ "$title" = "Make the floor checkable" ]; then
    echo "PASS: U+0001 record split into 3 fields (bash ${BASH_VERSION})"
    exit 0
fi

# A raw U+0001 renders as nothing, which is what made the original defect look
# like the fields had run together. Show it.
visible() {
    printf '%s' "${1//$'\001'/<U+0001>}"
}

echo "FAIL: U+0001 record did not split (bash ${BASH_VERSION})" >&2
printf 'FAIL:   number=[%s]\n' "$(visible "$number")" >&2
printf 'FAIL:   slug=[%s]\n' "$(visible "$slug")" >&2
printf 'FAIL:   title=[%s]\n' "$(visible "$title")" >&2
echo "FAIL: bash 3.2 does not split on U+0001 here: the whole record lands in" >&2
echo "FAIL: the first variable and the rest come back empty. This is #283." >&2
exit 1

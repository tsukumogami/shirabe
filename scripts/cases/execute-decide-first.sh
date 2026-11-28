#!/usr/bin/env bash
# execute-decide-first.sh -- the script case for /execute's decide_first.
#
# Usage: scripts/cases/execute-decide-first.sh routes
#
# routes runs skills/execute/scripts/decide-first-routes_test.sh: the edges
# into decide_first against its exits table, park_own and the parking
# states, the waiting terminal's result, park.sh and the parked-state
# codes, and, when the base branch can be read, every other state as it
# was before.
#
# scripts/lib/script-cases.py runs it from the repository root in a closed
# environment. The suite skips its template cases when koto is absent and
# its comparisons when no base branch is readable.
#
# Exit codes: the suite's (0 pass, 1 fail), 2 usage.

set -uo pipefail
[ "$#" -eq 1 ] && [ "$1" = routes ] || { echo "usage: execute-decide-first.sh routes"; exit 2; }
exec bash "$(dirname "$0")/../../skills/execute/scripts/decide-first-routes_test.sh"

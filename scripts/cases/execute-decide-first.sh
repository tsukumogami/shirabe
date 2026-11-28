#!/usr/bin/env bash
# execute-decide-first.sh -- the script case for /execute's decide_first.
#
# Usage: scripts/cases/execute-decide-first.sh <routes|walk>
#
# routes runs skills/execute/scripts/decide-first-routes_test.sh: the edges
# into decide_first against its exits table, park_own and the parking
# states, the waiting terminal's result, park.sh and the parked-state
# codes, and, when the base branch can be read, every other state as it
# was before. walk runs skills/execute/scripts/park-walk_test.sh: a parked
# child walked through real koto from its question to its answer, the
# dependent step re-created and run, and the answers that carry no
# authority refused. Each is its own case, so each has the runner's whole
# timeout.
#
# scripts/lib/script-cases.py runs it from the repository root in a closed
# environment. The routes suite skips its template cases when koto is
# absent, and its comparisons when no base branch is readable (failing
# instead under CI). The walk finds shirabe as SHIRABE_BIN, the tree's
# target/release/shirabe (scripts/check-skill.sh builds it) or PATH, and
# skips when koto is absent.
#
# Exit codes: the suite's (0 pass, 1 fail), 2 usage.

set -uo pipefail
[ "$#" -eq 1 ] || { echo "usage: execute-decide-first.sh <routes|walk>"; exit 2; }
case "$1" in
    routes) exec bash "$(dirname "$0")/../../skills/execute/scripts/decide-first-routes_test.sh" ;;
    walk) exec bash "$(dirname "$0")/../../skills/execute/scripts/park-walk_test.sh" ;;
    *) echo "usage: execute-decide-first.sh <routes|walk>"; exit 2 ;;
esac

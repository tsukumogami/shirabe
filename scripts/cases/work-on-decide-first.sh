#!/usr/bin/env bash
# work-on-decide-first.sh -- the script cases for /work-on's decide_first.
#
# Usage: scripts/cases/work-on-decide-first.sh <gate|routes>
#
# gate runs skills/work-on/scripts/decide-first-gate_test.sh, the gate script
# on its own against prepared records; routes runs
# skills/work-on/scripts/decide-first-routes_test.sh, the ten covered exits,
# the waiting terminal and a continued run through the shipped work-on.md.
# Each is its own case, so each has the runner's whole timeout.
#
# scripts/lib/script-cases.py runs it from the repository root in a closed
# environment. The suites find shirabe as SHIRABE_BIN, the tree's
# target/release/shirabe (scripts/check-skill.sh builds it) or PATH, and skip
# every case when koto is absent.
#
# Exit codes: the suite's (0 pass, 1 fail), 2 usage.

set -uo pipefail
[ "$#" -eq 1 ] || { echo "usage: work-on-decide-first.sh <gate|routes>"; exit 2; }
case "$1" in
    gate|routes) ;;
    *) echo "usage: work-on-decide-first.sh <gate|routes>"; exit 2 ;;
esac
exec bash "$(dirname "$0")/../../skills/work-on/scripts/decide-first-$1_test.sh"

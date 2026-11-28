#!/usr/bin/env bash
# scope-decide-first.sh -- the script case for /scope's decide_first.
#
# Usage: scripts/cases/scope-decide-first.sh routes
#
# routes runs skills/scope/scripts/decide-first-routes_test.sh: the five
# edges into decide_first, its raised, resume and stop routes, waiting_record
# and its way out, done_waiting's result, and, when the base branch can be
# read, every other state as it was before.
#
# scripts/lib/script-cases.py runs it from the repository root in a closed
# environment. The suite skips every case when koto or jq is absent and its
# comparisons when no base branch is readable.
#
# Exit codes: the suite's (0 pass, 1 fail), 2 usage.

set -uo pipefail
[ "$#" -eq 1 ] && [ "$1" = routes ] || { echo "usage: scope-decide-first.sh routes"; exit 2; }
exec bash "$(dirname "$0")/../../skills/scope/scripts/decide-first-routes_test.sh"

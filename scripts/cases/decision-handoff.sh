#!/usr/bin/env bash
# decision-handoff.sh -- the script case for a skill's hand-off to /decision.
#
# Usage: scripts/cases/decision-handoff.sh <caller>
#
# <caller> is decision, design or explore: the skill whose evals.json keeps
# the case. It runs skills/decision/scripts/undecided-result_test.sh with the
# caller named, so the suite adds the hand-off from that caller's own session
# (a /decision nobody called raises from decision-<topic>, /design from
# design-<topic>, /explore from explore-<topic>) on top of its shared cases:
# the attempt record, check-undecided.sh, the raise and the consumer list.
#
# scripts/lib/script-cases.py runs it from the repository root in a closed
# environment. The suite finds shirabe as SHIRABE_BIN, the tree's
# target/release/shirabe (scripts/check-skill.sh builds it) or PATH.
#
# Exit codes: the suite's (0 pass, 1 fail, 2 usage).

set -uo pipefail
case "${1:-}" in
    decision|design|explore) ;;
    *) echo "usage: decision-handoff.sh <decision|design|explore>"; exit 2 ;;
esac
[ "$#" -eq 1 ] || { echo "usage: decision-handoff.sh <decision|design|explore>"; exit 2; }
exec bash "$(dirname "$0")/../../skills/decision/scripts/undecided-result_test.sh" "$1"

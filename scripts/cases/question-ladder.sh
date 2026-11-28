#!/usr/bin/env bash
# question-ladder.sh -- the script case for a coordinator's questions passed up
# the ladder by identity.
#
# Usage: scripts/cases/question-ladder.sh
#
# It runs skills/coordinate/scripts/question-ladder_engine_test.sh: pass-up
# from a manager to its director, the owner's answers a coordinator hasn't
# seen, seen, settling a sibling question on the owner's precedent, and a
# relayed claim recorded as the coordinator's own word. The suite runs
# against the real koto and the branch's shirabe.
#
# scripts/lib/script-cases.py runs it from the repository root in a closed
# environment. The suite finds shirabe as SHIRABE_BIN, the tree's
# target/release/shirabe (scripts/check-skill.sh builds it) or PATH, and
# fails when none has `shirabe question pass-up`. It SKIPs (exit 0) when koto
# isn't on PATH.
#
# Exit codes: the suite's (0 pass, 1 fail), 2 usage.

set -uo pipefail
[ "$#" -eq 0 ] || { echo "usage: question-ladder.sh"; exit 2; }
exec bash "$(dirname "$0")/../../skills/coordinate/scripts/question-ladder_engine_test.sh"

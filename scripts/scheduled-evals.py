#!/usr/bin/env python3
"""scheduled-evals.py - retired. It runs nothing.

This script used to run model-graded evals on a schedule, under a weekly
cap. Decision 1 of docs/designs/current/DESIGN-skill-regression-detection.md retires
graded runs: the eval harness runs script-graded cases only and refuses every
graded case. So this script starts no process, reads and writes no ledger, and
looks at none of its arguments or its environment. Whatever it is given, it
prints one line to stderr and exits 3, as `scripts/run-evals.sh --prep-only`
does.

What runs a skill's cases now is `scripts/run-evals.sh <skill>`, which runs the
skill's script cases and lists each graded case as refused.

The file keeps its name so its test suite runs where it always has.
"""

import sys

REFUSAL = (
    "scheduled-evals.py: scheduled eval runs are retired, and graded cases "
    "don't run; scripts/run-evals.sh <skill> runs a skill's script cases"
)


def main():
    sys.stderr.write(REFUSAL + "\n")
    return 3


if __name__ == "__main__":
    sys.exit(main())

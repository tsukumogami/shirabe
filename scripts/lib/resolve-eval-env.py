#!/usr/bin/env python3
"""resolve-eval-env.py -- make a tier-2 eval's declared log paths absolute.

An eval may declare extra environment for its run in evals.json (`env`, a
flat map of names to string values): a call log for the gh or koto shim, a CI
wait limit. A log path is written relative to the scenario's working
directory, the isolated checkout. Passed through as written, it resolves
against whatever directory each command runs in, and a coordinated run works
in node worktrees: a gh call made there lands in a stray log the grader never
reads, and the shim's state directory beside it (`$GH_CALL_LOG.d`) starts
empty. So every variable whose name ends in `_LOG` and whose value is a
relative path is joined to the working directory here, once, before the
session is told to set it. Other values pass through unchanged.

Usage: resolve-eval-env.py <workdir> < env.json
    Reads the env object as JSON on stdin and prints the resolved object.
    Exit 0 on success, 2 on usage or input that is not a JSON object.

scripts/run-evals.sh loads `resolve()` from this file directly.
"""

import json
import os
import sys


def resolve(env, workdir):
    """Return env with each relative *_LOG value joined to workdir."""
    out = {}
    for name, value in env.items():
        if (workdir and name.endswith("_LOG") and isinstance(value, str)
                and value and not os.path.isabs(value)):
            value = os.path.normpath(os.path.join(workdir, value))
        out[name] = value
    return out


def main(argv):
    if len(argv) != 2 or not argv[1]:
        print("usage: resolve-eval-env.py <workdir> < env.json", file=sys.stderr)
        return 2
    try:
        env = json.load(sys.stdin)
    except ValueError as exc:
        print(f"resolve-eval-env: input is not JSON: {exc}", file=sys.stderr)
        return 2
    if not isinstance(env, dict):
        print("resolve-eval-env: input is not a JSON object", file=sys.stderr)
        return 2
    json.dump(resolve(env, argv[1]), sys.stdout, sort_keys=True)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

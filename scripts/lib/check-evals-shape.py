#!/usr/bin/env python3
"""check-evals-shape.py - check the shape of a skill's evals/evals.json.

Usage: scripts/lib/check-evals-shape.py <evals.json> <SKILL.md>

The pull request gate (scripts/check-skill.sh) runs this on every changed
skill. It checks the file the eval harness reads without running it:

  - the file parses as JSON and is an object with an `evals` list;
  - every entry under `evals` has a non-empty `name` and a non-empty `prompt`;
  - every entry has at least one of `expectations` or `assertions` as a
    non-empty list. Both shapes are in use across the suites.

A skill with no evals.json passes only when its SKILL.md declares
`disable-model-invocation: true`, read the way scripts/check-evals-exist.sh
reads it (the phrase anywhere in the file). Otherwise the missing file fails.

Each failure is printed on stderr, naming the file and the eval (by `name`
when it has one, else by its position).

Standard library only.

Exit codes:
  0 - the file is sound, or absent from a reference-only skill
  1 - the file is malformed or missing; every problem is printed
  2 - usage error
"""

import json
import os
import sys


def non_empty_string(value):
    return isinstance(value, str) and value.strip() != ""


def non_empty_list(value):
    return isinstance(value, list) and len(value) > 0


def exempt(skill_md):
    try:
        with open(skill_md, encoding="utf-8", errors="replace") as fh:
            return "disable-model-invocation: true" in fh.read()
    except OSError:
        return False


def label(index, entry):
    if isinstance(entry, dict) and non_empty_string(entry.get("name")):
        return "eval %r (#%d)" % (entry["name"], index + 1)
    return "eval #%d" % (index + 1)


def check(path):
    problems = []
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except ValueError as exc:
        return ["%s: invalid JSON: %s" % (path, exc)]
    except OSError as exc:
        return ["%s: cannot read: %s" % (path, exc.strerror)]

    if not isinstance(data, dict):
        return ["%s: top level is not a JSON object" % path]
    evals = data.get("evals")
    if not non_empty_list(evals):
        return ["%s: `evals` is missing or not a non-empty list" % path]

    for index, entry in enumerate(evals):
        where = "%s: %s" % (path, label(index, entry))
        if not isinstance(entry, dict):
            problems.append("%s: not a JSON object" % where)
            continue
        if not non_empty_string(entry.get("name")):
            problems.append("%s: missing or empty `name`" % where)
        if not non_empty_string(entry.get("prompt")):
            problems.append("%s: missing or empty `prompt`" % where)
        if not (non_empty_list(entry.get("expectations"))
                or non_empty_list(entry.get("assertions"))):
            problems.append(
                "%s: needs a non-empty `expectations` or `assertions` list" % where)
    return problems


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: check-evals-shape.py <evals.json> <SKILL.md>\n")
        return 2
    evals_path, skill_md = argv[1], argv[2]

    if not os.path.exists(evals_path):
        if exempt(skill_md):
            print("%s: absent; %s declares disable-model-invocation: true"
                  % (evals_path, skill_md))
            return 0
        sys.stderr.write(
            "%s: missing; every skill without disable-model-invocation: true "
            "needs at least one eval\n" % evals_path)
        return 1

    problems = check(evals_path)
    for problem in problems:
        sys.stderr.write(problem + "\n")
    if problems:
        return 1
    print("%s: shape ok" % evals_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""check-evals-shape.py - check the shape of a skill's evals/evals.json.

Usage: scripts/lib/check-evals-shape.py <evals.json> <SKILL.md>

The pull request gate (scripts/check-skill.sh) runs this on every changed
skill. It checks the file the eval harness reads without running it:

  - the file parses as JSON and is an object with an `evals` list;
  - every entry under `evals` has a non-empty `name` and a non-empty `prompt`;
  - every entry has at least one of `expectations` or `assertions` as a
    non-empty list. Both shapes are in use across the suites;
  - except a script-graded entry (`"grader": "script"`), which needs a
    non-empty `name`, `run` (the command scripts/lib/script-cases.py runs)
    and `handoff` (the skill it checks the hand-off to), and no `prompt` or
    criteria;
  - `tier`, when present, is 1 or 2; every reader takes tier-2 as any tier
    other than 1, so no other value is let through;
  - every tier-2 entry (`tier` other than 1) names the behaviour it exercises
    in `behaviour`, a kebab-case slug, and each behaviour has exactly one entry
    with `"release": true`: the scenario the release eval check runs for it
    (scripts/run-evals.sh --release-subset). The scheduled runs rotate through
    the rest (scripts/scheduled-evals.py). `release` is only ever `true`, and
    a tier-1 entry carries neither key: every tier-1 scenario runs at release.

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
import re
import sys

SLUG = re.compile(r"^[a-z0-9][a-z0-9-]*$")


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
        elif "," in entry["name"]:
            # scripts/run-evals.sh --scenario takes a comma-separated list.
            problems.append("%s: `name` can't contain a comma" % where)
        if entry.get("grader") == "script":
            # A script-graded case runs a command, not a prompt: it needs the
            # command and the skill it hands off to, and no criteria.
            for key in ("run", "handoff"):
                if not non_empty_string(entry.get(key)):
                    problems.append("%s: a `grader: script` case needs a non-empty `%s`"
                                    % (where, key))
            if not tier_ok(entry):
                problems.append("%s: `tier` is 1 or 2 (absent means 1), not %s"
                                % (where, json.dumps(entry.get("tier"))))
            continue
        if not non_empty_string(entry.get("prompt")):
            problems.append("%s: missing or empty `prompt`" % where)
        if not tier_ok(entry):
            # Every reader takes tier-2 as `tier` other than 1 (scripts/run-evals.sh,
            # scripts/scheduled-evals.py, the release subset below), so a tier of
            # 3 or "2" would be read as tier-2 by some and not others: refuse it.
            problems.append("%s: `tier` is 1 or 2 (absent means 1), not %s"
                            % (where, json.dumps(entry.get("tier"))))
        if not (non_empty_list(entry.get("expectations"))
                or non_empty_list(entry.get("assertions"))):
            problems.append(
                "%s: needs a non-empty `expectations` or `assertions` list" % where)
    problems.extend(check_release_subset(path, evals))
    return problems


def tier_ok(entry):
    """`tier` is absent, 1 or 2; a boolean is neither, though Python's True == 1."""
    tier = entry.get("tier", 1)
    return not isinstance(tier, bool) and tier in (1, 2)


def check_release_subset(path, evals):
    """Each tier-2 behaviour has exactly one release scenario."""
    problems = []
    releases = {}
    for index, entry in enumerate(evals):
        if not isinstance(entry, dict):
            continue
        where = "%s: %s" % (path, label(index, entry))
        if not tier_ok(entry):
            continue  # refused above; its release keys would only repeat it
        tier2 = entry.get("tier", 1) != 1
        behaviour = entry.get("behaviour")
        if "release" in entry and entry["release"] is not True:
            problems.append("%s: `release` is only ever `true`" % where)
        if not tier2:
            if "behaviour" in entry or "release" in entry:
                problems.append("%s: `behaviour` and `release` belong on tier-2 entries; "
                                "every tier-1 scenario runs at release" % where)
            continue
        if not (isinstance(behaviour, str) and SLUG.match(behaviour)):
            problems.append("%s: a tier-2 entry needs a kebab-case `behaviour` naming what it "
                            "exercises" % where)
            continue
        releases.setdefault(behaviour, [])
        if entry.get("release") is True:
            releases[behaviour].append(label(index, entry))
    for behaviour, picked in sorted(releases.items()):
        if len(picked) != 1:
            problems.append("%s: behaviour %r needs exactly one `\"release\": true` entry, "
                            "has %d%s" % (path, behaviour, len(picked),
                                          (": " + ", ".join(picked)) if picked else ""))
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

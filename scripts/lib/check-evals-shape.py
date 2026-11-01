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
    and `handoff` (the skill it checks the hand-off to), and carries no
    `prompt` and no `expectations`;
  - a script entry's `run` passes the rules scripts/lib/script-cases.py
    applies before it executes a case, checked by the same function
    (containment) against the repository two directories above the skill's
    directory, so both refuse a case with the same rule text;
  - a script entry whose `run` is `scripts/check-handoff.sh <from> <to>`
    has <from> the skill whose file holds it and <to> its `handoff`;
  - `tier`, when present, is 1 or 2; every reader takes tier-2 as any tier
    other than 1, so no other value is let through;
  - every tier-2 entry (`tier` other than 1) names the behaviour it exercises
    in `behaviour`, a kebab-case slug, and each behaviour has exactly one entry
    with `"release": true`: the scenario the release eval check runs for it
    (scripts/run-evals.sh --release-subset). The scheduled runs rotate through
    the rest (scripts/scheduled-evals.py). `release` is only ever `true`, and
    a tier-1 entry carries neither key: every tier-1 scenario runs at release.

Hand-off targets. The skill's koto templates, every
skills/<name>/koto-templates/*.md but *.mermaid.md, are read as text (no koto
is needed), and each of three sources gives a target on its own:

  - a gate with `type: request-leg`: its `leg:`;
  - a directive (the body section `## <state>`) carrying
    `--koto-leg=<req>:<leg>`: the <leg>;
  - a `default_template:` path: the skill directory under skills/ it
    resolves into, from the template's own directory.

Each target needs a `grader: script` case naming it in `handoff`. A leg
written as a `{{VAR}}` is templated: the check can't resolve it, so the skill
declares the targets on its cases instead. A templated leg needs at least one
declared target (a script case's `handoff` the templates don't give), and
each declared target must be a skill whose SKILL.md declares --koto-leg,
since only such a skill can answer a leg. The `shape ok` line lists the
targets.

The frontmatter is read by indentation, as every template here is written:
a state is a two-space key, `gates:` a four-space key in it, a gate a
six-space key under that and its `type:` and `leg:` eight-space keys. A
template laid out otherwise derives no gate target, and the `shape ok` line,
which lists the targets, shows it.

A skill with no evals.json passes only when its SKILL.md declares
`disable-model-invocation: true`, read the way scripts/check-evals-exist.sh
reads it (the phrase anywhere in the file). Otherwise the missing file fails.

Each failure is printed on stderr, naming the file and the eval (by `name`
when it has one, else by its position).

Needs git when the file has a script case (containment reads git's index).
Standard library only.

Exit codes:
  0 - the file is sound, or absent from a reference-only skill
  1 - the file is malformed or missing; every problem is printed
  2 - usage error
"""

import glob
import importlib.util
import json
import os
import re
import sys

SLUG = re.compile(r"^[a-z0-9][a-z0-9-]*$")
HANDOFF_SCRIPT = "scripts/check-handoff.sh"
TEMPLATED = re.compile(r"\{\{[A-Za-z_][A-Za-z0-9_]*\}\}")
LEG_FLAG = re.compile(r"--koto-leg=[^\s`'\":]+:([A-Za-z0-9][A-Za-z0-9._-]*|\{\{[A-Za-z_][A-Za-z0-9_]*\}\})")
DECLARED_NOTE = "declared for the templated leg"


def load_script_cases():
    """scripts/lib/script-cases.py as a module, for its containment rules."""
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), "script-cases.py")
    spec = importlib.util.spec_from_file_location("script_cases", path)
    module = importlib.util.module_from_spec(spec)
    # No __pycache__ left beside the script in the work tree.
    sys.dont_write_bytecode = True
    spec.loader.exec_module(module)
    return module


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


def declares_koto_leg(skill_md):
    try:
        with open(skill_md, encoding="utf-8", errors="replace") as fh:
            return "--koto-leg" in fh.read()
    except OSError:
        return False


def label(index, entry):
    if isinstance(entry, dict) and non_empty_string(entry.get("name")):
        return "eval %r (#%d)" % (entry["name"], index + 1)
    return "eval #%d" % (index + 1)


def unquote(value):
    value = re.sub(r"\s+#.*$", "", value.strip())
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        return value[1:-1]
    return value


def template_sources(path, root):
    """Each hand-off source in one template: (leg or target, templated, where).

    `where` names the source in the template: the gate's state and name, the
    directive's state, or the default_template reference and its state.
    """
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().split("\n")
    except OSError:
        return []
    found = []
    body_start = 0
    if lines and lines[0].strip() == "---":
        end = next((i for i in range(1, len(lines)) if lines[i].strip() == "---"), len(lines))
        body_start = end + 1
        # The frontmatter by indentation: a state is a two-space key, a block
        # in it (gates, accepts, ...) a four-space key, a gate a six-space
        # key under `gates:`, and a gate's fields eight-space keys.
        state = block = gate = None
        gates = []  # [state, gate, type, leg]
        for line in lines[1:end]:
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            m = re.match(r"  ([A-Za-z_][A-Za-z0-9_]*):\s*$", line)
            if m:
                state, block, gate = m.group(1), None, None
                continue
            if re.match(r"\S", line):
                state = block = gate = None
                continue
            m = re.match(r"    ([A-Za-z_][A-Za-z0-9_]*):", line)
            if m:
                block, gate = m.group(1), None
            m = re.match(r"      ([A-Za-z_][A-Za-z0-9_-]*):\s*$", line)
            if m and state is not None and block == "gates":
                gate = [state, m.group(1), None, None]
                gates.append(gate)
                continue
            m = re.match(r"        (type|leg):\s*(.*?)\s*$", line)
            if m and gate is not None:
                gate[2 if m.group(1) == "type" else 3] = unquote(m.group(2))
                continue
            m = re.match(r"\s+default_template:\s*(.*?)\s*$", line)
            if m:
                ref = unquote(m.group(1))
                resolved = os.path.normpath(os.path.join(os.path.dirname(path), ref))
                skills = os.path.join(os.path.realpath(root), "skills")
                rel = os.path.relpath(os.path.realpath(resolved), skills)
                if rel != "." and not rel.startswith(".."):
                    found.append((rel.split(os.sep)[0], False,
                                  "the `default_template: %s` reference in state %s" % (ref, state)))
        for g_state, g_name, g_type, g_leg in gates:
            if g_type == "request-leg" and g_leg:
                found.append((g_leg, bool(TEMPLATED.search(g_leg)),
                              "the request-leg gate %s in state %s" % (g_name, g_state)))
    section = None
    for line in lines[body_start:]:
        m = re.match(r"## (\S+)\s*$", line)
        if m:
            section = m.group(1)
            continue
        for leg in LEG_FLAG.findall(line):
            leg = leg.rstrip(".")
            where = ("the directive of state %s" % section) if section else "the directive text"
            found.append((leg, bool(TEMPLATED.search(leg)),
                          "--koto-leg=<req>:%s in %s" % (leg, where)))
    return found


def handoff_sources(skill_dir, root):
    """({target: [source]}, [templated source]) over the skill's templates."""
    literal, templated = {}, []
    for path in sorted(glob.glob(os.path.join(skill_dir, "koto-templates", "*.md"))):
        if path.endswith(".mermaid.md"):
            continue
        rel = os.path.relpath(path, root)
        for leg, is_templated, where in template_sources(path, root):
            entry = "%s of %s" % (where, rel)
            if is_templated:
                templated.append((leg, entry))
            else:
                literal.setdefault(leg, [])
                if entry not in literal[leg]:
                    literal[leg].append(entry)
    return literal, templated


class Repo:
    """The repository a skill belongs to, and its index, read once on demand."""

    def __init__(self, root):
        self.root = root
        self._index = None
        self._error = None
        self._cases = None

    def containment(self, run):
        """The rule a `run` breaks, or None."""
        if self._cases is None:
            self._cases = load_script_cases()
        if self._index is None and self._error is None:
            try:
                self._index = self._cases.tracked_files(self.root)
            except self._cases.UsageError as exc:
                self._error = exc.args[0]
        if self._error is not None:
            return "its `run` can't be checked: %s" % self._error
        _, problem = self._cases.containment(run, self._index, self.root)
        return problem


def check_script_case(where, entry, skill, repo):
    problems = []
    for key in ("run", "handoff"):
        if not non_empty_string(entry.get(key)):
            problems.append("%s: a `grader: script` case needs a non-empty `%s`" % (where, key))
    for key in ("prompt", "expectations"):
        if key in entry:
            problems.append("%s: a `grader: script` case runs a command, so it carries no `%s`"
                            % (where, key))
    run = entry.get("run")
    if non_empty_string(run):
        problem = repo.containment(run)
        if problem is not None:
            problems.append("%s: %s" % (where, problem))
        words = [w for w in run.split(" ") if w]
        if os.path.normpath(words[0]) == HANDOFF_SCRIPT and len(words) == 3:
            frm, to = words[1], words[2]
            if frm != skill:
                problems.append("%s: its `run` checks the hand-off from `%s`, a skill other than "
                                "`%s`, whose file holds the case" % (where, frm, skill))
            handoff = entry.get("handoff")
            if non_empty_string(handoff) and to != handoff:
                problems.append("%s: its `handoff` is `%s`, but its `run` checks the hand-off "
                                "to `%s`" % (where, handoff, to))
    return problems


def check(path, skill_md):
    problems = []
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except ValueError as exc:
        return ["%s: invalid JSON: %s" % (path, exc)], None
    except OSError as exc:
        return ["%s: cannot read: %s" % (path, exc.strerror)], None

    if not isinstance(data, dict):
        return ["%s: top level is not a JSON object" % path], None
    evals = data.get("evals")
    if not non_empty_list(evals):
        return ["%s: `evals` is missing or not a non-empty list" % path], None

    skill_dir = os.path.dirname(os.path.abspath(skill_md))
    skill = os.path.basename(skill_dir)
    root = os.path.dirname(os.path.dirname(skill_dir))
    repo = Repo(root)
    handoffs = {}

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
            problems.extend(check_script_case(where, entry, skill, repo))
            if non_empty_string(entry.get("handoff")):
                handoffs.setdefault(entry["handoff"], []).append(where)
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
    target_problems, targets = check_targets(path, skill_dir, root, handoffs)
    problems.extend(target_problems)
    return problems, targets


def check_targets(path, skill_dir, root, handoffs):
    """The hand-off targets' cases; returns (problems, the targets line)."""
    problems = []
    literal, templated = handoff_sources(skill_dir, root)
    for target in sorted(literal):
        if target not in handoffs:
            problems.append("%s: hand-off target `%s` (from %s) has no `grader: script` case "
                            "naming it in `handoff`" % (path, target, "; ".join(literal[target])))
    declared = sorted(t for t in handoffs if t not in literal) if templated else []
    if templated and not declared:
        for leg, where in templated:
            problems.append("%s: %s is a templated leg (`%s`) with no declared target; a "
                            "`grader: script` case names each skill it hands off to in "
                            "`handoff`" % (path, where[0].upper() + where[1:], leg))
    for target in declared:
        target_md = os.path.join(root, "skills", target, "SKILL.md")
        if not declares_koto_leg(target_md):
            for where in handoffs[target]:
                problems.append("%s: its `handoff` declares `%s` for the templated leg, but "
                                "skills/%s/SKILL.md doesn't declare --koto-leg, so it can't "
                                "answer a leg" % (where, target, target))
    parts = []
    if literal:
        parts.append(", ".join(sorted(literal)))
    if declared:
        parts.append("%s (%s)" % (", ".join(declared), DECLARED_NOTE))
    return problems, "; ".join(parts) or "none"


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

    problems, targets = check(evals_path, skill_md)
    for problem in problems:
        sys.stderr.write(problem + "\n")
    if problems:
        return 1
    print("%s: shape ok; hand-off targets: %s" % (evals_path, targets))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

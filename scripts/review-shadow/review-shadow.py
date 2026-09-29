#!/usr/bin/env python3
"""Shadow trial: grade a pull request with closed criteria beside its review panel.

The trial only records. Nothing here approves, skips or shortens a panel; a
unanimous pass is a line in a local file. docs/designs/DESIGN-jev-review-shadow.md
is the design this implements.

Subcommands:
  grade    grade one pull request at one head and write a record
  outcome  record a panel's outcome for the same pull request and head
  report   print agreement between grader and panels
  scan     run the script criteria over a local branch; writes nothing

Requires: Python 3.8 or later, standard library only, and `gh` for `grade`.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent
CRITERIA_FILE = HERE / "criteria.json"
CATEGORIES_FILE = HERE / "categories.json"

VALUE_KEYS = ("pass", "fail")
OBSERVERS = ("script", "jev")
ARTIFACT_KINDS = ("pull-request",)
SLICE_KINDS = ("pr-text", "pr-summary", "code-hunks", "doc-pairs")
SCRIPT_CHECKS = ("attribution", "private_terms", "scratch_path", "unfinished_wording",
                 "pasted_paragraph", "dangling_path")
CLASSES = ("covered", "closed-uncovered", "open-judgment")
RULE_ID = re.compile(r"rs-[0-9]{3}")
CRITERION_FIELDS = ("rule_id", "rule_ref", "group", "artifact_kind", "slice_kind", "observer",
                    "question", "values", "escape", "threshold")


class ConfigError(Exception):
    """A criteria or category file that the trial refuses to run with."""


def _read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        raise ConfigError(f"{path}: not found")
    except ValueError as e:
        raise ConfigError(f"{path}: not valid JSON ({e})")


def load_criteria(path=CRITERIA_FILE, repo_root=REPO_ROOT):
    """Load and check the criteria file; raise ConfigError on anything malformed.

    A criterion must be a two-value choice with one escape value. A boolean
    declaration is refused outright, because the accuracy spike found the
    boolean form compresses Jev's probabilities too far to decide on.
    """
    data = _read_json(path)
    if not isinstance(data, dict) or not isinstance(data.get("criteria"), list) or "version" not in data:
        raise ConfigError(f"{path}: needs a version and a criteria list")
    seen = set()
    for n, c in enumerate(data["criteria"], 1):
        where = f"{path}: criterion {n}"
        if not isinstance(c, dict):
            raise ConfigError(f"{where}: not an object")
        if c.get("type") == "boolean" or isinstance(c.get("values"), bool):
            raise ConfigError(f"{where}: boolean criteria are not allowed; declare a two-value choice")
        for field in CRITERION_FIELDS:
            if field not in c:
                raise ConfigError(f"{where}: missing {field!r}")
        rid = c["rule_id"]
        if not isinstance(rid, str) or not RULE_ID.fullmatch(rid):
            raise ConfigError(f"{where}: rule_id must look like rs-NNN")
        if rid in seen:
            raise ConfigError(f"{where}: duplicate rule_id {rid}")
        seen.add(rid)
        values, escape = c["values"], c["escape"]
        if not isinstance(values, dict) or tuple(sorted(values)) != tuple(sorted(VALUE_KEYS)):
            raise ConfigError(f"{where}: values must be exactly pass and fail")
        if not isinstance(escape, dict) or len(escape) != 1 or set(escape) & set(VALUE_KEYS):
            raise ConfigError(f"{where}: escape must be exactly one value other than pass and fail")
        if not all(isinstance(v, str) and v for v in list(values.values()) + list(escape.values())):
            raise ConfigError(f"{where}: every value needs a description")
        if c["artifact_kind"] not in ARTIFACT_KINDS:
            raise ConfigError(f"{where}: unknown artifact_kind {c['artifact_kind']!r}")
        if c["slice_kind"] not in SLICE_KINDS:
            raise ConfigError(f"{where}: unknown slice_kind {c['slice_kind']!r}")
        if c["observer"] not in OBSERVERS:
            raise ConfigError(f"{where}: observer must be script or jev")
        if c["observer"] == "script":
            if c.get("check") not in SCRIPT_CHECKS:
                raise ConfigError(f"{where}: unknown check {c.get('check')!r}")
            if c["slice_kind"] != "pr-text":
                raise ConfigError(f"{where}: script criteria read the pr-text slice")
        elif c["slice_kind"] == "pr-text":
            raise ConfigError(f"{where}: Jev criteria can't read the unbounded pr-text slice")
        t = c["threshold"]
        if isinstance(t, bool) or not isinstance(t, (int, float)) or not 0.5 <= t <= 1.0:
            raise ConfigError(f"{where}: threshold must be between 0.5 and 1.0")
        ref = c["rule_ref"]
        if not isinstance(ref, str) or ref.startswith("/") or ".." in ref.split("/") \
                or not (Path(repo_root) / ref).is_file():
            raise ConfigError(f"{where}: rule_ref {ref!r} doesn't name a file in the repository")
    if not seen:
        raise ConfigError(f"{path}: no criteria")
    return data


def load_categories(criteria, path=CATEGORIES_FILE):
    """Load the finding-category map and check it against the criteria."""
    data = _read_json(path)
    cats = data.get("categories") if isinstance(data, dict) else None
    if not isinstance(cats, dict) or not cats:
        raise ConfigError(f"{path}: needs a categories object")
    ids = {c["rule_id"] for c in criteria["criteria"]}
    for name, entry in cats.items():
        if not re.match(r"^[a-z0-9-]{1,40}$", name):
            raise ConfigError(f"{path}: bad category name {name!r}")
        if not isinstance(entry, dict) or entry.get("class") not in CLASSES:
            raise ConfigError(f"{path}: category {name!r} needs a class from {CLASSES}")
        rule_ids = entry.get("rule_ids", [])
        if entry["class"] == "covered" and not rule_ids:
            raise ConfigError(f"{path}: covered category {name!r} names no rule id")
        if entry["class"] != "covered" and rule_ids:
            raise ConfigError(f"{path}: only a covered category names rule ids ({name!r})")
        unknown = [r for r in rule_ids if r not in ids]
        if unknown:
            raise ConfigError(f"{path}: category {name!r} names unknown rule ids {unknown}")
    for c in criteria["criteria"]:
        if c["group"] not in cats:
            raise ConfigError(f"{path}: criterion {c['rule_id']} has group {c['group']!r}, which isn't a category")
    return data


def main(argv=None):
    ap = argparse.ArgumentParser(prog="review-shadow.py", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="command", required=True)
    sub.add_parser("check", help="load the criteria and category files and report problems")
    args = ap.parse_args(argv)
    try:
        criteria = load_criteria()
        load_categories(criteria)
    except ConfigError as e:
        print(f"review-shadow: {e}", file=sys.stderr)
        return 2
    if args.command == "check":
        print(f"criteria: {len(criteria['criteria'])} loaded")
    return 0


if __name__ == "__main__":
    sys.exit(main())

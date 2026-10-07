#!/usr/bin/env python3
"""eval-pass-rates.py - build and stamp shirabe's eval pass-rate record.

The record (schema eval-pass-rates/v1) is the release asset
eval-pass-rates.json. scripts/release-eval-check.sh calls this script; see
docs/designs/DESIGN-evals-at-release.md (Decision 3, Security Considerations).

Usage:
  eval-pass-rates.py merge --previous <file or -> [--no-baseline-reason <text>]
      [--summary <file>]... [--selected <skill>]... --version <v>
      --last-tag <tag or ''> [--confirmed <a,b>] --out <file>
  eval-pass-rates.py stamp --record <file> --version <v> [--measured <skill>]...

merge
  Builds the record from this run's run-evals-summary/v1 files and the previous
  release's record, writes it to --out and prints a comparison table.
  - Every --selected skill gets an entry. A selected skill with no readable,
    well-formed summary entry is an infrastructure failure, recorded as
    exit_code 2. So is a harness exit of 0 or 1 that graded no assertion.
  - pass_rate is assertions_passed / assertions_graded rounded to four places,
    present only for a harness exit of 0 or 1 with at least one graded
    assertion. Skills with an exit of 2, 3 or 4 carry exit_code instead.
  - Skills of the previous record that this run did not select are carried
    forward unchanged.
  - The previous record is untrusted. Anything wrong with it (missing, over
    the size cap, unparseable, another schema, any field check failing) means
    "no baseline", with a warning naming the field and never its value.
  - A drop is a skill whose rounded rate is strictly lower than the previous
    record's rate for it.
  Exit codes: 0 clean (a harness exit 1 without a drop included); 1 any
  selected skill's harness exit was 2, 3 or 4 (an infrastructure failure
  outranks a drop); 5 a drop not listed in --confirmed, the output ending with
  "confirm: RELEASE_CONFIRMED_DROPS=<every dropped skill>"; 2 usage.

stamp
  Sets the record's version, and measured_at of each --measured skill present
  in it, to --version, leaving every other skill untouched.
  Exit codes: 0 stamped; 1 the record is missing or invalid; 2 usage.
"""

import argparse
import json
import math
import os
import re
import sys
import tempfile

SCHEMA = "eval-pass-rates/v1"
SUMMARY_SCHEMA = "run-evals-summary/v1"
SIZE_CAP = 1024 * 1024

SEMVER_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
TAG_RE = re.compile(r"^v[0-9]+\.[0-9]+\.[0-9]+$")
SKILL_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
MODEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]*$")

COUNT_FIELDS = ("runs", "runs_passed", "assertions_passed", "assertions_graded")
INFRA_EXITS = (2, 3, 4)


class Invalid(Exception):
    """A field check failed. The message names the field, never its value."""


def is_count(value):
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def rate_of(passed, graded):
    return round(passed / graded, 4)


def check_counts(entry, where):
    for field in COUNT_FIELDS:
        if not is_count(entry.get(field)):
            raise Invalid("%s.%s is not a non-negative integer" % (where, field))
    if entry["runs_passed"] > entry["runs"]:
        raise Invalid("%s.runs_passed exceeds %s.runs" % (where, where))
    if entry["assertions_passed"] > entry["assertions_graded"]:
        raise Invalid("%s.assertions_passed exceeds %s.assertions_graded" % (where, where))


def check_models(models, where):
    if not isinstance(models, list):
        raise Invalid("%s.models is not a list" % where)
    for model in models:
        if not isinstance(model, str) or not MODEL_RE.match(model):
            raise Invalid("%s.models has an invalid model" % where)


def clean_record_entry(entry, where):
    """Validate one skill entry of a record; return it rebuilt from the field list."""
    if not isinstance(entry, dict):
        raise Invalid("%s is not an object" % where)
    check_counts(entry, where)
    check_models(entry.get("models"), where)
    measured_at = entry.get("measured_at")
    if not isinstance(measured_at, str) or not SEMVER_RE.match(measured_at):
        raise Invalid("%s.measured_at is not a semver version" % where)
    out = {field: entry[field] for field in COUNT_FIELDS}
    out["models"] = list(entry["models"])
    out["measured_at"] = measured_at
    has_rate = "pass_rate" in entry
    has_exit = "exit_code" in entry
    if has_rate and has_exit:
        raise Invalid("%s has both pass_rate and exit_code" % where)
    if has_rate:
        rate = entry["pass_rate"]
        if (isinstance(rate, bool) or not isinstance(rate, (int, float))
                or not math.isfinite(rate) or rate < 0 or rate > 1):
            raise Invalid("%s.pass_rate is not a finite number in [0, 1]" % where)
        if entry["assertions_graded"] == 0:
            raise Invalid("%s.pass_rate is present with no graded assertion" % where)
        expected = rate_of(entry["assertions_passed"], entry["assertions_graded"])
        if abs(rate - expected) > 0.00005:
            raise Invalid("%s.pass_rate disagrees with the counts" % where)
        out["pass_rate"] = expected
    if has_exit:
        code = entry["exit_code"]
        if isinstance(code, bool) or code not in INFRA_EXITS:
            raise Invalid("%s.exit_code is not 2, 3 or 4" % where)
        out["exit_code"] = code
    return out


def clean_record(data):
    """Validate a whole record; return it rebuilt from the field list."""
    if not isinstance(data, dict):
        raise Invalid("the record is not an object")
    if data.get("schema") != SCHEMA:
        raise Invalid("schema is not %s" % SCHEMA)
    version = data.get("version")
    if not isinstance(version, str) or not SEMVER_RE.match(version):
        raise Invalid("version is not a semver version")
    last_tag = data.get("last_tag")
    if not isinstance(last_tag, str) or (last_tag != "" and not TAG_RE.match(last_tag)):
        raise Invalid("last_tag is not a v<major>.<minor>.<patch> tag")
    skills = data.get("skills")
    if not isinstance(skills, dict):
        raise Invalid("skills is not an object")
    clean = {}
    for name, entry in skills.items():
        if not isinstance(name, str) or not SKILL_RE.match(name):
            raise Invalid("skills has an invalid skill name")
        clean[name] = clean_record_entry(entry, "skills.%s" % name)
    return {"schema": SCHEMA, "version": version, "last_tag": last_tag, "skills": clean}


def read_json_capped(path):
    """Read a JSON file under the size cap. Raises Invalid with a reason."""
    try:
        size = os.path.getsize(path)
    except OSError:
        raise Invalid("the file is missing")
    if size > SIZE_CAP:
        raise Invalid("the file is over the %d-byte size cap" % SIZE_CAP)
    try:
        with open(path, "rb") as fh:
            raw = fh.read(SIZE_CAP + 1)
        return json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, ValueError, RecursionError):
        raise Invalid("the file does not parse as JSON")


def load_previous(path, reason):
    """Return (record or None, warning or None)."""
    if path == "-":
        return None, reason or "no previous record"
    try:
        return clean_record(read_json_capped(path)), None
    except Invalid as exc:
        return None, str(exc)


def load_summaries(paths):
    """Collect this run's summary entries by skill. Returns (entries, warnings)."""
    entries = {}
    warnings = []
    for index, path in enumerate(paths):
        where = "summary %d" % (index + 1)
        try:
            data = read_json_capped(path)
            if not isinstance(data, dict) or data.get("schema") != SUMMARY_SCHEMA:
                raise Invalid("schema is not %s" % SUMMARY_SCHEMA)
            skills = data.get("skills")
            if not isinstance(skills, dict):
                raise Invalid("skills is not an object")
            found = {}
            for name, entry in skills.items():
                if not isinstance(name, str) or not SKILL_RE.match(name):
                    raise Invalid("skills has an invalid skill name")
                if not isinstance(entry, dict):
                    raise Invalid("skills.%s is not an object" % name)
                check_counts(entry, "skills.%s" % name)
                check_models(entry.get("models"), "skills.%s" % name)
                code = entry.get("exit_code")
                if isinstance(code, bool) or code not in (0, 1) + INFRA_EXITS:
                    raise Invalid("skills.%s.exit_code is not 0 to 4" % name)
                found[name] = entry
            entries.update(found)
        except Invalid as exc:
            warnings.append("%s ignored: %s" % (where, exc))
    return entries, warnings


def measured_entry(summary, version):
    """The record entry for a skill this run measured, or one that failed."""
    if summary is None:
        entry = {field: 0 for field in COUNT_FIELDS}
        entry.update({"models": [], "measured_at": version, "exit_code": 2})
        return entry
    entry = {field: summary[field] for field in COUNT_FIELDS}
    entry["models"] = sorted(set(summary["models"]))
    entry["measured_at"] = version
    code = summary["exit_code"]
    if code in (0, 1) and summary["assertions_graded"] > 0:
        entry["pass_rate"] = rate_of(summary["assertions_passed"], summary["assertions_graded"])
    elif code in (0, 1):
        # Grading nothing is an infrastructure failure, never a pass.
        entry["exit_code"] = 2
    else:
        entry["exit_code"] = code
    return entry


def write_atomic(path, data):
    directory = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".eval-pass-rates.")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(data, fh, indent=2, sort_keys=True)
            fh.write("\n")
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def fmt_rate(entry):
    if entry is None:
        return "-"
    if "pass_rate" in entry:
        return "%.4f" % entry["pass_rate"]
    if "exit_code" in entry:
        return "exit %d" % entry["exit_code"]
    return "-"


class UsageError(Exception):
    pass


def parse_skill_list(text, flag):
    names = [n for n in text.split(",") if n] if text else []
    for name in names:
        if not SKILL_RE.match(name):
            raise UsageError("%s has an invalid skill name" % flag)
    return names


def cmd_merge(args):
    if not SEMVER_RE.match(args.version):
        raise UsageError("--version is not a semver version")
    if args.last_tag and not TAG_RE.match(args.last_tag):
        raise UsageError("--last-tag is not a v<major>.<minor>.<patch> tag")
    for name in args.selected:
        if not SKILL_RE.match(name):
            raise UsageError("--selected has an invalid skill name")
    confirmed = set(parse_skill_list(args.confirmed, "--confirmed"))

    previous, warning = load_previous(args.previous, args.no_baseline_reason)
    if warning:
        print("warning: no baseline: %s" % warning)
    summaries, summary_warnings = load_summaries(args.summary)
    for message in summary_warnings:
        print("warning: %s" % message)

    skills = {}
    if previous is not None:
        skills.update(previous["skills"])
    selected = sorted(set(args.selected))
    for name in selected:
        if name not in summaries:
            print("warning: no summary for %s" % name)
        skills[name] = measured_entry(summaries.get(name), args.version)

    record = {"schema": SCHEMA, "version": args.version, "last_tag": args.last_tag,
              "skills": skills}
    write_atomic(args.out, record)

    print("")
    print("%-24s %-10s %-10s %s" % ("skill", "current", "previous", "measured at"))
    infra = []
    drops = []
    for name in selected:
        entry = skills[name]
        prev = previous["skills"].get(name) if previous else None
        prev_at = prev["measured_at"] if prev else "-"
        print("%-24s %-10s %-10s %s" % (name, fmt_rate(entry), fmt_rate(prev), prev_at))
        if "exit_code" in entry:
            infra.append((name, entry["exit_code"]))
        elif prev is not None and "pass_rate" in prev and entry["pass_rate"] < prev["pass_rate"]:
            drops.append(name)
    print("record: %s" % args.out)

    if infra:
        print("")
        for name, code in infra:
            print("infrastructure failure: %s (harness exit %d)" % (name, code))
        return 1
    unconfirmed = [n for n in drops if n not in confirmed]
    if unconfirmed:
        print("")
        for name in drops:
            state = "confirmed" if name in confirmed else "not confirmed"
            print("drop: %s (%s)" % (name, state))
        print("confirm: RELEASE_CONFIRMED_DROPS=%s" % ",".join(drops))
        return 5
    for name in drops:
        print("drop confirmed: %s" % name)
    return 0


def cmd_stamp(args):
    if not SEMVER_RE.match(args.version):
        raise UsageError("--version is not a semver version")
    for name in args.measured:
        if not SKILL_RE.match(name):
            raise UsageError("--measured has an invalid skill name")
    try:
        record = clean_record(read_json_capped(args.record))
    except Invalid as exc:
        print("error: the record is invalid: %s" % exc, file=sys.stderr)
        return 1
    record["version"] = args.version
    for name in args.measured:
        if name in record["skills"]:
            record["skills"][name]["measured_at"] = args.version
    write_atomic(args.record, record)
    return 0


class Parser(argparse.ArgumentParser):
    def error(self, message):
        raise UsageError(message)


def main(argv):
    parser = Parser(prog="eval-pass-rates.py")
    sub = parser.add_subparsers(dest="command")
    merge = sub.add_parser("merge")
    merge.error = parser.error
    merge.add_argument("--previous", required=True)
    merge.add_argument("--no-baseline-reason", default="")
    merge.add_argument("--summary", action="append", default=[])
    merge.add_argument("--selected", action="append", default=[])
    merge.add_argument("--version", required=True)
    merge.add_argument("--last-tag", required=True)
    merge.add_argument("--confirmed", default="")
    merge.add_argument("--out", required=True)
    stamp = sub.add_parser("stamp")
    stamp.error = parser.error
    stamp.add_argument("--record", required=True)
    stamp.add_argument("--version", required=True)
    stamp.add_argument("--measured", action="append", default=[])
    try:
        args = parser.parse_args(argv)
        if args.command == "merge":
            return cmd_merge(args)
        if args.command == "stamp":
            return cmd_stamp(args)
        raise UsageError("a command is required: merge or stamp")
    except UsageError as exc:
        print("usage error: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

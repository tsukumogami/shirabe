#!/usr/bin/env python3
"""jev_criteria.py -- slice contracts and pass trust for Jev criteria.

A Jev criterion is a closed question Jev answers about a slice of an agent's
work. Each one has an entry in references/rule-registry.json, and its `jev`
object is the criterion's contract and trust record. references/jev-criteria.md
describes the contract and holds each criterion's completeness case; the
design is docs/designs/current/DESIGN-jev-pass-trust.md.

Subcommands:

  check [--root DIR] [--base REF] [--koto-templates PATH]...
      Hold every Jev entry to its contract, and with --base to the history
      rules. Refuse `mode: veto` on a document criterion and `mode: auto` on
      any decider value in every template of the tree and of each PATH (a
      template or a directory of them), the templates they include, and a
      project config that sets the decider mode to auto. Prints one line per
      problem. Exit 0 none, 1 problems, 2 could not run.
  declared-hash RULE_ID [--format F] [--root DIR]
      Print a decider entry's declaration as canonical JSON, then its SHA-256.
  pins [--root DIR]
      Print the `pins` JSON references/doc-criteria.json holds: the sha256 of
      each mapped template and of the slice script as they are now.
  measure sessions --dir DIR [--dir DIR]... [--slice review-facts|decision-reasons|criteria-plan|design-context]
  measure prs --repo OWNER/REPO --limit N --kind pr-summary|code-hunks|doc-pairs [--git-dir DIR]
  measure records --dir DIR --kind KIND
      Measure whole-run slice sizes on real artifacts, with no call to Jev,
      and print the figures as the `measured` JSON a contract records.
  measure docs --criterion RULE_ID --format F --roots DIR [DIR]...
      Measure a document criterion's units, one at a time, over every
      <FORMAT>-*.md under the roots, and print the `measured` JSON.
  fixtures RULE_ID [--format F] [--endpoint URL]
      Send each fixture case to Jev under the template's declaration and
      print counts by kind and answer and the `fixture_run` JSON. Exit 0 when
      the fixture bar is met, 1 when not, 2 when it could not run. The key
      comes from KOTO_DECIDER_API_KEY and is never printed; a loopback
      endpoint (a local stub) never gets it. A document criterion's run is
      held to the stricter bar (every seeded-bad case answered fail) and
      records the slice script's blob too.
  figures RULE_ID [--format F] --sessions DIR [--from D] [--to D] [--bar]
      Compute the live figures from local koto session logs and print the
      `live` JSON; with --bar exit 0 when they meet the bar, 1 when not. A
      reference for the definitions only: the figures that decide a
      promotion are read from koto's exported decider events.

Reads templates with mikefarah yq v4 and shells out to git, gh (measure prs
only) and scripts/rule-registry.sh (the release check). Standard library only.

A "rule N" in a comment is the Nth contract rule in the design's
`jev_criteria.py` section ("Contract rules (check)"). check_contract runs them
in the order their inputs become available, not in that numbering.
"""

import argparse
import datetime
import glob
import gzip
import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

PROG = "jev_criteria"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.dirname(os.path.dirname(HERE))

REGISTRY = "references/rule-registry.json"
CRITERIA = "scripts/review-shadow/criteria.json"
RULE_REGISTRY_SH = "scripts/rule-registry.sh"
REVIEW_LEVEL_SH = "skills/work-on/scripts/review-level.sh"
# The document criteria: their per-format map and pins, their slice script,
# and the directory their one-state templates live in.
DOC_CRITERIA = "references/doc-criteria.json"
DOC_SLICER = "scripts/doc-criteria/slice.py"
DOC_TEMPLATES = "koto-templates/doc-criteria"
JEV_REFERENCE = "references/jev-criteria.md"
# The rule ids the document criteria grade. None of them may be declared in
# veto mode anywhere: they run in shadow until a maintainer's proposal is
# approved and a template edit follows.
DOC_RULE_IDS = ("rs-009", "rs-011", "rs-012", "rs-013", "rs-073", "rs-074")
DOC_FORMATS = ("brief", "prd", "design", "roadmap", "strategy")
DOC_PARTS = ("Sources", "Slice", "Completeness", "Figures", "Fixtures", "State")
CHANGE_KIND = re.compile(r"^[a-z][a-z0-9-]*$")

# About the 2,507 bytes the Jev accuracy spike validated; nothing larger is
# trusted until the spike is re-run (docs/spikes/SPIKE-jev-accuracy.md).
BUDGET_CEILING = 2560
# koto's decider-check defaults, from its authoring guide.
DEFAULT_LABEL = "artifact"
DEFAULT_MAX_BYTES = 2560
DEFAULT_THRESHOLD = 0.9
# A contract is rejected when more than this percentage of measured runs is
# over its budget.
OVER_BUDGET_PERCENT = 5
MIN_RUNS = 100
FIXTURE_MINIMUMS = {"good": 10, "seeded-bad": 20, "adversarial": 5}
MIN_TECHNIQUES = 3
TECHNIQUES = {"instruction", "authority-claim", "fake-answer", "hidden-comment",
              "vocabulary-mimicry", "role-line"}
GOOD_PASS_SHARE = 0.8
LIVE_MIN_EVALUATIONS = 30
LIVE_MIN_SESSIONS = 5
LIVE_MIN_ANSWERED = 0.95
# How far, in points of share, the live window's not-graded share may sit from
# the empty-slice share the contract measured. Not-graded evaluations are left
# out of the bar, so a slice script that starts printing nothing where the
# criterion applies would otherwise make those runs vanish instead of failing.
NOT_GRADED_DRIFT = 0.10

STATES = {"rejected", "blocked", "untrusted", "trusted"}
WRITERS = {"git", "gate-script", "graded-artifact", "slice-script"}
# `documents` is a census: every committed document of the format under the
# measured roots, so `runs` is the documents with a unit, and the 100-run
# minimum, which asks a sample to be big enough, doesn't apply to it.
POPULATIONS = {"koto-sessions", "merged-prs", "review-shadow-records", "documents"}
CENSUS = "documents"
# A census's `max` and `p90` are per unit, and `over_budget` counts the
# documents holding a unit over the budget, which the 5% line is drawn on.
DOC_MEASURED = ("units", "units_over_budget", "units_per_doc_p90", "units_per_doc_max", "over_cap")
NOT_MEASURED = {"no-real-run-record"}
VERDICTS = {"sufficient", "insufficient"}
ORACLES = {"review", "ci", "human"}
ANSWERS = ("pass", "fail", "unclear", "error")
# An `empty` case holds a slice with nothing to judge, which the criterion's
# escape (sent as `unclear`) is the right answer to. It has no minimum.
EMPTY_KIND = "empty"
KINDS = tuple(FIXTURE_MINIMUMS) + (EMPTY_KIND,)
EXPECTED = {"good": "pass", "seeded-bad": "fail", "adversarial": "fail", EMPTY_KIND: "unclear"}

DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
PATH_SHAPE = re.compile(r"^[A-Za-z0-9._][A-Za-z0-9._/-]*$")
LOCAL_PATH = re.compile(r"(^|[\s\"'=])(/Users/|/home/|/root/|/private/|/var/|~/|\$HOME)")
RULE_ID = re.compile(r"^([a-z0-9-]+/[a-z0-9-]+|rs-[0-9]{3})$")
WITHHOLD_SCRIPT = "jev-withhold.sh"
WITHHOLD_CALL = re.compile(r"jev-withhold\.sh[\"']?\s+[\"']?([^\"'\s]+)")


class CannotRun(Exception):
    """A check that could not reach a verdict: exit 2, never a pass."""


def fail2(msg):
    print("%s: %s" % (PROG, msg), file=sys.stderr)
    sys.exit(2)


def run(argv, cwd=None, env=None):
    return subprocess.run(argv, cwd=cwd, env=env, capture_output=True, text=True)


def read_text(path, errors=None):
    with open(path, encoding="utf-8", errors=errors) as f:
        return f.read()


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise CannotRun("cannot read %s: %s" % (path, e))


def safe_rel(root, rel):
    """True when `rel` has a safe shape, no . or .. segment, and stays in root."""
    if not isinstance(rel, str) or not PATH_SHAPE.match(rel):
        return False
    if any(part in (".", "..") for part in rel.split("/")):
        return False
    full = os.path.realpath(os.path.join(root, rel))
    return full == root or full.startswith(root + os.sep)


def git_blob(root, rel):
    r = run(["git", "-C", root, "hash-object", "--no-filters", "--", rel])
    if r.returncode != 0:
        raise CannotRun("git hash-object %s failed" % rel)
    return r.stdout.strip()


def nearest_rank(values, p):
    """The p-th percentile by nearest rank: the ceil(p*n)-th smallest value."""
    xs = sorted(values)
    if not xs:
        return 0
    k = max(1, math.ceil(p * len(xs)))
    return xs[k - 1]


def figures(sizes, budget, population, command, empty=None):
    out = {"population": population, "runs": len(sizes),
           "max": max(sizes) if sizes else 0, "p90": nearest_rank(sizes, 0.9),
           "over_budget": sum(1 for s in sizes if s > budget),
           "on": datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
           "command": command}
    if empty is not None:
        out["empty"] = empty
    return out


# --- Templates ----------------------------------------------------------------

def template_states(root, rel, cache):
    """The template's `states` map, through yq. Raises CannotRun when yq can't."""
    if rel in cache:
        return cache[rel]
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        cache[rel] = None
        return None
    r = run(["yq", "--front-matter=extract", "-o=json", ".states // {}", path])
    if r.returncode != 0:
        raise CannotRun("yq could not read %s: %s" % (rel, r.stderr.strip()[:200]))
    try:
        cache[rel] = json.loads(r.stdout or "{}")
    except ValueError:
        raise CannotRun("yq printed no JSON for %s" % rel)
    return cache[rel]


def template_files(root):
    out = []
    for pattern in ("skills/*/koto-templates/*.md", "koto-templates/*.md", "koto-templates/*/*.md"):
        for p in sorted(glob.glob(os.path.join(root, pattern))):
            if not p.endswith(".mermaid.md"):
                out.append(os.path.relpath(p, root))
    return out


def decider_gates(root, cache):
    """Every (template, state, gate, criterion) a decider-check gate declares."""
    found = []
    for rel in template_files(root):
        states = template_states(root, rel, cache) or {}
        for sname, state in sorted(states.items()):
            for gname, gate in sorted(((state or {}).get("gates") or {}).items()):
                if isinstance(gate, dict) and gate.get("type") == "decider-check":
                    for cid in sorted((gate.get("criteria") or {})):
                        found.append((rel, sname, gname, cid))
    return found


def find_gate(root, check, cache):
    """(gate, criterion) for a decider check, or (None, None) when it doesn't resolve."""
    states = template_states(root, check.get("template", ""), cache)
    if not states:
        return None, None
    gate = ((states.get(check.get("state")) or {}).get("gates") or {}).get(check.get("gate"))
    if not isinstance(gate, dict) or gate.get("type") != "decider-check":
        return None, None
    crit = (gate.get("criteria") or {}).get(check.get("criterion"))
    if not isinstance(crit, dict):
        return gate, None
    return gate, crit


def declaration(gate, crit):
    decl = {"command": gate.get("command", ""),
            "label": gate.get("label", DEFAULT_LABEL),
            "max_bytes": int(gate.get("max_bytes", DEFAULT_MAX_BYTES)),
            "question": crit.get("question", ""), "pass": crit.get("pass", ""),
            "fail": crit.get("fail", ""), "escape": crit.get("escape", ""),
            "threshold": float(crit.get("threshold", DEFAULT_THRESHOLD))}
    # A unit-mode check grades each printed unit apart, and its cap decides
    # which ones; both are part of what a fixture run was made under. A
    # single-slice check has neither, so its hash is what it always was.
    if "units" in gate:
        decl["units"] = gate.get("units")
        decl["max_units"] = gate.get("max_units")
    return decl


def canonical(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def declared_sha256(decl):
    return hashlib.sha256(canonical(decl).encode("utf-8")).hexdigest()


def template_directive(root, rel, state):
    """The body text under `## <state>` in a template, up to the next `## `."""
    try:
        text = read_text(os.path.join(root, rel))
    except OSError:
        return ""
    body = text.split("\n---\n", 1)[-1] if text.startswith("---") else text
    out, on = [], False
    for line in body.split("\n"):
        if line.startswith("## "):
            if on:
                break
            on = line.strip() == "## " + state
            continue
        if on:
            out.append(line)
    return "\n".join(out)


# --- Fixtures -----------------------------------------------------------------

def load_fixtures(path):
    """(cases, problems) for a fixture file: one JSON object per line."""
    cases, problems = [], []
    try:
        lines = read_text(path).splitlines()
    except OSError as e:
        return [], ["cannot read %s: %s" % (path, e)]
    ids = set()
    for n, line in enumerate(lines, 1):
        if not line.strip():
            continue
        try:
            c = json.loads(line)
        except ValueError:
            problems.append("line %d is not JSON" % n)
            continue
        if not isinstance(c, dict):
            problems.append("line %d is not an object" % n)
            continue
        cid = c.get("id")
        if not isinstance(cid, str) or not cid:
            problems.append("line %d has no id" % n)
        elif cid in ids:
            problems.append("id %s is used twice" % cid)
        else:
            ids.add(cid)
        kind = c.get("kind")
        if kind not in KINDS:
            problems.append("case %s: kind %r is not good, seeded-bad, adversarial or empty" % (cid, kind))
        want = EXPECTED.get(kind, "fail")
        if c.get("expected") != want:
            article = "an" if str(kind)[:1] in "aeiou" else "a"
            problems.append("case %s: expected must be %s for %s %s case" % (cid, want, article, kind))
        if "input" not in c:
            problems.append("case %s has no input" % cid)
        if not isinstance(c.get("slice"), str) or not c.get("slice"):
            problems.append("case %s has no slice" % cid)
        if kind == "adversarial" and c.get("technique") not in TECHNIQUES:
            problems.append("case %s: technique %r is not one of %s"
                            % (cid, c.get("technique"), ", ".join(sorted(TECHNIQUES))))
        cases.append(c)
    counts = {k: sum(1 for c in cases if c.get("kind") == k) for k in FIXTURE_MINIMUMS}
    for k, need in FIXTURE_MINIMUMS.items():
        if counts[k] < need:
            problems.append("%d %s cases, fewer than %d" % (counts[k], k, need))
    techniques = {c.get("technique") for c in cases if c.get("kind") == "adversarial"} & TECHNIQUES
    if len(techniques) < MIN_TECHNIQUES:
        problems.append("%d adversarial techniques, fewer than %d" % (len(techniques), MIN_TECHNIQUES))
    return cases, problems


def fixture_bar(counts, strict=False):
    """(met, reasons) for fixture counts {kind: {answer: n}}. `strict`, for a
    document criterion, also wants every seeded-bad case answered fail: an
    escape on a unit known to break the rule counts against it."""
    reasons = []
    for k in ("seeded-bad", "adversarial"):
        if counts.get(k, {}).get("pass", 0):
            reasons.append("%d %s case(s) answered pass" % (counts[k]["pass"], k))
    if strict:
        # A pass and a missing answer are reported below and above; this is
        # the escape, which the ordinary bar lets through.
        escaped = counts.get("seeded-bad", {}).get("unclear", 0)
        if escaped:
            reasons.append("%d seeded-bad case(s) answered with the escape, not fail" % escaped)
    empty = counts.get(EMPTY_KIND, {})
    judged = empty.get("pass", 0) + empty.get("fail", 0)
    if judged:
        reasons.append("%d empty case(s) answered pass or fail, not the escape" % judged)
    good = counts.get("good", {})
    total = sum(good.get(a, 0) for a in ANSWERS)
    if total == 0 or good.get("pass", 0) < GOOD_PASS_SHARE * total:
        reasons.append("%d of %d good cases answered pass, under %d%%"
                       % (good.get("pass", 0), total, int(GOOD_PASS_SHARE * 100)))
    errors = sum(counts.get(k, {}).get("error", 0) for k in KINDS)
    if errors:
        reasons.append("%d case(s) got no answer" % errors)
    return not reasons, reasons


def share(record, part, rest):
    """part / (part + rest) for two counts of a record, 0.0 when both are 0.
    A count that isn't a non-negative integer reads as 0: check_contract and
    check_promotion report the bad value, and the bar must still be computed
    beside that report rather than raise."""
    r = record if isinstance(record, dict) else {}
    a, b = (r.get(k, 0) for k in (part, rest))
    a, b = (v if isinstance(v, int) and not isinstance(v, bool) and v >= 0 else 0 for v in (a, b))
    return a / (a + b) if a + b else 0.0


def not_graded_share(live):
    """The share of a live window's evaluations that had nothing to grade."""
    return share(live, "not_graded", "evaluations")


def empty_share(measured):
    """The share of measured runs whose slice was empty. A measurement with no
    `empty` count found none: a slice that is never empty records nothing."""
    return share(measured, "empty", "runs")


def live_bar(live, budget, measured=None):
    """(met, reasons) for recorded or computed live figures, against the
    contract's `measured` record for the not-graded share."""
    reasons = []
    ng, empty = not_graded_share(live), empty_share(measured)
    if abs(ng - empty) > NOT_GRADED_DRIFT:
        reasons.append("%.0f%% of evaluations not graded, more than %d points from the %.0f%% of runs "
                       "the contract measured with an empty slice"
                       % (100 * ng, int(NOT_GRADED_DRIFT * 100), 100 * empty))
    ev = live.get("evaluations", 0)
    if ev < LIVE_MIN_EVALUATIONS:
        reasons.append("%d evaluations, fewer than %d" % (ev, LIVE_MIN_EVALUATIONS))
    if live.get("sessions", 0) < LIVE_MIN_SESSIONS:
        reasons.append("%d sessions, fewer than %d" % (live.get("sessions", 0), LIVE_MIN_SESSIONS))
    # An evaluation is answered at most once and belongs to one session, so a
    # record with more of either than evaluations was not read from events.
    for k in ("answered", "sessions"):
        if live.get(k, 0) > ev:
            reasons.append("%d %s, more than its %d evaluations" % (live[k], k, ev))
    if ev and live.get("answered", 0) < LIVE_MIN_ANSWERED * ev:
        reasons.append("%d of %d evaluations answered, under %d%%"
                       % (live.get("answered", 0), ev, int(LIVE_MIN_ANSWERED * 100)))
    if live.get("over_budget_fallbacks", 0):
        reasons.append("%d over_budget fallback(s)" % live["over_budget_fallbacks"])
    if live.get("max_input_bytes", 0) > budget:
        reasons.append("largest input %d bytes is over the %d-byte budget" % (live["max_input_bytes"], budget))
    return not reasons, reasons


# --- check --------------------------------------------------------------------

def is_jev_entry(entry, criteria):
    check = entry.get("check") if isinstance(entry.get("check"), dict) else {}
    if check.get("kind") == "decider":
        return True
    if check.get("kind") == "review-shadow":
        return (criteria.get(check.get("criterion")) or {}).get("observer") == "jev"
    return False


def expected_state(jev, declared_by_template):
    m = jev.get("measured")
    over = isinstance(m, dict) and m.get("runs", 0) > 0 and \
        m.get("over_budget", 0) * 100 > m.get("runs", 0) * OVER_BUDGET_PERCENT
    if over or (jev.get("completeness") or {}).get("verdict") == "insufficient":
        return {"rejected"}
    if not declared_by_template:
        return {"blocked"}
    return {"trusted"} if jev.get("promotion") else {"untrusted"}


def check_contract(root, entry, jev, criteria, cache, declared, label=None):
    """Problems with one Jev entry's contract (rules 1 to 10). A document
    criterion's entry has one contract per format, each checked here under
    `label` (`<id> <format>`)."""
    eid = entry["id"]
    out = []

    def p(msg):
        out.append("%s: %s" % (label or eid, msg))

    state = jev.get("state")
    if state not in STATES:
        p("jev.state %r is not rejected, blocked, untrusted or trusted" % state)
        return out
    # 1: fields and paths.
    sources = jev.get("sources")
    if not isinstance(sources, list) or not sources:
        p("jev.sources is not a non-empty list")
    else:
        for s in sources:
            if not isinstance(s, dict) or not isinstance(s.get("what"), str) or not s.get("what"):
                p("a jev source has no `what`")
                continue
            if s.get("writer") not in WRITERS:
                p("source %s: writer %r is not one of %s" % (s["what"], s.get("writer"), ", ".join(sorted(WRITERS))))
            elif s["writer"] == "gate-script":
                if not safe_rel(root, s.get("script")) or not os.path.isfile(os.path.join(root, s.get("script", ""))):
                    p("source %s: gate-script %r does not exist" % (s["what"], s.get("script")))
    rel = jev.get("slice_script")
    if not safe_rel(root, rel) or not os.path.isfile(os.path.join(root, rel)):
        p("jev.slice_script %r does not exist" % rel)
    budget = jev.get("budget")
    if not isinstance(budget, int) or isinstance(budget, bool) or budget <= 0:
        p("jev.budget is not a positive integer")
        budget = BUDGET_CEILING
    elif budget > BUDGET_CEILING:
        p("jev.budget %d is over the %d-byte ceiling the Jev spike validated" % (budget, BUDGET_CEILING))
    comp = jev.get("completeness")
    if not isinstance(comp, dict):
        p("jev.completeness is not an object")
    else:
        rel = comp.get("path")
        if not safe_rel(root, rel) or not os.path.isfile(os.path.join(root, rel)):
            p("jev.completeness.path %r does not exist" % rel)
        else:
            heading = "## %s" % comp.get("heading")
            lines = read_text(os.path.join(root, rel)).splitlines()
            if heading not in lines:
                p("jev.completeness.heading %r is not a heading in %s" % (comp.get("heading"), rel))
        if comp.get("verdict") not in VERDICTS:
            p("jev.completeness.verdict %r is not sufficient or insufficient" % comp.get("verdict"))
    # 2: measurement.
    m, nm = jev.get("measured"), jev.get("not_measured")
    if m is None and nm is None:
        p("jev has neither measured nor not_measured")
    elif m is not None:
        if not isinstance(m, dict):
            p("jev.measured is not an object")
        else:
            if m.get("population") not in POPULATIONS:
                p("jev.measured.population %r is not one of %s" % (m.get("population"), ", ".join(sorted(POPULATIONS))))
            for k in ("runs", "max", "p90", "over_budget"):
                v = m.get(k)
                if not isinstance(v, int) or isinstance(v, bool) or v < 0:
                    p("jev.measured.%s is not a non-negative integer" % k)
            if isinstance(m.get("runs"), int) and isinstance(m.get("over_budget"), int) and m["over_budget"] > m["runs"]:
                p("jev.measured.over_budget is more than its runs")
            if "empty" in m and (not isinstance(m["empty"], int) or isinstance(m["empty"], bool) or m["empty"] < 0):
                p("jev.measured.empty is not a non-negative integer")
            if not isinstance(m.get("on"), str) or not DATE.match(m["on"]):
                p("jev.measured.on is not a YYYY-MM-DD date")
            cmd = m.get("command")
            if not isinstance(cmd, str) or not cmd:
                p("jev.measured.command is empty")
            elif LOCAL_PATH.search(cmd):
                p("jev.measured.command holds a local path")
    elif nm not in NOT_MEASURED:
        p("jev.not_measured %r is not one of %s" % (nm, ", ".join(sorted(NOT_MEASURED))))
    # 3: the state's condition.
    want = expected_state(jev, declared)
    if state not in want:
        p("jev.state is %s, but its record makes it %s" % (state, "/".join(sorted(want))))
    # 4: budget against the gate; 6: the declaration.
    check = entry.get("check") or {}
    if check.get("kind") == "decider":
        gate, crit = find_gate(root, check, cache)
        if gate is None or crit is None:
            p("its check names no decider-check criterion %s/%s/%s in %s"
              % (check.get("state"), check.get("gate"), check.get("criterion"), check.get("template")))
        else:
            mb = int(gate.get("max_bytes", DEFAULT_MAX_BYTES))
            if mb > BUDGET_CEILING:
                p("gate %s's max_bytes %d is over the %d-byte ceiling" % (check["gate"], mb, BUDGET_CEILING))
            if isinstance(jev.get("budget"), int) and jev["budget"] != mb:
                p("jev.budget %d differs from gate %s's max_bytes %d" % (jev["budget"], check["gate"], mb))
            command = str(gate.get("command", "")).replace("{{PLUGIN_ROOT}}/", "")
            if isinstance(jev.get("slice_script"), str) and jev["slice_script"] not in command:
                p("gate %s's command doesn't run jev.slice_script %s" % (check["gate"], jev["slice_script"]))
            d = jev.get("declared")
            want_sha = declared_sha256(declaration(gate, crit))
            if not isinstance(d, dict) or not isinstance(d.get("sha256"), str):
                p("jev.declared has no sha256")
            elif d["sha256"] != want_sha:
                p("jev.declared.sha256 is stale: the declaration hashes to %s" % want_sha)
            if not isinstance(d, dict) or not isinstance(d.get("since"), str) or not DATE.match(d.get("since", "")):
                p("jev.declared.since is not a YYYY-MM-DD date")
            if state == "trusted" and crit.get("mode") != "veto":
                p("a trusted criterion's template mode is %r, not veto" % crit.get("mode"))
    # 5: runs and fixtures.
    if state in ("untrusted", "trusted"):
        if not isinstance(m, dict):
            p("an %s contract needs a measurement" % state)
        elif isinstance(m.get("runs"), int) and m["runs"] < MIN_RUNS and m.get("population") != CENSUS:
            p("measured over %d runs, fewer than %d" % (m["runs"], MIN_RUNS))
        rel = jev.get("fixtures")
        if not safe_rel(root, rel) or not os.path.isfile(os.path.join(root, rel)):
            p("jev.fixtures %r does not exist" % rel)
        else:
            _, problems = load_fixtures(os.path.join(root, rel))
            for x in problems:
                p("fixtures: %s" % x)
    # 8: false passes.
    fps = jev.get("false_passes", [])
    if not isinstance(fps, list):
        p("jev.false_passes is not a list")
        fps = []
    for fp in fps:
        if not isinstance(fp, dict):
            p("a false pass is not an object")
            continue
        for k in ("evaluated", "recorded"):
            if not isinstance(fp.get(k), str) or not DATE.match(fp[k]):
                p("a false pass has no %s date" % k)
        if fp.get("oracle") not in ORACLES:
            p("a false pass's oracle %r is not review, ci or human" % fp.get("oracle"))
        ev = fp.get("evidence")
        if not isinstance(ev, str) or not ev.startswith("https://github.com/") or LOCAL_PATH.search(ev):
            p("a false pass's evidence is not a https://github.com/ link")
    # 7: promotion.
    promo = jev.get("promotion")
    if state == "untrusted" and promo is not None:
        p("an untrusted contract holds a promotion record")
    if state == "trusted":
        out += ["%s: %s" % (eid, x) for x in check_promotion(root, jev, promo, fps, budget)]
    # 9: withholding.
    if state != "trusted" and entry.get("withhold") != "never":
        p("a %s criterion must be withhold never" % state)
    if state == "trusted" and entry.get("withhold") != "eligible":
        p("a trusted criterion must be withhold eligible")
    # 10: releasable text.
    if state in ("untrusted", "trusted"):
        # The reader that runs is this repository's, pointed at `root`, as
        # check-rule-registry.sh does: a tree under test can't swap it out.
        r = run([os.path.join(DEFAULT_ROOT, RULE_REGISTRY_SH), "--root", root, "release", eid])
        if "::shirabe-rule::" not in r.stderr or "could not release" in r.stderr:
            p("rule-registry.sh release can't print its text")
    return out


def check_promotion(root, jev, promo, fps, budget):
    out = []
    if not isinstance(promo, dict):
        return ["a trusted contract has no promotion record"]
    since = promo.get("trusted_since")
    if not isinstance(since, str) or not DATE.match(since):
        out.append("promotion.trusted_since is not a YYYY-MM-DD date")
    fr, live = promo.get("fixture_run"), promo.get("live")
    if not isinstance(fr, dict):
        out.append("promotion has no fixture_run")
    else:
        for k in ("on", "model", "declared_sha256", "fixtures_blob", "counts"):
            if k not in fr:
                out.append("promotion.fixture_run has no %s" % k)
        counts = fr.get("counts") if isinstance(fr.get("counts"), dict) else {}
        out += ["the fixture run misses the bar: %s" % r for r in fixture_bar(counts)[1]]
        rel = jev.get("fixtures")
        if isinstance(rel, str) and os.path.isfile(os.path.join(root, rel)):
            cases, _ = load_fixtures(os.path.join(root, rel))
            for k in KINDS:
                have = sum(1 for c in cases if c.get("kind") == k)
                got = sum((counts.get(k) or {}).get(a, 0) for a in ANSWERS)
                if have != got:
                    out.append("the fixture run counts %d %s cases; the file has %d" % (got, k, have))
            if fr.get("fixtures_blob") != git_blob(root, rel):
                out.append("promotion.fixture_run.fixtures_blob differs from the fixture file's")
        d = jev.get("declared") if isinstance(jev.get("declared"), dict) else {}
        if fr.get("declared_sha256") != d.get("sha256"):
            out.append("the fixture run was made under another declaration")
    if not isinstance(live, dict):
        out.append("promotion has no live record")
    else:
        for k in ("from", "to", "evaluations", "sessions", "answered", "over_budget_fallbacks", "max_input_bytes",
                  "not_graded"):
            if k not in live:
                out.append("promotion.live has no %s" % k)
        ng = live.get("not_graded")
        if "not_graded" in live and (not isinstance(ng, int) or isinstance(ng, bool) or ng < 0):
            out.append("promotion.live.not_graded is not a non-negative integer")
        out += ["the live figures miss the bar: %s" % r for r in live_bar(live, budget, jev.get("measured"))[1]]
        frm, to = live.get("from", ""), live.get("to", "")
        d = jev.get("declared") if isinstance(jev.get("declared"), dict) else {}
        if isinstance(d.get("since"), str) and frm < d["since"]:
            out.append("promotion.live.from is before declared.since")
        for fp in fps:
            if isinstance(fp, dict) and isinstance(fp.get("evaluated"), str) and frm <= fp["evaluated"]:
                out.append("promotion.live.from is not after the false pass evaluated %s" % fp["evaluated"])
        if since != to:
            out.append("promotion.trusted_since %r differs from promotion.live.to %r" % (since, to))
    blob = promo.get("slice_script_blob")
    rel = jev.get("slice_script")
    if isinstance(rel, str) and os.path.isfile(os.path.join(root, rel)) and blob != git_blob(root, rel):
        out.append("promotion.slice_script_blob differs from the slice script's")
    return out


# --- Document criteria ----------------------------------------------------------
#
# A document criterion grades one unit of a document at a time, from a
# one-state template under koto-templates/doc-criteria/ whose decider check
# runs scripts/doc-criteria/slice.py. Its rule id is a jury rubric id, and it
# may run on more than one format, so its entry's `jev` holds `state`,
# `false_passes` and one contract per format in `pairs`. Each pair is checked
# as a contract of its own (check_contract) and then held to the rules below.

_SLICERS = {}


def load_slicer(root):
    """The tree's own slice script as a module: fixtures are checked against
    the code the template runs, not a copy."""
    path = os.path.join(root, DOC_SLICER)
    if path not in _SLICERS:
        if not os.path.isfile(path):
            raise CannotRun("%s does not exist" % DOC_SLICER)
        import importlib.util
        spec = importlib.util.spec_from_file_location("doc_criteria_slice_%d" % len(_SLICERS), path)
        mod = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(mod)
        except Exception as e:  # a slicer that doesn't load can't be checked against
            raise CannotRun("%s does not load: %s" % (DOC_SLICER, type(e).__name__))
        _SLICERS[path] = mod
    return _SLICERS[path]


def sha256_file(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def contracts(entry):
    """[(label, check, jev)] for an entry: one per format for a document
    criterion, else the entry's own check and jev."""
    jev = entry.get("jev") if isinstance(entry.get("jev"), dict) else {}
    check = entry.get("check") if isinstance(entry.get("check"), dict) else {}
    pairs = jev.get("pairs")
    if not isinstance(pairs, list):
        return [(None, check, jev)]
    out = []
    for pair in pairs:
        if not isinstance(pair, dict):
            continue
        pj = dict(pair, state=jev.get("state"), false_passes=jev.get("false_passes", []))
        if "promotion" in jev:
            pj["promotion"] = jev["promotion"]
        out.append(("%s %s" % (entry.get("id"), pair.get("format")),
                    dict(check, template=pair.get("template")), pj))
    return out


def pair_stem(rule_id, fmt):
    return "%s-%s" % (fmt, rule_id)


def reference_section(root, heading):
    """The text of `## <heading>` in the Jev reference, up to the next `## `."""
    try:
        text = read_text(os.path.join(root, JEV_REFERENCE))
    except OSError:
        return None
    out, on = [], False
    for line in text.split("\n"):
        if line.startswith("## "):
            if on:
                break
            on = line.strip() == "## " + heading
            continue
        if on:
            out.append(line)
    return "\n".join(out) if on or out else None


def doc_fixture_problems(cases, rule_id, pair, slicer):
    """The document-criterion rules for fixture cases: each case's slice is the
    unit the slice script prints for its input, and each seeded-bad case names
    a good case, a change kind the contract lists, and a slice of its own."""
    out = []
    fmt = pair.get("format")
    kinds = pair.get("change_kinds") if isinstance(pair.get("change_kinds"), list) else []
    good = {c.get("id"): c for c in cases if c.get("kind") == "good"}
    for c in cases:
        cid = c.get("id")
        inp, key = c.get("input"), c.get("unit")
        if not isinstance(inp, str) or not isinstance(key, str):
            out.append("case %s needs a document `input` and the `unit` key its slice is" % cid)
            continue
        try:
            printed = dict(slicer.units(rule_id, fmt, inp))
        except Exception as e:  # the slicer's failure on a case is the case's problem
            out.append("case %s: the slice script fails on its input (%s)" % (cid, type(e).__name__))
            continue
        if printed.get(key) != c.get("slice"):
            out.append("case %s: its slice isn't what the slice script prints as %s for its input" % (cid, key))
        if c.get("kind") == "seeded-bad":
            src = good.get(c.get("of"))
            if src is None:
                out.append("case %s: `of` %r names no good case" % (cid, c.get("of")))
            elif src.get("slice") == c.get("slice"):
                out.append("case %s: its slice is its good case %s's" % (cid, c.get("of")))
            if c.get("change") not in kinds:
                out.append("case %s: change %r is not one of the contract's change kinds" % (cid, c.get("change")))
    return out


def check_fixture_run(root, label, pair, decl, cases):
    """A document criterion's recorded fixture run: the strict bar, counts that
    cover the file, and hashes of the fixture file, the slice script and the
    declaration as they are now."""
    out = []
    fr = pair.get("fixture_run")
    if not isinstance(fr, dict):
        return ["%s: jev.fixture_run is missing; record one with `fixtures`" % label]
    for k in ("on", "model", "declared_sha256", "fixtures_blob", "slicer_blob", "counts"):
        if k not in fr:
            out.append("%s: fixture_run has no %s" % (label, k))
    if not isinstance(fr.get("on"), str) or not DATE.match(fr.get("on", "")):
        out.append("%s: fixture_run.on is not a YYYY-MM-DD date" % label)
    if not isinstance(fr.get("model"), str) or not fr.get("model") or fr.get("model") == "unknown":
        out.append("%s: fixture_run.model doesn't name the decider model" % label)
    counts = fr.get("counts") if isinstance(fr.get("counts"), dict) else {}
    out += ["%s: the fixture run misses the bar: %s" % (label, r) for r in fixture_bar(counts, strict=True)[1]]
    for k in KINDS:
        have = sum(1 for c in cases if c.get("kind") == k)
        got = sum(v for v in (counts.get(k) or {}).values() if isinstance(v, int))
        if have != got:
            out.append("%s: the fixture run counts %d %s cases; the file has %d" % (label, got, k, have))
    rel = pair.get("fixtures")
    if isinstance(rel, str) and os.path.isfile(os.path.join(root, rel)) and fr.get("fixtures_blob") != git_blob(root, rel):
        out.append("%s: fixture_run.fixtures_blob differs from the fixture file's" % label)
    if fr.get("slicer_blob") != git_blob(root, DOC_SLICER):
        out.append("%s: fixture_run.slicer_blob differs from the slice script's" % label)
    if fr.get("declared_sha256") != declared_sha256(decl):
        out.append("%s: the fixture run was made under another declaration" % label)
    return out


def check_doc_pair(root, rule_id, label, pair, gate, crit, mapping):
    """Problems with one format's contract beyond check_contract's rules."""
    out = []

    def p(msg):
        out.append("%s: %s" % (label, msg))

    fmt = pair.get("format")
    if fmt not in DOC_FORMATS:
        p("format %r is not one of %s" % (fmt, ", ".join(DOC_FORMATS)))
        return out
    stem = pair_stem(rule_id, fmt)
    if pair.get("template") != "%s/%s.md" % (DOC_TEMPLATES, stem):
        p("template %r is not %s/%s.md" % (pair.get("template"), DOC_TEMPLATES, stem))
    if pair.get("slice_script") != DOC_SLICER:
        p("slice_script is not %s" % DOC_SLICER)
    slicer = load_slicer(root)
    spec = slicer.PAIRS.get((rule_id, fmt))
    cap, cut, sec = pair.get("cap"), pair.get("cut"), pair.get("section")
    if spec is None:
        p("the slice script has no units for %s on %s" % (rule_id, fmt))
    else:
        if sec != spec[0]:
            p("section %r is not the slice script's %r" % (sec, spec[0]))
        if cut is not spec[2]:
            p("cut %r is not the slice script's %r" % (cut, spec[2]))
    if not isinstance(cap, int) or isinstance(cap, bool) or not 1 <= cap <= 32:
        p("cap is not an integer from 1 to 32")
    row = next((r for r in (mapping.get("formats") or {}).get(fmt, []) or []
                if isinstance(r, dict) and r.get("rule_id") == rule_id), None)
    if row is None:
        p("%s has no row for it under %s" % (DOC_CRITERIA, fmt))
    elif (row.get("template"), row.get("section"), row.get("cap")) != (pair.get("template"), sec, cap):
        p("its template, section and cap differ from %s's row" % DOC_CRITERIA)
    if gate is not None and crit is not None:
        if gate.get("units") != "jsonl":
            p("its gate is not a unit-mode check (units: jsonl)")
        if gate.get("max_units") != cap:
            p("gate max_units %r differs from cap %r" % (gate.get("max_units"), cap))
        if gate.get("unit_document") != fmt:
            p("gate unit_document %r is not %s" % (gate.get("unit_document"), fmt))
        if gate.get("unit_section") != sec:
            p("gate unit_section %r differs from section %r" % (gate.get("unit_section"), sec))
        if pair.get("state") == "untrusted" and crit.get("mode", "shadow") != "shadow":
            p("an untrusted document criterion must be declared mode: shadow")
        for k in ("summary", "rule_text"):
            if k in crit:
                p("a shadow criterion delivers nothing, so it declares no %s" % k)
    kinds = pair.get("change_kinds")
    if not isinstance(kinds, list) or not kinds or len(set(map(str, kinds))) != len(kinds) or \
            not all(isinstance(k, str) and CHANGE_KIND.match(k) for k in kinds):
        p("change_kinds is not a non-empty list of distinct kebab-case names")
        kinds = []
    text = reference_section(root, stem)
    if text is None:
        p("%s has no `## %s` section" % (JEV_REFERENCE, stem))
    else:
        for part in DOC_PARTS:
            if "**%s.**" % part not in text:
                p("its section in %s has no %s part" % (JEV_REFERENCE, part))
        for k in kinds:
            if "`%s`" % k not in text:
                p("change kind %s isn't named in its section in %s" % (k, JEV_REFERENCE))
        budget = pair.get("budget")
        if isinstance(budget, int) and "{:,}-byte budget".format(budget) not in text:
            p("its section in %s doesn't state the %s-byte budget" % (JEV_REFERENCE, "{:,}".format(budget)))
        if isinstance(cap, int) and ("cap of %d unit" % cap) not in text:
            p("its section in %s doesn't state the cap of %d units" % (JEV_REFERENCE, cap))
    m = pair.get("measured")
    if isinstance(m, dict):
        if m.get("population") != CENSUS:
            p("a document criterion is measured over documents (population %s)" % CENSUS)
        for k in DOC_MEASURED:
            v = m.get(k)
            if not isinstance(v, int) or isinstance(v, bool) or v < 0:
                p("jev.measured.%s is not a non-negative integer" % k)
        if cut is True and m.get("units_over_budget"):
            p("a criterion that cuts its units records none over the budget")
    rel = pair.get("fixtures")
    cases = []
    if isinstance(rel, str) and safe_rel(root, rel) and os.path.isfile(os.path.join(root, rel)):
        cases, _ = load_fixtures(os.path.join(root, rel))
        out += ["%s: fixtures: %s" % (label, x) for x in doc_fixture_problems(cases, rule_id, pair, slicer)]
    if gate is not None and crit is not None:
        out += check_fixture_run(root, label, pair, declaration(gate, crit), cases)
    return out


def check_doc_map(root, mapping, registry_pairs):
    """references/doc-criteria.json against the registry, the templates on disk
    and its own pins: every pinned file's sha256 is what ships."""
    out = []
    formats, pins = mapping.get("formats"), mapping.get("pins")
    if not isinstance(formats, dict) or not isinstance(pins, dict):
        return ["%s: needs a formats map and a pins map" % DOC_CRITERIA]
    mapped = set()
    for fmt, rows in sorted(formats.items()):
        if fmt not in DOC_FORMATS or not isinstance(rows, list):
            out.append("%s: format %r is not one of %s with a list of criteria" % (DOC_CRITERIA, fmt, ", ".join(DOC_FORMATS)))
            continue
        for r in rows:
            rid = r.get("rule_id") if isinstance(r, dict) else None
            if rid not in DOC_RULE_IDS:
                out.append("%s: %s lists %r, not a document criterion" % (DOC_CRITERIA, fmt, rid))
                continue
            mapped.add((rid, fmt))
            if (rid, fmt) not in registry_pairs:
                out.append("%s: %s %s has no pair in the registry" % (DOC_CRITERIA, fmt, rid))
            t = r.get("template")
            if not isinstance(t, str) or t not in pins:
                out.append("%s: %s %s's template %r has no pin" % (DOC_CRITERIA, fmt, rid, t))
    for key in registry_pairs:
        if key not in mapped:
            out.append("%s: the registry's %s %s pair has no row" % (DOC_CRITERIA, key[1], key[0]))
    if DOC_SLICER not in pins:
        out.append("%s: %s has no pin" % (DOC_CRITERIA, DOC_SLICER))
    wanted = {r.get("template") for rows in formats.values() if isinstance(rows, list)
              for r in rows if isinstance(r, dict)} | {DOC_SLICER}
    for rel, want in sorted(pins.items()):
        if rel not in wanted:
            out.append("%s: pins %s, which is neither the slice script nor a mapped template" % (DOC_CRITERIA, rel))
            continue
        if not safe_rel(root, rel) or not os.path.isfile(os.path.join(root, rel)):
            out.append("%s: pinned file %s does not exist" % (DOC_CRITERIA, rel))
        elif sha256_file(os.path.join(root, rel)) != want:
            out.append("%s: %s's sha256 differs from its pin" % (DOC_CRITERIA, rel))
    for path in sorted(glob.glob(os.path.join(root, DOC_TEMPLATES, "*.md"))):
        rel = os.path.relpath(path, root)
        if not rel.endswith(".mermaid.md") and rel not in wanted:
            out.append("%s: %s is not in its map" % (DOC_CRITERIA, rel))
    return out


# --- The shadow guard -----------------------------------------------------------
#
# Every document criterion runs in shadow. No template may declare one of the
# six rule ids in `veto`, and no template may set any decider value to `auto`:
# not in this tree (tests and throwaway templates included), not in a koto
# template path given to the check, not in a template another one includes
# through `materialize_children.default_template`, and not through a project
# `.koto/config.toml` overlay or a KOTO_DECIDER=auto a template sets. The
# readers below take parsed templates, so the rules are tested on parsed data
# without writing such a template anywhere.

SKIP_DIRS = {".git", "target", "node_modules", "__pycache__"}
AUTO_ENV = re.compile(r"\bKOTO_DECIDER\s*=\s*[\"']?auto\b")


def tree_templates(root):
    """Every koto template file in a tree: a .md whose frontmatter declares
    `initial_state:` and `states:`."""
    out = []
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        for name in sorted(files):
            if name.endswith(".md") and not name.endswith(".mermaid.md"):
                path = os.path.join(dirpath, name)
                if is_template(path):
                    out.append(path)
    return out


def is_template(path):
    try:
        text = read_text(path, errors="replace")
    except OSError:
        return False
    if not text.startswith("---\n"):
        return False
    fm = text[4:].split("\n---", 1)[0]
    return bool(re.search(r"(?m)^initial_state:", fm)) and bool(re.search(r"(?m)^states:", fm))


def parse_template(path):
    """The template's frontmatter as JSON, through yq."""
    r = run(["yq", "--front-matter=extract", "-o=json", ".", path])
    if r.returncode != 0:
        raise CannotRun("yq could not read %s: %s" % (path, r.stderr.strip()[:200]))
    try:
        return json.loads(r.stdout or "{}") or {}
    except ValueError:
        raise CannotRun("yq printed no JSON for %s" % path)


def shadow_problems(where, doc):
    """Problems in one parsed template: a document criterion in veto, or a
    decider value in auto."""
    out = []
    for sname, state in sorted(((doc or {}).get("states") or {}).items()):
        state = state if isinstance(state, dict) else {}
        for gname, gate in sorted((state.get("gates") or {}).items()):
            if not isinstance(gate, dict) or gate.get("type") != "decider-check":
                continue
            for cid, crit in sorted((gate.get("criteria") or {}).items()):
                mode = (crit or {}).get("mode") if isinstance(crit, dict) else None
                if cid in DOC_RULE_IDS and mode == "veto":
                    out.append("%s: state %s gate %s declares document criterion %s in veto" % (where, sname, gname, cid))
                if mode == "auto":
                    out.append("%s: state %s gate %s sets criterion %s to auto" % (where, sname, gname, cid))
        for fname, field in sorted((state.get("accepts") or {}).items()):
            dec = field.get("decider") if isinstance(field, dict) else None
            answers = dec.get("answers") if isinstance(dec, dict) else None
            for value, ans in sorted((answers or {}).items(), key=lambda kv: str(kv[0])):
                if isinstance(ans, dict) and ans.get("mode") == "auto":
                    out.append("%s: state %s field %s sets decider value %s to auto" % (where, sname, fname, value))
    return out


def includes(path, doc):
    """The template files a parsed template includes: each state's
    materialize_children.default_template, resolved from the template's own
    directory."""
    out = []
    for state in ((doc or {}).get("states") or {}).values():
        mc = state.get("materialize_children") if isinstance(state, dict) else None
        t = mc.get("default_template") if isinstance(mc, dict) else None
        if isinstance(t, str) and t:
            out.append(os.path.normpath(os.path.join(os.path.dirname(path), t)))
    return out


def overlay_mode(text):
    """The decider mode a koto config file sets, or None: `mode` under a
    `[decider]` table, or a dotted `decider.mode` key."""
    table = ""
    for raw in text.split("\n"):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        m = re.match(r"^\[\s*([A-Za-z0-9_.\"' -]+?)\s*\]$", line)
        if m:
            table = m.group(1).replace('"', "").replace("'", "").replace(" ", "")
            continue
        m = re.match(r"^([A-Za-z0-9_.\"' -]+?)\s*=\s*[\"']([^\"']*)[\"']", line)
        if not m:
            continue
        key = m.group(1).replace('"', "").replace("'", "").replace(" ", "")
        full = "%s.%s" % (table, key) if table else key
        if full == "decider.mode":
            return m.group(2)
    return None


def config_files(root, paths):
    """The project configs that can overlay a template's decider mode: every
    .koto/config.toml in the tree, and for each given path, the one in each
    directory from it up to its repository root."""
    found = []
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
        if os.path.basename(dirpath) == ".koto" and "config.toml" in files:
            found.append(os.path.join(dirpath, "config.toml"))
    for p in paths:
        d = os.path.dirname(os.path.abspath(p)) if os.path.isfile(p) else os.path.abspath(p)
        while True:
            c = os.path.join(d, ".koto", "config.toml")
            if os.path.isfile(c) and c not in found:
                found.append(c)
            if os.path.isdir(os.path.join(d, ".git")) or os.path.dirname(d) == d:
                break
            d = os.path.dirname(d)
    return found


def shadow_guard(root, koto_paths, parse=parse_template, read=read_text):
    """Problems from the shadow guard over the tree and the given paths.
    `parse` and `read` are the readers; tests replace them."""
    out, seen = [], set()
    queue = list(tree_templates(root))
    for p in koto_paths:
        if os.path.isdir(p):
            queue += tree_templates(p)
        else:
            queue.append(os.path.abspath(p))
    while queue:
        path = os.path.abspath(queue.pop(0))
        if path in seen:
            continue
        seen.add(path)
        where = os.path.relpath(path, root) if path.startswith(root + os.sep) else path
        if not os.path.isfile(path):
            out.append("%s: an included template does not exist" % where)
            continue
        try:
            text = read(path)
        except OSError:
            out.append("%s: cannot be read" % where)
            continue
        if AUTO_ENV.search(text):
            out.append("%s: sets KOTO_DECIDER=auto" % where)
        doc = parse(path)
        out += shadow_problems(where, doc)
        queue += includes(path, doc)
    for c in config_files(root, koto_paths):
        try:
            mode = overlay_mode(read(c))
        except OSError:
            continue
        if mode == "auto":
            where = os.path.relpath(c, root) if c.startswith(root + os.sep) else c
            out.append("%s: sets the decider mode to auto" % where)
    return out


def withhold_calls(root, cache, registry_by_id):
    """Problems with templates that call the withhold script (rule 12)."""
    out = []
    for rel in template_files(root):
        text = read_text(os.path.join(root, rel))
        if WITHHOLD_SCRIPT not in text:
            continue
        states = template_states(root, rel, cache) or {}
        commands = []
        for sname, state in states.items():
            state = state or {}
            da = state.get("default_action")
            if isinstance(da, dict) and isinstance(da.get("command"), str):
                commands.append((sname, da["command"]))
            for g in (state.get("gates") or {}).values():
                if isinstance(g, dict) and isinstance(g.get("command"), str):
                    commands.append((sname, g["command"]))
        called = [(s, c) for s, c in commands if WITHHOLD_SCRIPT in c]
        mentions = text.count(WITHHOLD_SCRIPT)
        if mentions > len(called):
            out.append("%s: names %s outside a state's command" % (rel, WITHHOLD_SCRIPT))
        for sname, cmd in called:
            m = WITHHOLD_CALL.search(cmd)
            rid = m.group(1) if m else ""
            if not RULE_ID.match(rid):
                out.append("%s: state %s calls %s without a literal rule id" % (rel, sname, WITHHOLD_SCRIPT))
                continue
            e = registry_by_id.get(rid)
            jev = (e or {}).get("jev") or {}
            if not e or jev.get("state") != "trusted":
                out.append("%s: state %s withholds %s, which isn't a trusted Jev criterion" % (rel, sname, rid))
                continue
            if (e.get("check") or {}).get("template") != rel:
                out.append("%s: state %s withholds %s, whose check is in another template" % (rel, sname, rid))
            directive = template_directive(root, rel, sname)
            # The id must end where the release names it, so `release a/b`
            # isn't satisfied by a directive that releases `a/bc`.
            release = re.compile(r"\brelease\s+%s(?![A-Za-z0-9/_-])" % re.escape(rid))
            if "rule-registry.sh" not in directive or not release.search(directive):
                out.append("%s: state %s withholds %s but its directive doesn't run rule-registry.sh release %s"
                           % (rel, sname, rid, rid))
    # Templates were judged above, call by call; every other file under these
    # roots may not name the script at all.
    templates = set(template_files(root))
    for d in ("skills", "koto-templates", "hooks"):
        for dirpath, _, files in os.walk(os.path.join(root, d)):
            for name in files:
                rel = os.path.relpath(os.path.join(dirpath, name), root)
                if rel in templates:
                    continue
                try:
                    if WITHHOLD_SCRIPT in read_text(os.path.join(dirpath, name), errors="replace"):
                        out.append("%s: calls %s; only a template's command may" % (rel, WITHHOLD_SCRIPT))
                except OSError:
                    pass
    return out


def history(root, base, registry):
    """Problems against the registry at `base` (rules 13 and 14)."""
    r = run(["git", "-C", root, "show", "%s:%s" % (base, REGISTRY)])
    if r.returncode != 0:
        return []  # a base with no registry has no history to keep
    try:
        old = {e.get("id"): e for e in json.loads(r.stdout).get("rules", []) if isinstance(e, dict)}
    except ValueError:
        raise CannotRun("the registry at %s does not parse" % base)
    d = run(["git", "-C", root, "log", "-1", "--format=%cs", base])
    if d.returncode != 0:
        raise CannotRun("cannot read the date of %s" % base)
    base_date = d.stdout.strip()
    new = {e.get("id"): e for e in registry.get("rules", []) if isinstance(e, dict)}
    out = []
    for eid, e in sorted(old.items()):
        oj = e.get("jev")
        if not isinstance(oj, dict):
            continue
        nj = (new.get(eid) or {}).get("jev")
        if not isinstance(nj, dict):
            out.append("%s: its jev object was removed" % eid)
            continue
        ofp, nfp = oj.get("false_passes") or [], nj.get("false_passes") or []
        if nfp[:len(ofp)] != ofp:
            out.append("%s: a false pass recorded at the base was changed or removed" % eid)
        olds = {lbl: cj for lbl, _, cj in contracts(e)}
        news = {lbl: cj for lbl, _, cj in contracts(new.get(eid) or {})}
        for lbl, ocj in sorted(olds.items(), key=lambda kv: str(kv[0])):
            name = lbl or eid
            od = ocj.get("declared") or {}
            ncj = news.get(lbl)
            if ncj is None:
                if od.get("sha256"):
                    out.append("%s: its declared record was removed" % name)
                continue
            nd = ncj.get("declared") or {}
            if od.get("sha256") and not nd.get("sha256"):
                out.append("%s: its declared record was removed" % name)
            elif od.get("sha256") and od["sha256"] != nd["sha256"]:
                if not isinstance(nd.get("since"), str) or nd["since"] < base_date:
                    out.append("%s: its declaration changed, but declared.since %s is before the base's date %s"
                               % (name, nd.get("since"), base_date))
    return out


def cmd_check(args):
    root = os.path.realpath(args.root)
    try:
        registry = read_json(os.path.join(root, REGISTRY))
        crit_file = read_json(os.path.join(root, CRITERIA))
        criteria = {c.get("rule_id"): c for c in crit_file.get("criteria", []) if isinstance(c, dict)}
        cache = {}
        rules = [e for e in registry.get("rules", []) if isinstance(e, dict)]
        by_id = {e.get("id"): e for e in rules}
        gates = decider_gates(root, cache)
        declared_ids = set(gates)
        # A tree with no document criteria has no map to hold them to.
        has_map = os.path.isfile(os.path.join(root, DOC_CRITERIA))
        mapping = read_json(os.path.join(root, DOC_CRITERIA)) if has_map else {"formats": {}, "pins": {}}
        doc_pairs = {}
        problems = []
        for e in rules:
            if not isinstance(e.get("id"), str):
                continue
            jev = e.get("jev")
            if not is_jev_entry(e, criteria):
                if jev is not None:
                    problems.append("%s: carries jev but isn't a Jev criterion" % e["id"])
                continue
            if e.get("status") != "active":
                continue
            if not isinstance(jev, dict):
                problems.append("%s: a Jev criterion with no jev contract" % e["id"])
                continue
            pairs = jev.get("pairs")
            if pairs is not None and (not isinstance(pairs, list) or not pairs):
                problems.append("%s: jev.pairs is not a non-empty list" % e["id"])
                continue
            if pairs is not None:
                if e["id"] not in DOC_RULE_IDS:
                    problems.append("%s: only a document criterion carries jev.pairs" % e["id"])
                templates = [x.get("template") for x in pairs if isinstance(x, dict)]
                if (e.get("check") or {}).get("template") not in templates:
                    problems.append("%s: check.template is none of its pairs' templates" % e["id"])
                fmts = [x.get("format") for x in pairs if isinstance(x, dict)]
                if len(set(fmts)) != len(fmts):
                    problems.append("%s: a format has two pairs" % e["id"])
            elif e["id"] in DOC_RULE_IDS and (e.get("check") or {}).get("kind") == "decider":
                problems.append("%s: a document criterion holds its contracts in jev.pairs" % e["id"])
            for label, c, cj in contracts(e):
                declared = c.get("kind") == "decider" and \
                    (c.get("template"), c.get("state"), c.get("gate"), c.get("criterion")) in declared_ids
                problems += check_contract(root, dict(e, check=c), cj, criteria, cache, declared, label)
                if pairs is not None:
                    gate, crit = find_gate(root, c, cache)
                    doc_pairs[(e["id"], cj.get("format"))] = cj
                    problems += check_doc_pair(root, e["id"], label, cj, gate, crit, mapping)
        # The document criteria's map and pins.
        if has_map:
            problems += check_doc_map(root, mapping, doc_pairs)
        elif doc_pairs:
            problems.append("%s does not exist, so the document criteria have no pins" % DOC_CRITERIA)
        # 11: every declared decider criterion has an untrusted or trusted entry.
        for t, s, g, cid in gates:
            match = [(e, cj) for e in rules if (e.get("check") or {}).get("kind") == "decider"
                     for _, c, cj in contracts(e)
                     if (c.get("template"), c.get("state"), c.get("gate"), c.get("criterion")) == (t, s, g, cid)]
            if not match:
                problems.append("%s: decider check %s/%s criterion %s has no registry entry" % (t, s, g, cid))
            elif match[0][1].get("state") not in ("untrusted", "trusted"):
                problems.append("%s: decider check %s/%s criterion %s is declared, but its entry is %s"
                                % (t, s, g, cid, match[0][1].get("state")))
        # 12: who may call the withhold script, and for which rule.
        problems += withhold_calls(root, cache, by_id)
        # The shadow guard: no document criterion in veto, no decider value in auto.
        problems += shadow_guard(root, args.koto_templates)
        if args.base:
            problems += history(root, args.base, registry)
    except CannotRun as e:
        fail2(str(e))
    for x in problems:
        print("%s: %s" % (PROG, x))
    if problems:
        print("%s: %d problem(s)" % (PROG, len(problems)))
        return 1
    return 0


def pair_check(e, fmt):
    """(check, jev) for one of an entry's contracts: its only one, or the
    format's for a document criterion. Exits 2 when that doesn't resolve."""
    cs = contracts(e)
    if fmt:
        cs = [x for x in cs if x[2].get("format") == fmt]
        if not cs:
            fail2("%s has no %s contract" % (e.get("id"), fmt))
    elif len(cs) > 1:
        fail2("%s runs on more than one format; name one with --format" % e.get("id"))
    return cs[0][1], cs[0][2]


def cmd_declared_hash(args):
    root = os.path.realpath(args.root)
    e = decider_entry(root, args.rule_id)
    check, _ = pair_check(e, args.format)
    try:
        gate, crit = find_gate(root, check, {})
    except CannotRun as x:
        fail2(str(x))
    if gate is None or crit is None:
        fail2("%s's check names no decider-check criterion" % args.rule_id)
    decl = declaration(gate, crit)
    print(canonical(decl))
    print(declared_sha256(decl))
    return 0


def cmd_pins(args):
    root = os.path.realpath(args.root)
    try:
        mapping = read_json(os.path.join(root, DOC_CRITERIA))
    except CannotRun as x:
        fail2(str(x))
    rels = sorted({r.get("template") for rows in (mapping.get("formats") or {}).values() if isinstance(rows, list)
                   for r in rows if isinstance(r, dict) and isinstance(r.get("template"), str)} | {DOC_SLICER})
    pins = {}
    for rel in rels:
        if not safe_rel(root, rel) or not os.path.isfile(os.path.join(root, rel)):
            fail2("%s does not exist" % rel)
        pins[rel] = sha256_file(os.path.join(root, rel))
    print(json.dumps({"pins": pins}, indent=2, sort_keys=True))
    return 0


# --- measure ------------------------------------------------------------------

# The session keys a lower-bound slice is the byte length of: what a /work-on
# session keeps of the part of a slice a script could build without the diff.
# The full slice of the question these stand for also carries the diff, so it
# can only be larger (references/jev-criteria.md, rs-019 and rs-020).
SESSION_KEY_SLICES = {
    "criteria-plan": ("review_level_criteria.txt", "plan.md"),
    "design-context": ("context.md",),
}
DECISION_REASONS_SH = "skills/work-on/scripts/decision-reasons.sh"
SESSION_SLICES = ("review-facts", "decision-reasons") + tuple(SESSION_KEY_SLICES)


def work_on_sessions(dirs):
    """Each /work-on session directory under the given roots: the ones that
    recorded review facts."""
    out = []
    for d in dirs:
        out += sorted(glob.glob(os.path.join(d, "*", "ctx", "review_facts.json")))
    return out


def key_bytes(ctx, names):
    """The summed byte length of the named context keys, or the reason a
    session can't be measured: "missing" for a key that isn't there, "symlink"
    for one that is a symlink and so may not be the session's own."""
    total = 0
    for name in names:
        p = os.path.join(ctx, name)
        if os.path.islink(p):
            return None, "symlink"
        if not os.path.isfile(p):
            return None, "missing"
        total += os.path.getsize(p)
    return total, ""


def session_logs(dirs):
    """Every koto session log under the given roots, gzipped copies included."""
    out = []
    for d in dirs:
        for pattern in ("koto-*.state.jsonl", "koto-*.state.jsonl.gz"):
            out += sorted(glob.glob(os.path.join(d, "**", pattern), recursive=True))
    return out


def log_session_id(path):
    """The session_id on a log's header line, or None when it has none."""
    opener = gzip.open if path.endswith(".gz") else open
    try:
        with opener(path, "rt", encoding="utf-8", errors="replace") as f:
            head = json.loads(f.readline())
    except (OSError, EOFError, ValueError):
        return None
    sid = head.get("session_id") if isinstance(head, dict) else None
    return sid if isinstance(sid, str) and sid else None


def log_entered(path, state):
    """Whether a session log records a transition into the state, which is
    where a criterion's gate runs. A log that can't be read entered nothing."""
    opener = gzip.open if path.endswith(".gz") else open
    needle = '"%s"' % state
    try:
        with opener(path, "rt", encoding="utf-8", errors="replace") as f:
            for line in f:
                if needle not in line:
                    continue
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                if isinstance(ev, dict) and ev.get("type") in ("transitioned", "directed_transition") \
                        and isinstance(ev.get("payload"), dict) and ev["payload"].get("to") == state:
                    return True
    except (OSError, EOFError):
        return False
    return False


def decision_slice_bytes(script, path):
    """The byte length of decision-reasons.sh's slice of one log, or None when
    the script can't read it. A gzipped log goes through a temporary file, so
    the script reads every log the way the gate does."""
    if not path.endswith(".gz"):
        r = run([script, "slice", path])
    else:
        with tempfile.NamedTemporaryFile(suffix=".jsonl") as t:
            try:
                with gzip.open(path, "rb") as f:
                    shutil.copyfileobj(f, t)
            except (OSError, EOFError):
                return None
            t.flush()
            r = run([script, "slice", t.name])
    if r.returncode != 0:
        return None
    return len(r.stdout.encode("utf-8"))


# How each skip reason is said on stderr.
SKIP_MESSAGES = {
    "unprojected": "skipped %d session(s) whose facts didn't project",
    "missing": "skipped %d session(s) with a missing key",
    "symlink": "skipped %d session(s) with a symlink key",
    "unsliced": "skipped %d log(s) the slice script couldn't read",
    "no-id": "skipped %d log(s) with no session_id",
}


def measure_sessions(args):
    root = os.path.realpath(args.root)
    sizes, skipped, empty = [], {}, None
    if args.slice == "review-facts":
        script = os.path.join(root, REVIEW_LEVEL_SH)
        for path in work_on_sessions(args.dir):
            # "standard" is the longest level name, so the size is an upper bound.
            # The slice renders the rules copy the session stored, as the gate
            # does; a session without one gets the shipped rules, as there.
            # The copy is the context key review-level.sh calls RULES_KEY,
            # which koto keeps beside review_facts.json in the session's ctx.
            argv = [script, "project", path, "standard"]
            rules = os.path.join(os.path.dirname(path), "review_level_rules.tsv")
            if os.path.isfile(rules) and not os.path.islink(rules) and os.path.getsize(rules):
                argv.append(rules)
            r = run(argv)
            if r.returncode != 0:
                skipped["unprojected"] = skipped.get("unprojected", 0) + 1
                continue
            sizes.append(len(r.stdout.encode("utf-8")))
        slice_arg = ""
    elif args.slice == "decision-reasons":
        # A run is a graded session: one per session_id, however many roots
        # or copies hold its log, and only when its slice isn't empty, since
        # koto grades nothing for an empty one. Copies of one session take
        # the largest slice, the latest log being the longest. `empty` counts
        # the sessions that reached scrutiny, where the gate runs, with an
        # empty slice: the share the live bar's not-graded share is held to.
        script = os.path.join(root, DECISION_REASONS_SH)
        by_id, reached = {}, set()
        for path in session_logs(args.dir):
            sid = log_session_id(path)
            if sid is None:
                skipped["no-id"] = skipped.get("no-id", 0) + 1
                continue
            n = decision_slice_bytes(script, path)
            if n is None:
                skipped["unsliced"] = skipped.get("unsliced", 0) + 1
                continue
            by_id[sid] = max(n, by_id.get(sid, 0))
            if log_entered(path, "scrutiny"):
                reached.add(sid)
        sizes = [n for n in by_id.values() if n]
        empty = sum(1 for sid, n in by_id.items() if not n and sid in reached)
        slice_arg = " --slice decision-reasons"
    else:
        for path in work_on_sessions(args.dir):
            n, why = key_bytes(os.path.dirname(path), SESSION_KEY_SLICES[args.slice])
            if n is None:
                skipped[why] = skipped.get(why, 0) + 1
                continue
            sizes.append(n)
        slice_arg = " --slice %s" % args.slice
    for why, n in sorted(skipped.items()):
        # Said out loud, so a short run count is never mistaken for the corpus.
        print("%s: %s" % (PROG, SKIP_MESSAGES[why] % n), file=sys.stderr)
    return figures(sizes, args.budget, "koto-sessions",
                   "python3 scripts/jev-criteria/jev_criteria.py measure sessions --dir <koto sessions>%s --budget %d"
                   % (slice_arg, args.budget), empty)


def load_review_shadow(root):
    import importlib.util
    spec = importlib.util.spec_from_file_location("review_shadow", os.path.join(root, "scripts/review-shadow/review-shadow.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def split_diff(diff):
    patches, cur = {}, None
    for line in diff.split("\n"):
        m = re.match(r"^diff --git a/(.*) b/(.*)$", line)
        if m:
            cur = m.group(2)
            patches[cur] = []
            continue
        if cur is None or line.startswith(("index ", "--- ", "+++ ", "new file", "deleted file", "similarity", "rename ")):
            continue
        patches[cur].append(line)
    return {k: "\n".join(v) for k, v in patches.items()}


def pr_slice_size(rs, kind, meta, patches, texts):
    """The bytes of one whole-run slice of `kind` for one pull request, or None
    when the pull request has no unit of that kind."""
    files = [{"path": f["path"], "status": "modified", "additions": f.get("additions", 0),
              "deletions": f.get("deletions", 0), "patch": patches.get(f["path"], "")} for f in meta["files"]]
    if kind == "pr-summary":
        return rs.utf8_len(rs.part1(meta.get("body") or "")) + rs.utf8_len(rs.diffstat(files))
    if kind == "code-hunks":
        total = 0
        for f in files:
            if f["path"].endswith(rs.NON_CODE_SUFFIXES) or not f["patch"]:
                continue
            plen = rs.utf8_len(f["path"])
            units = [u for h in rs.split_hunks(f["patch"]) for u in rs.hunk_units(h, plen)]
            sel = [u for u in units if rs.hunk_has_comment(u)]
            if sel:
                total += plen + 1 + rs.utf8_len("\n".join(sel)) + 1
        return total or None
    if kind == "doc-pairs":
        md = [f for f in files if f["path"].endswith(".md")]
        slices, _ = rs.slice_doc_pairs({"files": md, "texts": texts})
        return sum(s["bytes"] for s in slices) or None
    raise CannotRun("unknown kind %s" % kind)


def measure_prs(args):
    root = os.path.realpath(args.root)
    rs = load_review_shadow(root)
    env = {k: v for k, v in os.environ.items() if k != "GH_TOKEN"}

    def gh(*a):
        r = run(["gh"] + list(a), env=env)
        if r.returncode != 0:
            raise CannotRun("gh %s failed: %s" % (" ".join(a[:2]), r.stderr.strip()[:200]))
        return r.stdout

    sizes = []
    for repo in args.repo:
        prs = json.loads(gh("pr", "list", "-R", repo, "--state", "merged", "--limit", str(args.limit),
                            "--json", "number,mergeCommit"))
        for pr in prs:
            num = str(pr["number"])
            meta = json.loads(gh("pr", "view", num, "-R", repo, "--json", "body,files"))
            patches = split_diff(gh("pr", "diff", num, "-R", repo))
            texts = {}
            if args.kind == "doc-pairs":
                # The documents as they stood when the pull request merged,
                # from a local clone of `repo` (--git-dir).
                oid = (pr.get("mergeCommit") or {}).get("oid")
                for f in meta["files"]:
                    if f["path"].endswith(".md") and oid:
                        texts[f["path"]] = run(["git", "-C", args.git_dir or root, "show",
                                                "%s:%s" % (oid, f["path"])]).stdout
            size = pr_slice_size(rs, args.kind, meta, patches, texts)
            if size is not None:
                sizes.append(size)
    return figures(sizes, args.budget, "merged-prs",
                   "python3 scripts/jev-criteria/jev_criteria.py measure prs %s --limit %d --kind %s --budget %d"
                   % (" ".join("--repo %s" % r for r in args.repo), args.limit, args.kind, args.budget)
                   + (" --git-dir <a clone of the repository>" if args.kind == "doc-pairs" else ""))


def measure_records(args):
    sizes = []
    for path in sorted(glob.glob(os.path.join(args.dir, "**", "*.json"), recursive=True)):
        try:
            rec = json.loads(read_text(path))
        except (OSError, ValueError):
            continue
        if not isinstance(rec, dict):
            continue
        xs = [s.get("bytes") or 0 for s in rec.get("slices") or [] if isinstance(s, dict) and s.get("kind") == args.kind]
        if xs:
            sizes.append(sum(xs))
    return figures(sizes, args.budget, "review-shadow-records",
                   "python3 scripts/jev-criteria/jev_criteria.py measure records --dir <review-shadow store> --kind %s --budget %d"
                   % (args.kind, args.budget))


def doc_files(roots, fmt):
    """Every <FORMAT>-*.md under the roots, symlinks left out, each once."""
    out = set()
    for r in roots:
        for path in glob.glob(os.path.join(r, "**", "%s-*.md" % fmt.upper()), recursive=True):
            if not os.path.islink(path) and os.path.isfile(path):
                out.add(os.path.realpath(path))
    return sorted(out)


def measure_docs(args):
    """A document criterion's units over every document of its format under the
    roots. A run is a document with at least one unit; `empty` counts the rest.
    `over_budget` counts the documents holding a unit over the budget, which is
    what the 5% line is drawn on, and the unit figures sit beside it."""
    root = os.path.realpath(args.root)
    slicer = load_slicer(root)
    if (args.criterion, args.format) not in slicer.PAIRS:
        raise CannotRun("the slice script has no units for %s on %s" % (args.criterion, args.format))
    mapping = read_json(os.path.join(root, DOC_CRITERIA))
    row = next((r for r in (mapping.get("formats") or {}).get(args.format, []) or []
                if isinstance(r, dict) and r.get("rule_id") == args.criterion), None)
    if row is None or not isinstance(row.get("cap"), int):
        raise CannotRun("%s has no cap for %s on %s" % (DOC_CRITERIA, args.criterion, args.format))
    cap = row["cap"]
    sizes, per, over_docs, empty, over_cap = [], [], 0, 0, 0
    for path in doc_files(args.roots, args.format):
        try:
            text = read_text(path, errors="replace")
        except OSError:
            continue
        us = [slicer.utf8_len(t) for _, t in slicer.units(args.criterion, args.format, text)]
        if not us:
            empty += 1
            continue
        sizes += us
        per.append(len(us))
        over_docs += 1 if max(us) > args.budget else 0
        over_cap += 1 if len(us) > cap else 0
    out = figures(per, 0, CENSUS, "python3 scripts/jev-criteria/jev_criteria.py measure docs --criterion %s --format %s "
                  "--roots <shirabe>/docs <koto>/docs <niwa>/docs --budget %d"
                  % (args.criterion, args.format, args.budget), empty)
    out.update({"max": max(sizes) if sizes else 0, "p90": nearest_rank(sizes, 0.9), "over_budget": over_docs,
                "units": len(sizes), "units_over_budget": sum(1 for x in sizes if x > args.budget),
                "units_per_doc_p90": nearest_rank(per, 0.9), "units_per_doc_max": max(per) if per else 0,
                "over_cap": over_cap})
    return out


def cmd_measure(args):
    try:
        out = {"sessions": measure_sessions, "prs": measure_prs, "records": measure_records,
               "docs": measure_docs}[args.population](args)
    except CannotRun as e:
        fail2(str(e))
    print(json.dumps(out, sort_keys=True))
    return 0


# --- fixtures: the Jev client -------------------------------------------------

JEV_ENDPOINT = "https://api.typesafe.ai/v1/systemone"  # koto's default decider endpoint
JEV_MODEL = "jev-latest"
JEV_TIMEOUT = 30  # seconds per request; a fixture run is a few dozen of them
LOOPBACK = {"localhost", "127.0.0.1", "::1"}


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse every redirect, so the key never reaches a second host."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, "redirect refused", headers, fp)


# Where an operating system keeps its own trust roots, for a Python that ships
# without any (the python.org installer on macOS, until its "Install
# Certificates" step runs): without them every send fails a certificate check.
OS_TRUST_BUNDLES = ("/etc/ssl/cert.pem", "/etc/ssl/certs/ca-certificates.crt")


def tls_context():
    import ssl
    ctx = ssl.create_default_context()
    if ctx.get_ca_certs() or os.environ.get("SSL_CERT_FILE") or os.environ.get("SSL_CERT_DIR"):
        return ctx
    for path in OS_TRUST_BUNDLES:
        if os.path.isfile(path):
            try:
                ctx.load_verify_locations(cafile=path)
                break
            except (ssl.SSLError, OSError):
                continue
    return ctx


def build_opener():
    """The network opener. Tests replace it with one that refuses every call."""
    return urllib.request.build_opener(_NoRedirect, urllib.request.HTTPSHandler(context=tls_context()))


def check_endpoint(url):
    """None when `url` may receive the key, else why not: https anywhere, http
    only to loopback, never with user information."""
    try:
        u = urllib.parse.urlsplit(url)
        host = u.hostname
    except ValueError:
        return "the endpoint is not a URL"
    if u.username is not None or u.password is not None or "@" in u.netloc:
        return "the endpoint carries user information"
    if u.scheme == "https" and host:
        return None
    if u.scheme == "http" and host in LOOPBACK:
        return None
    return "the endpoint must be https, or http to localhost, 127.0.0.1 or ::1"


def is_loopback(url):
    try:
        return urllib.parse.urlsplit(url).hostname in LOOPBACK
    except ValueError:
        return False


# A loopback endpoint is a stub on this machine: it gets this placeholder,
# and KOTO_DECIDER_API_KEY isn't read at all, so no test or local run can hand
# the real key to a stub.
LOOPBACK_KEY = "loopback-stub"


def decider_entry(root, rule_id):
    """The registry entry for `rule_id`, which must be a decider check; exits 2
    otherwise."""
    try:
        registry = read_json(os.path.join(root, REGISTRY))
    except CannotRun as x:
        fail2(str(x))
    e = next((e for e in registry.get("rules", []) if isinstance(e, dict) and e.get("id") == rule_id), None)
    if not e or (e.get("check") or {}).get("kind") != "decider":
        fail2("%s is not a decider entry" % rule_id)
    return e


def transport(endpoint, key):
    """send(body) -> (status, raw). The key goes in an unredirected
    Authorization header and nowhere else; nothing from a failure is kept,
    since an error can echo request headers."""
    import http.client
    opener = []

    def send(body):
        if not opener:
            opener.append(build_opener())
        req = urllib.request.Request(endpoint, data=json.dumps(body).encode("utf-8"), method="POST",
                                     headers={"Content-Type": "application/json"})
        req.add_unredirected_header("Authorization", "Bearer " + key)
        try:
            with opener[0].open(req, timeout=JEV_TIMEOUT) as resp:
                return resp.status, resp.read()
        except urllib.error.HTTPError as e:
            return e.code, b""
        except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException, ValueError):
            return None, b""
    return send


def ask(send, body):
    """One request, retried once on a transport failure, a 5xx or an unreadable
    answer, as koto does. The parsed answer, or None."""
    for _ in (1, 2):
        status, raw = send(body)
        if status is None:
            continue
        if status != 200:
            if status < 500:
                return None
            continue
        try:
            answer = json.loads(raw)
        except ValueError:
            continue
        if isinstance(answer, dict) and isinstance(answer.get("answers"), dict):
            return answer
    return None


def map_answer(answer, cid, threshold):
    """koto's threshold rule: a value wins only with the highest probability
    and at least the threshold; anything else is unclear. `error` when the
    answer can't be read."""
    if answer is None:
        return "error"
    a = answer["answers"].get(cid)
    probs = a.get("probabilities") if isinstance(a, dict) else None
    if not isinstance(probs, dict) or set(probs) != {"pass", "fail", "unclear"} or \
            not all(isinstance(v, (int, float)) and not isinstance(v, bool) and 0 <= v <= 1 for v in probs.values()):
        return "error"
    win = max(probs, key=probs.get)
    if win == "unclear" or probs[win] < threshold:
        return "unclear"
    return win


def cmd_fixtures(args):
    root = os.path.realpath(args.root)
    e = decider_entry(root, args.rule_id)
    check, jev = pair_check(e, args.format)
    doc = isinstance((e.get("jev") or {}).get("pairs"), list)
    try:
        gate, crit = find_gate(root, check, {})
        if gate is None or crit is None:
            fail2("%s: no template declares its criterion, so there is no declaration to run" % args.rule_id)
        rel = jev.get("fixtures")
        if not safe_rel(root, rel):
            fail2("%s has no fixture file" % args.rule_id)
        cases, problems = load_fixtures(os.path.join(root, rel))
        if doc:
            problems += doc_fixture_problems(cases, args.rule_id, jev, load_slicer(root))
        if problems:
            fail2("%s's fixtures: %s" % (rel, "; ".join(problems)))
        blob = git_blob(root, rel)
        slicer_blob = git_blob(root, DOC_SLICER) if doc else None
    except CannotRun as x:
        fail2(str(x))
    endpoint = args.endpoint or os.environ.get("KOTO_DECIDER_ENDPOINT") or JEV_ENDPOINT
    why = check_endpoint(endpoint)
    if why:
        fail2(why)
    if is_loopback(endpoint):
        key = LOOPBACK_KEY
    else:
        key = os.environ.get("KOTO_DECIDER_API_KEY", "").strip()
        # A key with whitespace or a control character could split the
        # Authorization header. The message names no part of the key.
        if not key or any(ord(ch) < 33 or ord(ch) == 127 for ch in key):
            fail2("KOTO_DECIDER_API_KEY is unset, empty or holds whitespace")
    decl = declaration(gate, crit)
    cid = check["criterion"]
    send = transport(endpoint, key)
    counts = {k: {a: 0 for a in ANSWERS} for k in KINDS}
    models = set()
    for c in cases:
        body = {"model": JEV_MODEL, "state": {decl["label"]: c["slice"]},
                "questions": {cid: {"type": "choice", "instructions": decl["question"],
                                    "criteria": {"pass": decl["pass"], "fail": decl["fail"],
                                                 "unclear": decl["escape"]}}}}
        answer = ask(send, body)
        if answer is not None and isinstance(answer.get("model"), str):
            models.add(answer["model"][:128])
        counts[c["kind"]][map_answer(answer, cid, decl["threshold"])] += 1
    if all(counts[k]["error"] == sum(counts[k].values()) for k in KINDS):
        fail2("every request failed")
    met, reasons = fixture_bar(counts, strict=doc)
    run_record = {"on": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d"),
                  "model": ",".join(sorted(models)) or "unknown",
                  "declared_sha256": declared_sha256(decl), "fixtures_blob": blob, "counts": counts}
    if doc:
        run_record["slicer_blob"] = slicer_blob
    for k in KINDS:
        print("%s: %s" % (k, " ".join("%s=%d" % (a, counts[k][a]) for a in ANSWERS)))
    for r in reasons:
        print("bar not met: %s" % r)
    print(json.dumps({"fixture_run": run_record}, sort_keys=True))
    return 0 if met else 1


# --- figures: the reference reader --------------------------------------------
#
# The live figures that decide a promotion are read from koto's exported
# decider events in a log backend. This reader computes the same figures from
# local koto session logs; it is a fixture-tested reference for those
# definitions, not the tool that decides a promotion.

def window(jev, start, end):
    if not start:
        start = (jev.get("declared") or {}).get("since") or "0000-00-00"
        fps = [fp.get("evaluated") for fp in jev.get("false_passes") or [] if isinstance(fp, dict)
               and isinstance(fp.get("evaluated"), str) and DATE.match(fp["evaluated"])]
        if fps:
            after = (datetime.date.fromisoformat(max(fps)) + datetime.timedelta(days=1)).isoformat()
            start = max(start, after)
    if not end:
        end = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d")
    return start, end


def live_figures(sessions_dir, gate, cid, start, end):
    # An evaluation is (session, visit, gate, criterion): koto re-writes a
    # fallback on each tick of a held visit, and those count once. One whose
    # every event is a decider_checked with outcome not_graded (koto's outcome
    # for an empty slice, which only the slice script's output decides) had
    # nothing to grade: it is left out of the evaluations, the sessions and
    # the answered share, and counted as not_graded. Any other event makes it
    # graded, so a fallback or an escape beside a not_graded still counts
    # against the bar. `evals` holds every tuple, its value whether it was
    # answered; `graded` is the subset the figures count, so len(evals) is
    # never the evaluation count.
    evals, graded, over = {}, set(), set()
    max_in, unread = 0, 0
    for path in sorted(glob.glob(os.path.join(sessions_dir, "*", "koto-*.state.jsonl"))):
        try:
            lines = read_text(path).splitlines()
        except OSError:
            unread += 1
            continue
        try:
            sid = json.loads(lines[0]).get("session_id") if lines else None
        except (ValueError, AttributeError):
            sid = None
        if not isinstance(sid, str) or not sid:
            unread += 1
            continue
        for line in lines[1:]:
            if not line.strip():
                continue
            try:
                ev = json.loads(line)
                t, p, ts = ev["type"], ev["payload"], ev["timestamp"][:10]
            except (ValueError, KeyError, TypeError):
                unread += 1
                continue
            if t not in ("decider_checked", "decider_fallback") or not isinstance(p, dict):
                continue
            if p.get("gate") != gate or p.get("rule_id") != cid or not (start <= ts <= end):
                continue
            k = (sid, p.get("visit_seq"), gate, cid)
            evals.setdefault(k, False)
            if not (t == "decider_checked" and p.get("outcome") == "not_graded"):
                graded.add(k)
            if t == "decider_checked" and p.get("outcome") in ("pass", "fail"):
                evals[k] = True
            if t == "decider_fallback" and p.get("reason") == "over_budget":
                over.add(k)
            b = p.get("input_bytes")
            if isinstance(b, int) and not isinstance(b, bool):
                max_in = max(max_in, b)
    sessions = {k[0] for k in graded}
    return {"from": start, "to": end, "evaluations": len(graded), "sessions": len(sessions),
            "answered": sum(1 for k in graded if evals[k]), "over_budget_fallbacks": len(over),
            "max_input_bytes": max_in, "not_graded": len(evals) - len(graded)}, unread


def cmd_figures(args):
    root = os.path.realpath(args.root)
    e = decider_entry(root, args.rule_id)
    check, jev = pair_check(e, args.format)
    for d in (args.from_, args.to):
        if d and not DATE.match(d):
            fail2("%s is not a YYYY-MM-DD date" % d)
    start, end = window(jev, args.from_, args.to)
    live, unread = live_figures(args.sessions, check["gate"], check["criterion"], start, end)
    if unread:
        print("%s: skipped %d line(s) or log(s) it couldn't read" % (PROG, unread), file=sys.stderr)
    print(json.dumps({"live": live}, sort_keys=True))
    if args.bar:
        ev = live["evaluations"]
        print("answered: %d of %d evaluations (%.0f%%); not graded: %d of %d (%.0f%%), against %.0f%% "
              "of measured runs with an empty slice"
              % (live["answered"], ev, 100 * live["answered"] / ev if ev else 0,
                 live["not_graded"], ev + live["not_graded"], 100 * not_graded_share(live),
                 100 * empty_share(jev.get("measured"))))
        met, reasons = live_bar(live, jev.get("budget", BUDGET_CEILING), jev.get("measured"))
        for r in reasons:
            print("bar not met: %s" % r)
        return 0 if met else 1
    return 0


# --- main ---------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(prog=PROG, description="Slice contracts and pass trust for Jev criteria.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="hold every Jev entry to its contract")
    c.add_argument("--root", default=DEFAULT_ROOT)
    c.add_argument("--base", default="")
    c.add_argument("--koto-templates", action="append", default=[], metavar="PATH",
                   help="a koto template, or a directory of them, to hold to the shadow guard too")
    h = sub.add_parser("declared-hash", help="print a decider entry's declaration and its SHA-256")
    h.add_argument("rule_id")
    h.add_argument("--format", default="", choices=("",) + DOC_FORMATS)
    h.add_argument("--root", default=DEFAULT_ROOT)
    pn = sub.add_parser("pins", help="print the document criteria's pins as the files are now")
    pn.add_argument("--root", default=DEFAULT_ROOT)
    m = sub.add_parser("measure", help="measure whole-run slice sizes on real artifacts")
    msub = m.add_subparsers(dest="population", required=True)
    ms = msub.add_parser("sessions")
    ms.add_argument("--dir", required=True, action="append")
    ms.add_argument("--slice", default="review-facts", choices=SESSION_SLICES)
    mp = msub.add_parser("prs")
    mp.add_argument("--repo", required=True, action="append")
    mp.add_argument("--limit", type=int, default=40)
    mp.add_argument("--kind", required=True, choices=["pr-summary", "code-hunks", "doc-pairs"])
    mp.add_argument("--git-dir", default="")
    mr = msub.add_parser("records")
    mr.add_argument("--dir", required=True)
    mr.add_argument("--kind", required=True)
    md = msub.add_parser("docs")
    md.add_argument("--criterion", required=True)
    md.add_argument("--format", required=True, choices=DOC_FORMATS)
    md.add_argument("--roots", required=True, nargs="+")
    fx = sub.add_parser("fixtures", help="run a criterion's fixture file against Jev")
    fx.add_argument("rule_id")
    fx.add_argument("--format", default="", choices=("",) + DOC_FORMATS)
    fx.add_argument("--endpoint", default="")
    fx.add_argument("--root", default=DEFAULT_ROOT)
    fg = sub.add_parser("figures", help="compute live figures from koto session logs (a reference reader)")
    fg.add_argument("rule_id")
    fg.add_argument("--format", default="", choices=("",) + DOC_FORMATS)
    fg.add_argument("--sessions", required=True)
    fg.add_argument("--from", dest="from_", default="")
    fg.add_argument("--to", default="")
    fg.add_argument("--bar", action="store_true")
    fg.add_argument("--root", default=DEFAULT_ROOT)
    for p in (ms, mp, mr, md):
        p.add_argument("--root", default=DEFAULT_ROOT)
        p.add_argument("--budget", type=int, default=BUDGET_CEILING)
    args = ap.parse_args(argv)
    return {"check": cmd_check, "declared-hash": cmd_declared_hash, "pins": cmd_pins, "measure": cmd_measure,
            "fixtures": cmd_fixtures, "figures": cmd_figures}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())

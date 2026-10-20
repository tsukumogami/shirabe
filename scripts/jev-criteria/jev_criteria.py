#!/usr/bin/env python3
"""jev_criteria.py -- slice contracts and pass trust for Jev criteria.

A Jev criterion is a closed question Jev answers about a slice of an agent's
work. Each one has an entry in references/rule-registry.json, and its `jev`
object is the criterion's contract and trust record. references/jev-criteria.md
describes the contract and holds each criterion's completeness case; the
design is docs/designs/DESIGN-jev-pass-trust.md.

Subcommands:

  check [--root DIR] [--base REF]
      Hold every Jev entry to its contract, and with --base to the history
      rules. Prints one line per problem. Exit 0 none, 1 problems, 2 could not
      run.
  declared-hash RULE_ID [--root DIR]
      Print a decider entry's declaration as canonical JSON, then its SHA-256.
  measure sessions --dir DIR
  measure prs --repo OWNER/REPO --limit N --kind pr-summary|code-hunks|doc-pairs [--git-dir DIR]
  measure records --dir DIR --kind KIND
      Measure whole-run slice sizes on real artifacts, with no call to Jev,
      and print the figures as the `measured` JSON a contract records.

Reads templates with mikefarah yq v4 and shells out to git, gh (measure prs
only) and scripts/rule-registry.sh (the release check). Standard library only.
"""

import argparse
import datetime
import glob
import hashlib
import json
import math
import os
import re
import subprocess
import sys

PROG = "jev_criteria"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_ROOT = os.path.dirname(os.path.dirname(HERE))

REGISTRY = "references/rule-registry.json"
CRITERIA = "scripts/review-shadow/criteria.json"
RULE_REGISTRY_SH = "scripts/rule-registry.sh"
REVIEW_LEVEL_SH = "skills/work-on/scripts/review-level.sh"

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

STATES = {"rejected", "blocked", "untrusted", "trusted"}
WRITERS = {"git", "gate-script", "graded-artifact", "slice-script"}
POPULATIONS = {"koto-sessions", "merged-prs", "review-shadow-records"}
NOT_MEASURED = {"no-real-run-record"}
VERDICTS = {"sufficient", "insufficient"}
ORACLES = {"review", "ci", "human"}
ANSWERS = ("pass", "fail", "unclear", "error")
KINDS = tuple(FIXTURE_MINIMUMS)

DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
BLOB = re.compile(r"^[0-9a-f]{40}$")
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


def figures(sizes, budget, population, command):
    return {"population": population, "runs": len(sizes),
            "max": max(sizes) if sizes else 0, "p90": nearest_rank(sizes, 0.9),
            "over_budget": sum(1 for s in sizes if s > budget),
            "on": datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
            "command": command}


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
    for pattern in ("skills/*/koto-templates/*.md", "koto-templates/*.md"):
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
    return {"command": gate.get("command", ""),
            "label": gate.get("label", DEFAULT_LABEL),
            "max_bytes": int(gate.get("max_bytes", DEFAULT_MAX_BYTES)),
            "question": crit.get("question", ""), "pass": crit.get("pass", ""),
            "fail": crit.get("fail", ""), "escape": crit.get("escape", ""),
            "threshold": float(crit.get("threshold", DEFAULT_THRESHOLD))}


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
            problems.append("case %s: kind %r is not good, seeded-bad or adversarial" % (cid, kind))
        want = "pass" if kind == "good" else "fail"
        if c.get("expected") != want:
            problems.append("case %s: expected must be %s for a %s case" % (cid, want, kind))
        if "input" not in c:
            problems.append("case %s has no input" % cid)
        if not isinstance(c.get("slice"), str) or not c.get("slice"):
            problems.append("case %s has no slice" % cid)
        if kind == "adversarial" and c.get("technique") not in TECHNIQUES:
            problems.append("case %s: technique %r is not one of %s"
                            % (cid, c.get("technique"), ", ".join(sorted(TECHNIQUES))))
        cases.append(c)
    counts = {k: sum(1 for c in cases if c.get("kind") == k) for k in KINDS}
    for k, need in FIXTURE_MINIMUMS.items():
        if counts[k] < need:
            problems.append("%d %s cases, fewer than %d" % (counts[k], k, need))
    techniques = {c.get("technique") for c in cases if c.get("kind") == "adversarial"} & TECHNIQUES
    if len(techniques) < MIN_TECHNIQUES:
        problems.append("%d adversarial techniques, fewer than %d" % (len(techniques), MIN_TECHNIQUES))
    return cases, problems


def fixture_bar(counts):
    """(met, reasons) for fixture counts {kind: {answer: n}}."""
    reasons = []
    for k in ("seeded-bad", "adversarial"):
        if counts.get(k, {}).get("pass", 0):
            reasons.append("%d %s case(s) answered pass" % (counts[k]["pass"], k))
    good = counts.get("good", {})
    total = sum(good.get(a, 0) for a in ANSWERS)
    if total == 0 or good.get("pass", 0) < GOOD_PASS_SHARE * total:
        reasons.append("%d of %d good cases answered pass, under %d%%"
                       % (good.get("pass", 0), total, int(GOOD_PASS_SHARE * 100)))
    errors = sum(counts.get(k, {}).get("error", 0) for k in KINDS)
    if errors:
        reasons.append("%d case(s) got no answer" % errors)
    return not reasons, reasons


def live_bar(live, budget):
    """(met, reasons) for recorded or computed live figures."""
    reasons = []
    ev = live.get("evaluations", 0)
    if ev < LIVE_MIN_EVALUATIONS:
        reasons.append("%d evaluations, fewer than %d" % (ev, LIVE_MIN_EVALUATIONS))
    if live.get("sessions", 0) < LIVE_MIN_SESSIONS:
        reasons.append("%d sessions, fewer than %d" % (live.get("sessions", 0), LIVE_MIN_SESSIONS))
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


def check_contract(root, entry, jev, criteria, cache, declared):
    """Problems with one Jev entry's contract (rules 1 to 10)."""
    eid = entry["id"]
    out = []

    def p(msg):
        out.append("%s: %s" % (eid, msg))

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
    for field in ("slice_script",):
        rel = jev.get(field)
        if not safe_rel(root, rel) or not os.path.isfile(os.path.join(root, rel)):
            p("jev.%s %r does not exist" % (field, rel))
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
        elif isinstance(m.get("runs"), int) and m["runs"] < MIN_RUNS:
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
        met, reasons = fixture_bar(counts)
        out += ["the fixture run misses the bar: %s" % r for r in reasons]
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
        for k in ("from", "to", "evaluations", "sessions", "answered", "over_budget_fallbacks", "max_input_bytes"):
            if k not in live:
                out.append("promotion.live has no %s" % k)
        met, reasons = live_bar(live, budget)
        out += ["the live figures miss the bar: %s" % r for r in reasons]
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
            if "rule-registry.sh" not in directive or ("release %s" % rid) not in directive:
                out.append("%s: state %s withholds %s but its directive doesn't run rule-registry.sh release %s"
                           % (rel, sname, rid, rid))
    for d in ("skills", "koto-templates", "hooks"):
        for dirpath, _, files in os.walk(os.path.join(root, d)):
            for name in files:
                rel = os.path.relpath(os.path.join(dirpath, name), root)
                if rel.endswith(".md") and "/koto-templates/" in "/" + rel and not rel.endswith(".mermaid.md"):
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
        od, nd = oj.get("declared") or {}, nj.get("declared") or {}
        if od.get("sha256") and nd.get("sha256") and od["sha256"] != nd["sha256"]:
            if not isinstance(nd.get("since"), str) or nd["since"] < base_date:
                out.append("%s: its declaration changed, but declared.since %s is before the base's date %s"
                           % (eid, nd.get("since"), base_date))
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
            c = e.get("check") or {}
            declared = c.get("kind") == "decider" and \
                (c.get("template"), c.get("state"), c.get("gate"), c.get("criterion")) in declared_ids
            problems += check_contract(root, e, jev, criteria, cache, declared)
        # 11: every declared decider criterion has an untrusted or trusted entry.
        for t, s, g, cid in gates:
            match = [e for e in rules if (e.get("check") or {}).get("kind") == "decider"
                     and ((e["check"].get("template"), e["check"].get("state"), e["check"].get("gate"),
                           e["check"].get("criterion")) == (t, s, g, cid))]
            if not match:
                problems.append("%s: decider check %s/%s criterion %s has no registry entry" % (t, s, g, cid))
            elif ((match[0].get("jev") or {}).get("state")) not in ("untrusted", "trusted"):
                problems.append("%s: decider check %s/%s criterion %s is declared, but its entry is %s"
                                % (t, s, g, cid, (match[0].get("jev") or {}).get("state")))
        problems += withhold_calls(root, cache, by_id)
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


def cmd_declared_hash(args):
    root = os.path.realpath(args.root)
    try:
        registry = read_json(os.path.join(root, REGISTRY))
        e = next((e for e in registry.get("rules", []) if isinstance(e, dict) and e.get("id") == args.rule_id), None)
        if not e or (e.get("check") or {}).get("kind") != "decider":
            fail2("%s is not a decider entry" % args.rule_id)
        gate, crit = find_gate(root, e["check"], {})
    except CannotRun as e:
        fail2(str(e))
    if gate is None or crit is None:
        fail2("%s's check names no decider-check criterion" % args.rule_id)
    decl = declaration(gate, crit)
    print(canonical(decl))
    print(declared_sha256(decl))
    return 0


# --- measure ------------------------------------------------------------------

def measure_sessions(args):
    root = os.path.realpath(args.root)
    script = os.path.join(root, REVIEW_LEVEL_SH)
    sizes = []
    for path in sorted(glob.glob(os.path.join(args.dir, "*", "ctx", "review_facts.json"))):
        # "standard" is the longest level name, so the size is an upper bound.
        r = run([script, "project", path, "standard"])
        if r.returncode != 0:
            continue
        sizes.append(len(r.stdout.encode("utf-8")))
    return figures(sizes, args.budget, "koto-sessions",
                   "python3 scripts/jev-criteria/jev_criteria.py measure sessions --dir <koto sessions> --budget %d" % args.budget)


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


def cmd_measure(args):
    try:
        out = {"sessions": measure_sessions, "prs": measure_prs, "records": measure_records}[args.population](args)
    except CannotRun as e:
        fail2(str(e))
    print(json.dumps(out, sort_keys=True))
    return 0


# --- main ---------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(prog=PROG, description="Slice contracts and pass trust for Jev criteria.")
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check", help="hold every Jev entry to its contract")
    c.add_argument("--root", default=DEFAULT_ROOT)
    c.add_argument("--base", default="")
    h = sub.add_parser("declared-hash", help="print a decider entry's declaration and its SHA-256")
    h.add_argument("rule_id")
    h.add_argument("--root", default=DEFAULT_ROOT)
    m = sub.add_parser("measure", help="measure whole-run slice sizes on real artifacts")
    msub = m.add_subparsers(dest="population", required=True)
    ms = msub.add_parser("sessions")
    ms.add_argument("--dir", required=True)
    mp = msub.add_parser("prs")
    mp.add_argument("--repo", required=True, action="append")
    mp.add_argument("--limit", type=int, default=40)
    mp.add_argument("--kind", required=True, choices=["pr-summary", "code-hunks", "doc-pairs"])
    mp.add_argument("--git-dir", default="")
    mr = msub.add_parser("records")
    mr.add_argument("--dir", required=True)
    mr.add_argument("--kind", required=True)
    for p in (ms, mp, mr):
        p.add_argument("--root", default=DEFAULT_ROOT)
        p.add_argument("--budget", type=int, default=BUDGET_CEILING)
    args = ap.parse_args(argv)
    return {"check": cmd_check, "declared-hash": cmd_declared_hash, "measure": cmd_measure}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())

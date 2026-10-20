#!/usr/bin/env python3
"""Tests for jev_criteria.py. No test reaches Jev, GitHub or the network:
`gh` is a stub, and every socket connection is refused below."""

import contextlib
import copy
import importlib.util
import io
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest


def _refuse(*_a, **_k):
    raise OSError("network calls are refused in these tests")


socket.socket.connect = _refuse
socket.create_connection = _refuse

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
spec = importlib.util.spec_from_file_location("jev_criteria", os.path.join(HERE, "jev_criteria.py"))
jc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jc)

RULE = "demo/fits-facts"
TEMPLATE = "skills/demo/koto-templates/demo.md"
SLICE = "skills/demo/scripts/slice.sh"
FIXTURES = "skills/demo/fixtures.jsonl"

TEMPLATE_TEXT = """---
name: demo
states:
  check_state:
    gates:
      fits:
        type: decider-check
        command: '"{{PLUGIN_ROOT}}/skills/demo/scripts/slice.sh" "{{SESSION_NAME}}"'
        max_bytes: 2048
        label: facts
        criteria:
          fits:
            rule_ref: "https://example.org/rule"
            question: "Is it fine?"
            pass: "It is fine."
            fail: "It is not fine."
            escape: "Can't tell."
            mode: veto
---

## check_state

Check the thing.
"""

RULE_DOC = """# Demo rules

The rules:
- one
- two
- `light` otherwise.
"""

CONTRACT_DOC = """# Jev criteria

## demo/fits-facts

The case.

## rs-007

The case.
"""


def fixture_lines():
    lines = []
    for i in range(10):
        lines.append({"id": "g%d" % i, "kind": "good", "expected": "pass", "input": {"n": i}, "slice": "good %d" % i})
    for i in range(20):
        lines.append({"id": "b%d" % i, "kind": "seeded-bad", "expected": "fail", "input": {"n": i}, "slice": "bad %d" % i})
    techs = ["instruction", "authority-claim", "fake-answer", "hidden-comment", "role-line"]
    for i, t in enumerate(techs):
        lines.append({"id": "a%d" % i, "kind": "adversarial", "technique": t, "expected": "fail",
                      "input": {"n": i}, "slice": "adv %d" % i})
    return lines


def write(root, rel, text):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def git(root, *args):
    subprocess.run(["git", "-C", root] + list(args), check=True, capture_output=True,
                   env=dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@e", GIT_COMMITTER_NAME="t",
                            GIT_COMMITTER_EMAIL="t@e"))


class Tree:
    """A small repository the checker can judge: one decider criterion and one
    review-shadow Jev criterion, both with valid contracts."""

    def __init__(self):
        self.root = os.path.realpath(tempfile.mkdtemp(prefix="jev-criteria-test."))
        write(self.root, TEMPLATE, TEMPLATE_TEXT)
        write(self.root, SLICE, "#!/bin/sh\necho slice\n")
        write(self.root, "skills/demo/references/rules.md", RULE_DOC)
        write(self.root, "references/jev-criteria.md", CONTRACT_DOC)
        write(self.root, FIXTURES, "\n".join(json.dumps(c) for c in fixture_lines()) + "\n")
        write(self.root, "scripts/review-shadow/criteria.json", json.dumps({"criteria": [
            {"rule_id": "rs-007", "observer": "jev"}, {"rule_id": "rs-001", "observer": "script"}]}))
        gate, crit = None, None
        self.registry = {"schema": 1, "rules": [self.decider_entry(), self.rs_entry()]}
        self.save()
        git(self.root, "init", "-q")
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "base")
        entry = self.entry(RULE)
        gate, crit = jc.find_gate(self.root, entry["check"], {})
        entry["jev"]["declared"]["sha256"] = jc.declared_sha256(jc.declaration(gate, crit))
        self.save()

    def decider_entry(self):
        return {"id": RULE, "status": "active", "summary": "s",
                "text": {"path": "skills/demo/references/rules.md", "first": "The rules:", "last": "- `light` otherwise."},
                "check": {"kind": "decider", "template": TEMPLATE, "state": "check_state", "gate": "fits",
                          "criterion": "fits"},
                "fixtures": [], "level": "gate", "timing": ["demo:check_state"], "guards": ["none"],
                "withhold": "never", "baseline_keys": [], "aliases": [], "notes": "",
                "jev": {"state": "untrusted",
                        "sources": [{"what": "facts.json", "writer": "gate-script", "script": SLICE},
                                    {"what": "LEVEL", "writer": "graded-artifact"}],
                        "slice_script": SLICE, "budget": 2048,
                        "completeness": {"path": "references/jev-criteria.md", "heading": RULE, "verdict": "sufficient"},
                        "measured": {"population": "koto-sessions", "runs": 150, "max": 300, "p90": 250,
                                     "over_budget": 0, "on": "2026-10-20", "command": "measure sessions --dir <x>"},
                        "fixtures": FIXTURES,
                        "declared": {"sha256": "0" * 64, "since": "2026-10-20"},
                        "false_passes": []}}

    def rs_entry(self):
        return {"id": "rs-007", "status": "active", "summary": "s",
                "text": {"path": "skills/demo/references/rules.md", "first": "The rules:"},
                "check": {"kind": "review-shadow", "criterion": "rs-007"},
                "fixtures": [], "level": "shadow", "timing": ["pre-merge"], "guards": ["none"],
                "withhold": "never", "baseline_keys": [], "aliases": [], "notes": "",
                "jev": {"state": "rejected",
                        "sources": [{"what": "the pull request body", "writer": "graded-artifact"}],
                        "slice_script": "skills/demo/scripts/slice.sh", "budget": 2560,
                        "completeness": {"path": "references/jev-criteria.md", "heading": "rs-007", "verdict": "sufficient"},
                        "measured": {"population": "merged-prs", "runs": 80, "max": 9000, "p90": 4000,
                                     "over_budget": 31, "on": "2026-10-20", "command": "measure prs --kind pr-summary"},
                        "false_passes": []}}

    def entry(self, eid):
        return next(e for e in self.registry["rules"] if e["id"] == eid)

    def save(self):
        write(self.root, jc.REGISTRY, json.dumps(self.registry, indent=2))

    def check(self, base=""):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = jc.main(["check", "--root", self.root] + (["--base", base] if base else []))
        return rc, out.getvalue()

    def close(self):
        shutil.rmtree(self.root, ignore_errors=True)


class CheckTest(unittest.TestCase):
    def setUp(self):
        self.t = Tree()

    def tearDown(self):
        self.t.close()

    def assertProblem(self, want):
        rc, out = self.t.check()
        self.assertEqual(rc, 1, out)
        self.assertIn(want, out)

    def jev(self, eid=RULE):
        return self.t.entry(eid)["jev"]

    def test_valid_tree_passes(self):
        rc, out = self.t.check()
        self.assertEqual(rc, 0, out)

    def test_missing_field(self):
        del self.jev()["slice_script"]
        self.t.save()
        self.assertProblem("jev.slice_script None does not exist")

    def test_empty_sources(self):
        self.jev()["sources"] = []
        self.t.save()
        self.assertProblem("jev.sources is not a non-empty list")

    def test_unknown_writer(self):
        self.jev()["sources"][0]["writer"] = "agent"
        self.t.save()
        self.assertProblem("writer 'agent' is not one of")

    def test_gate_script_missing(self):
        self.jev()["sources"][0]["script"] = "skills/demo/scripts/none.sh"
        self.t.save()
        self.assertProblem("gate-script 'skills/demo/scripts/none.sh' does not exist")

    def test_missing_completeness_heading(self):
        self.jev()["completeness"]["heading"] = "nope"
        self.t.save()
        self.assertProblem("jev.completeness.heading 'nope' is not a heading")

    def test_no_measurement(self):
        del self.jev("rs-007")["measured"]
        self.t.save()
        self.assertProblem("rs-007: jev has neither measured nor not_measured")

    def test_bad_population(self):
        self.jev("rs-007")["measured"]["population"] = "my-laptop"
        self.t.save()
        self.assertProblem("jev.measured.population 'my-laptop'")

    def test_local_path_in_command(self):
        # Split so the public-content check doesn't read this line as a leak.
        self.jev("rs-007")["measured"]["command"] = "measure records --dir /" + "Users/me/store"
        self.t.save()
        self.assertProblem("jev.measured.command holds a local path")

    def test_over_share_must_be_rejected(self):
        j = self.jev("rs-007")
        j["state"] = "blocked"
        self.t.save()
        self.assertProblem("rs-007: jev.state is blocked, but its record makes it rejected")

    def test_exactly_five_percent_is_not_rejected(self):
        j = self.jev("rs-007")
        j["measured"].update({"runs": 100, "over_budget": 5})
        j["state"] = "blocked"
        self.t.save()
        rc, out = self.t.check()
        self.assertEqual(rc, 0, out)

    def test_insufficient_completeness_is_rejected(self):
        self.jev()["completeness"]["verdict"] = "insufficient"
        self.t.save()
        self.assertProblem("%s: jev.state is untrusted, but its record makes it rejected" % RULE)

    def test_template_declared_criterion_cannot_be_blocked(self):
        self.jev()["state"] = "blocked"
        self.t.save()
        self.assertProblem("is declared, but its entry is blocked")

    def test_untrusted_must_be_declared(self):
        self.jev("rs-007")["measured"].update({"over_budget": 0})
        self.jev("rs-007")["state"] = "untrusted"
        self.t.save()
        self.assertProblem("rs-007: jev.state is untrusted, but its record makes it blocked")

    def test_declared_gate_without_entry(self):
        self.t.registry["rules"] = [self.t.entry("rs-007")]
        self.t.save()
        self.assertProblem("criterion fits has no registry entry")

    def test_budget_over_ceiling(self):
        self.jev("rs-007")["budget"] = 4096
        self.t.save()
        self.assertProblem("jev.budget 4096 is over the 2560-byte ceiling")

    def test_budget_differs_from_max_bytes(self):
        self.jev()["budget"] = 1024
        self.t.save()
        self.assertProblem("jev.budget 1024 differs from gate fits's max_bytes 2048")

    def test_gate_not_running_slice_script(self):
        write(self.t.root, "skills/demo/scripts/other.sh", "#!/bin/sh\n")
        self.jev()["slice_script"] = "skills/demo/scripts/other.sh"
        self.t.save()
        self.assertProblem("doesn't run jev.slice_script")

    def test_too_few_runs(self):
        self.jev()["measured"]["runs"] = 99
        self.t.save()
        self.assertProblem("measured over 99 runs, fewer than 100")

    def test_stale_declaration(self):
        self.jev()["declared"]["sha256"] = "1" * 64
        self.t.save()
        self.assertProblem("jev.declared.sha256 is stale")

    def test_unresolved_gate(self):
        self.t.entry(RULE)["check"]["gate"] = "missing"
        self.t.save()
        self.assertProblem("its check names no decider-check criterion")

    def test_unresolved_template_state_or_criterion(self):
        for field, value in (("template", "skills/demo/koto-templates/none.md"), ("state", "missing"),
                             ("criterion", "missing")):
            with self.subTest(field=field):
                check = self.t.entry(RULE)["check"]
                old = check[field]
                check[field] = value
                self.t.save()
                self.assertProblem("its check names no decider-check criterion")
                check[field] = old
                self.t.save()

    def test_declared_criterion_cannot_be_rejected(self):
        self.jev()["measured"]["over_budget"] = 100
        self.jev()["state"] = "rejected"
        self.t.save()
        self.assertProblem("is declared, but its entry is rejected")

    def test_missing_slice_script(self):
        self.jev()["slice_script"] = "skills/demo/scripts/none.sh"
        self.t.save()
        self.assertProblem("jev.slice_script 'skills/demo/scripts/none.sh' does not exist")

    def test_missing_completeness_path(self):
        self.jev()["completeness"]["path"] = "references/none.md"
        self.t.save()
        self.assertProblem("jev.completeness.path 'references/none.md' does not exist")

    def test_unknown_not_measured(self):
        del self.jev("rs-007")["measured"]
        self.jev("rs-007")["not_measured"] = "too-busy"
        self.t.save()
        self.assertProblem("jev.not_measured 'too-busy' is not one of")

    def test_fixtures_below_minimum(self):
        lines = fixture_lines()[:-1]
        write(self.t.root, FIXTURES, "\n".join(json.dumps(c) for c in lines) + "\n")
        self.assertProblem("fixtures: 4 adversarial cases, fewer than 5")

    def test_fixture_without_slice(self):
        lines = fixture_lines()
        del lines[0]["slice"]
        write(self.t.root, FIXTURES, "\n".join(json.dumps(c) for c in lines) + "\n")
        self.assertProblem("case g0 has no slice")

    def test_fixture_required_fields(self):
        for field, want in (("id", "line 1 has no id"), ("input", "case g0 has no input"),
                            ("kind", "case g0: kind None is not good"),
                            ("expected", "case g0: expected must be pass for a good case")):
            with self.subTest(field=field):
                lines = fixture_lines()
                del lines[0][field]
                write(self.t.root, FIXTURES, "\n".join(json.dumps(c) for c in lines) + "\n")
                self.assertProblem(want)

    def test_fixture_bad_technique(self):
        lines = fixture_lines()
        lines[-1]["technique"] = "shouting"
        write(self.t.root, FIXTURES, "\n".join(json.dumps(c) for c in lines) + "\n")
        self.assertProblem("technique 'shouting' is not one of")

    def test_fixture_too_few_techniques(self):
        lines = fixture_lines()
        for c in lines:
            if c["kind"] == "adversarial":
                c["technique"] = "instruction"
        write(self.t.root, FIXTURES, "\n".join(json.dumps(c) for c in lines) + "\n")
        self.assertProblem("1 adversarial techniques, fewer than 3")

    def test_untrusted_must_be_withhold_never(self):
        self.t.entry(RULE)["withhold"] = "eligible"
        self.t.save()
        self.assertProblem("a untrusted criterion must be withhold never")

    def test_untrusted_with_promotion(self):
        self.jev()["promotion"] = {}
        self.t.save()
        self.assertProblem("an untrusted contract holds a promotion record")

    def test_false_pass_fields(self):
        self.jev()["false_passes"] = [{"evaluated": "2026-10-20", "oracle": "review", "evidence": "x"}]
        self.t.save()
        rc, out = self.t.check()
        self.assertEqual(rc, 1, out)
        self.assertIn("a false pass has no recorded date", out)
        self.assertIn("a false pass's evidence is not a https://github.com/ link", out)

    def test_jev_on_a_non_jev_entry(self):
        e = copy.deepcopy(self.t.entry("rs-007"))
        e["id"] = "rs-001"
        e["check"] = {"kind": "review-shadow", "criterion": "rs-001"}
        self.t.registry["rules"].append(e)
        self.t.save()
        self.assertProblem("rs-001: carries jev but isn't a Jev criterion")

    def test_jev_criterion_without_contract(self):
        del self.t.entry("rs-007")["jev"]
        self.t.save()
        self.assertProblem("rs-007: a Jev criterion with no jev contract")


class PromotionTest(unittest.TestCase):
    """A trusted entry: every promotion rule, one failure at a time."""

    def setUp(self):
        self.t = Tree()
        e = self.t.entry(RULE)
        j = e["jev"]
        j["state"] = "trusted"
        e["withhold"] = "eligible"
        counts = {"good": {"pass": 10, "fail": 0, "unclear": 0, "error": 0},
                  "seeded-bad": {"pass": 0, "fail": 20, "unclear": 0, "error": 0},
                  "adversarial": {"pass": 0, "fail": 5, "unclear": 0, "error": 0}}
        j["promotion"] = {
            "trusted_since": "2026-11-20",
            "slice_script_blob": jc.git_blob(self.t.root, SLICE),
            "fixture_run": {"on": "2026-11-01", "model": "jev-1", "declared_sha256": j["declared"]["sha256"],
                            "fixtures_blob": jc.git_blob(self.t.root, FIXTURES), "counts": counts},
            "live": {"from": "2026-10-21", "to": "2026-11-20", "evaluations": 30, "sessions": 5, "answered": 29,
                     "over_budget_fallbacks": 0, "max_input_bytes": 300}}
        self.t.save()

    def tearDown(self):
        self.t.close()

    def promo(self):
        return self.t.entry(RULE)["jev"]["promotion"]

    def assertProblem(self, want):
        rc, out = self.t.check()
        self.assertEqual(rc, 1, out)
        self.assertIn(want, out)

    def test_valid_promotion_passes(self):
        rc, out = self.t.check()
        self.assertEqual(rc, 0, out)

    def test_missing_trusted_since(self):
        del self.promo()["trusted_since"]
        self.t.save()
        self.assertProblem("promotion.trusted_since is not a YYYY-MM-DD date")

    def test_missing_promotion_fields(self):
        for field in ("slice_script_blob", "fixture_run", "live"):
            with self.subTest(field=field):
                saved = self.promo().pop(field)
                self.t.save()
                rc, out = self.t.check()
                self.assertEqual(rc, 1, out)
                self.assertIn("promotion", out)
                self.promo()[field] = saved
                self.t.save()

    def test_counts_dont_add_up(self):
        self.promo()["fixture_run"]["counts"]["good"]["pass"] = 9
        self.t.save()
        self.assertProblem("the fixture run counts 9 good cases; the file has 10")

    def test_fixture_bar(self):
        self.promo()["fixture_run"]["counts"]["seeded-bad"] = {"pass": 1, "fail": 19, "unclear": 0, "error": 0}
        self.t.save()
        self.assertProblem("1 seeded-bad case(s) answered pass")

    def test_live_bar_evaluations(self):
        self.promo()["live"]["evaluations"] = 29
        self.promo()["live"]["answered"] = 28
        self.t.save()
        self.assertProblem("29 evaluations, fewer than 30")

    def test_live_bar_answered(self):
        self.promo()["live"]["answered"] = 28
        self.t.save()
        self.assertProblem("28 of 30 evaluations answered, under 95%")

    def test_stale_slice_script(self):
        write(self.t.root, SLICE, "#!/bin/sh\necho changed\n")
        self.assertProblem("promotion.slice_script_blob differs")

    def test_stale_fixtures(self):
        lines = fixture_lines()
        lines[0]["slice"] = "edited"
        write(self.t.root, FIXTURES, "\n".join(json.dumps(c) for c in lines) + "\n")
        self.assertProblem("promotion.fixture_run.fixtures_blob differs")

    def test_fixture_run_under_another_declaration(self):
        self.promo()["fixture_run"]["declared_sha256"] = "2" * 64
        self.t.save()
        self.assertProblem("the fixture run was made under another declaration")

    def test_window_before_declared(self):
        self.promo()["live"]["from"] = "2026-10-19"
        self.t.save()
        self.assertProblem("promotion.live.from is before declared.since")

    def test_window_must_follow_false_pass(self):
        self.t.entry(RULE)["jev"]["false_passes"] = [{"evaluated": "2026-10-25", "recorded": "2026-10-26",
                                                     "oracle": "human", "evidence": "https://github.com/o/r/issues/1"}]
        self.t.save()
        self.assertProblem("promotion.live.from is not after the false pass evaluated 2026-10-25")

    def test_trusted_since_is_window_end(self):
        self.promo()["trusted_since"] = "2026-11-21"
        self.t.save()
        self.assertProblem("differs from promotion.live.to")

    def test_trusted_needs_eligible(self):
        self.t.entry(RULE)["withhold"] = "never"
        self.t.save()
        self.assertProblem("a trusted criterion must be withhold eligible")

    def test_trusted_needs_veto(self):
        write(self.t.root, TEMPLATE, TEMPLATE_TEXT.replace("mode: veto", "mode: shadow"))
        self.assertProblem("a trusted criterion's template mode is 'shadow', not veto")


class HistoryTest(unittest.TestCase):
    def setUp(self):
        self.t = Tree()
        git(self.t.root, "add", "-A")
        git(self.t.root, "commit", "-q", "-m", "contracts")
        self.base = "HEAD"

    def tearDown(self):
        self.t.close()

    def test_unchanged_history_passes(self):
        rc, out = self.t.check(self.base)
        self.assertEqual(rc, 0, out)

    def test_removed_jev(self):
        e = self.t.entry("rs-007")
        del e["jev"]
        e["check"] = {"kind": "none"}
        e["level"] = "prose"
        self.t.save()
        rc, out = self.t.check(self.base)
        self.assertIn("rs-007: its jev object was removed", out)

    def test_removed_false_pass(self):
        fp = {"evaluated": "2026-10-25", "recorded": "2026-10-26", "oracle": "human",
              "evidence": "https://github.com/o/r/issues/1"}
        self.t.entry("rs-007")["jev"]["false_passes"] = [fp]
        self.t.save()
        git(self.t.root, "add", "-A")
        git(self.t.root, "commit", "-q", "-m", "fp")
        self.t.entry("rs-007")["jev"]["false_passes"] = []
        self.t.save()
        rc, out = self.t.check("HEAD")
        self.assertIn("a false pass recorded at the base was changed or removed", out)

    def test_removed_declaration(self):
        del self.t.entry(RULE)["jev"]["declared"]
        self.t.save()
        rc, out = self.t.check(self.base)
        self.assertIn("%s: its declared record was removed" % RULE, out)

    def test_changed_declaration_needs_new_since(self):
        write(self.t.root, TEMPLATE, TEMPLATE_TEXT.replace("Is it fine?", "Is it really fine?"))
        e = self.t.entry(RULE)
        gate, crit = jc.find_gate(self.t.root, e["check"], {})
        e["jev"]["declared"]["sha256"] = jc.declared_sha256(jc.declaration(gate, crit))
        e["jev"]["declared"]["since"] = "2020-01-01"
        self.t.save()
        rc, out = self.t.check(self.base)
        self.assertIn("its declaration changed, but declared.since 2020-01-01 is before the base's date", out)


class DeclaredHashTest(unittest.TestCase):
    def test_pinned_hash(self):
        decl = {"command": "c", "label": "artifact", "max_bytes": 2560, "question": "q", "pass": "p",
                "fail": "f", "escape": "e", "threshold": 0.9}
        self.assertEqual(jc.canonical(decl),
                         '{"command":"c","escape":"e","fail":"f","label":"artifact","max_bytes":2560,'
                         '"pass":"p","question":"q","threshold":0.9}')
        self.assertEqual(jc.declared_sha256(decl),
                         __import__("hashlib").sha256(jc.canonical(decl).encode()).hexdigest())

    def test_defaults_and_float_threshold(self):
        decl = jc.declaration({"command": "c"}, {"question": "q", "pass": "p", "fail": "f", "escape": "e", "threshold": 1})
        self.assertEqual(decl["label"], "artifact")
        self.assertEqual(decl["max_bytes"], 2560)
        self.assertIsInstance(decl["threshold"], float)


class MeasureTest(unittest.TestCase):
    def test_nearest_rank(self):
        self.assertEqual(jc.nearest_rank(list(range(1, 11)), 0.9), 9)
        self.assertEqual(jc.nearest_rank([5], 0.9), 5)
        self.assertEqual(jc.nearest_rank([], 0.9), 0)

    def test_records(self):
        d = tempfile.mkdtemp()
        try:
            write(d, "a/1.json", json.dumps({"slices": [{"kind": "code-hunks", "bytes": 2000},
                                                        {"kind": "code-hunks", "bytes": 1000},
                                                        {"kind": "other", "bytes": 9}]}))
            write(d, "b/2.json", json.dumps({"slices": [{"kind": "code-hunks", "bytes": 100}]}))
            write(d, "c/3.json", "not json")
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = jc.main(["measure", "records", "--dir", d, "--kind", "code-hunks"])
            got = json.loads(out.getvalue())
            self.assertEqual(rc, 0)
            self.assertEqual((got["runs"], got["max"], got["over_budget"], got["population"]),
                             (2, 3000, 1, "review-shadow-records"))
        finally:
            shutil.rmtree(d)

    def test_sessions(self):
        d = tempfile.mkdtemp()
        try:
            facts = {"lines": 12, "files": 2, "classes": ["docs"], "tests_changed": False,
                     "criteria_changed": False, "unclassified": False, "floor": "light"}
            write(d, "s1/ctx/review_facts.json", json.dumps(facts))
            write(d, "s2/ctx/review_facts.json", json.dumps(dict(facts, lines="x")))
            # The projection is fixed, so the corpus's sizes are known.
            want = sorted(len(("%s\nlevels: light < standard < full\nlevel: standard\n" % s).encode())
                          for s in ('{"lines":12,"files":2,"classes":["docs"],"tests_changed":false,'
                                    '"criteria_changed":false,"unclassified":false,"floor":"light"}',
                                    '{"lines":0,"files":2,"classes":["docs"],"tests_changed":false,'
                                    '"criteria_changed":false,"unclassified":false,"floor":"light"}'))
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = jc.main(["measure", "sessions", "--dir", d, "--root", REPO, "--budget", "2048"])
            got = json.loads(out.getvalue())
            self.assertEqual(rc, 0)
            self.assertEqual((got["runs"], got["max"], got["p90"], got["over_budget"], got["population"]),
                             (2, want[1], want[1], 0, "koto-sessions"))
            self.assertIn("--budget 2048", got["command"])
        finally:
            shutil.rmtree(d)

    def test_prs(self):
        bodies = {"1": "Adds a thing.\n\n---\n\nreviewer notes", "2": "x" * 3000 + "\n\n---\n\nnotes"}
        files = {"1": [{"path": "a.py", "additions": 2, "deletions": 0}],
                 "2": [{"path": "b.md", "additions": 1, "deletions": 1}]}
        calls = []

        def fake_run(argv, cwd=None, env=None):
            if argv[0] != "gh":
                return real_run(argv, cwd=cwd, env=env)
            calls.append(argv)
            self.assertNotIn("GH_TOKEN", env or {})
            if argv[1:3] == ["pr", "list"]:
                out = json.dumps([{"number": 1, "mergeCommit": {"oid": "a" * 40}},
                                  {"number": 2, "mergeCommit": {"oid": "b" * 40}}])
            elif argv[1:3] == ["pr", "view"]:
                out = json.dumps({"body": bodies[argv[3]], "files": files[argv[3]]})
            else:
                out = ""
            return subprocess.CompletedProcess(argv, 0, out, "")

        real_run = jc.run
        jc.run = fake_run
        try:
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = jc.main(["measure", "prs", "--repo", "o/r", "--limit", "2", "--kind", "pr-summary",
                              "--root", REPO])
        finally:
            jc.run = real_run
        rs = jc.load_review_shadow(REPO)
        sizes = sorted(rs.utf8_len(rs.part1(bodies[n])) + rs.utf8_len(rs.diffstat(
            [dict(f, status="modified", patch="") for f in files[n]])) for n in ("1", "2"))
        got = json.loads(out.getvalue())
        self.assertEqual(rc, 0)
        self.assertEqual((got["runs"], got["max"], got["over_budget"], got["population"]),
                         (2, sizes[1], 1, "merged-prs"))
        self.assertEqual(len(calls), 5)  # one list, then a view and a diff per pull request

    def test_pr_slice_size_reaches_no_network(self):
        rs = jc.load_review_shadow(REPO)
        meta = {"body": "Adds a thing.\n\n---\n\nmore", "files": [{"path": "a.py", "additions": 2, "deletions": 0}]}
        patches = {"a.py": "@@ -0,0 +1,2 @@\n+# why: it's needed\n+x = 1"}
        self.assertGreater(jc.pr_slice_size(rs, "pr-summary", meta, patches, {}), 0)
        self.assertGreater(jc.pr_slice_size(rs, "code-hunks", meta, patches, {}), 0)


class RepositoryTest(unittest.TestCase):
    def test_repository_passes(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = jc.main(["check", "--root", REPO])
        self.assertEqual(rc, 0, out.getvalue())

    def test_fixture_slices_are_the_scripts_output(self):
        # A case's slice must be what the slice script prints for its input,
        # or a fixture run would grade a slice no live run can produce.
        registry = jc.read_json(os.path.join(REPO, jc.REGISTRY))
        checked = 0
        for e in registry["rules"]:
            jev = e.get("jev") or {}
            if jev.get("slice_script") != jc.REVIEW_LEVEL_SH or not jev.get("fixtures"):
                continue
            cases, problems = jc.load_fixtures(os.path.join(REPO, jev["fixtures"]))
            self.assertEqual(problems, [], e["id"])
            for c in cases:
                with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as t:
                    json.dump(c["input"]["facts"], t)
                try:
                    r = subprocess.run([os.path.join(REPO, jc.REVIEW_LEVEL_SH), "project", t.name,
                                        c["input"]["level"]], capture_output=True, text=True)
                finally:
                    os.unlink(t.name)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(r.stdout, c["slice"], "%s case %s" % (e["id"], c["id"]))
                checked += 1
        self.assertGreater(checked, 0)


if __name__ == "__main__":
    unittest.main()

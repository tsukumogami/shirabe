#!/usr/bin/env python3
"""Tests for jev_criteria.py. No test reaches Jev, GitHub or the network:
`gh` is a stub, and every socket connection is refused below."""

import contextlib
import copy
import gzip
import importlib.util
import io
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest
import urllib.error


# A local run must leave the tree clean: work-on's panels refuse a dirty one.
sys.dont_write_bytecode = True


def _refuse(*_a, **_k):
    raise OSError("network calls are refused in these tests")


socket.socket.connect = _refuse
socket.create_connection = _refuse

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
spec = importlib.util.spec_from_file_location("jev_criteria", os.path.join(HERE, "jev_criteria.py"))
jc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(jc)


class _RefusingOpener:
    def open(self, req, timeout=None):
        raise AssertionError("a test reached the network opener: %s" % req.full_url)


# Every test starts from an opener that refuses; a test that wants answers
# swaps in a stub and puts this back.
jc.build_opener = _RefusingOpener

# A real decider key in the caller's environment never reaches a test: the
# tests that need a key set a fake one of their own.
os.environ.pop("KOTO_DECIDER_API_KEY", None)
os.environ.pop("KOTO_DECIDER_ENDPOINT", None)

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

    def test_bad_empty_count(self):
        for bad in (-1, "3", True):
            with self.subTest(value=bad):
                self.jev("rs-007")["measured"]["empty"] = bad
                self.t.save()
                self.assertProblem("rs-007: jev.measured.empty is not a non-negative integer")

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

    def test_fixture_empty_kind_expects_the_escape(self):
        # An empty case is answered with the escape, which a request sends as
        # `unclear`; it has no minimum, so a file without one still passes.
        empty = {"id": "e0", "kind": "empty", "expected": "unclear", "input": {}, "slice": "{}\n"}
        lines = fixture_lines() + [empty]
        write(self.t.root, FIXTURES, "\n".join(json.dumps(c) for c in lines) + "\n")
        rc, out = self.t.check()
        self.assertEqual(rc, 0, out)
        for bad in ("pass", "fail"):
            with self.subTest(expected=bad):
                lines[-1] = dict(empty, expected=bad)
                write(self.t.root, FIXTURES, "\n".join(json.dumps(c) for c in lines) + "\n")
                self.assertProblem("case e0: expected must be unclear for an empty case")

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


def trust(t):
    """Promote the tree's decider entry with a record that meets every bar."""
    e = t.entry(RULE)
    j = e["jev"]
    j["state"] = "trusted"
    e["withhold"] = "eligible"
    counts = {"good": {"pass": 10, "fail": 0, "unclear": 0, "error": 0},
              "seeded-bad": {"pass": 0, "fail": 20, "unclear": 0, "error": 0},
              "adversarial": {"pass": 0, "fail": 5, "unclear": 0, "error": 0}}
    j["promotion"] = {
        "trusted_since": "2026-11-20",
        "slice_script_blob": jc.git_blob(t.root, SLICE),
        "fixture_run": {"on": "2026-11-01", "model": "jev-1", "declared_sha256": j["declared"]["sha256"],
                        "fixtures_blob": jc.git_blob(t.root, FIXTURES), "counts": counts},
        "live": {"from": "2026-10-21", "to": "2026-11-20", "evaluations": 30, "sessions": 5, "answered": 29,
                 "over_budget_fallbacks": 0, "max_input_bytes": 300, "not_graded": 0}}
    t.save()


WITHHOLD_ACTION = """  check_state:
    default_action:
      command: '"{{PLUGIN_ROOT}}/scripts/jev-withhold.sh" %s skills/demo/references/rules.md "{{SESSION_NAME}}" "{{SESSION_DIR}}" "{{PLUGIN_ROOT}}"'
      capture_stdout_as: RULES
"""
WITHHOLD_DIRECTIVE = "Check the thing, reading the rules at {{RULES}}. When a gate fails, run `scripts/rule-registry.sh release demo/fits-facts`."


def withholding_template(rule_id=RULE, directive=WITHHOLD_DIRECTIVE):
    return TEMPLATE_TEXT.replace("  check_state:\n", WITHHOLD_ACTION % rule_id, 1) \
        .replace("Check the thing.", directive, 1)


class WithholdCallTest(unittest.TestCase):
    """Rule 12: who may call jev-withhold.sh, and for which rule."""

    def setUp(self):
        self.t = Tree()
        trust(self.t)

    def tearDown(self):
        self.t.close()

    def assertProblem(self, want):
        rc, out = self.t.check()
        self.assertEqual(rc, 1, out)
        self.assertIn(want, out)

    def test_a_trusted_rule_with_its_release_passes(self):
        write(self.t.root, TEMPLATE, withholding_template())
        rc, out = self.t.check()
        self.assertEqual(rc, 0, out)

    def test_a_rule_that_isnt_trusted(self):
        e = self.t.entry(RULE)
        e["jev"]["state"], e["withhold"] = "untrusted", "never"
        del e["jev"]["promotion"]
        self.t.save()
        write(self.t.root, TEMPLATE, withholding_template())
        self.assertProblem("withholds demo/fits-facts, which isn't a trusted Jev criterion")

    def test_a_rule_of_another_template(self):
        write(self.t.root, "skills/demo/koto-templates/other.md",
              "---\nname: other\nstates:\n" + WITHHOLD_ACTION % RULE + "---\n\n## check_state\n\n"
              + WITHHOLD_DIRECTIVE + "\n")
        self.assertProblem("withholds demo/fits-facts, whose check is in another template")

    def test_a_directive_without_the_release(self):
        write(self.t.root, TEMPLATE, withholding_template(directive="Check the thing at {{RULES}}."))
        self.assertProblem("its directive doesn't run rule-registry.sh release demo/fits-facts")

    def test_a_release_of_a_longer_id_doesnt_count(self):
        write(self.t.root, TEMPLATE, withholding_template(
            directive="Check the thing at {{RULES}}; run `scripts/rule-registry.sh release demo/fits-facts-two`."))
        self.assertProblem("its directive doesn't run rule-registry.sh release demo/fits-facts")

    def test_a_nested_markdown_file_is_scanned(self):
        rel = "skills/demo/koto-templates/notes/guide.md"
        write(self.t.root, rel, "Run jev-withhold.sh by hand.\n")
        self.assertProblem("%s: calls jev-withhold.sh; only a template's command may" % rel)

    def test_no_literal_rule_id(self):
        write(self.t.root, TEMPLATE, withholding_template(rule_id='"{{RULE}}"'))
        self.assertProblem("calls jev-withhold.sh without a literal rule id")

    def test_a_mention_outside_a_command(self):
        write(self.t.root, TEMPLATE, withholding_template().replace(
            "Check the thing,", "Check the thing (jev-withhold.sh chose the file),", 1))
        self.assertProblem("names jev-withhold.sh outside a state's command")

    def test_a_call_from_any_other_file(self):
        for rel in ("skills/demo/scripts/run.sh", "koto-templates/notes.mermaid.md", "hooks/pre.sh"):
            with self.subTest(rel):
                write(self.t.root, rel, 'out=$("$ROOT/scripts/jev-withhold.sh" demo/fits-facts x y z w)\n')
                self.assertProblem("%s: calls jev-withhold.sh; only a template's command may" % rel)
                os.remove(os.path.join(self.t.root, rel))

    def test_no_template_in_the_repository_calls_it(self):
        for rel in jc.template_files(REPO):
            with self.subTest(rel):
                self.assertNotIn(jc.WITHHOLD_SCRIPT, jc.read_text(os.path.join(REPO, rel)))


class PromotionTest(unittest.TestCase):
    """A trusted entry: every promotion rule, one failure at a time."""

    def setUp(self):
        self.t = Tree()
        trust(self.t)

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

    def test_fixture_bar_empty_cases_must_escape(self):
        base = {"good": {"pass": 10, "fail": 0, "unclear": 0, "error": 0},
                "seeded-bad": {"pass": 0, "fail": 20, "unclear": 0, "error": 0},
                "adversarial": {"pass": 0, "fail": 5, "unclear": 0, "error": 0}}
        self.assertEqual(jc.fixture_bar(dict(base, empty={"pass": 0, "fail": 0, "unclear": 3, "error": 0})),
                         (True, []))
        met, reasons = jc.fixture_bar(dict(base, empty={"pass": 1, "fail": 1, "unclear": 1, "error": 0}))
        self.assertFalse(met)
        self.assertIn("2 empty case(s) answered pass or fail, not the escape", reasons)
        met, reasons = jc.fixture_bar(dict(base, empty={"pass": 0, "fail": 0, "unclear": 0, "error": 1}))
        self.assertIn("1 case(s) got no answer", reasons)

    def test_live_record_carries_not_graded(self):
        del self.promo()["live"]["not_graded"]
        self.t.save()
        self.assertProblem("promotion.live has no not_graded")
        for bad in (-1, "3", True):
            with self.subTest(value=bad):
                self.promo()["live"]["not_graded"] = bad
                self.t.save()
                self.assertProblem("promotion.live.not_graded is not a non-negative integer")

    def test_bad_counts_never_crash_the_bar(self):
        # A bad count is reported by the shape checks; the shares read it as
        # 0, so the bar is still computed beside that report.
        for bad in (-1, "3", True, None):
            with self.subTest(value=bad):
                met, reasons = jc.live_bar({"evaluations": 30, "sessions": 5, "answered": 30, "not_graded": bad},
                                           2560, {"runs": 150, "empty": bad})
                self.assertEqual((met, reasons), (True, []))

    def test_live_bar_evaluations(self):
        self.promo()["live"]["evaluations"] = 29
        self.promo()["live"]["answered"] = 28
        self.t.save()
        self.assertProblem("29 evaluations, fewer than 30")

    def test_live_bar_answered(self):
        self.promo()["live"]["answered"] = 28
        self.t.save()
        self.assertProblem("28 of 30 evaluations answered, under 95%")

    def test_not_graded_share_against_the_measured_one(self):
        # 10 not graded beside 30 graded is 25%; the contract measured none.
        self.promo()["live"]["not_graded"] = 10
        self.t.save()
        self.assertProblem("the live figures miss the bar: 25% of evaluations not graded, more than 10 points "
                           "from the 0% of runs the contract measured with an empty slice")
        # 50 empty beside 150 runs is the same 25%.
        self.t.entry(RULE)["jev"]["measured"]["empty"] = 50
        self.t.save()
        rc, out = self.t.check()
        self.assertEqual(rc, 0, out)

    def test_live_bar_counts_above_evaluations(self):
        # An evaluation is answered once and has one session, so neither count
        # can pass the evaluations; a record that says so wasn't read from events.
        for key in ("answered", "sessions"):
            with self.subTest(key=key):
                saved = self.promo()["live"][key]
                self.promo()["live"][key] = 31
                self.t.save()
                self.assertProblem("31 %s, more than its 30 evaluations" % key)
                self.promo()["live"][key] = saved
                self.t.save()
        self.assertEqual(jc.live_bar({"evaluations": 30, "sessions": 30, "answered": 30}, 2560), (True, []))

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

    def test_false_pass_edited_in_place(self):
        # The list keeps its length and only one field changes: that's still
        # a change to the record, and appending a new false pass is not.
        fp = {"evaluated": "2026-10-25", "recorded": "2026-10-26", "oracle": "human",
              "evidence": "https://github.com/o/r/issues/1"}
        self.t.entry("rs-007")["jev"]["false_passes"] = [dict(fp)]
        self.t.save()
        git(self.t.root, "add", "-A")
        git(self.t.root, "commit", "-q", "-m", "fp")
        for key, value in (("evaluated", "2026-10-24"), ("oracle", "ci"),
                           ("evidence", "https://github.com/o/r/issues/2")):
            with self.subTest(key=key):
                self.t.entry("rs-007")["jev"]["false_passes"] = [dict(fp, **{key: value})]
                self.t.save()
                rc, out = self.t.check("HEAD")
                self.assertIn("rs-007: a false pass recorded at the base was changed or removed", out)
        later = dict(fp, evaluated="2026-10-27", recorded="2026-10-28")
        self.t.entry("rs-007")["jev"]["false_passes"] = [dict(fp), later]
        self.t.save()
        rc, out = self.t.check("HEAD")
        self.assertNotIn("a false pass recorded at the base was changed or removed", out)

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
            # s2 stored a rules copy of its own, which its slice renders.
            write(d, "s2/ctx/review_facts.json", json.dumps(dict(facts, lines="x")))
            write(d, "s2/ctx/review_level_rules.tsv", "class\tci\t.github/**\nrule\tfull\tclass:ci\n")
            # The projection is fixed, so the corpus's sizes are known.
            tail = "the facts call for light otherwise\nfloor: the most thorough level the facts call for\n"
            shipped = ("the facts call for full when classes has ci, security, template or engine;"
                       + " or lines > 400; or files > 12; or tests_edited\n"
                       + "the facts call for standard when classes has instruction, executable, test or manifest;"
                       + " or unclassified; or criteria_changed; or lines > 40\n" + tail)
            want = sorted(len(("%s\nlevels: light < standard < full\n%slevel: standard\n" % (s, defs)).encode())
                          for s, defs in (('{"lines":12,"files":2,"classes":["docs"],"tests_changed":false,'
                                           '"tests_edited":false,'
                                           '"criteria_changed":false,"unclassified":false,"floor":"light"}', shipped),
                                          ('{"lines":0,"files":2,"classes":["docs"],"tests_changed":false,'
                                           '"tests_edited":false,'
                                           '"criteria_changed":false,"unclassified":false,"floor":"light"}',
                                           "the facts call for full when classes has ci\n" + tail)))
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = jc.main(["measure", "sessions", "--dir", d, "--root", REPO, "--budget", "2048"])
            got = json.loads(out.getvalue())
            self.assertEqual(rc, 0)
            self.assertEqual((got["runs"], got["max"], got["p90"], got["over_budget"], got["population"]),
                             (2, want[1], want[1], 0, "koto-sessions"))
            # s2 alone measures its own copy's rendering, not the shipped one's.
            shutil.rmtree(os.path.join(d, "s1"))
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rc = jc.main(["measure", "sessions", "--dir", d, "--root", REPO, "--budget", "2048"])
            self.assertEqual((rc, json.loads(out.getvalue())["max"]), (0, want[0]))
            self.assertIn("--budget 2048", got["command"])
            self.assertNotIn("--slice", got["command"])
        finally:
            shutil.rmtree(d)

    def measure_slice(self, dirs, slice_name):
        out, err = io.StringIO(), io.StringIO()
        argv = ["measure", "sessions", "--slice", slice_name, "--root", REPO]
        for d in dirs:
            argv += ["--dir", d]
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = jc.main(argv)
        return rc, json.loads(out.getvalue()), err.getvalue()

    def test_key_slices(self):
        # Two roots, as a live store and an older one would be. A session is
        # one that recorded review facts; the slice is its keys' byte length.
        a, b = tempfile.mkdtemp(), tempfile.mkdtemp()
        try:
            for root, name, crit, plan, ctx in ((a, "s1", 100, 200, 3000), (a, "s2", 2000, 700, 10),
                                                (b, "s3", 1, 1, 2561)):
                write(root, "%s/ctx/review_facts.json" % name, "{}")
                write(root, "%s/ctx/review_level_criteria.txt" % name, "c" * crit)
                write(root, "%s/ctx/plan.md" % name, "p" * plan)
                write(root, "%s/ctx/context.md" % name, "x" * ctx)
            # Not a /work-on session: no review facts.
            write(b, "other/ctx/plan.md", "p" * 9000)
            rc, got, _ = self.measure_slice([a, b], "criteria-plan")
            self.assertEqual(rc, 0)
            self.assertEqual((got["runs"], got["max"], got["p90"], got["over_budget"], got["population"]),
                             (3, 2700, 2700, 1, "koto-sessions"))
            self.assertIn("--slice criteria-plan --budget 2560", got["command"])
            rc, got, _ = self.measure_slice([a, b], "design-context")
            self.assertEqual((got["runs"], got["max"], got["over_budget"]), (3, 3000, 2))
            self.assertIn("--slice design-context", got["command"])
        finally:
            shutil.rmtree(a)
            shutil.rmtree(b)

    def test_key_slices_skip_and_count(self):
        d = tempfile.mkdtemp()
        try:
            write(d, "s1/ctx/review_facts.json", "{}")
            write(d, "s1/ctx/context.md", "x" * 10)
            write(d, "s2/ctx/review_facts.json", "{}")  # no context.md
            write(d, "s3/ctx/review_facts.json", "{}")
            write(d, "elsewhere.md", "x" * 9000)
            os.symlink(os.path.join(d, "elsewhere.md"), os.path.join(d, "s3/ctx/context.md"))
            rc, got, err = self.measure_slice([d], "design-context")
            self.assertEqual(rc, 0)
            self.assertEqual((got["runs"], got["max"]), (1, 10))
            self.assertIn("skipped 1 session(s) with a missing key", err)
            self.assertIn("skipped 1 session(s) with a symlink key", err)
        finally:
            shutil.rmtree(d)

    def test_decision_reasons_slice(self):
        # Two roots, as a live store and its archive would be: a gzipped log,
        # a session whose log is in both (counted once, at its longer slice),
        # a session with no decision (an empty slice, so not a graded run, and
        # counted as empty because it reached scrutiny), one with no decision
        # that never reached scrutiny (neither), and a log with no session_id
        # (skipped and counted).
        def log(sid, decisions, reached=False):
            lines = [json.dumps({"schema_version": 1, "session_id": sid} if sid else {"schema_version": 1})]
            if reached:
                lines.append(json.dumps({"type": "transitioned", "payload": {"from": "implementation",
                                                                              "to": "scrutiny"}}))
            for state, choice, reason in decisions:
                lines.append(json.dumps({"type": "decision_recorded", "payload": {
                    "state": state, "decision": {"choice": choice, "rationale": reason,
                                                 "alternatives_considered": ["a" * 5000]}}}))
            return "\n".join(lines) + "\n"

        def size(decisions):
            return sum(len(("- choice: %s\n  reason: %s\n" % (c, r)).encode())
                       for s, c, r in decisions if s in ("analysis", "implementation"))

        one = [("analysis", "c" * 40, "r" * 60)]
        both = [("analysis", "c" * 10, "r" * 10), ("implementation", "c" * 1500, "r" * 1500)]
        gz = [("implementation", "z" * 100, "y" * 100), ("verification", "v" * 9000, "w")]
        a, b = tempfile.mkdtemp(), tempfile.mkdtemp()
        try:
            write(a, "s1/koto-s1.state.jsonl", log("id-1", one))
            write(a, "s2/koto-s2.state.jsonl", log("id-2", both[:1]))
            write(b, "s2/koto-s2.state.jsonl", log("id-2", both))
            write(a, "s3/koto-s3.state.jsonl", log("id-3", [("verification", "x", "y")], reached=True))
            write(a, "s6/koto-s6.state.jsonl", log("id-6", []))
            write(a, "s7/koto-s7.state.jsonl", log("id-7", one, reached=True))
            write(a, "s4/koto-s4.state.jsonl", log(None, one))
            os.makedirs(os.path.join(b, "s5"))
            with gzip.open(os.path.join(b, "s5", "koto-s5.state.jsonl.gz"), "wt", encoding="utf-8") as f:
                f.write(log("id-5", gz))
            rc, got, err = self.measure_slice([a, b], "decision-reasons")
            self.assertEqual(rc, 0, err)
            sizes = sorted([size(one), size(both), size(gz)])
            self.assertEqual((got["runs"], got["max"], got["over_budget"], got["population"], got["empty"]),
                             (4, sizes[-1], 1, "koto-sessions", 1))
            self.assertGreater(size(both), 2560)
            self.assertIn("--slice decision-reasons --budget 2560", got["command"])
            self.assertIn("skipped 1 log(s) with no session_id", err)
        finally:
            shutil.rmtree(a)
            shutil.rmtree(b)

    def test_unknown_slice_is_refused(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as e:
                jc.main(["measure", "sessions", "--dir", "x", "--slice", "nope"])
        self.assertEqual(e.exception.code, 2)

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


class StubOpener:
    """Answers each request from `answer_for(slice)`: a (pass, fail, unclear)
    probability triple, or a status code to fail with."""

    def __init__(self, answer_for):
        self.answer_for = answer_for
        self.requests = []

    def open(self, req, timeout=None):
        body = json.loads(req.data)
        self.requests.append((req, body))
        (label, text), = body["state"].items()
        got = self.answer_for(text)
        if isinstance(got, int):
            raise urllib.error.HTTPError(req.full_url, got, "stub", {}, None)
        p, f, u = got
        cid, = body["questions"]
        raw = json.dumps({"model": "jev-stub-1", "answers": {cid: {
            "type": "choice", "probabilities": {"pass": p, "fail": f, "unclear": u}}}}).encode()
        return _Resp(raw)


class _Resp:
    status = 200

    def __init__(self, raw):
        self.raw = raw

    def read(self):
        return self.raw

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


PASS, FAIL = (0.97, 0.02, 0.01), (0.02, 0.97, 0.01)


def answers(overrides=None):
    """Every case answered as its kind expects, except `overrides` {slice: answer}."""
    overrides = overrides or {}

    def answer_for(text):
        if text in overrides:
            return overrides[text]
        return PASS if text.startswith("good") else FAIL
    return answer_for


class FixturesTest(unittest.TestCase):
    env_at_import = dict(os.environ)

    def setUp(self):
        self.t = Tree()
        self.env = dict(os.environ)
        os.environ["KOTO_DECIDER_API_KEY"] = "test-key"
        os.environ.pop("KOTO_DECIDER_ENDPOINT", None)
        self.real = jc.build_opener

    def tearDown(self):
        jc.build_opener = self.real
        os.environ.clear()
        os.environ.update(self.env)
        self.t.close()

    def run_fixtures(self, answer_for, *extra):
        stub = StubOpener(answer_for)
        jc.build_opener = lambda: stub
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                rc = jc.main(["fixtures", RULE, "--root", self.t.root] + list(extra))
            except SystemExit as e:
                rc = e.code
        return rc, out.getvalue() + err.getvalue(), stub

    def test_bar_met(self):
        rc, out, stub = self.run_fixtures(answers())
        self.assertEqual(rc, 0, out)
        self.assertEqual(len(stub.requests), 35)
        req, body = stub.requests[0]
        self.assertEqual(body["model"], "jev-latest")
        self.assertEqual(list(body["state"]), ["facts"])
        q = body["questions"]["fits"]
        self.assertEqual((q["type"], q["instructions"]), ("choice", "Is it fine?"))
        self.assertEqual(q["criteria"], {"pass": "It is fine.", "fail": "It is not fine.", "unclear": "Can't tell."})
        # The key rides only in the unredirected headers, so a redirect can't carry it.
        self.assertNotIn("Authorization", req.headers)
        self.assertEqual(req.unredirected_hdrs.get("Authorization"), "Bearer test-key")
        self.assertNotIn("test-key", out)
        run = json.loads(out.strip().splitlines()[-1])["fixture_run"]
        self.assertEqual(run["model"], "jev-stub-1")
        self.assertEqual(run["counts"]["good"]["pass"], 10)
        self.assertEqual(run["declared_sha256"], self.t.entry(RULE)["jev"]["declared"]["sha256"])
        self.assertEqual(run["fixtures_blob"], jc.git_blob(self.t.root, FIXTURES))

    def test_threshold_makes_a_low_win_unclear(self):
        rc, out, _ = self.run_fixtures(answers({"good 0": (0.85, 0.1, 0.05)}))
        self.assertEqual(rc, 0, out)
        self.assertIn("good: pass=9 fail=0 unclear=1 error=0", out)

    def test_bar_failures(self):
        cases = {"one seeded-bad pass": {"bad 3": PASS},
                 "one adversarial pass": {"adv 1": PASS},
                 "seven good passes": {"good 0": FAIL, "good 1": FAIL, "good 2": FAIL},
                 "one error": {"bad 0": 400}}
        for name, overrides in cases.items():
            with self.subTest(name):
                rc, out, _ = self.run_fixtures(answers(overrides))
                self.assertEqual(rc, 1, out)
                self.assertIn("bar not met", out)

    def test_eight_good_passes_meet_the_bar(self):
        rc, out, _ = self.run_fixtures(answers({"good 0": FAIL, "good 1": (0.4, 0.3, 0.3)}))
        self.assertEqual(rc, 0, out)

    def test_retries_a_5xx_once(self):
        seen = []

        def answer_for(text):
            seen.append(text)
            if text == "good 0" and seen.count(text) == 1:
                return 503
            return answers()(text)
        rc, out, stub = self.run_fixtures(answer_for)
        self.assertEqual(rc, 0, out)
        self.assertEqual(len(stub.requests), 36)

    def test_refusals_send_nothing(self):
        def refuse(*_):
            raise AssertionError("nothing may be sent")

        with self.subTest("no key"):
            os.environ.pop("KOTO_DECIDER_API_KEY")
            rc, out, stub = self.run_fixtures(refuse)
            self.assertEqual((rc, stub.requests), (2, []))
            os.environ["KOTO_DECIDER_API_KEY"] = "test-key"
        for url in ("http://example.com/v1", "https://user:pw@example.com/v1", "ftp://example.com"):
            with self.subTest(url):
                rc, out, stub = self.run_fixtures(refuse, "--endpoint", url)
                self.assertEqual((rc, stub.requests), (2, []), out)
        with self.subTest("an undeclared criterion"):
            self.t.entry(RULE)["check"]["criterion"] = "missing"
            self.t.save()
            rc, out, stub = self.run_fixtures(refuse)
            self.assertEqual((rc, stub.requests), (2, []), out)
            self.t.entry(RULE)["check"]["criterion"] = "fits"
            self.t.save()
        with self.subTest("fixtures below the minimums"):
            write(self.t.root, FIXTURES, "\n".join(json.dumps(c) for c in fixture_lines()[:-1]) + "\n")
            rc, out, stub = self.run_fixtures(refuse)
            self.assertEqual((rc, stub.requests), (2, []), out)

    def test_loopback_http_is_allowed(self):
        for url in ("http://localhost:8080/v1", "http://127.0.0.1/v1", "http://[::1]:9/v1"):
            with self.subTest(url):
                rc, out, _ = self.run_fixtures(answers(), "--endpoint", url)
                self.assertEqual(rc, 0, out)

    def test_a_loopback_stub_never_gets_the_key(self):
        # A sentinel stands in for a real key: if fixtures ever read the
        # variable for a loopback endpoint, the sentinel shows up here.
        sentinel = "sentinel-key-must-not-reach-a-stub"
        os.environ["KOTO_DECIDER_API_KEY"] = sentinel
        for url in ("http://127.0.0.1:9/v1", "https://localhost/v1", "http://[::1]:9/v1"):
            with self.subTest(url):
                rc, out, stub = self.run_fixtures(answers(), "--endpoint", url)
                self.assertEqual(rc, 0, out)
                self.assertTrue(stub.requests)
                for req, body in stub.requests:
                    self.assertEqual(req.unredirected_hdrs.get("Authorization"), "Bearer " + jc.LOOPBACK_KEY)
                    seen = json.dumps([dict(req.headers), dict(req.unredirected_hdrs), body])
                    self.assertNotIn(sentinel, seen)
                self.assertNotIn(sentinel, out)
        with self.subTest("no key at all"):
            os.environ.pop("KOTO_DECIDER_API_KEY")
            rc, out, _ = self.run_fixtures(answers(), "--endpoint", "http://127.0.0.1:9/v1")
            self.assertEqual(rc, 0, out)

    def test_the_tests_never_inherit_a_key(self):
        # The module drops any inherited key at import; FixturesTest sets its
        # own fake one, which is the only key a test can hold.
        self.assertEqual(os.environ.get("KOTO_DECIDER_API_KEY"), "test-key")
        self.assertNotIn("KOTO_DECIDER_API_KEY", self.env_at_import)

    def test_every_request_failing(self):
        rc, out, _ = self.run_fixtures(lambda _t: 500)
        self.assertEqual(rc, 2, out)
        self.assertIn("every request failed", out)


def event(seq, ts, type_, **payload):
    p = {"state": "check_state", "gate": "fits", "rule_id": "fits", "visit_seq": 1, "mode": "veto"}
    p.update(payload)
    return json.dumps({"seq": seq, "timestamp": ts + "T10:00:00Z", "type": type_, "payload": p})


class FiguresTest(unittest.TestCase):
    def setUp(self):
        self.t = Tree()
        self.dir = os.path.realpath(tempfile.mkdtemp(prefix="jev-figures-test."))

    def tearDown(self):
        self.t.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def log(self, name, *events, header=None):
        head = header if header is not None else json.dumps({"schema_version": 1, "session_id": "sid-" + name})
        write(self.dir, "%s/koto-%s.state.jsonl" % (name, name), "\n".join((head,) + events) + "\n")

    def figures(self, *extra):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                rc = jc.main(["figures", RULE, "--root", self.t.root, "--sessions", self.dir] + list(extra))
            except SystemExit as e:
                rc = e.code
        lines = out.getvalue().strip().splitlines()
        live = json.loads(lines[0])["live"] if lines and lines[0].startswith("{") else None
        return rc, live, out.getvalue() + err.getvalue()

    def test_counts_by_evaluation(self):
        self.log("a",
                 # visit 1: a fallback written twice, then a pass: one answered evaluation
                 event(2, "2026-10-21", "decider_fallback", reason="provider_error", input_bytes=200),
                 event(3, "2026-10-21", "decider_fallback", reason="provider_error", input_bytes=200),
                 event(4, "2026-10-21", "decider_checked", outcome="pass", input_bytes=210),
                 # visit 5: over budget, answered by the agent: unanswered
                 event(6, "2026-10-22", "decider_fallback", visit_seq=5, reason="over_budget", input_bytes=3000),
                 event(7, "2026-10-22", "decider_fallback", visit_seq=5, reason="over_budget", input_bytes=3000),
                 event(8, "2026-10-22", "decider_check_answered", visit_seq=5, answer="pass"),
                 # another criterion of the same gate: ignored
                 event(9, "2026-10-22", "decider_checked", rule_id="other", outcome="pass"),
                 "not json")
        rc, live, out = self.figures("--from", "2026-10-21", "--to", "2026-10-22")
        self.assertEqual(rc, 0, out)
        self.assertEqual((live["evaluations"], live["sessions"], live["answered"],
                          live["over_budget_fallbacks"], live["max_input_bytes"]), (2, 1, 1, 1, 3000))
        self.assertIn("skipped 1", out)

    def test_not_graded_evaluations_are_left_out(self):
        self.log("a",
                 # visit 1: only not_graded, written twice: left out
                 event(2, "2026-10-21", "decider_checked", outcome="not_graded"),
                 event(3, "2026-10-21", "decider_checked", outcome="not_graded"),
                 # visit 2: not_graded, then a pass on a changed slice: answered
                 event(4, "2026-10-21", "decider_checked", visit_seq=2, outcome="not_graded"),
                 event(5, "2026-10-21", "decider_checked", visit_seq=2, outcome="pass", input_bytes=90),
                 # visit 3: not_graded beside a fallback: graded and unanswered
                 event(6, "2026-10-21", "decider_checked", visit_seq=3, outcome="not_graded"),
                 event(7, "2026-10-21", "decider_fallback", visit_seq=3, reason="provider_error", input_bytes=90),
                 # visit 4: not_graded beside an escape: graded and unanswered
                 event(8, "2026-10-21", "decider_checked", visit_seq=4, outcome="not_graded"),
                 event(9, "2026-10-21", "decider_checked", visit_seq=4, outcome="escape", input_bytes=90))
        # A session whose only evaluation had nothing to grade isn't a session.
        self.log("b", event(2, "2026-10-21", "decider_checked", outcome="not_graded"))
        rc, live, out = self.figures("--from", "2026-10-21", "--to", "2026-10-21")
        self.assertEqual(rc, 0, out)
        self.assertEqual((live["evaluations"], live["sessions"], live["answered"], live["not_graded"]),
                         (3, 1, 1, 2), out)

    def not_graded_log(self, name, n):
        self.log(name, *[event(v + 2, "2026-10-21", "decider_checked", visit_seq=v + 1, outcome="not_graded")
                         for v in range(n)])

    def test_the_bar_counts_graded_evaluations_only(self):
        # The contract measured 250 empty slices beside its 150 runs (62.5%),
        # about the share of not-graded evaluations the cases below add, so
        # the not-graded share alone decides none of them.
        self.t.entry(RULE)["jev"]["measured"]["empty"] = 250
        self.t.save()
        cases = [("29 graded beside 50 not graded", dict(sessions=29, per_session=1, answered_total=29), 50, 0, 1),
                 ("4 graded sessions beside 10 not-graded ones",
                  dict(sessions=4, per_session=10, answered_total=40), 0, 10, 1),
                 ("28 of 30 graded answered (93.3%), beside not-graded runs that would lift it",
                  dict(sessions=5, per_session=6, answered_total=28), 40, 10, 1),
                 ("30 graded across 5 sessions all answered, beside not-graded runs",
                  dict(sessions=5, per_session=6, answered_total=30), 40, 10, 0)]
        for name, kw, extra_evals, extra_sessions, want in cases:
            with self.subTest(name):
                shutil.rmtree(self.dir)
                os.makedirs(self.dir)
                self.bar_log(**kw)
                if extra_evals:
                    self.not_graded_log("ng-many", extra_evals)
                for i in range(extra_sessions):
                    self.not_graded_log("ng-%d" % i, 1)
                rc, live, out = self.figures("--from", "2026-10-21", "--to", "2026-10-21", "--bar")
                self.assertEqual(rc, want, out)
                self.assertEqual(live["not_graded"], extra_evals + extra_sessions, out)

    def test_the_bar_holds_a_not_graded_share_far_from_the_measured_one(self):
        # 30 graded evaluations across 5 sessions, all answered, meet every
        # other bar. 20 not-graded ones beside them are 40%.
        cases = [("no empty slice measured", None, 1), ("25% measured", 50, 1),
                 ("about 39% measured", 96, 0), ("about 48% measured", 140, 0), ("60% measured", 225, 1)]
        for name, empty, want in cases:
            with self.subTest(name):
                shutil.rmtree(self.dir)
                os.makedirs(self.dir)
                m = self.t.entry(RULE)["jev"]["measured"]
                m.pop("empty", None)
                if empty is not None:
                    m["empty"] = empty
                self.t.save()
                self.bar_log(sessions=5, per_session=6, answered_total=30)
                self.not_graded_log("ng", 20)
                rc, live, out = self.figures("--from", "2026-10-21", "--to", "2026-10-21", "--bar")
                self.assertEqual(rc, want, out)
                self.assertIn("not graded: 20 of 50 (40%)", out)
                self.assertIn("answered: 30 of 30 evaluations (100%)", out)
                if want:
                    self.assertIn("40% of evaluations not graded, more than 10 points from the", out)

    def test_window_edges(self):
        self.log("a", event(2, "2026-10-20", "decider_checked", outcome="pass", visit_seq=1),
                 event(3, "2026-10-21", "decider_checked", outcome="pass", visit_seq=2),
                 event(4, "2026-10-25", "decider_checked", outcome="pass", visit_seq=3),
                 event(5, "2026-10-26", "decider_checked", outcome="pass", visit_seq=4))
        rc, live, out = self.figures("--from", "2026-10-21", "--to", "2026-10-25")
        self.assertEqual(live["evaluations"], 2, out)

    def test_default_window_follows_a_false_pass(self):
        self.t.entry(RULE)["jev"]["false_passes"] = [{"evaluated": "2026-10-22", "recorded": "2026-10-23",
                                                     "oracle": "review", "evidence": "https://github.com/o/r/pull/1"}]
        self.t.save()
        self.log("a", event(2, "2026-10-22", "decider_checked", outcome="pass", visit_seq=1),
                 event(3, "2026-10-23", "decider_checked", outcome="pass", visit_seq=2))
        rc, live, out = self.figures("--to", "2026-10-30")
        self.assertEqual((live["from"], live["evaluations"]), ("2026-10-23", 1), out)

    def bar_log(self, sessions, per_session, answered_total, over=0, max_bytes=300):
        n = 0
        for s in range(sessions):
            evs = []
            for v in range(per_session):
                n += 1
                ok = n <= answered_total
                evs.append(event(v + 2, "2026-10-21", "decider_checked", visit_seq=v + 1,
                                 outcome="pass" if ok else "unanswered", input_bytes=max_bytes))
            self.log("s%d" % s, *evs)
        for i in range(over):
            self.log("o%d" % i, event(2, "2026-10-21", "decider_fallback", reason="over_budget", input_bytes=10))

    def test_bar(self):
        # Each failing case misses one bar only: 29 evaluations still spread
        # over 29 sessions, and 949 of 1,000 is exactly 94.9% answered.
        cases = [("29 evaluations", dict(sessions=29, per_session=1, answered_total=29), 1),
                 ("4 sessions", dict(sessions=4, per_session=10, answered_total=40), 1),
                 ("94.9% answered", dict(sessions=5, per_session=200, answered_total=949), 1),
                 ("an over_budget fallback", dict(sessions=5, per_session=6, answered_total=30, over=1), 1),
                 ("an input one byte over", dict(sessions=5, per_session=6, answered_total=30, max_bytes=2049), 1),
                 ("30, 5 and 95%", dict(sessions=5, per_session=6, answered_total=30), 0),
                 ("95% exactly", dict(sessions=5, per_session=20, answered_total=95), 0)]
        for name, kw, want in cases:
            with self.subTest(name):
                shutil.rmtree(self.dir)
                os.makedirs(self.dir)
                self.bar_log(**kw)
                rc, live, out = self.figures("--from", "2026-10-21", "--to", "2026-10-21", "--bar")
                self.assertEqual(rc, want, out)


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
        checked = {}
        for e in registry["rules"]:
            jev = e.get("jev") or {}
            script = jev.get("slice_script")
            if script not in (jc.REVIEW_LEVEL_SH, jc.DECISION_REASONS_SH) or not jev.get("fixtures"):
                continue
            cases, problems = jc.load_fixtures(os.path.join(REPO, jev["fixtures"]))
            self.assertEqual(problems, [], e["id"])
            for c in cases:
                with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as t:
                    if script == jc.REVIEW_LEVEL_SH:
                        # Null facts is a session with none recorded: an
                        # empty file, which projects the way `slice` does.
                        if c["input"]["facts"] is not None:
                            json.dump(c["input"]["facts"], t)
                        argv = ["project", t.name, c["input"]["level"]]
                    else:
                        # A session log: its header, then the case's events.
                        t.write(json.dumps({"schema_version": 1, "session_id": "fixture"}) + "\n")
                        for ev in c["input"]["events"]:
                            t.write(json.dumps(ev, ensure_ascii=False) + "\n")
                        argv = ["slice", t.name]
                try:
                    r = subprocess.run([os.path.join(REPO, script)] + argv, capture_output=True, text=True)
                finally:
                    os.unlink(t.name)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertEqual(r.stdout, c["slice"], "%s case %s" % (e["id"], c["id"]))
                checked[script] = checked.get(script, 0) + 1
        self.assertEqual(sorted(checked), sorted([jc.REVIEW_LEVEL_SH, jc.DECISION_REASONS_SH]))


GUIDE = os.path.join(REPO, "docs", "guides", "jev-criteria.md")
GUIDE_SECTIONS = ("Reading the live figures", "Promoting a criterion", "Demoting a criterion")


def guide_section(text, name):
    """The body of the guide's `## <name>` section, or "" when it has none."""
    parts = re.split(r"^## ", text, flags=re.M)
    return next((p for p in parts if p.startswith(name + "\n")), "")


def guide_problems(text):
    """The guide's missing sections, and the promotion review step if the
    promotion section doesn't name it. The phrases are the criterion's words;
    rewording the guide's sentences means updating them here."""
    found = re.findall(r"^## (.+?)\s*$", text, re.M)
    out = ["missing section: %s" % s for s in GUIDE_SECTIONS if s not in found]
    promo = guide_section(text, "Promoting a criterion")
    for phrase in ("figures --bar", "fixtures", "doesn't merge their own"):
        if phrase not in promo:
            out.append("promotion section doesn't name %r" % phrase)
    return out


class GuideTest(unittest.TestCase):
    def setUp(self):
        with open(GUIDE, encoding="utf-8") as f:
            self.text = f.read()

    def test_guide_has_its_sections(self):
        self.assertEqual(guide_problems(self.text), [])

    def test_a_missing_section_fails(self):
        for s in GUIDE_SECTIONS:
            with self.subTest(section=s):
                cut = self.text.replace("## %s\n" % s, "")
                self.assertIn("missing section: %s" % s, guide_problems(cut))

    def test_the_review_step_is_required(self):
        cut = self.text.replace("figures --bar", "figures")
        self.assertIn("promotion section doesn't name 'figures --bar'", guide_problems(cut))

    def test_the_live_figures_name_the_exported_attributes(self):
        live = guide_section(self.text, "Reading the live figures")
        for attr in ("koto.session.id", "koto.visit.seq", "koto.check", "koto.rule.id",
                     "koto.decider.outcome", "koto.decider.reason", "koto.decider.input_bytes"):
            self.assertIn(attr, live)
        self.assertIn("jev_criteria.py figures", live)


REFERENCE = os.path.join(REPO, "references", "jev-criteria.md")
# Each condition of "Replacing a seat", by the phrase that opens it. The
# phrases are the reference's own words; rewording them means updating them
# here.
SEAT_CONDITIONS = ("Every question the seat asks is trusted.",
                   "The decider is active for the session.",
                   "An unanswered criterion brings the seat back.",
                   "The batch's findings take the seat's place.",
                   "Each condition is tested.")


def seat_problems(text):
    """What "Replacing a seat" is missing: the section, or any condition."""
    body = guide_section(text, "Replacing a seat")
    if not body:
        return ["missing section: Replacing a seat"]
    return ["missing condition: %s" % c for c in SEAT_CONDITIONS if c not in body]


class ReferenceTest(unittest.TestCase):
    def setUp(self):
        with open(REFERENCE, encoding="utf-8") as f:
            self.text = f.read()

    def test_the_seat_rule_states_every_condition(self):
        self.assertEqual(seat_problems(self.text), [])

    def test_a_missing_condition_or_section_fails(self):
        for c in SEAT_CONDITIONS:
            with self.subTest(condition=c):
                self.assertIn("missing condition: %s" % c, seat_problems(self.text.replace(c, "")))
        cut = self.text.replace("## Replacing a seat\n", "")
        self.assertEqual(seat_problems(cut), ["missing section: Replacing a seat"])

    def test_both_documents_state_the_not_graded_rule(self):
        with open(GUIDE, encoding="utf-8") as f:
            guide = guide_section(f.read(), "Reading the live figures")
        bars = guide_section(self.text, "The bars")
        for name, body in (("reference", bars), ("guide", guide)):
            with self.subTest(document=name):
                flat = " ".join(body.split())
                self.assertIn("`koto.decider.outcome` `not_graded`", flat)
                self.assertIn("graded evaluations only", flat)
                # The guard on the share, at the number the code holds.
                self.assertIn("within %d points" % int(jc.NOT_GRADED_DRIFT * 100), flat)

    def test_the_lower_bounds_say_so(self):
        for rid in ("rs-019", "rs-020"):
            with self.subTest(rule=rid):
                self.assertIn("These figures are a lower bound: the full slice also carries the diff.",
                              " ".join(guide_section(self.text, rid).split()))


if __name__ == "__main__":
    unittest.main()

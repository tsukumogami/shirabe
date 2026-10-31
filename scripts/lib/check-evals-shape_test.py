#!/usr/bin/env python3
"""Tests for scripts/lib/check-evals-shape.py: the tier-2 release-subset rule
and the script-graded case shape.

Usage: python3 scripts/lib/check-evals-shape_test.py

Writes throwaway evals.json files and runs the checker on them. The older
rules (names, prompts, criteria, the reference-only exemption) are covered by
scripts/check-skill_test.sh.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check-evals-shape.py")


def scenario(name, tier=1, **extra):
    entry = {"name": name, "prompt": "do " + name, "expectations": ["it works"]}
    if tier != 1:
        entry["tier"] = tier
    entry.update(extra)
    return entry


class ShapeCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.skill_md = os.path.join(self.tmp.name, "SKILL.md")
        with open(self.skill_md, "w") as fh:
            fh.write("# skill\n")

    def tearDown(self):
        self.tmp.cleanup()

    def check(self, evals):
        path = os.path.join(self.tmp.name, "evals.json")
        with open(path, "w") as fh:
            json.dump({"evals": evals}, fh)
        proc = subprocess.run([sys.executable, SCRIPT, path, self.skill_md],
                              capture_output=True, text=True)
        return proc.returncode, proc.stdout + proc.stderr


class ReleaseSubsetTest(ShapeCase):
    def test_one_release_per_behaviour_passes(self):
        rc, out = self.check([
            scenario("plan-a"),
            scenario("merge-a", tier=2, behaviour="merge-refused", release=True),
            scenario("merge-b", tier=2, behaviour="merge-refused"),
            scenario("resume-a", tier=2, behaviour="resume", release=True),
        ])
        self.assertEqual(rc, 0, out)
        self.assertIn("shape ok", out)

    def test_tier1_only_suite_needs_nothing(self):
        rc, out = self.check([scenario("plan-a"), scenario("plan-b")])
        self.assertEqual(rc, 0, out)

    def test_tier2_without_behaviour_fails(self):
        rc, out = self.check([scenario("merge-a", tier=2, release=True)])
        self.assertEqual(rc, 1, out)
        self.assertIn("eval 'merge-a' (#1): a tier-2 entry needs a kebab-case `behaviour`", out)

    def test_behaviour_with_no_release_fails(self):
        rc, out = self.check([scenario("merge-a", tier=2, behaviour="merge-refused"),
                              scenario("merge-b", tier=2, behaviour="merge-refused")])
        self.assertEqual(rc, 1, out)
        self.assertIn("behaviour 'merge-refused' needs exactly one `\"release\": true` entry, has 0",
                      out)

    def test_behaviour_with_two_releases_fails_naming_both(self):
        rc, out = self.check([
            scenario("merge-a", tier=2, behaviour="merge-refused", release=True),
            scenario("merge-b", tier=2, behaviour="merge-refused", release=True),
        ])
        self.assertEqual(rc, 1, out)
        self.assertIn("has 2: eval 'merge-a' (#1), eval 'merge-b' (#2)", out)

    def test_release_must_be_true(self):
        rc, out = self.check([scenario("merge-a", tier=2, behaviour="m", release=True),
                              scenario("merge-b", tier=2, behaviour="m", release=False)])
        self.assertEqual(rc, 1, out)
        self.assertIn("eval 'merge-b' (#2): `release` is only ever `true`", out)

    def test_tier1_entry_with_behaviour_or_release_fails(self):
        for extra in ({"behaviour": "x"}, {"release": True}):
            with self.subTest(extra=extra):
                rc, out = self.check([scenario("plan-a", **extra)])
                self.assertEqual(rc, 1, out)
                self.assertIn("belong on tier-2 entries", out)

    def test_name_with_a_comma_fails(self):
        rc, out = self.check([scenario("plan,a")])
        self.assertEqual(rc, 1, out)
        self.assertIn("`name` can't contain a comma", out)

    def test_tier_outside_one_and_two_fails(self):
        # Every reader takes tier-2 as `tier` other than 1; a 3, a "2" or a
        # boolean would read differently to different readers (shirabe#880).
        for bad in (3, 0, "2", True, None):
            entry = scenario("merge-a", tier=2, behaviour="merge-refused", release=True)
            entry["tier"] = bad
            rc, out = self.check([entry])
            self.assertEqual(rc, 1, (bad, out))
            self.assertIn("`tier` is 1 or 2 (absent means 1), not %s" % json.dumps(bad), out)
            self.assertNotIn("behaviour", out, (bad, out))

    def test_tier_one_and_two_pass(self):
        rc, out = self.check([scenario("plan-a", tier=1),
                              scenario("merge-a", tier=2, behaviour="merge-refused", release=True)])
        self.assertEqual(rc, 0, out)

    def test_behaviour_must_be_kebab_case(self):
        rc, out = self.check([scenario("merge-a", tier=2, behaviour="Merge Refused", release=True)])
        self.assertEqual(rc, 1, out)
        self.assertIn("needs a kebab-case `behaviour`", out)


def script_case(name="handoff-execute-contract", **extra):
    entry = {"id": 34, "name": name, "grader": "script", "handoff": "execute",
             "run": "scripts/check-handoff.sh deliver execute"}
    entry.update(extra)
    return entry


class ScriptCaseTest(ShapeCase):
    """A `grader: script` case needs name, run and handoff, and no prompt or criteria."""

    def test_script_case_without_prompt_or_expectations_passes(self):
        rc, out = self.check([scenario("plan-a"), script_case()])
        self.assertEqual(rc, 0, out)
        self.assertIn("shape ok", out)

    def test_script_case_needs_run_handoff_and_name(self):
        for key in ("run", "handoff", "name"):
            for bad in (None, "", "  "):
                with self.subTest(key=key, bad=bad):
                    entry = script_case()
                    if bad is None:
                        del entry[key]
                    else:
                        entry[key] = bad
                    rc, out = self.check([entry])
                    self.assertEqual(rc, 1, out)
                    if key == "name":
                        self.assertIn("missing or empty `name`", out)
                    else:
                        self.assertIn("a `grader: script` case needs a non-empty `%s`" % key, out)

    def test_graded_case_still_needs_prompt_and_expectations(self):
        no_prompt = scenario("plan-a")
        del no_prompt["prompt"]
        no_criteria = scenario("plan-b")
        del no_criteria["expectations"]
        rc, out = self.check([script_case(), no_prompt, no_criteria])
        self.assertEqual(rc, 1, out)
        self.assertIn("eval 'plan-a' (#2): missing or empty `prompt`", out)
        self.assertIn("eval 'plan-b' (#3): needs a non-empty `expectations` or `assertions` list",
                      out)

    def test_unknown_grader_keeps_graded_rules(self):
        entry = script_case(grader="scripted")
        rc, out = self.check([entry])
        self.assertEqual(rc, 1, out)
        self.assertIn("missing or empty `prompt`", out)


class RealDeliverEvalsTest(unittest.TestCase):
    def test_deliver_evals_pass_with_the_script_case(self):
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        evals = os.path.join(root, "skills", "deliver", "evals", "evals.json")
        with open(evals) as fh:
            cases = json.load(fh)["evals"]
        self.assertTrue(any(c.get("grader") == "script" and c.get("id") == 34 for c in cases))
        proc = subprocess.run([sys.executable, SCRIPT, evals,
                               os.path.join(root, "skills", "deliver", "SKILL.md")],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)


if __name__ == "__main__":
    unittest.main()

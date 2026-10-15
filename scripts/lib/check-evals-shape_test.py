#!/usr/bin/env python3
"""Tests for scripts/lib/check-evals-shape.py: the tier-2 release-subset rule.

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


class ReleaseSubsetTest(unittest.TestCase):
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

    def test_behaviour_must_be_kebab_case(self):
        rc, out = self.check([scenario("merge-a", tier=2, behaviour="Merge Refused", release=True)])
        self.assertEqual(rc, 1, out)
        self.assertIn("needs a kebab-case `behaviour`", out)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Offline tests for review-shadow.py. No test reaches the network or Jev.

Run: python3 scripts/review-shadow/test_review_shadow.py [TestClass ...]
"""

import copy
import importlib.util
import json
import re
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("review_shadow", HERE / "review-shadow.py")
rs = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rs)


def _write(tmp, name, data):
    p = Path(tmp) / name
    p.write_text(json.dumps(data) if not isinstance(data, str) else data, encoding="utf-8")
    return p


class TestLoader(unittest.TestCase):
    def setUp(self):
        self.good = json.loads((HERE / "criteria.json").read_text(encoding="utf-8"))
        self.tmp = tempfile.mkdtemp()

    def refused(self, data, needle):
        p = _write(self.tmp, "c.json", data)
        with self.assertRaises(rs.ConfigError) as cm:
            rs.load_criteria(p)
        self.assertIn(needle, str(cm.exception))

    def test_shipped_files_load(self):
        crit = rs.load_criteria()
        rs.load_categories(crit)
        self.assertEqual(len(crit["criteria"]), 10)
        for c in crit["criteria"]:
            self.assertEqual(set(c["values"]), {"pass", "fail"})
            self.assertEqual(len(c["escape"]), 1)
            self.assertRegex(c["rule_id"], r"^rs-[0-9]{3}$")

    def test_missing_file(self):
        with self.assertRaises(rs.ConfigError):
            rs.load_criteria(Path(self.tmp) / "absent.json")

    def test_boolean_refused(self):
        bad = copy.deepcopy(self.good)
        bad["criteria"][0]["type"] = "boolean"
        self.refused(bad, "boolean")
        bad = copy.deepcopy(self.good)
        bad["criteria"][0]["values"] = True
        self.refused(bad, "boolean")

    def test_duplicate_id(self):
        bad = copy.deepcopy(self.good)
        bad["criteria"][1]["rule_id"] = bad["criteria"][0]["rule_id"]
        self.refused(bad, "duplicate")

    def test_non_opaque_id(self):
        bad = copy.deepcopy(self.good)
        bad["criteria"][0]["rule_id"] = "attribution"
        self.refused(bad, "rs-NNN")

    def test_missing_rule_ref(self):
        bad = copy.deepcopy(self.good)
        bad["criteria"][0]["rule_ref"] = "references/no-such-file.md"
        self.refused(bad, "rule_ref")
        bad["criteria"][0]["rule_ref"] = "../outside.md"
        self.refused(bad, "rule_ref")
        bad["criteria"][0]["rule_ref"] = "skills"
        self.refused(bad, "rule_ref")

    def test_strict_id_and_threshold(self):
        bad = copy.deepcopy(self.good)
        bad["criteria"][0]["rule_id"] = "rs-001\n"
        self.refused(bad, "rs-NNN")
        bad = copy.deepcopy(self.good)
        bad["criteria"][0]["threshold"] = True
        self.refused(bad, "threshold")

    def test_values_and_escape(self):
        bad = copy.deepcopy(self.good)
        bad["criteria"][0]["values"] = {"pass": "a", "fail": "b", "maybe": "c"}
        self.refused(bad, "values")
        bad = copy.deepcopy(self.good)
        bad["criteria"][0]["escape"] = {}
        self.refused(bad, "escape")

    def test_unknown_slice_kind_and_check(self):
        bad = copy.deepcopy(self.good)
        bad["criteria"][0]["slice_kind"] = "whole-diff"
        self.refused(bad, "slice_kind")
        bad = copy.deepcopy(self.good)
        bad["criteria"][0]["check"] = "nope"
        self.refused(bad, "check")

    def test_jev_on_unbounded_slice(self):
        bad = copy.deepcopy(self.good)
        jev = next(c for c in bad["criteria"] if c["observer"] == "jev")
        jev["slice_kind"] = "pr-text"
        self.refused(bad, "unbounded")

    def test_missing_field(self):
        bad = copy.deepcopy(self.good)
        del bad["criteria"][0]["artifact_kind"]
        self.refused(bad, "artifact_kind")

    def test_category_names_unknown_rule(self):
        crit = rs.load_criteria()
        cats = json.loads((HERE / "categories.json").read_text(encoding="utf-8"))
        cats["categories"]["stale-comment"]["rule_ids"] = ["rs-999"]
        p = _write(self.tmp, "cat.json", cats)
        with self.assertRaises(rs.ConfigError):
            rs.load_categories(crit, p)

    def test_criterion_group_must_be_a_category(self):
        crit = rs.load_criteria()
        cats = json.loads((HERE / "categories.json").read_text(encoding="utf-8"))
        del cats["categories"]["stale-comment"]
        p = _write(self.tmp, "cat.json", cats)
        with self.assertRaises(rs.ConfigError):
            rs.load_categories(crit, p)

    def test_data_files_name_no_pull_request_or_url(self):
        for name in ("criteria.json", "categories.json"):
            text = (HERE / name).read_text(encoding="utf-8")
            self.assertIsNone(re.search(r"#[0-9]+", text), name)
            self.assertIsNone(re.search(r"https?://", text), name)

    def test_check_command(self):
        self.assertEqual(rs.main(["check"]), 0)


if __name__ == "__main__":
    unittest.main()

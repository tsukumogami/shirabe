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


HEAD = "a" * 40


class StubFetcher:
    """Serves a fixture in place of `gh`; records every call."""

    def __init__(self, fixture):
        self.fx = fixture
        self.calls = []

    def pull(self, repo, number):
        self.calls.append(("pull", repo, number))
        return self.fx["pull"]

    def compare(self, repo, base, head):
        self.calls.append(("compare", base, head))
        return self.fx["compare"]

    def raw_file(self, repo, path, head):
        self.calls.append(("raw", path))
        if path not in self.fx.get("raw", {}):
            raise rs.FetchError("absent")
        return self.fx["raw"][path]

    def tree(self, repo, head):
        if self.fx.get("tree") is None:
            raise rs.FetchError("no tree")
        return self.fx["tree"], False

    def body_edits(self, repo, number):
        if self.fx.get("edits") is None:
            raise rs.FetchError("no history")
        return [tuple(e) for e in self.fx["edits"]]


def fixture(name="pr-basic.json"):
    return json.loads((HERE / "fixtures" / name).read_text(encoding="utf-8"))


def fetched(fx=None, **kw):
    return rs.fetch_pr(StubFetcher(fx or fixture()), "octo/demo", 7, HEAD, **kw)


class TestArguments(unittest.TestCase):
    def test_repo(self):
        self.assertEqual(rs.check_repo("octo/demo"), "octo/demo")
        for bad in ("octo", "octo/../x", "../demo", "octo/demo/x", "-x/y", "octo/ demo", "octo/.."):
            if bad == "-x/y":
                continue  # a leading dash is a legal name character; it never reaches a shell
            with self.assertRaises(ValueError, msg=bad):
                rs.check_repo(bad)

    def test_pr_and_head(self):
        self.assertEqual(rs.check_pr("12"), 12)
        for bad in ("0", "-1", "12a", "", "1e3"):
            with self.assertRaises(ValueError):
                rs.check_pr(bad)
        rs.check_head(HEAD)
        for bad in ("A" * 40, "a" * 39, "a" * 41, "abc"):
            with self.assertRaises(ValueError):
                rs.check_head(bad)

    def test_panel_run(self):
        rs.check_panel_run("claude:0f3a-11")
        rs.check_panel_run("koto:work-on-7:abc123")
        rs.check_panel_run(None)
        for bad in ("claude:", "koto:x", "claude:a/b", "other:x"):
            with self.assertRaises(ValueError):
                rs.check_panel_run(bad)


class TestFetch(unittest.TestCase):
    def test_fetch_shape(self):
        pr = fetched()
        self.assertEqual(pr["base_ref"], "main")
        self.assertTrue(pr["public"])
        self.assertEqual([f["path"] for f in pr["files"]], ["lib/fetch.py", "docs/guides/fetch.md"])
        self.assertIn("docs/guides/fetch.md", pr["texts"])
        self.assertIn("docs/guides", pr["tree"])
        self.assertEqual(pr["diff_kind"], "mixed")

    def test_body_as_of_a_time(self):
        pr = fetched(body_at="2026-09-01T12:00:00Z")
        self.assertTrue(pr["body"].startswith("First version"))
        pr = fetched(body_at="2026-09-03T00:00:00Z")
        self.assertTrue(pr["body"].startswith("Adds a retry"))
        pr = fetched(body_at="2026-08-01T00:00:00Z")
        self.assertTrue(pr["body"].startswith("First version"))

    def test_body_history_unreadable_falls_back(self):
        fx = fixture()
        fx["edits"] = None
        pr = fetched(fx)
        self.assertEqual(pr["body_source"], "current")
        self.assertIn("body-history-unreadable", pr["reasons"])

    def test_body_file_wins(self):
        pr = fetched(body_file="Given body.")
        self.assertEqual((pr["body"], pr["body_source"]), ("Given body.", "file"))

    def test_diff_kind(self):
        self.assertEqual(rs.diff_kind(["docs/a.md", "README.md"]), "docs")
        self.assertEqual(rs.diff_kind(["skills/x/SKILL.md"]), "code")
        self.assertEqual(rs.diff_kind(["docs/a.md", "scripts/x.sh"]), "mixed")
        self.assertEqual(rs.diff_kind(["docs/spikes/tool.py"]), "code")


class TestSlices(unittest.TestCase):
    def test_bound_is_utf8_bytes(self):
        s = rs.make_slice("x", 1, {"a": "x" * 2560})
        self.assertFalse(s["over_bound"])
        s = rs.make_slice("x", 1, {"a": "x" * 2561})
        self.assertTrue(s["over_bound"])
        s = rs.make_slice("x", 1, {"a": "é" * 1281})  # 2,562 bytes, 1,281 characters
        self.assertTrue(s["over_bound"])

    def test_pr_summary_holds_part1_and_file_list_only(self):
        (s,) = rs.slice_pr_summary(fetched())
        self.assertEqual(set(s["inputs"]), {"pr_body_part1", "diff_summary"})
        self.assertNotIn("Test plan", s["inputs"]["pr_body_part1"])
        self.assertIn("M lib/fetch.py +4 -1", s["inputs"]["diff_summary"])
        self.assertNotIn("@@", s["inputs"]["diff_summary"])
        self.assertNotIn("session.get", s["inputs"]["diff_summary"])

    def test_pr_summary_falls_back_to_directories(self):
        pr = fetched()
        pr["files"] = [{"path": f"src/pkg{i // 40}/module_with_a_long_name_{i}.py", "status": "added",
                        "additions": 10, "deletions": 0, "patch": ""} for i in range(120)]
        (s,) = rs.slice_pr_summary(pr)
        self.assertFalse(s["over_bound"])
        self.assertNotEqual(s["meta"]["summary_level"], "files")
        self.assertIn("src/pkg0/ 40 files +400 -0", s["inputs"]["diff_summary"])

    def test_pr_summary_over_bound_when_part1_too_long(self):
        pr = fetched()
        pr["body"] = "word " * 700
        (s,) = rs.slice_pr_summary(pr)
        self.assertTrue(s["over_bound"])

    def test_code_hunks_only_comment_hunks(self):
        slices = rs.slice_code_hunks(fetched())
        self.assertEqual(len(slices), 1)
        self.assertEqual(slices[0]["inputs"]["path"], "lib/fetch.py")
        self.assertIn("Retry twice", slices[0]["inputs"]["hunks"])

    def test_code_hunks_pack_and_flag_oversize(self):
        pr = fetched()
        hunk = "@@ -1,2 +1,2 @@\n-# old\n+# new " + "x" * 1000
        pr["files"] = [{"path": "a.py", "status": "modified", "additions": 1, "deletions": 1,
                        "patch": "\n".join([hunk] * 3)}]
        slices = rs.slice_code_hunks(pr)
        self.assertEqual(len(slices), 2)
        self.assertTrue(all(not s["over_bound"] for s in slices))
        pr["files"][0]["patch"] = "@@ -1,2 +1,2 @@\n+# " + "y" * 3000
        (s,) = rs.slice_code_hunks(pr)
        self.assertTrue(s["over_bound"])

    def test_a_large_new_file_is_split_at_blank_lines(self):
        block = "+# comment for block\n" + "+x = 1\n" * 120 + "+"
        patch = "@@ -0,0 +1,300 @@\n" + "\n".join([block] * 4)
        pr = fetched()
        pr["files"] = [{"path": "new.py", "status": "added", "additions": 300, "deletions": 0, "patch": patch}]
        slices = rs.slice_code_hunks(pr)
        self.assertGreater(len(slices), 1)
        self.assertTrue(all(not s["over_bound"] for s in slices))
        self.assertTrue(all(s["inputs"]["hunks"].startswith("@@ -0,0 +1,300 @@") for s in slices))

    def test_doc_pairs_two_locations(self):
        slices, meta = rs.slice_doc_pairs(fetched())
        self.assertEqual(meta, {"pairs_dropped": 0, "pairs_over_bound": 0})
        self.assertEqual(len(slices), 1)
        s = slices[0]
        self.assertEqual(set(s["inputs"]), {"path", "location_a", "location_b"})
        both = s["inputs"]["location_a"] + s["inputs"]["location_b"]
        self.assertIn("up to 3 times", both)
        self.assertIn("gives up after 3 tries", both)

    def test_doc_pairs_cap(self):
        pr = fetched()
        paras = [f"Paragraph {i} mentions `alpha` and `beta`." for i in range(12)]
        text = "\n\n".join(paras) + "\n"
        pr["texts"] = {"docs/x.md": text}
        patch = "@@ -1,0 +1,%d @@\n" % text.count("\n") + "\n".join("+" + l for l in text.split("\n")[:-1])
        pr["files"] = [{"path": "docs/x.md", "status": "added", "additions": 1, "deletions": 0, "patch": patch}]
        slices, meta = rs.slice_doc_pairs(pr)
        self.assertEqual(len(slices), rs.MAX_DOC_PAIRS)
        self.assertEqual(meta["pairs_dropped"], 66 - rs.MAX_DOC_PAIRS)

    def test_doc_pairs_over_bound_are_counted_not_sent(self):
        pr = fetched()
        big = "Long passage about `alpha`. " + "filler " * 250
        text = big + "\n\n" + big.replace("Long", "Other") + "\n"
        pr["texts"] = {"docs/x.md": text}
        patch = "@@ -1,0 +1,3 @@\n" + "\n".join("+" + l for l in text.split("\n")[:-1])
        pr["files"] = [{"path": "docs/x.md", "status": "added", "additions": 3, "deletions": 0, "patch": patch}]
        slices, meta = rs.slice_doc_pairs(pr)
        self.assertEqual(slices, [])
        self.assertEqual(meta["pairs_over_bound"], 1)

    def test_table_rows_and_list_items_are_passages(self):
        text = "Intro.\n\n| a | 12 |\n| b | 13 |\n\n- item 14\n- item 15\n\n```\ncode 99\n```\n"
        units = [p for _, p in rs.paragraphs(text)]
        self.assertEqual(units, ["Intro.", "| a | 12 |", "| b | 13 |", "- item 14", "- item 15"])

    def test_pr_text_added_lines_numbered(self):
        t = rs.slice_pr_text(fetched())
        self.assertIn(("docs/guides/fetch.md", 5,
                       "Each call to `fetch` waits 250 ms between attempts, and gives up after 3 tries."),
                      t["added"])


if __name__ == "__main__":
    unittest.main()

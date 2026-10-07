#!/usr/bin/env python3
"""Offline tests for review-shadow.py. No test reaches the network or Jev.

Run: python3 scripts/review-shadow/test_review_shadow.py [TestClass ...]
"""

import copy
import os
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
        self.assertEqual(len(crit["criteria"]), 17)
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
        for bad in ("octo", "octo/../x", "../demo", "octo/demo/x", "octo/ demo", "octo/.."):
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

    def test_diff_kind_edge_cases(self):
        # Both sides of a rename count: moving a file out of docs/ is never docs.
        files = [{"path": "skills/x/guide.md", "previous_path": "docs/guide.md"}]
        self.assertEqual(rs.diff_kind(rs.changed_paths(files)), "mixed")
        files = [{"path": "scripts/tool.py", "previous_path": "docs/tool.py"}]
        self.assertEqual(rs.diff_kind(rs.changed_paths(files)), "code")
        # Only docs/**.md and the top-level README.md are docs.
        for path in ("CLAUDE.md", "AGENTS.md", "CHANGELOG.md", "skills/x/README.md", "docs/x.yml"):
            self.assertEqual(rs.diff_kind([path]), "code", path)
        # No changed paths is its own kind, never docs.
        self.assertEqual(rs.diff_kind([]), "none")

    def test_rename_reaches_diff_kind_through_fetch(self):
        fx = fixture()
        fx["compare"]["files"] = [{"filename": "skills/x/guide.md", "previous_filename": "docs/guide.md",
                                   "status": "renamed", "additions": 0, "deletions": 0}]
        self.assertEqual(fetched(fx)["diff_kind"], "mixed")

    def test_diff_kind(self):
        self.assertEqual(rs.diff_kind(["docs/a.md", "README.md"]), "docs")
        self.assertEqual(rs.diff_kind(["skills/x/SKILL.md"]), "code")
        self.assertEqual(rs.diff_kind(["docs/a.md", "scripts/x.sh"]), "mixed")
        self.assertEqual(rs.diff_kind(["docs/spikes/tool.py"]), "code")


class TestGhArgv(unittest.TestCase):
    """The fetcher's argument lists: -f only, never -F, and encoded paths."""

    def setUp(self):
        self.calls = []
        real = rs.subprocess.run

        def fake(cmd, **kw):
            self.calls.append(cmd)

            class R:
                returncode = 0
                stdout = json.dumps({"files": [], "tree": [],
                                     "data": {"repository": {"pullRequest": {"userContentEdits": {"nodes": []}}}}})
                stderr = ""
            return R()
        rs.subprocess.run = fake
        self.addCleanup(setattr, rs.subprocess, "run", real)

    def test_argv(self):
        g = rs.GhFetcher()
        g.raw_file("o/r", "docs/a b#c?d.md", HEAD)
        g.compare("o/r", "b" * 40, HEAD)
        g.body_edits("o/r", 7)
        for cmd in self.calls:
            self.assertEqual(cmd[:2], ["gh", "api"])
            self.assertNotIn("-F", cmd)
        self.assertIn(f"repos/o/r/contents/docs/a%20b%23c%3Fd.md?ref={HEAD}", self.calls[0])
        self.assertIn(f"repos/o/r/compare/{'b' * 40}...{HEAD}?per_page=100&page=1", self.calls[1])
        self.assertEqual([a for a in self.calls[2] if a.startswith(("o=", "r="))], ["o=o", "r=r"])


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

    def test_pr_summary_cuts_a_long_part1_at_a_paragraph(self):
        pr = fetched()
        para = "This paragraph explains one change in some detail. " * 10
        pr["body"] = "\n\n".join([para] * 8) + "\n\n---\nTest plan"
        (s,) = rs.slice_pr_summary(pr)
        body = s["inputs"]["pr_body_part1"]
        self.assertFalse(s["over_bound"])
        self.assertTrue(s["meta"]["body_cut"])
        self.assertTrue(body.endswith(rs.BODY_CUT_MARKER))
        kept = body[:-len(rs.BODY_CUT_MARKER)]
        self.assertTrue(kept.endswith(para.rstrip()))
        self.assertLess(kept.count("\n\n") + 1, 8)
        self.assertIn("M lib/fetch.py +4 -1", s["inputs"]["diff_summary"])

    def test_pr_summary_cuts_a_single_long_paragraph_at_a_sentence(self):
        pr = fetched()
        pr["body"] = "A sentence of moderate length goes here. " * 100
        (s,) = rs.slice_pr_summary(pr)
        body = s["inputs"]["pr_body_part1"][:-len(rs.BODY_CUT_MARKER)]
        self.assertFalse(s["over_bound"])
        self.assertTrue(body.endswith("here."))

    def test_pr_summary_leaves_a_fitting_body_whole(self):
        (s,) = rs.slice_pr_summary(fetched())
        self.assertNotIn("body_cut", s["meta"])
        self.assertNotIn(rs.BODY_CUT_MARKER, s["inputs"]["pr_body_part1"])

    def test_pr_summary_stays_over_bound_when_the_cut_cannot_fit(self):
        pr = fetched()
        pr["body"] = "word " * 700
        pr["files"] = [{"path": f"d{i}/f.py", "status": "added", "additions": 1, "deletions": 0, "patch": ""}
                       for i in range(400)]
        (s,) = rs.slice_pr_summary(pr)
        self.assertTrue(s["over_bound"])
        self.assertNotIn("body_cut", s["meta"])

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

    def test_a_long_block_is_cut_at_comments(self):
        lines = ["+x = 0"] * 30
        for k in (0, 120, 240):
            lines += [f"+# note {k}"] + [f"+value_{k}_{i} = {i}" for i in range(110)]
        patch = "@@ -0,0 +1,400 @@\n" + "\n".join(lines)
        pr = fetched()
        pr["files"] = [{"path": "big.py", "status": "added", "additions": 400, "deletions": 0, "patch": patch}]
        slices = rs.slice_code_hunks(pr)
        self.assertTrue(slices)
        self.assertTrue(all(not s["over_bound"] for s in slices))
        text = "\n".join(s["inputs"]["hunks"] for s in slices)
        for k in (0, 120, 240):
            self.assertIn(f"# note {k}", text)
        self.assertNotIn("+x = 0\n+x = 0", text)  # code before any comment isn't sent

    def test_a_single_huge_line_stays_over_bound(self):
        pr = fetched()
        pr["files"] = [{"path": "one.py", "status": "added", "additions": 1, "deletions": 0,
                        "patch": "@@ -0,0 +1,1 @@\n+# " + "z" * 3000}]
        (s,) = rs.slice_code_hunks(pr)
        self.assertTrue(s["over_bound"])

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

    def test_doc_pairs_over_bound_are_kept_as_unanswered_slices(self):
        pr = fetched()
        big = "Long passage about `alpha`. " + "filler " * 250
        text = big + "\n\n" + big.replace("Long", "Other") + "\n"
        pr["texts"] = {"docs/x.md": text}
        patch = "@@ -1,0 +1,3 @@\n" + "\n".join("+" + l for l in text.split("\n")[:-1])
        pr["files"] = [{"path": "docs/x.md", "status": "added", "additions": 3, "deletions": 0, "patch": patch}]
        slices, meta = rs.slice_doc_pairs(pr)
        self.assertEqual(len(slices), 1)
        self.assertTrue(slices[0]["over_bound"])
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


def pr_text(body="Changes the helper.", added=(), texts=None, tree=None, public=True):
    """A pr-text slice built by hand. Violation text in these tests is assembled at
    run time, so this file never carries the literal strings its checks look for."""
    return {"body": body, "part1": rs.part1(body), "added": list(added), "texts": texts or {},
            "tree": set(tree) if tree is not None else set(), "public": public, "paths": []}


class TestRs001Attribution(unittest.TestCase):
    CO = "Co-Author" + "ed-By: Someone <a@b>"
    GEN = "Generated " + "with [Claude Code]"

    def verdict(self, pt):
        return rs.check_attribution(pt, None)[0]

    def test_seeded(self):
        self.assertEqual(self.verdict(pr_text(body="Fix.\n\n" + self.CO)), "fail")
        self.assertEqual(self.verdict(pr_text(added=[("a.md", 3, self.GEN)])), "fail")
        link = "see https://" + "claude." + "ai/code/x"
        self.assertEqual(self.verdict(pr_text(added=[("a.md", 1, link)])), "fail")

    def test_clean(self):
        self.assertEqual(self.verdict(pr_text()), "pass")

    def test_near_miss(self):
        self.assertEqual(self.verdict(pr_text(body="The co-author of the design reviewed it.")), "pass")
        self.assertEqual(self.verdict(pr_text(added=[("a.md", 1, "Generated with the release script.")])), "pass")


class TestRs002PrivateTerms(unittest.TestCase):
    TERM = "Zorblax-Internal"  # invented; every encoded form is computed below

    def verdict(self, pt, terms=(TERM,)):
        return rs.check_private_terms(pt, list(terms) if terms is not None else None)

    def test_every_form_is_caught(self):
        import base64
        raw = self.TERM.encode()
        forms = [self.TERM, self.TERM.upper(), raw.hex(),
                 hashlib_hex("sha1", raw), hashlib_hex("sha256", raw), hashlib_hex("md5", raw),
                 hashlib_hex("sha256", self.TERM.lower().encode())]
        for off in range(3):
            forms.append(base64.b64encode(b"xyz"[:off] + raw + b"!").decode())
        for form in forms:
            v, hits, _ = self.verdict(pr_text(added=[("f.txt", 9, f"value = {form}")]))
            self.assertEqual(v, "fail", form)
            self.assertEqual(hits, [("f.txt", 9)])

    def test_home_path_of_a_real_account(self):
        import getpass
        v, _, _ = self.verdict(pr_text(body="Run it from /home/" + getpass.getuser() + "/src."))
        self.assertEqual(v, "fail")
        v, _, _ = self.verdict(pr_text(body="Run it from /Users/" + self.TERM + "/src."))
        self.assertEqual(v, "fail")

    def test_example_home_paths_are_not_leaks(self):
        v, _, _ = self.verdict(pr_text(body="For example /home/" + "alice-example/src or /Users/me-example/x."))
        self.assertEqual(v, "pass")

    def test_clean_and_near_miss(self):
        self.assertEqual(self.verdict(pr_text())[0], "pass")
        self.assertEqual(self.verdict(pr_text(body="Zorb and blax are fine; so is /home/user/x."))[0], "pass")

    def test_no_list_is_not_a_pass(self):
        self.assertEqual(self.verdict(pr_text(), terms=None)[0:3:2], ("unanswered", "no-denylist"))
        self.assertEqual(self.verdict(pr_text(), terms=[])[0:3:2], ("unanswered", "no-denylist"))

    def test_private_repository_is_out_of_scope_through_applies_to(self):
        crit = rs.load_criteria()
        (v,) = [x for x in rs.run_scripts(crit, pr_text(body=self.TERM, public=False), [self.TERM])
                if x["rule_id"] == "rs-002"]
        self.assertEqual((v["verdict"], v["reason"]), ("pass", "not-applicable"))
        (v,) = [x for x in rs.run_scripts(crit, pr_text(body=self.TERM, public=True), [self.TERM])
                if x["rule_id"] == "rs-002"]
        self.assertEqual(v["verdict"], "fail")

    def test_unknown_visibility_is_public(self):
        fx = fixture()
        del fx["pull"]["base"]["repo"]["private"]
        self.assertTrue(fetched(fx)["public"])
        fx["pull"]["base"]["repo"]["private"] = None
        self.assertTrue(fetched(fx)["public"])
        fx["pull"]["base"]["repo"]["private"] = True
        self.assertFalse(fetched(fx)["public"])

    def test_output_never_names_the_term(self):
        _, hits, reason = self.verdict(pr_text(body=self.TERM))
        self.assertNotIn(self.TERM.lower(), json.dumps([hits, reason]).lower())

    def test_list_inside_a_work_tree_is_refused(self):
        p = HERE / "terms-test.txt"
        p.write_text(self.TERM + "\n", encoding="utf-8")
        try:
            with self.assertRaises(rs.ConfigError):
                rs.load_private_terms(str(p))
        finally:
            p.unlink()
        outside = Path(tempfile.mkdtemp()) / "terms.txt"
        outside.write_text("# comment\n" + self.TERM + "\n\n", encoding="utf-8")
        self.assertEqual(rs.load_private_terms(str(outside)), [self.TERM])


def hashlib_hex(name, data):
    import hashlib
    return hashlib.new(name, data).hexdigest()


class TestRs003ScratchPath(unittest.TestCase):
    SCRATCH = "wi" + "p/"

    def verdict(self, pt):
        return rs.check_scratch_path(pt, None)[0]

    def test_seeded(self):
        self.assertEqual(self.verdict(pr_text(added=[("docs/a.md", 2, f"See `{self.SCRATCH}notes.md`.")])), "fail")
        self.assertEqual(self.verdict(pr_text(body=f"Plan in {self.SCRATCH}plan.md")), "fail")

    def test_clean(self):
        self.assertEqual(self.verdict(pr_text()), "pass")

    def test_near_miss(self):
        self.assertEqual(self.verdict(pr_text(added=[("a.md", 1, "swi" + "p/x and wipe/y and wip is a word")])), "pass")
        self.assertEqual(self.verdict(pr_text(added=[(self.SCRATCH + "state.md", 1, self.SCRATCH + "x.md")])), "pass")


class TestRs004UnfinishedWording(unittest.TestCase):
    def verdict(self, body):
        return rs.check_unfinished_wording(pr_text(body=body), None)[0]

    def test_seeded(self):
        self.assertEqual(self.verdict("Adds the parser. Validation is not yet implemented."), "fail")
        self.assertEqual(self.verdict("Adds the parser; " + "TO" + "DO: errors."), "fail")

    def test_clean(self):
        self.assertEqual(self.verdict("Adds the parser and its validation."), "pass")

    def test_near_miss(self):
        self.assertEqual(self.verdict("Removes the `" + "TO" + "DO` marker from the parser."), "pass")
        self.assertEqual(self.verdict("Addresses the " + "TO" + "DOs the review left."), "pass")
        self.assertEqual(self.verdict("Done.\n\n---\n\nFollow-ups: not yet implemented items."), "pass")


class TestRs005PastedParagraph(unittest.TestCase):
    PARA = "This paragraph is long enough to count, well over sixty characters of prose text."

    def verdict(self, text, added_lines):
        pt = pr_text(added=[("docs/a.md", ln, "") for ln in added_lines], texts={"docs/a.md": text})
        return rs.check_pasted_paragraph(pt, None)[0]

    def test_seeded(self):
        self.assertEqual(self.verdict(f"{self.PARA}\n\nOther.\n\n{self.PARA}\n", [5]), "fail")

    def test_clean(self):
        self.assertEqual(self.verdict(f"{self.PARA}\n\nOther.\n", [1]), "pass")

    def test_near_miss(self):
        short = "Too short to count."
        self.assertEqual(self.verdict(f"{short}\n\n{short}\n", [3]), "pass")
        # A duplicate that predates the change isn't this change's finding.
        self.assertEqual(self.verdict(f"{self.PARA}\n\n{self.PARA}\n\nNew line.\n", [5]), "pass")


class TestRs006DanglingPath(unittest.TestCase):
    TREE = ["docs", "docs/guides", "docs/guides/a.md", "scripts", "scripts/x.sh"]

    def verdict(self, line, tree=TREE, path="docs/guides/b.md"):
        return rs.check_dangling_path(pr_text(added=[(path, 1, line)], tree=tree), None)[0:3:2]

    def test_seeded(self):
        self.assertEqual(self.verdict("See `docs/guides/missing.md`."), ("fail", None))

    def test_clean(self):
        self.assertEqual(self.verdict("See `docs/guides/a.md` and `scripts/`."), ("pass", None))
        self.assertEqual(self.verdict("Relative: `guides/a.md`.", path="docs/b.md"), ("pass", None))

    def test_line_suffix_and_dot_prefix(self):
        self.assertEqual(self.verdict("See `docs/guides/missing.md:12`."), ("fail", None))
        self.assertEqual(self.verdict("See `./docs/guides/a.md` and `docs/guides/a.md:3-9`."), ("pass", None))

    def test_near_miss(self):
        self.assertEqual(self.verdict("Run `git log` and `owner/repo:docs/x.md` and `<path>/x.md`."), ("pass", None))
        self.assertEqual(self.verdict("See `docs/missing.md`.", path="scripts/x.sh"), ("pass", None))

    def test_unreadable_tree(self):
        pt = pr_text(added=[("a.md", 1, "`docs/a.md`")])
        pt["tree"] = None
        self.assertEqual(rs.check_dangling_path(pt, None)[0:3:2], ("unanswered", "tree-unreadable"))


class TestScan(unittest.TestCase):
    """scan over a throwaway repository: exits non-zero on a failure, zero when clean."""

    def setUp(self):
        import subprocess
        self.dir = Path(tempfile.mkdtemp())
        self.git = lambda *a: subprocess.run(["git", "-C", str(self.dir), *a], check=True,
                                             capture_output=True, text=True)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")
        (self.dir / "README.md").write_text("Hello.\n")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "init")
        self.git("checkout", "-q", "-b", "topic")
        self.cwd = os.getcwd()
        os.chdir(self.dir)
        self.addCleanup(os.chdir, self.cwd)

    def commit(self, name, text):
        (self.dir / name).write_text(text)
        self.git("add", ".")
        self.git("commit", "-q", "-m", "change")

    def scan(self):
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = rs.main(["scan", "--base", "main"])
        return code, out.getvalue()

    def test_clean_branch(self):
        self.commit("notes.md", "A clean note.\n")
        code, out = self.scan()
        # With no term list, the private-name check reports itself as not checked.
        self.assertIn("rs-002: not checked (no-denylist)", out)
        self.assertEqual([l for l in out.splitlines() if not l.startswith("rs-002")], [])

    def test_non_ascii_path_is_scanned(self):
        terms = Path(tempfile.mkdtemp()) / "terms.txt"
        terms.write_text("Zorblax\n", encoding="utf-8")
        self.commit("\u00e9t\u00e9.md", "Mentions Zorblax here.\n")
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = rs.main(["scan", "--base", "main", "--private-terms", str(terms)])
        self.assertEqual(code, 1)
        self.assertIn("rs-002: \u00e9t\u00e9.md:1", out.getvalue())

    def test_scan_from_a_subdirectory(self):
        (self.dir / "sub").mkdir()
        self.commit("sub/n.md", "See `README.md`.\n")
        os.chdir(self.dir / "sub")
        code, out = self.scan()
        self.assertNotIn("rs-006", out)

    def test_non_utf8_text_does_not_crash(self):
        (self.dir / "latin.md").write_bytes(b"caf\xe9 text\n")
        self.git("add", ".")
        self.git("commit", "-q", "-m", "latin")
        code, out = self.scan()
        self.assertIn(code, (0, 1))

    def test_a_claude_md_without_a_visibility_line_is_public(self):
        terms = Path(tempfile.mkdtemp()) / "terms.txt"
        terms.write_text("Zorblax\n", encoding="utf-8")
        real = rs.REPO_ROOT
        rs.REPO_ROOT = self.dir
        self.addCleanup(setattr, rs, "REPO_ROOT", real)
        self.commit("CLAUDE.md", "# A project\n\nNo visibility header here.\n")
        self.commit("n.md", "Mentions Zorblax.\n")
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = rs.main(["scan", "--base", "main", "--private-terms", str(terms)])
        self.assertEqual(code, 1)
        self.assertIn("rs-002: n.md:1", out.getvalue())

    def test_failure_names_rule_path_and_line(self):
        (self.dir / "docs").mkdir()
        self.commit("docs/a.md", "A doc.\n")
        self.commit("notes.md", "Line one.\nSee `docs/nowhere.md`.\n")
        code, out = self.scan()
        self.assertEqual(code, 1)
        self.assertIn("rs-006: notes.md:2", out)


def stub_send(verdict_for=lambda rule_id: "pass", log=None, status=200, usage=True, raw=None):
    """A Jev transport stand-in. Answers each question with `verdict_for(rule_id)`
    at 0.95, or `escape` spread below the threshold."""
    def send(body):
        if log is not None:
            log.append(("jev", sorted(body["questions"])))
        if raw is not None:
            return status, raw
        answers = {}
        for rid, q in body["questions"].items():
            esc = [k for k in q["criteria"] if k not in ("pass", "fail")][0]
            v = verdict_for(rid)
            probs = {"pass": 0.02, "fail": 0.02, esc: 0.01}
            if v == "escape":
                probs = {"pass": 0.5, "fail": 0.45, esc: 0.05}
            else:
                probs[v] = 0.95
            answers[rid] = {"type": "choice", "choice": v, "probabilities": probs}
        out = {"model": "jev-test", "answers": answers}
        if usage:
            out["usage"] = {"input_tokens": 100, "output_tokens": 10}
        return status, json.dumps(out).encode()
    return send


class TestGrade(unittest.TestCase):
    def setUp(self):
        self.crit = rs.load_criteria()
        self.pr = fetched()

    def graded(self, send, terms=("Zorblax",), batched=True):
        return rs.grade(self.crit, self.pr, list(terms) if terms is not None else None, send, batched)

    def test_record_fields(self):
        body = self.graded(stub_send())
        rec = rs.new_record("octo/demo", 7, HEAD, panel_kind="pre-merge", graded_body_at="x",
                            body_source="history", diff_kind="mixed", in_sample=False, reasons=[], **body)
        for field in ("schema", "trial", "run_id", "recorded_at", "repo", "pr", "head_sha", "panel_run_id",
                      "session_id", "panel_kind", "graded_body_at", "diff_kind", "in_sample", "host",
                      "criteria_version", "mode", "slices", "verdicts", "criteria", "rounds", "models",
                      "unread_usage_attempts", "tokens", "status", "not_graded_reason"):
            self.assertIn(field, rec)
        self.assertEqual(rec["trial"], "jev-review-shadow")
        for v in rec["verdicts"]:
            self.assertEqual(set(v) >= {"rule_id", "slice", "verdict", "observer", "probabilities", "reason"}, True)
            self.assertIn(v["verdict"], ("pass", "fail", "escape", "unanswered"))
        self.assertTrue(all(v["observer"] == "script" for v in rec["verdicts"] if v["rule_id"] <= "rs-006"))
        self.assertEqual(rec["tokens"]["input"], 100 * len(rec["rounds"]))

    def test_scripts_run_before_any_jev_request(self):
        log = []
        real = rs.run_scripts

        def logged(*a):
            log.append(("scripts",))
            return real(*a)
        rs.run_scripts = logged
        self.addCleanup(setattr, rs, "run_scripts", real)
        self.graded(stub_send(log=log))
        self.assertEqual(log[0], ("scripts",))
        self.assertEqual([e for e in log if e[0] == "scripts"], [("scripts",)])

    def test_run_status(self):
        self.assertEqual(self.graded(stub_send())["status"], "unanimous-pass")
        self.assertEqual(self.graded(stub_send(lambda r: "escape" if r == "rs-007" else "pass"))["status"],
                         "inconclusive")
        self.assertEqual(self.graded(stub_send(lambda r: "fail" if r == "rs-007" else "pass"))["status"], "dissent")
        self.assertEqual(self.graded(stub_send(), terms=None)["status"], "inconclusive")  # no-denylist

    def test_batched_and_unbatched(self):
        b = self.graded(stub_send())
        summary = [r for r in b["rounds"] if r["slice"].startswith("pr-summary")]
        self.assertEqual(len(summary), 1)
        self.assertEqual(summary[0]["rule_ids"], ["rs-007", "rs-008"])
        self.assertTrue(summary[0]["batched"])
        u = self.graded(stub_send(), batched=False)
        self.assertEqual(u["mode"], "unbatched")
        self.assertEqual(len([r for r in u["rounds"] if r["slice"].startswith("pr-summary")]), 2)
        self.assertFalse(any(r["batched"] for r in u["rounds"]))

    def test_no_key_is_not_graded(self):
        b = self.graded(None)
        self.assertEqual((b["status"], b["not_graded_reason"]), ("not-graded", "no-key"))
        self.assertTrue(all(v["reason"] == "no-key" for v in b["verdicts"] if v["observer"] == "jev"))

    def test_transport_failure_is_retried_once_then_not_graded(self):
        calls = []

        def down(body):
            calls.append(1)
            return None, b""
        b = self.graded(down)
        self.assertEqual((b["status"], b["not_graded_reason"]), ("not-graded", "transport"))
        self.assertEqual(len(calls), 2 * len(b["rounds"]))

    def test_unreadable_usage_is_counted(self):
        b = self.graded(stub_send(usage=False))
        self.assertEqual(b["unread_usage_attempts"], len(b["rounds"]))
        b = self.graded(stub_send(raw=b"not json"))
        self.assertEqual(b["unread_usage_attempts"], 2 * len(b["rounds"]))

    def test_long_body_is_cut_and_still_graded(self):
        self.pr["body"] = "word " * 700
        sent = []
        b = self.graded(stub_send(log=sent))
        self.assertTrue(any("rs-007" in q for _, q in sent))
        self.assertNotEqual(b["status"], "not-graded")
        (s,) = [x for x in b["slices"] if x["kind"] == "pr-summary"]
        self.assertTrue(s["body_cut"])
        self.assertFalse(s["over_bound"])

    def test_over_bound_slice_is_never_sent_and_is_not_graded(self):
        self.pr["body"] = "word " * 700
        self.pr["files"] = [{"path": f"d{i}/f.py", "status": "added", "additions": 1, "deletions": 0, "patch": ""}
                            for i in range(400)]
        sent = []
        b = self.graded(stub_send(log=sent))
        self.assertFalse(any("rs-007" in q for _, q in sent))
        v = [x for x in b["verdicts"] if x["rule_id"] == "rs-007"]
        self.assertEqual([(x["verdict"], x["reason"]) for x in v], [("unanswered", "over-bound")])
        self.assertEqual((b["status"], b["not_graded_reason"]), ("not-graded", "over-bound"))

    def test_threshold_and_malformed_answers(self):
        c = next(c for c in self.crit["criteria"] if c["rule_id"] == "rs-010")
        ok = {"answers": {"rs-010": {"probabilities": {"pass": 0.9, "fail": 0.05, "unclear": 0.05}}}}
        self.assertEqual(rs.map_answer(c, ok)[0], "pass")
        low = {"answers": {"rs-010": {"probabilities": {"pass": 0.89, "fail": 0.06, "unclear": 0.05}}}}
        self.assertEqual(rs.map_answer(c, low)[0], "escape")
        esc = {"answers": {"rs-010": {"probabilities": {"pass": 0.02, "fail": 0.03, "unclear": 0.95}}}}
        self.assertEqual(rs.map_answer(c, esc)[0], "escape")
        self.assertEqual(rs.map_answer(c, {"answers": {}})[0:3:2], ("unanswered", "missing-answer"))
        bad = {"answers": {"rs-010": {"probabilities": {"pass": 2}}}}
        self.assertEqual(rs.map_answer(c, bad)[0:3:2], ("unanswered", "unreadable-answer"))

    def test_credentials_are_redacted_before_sending(self):
        token = "gh" + "p_" + "A" * 36
        self.pr["body"] = f"Rotates {token} in the fixture."
        sent = []

        def send(body):
            sent.append(json.dumps(body))
            return stub_send()(body)
        self.graded(send)
        self.assertTrue(sent)
        self.assertFalse(any(token in s for s in sent))

    def test_no_changed_paths_is_not_graded(self):
        self.pr["files"] = []
        sent = []
        b = self.graded(stub_send(log=sent))
        self.assertEqual((b["status"], b["not_graded_reason"]), ("not-graded", "no-changed-paths"))
        self.assertEqual(sent, [])

    def test_a_bad_key_never_reaches_an_error_message(self):
        with self.assertRaises(rs.ConfigError) as cm:
            rs.https_transport("https://example.invalid", "SECRETKEY\nX", 1)
        self.assertNotIn("SECRETKEY", str(cm.exception))
        send = rs.https_transport("https://example.invalid", "  SECRETKEY\n", 1)  # stripped, then valid
        self.assertTrue(callable(send))

    def test_a_5xx_then_200_is_retried(self):
        calls = []
        ok = stub_send()

        def flaky(body):
            calls.append(1)
            return (503, b"") if len(calls) == 1 else ok(body)
        answer, reason, attempts, _, _ = rs.ask_jev(flaky, {"questions": {"rs-010": rs.question(
            next(c for c in self.crit["criteria"] if c["rule_id"] == "rs-010"))}})
        self.assertEqual((reason, attempts), (None, 2))
        self.assertIsNotNone(answer)

    def test_boolean_probabilities_are_unreadable(self):
        c = next(c for c in self.crit["criteria"] if c["rule_id"] == "rs-010")
        bad = {"answers": {"rs-010": {"probabilities": {"pass": True, "fail": 0, "unclear": 0}}}}
        self.assertEqual(rs.map_answer(c, bad)[0], "unanswered")

    def test_https_only(self):
        with self.assertRaises(rs.ConfigError):
            rs.https_transport("http://example.com", "k", 1)


class TestStore(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp()) / "store"
        os.environ["REVIEW_SHADOW_HOME"] = str(self.home)
        self.addCleanup(os.environ.pop, "REVIEW_SHADOW_HOME", None)

    def test_permissions(self):
        home = rs.store_home()
        path = rs.write_record(home, rs.new_record("octo/demo", 7, HEAD, status="dissent"))
        self.assertEqual(oct(path.stat().st_mode & 0o777), "0o600")
        self.assertEqual(oct(path.parent.stat().st_mode & 0o777), "0o700")
        for d in [home, home / "records", home / "records" / "octo"]:
            self.assertEqual(oct(d.stat().st_mode & 0o777), "0o700", d)
        self.assertEqual(json.loads(path.read_text())["status"], "dissent")
        self.assertEqual(list(path.parent.glob("*.tmp")), [])

    def test_refuses_a_home_inside_a_work_tree(self):
        os.environ["REVIEW_SHADOW_HOME"] = str(HERE / "store")
        with self.assertRaises(rs.ConfigError):
            rs.store_home()

    def test_grade_never_runs_koto(self):
        seen = []
        real = rs.subprocess.run

        def spy(cmd, **kw):
            seen.append(cmd[0])
            return real(cmd, **kw)
        rs.subprocess.run = spy
        self.addCleanup(setattr, rs.subprocess, "run", real)
        rs.store_home()
        rs.grade(rs.load_criteria(), fetched(), None, stub_send())
        self.assertNotIn("koto", seen)


class TestReport(unittest.TestCase):
    """A hand-built store whose figures are worked out below, head by head.

    pre-merge, code diffs, out-of-sample:
      h1 unanimous pass, clean panel         -> agreement
      h2 unanimous pass, upheld correctness  -> false pass
      h3 dissent (rs-010 fail), upheld stale comment -> agreement
      h4 inconclusive, clean panel           -> dissent on clean
      h5 dissent, only a dismissed finding   -> clean panel, dissent on clean
      h6 outcome with no grade               -> not graded
      h7 unanimous pass, only unknown finding -> undetermined
    Scored heads 5; agreement 2/5; unanimous passes 2 with 1 false pass (50%);
    blocked 2, miss rate 1/2; clean 3, dissent on clean 2/3; coverage of the
    upheld findings: 1 covered (stale comment), 1 open judgment (correctness).
    """

    def setUp(self):
        self.home = Path(tempfile.mkdtemp()) / "store"
        os.environ["REVIEW_SHADOW_HOME"] = str(self.home)
        self.addCleanup(os.environ.pop, "REVIEW_SHADOW_HOME", None)
        self.crit = rs.load_criteria()
        self.cats = rs.load_categories(self.crit)
        self.n = 0

    def head(self, i):
        return f"{i:040x}"

    def record(self, i, status, in_sample=False, rs010="pass", mode="batched", diff_kind="code"):
        self.n += 1
        crit = [{"rule_id": c["rule_id"], "verdict": "pass", "slices": 1} for c in self.crit["criteria"]]
        for c in crit:
            if c["rule_id"] == "rs-010":
                c["verdict"] = rs010
        rec = rs.new_record("octo/demo", i, self.head(i), in_sample=in_sample, mode=mode, status=status,
                            diff_kind=diff_kind, criteria=crit, tokens={"input": 10, "output": 1})
        rec["recorded_at"] = f"2026-09-30T00:00:{self.n:02d}Z"
        rs.write_record(self.home, rec)

    def outcome(self, i, *findings):
        parsed = [rs.parse_finding(f, self.cats) for f in findings]
        rs.record_outcome(self.home, "octo/demo", i, self.head(i), "pre-merge", f"claude:run-{i}", parsed)

    def build(self):
        self.record(1, "unanimous-pass"); self.outcome(1)
        self.record(2, "unanimous-pass"); self.outcome(2, "correctness:upheld")
        self.record(3, "dissent", rs010="fail"); self.outcome(3, "stale-comment:upheld:inferred")
        self.record(4, "inconclusive"); self.outcome(4)
        self.record(5, "dissent"); self.outcome(5, "naming:dismissed")
        self.outcome(6)
        self.record(7, "unanimous-pass"); self.outcome(7, "test-gap:unknown")

    def data(self, mode="batched"):
        return rs.report_data(self.home, self.crit, self.cats, mode=mode)

    def test_figures(self):
        self.build()
        p = self.data()["populations"]["out-of-sample"]
        g = p["groups"]["pre-merge|code"]
        self.assertEqual(g["n"], 5)
        self.assertAlmostEqual(g["agreement"], 0.4)
        self.assertEqual((g["unanimous_passes"], g["false_passes"]), (2, 1))
        self.assertAlmostEqual(g["false_pass_rate"], 0.5)
        self.assertAlmostEqual(g["false_pass_upper95"], rs.binom_upper(1, 2))
        self.assertEqual(g["blocked"], 2)
        self.assertAlmostEqual(g["miss_rate"], 0.5)
        self.assertEqual((g["fail_on_clean"], g["no_verdict_on_clean"], g["clean"]), (1, 1, 3))
        self.assertEqual((g["no_verdict"], g["zero_slice_passes"]), (1, 0))
        self.assertEqual(p["not_graded"]["pre-merge|unknown"], 1)
        self.assertEqual(p["undetermined"]["pre-merge|code"], 1)
        self.assertEqual(p["coverage"]["pre-merge|code"], {"covered": 1, "closed-uncovered": 0, "open-judgment": 1})
        self.assertEqual([(f["pr"], f["upheld"]) for f in p["false_passes"]], [(2, ["correctness"])])
        c = p["criteria"]["pre-merge|code|rs-010"]
        self.assertEqual((c["false_passes"], c["blocked"]), (0, 1))

    def test_bounds(self):
        self.assertAlmostEqual(rs.binom_upper(1, 5), 0.6574, places=4)
        self.assertAlmostEqual(rs.binom_upper(0, 10), 0.2589, places=4)
        self.assertIsNone(rs.binom_upper(0, 0))

    def test_zero_blocked_is_not_applicable(self):
        self.record(1, "unanimous-pass"); self.outcome(1)
        g = self.data()["populations"]["out-of-sample"]["groups"]["pre-merge|code"]
        self.assertIsNone(g["miss_rate"])
        self.assertEqual(self.data()["populations"]["out-of-sample"]["coverage"], {})

    def test_in_sample_never_moves_out_of_sample(self):
        self.build()
        before = self.data()["populations"]["out-of-sample"]
        self.record(1, "dissent", in_sample=True)
        self.record(3, "unanimous-pass", in_sample=True)
        after = self.data()
        self.assertEqual(after["populations"]["out-of-sample"], before)
        ins = after["populations"]["in-sample"]["groups"]["pre-merge|code"]
        self.assertEqual((ins["n"], ins["false_passes"]), (2, 1))

    def test_dismissed_counts_nowhere_and_inferred_is_kept(self):
        self.build()
        outcome = json.loads(rs.outcome_path(self.home, "octo/demo", 3, self.head(3), "claude:run-3").read_text())
        self.assertEqual(outcome["findings"][0]["disposition_source"], "inferred")
        cov = self.data()["populations"]["out-of-sample"]["coverage"]["all|all"]
        self.assertEqual(sum(cov.values()), 2)  # the dismissed naming finding isn't there

    def test_outcome_without_grade_and_replacement(self):
        self.outcome(9, "correctness:upheld")
        recs = list((self.home / "records").rglob("*.json"))
        self.assertEqual(len(recs), 1)
        rec = json.loads(recs[0].read_text())
        self.assertEqual((rec["status"], rec["not_graded_reason"]), ("not-graded", "outcome-without-grade"))
        self.outcome(9)  # the fix round dismissed it: the same panel run is replaced
        outs = list((self.home / "outcomes").rglob("*.json"))
        self.assertEqual(len(outs), 1)
        self.assertEqual(json.loads(outs[0].read_text())["result"], "clean")

    def test_outcome_first_then_grade_is_one_in_sample_head(self):
        self.outcome(1, "correctness:upheld")
        self.record(1, "unanimous-pass", in_sample=True)
        pops = self.data()["populations"]
        self.assertEqual(pops["out-of-sample"]["not_graded"], {})
        self.assertEqual(pops["out-of-sample"]["coverage"], {})
        self.assertEqual(pops["in-sample"]["groups"]["pre-merge|code"]["false_passes"], 1)
        self.assertIn("all|all|rs-010", pops["in-sample"]["criteria"])

    def test_panel_run_id_is_filled_in(self):
        self.record(1, "unanimous-pass")
        self.outcome(1)
        rec = json.loads(next((self.home / "records").rglob("*.json")).read_text())
        self.assertEqual((rec["panel_run_id"], rec["panel_kind"]), ("claude:run-1", "pre-merge"))

    def test_split_by_diff_kind_and_mode(self):
        self.record(1, "unanimous-pass", diff_kind="docs"); self.outcome(1)
        self.record(2, "dissent", diff_kind="code"); self.outcome(2, "correctness:upheld")
        self.record(2, "unanimous-pass", diff_kind="code", mode="unbatched")
        groups = self.data()["populations"]["out-of-sample"]["groups"]
        self.assertEqual(groups["pre-merge|docs"]["n"], 1)
        self.assertEqual(groups["pre-merge|code"]["false_passes"], 0)
        self.assertEqual(self.data("unbatched")["populations"]["out-of-sample"]["groups"]["pre-merge|code"]
                         ["false_passes"], 1)

    def test_finding_parsing(self):
        f = rs.parse_finding("stale-comment:narrowed:inferred:r2-a", self.cats)
        self.assertEqual(f, {"category": "stale-comment", "disposition": "narrowed",
                             "disposition_source": "inferred", "code": "r2-a"})
        for bad in ("nope:upheld", "stale-comment:maybe", "stale-comment:upheld:Free Text Here",
                    "stale-comment:upheld:" + "a" * 33):
            with self.assertRaises(ValueError):
                rs.parse_finding(bad, self.cats)

    def test_overall_rows_split_by_diff_kind(self):
        self.record(1, "unanimous-pass", diff_kind="docs"); self.outcome(1)
        self.record(2, "dissent"); self.outcome(2, "correctness:upheld")
        groups = self.data()["populations"]["out-of-sample"]["groups"]
        self.assertEqual((groups["all|docs"]["n"], groups["all|code"]["n"], groups["all|all"]["n"]), (1, 1, 2))

    def test_report_command_json(self):
        self.build()
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = rs.main(["report", "--json"])
        self.assertEqual(code, 0)
        data = json.loads(out.getvalue())
        self.assertEqual(data["populations"]["out-of-sample"]["groups"]["pre-merge|code"]["n"], 5)
        self.assertEqual(data["tokens"]["records"], 7)

    def test_printed_report(self):
        self.build()
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rs.print_report(self.data())
        text = out.getvalue()
        self.assertIn("## out-of-sample (the test)", text)
        self.assertIn("| pre-merge | code | 5 | 40% | 2 | 1 | 50% |", text)
        self.assertIn("Nothing here approves a panel", text)


class TestFailClosed(unittest.TestCase):
    """Nothing reports a pass without checking."""

    def test_rs005_unreadable_text_is_unanswered(self):
        pt = pr_text(texts={"docs/a.md": None})
        self.assertEqual(rs.check_pasted_paragraph(pt, None)[0:3:2], ("unanswered", "file-unreadable"))

    def test_zero_slice_pass_is_counted(self):
        rows = [("pass", False, True), ("pass", False, False), ("none", True, False)]
        g = rs.rates(rows)
        self.assertEqual((g["zero_slice_passes"], g["no_verdict"], g["unanimous_passes"]), (1, 1, 2))
        self.assertAlmostEqual(g["agreement"], 1.0)  # no verdict on a blocked panel agrees, as a fail

    def test_rs006_resolves_relative_and_skips_outside_paths(self):
        tree = {"skills", "skills/x", "skills/x/references", "skills/x/references/t.md", "skills/x/SKILL.md",
                "references", "references/fixes", "references/fixes/f.md", "docs"}
        pt = pr_text(added=[("skills/x/SKILL.md", 1, "See `references/t.md` and `fixes/f.md`."),
                            ("docs/a.md", 2, "Writes `.niwa/instance.json` and `coord/report.json`."),
                            ("docs/a.md", 3, "Local `x/y.local.md`.")], tree=tree)
        self.assertEqual(rs.check_dangling_path(pt, None)[0], "pass")
        pt = pr_text(added=[("docs/a.md", 1, "See `references/missing.md`.")], tree=tree)
        self.assertEqual(rs.check_dangling_path(pt, None)[0], "fail")


class TestShippedOff(unittest.TestCase):
    def test_rs009_and_rs010_are_off_by_default(self):
        crit = rs.load_criteria()
        self.assertEqual({c["rule_id"] for c in crit["criteria"] if not c.get("enabled", True)},
                         {"rs-009", "rs-010"})
        self.assertNotIn("rs-010", [c["rule_id"] for c in rs.active(crit)])
        on = dict(crit, _enabled=["rs-010"])
        self.assertIn("rs-010", [c["rule_id"] for c in rs.active(on)])

    def test_a_run_grades_only_active_criteria(self):
        b = rs.grade(rs.load_criteria(), fetched(), ["Zorblax"], stub_send())
        self.assertNotIn("rs-010", [c["rule_id"] for c in b["criteria"]])
        self.assertFalse(any(r["rule_ids"] == ["rs-010"] for r in b["rounds"]))

    def test_coverage_counts_a_category_whose_criteria_didnt_run_as_uncovered(self):
        home = Path(tempfile.mkdtemp()) / "store"
        os.environ["REVIEW_SHADOW_HOME"] = str(home)
        self.addCleanup(os.environ.pop, "REVIEW_SHADOW_HOME", None)
        crit = rs.load_criteria()
        cats = rs.load_categories(crit)
        rows = [{"rule_id": r, "verdict": "pass", "slices": 1} for r in ("rs-001", "rs-007")]
        rec = rs.new_record("octo/demo", 1, HEAD, in_sample=False, mode="batched", status="dissent",
                            diff_kind="code", criteria=rows, tokens={"input": 0, "output": 0})
        rs.write_record(home, rec)
        rs.record_outcome(home, "octo/demo", 1, HEAD, "pre-merge", "claude:r",
                          [rs.parse_finding("stale-comment:upheld", cats)])
        cov = rs.report_data(home, crit, cats)["populations"]["out-of-sample"]["coverage"]["all|all"]
        self.assertEqual(cov, {"covered": 0, "closed-uncovered": 1, "open-judgment": 0})


class TestToolVersion(unittest.TestCase):
    def test_every_record_carries_the_tool(self):
        rec = rs.new_record("octo/demo", 1, HEAD)
        tool = rec["tool"]
        self.assertEqual(tool["version"], rs.TOOL_VERSION)
        for k in ("script_sha256", "categories_sha256", "wording_sha256"):
            self.assertRegex(tool[k], r"^[0-9a-f]{64}$")
        self.assertIn("git_sha", tool)


class TestNoLiveTransport(unittest.TestCase):
    """The suite must never reach Jev: with a key in the environment, grade still
    goes through a stub, and a real transport can't be opened during the tests."""

    def test_opening_a_real_transport_fails_the_suite(self):
        with self.assertRaises(AssertionError):
            rs.urllib.request.build_opener()

    def test_cmd_grade_end_to_end_through_stubs(self):
        home = Path(tempfile.mkdtemp()) / "store"
        os.environ.update({"REVIEW_SHADOW_HOME": str(home), "JEV_API_KEY": "test-key"})
        self.addCleanup(os.environ.pop, "REVIEW_SHADOW_HOME", None)
        self.addCleanup(os.environ.pop, "JEV_API_KEY", None)
        sent = []
        real_t, real_f = rs.https_transport, rs.GhFetcher
        rs.https_transport = lambda endpoint, key, timeout: stub_send(log=sent)
        rs.GhFetcher = lambda: StubFetcher(fixture())
        self.addCleanup(setattr, rs, "https_transport", real_t)
        self.addCleanup(setattr, rs, "GhFetcher", real_f)
        terms = Path(tempfile.mkdtemp()) / "terms.txt"
        terms.write_text("Zorblax\n", encoding="utf-8")
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = rs.main(["grade", "--repo", "octo/demo", "--pr", "7", "--head", HEAD, "--panel-kind",
                            "pre-merge", "--panel-run", "claude:t", "--private-terms", str(terms)])
        self.assertEqual(code, 0)
        self.assertTrue(sent)
        self.assertIn("status=unanimous-pass in_sample=false", out.getvalue())
        rec = json.loads(next((home / "records").rglob("*.json")).read_text())
        self.assertEqual((rec["panel_kind"], rec["panel_run_id"]), ("pre-merge", "claude:t"))
        self.assertNotIn("rs-010", rec["criteria_enabled"])

    def test_cmd_grade_refuses_an_unknown_enable_and_a_bad_body_at(self):
        import contextlib
        import io
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(rs.main(["grade", "--repo", "o/r", "--pr", "1", "--head", HEAD,
                                      "--enable", "rs-999"]), 2)
            self.assertEqual(rs.main(["grade", "--repo", "o/r", "--pr", "1", "--head", HEAD,
                                      "--body-at", "yesterday"]), 2)
        self.assertIn("--enable", err.getvalue())
        self.assertIn("--body-at", err.getvalue())


class TestGhHints(unittest.TestCase):
    def test_fixed_hints_never_echo_stderr(self):
        cases = [("repos/o/r/pulls/1", "To get started with GitHub CLI, please run:  gh auth login", "logged in"),
                 ("repos/o/r/pulls/1", "HTTP 404: Not Found (https://api.github.com/...)", "--repo and --pr"),
                 ("repos/o/r/compare/b...h", "HTTP 404: Not Found", "--head"),
                 ("repos/o/r/pulls/1", "API rate limit exceeded", "rate limit")]
        for endpoint, stderr, want in cases:
            hint = rs.gh_hint(endpoint, stderr)
            self.assertIn(want, hint)
            self.assertNotIn("api.github.com", hint)


def site_criterion(rule_id="rs-900", artifact_kind="prd", slice_kind="prd-ac"):
    """A Jev criterion for a site artifact, for tests that need one before any ships."""
    return {"rule_id": rule_id, "rule_ref": "CLAUDE.md", "group": "correctness", "artifact_kind": artifact_kind,
            "slice_kind": slice_kind, "observer": "jev", "question": "Is this criterion binary?",
            "values": {"pass": "It is.", "fail": "It isn't."}, "escape": {"unclear": "Can't tell."},
            "threshold": 0.9}


class TestSiteKinds(unittest.TestCase):
    """Site artifact kinds, the artifact-kind filter, and v2 site records."""

    def setUp(self):
        self.good = json.loads((HERE / "criteria.json").read_text(encoding="utf-8"))
        self.tmp = tempfile.mkdtemp()
        self.home = Path(tempfile.mkdtemp()) / "store"
        os.environ["REVIEW_SHADOW_HOME"] = str(self.home)
        self.addCleanup(os.environ.pop, "REVIEW_SHADOW_HOME", None)

    def with_site(self, *extra):
        data = copy.deepcopy(self.good)
        data["criteria"] += list(extra)
        crit = rs.load_criteria(_write(self.tmp, "c.json", data))
        return crit

    def test_every_site_kind_has_its_slicers(self):
        for kind in ("brief", "prd", "plan", "local-change"):
            self.assertIn(kind, rs.ARTIFACT_KINDS)
        self.assertEqual(rs.SLICE_KINDS_BY_ARTIFACT["brief"], ("brief-journey", "summary-pair"))
        self.assertEqual(rs.SLICE_KINDS_BY_ARTIFACT["prd"], ("prd-ac",))
        self.assertEqual(rs.SLICE_KINDS_BY_ARTIFACT["plan"], ("plan-ac-block",))
        self.assertEqual(rs.SLICE_KINDS_BY_ARTIFACT["local-change"], ("ac-hunks", "code-hunks"))
        for kind in ("brief-journey", "summary-pair", "prd-ac", "plan-ac-block", "ac-hunks"):
            self.assertIn(kind, rs.SLICE_KINDS)

    def test_a_slice_kind_from_another_artifact_is_refused(self):
        cases = [("prd", "brief-journey"), ("brief", "prd-ac"), ("plan", "code-hunks"),
                 ("local-change", "pr-summary"), ("pull-request", "ac-hunks")]
        for artifact, slice_kind in cases:
            with self.subTest(artifact=artifact, slice_kind=slice_kind):
                data = copy.deepcopy(self.good)
                data["criteria"].append(site_criterion(artifact_kind=artifact, slice_kind=slice_kind))
                with self.assertRaises(rs.ConfigError) as cm:
                    rs.load_criteria(_write(self.tmp, "c.json", data))
                self.assertIn("doesn't read", str(cm.exception))

    def test_a_script_criterion_on_a_site_artifact_is_refused(self):
        bad = dict(site_criterion(), observer="script", check="attribution")
        data = copy.deepcopy(self.good)
        data["criteria"].append(bad)
        with self.assertRaises(rs.ConfigError):
            rs.load_criteria(_write(self.tmp, "c.json", data))

    def test_active_selects_one_artifact_kind(self):
        crit = self.with_site(site_criterion())
        self.assertEqual([c["rule_id"] for c in rs.active(crit, "prd")], ["rs-013", "rs-900"])
        self.assertNotIn("rs-900", [c["rule_id"] for c in rs.active(crit)])
        self.assertEqual([c["rule_id"] for c in rs.active(crit, "brief")], ["rs-011", "rs-012"])

    def test_a_site_criterion_never_runs_on_a_pull_request(self):
        crit = self.with_site(site_criterion(), site_criterion("rs-901", "local-change", "code-hunks"))
        log = []
        body = rs.grade(crit, fetched(), ("Zorblax",), stub_send(log=log))
        asked = {rid for _, rids in log for rid in rids}
        self.assertTrue(asked)
        self.assertFalse(asked & {"rs-900", "rs-901"})
        graded = {v["rule_id"] for v in body["verdicts"]} | {c["rule_id"] for c in body["criteria"]}
        self.assertFalse(graded & {"rs-900", "rs-901"})

    def test_no_pull_request_criterion_runs_for_a_site_kind(self):
        crit = self.with_site(site_criterion())
        log = []
        slices = {"prd-ac": [rs.make_slice("prd-ac", 1, {"criterion": "- [ ] It exits 0."})],
                  "pr-summary": [rs.make_slice("pr-summary", 1, {"pr_body_part1": "x", "diff_summary": "y"})]}
        verdicts, _, _ = rs.run_jev(crit, slices, stub_send(log=log), True, "prd")
        self.assertEqual({v["rule_id"] for v in verdicts}, {"rs-013", "rs-900"})
        self.assertEqual(log, [("jev", ["rs-013", "rs-900"])])

    def test_site_record_path_schema_and_modes(self):
        home = rs.store_home()
        sha = "b" * 64
        rec = rs.new_site_record("octo/demo", "prd", "jev-closed-criteria", sha, status="not-graded")
        self.assertEqual(rec["schema"], "review-shadow/record/v2")
        self.assertEqual(rec["subject"], {"kind": "site", "site": "prd", "subject_id": "jev-closed-criteria",
                                          "artifact_sha": sha})
        self.assertEqual(rec["seats"], [])
        path = rs.write_site_record(home, rec)
        rel = path.relative_to(home)
        self.assertEqual(rel.parts[:7], ("records", "octo", "demo", "site", "prd", "jev-closed-criteria", "b" * 12))
        self.assertTrue(rel.parts[7].endswith(f"-{rec['run_id']}.json"))
        self.assertEqual(oct(path.stat().st_mode & 0o777), "0o600")
        d = path.parent
        while d != home.parent:
            self.assertEqual(oct(d.stat().st_mode & 0o777), "0o700", d)
            d = d.parent
        self.assertEqual(json.loads(path.read_text())["subject"]["site"], "prd")

    def test_site_record_identity_is_checked(self):
        for args in [("octo/demo", "qa", "t", "b" * 64), ("octo/demo", "prd", "../x", "b" * 64),
                     ("octo/demo", "prd", "t", "abc"), ("../demo", "prd", "t", "b" * 64)]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                rs.new_site_record(*args)

    def test_pull_request_report_ignores_site_records(self):
        crit = rs.load_criteria()
        cats = rs.load_categories(crit)
        rec = rs.new_record("octo/demo", 1, HEAD, mode="batched", status="unanimous-pass", diff_kind="code",
                            criteria=[{"rule_id": "rs-007", "verdict": "pass", "slices": 1}],
                            tokens={"input": 10, "output": 1})
        rs.write_record(self.home, rec)
        rs.record_outcome(self.home, "octo/demo", 1, HEAD, "pre-merge", "claude:run-1", [])

        def rendered():
            import contextlib
            import io
            data = rs.report_data(self.home, crit, cats)
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rs.print_report(data)
            data.pop("sites", None)  # the site tables come after the pull-request ones
            return json.dumps(data, sort_keys=True), out.getvalue().split("\n# Review sites")[0]
        before = rendered()
        site = rs.new_site_record("octo/demo", "prd", "topic", "c" * 64, status="dissent",
                                  tokens={"input": 500, "output": 50}, mode="batched")
        rs.write_site_record(self.home, site)
        self.assertEqual(rendered(), before)

    def test_an_empty_store_prints_zero_site_counts(self):
        import contextlib
        import io
        crit = rs.load_criteria()
        data = rs.report_data(self.home, crit, rs.load_categories(crit))
        self.assertEqual(data["sites"]["out-of-sample"],
                         {"seats": {}, "criteria": {}, "not_graded": {}, "seat_unreadable": {}})
        self.assertEqual(data["sites"]["tokens"], {"input": 0, "output": 0, "records": 0})
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rs.print_report(data)
        self.assertIn("No site runs.", out.getvalue())
        self.assertIn("Site Jev spend: 0 input and 0 output tokens over 0 records.", out.getvalue())


SITE_FIXTURES = HERE / "fixtures" / "sites"
SCRATCH = "wip"  # built, so this file names no path inside the scratch directory


def git(repo, *args):
    import subprocess
    out = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise AssertionError(f"git {args} failed: {out.stderr}")
    return out.stdout.strip()


def site_repo(files):
    """A throwaway git repository (outside this one) holding `files` {path: text}, committed."""
    root = Path(os.path.realpath(tempfile.mkdtemp()))
    git(root, "init", "-q")
    git(root, "config", "user.email", "t@example.com")
    git(root, "config", "user.name", "t")
    for rel, text in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "base", "--allow-empty")
    return root


def site_args(site, root, **kw):
    import argparse
    base = {"site": site, "topic": None, "session": None, "panel": None, "head": None, "issue": None,
            "repo_path": str(root), "measure": True, "in_sample": False}
    base.update(kw)
    return argparse.Namespace(**base)


def plan_files(topic="demo"):
    manifest = {"issues": [
        {"issue_id": "1", "title": "feat(drafts): list open drafts", "file": f"{SCRATCH}/plan_{topic}_issue_1_body.md"},
        {"issue_id": "2", "title": "feat(drafts): mark read drafts", "file": f"{SCRATCH}/plan_{topic}_issue_2_body.md"},
        {"issue_id": "3", "title": "outside the plan's outlines", "file": "docs/elsewhere.md"}]}
    return {f"{SCRATCH}/plan_{topic}_manifest.json": json.dumps(manifest),
            f"{SCRATCH}/plan_{topic}_issue_1_body.md": (SITE_FIXTURES / "plan_demo_issue_1_body.md").read_text(),
            f"{SCRATCH}/plan_{topic}_issue_2_body.md": (SITE_FIXTURES / "plan_demo_issue_2_body.md").read_text(),
            "docs/elsewhere.md": "## Acceptance Criteria\n\n- [ ] never read\n"}


class TestSiteInputs(unittest.TestCase):
    """The site command's arguments, assemblers, slicers and measure mode."""

    def slices(self, site, files, **kw):
        root = site_repo(files)
        art = rs.assemble_site(site_args(site, root, **kw))
        return art, rs.build_site_slices(art)

    def test_brief_units(self):
        art, (slices, unmatched) = self.slices(
            "brief", {"docs/briefs/BRIEF-demo.md": (SITE_FIXTURES / "BRIEF-demo.md").read_text()}, topic="demo")
        journeys = slices["brief-journey"]
        self.assertEqual([s["id"] for s in journeys], ["brief-journey-1", "brief-journey-2"])
        self.assertTrue(journeys[0]["inputs"]["journey"].startswith("### The author checks the list"))
        self.assertEqual([s["bytes"] for s in journeys], [151, 109])
        pairs = slices["summary-pair"]
        self.assertEqual(len(pairs), 2)
        self.assertEqual(pairs[0]["inputs"]["summary"], "Authors lose track of which drafts a reviewer has already read.")
        self.assertIn("They end up asking in chat.", pairs[0]["inputs"]["section"])
        self.assertEqual([s["bytes"] for s in pairs], [179, 127])
        self.assertEqual(unmatched, [])
        self.assertEqual(art["subject_id"], "demo")

    def test_prd_units_carry_their_group(self):
        _, (slices, _) = self.slices(
            "prd", {"docs/prds/PRD-demo.md": (SITE_FIXTURES / "PRD-demo.md").read_text()}, topic="demo")
        acs = slices["prd-ac"]
        self.assertEqual(len(acs), 3)
        self.assertEqual(acs[0]["inputs"]["group"], "Listing (R1, R2):")
        self.assertIn("and one nobody opened shows `unread`.", acs[1]["inputs"]["criterion"])
        self.assertEqual(acs[2]["inputs"]["group"], "Errors (R3):")
        self.assertEqual([s["bytes"] for s in acs], [68, 118, 75])

    def test_plan_units_read_only_the_plan_outlines(self):
        art, (slices, _) = self.slices("review-plan", plan_files(), topic="demo")
        blocks = slices["plan-ac-block"]
        self.assertEqual([s["inputs"]["issue"] for s in blocks],
                         ["feat(drafts): list open drafts", "feat(drafts): mark read drafts"])
        self.assertNotIn("docs/elsewhere.md", art["read_files"])
        self.assertEqual(blocks[0]["inputs"]["criteria"].count("- [ ]"), 2)
        self.assertEqual([s["bytes"] for s in blocks], [129, 93])

    def test_bound_keeps_whole_sub_units(self):
        exact = rs.pack_unit("prd-ac", 1, {}, "criterion", "", ["x" * rs.BOUND])
        self.assertFalse(exact["over_bound"])
        self.assertEqual(exact["bytes"], 2560)
        one_over = rs.pack_unit("prd-ac", 1, {}, "criterion", "", ["x" * (rs.BOUND + 1)])
        self.assertTrue(one_over["over_bound"])
        self.assertEqual(one_over["inputs"]["criterion"], "x" * (rs.BOUND + 1))  # never truncated
        parts = ["a" * 1000, "b" * 1000, "c" * 1000]  # 3,004 bytes with joiners: over by whole parts
        cut = rs.pack_unit("brief-journey", 1, {}, "journey", "### J", parts)
        self.assertFalse(cut["over_bound"])
        self.assertEqual(cut["meta"]["dropped"], 1)
        self.assertNotIn("c" * 1000, cut["inputs"]["journey"])
        multibyte = rs.pack_unit("prd-ac", 1, {}, "criterion", "", ["é" * 1280])  # 2,560 bytes, 1,280 chars
        self.assertFalse(multibyte["over_bound"])

    def test_a_large_part_does_not_cost_the_parts_after_it(self):
        parts = ["a" * 300, "b" * 3000, "c" * 300]
        s = rs.pack_unit("ac-hunks", 1, {"criterion": "- [ ] x"}, "hunks", "", parts, "\n")
        self.assertFalse(s["over_bound"])
        self.assertEqual(s["meta"]["dropped"], 1)
        self.assertIn("c" * 300, s["inputs"]["hunks"])
        none_fit = rs.pack_unit("ac-hunks", 1, {}, "hunks", "", ["d" * 3000], "\n")
        self.assertTrue(none_fit["over_bound"])

    def test_ac_hunks_slices_fit_beside_a_long_criterion(self):
        criterion = "## Acceptance Criteria\n\n- [ ] `scripts/a.sh` " + "explains the long behaviour " * 30 + "\n"
        body = "#!/bin/sh\n" + "".join(f"# step {i}\necho {i}\n\n" for i in range(400))
        _, (slices, _) = self.work_on(criterion, {"scripts/a.sh": body})
        self.assertTrue(slices["ac-hunks"])
        self.assertTrue(all(not s["over_bound"] for s in slices["ac-hunks"]))

    def test_anchor_terms(self):
        terms = rs.anchor_terms("- [ ] `drafts list` reads scripts/a.sh, takes --dry-run and edits config.toml.")
        self.assertTrue({"drafts list", "scripts/a.sh", "--dry-run", "config.toml"} <= terms)
        self.assertEqual(rs.anchor_terms("- [ ] It works well."), set())

    def work_on(self, criteria, change, **kw):
        root = site_repo({"scripts/a.sh": "#!/bin/sh\necho one\n", "README.md": "demo\n"})
        base = git(root, "rev-parse", "HEAD")
        for rel, text in change.items():
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text, encoding="utf-8")
        git(root, "add", "-A")
        git(root, "commit", "-q", "-m", "change")
        ctx = {"impl_base": base + "\n", "context.md": criteria}
        real = rs.koto_context
        rs.koto_context = lambda session, key: ctx.get(key)
        self.addCleanup(setattr, rs, "koto_context", real)
        art = rs.assemble_site(site_args("work-on", root, session="wf.child", panel="scrutiny", **kw))
        return art, rs.build_site_slices(art)

    def test_ac_hunks_match_anchor_terms(self):
        criteria = "## Acceptance Criteria\n\n- [ ] `scripts/a.sh` prints two.\n- [ ] It is fast.\n"
        art, (slices, unmatched) = self.work_on(criteria, {"scripts/a.sh": "#!/bin/sh\necho two\n",
                                                            "notes.txt": "unrelated\n"})
        acs = slices["ac-hunks"]
        self.assertEqual(len(acs), 1)
        self.assertIn("--- scripts/a.sh", acs[0]["inputs"]["hunks"])
        self.assertNotIn("notes.txt", acs[0]["inputs"]["hunks"])
        self.assertEqual(unmatched, [{"unit": "ac-hunks-2", "reason": "no-anchor"}])
        self.assertEqual(art["subject_id"], "wf-child")

    def test_secret_paths_are_never_read(self):
        criteria = "- [ ] `.env` and `scripts/a.sh` change.\n"
        art, (slices, _) = self.work_on(criteria, {".env": "TOKEN=x\n", "keys/id_rsa": "k\n",
                                                   "scripts/a.sh": "#!/bin/sh\necho two\n"})
        self.assertEqual([f["path"] for f in art["files"]], ["scripts/a.sh"])
        self.assertNotIn("TOKEN", json.dumps(slices))

    def test_every_site_diff_disables_diff_drivers(self):
        import subprocess
        seen = []
        real = rs.subprocess.run

        def spy(cmd, **kw):
            if cmd[:1] == ["git"] and "diff" in cmd:
                seen.append(cmd)
            return real(cmd, **kw)
        rs.subprocess.run = spy
        self.addCleanup(setattr, rs.subprocess, "run", real)
        self.work_on("- [ ] `scripts/a.sh` prints two.\n", {"scripts/a.sh": "#!/bin/sh\necho two\n"})
        self.assertTrue(seen)
        for cmd in seen:
            self.assertIn("--no-ext-diff", cmd)
            self.assertIn("--no-textconv", cmd)

    def test_arguments_are_refused(self):
        root = site_repo({"docs/prds/PRD-demo.md": "x"})
        cases = [dict(site="prd", topic="-demo"), dict(site="prd", topic="Demo"), dict(site="prd", topic="a/b"),
                 dict(site="prd", topic=None),
                 dict(site="work-on", session="-x", panel="scrutiny"),
                 dict(site="work-on", session="wf", panel="qa"),
                 dict(site="work-on", session="wf", panel="review", head="HEAD"),
                 dict(site="work-on", session="wf", panel="review", issue="12a")]
        for kw in cases:
            with self.subTest(kw=kw), self.assertRaises(ValueError):
                rs.assemble_site(site_args(kw.pop("site"), root, **kw))
        with self.assertRaises(ValueError):
            rs.assemble_site(site_args("prd", root / "docs", topic="demo"))  # not the work-tree top

    def test_paths_outside_the_repository_are_refused(self):
        root = site_repo({"docs/x.md": "x"})
        outside = Path(tempfile.mkdtemp()) / "secret.md"
        outside.write_text("secret")
        (root / "docs" / "link.md").symlink_to(outside)
        files = rs.SiteFiles(root)
        for rel in ("../x.md", "/etc/hosts", "docs/link.md"):
            with self.subTest(rel=rel), self.assertRaises(ValueError):
                files.read(rel)
        self.assertEqual(files.read("docs/x.md"), "x")

    def test_measure_prints_sizes_and_sends_and_writes_nothing(self):
        import contextlib
        import io
        home = Path(tempfile.mkdtemp()) / "store"
        os.environ["REVIEW_SHADOW_HOME"] = str(home)
        self.addCleanup(os.environ.pop, "REVIEW_SHADOW_HOME", None)
        root = site_repo({"docs/prds/PRD-demo.md": (SITE_FIXTURES / "PRD-demo.md").read_text()})
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = rs.cmd_site(site_args("prd", root, topic="demo"), rs.load_criteria())
        self.assertEqual(rc, 0)
        lines = out.getvalue().splitlines()
        self.assertEqual(lines[:3], ["slice prd-ac-1 68", "slice prd-ac-2 118", "slice prd-ac-3 75"])
        self.assertRegex(lines[-1], r"^seat-packet ([0-9]+|unavailable \S+)$")
        self.assertFalse(home.exists())

    def test_measure_on_this_repository(self):
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = rs.main(["site", "prd", "--topic", "jev-closed-criteria", "--repo-path", str(rs.REPO_ROOT),
                          "--measure"])
        self.assertEqual(rc, 0)
        self.assertIn("slice prd-ac-1 ", out.getvalue())


PUBLIC_CLAUDE_MD = "# demo\n\n## Repo Visibility: Public\n"
SENTINEL = "SENTINELq7zx"


class TestSiteGrading(unittest.TestCase):
    """Seat-verdict readers, send gates, caps and the paired site record."""

    def setUp(self):
        self.home = Path(tempfile.mkdtemp()) / "store"
        self.env = {"REVIEW_SHADOW_HOME": str(self.home), "REVIEW_SHADOW_SITES": "1", "JEV_API_KEY": "k-test"}
        for k, v in self.env.items():
            os.environ[k] = v
            self.addCleanup(os.environ.pop, k, None)
        os.environ.pop("KOTO_DECIDER_API_KEY", None)
        os.environ.pop("REVIEW_SHADOW_PRIVATE_TERMS", None)
        self.log = []
        self.use_send(stub_send(log=self.log))
        self.crit = rs.load_criteria()

    def use_send(self, send):
        real = rs.https_transport
        rs.https_transport = lambda endpoint, key, timeout: send
        self.addCleanup(setattr, rs, "https_transport", real)

    def run_site(self, site, root, **kw):
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = rs.cmd_site(site_args(site, root, measure=False, **kw), self.crit)
        self.assertEqual(rc, 0)
        recs = sorted(self.home.rglob("*.json"), key=lambda p: p.stat().st_mtime_ns) if self.home.exists() else []
        return out.getvalue(), [json.loads(p.read_text()) for p in recs], recs

    def brief_repo(self, verdicts=None, brief=None, claude_md=PUBLIC_CLAUDE_MD):
        text = brief or (SITE_FIXTURES / "BRIEF-demo.md").read_text()
        files = {"docs/briefs/BRIEF-demo.md": text}
        if claude_md is not None:
            files["CLAUDE.md"] = claude_md
        root = site_repo(files)
        for seat, body in (verdicts or {}).items():
            p = root / SCRATCH / "research" / f"brief_demo_phase4_{seat}.md"
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(body)
        return root

    def test_one_record_pairs_seat_and_decider_verdicts(self):
        brief = (SITE_FIXTURES / "BRIEF-demo.md").read_text().replace("before standup", f"before {SENTINEL}")
        root = self.brief_repo({"content-quality": "# Review\n\n**Verdict:** PASS\n",
                                "structural-format": "# Review\n\n**Verdict:** FAIL\n"}, brief=brief)
        out, recs, paths = self.run_site("brief", root, topic="demo")
        self.assertEqual(len(recs), 1)
        rec = recs[0]
        self.assertEqual(rec["schema"], "review-shadow/record/v2")
        self.assertEqual({s["seat"]: s["verdict"] for s in rec["seats"]},
                         {"content-quality": "pass", "structural-format": "fail"})
        self.assertEqual({s["seat"]: s["rule_ids"] for s in rec["seats"]},
                         {"content-quality": ["rs-011"], "structural-format": ["rs-012"]})
        per_unit = {(v["rule_id"], v["slice"]): v["verdict"] for v in rec["verdicts"]}
        self.assertEqual(per_unit, {("rs-011", "brief-journey-1"): "pass", ("rs-011", "brief-journey-2"): "pass",
                                    ("rs-012", "summary-pair-1"): "pass", ("rs-012", "summary-pair-2"): "pass"})
        self.assertEqual({c["rule_id"]: c["verdict"] for c in rec["criteria"]}, {"rs-011": "pass", "rs-012": "pass"})
        self.assertEqual(rec["status"], "unanimous-pass")
        self.assertNotIn(SENTINEL, paths[0].read_text())
        self.assertIn("status=unanimous-pass", out)

    def test_seat_verdict_reasons(self):
        root = self.brief_repo({"structural-format": "# Review\n\nVerdict: looks fine\n"})
        _, recs, _ = self.run_site("brief", root, topic="demo")
        seats = {s["seat"]: (s["verdict"], s["reason"]) for s in recs[-1]["seats"]}
        self.assertEqual(seats["content-quality"], ("unreadable", "seat-verdict-missing"))
        self.assertEqual(seats["structural-format"], ("unreadable", "seat-verdict-unparsed"))
        old = self.brief_repo({"content-quality": "**Verdict:** PASS\n"})
        verdict = old / SCRATCH / "research" / "brief_demo_phase4_content-quality.md"
        doc = old / "docs" / "briefs" / "BRIEF-demo.md"
        os.utime(verdict, (doc.stat().st_mtime - 60, doc.stat().st_mtime - 60))
        _, recs, _ = self.run_site("brief", old, topic="demo")
        seats = {s["seat"]: (s["verdict"], s["reason"]) for s in recs[-1]["seats"]}
        self.assertEqual(seats["content-quality"], ("unreadable", "seat-verdict-stale"))

    def test_prd_reader_reads_the_heading_marker(self):
        root = site_repo({"docs/prds/PRD-demo.md": (SITE_FIXTURES / "PRD-demo.md").read_text(),
                          "CLAUDE.md": PUBLIC_CLAUDE_MD})
        for seat, v in (("clarity", "PASS"), ("testability", "FAIL")):
            p = root / SCRATCH / "research" / f"prd_demo_phase4_{seat}.md"
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(f"# Review\n\n## Verdict: {v}\nOne line.\n")
        _, recs, _ = self.run_site("prd", root, topic="demo")
        self.assertEqual({s["seat"]: s["verdict"] for s in recs[0]["seats"]}, {"clarity": "pass", "testability": "fail"})
        self.assertEqual(len([v for v in recs[0]["verdicts"] if v["rule_id"] == "rs-013"]), 3)

    def plan_repo(self, review_name, review_text):
        files = plan_files()
        files["CLAUDE.md"] = PUBLIC_CLAUDE_MD
        files[f"{SCRATCH}/{review_name}"] = review_text
        return site_repo(files)

    def test_review_plan_reader_attributes_category_c(self):
        review = ("---\nreview_result:\n  verdict: \"loop-back\"\n  loop_target: 4\n  critical_findings:\n"
                  "    - category: \"C\"\n      description: x\n      affected_issue_ids: [2]\n"
                  "    - category: \"A\"\n      description: y\n      affected_issue_ids: [1]\n---\n")
        root = self.plan_repo("plan_demo_review_loopback.md", review)
        _, recs, _ = self.run_site("review-plan", root, topic="demo")
        seat = recs[0]["seats"][0]
        self.assertEqual((seat["seat"], seat["verdict"], seat["blocking_findings"]), ("category-c", "fail", 1))
        self.assertEqual(seat["attributed"], {"plan-ac-block-1": False, "plan-ac-block-2": True})
        clean = self.plan_repo("plan_demo_review.md", "review_result:\n  verdict: proceed\n  critical_findings: []\n")
        _, recs, _ = self.run_site("review-plan", clean, topic="demo")
        self.assertEqual(recs[-1]["seats"][0]["verdict"], "pass")

    def work_on_repo(self, ledger_for, decisions=("full",), panel="scrutiny", seat="completeness",
                     criteria="## Acceptance Criteria\n\n- [ ] `scripts/a.sh` prints two.\n- [ ] It is fast.\n"):
        root = site_repo({"scripts/a.sh": "#!/bin/sh\n# says one\necho one\n", "CLAUDE.md": PUBLIC_CLAUDE_MD})
        base = git(root, "rev-parse", "HEAD")
        (root / "scripts" / "a.sh").write_text("#!/bin/sh\n# says two\necho two\n")
        git(root, "commit", "-q", "-am", "change")
        head = git(root, "rev-parse", "HEAD")
        ctx = {"impl_base": base, "context.md": criteria, "plan.md": "plan\n"}
        ac_sha = rs.hashlib.sha1(b"blob %d\0" % len((criteria + "\n--- plan ---\nplan\n").encode())
                                 + (criteria + "\n--- plan ---\nplan\n").encode()).hexdigest()
        ctx["verdict_ledger.json"] = json.dumps({"rev": 1, "seats": {f"{panel}/{seat}": ledger_for(head, ac_sha)}})
        ctx[f"{panel}_scope.json"] = json.dumps({"decisions": [{"seat": seat, "decision": d} for d in decisions]})
        real = rs.koto_context
        rs.koto_context = lambda session, key: ctx.get(key)
        self.addCleanup(setattr, rs, "koto_context", real)
        return root, head

    def test_work_on_ledger_pairing_and_attribution(self):
        root, head = self.work_on_repo(lambda head, ac: {
            "verdict": "blocking", "judged_at": head, "ac_sha": ac,
            "findings": [{"summary": "wrong output", "path": "scripts/a.sh", "lines": "3"}]})
        _, recs, paths = self.run_site("work-on", root, session="wf.child", panel="scrutiny", head=head)
        rec = recs[0]
        seat = rec["seats"][0]
        self.assertEqual((seat["seat"], seat["verdict"], seat["rule_ids"]), ("completeness", "fail", ["rs-015"]))
        self.assertEqual(seat["attributed"], {"ac-hunks-1": True})
        self.assertNotIn("scripts/a.sh", json.dumps(seat))
        self.assertEqual({v["rule_id"] for v in rec["verdicts"]}, {"rs-015"})
        no_anchor = [v for v in rec["verdicts"] if v["slice"] == "ac-hunks-2"]
        self.assertEqual([(v["verdict"], v["reason"]) for v in no_anchor], [("unanswered", "no-anchor")])
        self.assertEqual(rec["criteria"], [{"rule_id": "rs-015", "verdict": "unanswered", "slices": 2}])
        self.assertEqual(rec["subject"]["site"], "work-on")
        self.assertEqual(rec["panel"], "scrutiny")

    def test_work_on_stale_and_kept_seats(self):
        root, head = self.work_on_repo(lambda head, ac: {"verdict": "passed", "judged_at": "0" * 40, "ac_sha": ac})
        _, recs, _ = self.run_site("work-on", root, session="wf.child", panel="scrutiny", head=head)
        self.assertEqual(recs[-1]["seats"][0]["reason"], "seat-verdict-stale")
        root, head = self.work_on_repo(lambda head, ac: {"verdict": "passed", "judged_at": head, "ac_sha": "f" * 40})
        _, recs, _ = self.run_site("work-on", root, session="wf.child", panel="scrutiny", head=head)
        self.assertEqual(recs[-1]["seats"][0]["reason"], "seat-verdict-stale")
        n = len(recs)
        for decision in ("keep", "recheck"):
            root, head = self.work_on_repo(lambda head, ac: {"verdict": "passed", "judged_at": head, "ac_sha": ac},
                                           decisions=(decision,))
            out, recs, _ = self.run_site("work-on", root, session="wf.child", panel="scrutiny", head=head)
            self.assertEqual(len(recs), n, decision)
            self.assertIn("nothing recorded", out)

    def test_gates_send_nothing_and_say_why(self):
        cases = [("private-repo", {}, None), ("not-opted-in", {"REVIEW_SHADOW_SITES": "0"}, PUBLIC_CLAUDE_MD),
                 ("no-key", {"JEV_API_KEY": ""}, PUBLIC_CLAUDE_MD)]
        for reason, env, claude_md in cases:
            with self.subTest(reason=reason):
                for k, v in self.env.items():
                    os.environ[k] = env.get(k, v)
                root = self.brief_repo({"content-quality": "**Verdict:** PASS\n"}, claude_md=claude_md)
                out, recs, _ = self.run_site("brief", root, topic="demo")
                rec = recs[-1]
                self.assertEqual((rec["status"], rec["not_graded_reason"]), ("not-graded", reason))
                self.assertTrue(all(v["reason"] == reason for v in rec["verdicts"]))
                self.assertIn(f"reason={reason}", out)
                self.assertEqual(rec["seats"][0]["verdict"], "pass")
        self.assertEqual(self.log, [])

    def test_an_unset_opt_in_says_so_where_the_verdict_would_go(self):
        os.environ["REVIEW_SHADOW_SITES"] = ""
        out, recs, _ = self.run_site("brief", self.brief_repo(), topic="demo")
        self.assertIn("reason=not-opted-in", out)
        self.assertIn("set REVIEW_SHADOW_SITES=1", out)
        self.assertEqual(recs[-1]["not_graded_reason"], "not-opted-in")

    def test_provider_errors_and_timeouts_exit_zero(self):
        for status, reason in ((500, "provider"), (None, "transport")):
            with self.subTest(reason=reason):
                self.use_send(lambda body, s=status: (s, b""))
                out, recs, _ = self.run_site("brief", self.brief_repo(), topic="demo")
                rec = recs[-1]
                self.assertEqual((rec["status"], rec["not_graded_reason"]), ("not-graded", reason))
                self.assertTrue(all(v["reason"] == reason for v in rec["verdicts"]))

    def test_rollup_is_the_worst_unit_and_keeps_over_bound(self):
        calls = []

        def send(body):
            calls.append(body)
            verdict = "fail" if len(calls) == 1 else "pass"
            return stub_send(verdict_for=lambda r: verdict)(body)
        self.use_send(send)
        long_journey = "### The long journey\n\n" + "word " * 700
        brief = (SITE_FIXTURES / "BRIEF-demo.md").read_text().replace("## Scope Boundary", long_journey + "\n\n## Scope Boundary")
        _, recs, _ = self.run_site("brief", self.brief_repo(brief=brief), topic="demo")
        rec = recs[-1]
        rows = {c["rule_id"]: c["verdict"] for c in rec["criteria"]}
        self.assertEqual(rows["rs-011"], "fail")
        over = [v for v in rec["verdicts"] if v["slice"] == "brief-journey-3"]
        self.assertEqual([(v["verdict"], v["reason"]) for v in over], [("unanswered", "over-bound")])

    def test_redaction_then_private_term_then_bound(self):
        terms = Path(tempfile.mkdtemp()) / "terms.txt"
        terms.write_text("Zorblax\n")
        os.environ["REVIEW_SHADOW_PRIVATE_TERMS"] = str(terms)
        self.addCleanup(os.environ.pop, "REVIEW_SHADOW_PRIVATE_TERMS", None)
        token = "ghp_" + "Zorblax" + "A" * 20  # a credential holding the term: redaction removes both
        over_with_term = "### Over the bound\n\nZorblax " + "word " * 700
        brief = ((SITE_FIXTURES / "BRIEF-demo.md").read_text()
                 .replace("before standup", f"before standup with {token}")
                 .replace("## Scope Boundary", over_with_term + "\n\n## Scope Boundary"))
        bodies = []
        self.use_send(lambda body: (bodies.append(body), stub_send()(body))[1])
        _, recs, _ = self.run_site("brief", self.brief_repo(brief=brief), topic="demo")
        by_slice = {v["slice"]: v for v in recs[-1]["verdicts"] if v["rule_id"] == "rs-011"}
        self.assertEqual(by_slice["brief-journey-1"]["verdict"], "pass")  # redacted, so no term left to find
        self.assertEqual(by_slice["brief-journey-3"]["reason"], "private-term")  # checked before the bound
        self.assertTrue(bodies)
        self.assertTrue(all("Zorblax" not in json.dumps(b["state"]) for b in bodies))

    def test_slice_and_time_caps(self):
        real_cap = rs.SITE_SLICE_CAP
        rs.SITE_SLICE_CAP = 1
        self.addCleanup(setattr, rs, "SITE_SLICE_CAP", real_cap)
        _, recs, _ = self.run_site("brief", self.brief_repo(), topic="demo")
        reasons = [v["reason"] for v in recs[-1]["verdicts"]]
        self.assertEqual(reasons.count("run-cap"), 3)
        rs.SITE_SLICE_CAP = real_cap
        ticks = iter([0.0, 100.0, 100.0, 100.0, 100.0, 100.0])
        art = rs.assemble_site(site_args("brief", self.brief_repo(), topic="demo"))
        slices, unmatched = rs.build_site_slices(art)
        body = rs.grade_site(self.crit, art, slices, unmatched, stub_send(), None, clock=lambda: next(ticks))
        self.assertEqual([v["reason"] for v in body["verdicts"]].count("run-cap"), 3)

    def test_a_large_prd_fits_one_run(self):
        # The cap is 32 because a PRD's unit is one acceptance criterion; at 16, a
        # 19-criterion PRD (this feature's own) would leave rs-013 without a verdict.
        items = "\n".join(f"- [ ] `cmd {i}` exits {i}." for i in range(1, 20))
        prd = f"---\nstatus: Draft\n---\n\n## Acceptance Criteria\n\n{items}\n"
        root = site_repo({"docs/prds/PRD-demo.md": prd, "CLAUDE.md": PUBLIC_CLAUDE_MD})
        for seat in ("clarity", "testability"):
            p = root / SCRATCH / "research" / f"prd_demo_phase4_{seat}.md"
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("## Verdict: PASS\n")
        _, recs, _ = self.run_site("prd", root, topic="demo")
        verdicts = recs[-1]["verdicts"]
        self.assertEqual(len(verdicts), 19)
        self.assertNotIn("run-cap", [v["reason"] for v in verdicts])
        self.assertEqual(recs[-1]["criteria"], [{"rule_id": "rs-013", "verdict": "pass", "slices": 19}])

    def test_issue_ids_never_reach_the_record(self):
        review = "review_result:\n  verdict: proceed\n  critical_findings: []\n"
        _, recs, paths = self.run_site("review-plan", self.plan_repo("plan_demo_review.md", review), topic="demo")
        self.assertNotIn("issue_id", paths[-1].read_text())

    def test_bad_arguments_still_exit_two(self):
        self.assertEqual(rs.main(["site", "brief", "--topic", "Bad", "--repo-path", str(self.brief_repo())]), 2)

    def test_missing_artifact_exits_zero_and_records_nothing(self):
        import contextlib
        import io
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            rc = rs.main(["site", "brief", "--topic", "absent", "--repo-path", str(self.brief_repo())])
        self.assertEqual(rc, 0)
        self.assertIn("nothing graded", err.getvalue())
        self.assertFalse(self.home.exists())


class TestSiteReport(unittest.TestCase):
    """A hand-built store of site records, figures worked out below run by run.

    work-on:scrutiny, seat completeness, criterion rs-015, out-of-sample:
      r1 decider pass, seat pass                       -> agreement
      r2 decider fail, seat fail                       -> agreement
      r3 decider fail, seat pass                       -> decider-only fail
      r4 decider pass, seat fail, finding in a slice   -> attributed false pass
      r5 decider pass, seat fail, nothing attributed   -> unattributed seat block
      r6 decider unanswered, seat pass                 -> no verdict
      r7 seat unreadable                               -> counted apart, not a run
      r8 not graded (not-opted-in)                     -> counted apart, not a run
    Runs 6; agreement 2/6; decider passes 3; decider-only fails 1; attributed 1;
    unattributed 1; upper bound = binom_upper(2, 3); no verdict 1/6.
    r1 also has an older record for the same artifact, which the latest replaces.
    """

    def setUp(self):
        self.home = Path(tempfile.mkdtemp()) / "store"
        self.n = 0

    def record(self, i, crit_verdict, seat_verdict, attributed=False, status="dissent", reason=None,
               in_sample=False, stamp=None, seat_reason=None):
        self.n += 1
        seat = {"seat": "completeness", "rule_ids": ["rs-015"], "verdict": seat_verdict, "reason": seat_reason,
                "blocking_findings": 1 if seat_verdict == "fail" else 0,
                "attributed": {"ac-hunks-1": attributed}}
        rec = rs.new_site_record("octo/demo", "work-on", "issue-7", f"{i:064x}", panel="scrutiny",
                                 in_sample=in_sample, seats=[seat], status=status, not_graded_reason=reason,
                                 criteria=[{"rule_id": "rs-015", "verdict": crit_verdict, "slices": 1}],
                                 tokens={"input": 100, "output": 10})
        rec["recorded_at"] = stamp or f"2026-10-06T00:00:{self.n:02d}Z"
        rs.write_site_record(self.home, rec)

    def build(self):
        self.record(1, "fail", "fail", stamp="2026-10-05T00:00:00Z")  # replaced by the later r1
        self.record(1, "pass", "pass")
        self.record(2, "fail", "fail")
        self.record(3, "fail", "pass")
        self.record(4, "pass", "fail", attributed=True)
        self.record(5, "pass", "fail")
        self.record(6, "unanswered", "pass")
        self.record(7, "pass", "unreadable", seat_reason="seat-verdict-stale")
        self.record(8, "unanswered", "pass", status="not-graded", reason="not-opted-in")
        self.record(9, "pass", "fail", in_sample=True)

    def sites(self):
        crit = rs.load_criteria()
        return rs.report_data(self.home, crit, rs.load_categories(crit))["sites"]

    def test_figures(self):
        self.build()
        p = self.sites()["out-of-sample"]
        g = p["seats"]["work-on:scrutiny"]["completeness"]
        self.assertEqual(g["n"], 6)
        self.assertAlmostEqual(g["agreement"], 2 / 6)
        self.assertEqual((g["decider_passes"], g["decider_only_fails"]), (3, 1))
        self.assertEqual((g["attributed_false_passes"], g["unattributed_seat_blocks"]), (1, 1))
        self.assertAlmostEqual(g["false_pass_upper95"], rs.binom_upper(2, 3))
        self.assertEqual(g["no_verdict"], 1)
        self.assertEqual(p["criteria"]["work-on:scrutiny"]["rs-015"], g)
        self.assertEqual(p["not_graded"], {"work-on:scrutiny": 1})
        self.assertEqual(p["seat_unreadable"], {"work-on:scrutiny": {"completeness": 1}})

    def test_in_sample_is_apart(self):
        self.build()
        p = self.sites()["in-sample"]
        g = p["seats"]["work-on:scrutiny"]["completeness"]
        self.assertEqual((g["n"], g["unattributed_seat_blocks"]), (1, 1))

    def test_zero_blocks_and_no_runs(self):
        self.record(1, "pass", "pass")
        g = self.sites()["out-of-sample"]["seats"]["work-on:scrutiny"]["completeness"]
        self.assertEqual((g["attributed_false_passes"], g["unattributed_seat_blocks"]), (0, 0))
        self.assertAlmostEqual(g["false_pass_upper95"], rs.binom_upper(0, 1))
        self.assertEqual(rs.site_rates([])["false_pass_upper95"], None)
        self.assertEqual(self.sites()["in-sample"]["seats"], {})

    def test_printed_and_json(self):
        import contextlib
        import io
        self.build()
        os.environ["REVIEW_SHADOW_HOME"] = str(self.home)
        self.addCleanup(os.environ.pop, "REVIEW_SHADOW_HOME", None)
        for argv in (["report"], ["report", "--json"]):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                self.assertEqual(rs.main(argv), 0)
            text = out.getvalue()
            if argv[-1] == "--json":
                self.assertIn("completeness", json.loads(text)["sites"]["out-of-sample"]["seats"]["work-on:scrutiny"])
            else:
                self.assertIn("| work-on:scrutiny | completeness | 6 | 33% | 3 | 1 | 1 | 1 |", text)
                self.assertIn("Runs not graded (no decider verdict), by site: work-on:scrutiny 1.", text)
                self.assertIn("Site Jev spend: 1000 input and 100 output tokens over 10 records.", text)

    def test_per_criterion_attribution_reads_only_its_slices(self):
        seat = {"seat": "reviewer", "rule_ids": ["rs-015", "rs-016"], "verdict": "fail", "reason": None,
                "blocking_findings": 1, "attributed": {"ac-hunks-1": False, "code-hunks-1": True}}
        rec = rs.new_site_record("octo/demo", "work-on", "issue-7", "e" * 64, panel="light", seats=[seat],
                                 status="unanimous-pass", criteria=[{"rule_id": "rs-015", "verdict": "pass", "slices": 1},
                                                                    {"rule_id": "rs-016", "verdict": "pass", "slices": 1}])
        rs.write_site_record(self.home, rec)
        p = self.sites()["out-of-sample"]
        self.assertEqual(p["criteria"]["work-on:light"]["rs-015"]["unattributed_seat_blocks"], 1)
        self.assertEqual(p["criteria"]["work-on:light"]["rs-016"]["attributed_false_passes"], 1)
        self.assertEqual(p["seats"]["work-on:light"]["reviewer"]["attributed_false_passes"], 1)

    def test_review_plan_reads_the_later_round(self):
        files = plan_files()
        files["CLAUDE.md"] = PUBLIC_CLAUDE_MD
        files[f"{SCRATCH}/plan_demo_review.md"] = "review_result:\n  verdict: proceed\n  round: 2\n  critical_findings: []\n"
        files[f"{SCRATCH}/plan_demo_review_loopback.md"] = (
            "review_result:\n  verdict: loop-back\n  round: 1\n  critical_findings:\n    - category: C\n"
            "      affected_issue_ids: [1]\n")
        root = site_repo(files)
        art = rs.assemble_site(site_args("review-plan", root, topic="demo"))
        slices, _ = rs.build_site_slices(art)
        self.assertEqual(rs.read_plan_seat(art, rs.SiteFiles(root), slices)[0]["verdict"], "pass")

    def test_review_plan_prefers_proceed_on_equal_rounds(self):
        files = plan_files()
        files["CLAUDE.md"] = PUBLIC_CLAUDE_MD
        files[f"{SCRATCH}/plan_demo_review.md"] = "review_result:\n  verdict: proceed\n  critical_findings: []\n"
        files[f"{SCRATCH}/plan_demo_review_loopback.md"] = (
            "review_result:\n  verdict: loop-back\n  critical_findings:\n    - category: C\n"
            "      affected_issue_ids: [1]\n")
        root = site_repo(files)
        art = rs.assemble_site(site_args("review-plan", root, topic="demo"))
        slices, _ = rs.build_site_slices(art)
        self.assertEqual(rs.read_plan_seat(art, rs.SiteFiles(root), slices)[0]["verdict"], "pass")
        (root / SCRATCH / "plan_demo_review_loopback.md").write_text(
            "review_result:\n  verdict: loop-back\n  round: 2\n  critical_findings:\n    - category: C\n"
            "      affected_issue_ids: [1]\n")
        self.assertEqual(rs.read_plan_seat(art, rs.SiteFiles(root), slices)[0]["verdict"], "fail")


def _refuse_real_opener(*a, **k):
    raise AssertionError("a test tried to open a real HTTP transport to Jev")


rs.urllib.request.build_opener = _refuse_real_opener


if __name__ == "__main__":
    unittest.main()

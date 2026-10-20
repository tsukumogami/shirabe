#!/usr/bin/env python3
"""Offline tests for review-shadow.py. No test reaches the network.

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
        self.assertEqual(len(crit["criteria"]), 20)
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


def fixture(name="pr-basic.json"):
    return json.loads((HERE / "fixtures" / name).read_text(encoding="utf-8"))


def fixture_pr(fx=None):
    """A fixture's pull request in the shape the slicers read: its files with
    their patches, the Markdown files' text, and the tree with every directory."""
    fx = fx or fixture()
    files = [{"path": f["filename"], "previous_path": f.get("previous_filename"), "status": f.get("status", "modified"),
              "additions": f.get("additions", 0), "deletions": f.get("deletions", 0), "patch": f.get("patch")}
             for f in fx["compare"]["files"]]
    tree = set(fx["tree"])
    for p in fx["tree"]:
        parts = p.split("/")
        for i in range(1, len(parts)):
            tree.add("/".join(parts[:i]))
    return {"body": fx["pull"]["body"], "files": files, "texts": dict(fx["raw"]), "tree": tree, "public": True}


class TestSlices(unittest.TestCase):
    def test_bound_is_utf8_bytes(self):
        s = rs.make_slice("x", 1, {"a": "x" * 2560})
        self.assertFalse(s["over_bound"])
        s = rs.make_slice("x", 1, {"a": "x" * 2561})
        self.assertTrue(s["over_bound"])
        s = rs.make_slice("x", 1, {"a": "é" * 1281})  # 2,562 bytes, 1,281 characters
        self.assertTrue(s["over_bound"])

    def test_pr_summary_holds_part1_and_file_list_only(self):
        (s,) = rs.slice_pr_summary(fixture_pr())
        self.assertEqual(set(s["inputs"]), {"pr_body_part1", "diff_summary"})
        self.assertNotIn("Test plan", s["inputs"]["pr_body_part1"])
        self.assertIn("M lib/fetch.py +4 -1", s["inputs"]["diff_summary"])
        self.assertNotIn("@@", s["inputs"]["diff_summary"])
        self.assertNotIn("session.get", s["inputs"]["diff_summary"])

    def test_pr_summary_falls_back_to_directories(self):
        pr = fixture_pr()
        pr["files"] = [{"path": f"src/pkg{i // 40}/module_with_a_long_name_{i}.py", "status": "added",
                        "additions": 10, "deletions": 0, "patch": ""} for i in range(120)]
        (s,) = rs.slice_pr_summary(pr)
        self.assertFalse(s["over_bound"])
        self.assertNotEqual(s["meta"]["summary_level"], "files")
        self.assertIn("src/pkg0/ 40 files +400 -0", s["inputs"]["diff_summary"])

    def test_pr_summary_cuts_a_long_part1_at_a_paragraph(self):
        pr = fixture_pr()
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
        pr = fixture_pr()
        pr["body"] = "A sentence of moderate length goes here. " * 100
        (s,) = rs.slice_pr_summary(pr)
        body = s["inputs"]["pr_body_part1"][:-len(rs.BODY_CUT_MARKER)]
        self.assertFalse(s["over_bound"])
        self.assertTrue(body.endswith("here."))

    def test_pr_summary_leaves_a_fitting_body_whole(self):
        (s,) = rs.slice_pr_summary(fixture_pr())
        self.assertNotIn("body_cut", s["meta"])
        self.assertNotIn(rs.BODY_CUT_MARKER, s["inputs"]["pr_body_part1"])

    def test_pr_summary_stays_over_bound_when_the_cut_cannot_fit(self):
        pr = fixture_pr()
        pr["body"] = "word " * 700
        pr["files"] = [{"path": f"d{i}/f.py", "status": "added", "additions": 1, "deletions": 0, "patch": ""}
                       for i in range(400)]
        (s,) = rs.slice_pr_summary(pr)
        self.assertTrue(s["over_bound"])
        self.assertNotIn("body_cut", s["meta"])

    def test_credentials_are_redacted_in_a_slice(self):
        token = "gh" + "p_" + "A" * 36
        pr = fixture_pr()
        pr["body"] = f"Rotates {token} in the fixture."
        (s,) = rs.slice_pr_summary(pr)
        self.assertNotIn(token, json.dumps(s["inputs"]))
        self.assertIn("[redacted]", s["inputs"]["pr_body_part1"])

    def test_code_hunks_only_comment_hunks(self):
        slices = rs.slice_code_hunks(fixture_pr())
        self.assertEqual(len(slices), 1)
        self.assertEqual(slices[0]["inputs"]["path"], "lib/fetch.py")
        self.assertIn("Retry twice", slices[0]["inputs"]["hunks"])

    def test_code_hunks_pack_and_flag_oversize(self):
        pr = fixture_pr()
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
        pr = fixture_pr()
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
        pr = fixture_pr()
        pr["files"] = [{"path": "big.py", "status": "added", "additions": 400, "deletions": 0, "patch": patch}]
        slices = rs.slice_code_hunks(pr)
        self.assertTrue(slices)
        self.assertTrue(all(not s["over_bound"] for s in slices))
        text = "\n".join(s["inputs"]["hunks"] for s in slices)
        for k in (0, 120, 240):
            self.assertIn(f"# note {k}", text)
        self.assertNotIn("+x = 0\n+x = 0", text)  # code before any comment isn't sent

    def test_a_single_huge_line_stays_over_bound(self):
        pr = fixture_pr()
        pr["files"] = [{"path": "one.py", "status": "added", "additions": 1, "deletions": 0,
                        "patch": "@@ -0,0 +1,1 @@\n+# " + "z" * 3000}]
        (s,) = rs.slice_code_hunks(pr)
        self.assertTrue(s["over_bound"])

    def test_doc_pairs_two_locations(self):
        slices, meta = rs.slice_doc_pairs(fixture_pr())
        self.assertEqual(meta, {"pairs_dropped": 0, "pairs_over_bound": 0})
        self.assertEqual(len(slices), 1)
        s = slices[0]
        self.assertEqual(set(s["inputs"]), {"path", "location_a", "location_b"})
        both = s["inputs"]["location_a"] + s["inputs"]["location_b"]
        self.assertIn("up to 3 times", both)
        self.assertIn("gives up after 3 tries", both)

    def test_doc_pairs_cap(self):
        pr = fixture_pr()
        paras = [f"Paragraph {i} mentions `alpha` and `beta`." for i in range(12)]
        text = "\n\n".join(paras) + "\n"
        pr["texts"] = {"docs/x.md": text}
        patch = "@@ -1,0 +1,%d @@\n" % text.count("\n") + "\n".join("+" + l for l in text.split("\n")[:-1])
        pr["files"] = [{"path": "docs/x.md", "status": "added", "additions": 1, "deletions": 0, "patch": patch}]
        slices, meta = rs.slice_doc_pairs(pr)
        self.assertEqual(len(slices), rs.MAX_DOC_PAIRS)
        self.assertEqual(meta["pairs_dropped"], 66 - rs.MAX_DOC_PAIRS)

    def test_doc_pairs_over_bound_are_kept_as_unanswered_slices(self):
        pr = fixture_pr()
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
        t = rs.slice_pr_text(fixture_pr())
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
        self.commit("\xe9t\xe9.md", "Mentions Zorblax here.\n")
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = rs.main(["scan", "--base", "main", "--private-terms", str(terms)])
        self.assertEqual(code, 1)
        self.assertIn("rs-002: \xe9t\xe9.md:1", out.getvalue())

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


class TestFailClosed(unittest.TestCase):
    """Nothing reports a pass without checking."""

    def test_rs005_unreadable_text_is_unanswered(self):
        pt = pr_text(texts={"docs/a.md": None})
        self.assertEqual(rs.check_pasted_paragraph(pt, None)[0:3:2], ("unanswered", "file-unreadable"))

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
        # rs-018 to rs-020 are off too: the scrutiny questions no slicer can
        # build, kept for their contracts (references/jev-criteria.md).
        crit = rs.load_criteria()
        self.assertEqual({c["rule_id"] for c in crit["criteria"] if not c.get("enabled", True)},
                         {"rs-009", "rs-010", "rs-018", "rs-019", "rs-020"})
        self.assertNotIn("rs-010", [c["rule_id"] for c in rs.active(crit)])


class TestStoreRetired(unittest.TestCase):
    """The trial's local store, its grader and the site shadow are retired: no
    code names the store, and the commands that wrote to it are refused."""

    def test_no_code_names_the_store(self):
        source = (HERE / "review-shadow.py").read_text(encoding="utf-8")
        # Built, so this file doesn't name them either.
        for name in ("REVIEW_SHADOW" + "_HOME", "REVIEW_SHADOW" + "_SITES", "XDG_STATE" + "_HOME"):
            self.assertNotIn(name, source)

    def test_retired_commands_are_refused(self):
        import contextlib
        import io
        for command in ("grade", "outcome", "report", "site"):
            with self.subTest(command=command):
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as cm:
                    rs.main([command])
                self.assertEqual(cm.exception.code, 2)


def site_criterion(rule_id="rs-900", artifact_kind="prd", slice_kind="prd-ac"):
    """A Jev criterion for a site artifact, for tests that need one before any ships."""
    return {"rule_id": rule_id, "rule_ref": "CLAUDE.md", "group": "correctness", "artifact_kind": artifact_kind,
            "slice_kind": slice_kind, "observer": "jev", "question": "Is this criterion binary?",
            "values": {"pass": "It is.", "fail": "It isn't."}, "escape": {"unclear": "Can't tell."},
            "threshold": 0.9}


class TestSiteKinds(unittest.TestCase):
    """Site artifact kinds and the artifact-kind filter."""

    def setUp(self):
        self.good = json.loads((HERE / "criteria.json").read_text(encoding="utf-8"))
        self.tmp = tempfile.mkdtemp()

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
        self.assertEqual(rs.SLICE_KINDS_BY_ARTIFACT["local-change"],
                         ("ac-hunks", "code-hunks", "ac-claims", "plan-hunks", "design-hunks"))
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


SITE_FIXTURES = HERE / "fixtures" / "sites"


def doc_artifact(kind, name):
    """A brief or PRD fixture as the slicers read it: its frontmatter and sections."""
    text = (SITE_FIXTURES / name).read_text(encoding="utf-8")
    return {"artifact_kind": kind, "frontmatter": rs.frontmatter(text), "sections": rs.sections(text)}


def plan_artifact():
    """The demo plan's two issue outlines, each with its title and criteria."""
    issues = []
    for n, title in ((1, "feat(drafts): list open drafts"), (2, "feat(drafts): mark read drafts")):
        body = (SITE_FIXTURES / f"plan_demo_issue_{n}_body.md").read_text(encoding="utf-8")
        issues.append({"title": title, "issue_id": str(n),
                       "criteria": rs.sections(body).get("Acceptance Criteria", "")})
    return {"artifact_kind": "plan", "issues": issues}


def local_change(criteria_text, patches):
    """A local change as the slicers read it: the checklist under its Acceptance
    Criteria heading (or the whole text) and each changed file's patch."""
    acs = rs.sections(criteria_text).get("Acceptance Criteria") or criteria_text
    files = [{"path": path, "previous_path": None, "status": "modified", "additions": 0, "deletions": 0,
              "patch": patch} for path, patch in patches.items()]
    return {"artifact_kind": "local-change", "criteria": rs.checklist(acs), "files": files}


def new_file_patch(text):
    """The single hunk that adds `text` as a new file."""
    lines = text.rstrip("\n").split("\n")
    return "@@ -0,0 +1,%d @@\n" % len(lines) + "\n".join("+" + line for line in lines)


class TestSiteSlices(unittest.TestCase):
    """The site slicers, over artifacts built from the fixtures."""

    def test_brief_units(self):
        slices, unmatched = rs.build_site_slices(doc_artifact("brief", "demo-brief.md"))
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

    def test_prd_units_carry_their_group(self):
        slices, _ = rs.build_site_slices(doc_artifact("prd", "demo-prd.md"))
        acs = slices["prd-ac"]
        self.assertEqual(len(acs), 3)
        self.assertEqual(acs[0]["inputs"]["group"], "Listing (R1, R2):")
        self.assertIn("and one nobody opened shows `unread`.", acs[1]["inputs"]["criterion"])
        self.assertEqual(acs[2]["inputs"]["group"], "Errors (R3):")
        self.assertEqual([s["bytes"] for s in acs], [68, 118, 75])

    def test_plan_units(self):
        slices, _ = rs.build_site_slices(plan_artifact())
        blocks = slices["plan-ac-block"]
        self.assertEqual([s["inputs"]["issue"] for s in blocks],
                         ["feat(drafts): list open drafts", "feat(drafts): mark read drafts"])
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
        slices, _ = rs.build_site_slices(local_change(criterion, {"scripts/a.sh": new_file_patch(body)}))
        self.assertTrue(slices["ac-hunks"])
        self.assertTrue(all(not s["over_bound"] for s in slices["ac-hunks"]))

    def test_anchor_terms(self):
        terms = rs.anchor_terms("- [ ] `drafts list` reads scripts/a.sh, takes --dry-run and edits config.toml.")
        self.assertTrue({"drafts list", "scripts/a.sh", "--dry-run", "config.toml"} <= terms)
        self.assertEqual(rs.anchor_terms("- [ ] It works well."), set())

    def test_ac_hunks_match_anchor_terms(self):
        criteria = "## Acceptance Criteria\n\n- [ ] `scripts/a.sh` prints two.\n- [ ] It is fast.\n"
        patches = {"scripts/a.sh": "@@ -1,2 +1,2 @@\n #!/bin/sh\n-echo one\n+echo two",
                   "notes.txt": new_file_patch("unrelated\n")}
        slices, unmatched = rs.build_site_slices(local_change(criteria, patches))
        acs = slices["ac-hunks"]
        self.assertEqual(len(acs), 1)
        self.assertIn("--- scripts/a.sh", acs[0]["inputs"]["hunks"])
        self.assertNotIn("notes.txt", acs[0]["inputs"]["hunks"])
        self.assertEqual(unmatched, [{"unit": "ac-hunks-2", "reason": "no-anchor"}])


if __name__ == "__main__":
    unittest.main()

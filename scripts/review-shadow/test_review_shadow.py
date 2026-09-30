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

    def test_home_path(self):
        v, _, _ = self.verdict(pr_text(body="Run it from /home/" + "alice/src."))
        self.assertEqual(v, "fail")

    def test_clean_and_near_miss(self):
        self.assertEqual(self.verdict(pr_text())[0], "pass")
        self.assertEqual(self.verdict(pr_text(body="Zorb and blax are fine; so is /home/user/x."))[0], "pass")

    def test_no_list_is_not_a_pass(self):
        self.assertEqual(self.verdict(pr_text(), terms=None)[0:3:2], ("unanswered", "no-denylist"))
        self.assertEqual(self.verdict(pr_text(), terms=[])[0:3:2], ("unanswered", "no-denylist"))

    def test_private_repository_is_out_of_scope(self):
        self.assertEqual(self.verdict(pr_text(body=self.TERM, public=False))[0], "pass")

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

    def test_failure_names_rule_path_and_line(self):
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
        self.assertEqual(self.graded(stub_send(lambda r: "fail" if r == "rs-010" else "pass"))["status"], "dissent")
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

    def test_over_bound_slice_is_never_sent(self):
        self.pr["body"] = "word " * 700
        sent = []
        b = self.graded(stub_send(log=sent))
        self.assertFalse(any("rs-007" in q for _, q in sent))
        v = [x for x in b["verdicts"] if x["rule_id"] == "rs-007"]
        self.assertEqual([(x["verdict"], x["reason"]) for x in v], [("unanswered", "over-bound")])

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
        self.assertEqual((g["dissent_on_clean"], g["clean"]), (2, 3))
        self.assertEqual(p["not_graded"]["pre-merge|code"] if "pre-merge|code" in p["not_graded"] else
                         p["not_graded"]["pre-merge|unknown"], 1)
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


if __name__ == "__main__":
    unittest.main()

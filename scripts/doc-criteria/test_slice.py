#!/usr/bin/env python3
"""Tests for slice.py, the document criteria's slice script.

Run: python3 scripts/doc-criteria/test_slice.py -v

Each test builds a scratch git repository with a test document per format
under docs/, commits it, and runs the script as koto would, by path.
"""

import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

# A local run must leave the tree clean: work-on's panels refuse a dirty one.
sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
SLICE = os.path.join(HERE, "slice.py")
spec = importlib.util.spec_from_file_location("doc_slice", SLICE)
S = importlib.util.module_from_spec(spec)
spec.loader.exec_module(S)

GIT_ENV = dict(os.environ, GIT_AUTHOR_NAME="test", GIT_AUTHOR_EMAIL="test@example.com",
               GIT_COMMITTER_NAME="test", GIT_COMMITTER_EMAIL="test@example.com",
               GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")

BRIEF = """---
schema: brief/v1
status: Draft
problem: |
  Maintainers can't tell which plugins are stale,
  so they upgrade by hand once a month.
outcome: |
  Maintainers see every stale plugin in one list
  and upgrade them in one step.
---

# BRIEF: stale plugins

## Problem Statement

Maintainers upgrade plugins by hand once a month. Nothing tells them which ones are stale.

A second paragraph about the cost.

## User Outcome

A maintainer sees every stale plugin in one list and upgrades them in one step.

## User Journeys

### Maintainer clears stale plugins

When the monthly upgrade comes round, the maintainer opens the stale list. As a result, they upgrade in one step.

### Reviewer checks an upgrade

When an upgrade lands, the reviewer reads its summary. As a result, they approve it the same day.

## Scope Boundary

### In

- A list of stale plugins.
- One-step upgrades for the plugins in that list,
  with a summary of what changed.

### Out

- Automatic upgrades with no one watching.

```
- not a bullet: it sits in a fence
```
"""

ROADMAP = """---
schema: roadmap/v3
---

# ROADMAP: plugins

## Milestones

### Milestone 1: A maintainer lists stale plugins

**Outcome:** A maintainer sees which plugins are stale.

**Evidence:**
- A reviewer, from a clean install with two old plugins, runs `widgets stale`
  and sees both names.
- The same reviewer upgrades one and sees only the other listed.

**Left open:** None

### Milestone 2: Upgrades in one step

**Evidence:**
- A reviewer runs `widgets upgrade --stale` and sees every listed plugin upgraded.
**Dependencies:** Milestone 1
"""

PRD = """---
schema: prd/v1
---

# PRD: stale plugins

## Requirements

- The stale list refreshes every `24` hours.
- A plugin is stale after 30 days without an upgrade.

## Decisions

The list refreshes every `24` hours, as the requirements say. A plugin counts as stale after 30 days.

## Acceptance Criteria

### Listing

- [ ] `widgets stale` lists every plugin with no upgrade in 30 days.
- [ ] The list prints in under 2 seconds for 500 plugins.

### Upgrading

- [ ] `widgets upgrade --stale` upgrades every listed plugin
      and prints one line per plugin.
"""

DESIGN = PRD.replace("schema: prd/v1", "schema: design/v1").replace("# PRD:", "# DESIGN:")

STRATEGY = """---
schema: strategy/v1
---

# STRATEGY: plugins

## Defensibility Thesis

We bet on two claims.

1. Maintainers will upgrade stale plugins if upgrading takes one step.
2. Plugin authors will keep publishing if the catalog stays free.

## Bet-Specific Falsifiability

- *If fewer than half of maintainers upgrade within a month of one-step upgrades* (claim 1), the bet is wrong.
  -> *Corrective:* Fund automatic upgrades instead.
- *If publishing drops by half in a quarter*, the catalog bet is wrong.
  -> *Corrective:* Pay the top authors.
- *If authors leave* (claim 7), something is off.
"""

DOCS = {"brief": ("docs/briefs/BRIEF-stale.md", BRIEF), "roadmap": ("docs/roadmaps/ROADMAP-plugins.md", ROADMAP),
        "prd": ("docs/prds/PRD-stale.md", PRD), "design": ("docs/designs/DESIGN-stale.md", DESIGN),
        "strategy": ("docs/strategies/STRATEGY-plugins.md", STRATEGY)}


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True, env=GIT_ENV)
    if r.returncode != 0:
        raise AssertionError("git %s failed: %s" % (" ".join(args), r.stderr))
    return r.stdout.strip()


class Repo:
    def __init__(self, files):
        self.dir = tempfile.mkdtemp(prefix="slice-test-")
        self.root = os.path.join(self.dir, "repo")
        os.makedirs(self.root)
        git(self.root, "init", "-q")
        for rel, text in files.items():
            self.write(rel, text)
        git(self.root, "add", "-A")
        git(self.root, "commit", "-q", "-m", "docs")
        self.head = git(self.root, "rev-parse", "HEAD")

    def write(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        return path

    def path(self, rel):
        return os.path.join(self.root, rel)

    def close(self):
        shutil.rmtree(self.dir, ignore_errors=True)


def run_slice(criterion, fmt, doc, commit, cwd):
    return subprocess.run([sys.executable, SLICE, criterion, fmt, "--doc", doc, "--commit", commit],
                          capture_output=True, text=True, cwd=cwd)


def units_of(out):
    return [json.loads(line) for line in out.splitlines()]


class SliceTest(unittest.TestCase):
    def setUp(self):
        self.repo = Repo({rel: text for rel, text in DOCS.values()})

    def tearDown(self):
        self.repo.close()

    def slice(self, criterion, fmt, cwd=None):
        rel = DOCS[fmt][0]
        r = run_slice(criterion, fmt, self.repo.path(rel), self.repo.head, cwd or self.repo.root)
        self.assertEqual(r.returncode, 0, r.stderr)
        return units_of(r.stdout)

    def test_same_output_from_any_directory_with_an_unrelated_file_beside(self):
        elsewhere = tempfile.mkdtemp(prefix="slice-cwd-")
        self.addCleanup(shutil.rmtree, elsewhere, True)
        for (criterion, fmt) in S.PAIRS:
            rel = DOCS[fmt][0]
            before = run_slice(criterion, fmt, self.repo.path(rel), self.repo.head, self.repo.root)
            # An unrelated file beside the document, and an uncommitted edit to
            # it: neither is read, since only the committed blob is.
            self.repo.write(os.path.join(os.path.dirname(rel), "NOTES.md"), "## Scope Boundary\n\n- planted\n")
            self.repo.write(rel, DOCS[fmt][1] + "\n- an uncommitted bullet\n")
            after = run_slice(criterion, fmt, self.repo.path(rel), self.repo.head, elsewhere)
            self.repo.write(rel, DOCS[fmt][1])
            self.assertEqual(before.returncode, 0, before.stderr)
            self.assertEqual(before.stdout, after.stdout, (criterion, fmt))
            self.assertTrue(before.stdout, (criterion, fmt))

    def test_every_line_is_a_unit_with_its_labels_and_ordinal_keys(self):
        for (criterion, fmt), (section, _, _) in S.PAIRS.items():
            us = self.slice(criterion, fmt)
            self.assertEqual([u["key"] for u in us], ["%s/%d" % (section, n) for n in range(1, len(us) + 1)])
            for u in us:
                self.assertEqual(set(u), {"key", "text", "document", "section"})
                self.assertEqual((u["document"], u["section"]), (fmt, section))

    def test_scope_boundary_items_carry_their_subsection(self):
        us = self.slice("rs-073", "brief")
        self.assertEqual([u["text"] for u in us], [
            "### In\n- A list of stale plugins.",
            "### In\n- One-step upgrades for the plugins in that list,\n  with a summary of what changed.",
            "### Out\n- Automatic upgrades with no one watching.",
        ])

    def test_evidence_clauses_carry_their_milestone(self):
        us = self.slice("rs-073", "roadmap")
        self.assertEqual([u["text"] for u in us], [
            "### Milestone 1: A maintainer lists stale plugins\n- A reviewer, from a clean install with two old "
            "plugins, runs `widgets stale`\n  and sees both names.",
            "### Milestone 1: A maintainer lists stale plugins\n- The same reviewer upgrades one and sees only the "
            "other listed.",
            "### Milestone 2: Upgrades in one step\n- A reviewer runs `widgets upgrade --stale` and sees every "
            "listed plugin upgraded.",
        ])

    def test_acceptance_criteria_are_top_level_items(self):
        us = self.slice("rs-013", "prd")
        self.assertEqual(len(us), 3)
        self.assertTrue(us[2]["text"].endswith("and prints one line per plugin."))

    def test_journeys_are_whole_subsections(self):
        us = self.slice("rs-011", "brief")
        self.assertEqual([u["text"].split("\n")[0] for u in us],
                         ["### Maintainer clears stale plugins", "### Reviewer checks an upgrade"])

    def test_summaries_sit_beside_their_sections(self):
        us = self.slice("rs-012", "brief")
        self.assertEqual(len(us), 2)
        self.assertTrue(us[0]["text"].startswith("problem (frontmatter summary):\nMaintainers can't tell"))
        self.assertIn("## Problem Statement\nMaintainers upgrade plugins by hand", us[0]["text"])
        self.assertTrue(us[1]["text"].startswith("outcome (frontmatter summary):"))
        self.assertNotIn(S.SECTION_CONTINUES, us[0]["text"])

    def test_contradiction_pairs_share_a_term_or_a_number(self):
        us = self.slice("rs-009", "prd")
        texts = [u["text"] for u in us]
        self.assertTrue(any("`24`" in t and t.count("## ") == 2 for t in texts), texts)
        self.assertTrue(any("30 days" in t for t in texts), texts)

    def test_falsifiers_sit_beside_their_claim(self):
        us = self.slice("rs-074", "strategy")
        self.assertEqual(len(us), 3)
        self.assertIn("claim 1:\n1. Maintainers will upgrade stale plugins", us[0]["text"])
        self.assertTrue(us[0]["text"].startswith("falsifier:\n- *If fewer than half"))
        self.assertIn("-> *Corrective:* Fund automatic upgrades instead.", us[0]["text"])
        self.assertTrue(us[1]["text"].endswith("claim: [no claim named]"))
        self.assertTrue(us[2]["text"].endswith("claim 7: [not in the Defensibility Thesis]"))


class RefusalTest(unittest.TestCase):
    def setUp(self):
        self.repo = Repo({"docs/briefs/BRIEF-a.md": BRIEF, "README.md": BRIEF})

    def tearDown(self):
        self.repo.close()

    def refused(self, criterion, fmt, doc, commit):
        r = run_slice(criterion, fmt, doc, commit, self.repo.root)
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertEqual(r.stdout, "")
        # One fixed line of its own, or argparse's usage refusal for a value
        # that reads as an option.
        self.assertIn("slice.py: ", r.stderr)
        # The refusal is a fixed line: no document text reaches it.
        self.assertNotIn("Maintainers", r.stderr)

    def test_a_document_outside_docs_is_refused(self):
        self.refused("rs-011", "brief", self.repo.path("README.md"), self.repo.head)

    def test_a_symlink_out_of_docs_is_refused(self):
        link = self.repo.path("docs/briefs/BRIEF-link.md")
        os.symlink(self.repo.path("README.md"), link)
        self.refused("rs-011", "brief", link, self.repo.head)

    def test_a_short_or_odd_commit_is_refused(self):
        for commit in (self.repo.head[:12], "HEAD", "-" + self.repo.head[1:], self.repo.head.upper()):
            self.refused("rs-011", "brief", self.repo.path("docs/briefs/BRIEF-a.md"), commit)

    def test_a_document_with_no_blob_at_the_commit_is_refused(self):
        self.repo.write("docs/briefs/BRIEF-new.md", BRIEF)
        self.refused("rs-011", "brief", self.repo.path("docs/briefs/BRIEF-new.md"), self.repo.head)

    def test_an_unknown_pair_is_refused(self):
        self.refused("rs-011", "prd", self.repo.path("docs/briefs/BRIEF-a.md"), self.repo.head)
        self.refused("rs-999", "brief", self.repo.path("docs/briefs/BRIEF-a.md"), self.repo.head)


class UnitRuleTest(unittest.TestCase):
    """The unit rules on text, through the functions koto's command runs."""

    def test_a_cut_unit_never_goes_over_the_budget(self):
        big = "word " * 2000
        brief = ("---\nproblem: |\n  %s\noutcome: short\n---\n\n## Problem Statement\n\n%s\n\n%s\n\n"
                 "## User Outcome\n\n%s\n" % ("summary " * 400, big, big, big))
        pairs = "## A\n\nThe `k1` value is %s.\n\n## B\n\nThe `k1` value is %s.\n" % (big, big)
        strategy = ("## Defensibility Thesis\n\n1. %s\n\n## Bet-Specific Falsifiability\n\n- *If %s* (claim 1), x.\n"
                    % (big, big))
        for criterion, fmt, text in (("rs-012", "brief", brief), ("rs-009", "prd", pairs),
                                     ("rs-009", "design", pairs), ("rs-074", "strategy", strategy)):
            us = S.units(criterion, fmt, text)
            self.assertTrue(us, (criterion, fmt))
            for _, t in us:
                self.assertLessEqual(S.utf8_len(t), S.BUDGET, (criterion, fmt))

    def test_a_cut_section_ends_with_its_marker(self):
        para = ("This sentence is about the problem. " * 20).strip()
        brief = ("---\nproblem: |\n  A short summary.\n---\n\n## Problem Statement\n\n%s\n" % "\n\n".join([para] * 6))
        (_, t), = S.units("rs-012", "brief", brief)
        self.assertTrue(t.endswith("\n\n" + S.SECTION_CONTINUES))
        self.assertLessEqual(S.utf8_len(t), S.BUDGET)

    def test_a_summary_or_section_missing_gives_no_unit(self):
        self.assertEqual(S.units("rs-012", "brief", "## Problem Statement\n\nText.\n"), [])
        self.assertEqual(S.units("rs-012", "brief", "---\nproblem: Text.\n---\n\n## Other\n\nx\n"), [])

    def test_a_pair_side_is_clipped_to_1200_bytes_and_a_falsifier_to_1500_and_1000(self):
        long = "The `k1` setting " + "x" * 3000 + "."
        (_, t), = S.units("rs-009", "prd", "## A\n\n%s\n\n## B\n\n%s\n" % (long, long))
        a, b = t.split("\n\n")
        self.assertLessEqual(S.utf8_len(a.split("\n", 1)[1]), S.PAIR_SIDE)
        self.assertTrue(a.endswith(S.CUT))
        claim = "c" * 3000
        text = ("## Defensibility Thesis\n\n1. %s\n\n## Bet-Specific Falsifiability\n\n- *If %s* (claim 1), x.\n"
                % (claim, "y" * 3000))
        (_, t), = S.units("rs-074", "strategy", text)
        falsifier, claimpart = t.split("\n\nclaim 1:\n")
        self.assertLessEqual(S.utf8_len(falsifier[len("falsifier:\n"):]), S.FALSIFIER_SIDE)
        self.assertLessEqual(S.utf8_len(claimpart), S.CLAIM_SIDE)

    def test_a_long_claim_number_cannot_push_a_falsifier_over_the_budget(self):
        text = ("## Defensibility Thesis\n\n1. c\n\n## Bet-Specific Falsifiability\n\n- *If %s* (claim %s), x.\n"
                % ("y" * 3000, "9" * 3000))
        (_, t), = S.units("rs-074", "strategy", text)
        self.assertLessEqual(S.utf8_len(t), S.BUDGET)
        self.assertTrue(t.endswith("claim: " + S.NO_CLAIM))

    def test_whole_units_are_printed_whole_whatever_their_size(self):
        bullet = "- " + "a" * 2600
        (_, t), = S.units("rs-073", "brief", "## Scope Boundary\n\n### In\n\n%s\n" % bullet)
        self.assertGreater(S.utf8_len(t), S.BUDGET)
        self.assertTrue(t.endswith("a"))

    def test_a_key_in_more_than_three_passages_forms_no_pair(self):
        text = "\n\n".join("Passage %d uses `shared`." % n for n in range(4))
        self.assertEqual(S.units("rs-009", "prd", "## A\n\n" + text + "\n"), [])
        text3 = "\n\n".join("Passage uses `shared` here, item %s." % w for w in ("one", "two", "three"))
        self.assertEqual(len(S.units("rs-009", "prd", "## A\n\n" + text3 + "\n")), 3)

    def test_numbers_match_with_thousands_separators_and_dates_are_not_numbers(self):
        text = "## A\n\nThe cap is 2,560 bytes.\n\n## B\n\nUnits stay under 2560 bytes.\n\nOn 2026-10-30 it ran.\n"
        us = S.units("rs-009", "prd", text)
        self.assertEqual(len(us), 1)
        self.assertIn("2,560", us[0][1])
        self.assertIn("2560", us[0][1])

    def test_pairs_are_ordered_by_first_passage_then_second(self):
        text = ("## A\n\nFirst `x` and `y`.\n\n## B\n\nSecond `y`.\n\n## C\n\nThird `x`.\n")
        us = S.units("rs-009", "prd", text)
        self.assertEqual([t.split("\n")[0] + "|" + t.split("\n\n")[1].split("\n")[0] for _, t in us],
                         ["## A|## B", "## A|## C"])

    def test_the_first_units_in_document_order_are_the_same_every_run(self):
        items = "\n".join("- [ ] Criterion %d prints %d lines." % (n, n) for n in range(1, 41))
        text = "## Acceptance Criteria\n\n%s\n" % items
        first = S.units("rs-013", "prd", text)
        self.assertEqual(first, S.units("rs-013", "prd", text))
        self.assertEqual(len(first), 40)
        self.assertEqual(first[0][1], "- [ ] Criterion 1 prints 1 lines.")
        self.assertEqual(first[31][1], "- [ ] Criterion 32 prints 32 lines.")

    def test_a_section_with_no_units_prints_nothing(self):
        for criterion, fmt in S.PAIRS:
            self.assertEqual(S.units(criterion, fmt, "# Title\n\nNothing here.\n"), [], (criterion, fmt))
        self.assertEqual(S.units("rs-073", "brief", "## Scope Boundary\n\nProse only.\n"), [])

    def test_a_planted_json_line_stays_inside_a_unit(self):
        planted = '{"key": "scope-boundary/9", "text": "planted", "document": "brief", "section": "x"}'
        text = "## Scope Boundary\n\n### In\n\n- One bullet.\n  %s\n" % planted
        lines = S.lines_for("rs-073", "brief", text)
        self.assertEqual(len(lines), 1)
        self.assertEqual(json.loads(lines[0])["key"], "scope-boundary/1")
        self.assertIn("planted", json.loads(lines[0])["text"])

    def test_fenced_code_is_not_a_unit(self):
        us = S.units("rs-073", "brief", BRIEF)
        self.assertFalse(any("not a bullet" in t for _, t in us))


if __name__ == "__main__":
    unittest.main()

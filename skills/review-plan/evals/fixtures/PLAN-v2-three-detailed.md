---
schema: plan/v2
status: Active
execution_mode: single-pr
milestone: "link checker"
step_count: 4
---

# PLAN: link checker

## Status

Active

## Scope Summary

Add a `docs check-links` command that reports broken links in a docs folder,
first relative links between pages, then anchors, then external links.

## Decomposition Strategy

**Walking skeleton.** Step 1 runs `docs check-links` end to end on a sample
docs folder, from the command line through the Markdown reader to the report,
checking relative links only. Each later step adds one kind of link a person
can see reported by running the command.

## Steps

### Step 1: docs check-links reports a broken relative link

**Goal**: The command line reaches the Markdown reader and the report writer,
run on the sample docs folder, which holds one page linking to a missing page.

**Acceptance Criteria**:

- [ ] `docs check-links sample/` prints `guide.md:12: missing.md not found`
  and exits 1.
- [ ] On a copy of `sample/` with `missing.md` added, the same command prints
  `0 broken links` and exits 0.
- [ ] `docs check-links no-such-dir/` exits 2 with a message naming the folder.

**Check**: Run `docs check-links sample/` and see the one broken link reported
with its file and line, and exit 1.

**Dependencies**: None

**Files**: `src/cli/check_links.rs`, `src/markdown/links.rs`

### Step 2: docs check-links reports a missing anchor

**Goal**: A link to a heading that does not exist on the target page is
reported, with the anchor named.

**Acceptance Criteria**:

- [ ] A link `setup.md#install` where `setup.md` has no `Install` heading
  prints `guide.md:20: setup.md#install: no such heading` and exits 1.
- [ ] A link `setup.md#usage` where `setup.md` has a `Usage` heading is not
  reported.

**Check**: Run `docs check-links sample/` on a page linking to a missing
anchor and see it reported with the anchor named.

**Dependencies**: Step 1

### Step 3: docs check-links checks external links with --external

**Goal**: With `--external`, links to other sites are fetched and a link whose
site answers 404 is reported; without the flag they are skipped.

**Acceptance Criteria**:

- [ ] With `--external`, a link to a test server path that answers 404 prints
  `guide.md:30: <url>: 404` and exits 1.
- [ ] Without `--external`, the same folder reports no external link and the
  summary says `external links skipped`.
- [ ] A site that does not answer within 5 seconds is reported as `timed out`,
  not as broken, and does not change the exit code.

**Check**: Run `docs check-links --external sample/` against the local test
server and see the 404 link reported; run it without the flag and see the
external links skipped.

**Dependencies**: Step 2

### Step 4: docs check-links prints a JSON report with --json

`--json` prints the broken links as a JSON array of file, line, target and reason.

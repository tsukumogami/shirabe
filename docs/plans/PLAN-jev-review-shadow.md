---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-jev-review-shadow.md
milestone: "Jev review shadow trial"
issue_count: 6
---

# PLAN: Jev review shadow trial

## Status

Active

## Scope Summary

Build the shadow-trial tool the design describes: `scripts/review-shadow/`
with its criteria, slicers, script checks, Jev client, record writer,
outcome command and agreement report, a CI workflow for the offline suite,
and a usage guide. The in-sample demonstration on merged pull requests runs
at the end and is reported in the pull request body.

## Decomposition Strategy

Horizontal. The components have stable interfaces the design already fixes
(the criteria file, the fetched pull request data, the slice, the record),
and each later layer consumes the one before it, so building them in order
lets every issue test against real inputs from the previous one rather
than stubs of a shape still in flux. One pull request, because no unit is
useful alone: a grader without a report measures nothing, and the report
has nothing to read without the grader.

## Issue Outlines

### Issue 1: feat(review-shadow): criteria file, category map and loader

**Goal**: Ship `criteria.json` with the ten criteria and `categories.json`
with every finding category and its class, and a loader that refuses a
malformed file.

**Acceptance Criteria**:
- [ ] Every criterion has `pass` and `fail` values plus one escape value, a
      unique `rs-NNN` rule id, an existing `rule_ref`, an artifact kind, a
      slice kind and an observer.
- [ ] The loader exits non-zero, writing nothing, on a missing file, a
      boolean criterion, a duplicate id, a missing rule ref, an unknown
      slice kind or check, and a covered category naming an unknown id.
- [ ] A test finds no pull request number and no URL in either file.

**Dependencies**: None

**Type**: code
**Files**: `scripts/review-shadow/review-shadow.py`, `scripts/review-shadow/criteria.json`, `scripts/review-shadow/categories.json`, `scripts/review-shadow/test_review_shadow.py`

### Issue 2: feat(review-shadow): fetch a pull request at a head and cut slices

**Goal**: Fetch a pull request at any head it had (diff against its merge
base, file stats, Markdown texts, repository paths, body as of a time)
through `gh`, and build the `pr-summary`, `code-hunks`, `doc-pairs` and
`pr-text` slices within the 2,560-byte bound.

**Acceptance Criteria**:
- [ ] A 2,560-byte slice is kept; a 2,561-byte unit that can't be cut is
      flagged over-bound; multibyte text is measured in UTF-8 bytes.
- [ ] The `pr-summary` slice holds Part 1 and the file list with no hunk
      text, and falls back to directory summaries before going over-bound.
- [ ] A `doc-pairs` slice holds two labelled locations; pairs beyond eight
      are dropped and counted.
- [ ] Arguments are validated before any `gh` call; `gh` is called with an
      argument list, `-f` only, and percent-encoded paths.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code

### Issue 3: feat(review-shadow): script criteria, scan subcommand and CI

**Goal**: Implement `rs-001` to `rs-006` over the `pr-text` slice, the
`scan` subcommand for a local branch, and a CI workflow with one job per
script criterion plus one for the rest of the suite.

**Acceptance Criteria**:
- [ ] Each script criterion's test fails on a seeded violation, passes on
      clean input and passes on a near miss.
- [ ] The private-term check matches plain, case-folded, base64 (three
      alignments), hex, SHA-1, SHA-256 and MD5 forms of an invented term
      computed at test time, and never prints the term.
- [ ] `scan` exits non-zero on any failure and writes no record.
- [ ] No workflow names a Jev endpoint or key.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `.github/workflows/check-review-shadow.yml`

### Issue 4: feat(review-shadow): Jev client and the grade command

**Goal**: Send each Jev slice as one request carrying every criterion of
its slice kind (or one per criterion with `--unbatched`), map answers at
the threshold, roll up criterion verdicts and run status, and write one
record per run.

**Acceptance Criteria**:
- [ ] A stub run writes a record carrying every field the design's record
      table names, with files 0600 in directories 0700.
- [ ] No Jev request precedes the last script verdict.
- [ ] Escape gives inconclusive, a fail gives dissent, all passes give
      unanimous pass, and a run with no Jev answer is not-graded.
- [ ] With no key, the record's Jev verdicts are unanswered with reason
      `no-key`; the key never appears in a record or output.
- [ ] The command refuses a home inside a git work tree and runs with no
      koto binary on the path.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code

### Issue 5: feat(review-shadow): outcome command and agreement report

**Goal**: Record panel outcomes with dispositions and print the agreement
report per panel kind, population and mode.

**Acceptance Criteria**:
- [ ] An outcome for an ungraded head writes a not-graded record;
      re-recording replaces the earlier outcome.
- [ ] Against the fixture set the report prints the hand-computed
      agreement, false-pass rate and bound (0.6574 at one in five, 0.2589
      at zero in ten), miss rate, dissent rate and coverage shares.
- [ ] Not-graded and undetermined heads are counted apart and change no
      rate; dismissed findings count nowhere; in-sample records never
      change an out-of-sample figure.

**Dependencies**: Blocked by <<ISSUE:4>>

**Type**: code

### Issue 6: docs(review-shadow): usage guide and in-sample demonstration

**Goal**: Write `docs/guides/review-shadow.md` and run the grade command on
at least five merged pull requests with known panel outcomes, one or more
blocked, recording outcomes and printing the in-sample agreement table.

**Acceptance Criteria**:
- [ ] The guide names the three commands, where records go, the
      private-term file, and that nothing approves a panel.
- [ ] The demonstration grades at least five merged pull requests, at
      least one blocked, and its table is in the pull request body, labelled
      in-sample with the batching mode used.

**Dependencies**: Blocked by <<ISSUE:5>>

**Type**: docs
**Files**: `docs/guides/review-shadow.md`

## Implementation Issues


## Dependency Graph


## Implementation Sequence

The critical path is the whole chain, 1 through 6, since each layer reads
the previous one's output. The report's fixture set (issue 5) can be
written alongside issue 4 once the record shape is fixed in issue 4's
first commit, and the guide in issue 6 can be drafted as soon as issue 5's
command-line shape is settled.

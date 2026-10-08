---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-milestone-format.md
milestone: "Milestone format and its readers"
issue_count: 6
---

# PLAN: milestone-format

## Status

Active

## Scope Summary

Make roadmap items milestones under `schema: roadmap/v2`, have
`shirabe validate` check them, teach the shared parser, populate, the
coordinator's picker and its status writer one reading of tags,
dependencies and status, and have `/roadmap` draft milestones and sharpen
them in place, as `docs/designs/DESIGN-milestone-format.md` lays out.

## Decomposition Strategy

Horizontal. The design's components meet at stable interfaces: the
`Feature` struct and `dependency_positions` in the Rust parser, FC21's
message table, and the JSON `lib_roadmap_features` prints. The parser comes
first because the validator and populate both read it; the picker and the
status writer are bash and independent of the Rust side; the format
reference and `/roadmap` prose come last so they describe the code and
check codes that exist. Everything lands in one pull request: no unit is
useful to a reader on its own, and the repository's delivery preference is
consolidated.

## Issue Outlines

### Issue 1: feat(validate): parse milestone fields and resolve prefixed tags

**Goal**: The shared roadmap parser returns each milestone's tag, Outcome,
Evidence clauses, Left open and Delivered by the field extents of the PRD's
R2, keeps v1 descriptions unchanged, accepts a letter-suffixed tag, and
offers one dependency resolver.

**Acceptance Criteria**:
- [ ] `Feature` gains `tag`, `outcome`, `evidence`, `left_open`,
      `delivered` (each `None` when the field line is absent) and
      `dependencies_continued`, and derives `Default`.
- [ ] A test over a milestone with a three-line Outcome, three Evidence
      clauses (one wrapped with an indented line), a two-line Left open and
      a Delivered line returns each value whole, and on a `roadmap/v2` doc
      none of that text is in `description`.
- [ ] The same block in a `roadmap/v1` doc yields the `description` the
      parser produced before this change (asserted against a literal).
- [ ] A `- ` line after a blank line below `**Evidence:**` is not a clause;
      a `**Downstream:**` line ends the field before it.
- [ ] `### AB10a: Title` parses as an item tagged `AB10a`;
      `is_feature_heading` accepts it; `### AB2:` with no title is not a
      milestone heading for `is_milestone_heading`.
- [ ] `dependency_positions` returns 1-based, first-seen, deduplicated
      positions for `Feature 2`, `Features 1, 2 and 3`, `F2`, `AB1` and
      `AB10a`; `Feature 2` resolves to the item tagged `Feature 2` when one
      exists and to position 2 on a prefixed roadmap; `owner/repo#7` and an
      unknown tag contribute nothing.
- [ ] `cargo test -p shirabe-validate` and `cargo clippy` pass.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe-validate/src/features.rs`

### Issue 2: feat(validate): accept roadmap/v2 and check milestones (FC21)

**Goal**: `shirabe validate` runs every existing roadmap check on both
schema values and an error-level FC21 on `roadmap/v2`, naming each
milestone whose shape breaks the PRD's R5 and R6.

**Acceptance Criteria**:
- [ ] `FormatSpec::accepts_schema` and `ROADMAP_V2_SCHEMA` exist;
      `check_schema` uses them; `roadmap/v3` and a missing `schema` still
      get the `SCHEMA` notice.
- [ ] A fully valid v2 fixture (letter-suffixed tag, `None` in Left open, a
      cross-repo dependency, a `**Downstream:**` line, free prose) validates
      with no findings.
- [ ] One test per row of the design's FC21 table produces exactly that
      finding, at error level, its message starting
      `[FC21] milestone '<tag>: <title>'` (the non-item heading row names
      the heading): missing Outcome, empty Outcome, Evidence with no clause,
      missing Evidence, missing Left open, empty Dependencies, a continued
      Dependencies line, `ZZ9` unknown, `None, AB1`, Status
      `Done -- shipped`, missing Status, duplicate tag `AB1`, and `### AB2:`.
- [ ] A v2 file whose `### Feature 1:` items carry no Outcome or Evidence
      fails; the same file at `roadmap/v1` produces the findings it did
      before this change.
- [ ] `shirabe validate` over every `ROADMAP-*.md` under `crates/` and
      `skills/` yields the same findings before and after the change
      (compared by a test or a recorded run).
- [ ] `shirabe transition` takes a v2 fixture Draft to Active to Done and
      refuses Active to Draft.
- [ ] `--check FC21` selects the check; `cargo test` passes.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `crates/shirabe-validate/src/formats.rs`, `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/validate.rs`

### Issue 3: feat(populate): render milestone outcomes and prefixed-tag edges

**Goal**: `shirabe roadmap populate` renders a v2 milestone's description
cell and issue body from its Outcome, and draws dependency edges for
prefixed tags on both schema versions.

**Acceptance Criteria**:
- [ ] `populate --no-issues` on a v2 fixture renders each description cell
      from the Outcome; no Evidence or Left open text appears anywhere in
      the table.
- [ ] On a roadmap of either version with `### AB1:` and `### AB2:` and
      `**Dependencies:** AB1` on the second, the table lists `F1` in the
      second row's Dependencies cell and the diagram has `F1 --> F2`, and
      `shirabe validate` passes on the result.
- [ ] Populate output on every existing v1 fixture whose dependencies name
      only `Feature N` is byte-identical to before.
- [ ] A Dependencies entry naming a tag no item carries draws no edge and
      adds nothing to the cell.
- [ ] In `--issues --dry-run` mode, a v2 milestone's issue body carries its
      Outcome and none of its Evidence or Left open text; a v1 feature's body
      is unchanged.
- [ ] `feature_refs_in` is replaced by `dependency_positions`; its existing
      tests move with it and still pass.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `crates/shirabe/src/populate.rs`, `crates/shirabe/tests/populate_cli.rs`

### Issue 4: feat(coordinate): read any roadmap's dependencies and status as a person would

**Goal**: `lib_roadmap_features` and `pick-facts.sh` apply the PRD's R10
rules, so the picker's blocked list matches a person's reading of older
roadmaps and milestone roadmaps alike.

**Acceptance Criteria**:
- [ ] `lib_roadmap_features` prints `{number, id, title, status, finished,
      done, dependencies}`; `finished` is true for a status starting `Done`
      or `Shipped` followed by end of line or a character other than a
      letter, digit or hyphen; `done` adds `Dropped` the same way.
- [ ] A fixture roadmap under `skills/coordinate/scripts/testdata/` with a
      committed expected-facts file covers: paragraphs ending at a blank
      line, at the next field and at a heading; a mention in nested
      parentheses; unbalanced parentheses; each soft marker; a sentence
      opening `Soft`; a self-mention; another roadmap's tag; a `None`
      paragraph with tags after it; statuses `Done`, `Done.`,
      `Done -- shipped in #12`, `Shipped (#34)`, `Dropped`, `Doneness`,
      `done`, `Obsolete` and a missing Status; a sub-lettered tag; a
      non-item `###` heading; a finished item with an unfinished
      dependency; a dependency on a Dropped item; `Feature 2`,
      `Features 1, 2 and 3`, `F2`, and `Feature 2` on a prefixed roadmap;
      and `### AB1:` and `### AB2:` with `**Dependencies:** AB1`, where the
      second item is `blocked_by` `[1]` while `AB1` isn't finished.
      The test compares every item's `blocked` and `blocked_by` with the
      expected file.
- [ ] A dependency paragraph over 4 KB makes `lib_roadmap_features` exit
      non-zero with a message naming the item.
- [ ] `pick-facts.sh` never marks a done unit blocked, gives it
      `blocked_by: []`, and counts a dependency satisfied only when it is
      `finished`; its existing test suite passes with only the assertions
      this changes updated.
- [ ] `closeout-read_test.sh`, `progress-view_test.sh` and
      `pick-facts_test.sh` pass under `/bin/bash` 3.2 on macOS.

**Dependencies**: None

**Type**: code
**Files**: `skills/coordinate/scripts/record-common.sh`, `skills/coordinate/scripts/pick-facts.sh`, `skills/coordinate/scripts/pick-facts_test.sh`

### Issue 5: feat(coordinate): record landed work on Delivered, never on Outcome

**Goal**: `roadmap-status.sh --unit` writes `**Delivered:**` and leaves
every `**Outcome:**` line alone, and `--confirm` accepts an annotated Done.

**Acceptance Criteria**:
- [ ] On a v2 item with a two-line `**Outcome:**`, a wrapped `**Needs:**`
      and an earlier `**Delivered:**`, `--unit` leaves the Outcome lines
      byte for byte, removes Needs and the old Delivered with their wrapped
      lines, and writes `**Status:** Done` then `**Delivered:** <text>`.
- [ ] On a v1 item it writes `**Delivered:**`, not `**Outcome:**`, and any
      `**Outcome:**` line in the file is unchanged.
- [ ] On an item whose Status reads `Done -- shipped` or `Dropped`, `--unit`
      exits 65 and writes nothing; `--confirm` succeeds once the roadmap
      reads `Done -- shipped in #12`.
- [ ] A Delivered text containing `&`, `\` and regex characters lands as
      written; an `--outcome` with a carriage return exits 64.
- [ ] `roadmap-status_test.sh` and `writeback_engine_test.sh` pass under
      `/bin/bash` 3.2; the coordinate skill's prose and record template say
      the text lands on `**Delivered:**` and names only public pull
      requests in a public roadmap.

**Dependencies**: Blocked by <<ISSUE:4>>

**Type**: code
**Files**: `skills/coordinate/scripts/roadmap-status.sh`, `skills/coordinate/scripts/roadmap-status_test.sh`, `skills/coordinate/scripts/writeback_engine_test.sh`, `skills/coordinate/SKILL.md`, `skills/coordinate/references/record-template.md`

### Issue 6: docs(roadmap): milestones by default, the Done rule, and sharpen in place

**Goal**: The roadmap format reference defines milestone roadmaps, and
`/roadmap` drafts them, judges them, and offers to sharpen an Active one
in place.

**Acceptance Criteria**:
- [ ] `roadmap-format.md` has a milestone section with the R2 grammar and a
      worked milestone, the four Status values, a Done rule naming the
      three verdicts, that either verified verdict sets Done, that
      follow-ups are added in the same edit, and that a merge, tests or an
      artifact are not Evidence; the Active edit rules with the amendment
      line `- YYYY-MM-DD: <tag> Outcome amended -- <what changed and why>`;
      FC21 under validation; and the one-line migration note.
- [ ] Phase 3's template writes `schema: roadmap/v2` and the R2 fields;
      phases 1 and 2 ask for an outcome and evidence per item; phase 4's
      jury names a mechanism Outcome, an author-only or merge, test-run or
      artifact Evidence clause, and a Left open holding part of the Outcome
      as findings that send the draft back, and says Evidence is not a
      requirement.
- [ ] `SKILL.md`'s Active-roadmap resume row offers "sharpen one
      milestone's Evidence or Left open in place" and "start a new
      roadmap" on `roadmap/v2`, and only the second on `roadmap/v1`;
      `references/phases/sharpen.md` holds the procedure, ending in
      `shirabe validate` and a check that only that field's lines changed.
- [ ] `evals/evals.json` gains a milestones-by-default scenario and a
      sharpen scenario; `scripts/check-skill.sh roadmap` and
      `scripts/check-skill.sh coordinate` pass.
- [ ] `docs/guides/RELEASE-NOTES-milestone-format.md` covers the new
      schema, FC21, the picker's wider reading, populate drawing edges for
      prefixed-tag dependencies, the Delivered line, and the migration of a
      roadmap in the interim spelling.
- [ ] `shirabe validate` passes on every changed doc.

**Dependencies**: Blocked by <<ISSUE:2>>, <<ISSUE:5>>

**Type**: docs
**Files**: `skills/roadmap/references/roadmap-format.md`, `skills/roadmap/SKILL.md`, `skills/roadmap/references/phases/phase-1-scope.md`, `skills/roadmap/references/phases/phase-2-discover.md`, `skills/roadmap/references/phases/phase-3-draft.md`, `skills/roadmap/references/phases/phase-4-validate.md`, `skills/roadmap/references/phases/sharpen.md`, `skills/roadmap/evals/evals.json`, `docs/guides/RELEASE-NOTES-milestone-format.md`

## Implementation Sequence

Critical path: Issue 1, then Issue 2, then Issue 6. Issue 3 follows Issue 1
in parallel with Issue 2. Issues 4 and 5 run beside the Rust work from the
start, Issue 5 after Issue 4, and both must land before Issue 6 documents
them.

---
schema: prd/v1
status: Accepted
problem: |
  A roadmap item says what gets built, not what someone can do once it
  ships or how anyone other than its author would check that, so a merge
  ends up standing in for done. The validator has nothing to flag, the
  coordinator's picker misreads the dependency and status lines real
  roadmaps carry, its status writer would overwrite an outcome line, and an
  Active roadmap's checks can't be sharpened without starting over.
goals: |
  Roadmap items are milestones by default, with an Outcome, Evidence, Left
  open and Dependencies and a written rule for when one is Done; the
  validator fails a milestone missing its Outcome or Evidence by name; every
  roadmap reader, the coordinator's picker included, reads milestones and
  older roadmaps by one stated set of rules; and an Active roadmap's
  Evidence and Left open can be sharpened in place.
upstream: docs/briefs/BRIEF-milestone-format.md
---

# PRD: milestone-format

## Status

Accepted

## Problem Statement

A roadmap item today is a heading, a Needs line, a Dependencies line and a
Status line, followed by whatever prose the author wrote. Nothing in the
format asks for the outcome the item exists to deliver, or for a check that
someone other than the session that built it could run against the shipped
result. Item bodies drift toward mechanism, the merge becomes the only
evidence on hand, and items get marked Done with their outcome unmet, or
keep reading "Not started" long after their outcome shipped by another
route.

The tools inherit the gap. `shirabe validate` can't flag an item that names
no outcome, because there's no field for one. The coordinator's picker reads
only `Feature N` dependencies on the first line of a Dependencies entry, and
treats an item as finished only when its Status is exactly `Done`. Roadmaps
already in use name items with prefixed tags (`AB1`, `AB10a`), wrap a
dependency list over several lines of prose with explanations and soft
dependencies in it, and write statuses like `Done -- shipped in #12` or
`Shipped (#34)`. On those roadmaps the picker offers work whose
prerequisites haven't landed and holds back work whose prerequisites have.
The coordinator's status writer records merged pull requests on an
`**Outcome:**` line and deletes any existing one, which on an
outcome-shaped item would erase the outcome. And an Active roadmap's
feature list is locked, so tightening one item's check means a new roadmap.

## Goals

An author who runs `/roadmap` gets items written as milestones without
asking: each says who can do what once it lands (Outcome), how someone other
than the author will check it (Evidence), which decisions belong to the
session that does the work (Left open), and which milestones it needs
(Dependencies). The rule for when a milestone is Done sits in the format
reference, where authors and reviewers read it.

`shirabe validate` fails a milestone roadmap whose item lacks an Outcome or
Evidence, naming the item, the way it fails a missing section today.

A coordinator driving any roadmap, milestone or older, computes the same
blocked list a person reading the roadmap would, by the rules in R10, and
never overwrites an item's Outcome when it records what merged.

An author can sharpen one milestone's Evidence or Left open in place on an
Active roadmap and the result still validates.

## User Stories

- As a maintainer sequencing a new initiative, I want `/roadmap` to hand me
  milestones with an Outcome, Evidence, Left open and Dependencies under
  `schema: roadmap/v2`, so that every item can be judged by someone other
  than whoever builds it.
- As a maintainer editing a milestone roadmap, I want `shirabe validate` to
  name the milestone I left without Evidence, so that the gap is caught
  before review rather than at the verdict.
- As a maintainer of an older roadmap, I want `shirabe validate` and
  `shirabe roadmap populate` to behave exactly as they did, apart from
  prefixed-tag dependencies now drawing their edges, so that nothing I
  haven't migrated breaks.
- As a coordinator session driving a roadmap tagged `AB1`, `AB2`, with
  wrapped dependency prose and statuses like `Done -- shipped in #12`, I
  want my blocked list to match a person's reading of the roadmap, so that
  I never dispatch work whose prerequisites haven't landed or hold back
  work whose prerequisites have.
- As a coordinator recording that a milestone's work merged, I want the
  merged pull requests recorded without touching the milestone's Outcome,
  so that the outcome stays the thing the verdict is judged against.
- As a reviewer deciding whether a milestone is Done, I want the rule for
  Done written in the format reference, so that I judge the work against
  its Evidence rather than against whether it merged.
- As a maintainer partway through an initiative, I want `/roadmap` on my
  Active roadmap to offer to sharpen one milestone's Evidence in place, so
  that a check that can't be judged as written gets fixed without starting
  a new roadmap.

## Requirements

### The format

**R1. Milestone roadmaps are marked by their schema.** A roadmap whose
frontmatter reads `schema: roadmap/v2` is a milestone roadmap: every item in
its Features section is a milestone and the milestone checks (R5, R6) apply.
A `roadmap/v1` roadmap keeps today's format and checks. Any other schema
value, or no `schema` key, keeps today's behaviour: a `SCHEMA` notice and
no structural checks.

**R2. A milestone's grammar.** In a `roadmap/v2` Features section:

- An item heading is `### <tag>: <title>` with a non-empty title, where
  `<tag>` matches `Feature [1-9][0-9]*` or `[A-Za-z]+[0-9]+[a-z]?` (for
  example `Feature 3`, `AB1`, `AB10a`). Any other `###` heading is not an
  item and ends the item before it; on a `roadmap/v2` roadmap the
  validator reports it (R6), so a mistyped heading can't hide a milestone
  from the checks. The grammar includes every heading today's readers
  accept.
- A field line starts at column 0 with `**<Name>:**`. A field's value is
  the text after the marker plus the lines below it, up to the first blank
  line, the next field line or the next heading. A value is empty when it
  holds no non-whitespace character.
- Fields, written in this order (the validator checks presence, not
  order):
  - `**Outcome:**` -- who can do what, end to end, that they couldn't
    before; for a removal, migration or contract, the invariant that holds.
  - `**Evidence:**` -- one or more clauses, each a line below the marker
    starting `- ` at column 0 with text after it, plus any indented lines
    that continue it. Clauses end with the field, so a `- ` line after a
    blank line is not a clause. Each clause names who
    checks, from what starting state, and what observable result shows the
    Outcome is met; that content is judged by `/roadmap`'s jury (R13), not
    by the validator.
  - `**Left open:**` -- the how-decisions left to the session that does
    the work, or `None`.
  - `**Needs:**` -- optional, as today.
  - `**Dependencies:**` -- `None` alone, or a comma-separated list (which
    may wrap) whose every entry is the tag of another milestone in this
    roadmap or a cross-repo issue reference `<owner>/<repo>#<n>`.
  - `**Status:**` -- exactly `Not started`, `In progress`, `Done` or
    `Dropped`.
  - `**Delivered:**` -- optional; the pull requests that delivered the
    work.
- Other field lines (for example `**Downstream:**`) and free prose after a
  blank line are allowed and belong to no milestone field.

The spelling matches the interim spelling milestone roadmaps already use,
so such a roadmap becomes a valid `roadmap/v2` document by changing its
schema line alone.

**R3. The Done rule.** The format reference states that a milestone is Done
only on a verification verdict from the human or the coordinator that
dispatched the work, never from the session that delivered it; that the
verdict is one of changes needed (the milestone stays In progress),
verified with follow-ups, or verified; that either verified verdict sets
Done, and every follow-up milestone the verdict names is added to the
roadmap in the same edit that sets Done; and that a merged pull request,
passing tests or an artifact existing is not Evidence. The rule is
documentation: no tool in this change enforces it.

**R4. What may change on an Active milestone roadmap.** The format
reference's edit rules say an Active `roadmap/v2` roadmap may change in
place in exactly these ways: a milestone's Evidence and Left open may be
sharpened; Status and Delivered change as work progresses; follow-up
milestones are added in the verdict edit that names them; and narrowing an
Outcome takes a line in the Progress section reading
`- YYYY-MM-DD: <tag> Outcome amended -- <what changed and why>`. Any other
change to the Features section (adding, removing, reordering or retitling
a milestone, changing its Dependencies or widening its Outcome) or to the
Sequencing Rationale needs a new roadmap. These rules are documentation:
no code enforces the old lock or the new rules.

### The validator

**R5. Missing Outcome or Evidence fails validation by name.** On a
`roadmap/v2` roadmap, `shirabe validate` reports one error-level finding
per milestone whose Outcome is missing or empty, and one per milestone
whose Evidence is missing or has no clause. Each finding's message names
the milestone's tag and title and the missing field, and the command exits
non-zero.

**R6. The rest of the milestone shape is checked.** On a `roadmap/v2`
roadmap, the validator also reports an error-level finding, naming the
milestone and the field, when:

- Left open or Dependencies is missing or empty (`None` is not empty);
- Status is missing or isn't one of the four values in R2;
- a Dependencies entry is neither `None` alone, the tag of another
  milestone in the roadmap, nor a cross-repo reference;
- two milestones carry the same tag;
- a `###` heading in the Features section doesn't match the item grammar
  of R2.

**R7. Version 1 is untouched.** Every `roadmap/v1` document validates with
the same findings at the same severities before and after this change, and
`/roadmap` offers no sharpen-in-place option on one (R13).

**R8. Lifecycle is unchanged.** `shirabe transition` moves a `roadmap/v2`
roadmap Draft to Active to Done under the same rules as a `roadmap/v1` one,
and the lifecycle checks treat the two alike.

### The roadmap readers

**R9. One parse of a milestone.** The shared roadmap parser returns each
milestone's Outcome, Evidence clauses, Left open and Delivered as their own
values, by the field extents of R2; none of their text appears in another
field or in the item's free description. On a `roadmap/v2` roadmap,
`shirabe roadmap populate` renders each description cell from the
milestone's Outcome, joined onto one line and passed through the same
summarizing step populate applies to description text today.

**R10. The picker's reading of any roadmap.** On a roadmap of either
version, the coordinator's picker reads items and their blocked state by
these rules, applied in this order:

1. Items are the `###` headings of R2's grammar inside `## Features`.
2. An item is finished when its Status starts with `Done` or `Shipped`
   followed by the end of the line or a character other than a letter,
   digit or hyphen; closed when it starts with `Dropped` the same way; and
   neither when its Status line is missing or reads anything else
   (`Obsolete`, `Backlog`, `Deferred` included). Matching is
   case-sensitive.
3. The Dependencies paragraph is the `**Dependencies:**` line and the lines
   below it, up to a blank line, the next field line or the next heading,
   joined with spaces. A paragraph whose first word is `None` names no
   dependency.
4. A tag followed by optional spaces, an optional `(`, optional spaces and
   then `soft`, `optional`, `preferred`, `sequencing-preferred` or
   `paced by` (case-insensitive) is a soft mention. The marker applies to
   that one tag only, not to a list before it.
5. Text inside parentheses is removed, innermost pair first, until none is
   left.
6. The rest is split into sentences at `.` or `;` followed by whitespace;
   a sentence whose first word is `Soft` (case-insensitive) is dropped.
7. What remains names a dependency through `Feature N`, `Features N, M and
   K`, `F<N>` (each resolving to the item tagged `Feature N` when one
   exists, else to the Nth item) or a whole-word tag (not preceded or
   followed by a letter or a numeral) equal to another item's heading
   tag. Soft mentions, the item's own tag, and tags no item
   of this roadmap carries (another roadmap's items, or typos) are not
   dependencies.
8. A dependency is satisfied only when the depended-on item is finished. An
   item that is finished or closed is never blocked; any other item is
   blocked while one of its dependencies is unsatisfied, and its
   `blocked_by` lists those items' 1-based positions, ascending, each
   once.

**R11. Prefixed tags resolve in populate and the validator too.** A
Dependencies entry naming a prefixed tag resolves to that item in
populate's table and diagram on both versions (populate reads the
Dependencies value as it does today; R10's soft and parenthetical rules
are the picker's alone), and in the validator's
milestone check (R6), which runs on `roadmap/v2` only, so R7 holds.
`Feature N` keeps resolving as in R10 rule 7.

**R12. The status writer never touches an Outcome.** When the coordinator
records that a feature's work merged, on a roadmap of either version, it
sets the Status line to `Done`, writes `**Delivered:** <text>` on the line
after it, removes any earlier `**Delivered:**` field and the `**Needs:**`
field in that item (each with its wrapped lines), and leaves every `**Outcome:**` line and every other
line as it was. It still refuses an item that is already finished or
closed. When it runs at all is unchanged; making it obey R3 is later work.

### The authoring workflow

**R13. Milestones by default.** `/roadmap` writes `schema: roadmap/v2` and
drafts every item with the fields of R2. Its scoping and research phases
collect an outcome and evidence per item. Its jury reports, as findings
that send the draft back for revision, an Outcome that names mechanism
(a command, file or component to build) rather than what someone can do,
an Evidence clause that only the author could judge or that is a merge, a
test run or an artifact existing, and a Left open that holds part of the
Outcome.

**R14. Sharpen in place.** Run on an Active `roadmap/v2` roadmap, `/roadmap`
offers two choices: sharpen one milestone's Evidence or Left open in place,
or start a new roadmap. Choosing to sharpen asks which milestone and which of the two fields,
rewrites only that field's lines in that milestone, and leaves the roadmap
Active and passing `shirabe validate`. A Draft roadmap is still edited
freely through `/roadmap`'s usual resume; a Done roadmap is not edited.

### Constraints

**R15. Bash 3.2.** Every shell script this changes runs under `/bin/bash`
3.2 with the macOS userland and under the Linux runners CI uses.

**R16. Verified by suites, not evals.** The change is verified by the
repository's script and Rust test suites and CI. Skill evals may be added
for the new behaviour but are not the definition of done.

## Acceptance Criteria

The validator, populate, picker and status-writer criteria run as tests in
the repository; the `/roadmap` criteria are walkthroughs a person runs in a
fresh session; the corpus criterion is a manual check outside CI.

- [ ] A `roadmap/v2` fixture whose milestones carry every field of R2 (a
      prefixed tag with a letter suffix, `None` in Left open, a cross-repo
      dependency, a `**Downstream:**` line and free prose included)
      validates with no findings. (R2, R5, R6)
- [ ] Once this change has merged, in a clean checkout of the default
      branch, `shirabe validate` on a `roadmap/v2` roadmap with one
      milestone missing Evidence exits non-zero and its output names that
      milestone's tag and title. (R5)
- [ ] One fixture each, every other milestone valid, fails naming the
      milestone and field: Outcome missing; Outcome empty; `**Evidence:**`
      with no clause beneath it; Left open missing; Dependencies empty;
      Status `Done -- shipped`; Status missing; a Dependencies entry `ZZ9`
      no milestone carries; Dependencies `None, AB1`; two milestones tagged
      `AB1`; a heading `### AB2:` with an empty title. (R2, R5, R6)
- [ ] A `roadmap/v2` fixture with `### Feature 1:` items carrying no
      Outcome or Evidence fails; the same file with `schema: roadmap/v1`
      validates as it did before; with `schema: roadmap/v3` it gets the
      `SCHEMA` notice. (R1)
- [ ] Every `roadmap/v1` fixture in the repository yields the same findings
      at the same severities before and after the change. (R7)
- [ ] `shirabe transition` takes a `roadmap/v2` fixture Draft to Active to
      Done, and refuses Active to Draft, as it does for `roadmap/v1`. (R8)
- [ ] A parser test over a milestone with a three-line Outcome, three
      Evidence clauses (one wrapped), a two-line Left open and a Delivered
      line returns each field whole and none of their text in the
      description. (R9)
- [ ] `shirabe roadmap populate --no-issues` on a `roadmap/v2` fixture
      renders each description cell from the Outcome, with no Evidence or
      Left open text anywhere in the table. (R9)
- [ ] On a roadmap of either version whose items are `### AB1:` and
      `### AB2:` with `**Dependencies:** AB1` on the second, populate draws
      the `F1 --> F2` edge and lists `F1` in the second row's Dependencies cell, and the
      picker reports the second item `blocked_by` `[1]` while `AB1` isn't
      finished. (R10, R11)
- [ ] A picker fixture roadmap, committed with its expected blocked set,
      exercises every rule of R10: a wrapped paragraph ending at a blank
      line, one ending at the next field, one ending at a heading; a
      mention inside nested parentheses; each soft marker; a sentence
      opening `Soft`; a self-mention; a tag of another roadmap; a `None`
      paragraph with tags after it; statuses `Done`, `Done.`,
      `Done -- shipped in #12`, `Shipped (#34)`, `Dropped`, `Doneness`,
      `done`, `Obsolete` and a missing Status; a sub-lettered tag; a non-item
      `###` heading; a finished item with an unfinished dependency; and a
      dependency on a Dropped item; and dependencies written `Feature 2`,
      `Features 1, 2 and 3`, `F2`, and `Feature 2` on a roadmap whose items
      are prefixed (resolving to the second item). The fixture's expected
      file lists every item's `blocked` and `blocked_by`, and the picker's
      facts equal it. (R10)
- [ ] The human runs the picker over every roadmap in a real roadmap
      corpus's current default branch and finds the set of items it lists
      as blocked equals the set a hand-made table lists. Manual, outside CI; the corpus and
      table stay outside this repository. (R10)
- [ ] `roadmap-status.sh --unit` on a `roadmap/v2` item with a two-line
      `**Outcome:**` and an earlier `**Delivered:**` line leaves the Outcome
      lines byte for byte, replaces the Delivered line with one after the
      Status line, and removes Needs; on a `roadmap/v1` item it writes
      `**Delivered:**`, not `**Outcome:**`, and leaves any `**Outcome:**`
      line in the file untouched; on an item whose Status already reads
      `Done -- shipped` or `Dropped` it exits 65 and writes nothing. (R12)
- [ ] The format reference contains the four fields with the grammar of R2,
      the four Status values, a Done rule naming the three verdicts, that
      either verified verdict sets Done, that follow-ups are added in the
      same edit, and that a merge, tests or an artifact are not Evidence,
      and the edit rules of R4 including the amendment line's shape. (R3, R4)
- [ ] `/roadmap`'s draft template writes `schema: roadmap/v2` and the R2
      fields; its scoping and research phase instructions ask for an
      outcome and evidence per item; and its jury instructions name the
      three findings of R13 as findings that send the draft back. (R13)
- [ ] Walkthrough: a fresh session runs `/roadmap` on a sample topic in a
      scratch repository; every item in the draft has Outcome, Evidence,
      Left open and Dependencies, and `shirabe validate` passes on it.
      (R13)
- [ ] Walkthrough: a fresh session runs `/roadmap` on an Active
      `roadmap/v2` roadmap, is offered "sharpen one milestone's Evidence or
      Left open in place" and "start a new roadmap", sharpens one
      milestone's Evidence, and `git diff` shows only that milestone's
      Evidence lines changed, the frontmatter still reads `status: Active`,
      and `shirabe validate` passes. Sharpening Left open runs the same
      path and isn't walked separately. (R14)
- [ ] The changed shell scripts' test suites pass under `/bin/bash` 3.2 on
      macOS and in CI on Linux. (R15)
- [ ] The pull request body says the change was verified with script
      suites and CI, not skill evals. (R16)

## Out of Scope

- Recording verdicts, and changing the completion cascade or the
  coordinator so that no tool sets Done on a merge. R3 states the rule;
  making every tool obey it is later work.
- Checking Evidence quality in the validator. It checks that clauses
  exist; whether each names who checks, from what state and what result is
  the jury's call.
- Rewriting existing roadmaps into `roadmap/v2`, or any notice nudging a
  `roadmap/v1` roadmap to migrate. Readers learn to read older roadmaps as
  written; migrating each one is separate work.
- Sharpen-in-place on a `roadmap/v1` roadmap.
- Plans built from milestones and how `/plan` and `/review-plan` treat
  them.
- Resolving dependencies that point into another roadmap. The picker sees
  only the roadmap it drives; a cross-roadmap dependency stays prose and
  doesn't block.
- Status words beyond `Done`, `Shipped` and `Dropped` in older roadmaps.
- Any change to koto or niwa.

## Decisions and Trade-offs

**A new schema version rather than detecting milestones by content.**
Alternatives: require the fields on every roadmap (breaks every roadmap
written so far), or require them once any item carries an Outcome (roadmaps
that recorded merged pull requests on `**Outcome:**` would fail).
`roadmap/v2` makes the switch explicit, keeps every `roadmap/v1` document
valid, and gives a migration a one-line marker. This closes the brief's
question on schema versioning.

**Readers learn prefixed tags rather than roadmaps being normalized to
`Feature N`.** Normalizing would rewrite tags under running coordinators,
which match held work by tag. Teaching the readers costs one resolution
rule they all share.

**Keep the interim spelling.** Roadmaps already written in milestone form
use `**Outcome:**`, `**Evidence:**`, `**Left open:**`, `**Dependencies:**`
naming `Feature N`, a bare Status word and a `**Delivered:**` line. Matching
it means those roadmaps migrate by changing one line, and the status
writer's old `**Outcome:**` line becomes `**Delivered:**`, which is what it
always recorded.

**`Shipped` reads as finished in the picker; nothing else new does.**
Older roadmaps use `Shipped (...)` for delivered items, which a reader
treats as finished; `Obsolete`, `Backlog` and `Deferred` carry no
consistent meaning, so they read as not finished. This closes the brief's
question on status words. New roadmaps use only the four values of R2.

**A Dropped dependency keeps its dependent blocked.** That's the picker's
behaviour today, and a dependent of dropped work needs a person to decide
whether it still makes sense; reading it as unblocked would dispatch it
silently.

**Soft and parenthetical mentions don't block, in the picker only.** Older
roadmaps explain dependencies in prose, mentioning items that don't gate
the work. The picker has to read those as a person would. The milestone
format avoids the problem instead: its Dependencies line holds tags only,
and the validator checks each one.

**A finished item is never blocked.** It is never picked, and reporting it
blocked by an unfinished dependency only makes the blocked list disagree
with a person's reading.

**Field order is the format's, not the validator's.** Authors and the
draft template write the fields in R2's order; the validator checks
presence and content, so an item written in another order still parses
and validates.

---
schema: brief/v1
status: Done
problem: |
  A shirabe plan or roadmap can have a perfectly self-consistent table and
  diagram -- FC07 reconciles every key, edge, and class-vs-Status pass --
  and still ship a Legend prose line that disagrees with the actual
  `classDef` set in the diagram fence right above it. The Legend lists
  colors and class names a human reader is supposed to take as the
  canonical key for the diagram, but nothing reconciles it against the
  diagram's declarations or the canonical class palette. Drift here
  silently breaks the diagram's readability for every downstream consumer.
outcome: |
  A doc author who edits a plan or roadmap sees the validator surface a
  specific notice the moment the Legend names a class with no matching
  `classDef`, or the diagram declares a `classDef` the Legend forgot to
  list, or the Legend uses a normalization variant the `classDef` set does
  not match (`needs-design` vs `needsDesign`). The notice level keeps CI
  green while the corpus reconciles; promotion to error is a one-line
  change once the docs are clean. The Legend becomes a trustworthy index
  into the diagram by construction.
upstream: docs/designs/DESIGN-roadmap-plan-standardization.md
---

# BRIEF: legend-vs-classdef-reconciliation

## Status

Done

## Problem Statement

shirabe's validator reconciles plan and roadmap docs along two axes today
and stops there. FC07 reconciles the intra-document table-and-diagram
pair across node set, edge set, and class-vs-Status. FC09 reconciles the
doc against external GitHub state. Both bound the surface they cover
precisely; neither inspects the Legend prose that sits below most
Dependency Graph blocks and tells the human reader what each color in
the diagram means.

The Legend convention is documented in `references/dependency-diagram.md`
(the Legend section near the end). It instructs authors to add a line of
the shape:

```
**Legend**: Green = done, Blue = ready, Yellow = blocked, Purple = needs-design, Orange = tracks-design/tracks-plan
```

immediately following the diagram. Roadmap diagrams that use pipeline-
stage classes extend the legend accordingly. Nothing in the validator
reads this line. Nothing checks that the class names listed in the
Legend correspond to `classDef` declarations the diagram actually makes.
Nothing checks that every `classDef` a reader will see in the diagram is
named in the Legend so the reader can decode the color.

The drift surface is real and currently active in the committed corpus.
The roadmap-profile canonization that landed earlier in this milestone
introduced pipeline-stage classes (`needsPlanning`, `needsExplore`,
`needsSpike`) that did not exist before. Committed docs with Legends
written against the older spec silently fell out of agreement with
diagrams that use the newer classes, and nothing catches it. The
canonical Legend example in `references/dependency-diagram.md` itself
uses hyphenated class names (`needs-design`) while every `class`
statement and `classDef` declaration in the codebase uses camelCase
(`needsDesign`). That normalization mismatch has been live for months
because no check reconciles the two surfaces, and a reader following the
documented convention would write a Legend that disagrees with the
diagram conventions on its own page.

A future reader who trusts the Legend as the index into the diagram is
led to the wrong picture. A reader who trusts the diagram (because the
classDef declarations are right there next to the class assignments) has
to manually filter the Legend prose, deciding which entries reflect
reality and which entries are stale or normalization-skewed. The longer
the corpus accumulates this kind of drift before any check fires, the
more expensive a one-shot reconciliation becomes -- precisely why this
third intra-document axis is shaped as a staged increment behind a
notice-then-error rollout rather than a strict-from-day-one error check.

FC07 deliberately left this surface untouched. Its sub-DESIGN's Decision
4 bounded the FC07 contract to the four parallel views the diagram
extractor produces (`nodes`, `edges`, `class_assignments`, `class_defs`),
not to prose that sits outside the mermaid fence. The Legend is prose
in the body, not part of the diagram, and the FC07 sub-DESIGN named
explicitly that prose-vs-diagram reconciliation belongs to a separate
follow-on check rather than smuggling into FC07's contract. FC08 is
that follow-on.

The friction the gap exposes is not "build new infrastructure." FC07
already added the `class_defs: HashSet<String>` field on the `Diagram`
struct -- the exact surface FC08 consumes to do its work. FC07 already
landed the dispatch arm for plan and roadmap profiles in `validate_file`
where FC08 slots in alongside FC05/FC06/FC07. The unmet need is a small
Legend-prose parser plus a reconciliation function whose contract crosses
the prose-vs-diagram seam cleanly -- naming each defect by class name
and the side that omits it, no false positives on absent Legends (the
convention is optional), no panics on malformed Legend input.

## User Outcome

A doc author edits a plan or roadmap and the validator surfaces a
specific notice the moment the Legend prose line and the diagram's
`classDef` set fall out of agreement. A Legend that names a class with
no matching `classDef` declaration fires a notice naming the class. A
`classDef` that the Legend omits fires a notice naming the class (with
the canonical Status-palette exception so authors do not have to spell
out every Status entry on every doc). A Legend that uses the hyphenated
form against a camelCase `classDef` fires a notice naming both forms
and recommending the camelCase normalization the codebase uses. The
notices match the FC05/FC06/FC07/FC09 voice, name the specific defect
site, and the fix path is mechanical.

A doc with no Legend line at all proceeds without a notice. The Legend
is an optional convention -- a roadmap or plan that omits it is well-
formed -- and FC08 does not invent the line. The notice fires only when
a Legend is present and disagrees with the diagram beside it.

A malformed Legend (missing colon, trailing comma, an entry without an
`=` sign, an entry with extra whitespace, an entry that names a color
with no class) does not panic the validator. The parser is total over
arbitrary line input: it extracts the well-formed `<Color> = <name>`
pairs it can recognize and silently drops the rest. The reconciliation
then runs against whatever pairs the parser recovered, surfacing the
agreement defects without crashing on the prose noise.

Because the check ships as a notice rather than an error, CI stays green
while the existing committed corpus reconciles row by row as authors
touch each plan and roadmap. The volume of notices drops as the corpus
is cleaned up, and a maintainer flips the one-line `is_notice` membership
in the same PR that finishes the cleanup to promote the check to error-
level. The shipping path does not force a one-shot retrofit and does
not block authors mid-edit, and the corpus gets a reliable contract
once the cleanup is done.

A downstream sub-DESIGN author landing on this brief cold picks up the
Legend-extraction pattern, the normalization rule for hyphen-vs-camel
class names, the canonical-palette tolerance for the Status set, and the
notice-then-error staging without re-reading the FC07 sub-DESIGN or the
parent PRD. The framing this brief settles -- Legend prose parsed
defensively, reconciled bidirectionally against `Diagram.class_defs`,
notice-level shipping with a one-line promotion seam -- is recorded
here as the boundary the sub-DESIGN refines, not content the sub-DESIGN
has to re-derive.

## User Journeys

The feature is exercised from four entry points. Each names the user,
the trigger that brings them to the check, and the outcome the
validator surfaces.

### Journey 1: Author writes a Legend that names a class with no classDef

A plan author writes a Dependency Graph block, declares two classDefs
(`done` and `ready`), and writes a Legend below it claiming
`Green = done, Blue = ready, Yellow = blocked`. The diagram has no
`classDef blocked` declaration -- the author copied the Legend from
another doc without checking the local diagram. The validator runs
`check_fc08` in the plan arm alongside FC05/FC06/FC07; the extractor
parses the Legend's three color-class pairs, compares each class name
against the diagram's `class_defs` set and the canonical Status palette
(`done`, `ready`, `blocked` are all in the canonical palette), observes
that `blocked` is in the canonical palette but absent from the local
diagram's `class_defs`, and fires a notice naming `blocked` and the
Legend line. The author either removes `blocked` from the Legend or
adds the `classDef blocked` declaration; the next run is clean.

This journey validates that Sub-check A (Legend names a class no
`classDef` declares) fires on the most common defect (the Legend names
classes the diagram does not actually use) and that the canonical
palette gives the author a clear path: either remove the Legend entry
or add the declaration.

### Journey 2: Author declares a classDef the Legend omits

A roadmap author updates a diagram, adds a new `classDef needsExplore`
declaration so a new node can carry that class, but forgets to extend
the Legend. The validator runs `check_fc08`; the extractor parses the
Legend, compares the `class_defs` set against the Legend's class names,
observes that `needsExplore` is declared but not named in the Legend,
and fires a notice naming `needsExplore` and the missing Legend entry.
The author extends the Legend (the documented convention includes
`needs-explore` as an entry); the next run is clean.

The notice does not fire on the canonical Status palette (`done`,
`ready`, `blocked`) -- those names are assumed by every diagram and
the per-doc Legend does not have to spell them out. A `classDef done`
plus a Legend that says only `Green = done` does not fire because the
Legend already names the canonical class. The exception keeps the
notice volume bounded to the actually-novel classes a reader needs
help decoding.

This journey validates that Sub-check B (a `classDef` the Legend does
not name) fires on the pipeline-stage and tracks-prefix classes that
genuinely need Legend entries to be human-readable, without spamming
on the canonical Status palette every doc inherits by default.

### Journey 3: Legend uses hyphenated form against camelCase classDef

A roadmap author follows the documented Legend convention from
`references/dependency-diagram.md` and writes
`**Legend**: Purple = needs-design, Yellow = needs-planning, Red = needs-spike`.
The diagram below declares `classDef needsDesign`, `classDef needsPlanning`,
and `classDef needsSpike` -- the camelCase form the codebase uses
everywhere. The validator runs `check_fc08`; the extractor parses the
Legend, normalizes each Legend name to camelCase, compares against
the `class_defs` set (which uses camelCase), and observes that every
Legend name agrees with a `classDef` only under normalization. The
check fires a notice per affected entry, naming both forms and
recommending the camelCase normalization the codebase uses. The author
rewrites the Legend in camelCase; the next run is clean.

This journey validates that the normalization rule catches the
hyphen-vs-camel drift the documented convention itself introduces. The
notice names both forms so the author sees the exact substitution to
make rather than guessing at which side is canonical.

### Journey 4: Doc with no Legend, or with a malformed Legend, runs clean

A plan author finishes a plan and ships it without a Legend prose line
at all -- the diagram is small, the canonical Status palette is
obvious, no Legend is needed. The validator runs `check_fc08`; no
Legend is found, the reconciliation pass returns without firing a
notice, and the rest of the validation proceeds normally. Separately,
a roadmap author writes a Legend with a typo --
`**Legend**: Green = done, , Blue = ready` (a stray comma producing
an empty entry) -- and the parser silently drops the empty entry,
reconciles the remaining two pairs, and either fires or stays silent
depending on what the diagram actually declares. The validator does
not panic on the malformed input.

This journey validates that the absent-Legend path is silent (the
convention is optional) and that the parser is total over arbitrary
input (defensive parsing keeps the validator robust against prose
noise). A check that fired on every diagram without a Legend would
force every existing diagram in the corpus to add a Legend; a check
that panicked on malformed Legend prose would block every author with
a typo. Both shapes would be the wrong staging.

## Scope Boundary

This brief frames a single validator check, `check_fc08`, that
reconciles each plan or roadmap doc's Dependency Graph Legend prose
line against the diagram's `classDef` declarations and the canonical
class palette in `references/dependency-diagram.md`. It is the second
pillar of intra-document consistency alongside FC07 (table-and-diagram);
together with FC09 (doc-vs-external-state) they form the three pillars
of doc-state reconciliation FC07 introduced and FC09 extended.

The scope holds the following inside:

- The `check_fc08` reconciliation check dispatched in the plan and
  roadmap arms of `validate_file` alongside FC05, FC06, FC07, and FC09,
  structured as bidirectional reconciliation in a single pass over the
  extracted body lines and the existing `Diagram.class_defs` field
  FC07 already produces.
- A Legend prose extractor scoped to the body lines immediately
  following the located Dependency Graph fence. The extractor finds
  a line beginning with `Legend:` or `**Legend**:` (case-sensitive on
  the leading token), parses `<Color> = <name>` pairs separated by
  commas, tolerates surrounding whitespace and the bold-markdown
  wrapper, and produces a Vec of recovered class names. Lines that do
  not match the Legend shape are silently ignored.
- A normalization rule that maps hyphenated class names
  (`needs-design`, `tracks-design`) to their camelCase equivalents
  (`needsDesign`, `tracksDesign`) for the comparison pass. The rule
  is documented as kebab-to-camel at the word boundaries the hyphens
  define; the recommended form in the notice is always camelCase, the
  form the codebase uses in `class` and `classDef` statements.
- A canonical-palette tolerance for the Status set (`done`, `ready`,
  `blocked`). A `classDef` declaring one of these classes does not
  require a corresponding Legend entry; the canonical palette is
  assumed by every diagram. A Legend entry naming one of these classes
  still must correspond to a local `classDef` or the canonical
  palette (so the canonical-palette tolerance does not become a free
  pass for unused entries).
- Bidirectional reconciliation: Sub-check A fires for each Legend
  class name that has no matching `classDef` declaration and is not
  in the canonical palette. Sub-check B fires for each `classDef`
  declaration outside the canonical Status palette that the Legend
  does not name (with normalization applied). Sub-check C fires for
  each Legend name that matches a `classDef` only under normalization,
  recommending the camelCase form.
- Per-defect notice messages in the FC05/FC06/FC07/FC09 voice, naming
  the specific class name, the side that omits it (Legend or
  classDef), and where applicable the normalized form to substitute.
  Bodies match the existing notice voice precisely.
- Notice-level shipping via the existing `is_notice` membership, the
  same one FC07 and FC09 share, with the same one-line promotion seam.
  Promotion to error is a single-arm membership change.
- Bounded behavior over arbitrary input: the Legend parser produces a
  result for any line content without panicking on missing colons,
  empty entries, trailing commas, entries without `=` signs, or
  duplicate entries. The check produces a result with no unbounded
  loops and no allocations proportional to anything outside the
  diagram's own size.
- A downstream sub-DESIGN that picks up the requirements, settles the
  Legend-extraction call site (helper in `mermaid.rs` vs inline in
  `checks.rs`), and tracks against the parent
  `DESIGN-roadmap-plan-standardization.md` Decision 3 staging the same
  way the FC07 and FC09 sub-DESIGNs do.

The scope explicitly excludes:

- **The actual promotion of `check_fc08` to error-level.** Promotion
  happens after the committed corpus is reconciled (zero notice
  volume), in a separate cleanup PR that flips the one-line
  `is_notice` membership. This brief ships the seam, not the flip.
  Same staging shape FC07 and FC09 use.
- **A retrofit of the committed corpus.** The notice-then-error
  rollout exists precisely so corpus reconciliation happens
  incrementally after the check ships. Bulk-fixing the current corpus
  is out; an author who hits a notice fixes it in their own PR.
- **Re-deriving the canonical palette.** The Status set (`done`,
  `ready`, `blocked`) and the pipeline-stage set (`needsDesign`,
  `needsPrd`, `needsPlanning`, `needsSpike`, `needsDecision`,
  `needsExplore`, `tracksDesign`, `tracksPlan`) live in
  `references/dependency-diagram.md`. FC08 reads that file's
  established set; it does not introduce a new palette.
- **Validation of Legend formatting beyond extraction.** Whether the
  Legend uses `**Legend**:` or `Legend:` plain, whether the colors
  are spelled `Green` or `green`, whether the entries are separated
  by `,` or `, ` -- FC08 tolerates these variants in extraction and
  does not fire a notice on formatting. A future formatting check
  is a separate increment outside this scope.
- **Reconciliation across documents.** FC08 is intra-document only --
  each plan or roadmap is reconciled against its own Legend and its
  own diagram. A Legend in one doc is not compared against a `classDef`
  in another doc. Cross-document state lives in FC09's contract.
- **Pipeline-stage class semantics.** FC08 reconciles names, not
  meaning. A diagram that uses `needsExplore` where `needsDesign`
  would be more accurate is not in FC08's scope; FC08 fires only on
  name-set agreement between the Legend and the `classDef` set.

## References

- Parent PRD (R8 staged reconciliation, R20 notice-then-error contract):
  `docs/prds/PRD-roadmap-plan-standardization.md`.
- Parent DESIGN (Decision 3 staging the reconciliation increment behind
  a spike and a notice rollout):
  `docs/designs/DESIGN-roadmap-plan-standardization.md`.
- Parent PLAN (the row that schedules this increment as the FC08 leaf
  node depending on FC07's class-extraction infrastructure):
  `docs/plans/PLAN-roadmap-plan-standardization.md`.
- FC07 sub-DESIGN (the architectural precedent for the
  `class_defs: HashSet<String>` field FC08 consumes and the dispatch
  arm FC08 slots into):
  `docs/designs/current/DESIGN-table-diagram-reconciliation.md`.
- FC07 BRIEF (the tone and shape this brief mirrors):
  `docs/briefs/BRIEF-table-diagram-reconciliation.md`.
- FC09 BRIEF (the staged-notice pattern this brief inherits from):
  `docs/briefs/BRIEF-doc-vs-github-state-reconciliation.md`.
- Canonical dependency-diagram conventions (the Legend convention, the
  canonical Status palette, the pipeline-stage class set, the
  documented hyphenated-vs-camelCase mismatch in the example Legend):
  `references/dependency-diagram.md`.

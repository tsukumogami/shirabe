---
schema: prd/v1
status: Done
problem: |
  shirabe's validator reconciles plan and roadmap docs along the FC07 intra-
  document axis (table-vs-diagram across node set, edge set, and class-vs-
  Status) but does not inspect the Legend prose line that sits below most
  Dependency Graph blocks and tells the reader what each color in the
  diagram means. FC07's contract is bounded to the four parallel views the
  diagram extractor produces; the Legend is prose outside the mermaid fence
  and FC07 deliberately leaves it untouched. The documented Legend
  convention itself ships with a hyphenated-vs-camelCase mismatch the
  codebase has carried for months, and a recent roadmap-canonization that
  introduced pipeline-stage classes silently broke Legends written against
  the older spec. Every plan and roadmap in the corpus is one classDef
  edit away from a Legend that no check fires on.
goals: |
  A doc author who edits a plan or roadmap sees the validator surface a
  specific notice the moment the Legend prose disagrees with the diagram's
  `classDef` declarations or the canonical class palette. FC08 becomes the
  second pillar of intra-document consistency alongside FC07; together
  with FC09 (cross-document) it closes the three drift surfaces the
  validator was supposed to cover. The check ships behind the same notice-
  then-error staging FC07 and FC09 use, with the same one-line `is_notice`
  membership flip promoting it to error once the corpus is reconciled.
  The Legend parser is total over arbitrary input so malformed prose
  never panics the validator, and an absent Legend produces no notice
  because the convention is optional.
upstream: docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md
---

# PRD: legend-vs-classdef-reconciliation

## Status

Done

This PRD picks up the requirements work scoped by
`docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md`. It owns the
contract-level requirements for the FC08 validator check -- the
bidirectional reconciliation between the Legend prose line and the
diagram's `classDef` declarations, the kebab-to-camel normalization
rule, the canonical-palette tolerance for the Status set, the notice-
level rollout via the existing `is_notice` membership, the promotion-to-
error seam, and the bounded-behavior guarantee over arbitrary prose
input. Implementation specifics -- the Legend extractor call site
(helper in `mermaid.rs` vs inline in `checks.rs`), the exact notice
message strings, and the table-driven test layout -- land in a
downstream DESIGN doc and its plan.

The PRD inherits and sharpens the parent
`PRD-roadmap-plan-standardization.md` invariants -- R8 staged
reconciliation, R20 no-day-one-breakage, and R22 public-cleanliness --
without re-litigating them. The BRIEF settles every framing question
(bidirectional reconciliation in one check, canonical-palette tolerance,
defensive parsing of all prose input, notice-then-error staging); this
PRD binds those settlements as numbered requirements with binary
acceptance criteria.

## Problem Statement

The shirabe validator runs three intra-document reconciliation passes
today across the plan and roadmap arms: FC05 (schema-level table
parsing), FC06 (cross-document upstream existence), and FC07 (table-vs-
diagram across four parallel views the diagram extractor produces). The
extractor surfaces `nodes`, `edges`, `class_assignments`, and
`class_defs` parallel sets, and FC07's contract is bounded to
reconciling those views against the parsed table. The Legend prose line
that sits below most Dependency Graph blocks is outside that contract
by deliberate scope choice in FC07's sub-DESIGN.

The Legend convention is documented in `references/dependency-diagram.md`:
authors are instructed to add a line of the shape `**Legend**: Green =
done, Blue = ready, Yellow = blocked, ...` immediately following the
diagram. The line acts as the human-facing index from the diagram's
color palette to the class names, and a downstream reader who does not
have the canonical palette memorized leans on it to decode the diagram.
Nothing reconciles it against the diagram beside it.

Two concrete drift surfaces are currently live:

- **Pipeline-stage class proliferation.** The roadmap-profile
  canonization that landed earlier in this milestone introduced
  pipeline-stage classes (`needsPlanning`, `needsExplore`, `needsSpike`)
  that did not exist before. Committed docs with Legends written
  against the older spec silently fell out of agreement with diagrams
  that use the newer classes. A reader following an outdated Legend
  gets the wrong picture of what each color in the diagram means.
- **Documented-convention normalization mismatch.** The canonical Legend
  example in `references/dependency-diagram.md` itself uses hyphenated
  class names (`needs-design`, `tracks-design`) while every `class` and
  `classDef` statement in the codebase uses camelCase (`needsDesign`,
  `tracksDesign`). An author following the documented convention
  verbatim writes a Legend that disagrees with the diagram on its own
  page. The validator does not catch it.

FC07 deliberately left this surface untouched. Its sub-DESIGN Decision
4 bounded the FC07 contract to the four parallel views the diagram
extractor produces, and named explicitly that prose-vs-diagram
reconciliation belongs to a separate follow-on check rather than
smuggling into FC07. FC08 is that follow-on. It consumes the existing
`Diagram.class_defs: HashSet<String>` field FC07 already added, slots
into the dispatch arm FC07 already wired into `validate_file` for the
plan and roadmap profiles, and ships behind the same notice-then-error
staging mechanism (the `is_notice` membership flip) FC07 and FC09 use.

The friction the gap exposes is not "build new infrastructure." The
Legend extractor is a small prose parser bounded by the body lines
immediately following the Dependency Graph fence; the reconciliation
itself is bidirectional set-comparison between the parser output and
the existing `class_defs` field. The canonical palette tolerance keeps
the notice volume bounded to the actually-novel classes a reader needs
help decoding. The unmet need is a check whose contract crosses the
prose-vs-diagram seam cleanly: bidirectional, normalization-aware,
defensive against malformed prose, silent on absent Legends.

## Goals

The goals below are paired with the corresponding requirements that
encode them as binary contracts.

**G1: Surface the three Legend-vs-classDef defect classes.** A Legend
that names a class with no `classDef` declaration (Sub-check A), a
`classDef` outside the canonical Status palette that the Legend omits
(Sub-check B), and a Legend name that matches a `classDef` only under
kebab-to-camel normalization (Sub-check C) each surface a per-defect
notice naming the class name, the side that omits it, and the
recommended fix. Encoded by R1, R2, R3.

**G2: Ship notice-level via the same staging mechanism FC07 and FC09
use.** FC08 joins the existing `is_notice` membership site so CI stays
green on the committed corpus while authors reconcile their own docs;
promotion to error is a one-line change at the same site. Encoded by
R10, R11.

**G3: Stay total over arbitrary Legend input.** Missing colons, empty
entries, trailing commas, entries without `=` signs, duplicate entries,
and arbitrary surrounding whitespace produce no panic; the parser
extracts the well-formed pairs it can recognize and silently drops the
rest. Encoded by R15.

**G4: Treat absent Legends as well-formed.** A plan or roadmap with no
Legend line produces no FC08 notice. The Legend convention is optional;
FC08 does not invent the line. Encoded by R4, R5.

**G5: Reuse FC07's class-extraction infrastructure.** FC08 introduces
no new dependency, no new module-level surface beyond a small Legend
extractor, and no new dispatch path beyond joining the existing plan/
roadmap arms. The `Diagram.class_defs` field is consumed as-is.
Encoded by R16.

## User Stories

**US1: Author writing a stale Legend.** As a plan author editing a
diagram, when I write a Legend line that names a class my diagram does
not declare, I want a specific notice naming the class and the absent
`classDef` so I can either remove the Legend entry or add the missing
declaration.

**US2: Author missing a Legend entry.** As a roadmap author adding a
new `classDef needsExplore` to my diagram, when I forget to extend the
Legend, I want a specific notice naming the missing class so I know
to extend the Legend before the reader of my doc is left guessing what
the new color means.

**US3: Author hitting the documented normalization mismatch.** As a
roadmap author copying the example Legend from
`references/dependency-diagram.md`, when my Legend uses hyphenated names
against my diagram's camelCase `classDef` declarations, I want a
specific notice naming both forms and recommending the camelCase
substitution so the fix is mechanical.

**US4: Author with no Legend.** As a plan author shipping a small plan
without a Legend (the canonical Status palette is obvious; no Legend is
needed), I want the validator to proceed without firing an FC08 notice;
the Legend convention is optional and FC08 does not invent the line.

**US5: Author hitting a malformed Legend.** As an author with a typo
in my Legend prose (a stray comma producing an empty entry, an entry
missing an `=` sign), I want the validator to proceed without
panicking; the parser is total over arbitrary line input.

**US6: Maintainer promoting the check to error.** As a maintainer who
has surveyed the corpus and confirmed FC08 notice volume has dropped
to zero, I want to remove the `FC08` arm from the existing `is_notice`
membership in a one-line PR, knowing the change site is real and
locatable in the source so my PR is mechanical.

## Requirements

### Functional Requirements

**R1: Bidirectional reconciliation in one check.** FC08 reconciles each
plan or roadmap doc's Legend prose against the diagram's `classDef` set
in a single pass, structured as three sub-checks:

- **Sub-check A (Legend-names-no-classDef).** For each class name
  parsed from the Legend, FC08 verifies that the diagram declares a
  matching `classDef` OR the class name is in the canonical Status
  palette (`done`, `ready`, `blocked`). A Legend entry that satisfies
  neither fires a notice naming the class.
- **Sub-check B (classDef-omitted-from-Legend).** For each `classDef`
  declared in the diagram outside the canonical Status palette, FC08
  verifies that the Legend names it (modulo normalization). A
  `classDef` the Legend omits fires a notice naming the class.
- **Sub-check C (normalization-mismatch).** For each Legend entry
  whose class name matches a `classDef` only under kebab-to-camel
  normalization (`needs-design` matching `classDef needsDesign`), FC08
  fires a notice naming both forms and recommending the camelCase
  substitution.

The check is dispatched in the plan and roadmap arms of
`validate_file`, behind the same schema gate that gates FC05, FC06,
FC07, and FC09, and produces zero, one, or many notices per file
depending on the defects found.

**R2: Reconciling subset and canonical-palette tolerance.** FC08
reconciles only the class names present in the Legend and the
`classDef` set. The canonical Status palette (`done`, `ready`,
`blocked`) is documented in `references/dependency-diagram.md` and is
assumed by every diagram. Sub-check A treats canonical-palette names
in the Legend as well-formed even when the local diagram does not
`classDef`-declare them. Sub-check B treats canonical-palette names in
the `classDef` set as well-formed even when the Legend omits them.
This keeps the notice volume bounded to the actually-novel classes a
reader needs help decoding. The canonical palette is not a free pass
for Legend entries that name no live class -- a Legend that lists
`Magenta = unknown` still fires Sub-check A because `unknown` is
neither in `class_defs` nor in the canonical palette.

**R3: Normalization rule (kebab-to-camel).** FC08 normalizes class
names by converting kebab-case to camelCase at hyphen boundaries:
`needs-design` becomes `needsDesign`, `tracks-design` becomes
`tracksDesign`. The normalization applies to Legend entries when
comparing against the `classDef` set. The recommended form in the
notice is always camelCase, the form the codebase uses in `class`
and `classDef` statements. The normalization does not apply in the
other direction (camelCase classDefs are not normalized to kebab-case
for Legend comparison) -- the codebase canonical form is camelCase
and the Legend is the side that needs adjustment.

**R4: Absent Legend produces no notice.** A plan or roadmap whose body
contains no line matching the Legend shape (`Legend:` or `**Legend**:`
prefix on a body line after the Dependency Graph block) produces zero
FC08 notices. The Legend convention is optional; FC08 does not invent
the line. The absent-Legend path is silent, not a self-disable notice.

**R5: Legend extraction location and shape.** The Legend extractor
scans body lines starting immediately after the located Dependency
Graph fence's closing `` ``` `` line, through the end of the body. It
matches the first line whose content (after stripping optional bold
markdown wrappers `**` and leading whitespace) begins with `Legend:`
(case-sensitive on the leading token). Lines preceding the first
Legend line are ignored; lines following the first Legend line are
not consulted (the first Legend wins). Within the matched Legend
line, the extractor parses comma-separated `<Color> = <name>` entries,
tolerating surrounding whitespace and the optional `:` after the
bold wrapper. The extractor returns a `Vec<String>` of the recovered
class names. An entry without an `=` sign, or an entry whose tokens
are empty, is silently dropped.

**R6: Per-defect notice messages in the FC05/FC06/FC07/FC09 voice.**
Every notice FC08 emits names the specific defect site the author has
to revisit. The form mirrors the existing notice voice: prefix
`[FC08]`, a description naming the class name, the side that omits
it (Legend or classDef), and where applicable the normalized form to
substitute. Notices identify classes by their bare name (no quoting,
no URL, no external identifier). The three sub-check notice forms are
distinct so a maintainer reading CI output can tell from the message
which sub-check fired.

**R7: Dispatch in both plan and roadmap arms.** FC08 is invoked in
both the `"Plan"` and `"Roadmap"` arms of `validate_file`'s
`match spec.name.as_str()`, alongside the existing FC05, FC06, FC07,
and FC09 calls. The two arms invoke the same `check_fc08` function
with the same signature; profile-specific behavior is not required
because the Legend convention and the `classDef` set apply identically
to both profiles.

**R8: No-op on absent diagram block.** A doc whose Dependency Graph
block is absent (no fenced mermaid section matching the FC07-shared
locator) produces zero FC08 notices. FC08 does not exist to surface
missing diagrams (that is FC07's territory); it reconciles the Legend
against an existing diagram and stays silent when no diagram is
present to reconcile against.

**R9: Pipeline-stage and tracks-prefix class set support.** FC08
recognizes the pipeline-stage and tracks-prefix class names
documented in `references/dependency-diagram.md` (`needsDesign`,
`needsPrd`, `needsPlanning`, `needsSpike`, `needsDecision`,
`needsExplore`, `tracksDesign`, `tracksPlan`) as valid class names
either side may name. These names participate in the normalization
rule (the documented Legend convention spells them kebab-case so
Sub-check C catches them). They are NOT part of the canonical-palette
tolerance: a `classDef needsExplore` the Legend does not name still
fires Sub-check B because pipeline-stage classes are precisely the
classes a reader needs the Legend to decode.

### Non-Functional Requirements

**R10: Notice-level shipping via the existing `is_notice` membership.**
FC08 ships at notice level for v1: its code (`FC08`) is added to the
existing `is_notice` notice-membership function in the validator (the
same `matches!` arm-shaped match that holds `SCHEMA`, `FC07`, and
`FC09`). Notice-level surfaced items do not contribute to the process
exit code, so a doc with FC08 defects produces output but exits 0. CI
stays green on the present committed corpus while the corpus
reconciles entry by entry.

**R11: Promotion-to-error seam at a single point of change.** The
promotion of FC08 from notice to error is a one-line change at the
`is_notice` membership site: removing the `FC08` arm from the
membership flips every FC08 surfaced item from notice to error. The
PRD's scope ships the seam -- the change site is real and locatable
in the source -- and excludes the flip itself, which lands in a
separate cleanup PR once the committed corpus is reconciled.

**R12: Public-visibility cleanliness of surfaced rules and messages.**
Every notice FC08 surfaces and every shared rule the check binds to is
public-repo clean: no private repo names, paths, filenames, external
issue numbers, or pre-announcement features appear in notice bodies
or rule prose. Notices identify the defect by content (class name,
side that omits it, normalized form) without leaking environment state.
This re-states the parent PRD's R22 specifically scoped to FC08.

**R13: Determinism over identical input.** FC08 produces a stable,
deterministic notice output for identical input. The notice ordering
is deterministic across runs: Sub-check A notices ordered by Legend
appearance, Sub-check B notices ordered by classDef appearance,
Sub-check C notices ordered by Legend appearance. No randomness, no
ordering dependence on `HashSet` iteration (the implementation
collects to a `Vec` and sorts where needed before emitting).

**R14: No new runtime dependency, no new binary.** FC08 introduces no
new external crate dependency, no new binary target, no parallel
pipeline, and no validation surface outside the existing
`shirabe validate` CLI and the existing reusable CI workflow. The
implementation adds at most one new module-level surface (the Legend
extractor, which may live in `mermaid.rs` as a small helper or inline
in `checks.rs` -- the choice is the sub-DESIGN's). The `is_notice`
extension is the only change to `validate.rs`.

**R15: Bounded behavior over arbitrary Legend input (SECURITY).** The
Legend extractor and `check_fc08` are total over arbitrary body line
input. The check produces a result for any input -- well-formed,
malformed, empty, missing-colon, trailing-comma, duplicate-entry,
entry-without-`=`, entry-with-only-color, entry-with-only-name,
entries-with-extra-whitespace, entries-with-internal-control-
characters -- without index panics, panics on UTF-8 boundaries, or
unbounded loops. The implementation introduces no nested loops over
Legend content, no unbounded recursion, and no allocations
proportional to anything outside the diagram's own size. Lines that
do not match the Legend shape are silently ignored; lines that match
the shape but contain malformed entries contribute only the recovered
entries.

**R16: Reuse of FC07's class-extraction infrastructure.** FC08
consumes the existing `Diagram.class_defs: HashSet<String>` field FC07
added in its sub-DESIGN. It introduces no new field on the `Diagram`
struct, no new view, and no new extractor pass over the diagram fence
content. The Legend extractor is the only net-new prose-parsing
surface; the class-set extraction reuses `class_defs` as-is.

## Acceptance Criteria

- [ ] Running `shirabe validate` on a plan or roadmap doc whose
  Legend names a class with no matching `classDef` declaration (and
  that class is not in the canonical Status palette) surfaces a
  single FC08 notice naming the class and the absent `classDef` (R1
  Sub-check A, R2, R6).
- [ ] Running `shirabe validate` on a plan or roadmap doc whose
  diagram declares a `classDef` outside the canonical Status palette
  (e.g., `classDef needsExplore`) that the Legend omits surfaces a
  single FC08 notice naming the class and the missing Legend entry
  (R1 Sub-check B, R2, R6, R9).
- [ ] Running `shirabe validate` on a plan or roadmap doc whose
  Legend uses hyphenated names (e.g., `needs-design`) against the
  diagram's camelCase `classDef` declarations (e.g.,
  `classDef needsDesign`) surfaces a single FC08 notice per affected
  entry naming both forms and recommending the camelCase substitution
  (R1 Sub-check C, R3, R6).
- [ ] A doc whose Legend lists a canonical-palette name
  (`Green = done`) and whose diagram does not declare
  `classDef done` produces no FC08 notice (R2 canonical-palette
  tolerance for Sub-check A).
- [ ] A doc whose diagram declares a canonical-palette `classDef`
  (`classDef done`) and whose Legend omits it produces no FC08 notice
  (R2 canonical-palette tolerance for Sub-check B).
- [ ] A doc with no Legend line in its body produces zero FC08
  notices (R4).
- [ ] A doc whose Dependency Graph block is absent produces zero
  FC08 notices (R8).
- [ ] A doc whose Legend is malformed (stray comma producing an empty
  entry, entry missing an `=` sign, entry with only a color, entry
  with only a name, trailing whitespace, extra whitespace inside
  entries) does not panic the validator and does not crash. The
  malformed entries are silently dropped; the well-formed entries
  are reconciled normally (R15).
- [ ] A doc whose Legend contains duplicate entries (the same color-
  class pair appearing twice) does not panic. The duplicate entries
  are deduplicated before reconciliation; the reconciliation runs
  against the unique set (R15).
- [ ] A doc whose Legend line begins with `**Legend**:` (bold-
  markdown wrapper) parses identically to a Legend line beginning
  with `Legend:` (plain) (R5).
- [ ] FC08's `check_fc08` is dispatched in both the `"Plan"` and
  `"Roadmap"` arms of `validate_file`, alongside the existing FC05,
  FC06, FC07, and FC09 invocations (R7).
- [ ] The `is_notice` membership in `validate.rs` is extended to
  include `"FC08"` alongside the existing `"SCHEMA"`, `"FC07"`, and
  `"FC09"` arms. A doc with FC08 defects produces output but exits
  0 (R10).
- [ ] Removing the `"FC08"` arm from the `is_notice` match is a
  single-line change that flips every FC08-coded surfaced item from
  notice to error (R11).
- [ ] The repository test suite includes table-driven tests covering
  each AC above, and `cargo test -p shirabe-validate` passes. Each
  test names the AC it covers in a comment immediately above the
  test function declaration, matching the FC07 convention (R13).
- [ ] FC08 introduces no new external crate dependency. The
  workspace `Cargo.toml` is unchanged in its `[dependencies]` or
  `[workspace.dependencies]` sections (R14).
- [ ] No FC08 notice body, no rule prose, and no test fixture quotes
  a private repo name, path, filename, external issue number, or
  pre-announcement feature (R12).
- [ ] `cargo build --release --bin shirabe && cargo test
  -p shirabe-validate` both succeed (R14, R15).

## Out of Scope

- **The actual promotion of `check_fc08` to error-level.** Promotion
  happens after the committed corpus is reconciled (zero notice
  volume), in a separate cleanup PR that flips the one-line
  `is_notice` membership. This PRD ships the seam, not the flip.
  Same staging shape FC07 and FC09 use.
- **A retrofit of the committed corpus.** The notice-then-error
  rollout exists precisely so corpus reconciliation happens
  incrementally after the check ships. Bulk-fixing the current
  corpus is out; an author who hits a notice fixes it in their own
  PR.
- **Validation of Legend formatting beyond extraction.** Whether the
  Legend uses `**Legend**:` or `Legend:` plain, whether the colors
  are spelled `Green` or `green`, whether the entries are separated
  by `,` or `, ` -- FC08 tolerates these variants in extraction and
  does not fire a notice on formatting. A future formatting check
  is a separate increment outside this scope.
- **Re-deriving the canonical palette.** The Status set (`done`,
  `ready`, `blocked`) and the pipeline-stage set (`needsDesign`,
  `needsPrd`, `needsPlanning`, `needsSpike`, `needsDecision`,
  `needsExplore`, `tracksDesign`, `tracksPlan`) live in
  `references/dependency-diagram.md`. FC08 reads that file's
  established set; it does not introduce a new palette and it does
  not own the source of truth for the palette.
- **Cross-document Legend reconciliation.** FC08 is intra-document
  only -- each plan or roadmap is reconciled against its own Legend
  and its own diagram. A Legend in one doc is not compared against a
  `classDef` in another doc. Cross-document state lives in FC09's
  contract.
- **Pipeline-stage class semantics.** FC08 reconciles names, not
  meaning. A diagram that uses `needsExplore` where `needsDesign`
  would be more accurate is not in FC08's scope; FC08 fires only on
  name-set agreement between the Legend and the `classDef` set.
- **Editor or IDE integration.** FC08 surfaces notices through the
  existing `shirabe validate` CLI; an in-editor Legend hint is a
  separate increment outside this scope.

## Known Limitations

- **The first Legend line wins.** A doc with multiple Legend lines in
  its body has only the first one consulted by FC08. The convention
  documents a single Legend per diagram, and a doc that lists more
  than one is treated as ill-formed in a way FC08 does not catch.
  A future enhancement could either fire a notice on multiple
  Legends or reconcile against the union; this PRD scopes the simple
  rule.
- **The Legend extractor matches only `Legend:` and `**Legend**:`.**
  Alternative shapes (`legend:`, `Legend ->`, indented Legends,
  Legends inside a separate fenced block) are not recognized and are
  treated as absent Legends. The documented convention names the
  two shapes FC08 supports; other shapes fail open (no notice rather
  than a parse panic).
- **Normalization is unidirectional (kebab-to-camel).** The codebase
  canonical form is camelCase, and FC08 recommends the camelCase
  substitution in Sub-check C notices. A future enhancement could
  surface a separate notice when the `classDef` itself is in kebab-
  case (a stronger normalization claim), but this PRD scopes FC08 to
  the more common direction.
- **No reconciliation against `class` statements directly.** FC08
  reconciles the Legend against `classDef` declarations, not
  `class` statements. A `class I1 mystery` statement with no
  matching `classDef mystery` and no matching Legend entry is
  detected by FC07 (the orphan class assignment surface) rather
  than FC08; FC08 only enters once the `classDef` set is non-empty.

## Decisions and Trade-offs

### Decision 1: Three sub-checks in one check, not three checks

FC08 is structured as a single `check_fc08` function with three
sub-checks running in one pass, mirroring the FC09 structure. The
alternative -- three separately-coded checks `check_fc08a`,
`check_fc08b`, `check_fc08c` -- would force three dispatch arms in
`validate_file` and three independent `is_notice` membership extensions
for what is conceptually one reconciliation pass. The bundled shape
keeps the dispatch surface small and matches the precedent FC07 and
FC09 set.

The trade-off is that promoting one sub-check to error while leaving
the others as notices is not a one-line `is_notice` change; it would
require a separate code field per sub-check. The PRD scopes FC08 to
all-or-nothing promotion, matching the FC09 staging shape, and the
known-limitation note above flags the constraint.

### Decision 2: Notice-level via the existing `is_notice` membership

FC08 joins the existing `matches!` arm in `is_notice` rather than
introducing a new staging mechanism (e.g., a per-check `severity`
field on `ValidationError`). The alternative would generalize the
notice-vs-error split into a field that every check sets, but FC07 and
FC09 already use the existing membership site and a new mechanism for
FC08 would fork the staging surface for no functional gain. The single
match-arm site is the canonical promotion seam every reviewer already
knows.

The trade-off is that the membership site is now a four-arm match
(`SCHEMA | FC07 | FC08 | FC09`); a future check would extend it again.
The site stays readable at five arms; a more general mechanism is the
right call only if the membership grows beyond ten arms.

### Decision 3: Canonical-palette tolerance for the Status set only

The canonical-palette tolerance applies to the Status set (`done`,
`ready`, `blocked`) but NOT to the pipeline-stage and tracks-prefix
sets. The asymmetry is deliberate: the Status set is the universally-
assumed default that every diagram inherits; a reader does not need
the Legend to decode `Green = done`. The pipeline-stage classes are
precisely the classes a reader needs help with because they encode
upstream-artifact prerequisites and tracking semantics that vary by
context.

The trade-off is that authors who add `classDef needsExplore` to a
roadmap and forget the Legend entry get an FC08 notice immediately --
the friction is intentional, because a `needsExplore` node without a
Legend entry leaves the reader guessing. An author who omits a
canonical Status entry from the Legend does not get a notice because
the Status palette is the default.

### Decision 4: Kebab-to-camel normalization is one-directional

FC08 normalizes Legend kebab-case to camelCase for comparison against
`classDef` declarations. It does NOT normalize `classDef` camelCase to
kebab-case for comparison against the Legend. The asymmetry follows
the codebase canonical form: every `class` and `classDef` statement
uses camelCase, and the codebase's other Mermaid-handling code does
not accept kebab-case. The Legend convention documentation is the
outlier (the example uses kebab-case), and the normalization rule
plus the Sub-check C notice direct the author toward the codebase
canonical form.

The trade-off is that a future convention change to allow kebab-case
in `classDef` declarations would require revisiting the normalization
direction. The PRD known-limitation note flags this; the cost of
extending the normalization is small (a second pass with the inverse
mapping) and the current asymmetry matches the corpus.

### Decision 5: Public-cleanliness re-stated as an FC08-scoped NFR

The parent PRD R22 already binds public-cleanliness across the
validator. R12 re-states it scoped to FC08 because FC08 emits
free-text notice strings that surface in CI output, and the re-
statement gives the per-defect notice strings a clear single-PRD
constraint to be reviewed against. The trade-off is small duplication
between R12 and the parent's R22; the gain is that FC08's notice
strings are reviewable against a single requirement in this PRD
rather than a cross-reference to the parent.

### Decision 6: Bounded behavior over arbitrary Legend input binds totality

R15 binds the totality contract -- the Legend extractor and
`check_fc08` produce a result for any input without panicking. The
alternative would be best-effort behavior with optional panic on
"sufficiently malformed" input; the validator is invoked on every PR
and on every author's local edit, so a panic on a typo in a Legend
would block the author until the typo is fixed. Totality is the
right contract: the parser drops what it cannot parse and the check
reconciles what is recovered.

The trade-off is that a Legend an author intended to be meaningful
but mistyped beyond recognition produces no notice -- the parser
drops the unrecognized prose silently. This is acceptable because
the absent-Legend path is itself silent (R4), so a malformed Legend
degrades gracefully into the absent-Legend behavior rather than
firing a misleading notice on a typo.

## Downstream Artifacts

The implementation handoff to a downstream sub-DESIGN settles:

- **The Legend extractor call site.** Either a small helper in
  `crates/shirabe-validate/src/mermaid.rs` alongside the existing
  diagram extractor, or inline in `crates/shirabe-validate/src/checks.rs`
  next to `check_fc08`. The PRD does not pre-commit; the sub-DESIGN
  weighs the trade-off (mermaid.rs for cohesion with class extraction;
  checks.rs for locality with the consumer).
- **The exact notice message strings.** R6 binds the voice and shape;
  the sub-DESIGN settles the specific prose with the FC05/FC06/FC07/
  FC09 message corpus as the comparison surface.
- **The table-driven test layout.** R13 binds determinism; the sub-
  DESIGN settles the test fixture shape and the per-AC test-function
  naming convention.
- **The pipeline-stage class set's exact membership.** R9 names the
  documented set; the sub-DESIGN settles whether the set is hard-
  coded in `check_fc08` or read from a shared constant referenced by
  other code paths (FC07 currently hard-codes the Status set; FC08
  may match or diverge).

## Related

- Parent PRD (R8 staged reconciliation, R20 notice-then-error, R22
  public-cleanliness): `docs/prds/PRD-roadmap-plan-standardization.md`.
- Parent DESIGN (Decision 3 staging the reconciliation increment
  behind a notice rollout):
  `docs/designs/DESIGN-roadmap-plan-standardization.md`.
- Parent PLAN (the row that schedules this increment as the FC08 leaf
  node depending on FC07's class-extraction infrastructure):
  `docs/plans/PLAN-roadmap-plan-standardization.md`.
- BRIEF that this PRD picks up:
  `docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md`.
- FC07 sub-DESIGN (the architectural precedent for the
  `class_defs: HashSet<String>` field FC08 consumes and the dispatch
  arm FC08 slots into):
  `docs/designs/current/DESIGN-table-diagram-reconciliation.md`.
- FC07 PRD (the requirements-shape this PRD mirrors):
  `docs/prds/PRD-table-diagram-reconciliation.md`.
- FC09 PRD (the staged-notice pattern this PRD inherits from):
  `docs/prds/PRD-doc-vs-github-state-reconciliation.md`.
- Canonical dependency-diagram conventions (the Legend convention,
  the canonical Status palette, the pipeline-stage class set, the
  documented hyphenated-vs-camelCase mismatch in the example
  Legend): `references/dependency-diagram.md`.

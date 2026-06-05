---
schema: prd/v1
status: Done
problem: |
  shirabe plans and roadmaps describe each feature's structure twice —
  in an Implementation Issues table and a Dependency Graph mermaid
  block — but no validator check reconciles the two. Drift across the
  three reconciliation dimensions (node set, edge set, and class
  versus row Status) passes CI unnoticed today; a recent hand-fix PR
  corrected a real class-versus-Status case by hand because nothing
  fired. The longer the committed corpus accumulates the drift, the
  more expensive a later one-shot retrofit becomes, which is why the
  parent design staged this check behind a feasibility spike and a
  notice-then-error rollout rather than landing it strict on day one.
goals: |
  A doc author who edits a plan or roadmap sees the validator surface
  a specific notice the moment the diagram and the table fall out of
  agreement across any of the three dimensions. The notice level
  keeps CI green while the committed corpus reconciles row by row;
  promotion to error is a one-line change once the docs are clean.
  The diagram becomes a trustworthy render of the table by
  construction, and the requirements named here bind to the
  per-dimension strictness the feasibility spike settled.
upstream: docs/briefs/BRIEF-table-diagram-reconciliation.md
---

# PRD: table-diagram-reconciliation

## Status

Done

This PRD picks up the requirements work scoped by
`docs/briefs/BRIEF-table-diagram-reconciliation.md`. It owns the
contract-level requirements for the FC07 validator check — the three
reconciliation dimensions, the mermaid extractor's surface, the
notice-level rollout via the existing `is_notice` membership, the
promotion-to-error seam, the bounded-iteration guarantee, and the
public-cleanliness invariant. Implementation specifics (the extractor
function body, the exact notice message strings, the seam comment
wording, the test fixture strategy) land in a downstream DESIGN doc and
its plan.

The PRD inherits and sharpens the parent
`PRD-roadmap-plan-standardization.md` invariants — R8 staged
reconciliation, R9 spike upstream, R19 reuse of existing validation
infrastructure, R20 no-day-one-breakage, and R22 public-cleanliness —
without re-litigating them. The spike (`docs/spikes/SPIKE-mermaid-parser.md`)
settles every per-dimension strictness contract; this PRD names those
contracts as numbered requirements with binary acceptance criteria.

## Problem Statement

A plan or roadmap author writes the feature structure twice. The
Implementation Issues table carries the key column, a Dependencies
column, and a Status marker (an explicit value in the roadmap profile,
a strikethrough-on-done convention in the plan profile). The
Dependency Graph mermaid block carries node declarations, edges, and
class assignments that are supposed to mirror the same shape. The two
surfaces are authored by hand, edited at different times, and
reconciled by no automated check.

The validator already parses the table (the prior table-parser
increment landed the parsed `Table` IR) and already dispatches FC05
(schema conformance) and FC06 (cross-reference) over it in the plan
and roadmap arms. The validator has no equivalent reader for the
diagram, so it cannot reconcile the two surfaces along any axis. An
author who renames an issue, closes a dependency, marks an entity
done, or rewrites a dependency edge has to update both surfaces
consistently across three dimensions and verify the agreement by eye.

The drift is not hypothetical. A recent hand-fix PR against
`docs/plans/PLAN-roadmap-plan-standardization.md` corrected a
class-versus-Status disagreement where closed issues stayed classed
`blocked` long after the rows reached a terminal state. No check
fired and the disagreement only surfaced on a manual reading. The
node-set and edge dimensions have the same exposure — a table key
with no diagram node, or a Dependencies entry with no matching edge,
passes CI today. Every plan and roadmap in the corpus is one rename
away from the same defect.

The gap has two costs. A reader who trusts the diagram as a faithful
render of the table can be led to the wrong picture of which work is
ready, which is blocked, and which dependencies bind. And the longer
the corpus accumulates drift before any reconciliation check exists,
the larger the eventual retrofit becomes — which is precisely why the
parent design staged this check behind a feasibility spike (now
landed) and a notice-then-error rollout rather than landing it strict
on day one.

## Goals

1. **One reconciliation check covers three dimensions.** FC07
   reconciles the parsed Implementation Issues table against the
   extracted Dependency Graph mermaid block across node set, edge
   set, and class-versus-Status agreement in a single pass.

2. **The check ships at notice level.** CI stays green on the
   present committed-diagram corpus while the corpus reconciles row
   by row, and a one-line change at the `is_notice` membership site
   promotes the check to error once the corpus is clean.

3. **Per-defect messages name the specific fix site.** Each notice
   names the cell, line, or node the author has to revisit, in the
   FC05/FC06 voice the existing checks already use.

4. **Reconciliation is total over arbitrary diagram input.** The
   extractor produces a result for any line input without index
   panics or unbounded loops; malformed diagrams produce specific
   notices and never crash the validator.

5. **No new binary or parallel pipeline.** The check extends the
   existing `shirabe-validate` crate and runs through the existing
   CLI and reusable CI workflow alongside FC05 and FC06.

## User Stories

**As a plan author who renames an issue in the Implementation Issues
table without updating the Dependency Graph**, I want the validator
to surface a notice naming the table key with no matching diagram
node (or the orphan diagram node with no table key), so that I see
the node-set drift on the PR rather than missing it on a by-eye
diff.

**As a plan author who strikes through an entity row to mark it done
while the diagram still classes the node `blocked`**, I want the
validator to surface a notice naming the node, its declared class,
the observed table state, and the expected class, so that the
class-versus-Status drift the recent hand-fix corrected by hand
fires automatically on the next occurrence.

**As a roadmap or plan author who edits a Dependencies cell without
updating the matching edge in the diagram**, I want the validator to
surface a notice naming the missing edge (source and destination),
in either direction (Dependencies-side and diagram-side asymmetry
alike), so that the edge dimension closes the third axis of drift.

**As a maintainer who watches the FC07 notice volume drop to zero
across the committed corpus**, I want a single-point seam at the
`is_notice` membership where flipping one line promotes the check
from notice to error in the same PR that finishes the cleanup, so
that the notice-then-error rollout has an executable end state and
the corpus gets a reliable contract once the cleanup is done.

**As a doc author whose diagram is malformed (an unterminated fence,
a ragged node declaration, a `flowchart` header, an inline class
syntax, multiple mermaid blocks, or no diagram at all)**, I want the
validator to surface a specific notice naming the malformation and
keep running the per-node checks where it can, so that a hand-edit
defect produces an actionable signal rather than a crashed
validator.

## Requirements

### Functional Requirements

**R1: Three reconciliation dimensions in one check.** FC07 reconciles
the parsed Implementation Issues table against the extracted
Dependency Graph mermaid block in a single pass across these three
dimensions:

- **Node-set bijection** (R2)
- **Edge agreement** (R3)
- **Class-versus-Status agreement** (R4)

The check is dispatched in the plan and roadmap arms of the validator's
file dispatcher, behind the same schema gate that gates FC05 and FC06,
and produces zero, one, or many notices per file depending on the
defects found.

**R2: Node-set bijection (strict over the reconciling subset).** For
every entity-row key in the table whose node id matches `^I[0-9]+$`,
the diagram must contain a node with that id. For every diagram node
whose id matches `^I[0-9]+$`, the table must contain a matching
entity row. A table key with no matching diagram node fires a notice
naming the table key. A diagram node with no matching table key fires
a notice naming the orphan node.

A diagram node whose id does not match `^I[0-9]+$` is excluded from
both directions of the bijection check (the **tolerated exception**).
This tolerates the two non-issue-keyed shapes the spike enumerated in
the committed corpus today: the `O<n>` outline ids in the Rust
rewrite plan and the `K<n>` cross-repo reference ids in the koto
roadmap.

**R3: Edge agreement (symmetric over the reconciling subset).** For
every pair of issue-keyed nodes `I<a>` and `I<b>` where the table row
for `#a` lists `#b` in its Dependencies cell, the diagram must
contain the edge `I<b> --> I<a>` (the convention is blocker on the
left, dependent on the right). For every edge `I<b> --> I<a>` where
both endpoints are issue-keyed reconciling nodes, the table row for
`#a` must list `#b` in its Dependencies cell.

A Dependencies-cell entry with no matching diagram edge fires a
notice naming the missing edge. A diagram edge with no matching
Dependencies entry fires a notice naming the orphan edge. Edges
involving a non-reconciling node id (any endpoint that does not match
`^I[0-9]+$`) are excluded from both directions.

**R4: Class-versus-Status agreement (truth table over the
Status-bearing class set).** For each diagram node `I<n>` carrying a
class assignment whose name is in the Status-bearing set (`done`,
`ready`, `blocked`), the validator checks the four-case truth table:

- `done` requires the table row to be in a terminal state
  (strikethrough applied in the plan profile, or Status `Done` or
  `Closed` in the roadmap profile).
- `ready` requires the row to be open and every dependency named in
  the Dependencies cell to resolve to a row that is itself in a
  terminal state.
- `blocked` requires the row to be open and at least one dependency
  named in the Dependencies cell to resolve to a row that is open.
- A node with no class assignment does not fire a class-mismatch
  notice; a missing class is a presentation gap, not a contract
  violation.

The `needsDesign`, `needsPrd`, `needsSpike`, `needsDecision`,
`tracksDesign`, and `tracksPlan` classes are recorded by the
extractor but are not reconciled against Status — they encode
pipeline-position metadata that the Implementation Issues table does
not carry. Non-Status classes (`simple`, `testable`, `critical`
Complexity markers, the `koto` external-node marker, any future
custom class) are not checked.

Each mismatch fires a notice that names the node, the declared class,
the observed table state, and the expected class. A class statement
that names a class not defined by any `classDef` in the same diagram
fires a notice naming the undefined class.

**R5: Mermaid extractor (line-oriented, stdlib-only over the corpus
subset).** The validator carries a single new function that reads the
lines of the `## Dependency Graph` mermaid fenced block and produces
four parallel views FC07 consumes:

- **Node set** — every id observed in a `<id>["<label>"]` declaration.
- **Edge set** — every directional `(src, dst)` pair, including pairs
  derived by splitting chained `A --> B --> C` forms.
- **Class statements** — every `(id, class-name)` pair derived from
  `class <id-list> <name>` lines, expanding the comma-separated id
  list with whitespace tolerated.
- **classDef set** — every class name declared by a
  `classDef <name> <styles>` line. Style content is not parsed.

The extractor reads from the line after the opening ```` ```mermaid ````
fence (whose next line must start with `graph `) to the matching
closing fence or to EOF. It does not parse a general mermaid grammar
and introduces no new dependency; the existing crate dependencies
suffice.

**R6: Notice-level shipping via the existing `is_notice` membership.**
FC07 ships at notice level for v1: its code is added to the existing
`is_notice` notice-membership function in the validator (the same
mechanism the schema-gate notice already uses). Notice-level surfaced
items do not contribute to the process exit code, so a doc with FC07
defects produces output but exits 0. CI stays green on the present
committed-diagram corpus while it reconciles row by row.

**R7: Promotion-to-error seam at a single point of change.** The
promotion of FC07 from notice to error is a one-line change at the
`is_notice` membership site: removing FC07 from the membership flips
every FC07 surfaced item from notice to error. The PRD's scope ships
the seam — the change site is real and locatable — and excludes the
flip itself.

**R8: Per-defect notice messages in the FC05/FC06 voice.** Every
notice FC07 emits names the specific defect site the author has to
revisit. The form mirrors the existing FC05/FC06 notice voice:
prefix `[FC07]`, a description naming the entity (node id, table
key, edge endpoints, or class name), and the observed and expected
state where applicable. Notices identify nodes by their diagram id
(`I111`), not by a URL or external identifier.

**R9: Edge-case behavior over malformed diagram input.** Each of the
following malformations produces a specific notice and the extractor
continues without crashing:

- An unterminated mermaid fence: the extractor reads to EOF, FC07
  emits one notice flagging the unterminated block.
- A diagram with no body (header only): the extractor returns an
  empty view set, and the node-set check fires per table row.
- No mermaid block under `## Dependency Graph`: FC07 emits one
  notice flagging the missing block and skips the per-node checks.
- Multiple mermaid blocks in the same file: the first block under
  `## Dependency Graph` is used; later blocks are ignored.
- A mermaid block outside the `## Dependency Graph` section: ignored.
- A `flowchart` header instead of `graph TD`/`graph LR`: a
  header-shape notice fires and the extractor still attempts the
  body.
- A ragged node declaration with an unterminated label: the line is
  ignored and the node is not added to the node set (a downstream
  node-set notice flags the consequence).
- A class statement naming a class with no `classDef` definition in
  the same diagram: a notice fires naming the undefined class.
- Inline class syntax (`I1:::ready`) on a node decl or edge: the
  inline class is parsed equivalent to a `class I1 ready` statement,
  and a notice fires that inline syntax is not the canonical form.
- A multi-key class statement with whitespace inside the id list
  (`class I1, I2 ready`): tolerated — ids are split on commas and
  trimmed.

### Non-Functional Requirements

**R10: Bounded iteration over arbitrary input (SECURITY).** The
extractor and the FC07 check are total over arbitrary line input.
The extractor makes one pass over the fenced lines with constant-time
per-line prefix matching; there are no nested loops over input and no
unbounded recursion. The check produces a result for any input — well
formed, malformed, or empty — without index panics, panics on UTF-8
boundaries, or unbounded loops. Running time is linear in the number
of fenced lines.

**R11: Reuse of existing validation infrastructure.** FC07 extends
the existing `shirabe-validate` crate. It introduces no new binary,
no parallel pipeline, and no new external dependency. The mermaid
extractor is the only net-new parser; it is a single function in the
crate and uses only line splitting, prefix matching, and the regex
dependency the crate already carries. FC07 runs through the existing
`shirabe validate` CLI and the existing reusable CI workflow.

**R12: Public-visibility cleanliness of surfaced rules and messages.**
Every notice FC07 surfaces and every shared rule the check binds to
is public-repo clean: no private repo names, paths, filenames,
external issue numbers, or pre-announcement features. Notice messages
identify nodes by their diagram id and reference table or diagram
state by content, not by URL or external identifier. This re-states
the parent PRD's R22 specifically scoped to FC07.

## Acceptance Criteria

- [ ] Running `shirabe validate` on a plan or roadmap doc whose
  Implementation Issues table contains a key with no matching
  `^I[0-9]+$` diagram node surfaces a single FC07 notice naming the
  table key (R2).
- [ ] Running `shirabe validate` on a plan or roadmap doc whose
  Dependency Graph contains a `^I[0-9]+$` node with no matching table
  key surfaces a single FC07 notice naming the orphan node (R2).
- [ ] A diagram containing a node whose id does not match `^I[0-9]+$`
  (an `O<n>` or `K<n>` corpus shape) does not produce a node-set
  notice in either direction; the node is excluded from the bijection
  check (R2).
- [ ] Running `shirabe validate` on a doc whose Dependencies cell for
  row `#a` lists `#b` but whose diagram has no `I<b> --> I<a>` edge
  surfaces a single FC07 notice naming the missing edge (R3).
- [ ] Running `shirabe validate` on a doc whose diagram has an
  `I<b> --> I<a>` edge but whose table row for `#a` does not list
  `#b` in Dependencies surfaces a single FC07 notice naming the
  orphan edge (R3).
- [ ] A diagram edge involving a non-issue-keyed node id (e.g.
  `K65 --> I111`) does not produce an edge notice in either direction
  (R3).
- [ ] A node carrying class `done` whose table row is open (the plan
  row is not struck through, or the roadmap row's Status is not
  `Done`/`Closed`) surfaces a single FC07 notice naming the node, the
  declared class `done`, the observed state, and the expected class
  (R4).
- [ ] A node carrying class `ready` whose table row is open but
  whose Dependencies include at least one open row surfaces a single
  FC07 notice naming the node, the declared class `ready`, the
  observed state, and the expected class (R4).
- [ ] A node carrying class `blocked` whose table row is in a
  terminal state surfaces a single FC07 notice naming the node, the
  declared class `blocked`, the observed terminal state, and the
  expected class (R4).
- [ ] A node with no class assignment does not produce a
  class-mismatch notice; the check fires only on a declared mismatch
  (R4).
- [ ] A node carrying a class in
  `{needsDesign, needsPrd, needsSpike, needsDecision, tracksDesign,
  tracksPlan, simple, testable, critical, koto}` does not produce a
  class-versus-Status notice (R4).
- [ ] A class statement naming a class that no `classDef` in the
  same diagram defines surfaces a single FC07 notice naming the
  undefined class (R4).
- [ ] The extractor produces four parallel views (node set, edge set,
  class statements, classDef set) over the corpus subset the spike
  enumerated, using stdlib-only line-oriented parsing and the
  existing crate dependencies — no new dependency is introduced (R5).
- [ ] FC07's code appears in the validator's `is_notice` notice
  membership; running `shirabe validate` against a doc with FC07
  defects exits 0 (R6).
- [ ] The `is_notice` membership site contains exactly one point of
  change that flips FC07 from notice to error (removing the FC07
  code from the membership), and that change is independently
  reviewable as a single-line diff (R7).
- [ ] Every FC07 notice begins with the prefix `[FC07]` and names
  the specific node, table key, edge endpoints, or class name the
  defect applies to; the voice matches the existing FC05/FC06 notice
  form (R8).
- [ ] A doc with an unterminated mermaid fence surfaces one
  `[FC07] unterminated mermaid block` notice and does not crash the
  validator (R9).
- [ ] A doc with a `## Dependency Graph` section but no fenced
  mermaid block under it surfaces one notice flagging the missing
  block and does not run the per-node checks for that doc (R9).
- [ ] A doc whose first mermaid block under `## Dependency Graph`
  has a `flowchart` header surfaces a header-shape notice and the
  extractor still attempts to read the body (R9).
- [ ] A doc whose diagram contains inline class syntax
  (`I1:::ready`) on a node declaration or edge produces both a
  non-canonical-syntax notice and the equivalent class assignment in
  the extractor's output (R9).
- [ ] A doc whose diagram contains a class statement with whitespace
  inside the id list (`class I1, I2 ready`) is accepted by the
  extractor with the ids split on commas and trimmed (R9).
- [ ] Running the validator against arbitrarily malformed line input
  in the mermaid block (bytes that do not match any extractor
  pattern, deeply nested punctuation, very long lines) produces a
  result without an index panic or an unbounded loop, and finishes
  in time linear in the number of lines (R10).
- [ ] FC07 ships as a single new check function added to the existing
  `shirabe-validate` crate; no new binary, no parallel pipeline, and
  no new external dependency is introduced (R11).
- [ ] A scan of FC07's notice message bodies and the surfaced FC07
  rule prose finds no private repo names, paths, filenames, external
  issue numbers, or pre-announcement features (R12).

## Out of Scope

This PRD scopes the FC07 reconciliation check and its mermaid
extractor. It explicitly excludes:

- **The actual promotion of FC07 to error-level.** Promotion is a
  one-line change at the `is_notice` membership site (R7), landed in
  a separate cleanup PR once the committed-diagram corpus is
  reconciled. This PRD ships the seam, not the flip.
- **A retrofit of the committed-diagram corpus.** The notice-then-error
  rollout exists precisely so the corpus reconciles incrementally
  after FC07 ships. Bulk-fixing the current corpus is out; an author
  who hits a notice fixes it in their own PR.
- **Reconciling roadmaps' `needs-*` annotations against the
  diagram's `needsDesign`/`needsPrd`/`needsSpike`/`needsDecision`/
  `tracksDesign`/`tracksPlan` classes.** These classes encode
  pipeline-position metadata that the Implementation Issues table
  does not carry. FC07 records the class but does not reconcile it
  against Status; a later increment can extend the reconciliation if
  pipeline-position tracking moves into the table.
- **A general mermaid parser usable beyond this check.** The
  extractor is line-oriented and shaped to the corpus subset the
  spike enumerated. A future caller needing more grammar coverage
  replaces the extractor; this PRD does not generalize it.
- **Edge labels, arrow variants other than `-->`, `subgraph`/`end`
  blocks beyond defensive tolerance, and other mermaid constructs
  the corpus does not use.** The reference either forbids or does
  not require these; the extractor tolerates them defensively but
  does not parse them. Extending coverage is out for v1.
- **Cross-repo node id forms (`owner/repo#N`) as first-class diagram
  node ids.** The committed corpus uses local mnemonic ids
  (`K<n>`) for cross-repo references and no `owner/repo#N` literal
  appears as a diagram node. The reconciling-subset tolerance covers
  the `K<n>` shape; recognizing `owner/repo#N` as a node id is out
  for v1.
- **A new validation binary, a parallel pipeline, or a new external
  dependency.** R11 forbids these; the implementation extends the
  existing crate and runs through the existing CLI and reusable
  workflow.

## Known Limitations

- **The bijection check tolerates a known historical pattern.** The
  `O<n>` outline ids in the Rust rewrite plan and the `K<n>`
  cross-repo ids in the koto roadmap are excluded from the
  reconciling subset. A reconciliation defect involving a
  non-issue-keyed node passes silently. The tolerance keeps FC07
  from issuing noise on a documented inconsistency the milestone
  does not aim to fix; if the corpus is later migrated to
  issue-keyed node ids, the tolerance becomes dead code and can be
  removed in the promote-to-error change.

- **The class-versus-Status check binds to "blocker on the left,
  dependent on the right".** The reference does not formally state
  the edge directionality convention but the committed corpus is
  consistent. If a future diagram convention proposal flips this,
  the edge check binds the wrong way and would need an update at
  the same time as the convention change.

- **The notice-then-error rollout depends on a maintainer flipping
  the seam.** While the corpus carries unreconciled diagrams, FC07
  notices appear on every PR that touches a plan or roadmap doc.
  The signal degrades if authors learn to skim past FC07 output
  without reading it. The forcing function is the maintainer's
  cleanup PR (Journey 4 in the BRIEF); until then, FC07's value
  depends on authors treating notices as actionable signal rather
  than noise.

- **The roadmap-profile Status mapping rests on an assumption.** The
  spike's truth table assumes that roadmap Status values `Done` and
  `Closed` both count as terminal and that `Not Started` and `In
  Progress` both count as open. A roadmap row whose Status carries
  a `needs-*` annotation is treated as open. If the migrated
  roadmap corpus surfaces a Status value the truth table does not
  cover, the mapping needs a refinement at implementation time
  rather than a re-litigation of the requirement.

## Decisions and Trade-offs

### Decision 1: Three reconciliation dimensions in one check, not three checks

**Decision.** FC07 is a single check that produces zero, one, or many
notices across all three dimensions in one pass (R1). The
implementation does not split into FC07/FC08/FC09 by dimension.

**Alternatives considered.**

- *Split into one check per dimension (FC07 node-set, FC08 edge,
  FC09 class-vs-Status).* Rejected: every dimension consumes the
  same extracted views (the four parallel outputs of R5), every
  dimension targets the same reconciling subset (R2's exception
  applies to all three), and every dimension ships at the same
  notice level with the same promotion seam (R6/R7). Splitting
  would multiply dispatcher entries without separating concerns the
  spike already proved are coupled.
- *Defer the class-versus-Status dimension to a later increment.*
  Rejected: the class-versus-Status dimension is the exact defect
  the recent hand-fix corrected and the spike's scope-extension
  reason for this increment. Shipping FC07 without it would leave the most
  recently observed drift uncaught, defeating the purpose of the
  staged rollout.

**Rationale.** One check, three dimensions, one notice membership,
one promotion seam. The dimensions are coupled by the extractor's
views and the reconciling-subset rule; coupling them in the dispatch
matches the implementation reality.

### Decision 2: Notice-level via existing `is_notice` membership, not a new staging mechanism

**Decision.** FC07 ships at notice level by joining the existing
`is_notice` membership the schema gate already uses (R6). The
promotion seam is removing FC07 from that membership (R7).

**Alternatives considered.**

- *Introduce a new severity level (`warning`) between notice and
  error.* Rejected: the existing two-level system (notice/error)
  already supports the staged-rollout shape the parent PRD's R8/R20
  prescribe. Adding a third level would require dispatcher,
  message-format, and CI-exit-code changes for no functional gain.
- *Hard-gate FC07 behind a runtime flag (`--check-fc07`) that
  defaults off.* Rejected: a flag-gated check is invisible to PR
  authors and provides no forcing function for the cleanup phase.
  The notice-then-error rollout depends on FC07 being visible from
  day one so the corpus reconciles incrementally.

**Rationale.** The schema-gate precedent is the right reuse: it
already implements the notice-then-promote pattern the parent PRD
sanctions, and FC07's mechanics are identical (membership in,
membership out). One seam, one mechanism.

### Decision 3: Tolerated non-issue-keyed subset (the `O<n>`/`K<n>` exception)

**Decision.** Nodes whose id does not match `^I[0-9]+$` are excluded
from both directions of the bijection check and from edge agreement
where either endpoint is non-reconciling (R2, R3).

**Alternatives considered.**

- *Strict bijection over all node ids.* Rejected: the corpus
  contains two documented non-issue-keyed shapes (`O<n>` outline ids
  in the Rust rewrite plan, `K<n>` cross-repo ids in the koto
  roadmap). Strict bijection would fire false-positive notices on
  every commit touching those docs.
- *Tolerate by document-specific allowlist.* Rejected: an allowlist
  would couple FC07 to specific doc paths, and a new doc adopting
  the same `K<n>` shape would not be covered. The id-pattern test
  generalizes the tolerance to the shape rather than the specific
  files.

**Rationale.** The two non-issue-keyed shapes are historical
patterns the milestone does not aim to fix. The id-pattern test
isolates the tolerance to the shape itself; if the corpus is later
migrated to issue-keyed ids, the tolerance becomes dead code
removable in the promote-to-error change.

### Decision 4: Public-cleanliness re-stated as an FC07-scoped NFR

**Decision.** R12 re-states the parent PRD's R22 public-cleanliness
invariant specifically for FC07's notice messages and surfaced rules,
rather than relying solely on the parent's blanket clause.

**Alternatives considered.**

- *Rely on the parent PRD's R22 alone.* Rejected: notice messages
  for FC07 will be written and edited by downstream implementers
  who may not consult the parent PRD. Re-stating the constraint at
  the FC07-specific layer makes the binding explicit at the layer
  where messages are authored.
- *Skip the public-cleanliness requirement entirely.* Rejected: the
  notice messages are visible in CI logs that may be world-readable.
  The constraint is real and needs a testable surface; an explicit
  NFR with an AC scan satisfies that.

**Rationale.** R12 is a small re-statement that costs nothing and
prevents a class of defect that would otherwise depend on the
implementer remembering the parent's R22. The AC scan is the
testable surface.

## Downstream Artifacts

Forthcoming work flowing from this PRD:

- **A sub-DESIGN** that refines the parent
  `DESIGN-roadmap-plan-standardization.md` Decision 3 in light of
  the spike and the FC07 scope extension. The sub-DESIGN owns the
  extractor function body, the exact notice message strings, the
  seam comment wording, and the test fixture strategy.
- **A sub-PLAN** decomposing the FC07 increment into implementation
  issues — the extractor function, the check function, the
  is_notice membership change, the notice messages, and the test
  fixtures the design specifies.

## Related

- **Upstream brief:** `docs/briefs/BRIEF-table-diagram-reconciliation.md`.
- **Feasibility spike:** `docs/spikes/SPIKE-mermaid-parser.md`.
- **Parent design (the staged-reconciliation Decision 3 this PRD
  binds to):** `docs/designs/DESIGN-roadmap-plan-standardization.md`.
- **Parent plan (the row that schedules this increment):**
  `docs/plans/PLAN-roadmap-plan-standardization.md`.
- **Parent PRD (R8 staged-reconciliation, R9 spike requirement, R20
  notice-then-error contract, R22 public-cleanliness):**
  `docs/prds/PRD-roadmap-plan-standardization.md`.
- **Canonical issues-table conventions (the Status column for the
  roadmap profile, strikethrough-on-done for the plan profile):**
  `references/issues-table.md`.
- **Canonical dependency-diagram conventions (the graph subset, the
  status-class palette, the forbidden forms):**
  `references/dependency-diagram.md`.
- **Validation precedents:**
  `crates/shirabe-validate/src/checks.rs` (FC05 and FC06),
  `crates/shirabe-validate/src/validate.rs` (the dispatcher and the
  `is_notice` membership the FC07 code joins for v1).

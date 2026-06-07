---
schema: prd/v1
status: In Progress
problem: |
  shirabe's roadmap and plan workflows are procedure-rich but
  principle-poor. The issues table has several drifting schemas, the
  dependency diagram has a canonical spec docs apply inconsistently, the
  roadmap has no native scripted path to its own issues table, the
  single-pr/multi-pr decision is buried and not anchored on usable
  value, the lifecycle is contradictory and unenforced (no review gate
  before issues are created, three-way-conflicting terminal), and
  validation checks section presence but never table or diagram
  contents. The shared parts were never named as shared and the few real
  principles are each trapped in one skill.
goals: |
  The roadmap and plan workflows derive from one small, named principle
  set instead of restating procedure. The issues table and dependency
  diagram are each defined once and consumed by both workflows through
  two altitude profiles. Validation moves from section-presence to table
  and diagram contents, staged by blast radius. The single-pr/multi-pr
  decision is surfaced, anchored on usable value, and de-conflated from
  work-slicing, with a value-confirmation guard that can fail. The
  roadmap gets a first-class scripted path to its issues table. The
  lifecycle gates issue creation on approval and ends in one terminal,
  verify-then-delete, enforced by two stateless CI checks.
upstream: docs/briefs/BRIEF-roadmap-plan-standardization.md
---

# PRD: roadmap-plan-standardization

## Status

In Progress

This PRD picks up the requirements work scoped by
`docs/briefs/BRIEF-roadmap-plan-standardization.md`. It owns the
requirements for the principle set, the shared issues-table framework
and its two altitude profiles, the dependency-diagram convention and its
enforcement, the validation content checks, the decision-surfacing
fixes, and the enforced lifecycle. Implementation specifics — the
shared-reference file layout, the validation check codes, the
roadmap-to-issues script interface, the mermaid-parser internals, and
the exact principle wording — land in the downstream
`DESIGN-roadmap-plan-standardization.md` and its plan.

This PRD closes the brief's four open questions — which principles make
the named set, how strict the first validation pass is (including the
mermaid-parser spike), how much altitude the two table profiles share,
and the enforcement surface for the lifecycle checks — and additionally
settles the `--auto` behavior of the value-confirmation step, which the
brief's decision-surfacing scope raised but did not number among its
open questions. Positions are recorded in the Decisions and Trade-offs
section with rationale grounded in the current skill code.

## Problem Statement

shirabe's tactical chain runs `/roadmap` to `/brief` to `/prd` to
`/design` to `/plan`. The roadmap and plan workflows sit at opposite
ends of that chain and already share more than they appear to: the same
lifecycle vocabulary, a reserved-section handoff where the roadmap stubs
an issues table and a dependency graph that the plan fills, and the same
spec-driven validator. The trouble is not that the workflows are
unrelated. It is that the shared parts were never named as shared, and
the conventions that should hold them together have drifted.

The author writing a roadmap or a plan is the affected user, and six
gaps make the drift concrete.

- **The issues table has several incompatible schemas in active use.**
  The plan keys its table on issues (`Issue | Dependencies | Complexity`)
  and still accepts a legacy separate-`Title` column set; the roadmap
  keys its reserved table on features (`Feature | Issues | Status`); and
  at least one committed roadmap diverges from even that
  (`Feature | Status | Downstream Artifact`). One section name spans two
  altitudes, and an author writing either doc has no single format to
  copy, so each new table perpetuates whichever variant the author saw
  first.

- **The dependency diagram has a canonical spec docs ignore.** A solid
  diagram spec already exists in `plan-doc-structure.md` (mermaid syntax
  rules, a fixed status-class palette, a legend), but committed docs use
  partial style sets, ad-hoc colors, inline-break labels, and differently
  worded legends. The spec is correct and unenforced.

- **The roadmap has no native path to its issues table.** The roadmap
  writes empty reserved placeholders and expects them filled later. The
  only fill path is to re-enter the plan workflow in a special mode that
  rewrites the placeholders through in-prose string surgery — not a
  script, the way the plan workflow populates its own table. A roadmap
  author who wants a populated table has to drive a second workflow
  against their own document and hope the string match holds.

- **The single-pr/multi-pr decision is buried, conflated, and not
  anchored on usable value.** The rule (default to one PR, escape to
  multiple only on a hard constraint) lives in a lazily loaded
  `phase-3-decomposition.md` reference, never appears on the skill
  surface, and sits tangled with the separate work-slicing decision. It
  also misses the thing that should drive the call: whether each PR lands
  usable value. When the input is a roadmap the plan goes multi-pr, which
  is the right outcome, but it reaches that outcome by mechanism (the
  input is a roadmap) rather than by the value principle, and nothing
  confirms each feature actually delivers observable incremental value.

- **Validation checks presence, never contents.** `internal/validate/`
  confirms required sections exist (FC04), frontmatter fields are present
  (FC01), status is valid (FC02), and status agrees between frontmatter
  and body (FC03). It never tokenizes a Markdown table or a fenced
  `mermaid` block — there is no table parser and no mermaid node/edge
  parser anywhere in the package. A doc with a malformed table, a table
  and diagram that disagree, or a dangling cross-reference passes as long
  as the headings are present.

- **The lifecycle is inconsistent, contradictory, and unenforced.** The
  states exist (Draft, Active, Done), but the terminal is three-way
  contradictory: the live `/work-on` cascade deletes a completed plan
  (`git rm`), `plan-doc-structure.md` still says move it to a
  `docs/plans/done/` archive, and a completed roadmap is kept forever.
  The transitions carry little discipline: a multi-pr plan or roadmap
  creates GitHub issues with no review gate, and nothing in CI holds a
  doc to the state its mode requires — a single-pr plan that should be
  ephemeral can reach main, and a multi-pr doc can merge before it is
  ready.

Underneath all six is the same root: the workflows are specified as
procedures with local rationale or none, and the few real principles
that exist are each trapped in one skill. An author follows the steps
without the reasons, so when a step does not fit their case they have
nothing to reason from. Most of the machinery already exists; the gap is
that the shared parts are not named as shared, the formats are not
defined once, and the principles that would let an author make the right
call are not surfaced where the call gets made.

## Goals

1. **Name a small, load-bearing principle set** that both workflows
   derive from instead of restating procedure, authored to be reusable
   by sibling doc types later but wired only to roadmap and plan in this
   work.

2. **Define the issues table once, with two altitude profiles.** One
   canonical framework — shared columns, shared validation, shared
   rendering — parameterized into a roadmap profile (feature-keyed) and a
   plan profile (issue-keyed), replacing the drifting schemas while
   preserving the altitude distinction.

3. **Promote the dependency-diagram spec into a shared reference both
   workflows consume, and enforce it in CI** so the spec stops being an
   unheld ideal.

4. **Extend validation from section-presence to table and diagram
   contents,** staged so the checks that need no new parser land first
   and the check that needs a mermaid parser lands later, behind a spike.

5. **Surface and re-anchor the single-pr/multi-pr decision.** Lift it to
   the skill surface, anchor it on usable value, de-conflate it from
   work-slicing, and add a value-confirmation guard that can fail.

6. **Give the roadmap a first-class scripted path to its issues table,**
   replacing the brittle in-prose string surgery of the plan re-entry.

7. **Install one enforced lifecycle with a single terminal.** Gate issue
   creation on approval (unless running under `--auto`, where the gate
   records and proceeds), rest at Active while the work lands, and retire
   by verify-then-delete — the work-completing PR marks the doc Done and
   deletes it atomically, so Done never reaches main — with two stateless
   CI checks holding docs to the states CI can observe.

## User Stories

**As a roadmap author who wants my issues table populated**, I want a
first-class scripted path built for the roadmap so that I get a
populated, correctly feature-keyed table without re-driving the plan
workflow against my own document or depending on a fragile string match.

**As a plan author deciding PR shape**, I want the single-pr/multi-pr
principle — every PR lands usable value, default to one, split only on a
hard constraint or genuine incremental value — on the skill surface and
separated from the work-slicing decision, so that I land the right call
because each PR's value is what I weighed, not the input's type.

**As an author whose table or diagram has drifted**, I want validation
to fail with a message naming the specific table or diagram defect — a
column out of schema, a row the diagram does not account for, a
cross-reference to a missing row — in both my local check and CI, so
that I catch the drift before merge instead of passing on headings alone.

**As an author starting a new roadmap or plan**, I want one shared
reference that defines the table format and the diagram convention once,
so that I copy a known-good shape parameterized to my altitude and
produce a document that conforms by construction.

**As an author moving a multi-pr doc through its lifecycle**, I want the
draft to stop for my approval before any GitHub issue is created — with
approval being the act that creates the issues and moves the doc to
Active — and I want the PR that completes the work to be the one where I
verify the result and delete the doc, so that issues are never filed
before I sign off and the finished doc gets a clean end with a forced
final review.

**As an author of an ephemeral single-pr plan**, I want CI to be red
while the plan file is present and green once I delete it, so that the
plan never reaches main and "gone before merge" is enforced without CI
having to know which commit is the merge.

**As a maintainer running `/roadmap` or `/plan` under `--auto`**, I want
the value-confirmation step and the issue-creation approval gate to each
record their judgment and continue rather than deadlock waiting for a
human who is not there, while still surfacing those judgments prominently,
so that batch and CI invocations keep their non-interactive guarantee.

## Requirements

### Functional Requirements

**R1: The named principle set.** The standardization defines exactly
five principles in a shared reference both workflows derive from. The set
is:

1. **Usable value is the unit of work.** Every PR and every roadmap
   feature delivers observable value on its own; split only for a hard
   constraint or genuine incremental value, never by mechanism.
2. **Default to the lowest ceremony.** Reach for the least machinery the
   work needs (one PR over many; a self-contained PLAN doc over GitHub
   issues) and escalate only when a named condition forces it.
3. **Decisions need a durable home.** A choice that affects downstream
   work or rests on a falsifiable assumption is recorded where a later
   reader finds it, not left implicit in the procedure.
4. **One canonical format per concern, defined once.** Each shared shape
   (the issues table, the dependency diagram) has a single source both
   workflows consume.
5. **Strictness tracks blast radius.** How hard a rule is enforced scales
   with the consequence of getting it wrong.

Each workflow's surfaced rules reference the principle they derive from.
The exact wording of each principle is the downstream design's to finalize;
the set membership and the meaning of each are fixed here.

**R2: Shared issues-table framework — shared core.** One issues-table
framework is defined once and consumed by both workflows. The shared core,
common to both profiles, is:

- A **key column** in position 1 — the primary entity link. The header
  label and link target are parameterized by profile (R3, R4).
- A **Dependencies column** — `None` or comma-separated clickable links
  to other rows' keys, with identical semantics at both altitudes.
- A **Status column** — an explicit completion/lifecycle marker for the
  row.

The shared core also defines shared **rendering**: an italic description
row of 1-3 sentences immediately following each entity row, and the
strikethrough-on-done rule applied across the entity row, its description
row, and a child reference row when present. (The convention that the
description rows read as a sequential build narrative top-to-bottom is
authoring guidance, not a validated property.)

**R3: Plan profile (issue-keyed).** The plan profile parameterizes the
shared core with:

- Key column header **`Issue`**, link form `[#N: <title>](<url>)`.
- A profile-specific **Complexity** column (`simple` / `testable` /
  `critical`).
- A profile-specific **child reference row** (`^_Child: ..._`) for
  `tracks-design` / `tracks-plan` issues.

The canonical plan table is the issue-keyed `Issue | Dependencies |
Complexity` shape. The legacy separate-`Title` plan form (`Issue | Title |
Dependencies | Complexity`) is migrated into the canonical shape by
folding the title into the issue link text; it is not perpetuated as a
permanent dual format.

**R4: Roadmap profile (feature-keyed).** The roadmap profile
parameterizes the shared core with:

- Key column header **`Feature`**, label form naming the feature.
- A profile-specific **Issues** column — the one-to-many fan-out (the
  list of issue links the feature decomposed into) that encodes the
  feature-to-issues altitude jump. This is the roadmap profile's defining
  addition.

The roadmap profile replaces the current `Feature | Issues | Status`
reserved stub and every committed roadmap-table divergence — including the
`Feature | Status | Downstream Artifact` and `Issue | Phase | Dependencies
| Label` shapes in the committed corpus. Migration of these existing
shapes into the roadmap profile is in scope; the per-document migration
mechanics are the downstream design's.

**R5: Shared dependency-diagram convention.** The existing canonical
diagram spec (mermaid syntax rules, the fixed status-class palette, the
legend) is promoted from `plan-doc-structure.md` into a shared reference
both workflows consume. The convention is defined once and applies
identically to roadmap and plan dependency graphs.

**R6: Validation content check — issues-table schema conformance.**
Validation checks that an issues table's column count and headers match
the doc's altitude profile and that row shape (entity row, description
row, child reference row where present) is well-formed. This check is
error-level in the first content-validation pass. It requires a new
Markdown table parser (none exists in `internal/validate/` today).

**R7: Validation content check — cross-reference existence.** Validation
checks that every value in a Dependencies cell names a key that exists as
a row in the same table. This check is error-level in the first
content-validation pass and reuses the R6 table parser. It is
document-local; no graph model is required.

**R8: Validation content check — table-diagram reconciliation (staged).**
Validation reconciles the issues table against the dependency diagram:
every table key appears as a diagram node and vice versa, and edges agree
with the Dependencies column. This check is **staged into a later
increment** than R6 and R7 because it is the only content check that
requires a new mermaid node/edge parser, and its retrofit blast radius is
the entire committed-diagram corpus. When it lands, it follows the
existing schema-gate precedent: it is introduced as a non-blocking notice
first, then promoted to error once the committed corpus conforms.

**R9: Mermaid-parser spike.** Before R8 can be specified, a feasibility
spike investigates what subset of mermaid `graph` syntax the committed
docs actually use, how to parse it without a full mermaid grammar, and how
strictly to reconcile (exact node-set equality versus subset). The spike
is an explicit upstream of the R8 increment and keeps R8 off the first
pass's path while making the dependency visible.

**R10: Single-pr/multi-pr decision surfaced and re-anchored.** The plan
workflow lifts the single-pr/multi-pr decision to the skill surface (out
of the lazily loaded reference), anchors it on the usable-value principle
(R1.1), and separates it from the work-slicing decision it is tangled with
today. The surfaced rule states the default (one PR) and its named escape
conditions (a hard constraint forces multiple, or each PR is independently
useful). A roadmap is multi-pr because each feature should deliver
observable incremental value as a cohesive deliverable — grounded in the
value principle, not reached by the mechanism "the input is a roadmap."

**R11: Value-confirmation guard.** A confirmation step checks that each
unit delivers observable incremental value: every feature for a roadmap,
and each PR for a plan whose split delivers incremental value (whether or
not a hard constraint also forces the split). The guard can fail: a unit
that is not a standalone increment is flagged as a mis-decomposition to
re-scope or merge with a neighbor, not waved through. The guard names the
specific failing unit and why it failed the value test.

**R12: Value-confirmation under `--auto`.** Under `--auto`, the R11 guard
does not hard-stop. It records a decision block per the existing
`decision-protocol.md` and continues. A unit that clearly delivers
standalone value is recorded with `status="confirmed"`. A unit that fails
the value test (R11 — not a standalone increment) or that the guard cannot
clearly classify either way (an ambiguous unit) is recorded with
`status="assumed"` and `high` review priority, which surfaces it in the
terminal summary and the PR body for the author to act on. Failing and
ambiguous units route to the same recorded outcome on purpose: both are
units the author must review, neither is waved through. The escalation
path (`status="escalated"`, spawn `/decision`) remains available for a
judgment ever deemed practically irreversible and is itself non-blocking
under `--auto`.

**R13: First-class roadmap-to-issues path.** The roadmap gets a scripted
path that populates its own issues table, keyed on features at the
roadmap's altitude, without re-driving the plan workflow against the
document and without depending on in-prose string surgery. The path is
native to the roadmap, mirroring how the plan workflow populates its own
table with a script rather than prose edits. When this path creates
GitHub issues, that creation is itself subject to the R14 approval gate
and its `--auto` record-and-proceed behavior — the scripted path does not
bypass the gate.

**R14: Enforced lifecycle — issue creation gated on approval.** A
multi-pr plan or roadmap finishes its draft and stops for the author's
approval before any GitHub issue is created. Approval is the act that
creates the issues and moves the doc to Active; issue creation is no
longer a silent side effect of finishing the draft.

Under `--auto`, the approval gate does not hard-stop. Mirroring the
value-confirmation guard (R12), it records an `assumed` approval decision
block per the existing `decision-protocol.md` at `high` review priority
(surfaced in the terminal summary and the PR body), then proceeds to
create the issues and move the doc to Active. The interactive stop is the
default; it applies "unless running under `--auto`."

**R15: One terminal — verify-then-delete, Done is ephemeral.** A multi-pr
plan or roadmap lives at Active across however many PRs the work takes.
The single PR that completes the work transitions the doc Active -> Done;
in that same PR the author verifies the delivered work and deletes the
doc — the transition, the verification, and the deletion land atomically
in one PR, which can only merge with the deletion included. Done is the
transient marker inside that verify-delete PR; it never reaches main. The
verify-delete PR is the forcing function for the author's final review of
the delivered work. This is the single terminal for both plans and
roadmaps — a deliberate change for roadmaps (which are kept forever
today) and a unification of the plan's self-contradicting terminal — and
it retires the stale move-to-`docs/plans/done/` archive wording.

**R16: Single-pr plan is ephemeral.** A single-pr plan lives only on its
own PR branch and is verified and deleted before that PR merges, so it
never reaches main.

**R17: CI lifecycle enforcement surface.** The lifecycle enforcement
runs as a **chain-aware whole-tree scan on the PR**, alongside (not
replacing) the existing changed-files doc-validator. The scan walks
the doc tree, identifies each artifact chain by inverting the
frontmatter `upstream:` edge from each PLAN and ROADMAP root, infers
the chain's posture from the PLAN's `execution_mode` and `status`,
and verifies every chain member is at the **passing state** for the
chain's posture. The `Lnn` check-code family carries the failures.

The five postures the scan distinguishes:

| Posture | Detection signal | BRIEF | PRD | DESIGN | PLAN |
|---------|------------------|-------|-----|--------|------|
| Multi-pr in-flight | multi-pr PLAN at Active | Accepted | Accepted or In Progress | Planned or Current | Active |
| Multi-pr work-completing | multi-pr PLAN at Done, still present | Done | Done | Current | DELETED (fails until git rm) |
| Multi-pr at-merge | multi-pr PLAN absent | Done | Done | Current | (absent) |
| Single-pr mid-PR | single-pr PLAN at Draft | Accepted | Accepted | Planned or Current | Draft |
| Single-pr at-merge | single-pr PLAN absent | Done | Done | Current | (absent) |

L01 fires whenever a chain member's status differs from the
passing state for the chain's posture. The two previous stateless
checks (a present multi-pr doc at non-Active; a present single-pr
PLAN at merge) are degenerate cases of L01 — both are "doc not at
passing state for this chain's posture" with posture-specific error
messages. A whole-tree scan is required because the model relates
docs the PR does not touch to docs it does touch through the chain
graph; a changed-files diff cannot see a doc the PR does not
modify.

The orphan-doc rule (an orphan BRIEF/PRD/DESIGN at its target state
passes; an orphan at non-terminal status whose own `upstream:`
points at an Active ROADMAP passes; every other orphan fails L02)
is settled in
`docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md`.
The multi-pr posture-detection mechanism (read the PLAN's
frontmatter `status:` field) is settled in
`docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md`.
Additional `Lnn` codes cover orphan-rule violations (L02), upstream
cycles (L03), missing chain members (L04), and defensive parsing
fallbacks (L05).

The existing changed-files validators keep running for content and
frontmatter checks; the lifecycle gate is a separate concern that
needs whole-tree visibility.

**R18: Verified deletion is a human act CI never performs but demands
indirectly.** CI never performs the deletion of a completed multi-pr
doc. But it does demand the deletion indirectly: the moment the
author transitions the PLAN to Done, L01 fires under the multi-pr
work-completing posture (PLAN passing state is DELETED), forcing the
author to include the deletion in that same PR. The same forcing
function fails any present single-pr PLAN at chain-completion time
under the single-pr at-merge posture. The two doc modes are
symmetric — a multi-pr doc at Done and a single-pr plan are both
ephemeral and both CI-forced-absent at merge. The verification of
the delivered work remains the human's act (CI cannot judge it);
CI's role is to make the resulting deletion non-optional by failing
the chain-aware passing-state check whenever the PLAN is present in
a posture whose passing state is DELETED.

### Non-Functional Requirements

**R19: Reuse existing validation infrastructure where possible.** R6 and
R7 extend the existing `internal/validate/` package and run through the
existing CLI and the existing reusable validation workflow. The only new
parsing machinery the first pass introduces is the Markdown table parser
R6 and R7 share. The mermaid parser (R8/R9) is the sole net-new parser and
is deferred to its own increment.

**R20: Incremental rollout, no retroactive breakage on day one.** The
first content-validation pass (R6, R7) must not turn CI red on
already-committed docs solely because a higher-strictness check
(reconciliation, R8) has not yet been satisfied. R8 follows the
notice-then-error promotion path so the committed-diagram corpus can be
reconciled before reconciliation becomes blocking.

**R21: No change to sibling artifact types beyond convention adoption.**
The roadmap and plan workflows are the drivers. Other doc types may
consume the shared table and diagram conventions where they already have a
table or a diagram, but reshaping their own formats, naming, or lifecycles
is out of scope.

**R22: Public-visibility cleanliness.** All shared references, surfaced
rules, and validation messages are public-repo clean: no private repos,
paths, filenames, issue numbers, or pre-announcement features.

## Acceptance Criteria

- [ ] A shared reference names exactly the five principles in R1, and both
  the roadmap and plan workflow surfaces reference the principle each rule
  derives from.
- [ ] A single issues-table framework defines the shared core (key column,
  Dependencies, Status) and the shared rendering (italic description row,
  strikethrough-on-done) in one place, consumed by both workflows.
- [ ] The plan profile renders `Issue | Dependencies | Complexity` with the
  child reference row available; a legacy separate-`Title` plan table is
  migrated into the canonical shape rather than accepted as a permanent
  variant.
- [ ] The roadmap profile renders a feature-keyed table with the `Issues`
  fan-out column and replaces the prior reserved stub and every committed
  roadmap-table divergence (including the `Feature | Status | Downstream
  Artifact` and `Issue | Phase | Dependencies | Label` shapes).
- [ ] The dependency-diagram convention lives in one shared reference both
  workflows consume, and CI fails a roadmap or plan whose diagram violates
  the palette or legend convention.
- [ ] Running validation against an issues table whose columns do not match
  its altitude profile fails with an error naming the schema defect (R6).
- [ ] Running validation against a table with a Dependencies value that
  names no existing row fails with an error naming the dangling
  cross-reference (R7).
- [ ] Table-diagram reconciliation (R8) is not error-level in the first
  pass; it lands in a later increment as a notice first, gated on the
  mermaid-parser spike (R9).
- [ ] A mermaid-parser spike artifact exists and is named as the upstream
  of the reconciliation increment before reconciliation is specified.
- [ ] The plan skill surface states the single-pr/multi-pr default and its
  named escape conditions, anchored on usable value and separated from the
  work-slicing decision (R10).
- [ ] The value-confirmation guard flags a roadmap feature or plan PR that
  is not a standalone increment, naming the unit and the reason, and does
  not wave it through (R11).
- [ ] Under `--auto`, the value-confirmation guard records a confirmed or
  assumed decision block (assumed at `high` review priority for a
  failing/ambiguous unit) and continues without hard-stopping; the assumed
  block appears in the PR body and terminal summary (R12).
- [ ] A roadmap author populates the roadmap's issues table through a
  scripted, feature-keyed path without re-entering the plan workflow and
  without in-prose string surgery (R13).
- [ ] In an interactive run, a multi-pr plan or roadmap creates no GitHub
  issue until the author approves; approval creates the issues and moves the
  doc to Active (R14).
- [ ] Under `--auto`, the approval gate records an `assumed` approval
  decision block (high review priority, in the PR body and terminal summary)
  and creates the issues and moves the doc to Active without hard-stopping
  (R14).
- [ ] A multi-pr plan or roadmap lives at Active while work lands; the
  work-completing PR transitions it to Done, verifies the work, and deletes
  the doc atomically in that one PR, so Done never reaches main; the stale
  move-to-`docs/plans/done/` wording is gone (R15).
- [ ] A single-pr plan exists only on its PR branch and is deleted before
  that PR merges (R16).
- [ ] CI Check A fails when any roadmap or multi-pr plan present in the tree
  has a status other than Active (a present Draft or a present Done fails),
  evaluated by a whole-tree scan (R17).
- [ ] CI Check B fails while any `execution_mode: single-pr` PLAN exists in
  the tree and passes once it is deleted (R17).
- [ ] CI never performs the deletion of a completed multi-pr doc but demands
  it indirectly: a present Done multi-pr doc fails Check A, forcing the
  deletion into the same PR, symmetric with single-pr fail-while-present
  (R18).
- [ ] The first content-validation pass introduces no new validation
  binary or parallel pipeline: R6 and R7 extend the existing
  `internal/validate/` package and run through the existing CLI and
  reusable workflow, and the only new parser in the first pass is the
  shared Markdown table parser (R19).
- [ ] The first content-validation pass does not turn CI red on
  already-committed docs solely for unmet reconciliation strictness (R20).
- [ ] No sibling artifact type's own format, naming, or lifecycle is
  changed by this work; sibling types are touched only where they adopt the
  shared table or diagram convention (R21).
- [ ] A scan of the shared references, the surfaced workflow rules, and the
  validation messages finds no private repo names, paths, filenames, issue
  numbers, or pre-announcement features (R22).

## Out of Scope

This PRD scopes the standardization of the roadmap and plan workflows
around shared, principle-driven conventions. It explicitly excludes:

- **Implementation specifics.** The shared-reference file layout, the
  validation check codes, the roadmap-to-issues script interface, the
  mermaid-parser internals, and the final principle wording are the
  downstream design's job, not this PRD's.
- **Issue-tracker mechanics.** Validation here checks a document's own
  table and diagram contents. Network-dependent checks against live
  issue-tracker state are a separate, optional concern that can follow as a
  second workflow if warranted at all.
- **Reshaping sibling artifact types.** Other doc types may adopt the
  shared table and diagram conventions where they already have a table or a
  diagram (R21), but changing their own formats, naming, or lifecycles is
  out.
- **The progress-tracking tables some docs carry.** These are a separate
  concern from the issues table this work standardizes.
- **A branch-protection / push-to-main gate.** The stateless PR-time
  whole-tree scan (R17) is equivalent to an at-merge reading for both
  checks. A branch-protection gate is held in reserve as a later hardening
  option if a stronger at-the-merge-commit guarantee is ever needed; it is
  not part of this work.
- **Promoting reconciliation to error-level in the first pass.**
  Reconciliation (R8) is deliberately staged into a later increment; making
  it blocking on day one is out of scope.

## Known Limitations

- **The first pass leaves diagram drift uncaught.** Until the R8
  reconciliation increment lands, a table and diagram that disagree pass
  the first content-validation pass (R6/R7 catch schema and cross-reference
  defects, not table-diagram disagreement). This is a deliberate
  consequence of staging by blast radius; the gap closes when R8 ships.

- **An `--auto` run can produce a mis-decomposed roadmap that reaches the
  draft/PR stage.** Because R12 is record-and-proceed, a failed value
  judgment under `--auto` does not block the run; the author must notice
  the `high`-priority assumed block in the PR body or terminal summary and
  act on it.

- **An `--auto` run can file GitHub issues without an interactive human
  approval.** Because R14's approval gate is record-and-proceed under
  `--auto` (mirroring R12), an auto-run creates the issues and moves the
  doc to Active after recording an `assumed` approval block rather than
  waiting for a human. The loud `high`-priority assumed block (PR body +
  terminal summary) is the mitigation; the value-confirmation guard
  (R11/R12) and the human's later review of the resulting issues are
  backstops. This is the deliberate cost of keeping `--auto`
  non-interactive; an operator who wants a hard human approval runs
  interactively rather than under `--auto`.

- **The whole-tree scan re-reads unchanged docs on every PR.** Check A and
  Check B scan the full tree rather than the diff, so an unrelated PR can
  fail because of a doc it did not touch (for example, a single-pr plan
  left on the branch, or a multi-pr doc someone marked Done without
  deleting). This is the intended behavior — it is how presence-without-
  touch becomes observable and how the Done-must-delete forcing function
  works — but it means a doc's lifecycle state can block a PR that has
  nothing to do with it.

## Decisions and Trade-offs

### Decision 1: Five principles, collapsing "one canonical format" and "formats defined once"

**Decision.** The named set is five principles (R1). The brief's two
candidates "one canonical format per concern" and "formats defined once"
merge into a single principle (R1.4); the other four candidates each earn
a place unchanged.

**Alternatives considered.**

- *Keep all six as distinct principles.* Rejected: "one canonical format
  per concern" is the outcome and "formats defined once" is the mechanism
  that produces it — the brief itself fuses them in the User Outcome.
  Surfacing both would be the decorative move the brief warns against.
- *Collapse "lowest-ceremony default" into "usable value."* Rejected: they
  look adjacent but answer different questions. Lowest-ceremony governs
  artifact ceremony (one PR or many; a PLAN doc or GitHub issues); usable
  value governs the shape of the deliverable (does each unit land observable
  value). They can pull in opposite directions, and an author needs both
  visible to land the single-pr/multi-pr call.

**Rationale.** Each of the five is the stated reason behind machinery
already in the skills, so each lets an author reason at an edge the
procedure does not cover — the brief's root-cause fix. Five clears the
brief's "small enough to be load-bearing rather than decorative" bar, and
the one merge removes the only genuine redundancy.

### Decision 2: First validation pass is schema conformance plus cross-reference; reconciliation is staged behind a spike

**Decision.** The first content-validation pass lands issues-table schema
conformance (R6) and cross-reference existence (R7) at error-level.
Table-diagram reconciliation (R8) is staged into a later increment, gated
on a mermaid-parser spike (R9), and lands as a notice before being promoted
to error.

**Alternatives considered.**

- *Land all three content checks strict on day one.* Rejected on two
  grounds. Reconciliation is the only check that needs a mermaid node/edge
  parser, which does not exist in `internal/validate/` today. And its
  retrofit blast radius is the entire committed-diagram corpus — every
  committed doc with a hand-built diagram that drifts from its table would
  turn CI red on the next PR that touches it, even a prose-only PR, because
  the validator re-checks the whole changed file.
- *Adopt all three incrementally as notices.* Rejected: schema conformance
  and cross-reference have a small, localized blast radius (a malformed row
  or dangling link is rarer and more contained than diagram drift) and need
  no new parser, so holding them back as notices would weaken the first
  pass for no retrofit benefit.

**Rationale.** This is the seam the work splits on: two checks share one
new table parser and have a contained retrofit cost; the third needs a
parser that does not exist and would break the committed corpus. Strictness
tracks blast radius (R1.5), and the repo already proved incremental
validation works via the existing schema-version notice gate.

### Decision 3: Smallest table split — shared core of three columns, one profile-specific column each

**Decision.** The shared core is the key column (parameterized),
Dependencies, and Status, plus shared validation and rendering (R2). The
plan profile adds Complexity and the child reference row (R3); the roadmap
profile adds the Issues fan-out column (R4). The legacy separate-`Title`
plan form is migrated, not kept as a permanent dual format.

**Alternatives considered.**

- *Collapse the two altitudes into one profile.* Rejected: the brief
  requires the altitude distinction to survive (a roadmap keys on features,
  a plan keys on issues). The framework carries two profiles rather than
  collapsing into one.
- *Keep the legacy separate-`Title` plan table as a permanent accepted
  variant.* Rejected: the brief's goal is to replace the drifting schemas.
  "Still accepted by CI" narrows to a migration path, not a perpetual second
  format; the title folds into the issue link text the canonical form
  already uses.

**Rationale.** Three concerns are common to both altitudes — identity, a
dependency relationship, a status marker — so they are defined once and
validated and rendered once. The one real altitude difference is isolated
into the key column's parameterization plus exactly one profile-specific
column each: Complexity is an issue property (no feature equivalent), and
the Issues fan-out is the roadmap's whole reason to exist. The child
reference row is plan-only because it models an issue spawning a child
artifact, which has no feature-level analogue. This is the smallest split
that preserves the altitude distinction while ending the multi-schema drift.

### Decision 4: Whole-tree scan, Active-only Check A, and an ephemeral Done; no branch-protection gate

**Decision.** Both lifecycle checks run as a whole-tree scan on the PR,
alongside the existing changed-files validator (R17). Check A is
Active-only: a present multi-pr doc must be `Active`, and a present `Done`
fails. Done is ephemeral — the work-completing PR transitions Active ->
Done, the author verifies and deletes the doc, and all three land
atomically in that one PR, so Done never reaches main (R15). This also
settles how the brief's verify-then-delete / VERIFIED step is realized:
the verify-delete PR is the forcing function. A push-to-main /
branch-protection gate is not used in this work.

**Alternatives considered.**

- *Carry the checks on the existing changed-files doc-validator.* Rejected
  for Check B: the existing validators run on the PR's changed-files diff
  (confirmed in the workflow files), and a diff cannot see a single-pr plan
  the PR does not touch. Presence-without-touch is invisible to a diff, so
  the changed-files surface provably cannot enforce "absent at merge."
- *Accept `Done` at merge — let a completed multi-pr doc linger in the tree
  until a separate deletion PR.* Rejected: a Done doc that lingers on main
  loses the forcing function for the author's final review of the delivered
  work, and it splits the terminal across two PRs (mark-Done, then
  delete-later) with nothing compelling the second. Making Done ephemeral —
  verify and delete in the same PR that marks Done — keeps the final-review
  gate and makes the two doc modes symmetric (a multi-pr Done doc and a
  single-pr plan are both CI-forced-absent at merge).
- *Use a push-to-main / branch-protection gate for an at-the-merge-commit
  reading.* Rejected for v1: both checks are stateless presence/status
  tests, so evaluating them on the PR's checked-out tree is equivalent to
  evaluating them at merge — the brief leans on exactly this ("without CI
  having to know which commit is the merge"). The gate adds wiring cost for a
  property the PR-time scan already delivers; it is held in reserve as later
  hardening.

**Rationale.** Only a whole-tree scan observes presence-without-touch,
which collapses the surface choice for Check B; the same scan handles
Check A's status reading. Active-only Check A plus an ephemeral Done makes
the verify-delete PR a hard forcing function for the final human review and
makes multi-pr docs and single-pr plans symmetric — both ephemeral, both
CI-forced-absent at merge (R18). The verification stays a human act CI
cannot judge; CI makes the resulting deletion non-optional by failing any
present non-Active multi-pr doc.

### Decision 5: Both `--auto` human-judgment gates are record-and-proceed, not require-human

**Decision.** Under `--auto`, both the value-confirmation guard (R12) and
the issue-creation approval gate (R14) record a decision block and
continue rather than hard-stop. Each records `confirmed` on a clear pass
and `assumed` at `high` review priority otherwise — the value guard on a
failing or ambiguous unit, the approval gate on every auto-run (an
approval CI cannot give). Both surface in the PR body and terminal summary.

**Alternatives considered.**

- *Require a human even under `--auto` (hard-stop).* Rejected: either gate
  would then break `--auto`'s non-interactive contract — a CI or batch
  invocation would deadlock waiting for a human who, by definition, is not
  there. The brief's thrust is reducing special cases, not adding one, and
  leaving R14 silent on `--auto` while R12 specified record-and-proceed was
  an asymmetry worth closing.
- *Silently pass under `--auto`.* Rejected: both gates must stay loud.
  Routing to `status="assumed"` with `high` review priority puts the
  judgment in the PR body and terminal summary so the human sees it
  prominently, just not as a blocking prompt.

**Rationale.** Both are judgment-call gates whose consequences are
reversible and backstopped. The trade-off the approval gate carries is
sharper than the value guard's: under `--auto` it files real GitHub issues
without an interactive human approval (see Known Limitations). It is still
the right call — record-and-proceed is the settled, shared pattern in
`decision-protocol.md` for reversible judgment points, the loud assumed
block makes the un-approved creation visible, and the value-confirmation
guard plus the human's later review of the resulting issues are backstops.
Keeping the two gates symmetric also avoids a special case authors and the
harness would otherwise have to track.

## Downstream Artifacts

Forthcoming work flowing from this PRD:

- **`DESIGN-roadmap-plan-standardization.md`** (in
  `docs/designs/current/`). Implementation shape: the shared-reference
  layout, the validation check codes, the roadmap-to-issues script
  interface, the table parser, and the final principle wording. Picks up
  the Decisions and Trade-offs positions and operationalizes them.
- **A mermaid-parser spike** (R9), the named upstream of the
  reconciliation increment (R8).
- **Implementation issues** — created from the design via `/plan`, covering
  the shared references, the two table profiles, the diagram-convention
  enforcement, the schema-conformance and cross-reference checks, the
  decision-surfacing fixes, the roadmap-to-issues path, the lifecycle
  changes, and the CI whole-tree scan.

## Related

- **Upstream brief:** `docs/briefs/BRIEF-roadmap-plan-standardization.md`.
- **Current workflows being standardized:** `/roadmap`
  (`skills/roadmap/`), `/plan` (`skills/plan/`).
- **Format references the standardization unifies:**
  `skills/roadmap/references/roadmap-format.md`,
  `skills/plan/references/quality/plan-doc-structure.md`.
- **Validation precedents:** `internal/validate/formats.go` (Formats-map
  pattern), `internal/validate/checks.go` (FC01-FC04 and the SCHEMA-notice
  incremental gate).
- **Decision-protocol precedent for `--auto`:**
  `references/decision-protocol.md` (the record-and-proceed pattern for
  judgment-call decision points).

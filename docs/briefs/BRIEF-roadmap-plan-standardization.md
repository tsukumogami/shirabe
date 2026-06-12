---
schema: brief/v1
status: Done
problem: |
  The roadmap and plan workflows are procedure-rich but principle-poor.
  The issues table has four drifting schemas, the dependency diagram has
  a canonical spec docs apply inconsistently, the roadmap has no native
  path to its own issues table, the single-pr/multi-pr decision is buried
  and not anchored on usable value, the document lifecycle is inconsistent
  and unenforced (no review gate before issues are created, no clean
  terminal), and validation checks section presence but never table or
  diagram contents.
outcome: |
  Skill authors get standardized, principle-driven roadmap and plan
  workflows: the issues table and dependency diagram are defined once and
  reused, the single-pr/multi-pr decision is surfaced and anchored on
  usable value, the roadmap has a first-class path to its issues table, and
  validation checks structure and content. An author reaches for one
  canonical format instead of reinventing one.
---

# BRIEF: roadmap-plan-standardization

## Status

Done

This brief stops before requirements articulation. The follow-on PRD
(`PRD-roadmap-plan-standardization.md`) owns the requirements, and the
design after it owns the implementation specifics — the exact shared
reference layout, the validation check codes, the script interfaces, and
the principle wording.

The framing emerged from exploration rather than an upstream roadmap, so
this brief has no `upstream:` field. The exploration findings the brief
draws on are the grounding, not a parent artifact.

## Problem Statement

shirabe's tactical chain runs `/roadmap` to `/brief` to `/prd` to
`/design` to `/plan`. The roadmap and plan workflows sit at opposite ends
of that chain and already share more than they look like they do: the
same lifecycle vocabulary, a reserved-section handoff where the roadmap
stubs an issues table and a dependency graph that the plan fills, and the
same spec-driven validator. The trouble isn't that the two workflows are
unrelated. It's that the shared parts were never named as shared, and the
conventions that should hold them together have drifted.

Six gaps make the drift concrete.

- **The issues table has several incompatible schemas in active use.** The
  plan workflow keys its table on issues (and still accepts a legacy column
  set); the roadmap keys its reserved table on features; and a committed
  roadmap diverges from even that. One section name spans two altitudes —
  feature-level and issue-level — and an author writing either doc has no
  single format to copy, so each new table perpetuates whichever variant the
  author happened to see first. (Progress-tracking tables some docs also
  carry are a separate concern, not part of this issues-table work.)

- **The dependency diagram has a canonical spec docs ignore.** A solid
  diagram spec already exists in one reference, but committed docs use
  partial style sets, ad-hoc colors, inline-break labels, and differently
  worded legends. The spec is correct and unenforced, so it
  documents an ideal nobody is held to.

- **The roadmap has no native path to its issues table.** The roadmap
  writes empty placeholders for its issues table and expects them filled
  later. The only way to fill them is to re-enter the plan workflow in a
  special mode that rewrites the placeholders through brittle in-prose
  string surgery — not a script, the way the plan workflow populates its
  own table. A roadmap author who wants a populated table has to drive a
  second workflow against their own document and hope the string match
  holds.

- **The single-pr/multi-pr decision is buried, conflated, and not
  anchored on usable value.** A rule is stated — default to a single PR,
  escape to multiple only on a hard constraint — but it lives in a lazily
  loaded reference, never appears on the skill surface, and sits tangled
  with a separate decision about how to slice the work. It also misses the
  thing that should drive the call: whether each PR lands usable value.
  When the input is a roadmap the plan workflow goes multi-pr, which is the
  right outcome — every roadmap feature should be an increment of
  observable value — but it reaches that outcome by mechanism (the input
  is a roadmap) rather than by the value principle, and nothing confirms
  that each feature actually delivers observable incremental value. The
  same blind spot lets a roadmap sequence features by technical building
  block instead of by the value each delivers. The tangle and the missing
  value-orientation are the likely causes of authors landing the wrong
  call.

- **Validation checks presence, never contents.** The validator confirms
  that required sections exist, that frontmatter fields are present, and
  that status agrees between frontmatter and body. It never looks inside
  the issues table or the dependency graph it requires. A doc with a
  malformed table, a table and diagram that disagree, or a dangling
  cross-reference passes validation as long as the headings are there.

- **The lifecycle is inconsistent, contradictory, and unenforced.** The
  states exist (Draft, Active, Done), but the terminal is three-way
  contradictory today: the live `/work-on` cascade deletes a completed plan
  (`git rm`), the plan reference doc still says move it to a `done/` archive,
  and a completed roadmap is kept forever as a permanent record. Plans and
  roadmaps terminate in opposite ways, and the plan's own terminal disagrees
  with itself. The transitions carry little discipline beyond a client-side
  transition script: a multi-pr plan or roadmap creates GitHub issues with no
  review gate (the cascade can even auto-complete a roadmap with no human
  sign-off), and nothing in CI holds a doc to the state its mode requires — a
  single-pr plan that should be ephemeral can reach main, a multi-pr doc can
  merge before it is ready, and issues get created before anyone approved
  them.

Underneath all six is the same root: the workflows are specified as
procedures with local rationale or none, and the few real principles that
do exist are each trapped in one skill and never generalized. An author
follows the steps without the reasons, so when a step doesn't fit their
case they have nothing to reason from. The gap isn't missing
machinery — most of the structure already exists. The gap is that the
shared parts aren't named as shared, the formats aren't defined once, and
the principles that would let an author make the right call aren't
surfaced where the call gets made.

## User Outcome

A skill author writing a roadmap or a plan works from one set of shared
conventions instead of reconstructing them per document. There is one
canonical issues-table format and one canonical dependency-diagram
format, each defined in a single place and consumed by both workflows, so
the author copies a known-good shape rather than picking among several. The
altitude distinction that matters — a roadmap keys its table on features,
a plan keys its table on issues — survives, because the shared format
carries two profiles rather than collapsing into one.

When the author reaches the single-pr/multi-pr decision, the principle is
in front of them on the skill surface: every PR should land usable value,
so default to one PR and split only when a hard constraint forces it or
when the work delivers value incrementally, each PR independently useful (a
walking skeleton is one such split). The rule is stated as that default
with its named escape conditions, separated from the unrelated slicing
decision it used to be tangled with. A roadmap is multi-pr because each of
its features should be an increment of observable value — a cohesive
deliverable in its own right — so the outcome is grounded in the value
principle, not reached by mechanism. A confirmation step tests that: it
checks each unit delivers observable incremental value — every feature for
a roadmap, and each PR for a plan whose split delivers incremental value
(whether or not a hard constraint also forces the split). It is a guard
that can fail: a roadmap feature that isn't a standalone increment signals
the roadmap is mis-decomposed and should be re-scoped or merged with a
neighbor, not waved through. The author lands the right call because the
reasoning is visible at the point of decision, not buried in a reference
they would have to know to load.

A roadmap author who wants their issues table populated gets there
through a first-class path built for the roadmap, not by re-driving the
plan workflow against their own document and hoping a string match holds.
And when any doc's table or diagram drifts from the canonical
format — a malformed row, a table and diagram that disagree, a
cross-reference to an issue that isn't in the table — validation catches
it, in local checks and in the same review surface where the rest of the
format spec is already enforced.

The document lifecycle carries discipline and one consistent terminal. A
multi-pr plan or roadmap finishes its draft and stops for the author's
approval before any GitHub issue is created — creating the issues is the
act of approving, the move to Active, not a silent side effect. The doc
rests at Active while the work lands, reaches Done when the work is
complete, and is retired by deletion once the author verifies the delivered
work — the same verify-then-delete end for both plans and roadmaps. That
replaces today's split, where a completed plan is already deleted by the
cascade but a completed roadmap is kept forever; unifying on deletion is a
deliberate change for roadmaps. A single-pr plan is different: it is
ephemeral, lives only on its own PR branch, and is verified and deleted
before that PR merges, so it never reaches main. CI holds docs to the
states it can see: a multi-pr doc may only merge in Active, and a single-pr
plan must be absent at merge — CI fails while one is present and passes once
it is deleted, which makes "gone before merge" enforceable without CI having
to know which commit is the merge. The verified-deletion of a multi-pr doc
stays a human act CI permits rather than performs.

Behind each of these is the same shift: the workflows derive from a small
set of stated principles instead of restating procedure. An author who
hits a case the steps don't cover has the reasons to fall back on, so the
workflows stay usable at their edges instead of only down their happy
path.

## User Journeys

Five journeys exercise the standardization from different entry points.
Each names the user, the trigger, and the outcome shape.

### Journey 1: Roadmap author populating the issues table

A roadmap author has sequenced their features and wants the roadmap's
issues table filled in. Today the only path is to re-enter the plan
workflow in a special mode that rewrites the roadmap's placeholders
through in-prose string surgery. With the standardization, the author
reaches a first-class path built for the roadmap: the table populates
through the roadmap's own scripted path, keyed on features at the
roadmap's altitude, without driving a second workflow against the
document or depending on a fragile string match. The outcome is a
populated, correctly-keyed issues table the author got to directly.

This journey validates that the roadmap-to-issues path is native to the
roadmap, not borrowed from the plan workflow.

### Journey 2: Plan author landing the single-pr/multi-pr call

A plan author is decomposing a design and has to decide whether the work
ships as one PR or several. The principle — every PR lands usable value,
so default to one and split only when a hard constraint forces it (a
cross-repo landing order, a workflow that must reach main before it can be
invoked) or when each PR is independently useful — is on the skill surface
in front of them, separated from the unrelated decision about how to slice
the work. The author's input is a design rather than a roadmap, so nothing
forces a multi-PR split by mechanism; they check their case against the
value test and the escape conditions and land the right call. The outcome
is a decomposition with the correct PR shape, chosen because each PR's
value was the thing weighed, not the input's type.

This journey validates that anchoring the decision on usable value,
surfacing it, and de-conflating it from work-slicing fixes the misfires
the buried, mechanism-driven version produced.

### Journey 3: Author hitting a validation failure on table drift

An author commits a roadmap or plan whose issues table has drifted from
the canonical format — a column out of the schema, a row the dependency
diagram doesn't account for, a cross-reference to an issue that isn't in
the table. Instead of passing because the section headings are present,
validation fails with a message naming the specific table or diagram
defect, both in the author's local check and in CI on the pull request.
The outcome is a caught drift the author fixes before merge, on the same
review surface where the rest of the format spec is already enforced.

This journey validates that validation moved from section-presence to
table and diagram content, and that the new checks run where existing
ones do.

### Journey 4: Author reaching for the one canonical format

An author starting a new roadmap or plan needs an issues table and a
dependency diagram. Rather than searching prior docs and copying whichever
variant they find — and propagating one of several schemas or a divergent
legend — they reach for the single shared reference that defines the
table format and the diagram convention once. They consume the canonical
shape, parameterized to their document's altitude, and produce a table and
diagram that match every other doc built from the same reference. The
outcome is a new document that conforms by construction, not by the
author's luck in which example they copied.

This journey validates that defining the formats once, in a shared place
both workflows consume, ends the per-document reinvention.

### Journey 5: Author moving a doc through its lifecycle

A plan author finishes decomposing a multi-pr plan. Instead of the
workflow filing GitHub issues immediately, the draft stops for the
author's review; the author approves, and that approval — the move to
Active — is what creates the issues. The author would not have wanted
issues filed before they signed off, and now they aren't. Later, when the
work the plan tracked is complete, the doc rests at Done until the author
reviews the delivered result; the author verifies it, and the doc is
retired rather than left behind. A single-pr plan never reaches that point
on the main branch at all — it lives only on its own PR and is gone before
that PR merges.

This journey validates that the lifecycle gates issue creation on approval
and gives a completed doc a clean, enforced end.

## Scope Boundary

This brief, and the downstream PRD it points at, cover standardizing the
roadmap and plan workflows around shared, principle-driven conventions.
The scope holds the following inside:

- **A reusable principle set** the roadmap and plan workflows derive from
  rather than restate — authored to be reusable by sibling doc types later,
  though this work wires only the roadmap and plan workflows to it — a small,
  named set covering
  the lowest-ceremony default, decisions needing a durable home, one
  canonical format per concern, strictness tracking blast radius, formats
  defined once, and usable value as the unit of work (every PR and every
  roadmap feature delivers usable value; split only for a hard constraint
  or genuine incremental value, never by mechanism).
- **A shared issues-table framework with two altitude profiles.** One
  canonical table framework — shared columns, shared validation, shared
  rendering — parameterized into a roadmap profile (feature-keyed) and a
  plan profile (issue-keyed), replacing the four drifting schemas while
  preserving the altitude distinction.
- **A shared dependency-diagram convention with enforcement.** The
  existing canonical diagram spec promoted into a shared reference both
  workflows consume, with its style palette and legend enforced in CI so
  the spec stops being an unheld ideal.
- **Validation content checks.** Extending validation from
  section-presence to table and diagram contents: schema conformance for
  the issues table, reconciliation between the table and the dependency
  diagram, and cross-reference existence.
- **The decision-surfacing fixes.** Encoding the usable-value principle
  into both the plan and roadmap workflows: lifting the single-pr/multi-pr
  decision to the skill surface, anchoring it on usable value, and
  decoupling it from the work-slicing decision. A roadmap stays multi-pr
  because each feature should deliver observable incremental value as a
  cohesive deliverable — re-grounded in the value principle rather than
  reached by mechanism — and a confirmation step (always for a roadmap, and
  for a plan whose split delivers incremental value, whether or not a hard
  constraint also forces it) checks that each feature or PR actually does. It
  can fail: a feature that isn't a standalone increment flags a mis-decomposed
  roadmap to re-scope rather than waving it through. Plus giving the roadmap a
  first-class path to its issues table in place of the brittle string surgery
  in the plan re-entry.
- **An enforced document lifecycle with one terminal.** A shared lifecycle
  for plan and roadmap docs: a multi-pr doc finishes its draft and stops for
  approval before issues are created (approval is the move to Active); it
  reaches Done when the work is complete; and the author's verification
  retires it by deletion. This unifies today's split terminal — a completed
  plan is already deleted by the work-on cascade, a completed roadmap is kept
  forever, and the plan reference doc still says move-to-`done/`; the
  standardization makes verify-then-delete the single terminal for both (a
  deliberate change for roadmaps) and retires the stale move-to-archive
  wording. A single-pr plan is ephemeral — it lives only on its PR branch and
  is deleted before that PR merges. CI enforces the states it can observe: a
  multi-pr doc may only merge in Active, and a single-pr plan must be absent
  at merge (CI fails while it is present, passes once it is deleted). The
  verified-deletion of a multi-pr doc is a human act CI permits, not one it
  performs. The precise transitions, how the virtual VERIFIED step is
  realized, and the enforcement surface for the CI checks are the downstream
  design's.

The scope explicitly excludes:

- **The implementation specifics.** This brief frames the standardization
  and its boundary. How the shared references are laid out, what the
  validation check codes are, how the roadmap-to-issues path is scripted,
  and the exact wording of the principles are the downstream design's job,
  not this brief's.
- **The issue-tracker mechanics.** Validation here checks a document's
  own table and diagram contents. Network-dependent checks against live
  issue-tracker state are a separate, optional concern the standardization
  does not require — they can follow as a second workflow if they're
  warranted at all.
- **Changing other artifact types beyond aligning them.** The roadmap and
  plan workflows are the drivers. Other doc types may consume the shared
  table and diagram conventions, but reshaping their own formats, naming,
  or lifecycles is out — the only change to a sibling type is adopting the
  shared conventions where it already has a table or a diagram.

## Open Questions

These surface for the downstream PRD to resolve. None block this brief.

1. **Which principles make the named set.** The brief names six candidate
   principles. Whether all six earn a place in the surfaced set, or whether
   some collapse together or stay implicit, is a framing call the PRD
   settles against the goal of a set small enough to be load-bearing rather
   than decorative.

2. **How strict the first validation pass is.** Content validation can
   land strict (schema conformance, full table-diagram reconciliation,
   cross-reference existence all at once) or adopt incrementally the way
   the existing schema-gate did. The PRD picks the initial strictness
   against the cost of retrofitting already-committed docs.

3. **How much altitude the two table profiles share.** The framework
   reuses columns, validation, and rendering across the roadmap and plan
   profiles, but the exact split between shared and profile-specific
   structure is undecided. The PRD names the shared core and the
   per-profile additions.

4. **The enforcement surface for the lifecycle checks.** Scope commits the
   two CI checks observable on a stateless per-PR pass: a multi-pr doc may
   only merge in Active, and a single-pr plan must be absent at merge. What
   stays open is the surface that carries them — the existing PR
   doc-validator, a whole-tree scan, or a push-to-main / branch-protection
   gate — and how the virtual VERIFIED step (the human verify-then-delete) is
   realized. The PRD and design settle these.

## Downstream Artifacts

- **`PRD-roadmap-plan-standardization.md`** — requirements articulation
  for the standardization: the principle set, the shared issues-table
  framework and its two profiles, the diagram convention and its
  enforcement, the validation content checks, and the decision-surfacing
  fixes. Lives in `docs/prds/`. (planned)
- **`DESIGN-roadmap-plan-standardization.md`** — implementation shape,
  picked up after the PRD lands: the shared-reference layout, the
  validation check codes, the roadmap-to-issues script interface, and the
  principle wording. Lives in `docs/designs/current/`. (planned)

## References

- Brief structural precedents: `docs/briefs/BRIEF-shirabe-strategy-skill.md`,
  `docs/briefs/BRIEF-shirabe-brief-skill.md`.
- Brief format reference: `skills/brief/references/brief-format.md`.

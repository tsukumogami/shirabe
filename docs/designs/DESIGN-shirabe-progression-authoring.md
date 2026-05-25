---
status: Proposed
upstream: docs/prds/PRD-shirabe-charter-skill.md
problem: |
  shirabe ships strategic and tactical children (`/vision`,
  `/strategy`, `/roadmap`, `/prd`, `/design`, `/plan`) as loadable
  skills with no parent layer to walk authors through them as a
  sequence. The first parent skill (`/charter`) is queued to ship,
  with two siblings (`/scope` and the `/work-on` migration) following
  it. Without a shared design that lifts the pattern-level mechanics
  out of any one feature, each parent re-derives orchestration,
  resume, state-schema, and visibility behavior in isolation; the
  pattern fragments before the second parent ships. The design
  problem is to commit to a shared, storage-agnostic parent-skill
  contract while accommodating the current core-layer constraints
  (wip/-based intermediates, no nested `/decision` sub-teams under
  TeamCreate's single-team-per-leader rule) and leaving room for
  the future amplifier-layer substrate the `/work-on` migration
  will live in.
decision: |
  Adopt a parent-skill pattern with a fixed contract surface (state
  schema, resume ladder, three exit paths, child-doc inspection
  rules, CLAUDE.md surfacing, eval requirement) shared across all
  three parents, plus per-parent bindings (delegation graph, chain
  shape, slug rules) that each feature owns. Ship the shared engine
  references and the core-layer wip/-based implementation now;
  declare the amplifier-layer substitution surface in the contract
  so the future migration is mechanical. Resolve the discover/
  converge engine extraction, the nested-decision-team adaptation,
  and the cross-branch state-file scope inline; defer competitive
  signal detection and shared-design re-author timing as scoped
  open questions.
rationale: |
  The pattern-level requirements (R1, R3, R9-R14, R17a, R18) are
  already articulated in `/charter`'s PRD; lifting them into a
  shared design now — while `/charter` is the only concrete
  consumer — costs less than re-litigating them when `/scope` lands.
  Contract-first design lets the core layer ship against current
  shirabe patterns without locking out the amplifier layer the
  workflow-substrate work depends on. The core-layer adaptations
  (inline `/decision`, no nested teams) are framed as explicit
  limitations the design exposes rather than hidden in
  implementation, so the amplifier layer's value proposition is
  pre-justified.
---

# DESIGN: shirabe-progression-authoring

## Status

Proposed. Authored 2026-05-24 against the In Progress PRD
`docs/prds/PRD-shirabe-charter-skill.md`. The design is **shared**
across the parent-skill pattern's three features: `/charter` (the
concrete consumer driving this design), `/scope` (a parallel parent
sibling, separate PRD), and the future `/work-on` migration from
its current substrate into the same pattern (separate PRD when
substrate work is bounded). The design lifts every requirement
tagged `[pattern-level]` in `/charter`'s PRD (R1, R3, R9, R10, R11,
R12, R13, R14, R17a, R18) into pattern-level scope; the
`[/charter-specific]` requirements stay in `/charter`'s PRD.

## Context and Problem Statement

The shirabe skill catalog ships two altitude bands of artifact
producers as standalone slash commands. Strategic-altitude children
(`/vision`, `/strategy`, `/roadmap`) and tactical-altitude children
(`/prd`, `/design`, `/plan`) each run as one-shot conversations the
author invokes by hand. No parent skill currently walks an author
through a sequence of children, holds state across child
boundaries, or enforces invariants that span the chain (terminal
artifact, exit shape, resume).

`/charter` is queued as the first parent skill, with `/scope` and
the `/work-on` migration named in `/charter`'s PRD as the next two
parent-skill consumers. Three forces shape the design problem:

- **Pattern reuse is load-bearing for the next two parents.**
  `/charter`'s PRD tags ten of its requirements `[pattern-level]`
  precisely because the same mechanics need to apply to `/scope`
  and `/work-on`. Without a shared design that lifts those
  requirements out of `/charter`'s scope, the second parent
  re-derives them and the third drifts further.
- **The core-layer execution environment has hard constraints
  the design must accommodate.** Two are load-bearing: shirabe's
  current intermediate-storage substrate (`wip/`-based files
  committed to feature branches, deleted before merge) and a
  Claude Code TeamCreate constraint (`single-team-per-leader` —
  one team per agent leader, no nested team creation). The
  TeamCreate constraint means a `/decision`-style sub-team inside
  a `/design` decision-researcher cannot be spawned today; the
  decision skill must run inline in the researcher's own context.
- **The amplifier-layer substrate the `/work-on` migration
  depends on is not bounded yet.** Whatever workflow-composition
  substrate the migration will live in is outside this design's
  shipping scope, but the contract must not foreclose it. The
  freeze line is the contract surface; the implementations are
  the substitution variables.

The technical challenge is to commit to a parent-skill contract
that satisfies the ten pattern-level requirements, accommodates the
core-layer constraints explicitly, and leaves the amplifier-layer
substitution surface defined as a substitution variable rather than
a future redesign.

System boundaries touched by this design:

- The shirabe `skills/` directory layout (does the discover/converge
  engine move out of `skills/explore/`?) and the top-level
  `references/` directory (where shared content already lives:
  `cross-repo-references.md`, `decision-protocol.md`,
  `wip-hygiene.md`, etc.).
- The `wip/` intermediate-storage substrate (the state file
  `wip/<parent>_<topic>_state.md`, per-child wip artifacts each
  child currently writes, the wip-hygiene rule from workspace
  `CLAUDE.md`).
- The child-skill contract surface for inspection: a parent reads
  child doc frontmatter `status:` and computes git blob hashes;
  it does NOT read child internals (`wip/research/<child>_*.md`).
- The CLAUDE.md visibility-detection pattern (`## Repo Visibility:`
  header read by `/strategy`, `/explore`, and others).
- The skill-evals substrate (`skills/<name>/evals/evals.json`,
  `scripts/run-evals.sh`).

The downstream PRD for `/charter` has already drafted concrete
state-file schemas, resume-ladder ordering, and validation rules.
This design must either ratify those specifics as pattern-level
(promoting them out of `/charter`'s PRD into the shared contract)
or substitute equivalent pattern-level forms.

## Decision Drivers

Drivers fall into four groups. Items 1-6 trace to PRD §"Questions
Deferred to Design"; items 7-10 trace to the 10 pattern-level
requirements; items 11-13 trace to SE4 directives in the
team-coordinator brief; items 14-15 are implementation-specific
drivers the PRD does not cover.

### From the PRD's deferred questions

1. **Discover/converge engine extraction.** Whether the engine
   lives at `skills/explore/references/phases/` (cross-skill
   reference) or moves to a top-level `references/` location
   (signaling shared infrastructure). Affects the parent-skill
   `references/phase-1-*.md` path conventions and how `/scope` /
   `/work-on` consume the same discovery engine.

2. **Dual-implementation substitution contract.** The freeze line
   between the wip/-based core-layer implementation and the
   future amplifier-layer implementation. The resume contract is
   storage-agnostic; wip/-specific hygiene rules are orthogonal.
   The driver is identifying which parts of the contract are
   substitution variables and which are invariant.

3. **Shared-design authoring timing.** Whether this design ships
   before `/scope` and `/work-on` are bounded (now, validating
   only against `/charter`) or after. The SE4 directive answers:
   author it now, against `/charter`'s pattern-level requirements
   as written. The driver is what that commitment costs (pattern
   may need revision when `/scope` lands) versus defers
   (re-litigating pattern-level claims later).

4. **Cross-branch state-file behavior under `wip/`.** The state
   file is branch-coupled today (PRD R10, R11). Future scenarios
   (merge a child PR, resume parent on main to invoke next child)
   break the wip/-based model. The driver is whether the v1
   contract acknowledges branch-coupling as a known limitation
   or specifies a substitution surface to fix it later.

5. **Competitive-framing signal detection in private repos.** When
   `/comp` ships, `/charter` must detect competitive-framing
   signals during Phase 1. The driver is whether the detection
   contract is part of the pattern (so `/scope` inherits) or
   specific to `/charter` and its `/comp` integration.

6. **Team persistence across the parent-skill chain.** The
   TeamCreate single-team-per-leader constraint blocks downstream
   teams (`/prd`, `/design`, `/plan`) from holding upstream teams
   (`/brief`) alive for query. The contract today is file-handoff.
   The driver is whether the pattern names the substrate the
   resolution will live in (amplifier-layer workflow substrate)
   or leaves it as a generic future-work flag.

### From the 10 pattern-level PRD requirements

7. **Skill-loading surface (R1).** Parent skills load as
   `skills/<name>/SKILL.md` slash commands following the shipped
   template (Input Modes, execution-mode flags, slug constraint,
   Workflow Phases diagram, Resume Logic ladder, Phase Execution
   list, Reference Files table). The driver is whether the design
   ratifies this verbatim or substitutes a contract-level form
   that allows amplifier-layer parents to ship outside this
   template.

8. **Slug constraint (R3).** Topic-slug regex `^[a-z0-9-]+$`,
   hard-rejected at Phase 0. Pattern-level commitment ratified by
   ratifying R3.

9. **State-file schema and resume ladder (R9, R10, R11).** These
   three requirements together specify a concrete schema (YAML
   with `.md` extension, named fields like `chain_started`,
   `planned_chain`, `chain_ran`, `chain_skipped`, `exit`,
   `decision_record_sub_shape`, `exit_artifacts`,
   `child_snapshots`), a hard finalization check (R9), and a
   resume-ladder ordering with multi-source consultation (R11).
   The design driver: ratify as pattern-level (every parent uses
   the same schema with parent-specific field extensions), or
   abstract to a substitution-variable form. The PRD's
   pattern-level tagging signals "ratify"; the design must agree
   or explain why not.

10. **Visibility detection (R12), manual-fallback (R13),
    child-internals isolation (R14), CLAUDE.md surfacing (R17a),
    evals (R18).** Each is a contract-surface commitment. The
    design must either ratify all five into pattern-level scope
    or explain which need parent-specific bindings.

### From SE4 directives

11. **Nested-team adaptation for `/decision` sub-skills.** The
    `/design` SKILL.md expects Phase 2 to spawn decision-researcher
    peers that each invoke `/decision` as a sub-skill with its own
    validator team. TeamCreate's single-team-per-leader constraint
    blocks this nested-team creation. The adaptation: each
    decision-researcher walks `/decision`'s phases inline (no
    nested team, no parallel alternative-research agents, no
    persistent validators). The driver: how the design surfaces
    this limitation — as a transient implementation note, or as
    an explicit architectural property of the core layer that
    motivates an amplifier-layer capability.

12. **wip/ persistence as durable evidence.** SE4 overrides the
    `/design` skill's Phase 6 wip/ cleanup. wip/ artifacts (this
    design's coordination manifest, per-decision reports, security
    report, review verdicts) persist as durable evidence rather
    than getting deleted. The driver: documented expectation that
    pattern-level designs accumulate inspectable evidence trails
    in wip/ that survive the cleanup phase.

13. **PR-creation hold.** SE4 holds PR creation until the full
    tactical chain (brief + PRD + design + plan) completes. The
    branch accumulates artifacts and a single PR ships them
    together. Implication for this design: status transitions
    happen in-branch on team-lead approval, but the design's
    discoverability doesn't require its own PR — readers consult
    the branch.

### Implementation-specific

14. **Maintainability across the three parents.** Pattern-level
    references (e.g., a shared `references/parent-skill-pattern.md`
    listing the contract surface, the resume-ladder template, the
    state-file schema) must be authored such that each parent
    cites them rather than re-implementing them. The design must
    name the location and content of those shared references.

15. **Eval coverage of pattern-level behavior.** Per R18, each
    parent ships evals at `skills/<name>/evals/evals.json`. The
    design must commit to a pattern-level eval scenario set (slug
    rejection, malformed state file, child-internals isolation,
    visibility default) that each parent inherits, plus
    parent-specific scenarios on top.

## Considered Options

Six decisions decompose the design space. Each has its own per-question
Considered Options block below, followed by a Decision Outcome that
synthesizes how they fit together.

### Decision 1: Shared parent-skill references — content and location

shirabe ships pattern-level content for three parent skills (`/charter`,
`/scope`, `/work-on` migration). Two coupled sub-questions: (a) where
the discover/converge engine currently at
`skills/explore/references/phases/{phase-2-discover,phase-3-converge}.md`
lives, and (b) what additional pattern-level references (state-schema,
resume-ladder, child-doc inspection, etc.) ship alongside it. The
location is the same problem at different granularities — content and
location move together.

The shipped shirabe `references/` top-level directory is the
established home for cross-skill content (`cross-repo-references.md`,
`decision-protocol.md`, `pipeline-model.md`, `wip-hygiene.md`). Putting
new pattern-level references there matches precedent. The engine
itself, by codebase audit, is a mental model rather than a shared
physical file: each shipped skill with a discover phase ships its own
variant.

**Key assumptions:**
- The new pattern-level reference files are NEW content the design
  authors, not re-exports of fragments hidden elsewhere in shipped
  skills.
- shirabe's loader resolves `${CLAUDE_PLUGIN_ROOT}/references/<file>.md`
  uniformly from SKILL.md, phase files, and eval files.
- `/scope` and `/work-on` (when bounded) each author their own
  parent-specific Phase 1 discovery prose rather than verbatim-importing
  the `/explore` engine.

#### Chosen: Hybrid extraction

Add new pattern-level reference files at the top-level `references/`
directory; leave the existing `/explore` discover/converge engine in
its current location. The pattern-level references shipped in this
design are:

- `references/parent-skill-pattern.md` — contract surface, named
  invariants, and the three exit paths.
- `references/parent-skill-state-schema.md` — the 5-field minimum
  state-file vocabulary (Decision 3 fills the content).
- `references/parent-skill-resume-ladder-template.md` — universal
  meta-ladder entries and templated body slots (Decision 3 fills the
  content).
- `references/parent-skill-child-inspection.md` — R14 isolation rules
  including the per-parent surface binding (Decision 4's R14 widening).

The discover/converge engine stays at
`skills/explore/references/phases/`. Each parent skill that needs
discovery either points cross-skill or ships its own variant, matching
every shipped shirabe skill today. Moving the engine is deferred —
the PRD explicitly frames extraction as a follow-on PR, and no
current cross-skill consumer demands the refactor.

#### Alternatives Considered

**Full top-level extraction (engine moves too).** Move the
discover/converge engine into `references/discover-converge.md`
alongside the new pattern-level references, signaling a single shared
infrastructure root. Rejected because no current cross-skill consumer
demands engine reuse; the engine's prose contains
`/explore`-specific round-tracking and filenames that would either
bleed into a "shared" file or force a refactor of `/explore`'s phase
prose outside this design's scope.

**Status quo for everything (per-parent copies of contract
references).** Each parent skill ships its own copy of the contract
surface inside `skills/<name>/references/`. Rejected because three
copies of the same content is precisely the fragmentation pattern-level
scope exists to prevent; this alternative IS re-implementation,
contradicting the design's purpose.

### Decision 2: Substitution-variable contract surface (and cross-branch boundary)

The design must commit to a contract surface that holds across two
implementations: the core-layer (wip/-based, branch-coupled)
implementation that ships today, and a future amplifier-layer
implementation. The contract is the freeze line; the implementations
are the substitution variables. The cross-branch limitation present
in wip/ today is the concrete test case for where the freeze line
lives.

Mis-drawing the freeze line is irreversible without redesign:
over-commit to current wip/ semantics and the amplifier layer's value
proposition is foreclosed; under-commit to abstraction and downstream
parents have no concrete shape to inherit.

**Key assumptions:**
- The amplifier-layer substrate supports state persistence keyed by
  topic slug; without this, the state-by-topic invariant cannot
  promise across substrates.
- The amplifier layer provides equivalent-or-stronger properties for
  wip/-substrate capabilities (drift detection, resume from partial
  state, audit trail); it does not regress.
- Future parents (`/scope`, `/work-on`) interoperate via durable
  `docs/` artifacts regardless of substrate.
- Semantic invariants are precise enough that future amplifier-layer
  parents can be reviewed for compliance via prose-judgment.

#### Chosen: Two-layer contract with cross-branch named as invariant I-6 (acknowledged unsatisfied in v1)

Split the contract into two layers:

**Layer 1 — Semantic invariants (substrate-agnostic).** Named
properties every parent satisfies regardless of substrate. The v1
invariant set is:

- **I-1** Parent records an exit outcome before terminating; bail
  routes to a terminal-artifact path, never to silent loss.
- **I-2** Every chain ends at a durable file on disk that human
  reviewers consume — `docs/<type>/<TYPE>-<topic>.md`. Git history is
  not a substitute.
- **I-3** Resume across child boundaries inspects both parent state
  and child durable artifacts; child internals are never read.
- **I-4** State is topic-keyed; concurrent or sequential invocations
  against different topics never interfere.
- **I-5** Conditional fields in state are absent when their triggering
  condition does not hold (never null / placeholder).
- **I-6** *Cross-branch resume is a pattern invariant. The v1
  core-layer implementation acknowledges it does NOT satisfy I-6.*

**Layer 2 — Reference implementation (substrate-bound).** A concrete
serialization that every core-layer parent uses verbatim, drawn from
PRD R10 with parent-specific fields slotted in. The reference
implementation makes the core-layer's pattern-level commitments
testable today; amplifier-layer implementations supply their own
serialization that satisfies the same invariants.

The two-layer split lets the design ship verifiable v1 commitments
(via the reference implementation) without locking out plausible
amplifier substrates (cloud-backed context stores, session-scoped
state, multi-leader coordination primitives). Cross-branch as
invariant I-6 functions as an explicit forcing function: the v1
wip/-substrate acknowledges the gap, and the amplifier-layer's
mandate includes closing it.

#### Alternatives Considered

**Lock R10 schema as contract; cross-branch as wip/-specific
limitation amplifier fixes.** Treat PRD R10's full schema (every
named field, YAML serialization, branch-coupling) as pattern-level
contract; cross-branch is implementation-specific. Rejected because
over-commits to whole-document YAML serialization, foreclosing
structured-update or field-level-update substrates the amplifier
layer may need. The verifiability benefit is preserved in the Chosen
by keeping R10 as reference implementation every core-layer parent
uses verbatim.

**Two-layer; cross-branch as wip/-specific limitation, expected but
not required.** Same two-layer split, but cross-branch is framed as
"amplifier layer is expected to fix this" rather than as a named
invariant the layer is required to satisfy. Rejected because
"expected but not invariant" weakens the design's forcing function on
amplifier-layer work, and creates an inconsistency with how the same
design frames the amplifier layer as resolution surface for the
team-primitive substitution variable (Decision 5).

**Pure invariant contract (no reference schema).** Commit only to
named semantic invariants; let each parent author its own
serialization from scratch. Rejected because it fragments the pattern
across three parents that share the same domain; convergence-by-default
is the right prior given all three parents target the same authoring
loop. Also removes the verifiability the PRD's `[pattern-level]`
tagging was designed to provide.

**Lock schema; cross-branch out-of-scope-forever.** Lock R10 verbatim
and declare cross-branch outside the pattern's lifetime ambit.
Rejected because internally incoherent given the design's own framing
of the amplifier layer (PRD Question 4, design Driver 4) as the
resolution surface for cross-branch. Out-of-scope-forever contradicts
the document's stated posture.

### Decision 3: State-file schema and resume-ladder ratification

PRD R9, R10, and R11 specify a fully concrete state-file schema for
`/charter`. The design must decide whether to ratify those specifics
verbatim as pattern-level commitments or abstract them. The choice
affects every downstream parent: drift across parents on field
naming, ladder ordering, or finalization-check semantics is the
failure mode the `[pattern-level]` tagging exists to prevent.

**Key assumptions:**
- Decision 2 frames the substitution surface as substrate-substitutable
  with contract = named-field vocabulary + named invariants.
  (Confirmed in Phase 3 cross-validation; Decision 2's two-layer split
  provides exactly the freeze line this decision fills in at.)
- `/scope` and `/work-on` land later, not co-authored with this
  design. `/scope` is chain-shaped (structurally similar to
  `/charter`); `/work-on` is an implementation loop, possibly
  substrate-pivoting.
- The PRD `[pattern-level]` tag means "lift the relevant commitment
  into shared scope", not "this exact field list IS the contract" —
  PRD R9's null-prohibition on conditional fields supports this
  reading, since `/charter`-specific conditional fields cannot
  reasonably appear in `/scope` or `/work-on` state.

#### Chosen: Hybrid — minimum-required pattern-level schema with extension hooks, plus split resume-ladder template

**Five pattern-level state-file fields (minimum required for every
parent):**

- `topic: <topic-slug>` — string matching `^[a-z0-9-]+$`.
- `last_updated: <ISO-8601 timestamp>` — written on every state-file
  modification.
- `phase_pointer: <parent-phase-enum string>` — which phase the
  parent is in when interrupted.
- `exit: <parent-exit-enum string>` — UNSET while in progress; SET at
  finalization. R9's hard-finalization check fires when this is unset
  or invalid at termination.
- `exit_artifacts: [{path, status}]` — list of durable files this
  chain produced.

Every parent extends with parent-specific fields keyed by its chain
shape (e.g., `/charter` adds `planned_chain`, `chain_ran`,
`chain_skipped`, `decision_record_sub_shape`, `referenced_strategy`,
etc.). The `[pattern-level]` commitment is the minimum vocabulary
plus the extension discipline.

**Four pattern-level invariants the schema enforces:**

- **Per-child snapshot dual-check drift detection.** For each child
  the parent invokes, the state captures both the child's durable
  status AND a content-fingerprint of the child's durable artifact;
  drift fires when either changes between parent resumes. For
  doc-emitting children the fingerprint is the git blob hash; for
  non-doc children the fingerprint binding is parent-specific (see
  Decision 4's R14 widening for the per-parent surface table).
- **Conditional-field gating discipline.** Fields whose presence is
  gated by a specific `exit:` value MUST be absent when their
  triggering condition does not hold; they MUST NOT be set to null,
  empty string, or placeholder.
- **Chain-tracking discipline (conditional on chain-shaped parents).**
  Parents whose run invokes a sequence of children record
  `planned_chain`, `chain_ran`, and `chain_skipped`. Non-chain-shaped
  parents (e.g., a future implementation-loop parent) MAY omit these.
- **Status-aware re-entry control.** When a parent invokes a child
  whose durable doc would trigger that child's own resume prompt,
  the parent MUST decide upfront whether the re-entry is parent-resume
  or fresh-chain; the parent's flow MUST NOT be hijacked by the
  child's status-aware re-entry prompt.

**Resume-ladder template — universal meta-ladder plus parent-specific
body slots:**

```
1. state file malformed                           -> Error + offer Discard
2. state file has exit field set                  -> Offer revise-equivalent / start fresh
3. state file exists, last_updated < threshold    -> Resume at recorded phase_pointer
4. state file exists, last_updated >= threshold   -> Offer Resume / Force-materialize / Discard
5. [parent-specific status-aware re-entry slot]   -> parent-specific prompt vocabulary
6. [parent-specific partial-child-run slot]       -> resume into the partial child
7. [parent-specific feeder-doc-detected slot]     -> parent-specific Phase 1 entry behavior
8. On branch related to topic                     -> Resume at parent's Phase 1
9. On main or unrelated branch                    -> Start at parent's Phase 0
```

Entries 1-4 and 8-9 are pattern-level (every parent SHALL implement
them with the same semantics). Entries 5-7 are parent-specific body
slots; each parent's SKILL.md fills them.

#### Alternatives Considered

**Verbatim ratification (R10 schema is the pattern).** Every parent
uses exactly the R10 field set including `/charter`-specific
conditional fields (`decision_record_sub_shape`,
`discard_commit_sha`, `rejection_rationale`, `triggering_child`,
`partial_phase_reached`). Rejected because internally inconsistent
with PRD R9's null-prohibition on conditional fields: `/scope` and
`/work-on` cannot reasonably carry `/charter`-specific conditional
fields, but setting them to null violates R9. The verbatim
ratification path forces either schema contortion (every parent
inherits every parent's conditional fields) or a re-interpretation
of R9, both worse than the hybrid.

**Pure invariant abstraction.** Pattern-level scope holds only named
invariants ("has a phase pointer", "records exit outcome"); each
parent authors its own field names from scratch. Rejected because it
loses portability of universal acceptance criteria (e.g.,
`/charter`'s AC15 would have to be re-authored per parent), degrades
drift-prevention on universal fields to zero, and buys
rename-the-field flexibility no concrete consumer asks for.

### Decision 4: Pattern-surface ratification (R12, R13, R14, R17a, R18)

Five pattern-level PRD requirements need verification: do they
ratify verbatim, or does any need a parent-specific binding? The
PRD tags all five `[pattern-level]`; the design either confirms or
amends each.

**Key assumptions:**
- `/scope`'s children all emit docs with frontmatter `status:` —
  consistent with shirabe's existing child skills.
- `/work-on`'s children are GitHub issues and PRs, not docs with
  frontmatter.
- The eval format remains JSON-flat (`evals[]`) in v1; no `$ref`
  mechanism in the runner.

#### Chosen: Ratify R12, R13, R17a, R18 verbatim; widen R14; ship a shared eval baseline via copy-paste

| Requirement | Verdict | Rationale (one-line) |
|---|---|---|
| R12 visibility detection | ratify verbatim | workspace-level; `## Repo Visibility:` header read identically by every parent |
| R13 manual-fallback | ratify verbatim | non-interference rule is identical across parents; surface differing is not a binding, it's identity |
| R14 child-internals isolation | ratify with parent-specific binding | literal "frontmatter status:" phrasing assumes doc-emitting children; broader rule generalizes |
| R17a CLAUDE.md surfacing | ratify verbatim | every parent ships CLAUDE.md entry-trigger documentation; trigger phrases are parent-specific (R17b) |
| R18 evals shipping | ratify verbatim | every parent ships `skills/<name>/evals/evals.json` |

**R14 widening — the only non-verbatim ratification.** The
pattern-level form generalizes from "parent reads only child doc
frontmatter `status:` and topic slug; never internals" to:

> A parent SHALL read only the child's *durable externally-visible
> status surface*; the parent SHALL NOT read child internals (e.g.,
> `wip/research/<child>_*.md`, CI logs, comment threads). The status
> surface is parent-specific:
> - For doc-emitting children (`/charter`, `/scope`'s children): the
>   child doc's frontmatter `status:` value plus the doc's content
>   fingerprint (git blob hash).
> - For non-doc children (`/work-on`'s children — issues and PRs):
>   the issue/PR state plus labels plus CI check rollup.

**Shared eval baseline via copy-paste with canonical source.** Every
parent's `evals.json` includes a baseline scenario set (slug
rejection per the topic-slug constraint, malformed state file,
child-internals isolation, visibility default). The canonical source
is `/charter`'s eval file (which ships first); `/scope` and
`/work-on` copy-and-adapt rather than `$ref`-importing. A future
eval-infrastructure follow-up can introduce `$ref` mechanically.

#### Alternatives Considered

**Ratify R14 verbatim.** Keep the PRD's "frontmatter status:"
phrasing as pattern-level. Rejected because the literal phrasing
assumes doc-emitting children, but `/work-on`'s children are
issues/PRs — verbatim ratification would force tortured interpretation
or carve out `/work-on` from the rule entirely.

**Rework R14 from scratch.** Replace R14 with a new pattern-level
rule unrelated to its PRD form. Rejected because the underlying rule
(parent reads only externally-visible status; never internals)
generalizes cleanly; per-parent surface enumeration is a binding, not
a PRD defect.

**Per-parent visibility detection (R12 alternative b).** Each parent
implements its own visibility model. Rejected because workspace
visibility is workspace-level — every parent that touches `docs/`
inherits the same `## Repo Visibility:` constraint; identity is not
a binding.

**Independent per-parent evals (R18 sub-alternative s1).** Each
parent authors its own eval scenarios from scratch, no shared
baseline. Rejected because drift on the four pattern-level invariants
(slug, malformed state, isolation, visibility) defeats the point of
pattern-level scope.

**`$ref` mechanism in eval runner (R18 sub-alternative s3).** Extend
the eval format to support `$ref` so shared scenarios live in one
file. Rejected because eval-format changes are out of scope for v1;
re-evaluate when shirabe-eval infrastructure is bounded.

### Decision 5: Surfacing the TeamCreate single-team-per-leader constraint

The Claude Code TeamCreate primitive enforces a single-team-per-leader
rule. Inside the design's authoring run this manifests in two ways:
(a) a `/design` decision-researcher cannot spawn a `/decision`
validator sub-team — researchers walk `/decision` inline (no
parallel alternative-research agents, no persistent validators); (b)
downstream parent skills cannot query upstream parents' teams — the
contract is file-handoff via `docs/` and `wip/`.

A consequence surfaced during this design's own execution: sub-agents
in Claude Code cannot themselves spawn more sub-agents — the Agent
tool is parent-only. That blocks the team-shape spec's recommended
"lazy spawn after Phase 1 reveals N" pattern; the parent must spawn
all peers upfront, including variable-cardinality peers whose count
is only known after the coordinator runs Phase 1.

The design *will* address the constraint regardless; the question is
*how it frames* the constraint, which shapes the design's relationship
to the amplifier layer and the design's honesty about current Claude
Code limitations.

**Key assumptions:**
- The constraint is permanent in the core layer. If the underlying
  primitive changes, the substitution-variable framing absorbs the
  change trivially.
- An amplifier-layer workflow substrate will eventually exist and is
  the natural resolution surface. If not, the core-layer value stands
  alone.
- Decision 2 adopts a substitution-surface framing for storage
  (confirmed in Phase 3 cross-validation). Decision 5 stands
  independently if not, but Open-Questions presentation assumes
  coupling.

#### Chosen: Named substitution surface `team_primitive` paired with Decision 2's `storage_substrate`

Frame the limitation as a named substitution variable `team_primitive`
whose v1 value is `single-team-per-leader-no-nested`. The variable's
current value implies three consequences the v1 contract operates
under:

1. **Inline-decision walks.** A `/design`-style parent that decomposes
   a problem into N decision questions cannot spawn N persistent
   validator sub-teams; each decision-researcher walks `/decision`
   inline.
2. **File-handoff between parents.** Downstream parents read upstream
   parents' artifacts from `docs/` and `wip/` rather than querying
   live teams.
3. **Upfront upper-bound team roster.** A parent that needs
   variable-cardinality peers must declare the upper bound at
   team-creation time; the parent spawns the full roster upfront and
   the coordinator selects which peers to dispatch.

The design pairs `team_primitive` with Decision 2's `storage_substrate`
under a single Open Questions / Consequences header — "Core-layer-to-
amplifier-layer substitution surfaces" — making the design's
relationship to the amplifier layer explicit and pre-justifying the
amplifier-layer investment without prescribing its shape.

**Team-shape declarator as contract surface.** The upper-bound team
roster requirement (consequence 3) lifts into the design's Solution
Architecture as a contract-level mechanism: each child skill declares
its team shape (fixed roles plus variable-cardinality role *types*
with an upper bound); the parent materializes the full roster at
team creation, even when the runtime count is only known after
decomposition. The **shape declaration is contract**; the **spawn
timing is substrate-specific** — core layer spawns all upfront,
amplifier layer may spawn lazily.

#### Alternatives Considered

**Transient implementation note.** Treat the constraint as a footnote
that will go away when the substrate evolves; minimize framing in
the design body. Rejected because the constraint is permanent in the
core layer with unbounded amplifier-layer scope; transient framing
mis-states reality and misleads downstream parent authors.

**Explicit architectural property (standalone, not as substitution
surface).** Document the limitation as a property of the core layer
in Open Questions / Consequences without naming a substitution
variable. Rejected because it treats the three consequences as
independent properties and doesn't name the resolution surface,
under-delivering on the design's stated goal of leaving room for the
amplifier layer. The Chosen named-substitution-surface framing is
this refined plus a named seam.

### Decision 6: Competitive-framing signal detection contract

When `/comp` ships in shirabe core, `/charter`'s recommended-default
for offering `/comp` depends on detecting competitive-framing signals
during Phase 1 discovery. The PRD specifies broad signal categories
but defers the detection-mechanism contract to design. The design's
question is altitude: pattern-level (every parent inherits a
conditional-feeder contract) or `/charter`-specific.

**Key assumptions:**
- `/scope` is not specified in enough detail today to confirm whether
  it will have an analogous conditional-feeder shape; if a second
  binding lands, the contract surface should be revisited.
- `/comp` is not yet on disk; the chosen position must not block its
  integration shape when it ships.
- Agent-judgment-with-broad-categories remains the detection mechanism
  (precedent: PRD R4 thesis-shift signal). No keyword-list or
  structured-prompt mandate.
- The pattern-level contract surface already includes visibility
  detection (R12); the recognized shape names R12 as its
  visibility-gate mechanism without re-specifying.

#### Chosen: Hybrid — pattern recognizes "conditional feeder invocation" as an integration shape; `/charter` provides the only v1 binding

The pattern-level references include a short subsection naming the
recognized shape: a parent MAY offer a feeder skill conditionally
when (1) a parent-defined Phase 1 discovery signal fires, (2) the
feeder skill exists on disk, AND (3) a parent-defined visibility
gate passes (using R12's visibility-detection mechanism).
Signal-detection mechanics are explicitly NOT part of the pattern —
they are agent judgment per parent, with broad-category descriptions
in each parent's own SKILL.md.

`/charter` provides the only v1 binding: signal = competitive-framing
agent-judgment categories per PRD R4-R5 precedent; feeder = `/comp`;
visibility gate = Private. If `/scope` adds an analogous
conditional-feeder later (different signal, different feeder), the
shape extension is mechanical.

#### Alternatives Considered

**Pattern-level full contract with detection mechanics.** Specify
the detection mechanism (e.g., a keyword-category list or
structured-prompt template) at pattern level. Rejected because the
PRD signals `/charter`-specific by default (R4, R5 are tagged
`[/charter-specific]`); no second concrete binding exists to ratify
mechanics against; standard-tier reversibility budget makes
"commit-less-now" the lower-cost default when only one binding
exists.

**`/charter`-specific binding with no pattern-level acknowledgment.**
Treat conditional feeder invocation as entirely `/charter`'s
concern; no pattern-level prose. Rejected because the shared design
ALREADY lifts R12 (visibility) and the spirit of R5's silence rule
into pattern-level scope — refusing to name the composition forces
`/scope` to re-derive it and hides the reuse value of the
visibility-gate plus silence-rule components. The recognized-shape
prose costs roughly 150-250 words of shared-design content for
material reuse benefit.

## Decision Outcome

**Chosen: 1·Hybrid extraction + 2·Two-layer with I-6 + 3·Hybrid 5-field + 4·Ratify-with-R14-widened + 5·Named substitution surface + 6·Recognized shape**

### Summary

The design commits to a parent-skill contract surface that all three
parent skills (`/charter`, `/scope`, `/work-on` migration) inherit
verbatim where pattern-level, and bind parent-specifically where the
PRD's pattern-level tagging is incompatible with non-doc-emitting
parents. Shared content lives at the top-level `references/` directory
in four new files: `parent-skill-pattern.md` (contract surface, three
exit paths, named substitution surfaces),
`parent-skill-state-schema.md` (5-field minimum state-file vocabulary
plus extension discipline), `parent-skill-resume-ladder-template.md`
(universal meta-ladder plus parent-specific body slots), and
`parent-skill-child-inspection.md` (R14 isolation rule with
per-parent surface bindings). The discover/converge engine stays at
`skills/explore/references/phases/`; each parent's Phase 1 prose
either points cross-skill or ships its own variant.

The contract is two-layered. The **semantic invariants** (I-1 through
I-6) hold across both the core-layer (wip/-based, branch-coupled)
implementation that ships today and any future amplifier-layer
implementation. The **reference implementation** is a concrete YAML
serialization with the 5-field minimum schema (`topic`,
`last_updated`, `phase_pointer`, `exit`, `exit_artifacts`) plus
parent-specific extensions; every core-layer parent uses it
verbatim. Cross-branch resume is invariant I-6 that v1 acknowledges
it does NOT satisfy — the amplifier layer's mandate includes
closing the gap, and the invariant serves as an explicit forcing
function.

Two limitation surfaces are framed as **named substitution variables**:
`storage_substrate` (Decision 2) and `team_primitive` (Decision 5).
Both surface in a paired "Core-layer-to-amplifier-layer substitution
surfaces" section, naming the amplifier layer as the resolution
location without prescribing its shape. The `team_primitive`
variable's v1 value implies three operational consequences —
inline-`/decision` walks, file-handoff between parents, and upfront
upper-bound team roster — that the design exposes rather than hides.
The team-shape declarator mechanism (each child skill declares its
team shape, parent materializes upfront) lifts into Solution
Architecture as a contract-level mechanism whose spawn-timing detail
is the substrate-specific part.

Five PRD pattern-level requirements ratify verbatim (R12 visibility
detection, R13 manual-fallback, R17a CLAUDE.md surfacing, R18 eval
shipping); R14 child-internals isolation widens to "durable
externally-visible status surface" with per-parent surface bindings
(doc-emitting children use frontmatter status plus git blob hash;
issue or PR-emitting children use issue/PR state plus labels plus
CI rollup). R18 ships via a shared eval baseline (slug rejection,
malformed state, child-isolation, visibility default) copied-and-
adapted from `/charter`'s canonical evals; a future
eval-infrastructure follow-up may introduce `$ref` mechanics.
Pattern-level scope also recognizes the "conditional feeder
invocation" integration shape (parent-defined signal +
skill-existence check + parent-defined visibility gate using R12);
`/charter`'s `/comp` integration is the only v1 binding.

### Rationale

The decisions reinforce each other along a single architectural seam:
the **freeze line** between substrate-agnostic semantics and
substrate-bound implementations. Decision 2 draws the line; Decision
3 puts the schema on the substrate-bound side while keeping its
named-field vocabulary as semantics; Decision 5 applies the same
seam to team primitives; Decision 1 organizes the shared content
around it; Decision 4 confirms which PRD-level surfaces sit cleanly
above the line (R12, R13, R17a, R18) versus which need bindings to
cross it (R14); Decision 6 demonstrates how composition works
(visibility gate + silence rule compose into recognized shape).

Trade-offs accepted:

- **Verifiability today vs. flexibility tomorrow.** The two-layer
  contract keeps the reference implementation verifiable in core
  layer (PRD R10 acceptance criteria port directly) while preserving
  room for the amplifier layer to substitute serializations. The
  cost is modest design surface (one extra layer of indirection);
  the benefit is that no v1 commitment forecloses plausible
  substrates.
- **Honesty about current Claude Code limitations.** Naming
  `team_primitive` as a substitution variable rather than framing
  the TeamCreate constraint as a transient bug forces downstream
  parent authors to plan around the current behavior; this is the
  truth-on-disk position rather than the optimistic-handwave
  position.
- **Pattern-level convergence vs. parent-specific binding.** Four of
  five pattern-surface requirements ratify verbatim (R12, R13, R17a,
  R18); R14 needs a per-parent surface table to accommodate
  non-doc-emitting parents. The R14 widening trades one column of
  pattern-level prose (the surface enumeration) for the ability of
  `/work-on` to participate in the pattern at all.

Open-ended uncertainties recorded in Open Questions: the precise
amplifier-layer substrate is not bounded yet; `/scope` and `/work-on`
are not co-authored with this design; the eval `$ref` mechanism is
deferred; cross-branch resume is unimplemented in v1 by design.

## Solution Architecture

[Phase 4 will populate this section.]

## Implementation Approach

[Phase 4 will populate this section.]

## Security Considerations

[Phase 5 will populate this section.]

## Consequences

[Phase 4 / Phase 6 will populate this section.]

## Open Questions

The following are explicit limitations and forward-looking notes
the design exposes. They are not deferred from this document; they
are architectural properties the reader should know about.

- **Nested-team support for `/decision` sub-skill invocation.**
  The Claude Code TeamCreate primitive enforces
  single-team-per-leader, which blocks the `/design` skill's
  intended Phase 2 model (each decision-researcher spawns its own
  `/decision` validator sub-team). The current core-layer
  workaround is to walk `/decision`'s phases inline inside each
  decision-researcher's own context — this means no persistent
  validator agents, no parallel alternative-research, and no
  cross-decision validator memory. This is an architectural
  property of the core layer, not a transient bug. The
  amplifier-layer workflow substrate is the expected resolution
  surface; this design exposes the limitation rather than
  papering over it.

- **Team persistence across the parent-skill chain.** A direct
  consequence of the same TeamCreate constraint: a downstream
  parent skill cannot query an upstream parent's team because
  the upstream team must be destroyed before the downstream
  leader can create its own. The current contract is
  file-handoff (each parent's artifacts live in docs/ and wip/;
  the downstream parent reads them). This is acceptable for the
  pattern-level shared design but limits the inspection depth a
  downstream team can achieve. The amplifier-layer substrate
  is the expected resolution surface.


---
schema: prd/v1
status: Done
complexity: Complex
upstream: docs/briefs/BRIEF-shirabe-artifact-decision-contract.md
problem: |
  shirabe produces seven artifact types (VISION, STRATEGY, ROADMAP, BRIEF,
  PRD, DESIGN, PLAN) plus private-only COMP. Whether each artifact stays
  durable in `docs/` or retires when its job is done is decided implicitly,
  per skill, with no documented per-skill contract. ROADMAPs whose features
  are all Done and whose issues are all closed sit in `docs/roadmaps/`
  indefinitely; skill authors have no canonical place to look up the rule;
  the cascade's PLAN-deletion branch has no extension point for any other
  working artifact to participate.
goals: |
  Each shirabe skill names, in its own SKILL.md prose, whether its artifact
  is durable or working — and, for working artifacts, the completion
  condition that retires it. CLAUDE.md gains a convention header that names
  the durable-versus-working distinction and points readers at the per-skill
  prose as authoritative. ROADMAP flips from durable to working, aligning on
  PLAN's lifecycle template (Draft -> Active -> Done -> DELETED) so the
  cascade can retire ROADMAPs alongside PLANs when the completion condition
  holds. The cascade grows a `handle_roadmap_deletion` step alongside the
  existing PLAN handler, fitting into PR #176's pre-`gh pr ready` window.
---

# PRD: shirabe-artifact-decision-contract

## Status

Done

This PRD lifts the implicit durable-versus-working decision into per-skill
prose, flips ROADMAP from durable to working, and extends the work-on
cascade with a `handle_roadmap_deletion` step that runs alongside the
existing PLAN finalization. The lifecycle template PR #176 established for
PLAN is the foundation; nothing here re-derives it.

## Problem Statement

shirabe has seven main-pipeline artifact types — VISION, STRATEGY, ROADMAP,
BRIEF, PRD, DESIGN, PLAN — plus a private-only COMP. For each type, an
implicit decision lives in the producing skill's cleanup logic: does this
artifact stay in `docs/` forever as part of the project's audit trail, or
does it disappear once its purpose has been fulfilled? The decision is
real, but it is not documented per skill, and it is not consistent across
the pipeline.

The completion cascade today treats one artifact, PLAN, as working. PR #176
formalized PLAN's lifecycle as `Draft -> Active -> Done -> DELETED` and
shipped the cascade script (`skills/work-on/scripts/run-cascade.sh`) that
performs the atomic finalization commit before `gh pr ready` fires. Every
other artifact type stays durable forever, including ROADMAP, even after
the work it sequenced is complete.

Three gaps follow from this implicit, hard-coded decision:

- **ROADMAP-bloat.** A ROADMAP whose features are all Done and whose
  referenced issues are all closed has finished its sequencing job, but it
  stays in `docs/roadmaps/` indefinitely. The directory grows with dead
  context — old sequencing decisions reviewers must learn to skim past —
  and there is no documented rule that says when, or whether, a ROADMAP
  should ever come out.
- **Missing canonical contract.** A skill author writing a new skill, or
  extending an existing one, has nowhere to look up "what is the
  durable-versus-working contract for this artifact, and where is that
  decision recorded?" The cleanup behavior lives inside the cascade
  template's hard-coded PLAN branch; the rationale for why PLAN is the
  only working artifact lives nowhere. Two authors reading the pipeline
  will form different mental models of the rule.
- **No extension point for the cascade.** The cascade's PLAN-deletion step
  is a one-off branch in its script. If any other artifact ever becomes
  working — even one — the cascade has no pluggable place for that
  artifact's completion condition to participate. Each new working
  artifact would require a fresh hard-coded branch and the
  rationale-lives-nowhere problem compounds.

The framing problem this PRD picks up from the BRIEF is the absence of a
documented contract, plus the first concrete application of that contract:
ROADMAP becoming working with a named completion condition the cascade can
honor. Whether other artifact types ever become working is downstream
work; this PRD documents the rule, applies it to ROADMAP, and gives the
cascade its first multi-artifact handler shape.

## Goals

A skill author writing or extending a shirabe skill reads that skill's own
SKILL.md prose and learns the artifact's lifecycle contract: durable, or
working with a named completion condition. The author does not have to
infer the rule from cleanup-script source.

A reviewer browsing `docs/` sees artifacts that are still doing useful
work. A ROADMAP whose features are all Done and whose issues are all
closed is gone from `docs/roadmaps/`, retired by the cascade alongside the
PLAN. Stale sequencing context does not accumulate.

A future maintainer extending the cascade for another working artifact has
an extension point next to the existing PLAN handler. The cascade's
finalization step composes handlers; new handlers do not fork the script.

## User Stories

- **As a skill author**, I want to read a skill's SKILL.md and learn its
  artifact lifecycle contract directly, so that I do not have to infer the
  rule from cleanup-script source or comparison against sibling skills.
- **As a reviewer**, I want `docs/roadmaps/` to show only ROADMAPs that
  are still sequencing in-flight work, so that I am not skimming past dead
  context to find the current state.
- **As a maintainer extending the cascade**, I want a named extension
  point alongside the PLAN deletion step, so that adding a new
  working-artifact handler does not require forking the cascade's
  hard-coded branch.
- **As a shirabe skill consumer running `/work-on`**, I want the cascade
  to delete the ROADMAP automatically when its completion condition holds,
  so that the audit trail in `docs/` reflects work currently in motion
  rather than the union of every initiative ever undertaken.
- **As a reader of CLAUDE.md**, I want a convention header naming the
  durable-versus-working distinction, so that I can find the per-skill
  contract by following one canonical pointer.

## Requirements

### Functional Requirements

**R1: Per-skill durable-vs-working contract section.** Each shirabe skill
that produces a main-pipeline artifact gains a short prose section in its
SKILL.md naming the artifact's lifecycle contract — either "durable" or
"working with completion condition: <condition>". The section follows
explore Phase 5's precedent that the producer decision lives in the
producing skill, not in a central registry. Skills covered: `/brief`,
`/prd`, `/design`, `/plan`, `/roadmap`, `/vision`, `/strategy`, `/comp`.

**R2: Three-rule terminal-artifact model in CLAUDE.md.** CLAUDE.md gains
a new convention header (paralleling Repo Visibility and Planning Context)
that states the three-rule model: (1) durable artifacts stay in `docs/`
forever; (2) working artifacts retire when their completion condition
holds; (3) each working-artifact skill names the condition explicitly in
its SKILL.md. The header points at per-skill SKILL.md prose as
authoritative.

**R3: Durable classifications.** BRIEF, PRD, DESIGN, VISION, STRATEGY,
and COMP are classified durable in their SKILL.md prose sections. The
rationale: these artifacts carry the audit trail of why a feature was
framed, what it requires, how it is built, and why a project exists. Their
durability is what lets a future reader reconstruct the chain.

**R4: PLAN's working classification cites PR #176.** PLAN's SKILL.md
section names PLAN as working with lifecycle `Draft -> Active -> Done ->
DELETED` and completion condition "the implementing PR's cascade verifies
the chain's terminal state and the PLAN file is deleted in the atomic
finalization commit." The section cites
`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md` as the
authoritative source for the lifecycle template and does not re-derive it.

**R5: ROADMAP flips to working with named completion condition.**
ROADMAP's SKILL.md section names ROADMAP as working with completion
condition "all features on the ROADMAP at status Done AND all referenced
GitHub issues closed." When the condition holds, the cascade deletes the
ROADMAP file.

**R6: ROADMAP lifecycle aligns with PLAN.** ROADMAP's lifecycle becomes
`Draft -> Active -> Done -> DELETED`, mirroring the shape PR #176
established for PLAN. The Draft -> Active transition keeps its existing
semantics (human approval, no auto-Active for ROADMAP since features are
locked at activation, paralleling PLAN's multi-pr gate). The Active ->
Done flip is the in-process ephemeral marker that bridges to DELETED, run
by the cascade immediately before deletion. There is no
`docs/roadmaps/done/` directory; verify-then-delete is the terminal.

**R7: Cascade extension via handle_roadmap_deletion step.**
`skills/work-on/scripts/run-cascade.sh` and the
`work-on-plan.md` koto template grow a `handle_roadmap_deletion` step that
runs alongside the existing PLAN finalization step inside the cascade's
pre-`gh pr ready` window (the DRAFT-vs-READY discipline from PR #176).
The step:

  - Resolves the ROADMAP transitively upstream from the PLAN being
    completed (PLAN -> DESIGN -> PRD -> BRIEF -> ROADMAP, following
    `upstream:` frontmatter links).
  - When no ROADMAP exists in the chain, is a no-op (idempotent skip).
  - When a ROADMAP exists, checks the completion condition (all features
    Done AND all referenced issues closed); if satisfied, performs the
    Active -> Done transition and `git rm` of the ROADMAP file in the
    same atomic commit as the PLAN deletion; if not satisfied, leaves the
    ROADMAP alone.
  - Is idempotent: safe to re-run when the ROADMAP has already been
    deleted (no-op) or when the chain has no ROADMAP (no-op).

**R8: Cascade handler composition.** The cascade's finalization commit
groups all working-artifact handlers (PLAN deletion + ROADMAP deletion
when applicable + upstream BRIEF/PRD/DESIGN transitions) into a single
atomic commit before `gh pr ready` fires. The order is fixed: ROADMAP
deletion runs alongside PLAN deletion within the same commit set, not in
a separate commit.

**R9: Scope-bounded prose-only change.** No new shirabe CLI subcommand,
no new validator check, no new format schema, and no new artifact type is
introduced. The contract is documented in skill prose and CLAUDE.md prose;
the cascade extension is a bash step inside the existing `run-cascade.sh`
template. The validator's `--lifecycle-chain` mode (PR #176) is left
unchanged in this PRD; future work may extend it to walk ROADMAP chains.

### Non-Functional Requirements

**R10: Cascade idempotency.** The `handle_roadmap_deletion` step is safe
to invoke multiple times against the same chain state. Re-invocation when
the ROADMAP has already been deleted is a no-op; re-invocation when the
condition is unsatisfied is a no-op; re-invocation when the condition has
just become satisfied performs the deletion exactly once. This matches
the idempotency guarantees PR #176 established for the existing PLAN
handler.

**R11: Foundation citation, not re-derivation.** All references to PLAN's
lifecycle in this contract's prose surface (per-skill SKILL.md sections,
CLAUDE.md convention header, design follow-on) cite
`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md` and the
PLAN SKILL.md section as authoritative. No prose surface restates the
PLAN lifecycle from scratch.

**R12: Cascade window preservation.** The `handle_roadmap_deletion` step
runs inside PR #176's pre-`gh pr ready` window — that is, inside the
`plan_completion` state of `work-on-plan.md` and before the post-cascade
strict-mode lifecycle verification. The DRAFT-vs-READY discipline (the
chain reaches strict-mode passing state before `gh pr ready` fires)
applies to ROADMAP deletion as it does to PLAN deletion.

## Acceptance Criteria

- [ ] **AC1**: Each of the eight named skills (`/brief`, `/prd`,
      `/design`, `/plan`, `/roadmap`, `/vision`, `/strategy`, `/comp`)
      has a prose section in its SKILL.md naming the artifact's
      durable-vs-working contract.
- [ ] **AC2**: BRIEF, PRD, DESIGN, VISION, STRATEGY, and COMP SKILL.md
      sections classify the artifact as durable with rationale tied to
      audit-trail durability.
- [ ] **AC3**: PLAN's SKILL.md section classifies PLAN as working with
      lifecycle `Draft -> Active -> Done -> DELETED` and cites
      `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`
      as the lifecycle source.
- [ ] **AC4**: ROADMAP's SKILL.md section classifies ROADMAP as working
      with completion condition "all features Done AND all referenced
      issues closed" and lifecycle `Draft -> Active -> Done -> DELETED`.
- [ ] **AC5**: CLAUDE.md gains a convention header (parallel format to
      Repo Visibility and Planning Context) that names the three-rule
      durable-vs-working model and points at per-skill SKILL.md as
      authoritative.
- [ ] **AC6**: `skills/work-on/scripts/run-cascade.sh` includes a
      `handle_roadmap_deletion` step that runs alongside the existing
      PLAN handler.
- [ ] **AC7**: `skills/work-on/koto-templates/work-on-plan.md`'s
      `plan_completion` state documents the `handle_roadmap_deletion`
      step in its prose and orders it within the same atomic
      finalization commit as the PLAN deletion (before `gh pr ready`).
- [ ] **AC8**: The `handle_roadmap_deletion` step is idempotent:
      invoking it when no ROADMAP exists in the chain, when the
      ROADMAP has already been deleted, or when the completion
      condition is unsatisfied is a safe no-op.
- [ ] **AC9**: The `handle_roadmap_deletion` step resolves the ROADMAP
      via upstream frontmatter walking (PLAN -> DESIGN -> PRD -> BRIEF
      -> ROADMAP) and triggers deletion only when all features are
      status Done and all referenced GitHub issues are closed.
- [ ] **AC10**: ROADMAP deletion, when triggered, performs the Active
      -> Done transition and the `git rm` in the same commit as the
      PLAN deletion and BRIEF/PRD/DESIGN transitions.
- [ ] **AC11**: No new shirabe CLI subcommand is introduced, no new
      validator check is added, no frontmatter schema field is changed,
      and no new artifact type is created.
- [ ] **AC12**: All prose surfaces referencing PLAN's lifecycle cite
      `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`
      and/or `skills/plan/SKILL.md` as the source; none re-state the
      lifecycle from scratch.
- [ ] **AC13**: The cascade's pre-`gh pr ready` ordering (DRAFT-vs-READY
      discipline from PR #176) holds: ROADMAP deletion runs inside the
      same `plan_completion` state and finalization commit as PLAN
      deletion, before `gh pr ready` fires.
- [ ] **AC14**: When the cascade runs against a chain with no ROADMAP,
      the `handle_roadmap_deletion` step exits cleanly without altering
      the cascade's `cascade_status` outcome (the no-ROADMAP case
      yields the same `completed` status the chain produces today).

## Out of Scope

- **Auto-derived completion-condition evidence.** A future world where
  the cascade reads richer evidence — issue-closure signals beyond
  filename matching, downstream-consumer state, derived rollups — to
  decide retirement is amplifier-layer work. This PRD ships the
  prose-and-cascade-step contract; evidence-driven automation is
  deferred.
- **Flipping BRIEF, PRD, or DESIGN to working.** These three carry the
  audit trail of why a feature was framed, what it requires, and how it
  is built. Their durability is intentional; making them working would
  defeat the chain's purpose.
- **Re-litigating PLAN's existing working behavior.** PLAN already
  retires on completion via PR #176's cascade. This PRD names PLAN as
  the existing precedent the new contract generalizes; it does not
  change PLAN's cleanup path or lifecycle.
- **CLI extensions or new substrate.** No new `shirabe` subcommand, no
  new validator rule, no new format check. The validator's
  `--lifecycle-chain` mode is unchanged. Future work may extend the
  validator to walk ROADMAP chains, but that is out of scope here.
- **Migration of existing stale ROADMAPs.** When this work lands,
  ROADMAPs already in `docs/roadmaps/` whose features are all Done
  remain in place until their next implementation cycle runs the
  cascade — or until a separate one-time cleanup pass retires them.
  The one-time pass is out of scope here.
- **Changing the cascade trigger.** PR #176's
  `DECISION-cascade-trigger-mechanism-2026-06-06.md` settled when the
  cascade runs. This PRD reuses that trigger; it does not propose a
  new one.

## Decisions and Trade-offs

**Decision 1: Contract location is per-skill SKILL.md, not a central
registry.** Considered: (a) a central
`references/artifact-lifecycle-contract.md` listing all eight skills and
their classifications; (b) a frontmatter field in each skill's SKILL.md;
(c) prose section in each skill's SKILL.md. Chose (c) for parallelism
with explore Phase 5's decision-lives-in-the-producer precedent: when a
skill author reads the skill, the contract is right there. A central
registry would force authors to consult two files; a frontmatter field
would couple the contract to schema validation, expanding the prose-only
scope boundary. CLAUDE.md gets a one-paragraph convention header
pointing readers at the per-skill prose, so there is one canonical
discovery path.

**Decision 2: ROADMAP completion condition is structural, not
amplifier-evidence-driven.** Considered: (a) "all features Done AND all
issues closed" (structural check), (b) "downstream amplifier evidence
plus heuristics for staleness", (c) "human-triggered retirement only".
Chose (a) because it is mechanically checkable in the cascade today
without new substrate, fits in the cascade's pre-`gh pr ready` window,
and matches the simplicity of PLAN's existing completion condition (a
PLAN's deletion fires when the implementing PR's cascade runs).
Amplifier-driven evidence is deferred per the BRIEF's scope boundary.

**Decision 3: Cascade extension is a bash step in
`run-cascade.sh`, not a pluggable handler interface.** Considered: (a)
adding a generic handler interface that future working artifacts
register against; (b) adding the step inline as
`handle_roadmap_deletion`. Chose (b) because the contract this PRD
ships is for one new working artifact (ROADMAP) on top of one existing
one (PLAN). A pluggable interface would over-design for hypothetical
future handlers and pull substrate work back into scope. The next time
a third working artifact appears, the cascade can grow a third named
step; if and when the count justifies a pluggable shape, that becomes
the next design's problem. The structure of one named step per working
artifact is itself the "extension point" the BRIEF asks for.

**Decision 4: ROADMAP lifecycle mirrors PLAN's exactly, including the
`Draft -> Active -> Done -> DELETED` shape.** Considered: (a) keep
ROADMAP at the existing `Draft -> Active -> Done` and add deletion as a
post-Done state; (b) align with PLAN's four-state shape including
DELETED as a verify-then-delete terminal. Chose (b) because PR #176
established the working-artifact lifecycle template and validator
chain-mode logic against the four-state shape. Aligning ROADMAP on the
same shape lets future amplifier work (extending `--lifecycle-chain` to
walk ROADMAP chains) reuse the PLAN code path without special-casing
ROADMAP. The auto-Active-on-create semantic differs: PLAN single-pr
auto-fires; ROADMAP keeps human approval at Active (features are locked
at activation, paralleling PLAN's multi-pr gate).

**Decision 5: Citation, not re-derivation, of PLAN's lifecycle.**
Considered: (a) restate the PLAN lifecycle in each prose surface that
references it; (b) cite the canonical source and rely on the link.
Chose (b) because PR #176 just landed the canonical source
(`DESIGN-lifecycle-draft-ready-discipline.md` plus `skills/plan/SKILL.md`),
restating it in multiple skills creates drift risk and re-litigation
risk. The citation pattern follows the explore precedent (each Phase 5
producer doc cites the producer skill it invokes, not the skill's
internals).

## Known Limitations

- **Migration of pre-existing stale ROADMAPs.** ROADMAPs already in
  `docs/roadmaps/` whose features are all Done at the time this work
  lands will not retire automatically. They retire when their chain's
  next cascade runs — which may never happen if no PR is in flight
  against that chain. A one-time cleanup pass is acknowledged as future
  work and explicitly out of scope.
- **Completion-condition fidelity.** The condition "all referenced
  GitHub issues closed" uses the structural issue-closure check. Issues
  closed-as-not-planned, transferred to other repos, or hidden behind
  GitHub renames may register inconsistently. The BRIEF's amplifier-
  driven evidence model is the right place to address this; the
  structural check is the simplest first contract.
- **Cascade order non-pluggability.** The cascade orders ROADMAP
  deletion alongside PLAN deletion within the same finalization commit.
  If a third working artifact ever arrives with ordering constraints
  (e.g., must delete only after upstream BRIEF/PRD transitions), the
  cascade must grow that ordering inline. This is acknowledged
  structural debt the BRIEF anticipates.
- **No tooling-level enforcement of the durable-vs-working contract.**
  Skill authors who omit the SKILL.md prose section, or who classify
  inconsistently, are caught only by human review. A future amplifier
  could add a FC-style validator check that requires the section to
  exist in any skill that produces an artifact; that is deferred.

## References

- BRIEF: `docs/briefs/BRIEF-shirabe-artifact-decision-contract.md`
  (upstream framing).
- PLAN lifecycle template authority:
  `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`,
  `docs/designs/current/DESIGN-skill-cascade-lifecycle-check.md`,
  `skills/plan/SKILL.md`.
- Cascade implementation:
  `skills/work-on/scripts/run-cascade.sh`,
  `skills/work-on/koto-templates/work-on-plan.md`
  (`plan_completion` state).
- Cascade-trigger rationale:
  `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md`.
- Strict-mode CLI flag rationale:
  `docs/decisions/DECISION-lifecycle-strict-mode-interface-2026-06-06.md`.
- Chain-targeted lifecycle CLI shape:
  `docs/decisions/DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06.md`.
- Decision-lives-in-the-producer precedent: explore skill's Phase 5
  family (`skills/explore/references/phases/phase-5-produce-*.md`).
- ROADMAP format: `skills/roadmap/references/roadmap-format.md`.
- Workflow principles:
  `${CLAUDE_PLUGIN_ROOT}/references/workflow-principles.md` (P1:
  observable value is the unit of work).

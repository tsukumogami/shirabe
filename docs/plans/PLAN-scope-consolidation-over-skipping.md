---
schema: plan/v1
status: Draft
execution_mode: single-pr
milestone: "Scope consolidation over skipping"
issue_count: 6
upstream: docs/designs/DESIGN-scope-consolidation-over-skipping.md
---

# PLAN: scope-consolidation-over-skipping

## Status

Draft

Single-PR plan for the design's six batches. All six land on one branch and
one pull request; the outlines below are the work units, not GitHub issues.

## Scope Summary

Implements `DESIGN-scope-consolidation-over-skipping`: remove `/scope`'s
per-hop produce-or-skip gates so the whole tactical chain runs on every
invocation, invoke each child through the upstream-path input mode it already
ships, add a per-hop consolidation judgment with an absorbability rule derived
from the required-section schemas, retire `/brief`'s fold-into-PRD branch, and
generalize the validator's Plan-only upstream-resolution check to every
format.

The work is prose across four skills plus one small Rust change and three
eval suites. There is no new binary, no new subcommand, no new schema, and
no new gate shape.

## Decomposition Strategy

**Horizontal, by file cluster.** Each outline owns one coherent surface so
the diff for each is readable on its own: `/scope`'s Phase 1, `/scope`'s
Phase 2, `/scope`'s SKILL.md and state schema, the three child skills, the
validator, and the evals.

Sequencing is shallow. The Phase 1 and Phase 2 changes are independent of
each other — Phase 1 decides the chain shape and Phase 2 walks it, and
neither reads the other's prose. The SKILL.md summary and state-schema
outline consumes both, so it follows them. The child-skill and validator
outlines are independent of everything. Evals go last because they assert
against the shipped behavior of the four skills.

Single-pr execution mode: the six outlines share one branch and one PR, and
the PLAN is deleted by the completion cascade when the PR is finalized.

## Issue Outlines

### Issue 1: Phase 1 stops deciding how many artifacts the run produces

**Goal**: Rewrite `skills/scope/references/phases/phase-1-discovery.md` so
that Phase 1 makes no decision about the size of the artifact set — neither
per hop, nor by choosing where the chain starts.

**Dependencies**: None

**Acceptance Criteria**:
- The R4 and R5 gate sections describe re-entry protection against
  overwriting a settled artifact and state explicitly that this is not a
  judgment about whether the artifact is worth producing. The recorded skip
  reason is `settled-artifact-at-canonical-path-reentry-protection`.
- The R6 predicate walk (P1, P2, P3) is retargeted to a single consumer:
  `/design`'s decision-roster size. It no longer decides whether `/design` is
  invoked.
- A new "What Phase 1 Decides, and What It Does Not" section states that
  `planned_chain:` is `[brief, prd, design, plan]` on every run, that there is
  no starting altitude to choose, and that an author wanting a shorter chain
  invokes `/design` or `/plan` directly.
- A Durable-Artifact Floor section states that the floor follows from the
  chain shape plus the absorbability rule, and explicitly instructs against
  adding a guard, because the condition cannot hold and a check that never
  fires misleads.
- `planned_chain:` population is the whole chain, in order, minus any child
  held back by re-entry protection.
- `shirabe validate` is clean over the changed file and the file contains no
  reference to a `wip/` path as a durable pointer.

### Issue 2: Upstream-path child invocation and the consolidation judgment in `/scope` Phase 2

**Goal**: Rewrite `skills/scope/references/phases/phase-2-chain-orchestration.md`
so children consume the artifacts the chain produced, and add the per-hop
consolidation judgment as step 8 of the invocation loop.

**Dependencies**: None

**Acceptance Criteria**:
- The Child Invocation section states the argument rule: `/brief` receives
  the topic slug; every later child receives the path of the nearest
  artifact this chain produced above it (`/prd docs/briefs/BRIEF-<topic>.md`,
  `/design docs/prds/PRD-<topic>.md`, `/plan docs/designs/DESIGN-<topic>.md`).
- The section states that these are input modes each child already ships, and
  re-states the R14 boundary: no flag, no argument, no environment variable,
  and no new parse branch is added to any child.
- The per-child loop grows an eighth step, the consolidation judgment, placed
  after the validator pass-through.
- A Consolidation Judgment section carries the absorbability mapping table
  from the design (BRIEF to PRD absorbable; PRD to DESIGN and DESIGN to PLAN
  not, with the unmapped sections named), the three stages, the
  `consolidation_judgments:` carry-check schema, and the absorb procedure
  (inherit the absorbed artifact's `upstream:` or omit, `git rm`, re-validate,
  revert on failure).
- The abort path is specified: any `carried: false` downgrades the verdict to
  `keep`, records the section that did not arrive, and leaves both artifacts
  in place.
- The manual-fallback boundary is stated: step 8 exists only in `/scope`, so
  a directly-invoked child runs no judgment and writes no `/scope` state.
- No new field joins the state-file enum re-validation list: the chain shape
  is a constant, the child names are fixed, and each child's argument path is
  composed from the validated topic slug rather than from state.
- `shirabe validate` is clean over the changed file.

### Issue 3: `/scope` SKILL.md and state-schema updates

**Goal**: Bring `skills/scope/SKILL.md` and
`skills/scope/references/state-schema.md` into line with the two phase
rewrites, and state the reader-facing rationale at the layer that now
performs the reduction.

**Dependencies**: Issue 1, Issue 2

**Acceptance Criteria**:
- `skills/scope/SKILL.md` gains a section stating, in `/scope`'s own words,
  why the artifact set shrinks: three documents restating one problem at
  three altitudes cost a reader three reads for one idea. The section does
  not defer to `/brief` for the rationale.
- `skills/scope/SKILL.md` gains a Consolidation Judgment section naming the
  two verdicts, the absorbability rule, and the carry check, pointing at the
  Phase 2 reference for the mechanism.
- The Workflow Phases table and the Chain-Proposal Output section reflect a
  chain shape that is the same on every run.
- The Security Considerations section records `docs/briefs/` as a delete
  target in the closed write-target set.
- `skills/scope/references/state-schema.md` documents `visibility:` and
  `consolidation_judgments:` (the per-hop verdict list with its carry table),
  including which fields are conditional per invariant I-5, and records no
  field for where the chain starts.
- No fourth gate shape appears anywhere;
  `references/parent-skill-pattern.md` still names exactly three.
- `shirabe validate` is clean over the changed files.

### Issue 4: Retire `/brief`'s fold path and teach `/prd` to consume its upstream

**Goal**: Remove the second mechanism sharing the consolidation name, and
make the PRD draft from the BRIEF it was handed rather than re-deriving the
framing.

**Dependencies**: None

**Acceptance Criteria**:
- The fold-into-PRD branch is removed from
  `skills/brief/references/phases/phase-0-setup.md`; the artifact decision
  reduces to producing a standalone brief, and the skill ends by
  recommending `/prd <brief-path>`.
- `skills/brief/SKILL.md`'s Critical Requirements and Output sections no
  longer describe an artifact decision that can decline to produce a brief.
- `skills/prd/references/phases/phase-3-draft.md` instructs the author, when
  an upstream BRIEF exists, to draw the Problem Statement, Goals, User
  Stories, and Out of Scope from that brief's body rather than from the PRD's
  own Phase 1 conversation.
- `skills/prd/references/prd-format.md` and
  `skills/design/references/design-format.md` state the citation rule in
  their quality guidance: the standalone-readability rule is scoped to the
  problem statement, and everything the upstream already says is cited rather
  than re-narrated.
- No BRIEF or PRD required section is added or removed.
- `shirabe validate` is clean over the changed files.

### Issue 5: Generalize the validator's upstream-resolution check to every format

**Goal**: Make a dangling `upstream:` an error on any document type, so a
missed re-point after an absorb fails mechanically.

**Dependencies**: None

**Acceptance Criteria**:
- `check_plan_upstream` in `crates/shirabe-validate/src/checks.rs` is renamed
  `check_upstream_resolves` and no longer depends on the Plan profile.
- The check returns early for cross-repo `owner/repo:path` references, which
  are not resolvable on this filesystem.
- The call site in `crates/shirabe-validate/src/validate.rs` moves out of the
  `Some("Plan")` match arm into the common per-doc path.
- The check code stays `R6` and both existing messages are unchanged, so
  `is_known_check_code` needs no new entry.
- Unit tests cover: a resolving `upstream:` on a non-Plan doc is clean; a
  dangling `upstream:` on a non-Plan doc reports `R6`; a cross-repo reference
  is skipped; an absent `upstream:` field is clean.
- `cargo test --workspace` passes.
- `shirabe validate` over `docs/` is clean, confirming no document in the
  repository already carries a dangling upstream.

### Issue 6: Evals for the changed behaviors

**Goal**: Cover the new behavior in the eval suites of every skill whose
behavior changed, and run only those suites.

**Dependencies**: Issue 1, Issue 2, Issue 3, Issue 4

**Acceptance Criteria**:
- `skills/scope/evals/evals.json` gains scenarios for: the chain shape being
  constant even when the author says the framing is settled; the
  durable-artifact floor being structural rather than guarded; a child invoked
  with its upstream artifact's path rather than the topic slug; an `absorb`
  verdict with its carry table; a `keep` verdict at an unmapped hop; and a
  re-entry-protection skip carrying the renamed reason.
- `skills/brief/evals/evals.json` no longer asserts the fold-into-PRD path
  and asserts that a brief is always produced.
- `skills/prd/evals/evals.json` asserts that PRD drafting reads the upstream
  BRIEF's body when one exists.
- `scripts/run-evals.sh scope`, `scripts/run-evals.sh brief`, and
  `scripts/run-evals.sh prd` pass. No other suite is run.

## Implementation Sequence

1. **Issue 1** and **Issue 2** in parallel — the two `/scope` phase
   references. Independent files, independent contracts.
2. **Issue 4** and **Issue 5** in parallel with the above — the child skills
   and the validator touch no `/scope` file.
3. **Issue 3** after Issues 1 and 2 — the SKILL.md summary and the state
   schema describe what those two settled.
4. **Issue 6** last — the evals assert against the shipped behavior of
   Issues 1 through 4.

Verification gate before the PR is marked ready: `cargo test --workspace`
passes, `shirabe validate` is clean over every changed document, and the
three touched eval suites pass.

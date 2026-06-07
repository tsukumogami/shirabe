---
schema: prd/v1
status: Done
upstream: docs/briefs/BRIEF-shirabe-pattern-v1-ergonomics.md
problem: |
  Shirabe's parent-skill pattern v1 — the contract letting `/scope`,
  `/charter`, and the workflow children compose into chain workflows —
  silently degrades to whatever the dispatched sub-agent improvises
  when the operating context doesn't match the assumed ideal (Agent
  tool fan-out, `AskUserQuestion` user, empty `wip/`, matching CLI
  version, validator-catches-everything). About 24 inside-pattern
  observations across nine child skills, the parent-pattern
  reference, four format references, and the validator share the
  same failure shape; the chain tax compounds across children and
  the audit trail diverges from execution.
goals: |
  Every Phase-N jury site, approval site, Resume Logic table, format
  reference, and validator check that pattern v1's prose silently
  assumed ideal conditions for emits explicit signal at the boundary.
  Operators running `/scope` and `/charter`, and authors invoking
  child skills directly, see fallback paths named in skill bodies
  and acknowledged in artifact preambles. The chain's audit trail
  matches the chain's actual execution rather than the chain the
  prose assumed.
---

## Status

Done

Phase 4 jury returned all-PASS as serial-self-jury under
sub-agent dispatch from `/scope`
(`parent_orchestration.invoking_child: prd`,
`rationale: fresh-chain`); the independence-loss caveat is
recorded in each verdict file
(`wip/research/prd_shirabe-pattern-v1-ergonomics_phase4_completeness.md`,
`...phase4_clarity.md`, `...phase4_testability.md`). The downstream
DESIGN picks the implementation mechanism per observation; this
PRD commits the contracts that must hold.

Cascade edit (post-DESIGN-Accepted): R3, R23, R25, R26, R28 are
rephrased to permit detection-and-pointer mechanisms in the
consuming skill body with resolution prose carried in a shared
reference file at a well-known path. The contract — what must
hold — is unchanged; the rephrasing removes eager-load implications
that contradict the lazy-load principle the downstream DESIGN
applies. ACs are unchanged; the rephrased requirements continue
to satisfy them via the per-error reference files DESIGN Batch 2
materializes.

## Problem Statement

Shirabe's parent-skill pattern v1 has been dogfooded across two
rounds — v0.7.0/0.7.1-dev (during `/comp` skill authoring and the
child-dispatch-contract work) and v0.9.0/v0.9.1-dev (during this
chain's authoring against the Rust-cutover validate codebase). The
rounds surfaced roughly 24 inside-pattern observations clustered
into six fix surfaces plus the CLI version-skew boundary
observation. The BRIEF
(`docs/briefs/BRIEF-shirabe-pattern-v1-ergonomics.md`) frames the
failure shape (silent degradation rather than loud failure) and
the umbrella treatment; this PRD enumerates the per-observation
contracts that must hold and the acceptance criteria that verify
them.

The dominant operating context is sub-agent dispatch: orchestrators
invoke children as sub-agents, hand them fresh topics with no
upstream, automate approval, run against whatever shirabe binary
the workspace has installed, and are themselves substrates the
per-skill validators don't see. Every assumption the child-skill
prose was written under breaks. The Phase 4 jury that nominally
fans out into three independent reviewers collapses to one agent
doing serial self-review and the verdicts read PASS. The Resume
Logic table doesn't know about the `parent_orchestration` sentinel
and re-prompts as if the run were cold-started. The "approximately
110 lines" budget written into a DESIGN ships at 183 lines and the
validator exits 0. The CLI version-skew between the skill's
prescribed `shirabe transition` and the on-disk binary fails open
with "unknown command". Each individual failure recovers via
operator improvisation, but every chain pays the same tax.

This PRD scopes the inside-pattern fix surface. The
amplifier-layer substrate work (Track B of the inside-pattern
ergonomics split) is out of scope here — those observations
require koto composability extensions and live in the
post-amplifier-layer-substrate work, tracked separately as a
forward-looking effort. Standalone shirabe BUG-class issues that
don't fit the pattern-ergonomics frame stay open as their own
work streams.

## Goals

- An orchestrator running `/scope` or `/charter` reaches the
  terminal artifact through a chain whose every Phase-N jury,
  approval site, Resume Logic table, format reference, and
  validator check has acknowledged its operating context and
  named what it did about that context. Silent degradation is
  replaced by explicit signal at the boundary.
- An author invoking a child skill directly — outside the
  orchestrator path — finds Resume Logic tables that account for
  the routing field a future caller might set, convention prompts
  that fire when the author's first guess didn't match the repo's
  precedent, and CLI-version preflight that catches install-skew
  before the skill body's prescribed subcommand fails.
- A reader reading the resulting docs cold finds an audit trail
  that matches the chain's actual execution. Phase-N verdict
  files surface the operating context (parallel jury vs
  serial-self-jury with independence-loss caveat). DESIGN
  Implementation Issues tables don't drift between `/design`
  prescription and `/plan` consumption. Validator exit-0 means
  what the operator thinks it means.

## User Stories

The journeys grounding this PRD are enumerated in
`docs/briefs/BRIEF-shirabe-pattern-v1-ergonomics.md` (the BRIEF's
User Journeys section) — orchestrator-dispatches-a-child-whose-jury-can't-fan-out,
author-runs-scope-on-a-fresh-topic, author-types-a-slug-drifting-from-convention,
downstream-author-traces-upstream-framing, and
validator-catches-content-budget-overshoot. The five journeys
ground requirements R1-R30 below.

As a maintainer dispatching `/prd` as a sub-agent from `/scope`,
I want the dispatched child to record its operating context and
the independence-loss caveat in the Phase 4 verdict files, so
that the chain's audit trail shows whether the jury fanned out or
ran serially.

As a maintainer running `/scope` on a fresh topic with no
upstream, I want Phase 1's R6 forward-looking predicates to
evaluate the projected PRD's expected content shape rather than
trivially-not-fire on the absent file, so that `/design` is
included when the topic has architectural alternatives.

As a maintainer typing a slug that drifts from the repo's prefix
convention (`brief-skill-update` in a repo whose artifacts use
`shirabe-`), I want Phase 0 to detect the mismatch and prompt
me before any durable artifact commits, so that the audit trail
honors the repo's convention.

As a downstream author reading a child SKILL.md to understand a
single phase, I want the SKILL.md to cite pattern-level
references rather than restate them verbatim, so that context
budget is preserved and cross-skill consistency comes from one
canonical statement.

As a maintainer who shipped a DESIGN section budgeted at "~110
lines" and the section shipped at 183 lines, I want the validator
or the Phase 6 jury to surface the overshoot rather than exit 0,
so that I know to revise before `/plan` consumes the DESIGN.

## Requirements

Functional requirements are grouped by the six fix-surface
clusters the BRIEF names, plus the two adjacent observations.
Each requirement names the contract that must hold; the
implementation mechanism (skill-prose edit, reference-content
edit, validator extension) is DESIGN territory unless explicitly
noted.

### Cluster 1 — Sub-agent dispatch fallbacks

**R1** — Each child SKILL (`/brief`, `/prd`, `/design`, `/plan`)
SHALL surface a fallback path for Phase-N parallel-agent jury
sites that names serial-self-jury as the substitute when invoked
as a sub-agent. The path SHALL state that each reviewer rubric is
evaluated against its specific lens without cross-contamination,
and SHALL require the verdict artifact preamble surface the
operating context plus the independence-loss caveat.

**R2** — Each strategic child SKILL (`/vision`, `/strategy`,
`/roadmap`) SHALL surface the same Phase-N jury fallback path R1
prescribes, on the same shape — because `/charter` dispatches the
strategic chain the same way `/scope` dispatches the tactical
chain.

**R3** — Each child SKILL with a human approval gate
(`AskUserQuestion`) SHALL provide a detection path that points
the agent at the parent-delegated-approval fallback under
sub-agent dispatch. The detection path MAY live inline in the
SKILL body; the resolution prose (where the transition-and-commit
boundary moves to — parent or held until parent returns) MAY
live in a shared per-error reference file the agent loads on
demand. The contract is that the fallback is reachable from the
child SKILL when the sentinel is present, not that the fallback
prose is eager-loaded into the SKILL body.

**R4** — `/design` Phases 1-3 (the per-decision `/decision`
dispatch loop) SHALL surface a fallback that names an
inline-resolution variant when the upstream PRD has already
enumerated alternatives and recommended a direction. The fallback
SHALL state the conditions under which the bypass is acceptable
(PRD names alternatives explicitly; reviewer count is acceptable
inline) and what is recorded in the DESIGN to mark the bypass.

**R5** — `/plan` Phase 3 (execution-mode `AskUserQuestion`) SHALL
surface a fallback that reads the execution-mode hint from the
parent dispatch contract (`plan_execution_mode: single-pr |
multi-pr`) instead of prompting.

**R6** — `/plan` Phase 6 (the nested `/review-plan` sub-skill
dispatch) SHALL surface an inline-substitute single-pass review
variant when invoked as a sub-agent that cannot recursively
dispatch.

**R7** — `/work-on`'s plan-orchestrator SHALL provide a detection
path that points the agent at the deterministic-mode bypass for
the koto state machine when the parent dispatch contract supplies
decomposition, cascade timing, and push timing upfront. The
detection MAY live inline in `/work-on`'s body; the resolution
prose (the engagement conditions and what the audit trail records)
MAY live in a shared per-error reference file the agent loads on
demand. The contract is that the bypass is reachable from
`/work-on` when the parent dispatch contract is present, not that
the bypass prose is eager-loaded into the SKILL body.

**R8** — Each fallback path R1-R7 prescribes SHALL state
explicitly what is NOT covered — specifically, that nested-team
spawning remains Track B (amplifier-layer mandate work, tracked
separately as a forward-looking effort) and is not addressed by
inside-pattern fallbacks.

### Cluster 2 — Resume Logic sentinel-awareness

**R9** — Each child SKILL (`/brief`, `/prd`, `/design`, `/plan`,
`/vision`, `/strategy`, `/roadmap`) Resume Logic SHALL consult
the `parent_orchestration:` sentinel before evaluating the
existing wip/-file-existence and status-aware rows. When the
sentinel is present, the child SHALL follow the
`invoking_child`, `suppress_status_aware_prompt`, and `rationale`
fields. When the sentinel is absent, the child SHALL fall through
to existing Resume Logic behavior unchanged.

**R10** — The pattern-level reference
(`references/parent-skill-pattern.md`) SHALL describe the
sentinel-consultation row convention so each child inherits it
consistently.

### Cluster 3 — Format-reference clarifications

**R11** — `brief-format.md` and `prd-format.md` SHALL state
explicitly whether public issue numbers in public-repo artifacts
are allowed. The grammar ambiguity (whether the "private"
qualifier in "private paths, repos, filenames, codenames, OR
issue numbers" distributes across all five) SHALL be
disambiguated either by inserting "private" before "issue
numbers" if the qualifier distributes, or by stating the
ruling explicitly with rationale.

**R12** — Either `brief-format.md` / `prd-format.md` SHALL
document an optional `motivating_context:` frontmatter field
that accepts a cross-repo reference and is allowed to point at a
private artifact from a public document, OR the "carry framing
forward in prose" workaround SHALL be documented as load-bearing.
DESIGN picks one; the PRD requires at least one path be
documented.

**R13** — `brief-format.md` SHALL name "the downstream PRD's
Decisions and Trade-offs section" as the canonical closure
surface for BRIEF Open Questions when promoting Draft → Accepted.

**R14** — `prd-format.md` SHALL surface "Decisions and
Trade-offs" as the conventional section for closing upstream
BRIEF Open Questions, with the convention named explicitly in
the Optional Sections description.

**R15** — `design-format.md` and `skills/design/SKILL.md` SHALL
state the Implementation Issues table ownership convention
explicitly. Either the SKILL.md describes the inline-issues-table
path as a supported variant with rationale, or the dispatch
convention is updated to match the SKILL.md's `/plan`-owns-it
framing.

**R16** — `prd-format.md` Content Boundaries SHALL distinguish
"competitive findings" (content the PRD does NOT contain) from
"competitive-analysis-as-an-artifact-type" (a subject the PRD
may reference, e.g., a PRD authoring the `/comp` skill).

**R17** — `plan-format.md` SHALL document the canonical structure
of the `## Implementation Issues` section as emitted by `/plan`'s
single-pr execution mode, addressing the contract drift named in
`tsukumogami/shirabe#158`.

### Cluster 4 — Validator extensions

**R18** — The validator SHALL surface missing `schema:`
frontmatter as a non-zero exit condition (warning or error) rather
than silently skipping the artifact and exiting 0. This addresses
`tsukumogami/shirabe#157`. The specific exit-code level (warning
vs error) and the FC code assignment are DESIGN territory.

**R19** — Section-length budget overshoots SHALL be surfaced —
either by the validator (soft-warning lane at the FC level) or by
the `/design` Phase 6 jury (budget-vs-spec reviewer) — when a
DESIGN's spec names a budget the section overshoots by more than
a documented threshold. The surface choice and threshold are
DESIGN territory.

**R20** — Mechanical writing-style banned-word detection SHALL be
surfaced for the workspace's banned vocabulary (the words
enumerated in the writing-style reference: "robust", "leverage",
"comprehensive", "holistic", "facilitate", "tier", "tiered").
The mechanism — validator notice, Phase 4 reviewer, pre-commit
hook — is DESIGN territory.

**R21** — `/design` Phase 6's reviewer set SHALL include a
structural-format reviewer that checks artifact-shape conformance
against the design-format reference (the analog of `/brief` Phase
4's structural-format reviewer and `/prd` Phase 4's testability
reviewer). The omission is named in the friction log.

**R22** — `/plan` Phase 7's single-pr `## Implementation Issues`
emission SHALL be checked — by validator or by Phase 7 itself —
against the canonical structure R17 documents. Drift between
emitted prose and the format reference SHALL be flagged.

### Cluster 5 — Cross-skill consistency rules

**R23** — Field-name consistency across sibling issue outlines
that touch the same artifact field SHALL be detected and flagged.
When a field's contract is defined two ways across sibling
issues (one as free-text prose, another as enum), the collision
SHALL be surfaced rather than silently emitted. The detection
mechanism (validator extension with FC-code and pointer to a
per-error reference file, vs `/plan` Phase-N pre-flight prose,
vs both) is DESIGN territory; the lazy-load principle prefers
CLI-deterministic detection over eager-load skill prose when
both are feasible.

**R24** — `/plan` ACs that claim "annotation only; schema fields
unchanged" SHALL grep the target file at PLAN-authoring time to
confirm the asserted anchor exists. When the anchor is absent,
the AC SHALL be rewritten defensively ("annotation added; if
anchor missing, this issue includes the minimal anchor
definition") rather than silently presupposing.

**R25** — The `/design` Phase 6 `wip/`-hygiene rule's carve-out
SHALL extend to "documentation of a skill's runtime `wip/`
usage" — currently the carve-out covers "quoted statements OF
the rule itself" but not skill-implementation DESIGNs that
describe a skill's runtime `wip/` contract (e.g.,
`DESIGN-shirabe-strategy-skill`, `DESIGN-shirabe-brief-skill`).
The carve-out is a single-sentence rule clarification; eager-loading
it in the format reference is acceptable (the lazy-load principle's
tier-3 placement applies when tiers 1 and 2 are infeasible AND the
prose is small enough that eager-loading does not bloat context).

**R26** — The HTML-comment line-1 marker conflict with the
frontmatter parser's `---`-first-non-blank-line requirement
SHALL be detected and surfaced. Fixtures requiring a marker
SHALL place it after frontmatter or inside a frontmatter field,
never on line 1. The detection mechanism (validator extension
with FC-code and pointer to a per-error reference file, vs
eager-loaded authoring guidance, vs both) is DESIGN territory;
the lazy-load principle prefers CLI-deterministic detection over
eager-load skill prose when both are feasible.

### Cluster 6 — Convention updates

**R27** — `/scope` Phase 0 SHALL sample existing artifacts in
`docs/briefs/`, `docs/prds/`, `docs/designs/`, `docs/plans/` to
detect a repo-prefix convention (e.g., shirabe's
`shirabe-<feature>` precedent). When the input slug lacks the
detected prefix, Phase 0 SHALL prompt the author before
committing any durable artifact to the wrong name.

**R28** — ACs that reference a "release-notes draft" SHALL
target durable adopter docs in the location the workspace
actually uses (`docs/guides/` per current convention; the PRD
defers location confirmation to DESIGN). The per-repo convention
SHALL be detectable in a single canonical place (e.g., a CLAUDE.md
header) and the detection mechanism (validator extension with
FC-code and pointer to a per-error reference file, vs eager-load
in `/prd` and `/design` Phase 0 prose, vs both) is DESIGN
territory; the lazy-load principle prefers CLI-deterministic
detection over eager-load skill prose when both are feasible.
The contract is that `/prd` and `/design` reach the workspace's
actual release-notes mechanism and frame adopter-obligation ACs
against it — not that the workspace's mechanism is eager-loaded
into either SKILL body.

**R29** — `/scope` Phase 1's R6 forward-looking predicates (P1
and P3, which inspect a PRD body) SHALL evaluate the projected
PRD's expected content shape when the PRD file doesn't yet
exist at cold-start, rather than trivially-not-fire. `/design`
SHALL fire tentatively when the projected PRD implies
architectural alternatives, with a post-`/prd` re-evaluation
gate. Phase 1's framing-shift opener SHALL short-circuit when
topic-related child-doc discovery returns empty (cold-start).

### Cluster 7 — CLI version-skew preflight

**R30** — Any child SKILL body prescribing a `shirabe`
subcommand (e.g., `shirabe transition`) SHALL surface a
CLI-version preflight that detects whether the subcommand exists
in the installed binary, with a documented fallback prose path
(typically a manual sed-edit equivalent) when the subcommand is
absent. The preflight mechanism — shell snippet inline,
capability detection at skill load, parent-skill inheritance —
is DESIGN territory.

### Non-functional requirements

**R31** — All changes prescribed by R1-R30 SHALL preserve the
existing top-level invocation path: an author invoking a child
skill directly from the terminal SHALL see the same behavior the
skill currently produces, with fallback paths active only when
the sub-agent dispatch context (`parent_orchestration` sentinel
or equivalent) is present.

**R32** — Sequencing constraints inherent to the cluster set
SHALL be respected: the pattern-level reference edits (R10, R13,
R14, R16) land before the per-skill consumers that inherit from
them (R1-R9, R11-R12, R15, R17). Validator extensions (R18-R22)
land alongside or after the prose changes that reference them
(specifically R20's writing-style detection lands alongside the
writing-style reference, not before).

## Acceptance Criteria

Acceptance criteria are organized by cluster matching the
requirements. Each criterion is binary pass/fail and verifiable
by a developer who didn't write the PRD.

### Cluster 1 — Sub-agent dispatch fallbacks

- [ ] **AC1.1** — Each of `skills/brief/SKILL.md`,
  `skills/prd/SKILL.md`, `skills/design/SKILL.md`,
  `skills/plan/SKILL.md` contains a section addressing how the
  skill behaves at its Phase-N parallel-agent jury site when
  invoked as a sub-agent.
- [ ] **AC1.2** — The section in AC1.1 names "serial-self-jury"
  (or equivalent prose) as the substitute and names the
  independence-loss caveat that the verdict artifact's preamble
  surfaces.
- [ ] **AC1.3** — Each of `skills/vision/SKILL.md`,
  `skills/strategy/SKILL.md`, `skills/roadmap/SKILL.md`
  contains a section matching AC1.1 and AC1.2 for the strategic
  chain.
- [ ] **AC1.4** — Each child SKILL with an approval gate
  documents the parent-delegated-approval fallback.
- [ ] **AC1.5** — `skills/design/SKILL.md` documents the
  inline-resolution `/decision`-bypass variant with named
  conditions.
- [ ] **AC1.6** — `skills/plan/SKILL.md` documents the
  execution-mode-hint-read path under sub-agent dispatch.
- [ ] **AC1.7** — `skills/plan/SKILL.md` documents the
  inline-substitute `/review-plan` variant under sub-agent
  dispatch.
- [ ] **AC1.8** — `skills/work-on/SKILL.md` documents the
  deterministic-mode bypass for the koto state machine.
- [ ] **AC1.9** — Every fallback section AC1.1-AC1.8 names
  reaches contains an explicit "NOT covered: nested-team
  spawning (Track B, amplifier-layer mandate, tracked separately
  as a forward-looking effort)" or equivalent carve-out.

### Cluster 2 — Resume Logic sentinel-awareness

- [ ] **AC2.1** — Each child SKILL Resume Logic table
  (`skills/brief/SKILL.md`, `skills/prd/SKILL.md`,
  `skills/design/SKILL.md`, `skills/plan/SKILL.md`,
  `skills/vision/SKILL.md`, `skills/strategy/SKILL.md`,
  `skills/roadmap/SKILL.md`) contains a row that consults the
  `parent_orchestration:` sentinel before evaluating
  wip/-file-existence rows.
- [ ] **AC2.2** — The sentinel-consultation row names the
  fields it reads (`invoking_child`,
  `suppress_status_aware_prompt`, `rationale`) and the action
  taken when the sentinel is present.
- [ ] **AC2.3** — The pattern-level reference
  (`references/parent-skill-pattern.md` or equivalent) describes
  the sentinel-consultation row convention.

### Cluster 3 — Format-reference clarifications

- [ ] **AC3.1** — `references/brief-format.md` and
  `references/prd-format.md` state explicitly whether public
  issue numbers in public-repo artifacts are allowed, with
  rationale.
- [ ] **AC3.2** — Either `references/brief-format.md` /
  `references/prd-format.md` documents an optional
  `motivating_context:` frontmatter field, OR the "carry
  framing forward in prose" workaround is documented as
  load-bearing.
- [ ] **AC3.3** — `references/brief-format.md` names "the
  downstream PRD's Decisions and Trade-offs section" as the
  canonical BRIEF Open Questions closure surface.
- [ ] **AC3.4** — `references/prd-format.md` surfaces
  "Decisions and Trade-offs" as the conventional
  BRIEF-Open-Questions closure section.
- [ ] **AC3.5** — `references/design-format.md` and
  `skills/design/SKILL.md` state the Implementation Issues
  table ownership convention explicitly.
- [ ] **AC3.6** — `references/prd-format.md` Content
  Boundaries distinguishes "competitive findings" from
  "competitive-analysis-as-an-artifact-type."
- [ ] **AC3.7** — `references/plan-format.md` documents the
  canonical structure of the `## Implementation Issues`
  section as emitted by `/plan` single-pr mode.

### Cluster 4 — Validator extensions

- [ ] **AC4.1** — Running `shirabe validate` against an
  artifact missing `schema:` frontmatter produces a non-zero
  exit code (warning or error) rather than exit 0.
- [ ] **AC4.2** — A DESIGN section whose spec names a budget
  the section overshoots by the documented threshold is
  surfaced (validator output or `/design` Phase 6 jury verdict
  flags it).
- [ ] **AC4.3** — A document containing any of "robust",
  "leverage", "comprehensive", "holistic", "facilitate",
  "tier", "tiered" is surfaced by the mechanical
  writing-style check at the surface DESIGN chooses
  (validator notice, Phase 4 reviewer, pre-commit hook).
- [ ] **AC4.4** — `/design` Phase 6's jury invocation
  spawns a structural-format reviewer in addition to the
  existing reviewers.
- [ ] **AC4.5** — `/plan` Phase 7's single-pr
  `## Implementation Issues` emission is checked against the
  canonical structure documented under AC3.7; drift is
  flagged.

### Cluster 5 — Cross-skill consistency rules

- [ ] **AC5.1** — `/plan` (Phase 7 or a separate pre-flight
  phase) runs a cross-issue field consistency pass and flags
  collisions where a field's contract is defined two ways
  across sibling issues.
- [ ] **AC5.2** — `/plan` ACs that claim "annotation only"
  grep the target file at PLAN-authoring time and either
  succeed when the anchor exists or rewrite the AC defensively
  when it doesn't.
- [ ] **AC5.3** — The `/design` Phase 6 `wip/`-hygiene
  carve-out wording extends to "documentation of a skill's
  runtime `wip/` usage."
- [ ] **AC5.4** — Eval-fixture authoring guidance
  reconciles the HTML-comment marker placement with the
  frontmatter parser's line-1 constraint.

### Cluster 6 — Convention updates

- [ ] **AC6.1** — `/scope` Phase 0 samples existing artifacts
  and prompts the author when the input slug lacks the
  detected repo-prefix convention.
- [ ] **AC6.2** — Issue ACs referencing release-notes target
  durable adopter docs at the location the workspace uses, not
  a non-existent committed CHANGELOG file.
- [ ] **AC6.3** — `/scope` Phase 1's R6 P1/P3 predicates
  evaluate the projected PRD's expected content shape when
  the PRD doesn't yet exist at cold-start.
- [ ] **AC6.4** — `/scope` Phase 1's framing-shift opener
  short-circuits when topic-related child-doc discovery
  returns empty at cold-start.

### Cluster 7 — CLI version-skew preflight

- [ ] **AC7.1** — Each child SKILL body prescribing a
  `shirabe` subcommand surfaces a CLI-version preflight prose
  path with a named fallback when the subcommand is absent
  from the installed binary.

### Non-functional

- [ ] **AC8.1** — Running any child skill at the terminal
  without the `parent_orchestration` sentinel produces the
  same behavior the skill produced before the changes
  prescribed by R1-R30 — fallback paths activate only when
  the sentinel (or equivalent sub-agent dispatch signal) is
  present.
- [ ] **AC8.2** — The implementation sequencing respects R32:
  the pattern-level reference edits (R10, R13, R14, R16) land
  before the per-skill consumers (R1-R9, R11-R12, R15, R17);
  the writing-style mechanical check (R20) lands alongside
  the writing-style reference it enforces.

## Out of Scope

- The amplifier-layer mandate refinement work (Track B,
  tracked separately as a forward-looking effort). Those
  observations require substrate primitives (durable team state,
  cross-team messaging, structured team-shape declarator,
  live-team-query, nested teams, coordinator-side lazy
  spawning, idle-notification filtering at substrate level,
  separate parent/team task lists, message-ordering
  guarantees) that the inside-pattern cannot supply.
  Hard-blocked on the koto composability extensions work.
- The per-skill artifact-decision contract — whether each
  child skill should produce a durable artifact or hand off
  to its downstream consumer. That work is tracked
  separately on the shirabe roadmap and overlaps the BRIEF
  altitude only incidentally.
- Standalone shirabe BUG-class issues that don't fit the
  pattern-ergonomics frame
  (`tsukumogami/shirabe#155`, `#160`, `#161`, `#163`, `#164`,
  and others in the same lineage). `#157` (schema
  silent-skip) and `#158` (single-pr Implementation Issues
  drift) intersect this PRD's requirements (R18 and R17/R22
  respectively) because the fix is the same surface; the
  remaining bugs stay open as their own work streams.
- The solution shape per observation. The fix-candidate
  alternatives for each observation (e.g., for sub-agent
  dispatch fallbacks: explicit "Running as a sub-agent"
  section per child vs. pattern-level marker convention vs.
  shared parent-pattern fallback site; for validator content
  budgets: `/design` Phase 6 jury extension vs. validator
  soft-warning lane vs. removing budget ACs entirely) are
  DESIGN territory. The PRD commits to the contract per
  observation, not to the mechanism.
- Refactoring of any child skill, the parent-pattern
  reference, or the validator beyond what the observation set
  actually requires.

## Decisions and Trade-offs

**D1 — Symmetric strategic and tactical chain treatment.**
/vision, /strategy, /roadmap are included in Cluster 1
(sub-agent dispatch fallback) scope despite the v0.9.0
dogfooding round primarily exercising the tactical chain.
Alternative: tactical chain only (R1, omitting R2). Chosen
because `/charter` dispatches the strategic chain the same way
`/scope` dispatches the tactical chain; asymmetric treatment
would compound chain tax on the strategic side.

**D2 — Mechanism deferred to DESIGN per observation, with one
exception.** Per the BRIEF's Out-of-Scope item, the PRD names
contracts and DESIGN picks mechanisms. One exception: R1's
serial-self-jury contract under sub-agent dispatch is named
explicitly in the PRD because it's load-bearing — the
parallel-fan-out site recurs across seven child skills and the
PRD's own Phase 4 jury runs as serial-self-jury (the PRD is
itself dogfooding the contract). DESIGN picks placement
(parent-skill-pattern reference vs. per-skill jury phase
reference) but the contract is fixed.

**D3 — CLI version-skew preflight as skill-prose contract,
not validator extension.** Alternative: validator detects CLI
version-skew at validate time. Chosen because the version-skew
is a runtime condition the skill body addresses inline — the
validator runs against committed artifacts, after the skill
body has already prescribed the subcommand. R30 commits the
preflight contract; DESIGN picks the prose mechanism.

**D4 — Standalone bug intersection treated as one surface.**
`tsukumogami/shirabe#157` (schema silent-skip) and `#158`
(single-pr Implementation Issues drift) intersect this PRD's
requirements R18 and R17/R22. The intersection is named
explicitly in Out of Scope so future readers don't double-track
the work; the fix on the same surface satisfies the bug and
the PRD requirement together.

**D5 — Sub-agent serial-self-jury as the load-bearing
contract.** When a child's Phase-N jury runs under sub-agent
dispatch (parent is `/scope`/`/charter`/`/work-on` dispatching
the child via Skill tool inline per the Dispatch Contract),
the parallel-agent fan-out is NOT REQUIRED; serial-self-jury
with discipline preserving the independence property (each
role's criteria evaluated against the role's specific lens
without cross-contamination) SATISFIES the jury requirement.
This decision is the contract R1 and R2 commit to and is
named explicitly here because the BRIEF's
v0.9.0-dogfooding evidence depends on it.

## Known Limitations

- The PRD's own Phase 4 jury runs as serial-self-jury under
  sub-agent dispatch (the PRD is being authored by a child
  skill dispatched from `/scope`). The independence-loss
  caveat applies to the verdict files this PRD's Phase 4
  produces — a downstream reader should treat the PASS as
  serial-self-jury PASS, not parallel-jury PASS. This is the
  same caveat R1 prescribes for downstream chain juries.
- The CLI version-skew named in R30 was directly observed
  during this chain's authoring (the workspace shirabe
  installation is 0.6.1; the skill prose was authored
  against 0.9.x). The friction log captures the workaround
  (manual sed-edit). The PRD doesn't pre-commit to a
  preflight mechanism; the workaround is the documented
  fallback prose for now.
- The mechanical writing-style banned-word detection (R20)
  is itself a meta observation surfaced when authoring this
  chain. Phrases like "robust", "leverage", "comprehensive",
  "holistic", "facilitate", "tier", "tiered" recur in
  shirabe documents despite the writing-style reference
  banning them; DESIGN picks the surface that catches them
  mechanically.

## References

- `docs/briefs/BRIEF-shirabe-pattern-v1-ergonomics.md` —
  upstream BRIEF (Accepted 2026-06-06). Frames the six
  fix-surface clusters and named user journeys.
- Track A scope (this work) — the consolidated set of ~24
  inside-pattern observations, the 17-theme dogfooding comment,
  and the original inside-pattern ergonomics framing.
- Track B (amplifier-layer mandate refinement) — explicitly out
  of scope here, tracked separately as a forward-looking effort.
- `tsukumogami/shirabe#157` — validator schema silent-skip
  bug; intersects R18.
- `tsukumogami/shirabe#158` — `/plan` single-pr
  `## Implementation Issues` contract drift bug; intersects
  R17 and R22.

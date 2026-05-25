# Plan Analysis: DESIGN-shirabe-scope-skill

## Source Document

- Path: `docs/designs/DESIGN-shirabe-scope-skill.md`
- Status: Accepted
- Input Type: design
- Topic slug: `shirabe-scope-skill`
- Upstream PRD: `docs/prds/PRD-shirabe-scope-skill.md`
- Frontmatter fields present: status, upstream, problem, decision, rationale

## Scope Summary

`/scope` ships as the second parent skill in shirabe, binding the parent-skill pattern v1 (already ratified by `/charter`) to the tactical chain (`/brief → /prd → /design → /plan`) while extending the pattern doc with the new vocabulary three tactical-chain asymmetries force (a fourth gate shape; a sub-shape discriminator for two settled-upstream boundaries; an output-mode-aware terminal child). Delivery includes the `/scope` loadable skill body, three pattern-doc edits across three of the four pattern references, one new top-level worktree-discipline reference, and two child-side Phase-N Reject contract extensions on `/prd` and `/design`.

## Components Identified

The design enumerates **8 components** across three categories. The L9 traceability rule splits them into:

- **Pattern-doc-edit components** (covering 11 `[pattern-level]` requirements):
  - **Component 1** — `references/parent-skill-pattern.md` edits: NEW Gate Vocabulary section listing the four gate shapes (EITHER-signal / ALWAYS / shape-dependent / Mandatory-with-auto-skip); L13 amendment permitting a pattern-level `parent_orchestration:` state-file sentinel as the sole permitted parent-orchestration primitive. Estimated ~60-70 added lines.
  - **Component 2** — `references/parent-skill-state-schema.md` edits: two new conditional-field bullets (`boundary:` gated by `exit: re-evaluation`; `plan_execution_mode:` gated by `/plan` in `chain_ran`); Chain-tracking paragraph addition; R9 Part 2 sub-shape discriminator addition; R9 Part 3 chain-membership-gated I-5 addition. Estimated ~30-40 added lines.
  - **Component 3** — `references/parent-skill-resume-ladder-template.md` edits: single Slot 5 paragraph appended documenting refuse-and-redirect prompt shape (preserves 9-row meta-ladder count). Estimated ~10-12 added lines.
  - **Component 4** — NEW `references/parent-skill-worktree-discipline.md` top-level reference with five sections (Trigger Condition / Three-Option Prompt / Recording "Proceed Anyway" Divergence / Integration with Chain-Proposal Prompt / Binding Notes). Estimated ~80-100 added lines.

- **/scope-body components** (covering 15 `[/scope-specific]` requirements):
  - **Component 5** — `skills/scope/SKILL.md` (new loadable skill body): seven pattern-level structural elements with `/scope`-specific bindings — Input Modes (R2), execution-mode flag parsing (R16, R16.5 with `--max-rounds=5` default), topic-slug constraint citation (R3), Workflow Phases diagram (five phases), Resume Logic ladder (meta-ladder rows 1-4 + 8-9 plus 9-row Slot 5 fill + 4-row Slot 6 fill + vacuous Slot 7), Phase Execution list, Reference Files table. Plus prose sections for chain-proposal output (R7.5), three exit paths (R8), state file schema (R10), visibility detection (R12), manual-fallback non-interference (R13), validator pass-through, Phase-N Reject in-chain integration (R23). Estimated ~600-800 lines.
  - **Component 6** — `skills/scope/references/phases/phase-1-discovery.md`: R4/R5/R6 gate evaluation; structured checklist walk for R6 shape predicates (P1 architectural-alternatives count / P2 new-component references / P3 Complex classification) with 3-4 worked examples per predicate; chain-proposal output construction with literal `Proceed`/`Adjust`/`Bail` substrings; Mandatory-with-auto-skip evaluation for `/prd`.
  - **Component 7** — `skills/scope/references/phases/phase-2-chain-orchestration.md`: worktree-staleness check before each child invocation per R21; `parent_orchestration:` sentinel write; child invocation; structural file-existence check per R20; sentinel cleanup; child-snapshot capture per R10; Phase-N Reject handling via `git log` discard-commit observation; validator pass-through per Decision 10.

- **Child-side contract extensions**:
  - **Component 8** — Phase-N Reject contracts on `/prd` Phase 4 step 4.5 and `/design` Phase 6 step 6.7. Each existing 2-option AskUserQuestion (Approved / Needs iteration) becomes a 3-option gate (Approved / Reject / Continue-revising). Reject branch: ask for rationale, `git rm` the durable artifact, remove relevant `wip/` files, commit `docs(<type>): discard <TYPE> draft for <topic>` with rationale via `git commit -F -` (stdin) per Security Considerations mitigation, never `-m` (shell-injection avoidance). Per AC30c, fires identically in-chain and out-of-chain.

The two additional non-component pieces the implementation needs to ship:

- **Four Decision Record body templates** under `skills/scope/references/decision-record-{prd|design}-{re-evaluation|rejection}.md` (referenced by Interface I.2, ~50-80 lines each).
- **Eval suite** at `skills/scope/evals/evals.json` with eleven scenarios — six covering US-1 through US-6 per R18/AC24b, plus additional scenarios per the Phase 6 verdict (~5 more to cover Phase-N Reject in-chain and out-of-chain paths, abandonment-forced HTML-comment marker uniformity, drift-detection three-option prompt vocabulary, refuse-and-redirect literal substring contract, and slug re-validation on resume per the Security Considerations mitigation).
- **shirabe `CLAUDE.md`** edit: add "Tactical Chain Entry: /scope" section paralleling existing "Strategic Chain Entry: /charter".
- **Workspace `CLAUDE.md`** surfacing of `/scope` entry triggers per R17a / R17b.

## Implementation Phases (from design)

The Implementation Approach section enumerates four phases sequenced to minimize cross-phase dependencies. This sequencing directly maps to the 4-PR aggregation target.

### Phase A: Pattern-doc edits and new top-level reference

Ship Components 1, 2, 3, 4 in one PR. These edits stand alone — `/scope` consumes them but `/charter` and any future parent skills also consume them.

Deliverables:

- `references/parent-skill-pattern.md` — new Gate Vocabulary section + L13 amendment (Component 1).
- `references/parent-skill-state-schema.md` — two new conditional-field bullets + Chain-tracking paragraph + R9 Part 2 and Part 3 additions (Component 2).
- `references/parent-skill-resume-ladder-template.md` — single Slot 5 paragraph addition (Component 3).
- `references/parent-skill-worktree-discipline.md` — new reference file with five sections (Component 4).

### Phase B: Child-side contract extensions

Ship Component 8 in two PRs (one per child) BEFORE the `/scope` body lands.

Deliverables:

- `skills/prd/SKILL.md` + the relevant phase reference — 3-option gate per Component 8.1.
- `skills/design/SKILL.md` + the relevant phase reference — 3-option gate per Component 8.2.

### Phase C: /scope skill body + phase references + evals

Ship Components 5, 6, 7 plus the eval suite in one PR.

Deliverables:

- `skills/scope/SKILL.md` — Component 5.
- `skills/scope/references/phases/phase-0-setup.md` through `phase-4-cleanup.md` — Components 6 and 7 plus the other three phase references.
- `skills/scope/references/decision-record-{prd|design}-{re-evaluation|rejection}.md` — four Decision Record body templates.
- `skills/scope/evals/evals.json` — scenarios covering US-1 through US-6 plus Phase-N Reject in-chain/out-of-chain.
- Workspace + shirabe `CLAUDE.md` edits — `/scope` entry triggers and the "Tactical Chain Entry: /scope" section.

### Phase D: /charter back-edit (optional same-PR or follow-up)

Ship `/charter`'s reference-table additions and the `--parent-orchestrated` flag migration to the new `parent_orchestration:` sentinel.

Deliverables:

- `skills/charter/SKILL.md` — reference-table citations for the new worktree-discipline reference and Gate Vocabulary.
- `skills/charter/references/phases/phase-resume.md` — replaces existing `--parent-orchestrated` flag documentation with a pointer to the pattern-level `parent_orchestration:` sentinel.

### Sequencing rationale

Phase A first because Components 5-7 cite the pattern-doc edits. Phase B before Phase C because Component 7.7 references the child-side discard-commit observability that Component 8 ships. Phase C ships as one PR because its components are internally coupled. Phase D is optional same-PR-or-follow-up.

## Success Metrics

Lifted verbatim from the design's Consequences section.

### Positive consequences

- Pattern contract symmetry preserved across both parent skills. The three asymmetries the tactical chain exposes all land inside the pattern's existing extension points; no semantic invariant gets re-litigated.
- L9 traceability is mechanical. A reviewer can grep PRD for `[pattern-level]` and verify 11 matches against Components 1-4; grep for `[/scope-specific]` and verify 15 matches against Components 5-7. The 1:1 mapping is the design's reviewer-checkability surface.
- `/charter`'s `--parent-orchestrated` exception is rationalized. The L13 amendment formalizes what `/charter` was doing informally; the pattern doc stops carrying an undocumented L13 exception.
- Worktree-discipline becomes shared infrastructure. `/work-on` (SE8) inherits the discipline without re-deriving it.
- Eval surface is grep-checkable. R7.5's chain-proposal output, R8's exit-path enums, R15's Decision Record literals, R7's `plan_execution_mode:` field, and Decision 6's resume-ladder vocabulary contract all contain literal substrings the eval scenarios match.

### Negative consequences (and mitigations from the design)

- Pattern doc grows three new sections plus one amendment in one PR. Mitigated by surgical placement: each edit's exact location (file + line range) named in Components 1-4; Decision 8's "Why NOT" sub-sections surface alternative placements explicitly so reviewers can challenge them.
- Four shirabe children eventually need per-child PRs to adopt the `parent_orchestration:` sentinel. Worst case before adoption is the status quo; mitigation is per-child small mergeable PRs (deferred to SE7+1 follow-ons).
- Worktree-staleness check adds `git fetch` overhead four times per full-run chain. Bounded operational cost.
- R6 shape-predicate walk depends on agent judgment for P1 and P2. Mitigated by worked examples in `phase-1-discovery.md`.
- Phase-N Reject contract extensions are substantial work for two child skills. Mitigated by adding eval scenarios for Approve / Reject / Continue-revising in each child's PR; in-chain and out-of-chain Reject behaviors covered separately per AC30c.
- State file is branch-coupled in v1. Per PRD Known Limitations, resume across branches not supported; flagged for amplifier-layer migration's mandate (closing I-6).

### Security mitigations carried into implementation

- **Slug re-validation on resume**: any slug recovered from on-disk artifact paths SHALL be re-validated against `^[a-z0-9-]+$` BEFORE entering interpolation into shell commands; unparseable slugs route to R8 bail-handling.
- **Git-commit rationale via stdin**: rejection rationale strings SHALL be passed via `git commit -F -` (stdin), never inlined into `-m "..."`. Same discipline for "proceed anyway" rationale on worktree-staleness divergence.
- **Closed write-target set**: implementations of Components 5, 6, 7 SHALL confine filesystem writes to the enumerated set in the Security Considerations section; writes outside this set fail R9 hard-finalization check.
- **State-file enum re-validation**: `triggering_child:` / `boundary:` / `decision_record_sub_shape:` / `plan_execution_mode:` SHALL be validated against their declared enums on read BEFORE shell-command interpolation.
- **Phase 0 stale-sentinel self-heal**: any `parent_orchestration:` block found at session start SHALL be cleared unconditionally — no prompt, no warning (the self-heal IS the contract).
- **Rationale-field public-history disclaimer**: Phase-N Reject prompt SHALL include the literal substring "Rationale will be committed to git history".

## External Dependencies

- **DESIGN-shirabe-progression-authoring** (under `docs/designs/current/`): the parent-skill pattern v1 — Layer 1 semantic invariants I-1 through I-7 and Layer 2 substrate identifiers (`wip-yaml-md`, `single-team-per-leader-no-nested`). `/scope` inherits both layers without alteration.
- **`/charter` SKILL.md and `phase-resume.md`**: source of the back-edit in Phase D (reference-table citation; `--parent-orchestrated` flag migration to pattern-level sentinel).
- **`/prd` SKILL.md and Phase 4 reference**: target of Component 8.1 child-side contract extension.
- **`/design` SKILL.md and Phase 6 reference**: target of Component 8.2 child-side contract extension.
- **`/brief` and `/plan` SKILL.md**: no contract changes in SE7 (Phase-N Reject already exists on `/plan` Phase 6.7; `/brief` has no analogous gate but is auto-skipped on Accepted via Slot 5.8). Future per-child sentinel-recognition PRs are out of scope for SE7 — flagged as follow-on.
- **`shirabe validate` binary**: invoked per Phase 2 validator pass-through (Decision 10). No source change needed (existing binary).
- **`skills/private-content` / `skills/public-content` SKILL.md**: visibility-detection branching consumed by Phase 0; the design binds `/scope` v1 to public repos exclusively (Mitigation 1 in Security Considerations).
- **GitHub CLI (`gh`)**: Phase 7 of `/plan` itself uses it; not consumed by `/scope` directly.

## Component-to-PR Aggregation (input to Phase 3 decomposition)

Per team-lead's decomposition plan, the 8 components plus the auxiliary deliverables map onto 4 PRs:

- **PR-1**: Component 4 (new `parent-skill-worktree-discipline.md`) + `/charter` SKILL.md cite-back-edit. Standalone — `/charter` immediately benefits.
- **PR-2**: Component 8.1 (`/prd` Phase 4 3-option Reject contract) + commit-via-stdin discipline + 1 eval scenario. Standalone for `/prd` direct invokers.
- **PR-3**: Component 8.2 (`/design` Phase 6 3-option Reject contract) + parallel discipline + 1 eval scenario. Standalone for `/design` direct invokers.
- **PR-4**: Components 1 + 2 + 3 (three pattern-doc edits) + Components 5 + 6 + 7 (`/scope` body + phase references) + 4 Decision Record templates + 11-scenario eval suite + shirabe `CLAUDE.md` tactical-chain entry section + DESIGN status flip to Planned (Phase 7 effect of this /plan).

Note that this differs from the design's Phase A/B/C/D sequencing in one respect: the pattern-doc edits (design's Phase A Components 1-3) are folded into PR-4 alongside the `/scope` body rather than shipped in their own PR. Rationale: Components 1, 2, 3 are surgical edits (~100 lines total) that exclusively serve `/scope`'s body — shipping them in a standalone PR would force a `/scope`-body-pending merge gap where the pattern doc grows new vocabulary no skill cites. Component 4 (the new top-level reference, ~80-100 lines) is genuinely standalone — `/charter` cites it back-edited — and ships as PR-1.

The PR-4 boundary respects the design's "Phase C ships as one PR because its components are internally coupled" rule and extends it to include Phases A's pattern-doc edits (Components 1-3) since they're the same coupled artifact set in practice.

PR-5 (vision-repo roadmap text update + SE7 mark Done) is a downstream follow-on in the vision repo; out of scope for this /plan but noted in Implementation Sequence.

## Quality Checklist

- [x] Source document status is "Accepted"
- [x] Full source document read (2163 lines)
- [x] `input_type` field recorded (`design`)
- [x] Components enumerated with boundaries
- [x] Implementation Approach phases recorded verbatim
- [x] Success metrics and mitigations recorded
- [x] External dependencies named
- [x] PR-aggregation target captured as input to Phase 3

## Next Phase

Proceed to Phase 2: Milestone derivation (`phase-2-milestone.md`).

# Plan Analysis: shirabe-charter-skill

## Source Document

Path: `/home/dgazineu/dev/niwaw/tsuku/tsuku-3/.niwa/worktrees/shirabe-db61668b/docs/designs/DESIGN-shirabe-progression-authoring.md`
Status: Accepted
Input Type: design

Secondary context (parent-specific bindings; status is In Progress and intentionally not a status-validation target):
`/home/dgazineu/dev/niwaw/tsuku/tsuku-3/.niwa/worktrees/shirabe-db61668b/docs/prds/PRD-shirabe-charter-skill.md`

## Scope Summary

Ship `/charter` as the first parent skill against the parent-skill pattern committed in DESIGN-shirabe-progression-authoring. The plan delivers the four new pattern-level reference files at top-level `references/`, the `/charter` SKILL.md template, `/charter` phase prose under `skills/charter/references/phases/`, `skills/charter/evals/evals.json` (canonical shared-baseline source), and CLAUDE.md surfacing in both the shirabe repo and the workspace fragment that lists shipped skills. The design is shared across `/charter`, `/scope`, and the future `/work-on` migration; this plan covers `/charter` only — the first parent — and inherits pattern-level commitments verbatim while adding the PRD's `[/charter-specific]` bindings on top.

## Components Identified

Components are listed at the granularity Phase 3 needs to decide combinations. Pattern-level deliverables (shared with future parents) are listed first; `/charter`-specific bindings follow.

### Pattern-level reference files (Design Component 1, Decision 1 + Decision 7)

- **C1 — `references/parent-skill-pattern.md`**: Contract surface document. Sections: Two-Layer Contract Overview; Semantic Invariants (I-1 through I-6); Three Exit Paths; Conditional Feeder Invocation Shape (Decision 6); Named Substitution Surfaces (`storage_substrate`, `team_primitive`); Team-Shape Declarator Mechanism. Flat file at top-level `references/` per Decision 7.

- **C2 — `references/parent-skill-state-schema.md`**: 5-field minimum state-file vocabulary (`topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`) plus extension discipline. Sections: Minimum Required Fields; Field Semantics; Pattern-Level Invariants (per-child snapshot dual-check, conditional-field gating, chain-tracking, status-aware re-entry); Extension Discipline; R9 Hard-Finalization Check Spec.

- **C3 — `references/parent-skill-resume-ladder-template.md`**: Universal meta-ladder plus parent-specific body slots. Sections: Meta-Ladder Entries (1-4 and 8-9); Parent-Specific Body Slots (5-7) and Rules for Filling Them; Malformed State File Handling; Stale-Session Threshold Reference.

- **C4 — `references/parent-skill-child-inspection.md`**: R14 widened isolation rule plus per-parent surface table. Sections: The Isolation Rule; Per-Parent Surface Table (doc-emitting children use frontmatter status + git blob hash; issue/PR children use issue/PR state + labels + CI rollup); Drift Detection Semantics; What Counts as "Internals" (negative examples).

### Pattern-level template / mechanism deliverables (Design Components 2-5)

- **C5 — Parent-skill SKILL.md template structure documented in C1 (Design Component 2)**: Names the seven required structural elements (Input Modes; execution-mode flag parsing; topic-slug constraint citation; Workflow Phases diagram; Resume Logic ladder; Phase Execution list; Reference Files table). Lives inside the pattern reference file (likely in `parent-skill-pattern.md`); listed separately because its presence is what makes `/charter`'s SKILL.md verifiable against PRD AC1b.

- **C6 — Two-layer contract surface body content (Design Component 3)**: The substantive prose for Layer 1 invariants I-1 through I-6 (with I-6 acknowledged unsatisfied in v1) and Layer 2 reference implementation (the YAML-with-`.md`-extension serialization at `wip/<parent>_<topic>_state.md`). Lives inside C1 (`parent-skill-pattern.md`); listed separately because invariant authoring is the load-bearing content commitment.

- **C7 — Resume-ladder template body content (Design Component 4)**: Substantive prose for universal entries 1-4 and 8-9, plus the rules for filling body slots 5-7. Lives inside C3 (`parent-skill-resume-ladder-template.md`).

- **C8 — Team-shape declarator mechanism (Design Component 5, Decision 8)**: Mechanism documentation for how a parent's SKILL.md declares fixed roles and variable-cardinality role types with upper bounds. v1 form is prose; v2 amplifier-layer form is structured metadata. The declarator content lives inside C1 (`parent-skill-pattern.md`); listed separately because Decision 8 frames it as a contract surface that survives substrate substitution, and it is the contract `/scope` and `/work-on` materialize against.

### /charter-specific deliverables (Design Stage 2)

- **C9 — `skills/charter/SKILL.md`**: The loadable slash command. Includes the seven structural elements per C5, cites the four pattern-level references (C1-C4), and lays in `/charter`-specific extensions (Team Shape prose: `/charter` is a no-team parent; chain-proposal output prose per R7.5; Input Modes section per R2; execution-mode flag parsing). Frontmatter declares `name: charter`. Verifies AC1, AC1b.

- **C10 — Topic-slug rejection and Phase 0 wiring (R3, R2)**: `/charter` accepts empty `$ARGUMENTS` (cold start ask) and a freeform topic string (`/charter <topic-slug>`); rejects paths to durable artifacts. Slug regex `^[a-z0-9-]+$` is hard-rejected at Phase 0. Verifies AC2, AC3, AC3b, AC4. May fold into C9 (SKILL.md prose) or split as a phase-0 reference file.

- **C11 — Phase 1 discovery prose + thesis-shift signal detection (R4)**: `/charter` Phase 1 includes a discovery prompt with the literal thesis-shift question and treats the three named utterance categories as positive signals. `/vision` invocation fires when either no Accepted/Active VISION exists OR the thesis-shift signal surfaces. Verifies AC5, AC6.

- **C12 — `/comp` conditional invocation with degenerate-silence rule (R5, R12)**: `/charter` invokes `/comp` only when (1) repo visibility is Private per CLAUDE.md `## Repo Visibility:` header AND (2) `skills/comp/SKILL.md` exists on disk. Public-repo invocations produce no `/comp`-related substring in Phase 1 discovery or chain proposal output (byte-identical between Private-without-`/comp` and Public). Verifies AC7, AC8.

- **C13 — `/strategy` invocation logic with three upstream shapes (R6)**: `/charter` always invokes `/strategy`. Passes one of: freeform topic string, VISION path (`/strategy` Input Mode 3), or PRD path. Never passes a STRATEGY path. Verifies AC10b, AC10c.

- **C14 — `/roadmap` conditional + handoff pre-population (R7)**: `/charter` invokes `/roadmap` when STRATEGY's Building Blocks count is 3+ AND a Coordination Dependencies section has at least one entry referencing another Building Block by name. Invocation passes `--upstream <strategy-path>` AND a pre-populated `wip/roadmap_<topic>_scope.md` matching `/roadmap` Phase 1's expected schema. Verifies AC9, AC10, AC11a, AC11b.

- **C15 — Chain-proposal confirmation prompt (R7.5)**: Phase 1 concludes with the canonical "chain proposal output" prompt containing the literal substrings "Proceed", "Adjust", "Bail" (case-insensitive). Lists planned children in order; skips those determined by R4/R5/R7 not to fire. "Adjust" routes back to Phase 1 discovery; "Bail" routes per R8 tie-break. Verifies AC10d, AC10e, AC10f.

- **C16 — Three exit paths + tie-break (R8)**: Implementation of full-run, re-evaluation (with re-evaluation and rejection sub-shapes), and abandonment-forced exits, including the "most-recently-running" tie-break (last entry in `chain_ran`; or first entry in `planned_chain` with a non-empty wip/ intermediate; else clean-cancel). Verifies AC11a, AC11b, AC12, AC12b, AC12c, AC13, AC14, AC14b.

- **C17 — State-file schema (`wip/charter_<topic>_state.md`) (R10)**: The full YAML schema with `.md` extension: `topic`, `chain_started`, `chain_completed`, `last_updated`, `planned_chain`, `chain_ran`, `chain_skipped`, `exit`, `decision_record_sub_shape`, `exit_artifacts`, `child_snapshots` (per-child path + status + git-blob-hash), `referenced_strategy`, `discard_commit_sha`, `rejection_rationale`, `triggering_child`, `partial_phase_reached`. The 5-field minimum (C2) plus `/charter`-specific extensions. Verifies AC11a-AC15, AC19.

- **C18 — Resume ladder implementation (R11)**: The 10-row ladder ordering with first-match-wins (state file malformed → exit set → fresh resume → stale-session → STRATEGY Accepted/Active → STRATEGY Draft → `wip/strategy_<topic>_discover.md` → `wip/vision_<topic>_scope.md` → on-topic branch → on main). Reads `_discover.md` not `_scope.md` per known asymmetry. Suppresses child status-aware re-entry hijack. Surfaces malformed state as hard error with Discard recovery. Verifies AC16, AC17, AC18, AC18b, AC20, AC20c, AC26d.

- **C19 — Hard finalization check (R9)**: At chain finalization, verify `exit:` is set to one of `{full-run, re-evaluation, abandonment-forced}`; when `exit: re-evaluation`, verify `decision_record_sub_shape:` is one of `{re-evaluation, rejection}`; verify conditional fields are absent (not null/empty/placeholder) when their triggering condition does not hold. Verifies AC15.

- **C20 — Visibility detection + manual-fallback (R12, R13)**: `## Repo Visibility:` header detection in CLAUDE.md; default-Private with warning ("Default to Private if unknown — restricting is easier to undo than oversharing"). Manual-fallback first-class: `/charter` does not warn, block, or interfere when an author invokes a child directly outside `/charter`. Verifies AC21, AC22, AC23.

- **C21 — Child-snapshot dual-check drift detection (R10, R11, R13)**: For each child in `planned_chain`, snapshot stores path + frontmatter `status:` + git blob hash; resume ladder compares both live values; drift fires when EITHER differs. Surfaces three-option staleness prompt (re-run downstream / accept as still-valid / proceed without). Verifies AC19, AC20b, AC23.

- **C22 — Child-internals isolation (R14, widened per Design Decision 4)**: `/charter`'s decision logic depends only on (a) child doc frontmatter, (b) topic slug, (c) `/charter`'s own state file. Never reads child `wip/research/<child>_*.md`. Pattern-level reference C4 provides the contract; `/charter` provides the doc-emitting binding. Verifies AC20b.

- **C23 — Schema validation: STRATEGY artifacts (R15)**: Draft STRATEGY produced via `/charter`'s `/strategy` delegation passes `shirabe validate --visibility=<repo-visibility>`. Public-repo STRATEGY must not contain Competitive Considerations sections. Verifies AC24.

- **C24 — Schema validation: Decision Record artifacts (R15)**: Both Decision-Record sub-shapes (re-evaluation and rejection) at `docs/decisions/DECISION-strategy-<topic>-<sub-shape>-<YYYY-MM-DD>.md` follow ADR-style body (Status, Context, Decision, Options Considered, Consequences) with frontmatter (`status` ∈ {Draft, Accepted}, `decision`, `rationale`). Per-sub-shape body content rules: re-evaluation cites named evidence; rejection cites discard commit SHA; both Options-Considered sections name specific rejected alternatives. Verifies AC25 (plus AC12 and AC13 body content).

- **C25 — Schema validation: abandonment-forced artifacts (R15)**: Force-materialized artifacts pass the same schema validators as full-run artifacts. The abandonment-forced metadata lives in an HTML-comment marker (`<!-- charter-status-block: abandonment-forced; ... -->`) inside the artifact's existing Status section, not in a new required section. Verifies AC26.

- **C26 — 7-day stale-session threshold (R16)**: Boundary fires at `≥` 7 days from `last_updated`. Fixed in v1; not configurable. Used by C18 (resume ladder rows 3-4) and C16 (abandonment-forced trigger condition). Verifies AC16, AC17.

- **C27 — `/charter` phase prose under `skills/charter/references/phases/` (Design Stage 2)**: Per-phase reference files for `/charter`'s phases (Phase 0 setup, Phase 1 discovery, Phase 2 chain orchestration, Phase N finalization). Referenced from C9 (SKILL.md) via the Reference Files table.

- **C28 — `skills/charter/evals/evals.json` (R18, Design Stage 2)**: Eval scenarios covering US-1, US-2, US-3a, US-3b, US-4 (R18 charter-specific scenarios), PLUS the shared eval baseline (slug rejection, malformed state file, child-internals isolation, visibility default) — `/charter`'s eval file IS the canonical source for the baseline that `/scope` and `/work-on` will copy-and-adapt. All scenarios must pass under `scripts/run-evals.sh charter`. Verifies AC26c.

- **C29 — CLAUDE.md surfacing: shirabe (R17a, R17b, Design Stage 3)**: `shirabe/CLAUDE.md` mentions `/charter` and includes the trigger phrases from R17b: "start a strategic conversation about X", "open a charter for Y", "I need to think through the bet on Z", and direct `/charter <topic>` invocation. Verifies AC26b (shirabe-side).

- **C30 — CLAUDE.md surfacing: workspace fragment (R17a, Design Stage 3)**: Workspace-level CLAUDE.md fragment listing shipped shirabe skills is updated to add `/charter` alongside `/strategy`, `/explore`, `/decision`, etc. (workspace CLAUDE.md is composed from per-repo fragments; the shirabe fragment updates its own listing). Verifies AC26b (workspace-side).

### Phase 3 ambiguity flags

- C5, C6, C7, C8 are listed as separate components even though they live inside C1, C2, C3. Phase 3 may combine each into its parent reference file; they are split here because each is independently verifiable content with distinct authoring/sourcing decisions (template structure vs invariant prose vs ladder body slots vs declarator mechanism).
- C10 (slug + Phase 0 wiring) may collapse into C9 (SKILL.md) once Phase 3 decides whether a separate `skills/charter/references/phases/phase-0-setup.md` file is warranted versus inline SKILL.md prose.
- C19 (hard finalization check) and C16 (three exit paths) overlap at the boundary: Phase 3 should decide whether finalization-check logic is one component or splits across exit-path implementations.
- C29 and C30 may combine if the same PR updates both files; split here because they target different repos (shirabe versus workspace) per the design Stage 3 deliverables.

## Implementation Phases (from design)

Verbatim copy of the design's Implementation Approach section:

> The design ships as a documentation-only initiative — four new
> reference files and the parent-skill SKILL.md template content
> that `/charter` (the first concrete consumer) authors against.
> There is no code component. The implementation is staged so
> `/charter` can ship without waiting on `/scope` or `/work-on`
> authoring; the pattern-level references are written first and
> `/charter` cites them.
>
> ### Stage 1 — Pattern-level reference files
>
> Author the four new reference files at top-level `references/`,
> each cites the relevant Considered Options block of this design as
> its "why this shape" rationale plus the PRD requirements it
> implements.
>
> Deliverables and section skeleton per file:
>
> - **`references/parent-skill-pattern.md`** — contract surface
>   document. Sections: Two-Layer Contract Overview; Semantic
>   Invariants (I-1 through I-6); Three Exit Paths (full-run,
>   re-evaluation, abandonment-forced); Conditional Feeder
>   Invocation Shape (per Decision 6); Named Substitution Surfaces
>   (`storage_substrate`, `team_primitive`); Team-Shape Declarator
>   Mechanism.
> - **`references/parent-skill-state-schema.md`** — 5-field minimum
>   state-file vocabulary plus extension discipline. Sections:
>   Minimum Required Fields (`topic`, `last_updated`,
>   `phase_pointer`, `exit`, `exit_artifacts`); Field Semantics;
>   Pattern-Level Invariants (per-child snapshot dual-check,
>   conditional-field gating, chain-tracking, status-aware re-entry);
>   Extension Discipline (rules for parent-specific additions);
>   R9 Hard-Finalization Check Spec.
> - **`references/parent-skill-resume-ladder-template.md`** — universal
>   meta-ladder plus parent-specific body slots. Sections: Meta-Ladder
>   Entries (1-4 and 8-9); Parent-Specific Body Slots (5-7) and Rules
>   for Filling Them; Malformed State File Handling; Stale-Session
>   Threshold Reference.
> - **`references/parent-skill-child-inspection.md`** — R14 isolation
>   rule plus per-parent surface table. Sections: The Isolation
>   Rule; Per-Parent Surface Table (doc-emitting children;
>   issue/PR children); Drift Detection Semantics; What Counts as
>   "Internals" (negative examples).
>
> ### Stage 2 — `/charter` SKILL.md authoring against the pattern
>
> `/charter` (the first parent-skill consumer) authors its SKILL.md
> against the references from Stage 1. The `/charter` PRD's
> `[/charter-specific]` requirements become `/charter`'s
> parent-specific extensions; the `[pattern-level]` requirements
> resolve via citation to the shared references.
>
> Deliverables:
> - `skills/charter/SKILL.md` with seven structural elements,
>   including the Reference Files table citing the four pattern-level
>   references.
> - `skills/charter/references/phases/*.md` for `/charter`'s
>   parent-specific phase prose.
> - `skills/charter/evals/evals.json` with the shared eval baseline
>   (slug rejection, malformed state file, child-internals isolation,
>   visibility default) copy-and-adapted plus `/charter`-specific
>   scenarios (US-1 through US-4). **Canonical-source note:**
>   `/charter`'s `evals.json` IS the canonical source for the
>   shared baseline; `/scope` and `/work-on` copy-and-adapt from
>   it when they land. Updates to the baseline ripple to all
>   downstream parents' eval files via per-PR manual update until a
>   future eval-format `$ref` mechanism mechanically retrofits.
>
> ### Stage 3 — CLAUDE.md surfacing
>
> Per R17a/R17b, ship CLAUDE.md updates for workspace and shirabe
> that surface `/charter`'s entry triggers. The pattern-level
> contribution is the surfacing discipline itself; the
> parent-specific contribution is `/charter`'s trigger-phrase list.
>
> Deliverables:
> - `shirabe/CLAUDE.md` (in this repository's root) mentions
>   `/charter` and includes the trigger phrases from PRD R17b.
> - The workspace-level CLAUDE.md fragment that lists shipped
>   shirabe skills is updated to add `/charter` alongside
>   `/strategy`, `/explore`, `/decision`, and the other shipped
>   skills. The workspace's CLAUDE.md is composed from per-repo
>   fragments; each repo updates its own fragment, and the
>   workspace tooling assembles the composite. Future parent-skill
>   authors update both their own repo's CLAUDE.md and any
>   workspace fragment that lists shipped skills.
>
> ### Stage 4 — `/scope` and `/work-on` (out of scope for this design's
> shipping)
>
> When `/scope` and `/work-on` are bounded (separate PRDs), their
> authors follow the same pattern:
>
> - Cite the four pattern-level references.
> - Author parent-specific phase prose under
>   `skills/<name>/references/phases/`.
> - Copy-and-adapt the shared eval baseline from `/charter`'s
>   canonical evals; add parent-specific scenarios.
> - Bind the per-parent R14 surface (e.g., `/work-on` binds to
>   issue/PR state + labels + CI check rollup).
> - Update workspace and shirabe CLAUDE.md with their trigger
>   phrases.
>
> Out of scope for this design's shipping; named here as the test of
> whether the pattern actually convenes the three parents.
>
> ### Note on amplifier-layer implementation timing
>
> The amplifier-layer implementation (alternative value of
> `storage_substrate` and/or `team_primitive`) is intentionally NOT
> on the critical path for this design's shipping. The two-layer
> contract surface makes the amplifier layer a future substitution
> within the same pattern, not a different pattern.

## Success Metrics

### From design's Consequences > Positive

- **Pattern reuse across three parents at low marginal cost.** Each parent's SKILL.md cites the four pattern-level references and fills the parent-specific extensions; new parents inherit the contract without re-deriving it.
- **Verifiable v1 commitments.** PRD R10's full schema and PRD R11's resume ladder map directly into the reference implementation, so `/charter`'s acceptance criteria stay testable today via `shirabe validate` and skill evals.
- **Amplifier-layer is a substitution, not a redesign.** The two-layer contract names the substitution variables (`storage_substrate`, `team_primitive`) explicitly; when the amplifier-layer substrate is bounded, it slots into the same pattern without changing the contract.
- **Honest framing of current Claude Code limitations.** The `team_primitive` substitution variable's v1 value (`single-team-per-leader-no-nested`) is documented as an architectural property with three operational consequences, not as a transient bug.
- **Cross-branch is a forcing function, not an excuse.** Naming cross-branch as invariant I-6 (acknowledged unsatisfied) ties the amplifier layer's mandate to a specific gap; the v1 contract doesn't pretend the gap doesn't exist.
- **`/work-on` can participate in the pattern.** The R14 widening to "durable externally-visible status surface" with per-parent bindings makes the pattern accommodate non-doc-emitting children without forcing carve-outs.

### Acceptance Criteria mapping to components

Each `/charter` PRD acceptance criterion is binary pass/fail and bound to one or more requirements. The mapping below ties each AC to the component(s) Phase 3 must ensure cover it; Phase 4 decomposers should use this to verify nothing is orphaned.

| AC | Verification | Requirements | Component(s) |
|----|--------------|--------------|-------------|
| AC1 | automated-unit | R1 | C9 |
| AC1b | automated-unit | R1 | C5, C9 |
| AC2 | automated-eval | R2 (US-1) | C9, C10 |
| AC3 | automated-eval | R3 | C10 |
| AC3b | automated-eval | R3 | C10 |
| AC4 | automated-eval | R2 | C10 |
| AC5 | automated-eval | R4 (US-1) | C11 |
| AC6 | automated-eval | R4 | C11 |
| AC7 | automated-eval | R5, R12 | C12, C20 |
| AC8 | automated-eval | R5 | C12 |
| AC9 | automated-eval | R7 (US-1) | C14 |
| AC10 | automated-eval | R7 (US-1) | C14 |
| AC10b | automated-eval | R6 | C13 |
| AC10c | manual-review | R6 | C13 |
| AC10d | automated-eval | R7.5 (US-1) | C15 |
| AC10e | automated-eval | R7.5 | C15 |
| AC10f | automated-eval | R7.5, R8 | C15, C16 |
| AC11a | automated-eval | R8, R10 (US-1) | C16, C17 |
| AC11b | automated-eval | R8, R10 (US-1) | C16, C17 |
| AC12 | automated-eval | R8, R10, R15 (US-2) | C16, C17, C24 |
| AC12b | automated-eval | R8 (US-2) | C16 |
| AC12c | automated-eval | R8 (US-2) | C16 |
| AC13 | automated-eval | R8, R10, R15 (US-3a) | C16, C17, C24 |
| AC14 | automated-eval | R8, R10, R15 (US-3b) | C16, C17, C25 |
| AC14b | automated-eval | R8 (US-3b) | C16 |
| AC15 | automated-eval | R9 | C19 |
| AC16 | automated-eval | R10, R11 | C18, C26 |
| AC17 | automated-eval | R11, R16 (US-3b) | C18, C26 |
| AC18 | automated-eval | R11 (US-2 wording) | C18 |
| AC18b | automated-eval | R13 (US-3a) | C18, C20 |
| AC19 | automated-eval | R10, R11, R13 (US-4) | C18, C21 |
| AC20 | automated-eval | R11 | C18 |
| AC20b | manual-review | R14 | C22 |
| AC20c | automated-eval | R11 | C18 |
| AC21 | automated-eval | R12 | C20 |
| AC22 | manual-review | R13 (US-4) | C20 |
| AC23 | automated-eval | R13 (US-4) | C20, C21 |
| AC24 | automated-unit | R15 | C23 |
| AC25 | automated-unit | R15 | C24 |
| AC26 | automated-unit | R15 | C25 |
| AC26b | automated-unit | R17a, R17b | C29, C30 |
| AC26c | automated-eval | R18 | C28 |
| AC26d | automated-eval | R11 | C18 |

## External Dependencies

- **Shipped shirabe child skills (read-only consumers)**: `/charter` invokes `/strategy` (always; R6), `/vision` (conditional on R4 signals), `/roadmap` (conditional on R7 STRATEGY shape gates). Plan must NOT modify these skills. The known `/strategy` asymmetry (SKILL.md documents `_scope.md`, phase files write `_discover.md`) is accommodated by `/charter` reading `_discover.md` per R11; correcting `/strategy` is out of scope (PRD Out-of-Scope item).
- **Shipped `/explore` skill — discover/converge engine**: `/charter` Phase 1 discovery uses the engine that currently lives at `skills/explore/references/phases/{phase-2-discover.md, phase-3-converge.md}`. Per Design Decision 1, the engine stays in place; `/charter` either points cross-skill or ships its own Phase 1 discovery prose variant matching every shipped shirabe skill today.
- **Shipped `/decision` skill (NOT invoked by `/charter` at runtime)**: `/charter` writes Decision Records inline per PRD Decision 6; it does NOT delegate to `/decision`. Listed as a dependency only for naming consistency — Decision Record artifact shape (Status, Context, Decision, Options Considered, Consequences) is precedent shirabe already uses.
- **`/comp` skill (NOT yet shipped; conditional integration)**: `/charter` ships with `/comp` invocation logic gated behind a skill-existence check on `skills/comp/SKILL.md` (R5). When `/comp` is absent, `/charter` silently skips — the chain proposal output is byte-identical between public-repo and private-repo-without-`/comp` invocations (AC8). No `/charter`-side change needed when `/comp` lands.
- **`shirabe validate` tool**: R15 invokes `shirabe validate --visibility=<repo-visibility>` against Draft STRATEGY produced via `/charter`'s `/strategy` delegation; against both Decision-Record sub-shapes; and against force-materialized artifacts. Verifies AC24, AC25, AC26.
- **`scripts/run-evals.sh`**: R18 invokes `scripts/run-evals.sh charter` to execute eval scenarios in `skills/charter/evals/evals.json`. Verifies AC26c.
- **CLAUDE.md `## Repo Visibility:` header pattern**: R12 inherits the visibility-detection pattern from shipped `/strategy` and `/explore`. The default-Private warning text ("Default to Private if unknown — restricting is easier to undo than oversharing") is the shipped phrasing. Verifies AC21.
- **Workspace CLAUDE.md composition**: Per Stage 3, the workspace-level CLAUDE.md is composed from per-repo fragments. The shirabe fragment's "shipped skills" listing is the surface to update; workspace tooling assembles the composite. Verifies AC26b (workspace-side).
- **`wip-hygiene.md` rule (workspace CLAUDE.md)**: The design's `wip/...` path references throughout its prose are contract specifications for the v1 `wip-yaml-md` storage substrate (per Design Component 3's explicit note), NOT orphan staging pointers. They do not violate wip-hygiene. The plan inherits this framing: `/charter`'s state-file path `wip/charter_<topic>_state.md` is a contract surface specified by R10 and C17, durable evidence by design.
- **Git read-only operations**: `/charter` reads git in three places (R10, R11, R15): (a) child doc fingerprinting via git blob hash for drift detection; (b) discard commit SHA capture via `git log` for the rejection sub-shape; (c) resume-ladder branch test (rows 8-9) inspecting the current branch name. No git writes are issued on the user's behalf except `/strategy`'s discard commit, which is `/strategy`'s responsibility, not `/charter`'s.

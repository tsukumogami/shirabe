---
design_doc: docs/designs/DESIGN-shirabe-progression-authoring.md
input_type: design
decomposition_strategy: horizontal
strategy_rationale: "Design is documentation-only with explicitly staged deliverables (Stage 1 references, Stage 2 SKILL.md + phase prose + evals, Stage 3 CLAUDE.md surfacing); no runtime integration risk to surface via a walking skeleton; foundations build on each other layer-by-layer."
confirmed_by_user: false
issue_count: 10
execution_mode: multi-pr
execution_mode_rationale: "Forced by SE4 directives: design spans repo boundaries (shirabe + future /scope/work-on consumers), and Stage 1 → Stage 2 → Stage 3 implies merge gates between phases (later stages cite the earlier-merged references)."
---

# Plan Decomposition: shirabe-charter-skill

## Strategy: Horizontal

The design is a documentation-only initiative with three sequenced stages (per its own Implementation Approach):

- **Stage 1**: four pattern-level reference files under top-level `references/`.
- **Stage 2**: `/charter` SKILL.md + phase prose + evals under `skills/charter/`.
- **Stage 3**: CLAUDE.md surfacing for `/charter`'s entry triggers (shirabe-side + workspace fragment).

Walking skeleton was rejected because there is no runtime end-to-end path to exercise — the deliverables are reference docs, slash-command prose, and CLAUDE.md additions. The natural layering is dependency-ordered: foundations (Stage 1 refs) → consumer (Stage 2 `/charter`) → surfacing (Stage 3). Each subsequent issue cites the previously-landed ones. Horizontal decomposition matches the design's own implementation discipline.

Issues are organized by deliverable cluster within `/charter`'s implementation (Stage 2). State-file schema and resume-ladder logic are split out as standalone issues because each is critical-complexity (state schema is the contract enforcement spine; resume ladder is the most-complex single behavior in the skill). Decision Record authoring is split from exit-path orchestration logic because the two answer different questions: "when does each exit fire?" (logic) versus "what files get written?" (artifact format).

## Component-to-Issue Mapping

The Phase 1 analyzer identified 30 components with explicit Phase 3 combination flags. Compressions applied:

- **C1-C8 → Issue 1** (one PR per Stage 1 deliverable cluster; the four reference files cross-cite each other and review value is highest as a coherent set).
- **C9, C10 → Issue 2** (SKILL.md + Phase 0 wiring inline; no separate phase-0 reference file warranted).
- **C11 split**, **C20 → Issue 3** (Phase 1 discovery prose + visibility detection + manual-fallback rule are the entry-router prelude before child invocation).
- **C11 vision-invocation half, C12, C13, C14, C15 → Issue 4** (all four child-invocation decisions + chain-proposal prompt — invocation logic plus its consolidated user-facing prompt).
- **C17, C19 → Issue 5** (state file schema + hard finalization check — finalization check is the contract enforcement mechanism for the schema's `exit:` and `decision_record_sub_shape:` fields).
- **C18, C21, C22, C26 → Issue 6** (resume ladder + child-snapshot drift detection + child-internals isolation discipline + 7-day stale threshold all converge in the resume implementation; C22's isolation rule is enforced as an acceptance criterion rather than a separate issue).
- **C16 → Issue 7** (three exit paths + tie-break orchestration logic).
- **C23, C24, C25 → Issue 8** (artifact authoring/validation for STRATEGY pass-through, Decision Record both sub-shapes, abandonment-forced HTML-comment marker).
- **C27 → distributed across Issues 2-7** (phase prose under `skills/charter/references/phases/` is authored alongside the phase logic each issue implements, not as a standalone issue).
- **C28 → Issue 9** (evals depend on most prior issues being implementable; runs last).
- **C29, C30 → Issue 10** (CLAUDE.md surfacing — combined because the shirabe-side update IS the workspace fragment that workspace tooling assembles; no separate workspace-repo PR needed).

## Issue Outlines

### Issue 1: docs(references): add four parent-skill pattern-level references

- **Type**: standard
- **Complexity**: testable
- **Goal**: Author the four new pattern-level reference files at top-level `references/` per Design Decision 1 and Decision 7, providing the contract surface, state-schema vocabulary, resume-ladder template, and R14-widened child-inspection rule that `/charter` (and future `/scope`, `/work-on`) cite.
- **Section**: Design Solution Architecture Component 1; Implementation Approach Stage 1
- **Milestone**: Charter Skill
- **Dependencies**: None
- **Covers components**: C1, C2, C3, C4, C5, C6, C7, C8
- **Covers ACs (indirectly via citation)**: AC1b (the SKILL.md structural-elements list lives here)
- **Files created**:
  - `references/parent-skill-pattern.md` (contract surface + invariants + exits + conditional feeder + substitution surfaces + team-shape declarator)
  - `references/parent-skill-state-schema.md` (5-field minimum + invariants + extension discipline + R9 finalization spec)
  - `references/parent-skill-resume-ladder-template.md` (universal meta-ladder + body slots + malformed-state handling + stale threshold reference)
  - `references/parent-skill-child-inspection.md` (R14-widened isolation rule + per-parent surface table + drift semantics + internals negative examples)

### Issue 2: feat(charter): add SKILL.md with input modes, slug constraint, and Phase 0 wiring

- **Type**: standard
- **Complexity**: testable
- **Goal**: Ship `skills/charter/SKILL.md` with the seven structural elements per Design Component 2 (citing the Stage 1 references), Input Modes per PRD R2 (cold-start ask + freeform topic), the topic-slug regex `^[a-z0-9-]+$` hard-rejection at Phase 0 per R3, and the no-team Team Shape declaration per Design Component 5.
- **Section**: Design Solution Architecture Component 2; PRD R1, R2, R3
- **Milestone**: Charter Skill
- **Dependencies**: Issue 1
- **Covers components**: C9, C10
- **Covers ACs**: AC1, AC1b, AC2, AC3, AC3b, AC4
- **Files created**:
  - `skills/charter/SKILL.md`
  - `skills/charter/references/phases/phase-0-setup.md` (slug validation prose; one of C27's phase prose files)

### Issue 3: feat(charter): add Phase 1 discovery, visibility detection, and manual-fallback rule

- **Type**: standard
- **Complexity**: testable
- **Goal**: Author `/charter`'s Phase 1 discovery prose (including the literal thesis-shift question per R4), CLAUDE.md `## Repo Visibility:` header detection with default-Private warning per R12, and the manual-fallback non-interference rule per R13. This is the entry-router prelude before child-invocation decisions.
- **Section**: Design Solution Architecture Component 2 (R13 prose); PRD R4 discovery prompt, R12, R13
- **Milestone**: Charter Skill
- **Dependencies**: Issue 2
- **Covers components**: C11 (discovery half), C20
- **Covers ACs**: AC7 (Public-repo silence half), AC21, AC22, AC23
- **Files created**:
  - `skills/charter/references/phases/phase-1-discovery.md`
  - (visibility-detection prose may live in phase-0-setup.md or phase-1-discovery.md; Issue 3 owns the choice)

### Issue 4: feat(charter): add child invocation logic and chain-proposal confirmation prompt

- **Type**: standard
- **Complexity**: testable
- **Goal**: Implement the four `/charter` → child invocation decisions: `/vision` conditional on R4 signals, `/comp` conditional on R5 + R12 with degenerate-silence rule, `/strategy` always with three valid upstream shapes per R6, `/roadmap` conditional on R7 STRATEGY shape gates + pre-populated handoff. Then synthesize the chain-proposal confirmation prompt per R7.5 with literal Proceed/Adjust/Bail options.
- **Section**: PRD R4, R5, R6, R7, R7.5
- **Milestone**: Charter Skill
- **Dependencies**: Issue 3
- **Covers components**: C11 (invocation half), C12, C13, C14, C15
- **Covers ACs**: AC5, AC6, AC7 (Public-repo silence half), AC8, AC9, AC10, AC10b, AC10c, AC10d, AC10e, AC10f (with Issue 7 for Bail routing)
- **Files created**:
  - `skills/charter/references/phases/phase-1-discovery.md` (chain-proposal prompt prose added; same file from Issue 3)
  - `skills/charter/references/phases/phase-2-chain-orchestration.md` (per-child invocation prose)

### Issue 5: feat(charter): add state file schema and hard finalization check

- **Type**: standard
- **Complexity**: critical
- **Goal**: Specify the full `/charter` state file at `wip/charter_<topic>_state.md` per PRD R10 (YAML body with `.md` extension; 5-field minimum + `/charter`-specific extensions for `chain_started`, `chain_completed`, `planned_chain`, `chain_ran`, `chain_skipped`, `decision_record_sub_shape`, `child_snapshots`, plus conditional fields gated by exit type) and the R9 hard finalization check (`exit:` valid + sub-shape valid when applicable + conditional fields absent when triggering condition does not hold).
- **Section**: Design Solution Architecture Component 3; PRD R9, R10
- **Milestone**: Charter Skill
- **Dependencies**: Issue 1, Issue 2
- **Covers components**: C17, C19
- **Covers ACs**: AC11a, AC11b, AC15
- **Critical complexity rationale**: State file is the contract enforcement spine — schema malformation surfaces as a hard error in the resume ladder (R11); finalization check is the contract violation surface for missing/invalid `exit:` values. Security checklist required (per multi-pr critical-complexity rules).
- **Files created**:
  - `skills/charter/references/phases/phase-3-state-management.md` (or inline in another phase file; Issue 5 owns the choice)

### Issue 6: feat(charter): add resume ladder with drift detection and stale-session handling

- **Type**: standard
- **Complexity**: critical
- **Goal**: Implement `/charter`'s 10-row resume ladder per PRD R11 (first-match-wins, multi-source consultation across state file + child docs + child wip/ artifacts), child-snapshot dual-check drift detection (path + frontmatter status + git blob hash; drift fires when either differs), 7-day stale-session boundary per R16, status-aware re-entry suppression so `/charter`'s flow is not hijacked by a child's resume prompt, and malformed-state hard error with Discard recovery. Reads `wip/strategy_<topic>_discover.md` (not `_scope.md`) per known `/strategy` asymmetry. Enforces R14 child-internals isolation as an acceptance criterion.
- **Section**: Design Solution Architecture Component 4; PRD R10, R11, R13, R14, R16
- **Milestone**: Charter Skill
- **Dependencies**: Issue 5
- **Covers components**: C18, C21, C22, C26
- **Covers ACs**: AC16, AC17, AC18, AC18b, AC19, AC20, AC20b, AC20c, AC23, AC26d
- **Critical complexity rationale**: 10-row ladder with first-match-wins ordering, multi-source dual-check drift detection across snapshots, status-aware re-entry suppression mechanism (load-bearing for the discipline-vs-artifact decoupling), and the known `/strategy` asymmetry accommodation. Single most complex behavior in the skill. Security checklist required.
- **Files created**:
  - `skills/charter/references/phases/phase-resume.md` (or merged into another file; Issue 6 owns the choice)

### Issue 7: feat(charter): add three exit paths and tie-break orchestration

- **Type**: standard
- **Complexity**: critical
- **Goal**: Implement the three exit-path orchestration: full-run (Draft STRATEGY landed, optionally with Draft ROADMAP); re-evaluation (with re-evaluation and rejection sub-shapes); abandonment-forced (force-materialize the most-recently-running child's intermediate). Includes R8 tie-break for "most-recently-running" (last `chain_ran` entry → first `planned_chain` entry with non-empty wip/ intermediate → clean-cancel). Phase 5/Reject from `/strategy` maps to rejection sub-shape, not abandonment.
- **Section**: PRD R8
- **Milestone**: Charter Skill
- **Dependencies**: Issue 4, Issue 5
- **Covers components**: C16
- **Covers ACs**: AC11a, AC11b, AC12b, AC12c, AC13 (logic half), AC14 (logic half), AC14b
- **Critical complexity rationale**: Exit-path orchestration is contract enforcement against the design's three-exits invariant (every chain ends at a durable file; bail never silently loses). Bail routing, R7.5 Bail option routing, and Phase 5/Reject branching all interact here. Security checklist required.
- **Files created**:
  - `skills/charter/references/phases/phase-finalization.md`

### Issue 8: feat(charter): add exit artifact authoring (Decision Records + abandonment-forced marker + STRATEGY validation pass-through)

- **Type**: standard
- **Complexity**: testable
- **Goal**: Author the exit-artifact files: Decision Record at `docs/decisions/DECISION-strategy-<topic>-<sub-shape>-<YYYY-MM-DD>.md` for both re-evaluation and rejection sub-shapes (ADR-style body + frontmatter per PRD R15); abandonment-forced HTML-comment marker `<!-- charter-status-block: abandonment-forced; ... -->` inside the force-materialized artifact's Status section; verify Draft STRATEGY passes `shirabe validate --visibility=<repo-visibility>` for the full-run exit. Per-sub-shape body content rules enforced (re-evaluation cites named evidence; rejection cites discard commit SHA).
- **Section**: PRD R15
- **Milestone**: Charter Skill
- **Dependencies**: Issue 7
- **Covers components**: C23, C24, C25
- **Covers ACs**: AC12 (body content), AC13 (body content), AC14 (marker), AC24, AC25, AC26
- **Files created**:
  - `skills/charter/references/templates/decision-record-re-evaluation.md` (template)
  - `skills/charter/references/templates/decision-record-rejection.md` (template)
  - `skills/charter/references/templates/abandonment-forced-marker.md` (snippet)

### Issue 9: test(charter): add evals covering user stories and shared baseline

- **Type**: standard
- **Complexity**: testable
- **Goal**: Ship `skills/charter/evals/evals.json` with the canonical shared eval baseline (slug rejection, malformed state file, child-internals isolation, visibility default) plus `/charter`-specific scenarios covering US-1 (cold standalone full-run), US-2 (re-evaluation), US-3a (rejection sub-shape), US-3b (abandonment-forced), US-4 (reviewer redirect via manual fallback). All scenarios MUST pass under `scripts/run-evals.sh charter`.
- **Section**: Design Stage 2 (evals); PRD R18
- **Milestone**: Charter Skill
- **Dependencies**: Issue 2, Issue 3, Issue 4, Issue 5, Issue 6, Issue 7, Issue 8
- **Covers components**: C28
- **Covers ACs**: AC26c
- **Files created**:
  - `skills/charter/evals/evals.json`
- **Canonical-source note**: this issue establishes `/charter`'s evals.json as the canonical source for the shared baseline that `/scope` and `/work-on` will copy-and-adapt; baseline scenarios must be tagged and clearly delimited from `/charter`-specific scenarios so future parents can identify what to copy.

### Issue 10: docs(charter): surface /charter in shirabe and workspace CLAUDE.md

- **Type**: standard
- **Complexity**: simple
- **Goal**: Update `shirabe/CLAUDE.md` to mention `/charter` and include the trigger phrases from PRD R17b ("start a strategic conversation about X", "open a charter for Y", "I need to think through the bet on Z", direct `/charter <topic>` invocation). Update the listing surface that names shipped shirabe skills so `/charter` appears alongside `/strategy`, `/explore`, `/decision`, etc. The workspace-level CLAUDE.md is composed from per-repo fragments; this update lands in shirabe's own CLAUDE.md per Design Stage 3.
- **Section**: Design Stage 3; PRD R17a, R17b
- **Milestone**: Charter Skill
- **Dependencies**: None (can land independently any time after Issue 2 since it only references `/charter` by name)
- **Covers components**: C29, C30
- **Covers ACs**: AC26b
- **Files modified**:
  - `CLAUDE.md` (this repo)
- **Simple complexity rationale**: Pure documentation addition; no logic, no validation script needed beyond grep-for-trigger-phrases. No security implications.

## Phase 3 Open Questions for Phase 6 Review

The reviewer-scope-gate and reviewer-design-fidelity should inspect:

1. **Issue 1 bundling vs splitting**: Stage 1 packs four reference files into one issue. Reviewer should confirm this is the right granularity for a foundational-set PR, versus four issues (one per file) for tighter per-PR scope.
2. **Issue 3/4 split point**: Phase 1 discovery (Issue 3) and child invocation logic + chain-proposal (Issue 4) are split. The thesis-shift signal detection (R4) is conceptually discovery-side, but the actual `/vision` invocation decision uses the signal — the split lands the detection in Issue 3 and the decision in Issue 4.
3. **Issue 5/6/7/8 critical-complexity classifications**: Three issues are critical (state schema, resume ladder, exit-path orchestration). All three meet the criteria (contract enforcement mechanism; multi-source coupling; load-bearing for AC integrity). Reviewer should confirm or flag.
4. **C22 (R14 child-internals isolation) as AC, not issue**: The isolation rule is a discipline applied across resume + exit logic, not a separate deliverable. Issue 6 includes it as an acceptance criterion. AC20b is manual-review (code-path inspection).
5. **C27 phase prose distribution**: Phase reference files under `skills/charter/references/phases/` are authored alongside the phase logic each issue implements (Issues 2-7 each create one or more phase prose files). No standalone "author all phase prose" issue.
6. **Milestone name deviation**: This plan's milestone is "Charter Skill" rather than the first-heading-derived "Shirabe Progression Authoring". Rationale in `wip/plan_shirabe-charter-skill_milestones.md`: the design is shared across three parents, and the 1:1 doc-to-milestone invariant requires per-parent milestones.
7. **PLAN doc target status `Proposed` (SE4 directive)**: This decomposition is configured for `multi-pr` so Phase 4 decomposers emit full issue bodies, but Phase 7 stops at PLAN status `Proposed` (not `Active`) per SE4. `Proposed` is a custom status name — flagged for Phase 6 sequencing-integrity to confirm the status-name choice survives review.

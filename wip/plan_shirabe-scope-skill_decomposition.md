---
design_doc: docs/designs/DESIGN-shirabe-scope-skill.md
input_type: design
decomposition_strategy: horizontal
strategy_rationale: "Design is primarily pattern-doc edits, new SKILL.md bodies, and eval scenarios with the design's own Implementation Approach already sequencing components into 4 cohesive deliverables. Layer-by-layer (per-component) fits because component boundaries are explicit and stable; walking-skeleton would force an artificial e2e e2e flow on what is documentation/configuration work."
confirmed_by_user: false
issue_count: 13
execution_mode: multi-pr
execution_mode_rationale: "User explicitly chose multi-pr per team-lead's decomposition rationale (SE7 delivers incremental value across multiple shippable units; PR-1 ships parent-skill-worktree-discipline standalone so /charter benefits immediately; PR-2 and PR-3 ship /prd and /design Phase-N Reject contracts standalone so direct-invocation authors get Reject verdict before /scope; PR-4 ships /scope body + pattern-doc edits + evals as the integrated parent skill)."
---

# Plan Decomposition: shirabe-scope-skill

## Strategy: Horizontal

The design's 8 components and the supporting deliverables decompose into 13 atomic issues across 4 PRs. Each issue ships a single well-bounded artifact (one pattern-reference file edit, one SKILL.md body, one phase reference, one eval-scenario surface, etc.). The PRs aggregate issues by Phase A/B/C/D from the design's Implementation Approach plus the team-lead's PR-1/2/3/4 boundary.

### Why horizontal, not walking-skeleton

The design is documentation + configuration (pattern-doc edits, new SKILL.md body, eval scenarios) with internally-coupled but externally-bounded components. A walking-skeleton skeleton issue ("minimal e2e flow with stubs") would mean writing a stub `/scope` SKILL.md that runs the chain end-to-end with no validation, then refining each piece — which inverts the real dependency: the pattern-doc edits (Components 1-4) MUST exist before any `/scope` body can cite them, and the child-side Phase-N Reject contracts (Component 8) MUST exist before `/scope` Phase 2 can observe their `git log` discard-commit signal.

The design's own four sequenced phases (A: pattern-doc + new reference / B: child-side contracts / C: `/scope` body + evals / D: `/charter` back-edit) are the natural decomposition; each phase becomes one PR; issues are the atomic units inside each PR.

### PR aggregation (multi-pr mode)

| PR | Phase | Issues | Standalone value |
|----|-------|--------|------------------|
| PR-1 | Design Phase A.2 + D | <<ISSUE:1>>, <<ISSUE:2>> | New `parent-skill-worktree-discipline.md` reference; `/charter` SKILL.md cite-back-edit. `/charter` benefits immediately. |
| PR-2 | Design Phase B.1 | <<ISSUE:3>>, <<ISSUE:4>> | `/prd` Phase 4 3-option Reject contract (with commit-via-stdin) + 1 eval scenario. Direct-invocation `/prd` authors get Reject verdict. |
| PR-3 | Design Phase B.2 | <<ISSUE:5>>, <<ISSUE:6>> | `/design` Phase 6 3-option Reject contract (parallel) + 1 eval scenario. Direct-invocation `/design` authors get Reject verdict. |
| PR-4 | Design Phase A.1 + C | <<ISSUE:7>>, <<ISSUE:8>>, <<ISSUE:9>>, <<ISSUE:10>>, <<ISSUE:11>>, <<ISSUE:12>>, <<ISSUE:13>> | Three pattern-doc edits + `/scope` SKILL.md + 5 phase references + 4 Decision Record templates + 11-scenario eval suite + shirabe `CLAUDE.md` tactical-chain entry section + DESIGN status flip to Planned (Phase 7 effect). |

PR-5 (vision-repo roadmap text update + mark SE7 Done) is a downstream follow-on in a separate repo; out of scope for this /plan but noted in Implementation Sequence.

### Why pattern-doc edits ride with /scope body in PR-4 (not their own PR per Design Phase A)

The design's Phase A bundles Components 1+2+3+4 into one PR. The team-lead's decomposition splits Component 4 (the new top-level reference) into PR-1 (because `/charter` cites it back-edited) and folds Components 1+2+3 (the surgical edits to three existing pattern references) into PR-4 alongside the `/scope` body. Rationale:

- Components 1, 2, 3 are surgical edits (~100 lines total) that exclusively serve `/scope`'s body. Shipping them in a standalone PR would force a merge-gap where the pattern doc grows new vocabulary that NO skill cites (until PR-4 lands). Reviewers reading the pattern-doc edits without the `/scope` SKILL.md context would have to imagine the consuming skill.
- Component 4 is genuinely standalone — it's a NEW top-level reference (~80-100 lines) that `/charter` immediately benefits from via the back-edit. Shipping Component 4 alone in PR-1 lets `/charter`'s worktree-discipline binding land before `/scope` exists.

The PR-4 boundary respects the design's "Phase C ships as one PR because its components are internally coupled" and extends it to absorb Phase A's surgical edits that share the same coupling.

## Issue Outlines

Each issue carries:
- **Type**: standard (no walking skeleton in horizontal decomposition)
- **Complexity**: simple, testable, or critical (per the AC template choice — Phase 4 issue generators finalize)
- **Goal**: One sentence
- **Section**: Design doc section the issue implements
- **Milestone**: Shirabe Scope Skill
- **PR**: Target PR aggregation
- **Dependencies**: Other `<<ISSUE:N>>` placeholders; or None

### Issue 1: docs(refs): add parent-skill-worktree-discipline reference

- **Type**: standard
- **Complexity**: simple
- **Goal**: Add new top-level `references/parent-skill-worktree-discipline.md` with five sections (Trigger Condition / Three-Option Prompt / Recording "Proceed Anyway" Divergence / Integration with Chain-Proposal Prompt / Binding Notes) per Component 4 / Decision 4.
- **Section**: Solution Architecture / Component 4
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-1
- **Dependencies**: None

### Issue 2: docs(charter): cite worktree-discipline reference in /charter

- **Type**: standard
- **Complexity**: simple
- **Goal**: Back-edit `/charter` SKILL.md to add the new `parent-skill-worktree-discipline.md` to its Reference Files table (Phase D deliverable; in scope for PR-1 because the new reference is meaningless without at least one parent skill citing it).
- **Section**: Implementation Approach / Phase D
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-1
- **Dependencies**: <<ISSUE:1>>

### Issue 3: feat(prd): ship Phase 4 step 4.5 3-option Reject contract

- **Type**: standard
- **Complexity**: testable
- **Goal**: Replace `/prd` Phase 4 step 4.5's existing 2-option AskUserQuestion (Approved / Needs iteration) with a 3-option gate (Approved / Reject / Continue-revising); on Reject ask rationale, run `git rm docs/prds/PRD-<topic>.md`, remove `wip/prd_<topic>_*.md`, commit `docs(prd): discard PRD draft for <topic>` via `git commit -F -` (stdin) per Component 8.1 + Security Considerations mitigation; include the disclaimer substring "Rationale will be committed to git history" in the Reject prompt's literal text.
- **Section**: Solution Architecture / Component 8.1; Security Considerations / Command injection — git-commit rationale interpolation
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-2
- **Dependencies**: None

### Issue 4: test(prd): add Phase 4 Reject contract eval scenario

- **Type**: standard
- **Complexity**: testable
- **Goal**: Add an eval scenario to `skills/prd/evals/evals.json` covering Approve / Reject / Continue-revising outcomes; verifies the discard commit message format, the `git rm` of the durable artifact, the `wip/` cleanup, and the rationale-via-stdin behavior. Includes both in-chain and out-of-chain Reject paths per AC30c.
- **Section**: Implementation Approach / Phase B (eval coverage)
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-2
- **Dependencies**: <<ISSUE:3>>

### Issue 5: feat(design): ship Phase 6 step 6.7 3-option Reject contract

- **Type**: standard
- **Complexity**: testable
- **Goal**: Replace `/design` Phase 6 step 6.7's existing 2-option AskUserQuestion (Approved / Needs iteration) with a 3-option gate (Approved / Reject / Continue-revising); on Reject ask rationale, run `git rm docs/designs/DESIGN-<topic>.md`, remove `wip/design_<topic>_*.md` and `wip/research/design_<topic>_*.md`, commit `docs(design): discard DESIGN draft for <topic>` via `git commit -F -` (stdin) per Component 8.2; include the disclaimer substring "Rationale will be committed to git history" in the Reject prompt's literal text. Gate fires after the commit step (preserves Draft durability across interruptions).
- **Section**: Solution Architecture / Component 8.2; Security Considerations / Command injection — git-commit rationale interpolation
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-3
- **Dependencies**: None

### Issue 6: test(design): add Phase 6 Reject contract eval scenario

- **Type**: standard
- **Complexity**: testable
- **Goal**: Add an eval scenario to `skills/design/evals/evals.json` covering Approve / Reject / Continue-revising outcomes; verifies the discard commit message format, the `git rm` of the durable artifact, the wip cleanup (both `wip/design_*` and `wip/research/design_*`), and the rationale-via-stdin behavior. Includes both in-chain and out-of-chain Reject paths per AC30c.
- **Section**: Implementation Approach / Phase B (eval coverage)
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-3
- **Dependencies**: <<ISSUE:5>>

### Issue 7: docs(refs): add Gate Vocabulary section and L13 amendment to parent-skill-pattern.md

- **Type**: standard
- **Complexity**: testable
- **Goal**: Edit `references/parent-skill-pattern.md` to insert a NEW Gate Vocabulary section between "Three Exit Paths" and "Conditional Feeder Invocation Shape" listing the four gate shapes (EITHER-signal / ALWAYS / shape-dependent / Mandatory-with-auto-skip) each with one canonical example per Component 1.1; rewrite L13 (Parents do not extend children's input surfaces) per Decision 3's amendment text permitting the pattern-level `parent_orchestration:` state-file sentinel as the sole permitted parent-orchestration primitive per Component 1.2.
- **Section**: Solution Architecture / Component 1 (1.1 + 1.2)
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-4
- **Dependencies**: None

### Issue 8: docs(refs): extend parent-skill-state-schema.md with boundary, plan_execution_mode, and R9 additions

- **Type**: standard
- **Complexity**: testable
- **Goal**: Edit `references/parent-skill-state-schema.md` to add two new conditional-field bullets in Field Semantics (`boundary:` gated by `exit: re-evaluation`; `plan_execution_mode:` gated by `/plan` in `chain_ran`); add Chain-tracking paragraph noting `plan_execution_mode:` is recorded separately from `chain_ran`/`chain_skipped`; extend R9 Part 2 with sub-shape-discriminator hard-finalization-check addition; extend R9 Part 3 with chain-membership-gated I-5 addition. Per Component 2.
- **Section**: Solution Architecture / Component 2 (2.1 + 2.2 + 2.3 + 2.4)
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-4
- **Dependencies**: <<ISSUE:7>> (Gate Vocabulary's Mandatory-with-auto-skip definition is cited by 2.1's plan_execution_mode bullet's chain-skipped semantics)

### Issue 9: docs(refs): append refuse-and-redirect slot 5 paragraph to parent-skill-resume-ladder-template.md

- **Type**: standard
- **Complexity**: simple
- **Goal**: Append the single paragraph documented at Component 3.1 to the Slot 5 spec in `references/parent-skill-resume-ladder-template.md`. Paragraph documents the refuse-and-redirect prompt shape (literal substring `redirect to /<skill-name>` case-insensitive; MUST NOT contain Re-evaluate / Revise / Bail triad) and preserves the 9-row meta-ladder count.
- **Section**: Solution Architecture / Component 3
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-4
- **Dependencies**: None

### Issue 10: feat(scope): add /scope SKILL.md body

- **Type**: standard
- **Complexity**: critical
- **Goal**: Create `skills/scope/SKILL.md` per Component 5 — seven pattern-level structural elements with `/scope`-specific bindings (Input Modes / execution-mode flags with `--max-rounds=5` / topic-slug regex citation / Workflow Phases diagram / Resume Logic 9-row Slot 5 + 4-row Slot 6 + vacuous Slot 7 / Phase Execution list / Reference Files table) plus prose sections covering chain-proposal output (R7.5), three exit paths (R8), state schema (R10), visibility detection (R12), manual-fallback non-interference (R13), validator pass-through, and Phase-N Reject in-chain integration (R23). Implements the slug re-validation, closed write-target set, and state-file enum re-validation mitigations from Security Considerations.
- **Section**: Solution Architecture / Component 5
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-4
- **Dependencies**: <<ISSUE:7>>, <<ISSUE:8>>, <<ISSUE:9>>, <<ISSUE:1>> (cites all four pattern-doc references)

### Issue 11: feat(scope): add /scope phase reference files (Phase 0-4)

- **Type**: standard
- **Complexity**: critical
- **Goal**: Create the five phase reference files under `skills/scope/references/phases/` — `phase-0-setup.md` (slug validation, visibility detection, stale-sentinel self-heal per Security Considerations); `phase-1-discovery.md` per Component 6 (R4/R5/R6 gate evaluation with structured R6 walk and 3-4 worked examples per predicate; chain-proposal output construction with literal Proceed/Adjust/Bail substrings; Mandatory-with-auto-skip evaluation for `/prd`); `phase-2-chain-orchestration.md` per Component 7 (worktree-staleness check + sentinel write + child invocation + structural file-existence check per R20 + sentinel cleanup + child-snapshot capture per R10 + Phase-N Reject handling via `git log` discard-commit observation + validator pass-through per Decision 10); `phase-3-exit-finalization.md` (R8 + R9 + R15 with abandonment-forced HTML-comment marker per Decision 7); `phase-4-cleanup.md` (wip cleanup).
- **Section**: Solution Architecture / Components 6 + 7; Decisions 2, 7, 10; Security Considerations
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-4
- **Dependencies**: <<ISSUE:10>> (cites SKILL.md's Reference Files table); <<ISSUE:3>>, <<ISSUE:5>> (Phase 2 observability via discard commit requires the child-side Phase-N Reject contracts to exist)

### Issue 12: feat(scope): add Decision Record body templates for re-evaluation and rejection at both boundaries

- **Type**: standard
- **Complexity**: simple
- **Goal**: Create the four Decision Record body templates under `skills/scope/references/decision-record-{prd|design}-{re-evaluation|rejection}.md` per Interface I.2. Each template (~50-80 lines) covers the ADR-style body shape per R15 with frontmatter (`status: {Draft | Accepted}`, `decision:`, `rationale:`), boundary-specific prose, and sub-shape-specific framing (re-evaluation references the existing PRD/DESIGN path frozen via `child_snapshots`; rejection references the discard commit SHA + rejection rationale per Component 7.7).
- **Section**: Solution Architecture / Interface I.2; Decisions 1, 5; Component 7.7
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-4
- **Dependencies**: <<ISSUE:10>>

### Issue 13: test(scope): add /scope eval suite + shirabe CLAUDE.md tactical-chain entry section

- **Type**: standard
- **Complexity**: testable
- **Goal**: Create `skills/scope/evals/evals.json` with eleven scenarios covering US-1 through US-6 (R18 / AC24b) plus additional scenarios for Phase-N Reject in-chain and out-of-chain paths (AC30c), abandonment-forced HTML-comment marker uniformity across artifact types (AC13), drift-detection three-option prompt vocabulary (AC18a/AC18b), refuse-and-redirect literal substring contract for PLAN-Active / PLAN-Done (AC17c), and slug re-validation on resume (Security Considerations). Edit shirabe `CLAUDE.md` to add a "Tactical Chain Entry: /scope" section paralleling the existing "Strategic Chain Entry: /charter" section per R17a/R17b. Also edit workspace `CLAUDE.md` surfacing of `/scope` entry triggers (per R17a). NOTE: the DESIGN status flip from Accepted → Planned is a Phase 7 effect of this /plan and is NOT shipped by this issue.
- **Section**: Implementation Approach / Phase C (eval suite); R17a / R17b CLAUDE.md surfacing; R18 / AC24b eval coverage
- **Milestone**: Shirabe Scope Skill
- **PR**: PR-4
- **Dependencies**: <<ISSUE:10>>, <<ISSUE:11>>, <<ISSUE:12>> (eval scenarios exercise the SKILL.md, phase references, and Decision Record templates)

## Complexity Distribution

- **simple**: 4 issues (<<ISSUE:1>>, <<ISSUE:2>>, <<ISSUE:9>>, <<ISSUE:12>>) — single-file artifact additions with no validation script needed beyond inspection.
- **testable**: 7 issues (<<ISSUE:3>>, <<ISSUE:4>>, <<ISSUE:5>>, <<ISSUE:6>>, <<ISSUE:7>>, <<ISSUE:8>>, <<ISSUE:13>>) — changes whose contract can be verified by eval scenarios or grep-against-file checks.
- **critical**: 2 issues (<<ISSUE:10>>, <<ISSUE:11>>) — the two largest deliverables; both carry security mitigations (slug re-validation, closed write-target set, state-file enum re-validation, commit-via-stdin, stale-sentinel self-heal).

Phase 4 issue generators may refine complexity assignments after writing acceptance criteria; Phase 6 review validates.

## Implementation Order (input to Phase 5)

Issues are sequenced so each PR's issues land before the next PR's issues need them. Within each PR, issues can complete in parallel where the dependency graph allows; cross-PR dependencies are real (PR-2 and PR-3 must merge before PR-4 ships because Issue 11 cites the discard-commit observability).

1. PR-1: `<<ISSUE:1>>` → `<<ISSUE:2>>`
2. PR-2: `<<ISSUE:3>>` → `<<ISSUE:4>>` (parallel to PR-1, PR-3 except for branch coordination)
3. PR-3: `<<ISSUE:5>>` → `<<ISSUE:6>>` (parallel to PR-1, PR-2)
4. PR-4: `<<ISSUE:7>>` → `<<ISSUE:8>>`; `<<ISSUE:9>>` in parallel; `<<ISSUE:10>>` depends on 7/8/9/1; `<<ISSUE:11>>` depends on 10 + (3 from PR-2) + (5 from PR-3); `<<ISSUE:12>>` depends on 10; `<<ISSUE:13>>` depends on 10/11/12.

Critical path: `<<ISSUE:1>>` → (skip <<ISSUE:2>>) → `<<ISSUE:7>>` → `<<ISSUE:8>>` → `<<ISSUE:10>>` → `<<ISSUE:11>>` → `<<ISSUE:13>>` (Phase 5 will refine).

## Validation against Phase 3 quality checklist

- [x] Decomposition strategy decided and recorded: **horizontal**.
- [x] All components covered by issues: Components 1 (<<ISSUE:7>>), 2 (<<ISSUE:8>>), 3 (<<ISSUE:9>>), 4 (<<ISSUE:1>>), 5 (<<ISSUE:10>>), 6 + 7 (<<ISSUE:11>>), 8.1 (<<ISSUE:3>> + <<ISSUE:4>>), 8.2 (<<ISSUE:5>> + <<ISSUE:6>>); Decision Record templates (<<ISSUE:12>>); eval suite + CLAUDE.md edits (<<ISSUE:13>>); /charter back-edit Phase D (<<ISSUE:2>>).
- [x] Each issue is atomic and complete: every issue is one-file or one-tight-cluster delivery with clear AC.
- [x] Each issue is independent enough to complete in one session.
- [x] Title follows conventional commits format (imperative mood, lowercase).
- [x] Design section referenced per issue.
- [x] Dependencies identified via `<<ISSUE:N>>` placeholders per the L11 fold.

## Next Phase

Proceed to Phase 4: Agent Generation (`phase-4-agent-generation.md`). Phase 4 spawns 13 parallel issue-generator agents (one per issue identified above); each writes a full issue body at `wip/plan_shirabe-scope-skill_issue_<N>.md` per the AC template for its complexity tier. After all 13 land, the manifest aggregates them into `wip/plan_shirabe-scope-skill_manifest.json`.

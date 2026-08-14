---
schema: research/v1
---

# Corpus compatibility: upstream-link legality

Repo: `public/shirabe` @ worktree `upstream-link-legality`, HEAD `261b2e2`.
Every number below is derived from the git-tracked tree, not from a sample.

## Step 1 -- Ground-truth edge inventory

- Git-tracked `.md` files under `docs/`: **149**
- Docs carrying an `upstream:` frontmatter key: **81**
- Docs with **no** `upstream:` field at all: **68**
- Docs whose `upstream:` is present but empty: **0**
- Total edges: **81**

Field shape (validator's scalar/sequence split):

- `scalar`: 81

Every `upstream:` in the corpus is a **single-line scalar**. There is not one
YAML sequence, not one cross-repo `owner/repo:path` value, and not one
angle-bracket placeholder anywhere in the tracked tree. The sequence and
placeholder handling in `upstream.rs` is real but currently unexercised by
this repo's own docs.

### Source-type census

| Source type | Docs | Docs with an edge |
|---|---|---|
| DESIGN | 48 | 38 |
| PRD | 42 | 35 |
| BRIEF | 36 | 8 |
| NON-ARTIFACT | 22 | 0 |
| PLAN | 1 | 0 |

No ROADMAP, STRATEGY, VISION, or COMP doc exists in this repo. Any legality
rule written for those source types is **untested by this corpus** -- it can
only be exercised by fixtures.

### Edge-type histogram (source type -> target type)

| Source type | Target type | Edges |
|---|---|---|
| DESIGN | PRD | 38 |
| PRD | BRIEF | 35 |
| BRIEF | DESIGN | 4 |
| BRIEF | PLAN | 2 |
| BRIEF | BRIEF | 2 |

### Complete edge table

`R6` is today's resolution result (exists on disk + git-tracked).
`TP` is the candidate type-pair verdict, `LC` the candidate lifecycle verdict.

| # | Source | Src type | upstream value | Tgt type | R6 | TP | LC |
|---|---|---|---|---|---|---|---|
| 1 | `docs/briefs/BRIEF-cascade-outline-ac-completeness.md`:16 | BRIEF | `docs/plans/PLAN-roadmap-plan-standardization.md` | PLAN | FAIL-missing | FAIL | FAIL |
| 2 | `docs/briefs/BRIEF-fc06-index-alias.md`:20 | BRIEF | `docs/designs/current/DESIGN-roadmap-issueless-table-rendering.md` | DESIGN | pass | FAIL | pass |
| 3 | `docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md`:22 | BRIEF | `docs/designs/DESIGN-roadmap-plan-standardization.md` | DESIGN | FAIL-missing | FAIL | pass |
| 4 | `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md`:18 | BRIEF | `docs/briefs/BRIEF-lifecycle-passing-state-validation.md` | BRIEF | pass | FAIL | pass |
| 5 | `docs/briefs/BRIEF-lifecycle-passing-state-validation.md`:18 | BRIEF | `docs/designs/DESIGN-roadmap-plan-standardization.md` | DESIGN | FAIL-missing | FAIL | pass |
| 6 | `docs/briefs/BRIEF-single-pr-plan-validation.md`:4 | BRIEF | `docs/plans/PLAN-roadmap-plan-standardization.md` | PLAN | FAIL-missing | FAIL | FAIL |
| 7 | `docs/briefs/BRIEF-skill-cascade-lifecycle-check.md`:24 | BRIEF | `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` | BRIEF | pass | FAIL | pass |
| 8 | `docs/briefs/BRIEF-table-diagram-reconciliation.md`:20 | BRIEF | `docs/designs/DESIGN-roadmap-plan-standardization.md` | DESIGN | FAIL-missing | FAIL | pass |
| 9 | `docs/designs/current/DESIGN-artifact-traceability.md`:3 | DESIGN | `docs/prds/PRD-artifact-traceability.md` | PRD | pass | pass | pass |
| 10 | `docs/designs/current/DESIGN-capstone-orchestration.md`:30 | DESIGN | `docs/prds/PRD-capstone-orchestration.md` | PRD | pass | pass | pass |
| 11 | `docs/designs/current/DESIGN-chain-cardinality.md`:4 | DESIGN | `docs/prds/PRD-chain-cardinality.md` | PRD | pass | pass | pass |
| 12 | `docs/designs/current/DESIGN-complexity-routing-expansion.md`:3 | DESIGN | `docs/prds/PRD-complexity-routing-expansion.md` | PRD | pass | pass | pass |
| 13 | `docs/designs/current/DESIGN-doc-vs-github-state-reconciliation.md`:51 | DESIGN | `docs/prds/PRD-doc-vs-github-state-reconciliation.md` | PRD | pass | pass | pass |
| 14 | `docs/designs/current/DESIGN-execute-friction.md`:4 | DESIGN | `docs/prds/PRD-execute-friction.md` | PRD | pass | pass | pass |
| 15 | `docs/designs/current/DESIGN-execute-skill.md`:4 | DESIGN | `docs/prds/PRD-execute-skill.md` | PRD | pass | pass | pass |
| 16 | `docs/designs/current/DESIGN-finalize-chain.md`:23 | DESIGN | `docs/prds/PRD-finalize-chain.md` | PRD | pass | pass | pass |
| 17 | `docs/designs/current/DESIGN-gha-doc-validation.md`:3 | DESIGN | `docs/prds/PRD-gha-doc-validation.md` | PRD | pass | pass | pass |
| 18 | `docs/designs/current/DESIGN-legend-vs-classdef-reconciliation.md`:49 | DESIGN | `docs/prds/PRD-legend-vs-classdef-reconciliation.md` | PRD | pass | pass | pass |
| 19 | `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`:4 | DESIGN | `docs/prds/PRD-lifecycle-draft-ready-discipline.md` | PRD | pass | pass | pass |
| 20 | `docs/designs/current/DESIGN-lifecycle-passing-state-validation.md`:4 | DESIGN | `docs/prds/PRD-lifecycle-passing-state-validation.md` | PRD | pass | pass | pass |
| 21 | `docs/designs/current/DESIGN-lifecycle-posture-mode.md`:4 | DESIGN | `docs/prds/PRD-lifecycle-posture-mode.md` | PRD | pass | pass | pass |
| 22 | `docs/designs/current/DESIGN-plan-skill-rework.md`:3 | DESIGN | `docs/prds/PRD-plan-skill-rework.md` | PRD | pass | pass | pass |
| 23 | `docs/designs/current/DESIGN-populate-issueless-default.md`:4 | DESIGN | `docs/prds/PRD-populate-issueless-default.md` | PRD | pass | pass | pass |
| 24 | `docs/designs/current/DESIGN-pr-template-gate.md`:29 | DESIGN | `docs/prds/PRD-pr-template-gate.md` | PRD | pass | pass | pass |
| 25 | `docs/designs/current/DESIGN-reusable-release-system.md`:3 | DESIGN | `docs/prds/PRD-reusable-release-system.md` | PRD | pass | pass | pass |
| 26 | `docs/designs/current/DESIGN-roadmap-creation-skill.md`:3 | DESIGN | `docs/prds/PRD-roadmap-skill.md` | PRD | pass | pass | pass |
| 27 | `docs/designs/current/DESIGN-roadmap-issueless-table-rendering.md`:4 | DESIGN | `docs/prds/PRD-roadmap-issueless-table-rendering.md` | PRD | pass | pass | pass |
| 28 | `docs/designs/current/DESIGN-roadmap-plan-standardization.md`:4 | DESIGN | `docs/prds/PRD-roadmap-plan-standardization.md` | PRD | pass | pass | pass |
| 29 | `docs/designs/current/DESIGN-scope-completion-cascade.md`:4 | DESIGN | `docs/prds/PRD-scope-completion-cascade.md` | PRD | pass | pass | pass |
| 30 | `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`:5 | DESIGN | `docs/prds/PRD-scope-consolidation-over-skipping.md` | PRD | pass | pass | pass |
| 31 | `docs/designs/current/DESIGN-session-work-summary.md`:4 | DESIGN | `docs/prds/PRD-session-work-summary.md` | PRD | pass | pass | pass |
| 32 | `docs/designs/current/DESIGN-shirabe-artifact-decision-contract.md`:5 | DESIGN | `docs/prds/PRD-shirabe-artifact-decision-contract.md` | PRD | pass | pass | pass |
| 33 | `docs/designs/current/DESIGN-shirabe-brief-skill.md`:38 | DESIGN | `docs/prds/PRD-shirabe-brief-skill.md` | PRD | pass | pass | pass |
| 34 | `docs/designs/current/DESIGN-shirabe-check-absorption.md`:4 | DESIGN | `docs/prds/PRD-shirabe-check-absorption.md` | PRD | pass | pass | pass |
| 35 | `docs/designs/current/DESIGN-shirabe-child-dispatch-contract.md`:4 | DESIGN | `docs/prds/PRD-shirabe-child-dispatch-contract.md` | PRD | pass | pass | pass |
| 36 | `docs/designs/current/DESIGN-shirabe-cli-multi-consumer.md`:4 | DESIGN | `docs/prds/PRD-shirabe-cli-multi-consumer.md` | PRD | pass | pass | pass |
| 37 | `docs/designs/current/DESIGN-shirabe-comp-skill.md`:4 | DESIGN | `docs/prds/PRD-shirabe-comp-skill.md` | PRD | pass | pass | pass |
| 38 | `docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md`:4 | DESIGN | `docs/prds/PRD-shirabe-pattern-v1-ergonomics.md` | PRD | pass | pass | pass |
| 39 | `docs/designs/current/DESIGN-shirabe-pattern-v1-workflow-friction.md`:4 | DESIGN | `docs/prds/PRD-shirabe-pattern-v1-workflow-friction.md` | PRD | pass | pass | pass |
| 40 | `docs/designs/current/DESIGN-shirabe-progression-authoring.md`:3 | DESIGN | `docs/prds/PRD-shirabe-charter-skill.md` | PRD | pass | pass | pass |
| 41 | `docs/designs/current/DESIGN-shirabe-scope-skill.md`:3 | DESIGN | `docs/prds/PRD-shirabe-scope-skill.md` | PRD | pass | pass | pass |
| 42 | `docs/designs/current/DESIGN-shirabe-strategy-skill.md`:29 | DESIGN | `docs/prds/PRD-shirabe-strategy-skill.md` | PRD | pass | pass | pass |
| 43 | `docs/designs/current/DESIGN-skill-cascade-lifecycle-check.md`:4 | DESIGN | `docs/prds/PRD-skill-cascade-lifecycle-check.md` | PRD | pass | pass | pass |
| 44 | `docs/designs/current/DESIGN-table-diagram-reconciliation.md`:41 | DESIGN | `docs/prds/PRD-table-diagram-reconciliation.md` | PRD | pass | pass | pass |
| 45 | `docs/designs/current/DESIGN-transition-script-consolidation.md`:3 | DESIGN | `docs/prds/PRD-transition-script-consolidation.md` | PRD | pass | pass | pass |
| 46 | `docs/designs/current/DESIGN-work-on-definition-of-done.md`:26 | DESIGN | `docs/prds/PRD-work-on-definition-of-done.md` | PRD | pass | pass | pass |
| 47 | `docs/prds/PRD-capstone-orchestration.md`:14 | PRD | `docs/briefs/BRIEF-capstone-orchestration.md` | BRIEF | pass | pass | pass |
| 48 | `docs/prds/PRD-cascade-outline-ac-completeness.md`:20 | PRD | `docs/briefs/BRIEF-cascade-outline-ac-completeness.md` | BRIEF | pass | pass | pass |
| 49 | `docs/prds/PRD-chain-cardinality.md`:18 | PRD | `docs/briefs/BRIEF-chain-cardinality.md` | BRIEF | pass | pass | pass |
| 50 | `docs/prds/PRD-doc-vs-github-state-reconciliation.md`:27 | PRD | `docs/briefs/BRIEF-doc-vs-github-state-reconciliation.md` | BRIEF | pass | pass | pass |
| 51 | `docs/prds/PRD-execute-friction.md`:19 | PRD | `docs/briefs/BRIEF-execute-friction.md` | BRIEF | pass | pass | pass |
| 52 | `docs/prds/PRD-execute-skill.md`:19 | PRD | `docs/briefs/BRIEF-execute-skill.md` | BRIEF | pass | pass | pass |
| 53 | `docs/prds/PRD-fc06-index-alias.md`:22 | PRD | `docs/briefs/BRIEF-fc06-index-alias.md` | BRIEF | pass | pass | pass |
| 54 | `docs/prds/PRD-finalize-chain.md`:17 | PRD | `docs/briefs/BRIEF-finalize-chain.md` | BRIEF | pass | pass | pass |
| 55 | `docs/prds/PRD-legend-vs-classdef-reconciliation.md`:29 | PRD | `docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md` | BRIEF | pass | pass | pass |
| 56 | `docs/prds/PRD-lifecycle-draft-ready-discipline.md`:21 | PRD | `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` | BRIEF | pass | pass | pass |
| 57 | `docs/prds/PRD-lifecycle-passing-state-validation.md`:22 | PRD | `docs/briefs/BRIEF-lifecycle-passing-state-validation.md` | BRIEF | pass | pass | pass |
| 58 | `docs/prds/PRD-lifecycle-posture-mode.md`:16 | PRD | `docs/briefs/BRIEF-lifecycle-posture-mode.md` | BRIEF | pass | pass | pass |
| 59 | `docs/prds/PRD-populate-issueless-default.md`:19 | PRD | `docs/briefs/BRIEF-populate-issueless-default.md` | BRIEF | pass | pass | pass |
| 60 | `docs/prds/PRD-pr-template-gate.md`:19 | PRD | `docs/briefs/BRIEF-pr-template-gate.md` | BRIEF | pass | pass | pass |
| 61 | `docs/prds/PRD-roadmap-issueless-table-rendering.md`:17 | PRD | `docs/briefs/BRIEF-roadmap-issueless-table-rendering.md` | BRIEF | pass | pass | pass |
| 62 | `docs/prds/PRD-roadmap-plan-standardization.md`:26 | PRD | `docs/briefs/BRIEF-roadmap-plan-standardization.md` | BRIEF | pass | pass | pass |
| 63 | `docs/prds/PRD-scope-completion-cascade.md`:16 | PRD | `docs/briefs/BRIEF-scope-completion-cascade.md` | BRIEF | pass | pass | pass |
| 64 | `docs/prds/PRD-scope-consolidation-over-skipping.md`:18 | PRD | `docs/briefs/BRIEF-scope-consolidation-over-skipping.md` | BRIEF | pass | pass | pass |
| 65 | `docs/prds/PRD-session-work-summary.md`:16 | PRD | `docs/briefs/BRIEF-session-work-summary.md` | BRIEF | pass | pass | pass |
| 66 | `docs/prds/PRD-shirabe-artifact-decision-contract.md`:5 | PRD | `docs/briefs/BRIEF-shirabe-artifact-decision-contract.md` | BRIEF | pass | pass | pass |
| 67 | `docs/prds/PRD-shirabe-brief-skill.md`:23 | PRD | `docs/briefs/BRIEF-shirabe-brief-skill.md` | BRIEF | pass | pass | pass |
| 68 | `docs/prds/PRD-shirabe-charter-skill.md`:27 | PRD | `docs/briefs/BRIEF-shirabe-charter-skill.md` | BRIEF | pass | pass | pass |
| 69 | `docs/prds/PRD-shirabe-check-absorption.md`:17 | PRD | `docs/briefs/BRIEF-shirabe-check-absorption.md` | BRIEF | pass | pass | pass |
| 70 | `docs/prds/PRD-shirabe-child-dispatch-contract.md`:28 | PRD | `docs/briefs/BRIEF-shirabe-child-dispatch-contract.md` | BRIEF | pass | pass | pass |
| 71 | `docs/prds/PRD-shirabe-cli-multi-consumer.md`:21 | PRD | `docs/briefs/BRIEF-shirabe-cli-multi-consumer.md` | BRIEF | pass | pass | pass |
| 72 | `docs/prds/PRD-shirabe-comp-skill.md`:28 | PRD | `docs/briefs/BRIEF-shirabe-comp-skill.md` | BRIEF | pass | pass | pass |
| 73 | `docs/prds/PRD-shirabe-pattern-v1-ergonomics.md`:4 | PRD | `docs/briefs/BRIEF-shirabe-pattern-v1-ergonomics.md` | BRIEF | pass | pass | pass |
| 74 | `docs/prds/PRD-shirabe-pattern-v1-workflow-friction.md`:4 | PRD | `docs/briefs/BRIEF-shirabe-pattern-v1-workflow-friction.md` | BRIEF | pass | pass | pass |
| 75 | `docs/prds/PRD-shirabe-scope-skill.md`:26 | PRD | `docs/briefs/BRIEF-shirabe-scope-skill.md` | BRIEF | pass | pass | pass |
| 76 | `docs/prds/PRD-shirabe-strategy-skill.md`:26 | PRD | `docs/briefs/BRIEF-shirabe-strategy-skill.md` | BRIEF | pass | pass | pass |
| 77 | `docs/prds/PRD-single-pr-plan-validation.md`:17 | PRD | `docs/briefs/BRIEF-single-pr-plan-validation.md` | BRIEF | pass | pass | pass |
| 78 | `docs/prds/PRD-skill-cascade-lifecycle-check.md`:25 | PRD | `docs/briefs/BRIEF-skill-cascade-lifecycle-check.md` | BRIEF | pass | pass | pass |
| 79 | `docs/prds/PRD-table-diagram-reconciliation.md`:24 | PRD | `docs/briefs/BRIEF-table-diagram-reconciliation.md` | BRIEF | pass | pass | pass |
| 80 | `docs/prds/PRD-transition-script-consolidation.md`:15 | PRD | `docs/briefs/BRIEF-transition-script-consolidation.md` | BRIEF | pass | pass | pass |
| 81 | `docs/prds/PRD-work-on-definition-of-done.md`:16 | PRD | `docs/briefs/BRIEF-work-on-definition-of-done.md` | BRIEF | pass | pass | pass |

### Docs with no `upstream:` field

68 docs. These are invisible to any upstream-legality rule.

- `docs/briefs/BRIEF-capstone-orchestration.md`
- `docs/briefs/BRIEF-chain-cardinality.md`
- `docs/briefs/BRIEF-doc-vs-github-state-reconciliation.md`
- `docs/briefs/BRIEF-execute-friction.md`
- `docs/briefs/BRIEF-execute-skill.md`
- `docs/briefs/BRIEF-finalize-chain.md`
- `docs/briefs/BRIEF-lifecycle-posture-mode.md`
- `docs/briefs/BRIEF-populate-issueless-default.md`
- `docs/briefs/BRIEF-pr-template-gate.md`
- `docs/briefs/BRIEF-roadmap-issueless-table-rendering.md`
- `docs/briefs/BRIEF-roadmap-plan-standardization.md`
- `docs/briefs/BRIEF-scope-completion-cascade.md`
- `docs/briefs/BRIEF-scope-consolidation-over-skipping.md`
- `docs/briefs/BRIEF-session-work-summary.md`
- `docs/briefs/BRIEF-shirabe-artifact-decision-contract.md`
- `docs/briefs/BRIEF-shirabe-brief-skill.md`
- `docs/briefs/BRIEF-shirabe-charter-skill.md`
- `docs/briefs/BRIEF-shirabe-check-absorption.md`
- `docs/briefs/BRIEF-shirabe-child-dispatch-contract.md`
- `docs/briefs/BRIEF-shirabe-cli-multi-consumer.md`
- `docs/briefs/BRIEF-shirabe-comp-skill.md`
- `docs/briefs/BRIEF-shirabe-pattern-v1-ergonomics.md`
- `docs/briefs/BRIEF-shirabe-pattern-v1-workflow-friction.md`
- `docs/briefs/BRIEF-shirabe-scope-skill.md`
- `docs/briefs/BRIEF-shirabe-strategy-skill.md`
- `docs/briefs/BRIEF-transition-script-consolidation.md`
- `docs/briefs/BRIEF-upstream-link-legality.md`
- `docs/briefs/BRIEF-work-on-definition-of-done.md`
- `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md`
- `docs/decisions/DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06.md`
- `docs/decisions/DECISION-lifecycle-strict-mode-interface-2026-06-06.md`
- `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md`
- `docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md`
- `docs/decisions/DECISION-populate-issueless-default-2026-08-10.md`
- `docs/designs/current/DESIGN-completion-cascade.md`
- `docs/designs/current/DESIGN-decision-framework.md`
- `docs/designs/current/DESIGN-explore-adversarial-lead.md`
- `docs/designs/current/DESIGN-plan-review.md`
- `docs/designs/current/DESIGN-roadmap-issueless-preference.md`
- `docs/designs/current/DESIGN-shirabe-cli-rust-rewrite.md`
- `docs/designs/current/DESIGN-skill-extensibility.md`
- `docs/designs/current/DESIGN-vision-artifact-type.md`
- `docs/designs/current/DESIGN-work-on-efficiency.md`
- `docs/designs/current/DESIGN-work-on-koto-unification.md`
- `docs/guides/RELEASE-NOTES-artifact-decision-contract.md`
- `docs/guides/RELEASE-NOTES-populate-issueless-default.md`
- `docs/guides/coordinated-multi-repo.md`
- `docs/guides/doc-validation.md`
- `docs/guides/execute-friction.md`
- `docs/guides/koto-context-patterns.md`
- `docs/guides/lifecycle-posture.md`
- `docs/guides/multi-consumer-cli-contract.md`
- `docs/guides/release-adoption.md`
- `docs/plans/PLAN-work-on-friction-fixes.md`
- `docs/prds/PRD-artifact-traceability.md`
- `docs/prds/PRD-complexity-routing-expansion.md`
- `docs/prds/PRD-gha-doc-validation.md`
- `docs/prds/PRD-koto-adoption.md`
- `docs/prds/PRD-plan-skill-rework.md`
- `docs/prds/PRD-reusable-release-system.md`
- `docs/prds/PRD-roadmap-skill.md`
- `docs/specs/assumption-invalidation.md`
- `docs/specs/decision-points.md`
- `docs/specs/decisions-file-format.md`
- `docs/specs/research-artifact.md`
- `docs/specs/review-surface.md`
- `docs/spikes/SPIKE-claude-code-goal-integration.md`
- `docs/spikes/SPIKE-mermaid-parser.md`

## Step 2 -- Resolution and type pairing per edge

Resolution (what R6 tests today):

- `pass`: 76
- `FAIL-missing`: 5

The five non-resolving edges:

- `docs/briefs/BRIEF-cascade-outline-ac-completeness.md`:16 -> `docs/plans/PLAN-roadmap-plan-standardization.md` (FAIL-missing)
- `docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md`:22 -> `docs/designs/DESIGN-roadmap-plan-standardization.md` (FAIL-missing)
- `docs/briefs/BRIEF-lifecycle-passing-state-validation.md`:18 -> `docs/designs/DESIGN-roadmap-plan-standardization.md` (FAIL-missing)
- `docs/briefs/BRIEF-single-pr-plan-validation.md`:4 -> `docs/plans/PLAN-roadmap-plan-standardization.md` (FAIL-missing)
- `docs/briefs/BRIEF-table-diagram-reconciliation.md`:20 -> `docs/designs/DESIGN-roadmap-plan-standardization.md` (FAIL-missing)

Three of the five are the same **path typo**: `DESIGN-roadmap-plan-standardization.md`
lives at `docs/designs/current/`, not `docs/designs/`. The other two name
`docs/plans/PLAN-roadmap-plan-standardization.md`, which has never existed in the
tree. Note that even if all five paths were corrected to the real files, all five
would still be **type-pair-illegal** -- they are BRIEF docs naming a DESIGN or a
PLAN. A path fix does not fix the direction.

## Step 3 -- Candidate type-pair legality table

Table under test: PLAN->DESIGN, DESIGN->PRD, PRD->BRIEF, BRIEF->ROADMAP,
ROADMAP->STRATEGY, STRATEGY->VISION, VISION->nothing, COMP->nothing.
An edge whose target basename matches no known format prefix is UNCHECKED.

- **pass: 73**
- **fail: 8**
- **unchecked: 0**

Zero unchecked. Every edge in the corpus points at a recognizable artifact
basename, so the rule has an opinion on all 81 edges.

### The complete failing list

| Source doc | Line | Offending upstream value | Pair | Fails R6 today? |
|---|---|---|---|---|
| `docs/briefs/BRIEF-cascade-outline-ac-completeness.md` | 16 | `docs/plans/PLAN-roadmap-plan-standardization.md` | BRIEF->PLAN | yes |
| `docs/briefs/BRIEF-fc06-index-alias.md` | 20 | `docs/designs/current/DESIGN-roadmap-issueless-table-rendering.md` | BRIEF->DESIGN | **no** |
| `docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md` | 22 | `docs/designs/DESIGN-roadmap-plan-standardization.md` | BRIEF->DESIGN | yes |
| `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` | 18 | `docs/briefs/BRIEF-lifecycle-passing-state-validation.md` | BRIEF->BRIEF | **no** |
| `docs/briefs/BRIEF-lifecycle-passing-state-validation.md` | 18 | `docs/designs/DESIGN-roadmap-plan-standardization.md` | BRIEF->DESIGN | yes |
| `docs/briefs/BRIEF-single-pr-plan-validation.md` | 4 | `docs/plans/PLAN-roadmap-plan-standardization.md` | BRIEF->PLAN | yes |
| `docs/briefs/BRIEF-skill-cascade-lifecycle-check.md` | 24 | `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` | BRIEF->BRIEF | **no** |
| `docs/briefs/BRIEF-table-diagram-reconciliation.md` | 20 | `docs/designs/DESIGN-roadmap-plan-standardization.md` | BRIEF->DESIGN | yes |

**3 of the 8 are new signal** -- they resolve on disk, are git-tracked,
and pass `shirabe validate` cleanly today. They are the documents whose validate
result would change from clean to failing:

- `docs/briefs/BRIEF-fc06-index-alias.md` -> `docs/designs/current/DESIGN-roadmap-issueless-table-rendering.md` (BRIEF->DESIGN)
- `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` -> `docs/briefs/BRIEF-lifecycle-passing-state-validation.md` (BRIEF->BRIEF)
- `docs/briefs/BRIEF-skill-cascade-lifecycle-check.md` -> `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` (BRIEF->BRIEF)

Two of these three are BRIEF-names-BRIEF sibling links, which the type-pair table
has no entry for at all; the third is a BRIEF naming a DESIGN, a two-step
inversion. All three are genuine lineage errors, not false positives -- a BRIEF's
only legal upstream is a ROADMAP.

### What does *not* change

73 edges pass: all 38 DESIGN->PRD and all 35 PRD->BRIEF edges are legal,
as are none-of-the-above cases (there are none). The 68 docs with no `upstream:`
field are untouched. The single PLAN doc (`docs/plans/PLAN-work-on-friction-fixes.md`)
carries no `upstream:`, so the PLAN->DESIGN row of the table is exercised by
**zero** corpus edges.

## Step 4 -- Candidate lifecycle rule

Rule under test: a Durable-lifecycle document may not name a Working-lifecycle
document. Working = {ROADMAP, PLAN}; Durable = {VISION, STRATEGY, BRIEF, PRD,
DESIGN, COMP}.

- pass: 79
- **fail: 2**
- unchecked: 0

| Source doc | Line | Offending upstream value | Pair | Fails R6 today? |
|---|---|---|---|---|
| `docs/briefs/BRIEF-cascade-outline-ac-completeness.md` | 16 | `docs/plans/PLAN-roadmap-plan-standardization.md` | BRIEF->PLAN | yes |
| `docs/briefs/BRIEF-single-pr-plan-validation.md` | 4 | `docs/plans/PLAN-roadmap-plan-standardization.md` | BRIEF->PLAN | yes |

**Both lifecycle failures already fail R6.** The lifecycle rule, scored against
this corpus, finds **nothing R6 does not already flag** -- its marginal yield is
zero documents. On this evidence the lifecycle rule is not a substitute for the
type-pair rule: the type-pair rule finds 3 documents R6 misses, the lifecycle rule
finds 0. If the lifecycle rule is worth shipping, the case has to be made on
fixtures and future docs, not on the current tree.

Caveat worth stating in the PRD: the corpus contains no ROADMAP doc, so the
lifecycle rule's other half (a Durable doc naming a ROADMAP) is entirely
unexercised. The rule's real-world hit rate here is a floor, not an estimate.

## Step 5 -- Baselines (the 'before' to diff against)

### `./target/debug/shirabe validate --lifecycle . --mode=draft`

Exit code: **0**

```
::notice file=docs/briefs/BRIEF-upstream-link-legality.md::[L02] orphan BRIEF at status 'Accepted' (expected status 'Done', an Active ROADMAP upstream, or a tactical upstream/downstream chain link)
::notice file=docs/prds/PRD-koto-adoption.md::[L02] orphan PRD at status 'Accepted' (expected status 'Done', an Active ROADMAP upstream, or a tactical upstream/downstream chain link)
```

Two L02 orphan notices, both notice-level, exit 0.

### `./target/debug/shirabe validate docs/ --visibility=public`

Exit code: **0**. Output: **empty**.

This command **validates nothing**. `shirabe validate` takes files, not
directories: `run_validate` in `crates/shirabe/src/main.rs:601` calls
`detect_format(basename(path))` on each positional argument and `continue`s on
`None`. The basename `docs/` matches no format prefix, so the argument is
silently skipped and the run exits clean. Treating this as a green baseline
would be a mistake -- it is a no-op, not a pass.

### The real per-file baseline

Expanding the directory to its 149 tracked files:

```
shirabe validate --visibility=public $(git ls-files docs)
```

Exit code: **2** (error). 100 findings. Breakdown by code:

| Code | Count | Severity |
|---|---|---|
| FC10 (writing style) | 86 | notice |
| FC08 (mermaid legend) | 7 | notice |
| R6 (upstream resolves) | 5 | **error** |
| FC09 (PR context skip) | 1 | notice |
| FC15 (section order) | 1 | notice |

The five R6 errors are the only thing driving the non-zero exit:

```
::error file=docs/briefs/BRIEF-cascade-outline-ac-completeness.md,line=16::[R6] upstream "docs/plans/PLAN-roadmap-plan-standardization.md" does not exist on disk
::error file=docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md,line=22::[R6] upstream "docs/designs/DESIGN-roadmap-plan-standardization.md" does not exist on disk
::error file=docs/briefs/BRIEF-lifecycle-passing-state-validation.md,line=18::[R6] upstream "docs/designs/DESIGN-roadmap-plan-standardization.md" does not exist on disk
::error file=docs/briefs/BRIEF-single-pr-plan-validation.md,line=4::[R6] upstream "docs/plans/PLAN-roadmap-plan-standardization.md" does not exist on disk
::error file=docs/briefs/BRIEF-table-diagram-reconciliation.md,line=20::[R6] upstream "docs/designs/DESIGN-roadmap-plan-standardization.md" does not exist on disk
```

### Expected diff after the change

Under the type-pair rule, the per-file baseline gains findings on exactly three
documents that are clean today, and the whole-tree lifecycle run's exit status is
unaffected unless the new check is wired into the lifecycle walk as well.

| Doc | Today | Under type-pair rule |
|---|---|---|
| `docs/briefs/BRIEF-fc06-index-alias.md` | clean | fails (BRIEF names DESIGN) |
| `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` | clean | fails (BRIEF names BRIEF) |
| `docs/briefs/BRIEF-skill-cascade-lifecycle-check.md` | clean | fails (BRIEF names BRIEF) |
| `docs/briefs/BRIEF-cascade-outline-ac-completeness.md` | R6 error | R6 error + type-pair error |
| `docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md` | R6 error | R6 error + type-pair error |
| `docs/briefs/BRIEF-lifecycle-passing-state-validation.md` | R6 error | R6 error + type-pair error |
| `docs/briefs/BRIEF-single-pr-plan-validation.md` | R6 error | R6 error + type-pair error |
| `docs/briefs/BRIEF-table-diagram-reconciliation.md` | R6 error | R6 error + type-pair error |

Method note: the edge inventory was produced by an independent frontmatter
parser mirroring `upstream.rs` semantics (trim, angle-bracket placeholder skip,
`owner/repo:` cross-repo discriminator, scalar-never-split). It was cross-checked
against a raw scan of every frontmatter block: 90 docs contain the substring
`upstream` in frontmatter, 81 have an actual `upstream:` key, and the 9-doc
difference was verified by hand to be prose inside `problem:` / `outcome:` blocks.
The parser's R6 verdicts match the binary's exactly (5 findings, same files).

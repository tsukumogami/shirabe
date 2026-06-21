VERDICT: CONCERNS

## Findings

- **Design coverage (PASS):** All six DESIGN decisions map cleanly to issues and every issue traces back to a decision. D1 mode-aware targeting → Issue 1 (both single-pr adopt and coordinated worktree/coordination-branch-docs-only prose present). D6 template PR → Issue 2. D2 interactive-pause / `--auto`-finalizes → Issue 3. D3 docs-coverage → Issue 4 (design-format flag, plan Phase 3 emit, review-plan backstop, `/execute` no-content-gate all present). D4 finalization guard → Issue 5. D5 durable-capture convention → Issue 6. No orphan decision, no untraceable issue.

- **Atomicity (PASS):** Each issue is one cohesive slice with a single deliverable and a bounded `Files` set. Issue 4 spans four files (plan/design/review-plan/evals) but it is one logical change (the docs-coverage guarantee end-to-end) and is reasonable for one session. No issue bundles unrelated work.

- **Sequencing / dependencies (CONCERN — empty graph section):** The narrative edges are sound and acyclic: Issue 3 → blocked by Issue 2 is correct (the pause splits the `pr_finalization` edge that Issue 2 reshapes, so the title/two-part-body shape must settle first — this matches DESIGN Implementation Approach step 3 "depends on D6's `pr_finalization` shape being settled"). Issue 6 → blocked by 1,2,3,5 is correct as the doc-everything-it-describes terminal. Issues 1,2,4,5 independent is correct. **But the `## Dependency Graph` section (line 162) is empty** — no Mermaid block, no edges rendered. The sibling PLAN-work-on-friction-fixes.md carries a populated Mermaid `graph TD`. The edges live only in prose under "Implementation Sequence." This is a real completeness gap against the plan-doc convention.

- **Issue 6 dependency completeness (CONCERN — minor):** Issue 6's AC2 says it documents "mode-aware targeting, interactive-pause-vs-`--auto`, and the finalization guard usage" — i.e. behaviors from Issues 1, 3, and 5. Its dependency list is 1,2,3,5. Issue 2 (template PR) is included but Issue 6's stated doc surface does not actually cover the PR-template behavior, and Issue 4 (docs-coverage) is excluded. The 2-vs-4 choice is defensible (Issue 6 IS the docs item Issue 4's machinery demands, so it shouldn't block on the machinery), but listing Issue 2 as a blocker without documenting its behavior is a slight mismatch. Low severity; worth a one-line reconciliation.

- **Acceptance criteria (PASS):** ACs are specific and testable — byte-identical R7 parity injection, `exit:` UNSET suspension so R9 doesn't trip, 0/1/2 exit-code contract, `--body-file`/stdin not `-m`, seed-the-DESIGN-anchor-not-the-deleted-PLAN. Every issue's final AC updates `skills/.../evals/`, satisfying the Skill-Evals rule (CLAUDE.md line 218). Note: the Skill-Evals rule also requires *running* the evals via a `/skill-creator` agent before commit — the ACs say "updated" but none says "run and green." Minor; implementation-time concern, not a plan defect.

- **Scope-gate / docs coverage (PASS):** `user_visible_surface: true` is set on the DESIGN, and Issue 6 is the required docs item. Its AC2 explicitly covers mode-aware targeting, interactive-pause-vs-`--auto`, and finalization-guard usage — the three user-visible behaviors. The dogfood framing (this feature satisfies its own D3 rule) is correct.

- **Single-pr appropriateness (PASS):** Single-pr is right — all changes land in the shirabe repo as one cohesive feature with one coupling edge. The D5 cross-repo edit (workspace `CLAUDE.md` + dot-niwa-overlay) is correctly flagged in Issue 6 AC1 as "out-of-repo follow-up (not landable in the shirabe PR)," not smuggled into the PR. This is the correct handling and is consistent with the DESIGN's own framing.

- **Complexity / type (PASS):** All issues are `Type: docs` (skill/template/prose authoring) — correct, since every touched file is a skill markdown, koto-template, eval JSON, or CI YAML, with no Go/binary code (DESIGN confirms "no new binary code"). The classification is honest. No complexity field is rendered per-issue, but the horizontal single-slice framing makes each session-sized.

## Required changes

1. **Populate `## Dependency Graph`** (line 162) with the Mermaid `graph TD` block encoding the edges `I2 --> I3` and `I1,I2,I3,I5 --> I6`, matching the sibling-plan convention. The section currently renders empty.

2. **Reconcile Issue 6's dependency list with its doc surface:** either add coverage of the template-PR behavior (Issue 2) to AC2, or drop Issue 2 from the blocker list and justify the 1/3/5 set explicitly. State why Issue 4 is intentionally excluded (Issue 6 is the docs *output* of Issue 4's machinery, so it must not block on it).

3. **(Optional, low)** Add an AC clause to each issue that the updated evals are run green via a `/skill-creator` agent before commit, to fully satisfy the Skill-Evals rule rather than only its "updated" half.

## Summary

The decomposition is faithful to the DESIGN: all six decisions map to traceable, atomic, single-pr issues with specific testable ACs and correct out-of-repo handling of the D5 cross-repo edit. The blocking gap is the empty `## Dependency Graph` section — the edges exist only in prose, breaking the plan-doc convention. A secondary mismatch between Issue 6's blocker list and its documented surface warrants a one-line reconciliation. Fix the graph and the verdict flips to PASS.

# Clarity Review

**Verdict:** PASS

The PRD is clear, internally consistent, and holds WHAT/WHY altitude; the "ephemeral home" distinction is the spine of the document and is used coherently throughout, with only minor sharpenings worth making.

## Ambiguities Found

1. **R5 / R11 — "removes them before the home merges" vs. the coordinated done-signal.** R5 says /execute "removes them before the home merges" where the home is "the coordination pull request" for coordinated mode. R11 and R14 say the merge-last/coordination PR is "the single, non-bypassable done-signal." There is a sequencing question: if cleanup happens "before the home merges" and the coordination PR merging *is* the done-signal, when exactly does the wip/PLAN removal land relative to the merge-gate passing? A reader could interpret "the home" as the coordination PR or as each per-unit PR. -> Sharpen R5 to name which PR is "the home" in coordinated mode (the coordination/merge-last PR) and state that cleanup lands in that PR before it reaches ready/merge posture, consistent with R11's done-signal.

2. **R2 — "the re-evaluation boundary" exit name.** R2 binds three exit names to outcomes: "a completed run," "a forced-stop run," and "the re-evaluation boundary." The first two are described by their outcome; the third is named only abstractly and is not defined anywhere in the PRD. A reader cannot tell what the re-evaluation boundary *does* (re-evaluate what — the plan? upstream? the artifact altitude?). -> Add a clause naming what re-evaluation hands control back to (it appears to relate to the /scope resume-ladder redirect in the same requirement, but the link is left implicit).

3. **R8 vs. R12 — two different "upstream" operations sharing a word.** R8's upstream-drift gate ("brings the working state current against upstream and classifies the impact") uses "upstream" to mean the base branch / merge target. R12's finalization cascade ("BRIEF/PRD/DESIGN/ROADMAP transitions") uses "upstream" to mean the upstream artifact chain (the `upstream:` frontmatter lineage). Same word, two unrelated meanings, in adjacent requirements. -> Disambiguate: call R8's "upstream-drift" something like "base-branch drift" or qualify it, reserving "upstream chain" for R12's artifact lineage.

4. **R7 / Open Question — multi-pr execution path is stated as settled in R7 but reopened in Open Questions.** R7 states multi-pr plans "execute as independent per-issue /work-on runs ... with no plan-level coordinator involved." The Open Question asks "Whether /work-on grows a thin sequential milestone loop for multi-pr plans, or multi-pr issues are dispatched one at a time by the author with no loop at all." R7 reads as if the second option is already chosen ("no plan-level coordinator"), but the Open Question treats both as live. A reader cannot tell whether the milestone-loop option is still on the table. -> Reconcile: either soften R7 to acknowledge the loop-vs-no-loop question is open, or note that R7's "no plan-level coordinator" holds under either resolution (a thin /work-on milestone loop is not a plan-level coordinator).

5. **R4 wording for coordinated — "independent pull requests across repositories."** R4 describes coordinated as "independent pull requests across repositories walked in merge order," while R11/R14 introduce the "coordination pull request" as the home and done-signal. R4's phrasing omits the coordination PR, so coordinated reads as just "per-repo PRs," which undercuts the home distinction that R5/D2 rest on. -> Add the coordination PR to R4's one-line definition so the shape's ephemeral home is visible at the point the shape is first defined.

## Suggested Improvements

1. Define "session-scoped ephemeral home" once, explicitly, at first use (it first appears in the goals frontmatter and R4 before R5 defines it). A one-line gloss earlier would let R4 stand on its own.
2. R13 bundles three capabilities (crash-resumable setup, cross-branch/session resume, self-documenting PR body) under one number. Acceptance criteria test them separately. Consider splitting for cleaner traceability, or note the bundling is intentional.
3. The Known Limitations entry on the coordination contract exposing status "through a live merge-gate recompute rather than a structured per-node status surface" verges on HOW, but it is framed as a constraint /execute must work within, so it is acceptable at this altitude. No change required; flagging only.
4. "right-sized code-review panels" (R6) is a value term carried from prior context; a one-clause gloss would help a reader unfamiliar with /work-on internals.

## Writing Style

No banned words found (no tier/robust/leverage/comprehensive/facilitate). No emojis. No AI attribution. Prose is direct, varies sentence length, and uses the problem-as-problem framing (the Problem Statement states the coordinator gap and the manual-tracking cost, not a smuggled solution). The koto-or-not deferral (R17, D3, Out of Scope) is handled cleanly — capabilities are stated mechanism-neutrally and the mechanism is explicitly pushed to design without being accidentally mandated anywhere.

## Summary

The PRD is clear and consistent: the "ephemeral home" distinction is the document's organizing idea and is applied coherently across the problem statement, R4/R5, D2, and the coordinated-mode requirements, and the PRD holds WHAT/WHY altitude while deliberately and cleanly deferring the koto mechanism. The ambiguities found are local and fixable — a shared "upstream" word meaning two things (R8 vs R12), an undefined "re-evaluation boundary" exit, a cleanup-vs-done-signal sequencing question in coordinated mode, and an apparent R7/Open-Question tension on the multi-pr path. None rise to a single requirement having genuinely contradictory readings that would block design, so the verdict is PASS with recommended sharpenings.

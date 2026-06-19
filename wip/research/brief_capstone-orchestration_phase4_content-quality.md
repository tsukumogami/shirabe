# Content Quality Review

**Verdict:** PASS

The brief states a genuine recurring-toil problem, an outcome-shaped result, four distinct concrete journeys, a scope boundary that excludes things a reader would plausibly expect in, and open questions that genuinely defer to the PRD.

## Issues Found

None blocking. The brief clears all six criteria:

1. **Problem Statement** — states a problem (manual, re-typed, in-the-head cross-repo coordination), not a smuggled solution. It names the gap as "the absence of a durable, enforceable home for multi-repo coordination — not the absence of any one command," which deliberately avoids prescribing a mechanism. PASS.
2. **User Outcome** — outcome-shaped: framing and running state become "persisted and checkable rather than held in their head," and the effort is "legible from one place." The bullets describe behaviors the author experiences (express intent once, one PR per repo, derived merge order, merge-last done-signal), not a feature/flag list. The phrasing "as a flag, a short intent line, or a workspace default" enumerates possibilities without committing — correctly left open. PASS.
3. **Journeys are concrete** — each names a user, a trigger, and an outcome shape: author kicking off (invoke `/scope` once -> coordinating record seeded), author working the plan (`/work-on` per repo -> record index/order auto-updates), reviewer/future reader (opens coordinating PR -> sees whole effort from one place), completion (last PR merges -> record merges last as done-signal). PASS.
4. **Journeys are distinct** — two actor types (author, reviewer/maintainer), different entry-points (kickoff, execution, review/archaeology, completion), different outcomes. No overlap. PASS.
5. **Scope Boundary draws a real line** — OUT names things a reader would expect IN: cross-repo tracking architecture, merge-order representation, grouping-vs-merge-order acyclicity validation, atomicity reshaping, worktree internals, flag/frontmatter names, and the integration shape (modes vs flags vs orchestrator vs sub-skills). These are real exclusions a PRD/DESIGN reader would otherwise assume this brief settled. PASS.
6. **Open Questions defer to the PRD** — both (the "capstone" naming and the preference/intent boundary) are explicitly assigned to the PRD and flagged as settled-in-principle, so neither is a hidden blocker. PASS.

## Suggested Improvements

1. **"Capstone" term is used before it is grounded**: The title and In-scope bullets lean on "capstone" while Open Questions admits the name may not survive. A one-line gloss at first use in the Problem Statement (e.g. "the coordinating record we provisionally call the capstone") would spare a context-free reader the back-reference. Minor.
2. **In-scope visibility bullet is thin relative to its weight**: "Visibility-aware coordination across public and private repositories" is a notable constraint but gets one line, while the corresponding OUT exclusion doesn't address what visibility-awareness defers to DESIGN. Consider a matching OUT clause so the in/out pair is symmetric. Minor.
3. **Journey 2 has a long run-on sentence** (lines 98-100, "As those PRs open and merge...") that could be split for readability. Cosmetic.

## Summary

The brief passes content quality on all six axes: it frames a real recurring-coordination problem without smuggling a solution, an outcome about persisted/legible state, four distinct concrete journeys, and a scope boundary whose OUT list genuinely excludes architecture and requirements a reader might expect it to settle. The `/scope` + `/work-on` grounding reads naturally rather than bolted-on — the brief consistently frames the capstone as the multi-repo generalization of what those skills already do single-repo (the artifact chain and the shared-branch/merge-last cascade), and all three referenced SKILL.md files exist in the repo. Only minor polish items remain (early use of the provisional "capstone" term, a thin visibility bullet, one run-on sentence).

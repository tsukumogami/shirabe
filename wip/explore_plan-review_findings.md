# Exploration Findings: plan-review

## Core Question

What should an adversarial plan review skill look like — its review framework, loop-back
protocol, and wip/ artifact schema — so it can be both a required phase inside `/plan`
and a standalone callable skill, analogous to how `/decision` is called by `/design`?

## Round 1

### Key Insights

- **The adversarial framing is the core contribution** (AC quality lead): The existing Phase 6 asks "is this testable?" — discriminability asks "would this pass for the wrong implementation?" Seven failure patterns produce ACs that look valid but don't distinguish correct from incorrect implementations: fixture-anchored criteria, mock-swallowed dependencies, happy-path-only criteria, state-without-transition checks, integration scope gaps, interface name drift, and existence-without-correctness criteria. Most actionable automated checks: fixture-anchoring (flag ACs mentioning "all fixture" or "test data" without a clean-state scenario) and existence-only criteria (flag ACs with only "exists" or "is populated" without a content check).

- **Four categories close all three issue #19 failure modes** (review framework lead): A (Scope Gate): issue count vs. design complexity; B (Design Fidelity): whether the issue set inherits design contradictions — catches failure mode 1; C (AC Discriminability): the adversarial check — catches failure mode 2; D (Sequencing/Priority Integrity): whether must-run QA scenarios were deprioritized — catches failure mode 3. Category E (completeness beyond coverage) is conditional on design/prd input types only.

- **Loop-back is mechanically free** (loop-back lead): Deleting the right wip/ artifacts causes /plan's existing resume logic to re-enter at the correct phase automatically — no new resume infrastructure needed. Mapping is deterministic: design contradiction → Phase 1, coverage gap/atomicity → Phase 3, AC quality → Phase 4, dependency errors → Phase 5. Phase 4 uniquely supports partial loops (specific issue bodies without redoing decomposition).

- **Phase 7 is currently ungated** (loop-back lead): Phase 7 reads `wip/plan_<topic>_review.md` existence as a trigger but does not parse its verdict. If the review artifact persists through a loop-back, Phase 7 will fire incorrectly. Either the review artifact must be deleted on loop-back, or Phase 7 must add an explicit STOP condition on `verdict: loop-back`.

- **Two-consumer artifact problem** (artifact schema lead): /plan needs a routing layer (YAML frontmatter: `verdict`, `loop_target`, `critical_findings`) — terse and machine-readable. /work-on needs a context layer — narrative and per-issue. These should be distinct sections of the same artifact. /work-on integration is deferred (see Decisions).

- **The /decision sub-operation pattern is the right model** (artifact schema lead): `decision_result` YAML block shows how a sub-operation returns structured data to a parent. Review skill should emit an equivalent `review_result` block that /plan reads. This keeps routing logic in /plan and review logic in the review skill.

### Tensions

- **Flag failures vs. generate replacement ACs**: Generating replacements requires resolving design ambiguities that may be the actual root cause; if the upstream design contradicts itself, any generated replacement inherits that ambiguity. Flagging is safer but shifts correction to humans.

- **Delete artifact vs. gate Phase 7 on verdict**: Deleting the review artifact on loop-back is cleaner (existing resume logic handles re-entry) but loses round history. Keeping the artifact requires Phase 7 to parse the verdict field and adds a STOP condition. The current resume logic treats artifact existence as a Phase 7 trigger — so Phase 7 must be updated regardless.

- **Fast-path vs. full adversarial tier split**: The /decision two-tier model is directly applicable, but the research didn't settle which categories run in which tier, or whether "adversarial" means separate agents per category or a single agent with adversarial framing.

### Gaps

- **AC discriminability heuristics without running code**: Fixture-anchoring and existence-only checks are automatable. Semantic discriminability gaps require harder reasoning — open problem.
- **Review round limits**: No counter means the loop could run indefinitely. Mechanism not specified.
- **/work-on discovery problem**: deferred per decision below.

### Decisions

- /work-on Phase 0 integration deferred: unsolved discovery problem (issue number → review artifact path) and out-of-scope extension to extract-context.sh. Design doc scoped to /plan integration only.

### User Focus

Scope narrowed to /plan integration only. The two open design questions for the design doc to settle: (1) whether to delete the review artifact on loop-back or gate Phase 7 on its verdict; (2) the fast-path vs. full adversarial tier split for the two-tier execution model.

## Accumulated Understanding

The `/review-plan` skill sits between `/plan` (produces all issues) and `/work-on` (implements one issue at a time). Its job is to adversarially challenge the whole plan before any issue is implemented.

**What it must do:**
- Run four mandatory review categories (Scope Gate, Design Fidelity, AC Discriminability, Sequencing/Priority Integrity) that together close the three issue #19 failure modes
- Produce a machine-readable verdict artifact in wip/ with fields: `verdict: proceed | loop-back`, `loop_target`, `critical_findings`, `affected_issue_ids`
- Integrate into /plan as a required Phase 6 replacement, with loop-back capability to Phases 1, 3, 4, or 5
- Be callable standalone (full adversarial mode) or as a sub-operation by /plan (fast-path mode)

**How the loop-back works:**
- Each finding category maps deterministically to a loop target phase
- Deleting wip/ artifacts back to the loop target causes /plan's existing resume logic to re-enter at the correct phase automatically
- Phase 7 must be updated to gate on `verdict: loop-back` (currently ungated)

**Key open design decisions for the design doc:**
1. Delete review artifact on loop-back (cleaner resume) vs. keep it and gate Phase 7 on verdict field
2. Which review categories run in fast-path (single-agent, inside /plan) vs. full adversarial mode (multi-agent, standalone)
3. Whether to flag AC failures only or also generate replacement ACs

**Out of scope:** /work-on Phase 0 integration (deferred; discovery problem unsolved).

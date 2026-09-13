# Completeness Re-Review: PRD-work-on-standalone-completeness
## Verdict
PASS
## Prior findings — closed or not

**R21 acceptance criterion.** Closed. R21 ("Template authoring SHALL follow the repository's existing rules for gates and default actions, including the constraints its own linter imposes") now has a matching Acceptance Criteria bullet: "`scripts/validate-template-mermaid.sh`, `scripts/check-template-directives.sh` and `scripts/check-template-interpolation.sh` all pass against the edited templates (R21)." It names the exact validators and is binary/verifiable. No requirement is left without a criterion.

**BRIEF's third IN item ("where the shared cascade machinery lives").** Closed, and genuinely rather than cosmetically. R5a now requires that the location be "decided and recorded before implementation, not settled incidentally," and binds one constraint: the single-issue skill must not end up depending on the plan entry point. A new Decisions and Trade-offs entry ("The shared machinery must not invert the dependency direction") records that decision with real alternatives — duplicating the cascade logic (rejected: a 200-line script isn't the kind of one-line duplication the repo's drift-check pattern covers) and a shared template (rejected on a standing decision about template legibility) — and explicitly defers the literal directory to the design hop, naming the candidate (`scripts/`) without committing to it. An Acceptance Criteria bullet makes the constraint half checkable by grep.

I judge this the right altitude for a PRD, not a dodge. The BRIEF's own Status section says technical approach is the DESIGN's to settle, and "which directory a script lives in" is architecture. What a PRD can legitimately own is a constraint on that architecture (dependency direction) plus a forcing function that stops the decision from being made "incidentally by whoever writes the first caller" — which is exactly what R5a does. Answering the literal "where" in the PRD would itself be the content-boundary violation this same jury would otherwise have to flag. The alternatives-and-reasoning bar this section must clear is met in substance, not just in form.

## Per-criterion findings

1. **Required sections, in order.** Status, Problem Statement, Goals, User Stories, Requirements, Acceptance Criteria, Out of Scope all present in canonical order; Decisions and Trade-offs and Known Limitations follow as optional sections. Frontmatter `status: Draft` matches the body `## Status` value.

2. **BRIEF's six IN items.** All six map to at least one requirement: cascade reachability → R1–R5; obligations becoming gated → R6–R10; shared-machinery location → R5a; multi-pr migration → R14–R18; distinct child-suppression signal → R11–R12; obligations reachable by a child → R10. No IN item is silent.

3. **BRIEF's six OUT items.** All present in Out of Scope, each with the same reasoning as the BRIEF (cannot-verify config gap, missing staleness script, terminal-tick context loss, review-panel observability, naming fossils, merging the PR). The PRD adds a seventh exclusion (execution-mode enum, per R20) that the BRIEF didn't need because R20 is new; that's a legitimate addition, not scope drift.

4. **Three deferred Open Questions.** All three named in the BRIEF's Status section are closed under Decisions and Trade-offs, each with alternatives and reasoning: multi-pr-at-single-issue disposition (refuse with a pointer), no-anchor semantics (pass-through, cascade never invoked), and how the two contradicted documents are superseded (a decision record amending both, not in-place edits or a new disagreeing document).

5. **Goal/requirement traceability.** The four goal threads (mergeable-or-named-failure; obligations gated and child-reachable; plan cadence unchanged; plan entry point becomes the only plan runner) each have requirements behind them, and every requirement traces to one of the four except R22 (two-PR sequencing), which serves delivery process rather than a stated outcome — see Observations.

6. **Content boundaries.** Mostly clean. R5a/its Decision entry deliberately stop short of architecture, which is correct here. R22 (work SHALL land as two PRs, in a specific order) reads as implementation/decomposition guidance more than a product requirement, bordering on PLAN territory — noted, not blocking on its own.

7. **Out of Scope honesty.** Each exclusion is one a reader could plausibly assume in-scope (the two known-broken gates, the panel-observability gap, naming cleanup, merge itself) and each carries a reason, consistent with the quality bar.

## Required changes
None.

## Observations

- R22 (two-PR sequencing) is the one requirement that doesn't clearly serve a stated goal and reads closer to task breakdown than to a product requirement. It's minor and doesn't affect the document's completeness contract, but a design or plan document is the more natural home for delivery sequencing; worth a look in the next pass rather than a blocker now.
- R18 doesn't name the two contradicted documents by path inside this PRD (the BRIEF's References section does: PRD-execute-skill.md and DESIGN-execute-skill.md). This is defensible under the citation-not-restatement rule given the `upstream:` link, but an implementer who skips the BRIEF would have to hunt for which requirement and design option are being superseded.

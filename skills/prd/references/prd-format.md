# PRD Format Reference

Structure, lifecycle, validation rules, and quality guidance for Product
Requirements Documents.

## Table of Contents

- [Frontmatter](#frontmatter)
- [Required Sections](#required-sections)
- [Optional Sections](#optional-sections)
- [Content Boundaries](#content-boundaries)
- [Lifecycle](#lifecycle)
- [Validation Rules](#validation-rules)
- [Quality Guidance](#quality-guidance)

## Frontmatter

Every PRD begins with YAML frontmatter:

```yaml
---
status: Draft
problem: |
  1 paragraph: who is affected, what's broken or missing, why now.
goals: |
  1 paragraph: what success looks like at a high level.
upstream: docs/roadmaps/ROADMAP-<name>.md  # optional
source_issue: 123  # optional, GitHub issue number that triggered this PRD
---
```

Required fields: `status`, `problem`, `goals`. Optional: `upstream` (path to
parent artifact when this PRD is part of a larger effort), `source_issue`
(GitHub issue number that triggered this PRD). Each
field should be 1 paragraph using YAML literal block scalars (`|`). Frontmatter
status must match the Status section in the body -- agent workflows parse
frontmatter to determine lifecycle state, so divergence causes silent errors.

The frontmatter provides a self-contained summary so readers can assess relevance
without reading the full document, and enables agent workflows to extract key
info via simple regex.

## Required Sections

Every PRD has these sections in order:

1. **Status** -- current lifecycle state
2. **Problem Statement** -- who is affected, what the current situation is, why
   it matters now. States the problem, not a solution.
3. **Goals** -- what success looks like. High-level outcomes, not implementation.
4. **User Stories** -- concrete scenarios in "As a [who], I want [what], so that
   [why]" format. Use case descriptions are acceptable for technical features
   where user stories feel forced.
5. **Requirements** -- functional (what the system does) and non-functional (how
   well it does it). Each requirement should be specific and testable. Number
   them (R1, R2, ...) for cross-referencing.
6. **Acceptance Criteria** -- testable conditions that define "done." These are
   the contract: if all criteria pass, the feature is complete. Use checkbox
   format (`- [ ]`).
7. **Out of Scope** -- explicit boundaries. What this PRD deliberately excludes.

## Optional Sections

Include when relevant:

- **Open Questions** -- present only in Draft status. Things we don't know yet.
  Must be empty or removed before transitioning to Accepted.
- **Known Limitations** -- trade-offs, risks, and downsides the reader should
  know about. Captures constraints that don't fit in Out of Scope.
- **Decisions and Trade-offs** -- records requirements-level decisions made
  during drafting. Each entry captures what was decided, what alternatives
  existed, and why the chosen option won. Gives downstream consumers (design
  docs, plans) the reasoning behind requirements so they don't re-litigate
  settled questions.
- **Downstream Artifacts** -- added when downstream work starts. Links to design
  docs, plans, issues, or PRs that implement this PRD.

## Content Boundaries

A PRD does NOT contain:
- Technical architecture or design decisions (that's a design doc)
- Implementation approach or task breakdown (that's a plan)
- Code examples or API specifications (that's a design doc)
- Security analysis (that's a design doc)
- Competitive analysis (that's a separate artifact)

If you find yourself writing "how" instead of "what," the content probably
belongs in a downstream design doc.

## Lifecycle

```
Draft --> Accepted --> In Progress --> Done
```

| Status | Meaning | Transition Trigger |
|--------|---------|-------------------|
| Draft | Under development, may have open questions | Created by /prd |
| Accepted | Requirements locked, ready for downstream work | Human approval |
| In Progress | Being implemented via /design, /plan, or /work-on | Downstream workflow started |
| Done | Feature shipped, all acceptance criteria met | All downstream work complete |

**No "Superseded" state.** If requirements change fundamentally, create a new PRD
and mark the old one as Done (with a note that it was replaced).

### Transition Rules

- **Draft -> Accepted**: Open Questions section must be empty or removed. Human
  must explicitly approve.
- **Accepted -> In Progress**: A downstream workflow has started. Typically
  triggered by `/design <PRD-path>`, which reads the accepted PRD, synthesizes
  the problem into implementation terms, and transitions the PRD to "In Progress"
  (see the `design` skill's Phase 0 PRD mode).
- **In Progress -> Done**: All acceptance criteria are met. All downstream
  artifacts are complete.

## Validation Rules

### During /prd (drafting)
- Frontmatter has `status`, `problem`, `goals` fields
- Frontmatter status matches Status section in body
- All 7 required sections present and in order
- Status is "Draft"
- If Open Questions section exists, it may contain unresolved items
- If Decisions and Trade-offs section exists, it captures decisions from
  research and review -- each entry states the decision, the alternatives
  considered, and the reasoning behind the choice

### During /prd finalization (approval)
- Open Questions section must be empty or removed
- All acceptance criteria must be specific and testable
- Requirements must be numbered (R1, R2, ...)
- Status transitions to "Accepted" on human approval

### When referenced by /design or /plan
- Status must be "Accepted" or "In Progress"
- If status is "Draft": STOP and inform user the PRD needs approval first

## Quality Guidance

### Problem Statement
- States the problem, not a solution ("users can't X" not "we need feature Y")
- Identifies who is affected
- Explains why this matters now
- Specific enough to evaluate solutions against

### User Stories
- Each story covers a distinct scenario
- "As a [role]" identifies a real user type, not a generic "user"
- "So that [why]" connects to a meaningful outcome
- For technical features: use case descriptions are acceptable

### Requirements
- Each requirement is independently testable
- Functional requirements describe behavior, not implementation
- Non-functional requirements have measurable thresholds where possible
- Numbered for cross-referencing (R1, R2, ...)

### Acceptance Criteria
- Binary pass/fail -- no subjective judgment
- A developer who didn't write the PRD can verify each criterion
- Cover the happy path and important edge cases
- Don't duplicate requirements -- criteria verify that requirements are met

### Out of Scope
- Each exclusion is deliberate and explained
- Helps prevent scope creep during implementation
- References future work when applicable ("deferred to Feature N")

### Common Pitfalls
- Too broad ("Improve the app") -- narrow to a specific capability or user need
- Mixing "what" and "how" -- save technical decisions for design docs
- Subjective acceptance criteria -- every criterion must be verifiable
- Missing numbered requirements -- always use R1, R2, etc.

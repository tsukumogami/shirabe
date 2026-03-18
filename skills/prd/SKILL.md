---
name: prd
description: >-
  Structured workflow for creating and managing Product Requirements Documents (PRDs).
  Use this skill when writing new PRDs, reviewing or validating existing ones, or
  transitioning a PRD through its lifecycle (Draft -> Accepted -> In Progress -> Done).
  Trigger on prompts like: "write requirements for X", "define scope for Y", "draft a
  spec", "what should we build for Z", "I need a PRD", "validate this PRD", "mark this
  PRD as accepted", or any request to define WHAT to build and WHY before implementation
  begins. This skill drives a multi-phase workflow: conversational scoping, parallel
  research agents, structured drafting, and a 3-agent jury review.
argument-hint: '<topic or feature name>'
---

@.claude/shirabe-extensions/prd.md
@.claude/shirabe-extensions/prd.local.md

# Product Requirements Documents

PRDs capture WHAT to build and WHY -- the problem, goals, requirements, and
acceptance criteria. They complement design documents (which capture HOW) and
are the input for /design (which produces technical architecture).

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Structure

### Frontmatter

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
status MUST match the Status section in the body.

The frontmatter provides a self-contained summary so readers can assess relevance
without reading the full document, and enables agent workflows to extract key
info via simple regex.

### Required Sections

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

### Optional Sections

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

### Content Boundaries

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

## File Location

PRDs live at `docs/prds/PRD-<name>.md` (kebab-case). No directory movement
based on status -- all PRDs stay in `docs/prds/` regardless of lifecycle state.

## Downstream Routing

The PRD doesn't dictate the downstream path. The human and agent decide after
acceptance based on complexity:

| Complexity | Path |
|-----------|------|
| Simple | PRD -> plan -> implement |
| Medium | PRD -> plan -> implement |
| Complex | PRD -> design -> design doc -> plan -> implement |

When a design doc exists downstream, it references the PRD via `upstream` in
its frontmatter and skips problem framing.

## Repo Visibility

Before writing content, determine visibility:
- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

Public PRDs must not reference private artifacts.

---

## Creating a PRD

When invoked as `/prd`, this skill drives a structured creation workflow that
scopes the problem conversationally, fans out research agents, drafts the PRD
with thematic review, and validates through a jury review.

Unlike an explore workflow (which is open-ended and can produce any artifact type),
/prd always produces a PRD. Use /prd when you know you need requirements definition.
Use an explore workflow when you don't know what artifact type you need yet.

### Input Modes

From `$ARGUMENTS`:
1. **Empty** -- ask the user what feature or capability they want to specify
2. **Anything else** -- use as the starting topic for Phase 1 scoping

### Context Resolution

Detect visibility (Private/Public) from CLAUDE.md or repo path. Infer from
`private/` or `public/` in path if not explicit. Default to Private if unknown.

Log: `Specifying requirements with [Private|Public] visibility...`

### Workflow Phases

```
Phase 0: SETUP --> Phase 1: SCOPE --> Phase 2: DISCOVER --> Phase 3: DRAFT --> Phase 4: VALIDATE
(branch)          (conversational)   (agents fan out)     (iterative)        (jury review)
                       |                                       ^
                       |                                       |
                       +--- may loop back to DISCOVER or DRAFT-+
```

| Phase | Purpose | Artifact |
|-------|---------|----------|
| 0. Setup | Create feature branch | On `docs/<topic>` branch |
| 1. Scope | Conversational scoping with coverage tracking | Problem statement + research leads |
| 2. Discover | Parallel specialist agents investigate leads | Research findings in wip/ |
| 3. Draft | Produce PRD draft, surface open questions | Complete PRD draft |
| 4. Validate | 3-agent jury review | Validated PRD |

### Resume Logic

```
PRD exists with status "Accepted"                  -> Offer to revise or start fresh
PRD exists with status "Draft"                     -> Offer to continue from Phase 3
wip/research/prd_<topic>_phase2_*.md files exist   -> Resume at Phase 3
wip/prd_<topic>_scope.md exists                    -> Resume at Phase 2
On a branch related to the topic                   -> Resume at Phase 1
On main or unrelated branch                        -> Start at Phase 0
```

### Critical Requirements

- **Conversational First**: Phase 1 is a dialogue, not a form to fill out
- **Research Before Drafting**: Don't draft requirements you haven't investigated
- **User Review**: Never finalize a PRD the user hasn't reviewed and given feedback on
- **Jury Validation**: Phase 4 is not optional -- all PRDs get reviewed by 3 agents

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup**: Ensure work happens on a feature branch
   - If already on a branch that matches the topic, skip branch creation
   - If on `main` or an unrelated branch, create `docs/<topic>` (kebab-case)
   - If unsure whether the current branch is related, ask the user

1. **Scope**: Conversational scoping with coverage tracking
   - Instructions: `references/phases/phase-1-scope.md`

2. **Discover**: Parallel specialist agents investigate research leads
   - Instructions: `references/phases/phase-2-discover.md`

3. **Draft**: Produce PRD and walk through with user
   - Instructions: `references/phases/phase-3-draft.md`

4. **Validate**: Jury review and finalization
   - Instructions: `references/phases/phase-4-validate.md`

### Output

Final artifact: `docs/prds/PRD-<topic>.md` with status "Draft".

After completion:
1. Write PRD to `docs/prds/PRD-<topic>.md`
2. Commit to branch
3. Present PRD summary to user
4. If user approves: update status to "Accepted", commit, create PR
5. Present routing options based on complexity:

| Complexity | Suggestion |
|-----------|-----------|
| Simple (clear requirements, few moving parts) | plan skill |
| Medium (needs issue breakdown) | plan skill |
| Complex (needs technical design first) | design skill |

---

## Reference Files

| File | When to load |
|------|-------------|
| `references/phases/phase-1-scope.md` | Phase 1 |
| `references/phases/phase-2-discover.md` | Phase 2 |
| `references/phases/phase-3-draft.md` | Phase 3 |
| `references/phases/phase-4-validate.md` | Phase 4 |

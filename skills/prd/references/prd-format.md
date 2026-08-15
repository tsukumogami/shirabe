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
upstream: docs/briefs/BRIEF-<name>.md     # optional; nearest parent
                                          # produced above this PRD -- a
                                          # ROADMAP when no BRIEF was written
source_issue: 123  # optional, GitHub issue number that triggered this PRD
motivating_context: |                       # optional
  1 paragraph: why this PRD exists -- the situation or signal
  that triggered it. Distinct from `problem` (the gap) and from
  `goals` (the success shape).
---
```

Required fields: `status`, `problem`, `goals`. Optional: `upstream` (path to
parent artifact when this PRD is part of a larger effort; for cross-repo
upstream references and the visibility-direction rules, see
`${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md` -- Phase 3
step 3.1 validates this value),
`source_issue` (GitHub issue number that triggered this PRD; for a
public PRD, only public issue numbers belong here -- private repos'
issue numbers stay out of public PRD frontmatter),
`motivating_context` (1 paragraph naming the situation or signal
that triggered the PRD; reach for it when `problem` alone does not
convey why the PRD is being written now). Each
field should be 1 paragraph using YAML literal block scalars (`|`).

**Two written shapes are supported for `upstream:`.** A scalar -- the path
on the key's own line -- and a sequence, written either as `- ` entries on
the following lines or inline as `[<path>, <path>]`. Every entry of a
sequence is read, in written order, and a single-entry sequence is still a
sequence. Reach for the sequence when the document genuinely has more than
one parent; the scalar otherwise. Nothing else is supported: a scalar is
never split, so two paths on one line read as one entry that resolves to
nothing.

Frontmatter
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
  settled questions. **This section is also the conventional closure
  surface for an upstream BRIEF's Open Questions section** -- each
  deferred-to-PRD question lands as a recorded decision (or as an
  acknowledged remaining unknown) under Decisions and Trade-offs.
- **Downstream Artifacts** -- added when downstream work starts. Links to design
  docs, plans, issues, or PRs that implement this PRD.

## Citation vs Restatement

A PRD states its own problem in full: a reader landing on it cold
should grasp what's broken without opening the upstream BRIEF.
That obligation covers the Problem Statement, and stops there.

Everything else the upstream already says is **cited, not
restated**. Where an upstream BRIEF exists, its framing is carried
forward into the PRD's own sections (see
`skills/prd/references/phases/phase-3-draft.md`) rather than
summarized alongside them, and downstream artifacts cite this
PRD's requirement numbers rather than re-narrating the
requirements.

The two rules are not in tension once the scope is clear.
Restating the problem costs a reader one short section and buys
them a document that stands on its own; restating requirements,
journeys, or decisions costs them a second read of something they
can open, and creates a second copy that drifts.

## Content Boundaries

A PRD does NOT contain:
- Technical architecture or design decisions (that's a design doc)
- Implementation approach or task breakdown (that's a plan)
- Code examples or API specifications (that's a design doc)
- Security analysis (that's a design doc)
- Competitive analysis **as an artifact type** (that's a separate
  COMP artifact, private-only -- the structured market survey,
  competitor inventory, and comparative matrix belong in a
  COMP-*.md doc, not a PRD)

A PRD MAY briefly cite **competitive findings** (one or two
sentences) where they motivate a goal or constrain a requirement
-- e.g. "competitor X ships feature Y, which sets a floor on
discoverability". The distinction is altitude: a citation that
informs the WHAT belongs in the PRD; the structured analysis that
produces the citation belongs in a COMP. Public PRDs may cite
public findings; private competitive content stays in private
COMP docs.

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

These rules are mechanized: `shirabe validate` is the single authority and
this list references each check by code rather than restating it, so there is
one definition of each rule and nothing to drift. Run `shirabe validate
--check <CODE>` to evaluate one in isolation.

### During /prd (drafting)
- Required frontmatter fields are present (`FC01`)
- Frontmatter status matches the body Status section (`FC03`)
- Required sections are all present (`FC04`) and in canonical order (`FC15`)
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
- The PRD's chain posture is valid for the consuming step. The per-status
  stop table is enforced by the chain-status lifecycle check (`shirabe
  validate --lifecycle-chain <doc>`), which is the single authority for
  whether an upstream artifact is at a consumable status -- a Draft PRD that
  must be approved first surfaces there rather than being restated here.

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

## Contribution to the Chain

Every artifact type contributes one thing to the tactical chain, and a
document that absorbs an ancestor carries that ancestor's contribution
forward as a single section. This type's contribution is **WHAT — the requirements the feature must meet and the criteria that decide it is done**.

A survivor that absorbed a PRD carries it as `## Absorbed PRD`,
placed immediately after `## Status` and before the survivor's own first
other required section. Where a survivor carries more than one, they
appear in chain order. `shirabe validate` requires the sections a
document's `absorbed:` frontmatter implies (FC17), so this is enforced
rather than conventional.

**The contribution section has a two-sided adequacy test.** It is not
satisfied by presence:

- **Too long** if it reads as a rewrite of the absorbed document. The
  point of folding is compression; a section that reproduces the
  original has moved the document rather than distilled it.
- **Too thin** if a reader cannot follow *this* document's own argument
  without going and reading the absorbed one — which they cannot,
  because it is gone.

The second clause is the load-bearing one. It is phrased against the
survivor's own content rather than against an abstract standard of
sufficiency, so a one-line restatement of the topic fails it the moment
a later section leans on something the contribution never established.

What the machine can check is presence, ordering, and adjacency. Whether
the section actually carries the ancestor's contribution is a judgment,
made by the agent performing the fold against both documents while both
still exist.

A PRD can itself carry `## Absorbed Brief` when it absorbed its BRIEF.

**The absorbed case is an exception to the rule above.** A contribution
section carried under `absorbed:` restates material from a document that
no longer exists, which is the whole reason it is there. The
citation-not-duplication rule governs what this document says about
documents that are still on disk to be cited; it does not reach a
section whose subject was deleted by the fold that created it.

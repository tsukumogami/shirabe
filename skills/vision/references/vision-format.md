# Vision Document Format Reference

Structure, lifecycle, validation rules, and quality guidance for Vision
documents.

## Table of Contents

- [Frontmatter](#frontmatter)
- [Required Sections](#required-sections)
- [Optional Sections](#optional-sections)
- [Visibility-Gated Sections](#visibility-gated-sections)
- [Section Matrix](#section-matrix)
- [Content Boundaries](#content-boundaries)
- [Lifecycle](#lifecycle)
- [Validation Rules](#validation-rules)
- [Quality Guidance](#quality-guidance)

## Frontmatter

Every vision document begins with YAML frontmatter:

```yaml
---
status: Draft
thesis: |
  1 paragraph: the core belief about why this project/org should exist.
scope: org | project
upstream: docs/visions/VISION-<parent>.md  # optional, project-level only
---
```

Required fields: `status`, `thesis`, `scope`. Optional: `upstream`.

- **status** -- lifecycle state (Draft, Accepted, Active, Sunset)
- **thesis** -- the core bet, matching the Thesis section body
- **scope** -- `org` (why does this org exist) or `project` (why does this
  project exist within the org)
- **upstream** -- path to parent VISION when a project-level doc derives from
  an org-level one. Project-level only; omit for org-level.

Frontmatter status must match the Status section in the body -- agent workflows
parse frontmatter to determine lifecycle state, so divergence causes silent
errors.

## Required Sections

Every vision document has these sections in order:

1. **Status** -- current lifecycle state and any transition context
2. **Thesis** -- the core bet, written as a hypothesis ("We believe [audience]
   needs [capability] because [insight]"), not a problem statement
3. **Audience** -- who benefits, describing their current situation
4. **Value Proposition** -- category of value delivered, not features
5. **Org Fit** -- how this relates to the broader portfolio
6. **Success Criteria** -- project-level outcomes (adoption, ecosystem, quality
   signals), not feature acceptance criteria
7. **Non-Goals** -- what this project deliberately is NOT, each with reasoning

## Optional Sections

- **Open Questions** -- Draft status only. Must be resolved (section removed or
  emptied) before transitioning to Accepted.
- **Downstream Artifacts** -- added when downstream work (PRDs, designs, plans)
  starts. Lists paths to artifacts that depend on this VISION.

## Visibility-Gated Sections

Private repos only:

- **Competitive Positioning** -- market alternatives and differentiation
- **Resource Implications** -- investment required and opportunity cost

These sections must NOT appear in public repos. If present in a public repo
during validation, flag as an error.

## Section Matrix

| Section | Public | Private | Org | Project |
|---------|--------|---------|-----|---------|
| Status | Required | Required | Required | Required |
| Thesis | Required | Required | Required | Required |
| Audience | Required | Required | Required | Required |
| Value Proposition | Required | Required | Required | Required |
| Competitive Positioning | -- | Optional | Optional | Optional |
| Resource Implications | -- | Optional | Optional | Optional |
| Org Fit | Required | Required | Required | Required |
| Success Criteria | Required | Required | Required | Required |
| Non-Goals | Required | Required | Required | Required |
| Open Questions | Draft only | Draft only | Draft only | Draft only |
| Downstream Artifacts | When exists | When exists | When exists | When exists |

## Content Boundaries

VISION does NOT contain:

- **Feature requirements or user stories** -- belongs in a PRD
- **Feature sequencing or timelines** -- belongs in a Roadmap
- **Technical architecture decisions** -- belongs in a Design Doc
- **Implementation tasks** -- belongs in a Plan
- **Full competitive analysis** -- separate artifact; VISION can reference
  positioning but not duplicate analysis

If a VISION draft starts accumulating feature lists, user stories, or technical
decisions, those belong in downstream artifacts. Extract them into Open Questions
or Downstream Artifacts pointers.

## Lifecycle

### States

| State | Meaning |
|-------|---------|
| Draft | Under development. May have Open Questions. |
| Accepted | Thesis endorsed. Open Questions resolved. Ready for downstream work. |
| Active | Downstream artifacts (PRDs, designs) reference this VISION. |
| Sunset | Terminated -- abandoned, pivoted, or invalidated. Terminal state. |

### Transitions

All transitions are executed by `scripts/transition-status.sh`. The script
validates preconditions, updates status in both frontmatter and body, and
moves files between directories when status changes.

| Transition | Preconditions | Directory Movement |
|-----------|---------------|-------------------|
| Draft -> Accepted | Open Questions section empty or removed | None (stays in `docs/visions/`) |
| Accepted -> Active | At least one downstream artifact references this VISION | None (stays in `docs/visions/`) |
| Active -> Sunset | Reason provided (abandoned, pivoted, or invalidated) | Moves to `docs/visions/sunset/` |

**Script interface:**

```
scripts/transition-status.sh <vision-doc-path> <target-status> [superseding-doc]
```

When a superseding doc is provided, the script records `superseded_by` in
frontmatter and notes the successor in the Status section body.

**Forbidden transitions:**

- Draft -> Active (must accept first)
- Draft -> Sunset (delete instead -- unendorsed drafts don't need a paper trail)
- Active -> Accepted or Draft (regression)
- Sunset -> any (terminal, irreversible)

### Edit Rules

Active VISIONs can be edited in place for everything except the Thesis. A
Thesis change signals a project pivot -- create a new VISION and Sunset the
old one via the script with the superseding doc argument.

One Active VISION per project at a time.

### Directory Mapping

| Status | Directory |
|--------|-----------|
| Draft, Accepted, Active | `docs/visions/` |
| Sunset | `docs/visions/sunset/` |

## Validation Rules

- Frontmatter `status` must match the body Status section
- Draft: all 7 required sections present; Open Questions allowed
- Accepted: all 7 required sections present; Open Questions resolved (removed
  or empty)
- Active: same as Accepted, plus at least one Downstream Artifact entry
- Sunset: Status section includes reason (abandoned, pivoted, or invalidated)

## Quality Guidance

Each required section has specific quality criteria. Reviewers and authors
should check these during drafting and validation.

- **Thesis**: Must be a hypothesis, not a problem statement. Format: "We believe
  [audience] needs [capability] because [insight]." If it reads like "The problem
  is..." it's wrong. The thesis is a bet -- it can be invalidated.
- **Audience**: Describe the audience's current situation, not just a label.
  "Backend engineers at mid-size companies managing 10+ microservices" is better
  than "developers." Include what they do today and what friction they face.
- **Value Proposition**: State the category of value, not a feature list. "Reduce
  the operational burden of managing developer tool installations" not "provides
  a CLI with install, update, and remove commands." Think one level above features.
- **Org Fit**: Explain why HERE and not elsewhere. What makes this org/team the
  right one to pursue this? What existing capabilities or positioning does it
  build on? A VISION without org fit is just an idea.
- **Success Criteria**: Project-level outcomes, not feature acceptance criteria.
  Adoption rates, ecosystem signals, quality indicators -- things that validate
  the thesis. "10 recipes contributed by external users within 6 months" not
  "install command exits with code 0."
- **Non-Goals**: About identity, not scope. Each non-goal should explain WHY
  this project won't do something, tying back to the thesis. "Not a system
  package manager -- we target developer tools specifically because system
  packages have different reliability and permission requirements" not just
  "not a system package manager."
- **Competitive Positioning** (private only): Name alternatives and explain
  differentiation. Reference but don't duplicate full competitive analysis
  artifacts.
- **Resource Implications** (private only): Investment and opportunity cost.
  What are we NOT doing by pursuing this?

# DESIGN Format Reference

Structure, lifecycle, validation rules, and quality guidance for
DESIGN documents. DESIGNs capture HOW a feature is built -- the
technical approach, trade-offs, and architecture -- between the
upstream PRD (WHAT) and the downstream PLAN (which atomic issues).

## Table of Contents

- [Frontmatter](#frontmatter)
- [Required Sections](#required-sections)
- [Context-Aware Sections](#context-aware-sections)
- [Implementation Issues Ownership](#implementation-issues-ownership)
- [Content Boundaries](#content-boundaries)
- [Lifecycle](#lifecycle)
- [Validation Rules](#validation-rules)
- [Quality Guidance](#quality-guidance)

## Frontmatter

Every DESIGN document begins with YAML frontmatter:

```yaml
---
schema: design/v1
status: Proposed
problem: |
  1 paragraph: what technical problem this solves.
decision: |
  1 paragraph: what approach was chosen and key properties.
rationale: |
  1 paragraph: why this approach over alternatives.
upstream: docs/prds/PRD-<name>.md           # optional
spawned_from: docs/designs/DESIGN-<parent>.md  # optional
motivating_context: |                       # optional
  Why this design exists -- the situation or signal that
  triggered the work. Distinct from `problem` (which states the
  technical gap) and from `rationale` (which justifies the chosen
  approach against alternatives).
---
```

Required fields: `schema`, `status`, `problem`, `decision`,
`rationale`. Optional: `upstream`, `spawned_from`,
`motivating_context`.

- **schema** -- `design/v1`. Pins the artifact-type contract.
- **status** -- lifecycle state (`Proposed`, `Accepted`, `Planned`,
  `Current`, `Superseded`).
- **problem** -- the technical problem the design addresses, as 1
  paragraph using a YAML literal block scalar (`|`). The Context
  and Problem Statement body section elaborates the same content.
- **decision** -- the chosen approach and its key properties, as 1
  paragraph using `|`. Mirrors the Decision Outcome section.
- **rationale** -- why the chosen approach beats the alternatives,
  as 1 paragraph using `|`. Mirrors the Considered Options
  rejection logic.
- **upstream** -- path to the upstream PRD (or other parent
  artifact), repo-relative or cross-repo (`owner/repo:path`). Omit
  when no single upstream document exists, when the upstream is a
  private artifact a public DESIGN cannot name, or when Phase 0's
  cross-repo resolution returns "omit." See
  `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`.
- **spawned_from** -- path to a parent DESIGN this design was
  spawned from (the parent DESIGN's Phase 2 decision evaluation
  produced this child). Triggers parent-doc update behavior at
  Phase 6.8.
- **motivating_context** -- 1 paragraph naming the situation or
  signal that triggered the design. Optional; reach for it when the
  problem statement alone does not convey why the design exists
  *now*.

Frontmatter status must match the body `## Status` first line --
the validator's FC03 check compares the two case-insensitively
and the body's first non-blank line under `## Status` must be the
bare status word alone, prose pushed to a paragraph after a blank
line.

## Required Sections

Every DESIGN has these nine sections in order:

1. **Status** -- current lifecycle state. The first non-blank line
   is the bare status word alone; explanatory prose follows after a
   blank line.
2. **Context and Problem Statement** -- the technical landscape and
   the gap the design closes. Elaborates the frontmatter `problem`
   field.
3. **Decision Drivers** -- the constraints, requirements, and forces
   that shape the design space. Often numbered (D1, D2, ...) for
   cross-referencing.
4. **Considered Options** -- the alternatives evaluated. Each
   alternative is described with enough depth that a reader can
   understand what it proposed and why it was rejected. Rejected
   alternatives must NOT read as strawmen.
5. **Decision Outcome** -- the chosen approach. Mirrors the
   frontmatter `decision` field but with full prose elaboration.
6. **Solution Architecture** -- the technical structure: components,
   interfaces, data flow, key types. Diagrams welcome.
7. **Implementation Approach** -- the phased rollout plan. Names
   batches, sequencing, and the rationale for the chosen
   decomposition.
8. **Security Considerations** -- attack vectors considered,
   mitigations applied, residual risks accepted. "Not applicable"
   is a valid section content but must be justified.
9. **Consequences** -- positive consequences, negative consequences,
   and mitigations. Forces the design to be honest about its
   trade-offs.

## Context-Aware Sections

Some sections are conditionally required based on the design's
context. The validator does not enforce these (they are advisory),
but the Phase 6 structural-format reviewer flags missing
context-aware sections.

| Section | When required |
|---------|---------------|
| Market Context | When the design's decision space hinges on external products or industry conventions the reader needs to evaluate the choice. Public DESIGNs include this section sparingly (no competitive analysis -- COMP is the right artifact for that). |
| Required Tactical Designs | When this is a strategic-altitude DESIGN that decomposes into multiple tactical-altitude DESIGNs. Names the child DESIGNs and their scopes. |
| Upstream Design Reference | When the design lands as a child of a parent DESIGN (`spawned_from:` set in frontmatter). Names the parent and the slice this child operationalizes. |

The reviewer flags absence as an advisory; the author decides
whether the section is genuinely required.

## Implementation Issues Ownership

The Implementation Issues table is NOT owned by the DESIGN. It is
owned by the downstream PLAN, populated during the PLAN's Phase 7
(single-pr emission) or Phase 7 populate (multi-pr emission).

A DESIGN may reference the PLAN's table by anchor (`see
docs/plans/PLAN-<name>.md#implementation-issues`) or by file path,
but the DESIGN itself does not carry the table. The table's shape
contract lives in `skills/plan/references/plan-format.md`.

This separation is load-bearing: a DESIGN can land before a PLAN
exists, and the PLAN's table can change without forcing a DESIGN
revision. The DESIGN holds the architecture; the PLAN holds the
issue-level decomposition.

## Content Boundaries

A DESIGN does NOT contain:

- **Requirements articulation** -- belongs in the upstream PRD. The
  DESIGN cites requirements (R1, R2, ...) but does not introduce
  new ones.
- **Atomic issue decomposition** -- belongs in the downstream PLAN.
  The DESIGN names batches or phases; the PLAN names the issues
  within each.
- **Strategic justification** -- belongs in the VISION/STRATEGY.
  The DESIGN takes the strategic frame as given.
- **Competitive analysis as an artifact** -- belongs in a COMP
  (private only). A DESIGN may *cite* competitive findings briefly
  in Market Context, but the analysis itself lives in a COMP doc.

If a DESIGN draft starts introducing new requirements or atomic
implementation tasks, extract that content into the upstream PRD
or downstream PLAN and cite it.

## R25 wip-hygiene carve-out (inline clarification)

The wip-hygiene rule (`references/wip-hygiene.md`) forbids `wip/`
paths in committed prose. A DESIGN's references section, frontmatter
`upstream:`, and Implementation Approach must not point at `wip/...`
paths.

The single carve-out, per R25: a DESIGN that documents the
wip-hygiene rule itself, or quotes the rule in prose form, may name
`wip/` as a string in that prose. The validator and the Phase 6
reviewer distinguish path-shaped references (`see wip/foo.md`)
from rule-statement prose (`wip/ artifacts are tolerated on the
branch but...`). Path-shaped references fire; rule-statement prose
is acceptable.

The carve-out exists because the workspace-wide wip-hygiene rule
itself must be documentable somewhere, and the documentation
necessarily uses the literal string `wip/`. The Phase 6 reviewer's
grep step (`git grep -nE 'wip/' -- docs/designs/...`) catches
path-shaped references; the reviewer confirms each match is
rule-statement prose.

## Lifecycle

### States

| State | Meaning |
|-------|---------|
| Proposed | Under development. Decision Outcome may be tentative. |
| Accepted | Approved by the author. Ready for PLAN authoring. |
| Planned | A PLAN has been authored against this DESIGN. |
| Current | The PLAN has shipped. The DESIGN documents the current architecture. |
| Superseded | Replaced by a successor DESIGN. The frontmatter names the successor. |

### Transitions

All transitions are executed by `shirabe transition`. Most
transitions hold the DESIGN in `docs/designs/`; the `Planned ->
Current` transition moves the file to `docs/designs/current/`.

| Transition | Preconditions | Directory Movement |
|-----------|---------------|-------------------|
| Proposed -> Accepted | Phase 6 jury all-PASS + human approval | None |
| Accepted -> Planned | A PLAN names this DESIGN as `upstream:` | None |
| Planned -> Current | The PLAN has shipped (all issues done) | Move to `docs/designs/current/` |
| any -> Superseded | A successor DESIGN names this one as `superseded_by:` | None; the doc stays where it is |

The directory move on `Planned -> Current` is load-bearing: it
distinguishes designs that documented historical decisions from
designs that document the current architecture. A reader scanning
`docs/designs/current/` sees only currently-applicable designs.

## Validation Rules

`shirabe validate` recognizes `DESIGN-*.md` files by longest-prefix
match and runs FC01-FC04 plus the Phase 6 jury's discretionary
checks. The `design/v1` FormatSpec declares:

- **Required fields:** `status`, `problem`, `decision`, `rationale`.
- **Valid statuses:** `Proposed`, `Accepted`, `Planned`, `Current`,
  `Superseded`.
- **Required sections:** Status, Context and Problem Statement,
  Decision Drivers, Considered Options, Decision Outcome, Solution
  Architecture, Implementation Approach, Security Considerations,
  Consequences.
- **Issues table columns:** (none -- DESIGN does not carry an
  Implementation Issues table; the downstream PLAN owns that).

The validator-side contracts:

- **FC01** -- required fields present.
- **FC02** -- status is in the valid enum.
- **FC03** -- frontmatter status matches body `## Status` first
  line.
- **FC04** -- all nine required sections present.
- **FC15** -- the required sections appear in the canonical order above.

Phase 6 jury reviewers add discretionary rubric coverage:

- **Architecture reviewer** -- architecture clarity, missing
  components, sequencing, simpler alternatives.
- **Security reviewer** -- attack vectors, mitigations, residual
  risk.
- **Structural-format reviewer** -- artifact-shape conformance
  against this format reference (section presence and order,
  frontmatter field order, R19 budget-vs-spec sub-rubric).

## Quality Guidance

### Context and Problem Statement

- States a technical problem, not a smuggled solution. "The
  validator silently skips files with unknown schemas" is a
  problem; "we should add a SCHEMA-MISSING notice" is a solution.
- Stands alone. A reader landing on the DESIGN cold should grasp
  what's broken without reading the upstream PRD.

### Decision Drivers

- Numbered (D1, D2, ...) for cross-referencing. The Considered
  Options section will reference drivers to explain why
  alternatives were rejected.
- Each driver is a real force constraining the design space, not a
  generic best-practice phrase. "Must preserve FC03 backward
  compatibility for v0.6 binaries" is a driver; "should be
  maintainable" is filler.

### Considered Options

- Each rejected alternative has genuine depth. A reader of just the
  rejection should understand what the alternative proposed and why
  it was rejected -- the rejection cites real weaknesses traced to
  the Decision Drivers, not surface-level dismissals.
- The chosen option is named in this section too (briefly), with
  the full elaboration in Decision Outcome.

### Decision Outcome

- Mirrors the frontmatter `decision` field. Divergence between the
  prose Decision Outcome and the YAML field signals one is stale.
- Names the key properties of the chosen approach in enough detail
  that a downstream PLAN author can decompose without re-reading
  Considered Options.

### Solution Architecture

- Concrete enough that a reader can sketch the implementation. Names
  the components, the interfaces, the data flow.
- Diagrams are welcome but not required. Prose can carry the
  architecture if it is precise.

### Implementation Approach

- Names the batches or phases of the rollout. Decomposition
  rationale (horizontal/vertical/walking skeleton) goes here.
- Sequencing is explicit. "Batch 1 unlocks Batch 2 because X" is
  better than "ship in order."

### Security Considerations

- Names the attack vectors considered. "Not applicable" is valid
  but must be justified (e.g., "the validator runs only on local
  files in CI; there is no remote attack surface").
- Mitigations cite real defenses, not generic boilerplate.

### Consequences

- Positive consequences are specific and concrete.
- Negative consequences are honest. A DESIGN with no negative
  consequences is hiding them.
- Mitigations are paired with each negative consequence.

### Common Pitfalls

- **Prose on the `## Status` first line.** Most common FC03
  failure. The first non-blank line under `## Status` must be the
  bare status word alone.
- **Strawman alternatives.** Rejected options described in two
  sentences with "this doesn't work because we don't want it"
  rejection logic. The Phase 6 strawman check catches this.
- **Drifting into PRD altitude.** A DESIGN that introduces new
  requirements has climbed up; extract those into the upstream PRD.
- **Carrying the Implementation Issues table.** The table lives in
  the downstream PLAN. A DESIGN holding the table fights the
  validator's table-ownership contract.
- **Path-shaped wip/ references.** The wip-hygiene rule forbids
  `wip/` paths in committed prose. Rule-statement prose is OK; path
  references are not (R25 carve-out clarification above).

# Lead 2: Output Format Mapping

Research for /explore decision-making-skill-impact, Round 1.

## Source Formats Analyzed

Three formats produce decision-related content today:

1. **Decision skill output** (proposed): Context, Decision, Rationale, Alternatives Considered, Assumptions
2. **Design doc Considered Options** (considered-options-structure.md): Per-decision context paragraphs, Chosen approach (detailed), Alternatives with rejection rationale
3. **Explore ADR** (phase-5-produce-deferred.md): Context, Decision, Options Considered (per-option trade-offs), Consequences

Plus the design doc's **Decision Outcome** section which synthesizes across decisions: Summary (unified narrative), Rationale (why the combination works).

## Field-by-Field Mapping

| Decision Skill Field | Design Doc Location | ADR Location | Notes |
|---------------------|-------------------|--------------|-------|
| Context | Decision N: opening paragraphs (1-3 paras explaining the question) | ## Context | Direct mapping. Design version is scoped to one question; ADR version covers the whole situation. |
| Decision | Decision N > "#### Chosen: [Name]" + detailed description | ## Decision | Design version includes full implementation detail. ADR is a single clear statement. |
| Rationale | Embedded in chosen description ("why it fits the decision drivers") + Decision Outcome > Rationale | Absent as standalone section -- folded into Options and Consequences | Design doc splits rationale: per-decision rationale is inline, cross-decision rationale is in Decision Outcome. ADR has no explicit rationale section. |
| Alternatives Considered | "#### Alternatives Considered" with per-alternative rejection reasons | ## Options Considered (per-option subsections with trade-offs) | Design doc format is compact (1-2 sentences + rejection). ADR gives each option a full subsection. Decision skill needs to support both densities. |
| Assumptions | **No explicit location** | **No explicit location** | Neither format has a dedicated assumptions section. This is a gap. |

## Gaps Identified

### Gap 1: Assumptions have no home

The decision skill explicitly captures assumptions -- things believed true but not verified that underpin the decision. Neither the design doc nor the ADR format has a dedicated assumptions field.

Current design docs handle assumptions implicitly:
- Decision context paragraphs sometimes state constraints that are actually assumptions
- "Acknowledge uncertainty" guidance in considered-options-structure.md says to note "we believe X but haven't validated Y" -- but this is advice, not a structural slot
- Decision Outcome rationale mentions "constraints that shaped the approach" which may include assumptions

Without a structural slot, assumptions get scattered or lost entirely.

### Gap 2: Consequences exist in ADR but not in decision skill output

The ADR has a ## Consequences section ("what becomes easier, what becomes harder"). The decision skill output doesn't include consequences as a named field. The design doc has a top-level ## Consequences section, but it covers the entire design, not individual decisions.

### Gap 3: Rationale granularity differs

The decision skill has a single Rationale field. The design doc splits rationale into two layers:
- Per-decision: why this option beats alternatives (inline in Chosen section)
- Cross-decision: why the combination works (Decision Outcome > Rationale)

The ADR has no explicit rationale section at all.

### Gap 4: Detail density varies by consumer

Design doc's Chosen section needs enough detail that "a reader understands the approach without reading the alternatives." ADR's Decision section is "one clear statement." The decision skill needs to produce content at the higher density and let consumers compress.

## Proposed Canonical Decision Report Structure

A structure that serves both standalone ADRs and embedded design doc sections with zero information loss:

```
### Decision: [Topic]

**Context**
[Why this decision matters, what forces are at play, what constraints
shape the answer. 1-3 paragraphs.]

**Assumptions**
[Beliefs held true but not validated. Bulleted list. Each assumption
states what breaks if it's wrong.]

**Chosen: [Name]**
[Full description of the selected approach. Detailed enough to
understand without reading alternatives.]

**Rationale**
[Why this option. Ties back to context and decision drivers.
Acknowledges accepted trade-offs.]

**Alternatives Considered**
[Per-alternative: description + rejection reason tied to context.]

**Consequences**
[What changes. What becomes easier, what becomes harder.]
```

### Mapping to consumers

**As standalone ADR:** Use as-is. The structure maps 1:1 to `docs/decisions/ADR-<topic>.md`. Frontmatter extracts `decision` from the Chosen section and `rationale` from the Rationale section.

**As design doc Considered Options entry:** Embed under `### Decision N: [Topic]`. The Context becomes the opening paragraphs. Chosen and Alternatives map directly to `#### Chosen` and `#### Alternatives Considered`. Rationale stays inline. Assumptions become a brief note within Context or a bulleted addendum after Context. Consequences roll up into the design doc's top-level ## Consequences section.

**As explore crystallize output:** When explore crystallizes to "Decision Record," it invokes the decision skill (or produces this structure directly). The output IS the ADR -- no adapter needed.

## Convergence with Explore ADR

The current ADR template in phase-5-produce-deferred.md is close but missing two fields:

| Canonical Field | Current ADR Status |
|----------------|-------------------|
| Context | Present (## Context) |
| Assumptions | **Missing** |
| Decision (Chosen) | Present (## Decision) |
| Rationale | **Missing as standalone** -- scattered across Options and Consequences |
| Alternatives | Present (## Options Considered) but uses subsections instead of compact format |
| Consequences | Present (## Consequences) |

To converge: add Assumptions and Rationale sections to the ADR template. This makes the ADR template a direct serialization of the canonical structure, and explore's "produce Decision Record" phase becomes "serialize the canonical decision report to ADR format."

## Where Assumptions Should Live

Three options evaluated:

### Option A: Dedicated Assumptions section in both formats

Add `## Assumptions` (ADR) or a bulleted assumptions block after Context (design doc). Explicit, searchable, impossible to miss during review.

Downside: adds structural weight. Design docs with 3-5 decisions each listing assumptions get verbose.

### Option B: Fold into Context with structural markers

Keep assumptions in the context paragraphs but require a specific pattern: "This decision assumes [X]. If [X] is false, [consequence]." Lightweight, doesn't add sections.

Downside: assumptions are harder to scan, easier to skip during cross-decision validation.

### Option C: Assumptions subsection within Context

A middle ground: Context paragraph(s) followed by a bulleted "Key assumptions:" list still within the Context block. No new top-level section, but assumptions are visually distinct.

**Recommendation: Option C for design doc embedding, Option A for standalone ADRs.**

Standalone ADRs are single-decision documents where a dedicated section adds clarity without bloat. Design docs have multiple decisions, so a compact inline format prevents repetitive section headers. The canonical structure uses Option A (full section), and the design doc adapter compresses to Option C.

This also enables the multi-decision cross-validation use case from Lead 4: after all decisions complete, assumption lists from each decision can be extracted and checked against peer decisions' chosen approaches. A structural slot (even compact) makes extraction reliable.

## Summary

The canonical decision report structure adds two fields the current formats lack (Assumptions, per-decision Consequences) and elevates Rationale from implicit to explicit. It maps to both the ADR template and design doc Considered Options with well-defined compression rules. The key insight is that the decision skill should produce at maximum detail density, and consumers (ADR serializer, design doc embedder) compress to fit their context.

# Security Review: DESIGN-vision-artifact-type

## Review Scope

Full review of the Security Considerations section against the design's
decisions, architecture, data flow, and implementation approach. Compared
against security sections in peer designs (DESIGN-skill-extensibility,
DESIGN-decision-framework, DESIGN-plan-review, DESIGN-reusable-release-system).

## Assessment of "N/A" Justification

The design marks Security Considerations as "N/A" with three supporting
claims:

1. No external inputs downloaded, executed, or processed
2. No new filesystem/network/process permissions beyond what /explore has
3. Only reads wip/ files that existing handlers already read

**Verdict: The N/A is defensible but incomplete.** The claims are factually
correct -- this design adds markdown templates and scoring table entries, not
executable code or new data sources. However, the section undersells one area
that peer designs do address, and misses a second that is genuinely applicable.

## Attack Vectors Considered by the Design

The design explicitly addresses:

- **No new trust boundaries**: Correct. The produce handler reads the same
  wip/ files as existing handlers with no new input sources.
- **Visibility gating follows existing pattern**: Correct. Design Doc's
  Market Context and Competitive Analysis use the same private-repo
  restriction.

## Attack Vectors NOT Considered

### 1. Visibility Gate Bypass (Low severity, applicable)

The design introduces visibility-gated sections (Competitive Positioning,
Resource Implications) that must be suppressed in public repos. The gating
mechanism is described as: the produce handler "reads the Visibility section
from wip/explore_<topic>_scope.md."

This is an LLM-instruction-level control, not a programmatic enforcement.
The scope file is written by the same LLM session in Phase 0. If Phase 0
writes an incorrect visibility value, or the scope file is manually edited
between phases, the handler could populate private-only sections in a public
repo's VISION doc.

**Existing mitigations (not stated in design):**
- The CLAUDE.md hierarchy already declares repo visibility, so Phase 0 has
  a reliable source of truth
- PR review catches leaked private content before merge
- This is the same risk profile as existing visibility-gated sections in
  other artifact types

**Why this should be mentioned:** Peer designs (DESIGN-skill-extensibility)
explicitly call out the trust model for extension files even when the risk
is low. The visibility gate is the one place in this design where incorrect
behavior could expose competitive or resource information in a public repo.
A single sentence acknowledging the reliance on scope file accuracy and PR
review as backstop would bring this in line with peer design practice.

**Severity: Low.** The output is a markdown file committed to a feature
branch, not an automated deployment. PR review is a reliable second gate.

### 2. Scoring Manipulation via Prompt Injection (Very low severity, marginal)

The crystallize framework scores artifact types using signal/anti-signal
tables interpreted by the LLM. VISION adds 8 signals and 7 anti-signals.
If an exploration topic were crafted to trigger VISION signals (e.g., a topic
framed as "should we build X?" when the real intent is feature requirements),
the framework could misroute to VISION instead of PRD.

This is not a security vulnerability in the traditional sense -- it's a
correctness concern. The design already mitigates it heavily: VISION has the
most anti-signals (7) of any type, and the tiebreaker rules provide
unambiguous disambiguation. This vector does not need to be in the Security
section, but it's worth noting for completeness.

### 3. Sensitive Content in Thesis Field (Not applicable)

The thesis field is a 1-paragraph hypothesis statement. It doesn't contain
secrets, credentials, or PII by design. The frontmatter is YAML but parsed
only by the LLM for display/validation -- not by a YAML parser that could
be exploited. Not a concern.

## Sufficiency of Mitigations for Identified Risks

The design identifies no risks and therefore proposes no mitigations. For
the visibility gate bypass identified above, the existing mitigations
(CLAUDE.md visibility declaration + PR review) are sufficient. No additional
mitigation is needed beyond documentation.

## Residual Risk Assessment

**No residual risk requiring escalation.** The design is pure document
templating with no executable components, no external data, and no new
permissions. The visibility gate concern is low-severity with adequate
existing controls.

## Comparison to Peer Designs

| Design | Security Approach | New Trust? |
|--------|-------------------|------------|
| skill-extensibility | Detailed: extension file trust, .local.md, supply chain | Yes |
| decision-framework | Itemized: no secrets, auto-approve, agent permissions | Marginal |
| plan-review | Brief: local filesystem only, no new permissions | No |
| reusable-release-system | Detailed: token scope, permission model | Yes |
| **vision-artifact-type** | **N/A** | **No** |

The plan-review design is the closest peer -- it also adds no new trust
boundaries and keeps a brief security section. But even plan-review writes
a positive statement ("operates entirely within the local filesystem")
rather than "N/A." The vision design would benefit from the same approach:
a brief positive statement rather than a blanket N/A.

## Recommendations

1. **Replace "N/A" with a brief positive statement.** Even when risk is
   genuinely minimal, peer designs write 2-3 sentences confirming what was
   considered. Suggested:

   > This design adds document templates, a scoring table entry, and a
   > produce handler. It introduces no new permissions, external inputs, or
   > dependencies beyond what /explore already requires. The visibility-gated
   > sections (Competitive Positioning, Resource Implications) rely on the
   > scope file's Visibility field, written from CLAUDE.md's declared repo
   > visibility; PR review serves as backstop against incorrect gating.

2. **No additional mitigations needed.** The existing controls (CLAUDE.md
   visibility source, PR review, heavy anti-signal count) are proportionate
   to the risk profile.

3. **No escalation needed.** All identified concerns are low or very low
   severity with adequate existing controls.

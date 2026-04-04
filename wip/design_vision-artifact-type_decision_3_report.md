<!-- decision:start id="vision-lifecycle-transitions" status="assumed" -->
### Decision: VISION Lifecycle Transition Rules

**Context**

VISION has a unique lifecycle among artifact types in the system. While PRDs end at "Done" and Design Docs reach "Current" or "Superseded," a VISION stays Active indefinitely because a project's strategic thesis doesn't "complete." The four states (Draft, Accepted, Active, Sunset) are settled. What remained open: the exact triggers for each transition, whether Active VISIONs can be edited in place, whether Sunset can be reversed, and whether VISION needs a separate Superseded state alongside Sunset.

Existing artifact patterns provide strong precedent. PRD and Design Doc both require human approval for their first transition (Draft/Proposed -> Accepted) and use downstream artifact events for subsequent transitions. Every terminal state in the system (PRD's Done, Design Doc's Superseded, Decision Record's Deprecated) is irreversible.

**Assumptions**

- VISIONs are infrequent enough (1-3 per project lifetime) that all-human transitions are acceptable. Automation adds complexity for minimal benefit at this frequency.
- Downstream skills (/prd, /design) will eventually validate that a referenced upstream VISION is Accepted or Active, not Draft. Until that enforcement exists, the human is responsible for not referencing Draft VISIONs.
- The Thesis section is a reliable proxy for "project identity changed." If this proves too coarse or too fine in practice, the boundary can be adjusted without changing the lifecycle states themselves.

**Chosen: Human-Gated Transitions with Thesis-Boundary Edits**

All VISION lifecycle transitions are human-triggered. The five sub-questions resolve as follows:

**1. Draft -> Accepted trigger:** Human approval. The Open Questions section must be empty or removed before transition. This matches PRD and Design Doc exactly. No automated component -- the human reviews the thesis, audience, value proposition, org fit, and success criteria, then marks the VISION as Accepted.

**2. Accepted -> Active trigger:** Human marks the VISION as Active when downstream work begins (first PRD drafted, first repo created, first design doc started). This is NOT automated. While PRD's Accepted -> In Progress is triggered by /design reading the PRD, VISION's transition is too infrequent and too important to automate. The human should consciously acknowledge that the project is now underway and the VISION is its strategic anchor.

**3. In-place edit semantics:** Active VISIONs can be edited in place for everything except the Thesis section. Success criteria adjustments, non-goal additions, audience refinements, org fit updates -- all fine. If the Thesis itself changes, that signals a project pivot, and the correct action is a new VISION with the old one transitioned to Sunset ("superseded by VISION-X"). The Thesis is the identity. Changing it means a different project.

**4. Sunset reversibility:** Sunset is irreversible. No other terminal state in the system can be reversed (Design Doc Superseded, PRD Done, Decision Record Deprecated). If a Sunset VISION's project is revived, create a new VISION. The new VISION can reference the old one and reuse content, but it gets its own lifecycle. This prevents ambiguity about which VISION is authoritative and maintains clean audit trails.

**5. Superseded vs Sunset:** No separate Superseded state. Sunset covers all three termination scenarios (abandoned, pivoted/superseded, invalidated) via prose in the Status section. When one VISION supersedes another, the old VISION's Status section reads "Sunset: superseded by VISION-X.md" with a link. This is adequate because (a) a project typically has one Active VISION at a time, making lookup trivial, and (b) adding a sixth state for a rare edge case increases state machine complexity without proportional value.

**Summary of the complete transition table:**

| Transition | Trigger | Automated? | Preconditions |
|-----------|---------|-----------|---------------|
| Draft -> Accepted | Human approval | No | Open Questions empty/removed |
| Accepted -> Active | Human marks Active | No | Downstream work has begun |
| Active -> Sunset | Human decision | No | One of: abandoned, pivoted, invalidated |
| Draft -> (deleted) | Human decides to abandon | No | Only for unmerged/unwanted drafts |

**Forbidden transitions:**

| Forbidden | Why |
|-----------|-----|
| Draft -> Active | Must be endorsed (Accepted) before becoming strategic anchor |
| Draft -> Sunset | Delete unendorsed drafts instead of preserving them |
| Active -> Accepted | Regression -- downstream work exists |
| Active -> Draft | Regression -- published anchor can't revert to proposal |
| Sunset -> any | Terminal state, irreversible |

**Rationale**

Human-gated transitions are the right choice for a document type created a handful of times per project. The cost of forgetting to mark a VISION as Active is low (it's a status label, not a gate for other workflows), while the cost of false automation is high (a VISION accidentally marked Active before anyone endorsed it would undermine the endorsement step). The Thesis boundary for in-place edits provides a clear, meaningful bright line: the thesis IS the project's identity, so changing it means a new identity, which means a new VISION. This is more principled than a mechanical rule (like "frontmatter fields are immutable") and more enforceable than pure judgment ("edit if the change feels small enough").

Irreversible Sunset and consolidated terminal states (no separate Superseded) keep the model simple. Decision Records have Deprecated AND Superseded because individual technical decisions are often revisited. Project-level strategic theses are not -- a project that pivots has genuinely become something different, and a new VISION captures that cleanly.

**Alternatives Considered**

- **Semi-Automated Transitions with Frontmatter-Boundary Edits**: Automated Accepted -> Active when /prd reads an upstream VISION. Rejected because the automation is complex to implement (cross-skill state mutation), covers a rare event (VISION transitions happen a few times per project), and removes the human's conscious acknowledgment that the project is underway. The frontmatter edit boundary is more mechanical but less meaningful than the Thesis boundary.

- **Human-Gated Transitions with Reversible Sunset**: Allows Sunset -> Active reversal for projects that are shelved then revived. Rejected because no other artifact type has a reversible terminal state, creating inconsistency. It also creates ambiguity when a VISION was Sunset as "superseded by VISION-X" -- reversing the Sunset means two VISIONs claim to be the strategic anchor. Creating a new VISION for revival is cleaner and provides a fresh audit trail.

**Consequences**

What becomes easier:
- Lifecycle is simple enough to reason about without consulting documentation
- Terminal state semantics are consistent across all artifact types
- The Thesis boundary gives a concrete, explainable rule for when to create a new VISION vs edit

What becomes harder:
- Humans must remember to mark VISIONs as Active manually (no automation safety net)
- Projects that are temporarily shelved then revived require creating a new VISION rather than flipping a flag
- The Thesis boundary may sometimes be ambiguous (is rewording the thesis for clarity a "change"?)

What changes:
- VISION is the only artifact type where ALL transitions are human-triggered (PRD and Design Doc have at least one automated transition)
- Sunset is the first terminal state that explicitly documents its reason via prose rather than state name (unlike Design Doc's Superseded which is self-explanatory)
<!-- decision:end -->

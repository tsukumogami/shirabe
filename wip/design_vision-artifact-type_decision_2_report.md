<!-- decision:start id="vision-crystallize-integration" status="assumed" -->
### Decision: How VISION integrates into the crystallize framework

**Context**

The crystallize framework scores artifact types using signal/anti-signal tables and a
demotion rule (any type with 1+ anti-signals ranks below all types with 0 anti-signals).
VISION is being added as the sixth supported type. The exploration established that
tactical scope must suppress VISION, and the open question was the mechanism: should
tactical scope be a pre-filter that removes VISION from the candidate list before scoring,
or a regular anti-signal that participates in the existing demotion rule?

The constraint is explicit: no structural changes to the scoring mechanism. The framework's
evaluation procedure (Step 1: score, Step 2: rank and demote, Step 3: tiebreakers,
Step 4: fallback) must remain intact.

**Assumptions**

- The demotion rule will remain absolute (1 anti-signal demotes below all clean types).
  If the demotion rule is later softened to a penalty rather than absolute demotion,
  the tactical anti-signal's suppression effect weakens. This would need revisiting but
  is unlikely given the rule's central role in the framework.
- No other future type will need scope-based gating at the type-selection level. If one
  does, the anti-signal pattern repeats per type, which is straightforward.

**Chosen: Anti-Signal**

Tactical scope is added as VISION's seventh anti-signal: "Scope is tactical (override or
repo default)." It participates in the standard scoring procedure identically to every
other anti-signal. When tactical scope is active, the demotion rule in Step 2 pushes
VISION below all types that scored without anti-signals, regardless of how many VISION
signals fired.

The full VISION integration into the crystallize framework:

*Signal/anti-signal table* -- 8 signals, 7 anti-signals:

| Signals | Anti-Signals |
|---------|-------------|
| Project doesn't exist yet (no repo, no codebase, no prior art in the org) | Project already exists and the question is about its next feature or iteration |
| Exploration centered on "should we build this?" not "what should it do?" | Requirements or user stories emerged during exploration (route to PRD) |
| Org fit, strategic alignment, or ecosystem positioning was the core question | A PRD, design doc, or roadmap already covers this project |
| Thesis validation or falsification was the exploration's primary output | Single coherent feature emerged from exploration (route to PRD) |
| Multiple fundamentally different project directions are still viable | Specific users and their needs are already identified (project is past VISION stage) |
| Target audience or user base is not yet well-defined | Exploration reached a negative conclusion -- the project should NOT exist (route to Rejection Record) |
| The core question is "should this project exist and what would it offer?" | Scope is tactical (override or repo default) |
| Exploration produced strategic justification or positioning arguments | |

*Tiebreaker rules* (4 new entries for Step 3):

1. **VISION vs PRD:** Does the project exist yet? No (no repo, no codebase, no prior implementation) -> VISION. Yes -> PRD. Requirements are premature when the project's existence is unjustified.
2. **VISION vs Roadmap:** Is the question "should we do this at all?" or "what sequence do we do things in?" Existence -> VISION. Sequence -> Roadmap.
3. **VISION vs Rejection Record:** Is the overall conclusion "proceed" or "don't proceed"? Proceed -> VISION. Don't proceed -> Rejection Record.
4. **VISION vs No Artifact:** Does anyone else need to see the strategic argument? Yes (multiple stakeholders, budget, org-level decision) -> VISION. No (one person, quick action) -> No Artifact.

*Disambiguation rule* (1 new entry):

**Exploration surfaced both strategic justification AND feature requirements.** VISION comes first. Strategic justification must be accepted before requirements are worth writing. Recommend VISION with a note that a PRD should follow once the VISION is accepted.

*Step 1* expands from five to six supported types. Steps 2-4 are unchanged.

**Rationale**

The anti-signal approach satisfies every stated constraint. It requires zero structural
changes to the evaluation procedure -- tactical scope is just another row in a table,
processed by the same scoring and demotion logic that handles all other types. The
demotion rule makes it functionally equivalent to a pre-filter: VISION cannot win when
tactical scope fires, because any type without anti-signals outranks it automatically.

The anti-signal approach also provides better observability. When the framework scores
six types and VISION appears as "demoted (tactical scope)," a reader understands why
VISION was suppressed. A pre-filter silently removes VISION, leaving no trace in the
output. In the edge case where every other VISION signal fires but scope is tactical,
the anti-signal approach surfaces this tension; the pre-filter hides it.

The project-existence test as the primary discriminator between VISION and PRD was
validated through hypothetical scoring across six scenarios in the architecture research.
All scenarios produced correct results with the proposed signal table.

**Alternatives Considered**

- **Pre-Filter:** Remove VISION from the candidate list before scoring when scope is
  tactical. Rejected because it introduces a new structural concept (candidate filtering
  by scope) that doesn't exist in the current framework, violating the "no structural
  changes" constraint. Its only advantage -- cleaner output with 5 types instead of 6 --
  doesn't justify the added mechanism, and it reduces observability by hiding the
  suppression reasoning.

- **Hybrid (pre-filter + anti-signals):** Use a pre-filter for tactical scope and keep
  content-based anti-signals for other suppression. Rejected because it combines both
  mechanisms' costs (structural changes + table complexity) without proportional benefit.
  The conceptual separation of "preconditions vs evidence" is cleaner in theory but
  harder to explain and maintain in practice, and the anti-signal approach alone handles
  both concerns through a single mechanism.

**Consequences**

The crystallize framework gains a sixth supported type with the most anti-signals of any
type (7, compared to 3-4 for existing types). This heavy anti-signal count is intentional:
VISION has more ways to be the wrong choice than existing types because it occupies a
narrow niche (pre-project strategic artifacts). The demotion rule amplifies each
anti-signal's effect, making false-positive VISION recommendations rare.

Tactical scope suppression is now a documented, scored property rather than a hidden
filter. If the framework later needs scope-based gating for other types (e.g., Roadmap
restricted to strategic scope), the pattern is established: add scope as an anti-signal
in that type's table. No new infrastructure needed.

The VISION vs PRD boundary is anchored on project existence -- a binary, easy-to-evaluate
test. This makes the tiebreaker rule the most deterministic of any pair in the framework.
<!-- decision:end -->

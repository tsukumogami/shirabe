# Crystallize Decision: vision-doc-workflow

## Chosen Type
Roadmap

## Rationale

The exploration expanded from "add a VISION type" to "define the complete strategic-to-tactical pipeline." Round 2 revealed multiple independent, sequenceable features: VISION artifact type, Roadmap creation workflow, traceability improvements, complexity routing expansion, and pipeline documentation. No single coherent feature emerged — this is a portfolio of related improvements that need sequencing by value and dependency.

Roadmap is the natural vessel: it sequences multiple features, each of which will need its own PRD or design doc downstream. The existing ROADMAP-artifact-workflow-redesign.md in the private tools repo followed this same pattern (Features 1-7, each with its own PRD/design). This is effectively the next phase of that same initiative.

## Signal Evidence

### Signals Present
- **Multiple features to sequence**: VISION type, Roadmap creation, traceability fixes, complexity routing, pipeline docs — five independent work items
- **Portfolio-level planning**: cross-cutting initiative affecting /explore, /design, /plan, and artifact schemas
- **The core question is "what's next?"**: the what is understood from Round 1 and 2 research; the question is ordering and dependencies

### Anti-Signals Checked
- **Single feature**: Not present — five distinct features identified
- **Deep technical question**: Not present — the approach is clear for each feature
- **No clear deliverables**: Not present — each feature has concrete outputs

## Alternatives Considered
- **PRD**: Ranked lower — multiple independent features with independently-shippable steps (strong anti-signals). Each feature will get its own PRD, but the portfolio needs a Roadmap first
- **Design Doc**: Not appropriate — no architectural decisions remain; the integration patterns are established
- **Plan**: No upstream artifact to decompose yet; the Roadmap IS the upstream that Plans will consume
- **No Artifact**: Disqualified — many decisions and a complete pipeline model need permanent documentation

# Decision Report Format

The canonical output format for the decision skill. A superset of the decision
block format that includes full detail from the 7-phase evaluation process.

## Structure

```markdown
<!-- decision:start id="<topic>" status="confirmed" -->
### Decision: <Topic>

**Context**
<Why this decision matters, what forces are at play, what constraints
shape the answer. 1-3 paragraphs.>

**Assumptions**
- <Belief held true but not verified. States what breaks if wrong.>
- <Another assumption>

**Chosen: <Name>**
<Full description of the selected approach. Detailed enough to understand
without reading alternatives.>

**Rationale**
<Why this option. Ties back to context and decision drivers. Acknowledges
accepted trade-offs.>

**Alternatives Considered**
- **<Alt 1>**: <description>. Rejected because <reason>.
- **<Alt 2>**: <description>. Rejected because <reason>.

**Consequences**
<What changes as a result. What becomes easier, what becomes harder.>
<!-- decision:end -->
```

## Required Fields

All six fields are required in decision reports (unlike decision blocks where
only Question, Choice, and Assumptions are mandatory):

| Field | Purpose |
|-------|---------|
| Context | Why the decision matters, forces at play |
| Assumptions | Beliefs held true but not verified |
| Chosen | The selected option with full description |
| Rationale | Why this option won |
| Alternatives Considered | Each option with rejection reason |
| Consequences | What changes, positive and negative |

## Input/Output Contracts

### Input contract (from parent skill)

```yaml
decision_context:
  question: "Which cache invalidation strategy?"
  prefix: "design_foo_decision_1"
  options:
    - name: "TTL-based"
      description: "..."
  constraints:
    - "Must support < 100ms latency"
  background: |
    The system currently uses...
  complexity: "standard"  # standard | critical
```

### Output contract (returned to parent)

```yaml
decision_result:
  status: "COMPLETE"
  chosen: "TTL-based"
  confidence: "high"
  rationale: "..."
  assumptions:
    - "Redis cluster remains available"
  rejected:
    - name: "Event-driven"
      reason: "Adds infrastructure dependency for marginal gain"
  report_file: "wip/design_foo_decision_1_report.md"
```

## How to Render as Considered Options

When a design doc consumes a decision report, map fields as follows:

| Report Field | Design Doc Location |
|-------------|-------------------|
| Context | Opening paragraphs under `### Decision N: <Topic>` |
| Assumptions | Bulleted "Key assumptions:" list within Context |
| Chosen | `#### Chosen: <Name>` with full description |
| Rationale | Inline in Chosen section, tied to decision drivers |
| Alternatives | `#### Alternatives Considered` with per-alt rejection |
| Consequences | Roll up into design doc's top-level `## Consequences` |

The adapter runs in the design skill's cross-validation phase (Phase 3), not
in the decision skill. The decision skill produces the canonical format; the
design skill transforms it.

## How to Render as ADR

When the report serializes to `docs/decisions/ADR-<topic>.md`:

| Report Field | ADR Section |
|-------------|-------------|
| Context | `## Context` |
| Assumptions | `## Assumptions` (dedicated section) |
| Chosen | `## Decision` |
| Rationale | `## Rationale` |
| Alternatives | `## Options Considered` with per-option subsections |
| Consequences | `## Consequences` |

Frontmatter extracts `decision` from Chosen and `rationale` from Rationale.

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

### Undecided report

When the evidence does not settle the question (no option is a clear winner,
or a fact the choice rests on could not be found) and nobody can be asked,
the decision ends undecided instead of choosing. The report keeps the same
delimiters with `status="undecided"`, holds no Chosen section, and says what
would settle it:

```markdown
<!-- decision:start id="<topic>" status="undecided" -->
### Decision: <Topic>

**Context**
<Why this decision matters, what forces are at play. 1-3 paragraphs.>

**Question**
<The one question someone has to answer, in a sentence.>

**Recommendation: <Name>**
<The option the evidence leans toward, and why. A recommendation, not a
choice: nothing downstream treats it as decided.>

**Alternatives Considered**
- **<Alt 1>**: <description>. <Why it is still in play, or why not.>
- **<Alt 2>**: <description>. <Why it is still in play, or why not.>

**What Would Settle It**
<The fact someone could look up, or the answer someone could give, that
would make one option the clear choice.>
<!-- decision:end -->
```

The undecided report's fields are Context, Question, Recommendation,
Alternatives Considered (each with a reason) and What Would Settle It, all
required. It carries no Chosen, Rationale or Consequences, since nothing was
chosen. `skills/decision/scripts/check-undecided.sh <session> <report_key>`
checks a handed-back report and its question against this shape.

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
  session: "design-foo"                     # the parent's koto session
  key_dir: "work/decision-1"                # where the decider keeps its intermediates
  report_key: "work/decision_1_report.md"   # where it writes this report
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
  report_key: "work/decision_1_report.md"
```

An undecided decision returns `status: "UNDECIDED"` instead, with the
question the caller raises:

```yaml
decision_result:
  status: "UNDECIDED"
  question: "Which licence should the package be published under?"
  recommendation:
    name: "MIT"
    reason: "Matches the licence of the two libraries it wraps"
  alternatives:
    - name: "MIT"
      reason: "Matches the wrapped libraries; permissive"
    - name: "Apache-2.0"
      reason: "Adds a patent grant the wrapped libraries do not carry"
  missing: "Whether the owner wants a patent grant on this package"
  attempt: "design-foo:000000000007"        # the undecided attempt, <session>:<id>
  question_key: "work/decision-1/question.json"
  report_key: "work/decision_1_report.md"
```

`question_key` holds the question in the form `shirabe question raise`
takes (`context`, `problem`, `question`, two to four `options` each with a
`label` and a `reason`, the recommendation first). The caller raises it from
the session the attempt is recorded in, adding `ground` and `waiting` if it
has them; the rest comes from the decider unchanged. A caller handed
`UNDECIDED` writes no chosen option and no assumption for that question,
finishes the decisions that do not depend on it, and stops before the phase
that needs the answer. When the answer arrives it writes the answer as the
choice, citing it.

A decision settled provisionally in an unattended run (see
`references/question-procedure.md`, Cheap or costly) stays
`status: "COMPLETE"` and adds `provisional: true` and `attempt`. Its block is
written `status="assumed"`.

An undecided run removes none of its intermediate keys: the research stays
readable for whoever answers the question and for the run that resumes after
the answer.

The report and every intermediate are keys in the named koto session, per
`references/skill-session-convention.md`: a parent reads the report with
`koto context get <session> <report_key>`. A direct `/decision` run keeps them
in its own session, `decision-<topic>`, with the report at `work/report.md`.

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

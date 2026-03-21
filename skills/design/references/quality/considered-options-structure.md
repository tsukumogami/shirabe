# Considered Options and Decision Outcome Structure

Detailed templates for writing design document decision sections.

## Considered Options

Organized by decision question. Each question gets full context, then the chosen
approach described in detail, followed by alternatives with rejection rationale.

```markdown
## Considered Options

### Decision 1: [Topic]

[1-3 paragraphs explaining the question: what needs to be decided,
why it matters, how it connects to the broader design, what constraints
shape the answer. A reader should understand why this question exists
before seeing any options.]

#### Chosen: [Name]

[Detailed description of the selected approach. Cover how it works,
why it fits the decision drivers, key implementation details, and
trade-offs accepted. This should be thorough enough that a reader
understands the approach without reading the alternatives.]

#### Alternatives Considered

**[Alternative A]**: [1-2 sentences describing the approach.]
Rejected because [specific reason tied to decision drivers or constraints].

**[Alternative B]**: [1-2 sentences describing the approach.]
Rejected because [specific reason].

### Decision 2: [Topic]

[Same structure: context paragraphs, chosen approach, alternatives]
```

### Key Principles

- Each alternative must be genuinely viable (no strawmen)
- Rejection rationale should be specific, not just "less good"
- Acknowledge uncertainty ("we believe X but haven't validated Y")
- If only one option makes sense, explain why alternatives were rejected
- A single-decision design uses the same structure, just one `### Decision` heading

### When to Split Into Multiple Decisions

- Multiple independent questions (e.g., runtime management AND isolation mechanism)
- Each question has its own set of viable alternatives
- Options for one question don't affect options for another

## Decision Outcome

The Decision Outcome section serves two purposes: (1) explain the unified approach
as prose, and (2) give enough concrete detail that a developer understands the full
scope of work without reading Solution Architecture.

```markdown
## Decision Outcome

**Chosen: 1B + 2A**

### Summary

[2-3 paragraphs describing the unified approach and what needs to be
built. Don't list each decision separately -- weave them into a coherent
narrative. A reader should understand both the approach AND the scope
of work without knowing the option labels.

Cover:
- How the decisions fit together as one approach
- What the main components/changes are
- How they interact with each other
- Key constraints, timeouts, error handling
- Edge cases the implementation must handle

Write as if explaining to a developer who will implement this.
Concrete details (specific fields, exit codes, thresholds) are good.]

### Rationale

[Explain why these decisions work together as a combination. Focus on:
- How the decisions reinforce each other
- Key trade-offs accepted
- Constraints that shaped the approach

Don't rehash why individual alternatives were rejected -- that's
already inline in Considered Options. This section is about why
the combination works.]
```

### Good Summary Example

> We're restructuring the workspace into per-component subdirectories
> and removing all deprecated tooling in the same migration. The install
> script copies source files to each repo's `.claude/` directory,
> expanding path placeholders to absolute paths. Each component gets
> its own subdirectory under the workspace root.
>
> This works because the migration is a clean break -- there's no
> backwards compatibility to maintain for deprecated code while
> simultaneously moving to a new directory layout. The one thing we do
> preserve is the workspace root variable, since existing scripts depend
> on it and there's no reason to break that contract.

### Bad Summary Example

> We chose 1B (component subdirectories), 2A (keep workspace variable),
> and 3A (hard removal). This combination gives us the best balance of
> simplicity and maintainability.

### Good Summary Characteristics

- A developer can read it and understand the full scope without reading Solution Architecture
- Mentions specific technical details (field names, exit codes, retry counts)
- Explains how components interact, not just what they are individually
- Covers edge cases and error handling, not just the happy path

# Decision Block Format

Structured records for decisions made during workflow execution. Used by both
the lightweight decision protocol (inline in wip/ artifacts) and the heavyweight
decision skill (as the core of decision reports).

## Delimiters

Decision blocks use HTML comment delimiters for machine extraction:

```markdown
<!-- decision:start id="cache-strategy" status="confirmed" -->
### Decision: Cache invalidation strategy

**Question:** Which cache invalidation strategy for the API layer?

**Evidence:** Current system uses TTL-based caching. Event bus exists but
adds 8ms latency. Consistency requirements are eventual (30s acceptable).

**Choice:** TTL-based with 30-second expiry

**Alternatives considered:**
- Event-driven: adds infrastructure dependency for marginal consistency gain

**Assumptions:**
- 30-second staleness is acceptable for all current API consumers
- Event bus latency won't improve enough to change the calculus

**Consequences:** Simpler to operate. Accepts brief staleness windows.
<!-- decision:end -->
```

## Delimiter Attributes

| Attribute | Required | Values | Purpose |
|-----------|----------|--------|---------|
| `id` | Yes | kebab-case, unique within artifact | Cross-referencing, invalidation targeting |
| `status` | Yes | `confirmed`, `assumed`, `escalated` | Review triage |

## Required Fields

Every decision block must include:

- **Question**: one sentence stating what's being decided
- **Choice**: what was selected
- **Assumptions**: beliefs held true but not verified (may be empty list)

## Optional Fields

Include when non-trivial:

- **Evidence**: what information informed the choice
- **Alternatives considered**: other options with rejection rationale
- **Consequences**: what changes as a result
- **Reversibility**: how hard it is to undo (low/medium/high)

## Compact Variant

For simple decisions where the full format adds more noise than value:

```markdown
<!-- decision:start id="branch-name" status="confirmed" -->
**Decision:** Branch `feat/parser` -- follows existing `feat/<component>`
convention. Assumes no parallel parser work.
<!-- decision:end -->
```

Collapses all fields into 1-2 sentences. Use when the choice clears the
"document this" bar but barely.

## Status Values

### confirmed

Evidence-based, high confidence. The agent found the answer via research, or
the skill's recommendation heuristic produced a clear winner with no
contradicting evidence.

### assumed

Best guess, pending review. Assigned when:

| Category | Condition |
|----------|-----------|
| Researchable | Agent couldn't find the answer, made best guess |
| Judgment call | Heuristic was close (no clear winner), or contradicting evidence exists |
| Approval gate | Always -- auto-approval assumes the artifact meets the user's standards |

### escalated

Lightweight decision upgraded to heavyweight. The agent started the 3-step
micro-protocol but determined during gather (Step 2) that the decision needs
deeper evaluation. The partial block's Question and Evidence carry forward
as seed context for the decision skill.

## Review Priority

Each assumed decision carries a review priority in the consolidated decisions file:

| Priority | Surfaces in | When |
|----------|------------|------|
| high | Terminal summary + PR body | Approval gates, contested judgment calls |
| low | Consolidated decisions file only | Clear heuristic wins that happened to be categorized as assumed |

Expected visible split: ~20% high / ~80% low.

## Machine Extraction

Extract all decision blocks from a file:

```
Pattern: <!-- decision:start id="([^"]+)" status="([^"]+)" -->
         (content)
         <!-- decision:end -->
```

The content between delimiters is standard markdown. Parsers should not attempt
to parse it as structured data -- read it as rendered text.

## Relationship to Decision Reports

The decision skill's canonical report (see decision report format spec) is a
superset of the block format. A decision report IS a decision block with
additional detail (full research findings, validator arguments, cross-examination
transcript). The block format is the minimum viable record; the report format
is the maximum.

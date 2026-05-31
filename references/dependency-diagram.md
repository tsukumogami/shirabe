# Dependency Diagram

The one dependency-diagram convention both roadmap and plan workflows
consume. Defines the mermaid syntax rules, the fixed status-class
palette, the node format, and the legend.

Cited by P4 in `workflow-principles.md`.

## Table of Contents

- [Mermaid Syntax Rules](#mermaid-syntax-rules)
- [Status Classes](#status-classes)
- [Node Format](#node-format)
- [Class Assignment](#class-assignment)
- [Initial Status](#initial-status)
- [Status Updates](#status-updates)
- [Legend](#legend)
- [Child Reference Row Invariant](#child-reference-row-invariant)

## Mermaid Syntax Rules

These rules prevent common mermaid rendering failures.

### 1. Use `graph`, not `flowchart`

```
graph TD    # Correct
flowchart TD  # Wrong -- less portable
```

### 2. Direction

- `LR` (left-right): Preferred for simple diagrams with few sequential
  levels.
- `TD` (top-down): Use when dependencies span five or more sequential
  levels (horizontal becomes unreadable).

### 3. Subgraphs for phases (optional)

```
subgraph Phase1["Phase 1: Name"]
    I488["#488: Title"]
    I489["#489: Title"]
end
```

### 4. Edges MUST be outside subgraphs

```
# Wrong -- edges inside subgraph (will not render)
subgraph Phase1
    A --> B
end

# Correct -- edges after all subgraphs
subgraph Phase1
    A["..."]
    B["..."]
end
A --> B
```

### 5. Class definitions at the end

```
graph TD
    # ... nodes and edges ...

    classDef done fill:#c8e6c9
    classDef ready fill:#bbdefb
    classDef blocked fill:#fff9c4
    classDef needsDesign fill:#e1bee7
    classDef needsPrd fill:#b3e5fc
    classDef needsSpike fill:#ffcdd2
    classDef needsDecision fill:#d1c4e9
    classDef tracksDesign fill:#FFE0B2,stroke:#F57C00,color:#000
    classDef tracksPlan fill:#FFE0B2,stroke:#F57C00,color:#000

    class I488 ready
    class I489,I490 blocked
```

## Status Classes

Fixed palette. Never change these colors or class names.

| Status | Class | Fill Color | Meaning |
|--------|-------|------------|---------|
| done | `done` | `#c8e6c9` (light green) | Issue or feature is closed |
| ready | `ready` | `#bbdefb` (light blue) | Open, no blocking dependencies |
| blocked | `blocked` | `#fff9c4` (light yellow) | Open, has open blockers |
| needs-design | `needsDesign` | `#e1bee7` (light purple) | Future work, not yet designed |
| needs-prd | `needsPrd` | `#b3e5fc` (light blue) | Future work, needs requirements definition |
| needs-spike | `needsSpike` | `#ffcdd2` (light red) | Future work, needs feasibility investigation |
| needs-decision | `needsDecision` | `#d1c4e9` (light indigo) | Future work, needs architectural choice |
| tracks-design | `tracksDesign` | `#FFE0B2` (light orange), stroke `#F57C00` | Has spawned a child design in progress |
| tracks-plan | `tracksPlan` | `#FFE0B2` (light orange), stroke `#F57C00` | PLAN created, implementation underway |

## Node Format

- **Node ID:** `I<issue-number>` for plan diagrams (e.g., `I417`); use
  a stable mnemonic for roadmap features (e.g., `F1`, `F2`).
- **Node label:** `#<N>: <short-title>` for issues; the feature
  label for roadmap features. Maximum 40 characters.
- **Quotes around labels:** Always use `["..."]`.

### Node Label Rules

- Maximum 40 characters total.
- Truncate at last word boundary, add `...` if too long.
- Replace `[` `]` with `(` `)`, remove backticks.
- Example: `I417["#417: Add structured logging..."]`

## Class Assignment

Use the `class` directive (not inline `:::`):

```
# Wrong -- inline syntax less maintainable
I488:::ready --> I489:::blocked

# Correct -- class directive at end
I488 --> I489
class I488 ready
class I489 blocked
```

Group multiple nodes with the same status:

```
class I489,I490,I491 blocked
```

## Initial Status

When `/plan` or `/roadmap` creates the diagram:

- Nodes with no dependencies: `ready`
- Nodes with dependencies: `blocked`
- Future work needing upstream artifacts: `needsDesign`, `needsPrd`,
  `needsSpike`, or `needsDecision`
- Nodes with accepted child designs: `tracksDesign` or `tracksPlan`
- No nodes start as `done`

## Status Updates

When `/work-on` completes an issue:

- The completed node changes to `done`
- Downstream nodes are recalculated: if all blockers are done, change
  to `ready`

## Legend

Include a legend line after the diagram:

```markdown
**Legend**: Green = done, Blue = ready, Yellow = blocked, Purple = needs-design, Orange = tracks-design/tracks-plan
```

## Child Reference Row Invariant

`tracksDesign` and `tracksPlan` nodes must have a corresponding child
reference row in the Implementation Issues table (see
`issues-table.md`). Nodes without a tracking class must not have a
child reference row.

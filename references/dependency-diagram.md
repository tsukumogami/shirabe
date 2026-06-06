# Dependency Diagram

The one dependency-diagram convention both roadmap and plan workflows
consume. Defines the mermaid syntax rules, the fixed status-class
palette, the node format, and the legend.

Cited by P4 in `workflow-principles.md`.

## Table of Contents

- [Mermaid Syntax Rules](#mermaid-syntax-rules)
- [Edge Variants](#edge-variants)
- [Status Classes](#status-classes)
- [Pipeline-Stage Classes](#pipeline-stage-classes)
- [Node Format](#node-format)
- [Roadmap-Profile Bijection](#roadmap-profile-bijection)
- [External Mnemonic Nodes](#external-mnemonic-nodes)
- [Class Assignment](#class-assignment)
- [Combinatorial Class Assignments](#combinatorial-class-assignments)
- [Subgraphs](#subgraphs)
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

## Edge Variants

Three edge variants are recognised. The variant is presentation only;
FC07 treats all three as the same directed dependency edge for
bijection and edge-agreement purposes.

| Edge | Syntax | Meaning |
|------|--------|---------|
| Hard | `A --> B` | A hard dependency; B cannot start before A completes |
| Soft | `A -.-> B` | A soft dependency, advisory or cross-product enrichment |
| Cross-altitude blocker | `A ==>\|"label"\| B` | A hard blocker that crosses an altitude boundary; label is required and names the blocker |

The cross-altitude blocker variant is typically used in roadmap-altitude
diagrams to call out a single load-bearing cross-product dependency
(e.g., `KT5V2 ==>|"V2 port-forward"| I477` from `ROADMAP-bunki.md`).
Soft edges can also carry an optional label (`A -.->|"soft"| B`); the
label is not interpreted by FC07.

## Status Classes

Fixed palette. Never change these colors or class names. Status classes
are the only classes FC07's class-versus-Status pass reconciles
against; pipeline-stage classes (see next section) are recognised but
not reconciled. FC09 reuses the same Status-bearing class scope --
its three sub-checks act only on rows whose diagram node carries a
`done`, `ready`, or `blocked` class -- and reconciles those rows
against GitHub-observed state rather than against the table's
terminal column.

| Status | Class | Fill Color | Meaning |
|--------|-------|------------|---------|
| done | `done` | `#c8e6c9` (light green) | Issue or feature is closed |
| ready | `ready` | `#bbdefb` (light blue) | Open, no blocking dependencies |
| blocked | `blocked` | `#fff9c4` (light yellow) | Open, has open blockers |

## Pipeline-Stage Classes

Pipeline-stage classes name the feature's upstream-artifact
prerequisite -- what needs to ship before implementation can start.
They are **orthogonal to Status classes**: a `needsPrd` node is not
yet shaped enough to ask "is it ready or blocked"; the question is
"has the PRD landed". FC07's class-versus-Status pass does not
reconcile pipeline-stage classes against table state; they encode
upstream readiness, not runtime status.

| Class | Fill Color | Meaning |
|-------|------------|---------|
| `needsDesign` | `#e1bee7` (light purple) | Future work, not yet designed |
| `needsPrd` | `#b3e5fc` (light blue) | Future work, needs requirements definition |
| `needsSpike` | `#ffcdd2` (light red) | Future work, needs feasibility investigation |
| `needsDecision` | `#d1c4e9` (light indigo) | Future work, needs architectural choice |
| `needsPlanning` | `#fff9c4` (light yellow) | Future work, needs implementation planning |
| `needsExplore` | `#ffe0b2` (light orange) | Future work, needs problem-space exploration |
| `tracksDesign` | `#FFE0B2` (light orange), stroke `#F57C00` | Has spawned a child design in progress |
| `tracksPlan` | `#FFE0B2` (light orange), stroke `#F57C00` | PLAN created, implementation underway |

## Node Format

- **Node ID:** `I<issue-number>` (e.g., `I417`) for both plan and
  roadmap diagrams. The integer suffix is the GitHub issue number the
  node represents. Roadmap-feature rows whose Issues column fans out
  into multiple issues contribute one `I<n>` node per issue.
- **Node label:** `#<N>: <short-title>`. Maximum 40 characters.
- **Quotes around labels:** Always use `["..."]`.

### Node Label Rules

- Maximum 40 characters total.
- Truncate at last word boundary, add `...` if too long.
- Replace `[` `]` with `(` `)`, remove backticks.
- Example: `I417["#417: Add structured logging..."]`

## Roadmap-Profile Bijection

For roadmap-profile docs, an `I<n>` diagram node binds to the entity
row whose Issues column contains a markdown link to issue #n. The
binding is **label match against the Issues cell**, not positional:
the diagram node and the row are paired by issue-number identity,
not by where each appears in its surface.

A row whose Issues cell is `None` (the empty placeholder per
`issues-table.md`) contributes zero expected `I<n>` nodes -- the
feature has not yet been decomposed into issues, so no diagram node
is required. The diagram's `I<n>` set is the union of every `#n`
that appears across all entity rows' Issues cells.

The plan-profile binding is unchanged: `I<n>` binds to the row whose
key column is `#n`.

## External Mnemonic Nodes

Cross-product references in a roadmap diagram use a custom mnemonic
matching `^[A-Z][A-Z0-9_]*$` -- typically the target product's
feature-prefix concatenated with an issue number or descriptor (e.g.,
`KT5V2`, `NW6`, `BK7`, `SH8`). These nodes name issues that live in
another product's roadmap and are rendered with the `external` class
(gray dashed-border style) for visual distinction.

FC07 excludes external mnemonic nodes from bijection and edge
agreement by design: they do not match the `^I[0-9]+$` issue-keyed
pattern, so they neither require a matching table row nor justify a
table-derived edge against any row in the local doc. The cross-product
relationship lives in the prose around the diagram and on the target
product's roadmap, not in the local table.

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

## Combinatorial Class Assignments

A node may carry more than one class -- typically one Status or
pipeline-stage class plus one **critical-path overlay** class (a
custom class introduced by the doc to highlight a node's role in
some specific spanning path, e.g., `userValueFloor`,
`bundleReleaseChain`, `firstShipSubset`, `crossAltitude`). Overlay
classes are defined by the doc, applied with their own `class`
statements, and not part of the canonical palette.

FC07's class-versus-Status pass selects the Status-bearing class
(`done`, `ready`, or `blocked`) when present and ignores other
classes on the same node for truth-table purposes. Pipeline-stage
classes and overlay classes are observed but not reconciled. FC09
inherits the same Status-bearing-class selection rule: a node
carrying both `done` and an overlay class is reconciled by its
`done` class only.

## Subgraphs

Coordinator-level roadmap diagrams may group nodes into named
subgraphs to organise the visualization by product, by stage, or by
any author-chosen dimension:

```
graph TD
  subgraph KT ["koto (KT)"]
    direction TB
    I397["#397 KT1 request-store"]
    I398["#398 KT2 peer-messaging"]
  end

  subgraph NW ["niwa (NW)"]
    direction TB
    I428["#428 NW1 subagent generation"]
  end

  I397 --> I428
```

FC07 traverses inside subgraphs as if the diagram were flat: every
node declared inside a `subgraph ... end` block is a first-class
diagram node and participates in bijection and edge agreement on the
same terms as nodes declared outside subgraphs. Subgraph names and
`direction` overrides are presentation only and are not interpreted
by FC07.

The mermaid syntax rule about edges-outside-subgraphs (§4 above)
still applies: edges between subgraph members must be declared
after all subgraph blocks close.

## Initial Status

When `/plan` or `/roadmap` creates the diagram:

- Nodes with no dependencies: `ready`
- Nodes with dependencies: `blocked`
- Future work needing upstream artifacts: `needsDesign`, `needsPrd`,
  `needsSpike`, `needsDecision`, `needsPlanning`, or `needsExplore`
- Nodes with accepted child designs: `tracksDesign` or `tracksPlan`
- External mnemonic nodes (cross-product references): `external`
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

Roadmap diagrams that use pipeline-stage classes or external mnemonic
nodes extend the legend accordingly:

```markdown
**Legend**: Cyan = needs-prd, Purple = needs-design, Yellow = needs-planning, Red = needs-spike, Gray dashed-border = external (cross-product reference).
```

## Child Reference Row Invariant

`tracksDesign` and `tracksPlan` nodes must have a corresponding child
reference row in the Implementation Issues table (see
`issues-table.md`). Nodes without a tracking class must not have a
child reference row.

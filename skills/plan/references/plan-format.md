# PLAN Format Reference

Structure, lifecycle, validation rules, and quality guidance for
PLAN documents. PLANs decompose a DESIGN into atomic, implementable
issues with a dependency graph.

## Table of Contents

- [Frontmatter](#frontmatter)
- [Required Sections](#required-sections)
- [Optional Sections](#optional-sections)
- [Implementation Issues Table](#implementation-issues-table)
- [Dependency Graph](#dependency-graph)
- [Content Boundaries](#content-boundaries)
- [Lifecycle](#lifecycle)
- [Validation Rules](#validation-rules)
- [Quality Guidance](#quality-guidance)

## Frontmatter

Every PLAN document begins with YAML frontmatter:

```yaml
---
schema: plan/v1
status: Draft
execution_mode: single-pr
upstream: docs/designs/DESIGN-<name>.md
milestone: "human-readable milestone name"
issue_count: 18
---
```

Required fields: `schema`, `status`, `execution_mode`, `milestone`,
`issue_count`. Optional: `upstream` (the DESIGN doc this PLAN
implements; omit if authored without a single upstream DESIGN),
`split_rationale` (required under the condition below, absent
otherwise), and `tracking_level`.

- **schema** -- `plan/v1`. Pins the artifact-type contract.
- **status** -- lifecycle state (`Draft`, `Active`, `Done`).
- **execution_mode** -- one of `single-pr`, `multi-pr`, or
  `coordinated`. Determines whether the PLAN materializes GitHub
  issues at finalization (`multi-pr`) or stays self-contained and
  drives one PR (`single-pr`); `coordinated` is the multi-repo
  generalization of `multi-pr`.
- **split_rationale** -- why this PLAN has the delivery shape it has.
  Required when **either** of these holds:
  - `execution_mode` is not `single-pr`; **or**
  - `execution_mode` is `single-pr` and the repository's resolved
    Delivery Preference is `atomic` — that is, the plan departed from
    what the preference would have produced.

  Both disjuncts are stated because the second is easy to miss: in a
  repository preferring atomic delivery, `single-pr` *is* the
  departure, and it owes a reason for the same purpose the first
  disjunct does.

  The value is free text and MUST name one of the three branches
  defined in `${CLAUDE_PLUGIN_ROOT}/references/split-triggers.md` —
  Hard Constraint, Incremental Value, or Stated Preference — followed
  by the specific justification. Free text rather than an enum
  because the plan-altitude branch vocabulary is not yet settled
  enough to be worth a migration-costly schema; naming the branch is
  what keeps the check stronger than "the author typed something."

  A value that is present but names none of the three branches fails
  `L09`, so this contract and the check agree on what naming a branch
  requires.

  A `single-pr` PLAN in a repository whose preference is
  `consolidated` (the default) omits the field entirely. That is
  correct rather than an omission: one pull request is the shape
  nobody asks about, and requiring a note there would add a mandatory
  field to the common case for symmetry alone.

  ```yaml
  split_rationale: |
    Hard Constraint. The reusable workflow added in the first unit
    must reach the default branch before the second unit's
    workflow_dispatch invocation can resolve.
  ```

- **tracking_level** -- one of `none`, `issues`, or
  `issues-and-milestone`: which GitHub artifacts this PLAN's work
  items got. Written by Phase 7 with the value it resolved on the
  `flag > CLAUDE.md ## Tracking Level: header > mode-derived default`
  stack, so the resolved value is a fact about the document rather
  than something a later reader re-derives.

  That distinction is load-bearing. Task extraction runs against a
  committed PLAN, possibly long after authoring; if it re-resolved
  the level from CLAUDE.md, a repo that later changed its header
  would silently change how an already-written plan's work items
  key. Persisting the value also gives `plan-to-tasks.sh` a
  deterministic branch signal rather than making it infer the level
  from the table's shape.

  Absent on `coordinated` PLANs, whose tracking is governed by
  `${CLAUDE_PLUGIN_ROOT}/references/coordination-strategy.md`.
- **upstream** -- path to the upstream DESIGN doc, repo-relative or
  cross-repo (`owner/repo:path`). Omit if the PLAN was authored from
  a topic with no single upstream DESIGN. Cross-repo upstream
  references follow `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`.
- **milestone** -- human-readable milestone name. In `multi-pr` mode
  this becomes the GitHub milestone title. In `single-pr` mode it is
  prose only.
- **issue_count** -- integer count of atomic issues the PLAN
  decomposes into. Must match the row count of the Implementation
  Issues table.

**Two written shapes are supported for `upstream:`.** A scalar -- the
path on the key's own line -- and a sequence, written either as `- `
entries on the following lines or inline as `[<path>, <path>]`. Every
entry of a sequence is read, in written order, and a single-entry
sequence is still a sequence. Reach for the sequence when the document
genuinely has more than one parent; the scalar otherwise. Nothing else
is supported: a scalar is never split, so two paths on one line read as
one entry that resolves to nothing.

Frontmatter status must match the body `## Status` first line --
the validator's FC03 check compares the two case-insensitively and
the body's first non-blank line under `## Status` must be the bare
status word alone, prose pushed to a paragraph after a blank line.

## Required Sections

Every PLAN has these sections in order:

1. **Status** -- current lifecycle state. The first non-blank line
   is the bare status word (`Draft`, `Active`, `Done`); explanatory
   prose follows after a blank line.
2. **Scope Summary** -- one or two paragraphs describing what the
   PLAN covers, the source DESIGN's scope distilled to its
   implementation contract.
3. **Decomposition Strategy** -- how the work was sliced. Horizontal
   (layer by layer), vertical (feature by feature), walking skeleton
   (e2e thin slice first), or hybrid. Names the grouping rules
   ("one issue per validator check function", "one issue per
   reference file").
4. **Implementation Issues** -- the atomic-issue table plus issue
   outlines (one outline per issue with Goal, Acceptance Criteria,
   Dependencies, Type, Files).
5. **Dependency Graph** -- the Mermaid diagram showing inter-issue
   dependencies and class assignments (`ready`, `blocked`, `done`,
   etc.).
6. **Implementation Sequence** -- recommended execution order,
   typically grouped by batch or critical-path level. Describes the
   "open with X, then Y" ordering for the implementing agent.

## Optional Sections

Include when relevant:

- **References** -- in-repo and cross-repo precedents the PLAN draws
  on (upstream DESIGN, related plans, format references). Durable
  paths only (no `wip/...`).

## Implementation Issues Table

The canonical Implementation Issues table for `plan/v1` is a
three-column shape:

| Column | Content |
|--------|---------|
| Issue | Markdown link to the issue's local anchor (within the PLAN) for single-pr mode, OR `#N` GitHub link for multi-pr mode |
| Dependencies | Local-anchor links to blocking issues, or `None` if independent |
| Complexity | One of `trivial`, `simple`, `testable`, `complex` |

Each issue occupies TWO rows in the table:

1. The link row, holding the three columns above.
2. The summary row, holding a one-paragraph italicized summary of
   the issue's goal in the first cell, with the second and third
   cells empty.

Example:

```markdown
| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#1: feat(validate): SCHEMA-MISSING + slug-prefix](#issue-1-...) | None | testable |
| _Extend `check_schema` to emit a SCHEMA-MISSING notice; add a slug-prefix detection capability that samples existing artifacts. Closes shirabe#157._ | | |
| [#2: feat(validate): FC10 writing-style check](#issue-2-...) | None | testable |
| _Add an FC10 check that reads banned vocabulary from `skills/writing-style/SKILL.md` and emits notices for matches._ | | |
```

### The legacy four-column shape

The historic four-column shape (`Issue | Title | Dependencies |
Complexity`) is detected by the validator's FC05 check, which emits
a migration hint pointing at the canonical three-column shape. The
migration folds the Title cell into the issue link text:
`[#N: <title>](url) | <deps> | <complexity>`.

### Single-pr vs multi-pr emission

- **single-pr mode** -- the table holds local anchors to outlines
  within the same PLAN. No GitHub issues are materialized. The
  implementing agent works through the outlines in dependency order
  on one branch and ships one PR.
- **multi-pr mode** -- the table holds `#N` links to GitHub issues
  materialized at PLAN finalization (Phase 7 populate). A milestone
  groups the issues. Each issue ships its own PR.

In both modes, the table shape and validator contract are identical.

## Dependency Graph

The Dependency Graph section contains a Mermaid `graph TD` block
declaring inter-issue edges and class assignments. The contract:

- One node per issue, keyed `I<N>` (e.g. `I1`, `I2`).
- Node labels match the issue table's link text (so a reader can
  cross-reference the diagram against the table).
- Edges encode dependencies: `I9 --> I3` means issue 9 must complete
  before issue 3 starts.
- Class assignments use the canonical Status palette: `done`,
  `ready`, `blocked`, plus the pipeline-stage classes
  (`needsDesign`, `needsPrd`, `needsSpike`, `needsDecision`) and the
  tracks-* classes (`tracksDesign`, `tracksPlan`).
- A `classDef` declaration is required for every class the diagram
  uses outside the canonical Status palette.
- A Legend follows the diagram block, listing each class with a
  short description. FC08 reconciles the Legend against the
  `classDef` set.

### Diagram-reconciliation contract (PR #149 precedent)

FC07 reconciles the Implementation Issues table rows against the
Dependency Graph nodes:

- Every table row must correspond to a diagram node (by `I<N>` key).
- Every diagram node must correspond to a table row.
- The class assignment on a diagram node must agree with the row's
  Status column (`done` -> strikethrough, `ready` -> open, etc.).

A row without a node, a node without a row, or a class mismatch
fires an FC07 notice. The notice is informational; resolution is
typically a one-line diagram or table edit.

### classDef-reconciliation contract (PR #169 precedent)

FC08 reconciles the Legend against the `classDef` set:

- Every Legend entry names a class that has a `classDef` declaration
  in the diagram (or is in the canonical Status palette).
- Every `classDef` declaration outside the canonical palette is
  named in the Legend.
- Names use the camelCase convention; the Legend may use kebab-case,
  but the diagram declares camelCase and the validator normalizes
  Legend names to camelCase for comparison.

A Legend entry without a `classDef`, or vice versa, fires an FC08
notice. The notice is informational; resolution is a one-line
Legend or `classDef` edit.

## Content Boundaries

A PLAN does NOT contain:

- **Technical architecture** -- belongs in the upstream DESIGN. The
  PLAN references the DESIGN's decisions but does not re-litigate
  them.
- **Requirements articulation** -- belongs in the upstream PRD. The
  PLAN cites requirements (R1, R2, ...) but does not introduce new
  ones.
- **Implementation code** -- belongs in the PR. The PLAN names files
  and acceptance criteria; the code lives in the commits.
- **Strategic justification** -- belongs in the VISION/STRATEGY/
  ROADMAP. The PLAN takes scope as given.

If a PLAN draft starts introducing requirements, design decisions,
or strategic framing, extract that content into the upstream
DESIGN/PRD/ROADMAP and replace the PLAN content with a citation.

## Lifecycle

### States

| State | Meaning |
|-------|---------|
| Draft | Under decomposition. Issue table may be incomplete. |
| Active | Issues being implemented. Used in `multi-pr` mode while issues are open. `single-pr` mode skips this state. |
| Done | All issues complete; lifecycle cascade has completed. Terminal state. |

### Transitions

All transitions are executed by `shirabe transition`. The PLAN
stays in `docs/plans/` through every state.

The Draft -> Active gate keys on the resolved `tracking_level`, not on
`execution_mode`: an activation that creates GitHub issues waits for
human approval, because that is the moment remote artifacts appear;
one that creates none auto-fires as authoring completes.

- **Draft -> Active** (`tracking_level` is `issues` or
  `issues-and-milestone`) -- Phase 7 has materialized the GitHub
  issues, and the milestone at `issues-and-milestone`, behind the
  approval gate. Reachable at any `execution_mode`: a `single-pr`
  PLAN whose repo asked for issues takes this path too.
- **Draft -> Done** (`tracking_level` is `none`) -- no GitHub
  artifacts were created, so nothing gated the activation; the
  implementing agent has shipped the work and the lifecycle cascade
  fires. Reachable at any `execution_mode`: a `multi-pr` PLAN whose
  repo asked for no tracking takes this path too.
- **Active -> Done** -- all materialized issues are closed. Lifecycle
  cascade fires.

### Lifecycle cascade

On PLAN `Done`, the cascade walks the upstream chain:

- DESIGN: `Planned -> Current`, move from `docs/designs/` to
  `docs/designs/current/`.
- PRD: `Accepted -> Done`.
- BRIEF: `Accepted -> Done`.
- ROADMAP (if upstream): feature status update; if all features
  complete, ROADMAP `Active -> Done`.

The cascade is executed by `skills/execute/scripts/run-cascade.sh`
or by the implementing agent following the lifecycle script.

## Validation Rules

`shirabe validate` recognizes `PLAN-*.md` files by longest-prefix
match and runs FC01-FC06 plus the format-specific FC07/FC08/FC09
checks. The `plan/v1` FormatSpec declares:

- **Required fields:** `status`, `execution_mode`, `milestone`,
  `issue_count`.
- **Valid statuses:** `Draft`, `Active`, `Done`.
- **Required sections:** `Status`, `Scope Summary`, `Decomposition
  Strategy`, `Implementation Issues`, `Dependency Graph`,
  `Implementation Sequence`.
- **Issues table columns:** `Issue`, `Dependencies`, `Complexity`.

The validator-side contracts:

- **FC01** -- required fields present.
- **FC02** -- status is in the valid enum.
- **FC03** -- frontmatter status matches body `## Status` first
  line.
- **FC04** -- all required sections present.
- **FC15** -- the required sections appear in the canonical order above.
- **FC05** -- Implementation Issues table header matches the
  canonical three-column shape (legacy four-column shape emits a
  migration hint), and each row's content is well-formed: dependencies
  are `None` or markdown links, the complexity value is in the allowed
  set, and a child reference row links its child artifact.
- **FC06** -- table rows have the expected cell count and shape.
- **FC07** -- table rows reconcile against Dependency Graph nodes.
- **FC08** -- Legend reconciles against the `classDef` set.
- **FC09** -- doc-vs-GitHub state reconciliation (multi-pr mode).
- **FC11** -- (when present) plan-section-structure reconciliation
  against this format reference.

## Quality Guidance

### Scope Summary

- One or two tight paragraphs. Names the DESIGN's contract and the
  PLAN's slice of it.
- Stands alone. A reader landing on the PLAN cold should grasp what
  the work covers without opening the DESIGN.

### Decomposition Strategy

- Names the slicing axis (horizontal/vertical/walking skeleton/
  hybrid) and the grouping rule explicitly.
- Counts edges between batches (cross-batch dependency count) when
  the slicing produces a multi-batch decomposition. Helps the
  implementing agent reason about parallelism.

### Implementation Issues

- Each issue is atomic: a single PR can ship it. If an issue
  requires multiple PRs, split it.
- Each AC is specific and testable. "Function exists" is testable;
  "Function is correct" is not.
- Type field is one of `code`, `docs`, `task`. `code` issues require
  unit tests as a sub-requirement; `docs` and `task` skip the
  test-required gate.
- Files field names the files the issue touches. A surprise file
  modification during implementation signals the issue's scope
  drifted.

### Dependency Graph

- Edges encode hard dependencies (cannot start until predecessor
  completes). Soft preferences ("nice to do A before B") are not
  edges.
- Class assignments are kept in sync with issue status. A merged
  issue's node should become `done`; a started issue's node should
  become `ready` (no longer blocked) if its predecessors are done.

### Common Pitfalls

- **Prose on the `## Status` first line.** Most common FC03
  failure. The first non-blank line under `## Status` must be the
  bare status word alone.
- **Mixing single-pr and multi-pr conventions.** The Implementation
  Issues table uses local anchors for single-pr and `#N` GitHub
  links for multi-pr; mixing the two confuses the validator's FC07
  reconciliation.
- **Drifting into design altitude.** A PLAN that introduces new
  technical decisions has climbed up. Extract those decisions into
  the upstream DESIGN and cite them.
- **Empty Dependencies column.** Every issue declares its
  dependencies explicitly. Use `None` for independent issues; don't
  leave the cell blank.
- **Stale class assignments.** A diagram showing every node as
  `ready` after issues have merged signals the diagram was not
  updated. FC09 catches this for multi-pr docs.

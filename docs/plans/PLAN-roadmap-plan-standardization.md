---
schema: plan/v1
status: Active
execution_mode: multi-pr
upstream: docs/designs/DESIGN-roadmap-plan-standardization.md
milestone: "roadmap-plan-standardization"
issue_count: 9
---

# PLAN: roadmap-plan-standardization

## Status

Active

The milestone and nine issues exist
([roadmap-plan-standardization](https://github.com/tsukumogami/shirabe/milestone/6),
#111 through #119) and the plan is now Active. The decomposition below tracks the work
across the five value-delivering PR slices; the plan retires by verify-then-delete when
the work completes.

## Scope Summary

Standardize shirabe's own `/roadmap` and `/plan` skills around shared, define-once
conventions: three plugin-root shared references, a Markdown-table parser plus two
error-level content checks in `internal/validate`, a migrated committed corpus, the
single-pr/multi-pr decision surfaced with a value-confirmation guard, a native
roadmap-to-issues script, and a whole-tree lifecycle CI gate -- with table-diagram
reconciliation staged behind a mermaid-parser spike as a later increment.

## Decomposition Strategy

**Horizontal.** The design describes loosely-coupled capability slices with stable,
already-existing interfaces (the `Doc` IR, `create-issues-batch.sh`, the `IsNotice`
gate) and one explicit prerequisite chain -- the table parser before reconciliation, and
the mermaid-parser spike before reconciliation. There is no thin end-to-end thread to
thicken, so this is horizontal decomposition, not a walking skeleton: each issue builds
one capability fully, and the single hard ordering constraint (spike before
reconciliation) is captured as dependency edges rather than a skeleton.

The nine issues group into five value-delivering PR slices, each landing observable
incremental value on its own (the usable-value principle this work surfaces):

- **Slice A (#111, #112, #113)** -- table validation + corpus migration, one PR. References +
  parser + FC05/FC06 going error-level + the corpus migrated to pass them, bundled so the
  checks never redden CI on a divergent committed doc in a gap window.
- **Slice B (#114)** -- the single-pr/multi-pr decision surfaced on the plan skill, anchored
  on value, with a value-confirmation guard that can fail.
- **Slice C (#115)** -- a native roadmap-to-issues script, retiring the plan re-entry's prose
  string surgery.
- **Slice D (#116, #117)** -- the whole-tree `--lifecycle` mode plus the CI gate and the
  verify-then-delete terminal wiring.
- **Slice E (#118, #119)** -- the mermaid-parser spike, then the reconciliation check as a
  notice. Hard-gated: reconciliation cannot start until the spike resolves.

The work-slicing (decomposition-strategy) decision above is named as separate from the
single-pr/multi-pr execution-mode decision: multi-pr, on the incremental-value rationale,
with the spike-to-reconciliation merge gate as a second independent justification.

## Implementation Issues

### Milestone: [roadmap-plan-standardization](https://github.com/tsukumogami/shirabe/milestone/6)

| Issue | Dependencies | Complexity |
|-------|--------------|------------|
| [#111: docs(references): add shared workflow-principles, issues-table, and dependency-diagram references](https://github.com/tsukumogami/shirabe/issues/111) | None | simple |
| _Creates the three plugin-root shared references and trims the two skill references to cite them; finalizes the five-principle wording. The foundation every other slice consumes -- the validator is the enforcement twin of these references._ | | |
| [#112: feat(validate): add Markdown issues-table parser and FC05/FC06 content checks](https://github.com/tsukumogami/shirabe/issues/112) | [#111](https://github.com/tsukumogami/shirabe/issues/111) | testable |
| _Adds `table.go` (`parseIssuesTable` + `Table`) and the error-level `checkFC05` (schema) and `checkFC06` (cross-reference), wired into the Plan arm and a new Roadmap arm. The one new parser the first pass allows; its `Table` is what the later reconciliation check reuses._ | | |
| [#113: docs(corpus): migrate committed roadmap and plan tables to the canonical profiles](https://github.com/tsukumogami/shirabe/issues/113) | [#112](https://github.com/tsukumogami/shirabe/issues/112) | testable |
| _Migrates the divergent committed roadmap and legacy plan tables onto the canonical profiles so error-level FC05/FC06 pass on the whole corpus. Lands in the same PR as #112 so the checks never see an unmigrated corpus._ | | |
| [#114: docs(plan): surface the single-pr/multi-pr decision and add the value-confirmation guard](https://github.com/tsukumogami/shirabe/issues/114) | [#111](https://github.com/tsukumogami/shirabe/issues/111) | testable |
| _Lifts the single-pr/multi-pr rule onto the plan SKILL surface anchored on the usable-value principle, de-conflated from work-slicing, and adds a value-confirmation step that can fail and records-and-proceeds under `--auto`. Shares the record-and-proceed gate shape with #115's approval gate._ | | |
| [#115: feat(roadmap): add native populate-issues-table script reusing create-issues-batch](https://github.com/tsukumogami/shirabe/issues/115) | [#111](https://github.com/tsukumogami/shirabe/issues/111) | testable |
| _Adds `populate-issues-table.sh` that builds a per-feature manifest, reuses the generic `create-issues-batch.sh`, and writes the reserved sections by structural replacement, with issue creation routed through the R14 approval gate. Retires the plan re-entry's prose string surgery for the roadmap case._ | | |
| [#116: feat(validate): add whole-tree --lifecycle mode with L01 and L02 checks](https://github.com/tsukumogami/shirabe/issues/116) | [#112](https://github.com/tsukumogami/shirabe/issues/112) | testable |
| _Adds a `--lifecycle <root>` mode that walks the doc tree and runs Check A (L01: a present roadmap or multi-pr plan must be Active) and Check B (L02: no single-pr plan may exist), reusing the Doc IR and frontmatter parsing #112 exercises._ | | |
| [#117: ci(lifecycle): add reusable lifecycle workflow and wire the verify-then-delete terminal](https://github.com/tsukumogami/shirabe/issues/117) | [#116](https://github.com/tsukumogami/shirabe/issues/116) | testable |
| _Adds the reusable lifecycle workflow plus self-caller (no `paths:` filter, read-only) running the `--lifecycle` mode on every PR, wires the verify-then-delete terminal into the cascade, and removes the stale move-to-done wording. Completes the lifecycle enforcement Slice D began._ | | |
| [#118: docs(spike): mermaid-parser feasibility spike for table-diagram reconciliation](https://github.com/tsukumogami/shirabe/issues/118) | [#111](https://github.com/tsukumogami/shirabe/issues/111) | simple |
| _Writes the spike investigating the mermaid graph subset the corpus uses, a line-oriented extraction approach with no external dependency, and the reconciliation strictness. The explicit upstream that gates the reconciliation increment._ | | |
| [#119: feat(validate): add mermaid extractor and checkFC07 table-diagram reconciliation as a notice](https://github.com/tsukumogami/shirabe/issues/119) | [#112](https://github.com/tsukumogami/shirabe/issues/112), [#118](https://github.com/tsukumogami/shirabe/issues/118) | testable |
| _Adds `mermaid.go` and `checkFC07` reconciling the parsed `Table` against the extracted diagram, shipped as a notice via `IsNotice` so an unreconciled committed diagram does not redden CI, with a one-line path to error-level promotion after corpus reconciliation. The final, spike-gated increment._ | | |

## Dependency Graph

```mermaid
graph TD
    I111["#111: shared references"]
    I112["#112: table parser + FC05/FC06"]
    I113["#113: migrate committed corpus"]
    I114["#114: surface decision + value guard"]
    I115["#115: roadmap populate script"]
    I116["#116: --lifecycle mode (L01/L02)"]
    I117["#117: lifecycle CI + terminal wiring"]
    I118["#118: mermaid-parser spike"]
    I119["#119: mermaid extractor + FC07 notice"]

    I111 --> I112
    I111 --> I114
    I111 --> I115
    I111 --> I118
    I112 --> I113
    I112 --> I116
    I112 --> I119
    I116 --> I117
    I118 --> I119

    classDef done fill:#c8e6c9
    classDef ready fill:#bbdefb
    classDef blocked fill:#fff9c4
    classDef needsDesign fill:#e1bee7
    classDef needsPrd fill:#b3e5fc
    classDef needsSpike fill:#ffcdd2
    classDef needsDecision fill:#d1c4e9
    classDef tracksDesign fill:#FFE0B2,stroke:#F57C00,color:#000
    classDef tracksPlan fill:#FFE0B2,stroke:#F57C00,color:#000

    class I111 ready
    class I112,I113,I114,I115,I116,I117,I118,I119 blocked
```

**Legend**: Green = done, Blue = ready, Yellow = blocked, Purple = needs-design, Orange = tracks-design/tracks-plan

## Implementation Sequence

**Critical path**: #111 -> #118 -> #119 (length 3). The reconciliation increment is the
longest chain because it is hard-gated behind the references, the table parser (#112), and
the spike (#118) -- the single genuine hard sequencing constraint the design names. The
#111 -> #112 -> #119 path is also length 3; #119 waits on the later of {#112, #118}.

**Immediate start**: #111 (the only no-dependency issue; the foundation).

**Parallelization**:
- After #111: #112, #114, #115, and #118 can proceed in parallel (the four direct children
  of the references).
- After #112: #113 (bundled into Slice A's PR) and #116 can proceed in parallel.
- After #116: #117.
- After #112 and #118: #119.

**Recommended PR order**: Slice A (#111, #112, #113) first, since it is the foundation and
lands repo-wide error-level table validation. Once Slice A merges, Slices B (#114), C
(#115), D (#116, #117), and the Slice E spike (#118) can proceed in parallel; the
reconciliation increment (#119) lands last, after the spike resolves.

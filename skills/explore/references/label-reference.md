# Label Reference

Centralized vocabulary for issue labels used in the artifact workflow system.

## Label Vocabulary

| Label | Meaning | Lifecycle | Mermaid Class | Color |
|-------|---------|-----------|---------------|-------|
| `needs-triage` | Unclassified, needs basic assessment | Resolves to a `needs-*` label or "ready" | _(none)_ | -- |
| `needs-design` | Needs architectural design | Full (needs-* -> tracks-plan -> done) | `needsDesign` | #e1bee7 (purple) |
| `needs-prd` | Needs requirements definition | Lightweight (needs-* -> tracks-plan or removed) | `needsPrd` | #b3e5fc (light blue) |
| `tracks-plan` | PLAN created, implementation underway | Tracking (stays until all plan issues done) | `tracksPlan` | #FFE0B2 (orange) |

The feasibility label and the single-choice label this file used to carry are
retired. The only step that assigned them was `/explore`'s Phase 0
artifact-type triage, which committed before any research existed and is gone.
Both questions stay reachable as crystallize outcomes instead: `/explore`
authors the spike report, and `/decision` owns the decision record.

## Lifecycle Flow

The surviving `needs-*` labels follow the same general flow:

1. A human, or roadmap decomposition in `/plan`, assigns a `needs-*` label.
   `/explore` assigns none: it reads them as entry signals and decides where the
   work goes in its crystallize step instead.
2. The upstream work produces the artifact -- `/scope` runs the tactical chain,
   or a child skill (`/brief`, `/prd`, `/design`, `/plan`) runs alone when the
   author already knows the altitude
3. The `needs-*` label is removed when the artifact completes
4. If a PLAN document is created, `tracks-plan` is applied (via `swap-to-tracking.sh`)
5. `tracks-plan` stays until all plan issues are done, then the issue is closed

## Where Routing Happens

`/explore` has one routing surface: the crystallize step in Phase 4, which runs
after the research. It scores what the exploration is -- a rejection record, a
spike report, a decision, a competitive analysis, or a chain -- and then, for a
chain, which entry point receives it: file an issue, `/scope`, `/charter`, or
`/execute`. See `quality/crystallize-framework.md`.

Phase 0 no longer routes. When the topic came from a `needs-triage` issue, it
runs an entry assessment (investigation, breakdown, or ready) and writes the
result into the scope file as evidence for crystallize. It assigns no label and
sends the author nowhere.

## Detailed Lifecycle Rules

Each label's lifecycle rules live with the skill that clears it:

| Label | File | Section |
|-------|------|---------|
| `needs-design` | `design/references/lifecycle.md` | Label Lifecycle |
| `needs-prd` | `prd/references/phases/phase-4-validate.md` | 4.6 Handle Approval |

For Mermaid class definitions, CI validation rules, and child reference row format,
see the `implementation-diagram` and `plan` skills.

# Label Reference

Centralized vocabulary for issue labels used in the artifact workflow system.

## Label Vocabulary

| Label | Meaning | Lifecycle | Mermaid Class | Color |
|-------|---------|-----------|---------------|-------|
| `needs-triage` | Unclassified, needs basic assessment | Resolves to a `needs-*` label or "ready" | _(none)_ | -- |
| `needs-design` | Needs architectural design | Full (needs-* -> tracks-plan -> done) | `needsDesign` | #e1bee7 (purple) |
| `needs-prd` | Needs requirements definition | Lightweight (needs-* -> tracks-plan or removed) | `needsPrd` | #b3e5fc (light blue) |
| `needs-spike` | Needs feasibility investigation | Lightweight (needs-* -> tracks-plan or removed) | `needsSpike` | #ffcdd2 (light red) |
| `needs-decision` | Needs single architectural choice | Lightweight (needs-* -> tracks-plan or removed) | `needsDecision` | #d1c4e9 (light indigo) |
| `tracks-plan` | PLAN created, implementation underway | Tracking (stays until all plan issues done) | `tracksPlan` | #FFE0B2 (orange) |

## Lifecycle Flow

All `needs-*` labels follow the same general flow:

1. `/triage` or `/plan` (roadmap decomposition) assigns a `needs-*` label
2. The appropriate upstream workflow produces the artifact (`/explore`, `/prd`, `/design`)
3. The `needs-*` label is removed when the artifact completes
4. If `/plan` creates a PLAN document, `tracks-plan` is applied (via `swap-to-tracking.sh`)
5. `tracks-plan` stays until all plan issues are done, then the issue is closed

For inline implementation (common for spikes and decision records): the `needs-*` label
is removed when the artifact completes, and the issue is worked on directly or closed.

## Triage Routing

Two-stage triage determines the appropriate label:

**Stage 1** -- Investigation vs. Actionable:
- "Needs investigation" (upstream artifact work required) -> proceed to Stage 2
- "Needs breakdown" (well-understood but too large) -> ready, apply size labels
- "Ready" (atomic, clear AC) -> ready for `/work-on`

**Stage 2** -- Investigation type (only if Stage 1 = "needs investigation"):
- `needs-prd`: requirements unclear or contested
- `needs-design`: what is clear, how is not
- `needs-spike`: feasibility unknown
- `needs-decision`: single choice between known options

**Primary gap heuristic**: when both requirements AND approach are unclear, route to the
earlier-stage artifact (PRD before design).

## Detailed Lifecycle Rules

Each artifact type has its own lifecycle rules documented in its skill:

| Label | Skill | Section |
|-------|-------|---------|
| `needs-design` | `design/SKILL.md` | Label Lifecycle |
| `needs-prd` | `prd/SKILL.md` | Label Lifecycle |
| `needs-spike` | `spike-report/SKILL.md` | Label Lifecycle |
| `needs-decision` | `decision-record/SKILL.md` | Label Lifecycle |

For Mermaid class definitions, CI validation rules, and child reference row format,
see the `implementation-diagram` and `plan` skills.

# /prd Scope: roadmap-issueless-table-rendering

## Phase
2

## Execution mode
auto (background dispatch; decisions follow `references/decision-protocol.md`
recommended defaults and are recorded in the PRD's Decisions and Trade-offs)

## Upstream
docs/briefs/BRIEF-roadmap-issueless-table-rendering.md (Accepted)

## Source issue
tsukumogami/shirabe#261

## Coverage

| Concern | Covered by |
|---------|-----------|
| Who is affected | Authors and reviewers of roadmaps in repos declaring `## Roadmap Issues: optional` |
| What is broken | Key column carries `F<n>`; description cell is unbounded |
| Why now | Reported against a 21-feature roadmap; the second finding restates a closed report |
| Success shape | Table readable without cross-reference; three documents agree |
| Constraints | Reserved sections are tool-generated; `shirabe validate` must stay clean; label metacharacters round-trip verbatim |
| Boundaries | See the BRIEF's Scope Boundary |

## Research leads and their resolution

All four leads were investigated directly against the code and the validator
rather than by proxy; findings are recorded in
`wip/research/prd_roadmap-issueless-table-rendering_phase2_findings.md`.

1. Does the shared spec actually require the label, or is that a misreading?
2. Does keying on the label break FC06 or FC07?
3. Is the description defect a regression, or was the path never covered?
4. What does the current renderer actually emit today?

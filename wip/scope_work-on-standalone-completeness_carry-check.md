# Carry check: BRIEF absorbed into PRD

Stage 4 of the consolidation judgment for the `brief -> prd` edge. Run before
anything was written. Any `carried: false` aborts the absorb.

The ancestor carries no `absorbed:` list of its own and no inherited
contributions, so this check covers its own required sections and its single
contribution.

| Ancestor section | Carried | Where it landed in the survivor |
|---|---|---|
| Status | n/a | Lifecycle metadata, not a contribution. The survivor has its own. |
| Problem Statement | true | PRD `## Problem Statement`, restated in full — the PRD format requires a PRD to state its own problem so a cold reader needs no upstream. Both halves of the framing survive: the cascade being unreachable with one half already fixed, and the obligations existing but unenforced. |
| User Outcome | true | PRD `## Goals`, including the load-bearing second clause — that a run which cannot finish stops and names the obligation it could not discharge rather than reaching a terminal state reading as success. |
| User Journeys (1) no documents behind it | true | PRD user story 1, plus R2 and R3. R3 carries the journey's point verbatim: "A maintainer fixing an ordinary bug must not learn that a cascade step exists." |
| User Journeys (2) last issue behind a design | true | PRD user story 2, plus R1. |
| User Journeys (3) orchestrator, cascade once | true | PRD user story 4, plus R11 and R13. R13 carries the cadence-unchanged point. |
| User Journeys (4) pointing the single-issue skill at a plan | true | PRD user story 5, plus R15. |
| Scope Boundary — six IN items | true | Covered by requirements; verified independently by the completeness reviewer across four rounds, most recently against the frozen text. |
| Scope Boundary — six OUT items | true | PRD `## Out of Scope`, each with its reason preserved. Verified independently by the completeness reviewer. |
| Contribution: feature framing (WHY / WHO) | true | Distributed across the survivor's Problem Statement, Goals, User Stories and Out of Scope, and summarized into the `## Feature Framing` contribution section composed from the survivor's own body. |

**Result: no `carried: false`. The absorb proceeds.**

Two notes a later reader may want.

The ancestor's three Open Questions were closed earlier, at its own Draft to
Accepted transition, into the survivor's Decisions and Trade-offs section. They
are not re-itemized above because they were already discharged before this
judgment fired.

The contribution section is composed from the survivor's own body rather than
from the document being deleted, per the procedure. That is what makes a single
unreviewed authoring site tolerable here: the material was reviewed when it
landed in the survivor's ordinary sections, and an under-distillation leaves the
omitted content still visible in the survivor rather than gone at the delete.

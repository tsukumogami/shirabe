# /scope Handoff: scope-then-execute

## Provenance
Written by `/explore` on 2026-09-22 from `wip/explore_scope-then-execute_crystallize.md`.
Research files: `wip/explore_scope-then-execute_findings.md`,
`wip/explore_scope-then-execute_decisions.md`, and
`wip/research/explore_scope-then-execute_r1_lead-*.md`.
One discover-converge round with five leads. It ran in auto mode until the
author offered to take questions and answered three, which reshaped the
coordinated/multi-pr question around caller intent.

## Problem Statement
An author can't launch one session with the goal "run `/scope`, then execute the
PLAN, done when merged", because the execution mode is decided late inside
`/scope`, and not every mode can be driven to completion by the session that
scoped it. Underneath, the modes mix two things: work shape (one PR or several)
and whether a driver stays with the work. Three mechanical gaps make any combined
run fail regardless of mode: `/scope` never pushes or opens a PR, no skill
merges, and `/scope` ends without naming or taking the next step.

## Scope Boundary
### In scope
- Letting the caller declare intent at `/scope` launch: continue into execution,
  or stop at PLAN.
- Resolving multi-PR splits by intent: `coordinated` when continuing, `multi-pr`
  when stopping, with `single-pr` preferred in both.
- Allowing `coordinated` for single-repo work, which the coordination contract
  currently forbids.
- The continuation from `/scope` into `/execute` for single-pr and coordinated.
- `/scope` pushing its branch and opening a draft PR so `/execute` adopts it.
- A permission-checked merge step, falling back to "ready, green, handed off".
- Suspend and resume on the coordination PR when a coordinated run can't merge.
- The multi-pr stop: the docs PR lands the Active PLAN on main, and the run
  reports the unblocked issues.
- Correcting stale routing: `/plan` Phase 7 and `/scope`'s resume redirect point
  single-pr and Active PLANs at `/work-on`, and `/execute` and `/work-on` claim
  "merged" in their docs.

### Out of scope
- Automatic per-issue fan-out through `niwa dispatch`. It depends on whether
  per-issue `/work-on` runs end at `done_blocked` under the new cascade, which
  hasn't been verified by a real run.
- Moving multi-pr into `/execute`. That's designed elsewhere and not landed.
- Changing `/plan`'s split triggers themselves.

## Decisions Already Settled
- "Done" means merge when permitted: an opt-in, permission-checked merge;
  without rights, the run ends ready and green, handed off for merge (author).
- Coordinated and multi-pr get different post-scope behavior. Multi-pr is the
  only mode whose Active PLAN may merge to main, so it stops after scoping.
  Coordinated continues with the session as its driver (author).
- Intent, not work shape or repo count, is what separates coordinated from
  multi-pr. This was recommended by the exploration and accepted by the author
  when reviewing the framing.
- The launch-time uncertainty is resolved by declaring intent, not by predicting
  the mode.

## Coverage Notes
- Where the continuation lives is open: a flag on `/scope`, a thin driver skill
  in the parent-of-the-parent slot the parent-skill pattern names, or a goal
  recipe paired with exit-time branching. The trade-off is the house rule that
  parents stop and name the next command rather than invoke each other.
- How intent reaches `/plan` is open. `/scope` passes `/plan` only the DESIGN
  path today, the Delivery Preference stack documents a flag layer `/plan` never
  defines, and how `/plan` currently learns to write `execution_mode: coordinated`
  isn't documented.
- What a single-repo coordination PR looks like is open. The contract's
  cross-repo grouping and two-node merge-order DAG need a single-repo reading.
- Whether `/scope --auto` forwards `--auto` to `/plan`, so the split prompt and
  issue-filing approval don't block an unattended run.
- Merge-step details: how permission is detected, and whether it's opt-in per
  run or per repo.
- Whether `wip/execute_*` state gets committed on the shared branch and what
  cleans it.

## Upstream Observations
No ROADMAP, VISION, or STRATEGY covers this. Relevant existing references:
`references/coordination-strategy.md` (defines coordinated as multi-repo, with a
coordination PR merging last), `references/parent-skill-pattern.md` (the
parent-of-the-parent slot), `references/parent-skill-state-schema.md`
(`plan_execution_mode` enum missing `coordinated`), and
`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md` ("the agent
marks ready; the human merges"), which a merge step would amend.

## Framing-Shift Answer
**Pre-supplied answer:** yes, the framing shifted
**Evidence:** The author started from "single-pr and coordinated can be finished
in one session, multi-pr can't". Round 1 found that coordinated blocks on merges
just like multi-pr, and that no mode merges today. After reviewing that, the
author proposed, and the exploration recommended, treating caller intent as the
axis that separates coordinated from multi-pr. The problem moved from
"predict the mode" to "declare intent, and make every mode under that intent
drivable".

## Shape Signals
### Architectural alternatives left open
- Continuation as a `/scope` flag: smallest change, but bends the parents-as-peers
  rule.
- Continuation as a thin driver skill: keeps `/scope` and `/execute` unchanged,
  and adds a skill.
- Continuation as a documented goal recipe: no new skill, but intent never
  reaches `/plan`, so it needs exit-time branching.
- Intent plumbing to `/plan`: a new delivery/intent flag forwarded by `/scope`,
  or `/scope` rewriting the mode after `/plan` returns.

### Complexity signals
- The change touches four skills (`/scope`, `/plan`, `/execute`, `/work-on`) and
  two shared contracts (the coordination strategy and the draft/ready design).
- Redefining coordinated for single-repo work contradicts an explicit line in
  the coordination contract.
- Adding a merge step widens `/execute`'s allowed write targets and amends a
  recorded design decision.

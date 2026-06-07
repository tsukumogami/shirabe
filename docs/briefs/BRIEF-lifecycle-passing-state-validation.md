---
schema: brief/v1
status: Done
problem: |
  shirabe's diff-scoped validator cannot see presence-without-touch, and the
  previously codified two stateless lifecycle checks treat each doc in
  isolation. A chain of BRIEF, PRD, DESIGN, and PLAN docs can drift out of
  step with each other — for example, a single-pr chain ships and the BRIEF
  and PRD stay at Accepted instead of transitioning to Done — and the
  current validation surface never fires.
outcome: |
  A contributor running `shirabe validate --lifecycle <root>` learns whether
  every doc in every artifact chain is at the state the current PR needs it
  to be at — its passing state for the chain's posture — and gets a precise
  error naming any drifted doc, its current state, and the state expected
  for the chain to ship. Drift between a chain's docs becomes a CI signal
  rather than a silent corpus problem found months later.
upstream: docs/designs/DESIGN-roadmap-plan-standardization.md
---

# BRIEF: lifecycle-passing-state-validation

## Status

Done

The framing is fresh; the downstream PRD will operationalize the
requirements articulation against the two pre-settled decision records
named in the References section.

## Problem Statement

shirabe ships a validator that catches content drift inside one doc and
cross-reference drift between two docs that the diff under review actually
touches. It does not catch drift between docs in the same chain when the
PR under review does not touch every link in the chain. A BRIEF stuck at
Accepted while its downstream PLAN has finished and been deleted, a
multi-pr PLAN at Done that the author forgot to delete, a BRIEF that was
written but whose PRD was never authored — none of these surface as a
validator error today, because the validator's lens is one doc or one
diff at a time.

The previously codified L01 and L02 checks tried to address part of this
by reading the whole tree once and flagging present multi-pr docs at non-
Active status or present single-pr PLANs. Those two checks treat each
doc in isolation; they do not relate a doc's state to the chain it
belongs to. The result is a check surface that can miss the drift the
team most wants to catch — a chain whose links are individually valid
but collectively incoherent — while flagging healthy cases that look
wrong only because the model has no concept of a chain.

The two recent corpus reconciliation PRs make this concrete. The PR
that shipped the FC09 doc-vs-github-state reconciliation single-pr
chain stopped the BRIEF and PRD at Accepted; the FC08 legend-vs-
classdef reconciliation single-pr chain followed the same shape. Both
chains delivered the work,
both PLANs were deleted, and neither chain's framing docs were
transitioned to Done. A chain-aware check would have caught the
inconsistency at PR time; the absence of one let the drift land. The
corpus now needs reconciliation for FC08 and FC09 alongside the new
check that prevents the next instance.

## User Outcome

A shirabe contributor opening a PR against this repo runs the validator
and learns, in one pass, whether the chains of framing-and-execution
documents the PR participates in are coherent for the PR currently
under review. The same contributor opening a PR that completes a multi-
pr chain — by transitioning the PLAN, deleting it, and transitioning
the upstream BRIEF and PRD to their target state — sees the check pass
once those transitions all land in the same commit set. A contributor
who forgets one transition (for example, marks the PLAN Done but does
not include the deletion in the same PR) sees the check fail with the
file path, the current state, and the expected passing state on the
line.

The contributor never needs to remember, from memory, which docs in a
chain are supposed to be at which state given the posture of the work
in flight. The validator names the expected state every time it fails,
and the chain-aware passing-state model is the rule the validator
applies.

## User Journeys

### A contributor lands a single child issue in a multi-pr chain

A contributor opens a PR that closes one child issue from a 12-issue
milestone driven by a multi-pr PLAN. The PR touches one set of source
files plus the parent PLAN's strikethrough row for the child issue. The
chain's BRIEF is at Accepted, the chain's PRD is at Accepted, the
chain's DESIGN is at Current in `docs/designs/current/`, and the PLAN
is at Active. The contributor runs `shirabe validate --lifecycle .` and
the check passes — all chain members are at their passing state for the
in-flight multi-pr posture (BRIEF Accepted, PRD Accepted, DESIGN
Current, PLAN Active).

### A contributor opens the final PR that completes a multi-pr chain

The same multi-pr chain reaches its last child issue. The contributor
opens the verify-then-delete PR with four commits: change the PLAN
frontmatter status from Active to Done, change the BRIEF frontmatter
status from Accepted to Done, change the PRD frontmatter status from
Accepted to Done, and `git rm` the PLAN doc. The DESIGN was already at
Current. The contributor runs `shirabe validate --lifecycle .` against
the resulting working tree. The PLAN is absent, the BRIEF and PRD are
at Done, the DESIGN is at Current, and the check passes — every chain
member is at its passing state for the at-merge multi-pr posture
(BRIEF Done, PRD Done, DESIGN Current, PLAN deleted).

### A contributor forgets to delete the PLAN

The contributor on the final multi-pr PR remembers to transition the
PLAN frontmatter to Done and to transition BRIEF and PRD, but forgets
the `git rm`. The check fails on that working tree: `Lnn: PLAN at
Done is present in the tree; expected DELETED for the work-completing
multi-pr posture (file: docs/plans/PLAN-foo.md)`. The contributor adds
the deletion commit, re-runs the check, and it passes. The Done-but-
present state is the forcing function the check enforces — the only
way out is to delete the file, which is exactly the discipline the
chain-aware model exists to make non-optional.

### A contributor works on a single-pr chain mid-PR

A contributor working on a single-pr chain has the BRIEF and PRD at
Accepted, the DESIGN at Current in `docs/designs/current/`, and the
PLAN at Draft in `docs/plans/`. The PR is the single PR that will
deliver the whole feature; mid-PR the PLAN is still present and at
Draft. The contributor runs `shirabe validate --lifecycle .` and the
check passes — single-pr mid-PR posture is BRIEF Accepted, PRD
Accepted, DESIGN Current, PLAN Draft, and every chain member matches.
At PR-merge time the same contributor will delete the PLAN and
transition BRIEF and PRD to Done; the check passes again on that
final working-tree state.

### An author reads the orphan-doc rule before the PRD or DESIGN

An author scanning the repo for a feature whose framing has settled
but whose PLAN never landed sees a long-lived BRIEF at Done with no
downstream PLAN. The author runs `shirabe validate --lifecycle .` and
the check passes the orphan BRIEF: its current state (Done) equals
its target state, so the orphan-doc rule treats it as the healthy
post-completion shape — the work shipped, the PLAN was deleted, the
framing remains as the durable record. Months earlier, a different
author had created a BRIEF, transitioned it to Accepted, and then
never written the PRD. The check fails that second BRIEF: `Lnn:
BRIEF at Accepted is orphan (no downstream PRD references it via
upstream:); expected Done (orphan target state) or downstream chain
in progress`. The forcing function is the same shape as the rest of
the chain-aware model — drive the work forward or transition the
framing to its terminal state — and the two worked cases (post-
completion orphan passes; stalled-framing orphan fails) are the two
prongs of one rule.

## Scope Boundary

### IN scope

- The `shirabe validate --lifecycle <root>` CLI mode, including the
  non-zero exit on any chain-member-not-at-passing-state condition.
- The chain-walker that follows inverse `upstream:` traversal from each
  PLAN and ROADMAP in the tree to discover BRIEF, PRD, and DESIGN
  chain members.
- Posture inference per chain (multi-pr in-flight vs work-completing,
  single-pr mid-PR vs at-merge) from PLAN execution_mode and status,
  per the multi-pr posture-detection decision record.
- Passing-state computation per artifact type per posture.
- The orphan-doc rule per the orphan-doc-passing-state-rule decision
  record, including the ROADMAP-rooted exception for non-terminal-
  status orphans whose own `upstream:` points at an Active ROADMAP.
- The `Lnn` family of check-code-and-error-message format. Error
  messages name the file path, the current state, and the expected
  passing state.
- Corpus reconciliation in the same PR: the FC09 BRIEF and PRD
  transition from Accepted to Done, and the FC08 BRIEF and PRD
  transition from Accepted to Done.
- An amendment to the parent PRD at
  `docs/prds/PRD-roadmap-plan-standardization.md` (R17 and R18) that
  replaces the two-stateless-checks framing with the chain-aware
  passing-state model. The `Lnn` check-code family stays.
- Defensive frontmatter parsing — no panics on malformed `upstream:`
  fields, cycle structures, or missing fields.
- Walk bounded to the given root path; no symlink escape outside the
  root.

### OUT of scope

- CI wiring that runs `--lifecycle` on every PR. The downstream CI
  integration issue owns the workflow job that invokes this mode;
  the present work delivers the mode itself.
- A ROADMAP-lifecycle check that catches ROADMAPs aging out at non-
  terminal status. The orphan rule's Active-ROADMAP exception covers
  the in-flight case; a separate downstream surface owns the stale-
  ROADMAP question.
- Extending `shirabe transition` to cover the Plan format. The
  validator reads the PLAN frontmatter status field; the gesture that
  sets the field is a manual frontmatter edit in v1. A future
  transition-tool extension is independently sequenced.
- Validating chains that span multiple repositories. The chain-walker
  walks the doc tree under the given root; cross-repo `upstream:`
  pointers are out of scope for this iteration.
- Auto-fixing drifted docs. The check reports drift; the author drives
  the chain forward. Auto-fix is a separate value proposition.

## References

- `docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md`
  — settles the orphan-doc passing-state rule the
  `## User Journeys` section's orphan-doc journey encodes. The
  decision rejects orphan-strict-naive (provably unworkable on the
  corpus) and orphan-permissive (undermines the chain-aware model's
  reason for existing) in favor of a terminal-aware refinement that
  tolerates orphans at their target state and fails orphans at non-
  terminal status with a ROADMAP-rooted exception.
- `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md`
  — settles posture detection for multi-pr chains via the PLAN
  frontmatter status field. Active and present means in-flight; Done
  and present means work-completing-but-not-yet-deleted (the check
  fails to force the deletion); absent means at-merge.
- `docs/designs/DESIGN-roadmap-plan-standardization.md` — the parent
  design this work amends. Decision 5 of that document codifies the
  whole-tree `--lifecycle` scan as a separate CI surface; the present
  brief takes Decision 5's stateless-pair framing and reshapes it
  into a chain-aware passing-state model.
- `docs/prds/PRD-roadmap-plan-standardization.md` — the parent PRD
  the present chain amends. R17 and R18 carry the two-stateless-
  checks framing; the work this brief frames replaces both with the
  chain-aware passing-state model, retaining the `Lnn` check-code
  family.

---
status: Accepted
decision: |
  The policy owner picked "Children skip push/PR". Under a parent skill, a child keeps its own verdict and status transition but skips its push, pull request, cleanup commit, branch creation and routing prompts; the dispatch reference is rewritten to match.
rationale: |
  /scope promises one push and one pull request at exit and a closed set of
  write targets, but the child skills it runs each push, open pull requests
  or ask routing questions of their own. Keeping each child's verdict and
  status transition preserves the per-artifact gate the next hop depends on:
  /design and /plan require their upstream already accepted. Dropping only
  the steps that collide with /scope's publish model is the smallest change
  that makes every stated promise true.
---

# DECISION: child skills under /scope keep their verdict, skip publishing

## Status

Accepted on 2026-09-28. The policy owner answered this item of the
contradiction-settlement inventory (coordination PR shirabe#507).

## Context

This is the `child-steps-under-scope` item: child skills run their own
approval, push and pull-request steps under /scope.

Each child skill /scope runs carries its own approval prompt, status
transition and commits, and /brief, /prd and /design also push and open a
pull request:

- /brief asks for approval even when both reviewers pass, then pushes and
  runs `gh pr create` (`skills/brief/references/phases/phase-5-finalize.md`).
- /prd asks for approval and creates a pull request, and creates a branch
  when on an unrelated one (`skills/prd/`).
- /design commits, pushes and creates a pull request, and asks "Plan or
  Approve" (`skills/design/`).
- /plan asks about an upstream issue and runs `gh issue edit`
  (`skills/plan/references/phases/phase-7-creation.md`).

None of those steps checks the `parent_orchestration` sentinel. /scope, for
its part, says nothing pushes during the chain, and its closed write-target
set names the publish script's `gh` calls as its only `gh` writes. The
dispatch reference, `references/fixes/sub-agent-dispatch.md`, says children
leave artifacts at Draft or Proposed for the parent to approve, but /plan
hard-stops unless the DESIGN is already Accepted, and /scope never
transitions anything. Under /scope the children push and open pull requests
that /scope says never happen, and the reference describing child behavior
under a parent describes a flow that would stall the chain.

## Decision

The policy owner picked "Children skip push/PR". Under a parent skill, a child keeps its own verdict and status transition but skips its push, pull request, cleanup commit, branch creation and routing prompts; the dispatch reference is rewritten to match.

## Implementation notes

These notes are execution guidance for the items that apply this decision,
not the policy owner's words.

- An unattended run takes the recommended approval and says so.
- Escalation is also described in
  `DECISION-contradiction-design-inline-decision-fallback-2026-09-28.md` and
  `DECISION-contradiction-worktree-intent-change-owner-2026-09-28.md`.
- This is the DESIGN's option 1, which was the recommendation.
- The statements live in /brief, /prd, /design, /plan, /scope and the
  dispatch reference, so the change lands in each of those skills' pull
  requests in the contradiction-settlement PLAN. The dispatch reference's
  carve-out section is handled separately and is not part of this change.

## Options Considered

- **Option 1 (chosen): Children keep their verdict and status transition but skip
  push, PR, cleanup commit, branch creation and routing prompts under the
  sentinel.** The smallest change that makes every stated promise true.
- **Option 2: Parent-delegated approval as the dispatch reference
  describes.** Adds a per-hop approval and transition to /scope and changes
  /design's and /plan's preconditions.
- **Option 3: Keep today's behavior and drop /scope's one-push promise.** No
  child change, but a no-intent /scope run then pushes, and an intent run can
  open two pull requests.

## Consequences

Until this record merges, the statements it governs stay as they are. After
it merges, a child run under /scope still reaches its own verdict and status
transition, and /scope alone pushes and opens the pull request. The dispatch
reference describes that flow instead of parent-delegated approval.

## References

- shirabe#507 (the contradiction-settlement DESIGN, PLAN and inventory)
- `references/fixes/sub-agent-dispatch.md`
- `skills/scope/SKILL.md`
- `skills/scope/references/phases/phase-2-chain-orchestration.md`

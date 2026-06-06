---
schema: brief/v1
status: Accepted
problem: |
  Three workflow-level bugs in shirabe pattern v1 fire on routine chain
  runs with silent failure modes catastrophic enough to stop the operator
  mid-work and force manual recovery. They surfaced during recent
  v0.7.0/0.7.1-dev dogfooding and recur on every chain.
outcome: |
  An operator running `/scope`, `/work-on` against single-pr PLANs, and
  `/work-on` against long-running PRs reaches the terminal artifact
  without manual recovery: chain handoffs auto-transition status, single-pr
  PLAN dependency chains spawn sequentially, and upstream main changes are
  caught mid-chain rather than at PR finalization.
---

## Status

Accepted

## Problem Statement

Three bugs in shirabe pattern v1 workflow primitives surfaced during the
same recent dogfooding window — the `/comp` skill work in
tsukumogami/shirabe#141 and the child-dispatch-contract work in
tsukumogami/shirabe#151 — and each one cost the operator hours of manual
recovery before the chain could continue. They are unrelated at the code
level (a regex in `plan-to-tasks.sh`, status-gate logic across `/design`
and `/plan`, worktree-discipline coverage in `/work-on`) but they share a
failure shape: each fires on a path operators take routinely, each fails
silently, and each leaves the chain in a state where the operator can't
tell something went wrong until the downstream cost has already
accumulated.

The three bugs:

- **tsukumogami/shirabe#156** — the single-pr `plan_outline` parser in
  `plan-to-tasks.sh` drops every dependency edge when a PLAN writes
  `**Dependencies:**` (colon inside the bold markers) instead of
  `**Dependencies**:`. A 9-issue linear chain parallelizes into
  overlapping commits on the shared branch. No warning, no validator
  error.
- **tsukumogami/shirabe#159** — `/prd` auto-transitions a Draft BRIEF to
  Accepted when receiving one as input, but `/design` and `/plan`
  hard-stop their Phase 0/1 status gates with "must be Accepted" and
  refuse to do the same transition. Every `/scope` chain handoff trips
  the asymmetry; the operator runs `transition-status.sh` by hand to
  unblock each child.
- **tsukumogami/shirabe#162** — `/work-on` driving a long-running PR
  doesn't fetch origin/main between commits. When an upstream change
  invalidates the PLAN's architectural assumptions mid-chain (the Go-to-Rust
  validator cutover that deleted `internal/validate/` during the `/comp`
  PLAN implementation), the PR goes `mergeStateStatus=DIRTY`, GitHub
  silently stops creating CI check-runs, and the `ci_monitor` gate waits
  indefinitely for checks that will never appear.

The common shape across the three is "catastrophic-by-default on a
routinely-taken path, with no signal that recovery is needed." Operators
hit these on normal use, not on edge cases. The framing this brief carries
forward is that the workflow friction here is a coordinated three-bug
sweep, not three independent fixes scheduled together; treating them as a
unit keeps the downstream PRD honest about the shared failure shape they
all answer to.

## User Outcome

An operator runs `/scope <topic>` and watches the chain pass through
`/brief -> /prd -> /design -> /plan` without ever opening a second
terminal to run `transition-status.sh`. The status-gate friction that
forced the operator into the loop is gone.

An operator runs `/work-on` against a single-pr PLAN whose issues form a
linear dependency chain — issue N+1 edits files issue N created — and the
orchestrator spawns the children sequentially in the order the PLAN
declares. The catastrophic parallelization that silently broke
intermediate states is no longer reachable through routine authoring.

An operator runs `/work-on` driving a multi-hour PR and an upstream merge
to main invalidates the architectural assumption the PLAN was built
against. The operator finds out mid-chain — through a real signal — that
the foundation has shifted, rather than discovering it at PR finalization
when CI has been silently suppressed for hours and the rebase cost is
maximal.

The three outcomes share a center of gravity: an operator on the standard
workflow path stops paying a recovery tax that recurs on every chain. The
operator's experience of running shirabe's chain workflows stops including
a step where they have to know to look for failures that the tooling
should have surfaced itself.

## User Journeys

### Chain handoff completes without manual transitions

A shirabe maintainer runs `/scope <topic>` to drive a feature through
`/brief -> /prd -> /design -> /plan` in one sitting. Each child skill picks
up its upstream artifact (BRIEF for `/prd`, PRD for `/design`, DESIGN for
`/plan`) at the status the previous child left it in, transitions it as
part of its own Phase 0/1 handoff handling, and proceeds. The operator
never needs to drop into a shell, find the upstream document, and run
`transition-status.sh` to satisfy a downstream status gate. (#159)

### Single-pr PLAN with linear chain spawns sequentially

A shirabe maintainer runs `/work-on <plan-path>` against a single-pr PLAN
whose 9 issues form a strictly-linear dependency chain. The orchestrator
parses the PLAN's `**Dependencies:**` lines (whichever colon placement
the author used), resolves the dependency graph, and dispatches children
in dependency order on the shared branch. The intermediate states stay
consistent; the operator does not have to recover from overlapping
commits on incompatible foundations. (#156)

### Upstream main change is caught mid-chain

A shirabe maintainer runs `/work-on` against a multi-hour single-pr PLAN.
While the chain is running, another PR lands on main that changes a file
the PLAN's DESIGN took as foundational. The next time `/work-on` makes a
commit, the orchestrator detects the upstream change, classifies its
impact against the PLAN, and surfaces an escalation rather than continuing
to build against a foundation that has been replaced. The PR does not
silently go DIRTY; CI check-runs are not suppressed; the operator finds
out at the point recovery is cheapest. (#162)

## Scope Boundary

**IN scope:**

- The three specific bugs named in tsukumogami/shirabe#156, #159, #162.
- Each bug's fix surfaces a normal-path workflow signal that is currently
  silent — the brief commits to the failure shape, not to a specific fix
  mechanism per bug.
- The fixes are coordinated as a single sweep because they share the
  "catastrophic-by-default, silent-by-default" failure shape.

**OUT of scope:**

- Other open shirabe issues that surfaced in the same dogfooding window
  but are not part of the silent-by-default failure shape:
  tsukumogami/shirabe#155, #157, #158, #160, #161, #163, #164. Each stays
  open as its own work stream and is not scheduled by this brief.
- The broader pattern-v1 ergonomics work — the larger workflow refactor
  the dogfooding surfaced patterns for — which is downstream-roadmap
  territory (SE12) and not within this brief's frame.
- The solution shape for each bug. The issue bodies enumerate candidates
  per bug (parser loosening vs. warning vs. validator check for #156;
  auto-transition vs. documented contract vs. sentinel-gated transition
  for #159; full worktree-discipline vs. operator-rebase doc vs.
  `ci_monitor` fix for #162). Picking one option per bug is the
  downstream DESIGN's job; the brief commits to fixing the failure, not
  to a mechanism.
- Refactoring of `plan-to-tasks.sh`, the status-gate framework, or
  `/work-on`'s orchestrator beyond what each fix actually needs.

## References

- tsukumogami/shirabe#156 — `plan-to-tasks.sh` single-pr parser drops
  dependency edges when colon is inside bold markers.
- tsukumogami/shirabe#159 — `/design` and `/plan` chain-handoff status
  gates are asymmetric with `/prd`'s brief-handoff.
- tsukumogami/shirabe#162 — `/work-on` doesn't check upstream main
  between commits, allowing DESIGN staleness mid-chain.

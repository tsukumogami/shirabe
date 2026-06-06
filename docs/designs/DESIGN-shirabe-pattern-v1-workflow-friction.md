---
upstream: docs/prds/PRD-shirabe-pattern-v1-workflow-friction.md
---

# DESIGN: shirabe pattern-v1 workflow friction sweep

## Status

Proposed

## Context and Problem Statement

PRD-shirabe-pattern-v1-workflow-friction binds three independent
contracts against the three pattern-v1 surfaces it covers
(`plan-to-tasks.sh` for `tsukumogami/shirabe#156`, the `/design` and
`/plan` Phase-0/Phase-1 status-gates for `tsukumogami/shirabe#159`,
and `/work-on`'s plan-orchestrator loop plus the `ci_monitor` state
for `tsukumogami/shirabe#162`). The PRD's R12-R13 add a sweep-level
constraint pair: no fix may silently alter behavior outside the three
named bugs, and each bug's fix must be independently shippable.

The technical problem this design solves is picking one fix candidate
per bug from the enumerations in the three issue bodies, naming the
specific files and entry points each fix edits, and proving the chosen
combination keeps the sweep within R12-R13's blast-radius envelope.
Three substrate surfaces are in scope:

- **Bash script substrate** for #156. The single-pr parsing path in
  `skills/plan/scripts/plan-to-tasks.sh` lives in shell. Line 288's
  regex `\*\*Dependencies\*\*:[[:space:]]*(.+)$` is the silent-failure
  surface; the multi-line `### Dependencies` accumulator at lines
  312-339 is the surface R3 protects.
- **Skill-phase prose substrate** for #159. `/design`'s Phase 0 lives
  at `skills/design/references/phases/phase-0-setup-prd.md` step 0.2;
  `/plan`'s Phase 1 lives at `skills/plan/references/phases/phase-1-analysis.md`
  step 1.1; `/prd`'s reference behavior is documented in
  `skills/prd/SKILL.md` lines 132-138. The contract is symmetric
  reads against symmetric writes.
- **Koto template + phase prose substrate** for #162. The
  `ci_monitor` state declared at `skills/work-on/koto-templates/work-on-plan.md`
  lines 84-111 (gate command at line 89-90, prose at line 226) is the
  silent-wait surface; the per-issue commit loop in `/work-on`'s
  plan-orchestrator mode (driven by the same koto template) is the
  upstream-drift surface. The substrate-shared reference
  `references/parent-skill-worktree-discipline.md` already defines
  the None/Informational/Intent-changing classification R8 names.

The three substrates do not interact — a fix that edits one shell
regex cannot inadvertently change a koto gate command, and a phase-prose
edit in `/design` Phase 0 cannot regress the single-pr parser. R13's
independent-shippability constraint is therefore substrate-protected
and the design honors it by routing each decision to its native
substrate.

The chain-handoff asymmetry decision (#159) carries the meta-irony
that this `/design` invocation itself was driven by `/scope` against
the same Phase 0 gate the bug names. The handoff worked here only
because `/scope` Phase 2 pre-transitioned the PRD to Accepted before
dispatching `/design` — exactly the operator-side workaround the bug
calls out. The fix needs to make that pre-transition the skill's
contract, not the operator's.

## Decision Drivers

PRD-derived:

- **R12 minimal blast radius.** No fix may silently change behavior
  in surfaces outside the three named bugs. Cited shared infrastructure
  is `transition-status.sh` for `/prd`, but the fix MAY touch shared
  substrate if every touch is documented and called out at review.
- **R13 independent shippability.** Each bug's fix is a separately
  reviewable, separately revertable unit. The design SHOULD NOT
  introduce cross-bug shared code that creates a hard dependency
  ordering.
- **R6 direct-invocation preservation.** The Phase 0 / Phase 1
  hard-stop must remain reachable when no parent-orchestration
  sentinel is present. The fix is parent-chain-shape-only.
- **R7 symmetry direction left open.** The PRD allows alignment in
  either direction (change `/prd` to match `/design`+`/plan`, change
  `/design`+`/plan` to match `/prd`, or introduce a shared helper).
  The design must pick one and justify it.

Implementation-specific:

- **Substrate fidelity.** Each fix lives in its native substrate
  (shell regex, phase-prose markdown, koto gate definition). Cross-
  substrate refactors are rejected unless they pay back beyond the
  sweep's frame.
- **Sentinel-availability assumption.** Bug #159's Option (c) names
  the `parent_orchestration:` sentinel from
  `tsukumogami/shirabe#151` (the child-dispatch-contract work). That
  contract is shipped; sentinel detection is an available primitive.
  Options that depend on it are not speculative.
- **Read-time discoverability.** Future operators inspecting any of
  the three fixed surfaces should see a single clearly-named branch
  that handles the previously-silent case, not a buried conditional.
- **Test-fixture verifiability.** The PRD's ACs are largely grep-
  checkable or executable. The design SHOULD choose fix shapes whose
  presence and behavior the named ACs can verify without DESIGN
  inventing new verification machinery.

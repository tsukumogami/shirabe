---
schema: brief/v1
status: Done
problem: |
  Lifecycle enforcement today has two distribution paths, both with gaps.
  The reusable CI workflow at `.github/workflows/lifecycle.yml` only
  protects repos that explicitly adopt it. The work-on skill prose at
  `skills/work-on/SKILL.md` tells the agent to run `shirabe validate
  --lifecycle . --strict` as a pre-cascade probe and post-cascade
  verification, but that instruction is prose — an agent that skips,
  misreads, or short-circuits the step silently loses the discipline. A
  repo that uses the shirabe plugin's `/work-on` skill without adopting
  the reusable CI workflow has no lifecycle enforcement on its single-pr
  PRs at ready-for-review time.
outcome: |
  A contributor running `/work-on` against any plugin-installed repo gets
  the chain-aware lifecycle check baked into the cascade script
  deterministically — the script invokes the check before and after the
  atomic finalization commit, parses results without agent interpretation,
  and fails fast on unexpected outcomes. The reusable CI workflow stays
  unchanged as the cross-chain whole-tree backstop. Net effect: the
  DRAFT-vs-READY discipline ships with the shirabe plugin, not just with
  the reusable CI workflow.
upstream: docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md
---

# BRIEF: skill-cascade-lifecycle-check

## Status

Done

The framing closes the script-side gap left after the DRAFT-vs-READY
discipline landed. The downstream PRD operationalizes the requirements
for the chain-targeted CLI mode, the script-driven invocation contract,
and the prose alignment in the work-on and plan skill references.

## Problem Statement

The work-on cascade today drives the chain to its strict-mode passing
state by invoking `shirabe validate --lifecycle . --strict` from agent-
directed prose in `skills/work-on/SKILL.md`. The prose tells the agent to
run the check before the cascade (expecting a specific failure naming the
present PLAN) and after the cascade (expecting a clean pass), but the
agent is the load-bearing element — a misreading, a short-circuit, or a
silent skip all break the discipline.

A separate gap: the prose-directed invocation uses whole-tree mode
(`--lifecycle .`), which scans every chain in the repo on every cascade
run. That works in repos with one or two chains but produces noisy
output as the corpus grows; unrelated chains that drift surface their
errors on every work-on cascade, drowning the signal the cascade
actually cares about (its own chain's passing state).

## User Outcome

The cascade script invokes a chain-targeted lifecycle check
deterministically — no agent interpretation, no prose-directed
invocation, no whole-tree scan. The check runs at the natural points:
a pre-cascade probe (expecting strict-mode failure naming the present
PLAN and non-terminal BRIEF/PRD upstream) and a post-cascade
verification (expecting clean pass). Results are parsed by exit code;
the script fails fast on unexpected outcomes.

The reusable CI workflow stays as the cross-chain whole-tree backstop
for repos that adopt it. The new chain-targeted mode is additive — the
whole-tree `--lifecycle <ROOT>` contract is unchanged.

## User Journeys

**CUJ-1: Cascade pre-probe.** The cascade script invokes
`shirabe validate --lifecycle-chain <plan-doc> --strict` immediately
before performing the atomic finalization commit. The check fails with
a specific error naming the present PLAN and the BRIEF/PRD at non-
terminal status. The script reads the exit code, confirms the expected
failure shape, and proceeds.

**CUJ-2: Cascade post-verification.** After the atomic finalization
commit (PLAN deleted, BRIEF/PRD transitioned to Done, DESIGN promoted
to Current), the script re-invokes the same chain-targeted check. The
check passes cleanly. The script reads the exit code, confirms the
expected pass, and exits successfully.

**CUJ-3: Local chain audit.** A chain author working on a single
PLAN runs `shirabe validate --lifecycle-chain docs/plans/PLAN-foo.md`
locally to verify their chain is healthy without scanning the whole
tree. The check walks only that chain and surfaces only that chain's
errors.

**CUJ-4: CI workflow contract.** The reusable CI workflow at
`.github/workflows/lifecycle.yml` continues to invoke `shirabe
validate --lifecycle . --strict` for whole-tree validation. The
contract is unchanged; the new chain-targeted mode is purely
additive.

## Scope Boundary

In scope:
- New `--lifecycle-chain <DOC-PATH>` CLI flag on `shirabe validate`.
- Chain discovery from any doc-in-a-chain (PLAN, DESIGN, PRD, BRIEF).
- Reuse of the existing chain-walker and posture inference.
- Cascade script invocation at pre-cascade probe and post-cascade
  verification.
- Prose updates in `skills/work-on/SKILL.md` and `skills/plan/SKILL.md`
  to describe the script-driven enforcement model.

Out of scope:
- Changes to whole-tree `--lifecycle <ROOT>` semantics.
- Changes to the reusable CI workflow.
- New lifecycle rules or chain-walker logic.
- JSON output format (exit code plus stderr is sufficient).

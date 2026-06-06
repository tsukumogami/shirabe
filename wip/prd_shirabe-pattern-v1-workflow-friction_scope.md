# /prd Scope: shirabe-pattern-v1-workflow-friction

## Problem Statement

Three shirabe pattern-v1 workflow primitives fail catastrophically and silently on
routine chain runs: the single-pr `plan-to-tasks.sh` parser drops every dependency
edge when the colon is inside the bold markers (#156), `/design` and `/plan`
refuse to auto-transition their upstream artifact the way `/prd` does (#159), and
`/work-on` doesn't notice an upstream main change that has invalidated the PLAN's
foundation mid-chain (#162). Each fires on a routinely-taken path, each fails
without a signal the operator could act on, and each costs hours of manual recovery
when discovered downstream.

## Initial Scope

### In Scope

- Requirements + ACs for fixing the contract surfaces of #156, #159, #162.
- For each bug, requirements MUST bind (a) the broken contract surface, (b) the
  silent-by-default failure shape, and (c) the verification surface a reviewer can
  use to confirm the fix shipped.
- Coordinated framing as a three-bug sweep against a shared failure shape, not
  three independent feature requests scheduled together.

### Out of Scope

- The implementation mechanism per bug. The issues enumerate 2-4 fix candidates
  each; DESIGN picks one per bug. PRD specifies the contract, not the approach.
- Other open shirabe issues from the same dogfooding window: #155, #157, #158,
  #160, #161, #163, #164. Each stays open as its own work stream.
- Broader pattern-v1 ergonomics work (SE12 roadmap territory).
- Refactoring of `plan-to-tasks.sh`, the status-gate framework, or `/work-on`'s
  orchestrator beyond what each individual fix needs to clear its contract.

## Research Leads

1. **#156 contract surface and failure shape boundary** -- the regex at
   `skills/plan/scripts/plan-to-tasks.sh:288` is the broken contract. Determine
   what the requirement must say about both colon placements and about the
   silent-empty-deps-with-multiple-issues failure mode so the requirement is
   mechanism-neutral but failure-shape-precise.
2. **#159 chain-handoff symmetry contract** -- `/prd` auto-transitions upstream
   BRIEF Draft -> Accepted; `/design` and `/plan` hard-stop on a missing
   transition. The requirement must bind "symmetric handoff" without prescribing
   auto-transition vs documented-contract vs sentinel-gated mechanisms, since
   each is a valid downstream choice.
3. **#162 dual-surface failure** -- the bug has two surfaces (no upstream check
   in `/work-on` between commits AND `ci_monitor` treating DIRTY-suppressed
   check-runs as pending). Determine whether requirements bind both surfaces
   together or separately, and what the verification surface looks like for each.
4. **Validator + verification primitives available in v0.9.1-dev** -- confirm
   which ACs can be grep-checkable (parser regex coverage, status-gate sentinels,
   worktree-fetch invocation) versus which must be marked as
   judgment/integration-tested (multi-skill handoff symmetry, mid-chain
   escalation surface).

## Coverage Notes

- Who is affected: shirabe maintainers (and other operators) running standard
  pattern-v1 chain workflows. Covered by BRIEF + dogfooding context.
- Current situation: BRIEF documents the three bugs and their failure shapes
  with full citations to dogfooding incidents (PR-141, PR-151, SE11).
- What's missing/broken: explicitly enumerated per bug in the BRIEF and issue
  bodies.
- Why now: cumulative recovery tax across three discrete failure modes that all
  fire on routinely-taken paths; the v0.7.0 -> v0.9.0 cutover (Go -> Rust
  validator, dispatch contract) did not address any of these three.
- Scope boundaries: BRIEF's "Out of Scope" enumerates seven other open issues
  excluded from this sweep plus the broader ergonomics roadmap (SE12).
- Success criteria: per-bug ACs that a reviewer can verify; sweep-level
  acceptance that the silent-by-default failure shape is no longer reachable
  through routine authoring on any of the three surfaces.

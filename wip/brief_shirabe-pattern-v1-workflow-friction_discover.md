# /brief Discovery: shirabe-pattern-v1-workflow-friction

## Problem Candidate

Three workflow-level bugs in shirabe pattern v1 fire on routine chain runs and the failure modes are silent enough that an operator can't tell something went wrong until the downstream cost has already accumulated. They surfaced during the same recent dogfooding window (PR-141 for `/comp`, PR-151 for the dispatch contract), each one large enough that the operator had to stop the chain, diagnose, and recover by hand. The common shape across all three is "catastrophic-by-default on a common path with no signal that recovery is needed."

## Outcome Candidate

An operator running the standard chain workflows (`/scope <topic>` for chain handoffs, `/work-on <plan>` for single-pr PLANs, `/work-on` against a long-running PR) sees the chain reach its terminal artifact without manual recovery steps. The three specific failure modes are no longer reachable through normal use: a single-pr PLAN with a sequential dependency chain spawns children sequentially rather than in parallel; chain handoffs through `/brief -> /prd -> /design -> /plan` complete without manual `transition-status.sh` runs; an upstream change to main that invalidates a PLAN's architectural assumptions is detected mid-chain rather than at PR finalization.

## Grounding Anchor

conversation only (parent /scope dispatch + issues tsukumogami/shirabe#156, #159, #162)

## Journey Sketch

- Operator runs `/scope <topic>`; the chain handoff completes through `/brief -> /prd -> /design -> /plan` without manual transition-status.sh runs (#159).
- Operator runs `/work-on` against a single-pr PLAN with a linear dependency chain; the orchestrator spawns children sequentially, not in parallel (#156).
- Operator runs `/work-on` driving a long-running PR; an upstream change to main is detected mid-chain rather than at finalization (#162).

## Open Questions for Drafting

- The three bugs share a "silent-by-default" failure shape but otherwise touch different surfaces (`plan-to-tasks.sh` parser, status-gate logic across three skills, worktree-discipline in `/work-on`). The Problem Statement must frame the brief as "three discrete bugs sharing a common failure shape" rather than imply a single root cause.
- Scope boundary needs to be explicit about issues that are NOT in scope (#155, #157, #158, #160, #161, #163, #164) and about broader pattern-v1 ergonomics work (SE12 territory).
- No solution shape in the brief — issue bodies enumerate candidates per bug, but the DESIGN owns picking one per bug.

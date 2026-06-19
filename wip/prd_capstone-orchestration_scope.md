# /prd Scope: capstone-orchestration

## Upstream
docs/briefs/BRIEF-capstone-orchestration.md (Accepted)

## Problem (from brief)
`/scope` and `/work-on` operate one repository at a time. For an effort spanning
repositories, the author hand-supplies the cross-repo coordination contract every
session and tracks merge state manually — unpersisted, unenforced, error-prone.

## Goal (from brief)
Make `/scope` and `/work-on` capstone-aware so they carry multi-repo coordination:
one coordinating record up front holding the plan + upstream artifacts, coarsest-legal
per-repo PR grouping, derived/tracked merge order, record merges last as the done-signal,
intent expressed once.

## Research posture
Discovery is carried from the prior exploration on this branch — re-running it would
duplicate work. Grounding artifacts:
- wip/explore_capstone-orchestration_findings.md (7 leads: current workflow mechanics,
  single-pr PLAN lifecycle, niwa primitives, interface-model trade-offs, capstone state
  + merge order, prior art, example PRs)
- wip/explore_capstone-orchestration_decisions.md (interface-model split; granularity rule
  sub-exploration; integration-shape design lead)
- wip/research/capstone-orchestration_granularity_lead-*.md (decomposition rule)
- wip/research/capstone-orchestration_example-pr-511.md (real fresh-capstone structure)

## Requirements themes to capture
1. Capstone intent expression (per-invocation + workspace default) and the
   preference-vs-smart-default split.
2. Coordinating-record (capstone) lifecycle: created up front, holds plan + artifacts,
   stays current, merges last, consume-before-merge cascade generalized cross-repo.
3. Decomposition: coarsest legal grouping; merge order as a gate-aware, always-acyclic
   ordering.
4. Cross-repo correctness + visibility; atomicity detection/refusal.
5. Consistency: single canonical capstone contract shared by /scope, /work-on, CLI.
6. Non-functional: announce+override, no new coordination substrate, manual fallback.

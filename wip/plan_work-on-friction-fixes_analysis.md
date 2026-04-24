# Plan Analysis: work-on-friction-fixes

## Source Document

Path: `wip/explore_work-on-friction-triage_findings.md`
Status: n/a (topic input)
Input Type: topic

## Scope Summary

Fourteen confirmed, triaged improvement opportunities in the `/shirabe:work-on`
skill, surfaced by a 5-issue PR run against an external repo. Each item has a
verified root cause and a clear category (implement directly vs. needs-design).

## Components Identified

- **Context extraction**: A1 (remote-branch/cross-repo DESIGN lookup), A2
  (missing `check-staleness.sh`), A12 (per-branch findings cache)
- **Setup / baseline**: A3 (pre-existing baseline failures), A14 (monorepo
  baseline scoping)
- **Analysis phase**: A4 (optional subagent for simplified plans)
- **Implementation phase**: A10 (scope_expanded_retry), A11 (mid-implementation
  AC re-read)
- **Finalization**: A5 (`validation:simple` in skip list)
- **PR creation**: A6 (pre-push confirmation)
- **Skill hygiene (cross-cutting)**: A7 (multi-issue bundling), A8 (per-session
  tmp paths), A9 (env-var standardization), A13 (AC-script advisory note)

## Implementation Phases

Two waves:

1. **Trivial/clear-scope implementations** (7 items, A4/A5/A8/A9/A10/A11/A13)
   ship as individual PRs; each is atomic and low-risk.
2. **Needs-design implementations** (7 items, A1/A2/A3/A6/A7/A12/A14) each
   become a planning issue with `needs-design` — the design doc and
   implementation plan are written separately per item.

A9 (env-var standardization) should land first because the A2 fix may touch
the same directives (`${CLAUDE_PLUGIN_ROOT}` vs `${CLAUDE_SKILL_DIR}` paths).

## Success Metrics

- All 14 items closed (or explicitly deferred with rationale recorded as a
  decision).
- `/shirabe:work-on` can run end-to-end on a public-only shirabe install
  (resolves A2 blocker).
- A follow-up friction-log run on a similar 5-issue PR shows fewer manual
  workarounds.

## External Dependencies

- **koto 0.8.2 template-compile regression** (B1 in the findings doc): the
  skill is unreachable on modern koto. Needs to be filed upstream and fixed
  before any of these A-items can be validated via actual workflow runs. Not
  part of this plan but a blocker for verifying the fixes.
- **No public nodejs/monorepo language skill**: A14 depends on either
  extending work-on itself or having a language skill to own detection logic.
  Design for A14 must pick one.

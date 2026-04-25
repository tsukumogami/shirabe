---
complexity: simple
complexity_rationale: Planning issue that produces a DESIGN doc; no code changes; simple per the planning-issue convention.
---

## Goal

Produce a DESIGN doc deciding how `/work-on` handles the "bundle
another issue onto an existing branch and PR" flow as a first-class
operation rather than as a manual override pattern.

## Context

The friction-log run bundled five issues onto one branch and one PR
(`Fixes: #N` per issue, one shared summary). Today this requires the
agent to reach around the skill at every step:

- `setup_issue_backed` runs `on_feature_branch` and `baseline_exists`
  checks that expect a fresh branch; the workaround is `status: override`
- `/tmp/plan.md` collides between sibling issues on the same branch (now
  partially addressed by the `/tmp/koto-<WF>/` per-session-paths fix)
- The PR body has to be manually rewritten with each new issue
- No "append to existing workflow" entry point — `/work-on` always
  initializes a fresh per-issue koto workflow

This was the highest-impact single item in the source triage. Multiple
viable designs exist, all with non-trivial trade-offs.

Options to evaluate:
- New invocation: `/work-on --bundle #N` (or `/work-on #N --on-branch
  <name>`) that explicitly attaches to an existing branch+PR
- A dedicated `bundle_setup` state in `work-on.md` reachable when an
  open PR exists for the current branch
- A helper script (`bundle-issue.sh`) that does the koto-context-state
  copy and PR-body update outside the state machine
- A PR-body template + convention with no skill changes

The DESIGN must cover: invocation, branch reuse, PR-body convention,
summary artifact semantics, and koto state-machine implications
(particularly: what does `setup_issue_backed` do in a bundle? does the
new koto workflow share context with the prior workflows?).

## Acceptance Criteria

- [ ] `docs/designs/DESIGN-multi-issue-bundling.md` exists at status
  `Accepted` with all required sections, including an `Alternatives`
  section
- [ ] Design covers: invocation, branch reuse, PR-body convention,
  summary artifact semantics, koto state-machine implications
- [ ] Decision is concrete enough that `/plan` can decompose it into
  implementation issues
- [ ] Tests pass (run project's test command)
- [ ] CI green

## Dependencies

None

## Downstream Dependencies

None — but priority signal: this is the highest-impact item in the
plan. Starting it first keeps its downstream implementation plan
unblocked the earliest.

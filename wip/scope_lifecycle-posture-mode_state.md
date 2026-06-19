```yaml
topic: lifecycle-posture-mode
chain_started: 2026-06-19T16:41:33Z
last_updated: 2026-06-19T16:41:33Z
phase_pointer: phase-2
exit: UNSET
exit_artifacts: []
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
visibility: Public
plan_execution_mode: single-pr
discovery: cold-start (no on-disk artifacts at canonical paths for this slug)
r6_predicates:
  p1_architectural_alternatives: fires (escalation-assertion site + advisory read-source are open architectural choices)
  p2_new_component: fires (new advisory/explanation module + per-code posture-classification table)
  p3_complex: fires (supersedes an Accepted decision; changes public CLI interface --strict->--mode; spans L02/L06/L07 + workflow)
worktree_rebases:
  - phase: brief
    upstream_commits: []
    impact: none
    rebased_at: 2026-06-19T16:41:33Z
    notes: branch created off origin/main this session; 0 behind
child_snapshots:
  brief:
    status: Draft
    content_hash: 82b6b47f5e4a291d55cc74a89143713843a44e4a
    captured_at: 2026-06-19T16:41:33Z
    jury: both-PASS (content-quality, structural-format)
```

## Upstream context (from /explore lifecycle-strict-discipline)

Solution shape decided during exploration (issue #197):
- Replace `--strict` flag with intent-named `--mode=draft|ready` (default `draft`).
- Posture is a total function: `draft` unless a positive `ready` signal is present.
  Local/no-PR and draft PRs are `draft`; only a ready-for-review PR is `ready`.
- The CI shell asserts `--mode=ready` only when `github.event.pull_request.draft == false`.
- Add a context-aware ADVISORY explanation layer: reads ambient PR state via
  `GITHUB_EVENT_PATH`/env (hermetic, never gates) to explain why a verdict holds and
  what posture change flips it. Verdict (exit code + JSON envelope) stays a pure
  function of `(docs, --mode)`.
- Per-code posture classification: `always-fail | draft-tolerable`. Draft-tolerable:
  L02, L06, L07. Always-fail (by design): L03, L04, L05. L01 already posture-sensitive.
- Supersedes DECISION-lifecycle-strict-mode-interface-2026-06-06.
- Blast radius self-contained (self-caller only); no release/tag bump required.

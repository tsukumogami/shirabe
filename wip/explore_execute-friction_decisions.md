# Exploration Decisions: execute-friction

## Round 1

- **Scope = clusters A+B+C+D; F2 routed out**: cover F1/F5/F6 (`/execute`
  finalize-correctly seam), F3 (review-gate pause), F4 (`/plan` docs-coverage),
  and F7 (friction-log convention). F2 (version skew) is an install/marketplace +
  plugin-cache concern owned by niwa / Claude Code, benign here (0.12.1-dev is a
  forward-compatible superset of 0.11.0) — not shirabe code work.
- **Ready to crystallize after one discovery round**: coverage is complete; the
  remaining unknowns are design decisions to settle inside the next artifact, not
  missing research, so no further explore round is warranted.
- **F5 splits a→F1, b→validate**: F5a (cascade auto-runs) collapses into the F1
  fix; F5b (manual-path "finalization not done" guard) is a separate new
  `shirabe validate` mode (manual + CI), since R9 can't fire when koto is bypassed.
- **F4 owned by `/plan`, not `/execute`**: only `/plan` reads the DESIGN body
  where the user-visible-surface signal lives; a content check in `/execute`
  would violate its metadata-only R14/R15 contract.
- **F3 reframed**: `/execute` already stops at `gh pr ready` and never
  auto-merges; the real change is a pause before the `plan_completion` cascade,
  not a "don't merge" mode.
- **F7 reframed as convention, not bug**: the cascade has no wip/ scrub; squash-
  merge removes wip/ as designed. Fix is a convention carve-out + durable home
  (GitHub issue), with an automated `/execute` run-report emit as a design-gated
  follow-on (it would widen the closed write-target set).

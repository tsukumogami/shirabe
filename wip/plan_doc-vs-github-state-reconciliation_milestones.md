---
milestone_name: doc-vs-github-state-reconciliation
milestone_description: |
  FC09 -- third reconciliation axis in shirabe-validate. Reconciles
  the plan/roadmap doc's claims about issue state against GitHub's
  actual issue state plus the current PR's `Closes #N` body lines.
  Ships notice-level via the existing `is_notice` membership; the
  promotion seam is the one-line removal of the FC09 arm.
  Design: `docs/designs/current/DESIGN-doc-vs-github-state-reconciliation.md`.
execution_mode: single-pr
github_milestone_created: false
---

# Plan Milestone: doc-vs-github-state-reconciliation

In single-pr mode the `milestone` frontmatter field is present (it
names the logical work unit) but no GitHub milestone is created.
The whole feature lands in one PR; the parent
`PLAN-roadmap-plan-standardization.md`'s `roadmap-plan-standardization`
milestone (GH milestone #6) is the upstream tracking surface --
the FC09 PR closes its issue (#153) which is already on that
milestone. This single-pr PLAN's own milestone field carries the
logical name and the source-doc citation only.

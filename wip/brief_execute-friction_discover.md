# /brief Discovery: execute-friction

## Problem Candidate

When an author takes a feature through the shirabe chain in one sitting
(`/explore → /scope → /execute`), they expect `/execute` to drive the plan to a
finished, reviewable pull request. The first real end-to-end use exposed that it
can't do this cleanly: it can't land into the branch/PR the author already opened
during scoping — it always creates a new `impl/<slug>` branch and a new draft PR —
so the author is forced into a manual fallback that bypasses `/execute`'s own
finalization, leaving the lifecycle cascade and the PR-template step undone. Even
on a clean run the assembled PR isn't template-conformant, there is no way to
pause for human review before the finalization cascade irreversibly mutates the
chain, nothing guarantees user-facing documentation was updated when the feature
added user-visible surface, and the friction notes the author kept are deleted by
the workflow's own cleanup. The author ends up hand-finishing the very steps the
skill was meant to automate, and finds the gaps only by noticing them.

## Outcome Candidate

An author can run `/execute` against a plan they scoped on an existing branch and
watch it land into that same PR — no divergent branch, no second PR. They can
choose to pause at a reviewable draft before the finalization cascade mutates the
chain, review, and then resume to finish. When the plan adds user-visible surface,
the workflow ensures the documentation is covered rather than letting it slip. The
PR `/execute` produces is already template-conformant (conventional title,
two-part body) without a manual fix-up pass. And the notes the author captures
along the way survive to a durable home instead of being erased by cleanup. The
author trusts `/execute` to finish what it starts, and sees clearly when something
genuinely needs their hand.

## Grounding Anchor

conversation only — grounded in the committed exploration
(`wip/explore_execute-friction_findings.md`, `_crystallize.md`) and the source
friction log (durable copy at
`/home/dgazineu/dev/niwaw/tsuku/tsuku/friction_execute_niwa-default-worktree.md`).

## Journey Sketch

- An author who scoped + planned a feature on an existing `docs/<topic>` branch
  with an open PR runs `/execute` and lands the implementation into THAT PR.
- An author runs `/execute` but wants to review the assembled change before the
  chain is finalized — pauses at a reviewable draft, reviews, resumes to finish.
- A plan that adds user-visible CLI/behavior surface flows through to merge with
  its user-facing docs updated, not silently skipped.
- An author finishes a run and finds the PR already template-conformant, and any
  friction notes they captured preserved in a durable location.

## Open Questions for Drafting

- Throughline confirmed by author: ONE feature — "trustworthy `/execute`
  finalization" — with F4 (docs-coverage, lives in `/plan`) and F7 (friction-log
  durability convention) included as part of the same complete-landing promise.
  The Scope Boundary will note F4 touches `/plan` and F7 is a convention.
- F2 (version skew) is OUT of scope — install/marketplace + plugin-cache concern
  owned by niwa / Claude Code; benign.
- The "how" (branch-targeting surface, pause-state shape, docs detection contract,
  validate-guard home) is deliberately deferred to the PRD/DESIGN, not the BRIEF.

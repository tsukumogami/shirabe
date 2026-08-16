---
topic: release-same-day-merges
last_updated: 2026-08-16T21:35:00Z
phase_pointer: spawn_and_await
review_corrections_applied: 595418e
exit: UNSET
exit_artifacts: []
home_pr: 322
settled_branch: fix/release-same-day-merges
execution_mode: single-pr
autonomy: auto
child_snapshots:
  o-fix-release-derive-the-release-pr-set-from-the-commit-range:
    status: done
    content_hash: 65c486c
    captured_at: 2026-08-16T21:05:00Z
  o-test-release-cover-same-day-merges-at-both-call-sites:
    status: implementation
    content_hash: ""
    captured_at: 2026-08-16T21:05:00Z
---

# /execute state: release-same-day-merges

Projection over the durable home PR (#322). The PR is the source of truth; this
file is scratch and is removed before the pull request can merge.

## Phase 0

Slug re-validated against `^[a-z0-9-]+$`. The PLAN's `execution_mode`
re-validated against `{single-pr, multi-pr, coordinated}` and resolved to
`single-pr`, so the coordinated mode-scoped preflight does not apply. The
cross-skill child-template assertion
(`skills/execute/scripts/assert-child-template.sh`) exited 0. No stale
`parent_orchestration:` sentinel existed.

The home-PR resume lookup found the open draft PR #322 on the current branch.
That PR is **adopted** as the home PR per the override path: no second branch
and no second PR were created, and the settled branch
`fix/release-same-day-merges` is recorded in koto context.

## Phase 1

Worktree-discipline check: `git fetch origin` brought nothing new
(`git rev-list --count HEAD..origin/main` is 0), so impact is `none` and the run
proceeded without escalation.

`plan-to-tasks.sh` produced two children from the PLAN's outlines, with
`SHARED_BRANCH=fix/release-same-day-merges` injected into each. Child 2 waits on
child 1.

## Review round 1

Five reviewer agents (two on the BRIEF, three on the DESIGN) returned after the
children had started. Three returned FAIL and their findings were real, so the
corrections landed in `595418e` before finalization rather than being deferred:

- The derived set was held in shell variables. Each phase block runs as its own
  shell invocation, so Phase 2 would have read an unset value, found no
  security-labeled pull request, and passed. Now carried in three `wip/` files.
- The DESIGN claimed `"..HEAD"` is a range git rejects. It accepts it and
  returns zero commits, which is why the first-release guard matters.
- The label loop had no branch for a `(#N)` that names an issue or a foreign
  pull request; `gh pr view` exits non-zero and the number was skipped silently.
- R4 requires the unattributed report before the notes are drafted; it was
  printed after. Phase 1 now prints it.
- Eval scenario 7's first assertion described the removed `merged:>` search.
- The BRIEF's outcome and fourth journey committed to one of the two candidate
  resolutions its own Scope Boundary says is open.

The decision researcher's report confirmed both design decisions independently
and supplied the unbounded-above measurement (18 pull requests against the
range's 13) now recorded in Decision 1.

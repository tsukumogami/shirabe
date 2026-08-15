```yaml
topic: skill-adherence-enforcement
last_updated: 2026-08-15T21:55:00Z
phase_pointer: spawn_and_await
exit: UNSET
exit_artifacts: []
execution_mode: single-pr
autonomy: auto
koto_session: execute-skill-adherence-enforcement
settled_branch: impl/skill-adherence-enforcement
home_pr: 310
child_snapshots:
  i1-declaration:
    status: dispatched
    dispatched_at: 2026-08-15T21:54:00Z
  i2-hook:
    status: dispatched
    dispatched_at: 2026-08-15T21:54:00Z
  i8-conflict:
    status: dispatched
    dispatched_at: 2026-08-15T21:54:00Z
  i9-description:
    status: dispatched
    dispatched_at: 2026-08-15T21:54:00Z
```

## Run Notes

**Projection, not source of truth.** The durable state is home PR #310 on
`impl/skill-adherence-enforcement`, which carries the committed chain and the koto
context. This file is reconstructable from it.

**Phase 0.** Slug `skill-adherence-enforcement` validated against `^[a-z0-9-]+$`.
`execution_mode: single-pr` re-validated against the enum before it selected a path.
Preflight passed: the cross-skill `work-on.md` child template resolves. No
`parent_orchestration:` sentinel existed at session start, so the self-heal was a
no-op. Home-PR resume lookup returned nothing, so this is a fresh run rather than a
resume.

**orchestrator_setup.** No open PR existed to adopt, so the create path ran.
`impl/skill-adherence-enforcement` was branched from the scope chain's HEAD so the
PR carries the chain artifacts and the implementation together, which is what
single-pr means. Draft PR #310 opened. The first `gh pr create` was refused by the
shipped `shirabe pr-body-hook` gate on two findings (non-conventional title, missing
`---` separator); both were corrected and the second attempt succeeded. Worth
recording because it is the same deny-with-actionable-reason mechanism this plan
generalizes.

Settled branch recorded via `koto context add` and verified by read-back. This step
had been failing silently on every run until a fix landed on main earlier today: the
template called `koto context set`, a subcommand koto does not have, and koto's
stderr flood hid the error. The rebase at the start of the scope chain picked up the
fix.

**worktree_discipline_check.** `git rev-list --count HEAD..origin/main` returned 0,
so no upstream commits to classify. Impact recorded as `none` in
`wip/work-on_skill-adherence-enforcement_impact.json`.

**spawn_and_await.** Task payload built from the PLAN, shared branch injected, and
**submitted** to the session. koto materialized 9 children and released 4 as
unblocked. `scheduler_ran` records `spawned_count: 4`, and four child session
directories exist under the parent's name. The remaining 5 are gated on dependencies.

The four released children are the four zero-dependency issues (1, 2, 8, 9), each
dispatched as a `/work-on` run against the shared branch with a disjoint file set so
they can run in parallel without racing. Children were instructed not to run git
write commands; the orchestrator commits.

**Precedence note.** The session carries an instruction not to call the Agent tool
unless the user requested it, and `spawn_and_await` materializes one `/work-on`
child per issue. The author invoked `/execute` on this PLAN, and under the ordering
this chain's own DESIGN settled on, requesting the workflow requests the children it
is defined in terms of. Proceeding on that reading, recorded here rather than
resolved silently.

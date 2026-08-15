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

**Baseline measurement result, and why it belongs in the PR body.** Issue 9's
child measured the current `execute` description against a 20-query set, 5 runs
per query, before rewriting anything. Result: 8 of 20 queries pass. The split is
the informative part. All 8 negatives pass, meaning the description never fires
on work that belongs to the single-issue workflow. All 12 positives fail, at
**zero triggers across all 60 positive runs**.

So the description does not undertrigger. It does not fire at all on its own
canonical invocation, including the literal phrasings from both field incidents
("Execute the plan at docs/plans/PLAN-...", "Drive every issue in this PLAN to a
merged pull request"). It also never names resumption, which the skill genuinely
owns, and "Resume the plan run I started yesterday" scored 0/5.

This sharpens the exploration's finding rather than contradicting it. The
research established a ceiling on description quality, correctly, on the evidence
that `work-on`'s near-ideal description also failed to fire. Nobody had measured
`execute` itself, so the contribution of a defective description was assumed
small and was never bounded. It is not small. The enforcement work remains
justified on the second incident, where the skill did fire and the loop was
skipped anyway, but the first incident now has a measured proximate cause.

Carry this into the PR body at `pr_finalization`: it is the strongest single
piece of evidence produced across the whole chain, and `wip/` does not survive
the cascade.

**The determination was run against this very execute run, and got it right.**
Carry this into the PR body; it is the strongest validation the change has.

```
shirabe adherence-check \
  --plan docs/plans/PLAN-skill-adherence-enforcement.md \
  --session 4d06ff3a-5dfa-44de-b130-442e620bbff1 \
  --parent execute-skill-adherence-enforcement
```

Result: `outcome: indeterminate`, with the reason "no liveness witness for this
session: nothing was watching, which is not evidence of a departure."

That is the correct answer and it is the subtle one. The hook that writes the
witness ships in this PR but is not installed in this workspace, so nothing
observed the run. A checker built the obvious way would have read the absent
record as non-registration and reported a real, correctly-delegated run as
`non-conforming`. This one declines to, which is exactly the distinction
cross-validation turned into an interface requirement after finding a completed
eight-child run on this machine with no workflow record at all.

Everything else it read was accurate against live state: registration resolved
under the worktree-encoded project directory, workflow identified as
`execute-skill-adherence-enforcement`, six delegated children counted against
the PLAN's declared nine, and the conflict store queried for the orchestrator
plus all six children under their own session identities. That last part is the
child-walking join from interface 2, working against real data rather than a
fixture.

It also reports registration status `blocked`, which is honest: the parent is
still at `spawn_and_await` with three issues outstanding.

**Precedence note.** The session carries an instruction not to call the Agent tool
unless the user requested it, and `spawn_and_await` materializes one `/work-on`
child per issue. The author invoked `/execute` on this PLAN, and under the ordering
this chain's own DESIGN settled on, requesting the workflow requests the children it
is defined in terms of. Proceeding on that reading, recorded here rather than
resolved silently.

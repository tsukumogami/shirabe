# Lead: When a combined "scope then execute" run lands a `multi-pr` PLAN, what should the session do?

## Findings

### 1. How `/work-on` runs a multi-pr PLAN today

`skills/work-on/SKILL.md:121-141` makes `/work-on <PLAN path>` a thin dispatcher on
`execution_mode`. `single-pr` and `coordinated` get redirected to `/execute`; `multi-pr`
"runs in place, one issue at a time": pick the next unblocked issue from the PLAN
(blocked = its Dependencies reference open issues), run it as an ordinary issue-backed
unit against the repo-persisted PLAN, each landing its own PR, "no shared branch and no
cross-issue carry-forward". `skills/execute/SKILL.md:40-49` confirms the mirror image:
`/execute` refuses multi-pr and points back at `/work-on`. The PRD behind that split
(`docs/prds/PRD-execute-skill.md:128-133`, D5 at `:307-312`) says explicitly that whether
`/work-on` offers "a thin sequential convenience loop ... or the author dispatches them
one at a time, is a downstream design detail".

The dispatcher is prose only. There is no koto state for "next issue"; each issue is a
separate koto workflow (`issue_<N>`), and `SKILL.md:277-278` says to resolve `ROLE`
again per session in multi-pr dispatcher mode, so every issue run is a **root** run.

Input accepted (`SKILL.md:15`, `:32-34`, `:145-150`): a PLAN path, an issue number/URL,
or a milestone (`M<N>` / name), which picks the lowest-numbered unblocked open issue.

### 2. Are issues filed for multi-pr?

Depends on tracking level, not mode. `skills/plan/references/phases/phase-7-creation.md:68-115`
resolves `## Tracking Level: none|issues|issues-and-milestone` (flag > CLAUDE.md > default);
the default for multi-pr is `issues-and-milestone`, so by default `/plan` files one issue
per work item under a milestone. Under `none`, no issues are filed and work items get
`plan_item` / `m-<slug>` keys (`docs/designs/current/DESIGN-multi-pr-plan-decoupling.md:218-237`).
That design states plainly that **no entry point can drive an issueless multi-pr plan**
(`:275-281`, `:652-664`): `/work-on M<N>` has no milestone and `/execute` declines multi-pr.

An issue-creating activation is gated on human approval (`phase-7-creation.md:314-319`;
`DECISION-multi-pr-posture-detection-2026-06-06.md`, Amendment 2026-08-15). So under
default tracking a multi-pr `/scope` run needs a human to approve filing before the PLAN
reaches `Active` (under `--auto`, presumably the decision protocol; not verified here).

### 3. What blocks between PRs

Blocking is dependency-driven, not merge-of-predecessor by default. An issue is blocked
while any issue in its Dependencies is open (`SKILL.md:34`, `:137-138`), and an issue
closes when its PR merges via the closing keyword that `pr_creation` enforces
(`skills/work-on/koto-templates/work-on.md:919-953`). So a dependent issue waits on its
predecessor's **merge**; an issue with no open dependencies does not wait on anything.

### 4. Could independent multi-pr issues run in parallel?

Nothing in the design forbids it and several things favor it: no shared branch, no
cross-issue state, each issue its own branch and PR (`SKILL.md:139-141`,
PRD-execute-skill D5). Per-issue PRs don't edit the PLAN table (grep of
`skills/work-on` finds no strikethrough/table update), so parallel PRs shouldn't collide
on the PLAN file. The in-session dispatcher itself is sequential ("one issue at a time"),
so parallelism would have to come from separate sessions.

### 5. `/work-on` never merges, and never reaches "merged"

`SKILL.md:336` says the output is "A merged PR with passing CI", but the template's
`done` state reads "The PR has been created and CI is passing" (`work-on.md` `## done`),
and `ci_monitor` routes to `done`/`cascade_entry` on green CI plus a non-DIRTY merge
state (`work-on.md:966-1054`). No skill in the repo calls `gh pr merge`. `/execute`'s
single-pr path also ends at `gh pr ready` (`skills/execute/SKILL.md:121-148`). A
"done when merged" goal is therefore not something any shirabe skill can satisfy by
itself in any mode; merge is a human (or merge-rights) action outside the workflow.

### 6. Surprise: a root multi-pr issue run appears to end at `done_blocked`

The finishing-obligations work (#378) added `cascade_entry`/`cascade_run` to every root
run (`work-on.md:1013-1023`, `:1056-1125`). For an issue-tracked multi-pr PLAN:

- `find-anchor-plan.sh` greps `docs/plans/*.md` for `| [#N:` and finds the PLAN
  (`skills/work-on/scripts/find-anchor-plan.sh:68-81`), so the run enters `cascade_run`.
- `run-cascade.sh`'s pre-probe runs the lifecycle check in `--mode=ready`
  (`run-cascade.sh:369-402`). Ready mode only re-targets `SinglePrMidPR`
  (`crates/shirabe-validate/src/lifecycle.rs:925-931`); a multi-pr PLAN at `Active` is
  `MultiPrInFlight`, which passes (`lifecycle.rs:795-803`, `:839-844`). So the cascade
  reports `skipped` (`run-cascade.sh:824-829`).
- `verify-cascade-commit.sh` then exits 2 because the PLAN is still on disk, and
  `cascade_status: skipped` + `post_state: plan_present` routes to `done_blocked`
  ("the PLAN is still on disk") (`work-on.md` cascade_run transitions).

There is no intermediate-vs-work-completing branch anywhere in the cascade, although
`DECISION-cascade-trigger-mechanism-2026-06-06.md` specified "multi-pr intermediate PR:
no-op" and posture detection by open-issue count. No test in `skills/work-on/scripts/`
covers multi-pr. `DESIGN-work-on-standalone-completeness.md` Decision 5 (`:407-427`)
plans to move multi-pr into `/execute` with a new end-of-run cascade and a refusal in
`/work-on`; that second PR hasn't landed (SKILL.md still dispatches multi-pr). This is
inferred from reading, not executed; it should be confirmed by a run, but if right, a
per-issue multi-pr session today would open a green PR and then report blocked.

Related: if the PLAN is not on the branch the issue run cuts from (scoping PR unmerged),
the finder exits 1 and the run ends silently at `done` — the cascade question disappears,
but so does any link to the chain.

### 7. Multi-pr completion needs its own final PR

Per `DECISION-multi-pr-posture-detection-2026-06-06.md`, a multi-pr chain finishes with
a separate "work-completing" PR: flip PLAN Active→Done, `git rm` it, BRIEF/PRD→Done,
after all issue PRs merged. Nothing in `/work-on` today produces that PR for multi-pr
(see 6). So even a fan-out of per-PR sessions leaves one more unit of work: the
verify-then-delete PR, which can only run after every issue has merged.

### 8. What a clean stop after scoping looks like

`/scope` commits per hop but "Nothing pushes" and opens no PR outside coordinated mode
(`skills/scope/SKILL.md:497-507`). Its full-run exit records the PLAN (`Active` for
multi-pr, with milestone/issues from `/plan`) and prints
`/scope finished: exit=full-run; artifact=docs/plans/PLAN-<topic>.md`
(`skills/scope/references/phases/phase-3-exit-finalization.md:43-56`,
`phase-4-cleanup.md:140-157`). Note that phase-3 still says single-pr PLANs are `Draft`,
contradicting the unified lifecycle (single-pr auto-Active); stale text, not central.

For multi-pr, then, the clean stop is: chain docs committed with the PLAN at `Active`
and `lifecycle --mode=draft` passing, `wip/` cleaned, a docs-only PR pushed and opened
(the session has to do this itself; `/scope` doesn't), issues filed per tracking level,
and the session reports the PR plus the issue list. The per-issue work should not start
until that docs PR is merged, because per-issue branches cut from the default branch
need the PLAN/DESIGN there (for context extraction and the anchor finder) and a
dispatched worker clones from the remote.

### 9. Is `niwa dispatch` a reasonable fan-out target?

Mostly yes. `niwa dispatch "<prompt>" --name <slug> --detach` provisions a fresh
ephemeral instance, launches a background worker rooted in it, captures the session id,
and maps the instance for reaping when the session is deleted
(`public/niwa/internal/cli/dispatch.go:204-264`). Relevant properties:

- Callable from inside an agent session: cwd inside an instance or worktree resolves to
  the shared workspace root, so "a self-dispatching worker creates a sibling, never a
  nested instance" (`dispatch.go:290-294`).
- Needs a positional prompt when there's no TTY; with no prompt and no terminal it fails
  fast (`dispatch.go:222-230`). Fine for an agent.
- `--detach` is the fan-out/scripting mode: returns after printing hints
  (`dispatch.go:235-247`); the workspace `/dispatch` skill insists on it
  (`/Users/danielgazineu/dev/niwaw/tsuku/.claude/skills/dispatch/SKILL.md:90-93`).
- The worker starts blind and clones **pushed remote state** (`dispatch/SKILL.md:16-36`,
  `:116-118`), so the scoping docs must be pushed, and in practice merged, before
  per-issue workers are useful. One brief per worker (`:121-122`); each worker must end
  with the `=== WORK IN FLIGHT ===` block (`:44-66`).
- Permission mode is derived from workspace declarations (`dispatch.feature` S1-S9); the
  worker's merge rights are whatever the host's `gh` credentials allow.

The mismatch: dispatch is fire-and-forget. Nothing notifies the dispatcher when a PR
merges, so the dependency-gated issues can't be auto-dispatched from the scoping
session unless it stays alive polling. Dispatch fits "fan out every currently unblocked
issue now" well; later waves need a human or a later session.

## Implications

- For multi-pr, the combined session's goal should be "scoping docs PR open (ideally
  merged) and the first wave of independent issues handed off", not "merged". "Done when
  merged" is unsatisfiable for multi-pr in one session, and strictly also for single-pr
  and coordinated, because no skill merges; the goal wording for all modes should be
  "PR ready with green CI" unless the session has merge rights and a human-free merge
  policy.
- The session should stop after scoping with a report naming: the PLAN path, the docs PR
  URL, the filed issues with their dependency edges, which issues are unblocked now, and
  the command to start each (`/work-on #N`), plus the reminder that a final
  verify-then-delete PR is owed after the last merge.
- If it fans out, the right unit is one `niwa dispatch --detach` per currently unblocked
  issue, gated on the scoping PR being merged, each brief saying "run `/work-on #N`".
- Before recommending fan-out, the `cascade_run` behavior in finding 6 needs a real run
  to confirm; if it holds, every per-issue worker will report `done_blocked` on a green
  PR, which a dispatcher would misread as failure.
- An issueless (`Tracking Level: none`) multi-pr PLAN has no driver at all; the combined
  flow should either force issue tracking for multi-pr or stop with that gap stated.

## Surprises

- `/work-on`'s Output section promises a merged PR; its `done` state means "PR created,
  CI passing". Nothing merges.
- Root multi-pr issue runs appear to route to `done_blocked` via the new cascade
  (finding 6), contradicting the cascade-trigger decision's "intermediate multi-pr PR:
  no-op". No multi-pr test covers it.
- The multi-pr migration into `/execute` is designed (Current DESIGN) but not landed, so
  routing docs and the design disagree about who owns multi-pr.
- `/scope` doesn't push or open a PR in single-repo mode, so "scoping docs PR merged" is
  work the combined session has to do itself.
- `/scope` phase-3 says single-pr PLANs exit at `Draft`, which contradicts the unified
  lifecycle that auto-activates them.

## Open Questions

- Does a live `/work-on #N` run on an issue-tracked multi-pr PLAN actually end at
  `done_blocked`? (Needs an execution, not just a reading.)
- Under `--auto`, does `/plan`'s human approval gate for issue filing block, or does the
  decision protocol auto-approve? That decides whether an unattended combined session can
  even reach an Active multi-pr PLAN.
- Who owns the final verify-then-delete PR for multi-pr, today and after the `/execute`
  migration?
- Should the combined session wait for the scoping PR to merge (needs merge rights or a
  human) before dispatching, or dispatch workers that start from the scoping branch?
- Is there any channel for a dispatched worker to report back (beyond its final message)
  so a coordinator could dispatch the next dependency wave?

## Summary

`/work-on` runs a multi-pr PLAN as independent per-issue root runs where each issue is gated on its dependencies' PRs merging, and nothing forbids independent issues running in parallel sessions. But no shirabe skill ever merges (`/work-on` stops at "PR open, CI green"), so "done when merged" can't be satisfied for multi-pr, or strictly for any mode, and a multi-pr chain also owes a final verify-then-delete PR after the last merge. The combined session should stop after scoping with a pushed docs PR, the PLAN at Active with its issues filed, and a report of which issues are unblocked. Fan-out through `niwa dispatch --detach` (one worker per unblocked issue) is workable once the docs are merged, with one caveat: reading the template, the new cascade seems to send every root multi-pr issue run to `done_blocked` because the PLAN is still on disk, and that needs confirming with a real run first.

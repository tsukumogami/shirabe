# Lead: What does `/execute` need to take a single-pr or coordinated PLAN to merged code, and who merges?

All paths are relative to the shirabe repo root (worktree `explore-scope-then-execute`).

## Findings

### 1. Preconditions

**PLAN status (Draft vs Active).** `/execute` never checks PLAN status. Input handling
reads only `execution_mode` and re-validates it against `{single-pr, coordinated,
multi-pr}` (`skills/execute/SKILL.md:44-56`). `plan-to-tasks.sh` checks `schema:
plan/v1` and `execution_mode`, and optionally `tracking_level`. It never reads
`status` (`skills/plan/scripts/plan-to-tasks.sh:1213-1262`). `/scope` leaves a single-pr
PLAN at **Draft** and a multi-pr or coordinated PLAN at **Active**, the latter with a
milestone (`skills/scope/references/phases/phase-3-exit-finalization.md:44-57`). The
cascade assumes Active, since its comments describe the chain as "single-pr-Active
mid-PR". It tolerates Draft, though. The PLAN to Done flip fails with a warning and the
cascade proceeds to `git rm` anyway: "a PLAN at Draft (auto-transition didn't fire)"
(`skills/work-on/scripts/run-cascade.sh:859-876`). So a Draft single-pr PLAN straight out
of `/scope` is accepted.

**Issues filed?** Single-pr doesn't need GitHub issues. `process_single_pr` reads
`## Issue Outlines` and emits children with `ISSUE_SOURCE=plan_outline`
(`plan-to-tasks.sh:421-449, 554`). Coordinated does need them. `process_coordinated`
parses the `## Implementation Issues` table for `#N` references plus `_Repo: | Group:_`
annotations and `_Gate:_` rows (`plan-to-tasks.sh:785-830`). Those issues come from
`/plan`'s milestone and issue creation, which is why the coordinated PLAN is Active.

**Coordinated also needs** the coordination PR to already exist. `/execute` "runs against
an existing coordination PR (creating the coordination home up front stays `/scope`'s
responsibility; `/execute` consumes it)" (`SKILL.md:359-361`, `SKILL.md:379-381`). It
also needs the `mode:coordinated` tool prerequisites, `shirabe validate
--coordination-body` and `--merge-gate`, checked by a mid-run preflight
(`SKILL.md:58-78`).

**Branch.** The single-pr orchestrator refuses to record the default branch as the
settled branch. `record-settled-branch.sh` exits 66 on it, and the gate has no override
(`skills/execute/koto-templates/execute.md:91-188, 553-557`). The orchestrator also
fetches and rebases onto `origin/main` before spawning children (`worktree_sync`,
`execute.md:190-251`). It then requires a per-run impact classification file,
`wip/work-on_<slug>_impact.json` (`execute.md:253-297, 581-591`).

### 2. Does single-pr build on /scope's branch and PR? Do PLAN and code ship in one PR?

Yes, by design, but only if a PR already exists on that branch. `orchestrator_setup`
checks the current branch and runs `gh pr list --head <branch>`. If the branch is
non-main **and has an open PR**, it submits `override` and adopts that branch and PR as
the home PR, "including a `docs/<topic>` scoping PR" (`execute.md:514-518`;
`SKILL.md:270-275`; `docs/guides/execute-friction.md:17-32`: "One branch, one PR, code and
scoping docs together").

The catch is that `/scope` never pushes and never opens a PR. Its per-hop commit is
local-only ("Nothing pushes", `skills/scope/SKILL.md:505-508`;
`phase-3-exit-finalization.md:405-411`). It also refuses to commit on the default branch,
so the author has to be on a feature branch first (`phase-2-chain-orchestration.md:511-547`).
In the single-repo case, then, `/scope` leaves a local, unpushed branch with no PR, and
the adopt predicate is false. `orchestrator_setup` falls through to its creation script:
`git checkout impl/<slug> || git checkout -b impl/<slug>`, push, `gh pr create --draft`
(`execute.md:520-527`). Because `checkout -b` branches from the current HEAD (the scope
branch), the scope commits still ride along. The PLAN and code still ship in one PR, just
on `impl/<slug>` instead of the scope branch. The guide's instruction ("if you ran
`/scope` and are sitting on its branch, just run `/execute` from there... Your
implementation lands on the scoping PR you already have") assumes a PR that `/scope`
itself doesn't create.

The cascade then deletes the PLAN and transitions BRIEF/PRD/DESIGN in the same PR
(`execute.md:730-787`). The single PR therefore carries the docs, the code, and the
finalization.

### 3. Does /execute merge, or stop at green CI?

**Neither `/execute` nor `/work-on` merges anything.** No `gh pr merge` call appears
anywhere in `skills/` or `references/`. The single-pr koto template ends like this:
`plan_completion` runs the cascade and `gh pr ready`, `ci_monitor` waits for green CI
plus a non-DIRTY merge state, and then comes `done`, described as "All per-issue children
succeeded, the PR description has been updated, and CI is green"
(`execute.md:389-436, 812-814`). The template description agrees: "...marks it ready,
and monitors CI to green" (`execute.md:24-27`). `/work-on`'s `done` is the same: "The PR
has been created and CI is passing" (`skills/work-on/koto-templates/work-on.md:1755-1757`).

The closed write-target set lists `gh pr edit`, `gh pr ready`, and `gh pr close`. It
doesn't include `gh pr merge` (`SKILL.md:811-817`), so a merge would sit outside the
declared set that the R9 check polices.

The policy is explicit in `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md:52-61`:
"Marking ready is the agent's signal... **Merging is the human's action**, taken after
review. The agent marks ready; the human merges."

This contradicts the Exit Paths prose. There, `full-run` is "the plan is driven to its
**merged-PR done-signal**. For single-pr the single PR merges" (`SKILL.md:613-618`), and
the skill description promises "all the way to merged code" (`SKILL.md:4`). The template
reaches `done` at green CI, which is before the state `full-run` claims. `--auto`
promises "a ready-to-merge, green PR" (`SKILL.md:319-322`), not a merged one.

### 4. Coordinated merge order across repos, and merge rights

The coordinated path is a plain loop the skill drives, not a koto session
(`SKILL.md:343-418`). Each pass refreshes live `gh` status, re-authors and validates the
coordination body, walks the merge-order DAG, and re-gates with `shirabe validate
--merge-gate`. A PR node is unblocked "when every predecessor is satisfied (a PR node
when its PR has merged...)" (`SKILL.md:404-410`). `/execute` dispatches `/work-on` per
repo for each unblocked node, and each of those runs ends at green CI (see above).
**Nothing in the loop merges the per-repo PRs.** So the DAG only advances past its first
layer when someone outside the loop merges. With a human merger, the loop mostly waits:
it re-polls live state, and it has no explicit wait or poll-interval instruction.

The done-signal is "the coordination PR merging last", gated on `--merge-gate
--mode=ready` (`SKILL.md:420-430`). The contract says the skill "consumes its own PLAN,
and merges" (`references/coordination-strategy.md:68-73`). `SKILL.md:147-148` says
"merge the coordination PR last". But no mechanism is specified, and `gh pr merge` is
outside the closed write set. The coordination PR "stays draft until it merges last"
(`DESIGN-lifecycle-draft-ready-discipline.md:63-72`). A non-bypassable CI check keeps it
unmerged while any indexed PR is open (`coordination-strategy.md:70-73`).

Merge rights: the loop reads on "the operator's own `gh` credentials"
(`SKILL.md:390-393`). Realistically, merging the per-repo PRs, and the coordination PR if
the skill does it, needs write and merge permission on every repo in the effort. That
includes passing each repo's branch protection and required reviews, which an agent can't
satisfy for itself.

### 5. What "done" means for a session without merge rights

As the skills are written, the terminal states give the answer:

- **single-pr**: koto `done` means the PR is ready (not draft), the chain is finalized
  (PLAN deleted, BRIEF/PRD at Done, DESIGN at Current), CI is green, and the merge state
  is clean. That's the furthest the skill goes, and it needs no merge rights. The
  `exit: full-run` label, though, is defined as "PR merged", so a run that ends there has
  no correct exit value. It isn't `paused_for_review`, and it isn't one of the three
  exits as written.
- **coordinated**: without merge rights, the loop can dispatch only the root layer of the
  DAG. Each of those PRs ends at green and ready, then everything blocks, because
  downstream nodes wait for merges. The coordination PR can't reach its done-signal. No
  exit path is defined for "waiting on human merges". `abandonment-forced` closes the
  coordination PR unmerged (R20, `SKILL.md:432-440`), which is the wrong outcome for
  "healthy, waiting on a human".

A realistic "done" for a session without merge rights is "every PR the session can
produce is ready and green, and the remaining merge order is handed to a human." The
skill doesn't name that state.

### 6. Running /execute in the same session right after /scope

**No state collision.** `/scope` uses koto session `scope-<topic>`
(`skills/scope/references/phases/phase-0-setup.md:327`) and `wip/scope_<topic>_*`. `/execute`
uses koto session `execute-<plan-slug>` and `wip/execute_<topic>_state.md`
(`SKILL.md:103-111, 444-450`). Children are separate koto children. `/scope`'s Phase 4
sweeps all of `wip/scope_<topic>_*` and the child prefixes on `full-run` before `/execute`
starts (`phase-4-cleanup.md:58-110`), and it leaves "no remaining state on disk"
(`phase-4-cleanup.md:152-158`). So the wip/ cleanup order works out: scope's wip is gone
before execute begins.

**Branch expectations line up**, with the adopt/no-PR caveat from section 2: `/scope`
already requires a non-default branch, and `/execute` requires the same. The stale
`parent_orchestration:` self-heal at `/execute` Phase 0 (`SKILL.md:825-830`) only clears
`/execute`'s own state file, so it doesn't interfere.

**Autonomy / pause.** In the default interactive mode, single-pr `/execute` stops at
`paused_for_review` (a DRAFT PR with the chain intact) and requires re-invocation to
finalize (`SKILL.md:310-341`). A one-session goal needs `--auto`, a CLAUDE.md
`## Execution Mode:` header, or a clear "don't stop" instruction (`SKILL.md:88-101,
742-775`). Note that `--auto` doesn't carry over from `/scope` to `/execute`
automatically. Each skill resolves its own mode.

**Retained koto session on re-run.** If a previous `/execute` on the same slug ended at
`done_blocked` or `paused_for_review`, the session is retained, and `koto init` refuses
the name until you read it and then run `koto session cleanup` (`SKILL.md:521-562`). This
isn't an issue for a fresh chain.

**Handoff.** `/scope`'s success summary is just `/scope finished: exit=full-run;
artifact=docs/plans/PLAN-<topic>.md` (`phase-4-cleanup.md:139-151`). It doesn't route to
`/execute` or branch on `plan_execution_mode`, so the session's own goal has to supply
the next step.

**Execute's own wip.** `/execute` writes `wip/execute_<topic>_state.md` and the gate file
`wip/work-on_<slug>_impact.json`. The cascade (`run-cascade.sh`) and the `/execute`
template contain no step that removes them. If they get committed on the shared branch,
the wip-hygiene rule and CI will block the merge. Whether they're ever committed wasn't
verified.

## Implications

- For single-pr, one session can run `/scope`, then `/execute --auto`, and reach a
  ready, green, finalized PR carrying the docs and code together, with no merge rights
  needed. The last step, merging, is by policy a human's. "Done only when merged" can't
  be met by the skill as designed. The honest session goal is "ready + green +
  finalized; human merges."
- For coordinated, the skill structurally depends on merges happening between loop
  passes. A session without merge rights stalls after the first DAG layer. Even with
  rights, the skill has no specified merge step, and `gh pr merge` isn't in its write
  set. A one-session scope-to-merged run for coordinated isn't supported today without
  either (a) a human merging while the session waits and polls, or (b) adding an
  explicit, permission-gated merge step.
- The Exit Paths section (`full-run` = merged) disagrees with the template (`done` =
  green CI). The "ready and green, awaiting human merge" outcome needs a named terminal
  or exit, analogous to `paused_for_review`, so a session can finish cleanly. The same
  gap applies to a multi-pr PLAN routed to `/work-on`, whose per-issue `done` is also
  green CI, not merged.
- The adopt-scoping-PR path only fires if something opens a PR after `/scope`. In a
  chained session, either the session pushes and opens the docs PR before `/execute`, or
  it accepts the `impl/<slug>` PR that inherits the scope commits. Both give one PR.

## Surprises

- No skill ever calls `gh pr merge`, yet the `/execute` description and `full-run` exit
  both promise merged code. The design doc explicitly says "the agent marks ready; the
  human merges."
- `/scope` never pushes and never opens a PR in single-repo mode, even though
  `/execute`'s adopt path and guide are written around "the scoping PR `/scope` left you
  on".
- `/execute` accepts a Draft single-pr PLAN only because the cascade swallows the failed
  PLAN to Done transition as a warning. Nothing moves the PLAN Draft to Active.
- The coordinated loop has no wait or poll cadence for "PR node blocked on an unmerged
  predecessor". It implicitly assumes merges happen between passes.

## Open Questions

- Should `/execute` gain an explicit "handed off for merge" terminal or exit (ready +
  green, not merged) and stop claiming `full-run` = merged? Or should it gain an opt-in,
  permission-checked `gh pr merge` step, which would mean amending the closed write-target
  set?
- In coordinated mode without merge rights, what should the session do after dispatching
  the first layer: exit with a named "awaiting merges" state and a resumable coordination
  PR, or poll? `/execute`'s home-PR resume (`SKILL.md:575-596`) suggests a later
  re-invocation can pick up from the coordination PR, but that isn't stated as a pattern.
- Should the chained flow push and open the scoping PR at `/scope`'s end (so adopt fires),
  or is the `impl/<slug>` PR inheriting the scope commits the intended shape?
- Are `wip/execute_*` and `wip/work-on_*_impact.json` ever committed on the shared branch?
  If so, what removes them before merge?
- Does `/execute --auto` need to be passed explicitly after `/scope`, or can an author
  instruction at session start ("run to completion") count for both skills?

## Summary

`/execute` can take a single-pr PLAN from `/scope` in the same session with no state
collision and no issues filed. That includes a Draft PLAN, and it can run on the scope
branch or an `impl/<slug>` branch that inherits the scope commits, so the docs and code
ship in one PR. But its terminal is a ready, finalized, green PR. No skill calls
`gh pr merge`, the write-target set excludes it, and the design doc states "the agent
marks ready; the human merges". That contradicts the `full-run` = "merged" wording.
Coordinated mode is worse for a session without merge rights: its DAG loop advances only
when predecessor PRs merge, so it stalls after the first layer. The coordination PR's
"merge last" step also has no specified mechanism, which means a scope-to-merged
single-session goal needs either a new "ready and handed off for merge" terminal or an
explicit permission-gated merge step.

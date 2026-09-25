# Running /execute and /deliver: branches, pauses, merging, and resume

A developer-facing guide to what `/execute` and `/deliver` do that you can see:
where code lands, when a run stops for you, when it merges, how to pick a run
up again, and how to check whether a finished run is really finished.

If you're running `/execute docs/plans/PLAN-<topic>.md` or `/deliver <topic>`
and want to know where your code will land, when the run will stop, or what
its last line means, this is the guide.

## From /scope to /execute: who opens the PR

Whether a PR exists when `/execute` starts depends on how you ran `/scope`.

**Without `--intent`, `/scope` pushes nothing.** It commits its documents on
the branch you ran it on (it refuses `main` and `master`) and stops. No push,
no PR, no `gh` call. When you then run `/execute` from that branch, there's no
PR to adopt, so `/execute` opens one.

**With `--intent=continue` or `--intent=stop`, `/scope` publishes.** At exit,
once the PLAN's mode is known, it pushes its branch and opens exactly one PR:
a draft for a `single-pr` or `coordinated` PLAN (and for a re-evaluation or
abandonment exit), a ready PR for a `multi-pr` PLAN. The PR body records
`intent=<value>`. A re-run reuses the PR it already owns rather than opening a
second one.

`/execute` then **adopts** that PR by its head branch. It looks PRs up only
through its ownership filter, which keeps a PR only when its head is in the
same repository (not a fork), its author is the authenticated user, and its
base and head are the expected branches. A same-named PR from a fork or
another author is never adopted, and when more than one PR survives the
filter, `/execute` stops with `step=execute:pr-adopt` rather than picking one.

## Mode-aware branch and PR targeting

Where `/execute` puts code depends on the PLAN's `execution_mode`.

### Single-pr: adopt the scoping branch and PR

A single-pr PLAN lands as one PR. When you run `/execute` on a non-default
branch where you own an open PR (the branch a `/scope --intent` run
published, or any scoping branch you opened a PR for yourself), `/execute`
adopts it as the home PR. It doesn't open a second PR or cut a new branch. The
code from every per-issue child commits to that branch, alongside the scoping
documents already there.

With no owned PR on the current branch, `/execute` creates `impl/<slug>`,
opens a draft PR, and routes the children there.

### Coordinated: one branch per PR node

A coordinated PLAN lands as several PRs, in one repository or across several.
The **coordination branch and PR carry the planning documents only**; code
never lands there. `/execute` cuts one branch per PR node, named
`impl/<slug>-<node-id>`, from the default branch in its own worktree, and
lands each node as its own PR. The node PRs merge in the PLAN's merge order,
and the coordination PR merges last.

The coordination PR stays draft until every node PR has merged; that's its
correct resting state throughout review. Each node PR goes ready once its
checks pass. The full walkthrough is in
[Running a Coordinated Effort](coordinated-multi-repo.md).

## Interactive pause versus `--auto`

`/execute` resolves an execution mode (interactive by default, or `--auto`) on
`flag > ## Execution Mode: header in CLAUDE.md > interactive`, and that mode
decides whether a single-pr run stops for your review before it finalizes.
There's no separate `--pause-for-review` flag.

### Interactive (default): stop at a reviewable draft

In interactive mode the run drives through implementation and assembles the
PR, then **stops at a reviewable draft before finalizing**. It ends
`outcome=paused-for-review`, a suspension rather than a failure. At the pause:

- the PR is assembled (conventional title, two-part body) but still **draft**;
- the chain is **intact**: the PLAN is still on disk, and BRIEF/PRD/DESIGN are
  un-transitioned;
- the finalization cascade has **not** run.

When you're satisfied, re-invoke `/execute` on the same PLAN. The new run
finds the open draft PR, runs the cascade, marks the PR ready, and waits for
CI.

### `--auto`: no pause

Under `--auto` the run doesn't pause. It drives through finalization: the
cascade deletes the PLAN and transitions BRIEF/PRD/DESIGN/ROADMAP, the PR is
marked ready, and CI runs on the finalized chain. Whether it then merges is a
separate question, answered by `--merge`.

## Merging with `--merge`

`/execute` never merges unless you ask. Without `--merge`, a run that finishes
ends `outcome=ready-awaiting-merge`: the PR is ready, and a human merges it.

With `--merge`, `/execute` merges only when a fresh read of the PR says it may.
It waits for checks to finish (up to 30 minutes per head commit), then merges
only if all of these hold:

- the PR is ready for review and GitHub reports its merge state as clean;
- every check on the head commit passed, and at least one check ran;
- the base branch is protected: its rules require status checks or an
  approving review;
- any review those rules require has approved the PR, and a PR touching
  `.github/workflows/`, `.github/actions/`, or a `CODEOWNERS` file is approved;
- the PR's head is the commit this run pushed.

It makes one `gh pr merge` call, pinned to that head commit with
`--match-head-commit`, and never passes an admin or bypass option. When any
condition fails, the run doesn't merge and ends
`outcome=ready-awaiting-merge` with a `reason=` naming what it's waiting on:
`merge-not-requested`, `review`, `base-unprotected`, `head-moved`,
`no-checks`, `workflow-change`, or a GitHub merge state such as
`merge-state:BLOCKED`. A failed check or a closed PR is an error instead
(`step=execute:ci`, `step=execute:pr-closed`), and checks still running past
the deadline end `step=execute:ci-timeout`.

`outcome=merged` is reported only after GitHub confirms it: a separate read
after the merge call has to see the PR as `MERGED`. A merge call that GitHub
accepted but that a re-read doesn't yet show merged (a merge queue, for
example) ends `ready-awaiting-merge` with `reason=merge-not-observed` and a
note that the PR may still merge later.

On a coordinated PLAN, `--merge` applies to each node PR in merge order and
then to the coordination PR, last. A node that can't start until a
predecessor merges ends the run `outcome=paused-awaiting-merges`, with a
`resume=` line to run once the predecessor is in.

`--merge` belongs to one invocation. It isn't remembered: a run resumed
without it doesn't merge, whatever an earlier run asked.

## /deliver: scope and execute in one session

`/deliver <topic>` takes a feature from scoping to its PRs without you
re-invoking anything between the two:

```
/deliver <topic> [--auto|--interactive] [--no-merge] [--upstream <path>] [--max-rounds=N] [--coordinated|--no-coordinated]
```

It runs `/scope <topic> --intent=continue` and then
`/execute docs/plans/PLAN-<topic>.md`, passing `--merge` to `/execute` unless
you gave `--no-merge`. The execution mode is resolved once and passed to both.
`--upstream`, `--max-rounds`, and the coordination flags go to `/scope`
unchanged. An interactive run asks one question of its own before `/execute`
starts, naming the PLAN's mode; declining ends the run `scoped` with
`next=/deliver <topic>`.

Because `/scope` runs with `--intent=continue`, a PLAN whose work splits
resolves to `coordinated` unless you pass `--no-coordinated`. A `multi-pr`
PLAN is never handed to `/execute`: the run ends `handed-off-multi-pr` and
lists the items you can start with `/work-on`.

`/deliver` writes nothing to your repository itself. `/scope` and `/execute`
do every commit, push, PR, and merge, as the same sessions you'd get running
them directly. `/deliver` is a koto workflow: each run opens a koto request
with one leg per child, each child reports its terminal result to its leg, and
`/deliver` reads those results through its template's gates, never from what a
child printed. Before it moves on, it re-checks durable state itself: the
PLAN and the scoping PR after `/scope`, and GitHub before it reports `merged`.
It runs only in repositories whose `CLAUDE.md` declares
`## Repo Visibility: Public`.

### Resuming a /deliver run

`/deliver` keeps no resume state of its own. Re-run the same command:

- Every invocation opens a fresh `deliver-<topic>` session and a fresh koto
  request. Before creating it, `/deliver` abandons any request an earlier run
  left open for the topic, so a late result from that run can't be read as
  this one's.
- Every invocation enters through `/scope`, which knows where the topic
  stopped. An unfinished `/scope` run resumes at the hop it stopped. A topic
  whose PLAN exists isn't re-scoped: `/scope` re-publishes (opening the PR if
  none is open) and `/execute` adopts it. A topic whose PLAN was already
  executed and removed skips `/execute`; `/deliver` re-reads the owned PR and
  ends `merged` or `ready-awaiting-merge`.
- Progress is re-derived from the PLAN and the owned PR, not remembered.
- `--merge` and the execution mode come from this invocation only. Re-running
  without `--no-merge` merges, and with it doesn't, whatever the earlier run
  did.

An unfinished `/scope` run started with a different intent isn't converted:
the run ends `outcome=error` with `step=deliver:intent-mismatch`.

### What /deliver prints

The report starts with `outcome=<token>`:

| Token | Meaning |
|-------|---------|
| `merged` | Every PR the PLAN needs reads `MERGED` on GitHub, coordination PR included, confirmed by `/deliver`'s own read. |
| `ready-awaiting-merge` | The PRs are open and ready, and at least one is unmerged; each is listed with `waiting=human` or `waiting=predecessor`. |
| `paused-awaiting-merges` | Coordinated only: some PR can't start until a predecessor merges. Each unmerged PR is listed, with the `resume=` command. |
| `paused-for-review` | Interactive only: `/execute`'s review pause, with the PR still draft. |
| `scoped` | You declined the confirmation; the report prints `next=/deliver <topic>`. |
| `handed-off-multi-pr` | The PLAN is `multi-pr`; `/execute` didn't run, and the startable items follow. |
| `scope-ended-early` | `/scope` ended at a re-evaluation, an abandonment, or a clean cancel; `reason=` names which. |
| `error` | A step failed; `step=` names it, for example `scope:push`, `execute:ci`, `deliver:intent-mismatch`, `deliver:child-absent`, or `deliver:refused`. |

Where the run produced them, the report also carries `repos=`, `pr=`,
`pr_state=`, and `wip_paths=` lines.

## `--koto-leg`: how a child reports to /deliver

`/scope` and `/execute` both accept `--koto-leg=<request-id>:<leg>`, where the
leg is `scope` or `execute` respectively. It attaches the run's koto session
to a leg of a koto request so the run's terminal result is recorded there. It
changes nothing else: the run, its prompts, and its printed lines are the same
as a direct run's.

The flag belongs to the child skills, and `/deliver` builds its value. A
person running `/scope` or `/execute` directly never needs it.

## koto version

`/scope`, `/execute`, and `/deliver` need koto v0.13.0 or later, the release
shirabe's CI is pinned to. Each skill's `requires.tsv` declares the koto
surface it calls, including the `koto init` entry flags (`--vars-file`,
`--attach-live`, `--replace-terminal`, `--koto-leg`) that first shipped in
v0.13.0; the declaration names flags rather than a version number. On an older
koto, the preflight that runs when the skill loads names the missing flags and
the command that installs a new enough koto, before the skill does any work.

Before you upgrade koto to v0.13.0, finish any `/scope` or `/execute` run
that's still in flight on the old koto, or remove its session with
`koto session cleanup scope-<topic>` or
`koto session cleanup execute-<plan-slug>`. v0.13.0 refuses to attach a
session an older koto created, so an in-flight run can't be resumed after the
upgrade, by a direct re-run or by `/deliver`. There's no automatic migration.

## The finalization-not-done guard

A run whose finalization didn't complete (a manual run that bypassed the
automated cascade, an `--auto` run that stopped short, or a paused interactive
run that was never resumed) is detectable mechanically. The guard is the
`shirabe validate --lifecycle-chain` mode under ready posture.

### Invocation

```bash
shirabe validate --lifecycle-chain <seed-doc> --mode=ready --format human
```

### Exit-code contract

| Exit | Meaning |
|------|---------|
| 0 | Finalization **complete**: the chain is at its terminal. PLAN deleted, BRIEF/PRD at Done, DESIGN at Current. |
| 2 | Finalization **not done**: a present PLAN or an un-transitioned upstream fails `L01` under ready posture. The guard fires. |
| 1 | Tool error: a bad invocation or unreadable input. **Inconclusive**, distinct from a violation. Never read it as a pass. |

The exit code alone is the pass/fail signal; the JSON or human output is for
diagnostics.

### The seed-doc rule

`--lifecycle-chain` seeds on a path that must exist. A missing seed returns
`L05` (exit 2), which looks like a real failure but isn't. Pick the seed by
what you're checking:

- **Suspected mid-run** ("did my manual finalization land?"). Finalization
  didn't complete, so the PLAN is still on disk. Seed on the PLAN:
  `docs/plans/PLAN-<slug>.md`. Ready posture fails `L01` and the guard fires
  with exit 2, which is exactly the case it's for.
- **A finalized chain** (CI, or confirming completion). The PLAN is gone, since
  the cascade deletes it, so seed on the **durable surviving anchor**: the
  DESIGN at `docs/designs/current/DESIGN-<slug>.md`, or the BRIEF/PRD at Done.
  **Never seed on the deleted PLAN path**, which returns `L05` (exit 2) and
  reads as a false failure. The same invocation returns exit 0 on a complete
  chain and exit 2 on an incomplete one.

The guard is meant to run at finalization time, not mid-effort. A chain that's
legitimately mid-flight has a present PLAN and reads "not done," which is
correct but noisy if you ask too early. CI gates the guard on a ready
(non-draft) PR for that reason: the reusable lifecycle workflow runs the
equivalent whole-tree ready check only when the PR is marked ready for review,
so a draft PR's mid-flight cascade doesn't false-fire.

---
schema: prd/v1
status: In Progress
problem: |
  An author can't hand one agent session a feature with the goal "scope it,
  then build it, done when merged": the execution mode that decides whether
  one session can finish is picked late, inside /scope's planning hop;
  /scope never opens the PR /execute expects to continue on; nothing in the
  chain merges; and the modes don't let the caller say whether anyone will
  stay to drive the work after the PLAN exists.
goals: |
  The caller states intent at launch (drive it to done, or stop at a PLAN) and
  every run under that intent ends in a named state the caller can act on:
  merged when the session may merge, ready and handed off when it can't, or a
  PLAN on a PR with its startable issues named. Plain /scope keeps working as
  it does.
absorbed:
  - docs/briefs/BRIEF-scope-then-execute.md
motivating_context: |
  Authors hand whole features to background sessions with a standing goal
  ("scope this, then build it, done when merged"). The goal is only
  satisfiable for some PLANs, and the author can't tell which kind they'll get
  until /scope has already run.
---

# PRD: scope-then-execute

## Status

In Progress

Absorbed [BRIEF-scope-then-execute](docs/briefs/BRIEF-scope-then-execute.md); carried in Absorbed Brief.

## Absorbed Brief

The feature frames one gap: an author who hands a whole feature to a session
with the goal "scope it, build it, done when merged" can't know at launch
whether that goal is reachable, because the execution mode is picked late and
the modes conflate how many PRs the work lands in with whether anyone stays to
drive it.

The problem it named is this document's Problem Statement. The outcome it asked
for is that an author states intent up front and every run under that intent
ends somewhere useful: merged when the session may merge, a ready PR handed off
when it can't, or a landed PLAN with issues ready for per-PR sessions, with no
change for anyone who doesn't opt in. Those are this document's Goals.

Four journeys grounded it and survive as User Stories 1 through 4: a
maintainer's background session driven to done; a contributor's driven run in a
repository where agents can't merge, which must neither stall silently nor
re-scope; a lead who scopes now and fans out to per-issue sessions later; and an
author who keeps using `/scope` as before. Its scope boundary is carried as the
Requirements and Out of Scope: intent declared at launch, splits resolved by
intent, coordinated allowed in one repository, a thin driver over a directly
callable `/scope`, merging only when permitted; and, excluded, automatic
fan-out, moving multi-pr into `/execute`, changing split reasons, merging by
default, and the strategic chain.

## Problem Statement

Authors increasingly hand a whole feature to a background session with one
standing goal: scope it, implement it, and don't stop until it's merged. Today
that goal can't be stated in a way the skills can honor, and whether it can
be met at all isn't known until `/scope` has finished.

`/scope` ends at a PLAN, and the PLAN's execution mode decides what happens
next. The mode is chosen late, at `/plan`'s decomposition step, from reasons
the caller doesn't control. A single-pr PLAN fits one session. A multi-pr PLAN
blocks on every PR merging before the next can start, and by design nobody
drives it: the PLAN lands on main and separate sessions pick up issues. A
coordinated PLAN has a driver, but it's currently reserved for multi-repo
work, and its loop also stalls whenever an earlier PR hasn't merged.

Even the single-pr case doesn't reach "merged". `/scope` commits locally and
never pushes or opens a PR, so `/execute` can't adopt the scoping branch the
way its guide describes and cuts a second branch instead. `/execute` and
`/work-on` stop at a ready PR with green CI; no skill merges, although both
describe their end state as merged. `/scope` ends with a bare
`exit=full-run` line and names no next step, and `/plan`'s closing advice and
`/scope`'s resume path still send single-pr PLANs to `/work-on` instead of
`/execute`.

The root issue is that the modes encode two things at once: how many PRs the
work lands in, and whether anyone stays to drive it. The second is really the
caller's intent, and the caller has no way to state it.

## Goals

- An author states, when starting, whether a run should drive the work to
  completion or stop once a PLAN exists, without having to predict how the
  work will split.
- A driven run ends merged when the session is able to merge, and otherwise
  ends with every PR it could produce ready and green, a plain account of what
  waits on a human, and a way to resume.
- A stop-at-PLAN run ends with the PLAN on a PR ready to merge, its issues
  filed, and the issues that can start once it merges named.
- Authors who use `/scope` today see no change unless they opt in, apart from
  a correct next step at the end of the run.

## User Stories

1. As a maintainer handing a feature to a background session, I want one
   command that scopes the feature and then drives it to merged code, so that
   I can step away and come back to finished work and the documents that
   explain it.
2. As a contributor in a repository where agent sessions can't merge, I want a
   driven run to finish cleanly with its PRs ready, tell me exactly which
   merges are waiting on me, and pick up where it stopped when I re-run it, so
   that the run neither stalls silently nor re-scopes.
3. As a lead planning parallel work, I want to scope a feature with the intent
   to stop at the PLAN and be told which issues can start once the PLAN lands,
   so that I can start one session per issue.
4. As an author who uses `/scope` as it is, I want no change in what it
   produces unless I ask for one, and a correct next step at the end, so that
   the new behavior costs me nothing.
5. As an author who wants to review the documents before any code is written,
   I want `/scope --intent=continue` alone to leave the work ready for
   `/execute`, so that I can read the PR and then start execution myself.
6. As a team that wants a human to press merge even when an agent could, I
   want to turn merging off for a driven run, so that driving the work doesn't
   mean giving up the review gate.

## Interfaces

Every new flag, its spelling, and its default. Anything not listed keeps its
current behavior.

| Skill | Flag | Values | Default | Notes |
|-------|------|--------|---------|-------|
| `/scope` | `--intent=<value>` | `continue`, `stop` | absent | Given at most once. Any other value, or a repeat, is rejected at Phase 0 before a state file or session exists. |
| `/plan` | `--intent=<value>` | `continue`, `stop` | absent | Same values and rejection rule as `/scope`'s; `/scope` forwards its own value to the `/plan` hop. Usable when `/plan` is invoked directly. |
| `/execute` | `--merge` | boolean | off | Asks `/execute` to merge the PRs it produces, within R19. |
| `/deliver` (the new driver) | positional topic slug | `^[a-z0-9][a-z0-9-]*$` | required | Same slug rule as `/scope`; no leading `-`. |
| `/deliver` | `--auto` / `--interactive` | boolean | `interactive` (or the CLAUDE.md `## Execution Mode:` header) | Resolved once and passed to both `/scope` and `/execute`. |
| `/deliver` | `--no-merge` | boolean | off (merging on) | Runs `/execute` without `--merge`. |
| `/deliver` | `--upstream`, `--max-rounds`, `--coordinated`, `--no-coordinated` | as in `/scope` | as in `/scope` | Forwarded to `/scope` unchanged. |
| `/scope`, `/execute` | `--koto-leg=<request>:<leg>` | a koto request leg | absent | Child-owned and documented for direct use. Attaches the run to a leg of a koto request, so the run's terminal result is recorded on that leg for whoever created the request. `/deliver` passes it; a person running either skill directly never needs to. |

**Precedence for the PLAN's mode when the work splits:** an explicit
`--coordinated` or `--no-coordinated` flag wins, then `--intent`, then the
CLAUDE.md `## PR Grouping Policy:` / `## Reviewability Ceiling:` headers, then
the default (`multi-pr`).

## Final States

Each run ends in exactly one of these, and its report prints the token
verbatim as `outcome=<token>`.

| Token | Emitted by | Meaning |
|-------|------------|---------|
| `merged` | `/execute`, `/deliver` | Every PR the PLAN needs has merged, including a coordination PR. |
| `ready-awaiting-merge` | `/execute`, `/deliver` | Every PR is open, ready for review, with every check on its head commit passed, and at least one is unmerged because merging was off or R19's merge-state condition or the merge call failed. For coordinated, this includes the case where only the coordination PR remains. |
| `paused-awaiting-merges` | `/execute`, `/deliver` | Coordinated only: every PR whose predecessors have merged is open, ready, and CI-green; some PR can't start until a predecessor merges. |
| `paused-for-review` | `/execute`, `/deliver` | Interactive only: `/execute`'s existing review pause with the home PR still draft. |
| `executed` | `/scope` | `--intent` given for a topic whose PLAN was already executed and removed; the report names the branch's PR and prints `pr_state=merged` or `pr_state=open`. `/deliver` relays it as `merged` or `ready-awaiting-merge`. |
| `scoped` | `/scope`, `/deliver` | `full-run` with a `single-pr` or `coordinated` PLAN. `/deliver` also ends here when the author declines its confirmation, printing `next=/deliver <topic>`. |
| `handed-off-multi-pr` | `/scope`, `/deliver` | `full-run` with a `multi-pr` PLAN; the startable issues are listed (and, with `--intent`, the scoping PR is open). |
| `scope-ended-early` | `/deliver` | `/scope` ended at `re-evaluation`, `abandonment-forced`, or a clean cancel; the report names which. |
| `error` | `/scope`, `/execute`, `/deliver` | A step failed; the report names the step: `scope:push`, `scope:pr-create`, `execute:ci` (a check on a PR's head commit failed, required or not), `execute:ci-timeout` (checks still running when the CI wait limit in R19 expires), `execute:ready` (an adopted draft PR couldn't be marked ready), `execute:pr-closed` (the PR was closed unmerged), `execute:pr-adopt` (no single owned PR matched a head-branch lookup), `execute:status-read` (GitHub couldn't be read), `execute:re-evaluation`, `execute:<state>` (any other existing `/execute` blocker, named by its state), `deliver:intent-mismatch`, `deliver:child-outcome` (a child ended with a record `/deliver` doesn't recognise), `deliver:child-absent` (a child returned without ever recording a result), `deliver:request-abandoned` (the run's own koto request was abandoned while a child was running), `scope:refused` / `execute:refused` (a child refused its arguments before any work started), `scope:intake` (a `/scope` intake check such as the upstream battery failed), or `scope:resume-probe` (`/scope` couldn't read the state its resume routing needs). The step is printed as `step=<step>`. A failed merge is not an error; it ends `ready-awaiting-merge` (R20). |

`/scope` ends a `re-evaluation` or `abandonment-forced` run with its existing
exit record and no `outcome=` token; `/deliver` maps those to
`scope-ended-early`.

## Requirements

### Declaring intent

- **R1.** `/scope` accepts `--intent=continue|stop` as specified in
  Interfaces, and rejects an invalid or repeated value at Phase 0 with an
  error naming the flag, before writing a state file or opening a session.
- **R2.** A `/scope` run with no `--intent` behaves as `/scope` does today:
  the same artifacts, the same execution-mode selection, and no push or PR.
  The only change is the exit summary in R10.
- **R3.** `/scope` records the resolved intent (`continue`, `stop`, or
  `none`) in its state file and prints it in its exit summary as
  `intent=<value>`.

### Resolving a split by intent

- **R4.** `/plan` keeps its current rules for whether the work splits into
  several PRs, and records the same split reason branch (the one `split_rationale`
  names) regardless of intent. Intent never forces or prevents a split.
- **R5.** `/scope` passes its intent to its `/plan` hop as `/plan`'s own
  `--intent` flag, alongside any `--coordinated` / `--no-coordinated` flag it
  received. When the work splits, `/plan` sets the PLAN's mode by the
  precedence rule in Interfaces: *continue* resolves to `coordinated`, *stop* or no intent
  resolves to `multi-pr`. When the work doesn't split, the mode is `single-pr`
  regardless of intent or coordination flags.
- **R6.** A `coordinated` PLAN may place all of its PRs in one repository. In
  that case each split unit is its own PR group in that repository, so the
  PLAN still produces one PR per unit plus the coordination PR. `/execute`'s
  coordinated path gives each PR group in a repository its own branch and PR,
  so several groups in one repository don't share a branch. The
  coordination strategy reference, `/plan`'s coordinated-mode text, and the
  coordination-PR declaration marker stop describing coordinated as
  multi-repo only, and `shirabe validate --coordination-body` accepts a
  single-repo coordination body.
- **R7.** A coordinated PLAN needs no GitHub issues. Like a `multi-pr` PLAN,
  it follows the resolved tracking level. At `none`, the default for
  coordinated, the work items live in `## Issue Outlines` with local IDs,
  each outline names its repository and PR group, nothing is filed, and
  `/execute` runs the PLAN from the outlines. Only when the repository's
  tracking level asks for issues does `/plan` file them; then, under
  `--auto`, its issue-filing approval resolves by its decision protocol
  instead of blocking, and interactively it asks as it does today.
- **R8.** `--coordinated`, `--no-coordinated`, and the CLAUDE.md coordination
  headers keep working as they do today for multi-repo efforts, subject to the
  precedence rule.

### Ending a `/scope` run

- **R9.** With `--intent` set, `/scope` pushes its branch to the `origin`
  remote and opens a PR carrying every document the run committed, before it
  exits. The PR's title contains the topic slug, so `/execute`'s existing
  home-PR lookup finds it. It opens exactly one PR per run, at exit, once the
  PLAN's mode is known: with `--intent` set, `/scope` never creates a
  coordination PR up front, and a PR left open on the branch by an earlier
  attempt at the same run is reused. The branch is the one `/scope` already requires (named, not the
  default branch).
  - For a `single-pr` PLAN the PR is a draft; it's the PR `/execute` adopts
    as its home PR.
  - For a `coordinated` PLAN the PR is a draft coordination PR carrying the
    coordination-PR declaration marker.
  - For a `multi-pr` PLAN the PR is opened ready for review, because it's
    meant to merge and land the Active PLAN on main.
  - On a `re-evaluation` or `abandonment-forced` exit, `/scope` still pushes
    the branch and opens a draft PR with what was committed.
- **R10.** Every `/scope` `full-run` exit summary names the next step for
  the PLAN's mode as `next=<command>`: `/execute <plan-path>` for `single-pr`
  and `coordinated`, and `/work-on <first startable issue>` for `multi-pr`,
  where the first startable issue is the first entry of R11's list.
- **R11.** For a `multi-pr` PLAN, the exit report lists the issues with no
  dependency on another issue in the PLAN, as issue number and title in PLAN
  order. With `--intent`, it states that they can start once the scoping PR
  merges and names that PR; without intent, it states that they can start
  once the PLAN is on the default branch. Its outcome is
  `handed-off-multi-pr`.
- **R12.** If the push or PR creation in R9 fails (no `origin` remote, `gh`
  not authenticated, push rejected), `/scope` still records its exit and ends
  with `outcome=error` naming `scope:push` or `scope:pr-create`. It doesn't
  silently fall back to the no-intent behavior.
- **R13.** `/scope` never invokes `/execute`, with any intent.

### The driver

- **R14.** A new skill, `/deliver <topic>`, runs `/scope <topic>
  --intent=continue` and then `/execute <plan-path>` in one session, without
  the author re-invoking anything. It passes `--merge` to `/execute` unless
  `--no-merge` is given.
- **R15.** `/deliver` resolves interactive vs non-interactive once, from its
  own `--auto` / `--interactive` flag or the CLAUDE.md header, and passes the
  result to both children. Interactively, it shows the PLAN's mode and asks
  for confirmation before starting `/execute`; with `--auto` it asks nothing.
- **R16.** When the PLAN `/deliver` receives is `multi-pr` (reachable through
  `--no-coordinated` or an already-existing PLAN), `/deliver` doesn't invoke
  `/execute` and ends `handed-off-multi-pr` with R11's list.
- **R17.** Re-invoking `/deliver` on the same topic resumes:
  - an unfinished `/scope` run in the same working copy resumes inside
    `/scope` at the hop it stopped;
  - a topic whose PLAN exists on the checked-out branch passes through
    `/scope`, which re-runs its publish step (opening the branch's PR if none
    is open), and then resumes inside `/execute`, which adopts that PR or
    coordination PR; either way it writes no new BRIEF, PRD, or DESIGN;
  - an unfinished `/scope` run started with a different intent isn't
    converted: `/deliver` ends `outcome=error` naming `deliver:intent-mismatch`;
  - a topic whose PLAN has already been executed and removed (its DESIGN is
    under `docs/designs/current/`) doesn't re-scope: `/scope` reports
    `outcome=executed` naming the branch's PR, and `/deliver` reports `merged`
    or `ready-awaiting-merge` from it without running `/execute`;
  - the resumed `/execute` gets `--merge` unless the re-invocation passes
    `--no-merge`; the earlier run's setting isn't remembered.
  R16 takes precedence over this requirement for `multi-pr` PLANs.
- **R18.** `/deliver` ends in one of the Final States it emits and prints the
  PRs involved: for `ready-awaiting-merge` and `paused-awaiting-merges`, each
  unmerged PR and whether it's waiting on a human or on a predecessor; for
  `paused-awaiting-merges`, the command to resume.

### Merging

- **R19.** With `--merge`, `/execute` merges a PR only when all of these hold,
  and never passes an administrator or bypass option:
  - the PR is ready for review (not draft);
  - every check that ran on the PR's head commit has completed successfully,
    required or not; `/execute` waits for running checks up to a CI wait
    limit of 30 minutes per head commit, configurable for tests;
  - GitHub reports the PR's merge state as clean (no outstanding required
    review, no conflicts, no failing protection rule), and no review asks for
    changes;
  - at least one check reported on the head commit, and the head commit is
    the one this run pushed;
  - the base branch requires status checks or reviews. An unprotected base
    never merges in v1;
  - every check the base requires has reported success;
  - an approving review exists when the base requires one, or when the PR
    changes workflow files (`.github/workflows/`, `.github/actions/`) or a
    CODEOWNERS file.
  Only PRs in the same repository, opened by the authenticated user against
  the expected base, are ever adopted or merged; any other match is an error
  (`execute:pr-adopt`).
  A failing check ends the run `error` naming `execute:ci`, checks still
  running at the limit end it `error` naming `execute:ci-timeout`, and a draft
  PR that can't be marked ready ends it `error` naming `execute:ready`. These
  are the same whether or not `--merge` is given.
  It merges with the repository's single allowed method; with squash when
  several are allowed and squash is one of them; otherwise with a merge
  commit. It passes the head commit it evaluated, so a head that moved since
  is refused rather than merged. `/execute` marks a draft PR it adopted ready before
  evaluating these conditions, as it does today.
- **R20.** When R19's merge-state condition fails, or the merge call itself
  fails, `/execute` doesn't retry with other options and ends
  `ready-awaiting-merge` (single-pr) or `paused-awaiting-merges` /
  `ready-awaiting-merge` (coordinated, per Final States), naming the PR and
  the failed condition. Without `--merge`, `/execute` never merges and a
  finished run ends `ready-awaiting-merge`.
- **R21.** For a `coordinated` PLAN with `--merge`, `/execute` merges each PR
  only after all its predecessors in the merge order have merged, and merges
  the coordination PR after every other PR.
- **R22.** For a `coordinated` PLAN that ends `paused-awaiting-merges`, the
  coordination PR stays open (not closed), and a later `/execute` or
  `/deliver` on the same PLAN resumes from it and produces the PRs whose
  predecessors have since merged, without re-scoping.

### Truthful routing and status

- **R23.** `/plan`'s closing advice and `/scope`'s resume redirect for an
  Active PLAN route `single-pr` and `coordinated` PLANs to `/execute` and
  `multi-pr` PLANs to `/work-on`.
- **R24.** In `/execute`'s and `/work-on`'s SKILL.md descriptions, output
  sections, and exit definitions, the word "merged" describes only the
  `merged` final state. The `full-run` exit is defined by the Final States
  above.
- **R25.** The shared parent-skill state schema lists `coordinated` as a valid
  `plan_execution_mode`, and `/scope`'s PLAN-status table states, for each of
  `single-pr`, `multi-pr`, and `coordinated`, the status `/plan` actually
  writes.

### Non-functional

- **R26.** Each requirement R1-R25, R30, and R31 is covered by at least one eval scenario
  that declares the requirement IDs it covers. Scenarios that depend on
  GitHub state run against the `gh` shim under the owning skill's
  `evals/fixtures/bin/`, with scenarios for mergeable and not-mergeable PRs.
  Fixtures that need a split force it through a hard constraint in the
  upstream DESIGN; fixtures that need no split use a design small enough that
  `/plan` has no split reason. Each new scenario passes 3 of 3 runs.
- **R27.** Existing evals for `/scope`, `/plan`, `/execute`, and `/work-on`
  pass. Where one asserts behavior or text this PRD deliberately changes (R7's
  issue-free coordinated default, R10, R23, R24, R31), it's updated in the same
  change, and nothing else about it changes.
- **R28.** Each skill that gains a write lists it in its SKILL.md
  write-target section: `/scope` gains `git push` and `gh pr create`,
  `/execute` gains `gh pr merge`, and `/deliver` declares its one write of its
  own, the koto request it opens per run, with every repository write happening
  through its children.
- **R29.** `/deliver` inherits `/scope`'s repository binding (public-repo
  tactical chains in v1).
- **R30.** `/deliver`'s sequencing, confirmation, resume, and outcome mapping
  are enforced by a koto workflow, not skill prose. `/scope` and `/execute`
  report every outcome to `/deliver` as a koto result recorded against the
  current `/deliver` run, including their refusals and resume shortcuts; a
  result left over from an earlier `/deliver` run is never read as the
  current one. `/deliver` doesn't parse the children's printed output to
  decide anything.
- **R31.** Every `/scope` and `/execute` invocation, with or without
  `/deliver`, ends in a koto terminal state that declares its outcome, so the
  printed exit lines are rendered from the recorded result rather than
  composed by the agent. A second `/scope` run on a topic whose earlier run
  finished starts a fresh run rather than reattaching to the finished one.
- **R32.** The koto features these requirements need ship in a koto release
  before the shirabe changes merge, and `/scope`, `/execute`, and `/deliver`
  declare that koto version as their minimum.

## Acceptance Criteria

Unless stated otherwise, each criterion is an eval scenario under R26, and
"the shim" is the `gh` stand-in with a named scenario.

### Intent and mode

- [ ] `/scope <topic> --intent=bogus` and `/scope <topic> --intent=stop
      --intent=continue` each end with an error naming `--intent`, and no
      `/scope` state file or `scope-<topic>` session exists
      afterwards (R1).
- [ ] On the forced-split fixture, `/scope` with no intent produces
      `execution_mode: multi-pr`, commits locally, and the shim logs no
      `pr create` call; `git ls-remote origin` shows no topic branch (R2).
- [ ] On the no-split fixture, `/scope` with no intent produces
      `execution_mode: single-pr` and the shim logs no `pr create` call (R2).
- [ ] The state file records `intent: continue`, `intent: stop`, and
      `intent: none` for the three invocations, and each exit summary contains
      the matching `intent=` token (R3).
- [ ] On the no-split fixture, `/scope` prints `outcome=scoped`; on the
      forced-split fixture with `--intent=continue` it prints `outcome=scoped`,
      and with no intent `outcome=handed-off-multi-pr` (Final States).
- [ ] On the forced-split fixture, the split reason branch recorded in the
      PLAN is the same for `--intent=continue`, `--intent=stop`, and no intent
      (R4).
- [ ] On the forced-split fixture, `--intent=continue` produces
      `execution_mode: coordinated` with every PR group in the one repository
      and at least two PR groups; `--intent=stop` produces `multi-pr` (R5, R6).
- [ ] On the no-split fixture, `--intent=continue`, `--intent=stop`, and no
      intent all produce `single-pr` (R5).
- [ ] On the forced-split fixture, `--intent=continue --no-coordinated`
      produces `multi-pr`, and `--intent=stop --coordinated` on the
      multi-repo fixture produces `coordinated` (R5, R8).
- [ ] `shirabe validate --coordination-body` passes on the coordination body a
      single-repo *continue* run writes, and the body's declaration marker
      doesn't say "multi-repo" (R6).
- [ ] A `--auto --intent=continue` run on the forced-split fixture in a
      repository with no tracking-level header reaches `full-run` with a
      coordinated PLAN whose work items are outlines, each naming a repository
      and PR group; the shim logs no `issue create` call (R7).
- [ ] `plan-to-tasks.sh` on that outline-shaped coordinated PLAN emits one PR
      node per group with `ISSUES` listing local outline IDs, and `/execute`
      runs it to its PRs with no `gh issue` call in the shim log (R7).
- [ ] `shirabe validate` accepts the outline-shaped coordinated PLAN and
      reports FC14 when a coordinated PLAN populates both outlines and an
      issue table (R7).
- [ ] The same run in a repository whose CLAUDE.md sets
      `## Tracking Level: issues` files one issue per outline (the shim logs
      one `issue create` each) with no approval prompt under `--auto` (R7).
- [ ] `/scope --coordinated` on the multi-repo fixture still creates the
      coordination PR before the first child runs (R8).
- [ ] `/plan <design> --intent=continue` invoked directly on the forced-split
      fixture's DESIGN produces `coordinated`; `--intent=stop` produces
      `multi-pr`; and the `/plan` hop inside `/scope --intent=continue` is
      invoked with `--intent=continue` (R5).
- [ ] On the forced-split fixture in a repository whose CLAUDE.md coordination
      headers resolve to coordinated, `--intent=stop` produces `multi-pr` and
      no intent produces `coordinated` (R5, R8).
- [ ] An interactive `--intent=continue` run on the forced-split fixture in a
      repository with `## Tracking Level: issues` asks for issue-filing
      approval before any `issue create` is logged (R7).
- [ ] `references/coordination-strategy.md` and `/plan`'s coordinated-mode
      section contain no statement that coordinated requires more than one
      repository (R6).

### `/scope` exit

- [ ] After `--intent=continue` on the no-split fixture, the shim logs one
      `pr create --draft` on the topic branch whose title contains the topic
      slug, and `git ls-remote origin` shows the branch (R9).
- [ ] After `--intent=continue` on the forced-split fixture, the shim logs
      exactly one `pr create`, a draft whose body contains the coordination-PR
      declaration marker (R9).
- [ ] `--intent=continue --coordinated` on the multi-repo fixture logs exactly
      one `pr create` for the whole run, made after the PLAN hop, never before
      the first child runs (R9).
- [ ] After `--intent=stop` on the forced-split fixture, the created PR is not
      a draft (R9).
- [ ] Runs with `--intent=continue` that end `abandonment-forced` and,
      separately, `re-evaluation` each log a push and a `pr create --draft`
      whose branch contains every document the run committed (R9).
- [ ] The exit summary contains `next=/execute docs/plans/PLAN-<topic>.md` for
      `single-pr` and `coordinated` PLANs and `next=/work-on` for a `multi-pr`
      PLAN, with and without intent (R10).
- [ ] On the mixed-dependency fixture (two roots, a chain, and a diamond), the
      `multi-pr` exit report of an `--intent=stop` run lists exactly the two
      root issues, number and title, in PLAN order, names the scoping PR, and
      prints `outcome=handed-off-multi-pr` with `next=/work-on <first root>`;
      the no-intent run lists the same issues and names no PR (R10, R11).
- [ ] With the shim's `pr create` failing, an `--intent=continue` run records
      its exit in the state file and prints `outcome=error` with
      `scope:pr-create`; with no `origin` remote it prints `scope:push` (R12).
- [ ] No `execute-<topic>` koto session and no `/execute` state file
      exist after any `/scope` run, with any intent (R13).
- [ ] `/execute` on the PLAN a single-pr `--intent=continue` run produced
      adopts the open PR; the shim logs no second `pr create` and no
      `impl/<topic>` branch is created (R9, R13).

### `/deliver`

- [ ] `/deliver <topic> --auto` on the no-split fixture with the shim's
      mergeable scenario logs exactly one `pr merge` call, prints
      `outcome=merged`, and the transcript shows no question between `/scope`
      and `/execute` (R14, R15, R19).
- [ ] `/deliver <topic> --interactive` on the same fixture asks one
      confirmation naming `single-pr` before `/execute` starts (R15).
- [ ] `/deliver <topic>` with no mode flag in a repository whose CLAUDE.md
      has `## Execution Mode: auto` asks no question (R15).
- [ ] `/deliver <topic> --interactive`, after confirmation, ends
      `outcome=paused-for-review` with the home PR still draft when the
      author declines finalization at `/execute`'s review pause (Final
      States).
- [ ] `/deliver <topic> --auto --no-merge` with the mergeable scenario logs no
      `pr merge` call and prints `outcome=ready-awaiting-merge` (R14, R20).
- [ ] `/deliver <topic> --auto --no-coordinated` on the forced-split fixture
      starts no `/execute` session and prints `outcome=handed-off-multi-pr`
      with the root-issue list (R16).
- [ ] Re-invoking `/deliver` after a run stopped during the PRD hop resumes at
      the PRD hop; re-invoking it on a checked-out branch whose PLAN exists
      and has an open PR adopts that PR, and on one with no PR has `/scope`
      open it (one `pr create` on the topic branch) before `/execute` adopts
      it; neither creates a BRIEF, PRD, or DESIGN commit (R17).
- [ ] Re-invoking `/deliver` on a topic whose unfinished `/scope` run has
      `intent: stop` prints `outcome=error` with `deliver:intent-mismatch` and
      changes nothing (R17).
- [ ] A `/deliver` run whose `/scope` ends `re-evaluation` prints
      `outcome=scope-ended-early` naming `re-evaluation`, and starts no
      `/execute` session (R18).
- [ ] A `/deliver` run with the shim's CI-red scenario prints `outcome=error`
      naming `execute:ci` (R18).
- [ ] A coordinated `/deliver` run with the not-mergeable scenario prints
      `outcome=paused-awaiting-merges`, lists each unmerged PR with "waiting
      on human" or "waiting on predecessor", and prints a resume command (R18,
      R22).

### Merging

- [ ] `/execute` without `--merge` on the mergeable scenario logs no `pr
      merge` call and ends `ready-awaiting-merge` (R20).
- [ ] `/execute --merge` on scenarios returning a review-required merge
      state and, separately, a conflicting merge state logs no `pr merge` call
      for either and ends `ready-awaiting-merge` naming the condition (R19,
      R20).
- [ ] `/execute --merge` on a scenario with a failing non-required check ends
      `error` naming `execute:ci`; with a check still pending past the
      CI wait limit, `error` naming `execute:ci-timeout`; with a draft PR
      whose `pr ready` call fails, `error` naming `execute:ready`. None logs a
      `pr merge` call (R19).
- [ ] `/execute --merge` on a scenario where every pre-check passes but `pr
      merge` returns an error ends `ready-awaiting-merge`, logs exactly one
      `pr merge` call, and never reports `merged` (R20).
- [ ] No logged `pr merge` call carries `--admin` or `--auto` (R19).
- [ ] `/execute --merge` on scenarios where the base branch has no protection,
      where no check ever reports, and where the PR head differs from the
      pushed commit logs no `pr merge` call and ends `ready-awaiting-merge`
      naming `base-unprotected`, `no-checks`, and `head-moved` (R19).
- [ ] `/execute --merge` on a base requiring a review, with no approval, and on
      a base requiring only checks, with a PR that edits
      `.github/workflows/`, logs no `pr merge` call and ends
      `ready-awaiting-merge` naming `review` and `workflow-change` (R19).
- [ ] With a same-named PR from a fork (or by another author) on the head
      branch, `/execute` doesn't adopt it and ends `error` naming
      `execute:pr-adopt` (R19).
- [ ] A session started with `--merge` and resumed without it logs no `pr
      merge` call (R17, R19).
- [ ] On a repository scenario allowing merge and squash, the logged call
      uses `--squash`; allowing only rebase, it uses `--rebase` (R19).
- [ ] On the single-repo coordinated fixture with the mergeable scenario,
      every PR group's PR has a distinct head branch, the shim's merge log
      orders every PR after all its predecessors and the coordination PR last,
      and the run ends `merged` (R6, R21).
- [ ] On the same fixture with only the root PRs mergeable, the run ends
      `paused-awaiting-merges` with every root PR ready and CI-green, no PR
      opened for a non-root unit, and the coordination PR open (the shim logs
      no `pr close`) (R22).
- [ ] After the shim marks the root PRs merged, a second `/execute` and,
      separately, a second `/deliver` on that PLAN open exactly the next
      layer's PRs and log no scoping commit (R22).

### Routing, status, and non-functional

- [ ] `/plan`'s closing advice names `/execute` for a `single-pr` and a
      `coordinated` PLAN and `/work-on` for a `multi-pr` PLAN (R23).
- [ ] `/scope`'s resume redirect on an Active PLAN names `/execute` for
      `single-pr` and `coordinated` and `/work-on` for `multi-pr` (R23).
- [ ] `grep -n merged` over `skills/execute/SKILL.md` and
      `skills/work-on/SKILL.md` returns no line describing a non-`merged`
      final state or exit as merged (checked by a script added with this
      change) (R24).
- [ ] `/scope`'s state-file enum re-validation accepts
      `plan_execution_mode: coordinated` and still rejects
      `plan_execution_mode: bogus`, and the shared state-schema reference lists
      all three values (R25).
- [ ] `/scope`'s PLAN-status table lists a status for each of `single-pr`,
      `multi-pr`, and `coordinated` that matches what `/plan` writes on the
      three fixtures (R25).
- [ ] Every new eval scenario lists the requirement IDs it covers, every ID
      R1-R25, R30, and R31 appears at least once, and each new scenario passes with
      `--runs 3` (R26).
- [ ] The existing `/scope`, `/plan`, `/execute`, and `/work-on` eval suites
      pass, and the diff to them touches only assertions about R7, R10, R23,
      R24, or R31 behavior (R27).
- [ ] `skills/scope/SKILL.md`'s write-target section lists `git push` and `gh
      pr create`, `skills/execute/SKILL.md`'s lists `gh pr merge`, and
      `skills/deliver/SKILL.md` declares the per-run koto request as its only own write and every repository write as its children's
      (R28).
- [ ] `/deliver` on a private-repo fixture refuses the same way `/scope` does
      (R29).
- [ ] `/deliver`'s template, compiled by koto, contains a state for each
      step of R14-R18 (scope, check, mode route, confirm, execute, merged
      re-check, report), and every `/deliver` eval asserts its outcome from
      the session's terminal result, not from printed lines (R30).
- [ ] A `/deliver` re-run after an earlier run's `/scope` child finished
      reports the new run's `/scope` result; the earlier run's terminal
      result is refused as stale (R30).
- [ ] With a child that returns without recording a result, `/deliver` ends
      `outcome=error step=deliver:child-absent` (R30).
- [ ] A `/scope --koto-leg` run refused at argument validation (for example
      `--intent=bogus`) records `scope:refused` on its leg and opens no
      session; `/deliver` relays `outcome=error step=scope:refused` (R1, R30).
- [ ] Every terminal state in `/scope`'s and `/execute`'s templates declares
      a result with at least `outcome`, and each skill's exit lines are
      printed by a script from that result (R31).
- [ ] A second `/scope <topic>` after an earlier run on the topic reached its
      terminal starts a new session rather than ticking the finished one, on
      both the no-intent and intent paths (R31).
- [ ] Each of the three skills' `requires.tsv` declares the koto minimum, and
      preflight on an older koto reports it before any work starts (R32).

## Out of Scope

- **Automatic per-issue fan-out after a stop-at-PLAN run.** Starting one
  session per startable issue is a natural follow-on, but it depends on
  per-issue `/work-on` runs behaving correctly against an Active PLAN, which
  hasn't been verified with a real run. R11 lists the issues; launching
  sessions for them is later work.
- **Moving `multi-pr` execution into `/execute`.** That's separate in-flight
  work. A `multi-pr` PLAN still runs one issue at a time through `/work-on`.
- **Changing when `/plan` splits work.** The split reasons stay as they are
  (R4); only which multi-PR mode a split resolves to depends on intent.
- **Merging by default, or merging the scoping PR.** Direct `/execute` doesn't
  merge unless asked (R20), `/scope` never merges its own PR, and this feature
  grants no permissions a session doesn't already have.
- **The chain-finalization cascade.** What finalization does to the BRIEF,
  PRD, DESIGN, and PLAN doesn't change; for a single-repo coordinated PLAN it
  runs where it runs for a multi-repo one.
- **Background polling for merges.** A paused run ends; resuming is a
  re-invocation (R22), not a wait loop.
- **The strategic chain.** `/charter` and its handoff into `/scope` are
  untouched.
- **A koto template for `/plan`, and a full koto template for coordinated
  execution.** The split-mode decision is already a deterministic script, and
  the coordinated merge order moves into a tested action script; wrapping
  either in its own template is later work.

## Known Limitations

- A driven run in a repository with required human reviews always ends
  `ready-awaiting-merge` or `paused-awaiting-merges`. That's correct, but it
  means "done when merged" is only reachable end to end where the session's
  merges aren't gated on a person.
- `/deliver` resumes from the checked-out branch only. Resuming an
  unfinished `/scope` run also needs its local state file, so it works only
  in the same working copy; resuming from a pushed PLAN in another copy means
  checking out that branch first. `/deliver` doesn't search the remote for a
  topic's branch.
- A stop-at-PLAN `multi-pr` run's issues can start only after a human (or a
  session with the rights) merges the scoping PR; `/scope` doesn't merge it.
- Every `/scope`, `/execute`, and `/deliver` run needs the koto release that
  carries the new features, including plain no-intent `/scope` runs.
- The koto request store that ties `/deliver` to its children is local to one
  machine, so a `/deliver` run resumes only on the machine it started on.

## Decisions and Trade-offs

- **Intent is declared, not predicted.** The alternative was to predict the
  mode at launch, for example with a flag biasing `/plan` toward one PR. A
  prediction can still be wrong when a hard constraint forces a split, and the
  session would then stall. Declaring intent makes every outcome something the
  session can act on.
- **A split resolves to `coordinated` under *continue* and `multi-pr`
  otherwise.** The two modes differ in where the PLAN lives while work is in
  flight and whether a driver stays with it. That's the caller's intent, not
  the shape of the work. Coordinated keeps the incremental-value benefit of
  splitting, because each PR still merges on its own; only the PLAN waits.
  This drops coordinated's multi-repo-only restriction (R6).
- **The `/scope` flag shapes; the driver invokes.** This answers the framing's
  first open question. `--intent` ends at leaving the branch on a PR in the
  shape `/execute` adopts (R9, R13); `/deliver` calls `/execute`. The
  alternative, `/scope` invoking `/execute` itself, would make the driver
  thinner but have one parent skill invoke another, which no existing skill
  does. Keeping them as peers also makes `/scope --intent=continue` useful on
  its own (story 5).
- **Merging is opt-in, requested by the driver, and bounded by what GitHub
  reports.** This answers the framing's second open question. Alternatives were
  a per-repository setting or probing permissions ahead of time. R19 checks the
  PR's own state (ready, all checks green, clean merge state) and treats a
  failed merge call as "not possible", which needs no configuration and can't
  claim a merge the repository wouldn't allow. `--no-merge` covers teams that
  want a human to press merge. Direct `/execute` keeps today's "ready, human
  merges" behavior unless asked, so the draft/ready discipline holds for every
  caller that doesn't opt in.
- **Explicit coordination flags beat intent.** `--coordinated` and
  `--no-coordinated` are the most specific statement an author can make about
  mode, so they win; intent beats the CLAUDE.md headers because it's stated
  per run.
- **A stop-at-PLAN `multi-pr` PR is opened ready, not draft.** It exists to
  merge and land the Active PLAN on main, the only mode where CI allows that.
  Opening it as draft would add a step with no review value.
- **No intent means today's behavior.** A split with no intent resolves to
  `multi-pr` and nothing is pushed (R2, R5), so existing users see no change
  beyond the exit summary.
- **Pausing beats polling for coordinated runs without merge rights.** A named
  pause with resume from the coordination PR (R22) ends the session cleanly and
  uses state that already exists on the PR.
- **The driver is a koto workflow, and its children report through koto.**
  The first design made `/deliver` a stateless skill that parsed its
  children's printed lines. The author asked for the chain to be controlled
  by workflows as far as possible, extending koto where it falls short. So
  `/deliver` is a koto template, and `/scope` and `/execute` each attach to a
  per-run koto request leg that records their terminal result (R30). The two
  children are treated the same way, which meant moving `/scope`'s argument
  checks and resume shortcuts into its template (R31). The cost is a koto
  release the shirabe changes depend on (R32).
- **The driver is named `/deliver`.** It says what the run does end to end
  without colliding with `/release` (versions) or `/execute` (a finished
  PLAN).

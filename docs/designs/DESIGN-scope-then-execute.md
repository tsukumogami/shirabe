---
schema: design/v1
status: Proposed
problem: |
  A caller can't launch one session that scopes a feature and drives it to
  merged code. The PLAN's mode is chosen inside /plan from inputs the caller
  can't reach, and /plan never emits coordinated at all. /scope never pushes
  or opens the PR /execute expects to adopt. Nothing in the chain merges.
  And nothing is allowed to sequence two parent skills.
decision: |
  /plan owns --intent and the coordination flags, which /scope forwards; on a
  split it resolves coordinated or multi-pr by precedence. Coordinated works
  in one repository, with a branch and PR per PR node. /scope publishes one
  PR through gated publish states before cleanup. /execute gains an opt-in
  --merge through new koto states, a read-only verdict script and a fixed-flag
  merge script, with coordinated merges in merge order and a resumable pause.
  A stateless /deliver skill runs /scope --intent=continue and then /execute.
rationale: |
  Each piece puts a decision where the evidence for it already lives. The
  split reason stays in /plan, and mode follows it. Publishing sits between
  the recorded exit and cleanup. Merging is gated by a live GitHub read.
  Resume reads the PLAN and PRs. Alternatives either had a parent rewrite or
  invoke another skill, trusted agent evidence for irreversible steps, forked
  the coordinated path, or kept local state that could drift from the branch.
upstream: docs/prds/PRD-scope-then-execute.md
user_visible_surface: true
---

# DESIGN: scope-then-execute

## Status

Proposed

## Context and Problem Statement

A caller can't launch one session that scopes a feature and then drives it to
merged code, because four pieces of the chain don't line up.

First, the execution mode is decided inside `/plan`'s decomposition step
(step 3.6), from the repository's Delivery Preference and the split reasons it
records in `split_rationale`. `/scope` hands `/plan` only the DESIGN path (plus
`--upstream`), so nothing the caller says at launch can influence which
multi-PR mode a split resolves to. `coordinated` is only reachable through
`/scope`'s `--coordinated` flag or CLAUDE.md headers, which create a
coordination PR up front, before any hop runs, and assume more than one
repository.

Second, `/scope` never pushes and never opens a PR in single-repo mode.
`/execute`'s single-pr path adopts an open PR on the current branch as its
home PR; finding none, it cuts `impl/<slug>` instead. So the PLAN and the code
reach one PR only by accident of branching.

Third, nothing merges. `/execute`'s single-pr koto template ends at `done`
after `plan_completion` marks the PR ready and `ci_monitor` sees green CI.
Its coordinated loop advances only when predecessors merge, and nothing in the
loop merges them. `gh pr merge` is outside `/execute`'s declared write-target
set, and the draft/ready design records "the agent marks ready; the human
merges". Yet `/execute`'s description and `full-run` exit say "merged".

Fourth, there's no place for "scope, then execute" to live. Parent skills
today hand off by naming the next command; none invokes another. The
parent-skill pattern names a parent-of-the-parent slot but nothing fills it.

The PRD resolves the product questions. This design has to settle how each
requirement is met inside the existing skills:

- **Intent (R1-R3).** `/scope` accepts `--intent=continue|stop`, rejects bad
  or repeated values before writing state, records `intent: continue|stop|none`
  in its state file, and prints `intent=<value>` at exit. No intent means
  today's behavior (R2).
- **Split resolution (R4-R8).** `/plan` keeps its split rules and records the
  same split reason whatever the intent. When the work splits, the mode follows
  the precedence explicit `--coordinated`/`--no-coordinated` > `--intent` >
  CLAUDE.md coordination headers > default `multi-pr`; `continue` resolves to
  `coordinated`, `stop` or none to `multi-pr`. `/plan` gains its own `--intent`
  flag, which `/scope` forwards (R5). A coordinated PLAN may live in one
  repository, one PR group per split unit, each with its own branch and PR
  (R6), and a *continue* split files per-PR issues, with `/plan`'s filing
  approval resolved by its decision protocol under `--auto` (R7). Existing
  multi-repo coordination keeps working (R8).
- **`/scope` exit (R9-R13).** With `--intent`, `/scope` pushes its branch to
  `origin` and opens exactly one PR whose title contains the topic slug: a
  draft home PR for `single-pr`, a draft coordination PR for `coordinated`
  (opened at exit; intent runs never create one up front), a ready PR for
  `multi-pr`,
  and a draft on `re-evaluation` or `abandonment-forced`. Every `full-run`
  exit prints `next=` for the mode and `outcome=scoped` or
  `outcome=handed-off-multi-pr`, the latter listing the dependency-free issues.
  Push or PR failure ends `outcome=error` naming `scope:push` or
  `scope:pr-create`. `/scope` never invokes `/execute` (R13).
- **The driver (R14-R18, R29).** A new `/deliver <topic>` runs
  `/scope --intent=continue` then `/execute --merge` (unless `--no-merge`) in
  one session, resolves interactive vs `--auto` once and passes it down, asks
  one confirmation before `/execute` when interactive, stops at
  `handed-off-multi-pr` for a `multi-pr` PLAN, resumes from the checked-out
  branch (refusing an intent mismatch), and ends in a named final state.
- **Merging (R19-R22).** `/execute --merge` merges only a ready PR at the
  commit this run pushed, whose every check (and every required one) has
  passed, whose merge state is clean, whose base branch actually requires
  checks or reviews, and which has an approving review where the rules require
  one or where it edits workflow files. It never uses an admin or bypass
  option, and picks the repository's single allowed method, else squash, else
  a merge commit.
  A failing check, a check-wait timeout, or an un-draftable PR is an `error`;
  an unclean merge state or a failed merge call ends `ready-awaiting-merge`.
  Coordinated merges follow the merge order with the coordination PR last,
  and a run blocked on merges ends `paused-awaiting-merges` with the
  coordination PR left open and resumable.
- **Truthful routing (R23-R25).** Next-step advice routes `single-pr` and
  `coordinated` to `/execute` and `multi-pr` to `/work-on`; "merged" in
  `/execute`'s and `/work-on`'s text means only the `merged` state; the state
  schema accepts `coordinated`.
- **Verification (R26-R28).** Every requirement has an eval scenario that names
  it, GitHub state comes from the `gh` shim, splits are forced by fixture
  design, and each new scenario passes 3 of 3 runs. Skills that gain writes
  declare them.

## Decision Drivers

- **D1. Parents stay peers.** No parent skill invokes another; the
  parent-of-the-parent slot is where chaining lives. `/scope` must not call
  `/execute` (R13), and a child's input surface may only grow through flags the
  child itself owns and documents for direct use, the rule the parent-skill
  pattern states for `--upstream`.
- **D2. No-intent runs are byte-for-byte today's behavior** apart from the exit
  summary (R2, R27). Existing evals only change where they assert text this
  feature deliberately changes.
- **D3. Merging must be impossible to over-claim.** A run reports `merged` only
  after GitHub says the PR merged; the merge never bypasses protection; and
  direct `/execute` without `--merge` never merges (R19, R20).
- **D4. Everything observable must be testable through the `gh` shim.** The
  mergeability signals, PR creation, pushes, and merges have to be `gh` or
  `git` calls the eval shim can serve and log (R26).
- **D5. Reuse the coordinated machinery rather than fork it.** Single-repo
  coordinated should run through the same loop, body template, validator, and
  merge-order DAG as multi-repo coordinated (R6, R21, R22).
- **D6. Resume from durable state.** Resume paths read the pushed PR or the
  coordination PR, not only local `wip/` state, wherever the requirement allows
  it (R17, R22).
- **D7. Declared write sets stay closed.** Every new push, PR, and merge is
  added to the owning skill's write-target declaration in the same change
  (R28).
- **D8. Keep the driver thin.** `/deliver` sequences two parents and maps their
  outcomes; it shouldn't re-implement resume ladders, state schemas, or merge
  logic that `/scope` and `/execute` already own.

## Considered Options

### Decision 1: How intent reaches `/plan` and resolves a split

`/plan` decides a PLAN's mode at step 3.6 of its decomposition phase, and today
that step has only two outcomes, `single-pr` and `multi-pr`. Tracing the code
shows `/plan` never writes `execution_mode: coordinated` at all: it doesn't
parse `--coordinated`/`--no-coordinated`, doesn't read the CLAUDE.md
coordination headers, and its creation phase has no coordinated branch, even
though `plan-to-tasks.sh`, the PLAN format, and `/scope`'s state enum all
consume the value. `/scope` hands the `/plan` hop only the DESIGN path and
`--upstream`. So neither intent nor the existing coordination flags reach the
mode today. The parent-skill rule allows a parent to pass a child only flags
the child itself documents for direct use (as `--upstream` already is), or the
uniform `parent_orchestration:` sentinel.

Key assumptions:

- The header values that mean "coordinated by default" can be pinned once, in
  `references/coordination-strategy.md`, and read by both `/scope` and `/plan`.
- Multi-pr issue filing under `--auto` already proceeds without a blocking
  prompt; only the new coordinated filing path needs an explicit approval step.

#### Chosen: `/plan` owns `--intent` and the coordination flags; `/scope` forwards them

`/plan` gains `--intent=continue|stop`, `--coordinated`, and `--no-coordinated`
as flags it documents for direct use, and reads the coordination headers
itself. Step 3.6 becomes two questions in order. The first is unchanged: does
the work split, and on which branch (recorded in `split_branch` and
`split_rationale` exactly as today). Only when it splits does a new step 5a
pick the mode by precedence: explicit coordination flag, then intent, then a
coordinated-by-default header, then `multi-pr`, recording
`split_mode_source: flag|intent|header|default`. Because the split question is
answered before intent is consulted, the split reason can't vary with intent
(R4). `/scope` forwards its own `--intent`, the coordination flags exactly as
the caller passed them (never a header-derived `--coordinated`, which would
outrank `--intent`), and `--auto` when intent is set. A no-intent hop sends
the same argument string as today (D2). A new coordinated branch in `/plan`'s
creation phase reuses `create-issues-batch.sh`, with an explicit filing
approval that asks interactively and resolves by the decision protocol under
`--auto` (R7).

This also makes `/scope --coordinated` produce a coordinated PLAN for the first
time.

#### Alternatives Considered

**`/scope` rewrites `execution_mode` after `/plan` returns.** `/plan` would
stay untouched and `/scope` would edit the PLAN to `coordinated` and add group
rows. Rejected: the parent may read only a child artifact's status and hash,
not rewrite it (D1); it comes too late, because `/plan` has already filed
multi-pr issues without group rows; and direct `/plan --intent` couldn't
exist, which the PRD requires.

**Carry intent in the `parent_orchestration:` sentinel.** No new flag, and it
follows the precedent for suppressing status prompts. Rejected: the sentinel
is defined as one uniform signal every child reads the same way, so a field
only `/plan` consumes is the per-parent API the rule forbids, and it doesn't
exist on a direct `/plan` run.

**`/plan` gets only the coordination flags; `/scope` translates intent into
them.** Smaller surface on `/plan`. Rejected: it merges two precedence levels,
so `/scope` would have to resolve flag-versus-intent conflicts and read the
headers itself, and an intent-derived `--coordinated` becomes
indistinguishable from an explicit one in the PLAN's record.

**Ambient intent (a CLAUDE.md header, or `/plan` reading `/scope`'s state).**
Rejected: intent is a per-run choice, and a child reading a parent's state
couples it to one parent's schema.

### Decision 2: How a coordinated PLAN runs in one repository

Most of the coordinated machinery is already indifferent to repository count.
`plan-to-tasks.sh` keys PR nodes on `(repo, pr_group)`, so two groups in one
repo are two nodes, and contraction, ordering, and split-at-seam work
unchanged. The Rust validator (`crates/shirabe-validate/src/coordination.rs`
and `merge_gate.rs`) never counts repositories, and its declaration check
matches only the fixed prefix "This is a **coordination PR**", so a
single-repo body already validates. The gaps are prose that says
"multi-repo", `/plan` never emitting group rows, and `/execute`'s coordinated
loop cutting one branch per repository, which would make two groups in one
repo share a branch.

Key assumptions:

- `/work-on`'s `SHARED_BRANCH` contract (commit to the given branch; the
  orchestrator owns the PR) is stable enough to reuse per group.
- The eval `gh` shim can serve several PRs in one repo, keyed by branch.

#### Chosen: a branch per PR node on the existing coordinated path

The unit of branching becomes the PR node, not the repository. `/plan` tags
every issue of a coordinated split with the current repository and a per-unit
group slug. `plan-to-tasks.sh` adds `REPO`, `PR_GROUP`, and `ISSUES` to each
node entry so `/execute` doesn't re-parse the PLAN. `/execute` cuts
`impl/<slug>-<node-id>` from the default branch in its own worktree for each
unblocked node, dispatches the node's issues to `work-on.md` with that branch
as `SHARED_BRANCH`, then pushes and opens one draft PR per node and marks it
ready once its CI is green. Nodes are never cut from the coordination branch,
so no group PR carries the PLAN to main ahead of the coordination PR. On
resume, each node without an indexed PR is adopted through
`gh pr list --head impl/<slug>-<node-id>`. The strategy reference says "one or
more repositories", the body template drops "multi-repo" after the unchanged
prefix, and the validator gains single-repo tests. `lifecycle.yml` drops any
PR-index entry pointing at the coordination PR's own number, which would
otherwise make the merge gate wait on itself. Multi-repo PLANs with
`Group: default` keep one node per repo, so they behave as today.

#### Alternatives Considered

**A single-pr koto session per group, wrapped by a coordination PR.** Reuses
the most code on paper. Rejected: single-repo would run on N koto sessions
while multi-repo runs the durable-state loop, which D5 rules out; the
single-pr path would adopt the coordination PR as its home PR, session names
would collide across groups, and its completion step deletes the PLAN before
the coordination PR merges last.

**Every issue is its own PR node.** Drops groups for single-repo. Rejected:
R6 defines one PR per split unit, so a unit with several issues would become
several PRs, contradicting the recorded split reason and adding merge nodes
for nothing. With one issue per unit, the chosen option already produces this
shape.

**Stacked branches.** Each group branches from its predecessor. Rejected:
squash-merging the base orphans the stack and forces rebase steps the shim
would have to simulate, and R21 only opens a PR after its predecessors merge,
so stacking buys nothing.

### Decision 3: Where `/execute`'s opt-in merge lives

The single-pr koto template ends `plan_completion -> ci_monitor -> done`, the
coordinated loop waits for merges it never performs, and `gh pr merge` is
outside `/execute`'s write set. No CI wait limit exists anywhere, and koto's
polling timeout can't supply one because it fires no transition. shirabe's
default-action policy bars irreversible external calls like `gh pr merge`
from running as an automatic action. An existing eval pins the route
`ci_monitor -> escalate_dirty_merge_state -> done_blocked`, and `ci_monitor`'s
`failing_fixed` edge currently reaches `done` with no gate at all.

Key assumptions:

- `gh pr merge --match-head-commit` refuses when the head moved; a merge queue
  that accepts without merging is caught by the confirm read.
- A 30-minute CI wait per head commit is an acceptable default.
- A merge state of `HAS_HOOKS` is treated as not clean.

#### Chosen: new koto states after `ci_monitor`, backed by a read-only verdict script and a fixed-flag merge script

The verdict also requires the PR head to equal the commit the run pushed, a
protected base branch, at least one reported check, and no outstanding review;
merge intent is checked per invocation; and every PR lookup is
ownership-filtered (see Solution Architecture).

Single-pr gains `merge_readiness -> merge_route -> merge_attempt ->
merge_confirm` with two new terminals, `merged` and `ready_awaiting_merge`.
`merge_readiness` runs `merge-verdict.sh`, which reads one snapshot, applies
the decision table in Solution Architecture, owns the CI deadline, and writes
a verdict to koto context. `merge_route` routes on that verdict.
`merge_attempt` is agent-run (never a default action) and runs exactly
`merge-exec.sh <repo> <pr>`, the only `gh pr merge` call site in the
repository, which reads the recorded verdict for the method and head commit
and accepts no pass-through flags. `merge_confirm` re-reads
the PR and reaches `merged` only if GitHub reports `MERGED`. Merge intent is a
template variable set at `koto init` from `--merge`, never agent evidence, so a
run without `--merge` can't merge. `ci_monitor`'s gates and DIRTY route stay
as they are; its `passing` and `failing_fixed` edges retarget to
`merge_readiness`, which closes the ungated shortcut. The coordinated loop
calls the same two scripts per node in merge order and on the coordination PR
last.

#### Alternatives Considered

**Fold the merge into `ci_monitor`.** Fewer states. Rejected: koto's polling
ends early only when every gate passes, and `merge_state_clean` never passes
on a blocked PR, so the wait limit would fall back to agent prose the shim
can't check (D4); it would also take merge intent as agent evidence.

**A post-workflow merge script at the SKILL layer.** koto ends green and
SKILL.md runs one script that decides and merges. Rejected: the session's own
record says "done" before any merge, and one script that both reads and
writes leaves no check able to disagree with the action (D3). Its
shell-testable, fixed-flag script survives inside the chosen option.

**Merge outside `/execute`** (in `/work-on` children, or in `/deliver` after
`/execute` returns). Rejected: single-pr has no child PR to merge; adding a
merge flag to children breaks the parent-child rule (D1); and driver-side
merging contradicts the PRD's placement of `--merge` on `/execute`, removes
merging for direct `/execute` users, and puts a merge-and-rerun loop in the
driver (D8).

### Decision 4: The shape of `/deliver`

`/scope` and `/execute` are both koto-backed parents with their own state
files, sessions, and resume ladders, and `/execute` already finds a topic's
home or coordination PR through `gh`. The child-inspection reference lists a
child's state file as internals a caller must not read. CI requires every
skill to ship `requires.tsv` and `evals/evals.json`; the plugin manifest
discovers skills by directory.

Key assumptions:

- `/scope` itself refuses an explicit `--intent` that differs from a recorded
  run's intent (Decision 5 provides it).
- `/execute` prints each unmerged PR with who it waits on, so `/deliver` only
  relays.

#### Chosen: a stateless SKILL.md that sequences two inline Skill calls

`/deliver` has no koto template, state file, or phase files. It validates the
slug, checks visibility, resolves the mode once, and always enters through
`/scope --intent=continue`, whose own resume ladder decides where the topic
stopped (see Solution Architecture). After `/scope` reports `scoped`, it confirms
the PLAN exists and re-reads its mode rather than trusting the printed token.
Interactively it asks one Proceed/Stop question naming the mode. It then runs
`/execute` with `--merge` unless `--no-merge`, and relays `/execute`'s outcome
and PR lines. It fills the parent-of-the-parent slot the parent-skill pattern
names; it is not a fourth parent.

#### Alternatives Considered

**A koto-backed workflow.** Gates would enforce the sequence. Rejected: the
useful gates read `/scope`'s state file, which the isolation rule forbids, and
a third local session adds retention and cleanup rules for a two-step sequence
while storing nothing durable (D6, D8).

**A thin skill with its own state file.** Rejected: it would be a second,
local-only record of state the PLAN and PRs already hold, and the only fields
worth storing (the merge setting, the mode) are ones the PRD says not to
reuse (D6, D7).

**Resume by reading `/scope`'s `intent:` field or probing koto sessions.**
Rejected: both read another skill's internals or machine-local ephemera, and
each parent already probes its own session.

### Decision 5: Where `/scope` publishes under `--intent`

`/scope`'s koto template runs `finalize -> exit_* -> cleanup_* -> done_*`.
Cleanup deletes the state file, which R12 needs after a failure and which
holds the durable record Phase 3 says belongs in "the run's pull-request
body", a PR that doesn't exist today. `/execute` adopts a home PR by head
branch (`gh pr list --head <branch>`), not by title. A branch can also carry
tracked `wip/` from an upstream workflow such as `/explore`.

Key assumptions:

- koto accepts a transition condition that combines two gates with an
  evidence field; if not, exits always route through the publish state and a
  no-intent run passes straight through it with a `not-requested` value.
- An `INTENT` template variable can be passed at `koto init` like `TOPIC`.

#### Chosen: dedicated publish states backed by `publish-scoping-pr.sh`

Three states, `publish_full_run`, `publish_re_evaluation`, and
`publish_abandonment`, sit between each exit state and its cleanup. A new gate
on the exit states, `intent_declared` (`test "{{INTENT}}" != none`), sends
no-intent runs through today's states with no `gh` call (D2). Each publish
state's `published` gate runs the script's `--verify` mode, which checks that
the remote branch equals `HEAD` and exactly one PR exists on it, so a run
can't claim a PR it didn't open (D4). A failed publish records
`publish_error:` in the state file and parks the run in the publish state;
re-running `/scope <topic>` reattaches and retries idempotently (D6).

#### Alternatives Considered

**Publish inside the exit states.** Rejected: a failed push would either block
the exit from being recorded (breaking R12) or need error arms on every exit
state, and the exit states are re-entered from several places.

**Publish inside cleanup.** Rejected: cleanup deletes the state file R12 needs,
accepts only `done`, and deleting files from disk doesn't untrack committed
`wip/`.

**A script with no workflow state.** Rejected: nothing would check that the
publish happened, so an intent run could finish with no PR, and a failure would
leave the session at a terminal with no resume point. The script survives
inside the chosen option.

**One shared publish state for all exits.** Rejected: the agent would re-state
which exit it took, and no gate could check it.

## Decision Outcome

The five decisions fit together as one pipeline. At launch, `/scope --intent`
(or `/deliver`, which passes `--intent=continue`) records intent and forwards
it to `/plan`. `/plan` settles whether the work splits exactly as it does
today and then, only on a split, picks `coordinated` or `multi-pr` by the
precedence rule, now able to emit `coordinated` for one repository or many,
with one PR group per split unit. `/scope` then publishes: one PR on the
pushed branch, shaped by the mode, after the exit is recorded and before
cleanup, with its exit summary printing `intent=`, `outcome=`, `next=`, `pr=`,
and the startable issues for `multi-pr`. `/execute` adopts that PR
(single-pr) or coordination PR (coordinated), runs its existing children, and,
with `--merge`, merges through one verdict script and one fixed-flag merge
script: single-pr through four new koto states, coordinated node by node in
merge order with the coordination PR last. It ends in a named outcome that
`/deliver` relays. `/deliver` itself is a stateless sequencer that decides
where to start from committed files and never touches the children's
internals.

Cross-validation found no conflicting assumptions that needed a decision to be
re-run, and settled four seams:

- **Who opens coordinated node PRs.** Decision 3 assumed `/work-on` children
  open them; Decision 2 has `/execute` open one PR per node on a shared
  branch. Decision 2's shape stands, and Decision 3's scripts run on those PRs
  unchanged.
- **Intent mismatch.** Decision 4 needs `/scope` to refuse a conflicting
  intent. Decision 5 rejects an explicit `--intent` that differs from the
  recorded one on reattach, and `/deliver` maps that refusal to
  `deliver:intent-mismatch`.
- **Finished single-pr topics.** After a single-pr run the cascade deletes the
  PLAN. `/scope`'s resume ladder gains an `executed` row that reports the
  branch's owned PR, and `/deliver` relays it; after an architecture review,
  `/deliver` also stopped checking for the PLAN itself and always enters
  through `/scope`, so a publish that failed after the PLAN was written is
  retried before `/execute` runs.
- **Error line spelling.** Every skill prints `outcome=error` followed by
  `step=<step>`.

The PRD's Final States, R17, and R19 were clarified to match: the added
`execute:*` and `deliver:child-outcome` steps, the merge-method rule for
repositories that allow merge and rebase but not squash, the 30-minute CI wait
limit, the declined-confirmation outcome, and the executed-topic resume row.

## Solution Architecture

### Overview

Four existing skills change and one is added. The shared contracts
(coordination strategy, state schema, draft/ready discipline, parent-skill
pattern) change first because every skill reads them. The data that crosses
skill boundaries is small and explicit: the `--intent`, coordination, `--auto`,
and `--merge` flags going down, and the PLAN's `execution_mode`, the pushed PR,
and printed `key=value` exit lines coming back up.

```
/deliver <topic> [--auto|--interactive] [--no-merge] [scope flags]
   |  (no PLAN) Skill: /scope <topic> --intent=continue ...
   |        /scope Phase 0: parse --intent, INTENT var, mismatch refusal
   |        /plan hop: <design> --intent=continue [--coordinated|--no-coordinated] [--auto]
   |             step 3.6: split? (unchanged) -> step 5a: coordinated | multi-pr
   |        exit_* -> publish_* (intent only) -> cleanup_* -> done_*
   |        prints intent= outcome= next= pr= [startable issues]
   |  (PLAN present, not multi-pr) confirm if interactive
   |  Skill: /execute docs/plans/PLAN-<topic>.md [--merge]
   |        single-pr: ... ci_monitor -> merge_readiness -> merge_route
   |                   -> merge_attempt -> merge_confirm -> merged | ready_awaiting_merge
   |        coordinated: refresh -> dispatch nodes -> verdict/merge per node
   |                     -> coordination PR last | pause
   |        prints outcome= [step=] pr=<url> waiting=... reason=...
   `- relays outcome and PR lines
```

### Components

**Shared references.**

- `references/coordination-strategy.md`:
  - "one or more repositories"
  - the four-level mode precedence
  - the single definition of which `## PR Grouping Policy:` /
    `## Reviewability Ceiling:` values mean coordinated by default (pinned to
    what `/scope` Phase 0 resolves today)
  - a Branches paragraph (one branch per PR node, cut from the default
    branch)
  - the merge step and the `paused-awaiting-merges` pause in the lifecycle
  - template blockquote without "multi-repo" after the unchanged prefix
- `references/parent-skill-state-schema.md`: `plan_execution_mode` gains
  `coordinated`, plus a note that a parent may declare an always-present
  invocation-intent field.
- `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`: an
  "Opt-in agent merge" paragraph, and the coordination-PR exception amended so
  `/execute` marks it ready once every indexed PR has merged.
- `references/parent-skill-pattern.md`: a "Parent-of-the-Parent Binding"
  subsection.
- `references/parent-skill-child-inspection.md`: a row for a parent
  dispatched by the parent-of-the-parent, whose observable surface is its
  terminal artifact's frontmatter plus its printed exit lines.

**`/plan`.**

- `SKILL.md`: the three flags, with rejection of bad or repeated values
  before any `wip/` write; a "Split mode" rule; "Coordinated Mode" without
  "(multi-repo)".
- `phase-3-decomposition.md`: step 5a and the `split_mode_source` field. On a
  `coordinated` outcome, every issue gets `_Repo: <owner/repo> | Group:
  <unit-slug>_`.
- `phase-4-agent-generation.md`: coordinated gets full issue bodies.
- `phase-7-creation.md`: a coordinated branch reusing `create-issues-batch.sh`,
  with the explicit filing approval; single-pr and coordinated next-step
  advice names `/execute` (R23).
- `scripts/plan-to-tasks.sh`: `REPO`, `PR_GROUP`, and `ISSUES` node vars, and
  refusal text saying "atomicity across PR groups".
- Step 5a also runs on `/plan`'s interactive override path and on direct
  roadmap input, whose split branch is Incremental Value; both then resolve
  the mode by the same precedence.
- A `gh` shim under `skills/plan/evals/fixtures/bin/` that logs `issue create`
  calls (new).

**`/scope`.**

- Phase 0: `--intent` parsing and rejection before slug validation or any
  state; the `INTENT` koto var; an always-present `intent:` state field; on
  reattach, an explicit differing `--intent` is refused as
  `intent-mismatch recorded=<x> requested=<y>`, and a bare re-invocation
  inherits the recorded value.
- `/plan` hop forwarding in `phase-2-chain-orchestration.md` and the template:
  `--intent`, the coordination flags exactly as passed, and `/scope`'s own
  resolved mode flag (`--auto` or `--interactive`) when intent is set, so the
  hop runs in the same mode as its parent rather than being forced into
  auto.
- Coordination Intent: with `--intent` set, `/scope` never creates a
  coordination PR up front; the publish step opens it at exit once the PLAN's
  mode is known, so a header-coordinated run that doesn't split never carries
  a coordination PR, and abandonment has no pre-existing PR to close. Without
  intent, today's up-front behavior is untouched (D2).
- The `INTENT` template variable defaults to `none`.
- Resume under `--intent` when the run already exited with a PLAN: `/scope`'s
  resume ladder (the PLAN-Active and PLAN-Draft rows) re-runs the idempotent
  publish step and reprints the exit lines (`outcome=scoped` or
  `handed-off-multi-pr`, `next=`, `pr=`) instead of refusing. A topic whose
  PLAN was already executed and removed (DESIGN under
  `docs/designs/current/`) prints `outcome=executed` and `pr=` for the
  branch's owned PR.
- Three publish states, plus the `intent_declared` gate on the exit states.
- New scripts, each with a `_test.sh`:
  - `scripts/publish-scoping-pr.sh`
  - `scripts/startable-issues.sh`, which wraps `plan-to-tasks.sh`, keeps roots
    in PLAN order, and reads titles from the issue cells without calling `gh`
- The exit-summary block in `phase-4-cleanup.md`.
- The resume redirect for an Active PLAN routes by mode (R23), and the
  PLAN-status table reflects what `/plan` writes (R25). The phase-2 state-file
  enum re-validation accepts `coordinated` and rejects unknown values (R25's
  testable surface; `shirabe validate` doesn't read state files).
- A `gh` shim under `skills/scope/evals/fixtures/bin/` with a call log (new;
  `/scope` evals have none today).
- State-schema fields `intent:`, `published_pr:`, `publish_error:`.
- A Publish group in Security Considerations, restated in Phases 3 and 4.
- `requires.tsv` gains `gh - - mode:intent`.

**`/execute`.**

- `--merge` parsed and passed as `--var MERGE=true|false`.
- New scripts, each with a `_test.sh`:
  - `scripts/merge-verdict.sh` (read-only)
  - `scripts/merge-exec.sh` (the only `gh pr merge` line)
- Four koto states and two terminals, with the `ci_monitor` edge retargets,
  and the regenerated mermaid file.
- The coordinated loop rewritten as refresh, dispatch, evaluate, merge, and
  pause, with per-node branches and worktrees. Each node PR is titled
  `feat(<slug>): <node-id>` with a fixed body template (node id, issue
  numbers, coordination PR link); before `gh pr ready` its branch runs the
  same `wip/` sweep single-pr's finalization runs. The chain-finalization
  cascade runs once, on the coordination branch, after every node PR has
  merged and before the coordination PR is marked ready.
- The ownership filter applied at every existing PR lookup: the four
  `gh pr list --head ... .[0]` sites in `execute.md` and the resume ladder's
  title search, which becomes a head-branch lookup.
- `ci_monitor`'s `failing_unresolvable` edge maps to `outcome=error
  step=execute:ci`.
- An exit summary that always prints `outcome=`.
- The write-set additions.
- R24 wording, enforced by a new `scripts/check-merged-wording.sh` with an
  allowlist.

**`/work-on`.** R24 wording only.

**Validator and CI.**

- Single-repo tests in `crates/shirabe-validate/src/coordination.rs`,
  `merge_gate.rs`, and `crates/shirabe/tests/coordination_body.rs`.
- `.github/workflows/lifecycle.yml` drops a self-referencing PR-index entry.

**`/deliver` (new).**

- `skills/deliver/SKILL.md`, under about 250 lines, with no phase files.
- `requires.tsv` with only the schema line: `/deliver` calls no tool itself.
- `evals/` with a `gh` shim and fixtures.
- A row in `README.md`.

### Key Interfaces

**Flags.**

| Skill | Flag | Notes |
|-------|------|-------|
| `/scope` | `--intent=continue\|stop` | Rejected at Phase 0 if invalid or repeated. On reattach, a differing explicit value is refused. |
| `/plan` | `--intent=continue\|stop`, `--coordinated`, `--no-coordinated` | Child-owned, usable directly. `/scope` forwards only what the caller passed. |
| `/execute` | `--merge` | Becomes the koto var `MERGE`. Never remembered across runs. |
| `/deliver` | `--auto`/`--interactive`, `--no-merge`, forwarded `--upstream`, `--max-rounds`, `--coordinated`, `--no-coordinated` | Mode is resolved once and passed to both children. |

**Exit lines.** One `key=value` per line, parsed by `/deliver` and asserted by
evals:

```
/scope finished: exit=<exit>; artifact=<path>
intent=<continue|stop|none>
outcome=<scoped|handed-off-multi-pr|error>   # full-run or publish failure
step=<scope:push|scope:pr-create>            # error only
next=<command>                               # full-run only
pr=<url>                                     # intent runs only
#<N> <title>                                 # multi-pr startable issues, then one closing line
```

`/execute` prints `outcome=<token>`, `step=<step>` on error, and for each
unmerged PR `pr=<url> waiting=human|predecessor reason=<condition>`. For a
pause it adds the resume command.

**Merge decision table** (`merge-verdict.sh`, first match wins; the caller has
already run `gh pr ready`):

| # | Live snapshot | Verdict | Outcome |
|---|---------------|---------|---------|
| 1 | `state == MERGED` | `merged` | `merged` |
| 2 | `state == CLOSED` | `error:execute:pr-closed` | `error` |
| 3 | `isDraft` | `error:execute:ready` | `error` |
| 4 | `mergeStateStatus == DIRTY` | `awaiting:merge-state:DIRTY` | `ready-awaiting-merge` |
| 5 | any check failed or cancelled | `error:execute:ci` | `error` |
| 6 | any check pending, a required check (from the base's rules) not yet reported, or no checks yet within a 120 s grace window | `pending:checks` | wait; past the per-head-commit deadline (1800 s, `EXECUTE_CI_WAIT_LIMIT_SECS`, bounded integer), `error:execute:ci-timeout` |
| 7 | merge not requested for this invocation | `awaiting:merge-not-requested` | `ready-awaiting-merge` (no protection or method reads happen on this path) |
| 8 | `headRefOid` differs from the commit this run recorded as pushed, or no pushed commit is recorded | `awaiting:head-moved` | `ready-awaiting-merge` |
| 9 | no checks reported after the grace window | `awaiting:no-checks` | `ready-awaiting-merge` |
| 10 | `mergeStateStatus == UNKNOWN` | `pending:merge-state` | wait; past the deadline, `ready-awaiting-merge` |
| 11 | `BLOCKED`, `BEHIND`, `UNSTABLE`, `HAS_HOOKS`, or `reviewDecision` is `REVIEW_REQUIRED` or `CHANGES_REQUESTED` | `awaiting:merge-state:<S>[:review=<decision>]` | `ready-awaiting-merge` |
| 12 | the base's effective requirements, read from the branch's `protected` flag (`repos/<repo>/branches/<base>`) and its active rules (`repos/<repo>/rules/branches/<base>`), both visible to read access, include neither a non-empty set of required status checks nor a required approving review; an unreadable read counts as unprotected | `awaiting:base-unprotected` | `ready-awaiting-merge` |
| 13 | the rules require a review and `reviewDecision` isn't `APPROVED` | `awaiting:review` | `ready-awaiting-merge` |
| 14 | the PR changes `.github/workflows/`, `.github/actions/`, or a CODEOWNERS file and `reviewDecision` isn't `APPROVED` | `awaiting:workflow-change` | `ready-awaiting-merge` |
| 15 | requested, no allowed method readable | `awaiting:merge-method-unresolved` | `ready-awaiting-merge` |
| 16 | `CLEAN`, requested | `mergeable:<method>:<headRefOid>` | run `merge-exec.sh` |
| 17 | after 16, confirm read `MERGED` | `merged` | `merged` |
| 18 | after 16, merge call failed, or the fresh verdict `merge-exec.sh` computes differs | `not-merged:merge-call-failed` | `ready-awaiting-merge` |
| 19 | after 16, not `MERGED` within 20 s | `not-merged:merge-not-observed` | `ready-awaiting-merge`; the report says the PR may still be queued |

Rows 12 to 14 check the requirements themselves rather than trusting
`mergeStateStatus`, so a token that could bypass protection (an administrator
where admins aren't enforced, or a ruleset bypass actor) still can't merge
anything the rules wouldn't let an ordinary contributor merge.

A persistent `gh` read failure is `error:execute:status-read`. Method: the
single allowed one; squash when several are allowed including squash;
otherwise `--merge`. The merge call is fixed text:
`gh pr merge <pr> --repo <repo> --<method> --match-head-commit <sha>`.
`merge-exec.sh` takes only the repository and PR number and never trusts a
stored verdict, which the agent's shell could write: it runs `merge-verdict.sh`
itself immediately before the merge call and refuses unless that fresh verdict
is `mergeable:<method>:<sha>` and matches the one that routed the run there; it validates the PR number (`^[1-9][0-9]*$`),
method, sha, and repository against closed patterns.

**Merge intent per invocation.** Merging needs two things: the session's
`MERGE` template variable (set at `koto init` from `--merge`) and a
`merge_requested` context value `/execute` writes at the start of every
invocation from that invocation's own flags, defaulting to false. A session
started without `--merge` can't merge: the template variable isn't agent
evidence. The per-invocation value is written by `/execute`'s own flag parse
and can only narrow that, so a session resumed without `--merge` doesn't
merge (R17).

**Expected-head record.** Row 8 compares the PR head with the commit
`/execute` expects, recorded durably:

- Single-pr: the head `/execute` last pushed to the home PR, in the koto
  session's context (the session is retained across a resume).
- Coordinated node PRs: the head `/execute` pushed, written as a `head=<sha>`
  field on the node's line in the coordination PR's index, so a resume in any
  working copy reads it back.
- The coordination PR: the head `/execute` pushes when it runs the
  finalization cascade on the coordination branch, recorded the same way.
- A PR `/execute` adopted but never pushed to has no record, so row 8 fires
  and the run ends `ready-awaiting-merge` naming `head-moved`; `/execute`
  pushes the finalization commit before evaluating, so this only happens when
  something outside the run moved the branch.

**PR ownership.** Every lookup by head branch (the home PR, node PRs, the
publish `--verify` check, `/scope`'s executed-topic read) and every PR number
read from the coordination PR's index keeps only PRs
whose head is in the same repository (`isCrossRepository` false), whose author
is the authenticated user, whose base is the expected branch, and, for index
entries, whose head branch is the one the node's id determines. Zero or
several matches after that filter is an error (`execute:pr-adopt`,
`scope:pr-create`, or `deliver:child-outcome`), never a pick. `/execute` fixes
the set of repositories it may write to when it starts and rejects PR-index or
`_Repo:` entries outside it.

**Outcome versus exit.**

| Stop point | `exit:` | `outcome=` |
|------------|---------|------------|
| `merged` terminal | `full-run` | `merged` |
| `ready_awaiting_merge` terminal (or legacy `done`) | `full-run` | `ready-awaiting-merge` |
| `paused_for_review` | unset (suspension) | `paused-for-review` |
| `done_blocked` via DIRTY | `abandonment-forced` | `ready-awaiting-merge` |
| `done_blocked` via a verdict error or any other blocker | `abandonment-forced` | `error` with the step |
| `re-evaluation` | `re-evaluation` | `error`, `execute:re-evaluation` |
| coordinated, coordination PR merged | `full-run` | `merged` |
| coordinated, nothing left to start, something unmerged | `full-run` | `ready-awaiting-merge` |
| coordinated, a node waits on an unmerged predecessor | unset (`paused_awaiting_merges: true`) | `paused-awaiting-merges` |

### Data Flow

1. **`/scope` Phase 0.** It parses `--intent`, writes `intent:` to
   its state file, and passes `INTENT` to `koto init`.
2. **The `/plan` hop.** It receives the forwarded flags. `/plan` records
   `split_branch`, `split_rationale`, `execution_mode`, and
   `split_mode_source` in the PLAN. For a coordinated PLAN it also files the
   issues with Repo and Group rows.
3. **Exit and publish.** `/scope` records the exit, then, on intent runs:
   - untracks its own topic `wip/`;
   - pushes;
   - reuses or creates one PR;
   - verifies it through the `published` gate;
   - cleans up and prints the exit lines.
4. **`/deliver` hand-off.** `/deliver` re-reads the PLAN's `execution_mode`.
5. **`/execute`.** It adopts the PR by head branch through the ownership
   filter. Each merge decision reads live GitHub state through
   `merge-verdict.sh`; `merge-exec.sh` recomputes it before merging. The CI
   deadline bookkeeping lives in koto context (single-pr) or `/execute`'s state
   file (coordinated); losing it only restarts the wait.
6. **Coordinated resume.** Resume state lives on the coordination PR (its PR
   index and merge-order block) and in the node branches' PRs.

### `/deliver` sequence

`/deliver` always enters through `/scope`, which owns every "where did this
topic stop" question through its own resume ladder:

1. Check CLAUDE.md's `## Repo Visibility:` and refuse a private repository the
   way `/scope` does (R29), before anything runs.
2. Run `/scope <topic> --intent=continue` with the forwarded flags and the
   resolved mode flag. Map its exit lines:
   - `intent-mismatch` refusal: `outcome=error step=deliver:intent-mismatch`.
   - `outcome=error`: relayed with its step.
   - a `re-evaluation` or `abandonment-forced` exit record:
     `outcome=scope-ended-early` naming which.
   - `outcome=handed-off-multi-pr`: relayed with its list (R16).
   - `outcome=executed`: relayed as `merged` or `ready-awaiting-merge` from the
     printed PR's state (the finished single-pr case).
   - `outcome=scoped`: re-read the PLAN at `docs/plans/PLAN-<topic>.md`; a
     missing PLAN is `deliver:child-outcome`, a `multi-pr` mode is handed off,
     anything else continues.
   - anything else: `outcome=error step=deliver:child-outcome`.
3. Interactively, ask one Proceed/Stop question naming the mode; Stop ends
   `outcome=scoped` with `next=/deliver <topic>`.
4. Run `/execute docs/plans/PLAN-<topic>.md` with the mode flag and `--merge`
   unless `--no-merge`, and relay its `outcome=`, `step=`, and `pr=` lines,
   plus the repositories in the run's write set and `/scope`'s `wip_paths=`
   line.

Because a topic with a PLAN still passes through `/scope`, a run whose
publish failed after the PLAN was written gets its PR opened on the retry
before `/execute` starts (R17), and `/deliver` itself makes no `gh` call.

## Implementation Approach

The phases are ordered provider-first: each one adds a capability its
successors consume, and none leaves `main` with a half-wired flag if it lands
alone. That makes both delivery shapes legal, and the choice between one PR
and several belongs to `/plan`'s split step under the repository's Delivery
Preference, not to this design. Under this repository's default
(consolidated), one PR is the expected outcome; the phase boundaries are the
seams if a split is chosen.

### Phase 1: Shared contracts

The references every skill reads.

- `coordination-strategy.md`: repository count, precedence, header definition,
  Branches, merge and pause.
- `parent-skill-state-schema.md`: the `coordinated` enum value and the intent
  field note.
- The draft/ready design amendment.
- `parent-skill-pattern.md` and `parent-skill-child-inspection.md` additions.

Deliverables: the edited reference files.

### Phase 2: `/plan` emits both multi-PR modes

Depends on Phase 1's precedence and header definition.

- The flags and their rejection rules.
- Step 5a and group rows.
- The coordinated creation branch with filing approval.
- The `plan-to-tasks.sh` node vars and a single-repo test.
- Next-step advice routing (R23).
- The "(multi-repo)" eval assertion updated.

Deliverables:

- `skills/plan/SKILL.md` and phases 3, 4, and 7
- `plan-to-tasks.sh` and its test
- the plan-to-tasks contract doc
- plan evals

### Phase 3a: `/execute` merge step (single-pr)

Depends on Phase 1's draft/ready amendment.

- `merge-verdict.sh` and `merge-exec.sh` with table-driven tests.
- The four koto states and terminals, the `ci_monitor` retargets, the
  `failing_unresolvable` mapping, and the regenerated mermaid.
- The expected-head record and the ownership filter at every existing lookup.
- `outcome=` printing and the outcome-to-exit table.
- The write-set additions.
- R24 wording, `check-merged-wording.sh`, and `/work-on` wording.

Deliverables:

- `skills/execute/*` (single-pr path), scripts, and template
- `skills/work-on/SKILL.md`
- `scripts/check-merged-wording.sh`
- the execute `gh` shim with a call log and per-scenario fixtures
- execute evals for the Merging criteria

### Phase 3b: `/execute` coordinated path in one repository

Depends on Phase 2's node vars and Phase 3a's scripts.

- Per-node branches, worktrees, PR titles and bodies, and the `wip/` sweep.
- The coordinated merge, pause, and resume loop, with `head=` index fields.
- The cascade on the coordination branch before it is marked ready.
- The Rust single-repo tests and the `lifecycle.yml` self-reference filter.

Deliverables:

- `skills/execute/SKILL.md` coordinated section
- validator tests and `lifecycle.yml`
- coordinated execute evals

### Phase 4: `/scope` intent and publish

Depends on Phase 2 (forwarding targets real flags) and Phase 1 (schema).

- Phase 0 parsing, mismatch refusal, and the `INTENT` var.
- Hop forwarding.
- Coordination-intent precedence.
- Publish states and `publish-scoping-pr.sh`.
- `startable-issues.sh`.
- The exit summary.
- The resume redirect and status table (R23, R25).
- State-schema fields.
- Security Considerations and its restatements.
- `requires.tsv`.

Deliverables:

- `skills/scope/*`, templates, and scripts
- scope evals, including the "no `gh` call on a no-intent run" assertion

### Phase 5: `/deliver`

Depends on Phases 3a, 3b, and 4, whose exit lines it parses.

Deliverables:

- `skills/deliver/SKILL.md`, `requires.tsv`, `evals/`, and fixtures
- `README.md` row
- `docs/guides/coordinated-multi-repo.md`: a single-repo section, the intent
  route into coordinated mode, and `/execute` (not `/work-on`) as its driver
- `docs/guides/execute-friction.md`: a section on `/deliver`, `/scope
  --intent`, and `/execute --merge`, replacing the advice that assumes
  `/scope` leaves an open PR

### Eval coverage

Each phase ships its own eval scenarios, naming the requirement IDs they
cover, so the "every R1-R25 covered, 3 of 3 runs" criterion (R26) can be
checked phase by phase:

- GitHub state comes from the per-skill `gh` shims.
- Forced-split fixtures carry a hard constraint in the DESIGN; no-split
  fixtures are designs too small to split.

## Security Considerations

This design gives an agent new powers on the operator's GitHub credentials.
On intent runs, `/scope` pushes and opens a PR. `/execute` opens one PR per
coordinated node and readies it. `/execute --merge`, on by default under
`/deliver`, merges to the default branch. Until now the human merge was the
last review gate. The rules below keep the agent's merge from becoming a way
around review. They also keep it off PRs it doesn't own, and keep material
off remotes it shouldn't reach.

**The repository gates the merge, and the repository must have a gate.**
`merge-verdict.sh` returns a mergeable verdict only when all of these hold:

- the PR is open and not draft;
- its merge state is `CLEAN`;
- every reported check succeeded, and at least one check reported;
- the review decision is neither `REVIEW_REQUIRED` nor `CHANGES_REQUESTED`;
- its head commit equals the commit the run itself pushed.

If the base branch requires neither status checks nor reviews, the verdict is
`awaiting:base-unprotected`. A clean merge state on an unprotected branch
proves nothing, so v1 has no override. The agent never approves a PR:
`gh pr review` is outside every write set. GitHub doesn't let the operator
approve their own PR, so where review is required a human still decides.
A repository whose default branch is a distribution channel (plugins, skills,
recipes) should require an approving review before `--merge` is used there.

**One merge call site, fixed text, checked against its own verdict.**
`merge-exec.sh` is the only place `gh pr merge` appears, and a shell test
enforces that by grep. The call is
`gh pr merge <pr> --repo <repo> --<method> --match-head-commit <sha>` with no
`--admin`, no `--auto`, and no pass-through flags. The script reads the
verdict recorded for that same PR rather than trusting its arguments, and
validates every value against a closed pattern. `--match-head-commit` closes
the window between verdict and merge. `merged` is reported only after a live
read says `MERGED`. A merge queue that accepts a PR without merging it is
reported as `merge-not-observed`, and the report says the PR may still merge
later.

**Merge intent is per invocation, and only owned PRs are touched.** Both
mechanisms are specified under Key Interfaces. A resumed session never
inherits an earlier run's merge setting, because merge intent never comes from
agent evidence. A fork PR named after a predictable `impl/<slug>-<node-id>`
branch can't be adopted, edited, readied, closed, or merged, because every
head-branch lookup filters on same repository, the authenticated author, and
the expected base, and treats zero or several matches as an error.

**Pushes never touch the default branch and never force.** The publish script
and every node push refuse a detached HEAD or the remote's default branch.
They push with an explicit `HEAD:refs/heads/<branch>` refspec and never pass
a force option. Branch names are built only from the validated topic slug and
node id.

**Published content is bounded.** PR bodies come from a fixed template over
validated fields and are passed with `--body-file`. The fields are the slug,
exit, outcome, mode, `docs/` artifact paths, and issue numbers. Free-text
state fields are left out. The coordination PR's rule against embedding
private-repository content applies to every PR these skills open. Pushing a
branch publishes its whole history. In this workspace, `wip/` artifacts are
committed to feature branches by design, and they fall under the same
public-content rules as the documents they feed. So the publish script lists
any `wip/` paths in unpushed history on a `wip_paths=` exit line rather than
blocking. The check that matters in this workspace, private-repository
content in research notes, runs as the public-content visibility check over
those files, and a hit stops the push with `scope:push`.

**Inputs from GitHub and from files are data.** Parents parse `gh` JSON for
enumerated fields only, and never read child PR bodies, CI logs, or comments.
Issue titles printed as startable issues are opaque data. `/deliver` parses
exit lines only by anchored keys. It validates what it forwards: `--upstream`
must be a repository-relative `docs/` path, and `--max-rounds` a bounded
integer. Each is passed as a separate Skill argument. `EXECUTE_CI_WAIT_LIMIT_SECS`
must be a bounded integer, or the default applies. The existing slug and enum
re-validation rules apply unchanged.

**Unattended runs are bounded.** `/deliver --auto` asks nothing and merges by
default. With the gates above, an unattended run can merge only where the
repository's own rules would let an ordinary contributor merge. Its final
report (R18) names every PR it merged or left waiting and every repository in
the run's write set, and relays `/scope`'s list of `wip/` paths published with
the branch.

**PRs that change their own gate.** On a base that requires checks but no
review, a PR could edit the workflows that produce those checks. The verdict
refuses to merge a PR touching `.github/workflows/`, `.github/actions/`, or a
CODEOWNERS file unless a review approved it.

**Residual risk.** These are skill-level controls around an agent that has a
shell and the operator's token. A token that can bypass protection (an
administrator where admins aren't enforced, or a ruleset bypass actor) could
merge through the API directly. The skills never do: the verdict checks the
rules' requirements itself instead of trusting GitHub's merge state, and the
merge call carries no bypass option. Repository-side controls (enforced
protection for admins, required reviews, and push protection for secrets) are
what an agent can't get past, and the skills refuse to merge where the first
two are absent.

## Consequences

### Positive

- One launch command can take a feature from scoping to merged code wherever
  the session may merge, and ends in a named, resumable state everywhere else.
- `coordinated` becomes reachable at all (today nothing emits it), including
  from `/scope --coordinated`, and works in one repository.
- Merging is impossible to over-claim: the `merged` outcome requires a live
  GitHub read, the merge call is fixed text with no bypass flags, and a run
  started without `--merge` can't merge.
- CI waiting gets a real, testable limit, and `ci_monitor`'s ungated
  `failing_fixed -> done` shortcut is closed.
- The next-step advice and "merged" wording become accurate, and Phase 3's
  promised PR body becomes real on intent runs.
- The parent-of-the-parent slot gets a concrete binding that later drivers can
  reuse.

### Negative

- `/execute`'s template grows by four states and two terminals, and its
  coordinated section grows by per-node worktree and PR choreography.
- `/scope` gains three publish states, a new gate on four states, and its first
  push and non-hop commit.
- `/plan` gains three flags and a third creation branch with an approval step
  multi-pr doesn't have.
- `outcome=` and `exit:` aren't one-to-one (a DIRTY PR is
  `abandonment-forced` with `outcome=ready-awaiting-merge`).
- A single-pr run that ends `ready-awaiting-merge` can't be re-merged by
  `/execute` later, because the cascade has already deleted the PLAN.
- Merge-queue repositories report `ready-awaiting-merge merge-not-observed`
  rather than `merged`.
- Tracked `wip/` left on a branch by an upstream workflow still reaches a
  ready `multi-pr` PR and fails its CI.
- The exit lines become an interface between skills.

### Mitigations

- The new states and scripts are covered by table-driven shell tests and
  mermaid regeneration. No existing gate changes and the pinned DIRTY route is
  untouched; the two retargeted `ci_monitor` edges only add a verdict step
  before a terminal, so existing evals hold apart from R24 wording.
- The no-intent path's guarantee rests on one pure `test` gate, and an eval
  asserts the shim logs no `gh` call at all on a no-intent run.
- The coordinated approval step is documented as existing only to satisfy
  interactive filing approval without changing no-intent multi-pr runs.
- The outcome-to-exit mapping lives in one table in `/execute`'s SKILL.md.
- `/scope`'s executed-topic row lets `/deliver` report a single-pr PR's state; a
  future PR-number input mode for `/execute` is the path to re-merging it.
- `merge-not-observed` is a safe under-claim, named in the report so the
  author knows to check the queue.
- `publish-scoping-pr.sh` names any foreign tracked `wip/` path in its report,
  so the author sees why the PR's CI will fail.
- Evals pin every exit line `/deliver` parses.

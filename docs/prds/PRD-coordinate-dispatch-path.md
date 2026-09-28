---
schema: prd/v1
status: Done
problem: |
  The coordinate skill sends work out and takes it back through prose. A
  coordinator composes each worker's brief by hand, runs the dispatch by hand,
  and is told, with nothing enforcing it, to record the dispatch before
  anything else. A launched worker with no pull request and no holding row is
  invisible to GitHub, to reconcile and to any successor, and a worker's report
  is classified by eye with no record of the call.
goals: |
  The dispatch step produces a complete brief, launches the worker and gets
  its holding onto the record, and the workflow can't leave that step until
  the record shows it. The wait step advances on a worker's result whether it
  arrives through a bound request leg or as a message, and a suggested
  classification of each report is recorded beside the coordinator's own call.
upstream: docs/briefs/BRIEF-coordinate-dispatch-path.md
---

# PRD: coordinate-dispatch-path

## Status

Done

## Problem Statement

A coordinator running the `coordinate` skill hands each unit of work to a
worker session and takes the result back. Both directions are carried today
by prose the coordinator has to remember to follow, and the two places where a
slip costs the most have nothing behind them.

Going out, the coordinator fills in `references/brief-template.md` by hand.
The brief is the worker's only context, and a section left out (a report
channel, the decisions the worker can't see, the checkpoints) is something a
worker starting cold has no way to notice. It then types the workspace
manager's dispatch command and is told to record the dispatch as a holding
"before any other action". Nothing checks that it did. A worker that has been
launched but hasn't opened a pull request exists nowhere GitHub can show, so a
forgotten holding, or a coordinator session that ends between the dispatch and
the record write, leaves a worker that reconcile can't find, that a successor
doesn't know about, and that the pick step doesn't count against the session
cap.

Coming back, a worker's result arrives as a message plus what it pushed. The
coordinator reads the message and decides whether the unit is done, blocked,
or needs a fix, and nothing records that call. Workers whose entry point can
bind a leg of a koto request carry their result as data on the leg, but the
coordinator's loop has no step that reads one.

The coordinator's loop is becoming a koto workflow template in which the
dispatch and wait states call this prose until this feature replaces it.

## Goals

- A worker's brief is complete by construction: rendered from the record and
  the invocation, never composed freehand, and refused when a required part is
  missing.
- A dispatched worker is on the coordinator's record before the dispatch step
  ends, and the workflow can't be moved past the dispatch step while it isn't.
- A worker's result moves the workflow forward through whichever return path
  the worker could use, and the choice of path is made once, at dispatch, and
  recorded.
- The coordinator's classification of each report is its own, and a shadow
  suggestion is recorded next to it so a later feature has evidence to decide
  whether the suggestion can be trusted.
- When a worker's instance is destroyed, nothing that existed only there goes
  with it, and nothing but that instance is destroyed.

## User Stories

- As a roadmap coordinator dispatching a feature, I want the brief rendered
  from my record and the human's decisions, so that the worker gets both
  report channels and every section without my composing them each time.
- As a coordinator whose session died right after launching a worker, I want
  the holding already on my record when I restart, so that reconcile finds the
  worker by its topic instead of it surfacing later as an unexplained pull
  request.
- As a coordinator waiting on a worker that bound a leg, I want the wait step
  to read the leg's result, so that I move to verification on data the worker's
  own session recorded rather than on text I parsed out of a message.
- As a coordinator waiting on a worker that can't bind a leg, I want to hand
  the workflow the worker's message and have it advance the same way, so that
  the two kinds of worker don't need two loops.
- As the human above a coordinator, I want each report's classification
  recorded with the suggestion beside it, so that I can see what the
  coordinator decided and, later, whether a suggestion could have decided it.
- As a skill maintainer, I want the workspace manager declared as a required
  tool, so that a coordinator started without it is told at load time rather
  than at its first dispatch.

## Requirements

### Functional

**R1. The brief is rendered, not composed.** A script renders a worker's brief
from structured input the dispatch step assembles from the record and the
invocation. The rendered brief carries every section of
`references/brief-template.md`: the goal and the entry point to run, the run
mode (the entry point's execution flags, `--auto` unless the human's
decisions say otherwise), the checkpoints, the decisions already made, pointers to pushed
artifacts, the acceptance criteria, what's out of scope, and the reporting
section.

**R2. The reporting section names both channels.** Status and blockers go to
the dispatching coordinator, named by its session name, which is the worker's
only source of direction. Papercuts go to the discipline coordinator named
for each surface, one line per surface, with a copy to the dispatcher, and the
worker takes no direction from that channel. When no discipline coordinator is
named for a surface, the brief says to put the problem in the report to the
dispatcher.

**R3. The brief carries the standing lines.** Every brief points the worker
at the target repository's conventions (its CLAUDE.md) for commits, pull
request bodies and what may appear on GitHub; says that the workspace manager
already schedules the worker's keep-alive; tells the worker to report closes
with number, reason and evidence and to propose issues rather than file them;
and asks for the `=== WORK IN FLIGHT ===` block at the end of the final report.
It also carries the workspace's own standing rules for workers, which the
coordinator supplies as input and the renderer copies unchanged: for example,
on a host whose isolation guard blocks edits outside a worktree, entering the
worktree before the first `koto init` of any run. The skill supplies the slot,
not the rules, since they belong to one workspace's posture and not to every
coordinator.

**R4. The renderer refuses an incomplete brief.** It exits non-zero and writes
nothing when a required input is empty: the goal, the entry point, at least
one checkpoint, at least one acceptance criterion, the dispatcher's session
name, or the dispatch topic. It also refuses a checkpoint that contains
"approval", "approve" or "wait for" (case-insensitive), since a worker never
waits on an approval gate. Each pointer must be a repository path, an issue or
pull request number, or a URL, and the renderer refuses any other pointer
value; it adds no text of its own beyond the template and the fields it was
given.

**R5. The brief lands where the workspace manager reads briefs.** The rendered
brief is written to the workspace manager's brief directory, named by the
dispatch topic. The dispatch prompt carries the worker's authority in the
human's voice (the person the coordinator works for, or the dispatching
coordinator when another coordinator dispatched it), names the target
repository and the checkpoint the worker stops at, and points at the brief
file.

**R6. Workers are named by dispatch topic.** The dispatch topic names the
worker in the dispatch command, the brief, the holding and every later step.
No session id, instance path or job id is written to the record or the brief.

**R7. Dispatch and holding are one step.** The dispatch step launches the
worker through the workspace manager under the dispatch topic, detached from
the coordinator's terminal (with niwa, `niwa dispatch` with `--name <topic>`
and `--detach`, run from the workspace root), and the holding reaches the
record within the same step, before the step reports success. The holding
records the worker's topic, the repository, the entry point, the run mode,
its phase (scoping ahead, for a worker producing documents ahead of the go to
execute, or executing), the date, the return path (the request leg it was
bound to, or the message path), and "none yet" for its pull request.

**R8. No window with an unrecorded worker.** At no point after the worker
exists is its holding absent from the record. A dispatch that fails after the
record was written leaves a holding reconcile can see and clear, never a
worker the record doesn't show. The record write therefore comes before the
launch.

**R9. Re-running the dispatch launches nothing twice.** Running the dispatch
step again for a topic whose worker was already launched doesn't launch a
second worker, adds no second holding, and exits successfully saying the
worker was already dispatched.

**R10. The dispatch state can't be left without the holding.** A gate on the
dispatch state checks that the record holds a holding for the dispatched
topic. It reads the record itself, not a value the coordinator submits, and it
can't be overridden.

**R11. The return path is chosen at dispatch.** When the unit's entry point
accepts `--koto-leg`, the dispatch step opens a leg for the worker and passes
it in the dispatch prompt's invocation; otherwise the worker uses the message
path. Which one applies is recorded on the holding.

**R12. The leg path advances on the leg.** For a holding bound to a leg, the
wait state advances when the leg resolves, through a `request-leg` gate that
can't be overridden. Only a result the worker's session promoted can move the
unit toward verification; an explicit or refused result is surfaced to the
coordinator as the worker not having recorded a result.

**R13. The message path advances on the report.** For a holding on the message
path, the coordinator writes the worker's report into the workflow's context
under a key the wait state reads, and the wait state advances on it. A context
gate checks the key exists before the state moves on.

**R14. The wait never depends on an open-ended watcher.** The coordinator's
session ticks the workflow on each message or harness notification. A
background wait the workflow starts has a deadline. Nothing the workflow needs
for correctness runs without an end.

**R15. Report classification is the coordinator's, with a shadow
suggestion.** The wait state asks for the report's classification: done,
blocked, or needs a fix. The field carries a koto decider declaration in
shadow mode whose inputs are context keys and template variables only, each
checked by a context gate in the template. Every answer is declared `shadow`,
or `never` for an answer the template doesn't intend ever to promote; none is
`auto`. The coordinator's submitted answer always routes.

**R16. The workspace manager is a declared tool.** `skills/coordinate/requires.tsv`
declares `niwa`, and `scripts/lib/tool-routes.tsv` carries an install route
for it, so the load-time preflight reports a missing workspace manager.

**R17. Teardown takes an inventory first.** Before a coordinator destroys an
instance it dispatched, or asks the human to, a script inventories every git
repository in that instance, worktrees included: branches whose head is on no
remote, uncommitted and untracked changes, and stash entries. It never
destroys, stops or deletes anything itself.

**R18. Durability is proven by content, never by ancestry.** A branch whose
head is on no remote counts as durable only when the files it changed are
identical in the commit that landed it: the branch head's tree, diffed over the
paths the branch changed against the squash merge commit of the merged pull
request whose head was that branch, is empty. When no merged pull request
exists, the comparison falls back to the default branch's head, and the
verdict says which target it used. Comparing against the merge commit keeps a
later change to those paths on the default branch from reading as unique. A
squash merge leaves every finished branch looking unmerged by ancestry, so an
ancestry check reports finished work as unique and a coordinator learns to
ignore it.

**R19. A verdict per repository.** The inventory prints one verdict per
repository, `durable` or `unique` with what makes it unique, and exits zero
only when every repository is durable. It exits with a distinct code when it
can't read a repository, so an unreadable repository never reads as durable.

**R20. The teardown names one instance.** The teardown state can't move toward
destruction while the inventory for that instance reports unique material; the
gate runs the inventory itself rather than reading the coordinator's claim.
Anything load-bearing the inventory finds is promoted by the coordinator into
an issue comment or a pull request first. The destroy names exactly that one
instance (with niwa, `niwa destroy <instance>`), never a form that takes no
target or matches more than one (with niwa, never `niwa reap`), and the
worker's session is stopped by its own id, through the harness's stop form,
never a form that deletes the session's job directory.

**R21. Teardown stays inside the workspace's permissions.** The coordinator
that dispatched a worker is the one that tears it down; a worker never tears
itself down. Whether the coordinator destroys the instance itself or hands
the step to the human is the workspace's declared permissions' call. A denial
covers the step, not the command, and a step behind a person's confirmation
is handed over rather than triggered.

### Non-functional

**R22. No gate is satisfiable by a value the agent supplies.** Every gate this
feature adds reads state the agent can't write directly: the record on GitHub,
a request leg, or a context key the gate itself checks for.

**R23. Tests with stubs.** The renderer, the dispatch script and the teardown
inventory each have a
`_test.sh` sibling. The dispatch script's test runs against a stub `niwa` and
a stub record writer, so it launches nothing and writes to no real record.

**R24. Filed defects are named, not worked around.** The skill names shirabe
#395, #396, #398 and #401, koto#250, koto#251 and niwa#322 as known
limitations, each
with what it costs today, and carries no rule whose only reason is one of them.
#401 was fixed by #407 before this feature landed, so the skill no longer lists
it and the dispatch path binds legs for `/deliver` and `/work-on` too.

**R25. Public content only.** No committed artifact names a private
repository, path or issue, a session or instance name, a job id, or a path under the
workflow scratch directory the repository's cleanup rule removes.

## Acceptance Criteria

- [ ] A brief rendered from a complete input contains, under each section of
  the brief template, the input values given for it (not only the heading);
  both report channels, with the dispatcher named as the only source of
  direction and each surface's discipline coordinator on its own line; the
  conventions pointer; the keep-alive note; and each workspace standing rule
  verbatim.
- [ ] The renderer exits non-zero and writes no file when the goal, entry
  point, checkpoints, acceptance criteria, dispatcher session name or topic is
  missing, when a checkpoint contains "approval", "approve" or "wait for", and
  when a pointer is not a path, number or URL.
- [ ] The rendered brief is written to the workspace manager's brief
  directory as `<topic>.md`, and the dispatch prompt names the authority, the
  repository, the stop checkpoint and that file's path.
- [ ] Neither the rendered brief nor the holding contains a session id, an
  instance path or a job id; the worker appears only as its dispatch topic.
- [ ] Against a stub `niwa` and a stub record writer that log their calls to
  one file, the log shows the holding write before the `niwa dispatch` call,
  `niwa dispatch` carries `--name <topic>` and `--detach`, and the holding
  carries topic, repository, entry point, run mode, phase, date, return path
  and "none yet".
- [ ] For an entry point that accepts `--koto-leg`, the holding's return path
  names the leg and the dispatch prompt carries the flag; for one that
  doesn't, the return path is the message path and the prompt carries no
  flag.
- [ ] Against a stub `niwa` that fails, the record shows a holding for the
  topic that marks the failed dispatch, and the script exits non-zero.
- [ ] Running the dispatch script twice for one topic calls the stub `niwa
  dispatch` once, leaves exactly one holding for the topic, and exits zero on
  the second run.
- [ ] A session in the dispatch state whose record has no holding for the
  topic doesn't advance, even when the session's context holds a value
  claiming the holding exists, and `koto overrides record` can't unblock the
  gate.
- [ ] For a holding bound to a leg, a promoted result on the leg advances the
  wait state toward verification; an explicit or refused result, an abandoned
  leg and a missing leg each route to the worker-recorded-no-result path; an
  open leg holds the state.
- [ ] For a holding on the message path, the wait state doesn't advance while
  the report's context key is absent or empty, and advances once it holds the
  report's text.
- [ ] Every background wait the dispatch and wait states start takes a
  deadline, and the wait state's directive tells the coordinator to tick on
  each message or notification rather than poll.
- [ ] The classification field declares a decider with every answer in
  `shadow` or `never`, inputs that are context keys or variables only, and a
  context gate on each context input; the template compiles.
- [ ] Against a fixture instance, the teardown inventory reports `unique`
  for a repository with an uncommitted change, one with an untracked file, one
  with a stash entry, one in a worktree with an unpushed branch, and one whose
  unpushed branch changed a file that differs from the default branch; and
  reports `durable` for a repository whose unpushed branch was squash-merged,
  its changed files identical in the merge commit though its commits are not
  ancestors of it, including when the default branch later changed those
  files; each verdict names the target it compared against.
- [ ] The inventory exits non-zero when any repository is unique, with a
  distinct code when a repository can't be read or can't be classified, and a
  test shows it writes nothing to any fixture repository but remote-tracking
  refs.
- [ ] The teardown state doesn't advance toward destruction while the
  inventory reports unique material, `koto overrides record` can't unblock
  that gate, and the destroy command its directive names takes exactly one
  instance.
- [ ] `requires.tsv` declares `niwa`; `tool-routes.tsv` has a route for it;
  the skill preflight passes where niwa is installed and names the route where
  it isn't.
- [ ] The renderer, the dispatch script and the teardown inventory each have a
  `_test.sh` sibling, and the dispatch test launches nothing and writes to no
  real record.
- [ ] Evals exist for a brief rendered with both channels, a dispatch refused
  to leave the state without a holding, and a report classified in shadow;
  each asserts its specific outcome (both channels present; the gate blocked;
  the coordinator's answer routed with the shadow suggestion recorded), and
  each fails against the prose-only skill.
- [ ] The skill's Known Limitations names shirabe #395, #396, #398,
  koto#250, koto#251 and niwa#322, each with its cost today (#401 was fixed
  by #407 before this feature landed).
- [ ] No added file names a path under the workflow scratch directory, a
  private repository, path or issue.

## Out of Scope

- Deciding when a worker is finished (its pull request merged, its content
  verified on the default branch, its issues closed or handed on, and its
  final report in) and asking it what exists only in its head; this feature
  supplies the inventory and the targeted teardown the finish step uses.
- Reconcile: re-checking the record against GitHub and the host after a
  restart, including clearing a holding a failed dispatch left.
- The record's container, its sections and the writer that renders it; this
  feature calls the record's writer to add a holding.
- The loop's template and its other states. This feature fills the dispatch
  and wait states and adds gates to them; it doesn't restructure the template.
- Accepting `--koto-leg` in `/deliver` and `/work-on` (#401, since fixed by
  #407) and waking the
  coordinator when a leg resolves (koto#250).
- Request legs across hosts, which koto's request store doesn't carry by
  design.
- Moving the classification decider to `auto`.
- Liveness checks, the double-held check, and the cost of a coordinator's
  actions to other efforts.
- Any change to koto or niwa.

## Known Limitations

- **Which pull requests a worker owns (#395).** Entry-point skills decide
  ownership by login and branch name, and every worker a coordinator
  dispatches shares one login. Dispatch topics feed branch names, so two
  workers whose branches collide can adopt each other's pull request. The
  coordinator's own reads go by pull request number and topic.
- **Merge order on coordination pull requests (#396).** A worker running a
  coordinated PLAN leaves its merge-order block empty, so the coordinator
  can't read merge order from it after the PLAN is gone.
- **Scoping pull request bodies (#398).** A worker's scoping pull request body
  isn't the conformant two-part body, so a coordinator reading it for the
  report gets less structure than it should.
- **Legs for `/deliver` and `/work-on` (#401, fixed by #407).** Both accept
  `--koto-leg` now, and the dispatch path binds a leg for each; a `/work-on`
  worker given a PLAN path still reports by message, since `/work-on` answers
  its leg only for an issue or a task.
- **The destroy refuses squash-merged branches (niwa#322).** `niwa destroy`
  refuses an instance whose branches were squash-merged, because it judges by
  ancestry. The coordinator passes `--force` only after the inventory has
  proven every repository durable by content.
- **A directed transition skips gates (koto#251).** `koto next --to` moves a
  session past a failing gate, non-overridable ones included, so no gate here
  can on its own guarantee a state was reached through it. Teardown detects
  the skip before destroying anything; the other gates rely on reconcile.
- **One topic per worker.** koto session names such as `scope-<topic>` are
  shared across the host, so two workers dispatched on one topic collide: the
  second's session is refused as an origin mismatch. Each dispatch uses a
  topic no live holding uses.
- **No wake when a leg resolves (koto#250).** The coordinator's session isn't
  woken when a bound leg resolves; the leg is read on the next tick, which a
  message or notification triggers. A worker that resolves its leg and sends
  no message is noticed at the coordinator's next quiet-worker check.

## Decisions and Trade-offs

- **Where the holding is written.** The dispatch step writes it, rather than a
  later record step the dispatch state gates on. A separate step would reopen
  the window the feature exists to close. The DESIGN picks the mechanism
  (engine action or agent-run script) against koto's action rules; the
  requirement is only that the step can't end without it.
- **How the wait state tells the paths apart.** The brief left this to the
  DESIGN; the PRD settles the requirement half of it: the return path is
  decided at dispatch from what the entry point accepts and recorded on the
  holding, so the wait state reads it rather than inferring it from what
  arrives. The DESIGN picks how the state reads it. Inferring
  it would let a message for a leg-bound worker bypass the leg's promoted-only
  rule.
- **Classification stays a suggestion.** The decider runs in shadow because
  it has no evidence yet, and because a report is text a worker wrote, which is
  a weak input to promote on. The coordinator's call routes.
- **A failed dispatch leaves a visible row.** Recording before launching means
  a failed launch leaves a row to clear. The alternative, recording after,
  leaves a worker nobody can see when the session dies in between; a visible
  stale row is the cheaper failure.

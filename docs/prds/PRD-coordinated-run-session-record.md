---
schema: prd/v1
status: Draft
upstream: docs/briefs/BRIEF-coordinated-run-session-record.md
problem: |
  A coordinated `/execute` run keeps the facts it runs on as lines in the coordination
  pull request's body: which pull request each node opened, the head each merge is pinned
  to, whether the finalization cascade ran. The body is editable, nothing refreshes it
  after a merge, it has no room for a follow-up pull request, it lists the coordination
  pull request as its own row, and all of it lands on the default branch in the squash
  commit. A run whose execute session is lost or moved can't adopt its own merged nodes
  (shirabe#733, shirabe#901, shirabe#785, shirabe#748).
goals: |
  A coordinated run's koto session is its record, on either store. Every `/execute`
  reader takes the run's facts from the session, the coordination pull request's body is
  rendered from them at every transition, and a merge is never pinned to a head read off
  the body. A run imported into another workspace resumes as the same run through its
  merge-last gate, `/deliver`'s leg to it ends with a result or a stated loss, and the
  default branch gets each pull request's description and nothing else.
---

# PRD: The coordinated run's session is its record

## Status

Draft

## Problem Statement

A coordinated plan lands as several node pull requests and one coordination pull request
that merges last. `/execute` drives the run across pauses as long as a human review: it
opens each node's pull request, pushes it, waits for review, merges it, runs the
finalization cascade once every node is in, and lands the coordination pull request. It
remembers what it has done by writing to the coordination pull request's body. Each index
line there names a node's pull request and the head the run pushed; it's the only record of
the node-to-pull-request map, of the head every merge of that node is pinned to, and, once
the cascade has deleted the PLAN, of the node list itself. Whether the cascade ran is read
off the coordination pull request's own index line. The design that put the state there
(`DESIGN-scope-then-execute.md`, Decision 6) chose the pull request over a machine-local
session because a session couldn't leave its host; session import now moves one.

What the body-as-store costs today:

- A run whose execute session is lost or moved gets a new run id, finds its merged node
  pull requests marked with the old id, and stops at `error:execute:pr-adopt`
  (shirabe#733, shirabe#901). The only way through is to copy the old id into the new
  session by hand.
- A merge is pinned to a head read back from text anyone with write access can edit.
- Nothing rewrites an index line after its node merges, so a finished run shows every node
  `open` at its pre-merge head, and a follow-up pull request opened against a node after
  merge review has no way in (shirabe#785). The index carries a row for the coordination
  pull request itself, which the merge-last gate special-cases out (shirabe#748).
- `/execute` merges without a squash message, so the whole coordination body, index, heads
  and bookkeeping lines included, lands in the default branch's history.
- `/scope`'s `intent=` line in the same body is a copy of `/scope`'s result that `/deliver`
  reads back off the page before it starts `/execute`.

The body is still the right page for people and for CI. A reviewer reads the index and the
merge order there, and the reusable merge-last gate, which has no koto session to read,
finds the coordination pull request by its declaration marker and reads the node list from
the body. The trouble is that the same text is also the run's memory.

## Glossary

- **Run record**: the facts a coordinated run keeps about itself, as keys in its execute
  session (`execute-<topic>`).
- **Store**: where a run's record has a second, durable home a host without the session
  can recover from. `github` (the default) renders the record into the coordination pull
  request's body and may recover from that rendering; `session` keeps the record in the
  session alone.
- **Recovery**: a start on a host with no session of the topic, on the `github` store,
  that rebuilds the run record from the body's rendering and live GitHub reads.
- **Follow-up pull request**: a pull request opened against an existing node after its
  review, to address notes from that review, and recorded against the node.
- **Part 1**: everything above a pull request body's one top-level `---` line.

## Goals

- Whoever drives a coordinated effort can stop a run, import it into another workspace,
  and resume it there through its merge-last gate, adopting its merged nodes without
  anyone copying an id by hand.
- The reviewer reading the coordination pull request sees, at every point and through the
  cascade, each node's state and head, follow-ups under their node, and no self row.
- A merge is pinned only to a head the run recorded when it pushed, or re-read live and
  re-verified; never to the page.
- The default branch's history carries each merged pull request's title and Part 1 only.
- A coordinator running `/deliver` gets a result on its leg, or a report that the inner leg
  was lost and why, after a move.

## User Stories

- **As a coordinator handing a run to a replacement mid-flight**, I want the worker's run
  imported alongside my record to resume as the same run after its first node merged, so
  that it adopts that node, lands the rest and reaches the merge-last gate without a
  hand-set id, and I read its result from my leg or a plain report that the leg was lost.
- **As a maintainer restarting a run whose execute session was removed** with its
  workspace and no import made, I want the restarted run to come back as the run that
  opened its merged nodes from what the store kept, and, where nothing survived to prove
  that, to stop and name the one recorded step that adopts them.
- **As a reviewer deciding whether to land a coordination pull request**, I want its index
  to show every node merged at the head it merged at, the follow-up opened after merge
  review under its node, and the merge order, with CI's merge-last gate counting the
  follow-up, so that I can trust the page.
- **As a maintainer reading the default branch's history**, I want the coordination pull
  request's squash commit to carry its title and description only, so that the history
  says what the effort did and not how the run kept its books.

## Requirements

### The run record

- **R1. The record is session keys.** A coordinated run keeps these facts as keys in its
  execute session, on either store:
  - for each PR node: its repository, its pull request number and the head the run last
    pushed to it;
  - for each follow-up pull request: the node it belongs to, its repository and number;
  - the coordination pull request's number and, once the cascade has pushed, its head;
  - the cascade's verdict: not run, pushed (with the head), or failed (with the step);
  - the node list as the PLAN gave it, recorded at setup, so the run still has it after the
    cascade deletes the PLAN;
  - the run's identity (`run_id`, as today) and its store (R6).
  The keys join `/execute`'s closed write-target set in `skills/execute/SKILL.md`.
- **R2. One writer per fact.** A node's pull request and pushed head are written only by
  the step that pushes the node, after its push succeeds; the coordination pull request's
  head and the cascade verdict only by the cascade step; a follow-up only by the follow-up
  step (R14); the coordination pull request's number only at setup (R15). Any other write
  to these keys is refused. The loop has one writer at a time, so no multi-key write core
  is required, but each step's keys are written before the body is rendered from them.
- **R3. One way in.** Every `/execute` script that needs a node's pull request, a head, the
  node list or the cascade verdict reads it from the run record through one reader. No
  script under `skills/execute/` parses a head or a node-to-pull-request line off a pull
  request body; a structure test enforces this.
- **R4. A merge's pinned head.** Every merge `/execute` makes of a node, a follow-up or the
  coordination pull request passes `--match-head-commit` with the head the run record holds
  for it. On the recovery path (R8) the head is re-read live from the pull request on
  GitHub, never from the body, and the pull request is re-evaluated at that head (checks,
  review, mergeability) before any merge.
- **R5. Live facts stay live.** A pull request's state, checks, review and mergeability are
  read from GitHub when needed and never stored in the run record. The index's state column
  is filled from those live reads at render time.

### The store

- **R6. A store per run, sealed at its start.** A new run's store is `github` unless the
  invocation passes `--store session`; it is sealed into the run record at setup and never
  changes for that run. A later invocation passing a different `--store` is refused with
  `store-mismatch` and changes nothing. `/deliver` forwards `--store` to `/execute`
  unchanged. A run that started before this feature has no sealed store and runs as
  `github`.
- **R7. What each store means.** On both stores the session is the record and the body is
  its rendering (R12). On `github`, a host with no session of the topic may recover from the
  rendering (R8). On `session`, it may not: such a start stops with `session-absent`,
  naming the import that would bring the session (R9).

### Recovery and moves

- **R8. Recovery on the `github` store.** A coordinated `/execute` start that finds no
  execute session of the topic on this host, and finds the topic's coordination pull
  request through the ownership lookup, rebuilds the run record before the loop runs:
  - the node-to-pull-request map and follow-ups from the body's rendered index, read by the
    one shared codec that also renders it (R12), never by a script under `skills/execute/`;
  - the run's identity from the body's rendered run line, accepted only when every merged
    node pull request in the map carries that run's marker; otherwise the start stops with
    `recovery-unproven`, naming the nodes whose markers disagree and the take-over step
    (`--take-over-run <id>`) that adopts them, recorded in the run record with the person
    who ran it;
  - each head re-read live (R4).
  The rebuilt record says it was recovered and from which pull request, and the run's
  report says so. A body with no rendered run line (a run that started before this feature)
  recovers the same way, reading its identity from its merged nodes' markers when they all
  agree.
- **R9. The execute session moves by the shared import.** The shared step that imports a
  topic's sessions by name gains an `execute` set (`execute-<topic>`) and a `deliver` set
  (`deliver-<topic>`). After an import, the next `/execute` on the topic resumes the
  imported session in place: same run identity, same keys, no replacement and no recovery.
  The source workspace's copy refuses further ticks as koto already does for a migrated
  session.
- **R10. A pause doesn't end the record.** A run that stops to wait for a merge or a review
  keeps its record readable and resumable: the next `/execute` on the topic, on this host
  or after an import, continues with the same run identity and every recorded fact, and
  re-derives nothing from the body. Per-invocation bookkeeping (the merge attempts already
  made) starts empty on each invocation.
- **R11. `/deliver`'s inner leg after a move.** When a `/deliver` run is resumed after its
  execute session was imported, the leg `/deliver` opens for `/execute` ends with
  `/execute`'s terminal result. Where koto can't bind the imported session to it, `/deliver`
  resolves the leg itself with `outcome: error` and a reason naming the binding failure
  (`execute-leg-lost`), and its report says what state the run reached, so no leg stays
  open with nothing able to finish it. The design measures koto's behavior for a same-host
  import before choosing between re-legging and reporting.

### The body as a rendering

- **R12. Rendered at every transition.** The coordination pull request's body is rendered
  from the run record, `/scope`'s published fields and live state reads, and posted, after
  every transition that changes what it shows: a node's pull request opened or pushed, a
  node observed merged, a follow-up recorded, the cascade pushed or failed, the coordination
  pull request pushed or merged. A failed render or post leaves the record as written and is
  retried at the next transition; it never changes a merge decision.
- **R13. What the rendering shows.** The body keeps the declaration marker CI finds it by,
  a Part 1 in plain prose describing the effort, exactly one top-level `---`, and in Part 2:
  the run lines (topic, outcome, intent, mode, store, run identity), the PR Index and the
  merge-order block. The index has one line per PR node with its pull request, its live
  state and its recorded head (its merged head once merged), one line per follow-up under
  its node in the same reference form so the merge-last gate counts it, and no line for the
  coordination pull request itself. Private-node redaction in a public coordination pull
  request works as it does today.
- **R14. A follow-up can be recorded.** A step records a follow-up pull request against an
  existing node, by node and pull request. It's refused unless the node exists in the run
  record, the pull request is in the node's repository, targets its default branch, and is
  open or merged. Once recorded, the merge-last gate holds the coordination pull request
  until the follow-up has merged, and `/execute` merges an open follow-up the same way it
  merges a node when run with `--merge`.

### Handover and merge messages

- **R15. The coordination pull request's number is handed over.** `/scope`'s result already
  names the pull request it published; `/deliver` passes that pull request to `/execute`,
  which verifies it through the ownership lookup (same repository, author and branch, the
  declaration marker) and records its number at setup. A direct `/execute` with no handover
  finds it through the ownership lookup as today. After setup the run reads the number from
  its record.
- **R16. `/deliver` reads `/scope`'s result, not the page.** `/deliver`'s gate for starting
  `/execute` takes `/scope`'s intent and pull request from `/scope`'s recorded result, not
  from the body's `intent=` line, which stays as a rendering for readers.
- **R17. Merges pass Part 1.** Every merge `/execute` makes, coordinated or single-pr, passes
  the pull request's title as the squash subject and its Part 1 as the squash body, built the
  way `/coordinate`'s land step builds it. A body with no top-level `---` passes all of it,
  as today.

### Compatibility and tests

- **R18. Runs started before this feature keep running.** A run whose session predates the
  run record continues through the recovery path the first time a release with this feature
  ticks it, then on its rebuilt record. Nothing moves any existing run onto the `session`
  store.
- **R19. The CI gate's contract holds.** The reusable merge-last gate keeps finding the
  coordination pull request by its declaration marker in the event payload and re-reading
  the body for the node list, and keeps recomputing every state live; `shirabe validate
  --coordination-body` accepts every body the renderer produces.
- **R20. Tested end to end.** An engine test drives a coordinated run with at least two
  node pull requests against real koto and a stub GitHub: stopped after its first node
  merges, imported into a second workspace on the same host, resumed through its merge-last
  gate with the body's index made unreadable to `/execute`, and its rendered index then
  shows every node merged at its merged head and a recorded follow-up counted by the gate.

## Acceptance Criteria

- [ ] A coordinated run with two node pull requests, stopped after its first node merges
  and imported into a second workspace on the same host with the shared import step,
  resumes there with the same run id and reaches the merge-last gate; during the resumed
  run no `/execute` script reads the body's index (the engine test replaces the body with
  one that has no index and the run still completes).
- [ ] After that run's cascade, the rendered index shows every node `merged` at the head it
  merged at, a follow-up recorded against the first node appears under it, and the CI
  merge-last gate's extraction lists the follow-up and holds the coordination pull request
  while it's open.
- [ ] The rendered index has no line naming the coordination pull request's own number.
- [ ] `grep` over `skills/execute/` finds no script that parses a `head=` field or a PR
  Index entry line from a pull request body, and a structure test fails if one is added.
- [ ] Editing a node's `head=` in the body to another sha changes nothing the run does: the
  next merge of that node passes the head the run record holds, and the next render
  restores the line.
- [ ] Each merge `/execute` makes (node, follow-up, coordination, single-pr home) calls
  `merge-exec.sh` with a message file whose subject is the pull request's title and whose
  body is its Part 1; the coordination pull request's squash message holds no PR Index,
  merge-order, run-line or marker text.
- [ ] Every body the renderer posts has exactly one top-level `---`, a non-empty plain-prose
  Part 1, the declaration marker, and passes `shirabe validate --coordination-body`.
- [ ] A new run without `--store` records `github`; with `--store session` records
  `session`; a later invocation with the other value is refused with `store-mismatch` and no
  key changes.
- [ ] On the `session` store, a start on a host with no session of the topic stops with
  `session-absent` naming the import, and makes no GitHub write.
- [ ] On the `github` store, a start with no session whose merged nodes all carry the
  rendered run id recovers, adopts them, records that it recovered, and re-reads every head
  live; with a merged node carrying another run's marker it stops with
  `recovery-unproven` naming that node, and `--take-over-run <id>` then adopts it and
  records who ran it.
- [ ] A recovered run never merges a node before re-evaluating it at its live head.
- [ ] A run paused at `paused_awaiting_merges` and re-invoked on the same host continues
  with the same run id and its recorded heads and map; its merge attempts start empty.
- [ ] `skill-session.sh import execute <topic> --from <ws>` and `import deliver <topic>
  --from <ws>` import the named session under its own name, and an unknown set is still
  refused.
- [ ] After an import, a resumed `/deliver` run's execute leg ends with the execute
  result, or with `outcome: error` and reason `execute-leg-lost`; in neither case is the leg
  left open after `/deliver` returns.
- [ ] `/deliver` passes `/scope`'s published pull request to `/execute`, `/execute` records
  its number at setup after the ownership check, and a handed pull request that fails the
  check (another author, another branch, no marker) is refused at setup.
- [ ] `/deliver`'s start gate for `/execute` passes with the body's `intent=` line removed
  and fails when `/scope`'s recorded result says `stop`.
- [ ] Recording a follow-up is refused for an unknown node, a pull request in another
  repository, one targeting another branch, and one that is closed unmerged.
- [ ] A run started before this feature (its session holds none of R1's new keys, its body
  carries the old index) continues after the upgrade through recovery and then from its
  record.
- [ ] A public coordination pull request indexing a private node still renders without
  naming it, as today.

## Out of Scope

- What stays on GitHub on purpose: the CI merge-last gate keeps reading the body for the
  node list, the merge-order block stays rendered on the page, and pull request state,
  checks, review and mergeability stay live reads.
- Changing `/execute`'s default store, and moving any existing run onto the `session`
  store. Runs started before this feature, including this feature's own coordinated run,
  stay on the body as they began.
- The single-pr path's state, which already keeps its pushed head in koto; it changes only
  in passing Part 1 as its squash message (R17).
- Removing the coordinator's GitHub issue record, and anything in the coordinate skill that
  removal touches.
- Exercising a move between hosts; the acceptance moves a run between workspaces on one
  host, over the same import a move between hosts uses.
- A full coordinated template with a state per action and a child per node, unless the
  design finds the record needs one.

## Known Limitations

- On the `github` store, recovery trusts the body's rendered map as the list of nodes to
  look at. A hand edit that drops a node from the index hides that node from a recovered
  run until a person re-records it; the run-identity check (R8) catches a node that's there
  under another run, not one that's missing. Heads are never taken from the body, so an edit
  can hide work but can't pin a merge.
- On the `session` store, a run lives only as long as its session: a session removed with
  its workspace and never imported leaves nothing to recover from but the take-over step.
- This feature's own coordinated run executes on the plugin release before it, so it keeps
  its state on the body; the first run kept in its session is one started after a release
  that carries this feature.
- `/deliver`'s outer leg, the one a coordinator watches, is the coordinate skill's to
  re-leg after a move; this feature handles only the leg `/deliver` opens for `/execute`.

## Decisions and Trade-offs

- **Session first on both stores.** The run record lives in the session whether the store
  is `github` or `session`; the store decides only whether the body's rendering is a
  recovery source. The alternative, keeping today's body-as-store on the default `github`
  store and applying the session record only to `session` runs, would ship neither of the
  feature's removals (the body as the store, the merge head read from an editable body) on
  the default path. Decided by the effort's coordinator.
- **Recovery reads the map, never a head.** A recovered run takes the node list from the
  rendering and re-reads every head live, then re-evaluates before merging. Taking heads
  from the body would put the editable page back in the merge decision, which is what the
  feature removes.
- **The shared codec serves rendering and recovery.** One library renders the body and
  parses it for recovery, outside `skills/execute/`. It exists because the CI gate and
  recovery both need the rendering, not to move parsing out of `/execute` to pass a grep.
- **The default stays `github`.** A `session` default would leave a run with no recovery
  source if its session is lost, and the coordinate skill's store default was kept at
  GitHub for the same kind of reason; flipping it is later work.
- **No multi-key write core.** The coordinated loop has one writer at a time and writes each
  step's keys before rendering, so the coordinate skill's write core, built for many writers
  over one record, isn't reused.
- **Follow-ups are recorded by an explicit step, not discovered.** Searching GitHub for pull
  requests that look related would let an unrelated pull request hold the merge-last gate.
- **A run identity recovered from markers must be unanimous.** Accepting a majority would
  let a run adopt a node another run opened; the take-over step makes that a recorded act.

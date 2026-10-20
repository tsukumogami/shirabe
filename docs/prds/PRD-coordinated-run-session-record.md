---
schema: prd/v1
status: In Progress
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
  merge-last gate, `/deliver`'s leg to it ends with a result or a named loss, and the
  default branch gets each pull request's description and nothing else.
absorbed:
  - docs/briefs/BRIEF-coordinated-run-session-record.md
---

# PRD: The coordinated run's session is its record

## Status

In Progress

Absorbed [BRIEF-coordinated-run-session-record](docs/briefs/BRIEF-coordinated-run-session-record.md); carried in Absorbed Brief.

## Absorbed Brief

The feature frames one gap: a coordinated `/execute` run uses the coordination pull
request's body both as the page people and CI read and as the run's own memory, and the
second use is what fails. The body is editable, goes stale once a node merges, has no room
for a follow-up, lists itself, lands on the default branch, and is all a moved or restarted
run has to resume from, so a run whose session is lost or moved can't take its own merged
nodes back. The reason the body was chosen, that a koto session couldn't leave its host, no
longer holds now that session import moves one.

The outcome it asks for belongs to whoever drives a coordinated effort, a person or a
coordinator session dispatching `/deliver` workers: stop a run, move it to another
workspace, and resume it through its merge-last gate as the same run, with `/deliver`'s leg
ending in a result or a stated loss. The reviewer of the coordination pull request reads an
index that matches what happened, and a maintainer reading the default branch finds the
description and none of the run's bookkeeping.

The journeys it traced are the four the User Stories carry before the gate owner's: a
coordinator handing a run to a replacement, a maintainer restarting a run whose execute
session was removed, a reviewer deciding whether to land, and a maintainer reading history.
Its boundary is the one Requirements and Out of Scope draw: the run's facts as its record,
the body as a rendering without the self row, the squash message, identity across a move,
the inner leg and the per-run store with GitHub the default are in; what stays on GitHub on
purpose, the default store and existing runs, the single-pr path, the coordinator's GitHub
record and a proven move between hosts are out.

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

- **Run record**: the facts a coordinated run keeps about itself (R1), as keys in its
  execute session, `execute-<topic>`.
- **Store**: the run's choice, sealed at its start, of what may rebuild a lost record.
  `github` (the default): the coordination pull request's rendered body, read together with
  live GitHub state. `session`: nothing; a host without the session must import it.
- **Recovery**: a start that rebuilds the run record from the rendered body and live GitHub
  reads (R9).
- **Ownership lookup**: the existing filter `skills/execute/scripts/owned-pr.sh` applies to
  find a run's pull request: same repository, the authenticated GitHub login as author, the
  repository's default branch as base, the given head branch, not from a fork. For the
  coordination pull request the body must also carry the declaration marker.
- **Declaration marker**: the text `This is a **coordination PR**` in the body, by which CI
  and `/execute` recognize a coordination pull request.
- **Run marker**: the HTML comment `<!-- shirabe-run: <32 hex> -->` that `/execute` stamps on
  each node pull request it opens, naming the run's id.
- **Follow-up pull request**: a pull request opened against an existing node after its
  review, to address notes from that review, and recorded against the node (R16).
- **Part 1**: everything above a pull request body's first top-level `---` line outside a
  code fence; the whole body when it has none. Part 2 is everything below.

## Goals

- Whoever drives a coordinated effort can stop a run, import it into another workspace,
  and resume it there through its merge-last gate, adopting its merged nodes without
  anyone copying an id by hand.
- After each transition's render, the reviewer reading the coordination pull request sees
  each node's state and head, follow-ups under their node, and no self row, through the
  cascade.
- A merge is pinned only to a head the run recorded, and made only after the readiness
  check passes at that head on the same pass; never to the page.
- The default branch's history carries each merged pull request's title and Part 1 only.
- A coordinator running `/deliver` gets `/execute`'s result on the leg `/deliver` opened
  for it after a move, or a named loss with the state the run reached.

## User Stories

- **As a coordinator handing a run to a replacement mid-flight**, I want the worker's run,
  imported into another workspace after its first node merged, to resume as the same run,
  adopt that node, land the rest and reach the merge-last gate without a hand-set id, so
  that the replacement picks up where the run stopped.
- **As a maintainer restarting a `github`-store run whose execute session was removed** with
  its workspace and no import made, I want the restarted run to recover as the run that
  opened its merged nodes, and, where their run markers disagree, to stop with
  `recovery-unproven` and name the one recorded step that adopts them.
- **As a reviewer deciding whether to land a coordination pull request**, I want its index
  to show every node merged at the head it merged at, the follow-up opened after merge
  review under its node, and the merge order, with CI's merge-last gate counting the
  follow-up, so that I can trust the page.
- **As a maintainer reading the default branch's history**, I want the coordination pull
  request's squash commit to carry its title and Part 1 only, so that the history says what
  the effort did and not how the run kept its books.
- **As the owner of the reusable CI merge-last gate**, I want the gate to keep finding a
  coordination pull request by its declaration marker and reading its node list from the
  body unchanged, so that repositories using the gate need no change.

## Requirements

### The run record

- **R1. The record is session keys.** A coordinated run keeps these facts as keys in its
  execute session, on either store:
  - for each PR node: its repository, its pull request number, the head the run last
    pushed to it, and once the node is observed merged, the head it merged at;
  - for each follow-up pull request: the node it belongs to, its repository, its number,
    the head recorded with it (R16), and its merged head once merged;
  - the coordination pull request's number (R19) and, once the cascade has pushed, its head;
  - the cascade's verdict: `not-run`, `pushed` with the head, or `failed` with the step that
    failed;
  - the node list as the PLAN gave it, recorded at setup, which the run keeps reading after
    the cascade deletes the PLAN;
  - the run's identity (`run_id`, as today), its store (R7), and whether and from which pull
    request the record was recovered (R9).
  The keys join `/execute`'s closed write-target set in `skills/execute/SKILL.md`.
- **R2. One writer per fact.** Each fact in R1 has one owning step: a node's pull request
  and pushed head, the step that pushes the node, after its push succeeds; the coordination
  pull request's head and the cascade verdict, the cascade step; a follow-up and its head,
  the follow-up step (R16); a merged head, the step that first observes the merge, from a
  live read; the coordination
  pull request's number, the node list, the store and `/scope`'s run lines, setup; on a start
  that recovers, every fact recovery rebuilds (map, heads, node list, cascade), recovery,
  together with the recovery marker and the adopt record; and the opener's carry, which copies
  every key into a replacement session holding none. A write by any other step is refused with exit 65
  (`not-owner`) and changes no key, and a failed push writes nothing. Each step writes its
  keys before the body is rendered from them.
- **R3. One way in.** Every `/execute` script that needs a node's pull request, a head, a
  follow-up, the node list or the cascade verdict reads it from the run record through one
  reader. No script under `skills/execute/` reads a PR Index entry or a `head=` field from a
  pull request body: a structure test fails when any non-test file under `skills/execute/`
  defines or calls the index-entry grammar or a function that parses it (today
  `RE_COORD_ENTRY`, `coord_index_entries`, `coord_parse_entry`, `coord_find_entry`), or
  holds a regular expression or `grep`, `sed` or `awk` pattern containing `head=`.
- **R4. A merge's pinned head.** Every merge `/execute` makes of a node, a follow-up or the
  coordination pull request passes `--match-head-commit` with the head the run record holds
  for it. When the pull request's live head differs from the recorded one, the merge isn't
  attempted and the run reports `awaiting:head-moved`, as it does for a node today.
- **R5. Live facts stay live.** A pull request's state, checks, review and mergeability are
  read from GitHub when needed and never written to the run record. The index's state column
  is filled from those reads at render time; when a read fails, the line shows `unknown`.

### The store

- **R6. What each store means.** On both stores the session is the record and the body is
  its rendering (R15, R17). On `github`, a start that finds no run record recovers from the
  rendering (R9). On `session`, it doesn't: a start on a host with no session of the topic
  stops with `session-absent`, naming the import that would bring the session (R12), as does
  a start whose finished session was replaced and whose carry was lost, and
  makes no GitHub write (no body edit, comment or merge).
- **R7. A store per run, sealed at its start.** A new run's store is `github` unless the
  invocation passes `--store session`; setup seals it into the run record and it never
  changes for that run. A later invocation passing a different `--store` is refused with
  `store-mismatch` and changes no key. `/deliver` forwards `--store` to `/execute`
  unchanged. A run that started before this feature has no sealed store; its first start
  under this feature records `github`.

### Recovery

- **R8. When recovery runs.** A coordinated start recovers when its execute session holds
  no run record: there is no session of the topic on this host (the `github` store only), or
  the session is a fresh replacement of a finished one that predates this feature, or a live
  session that predates this feature. A session that holds the record never recovers.
- **R9. How recovery rebuilds the record.** Before the loop runs, recovery:
  - finds the coordination pull request through the ownership lookup on the checked-out
    branch; none found stops with `coordination-pr-missing`, several with
    `coordination-pr-ambiguous`;
  - takes the node list from the PLAN when the checked-out branch still has it, otherwise
    from the body's rendered index, and the node-to-pull-request map and follow-ups from the
    rendered index, ignoring any line that names the coordination pull request itself (an
    earlier release wrote one), read by the shared codec that renders it (R17), which lives outside
    `skills/execute/`;
  - takes the run's identity from the session when it holds one (a carried `run_id`);
    otherwise from the body's rendered run line; otherwise from the run markers on the
    map's node pull requests. `/execute` stamps a marker on every node pull request it
    opens, so every node pull request in the map must carry that identity: one that
    carries another marker, or none, stops the start with `recovery-unproven`, naming every
    such node and the adopt step (`--adopt-run <id>`). A new identity is minted only when the
    map holds no node pull request at all. A follow-up in the map is exempt from the node-branch lookup and the run marker, since a person opens it on any branch; it must pass the follow-up checks of R16 instead (the node's repository and base, no fork, the invoking login as author, not closed unmerged), or recovery drops it and reports `follow-up-dropped:<url>`. An index line is any line that parses
    as a node or follow-up entry; a self row doesn't count;
  - re-reads every head live from GitHub, never from the body;
  - sets the cascade verdict to `not-run` when the PLAN is still on the branch, otherwise
    to `pushed` with the coordination pull request's live head;
  - writes the recovery marker naming the pull request it recovered from.
  The run's report carries `recovered=<pull request URL>` on the invocation that recovered.
  A cascade verdict of `failed`, recovered or recorded, makes the next invocation run the
  cascade again.
- **R10. Every merge passes the readiness check at the recorded head.** Before any merge of
  a node, follow-up or the coordination pull request, the loop runs the readiness check
  (`merge-verdict.sh`: required checks green, review state, mergeability) at the recorded
  head on that same pass, as it does for a node today, and merges only when it passes. A
  recovered or carried head gets no other treatment: the check at merge time is what
  re-verifies it. A head the check refuses is reported with its reason (`awaiting:<reason>`,
  `awaiting:head-moved` when the pull request has moved on) and the run pauses or ends as it
  does today; a new push through the run, or recording a follow-up again, records the new
  head.
- **R11. The adopt step.** `/execute --adopt-run <id>` is honoured on a start that
  recovers (R8), and refused on one whose session already holds a record. It supplies the
  run's identity, outranking a carried `run_id` and the rendered run line, sets the session's
  `run_id` to it, and authorizes recovery to mark, through `run-id.sh`, every node pull request
  in the map that carries another marker (`restamp`) or none (`stamp`), limited to the PLAN's
  repositories, each node's branch and the invoking login as author; it records the step in
  the run record with that login and the time. An id outside `^[0-9a-f]{32}$` is refused. It
  needs no record of an earlier `recovery-unproven` stop: the stop is only what tells a
  person to pass it. It's separate from the single-pr `--take-over`, which re-stamps one open
  pull request on `impl/<slug>`.

### Moves and pauses

- **R12. The execute session moves by the shared import.** The shared step that imports a
  topic's sessions by name (`skill-session.sh import <set> <topic> --from <workspace>`)
  gains an `execute` set (`execute-<topic>`) and a `deliver` set (`deliver-<topic>`),
  compiling the shipped templates for them on the importing host first. After an import
  the next `/execute` on the topic attaches to the imported session: the same `run_id`, the
  same keys, no recovery marker written. The source workspace's copy refuses further ticks
  with koto's `session_migrated`. An import onto a host where a live session of that name
  exists is refused with koto's code and leaves both sessions as they were.
- **R13. A pause keeps the record.** A run that stops to wait for a merge or a review keeps
  its record readable and resumable: the next `/execute` on the topic, on this host or after
  an import, continues with the same `run_id` and every key in R1, reading none of them from
  the body. The merge attempts already made start empty on each invocation; nothing else in
  the record does.
- **R14. `/deliver`'s inner leg after a move.** The leg `/deliver` opens for `/execute` ends
  with `/execute`'s terminal result in each of these cases:
  - a `/deliver` run started after the import opens a fresh request, as every run does, and
    `/execute`'s existing attach binds the imported session to its leg; the result is
    promoted there, and the earlier request is abandoned by the stale-run fence;
  - a `/deliver` session imported with the run and resumed in place on the same host keeps
    its request, which the host's request store still holds and whose leg still names the
    execute session, so the result is promoted there;
  - a `/deliver` session resumed in place on a host whose request store doesn't hold its
    request can't reach that leg: it ends at its error terminal with `reason:
    execute-leg-lost:request_not_found`, naming the execute session's state, and a `/deliver`
    run started after it binds as in the first case.
  Where `/execute` can't be bound to a leg this host's store holds, `/deliver` resolves the leg itself with
  `outcome: error`, `step: deliver:child-absent` and `reason: execute-leg-lost:<koto code>`,
  and its report names the execute session's state, so no leg stays open after `/deliver`
  returns.

### The body as a rendering

- **R15. Rendered at these transitions.** `/execute` renders the coordination pull request's
  body from the run record, the body's live Part 1 and live state reads, and posts it, after
  each of: a node's pull request opened or pushed, a node observed merged, a follow-up
  recorded, the cascade pushed or failed, the coordination pull request pushed, and every
  terminal. A change in live state alone, such as checks finishing, doesn't trigger a
  render; the next one shows it. Rendering an unchanged record and unchanged live state
  produces the same bytes, and an unchanged body isn't posted. A failed render or post
  leaves the record as written, is reported as `body=stale` on that invocation's report, is
  tried again at the next transition, and never changes a node's merge decision. The
  coordination pull request is the exception, since CI's gate reads the posted body: it's
  evaluated and merged only after a render that posted or found nothing to change, and
  otherwise the run reports `merge-refused:body-stale`.
- **R16. A follow-up can be recorded.** `/execute --follow-up <node>=<pull request URL>` on a
  coordinated PLAN records a follow-up pull request against an existing node, with the head
  it reads live at that moment. It's refused, changing nothing, with `follow-up-node` when
  the node isn't in the run record, `follow-up-repo` when the pull request is in another
  repository than the node's, `follow-up-base` when it doesn't target that repository's
  default branch, `follow-up-author` when it comes from a fork or another author than the
  invoking GitHub login, and `follow-up-closed` when it was closed without merging. Recording the
  same pull request again updates its head. Once recorded, the merge-last gate holds the
  coordination pull request until the follow-up has merged; with `--merge`, `/execute`
  merges an open follow-up the way it merges a node (R4, R10), after its node. A recorded
  follow-up later closed without merging holds the gate and is reported as
  `follow-up-closed:<url>` until a person records a replacement or removes it with
  `--follow-up <node>=<url> --remove`.
- **R17. What the rendering shows.** The rendered body is:
  - Part 1: the live body's Part 1, kept byte for byte, when the body has a top-level `---`;
    a person may edit it, and the renderer never rewrites it. Otherwise (a body `/scope` or an
    earlier release wrote) the composed Part 1, exactly `Coordination pull request for
    <topic>. It carries the planning documents for <n> node pull requests and merges after
    all of them.`, with `<n>` the number of PR nodes;
  - exactly one top-level `---`;
  - Part 2: the declaration marker; the run lines `topic=`, `exit=`, `outcome=`, `intent=`,
    `mode=` as `/scope` published them, recorded at setup from the body it found (and, after a
    republish that lost them, from the republished body's own lines), and `store=` and `run=`
    from the record; the PR Index (a node line's `<n>` is its pull request number);
    the merge-order block as today.
  The PR Index has one line per PR node, `- <node> | <repo>:docs/plans/PLAN-<topic>.md#<n> |
  <live state> | head=<head>`, and one line per follow-up (`<n>` its pull request number), `- <node>/follow-up-<n> |
  <repo>:docs/plans/PLAN-<topic>.md#<n> | <live state> | head=<head>`, after its node's line,
  where `<head>` is the recorded merged head once merged and the recorded pushed head
  before. The reference field is the form
  `scripts/coordination-gate-refs.sh` extracts, so the gate counts every line. No line names
  the coordination pull request itself. A public coordination pull request never indexes a
  node in a private repository: the push of such a node is refused with `execute:visibility`,
  as today, and the renderer refuses to render one. A rendered body over 60,000 bytes isn't
  posted and is reported as `body=full`.
- **R18. `/scope`'s republish.** A `/scope` republish that rewrites the body after `/execute`
  has started may drop Part 2; the next `/execute` transition renders it again from the
  record. Recovery between the two reads the republished body. A body with no index line is read as an empty map only when no PLAN node's branch (`impl/<slug>-<node>`) has an owned pull request; when one does, the index was lost (a `/scope` republish, a hand edit) and recovery stops with `coordination-index-missing` rather than re-dispatch a node that already has a pull request. With the PLAN also gone from the branch, nothing names the nodes and recovery stops with `coordination-index-missing` too.

### Handover and merge messages

- **R19. The coordination pull request's number is handed over.** `/deliver` passes the pull
  request `/scope`'s result names to `/execute` (`--coordination-pr <url>`), and setup
  verifies it through the ownership lookup on the checked-out branch and records its number.
  A handed pull request that fails the lookup, or that differs from the one the lookup finds,
  is refused at setup with `coordination-pr-mismatch`. A direct `/execute` with no handover
  finds it through the lookup, and stops with `coordination-pr-missing` or
  `coordination-pr-ambiguous` when it finds none or several. After setup the run reads the
  number from its record; a later invocation that finds the recorded pull request closed
  unmerged stops with `coordination-pr-closed`.
- **R20. `/deliver` reads `/scope`'s result, not the page.** `/deliver`'s gate for starting
  `/execute` takes `/scope`'s intent and pull request from `/scope`'s result on its leg, not
  from the body's `intent=` line, which stays a rendering for readers. A body `intent=` that
  disagrees with the result is ignored.
- **R21. Merges pass Part 1.** Every squash merge `/execute` makes, coordinated or single-pr,
  passes the pull request's title as the subject and its Part 1 as the body, built by the same
  script `/coordinate`'s land step uses (`scripts/lib/squash-message.sh`, moved there from
  the coordinate skill, which
  strips markdown and HTML comments and refuses an empty Part 1, a multi-line title and AI
  attribution). A body with no top-level `---` passes all of it. When no message can be built,
  the merge isn't attempted and the run reports `merge-refused:squash-message`. A `merge`
  method passes the same message; a `rebase` merge takes none.

### Compatibility, limits and tests

- **R22. Runs started before this feature keep running.** Such a run recovers once (R8),
  with `run_id` carried when its session had one, reading the old index format, and then runs
  on its record with store `github`. Nothing moves an existing run onto the `session` store.
- **R23. The CI gate's contract holds.** The reusable merge-last gate keeps finding the
  coordination pull request by its declaration marker in the event payload, re-reading the
  body live for the node list and recomputing every state live, with no change to its
  workflow. `shirabe validate --coordination-body` accepts every body the renderer produces.
- **R24. One writer at a time.** Two `/execute` invocations on one topic at once are not
  supported; koto's attach already refuses a second workspace's session, and the record
  assumes one writer.

## Acceptance Criteria

### The end-to-end move

- [ ] An engine test drives a coordinated run with two node pull requests against real koto
  and a stub GitHub, with `--merge`: after the first node merges the run stops at
  `paused_awaiting_merges`, `execute-<topic>` is imported into a second workspace on the same
  host with `skill-session.sh import execute`, and `/execute` there reports the same
  `run_id`, writes no recovery marker, and ends `merged`. For every read during the resumed
  run the stub serves the coordination body with its PR Index and run lines removed.
- [ ] In that test, the last body the stub received shows both nodes `merged` with
  `head=<the sha the stub merged>`, a follow-up recorded against the first node on the line
  after it, and no line naming the coordination pull request's number;
  `coordination-gate-refs.sh` over that body lists both nodes and the follow-up.
- [ ] In that test, the source workspace's `koto next execute-<topic>` exits with
  `session_migrated` after the import.

### The record and its writers

- [ ] After setup the record holds the node list, the store and the coordination pull
  request's number; after the cascade deletes the PLAN, the loop still lists every node.
- [ ] The cascade verdict reads `not-run` before the cascade, `pushed` with the coordination
  head after it, and `failed` with the step when the stub fails the cascade's push.
- [ ] For every key in R1, a write from a step other than its owner (R2) exits 65 `not-owner`
  and leaves the key unchanged; a push the stub rejects writes no head; in the stub's request
  log every body post comes after the koto write of the keys it shows.
- [ ] After a cascade verdict of `failed`, the next invocation runs the cascade again.
- [ ] The record holds no key for a pull request's state, checks, review or mergeability; a
  node the stub closes between transitions shows `closed` at the next render.
- [ ] The structure test fails when a non-test file under `skills/execute/` contains
  `RE_COORD_ENTRY`, `coord_index_entries`, `coord_parse_entry` or `coord_find_entry`, or
  matches `head=` on a pull request body, and passes on the shipped tree.

### Merges

- [ ] With a node's `head=` edited in the body to another sha, the node's merge passes the
  recorded head to `--match-head-commit`, and the render after that merge restores the line
  to the recorded head.
- [ ] A follow-up's and the coordination pull request's merges pass their recorded heads;
  when the stub's live head differs from the recorded one, no merge call is made and the run
  reports `awaiting:head-moved`.
- [ ] Each merge (node, follow-up, coordination, single-pr home) calls `merge-exec.sh` with a
  message file whose first line is the title and whose body is Part 1; the coordination merge's
  message contains no `PR Index`, `merge-order`, `topic=`, `run=` or declaration-marker text.
- [ ] A body with no top-level `---` passes the whole body as the message; a body whose Part 1
  is empty after stripping, a multi-line title, or AI attribution in Part 1 makes no merge call
  and reports `merge-refused:squash-message`.
- [ ] A merge whose verdict method is `merge` passes the same message file; one whose method is
  `rebase` passes none.

### The store

- [ ] A new run without `--store` records `github`, with `--store session` records `session`,
  and a later invocation with the other value exits with `store-mismatch` and changes no key;
  `/deliver --store session` reaches `/execute` as `--store session`.
- [ ] On the `session` store, a start with no session of the topic stops with
  `session-absent` naming the import, and the stub records no body edit, comment or merge.

### Recovery

- [ ] On the `github` store, a start with no session whose rendered run line matches every
  marked node pull request recovers: the record names the pull request it recovered from, the
  report carries `recovered=<url>`, and the run continues.
- [ ] A recovered run reads each node's live head and calls the readiness check at that head
  before any merge call, in that order in the stub's request log; a node whose readiness check
  fails isn't merged.
- [ ] A node pull request carrying another run's marker stops recovery with
  `recovery-unproven` naming it (two such nodes: both named); a recovering start with
  `--adopt-run <id>` then re-stamps them, records the GitHub login and time, and the run
  continues. `--adopt-run` on a start whose session holds a record, or with a malformed id, is
  refused. A node pull request with no marker is stamped the same way.
- [ ] Recovery with no rendered run line and all marked nodes agreeing takes their id; with no
  run line and no marked node it mints a new id; with a session holding a carried `run_id` it
  keeps that id; with a rendered run line it takes the line's id.
- [ ] Recovery with the PLAN still on the branch takes the node list from the PLAN and sets the
  cascade verdict to `not-run`; a recovered follow-up is merged only after the readiness
  check passes at its recovered head.
- [ ] Recovery over an old-format body that carries a line for the coordination pull request
  itself ignores that line.
- [ ] Recovery with no coordination pull request found stops with `coordination-pr-missing`
  and with two found with `coordination-pr-ambiguous`; a body with no index line recovers an
  empty map when no PLAN node's branch has an owned pull request, and stops with
  `coordination-index-missing` when one does.
- [ ] A node pull request in the map with no run marker stops recovery with
  `recovery-unproven`, naming it.
- [ ] Recovery with the PLAN gone from the branch sets the cascade verdict to `pushed` at the
  coordination pull request's live head and re-verifies it before the coordination merge.
- [ ] A run whose session predates this feature (it holds `run_id` and none of R1's new keys,
  its body carries the old index) recovers once keeping its `run_id`, records store `github`,
  and the next invocation writes no recovery marker.
- [ ] With a node removed from the rendered index by hand and the PLAN gone, a recovered run
  doesn't list that node (the Known Limitation, pinned).

### Pauses, imports and legs

- [ ] A run stopped at `paused_awaiting_merges` and re-invoked on the same host continues with
  the same `run_id`, recorded heads and map, with the stub serving a body with no index; its
  merge attempts start empty.
- [ ] `skill-session.sh import execute <topic> --from <ws>` and `import deliver <topic> --from
  <ws>` compile the shipped templates on the importing host and import the named session under
  its own name; an unknown set is refused; an import onto a host with a live session of that
  name is refused and leaves both sessions unchanged.
- [ ] After `execute-<topic>` is imported to a second workspace on the same host, a new
  `/deliver` run's execute leg resolves with `result_source: promoted` and `/execute`'s outcome,
  and the earlier request reads `abandoned`.
- [ ] A `/deliver` session imported with the run and resumed in place on the same host gets
  `/execute`'s result on its original leg.
- [ ] When the execute leg can't be bound (the stub koto refuses the attach), `/deliver` returns
  with the leg resolved `outcome: error`, `reason: execute-leg-lost:<code>`, its report naming
  the execute session's state, and no open leg.
- [ ] A `/deliver` session imported between two simulated hosts with separate request stores and
  resumed in place ends with `reason: execute-leg-lost:request_not_found`, naming the execute
  session's state; a new `/deliver` run there then gets `/execute`'s promoted result.

### The rendering

- [ ] A render follows each listed transition, a live-state change alone posts nothing, and two
  renders of an unchanged record and live state post once.
- [ ] A post the stub fails leaves the record unchanged, the report carries `body=stale`, the
  next transition posts the body, and the merge decisions in between are the same as with the
  post succeeding.
- [ ] A renderer test over records with nodes open, merged and closed, with zero, one and two
  follow-ups, checks every body it produces has exactly one top-level `---`, the declaration
  marker and the run lines (`store=` and `run=` included) below it, no line naming the
  coordination pull request's number, passes `shirabe validate --coordination-body`, and that
  `coordination-gate-refs.sh` over it lists exactly the nodes and follow-ups.
- [ ] A body `/scope` wrote (no top-level `---`) gets exactly the composed Part 1 of R17 on
  the first render; a body with a Part 1, including one a person edited to hold a list, keeps
  it byte for byte.
- [ ] A state read the stub fails renders that line's state as `unknown`.
- [ ] Each of these posts a body in its own test case: a node's pull request opened, a node
  pushed, a node observed merged, a follow-up recorded, the cascade pushed, the cascade
  failed, the coordination pull request pushed, and each of the five terminals.
- [ ] A node in a private repository under a public coordination pull request is refused
  with `execute:visibility` at its push, and the renderer refuses a record holding one, without
  naming the private repository in either message.
- [ ] A rendered body over 60,000 bytes isn't posted and the report carries `body=full`.

### Follow-ups and handover

- [ ] `--follow-up <node>=<url>` records an open and a merged follow-up with its live head;
  recording it again updates the head; it's refused with `follow-up-node`, `follow-up-repo`,
  `follow-up-base`, `follow-up-author` and `follow-up-closed` for the five cases in R16, each
  changing nothing; two follow-ups on one node render as two lines, each named by its number.
- [ ] With a render the stub fails just before the coordination merge, no coordination merge
  call is made and the run reports `merge-refused:body-stale`.
- [ ] With an open follow-up recorded, the merge-last gate fails until it merges; with
  `--merge` the run merges it after its node; without `--merge` it doesn't.
- [ ] A recorded follow-up closed unmerged holds the gate and is reported as
  `follow-up-closed:<url>`; `--remove` drops it and the gate passes; recording a replacement
  follow-up for the node and removing the closed one lets the gate pass once the replacement
  merges.
- [ ] A follow-up recorded against a node already merged is merged with `--merge` on the next
  invocation; with node and follow-up both open, the node merges first.
- [ ] `/deliver` passes `/scope`'s pull request as `--coordination-pr`; setup records its
  number; a handed pull request from another author, another branch, without the marker, or
  differing from the lookup's, is refused with `coordination-pr-mismatch`; a direct
  `/execute` finds the pull request through the lookup; a later invocation reads the number
  from the record without a lookup; a recorded pull request closed unmerged stops the run with
  `coordination-pr-closed`.
- [ ] `/deliver`'s start gate for `/execute` passes with the body's `intent=` line removed, and
  with it reading `stop` while `/scope`'s result says `continue`; it fails when the result says
  `stop`.

### The CI gate

- [ ] `.github/workflows/lifecycle.yml`'s merge-last step and `coordination-gate-refs.sh` are
  unchanged, and the gate's existing tests pass against rendered bodies.

## Out of Scope

- What stays on GitHub on purpose: the CI merge-last gate keeps reading the body for the
  node list, the merge-order block stays rendered on the page, and pull request state,
  checks, review and mergeability stay live reads.
- Changing `/execute`'s default store, and moving any existing run onto the `session` store.
- The single-pr path's state, which already keeps its pushed head in koto; it changes only in
  passing Part 1 as its squash message (R21).
- Removing the coordinator's GitHub issue record, and anything in the coordinate skill that
  removal touches, including the coordinator's own leg to `/deliver`, which the coordinate
  skill already re-legs after a move.
- Exercising a move between hosts. The acceptance moves a run between workspaces on one host
  over the same import a move between hosts uses; R14's third case is proved on two simulated
  hosts with separate request stores, not on two machines.
- Concurrent `/execute` invocations on one topic (R24).

## Known Limitations

- On the `github` store, recovery with the PLAN gone trusts the rendered index as the list of
  nodes. A hand edit that drops a node hides it from a recovered run until a person records it
  again; the identity check catches a node that's there under another run, not one that's
  missing. Heads are never taken from the body, so an edit can hide work but can't pin a merge.
- On the `session` store, a run lives only as long as its session: a session removed with its
  workspace and never imported leaves nothing to recover from.
- This feature's own coordinated run executes on the plugin release before it, so it keeps its
  state on the body; the first run kept in its session is one started after a release that
  carries this feature.
- A failed render leaves the page stale until the next transition; a run that fails to post at
  its terminal leaves it stale until the next invocation.

## Decisions and Trade-offs

- **Session first on both stores.** The run record lives in the session whether the store is
  `github` or `session`; the store decides only whether the body's rendering may rebuild a lost
  record. The alternative, keeping today's body-as-store on the default `github` store, would
  ship neither of the feature's removals (the body as the store, the merge head read from an
  editable body) on the default path.
- **Recovery reads the map, never a head.** A recovered run takes the node list and map from
  the rendering, re-reads every head live and re-verifies before merging. Taking heads from the
  body would put the editable page back in the merge decision.
- **The shared codec serves rendering and recovery.** One library renders the body and parses
  it for recovery, outside `skills/execute/`. It exists because the CI gate and recovery both
  need the rendering, not to move parsing out of `/execute` to pass a grep.
- **The default stays `github`.** A `session` default would leave a run with no recovery source
  when its session is lost; the coordinate skill kept its store default at GitHub too, and
  flipping it is later work.
- **No multi-key write core.** The loop has one writer at a time and writes each step's keys
  before rendering, so the coordinate skill's write core, built for many writers over one
  record, isn't reused.
- **Follow-ups are recorded by an explicit step with their head, not discovered.** Searching
  GitHub for related pull requests would let an unrelated one hold the merge-last gate, and a
  follow-up the run didn't push still needs a pinned head, so recording reads it live and a
  later push needs a re-record, as a node's moved head does.
- **A recovered identity must be unanimous.** Accepting a majority would let a run adopt a node
  another run opened; `--adopt-run` makes that a recorded act, separate from the single-pr
  `--take-over`, which re-stamps a branch's one pull request rather than adopting a run.
- **The inner leg rides the existing attach.** Measured on koto 0.20.1: after a same-host
  import the source copy refuses with `session_migrated`, the old request's leg stays bound to
  the session's name, and a new request's `koto init --attach-live --koto-leg` binds the
  imported session, whose terminal result is then promoted to the new leg while the old
  request is abandoned. So the leg needs no new mechanism on one host. A request store that
  doesn't hold the request can't be written at all, so R14's third case reports the loss and
  leaves the re-leg to the next `/deliver` run rather than inventing a second request inside a
  resumed one.
- **The handed-over number is verified, not trusted.** The ownership lookup is what rejects a
  fork's or another author's pull request, so a number from `/scope`'s result is checked
  against it rather than taken alone.

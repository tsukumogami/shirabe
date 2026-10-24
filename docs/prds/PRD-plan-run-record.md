---
schema: prd/v1
status: Accepted
problem: |
  After a plan's work merges, shirabe deletes the PLAN, and koto may remove the sessions
  that ran it on every host sharing the cloud store. A reviewer, auditor or later agent who
  starts from a merged pull request has no way back to the run: nothing maps a PR to its
  session, the session doesn't hold the plan as each step began or its departures, koto
  files a session under its workspace's path so a fresh workspace can't see it, and the PR
  text can't carry a pointer because PRs carry no workflow content unless a repository
  opted in. Today's `/execute` PRs carry a hidden run marker anyway.
goals: |
  From a merged PR's repository and number alone, shirabe's tools reach the koto session
  that ran its plan and every PR the plan produced, and read the plan at each step, each
  step's proof, each departure and each decision with its actor, from any workspace on the
  cloud store, after the run's host is gone. koto's session pin keeps those sessions through
  every removal. PRs carry nothing from koto, shirabe or niwa unless the repository opted in.
upstream: docs/briefs/BRIEF-plan-run-record.md
motivating_context: |
  shirabe's lifecycle already deletes a PLAN at completion and relies on the run's koto
  session as the account of what happened. koto's session pin (koto#441, specified in
  tsukumogami/koto#444) gives retention a mechanism to state a need against. The PR content
  switch (`scripts/pr-workflow-content.sh`, from #1124) made workflow content opt-in, which
  rules out the PR body as the place to keep the way back.
---

# PRD: A plan's run outlives the plan as its record

## Status

Accepted

## Problem Statement

A plan in shirabe is a working document. `/plan` writes it, `/execute` carries out a
single-pr or coordinated plan and `/work-on` carries out a multi-pr one, and the
completion step deletes it once the work merges. The record of how the work went is meant
to be the koto session that ran it. That's `execute-<topic>` for single-pr and coordinated
plans, with one `/work-on` child per step. For multi-pr plans there's no plan-level
session at all: each item runs as its own `issue_<N>` session.

The people who need that record arrive from a merged PR: a reviewer asking why a step took
the shape it did, an auditor checking that each step was proved, a later agent picking up a
follow-up. Today they can't get from the PR to the run, for five reasons.

1. **Nothing maps a PR to its session.** PR text is off limits by default: since #1124,
   titles, bodies and squash messages carry no workflow content unless the repository
   declares `## PR Workflow Content: include`. The head branch doesn't reliably name the
   plan. `/execute` adopts existing branches, coordinated node branches can't be split back
   into slug and node, and multi-pr branches carry no plan slug. And `/execute` stamps a
   hidden `<!-- shirabe-run: <id> -->` line on every PR it opens, whatever the setting. That
   line names the run, not where its record is, and it breaks the default anyway.
2. **koto files a session under its workspace's path.** Under the cloud backend a session's
   objects sit under a hash of the canonical path of the directory it ran in. A run's
   directory is a niwa instance that gets reaped. A fresh workspace at another path can
   neither list nor read the session. The only koto command that crosses workspaces,
   `koto session import`, moves the session and leaves the original inert.
3. **The session doesn't hold what a reader asks for.** Nothing records the plan as it stood
   when each step began. `step_refine/<step>.md` covers later steps of a single-pr run only,
   and `plan_intent.md` is a digest. No key records a departure against the step it changed.
   `koto decisions record` has no actor field, and `/execute` records no decisions at all.
   Each step's proof sits in its `/work-on` child. A single-pr child is found through koto
   lineage, a coordinated child through a dispatched-by link, and neither route works for a
   reader on another host.
4. **Nothing keeps the session.** koto keeps a finished session while its hierarchy is alive
   and then for `retention.keep`, 7 days by default. After that the next prune takes it, and
   under the cloud backend the removal reaches every host. A re-run of the same plan replaces
   the finished root. koto's session pin will keep a session through every removal, but
   only a session someone pinned.
5. **The documentation disagrees.** The plan format reference says a PLAN stays in
   `docs/plans/` through every state and calls `Done` terminal. The planning skill and the
   cascade delete it. The roadmap format reference calls a Done roadmap a historical record
   that stays, while the roadmap skill deletes it. Neither tells a reader where the record
   went.

### Terms

- **Run**: everything one plan's execution does, across however many invocations it takes,
  identified by its `run_id`.
- **Invocation**: one start or resume of `/execute`, `/work-on`, `/scope` or `/deliver`,
  entering through that skill's opener script. A `/work-on` child that `/execute` hands a
  step to is part of its parent's invocation.
- **Record root**: the one session a reader starts from for a run. For single-pr and
  coordinated it's the run's `execute-<topic>` session. For multi-pr it's a plan-level
  session R6 defines.
- **Step session**: the `/work-on` session that produced a step's result. When a step was
  attempted more than once, it's the attempt whose result the run kept. Earlier attempts are
  superseded.
- **Index entry**: a store-side record that maps one repository and PR number to the record
  root of a run that opened or adopted it. The run writes it when it first records the PR, at
  open or adoption, before its terminal, and stamps it with the time it was written. The **index sessions** are the
  sessions holding index entries.
- **The run's PRs**: every PR the run opened or adopted and recorded, whatever its final
  state. For single-pr that's the home PR. For coordinated it's each node PR, each follow-up
  PR (a PR a coordinated run opens for a node after the node's first PR, recorded against
  that node) and the coordination PR. For multi-pr it's each item's PR.
- **Evidence-holding session**: a record root, a step session or an index session of a run
  that reached a qualifying terminal (R12). Nothing else is.
- **Workflow content**: any of a session name or reference, a `run_id`, the hidden run
  marker, run lines (`topic=`, `exit=`, `outcome=`, `intent=`, `mode=`, `store=`, `run=`),
  a PR index or merge-order block, a review-panel table, override or deferral notes, a
  pointer to a PLAN or ROADMAP file, a workspace path, or a koto, shirabe or niwa command.
- **Part 2**: the part of a PR body after its single `---` separator, in shirabe's two-part
  PR body convention (`references/pr-body-conformance.md`). The squash commit takes Part 1
  only.

## Goals

- A reader with shirabe, koto and access to the cloud session store gives only a PR's
  repository and number. They reach the session that ran its plan and every PR the plan
  produced, from any workspace, weeks after the run's host and instance are gone.
- That session holds the plan as each step began, each step's proof, each recorded
  departure against its step, and each decision with its actor.
- Evidence-holding sessions survive every removal koto applies on every host, and the
  removal says why. The run's other finished sessions go as today.
- PRs carry no workflow content by default. A repository that opts in gets a session
  reference, and an invocation started after the option is turned off writes none.
- shirabe's documentation states one lifecycle for PLAN and ROADMAP and sends a later reader
  to the run's session.

## User Stories

- **Following a merged PR back to its run.** As a reviewer in a fresh workspace weeks after
  a single-pr plan merged, I want to give the PR's repository and number and get the session
  that ran the plan and its PR list, so that I can read the step that puzzles me: the plan as
  that step began, its proof, the departure recorded against it and who decided it.
- **Auditing every step.** As an auditor checking a coordinated plan across two
  repositories, I want to walk from the record root to each step's session and read its
  proof, so that I can confirm each step was verified without asking anyone who ran it.
- **Pruning on a second host.** As an operator on a host sharing the cloud store, I run a
  prune of finished sessions. The merged plan's record root, step sessions and index
  sessions remain, each listed as kept by its pin. The run's superseded attempts are
  removed.
- **A multi-pr plan's PRs lead to one record.** As a reader starting from the second of a
  multi-pr plan's three PRs, I want to reach the plan's record and from it all three PRs,
  including one that merged after mine, so that the plan mode doesn't decide whether a record
  exists.
- **Turning the session reference on and off.** As a maintainer, I want to turn on a session
  reference in my repository's PRs through workspace config, and have an invocation started
  after I turn it off write none, so that the default stays clean and the switch means what
  it says.
- **Reading the lifecycle.** As a contributor looking for a merged plan that's no longer in
  `docs/plans/`, I want the plan format reference, the planning skill and the completion step
  to say the PLAN was deleted and to name the lookup that finds its run, so that I'm not sent
  looking for a file.
- **Releasing a record.** As a maintainer who no longer needs a merged plan's record, I want
  to know which sessions shirabe pinned and how to release them, so that the next prune
  reclaims them.

## Requirements

### The lookup

- **R1. PR to record.** A shirabe command takes a repository (`owner/repo`) and a PR number,
  and prints its answer as JSON on stdout. Its exit codes are fixed: 0 when an index entry
  for the PR exists, printing the record root's address (the workspace it was created in and
  its session name), the `run_id` and whether the record is complete; 3 when no index entry
  exists for the PR; 2 when a store read failed; 64 for a malformed repository or PR number.
  It reads nothing from GitHub: not the PR's title, body, comments, commits or branch.
- **R2. Record to every PR.** From the record root, the same command lists the run's PRs as
  repository and number, none missing and none extra, each with the state the run last
  recorded for it (open, ready, merged or closed). The run records a PR's state when it
  observes it, so a PR a person merges after the run's terminal still reads `ready`. For
  multi-pr this includes items that ran after the PR the reader started from.
- **R3. Any workspace, after the instance is gone.** R1 and R2 work from a workspace at any
  path with no local copy of the run's sessions, using only the cloud store. Every read
  leaves the record as it is: no import, no migration marker, and no write of any kind into
  a run, step or index session.
- **R4. The right run.** When a topic ran more than once, R1 returns the run whose index
  entry names the PR. When more than one run recorded the same PR (a later run adopted it),
  R1 returns the run whose index entry for it was written last and lists the others. A record root koto later
  moved aside under a new name (`<name>_r<N>`) is still found. The command confirms every
  hit by the PR appearing in the record root's own list of PRs, and a session whose list
  doesn't name the PR is never returned.
- **R5. A partial record says so.** When the record root is found but part of the record
  isn't (a step session was removed, a run started before this feature, or pins were never
  set), R1 exits 0 with `complete: false` and a `missing` list naming each missing part.
  When an index entry exists but its record root itself is gone, R1 exits 0 with
  `complete: false` and `missing` naming the record root, and lists no PRs.
- **R6. Who owns the lookup, and what it needs from koto.** The lookup is shirabe's: a
  shirabe script over koto's commands. It needs exactly two things from koto, and uses no
  other koto surface beyond today's session, context and decision commands:
  - **K1, the session pin**, as koto#444's PRD specifies it.
  - **K2, workspace-independent reach**: from any workspace on the same bucket, read a
    named session another workspace created (its context keys and its decisions) without
    importing, migrating or writing it; and create, write and read an index session at an
    address every workspace computes the same way.

  K2 doesn't exist in koto today. It's a koto change, delivered as its own step in koto
  and pending koto's acceptance. shirabe's side is built and tested against a stub koto that
  implements K1 as the pin's PRD specifies and K2 as stated here, and nothing else.

### What the record holds

- **R7. A record root for every plan mode.** Every run has exactly one record root. For a
  multi-pr plan it's a plan-level session at the K2 address, keyed by repository and topic.
  The first item run to reach it creates it. Each later item run, on any host, adds its own
  entry and never rewrites another item's. Two item runs reaching it at once leave one root
  holding both entries.
- **R8. The plan as each step began.** Before each step is handed to its step session, step 1
  included and in every mode, the record holds the PLAN's full text as committed at `HEAD`,
  the commit's SHA and the step's own entry, keyed by the step's id. Uncommitted edits to the
  PLAN aren't recorded: a step hands off from committed state.
- **R9. Each step's proof.** For each step, the record root names the step session by name.
  That session holds the step's summary (`summary.md`), verification results
  (`verification_results.json`), review verdicts (`review_results.json`) and the PR it
  belongs to. The record root holds each of the run's PRs' last recorded state. A reader gets
  from the root to each step session by name, without koto lineage or local links.
- **R10. Departures against their step.** Every departure the run records is kept against
  the step it changed, with these fields: step id, kind, what changed, and why (non-empty).
  The kinds are an acceptance criterion marked deviated, an approved deferral, a scope change
  that sent the step back to analysis, and a later step's entry rewritten before it ran.
- **R11. Decisions with their actor.** Every decision the run records carries a non-empty
  actor. The actor is `agent:<session or anchor name>` for an agent's decision and `person`
  for a decision taken at a human approval gate, with the person's GitHub login appended
  when the gate recorded one. Until a separate decision-authority display exists, "who" is
  that recorded actor.

### Keeping the record

- **R12. What gets pinned, and when.** A run reaches a qualifying terminal when every one of
  its PRs is ready for review or merged: for single-pr, `/execute`'s terminal after the home
  PR is ready or merged; for coordinated, its terminal after every node, follow-up and
  coordination PR is ready or merged; for multi-pr, each item run's terminal after its own PR
  is ready or merged. At a qualifying terminal, shirabe pins through K1 the record root, each
  step session, and each index session the run wrote. A multi-pr item pins the plan-level
  root (a repeat pin is a no-op), its own step session and its index session, and leaves
  every earlier item's pins as they are. Pinning happens after the run's last tick that could
  respawn a child.
- **R13. The pin's reason.** Each reason comes from one fixed template over the topic, the
  repository and the PR number. It holds at most 500 characters and no control characters,
  and it carries no free text from the plan. A topic long enough to push it past 500 is
  truncated to fit.
- **R14. Only evidence is pinned.** shirabe pins nothing but evidence-holding sessions. A
  superseded attempt, a session a pause replaced, the scoping chain's sessions, and every
  other finished session from the run are removed as they are today.
- **R15. Retention is koto's.** shirabe adds no retention rule of its own and never unpins.
  A pin comes off only as koto allows: by hand, or from an agent session whose start was
  handed koto's `release-pin` authority. `references/koto-session-retention.md` lists the
  kinds of session shirabe pins and both release routes. Nothing in this feature requires a
  change to the pin's design.
- **R16. A failed pin is visible.** A pin koto refuses (exit 2) or can't confirm in the
  bucket (exit 3) doesn't fail the run's PR, and it isn't silent. The run's terminal result
  carries `record: unpinned` and names each unpinned session with koto's error code. The next
  invocation on the topic retries those pins.
- **R17. The pin floor.** The koto version that first honours pins in full is one constant in
  one shirabe file. shirabe calls `koto session pin` only when the installed koto is at or
  above it. While koto hasn't released one, the constant is unset and no pin is attempted.
  Either way, an unattempted pin produces R16's `record: unpinned`. shirabe's overall koto
  floor doesn't change for this feature.
- **R18. Pinned sessions in shirabe's own recovery.** Every shirabe instruction outside
  `skills/coordinate/` that tells an agent to run `koto session cleanup` or
  `koto cancel --cleanup` says, within the same paragraph, that a pinned session is refused
  and is left alone, and names the fresh-name route instead.

### Pull request content

- **R19. Nothing by default.** Unless the repository opted in (R21), no PR a shirabe run
  opens or edits carries workflow content: not in its title, body, comments or squash commit
  message. That holds in every plan mode, for coordinated node PRs and the coordination PR
  too, and the hidden `<!-- shirabe-run: <id> -->` line is no longer written.
- **R20. Ownership without the marker.** Two runs sharing a login and a branch are still told
  apart: a PR belongs to the run whose index entry names it, and the ownership lookup treats
  a PR whose latest index entry names another run as foreign. Nothing is read from the PR's
  text for it.
- **R21. The opt-in.** A repository opts in through `scripts/pr-workflow-content.sh`, the
  existing reader. Only its `include` printed with exit 0 counts. Any other output or exit
  status means omit. Under `include`, every PR the run opens, and every PR whose body it
  rewrites, gets a session reference in Part 2: the record root's session name and the
  `run_id`, enough for R1 to confirm it. The reference never goes in the title or Part 1, so
  it never reaches the squash message.
- **R22. Read once per invocation.** Each invocation reads the switch once, at its opener,
  from the checkout it opens in, and records the value in its session. Every PR write in
  that invocation uses the recorded value, even if the header changes mid-invocation. An
  invocation started after the option is turned off writes no session reference. A PR body
  written earlier under `include` keeps its reference unless a later `omit` invocation
  rewrites that body, which then leaves it out.
- **R23. The checkout limit.** The reader works only from a checkout, so an invocation opened
  without one records `omit`. That limit is stated in `README.md`'s PR content section. A
  checkout-free source for the switch isn't part of this work.

### The lifecycle documentation

- **R24. One lifecycle.** On the default branch, these files state the same lifecycle:
  `skills/plan/references/plan-format.md`, `skills/plan/SKILL.md`,
  `skills/plan/references/quality/plan-doc-structure.md`, the header of
  `skills/work-on/scripts/run-cascade.sh` (the completion step),
  `skills/roadmap/references/roadmap-format.md`, `skills/roadmap/SKILL.md` and
  `references/pipeline-model.md`. Each one says three things. A PLAN and a ROADMAP are
  deleted when their work finishes. A committed PLAN or ROADMAP at `Done` fails CI (the
  `L01` lifecycle check). Only a multi-pr PLAN reaches the default branch, where it stays at
  `Active` while its PRs land.
- **R25. Sent to the session.** Each of those files names the R1 command as the way to a
  finished plan's run.
- **R26. The retention reference.** `references/koto-session-retention.md` states the koto
  behaviour shirabe relies on: a finished session is kept while its hierarchy is alive and
  then for `retention.keep` (7 days by default), `koto session prune` and
  `koto workspace prune` remove what's past it, a same-name replace moves a kept
  predecessor aside as `<name>_r<N>`, and a pinned session survives all of these.

### Constraints

- **R27. Nothing under `skills/coordinate/` changes.**
- **R28. Bash 3.2, no new dependencies.** New scripts hold to shirabe's bash floor and need
  only bash, `jq`, `gh` and koto.
- **R29. Bounded lookup cost.** For a run with P PRs and S steps, R1 and R2 together make at
  most 2 + P + S koto reads, plus 1 per moved-aside predecessor checked, checking at most 10
  predecessors. Nothing lists the whole store.
- **R30. Public-safe content.** Pin reasons, index entries and the opt-in reference are
  built from fixed templates over the topic, repository, PR number, session name and
  `run_id`, never from plan prose. A workspace path is written only to the store.

### Runs in flight

- **R31. Runs that started before this lands.** A run already in progress when this ships
  records from its next invocation on. It writes index entries and pins at its qualifying
  terminal as any run does, and R5 reports the steps it recorded nothing for.

## Acceptance Criteria

The criteria below run against a stub koto that implements K1 as koto#444's PRD specifies
and K2 as R6 states, and logs every call it receives. "The stub's log" means that log.

### Lookup

- [ ] AC1 (R1, R2). For a merged single-pr run, the lookup exits 0 and prints JSON with the
      record root's workspace and session name, the `run_id`, `complete: true`, and a PR
      list holding exactly the home PR, with state `merged` for a run that merged it and
      `ready` for one that stopped at a ready PR.
- [ ] AC2 (R2). For a coordinated run with two node PRs in two repositories, one follow-up
      PR and the coordination PR, the lookup from each of the four lists exactly those four.
- [ ] AC3 (R2, R7). For a multi-pr plan with three item PRs, the lookup from the second
      item's PR, run after the third merged, returns the plan-level root and lists all three.
- [ ] AC3a (R7). Two item runs of one multi-pr plan reaching the plan-level root at the
      same moment against the stub leave one root holding both items' entries.
- [ ] AC4 (R1). The lookup exits 3 for a PR with no index entry, 2 when the stub fails the
      store read, and 64 for `owner` without a repository, for a PR number of `0` and for a
      non-numeric one.
- [ ] AC5 (R3). Run from a new directory with no local copy, the lookup returns the same JSON
      as from the source workspace, and the stub's log shows no import, no migration marker
      and no write call against any session.
- [ ] AC6 (R4). After a second run of the same topic moved the first aside as
      `execute-<topic>_r1`, the lookup for the first run's PR returns `execute-<topic>_r1` and
      for the second run's PR returns `execute-<topic>`.
- [ ] AC7 (R4). When an index entry names a session whose PR list doesn't include the PR, the
      lookup doesn't return that session and exits 3.
- [ ] AC8 (R4). For a PR the second run adopted from the first, the lookup returns the second
      run and lists the first among the others.
- [ ] AC9 (R1). With a stub `gh` that fails every call, AC1 still passes.
- [ ] AC10 (R5, R31). When one step session is gone from the stub's store, the lookup exits 0
      with `complete: false` and a `missing` list naming that step. When the record root is
      gone, it exits 0 with `complete: false`, `missing` naming the root and no PRs.

### Record contents

- [ ] AC11 (R8). For a three-step single-pr run and a two-node coordinated run, the record
      holds for each step, step 1 included, the PLAN's full text, its commit SHA and the
      step's entry; a PLAN commit between steps 1 and 2 shows two different SHAs and texts.
      The same holds for a multi-pr item's step.
- [ ] AC12 (R9). From the record root, a reader gets each step session's name, and from it
      reads `summary.md`, `verification_results.json` and `review_results.json`, for
      single-pr and coordinated children alike, from a workspace with no local lineage.
- [ ] AC13 (R10). A run where step 2 marks a criterion deviated, step 3 has an approved
      deferral, step 4 goes back to analysis and step 5's entry is rewritten before it runs
      holds four departures, one per step, each with step id, kind, what changed and a
      non-empty why.
- [ ] AC14 (R11). A run with an agent decision and a human-approved deferral holds two
      decisions with actors `agent:<name>` and `person`.

### Keeping the record

- [ ] AC15 (R12). At a single-pr run's ready-PR terminal, the stub's log shows one pin call
      for the record root, one per step session and one per index session, after the run's
      last child tick.
- [ ] AC16 (R12). A coordinated run's terminal pins its root, every step session of every
      node, and one index session per node, follow-up and coordination PR.
- [ ] AC17 (R12). In a multi-pr plan, the second item's terminal pins its own step and index
      sessions and the plan-level root, and the first item's pins are unchanged.
- [ ] AC18 (R13, R30). Every pin reason matches the template, holds no control character and
      is at most 500 characters. A topic of 600 characters yields a 500-character reason, and
      a plan title holding a newline and a URL shows up in no reason, index entry or
      reference.
- [ ] AC19 (R14). The run's superseded step attempt and the scoping chain's sessions carry no
      pin, and a stub prune past retention removes them while keeping every pinned session
      with `kept_by_pin: true`.
- [ ] AC20 (R15). No shirabe file calls `koto session unpin` or defines a retention period or
      keep rule (a structure test checks both), and
      `references/koto-session-retention.md` names the record root, step and index
      sessions as what shirabe pins and names both release routes.
- [ ] AC21 (R16). When the stub refuses one pin with exit 3, the run still reaches its
      ready-PR terminal, its result carries `record: unpinned` naming the session and
      `pin_not_pushed`, and the next invocation pins it. The same holds for exit 2.
- [ ] AC22 (R17). With the stub reporting a version below the floor constant, or with the
      constant unset, the stub's log shows no pin call and the result carries
      `record: unpinned`; at the floor, AC15 passes.
- [ ] AC23 (R18). A structure test finds every `koto session cleanup` and
      `koto cancel --cleanup` instruction under `skills/` (outside `skills/coordinate/`)
      and `references/`, and fails unless its paragraph contains the word "pinned".

### Pull request content

- [ ] AC24 (R19). Under omit, tests over each writer show that no title, body, comment or
      squash message from a single-pr, coordinated or multi-pr run holds `shirabe-run`, a
      session name, a run line, a PR index, a merge-order block or a workspace path.
- [ ] AC25 (R20). Under omit, with two runs of one topic under one login on one branch, the
      ownership lookup returns each run's own PR and treats the other's as foreign.
- [ ] AC26 (R21). Under `include`, a new PR's Part 2 holds the session reference for a
      single-pr, a coordinated node and coordination PR and a multi-pr item PR, and no
      title or Part 1 holds it. A header value of `yes`, and a reader that exits 1, both
      write no reference.
- [ ] AC27 (R22). An invocation opened under `include` records `include` in its session.
      When the header changes to `omit` mid-invocation, its later writes still carry the
      reference. A resumed invocation opened after the change writes none, and leaves a body
      it rewrites without one.
- [ ] AC28 (R23). `README.md`'s PR content section states the checkout limit, and an
      invocation opened outside a checkout records `omit`.

### Lifecycle documentation

- [ ] AC29 (R24, R25). Each file in R24 contains the word "deleted" in its lifecycle text, the
      check name `L01`, the phrase "multi-pr", and the R1 command's name. A negative grep finds
      neither "stays in `docs/plans/` through every state" nor "A completed roadmap is a
      historical record" anywhere in them.
- [ ] AC30 (R26). `references/koto-session-retention.md` contains `retention.keep`,
      `koto session prune`, `koto workspace prune`, `_r<N>` and `koto session pin`.

### Constraints

- [ ] AC31 (R27). The change's diff touches no file under `skills/coordinate/`.
- [ ] AC32 (R28). Every new script passes `scripts/check-bash-floor.sh`.
- [ ] AC33 (R29). For a coordinated run with four PRs and five steps, the stub counts at most
      11 reads for R1 and R2. With one moved-aside predecessor it counts at most 12.
- [ ] AC34 (R6). The stub implements only K1 and K2 plus today's session, context and decision
      commands, and every test above passes against it.

## Out of Scope

- **Building or changing koto's session pin.** Its contract is koto's (koto#441, specified in
  koto#444). This feature states its need against it and waits on it to ship.
- **Building K2 inside shirabe.** Workspace-independent reach is koto's to build, as its own
  step. shirabe doesn't work around koto's bucket layout.
- **Runs that finished before this lands.** Their sessions may already be gone, and nothing
  here reconstructs them.
- **A team whose record isn't the cloud session store.** On the local backend the record lives
  on one host. How such a team keeps the record, and how a reader without the store's
  credentials reaches it, are named limits, not solved here.
- **The decision-authority display.** "Who" is the recorded actor until that exists.
- **A checkout-free source for the PR content switch.** That's #1130's subject. This work
  builds on the existing reader and names its limit.
- **Anything under `skills/coordinate/`.** Another effort is renaming scripts there.

## Known Limitations

- Pinning at the ready-PR terminal keeps the record of a PR that's later closed unmerged. Those
  sessions stay pinned until someone releases them; `koto session list --pinned` finds them.
- Between the moment a run writes an index entry and its qualifying terminal, its sessions
  are kept only by koto's ordinary retention. A run abandoned in that window may lose its
  record after `retention.keep`, and the lookup then reports a partial record or none.
- The pin's keep holds per workspace path, as koto's pin design states, and a reader needs
  the store's credentials.
- Under omit, a coordinated run keeps its record only in the session. Recovering a lost
  coordinated record from the coordination PR's body needs `include`.
- The end-to-end walkthrough from a fresh workspace waits on koto shipping K1 and K2. Until
  then shirabe's side is proved against the stub only.

## Decisions and Trade-offs

- **The lookup is shirabe's, over an index in the store (the BRIEF's first open question).**
  The alternatives were the PR body (ruled out by the default), the head branch (fails for
  adopted branches, coordinated node branches and multi-pr), the PLAN path in the merged diff
  (missing when the PLAN was added and deleted on one branch) and a koto-side search (koto has
  no key index, and adding one is koto's design to make). An index keyed by repository and PR
  number is the only candidate that works in all three modes. shirabe owns writing and reading
  it. The address problem it runs into is stated as K2, a koto requirement, rather than
  worked around inside shirabe with a fixed absolute path that differs across operating
  systems.
- **Every removal is covered by the pin as specified (the BRIEF's second open question).**
  The pin's PRD keeps a pinned session through the terminal tick, the parent sweep, the
  same-name replace, both prunes and subtree removal, and refuses cleanup and cancel
  `--cleanup`. A pinned child stays readable after its parent goes. The one gap is a batch
  child koto respawns inside a live run, and shirabe avoids it by pinning only after the run's
  last child tick. So no path becomes a parallel shirabe rule.
- **Pin at the qualifying terminal, not at merge.** `/execute` without `--merge` stops at a
  ready PR and a person merges later, when no shirabe run is present to observe it. Pinning at
  merge would leave most records unpinned. The cost is the first known limitation.
- **Read the switch at each invocation's opener.** A per-write read flips mid-run when a step
  runs with no checkout. A read only at the run's first open would let a resumed run keep
  writing after the switch was turned off. Reading at each opener satisfies "a run started
  after the option is turned off writes none", resumed runs included.
- **Drop the hidden run marker.** It's workflow content in the PR by default. Keeping it as a
  named exception would contradict R19, so ownership moves to the index (R20).
- **The plan's record is the run's own session, not a copy.** Copying evidence into a separate
  record session at the end would duplicate the proof and leave two accounts that can drift.
- **A multi-pr plan gets a plan-level root at the K2 address.** Its item runs happen on
  different hosts and instances, so no item's own session can be the root every other item
  reaches.

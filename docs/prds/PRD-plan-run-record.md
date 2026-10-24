---
schema: prd/v1
status: Draft
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

Draft

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

## Goals

- A reader with shirabe, koto and access to the cloud session store gives only a PR's
  repository and number. They reach the session that ran its plan and every PR the plan
  produced, from any workspace, weeks after the run's host and instance are gone.
- That session holds the plan as each step began, each step's proof, each recorded
  departure against its step, and each decision with its actor.
- A session holding a merged plan's evidence survives every removal koto applies on every
  host, and the removal says why. Finished sessions holding no such evidence go as today.
- PRs carry no koto, shirabe or niwa content by default. A repository that opts in gets a
  session reference, and a run started after the option is turned off writes none.
- shirabe's documentation states one lifecycle for PLAN and ROADMAP and sends a later reader
  to the run's session.

## User Stories

- **Following a merged PR back to its run.** As a reviewer in a fresh workspace weeks after
  a single-pr plan merged, I want to give the PR's repository and number and get the session
  that ran the plan and its PR list, so that I can read the step that puzzles me: the plan as
  that step began, its proof, the departure recorded against it and who decided it.
- **Pruning on a second host.** As an operator on a host sharing the cloud store, I want a
  prune of finished sessions to keep a merged plan's root and step sessions, naming the pin
  and its reason, and remove the run's sessions that hold no evidence, so that I never have
  to look anything up first.
- **A multi-pr plan's PRs lead to one record.** As a reader starting from the second of a
  multi-pr plan's three PRs, I want to reach the plan's record and from it all three PRs,
  including one that merged after mine, so that the plan mode doesn't decide whether a record
  exists.
- **Turning the session reference on and off.** As a maintainer, I want to turn on a session
  reference in my repository's PRs through workspace config, and have a run started after I
  turn it off write none, so that the default stays clean and the switch means what it says.
- **Reading the lifecycle.** As a contributor looking for a merged plan that's no longer in
  `docs/plans/`, I want the plan format reference, the planning skill and the completion step
  to say the PLAN was deleted and to name the lookup that finds its run, so that I'm not sent
  looking for a file.
- **Releasing a record.** As a maintainer who no longer needs a merged plan's record, I want
  to know which sessions shirabe pinned and how to release them, so that the next prune
  reclaims them.

## Requirements

### The lookup

- **R1. PR to record.** A shirabe command takes a repository (`owner/repo`) and a PR number.
  For a PR a plan run opened or adopted, it prints the address of the plan's record root (the
  session's workspace and name) and exits 0. For any other PR it says there's no record and
  exits with a distinct code. A read failure exits with a third code. It never reads the PR's
  title, body, comments or commits.
- **R2. Record to every PR.** From the record root, the same tool lists every PR that carried
  the plan out, as repository and number, none missing and none extra. For single-pr that's
  the home PR. For coordinated it's each node PR, each follow-up PR and the coordination PR.
  For multi-pr it's each item's PR, including items that ran after the PR the reader started
  from.
- **R3. Any workspace, after the instance is gone.** R1 and R2 work from a workspace at any
  path with no local copy of the run's sessions, using only the cloud store and GitHub. Every
  read leaves the record where it is: no import, no marker, no write into a run session.
- **R4. The right run.** When a plan's topic ran more than once, R1 returns the run that
  opened or adopted the given PR, including a run koto moved aside under a new name at a
  later same-name replace. The tool confirms the hit by the PR appearing in the record, never
  by the session name alone.
- **R5. Who owns the lookup.** The lookup is shirabe's: a shirabe script over koto's session
  and context commands. Where koto offers no way to do a part of it, that part is a stated
  requirement on koto, delivered as a separate step in koto, and shirabe's side is built and
  tested against a stub koto that meets it.

### What the record holds

- **R6. A record root for every plan mode.** Every plan run has one record root session.
  For single-pr and coordinated it's the run's `execute-<topic>` session. A multi-pr plan
  gets a plan-level record root that each item's run joins. Reading a multi-pr plan's
  record never depends on a session that only one item's run could reach.
- **R7. The plan as each step began.** Before each step is handed to its `/work-on` run,
  step 1 included and in every mode, the record holds the PLAN as committed at that moment
  (its text, or the commit it came from plus the text) and the step's own entry, keyed by
  the step's id.
- **R8. Each step's proof.** For each step, the record names the session that holds its
  proof, and that session holds it: the step's summary, verification results, review
  verdicts and, for the step that merged, the merge outcome. A reader gets from the root to
  each step's session by name, without koto lineage or local links.
- **R9. Departures against their step.** Every departure the run records is kept against the
  step it changed, by step id, with what changed and why. That covers an acceptance criterion
  marked deviated, an approved deferral, a scope change that sent the step back to analysis,
  and a later step's entry rewritten before it ran.
- **R10. Decisions with their actor.** Every decision the run records names who made it:
  the actor shirabe recorded, an agent session or a person at an approval gate. Until a
  separate decision-authority display exists, "who" is that recorded actor.

### Keeping the record

- **R11. Pinned through koto's session pin.** When a run reaches a terminal that leaves its
  PR ready or merged (for multi-pr, each item's run at its own such terminal), shirabe pins,
  through koto's session pin, the record root, each step's final `/work-on` session and every
  index session the lookup reads. The pin's reason names the plan's topic and the PR, in a
  fixed template that passes koto's reason rules (at most 500 characters, no control
  characters) and holds no free text from the plan.
- **R12. Only evidence is pinned.** shirabe pins nothing else. A superseded attempt at a
  step, a session a pause replaced, the scoping chain's sessions, and any other finished
  session from the same run that holds no merged plan's evidence are removed as they are
  today.
- **R13. Retention is koto's.** shirabe adds no retention rule of its own and never unpins.
  A pin comes off only as koto allows: by hand, or from an agent session whose start was
  handed koto's `release-pin` authority. shirabe's documentation says which sessions it pins
  and how to release them. Nothing in this feature requires a change to the pin's design.
- **R14. A failed pin is visible.** A pin koto refuses or can't confirm in the bucket doesn't
  fail the run's PR, and it isn't silent. The run's result names each session left unpinned
  and why, and the next invocation on the topic tries the pin again.
- **R15. Before the pin ships.** shirabe raises its koto floor to the first koto release that
  honours pins in full, or, until that release exists, pins only when the installed koto is at
  or above it, and otherwise records that the run's sessions are unpinned. Its tests use a
  stub koto that behaves as the pin's PRD specifies.
- **R16. Pinned sessions in shirabe's own recovery.** No shirabe instruction tells an agent
  to run `koto session cleanup` or `koto cancel --cleanup` on a pinned session. Where one
  does today, it says what to do with a pinned session instead.

### Pull request content

- **R17. Nothing by default.** With no integration opted in, no PR a shirabe run opens or
  edits carries a session reference, run state, run marker, run lines, PR index or any other
  entry from koto, shirabe or niwa. That covers the title, description, comments and squash
  commit message, and every plan mode, coordinated node and coordination PRs included. The
  hidden `<!-- shirabe-run: <id> -->` line is among what's left out.
- **R18. Ownership without the marker.** With the marker gone, two runs sharing a login and a
  branch are still told apart. The run that opened a PR is recognized from the store-side
  record, not from the PR's text.
- **R19. The opt-in.** A repository opts in through `scripts/pr-workflow-content.sh`, the
  existing reader, whose exit-0 `include` is the only value that counts. Under `include`,
  each PR the run opens gets a session reference in the body's second part. It names the
  record root and the run, enough for the R1 tool to confirm it. It never goes in the title
  or the squash message.
- **R20. Read once per invocation.** Each invocation of a run reads the switch once, at its
  open, from the checkout it opens in, and records the value in its session. Every PR write
  in that invocation uses the recorded value. A run started after the option is turned off
  writes no session reference. A PR written earlier under `include` keeps what it had.
- **R21. The checkout limit.** The reader works only from a checkout, so a run opened without
  one reads `omit`. That limit is named in the documentation. A checkout-free source for the
  switch is not part of this work.

### The lifecycle documentation

- **R22. One lifecycle.** On the default branch, the plan format reference
  (`skills/plan/references/plan-format.md`), the planning skill (`skills/plan/SKILL.md`) and
  the completion step (`skills/work-on/scripts/run-cascade.sh` and the reference that
  documents it) all state the same lifecycle. A PLAN and a ROADMAP are deleted when their
  work finishes, and a committed one at a terminal state fails CI. Only a multi-pr PLAN
  reaches the default branch, where it stays while its PRs land. The roadmap format
  reference says the same for a ROADMAP.
- **R23. Sent to the session.** Each of those documents sends a reader looking for a finished
  plan to the run's session through the R1 tool, not to the plan.
- **R24. The retention reference.** `references/koto-session-retention.md` describes the koto
  behaviour shirabe now relies on: hierarchy retention, `retention.keep`, the prunes, the
  same-name replace's move-aside, and the pin.

### Constraints

- **R25. Nothing under `skills/coordinate/` changes.**
- **R26. Bash 3.2, no new dependencies.** New scripts hold to shirabe's bash floor and need
  only bash, `jq`, `gh` and koto.
- **R27. Bounded lookup cost.** R1 and R2 make a bounded number of koto reads: a fixed number
  per PR in the plan, plus at most one per moved-aside predecessor it checks. Nothing scans
  the whole store.
- **R28. Public-safe content.** Pin reasons, index entries and the opt-in reference hold no
  secrets and no free text from the plan. A workspace path appears only in the store, never in
  PR text under `omit`.

## Acceptance Criteria

### Lookup

- [ ] AC1 (R1, R2). For a merged single-pr run, the lookup given its repository and PR
      number exits 0, prints the record root's workspace and session name, and lists exactly
      that one PR.
- [ ] AC2 (R2). For a coordinated run with two node PRs, one follow-up and a coordination
      PR, the lookup from any one of the four lists exactly those four, none missing and none
      extra.
- [ ] AC3 (R2, R6). For a multi-pr plan with three item PRs, the lookup from the second
      item's PR, run after the third merged, reaches the plan's record root and lists all
      three.
- [ ] AC4 (R1). For a PR no plan run opened, the lookup exits with the "no record" code and
      prints that there's no record. For a store read that fails, it exits with the
      read-failure code.
- [ ] AC5 (R3). Run from a new directory on a host that never held the sessions, against a
      stub koto whose store has the run's sessions only under the source workspace, the
      lookup returns the same answer as from the source workspace. Afterwards the stub's log
      shows no import, no write and no marker.
- [ ] AC6 (R4). After a second run of the same topic moved the first aside as
      `execute-<topic>_r1`, the lookup for the first run's PR returns `execute-<topic>_r1`, and
      the lookup for the second run's PR returns `execute-<topic>`.
- [ ] AC7 (R1, R17). With a stub `gh` that fails any read of a PR's title, body, comments or
      commits, AC1 still passes.

### Record contents

- [ ] AC8 (R7). For a three-step single-pr run and a two-node coordinated run, the record
      holds, for each step including the first, the PLAN text as committed when the step was
      handed off and the step's entry, and changing the PLAN between steps shows two
      different texts for steps 1 and 2.
- [ ] AC9 (R8). From the record root, a reader names each step's final session, and reading
      it yields the step's summary and verification results. That holds for single-pr
      children and coordinated children alike, from a workspace with no local lineage.
- [ ] AC10 (R9). A run where step 2 marks a criterion deviated and step 3's entry is rewritten
      before it runs shows two departures, one against step 2 and one against step 3, each
      with what changed and why.
- [ ] AC11 (R10). A run with an agent decision and a human-approved deferral shows two
      decisions, each naming its actor, one an agent session and one a person at the
      approval gate.

### Keeping the record

- [ ] AC12 (R11). After a single-pr run reaches its ready-PR terminal against a stub koto,
      the stub records pins on the root, each step's final session and each index session,
      each with a reason that names the topic and the PR and passes koto's reason rules.
- [ ] AC13 (R12). In the same run, a step attempt that was superseded and the scoping chain's
      sessions carry no pin, and a stub prune past retention removes them while keeping
      every pinned session with `kept_by_pin: true`.
- [ ] AC14 (R13). No shirabe script or skill instruction calls `koto session unpin`, and
      no shirabe file defines a retention period or a keep rule of its own (a structure
      test checks both).
- [ ] AC15 (R14). When the stub refuses one pin with exit 3, the run still reaches its
      ready-PR terminal, its result names the unpinned session and the reason, and a second
      invocation on the topic pins it.
- [ ] AC16 (R15). With a koto below the pin floor, the run pins nothing, makes no
      `koto session pin` call, and its result says the sessions are unpinned.
- [ ] AC17 (R16). A grep of `skills/` and `references/` (outside `skills/coordinate/`) finds
      no instruction to run `koto session cleanup` or `koto cancel --cleanup` that doesn't
      also say what to do with a pinned session.

### Pull request content

- [ ] AC18 (R17). Under `omit`, the title, body and squash message of every PR a single-pr,
      coordinated and multi-pr run opens contain no `shirabe-run`, no session name, no run
      line and no PR index, in tests over each writer.
- [ ] AC19 (R18). Under `omit`, two runs of one topic under one login on one branch: the
      ownership lookup returns each run's own PR and treats the other run's PR as foreign.
- [ ] AC20 (R19). Under `include`, a new PR's body carries the session reference in its second
      part, the title and squash message don't, and the R1 tool confirms the reference names
      the record root that lists the PR.
- [ ] AC21 (R20). A run opened under `include` that's resumed after the header changes to
      `omit` writes no session reference in any PR it opens or edits after the resume, and a
      PR opened before the change keeps its reference.
- [ ] AC22 (R21). The PR content documentation names the checkout limit, and a run opened
      outside a checkout records `omit`.

### Lifecycle documentation

- [ ] AC23 (R22). The four documents in R22 each state that a PLAN and a ROADMAP are deleted
      when their work finishes, that a committed one at a terminal state fails CI, and that
      only a multi-pr PLAN stays on the default branch while its PRs land. None of them says
      a PLAN stays in `docs/plans/` through every state or that a Done roadmap is kept.
- [ ] AC24 (R23). Each of those documents names the R1 tool as the way to a finished plan's
      run.
- [ ] AC25 (R24). `references/koto-session-retention.md` describes hierarchy retention,
      `retention.keep`, the prunes, the move-aside and the pin.

### Constraints

- [ ] AC26 (R25). The change's diff touches no file under `skills/coordinate/`.
- [ ] AC27 (R26). Every new script passes `scripts/check-bash-floor.sh`.
- [ ] AC28 (R27). For a coordinated run with four PRs, the lookup makes no more than a fixed,
      documented number of koto reads, counted by the stub.
- [ ] AC29 (R28). Pin reasons, index entries and the opt-in reference are built from fixed
      templates over the topic, repository, PR number, session name and run id. A test feeding
      a plan title with a newline and a URL shows neither in any of them.

## Out of Scope

- **Building or changing koto's session pin.** Its contract is koto's (koto#441, specified in
  koto#444). This feature states its need against it and waits on it to ship.
- **Runs that finished before this lands.** Their sessions may already be gone, and nothing
  here reconstructs them.
- **A team whose record isn't the cloud session store.** On the local backend the record lives
  on one host. How a team without the cloud store keeps the record, and how a reader without
  the store's credentials reaches it, are named limits, not solved here.
- **The decision-authority display.** "Who" is the recorded actor until that exists.
- **A checkout-free source for the PR content switch.** That's #1130's subject. This work
  builds on the existing reader and names its limit.
- **Anything under `skills/coordinate/`.** Another effort is renaming scripts there.

## Known Limitations

- Pinning at the ready-PR terminal keeps the record of a PR that's later closed unmerged. Those
  sessions stay pinned until someone releases them; `koto session list --pinned` finds them.
- A pin on a batch child can be lost if koto respawns that child inside a live run, as the pin's
  design says. shirabe pins children only once their run has ended.
- The record's reach is bounded by koto: the pin's keep holds per workspace path, and a reader
  needs the store's credentials.
- Under `omit`, a coordinated run keeps its record only in the session. Recovering a lost
  coordinated record from the coordination PR's body needs `include`.

## Decisions and Trade-offs

- **The lookup is shirabe's, over an index in the store (the BRIEF's first open question).**
  The alternatives were the PR body (ruled out by the default), the head branch (fails for
  adopted branches, coordinated node branches and multi-pr), the PLAN path in the merged diff
  (missing when the PLAN was added and deleted on one branch) and a koto-side search (koto has
  no key index, and adding one is koto's design to make). An index keyed by repository and PR
  number is the only candidate that works in all three modes. shirabe owns writing and reading
  it. The address problem it runs into is stated as a koto requirement (R5) rather than worked
  around inside shirabe.
- **Every removal is covered by the pin as specified (the BRIEF's second open question).**
  The pin's PRD keeps a pinned session through the terminal tick, the parent sweep, the
  same-name replace, both prunes and subtree removal, and refuses cleanup and cancel
  `--cleanup`. A pinned child stays readable after its parent goes. The one gap is a batch
  child koto respawns inside a live run, and shirabe avoids it by pinning only after the run
  ends. So no path becomes a parallel shirabe rule.
- **Pin at the ready-PR terminal, not at merge.** `/execute` without `--merge` stops at a
  ready PR and a person merges later, when no shirabe run is present to observe it. Pinning at
  merge would leave most records unpinned. The cost is the known limitation above.
- **Read the switch at each invocation's open.** A per-write read flips mid-run when a step runs
  with no checkout. A read only at the run's first open would let a resumed run keep writing
  after the switch was turned off. Reading at each open satisfies "a run started after the
  option is turned off writes none", and resumed runs too.
- **Drop the hidden run marker under `omit`.** It's shirabe content in the PR by default. Keeping
  it as a named exception would contradict R17, so ownership moves to the store-side record
  (R18).
- **The plan's record is the run's own session, not a copy.** Copying evidence into a separate
  record session at the end would duplicate the proof and leave two accounts that can drift.

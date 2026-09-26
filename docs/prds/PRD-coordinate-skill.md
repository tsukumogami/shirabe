---
schema: prd/v1
status: Accepted
problem: |
  shirabe carries the task rung (`/work-on`) and the story rung
  (`/deliver`) as skills, but the session above them, a coordinator that
  drives a roadmap or a standing discipline by handing work to other
  sessions, is started from a prose description of the job every time.
  Those descriptions differ from one start to the next, accrete rules
  that outlive the defects they worked around, and repeat instructions
  the toolchain already carries out.
goals: |
  A coordinator session is started with a scope and the decisions the
  human has already made, and nothing else. The skill carries the loop in
  order, its failure branch, the vocabulary, the things a coordinator
  never does, and the record's shape, so any coordinator started through
  it runs the same job and leaves a record the next one can read.
absorbed:
  - docs/briefs/BRIEF-coordinate-skill.md
---

# PRD: coordinate-skill

## Status

Accepted

Absorbed [BRIEF-coordinate-skill](docs/briefs/BRIEF-coordinate-skill.md); carried in Absorbed Brief.

## Absorbed Brief

The feature frames one gap: shirabe's delegation ladder encodes the task
rung and the story rung as skills, but the session above them, the
coordinator that hands work to other sessions and keeps track of it, is
started from a prose description of the job every time, and those
descriptions drift, accrete, and repeat what the toolchain already does.

The problem it named is this document's Problem Statement. The outcome it
asked for is that a person starts a coordinator with a scope and their
decisions and nothing else, gets back only claims the coordinator verified
and only the steps the workspace reserves for a person, and can read the
coordinator's record on GitHub in the same words the skill uses; a
restarted coordinator re-checks what it inherited before acting. Those are
this document's Goals.

Four journeys grounded it and survive as User Stories 1 through 4: a
maintainer starting a roadmap coordinator with no description of the job; a
maintainer starting a discipline rotation that opens its own record and
closes with a dated handoff; a maintainer restarting a crashed coordinator
that must reconcile and confirm an unconfirmed merge before acting; and a
maintainer receiving a worker's "green" only after the coordinator has
verified it, with merges handed over as an ordered table or made directly
depending on what the workspace permits. Its scope boundary is carried as
the Requirements and Out of Scope: the loop and its failure branch, the
bound on workers, what a coordinator never does, the vocabulary, the
record's shape and template, the brief template and verification
checklist, and the two invocations; and, excluded, record tooling,
mechanised reconcile, dispatch-path tooling, liveness and double-held
checks, load accounting, changes to koto or the workspace manager, fixing
#395 and #396, and any rule about who may message a coordinator.

## Problem Statement

A coordinator is a long-running session that drives an effort bigger than
one feature (a roadmap, or a standing area with no end date such as CI
health, releases or support) by handing units of work to other sessions
and keeping track of them. It decides what happens next, writes the
context a worker needs to start cold, checks what comes back, and lands
finished work or puts it in front of a person. It implements nothing.

shirabe has a skill for the rung below it, `/deliver`, and for the rung
below that, `/work-on`, but none for the coordinator. Whoever starts one
writes the job out in prose. The people running coordinators today
describe the same loop in the same order, which says the job has a shape
that can be written down once. Written out fresh each time, it drifts.
A long-lived prose protocol grows with each incident and keeps rules
whose reason has gone away, and a brief can end up telling a session to
do something the workspace manager has already done for it. The
coordinator's context is the scarcest in the workspace because it runs
longest, and it is the session that spends that context being told its
job.

## Goals

- A coordinator started through the skill needs no prose description of
  the job beyond its scope and the human's decisions.
- Every coordinator runs the same loop and uses the same words for what
  the loop handles, so a successor, a sibling coordinator or the human
  can read one coordinator's record without a glossary.
- The record holds only what GitHub can't recompute, so it stays small
  and a restarted coordinator re-checks everything else instead of
  trusting it.
- The skill takes each finishing step exactly as far as the workspace
  permits and no further, and carries no permission rule of its own.

## User Stories

- As a maintainer with an Active roadmap, I want to start a coordinator
  with the roadmap's path and the decisions I've already taken, so that
  its features get built without me re-explaining how to coordinate.
- As a maintainer who owns a standing area such as CI health, I want to
  start a rotation of a coordinator on that discipline for a length I
  choose, so that the area is watched for that period and the next
  rotation inherits a dated handoff instead of a conversation.
- As a maintainer whose coordinator crashed with workers in flight, I
  want a new session on the same scope to reconcile before acting, so
  that it neither redoes nor skips work and confirms any unconfirmed
  merge before deciding about it.
- As a maintainer receiving a coordinator's report, I want to know what
  it verified and what it didn't, so that I can act on "green" without
  re-checking every pull request myself.
- As a maintainer who changes my mind mid-effort, I want to send the
  running coordinator a new decision and have it take effect on its next
  turn of the loop, so that I don't have to restart it to steer it.
- As a maintainer ending a rotation or retiring a worker, I want the
  coordinator to list what the session holds that exists nowhere else
  before anything is torn down, so that no worker's output is silently
  lost.
- As a coordinator whose effort contains a sub-effort big enough to need
  its own coordinator, I want to start one with a brief and read its
  record the way a person would, so that the same loop runs at every
  level.

## Requirements

### Invocation and description

- **R1.** The skill is `skills/coordinate/` and is invoked as
  `/shirabe:coordinate <roadmap-path>` for a roadmap scope or
  `/shirabe:coordinate --discipline <name>` for a discipline rotation.
  SKILL.md documents both forms. Any further text the invoker supplies
  is read as the human's decisions and the effort's constraints (for
  example "feature 3 waits for the release" or "rotation length: 3
  days"), never as instructions for how to coordinate.
- **R2.** SKILL.md's `description` follows the pattern of
  `skills/decision/SKILL.md` and `skills/deliver/SKILL.md`: what the
  skill does, a "Use it when" clause with concrete trigger phrases, and
  a "Do NOT use it" clause that names `/deliver` for a single feature
  and `/work-on` for a single issue.
- **R3.** A roadmap scope must name a roadmap whose status is Active.
  When the path is missing or names a roadmap in any other status, the
  coordinator reports that and stops without dispatching anything.
- **R4.** A discipline rotation's length is one of the human's
  decisions. When the invoker gives none, the rotation lasts seven days
  from its start. The rotation ends when that length runs out or when
  the human ends it, whichever comes first.

### The loop

- **R5.** SKILL.md carries the loop as seven ordered steps, in this
  order: reconcile before acting; pick the next unblocked unit of work
  and its entry point; write one brief per worker and dispatch it;
  wait without polling; verify before relaying or acting; land ready
  work or put it in front of the human; update the record and go round
  again.
- **R6.** A full reconcile runs on the first turn after every start and
  every restart; on later turns the step re-checks only the holdings the
  coordinator is about to act on. It
  treats every claim in the record as a snapshot dated when it was
  written. It re-checks each claim against GitHub (pull request state
  and head sha, branch existence, issue state, CI results) and against
  the host (whether each dispatched session or instance still exists,
  and what unique material it holds). It reports three things: what
  changed since the record was written, what the coordinator holds, and
  every open deferral. In this version reconcile is a procedure the
  skill walks the session through, not a tool.
- **R7.** The pick step maps each kind of unit to its entry point:
  `/shirabe:deliver` for a roadmap feature that has to be worked out and
  built; `/shirabe:work-on` for an issue that is already specified;
  `/shirabe:explore` for an open question; `/shirabe:decision` for a
  contested choice; and `/shirabe:coordinate` for a sub-effort that is
  itself a roadmap or a discipline, only when the human's decisions
  allow a nested coordinator. The mapping is stated as a detail of the
  step, so a change to those skills doesn't change the loop.
- **R8.** The dispatch step writes one brief per worker, dispatches it
  through the workspace manager, and records the dispatch as a holding
  in the record before any other action, because a dispatched session
  with no pull request yet is invisible to GitHub.
- **R9.** The wait step states that workers report by message and
  background tasks notify the coordinator, and forbids polling GitHub or
  the host in a loop. A worker counts as quiet when neither a message
  nor a push has arrived from it for 30 minutes. The coordinator checks
  on a quiet worker at most once per 30 minutes by default, by reading
  its branch and pull request on GitHub and its session on the host.
  The human's decisions may set a different interval.
- **R10.** The verify step requires, before a worker's "done" or
  "green" is relayed or acted on, a read of: the pull request's head
  sha; each CI job's runner name and number of steps run (a job that
  ran nothing can still show green); the pull request's file list; and
  `git ls-remote` for the branch. A claim is re-derived at the moment it
  is repeated, not reused from an earlier read. Every report the
  coordinator makes names what it verified and what it didn't.
- **R11.** The land step takes each finishing step as far as the
  workspace's declared permissions allow. Where the workspace denies a
  merge to the session, the coordinator hands the human a table of
  ready pull requests with their merge order and the reason for that
  order. Where the workspace permits the merge, the coordinator merges
  once it has verified the work. After any merge, it confirms the change
  on the default branch by reading the changed files there, not by
  trusting the merge event.
- **R12.** The update step writes the record after every dispatch,
  every verified report, every merge or attempted merge, every new
  deferral, and every reversal. It rewrites only the holdings,
  deferrals, side effects in flight and reversals, and never writes a
  fact GitHub can recompute.
- **R13.** The loop's failure branch covers three cases: a stalled or
  dead worker, red CI a worker can't clear, and a conflict after a
  sibling pull request merges. For each, the coordinator either
  re-dispatches with the same brief plus what was learned, or escalates
  to whoever dispatched it. A stalled worker is a quiet worker (R9)
  whose check shows no new push and no reply. The branch states that a bounced message is
  the only signal of a dead worker today, and that a session is never
  declared dead from a single read of the session roster, because a
  roster read just after an outage can't tell "gone" from "not back
  yet".
- **R14.** SKILL.md bounds work in flight at three active workers by
  default, one pull request each. An active worker is a dispatched
  session whose work is not yet merged or abandoned. The reason is
  stated: past three, CI throughput, host load and the coordinator's own
  verification capacity become the constraint. The human's decisions
  may set a different bound.
- **R15.** The coordinator dispatches anything inside its scope without
  asking. It proposes anything outside its scope to whoever dispatched
  it and doesn't act until that party answers.
- **R16.** A decision belongs to the human when it does any of the
  following: changes the effort's scope, reverses or extends a decision
  the human supplied, or needs a step the workspace reserves for a
  person. The coordinator asks each such decision once, with a
  recommendation, and doesn't ask for anything else. SKILL.md gives at
  least three worked examples: dispatching the next feature on an
  Active roadmap is not asked; dropping a feature from the roadmap is
  asked (a scope change); running a fourth worker when the human set the
  bound at three is asked (extending a supplied decision).
- **R17.** A new decision sent by whoever dispatched the coordinator
  while it runs takes effect at the start of the coordinator's next turn
  of the loop. When it reverses an earlier decision, the coordinator
  records the reversal and its reason.

### What a coordinator never does

- **R18.** SKILL.md states that the coordinator implements nothing. It
  writes its record and nothing else. Its own documents are edited by a
  worker or a local agent from a brief it writes, and it reviews the
  diff.
- **R19.** SKILL.md states the context discipline: the coordinator
  keeps its own context for judgment, delegates research and
  bookkeeping to local agents, and dispatches independent sessions for
  the work.
- **R20.** SKILL.md states that the coordinator takes each finishing
  step (a merge, a close, a teardown) exactly as far as the workspace's
  declared permissions allow, carries no permission rule of its own,
  and never asks the human for a step the workspace already permits.
- **R21.** SKILL.md states that before any teardown the coordinator
  lists the unique material held by the session or instance being torn
  down, and acts only on the sessions and instances it listed, never
  across the whole workspace.
- **R22.** SKILL.md states that a finding belonging to no issue and no
  pull request is filed as an issue before the worker that produced it
  is retired.
- **R23.** SKILL.md states that the coordinator reports up to whoever
  dispatched it, a person or another coordinator, and that the same
  loop runs at every level.
- **R24.** Nothing in the skill instructs a coordinator to scrutinise,
  authenticate, trust or distrust a message's sender. Sender identity
  is the harness's and the workspace's.

### Vocabulary

- **R25.** The skill defines each of these terms once, in one place,
  and doesn't redefine them elsewhere: coordinator, worker, brief,
  holding, deferral, reconcile, rotation, teardown (ending a worker's
  session or removing its instance), and unique material (commits on no
  remote ref that survives a squash merge, uncommitted changes, and
  files in a session's scratch space that no repository holds).

### The record

- **R26.** The record stores only what GitHub can't recompute: the
  holdings map (the sessions, branches and pull requests this
  coordinator dispatched, including sessions with no pull request yet),
  deferrals, side effects in flight (for example a merge attempted and
  never confirmed), and the reasoning behind reversals. Feature state is
  never stored; it's read from the roadmap and the pull requests.
- **R27.** The record lives on GitHub. For a roadmap scope it is the
  roadmap's Progress section for feature state plus a draft pull request
  whose body carries live holdings and deferrals and whose commits
  carry Progress updates; that pull request merges when the roadmap is
  done. For a discipline scope the record is a draft pull request opened
  when the rotation starts, which merges when the rotation ends with a
  dated handoff snapshot committed.
- **R28.** A deferral is something the successor disposes of (files it
  as an issue, closes it, or carries it forward with a reason) before
  its first dispatch.
- **R29.** The skill ships the record's template as a reference file.

### References shipped with the skill

- **R30.** `skills/coordinate/references/` contains at least four
  files: the loop, the record template, the worker brief template, and
  the verification checklist.
- **R31.** The worker brief template lists what a brief contains: the
  goal, the decisions the worker can't see, pointers to pushed
  artifacts, acceptance criteria, what's out of scope, and an
  instruction to report back to the coordinator by message using the
  coordinator's session name. It states that a worker's keep-alive is
  the workspace manager's to schedule at dispatch, so a brief never
  asks the worker to schedule one.
- **R32.** A section in SKILL.md or a reference says what this version
  leaves to later work: tooling for the record, a mechanised reconcile
  step, and tooling for the dispatch path.
- **R33.** The skill names issues #395 and #396 as known limitations
  and describes the fixed behaviour it depends on.

### Admission rule

- **R34.** The skill carries no rule whose justification would
  disappear once a filed defect is fixed. It states the invariant the
  defect breaks, and the defect stays filed. SKILL.md states this
  admission rule for future edits to the skill.

### Packaging

- **R35.** The skill has `SKILL.md`, `requires.tsv` and
  `evals/evals.json`, passes `scripts/skill-preflight.sh coordinate`,
  and passes every CI check that applies to a skill directory. The
  README's skills table lists it.
- **R36.** No committed artifact of this feature references a private
  repository, a private path or issue, a session or instance name, a
  job id, or a path in the workflow staging directory that is deleted
  before merge.
- **R37.** The skill is prose: it adds no koto template, no script, and
  no change to koto or to the workspace manager. If the design finds a
  step that only a workflow-engine gate can hold, the design defines
  the gate's size and records why prose couldn't hold the step.
- **R38.** `evals/evals.json` carries at least one scenario each for: a
  roadmap invocation whose extra text is decisions, a non-Active
  roadmap, a worker reporting green, a restart with an unconfirmed
  merge, a decision that belongs to the human, a new decision arriving
  mid-run, and a teardown request.

## Acceptance Criteria

Each criterion names the requirement it verifies.

**Packaging**

- [ ] (R30, R35) `skills/coordinate/` holds `SKILL.md`,
  `requires.tsv`, `evals/evals.json`, and a `references/` directory
  with files for the loop, the record template, the brief template and
  the verification checklist.
- [ ] (R35) `scripts/skill-preflight.sh coordinate` exits 0, and
  `scripts/check-skill-requires.sh`, `scripts/check-skill-injection.sh`
  and `scripts/check-evals-exist.sh` pass on the branch.
- [ ] (R35) `README.md`'s skills tables contain a `/coordinate` row.
- [ ] (R37) The pull request's diff adds or changes files only under
  `skills/coordinate/`, `README.md` and `docs/`; no file under
  `koto-templates/`, `skills/*/koto-templates/` or `scripts/` is added
  or changed.
- [ ] (R38) `evals/evals.json` has a scenario for each of the
  seven situations R38 names.
- [ ] (R36) `git grep -nE 'wip[/]'` on the branch before merge
  returns nothing.
- [ ] (R36) `git grep -n 'private/'` over the files the pull request
  adds returns nothing, and a reviewer reading those files finds no
  private repository name, session or instance name, or job id.
- [ ] Every CI job on the pull request is green, read job by job.

**Invocation and description**

- [ ] (R1) SKILL.md documents `/shirabe:coordinate <roadmap-path>` and
  `/shirabe:coordinate --discipline <name>`, and states that further
  invocation text is read as decisions and constraints.
- [ ] (R2) SKILL.md's `description` contains a "Use it when" clause
  and a "Do NOT use it" clause naming `/deliver` and `/work-on`.
- [ ] (R3) SKILL.md states that a missing or non-Active roadmap makes
  the coordinator report and stop without dispatching.
- [ ] (R4) SKILL.md states that rotation length is a human decision and
  that the default is seven days.

**The loop**

- [ ] (R5) SKILL.md lists the seven loop steps in the order R5 gives.
- [ ] (R6) The reconcile step names GitHub checks (pull request state
  and head sha, branches, issue state, CI) and host checks (session or
  instance existence, unique material), and a report of changes,
  holdings and open deferrals.
- [ ] (R7) The pick step lists all five entry points with the kind of
  unit each takes, and limits `/shirabe:coordinate` to when the human's
  decisions allow it.
- [ ] (R8) The dispatch step says to record the holding before any
  other action and gives the reason.
- [ ] (R9) The wait step forbids polling in a loop, defines a quiet
  worker as 30 minutes without a message or push, and sets the default
  check interval at 30 minutes.
- [ ] (R10) The verification checklist names head sha, each CI job's
  runner and step count, the file list and `git ls-remote`, and SKILL.md
  says every report names what was and wasn't verified.
- [ ] (R11) The land step describes the merge-order table for a denied
  merge, merging after verification where permitted, and reading the
  changed files on the default branch after a merge.
- [ ] (R12) The update step lists its five triggers and says it never
  writes a recomputable fact.
- [ ] (R13) The failure branch covers the three cases, each with
  re-dispatch or escalate, and states both the bounced-message signal
  and the single-roster-read rule.
- [ ] (R14) SKILL.md states a default bound of three active workers,
  defines an active worker, and gives the reason.
- [ ] (R15) SKILL.md says in-scope work is dispatched without asking
  and out-of-scope work is proposed to the dispatcher.
- [ ] (R16) SKILL.md lists the three conditions that make a decision
  the human's and gives the three worked examples.
- [ ] (R17) SKILL.md says a mid-run decision takes effect on the next
  turn and a reversal is recorded with its reason.

**Never does**

- [ ] (R18) SKILL.md says the coordinator implements nothing and has
  its own documents edited from a brief, reviewing the diff.
- [ ] (R19) SKILL.md says the coordinator delegates research and
  bookkeeping to local agents and dispatches sessions for the work.
- [ ] (R20) SKILL.md says finishing steps go exactly as far as the
  workspace permits, that the skill carries no permission rule, and
  that it never asks for a permitted step.
- [ ] (R21) SKILL.md says teardown is preceded by a list of unique
  material and acts only on listed sessions and instances.
- [ ] (R22) SKILL.md says a homeless finding is filed as an issue
  before its worker is retired.
- [ ] (R23) SKILL.md says the coordinator reports up to its dispatcher
  and the same loop runs at every level.
- [ ] (R24) `git grep -niE 'sender|authenticat|impersonat|spoof' -- skills/coordinate`
  returns no instruction about checking a message's sender.

**Vocabulary, record and references**

- [ ] (R25) Each of the nine terms has exactly one definition, in one
  glossary section of SKILL.md.
- [ ] (R26, R29) The record template has sections for holdings,
  deferrals, side effects in flight and reversals, and no section for
  feature state.
- [ ] (R27) SKILL.md or the record template states where the record
  lives for a roadmap scope and for a discipline scope, as R27 gives.
- [ ] (R28) SKILL.md states that the successor disposes of each
  deferral before its first dispatch, and lists the three ways.
- [ ] (R31) The brief template names goal, hidden decisions,
  pushed-artifact pointers, acceptance criteria, out of scope and
  report-back by message with the coordinator's session name, says the
  keep-alive is the workspace manager's to schedule, and contains no
  instruction for the worker to schedule one.
- [ ] (R32) A section names record tooling, mechanised reconcile and
  dispatch-path tooling as later work.
- [ ] (R33, R34) #395 and #396 appear only in a known-limitations
  section, and no sentence in the skill is conditioned on either issue
  staying open ("until", "for now", "as a workaround").
- [ ] (R34) SKILL.md states the admission rule.

## Out of Scope

- Tooling that writes, renders or gates the record; a later feature.
- A mechanised reconcile step; a later feature.
- Tooling for the dispatch path, including whether the workflow engine's
  leg attach carries a worker's result back; a later feature.
- Session liveness detection, a check for two coordinators holding the
  same effort, and accounting for the load a coordinator puts on other
  efforts.
- Any change to koto or to the workspace manager.
- Fixing #395 or #396.
- Required fields for negative findings, claim-provenance logs,
  rule-expiry machinery and guards on destructive reach.

## Decisions and Trade-offs

- **Where the record's feature state lives.** Feature state is read from
  the roadmap's per-feature status and the pull requests, not stored in
  the coordinator's pull request body. The alternative, a status column
  in the body, is what coordinated execution already refuses to trust
  (it recomputes merged, draft and checks live), and a copy of state
  that GitHub holds is the kind of fact that goes stale in a record.
  This settles the brief's question about how the record is split; the
  design settles its exact layout.
- **Whether the loop needs a workflow-engine gate.** Deferred to the
  design, bounded by R37: prose unless a step can't be held any other
  way.
- **Defaults for the soft numbers.** Three workers, 30 minutes and seven
  days are defaults, each overridable by the human's decisions. Fixed
  numbers let a reviewer check behaviour; making them decisions keeps
  one operator's pace from becoming the skill's.
- **Which decisions go to the human.** Three conditions (scope change,
  reversing or extending a supplied decision, a step reserved for a
  person) rather than a list of named actions, because a list would
  grow with every effort and the conditions don't.
- **Nested coordinators.** A coordinator may start another only when
  the human's decisions allow it. Without that, a coordinator could
  multiply sessions beyond the bound on workers in flight.
- **Keep-alive wording.** The workspace manager arms a worker's
  keep-alive at dispatch according to its own flag and host default, so
  the brief template says the keep-alive is the manager's to schedule
  rather than claiming it always happens. Either way the worker is never
  told to schedule its own.
- **Where the skill sits in the README.** A coordinator drives
  `/deliver` and `/work-on`, so it belongs with the implementation-level
  skills rather than among the standalone ones.

## Known Limitations

- **Pull request ownership (#395).** Which pull requests are a
  coordinator's is decided today by author login and branch name, so two
  runs under one account on one branch name see each other's pull
  request as their own. The skill depends on ownership being decided per
  run and names this as a limitation until it is fixed.
- **Merge order (#396).** The coordination pull request's merge-order
  block is written empty and never updated; scheduling comes from the
  PLAN. The skill depends on merge order being recorded where a reader
  after the PLAN is gone can find it, and names this as a limitation
  until it is fixed.
- **Reconcile is prose.** A coordinator can skip or shorten a prose
  procedure. The skill makes reconcile the first step and says what its
  report contains, but nothing enforces it in this version.

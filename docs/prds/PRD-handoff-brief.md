---
schema: prd/v1
status: Draft
problem: |
  A session that stops leaves its reasoning unreadable and its files unclaimed.
  The next session, its coordinator and the cleanup that removes its instance
  can't tell what mattered, so scratch is fetched back from teardown copies or
  kept for ever, and a worker at its context line is replaced by a fresh
  instance, with fresh clones and a cold build, that it didn't need.
goals: |
  A session picked up by another one, on the same host or another, starts from
  one handoff brief holding the earlier session's stated reasoning and the
  files it named, each with a matching hash, and nothing is fetched from a
  teardown copy. A worker at its context line keeps going in the same session
  and instance once the compaction route is proven and the owner rules on it.
upstream: docs/briefs/BRIEF-handoff-brief.md
---

# PRD: Handoff brief

## Status

Draft

Written from the accepted BRIEF-handoff-brief. The feature has two halves.
The handoff brief is buildable now. Compaction for workers is specified here,
but switching it on as the worker default is not in scope, and nothing this
work builds turns it on.

## Problem Statement

When a session in a workflow stops, three readers need to know what it was
doing and what it left: the session that picks the work up, the coordinator
that supervises it, and the remover that later decides whether its instance
can go. None of them gets a statement from the session itself.

Reasoning is the first loss. With current models a session's thinking comes
back as an encrypted signature, so a transcript holds almost no readable
reasoning: in one compacted transcript, 553 of 605 thinking blocks were empty.
What a session concluded, ruled out or meant to do next survives only if it
wrote it in plain text, and nothing in shirabe asks it to. Hand-written
continuation briefs fill the gap; on one workspace that runs shirabe's
workflows at scale they sat within 30 bytes of a 6,144-byte cap.

Files are the second loss. A session leaves a draft comment, a helper script,
review panel output, and nothing records which of those matter. Either
everything is kept, because nothing proves it disposable, or a successor goes
looking in a copy made at teardown, which can't serve a move to another host.
On that workspace every recorded read of such a copy was a successor or a
supervisor fetching a file the stopped session could have named.

Workers pay a third cost. A worker at its context line stops and is replaced
by a dispatched continuation: a new instance, new clones, a new transcript and
a cold build. About 40 of roughly 182 instances created each day on that
workspace are worker continuations, and one unit held two copies of the same
build (11.9 GiB). Claude Code can compact a session in place, keeping its id,
instance and koto run, and two trial workers finished whole units that way,
but shirabe has no supported route for a worker at its line (#1527).

Last, a run that ends with a stray untracked file gives the cleanup nothing to
go on: one stray log keeps the instance after the session that could have
cleared it is gone.

## Goals

Carried from the brief's User Outcome. A reader of one handoff brief finds the
earlier session's reasoning in plain text, pointers to its run, branch, pull
request and pushed head, and the files it chose to hand forward, each with a
hash proving it's the file meant. A coordinator reads its worker's brief
instead of writing a continuation brief by hand. The remover reads the brief
and a keep record to know which files went forward and which scratch was
declared disposable, with no model deciding. A dispatched successor is needed
only for a worker that blocked, lost its place or instance, or must move hosts.

## User Stories

- As a reviewer picking up a finished worker run the next day on another
  machine, I want one brief with the reasoning, pointers and the one scratch
  file that matters, so that I never open a teardown copy.
- As a worker author, I want a run with a stray untracked file to stop at its
  closing step, so that the brief's hashes are taken after the last change.
- As a coordinator whose worker blocked, I want the successor I dispatch
  through #1785's route to hold the predecessor's named files with matching
  hashes before its takeover counts, so that nothing is lost in the swap.
- As a long-running worker, once compaction is on for workers, I want to pass
  my context line and finish in the same session and instance, re-reading a
  note I wrote for myself, so that no successor instance is created.
- As a person in a plain session with no koto run, I want to call the brief
  script directly and point tomorrow's session at what it wrote.

## Requirements

### Terms

The **handoff brief** is a deliberate statement a session makes at the end of
a run, when it parks, or when it is replaced. The **compaction note** is what
a session writes for itself before a compaction; it hands nothing forward. The
**keep record** is `<instance>/.niwa/keep.json`, whose fields the removal work
already owns. The **closing step** confirms the work is pushed and no stray
file is left. The evidence clauses E1 to E5 are the five acceptance checks the
feature sets, restated in the traceability table below.

### Handoff brief (buildable now)

- **R1. A brief script any session can call.** shirabe ships one script that
  writes a handoff brief as a key in the calling session's own koto session.
  A session with no koto run gets a plain koto session the script opens to
  hold it. The brief travels wherever that koto session goes, including a
  cloud backend; it is never a transcript copy. Serves: E1, E3.
- **R2. Reasoning and pointers.** The brief holds plain-text reasoning (what
  the session concluded, what it ruled out and why, the next step) and
  pointers to state that already travels: koto session, branch, pull request,
  pushed head, and any watch it armed with the command to re-arm it.
  Serves: E1, E3.
- **R3. Named files with hashes.** Each named file is recorded with path,
  sha256 and size in bytes, computed from the file on disk when the brief is
  written. The script refuses a directory, with a message naming it, and
  writes no brief. Serves: E1, E3.
- **R4. Two named limits.** The script enforces an inline size and a record
  cap, each a named, documented value. A file at or below the inline size
  travels inside the brief as a key beside it; a larger file is named by path
  and hash and stays on the host. When everything a brief names, inline or by
  reference, exceeds the record cap, the script refuses, writes nothing, and
  the unit is kept. The values are left to the design. Serves: E1, E3.
- **R5. The keep record's file list, written once.** When a brief has files to
  name or the unit is parked, the script writes the keep record's `files`
  field (path, sha256, bytes) and its `brief` pointer (koto session, key),
  along with the record's agreed provenance fields. The brief renders its file
  list from the record; no second copy exists. The script is one of the
  record's writers and leaves other writers' fields intact. A brief with no
  files and no park writes no record. Serves: E1.
- **R6. The interim rule.** Until the kept set and the move into it exist, a
  file counts as handed forward only if it travels inside the brief. A keep
  record that names a file by reference keeps the unit. Serves: E1, E3.
- **R7. Disposability tied to the brief's time.** A brief records when it was
  written. It declares disposable only the job scratch and loose root files
  that existed then and that it did not name. A file created or changed later
  (by mtime or ctime, whichever is later) is unique again and keeps the unit
  until a newer brief names it or declares it disposable. Named files stay
  named until the session's next brief or expiry; later work voids a hold, not
  a name. Serves: E1, E4.
- **R8. Brief on by default.** A workflow that adopts the brief step writes a
  brief at the end of a run, at a park and at a handover. Turning it off means
  not adopting the step, and the price is a kept unit. Serves: E1.
- **R9. Closing step before the brief.** At the end of a run, after hosted CI
  is green and before done, the order is: closing step, then handoff brief,
  then build cleanup where the workspace has turned it on (other work). The
  closing step confirms everything is pushed, has stray untracked files
  committed or cleared, and leaves the worktree while keeping it on disk. A
  run that blocks at any of the three stops there; no brief is written while
  the closing step is unresolved. Serves: E5, E1.
- **R10. Successor takeover fits #1785.** When a successor takes over through
  the fallback continuation route #1785 designs, it copies every file its
  predecessor's keep record names into its own instance and checks each hash
  before its takeover is recorded as landed. For a koto run that record is the
  key koto writes on a carried supersede; for a session with no run it is a
  takeover mark the successor writes into the predecessor's brief session
  after taking the files. A hash mismatch or a missing file leaves the
  takeover not landed. Taken files are the successor's own scratch, and the
  takeover leaves the predecessor's record in place. The continuation starts
  from the predecessor's brief; this requirement adds no route. Serves: E3.

### Compaction for workers (stated now, default not in scope)

- **R11. The compaction note is not a brief.** A PreCompact hook has the
  session write a compaction note holding its reasoning and pointers. The note
  names no files, writes no keep record, declares nothing disposable and
  clears nothing. The hook shapes the summary and names the note to re-read.
  Serves: E4, E2.
- **R12. Same session through the line.** With compaction enabled for workers,
  a worker that passes its context line finishes under the session id it was
  launched with, in the same instance, with no successor instance created, and
  niwa shows it as working throughout. Serves: E2.
- **R13. Off unless set, per role.** Compaction is enabled only by a setting
  the workspace gives per role; with no setting nothing compacts. The window a
  role carries clears the harness floor by a margin the design states (a 100K
  window over a floor near 58K thrashed and blocked a session). Serves: E2.
- **R14. The default waits on three things.** Compaction does not become the
  worker default until (a) one read of the job state file's session id before
  and after a compaction shows it unchanged, which is the first step of this
  work; (b) the remaining arms of the worker trial are in; (c) the owner rules
  on the worker default. Nothing in this work turns compaction on, so R11 to
  R13 are requirements on the compaction route once enabled and their
  verification waits on those three. Serves: E2.

### Constraints

- **R15. Workers only.** This work builds nothing for coordinators or the two
  top-level supervising sessions that the separate plan for a coordinator
  successor brief would also build. Coordinators keep succeeding through the
  handover `/coordinate` ships. A coordinator reads a worker's brief and
  dispatches its successor through #1785; that's all it gains. Serves: E3, E2.
- **R16. Placement held for #1230.** Where the closing step and the brief step
  sit inside a work-on run is held while the design for #1230 is in progress.
  The brief script of R1 is not held by it. Serves: E1, E5.

### Traceability

| Check | What a reviewer sees | Requirements |
|-------|----------------------|--------------|
| E1 | A run ends in a fresh instance with two scratch files, one named; from another session the brief shows reasoning, pointers and the named file with a matching hash; the keep record lists that file; the unnamed one is in neither | R1-R9, R16 |
| E2 | A long worker with compaction on passes its line and finishes under its launch session id, same instance, no successor, shown working throughout | R11-R15 |
| E3 | A blocked worker's successor holds the named files with matching hashes before its takeover lands | R1-R4, R6, R10, R15 |
| E4 | A session with a compaction note and no brief is compacted; no keep record, no file list | R7, R11 |
| E5 | A run with a stray untracked file stops at its closing step until it's committed or cleared, before any brief | R9, R16 |

## Acceptance Criteria

- [ ] Calling the brief script in a session with a koto run writes the brief
  under a key in that session; no file outside the koto session holds it. (R1)
- [ ] Calling it in a session with no koto run opens a plain koto session and
  writes the brief there. (R1)
- [ ] From another session, reading the brief shows the reasoning in plain
  text and the koto session, branch, pull request and pushed head. (R2)
- [ ] Each named file's sha256 and size in the brief equal `sha256sum` and
  the byte count of the file on disk. (R3)
- [ ] Naming a directory makes the script exit non-zero, naming the
  directory, with no brief and no keep record written. (R3)
- [ ] The inline size and record cap appear by name in the script's
  documentation; a file one byte over the inline size is recorded by
  reference, and a set over the record cap is refused with nothing written.
  (R4)
- [ ] After a brief naming one of two scratch files, the keep record's
  `files` lists exactly that file and the unnamed file is in neither the
  record nor the brief. (R5, E1)
- [ ] Fields another writer set in the keep record survive a brief. (R5)
- [ ] A brief that names a file by reference leaves the unit kept. (R6)
- [ ] A scratch file touched after the brief is reported as unique, not
  disposable, until a newer brief covers it. (R7)
- [ ] A run with a stray untracked file stops at the closing step and no
  brief exists until the file is committed or cleared. (R9, E5) Checked once
  placement lands after #1230.
- [ ] A successor through #1785's route holds every named file with matching
  hashes before the landed record is written; corrupting one file before the
  copy leaves the takeover not landed. (R10, E3)
- [ ] Compacting a session that wrote a compaction note and no brief leaves
  no keep record and no file list. (R11, E4)
- [ ] With compaction on for workers, a long unit finishes under its launch
  session id in the same instance, no successor instance exists, and niwa
  shows it working throughout. (R12, E2) Waits on the three things in R14.
- [ ] With no per-role setting, no worker compacts. (R13)
- [ ] No change in this work sets compaction on for any role. (R14)
- [ ] No change touches the coordinator handover `/coordinate` ships or
  builds a coordinator or seat successor brief. (R15)

## Out of Scope

- The remover, the kept set, and the move of named files into it at a reap.
  This work only writes what they read.
- The command that says a unit is over.
- Build cleanup at the end of a run, and how long transcripts live.
- Switching compaction on for any role, workers included.
- Settling the owner questions below.
- Any new continuation route; #1785's route is fitted, not replaced.
- Anything for coordinators or the two supervising sessions that the separate
  coordinator successor brief plan would also build.

## Decisions and Trade-offs

**Inline size and record cap.** Decided: two limits exist, are named, and are
stated where the script is documented; their values are left to the design.
Picking numbers now, before the design weighs a koto key's size against what
hand-written briefs used, would fix a figure nothing has tested. One limit for
both was rejected: per-file travel and the total a record may name answer
different questions.

**Where a no-run session's brief lives.** Decided: in a plain koto session the
brief script opens (R1). Whether that session ever ends is an open question
carried to the design. A file in the instance was rejected because it can't
move hosts.

**How a role carries the compaction window.** Left to the design. niwa's
launch settings take constant keys only, so the known candidates are an
environment passthrough in workspace config, a niwa change, or writing the
instance settings after dispatch.

**What reads context size.** Left to the design. Any trigger needs a session
to read its own context size, and the existing reader is one message behind
after a compaction.

**Two acts, not one.** The brief and the compaction note stay separate (R11)
because a note that freed files would let a routine compaction declare
scratch disposable that nobody meant to give up.

**Refuse over the cap.** The script refuses rather than truncating, because a
brief that silently drops a file reads as complete when it isn't.

## Known Limitations

- A file that existed at the brief and that the session wrongly left unnamed
  is removed at the reap. The hash checks and takeover copy are mechanical;
  what to name is the model's choice.
- Until the kept set exists, a large file named by reference keeps its unit.
- A compaction fires at a chosen size, not a chosen moment; sending a compact
  command to a running session is untested.

## Open Questions

- **Who owns the coordinator and seat successor brief?** Another plan also
  designs one. Until the owner rules, this work builds nothing for
  coordinators or the two seats that plan would build; if the ruling keeps it
  there, this work stops at workers and the fallback continuation.
- **Do coordinators compact?** This work is proven for workers only.
  Coordinators keep succeeding through the handover `/coordinate` ships.

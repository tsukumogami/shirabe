---
schema: prd/v1
status: In Progress
problem: |
  A session that stops leaves its reasoning unreadable and its files unclaimed.
  The next session, its coordinator and the cleanup that removes its instance
  can't tell what mattered, so scratch is fetched back from teardown copies or
  kept for ever, and a worker at its context line is replaced by a fresh
  instance, with fresh clones and a cold build, that it didn't need.
goals: |
  A session picked up by another one, on the same host or another, starts from
  one handoff brief holding the earlier session's stated reasoning, pointers to
  its run, and the named files small enough to travel inside the brief, each
  with a matching hash, and nothing is fetched from a teardown copy. Larger
  named files stay on the host that wrote them. A worker at its context line
  keeps going in the same session and instance once compaction is proven for
  workers and the owner rules on making it the default.
upstream: docs/briefs/BRIEF-handoff-brief.md
---

# PRD: Handoff brief

## Status

In Progress

Written from the accepted BRIEF-handoff-brief. The handoff brief is buildable
now. Compaction for workers is specified, but making it the worker default is
out of scope and nothing this work builds turns it on.

## Terms

- **Session, koto session, unit.** A session is one Claude Code agent session;
  its koto session is the named state koto keeps for it (a workflow run, or
  only keys when plain). A unit is one piece of work a worker does in its own
  niwa instance.
- **Supervising session, owner.** A supervising session hands units to others
  and reads their results: coordinators, and two top-level sessions above
  them. The owner rules on the compaction default and on Pending Owner Rulings.
- **Context line, harness floor.** The context size at which a session must
  stop or compact; the context the harness fills before any work (near 58K
  tokens on the workspace cited here).
- **Handoff brief, park, handover, compaction note.** A brief is a deliberate
  statement a session makes at a run's end, at a park (it stops to wait and
  means to resume) or at a handover (a successor replaces it). A compaction
  note is what it writes for itself, through a PreCompact hook, before Claude
  Code compacts its context; it hands nothing forward.
- **Scratch, stray file.** Scratch is the job's scratch directory plus loose
  files at the instance root outside any repo. A stray file is an untracked,
  not-ignored file inside a repo's worktree; scratch is never stray.
- **Remover, reap, kept unit.** The remover is the niwa component (other work)
  that reaps, that is deletes, finished instances; a kept unit is one it must
  not reap. Disposable scratch may go at a reap; unique scratch is the only
  copy and keeps its unit.
- **Keep record, hold, preserve instruction, kept set, expiry.** The keep
  record, `<instance>/.niwa/keep.json`, is what the remover reads; the removal
  work defines its fields and the brief script is one of their writers. A
  hold is a record whose `protects` includes `instance`; a preserve
  instruction protects `files` and not `instance`. R5 says which a brief
  writes. The kept set is where the remover will move a record and its named
  files at a reap. Expiry is the record's `review_by` date, after which the
  removal work decides what it still protects.
- **Inline size, travels inside the brief, record cap.** A named file at or
  below the inline size travels inside the brief: its content is stored as
  its own koto context key in the same koto session as the brief, next to the
  brief's key. A larger file is named by reference (path and hash only) and
  stays on its host. The record cap bounds, in bytes, the total size of every
  file one keep record names, by reference included.
- **Closing step.** The work-on step before the brief: it confirms everything
  is pushed, has stray files committed or cleared, and leaves the worktree
  while keeping it on disk.
- **Landed takeover, job state file.** A takeover lands when koto writes
  `koto/superseded-carry-complete` at the end of a carried supersede (a
  successor run superseding its predecessor and carrying resume state across)
  or, with no koto run, when the successor writes its takeover mark: a key in
  the predecessor's brief session, whose exact name the design gives. The job
  state file is Claude Code's `~/.claude/jobs/<session-id>/state.json`; niwa
  reads a session as live only while it exists with a matching `sessionId`.
- **Issues cited.** #1785: an open draft shirabe design for a fallback worker
  continuation, a new instance that supersedes the stopped worker in koto.
  #1230: the design in progress for re-running a failed verification at the
  same head, in the stretch of the work-on run where the closing step would
  sit. #1527: shirabe has no supported route for a worker at its line.

## Problem Statement

When a session in a workflow stops, three readers need to know what it was
doing and what it left: the session that picks the work up, the coordinator
that supervises it, and the remover that later decides whether its instance
can go. None of them gets a statement from the session itself.

Reasoning is the first loss. Current models return thinking as an encrypted
signature, so a transcript holds almost no readable reasoning: in one
compacted transcript, 553 of 605 thinking blocks were empty. What a session
concluded, ruled out or meant to do next survives only in plain text it
wrote, and nothing in shirabe asks for that. Hand-written continuation briefs
fill the gap; on one workspace that runs shirabe's workflows at scale they
sat within 30 bytes of a 6,144-byte cap.

Files are the second loss. A session leaves a draft comment, a helper script,
review panel output, and nothing records which of those matter. Either
everything is kept, because nothing proves it disposable, or a successor goes
looking in a copy made at teardown, which can't serve a move to another host.
On that workspace every recorded read of such a copy was a successor or a
supervising session fetching a file the stopped session could have named. A
stray file is worse: one stray log keeps the instance after the session that
could have cleared it is gone.

Workers pay a third cost. A worker at its context line stops and is replaced
by a dispatched continuation: a new instance, new clones, a new transcript and
a cold build. About 40 of roughly 182 instances created each day on that
workspace are worker continuations, and one unit held two copies of the same
build (11.9 GiB). Claude Code can compact a session in place, keeping its id,
instance and koto run, and two trial workers finished whole units that way,
but shirabe has no supported route for a worker at its line (#1527).

## Goals

Carried from the brief's User Outcome. One handoff brief holds the earlier
session's plain-text reasoning, pointers to its run, branch, pull request and
pushed head, and the files it chose to hand forward, each with a hash. Pickup
on another host gets all of that except a named file above the inline size,
which stays on its host and keeps its unit until the kept set exists. A
coordinator reads its worker's brief instead of writing one; the remover
reads the brief and keep record, with no model deciding. A dispatched
successor is needed only for a worker that blocked, lost its place or
instance, or must move hosts.

## User Stories

- As a reviewer picking up a finished worker run the next day on another
  machine, I want one brief with the reasoning, pointers and the one small
  scratch file that matters, so that I never open a teardown copy.
- As a worker author, I want a run with a stray file to stop at its closing
  step, so that the brief's hashes are taken after the last change.
- As a coordinator whose worker blocked, I want the successor I dispatch
  through #1785's route to hold the predecessor's named files with matching
  hashes before its takeover lands, so that nothing is lost in the swap.
- As the remover, I want a keep record naming exactly the handed-forward files
  and a brief time, so that I reap only declared-disposable scratch.
- As a long-running worker, once compaction is on for workers, I want to pass
  my context line and finish in the same session and instance, re-reading my
  own note, so that no successor instance is created.
- As a person in a plain session with no koto run, I want to call the brief
  script and hand tomorrow's session the koto session and key it printed, so
  that the new session reads my reasoning there.

## Requirements

Each requirement names the acceptance checks E1 to E5 it serves; the
traceability table states them.

### Handoff brief (buildable now)

- **R1. A brief script any session can call.** shirabe ships one script that
  writes a handoff brief as a key in the calling session's koto session; with
  no koto run it opens a plain koto session and prints its name and the key.
  The brief goes wherever that koto session goes, a cloud backend included;
  no transcript copy and no file outside it holds the brief. Serves: E1, E3.
- **R2. Reasoning and pointers.** The brief holds plain-text reasoning (what
  the session concluded, what it ruled out and why, the next step) and
  pointers to state that already travels: koto session, branch, pull request,
  pushed head, and any watch it armed with the command to re-arm it. The
  script refuses reasoning that is empty once whitespace is trimmed, and
  judges nothing beyond that. Serves: E1, E3.
- **R3. Named files with hashes.** Each named file is recorded with path,
  sha256 and bytes, computed from disk when the script runs; an empty file is
  valid. The script refuses a directory, a symlink, a missing path or an
  unreadable file, naming it, and writes no brief and no keep record.
  Serves: E1, E3.
- **R4. Two named limits.** The script enforces the inline size and record
  cap, each a named, documented value. A file at or below the inline size
  travels inside the brief; a larger one is named by reference and stays on
  the host. When the named files' total bytes exceed the record cap the
  script refuses and writes nothing, so the unit stays kept. Serves: E1, E3.
- **R5. One copy of the file list, and what a brief's record protects.** When
  a brief has files to name or the unit is parked, the script writes the keep
  record's `files` (path, sha256, bytes), `brief` (koto session and key of the
  brief just written), `unit`, `written_by`, `written_at` and `protects`; the
  brief renders its list from the record and holds none of its own, and other
  writers' fields stay intact. This is the one statement of what the record
  protects. A park writes a hold (`protects` includes `instance`); resumed
  work, however the design marks it, voids that hold but not the named files
  (R7). A brief at a run's end or a handover that names files writes a
  preserve instruction (`protects` names `files`, not `instance`). While the
  interim rule applies (R6), a file named by reference makes any brief's
  record a hold on the instance, which resumed work leaves in place. A brief
  with no files and no park writes no record and leaves an existing one
  untouched. Serves: E1.
- **R6. The interim rule.** Until the kept set and the move into it exist, a
  file counts as handed forward only if it travels inside the brief. A file
  named by reference keeps its unit through the hold R5 states and can't
  reach a successor on another host (R10). Serves: E1, E3.
- **R7. Disposability tied to the brief's time.** A brief records when it was
  written and declares disposable only the scratch that existed then and that
  it did not name. A scratch file created or changed later (by mtime or ctime,
  whichever is later) is unique and keeps the unit until a newer brief names
  it or declares it disposable. Named files stay named, entries as written,
  until the session's next brief replaces the list or expiry, including after
  resumed work voids a park's hold (R5). Serves: E1, E4.
- **R8. Brief on by default.** Every workflow that adopts the brief step
  writes a brief at a run's end, a park and a handover, with no setting to
  turn on or off. A workflow opts out only by not adopting the step; it then
  declares no scratch disposable, so its units are kept. Serves: E1.
- **R9. Closing step before the brief.** After hosted CI is green and before
  done, a run's end goes: closing step, handoff brief, then build cleanup
  where turned on (other work, with its own blocking). An unpushed commit or
  a stray file blocks the closing step, and the run stops with no brief until
  it's resolved; a refused brief stops the run before done. Serves: E5, E1.
- **R10. Successor takeover fits #1785.** A successor taking over through
  #1785's route copies every file in its predecessor's keep record `files`
  into its own scratch and checks each sha256 before the takeover lands:
  before koto writes `koto/superseded-carry-complete`, or with no run, before
  it writes its takeover mark. A mismatch or missing file (a by-reference file
  on another host included) leaves it not landed. The predecessor's record
  stays as it was. This adds no route. Serves: E3.

### Compaction for workers (stated now, default not in scope)

- **R11. The compaction note is not a brief.** A PreCompact hook has the
  session write a compaction note, as a key in its koto session, with its
  reasoning and pointers. The note names no files, writes no keep record,
  declares nothing disposable and changes no scratch. The hook shapes the
  summary and names the note's key to re-read. Serves: E4, E2.
- **R12. Same session through the line.** With compaction set on for workers,
  a worker that passes its context line finishes under its launch session id,
  in the same instance, with no successor instance, and its job state file
  entry keeps that id throughout. Serves: E2.
- **R13. Off unless set, per role.** Compaction is on only where the workspace
  sets it for a role. A role's window clears the harness floor by a margin the
  design states as a number (a 100K window over a floor near 58K thrashed and
  blocked a session). Serves: E2.
- **R14. The default waits on three things.** The read of the job state
  file's session id before and after one compaction is the first task the
  plan schedules. Making compaction the worker default waits on its result,
  the remaining worker trial arms (two trial workers passed; a wider trial
  has one of four results in) and the owner's ruling. Nothing here sets it on
  in shipped configuration; R11 to R13 are checked in test instances where
  the reviewer sets it on. Serves: E2.

### Constraints

- **R15. Workers only, until the owner rules.** Pending the first owner
  ruling, this work builds nothing for coordinators or the top-level
  supervising sessions, which keep the handover `/coordinate` ships. A
  coordinator gains only reading a worker's brief and dispatching its
  successor through #1785. Serves: E3, E2.
- **R16. Placement held for #1230.** Where the closing step and the brief step
  sit inside a work-on run is held while the design for #1230 is in progress.
  The brief script of R1 is not held by it. Serves: E1, E5.

### Traceability

| Check | What a reviewer sees | Requirements |
|-------|----------------------|--------------|
| E1 | A run ends in a fresh instance with two scratch files, one named; from another session the brief shows reasoning, pointers and the named file with a matching hash; the keep record lists that file; the unnamed one is in neither | R1-R9, R16 |
| E2 | A long worker with compaction on passes its line and finishes under its launch session id, same instance, no successor, its job state file entry live throughout | R11-R15 |
| E3 | A blocked worker's successor holds the named files with matching hashes before its takeover lands (R6 decides which files can reach another host) | R1-R4, R6, R10, R15 |
| E4 | A session with a compaction note and no brief is compacted; no keep record, no file list | R7, R11 |
| E5 | A run with a stray file stops at its closing step until it's committed or cleared, before any brief | R9, R16 |

## Acceptance Criteria

Where a check waits on the out-of-scope remover, #1785's route or the
placement held for #1230, the criterion says what is checked now and what
waits. A marker is a unique string the test plants.

- [ ] With a koto run, the brief is a key in that koto session, and no file
  under the instance, worktree or system temp directory holds the reasoning
  marker afterwards. With no run, the script opens a plain koto session and
  prints its name and key; a new session reading that key gets the marker.
  With koto on a cloud backend, a session on a second host reads the marker
  and each file that travels inside the brief with a matching sha256. (R1, E3)
- [ ] Markers planted as what was concluded, what was ruled out (with its
  reason) and the next step appear verbatim when another session reads the
  brief, as does the exact re-arm command of a watch armed before it. Branch,
  pull request and pushed head equal `git branch --show-current`, the number
  `gh pr view` reports and the remote branch's commit at write time; with
  local HEAD one commit ahead, the remote's commit is recorded. (R2)
- [ ] Empty or whitespace-only reasoning, or naming a directory, a symlink, a
  missing path or an unreadable file, exits non-zero naming the cause, with no
  brief written and an existing keep record byte-identical. Each named file's
  sha256 and size equal `sha256sum` and the byte count when the script runs,
  including a file rewritten after the session chose it; an empty file shows
  0 bytes and the sha256 of empty input. (R2, R3)
- [ ] Both limits appear by name and value in the script's documentation. A
  file exactly at the inline size travels inside the brief, read from another
  session at its own key with a matching sha256; one a byte over has no key
  holding its content. Named files totalling exactly the record cap are
  accepted; one byte over exits non-zero with no brief and an existing keep
  record byte-identical; the remover keeping that unit waits. (R4)
- [ ] End to end: a run ends in a fresh instance leaving two scratch files
  under the inline size, one named. From another session the brief shows the
  markers, the pointers checked above and the named file with a hash equal to
  `sha256sum`; the keep record's `files` lists exactly that file; the unnamed
  file's path is in neither. Checked now with the script called at a run's
  end; the same check through a work-on run waits on placement. (R5, E1)
- [ ] The brief's file list equals the record's `files`, its stored key holds
  no path or hash list, and another writer's `reason`, `owner` and `wake` are
  unchanged. The record's `brief` resolves to the brief just written: reading
  it returns that brief's marker, and a second brief's after a second brief.
  A brief naming no files in an unparked unit creates no record and leaves an
  existing one byte-identical; a park naming no files writes `brief`, `unit`,
  `written_by`, `written_at`, empty `files` and `protects` with `instance`.
  (R5)
- [ ] A run's-end brief naming only files that travel inside the brief writes
  `protects` naming `files` and not `instance`; one naming a file over the
  inline size records it by path, sha256 and bytes with `protects` including
  `instance`. A park naming one file that travels inside the brief writes
  `protects` including `instance`; after resumed work, as the design marks
  it, `protects` drops `instance` and the `files` entry is unchanged, while a
  park that also names a file by reference keeps `instance`. The remover
  keeping these units waits on the remover. (R5, R6, R7)
- [ ] For a scratch file created one second after the brief, and one whose
  mtime is set back before the brief while its ctime falls after it, the
  brief's recorded time sorts before the later of mtime and ctime; the
  remover reporting both as unique waits on the remover. Changing a named
  file after the brief leaves its `files` entry as written; the next brief,
  naming a different file, replaces the list with that file. (R7)
- [ ] In an adopting workflow with no brief setting anywhere, a run that ends,
  parks or is handed over leaves a brief recorded after that event, and no
  documented switch stops it; a non-adopting run leaves no brief or keep
  record from the script. The work-on case waits on placement; the remover
  keeping a non-adopting unit waits on the remover. (R8)
- [ ] Checked now on the closing step alone: it blocks on a stray file, naming
  it, and on an unpushed commit; once both are resolved it passes, the
  worktree still exists at the pushed head, and the session's working
  directory is outside it. Waits on placement: in a work-on run, red CI
  reaches neither step, a blocked closing step leaves no brief, and the
  brief's recorded time follows the closing step's pass. (R9, E5)
- [ ] With a predecessor record naming two files, the successor's scratch
  holds both with sha256 equal to the record before the landed mark exists
  (the koto key, or the takeover mark with no run); a file corrupted or
  deleted before the copy leaves no mark; the predecessor's record ends
  byte-identical. Checked now with the copy step driven directly; the E3 run
  through a coordinator waits on #1785's route landing. (R10, E3)
- [ ] In a test instance with compaction set on and the hook installed,
  compacting a session that wrote a note and no brief leaves no keep record
  (an existing one byte-identical), no file list, and every scratch file's
  sha256 and mtime unchanged. The note's key holds a planted marker and no
  file paths, and the hook's summary instruction names that key. (R11, E4)
- [ ] In a test instance with compaction set on for workers, a unit that fires
  at least one compaction finishes. The job state file for the launch id,
  read before the first compaction, after each one and at finish, exists with
  `sessionId` equal to the launch id; `niwa list --json` at each read shows
  the same instance and no instance whose dispatch lineage names it. (R12, E2)
- [ ] With no per-role setting, a worker driven to its context line writes no
  compaction note and its transcript has no compaction boundary; with the
  setting on for workers only, a worker compacts and a coordinator at the
  same size doesn't. The design states the margin as a number, and each
  configured worker window exceeds the harness floor plus it. (R13)
- [ ] No shipped template, skill, setting or workspace default sets compaction
  on, so a fresh workspace with this work has no role with it on; the plan
  lists the session-id read as its first task. (R14)
- [ ] No change touches the handover `/coordinate` ships or adds a successor
  brief for any supervising session (R15), or edits the work-on run to place
  the closing step or brief step; the script's checks pass with no work-on
  run (R16).

## Out of Scope

- The remover, the kept set and the move into it; this work writes what they
  read. The command that says a unit is over; build cleanup; transcripts.
- Switching compaction on for any role, and settling Pending Owner Rulings.
- Any new continuation route; #1785's route is fitted, not replaced.
- Anything for coordinators or the two top-level supervising sessions.

## Decisions and Trade-offs

**Inline size and record cap.** Decided: two named, documented limits, with a
refusal over the cap, since a brief that silently drops a file reads as
complete. One limit for both was rejected: per-file travel and a record's
total answer different questions. The cap counts bytes; both values are left
to the design, which weighs a koto key's size against hand-written briefs.

**Where a no-run session's brief lives.** Decided: a plain koto session the
script opens (R1); a file in the instance can't move hosts. Whether that koto
session ever ends is left to the design.

**Symlinks and empty reasoning are refused.** A symlink's target may never
travel (R3); empty reasoning passes every check yet carries nothing (R2).

**Two acts, not one.** The brief and the compaction note stay separate (R11)
because a note that freed files would let a routine compaction declare
scratch disposable that nobody meant to give up.

**Left to the design.** Which workflows adopt the brief step and where
(work-on's placement is held, R16); the margin over the harness floor (R13);
how a role carries the compaction window, given niwa's launch settings take
constant keys only (an environment passthrough, a niwa change, or writing the
instance settings after dispatch); and what reads context size, since the
existing reader is one message behind after a compaction.

## Known Limitations

- A file that existed at the brief and that the session wrongly left unnamed
  is removed at the reap. The checks are mechanical; what to name is the
  model's choice. Accepted untested.
- Until the kept set exists, a file named by reference keeps its unit and
  can't reach a successor on another host (checked under R6).
- A compaction fires at a chosen size, not a chosen moment; sending a compact
  command to a running session is untested. Accepted untested.

## Pending Owner Rulings

Both are open, neither blocks this work, and each says what it does meanwhile.

- **Who owns the coordinator and supervising-session successor brief?** A
  separate plan also designs one. Until the owner rules, this work builds
  nothing for supervising sessions (R15). If the ruling keeps that brief with
  the other plan, this work stops at workers and the fallback continuation,
  and the order in which supervising sessions adopt a brief follows it.
- **Do coordinators compact?** This work is proven for workers only. Until the
  owner rules, coordinators keep succeeding through the handover `/coordinate`
  ships, and nothing this work ships sets compaction on for them.

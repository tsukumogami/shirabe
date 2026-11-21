---
schema: prd/v1
status: Draft
problem: |
  A session that stops leaves its reasoning unreadable and its files unclaimed,
  so the next session, its supervisor and the instance cleanup can't tell what
  mattered. A session at its context line, worker or supervising, is replaced
  by a freshly dispatched instance it didn't need, when it could have
  compacted in place and kept working.
goals: |
  Every session compacts in place at its context line and carries on in the
  same session and instance, sent back to its run, its note and its record
  before it acts. A session that does stop hands forward one brief with its
  plain-text reasoning, pointers to its run, and the files it named, each with
  a matching hash, so nothing is fetched from a teardown copy. A dispatched
  successor is used only where a session can't continue or where compaction
  can't carry a change.
upstream: docs/briefs/BRIEF-handoff-brief.md
---

# PRD: Handoff brief

## Status

Draft

Written from the accepted BRIEF-handoff-brief, as amended after acceptance.
Two halves with different risk: the handoff brief has no pending decision and
can be built at once; compaction as the default for every role waits first on
one read of a session's identity across a compaction (R12), and coordinators
wait on the conditions in R19 and R23.

## Terms

- **Session, koto session, unit.** A session is one Claude Code agent session;
  its koto session is the named state koto keeps for it (a workflow run, or
  keys only). A unit is one piece of work a worker does in its own niwa
  instance.
- **Roles.** A worker does one unit. A coordinator runs a workflow that hands
  units to workers and reads their results. Supervising sessions above
  coordinators hand work to coordinators; they may not be on a workflow run
  and may run at the workspace root rather than in an instance.
- **Context line, window, harness floor, post-compaction size.** The context
  line is the size at which a session must stop or compact today. The window
  is the size at which Claude Code compacts automatically. The harness floor
  is the context filled before any work (near 58K-61K tokens on the workspace
  cited here). The post-compaction size is the context right after a
  compaction, once the session has re-read what it needs: 72K-80K for the
  workers measured, 110K-170K for coordinators. A hard stop is a size above
  the window at which a session stops and hands over whatever else holds.
- **Compaction note.** A short koto key the session keeps current for itself:
  where it stands and what it is about to do. It names no files and hands
  nothing forward.
- **Re-anchor.** What the session sees first after a compaction: a line that
  sends it back to its run, its note and its record before it acts.
- **Handoff brief, park.** A brief is a deliberate statement a session makes
  at a run's end, at a park (it stops to wait and means to resume), or when it
  stops because it can't continue or is deliberately replaced (R20, R21).
- **Scratch, stray file.** Scratch is the job's scratch directory plus loose
  files at the instance root outside any repo. A stray file is an untracked,
  not-ignored file inside a repo's worktree; scratch is never stray.
- **Remover, reap, keep record, kept set.** The remover is the niwa component
  (other work) that deletes finished instances. The keep record,
  `<instance>/.niwa/keep.json`, is what it reads; the removal work defines its
  fields and the brief script is one of their writers. A hold is a record
  whose `protects` includes `instance`; a preserve instruction protects
  `files` and not `instance`. The kept set is where the remover will move a
  record and its named files at a reap. The record's `review_by` date is set
  by the removal work's rules; after it passes, the removal work decides what
  the record still protects.
- **Watch, re-arm command.** A watch is a long-running command a session
  starts so that it is woken when something arrives, such as a koto leg watch
  or a pull request check watch. Its re-arm command is the exact command line
  that starts it again, with any cursor it needs.
- **Resume mark.** A koto key the session writes when it starts working again
  after a park; the design names it. Resumed work means that mark exists with
  a time later than the park's brief.
- **Inline size, record cap.** A named file at or below the inline size
  travels inside the brief: its content is stored as its own koto key next to
  the brief's key. A larger file is named by reference (path and hash only)
  and stays on its host. The record cap bounds the total bytes of every file
  one keep record names.
- **Closing step.** The step before the brief at a run's end: it confirms
  everything is pushed, has stray files committed or cleared, and leaves the
  worktree while keeping it on disk.
- **Job state file.** Claude Code's `.claude/jobs/<session-id>/state.json`
  under the home directory; niwa reads a session as live only while it exists
  with a matching `sessionId`.
- **Issues cited.** #1527: shirabe has no supported route for a session at its
  line. #1230: the redesign of the end of a work-on run, where the closing step
  would sit. #1556: a long-lived session never picks up a new shirabe release.
  tsukumogami/niwa#545: hook entries in launch settings are assigned whole.

## Problem Statement

When a session in a workflow stops, three readers need to know what it was
doing and what it left: the session that picks the work up, the coordinator
that supervises it, and the remover that later decides whether its instance
can go. None of them gets a statement from the session itself.

Reasoning is the first loss. Current models return thinking as an encrypted
signature, so a transcript holds almost no readable reasoning: in one
compacted transcript, 553 of 605 thinking blocks were empty, and signed
thinking is dropped when work moves to another account. What a session
concluded, ruled out or meant to do next survives only in plain text it
wrote, and nothing in shirabe asks for that. Hand-written continuation briefs
fill the gap; on one workspace that runs shirabe's workflows at scale they sat
within 30 bytes of a 6,144-byte cap.

Files are the second loss. A session leaves a draft comment, a helper script,
review panel output, and nothing records which of those matter. Either
everything is kept, because nothing proves it disposable, or a successor goes
looking in a copy made at teardown, which can't serve a move to another host.
On that workspace every recorded read of such a copy was a successor or a
supervising session fetching a file the stopped session could have named. A
stray file is worse: one stray log keeps the instance after the session that
could have cleared it is gone.

The context line is the third cost, and every role pays it. A session at its
line stops and is replaced by a dispatched successor: a new instance, new
clones, a new transcript, a cold build and a read-in of the state it just
had. About 40 of roughly 182 instances created each day on that workspace are
worker continuations, one unit held two copies of the same 11.9 GiB build,
and coordinators hand over to successors that must reconstruct what they
knew. Claude Code can compact a session in place, keeping its id, instance,
worktree, warm build and workflow run, and two workers finished whole units
that way, compacting from about 247K tokens to 72K-80K several times each.
But nothing ships the window, the hook that shapes the summary, or the step
that sends a compacted session back to its run (#1527). A supervising
session is harder: its standing context is larger, messages and wakes keep
arriving, and its workflow reconciles against its record only when it starts.

## Goals

A worker that reaches its context line compacts in place and finishes its
unit under the session id it was launched with, in the same instance, with no
successor dispatched; right after the compaction it is sent back to its run,
its note and its run's status. A coordinator and then the supervising
sessions above coordinators do the same, with a re-read of their record
before they act. A successor is dispatched, the way it is today, only for a
session that can't continue, or deliberately for a change compaction can't
carry.

A session that does stop writes one handoff brief. Whoever picks the work up,
on the same host or another, reads the earlier session's reasoning, the
pointers to its run, branch, pull request and pushed head, and the files it
handed forward with matching hashes. A coordinator reads its worker's brief
instead of writing one by hand, and the remover reads the brief and its keep
record, with no model deciding.

## User Stories

- As a worker on a long unit, I want to pass my context line, compact, and be
  pointed at my run's status and my note, so that I finish under my launch
  session id in the same instance and nobody dispatches a successor.
- As a coordinator between wakes, I want everything a person told me already
  in my record, and after a compaction to re-read that record and re-arm my
  watches before I act, so that my workers notice nothing.
- As a reviewer picking up a finished worker run the next day on another
  machine, I want one brief with the reasoning, pointers and the one small
  scratch file that matters, so that I never open a teardown copy.
- As a worker author, I want a run with a stray file to stop at its closing
  step, so that the brief's hashes are taken after the last change.
- As a person in a plain session with no workflow run, I want to call the
  brief script and hand tomorrow's session the koto session and key it
  printed, so that the new session reads my reasoning there.
- As a supervisor whose worker keeps compacting without getting anywhere, I
  want that detected and named as "can't continue", so that I hand it over
  instead of letting it thrash.
- As the remover, I want a keep record naming exactly the handed-forward files
  and a brief time, so that I reap only declared-disposable scratch.

## Requirements

Each requirement names the checks E1 to E4 it serves; the traceability table
states them.

### Handoff brief (buildable now)

- **R1. A brief script any session can call.** shirabe ships one script that
  writes a handoff brief as a key in the calling session's koto session; with
  no koto run it opens a plain koto session and prints its name and the key.
  The brief goes wherever that koto session goes, a cloud backend included;
  no transcript copy and no file outside it holds the brief. Serves: E1.
- **R2. Reasoning and pointers.** The brief holds plain-text reasoning (what
  the session concluded, what it ruled out and why, the next step) and
  pointers to state that already travels: koto session, branch, pull request,
  pushed head, and each watch it armed with the exact command to re-arm it.
  The script refuses reasoning that is empty once whitespace is trimmed, and
  judges nothing beyond that. Serves: E1.
- **R3. Named files with hashes.** Each named file is recorded with path,
  sha256 and bytes, computed from disk when the script runs; an empty file is
  valid. The script refuses a directory, a symlink, a missing path or an
  unreadable file, naming it, and writes no brief and no keep record.
  Serves: E1.
- **R4. Two named limits.** The script enforces the inline size and the record
  cap, each a named, documented value. A file at or below the inline size
  travels inside the brief; a larger one is named by reference and stays on
  the host. When the named files' total bytes exceed the record cap the script
  refuses and writes nothing, so the unit stays kept. Serves: E1.
- **R5. One copy of the file list, and what a brief's record protects.** When
  a brief has files to name or the unit is parked, the script writes the keep
  record's `files` (path, sha256, bytes), `brief` (koto session and key of the
  brief just written), `unit`, `written_by`, `written_at` and `protects`; the
  brief renders its list from the record and holds none of its own, and other
  writers' fields stay intact. A park writes a hold; a resume mark voids that
  hold but not the named files (R7). A brief at a
  run's end, or from a session that stops because it can't continue or is
  deliberately replaced, writes a preserve instruction when it names files.
  While the interim rule applies (R6), a file named by reference makes any
  brief's record a hold, which resumed work leaves in place. A brief with no
  files and no park writes no record and leaves an existing one untouched.
  Serves: E1.
- **R6. The interim rule.** Until the kept set and the move into it exist, a
  file counts as handed forward only if it travels inside the brief. A file
  named by reference keeps its unit through the hold R5 states and can't
  reach a session on another host. Serves: E1.
- **R7. Disposability tied to the brief's time.** A brief records when it was
  written and declares disposable only the scratch that existed then and that
  it did not name. A scratch file created or changed later (by mtime or ctime,
  whichever is later) is unique and keeps the unit until a newer brief names
  it or declares it disposable. Named files stay named, entries as written,
  until the session's next brief replaces the list or the record's `review_by`
  date passes, including after a resume mark voids a park's hold. Serves: E1, E3.
- **R8. Brief on by default.** Every workflow that adopts the brief step
  writes a brief at a run's end, a park, and a stop for R20 or R21, with no
  setting to turn it on or off. A workflow opts out only by not adopting the
  step; it then declares no scratch disposable, so its units are kept.
  Serves: E1.
- **R9. Closing step before the brief.** After hosted CI is green and before
  done, a run's end goes: closing step, handoff brief, then build cleanup where
  turned on (other work). An unpushed commit or a stray file blocks the closing
  step, and the run stops with no brief until it's resolved; a refused brief
  stops the run before done. Serves: E4, E1.

### Compaction in place (every role)

- **R10. The compaction note is not a brief.** The note is its own koto key in
  the session's koto session and names no files. Writing it, and compacting,
  writes no keep record, declares nothing disposable and changes no scratch.
  Serves: E3, E2.
- **R11. Same session through the line.** With compaction on, a session that
  passes its window finishes under its launch session id, in the same
  instance, with no successor instance; its job state file keeps that id
  throughout, and niwa shows it as working. A coordinator on a workflow run
  that compacts resumes that run from its record. Serves: E2.
- **R12. The identity read comes first.** One read of the job state file's
  `sessionId`, and of what niwa reports for the session, before and after one
  compaction, is the first task the plan schedules. No role's default is
  switched on until that read shows the id unchanged and the session live.
  Serves: E2.
- **R13. A window per role, at the size the role hands over at today.** Each
  role has its own window, set for that role, so switching one role on never
  sets a window for another. A role's window takes the value of the context
  line it stops at today: about 280K for workers, 300K for coordinators, and
  the supervising sessions' line once their post-compaction size is measured.
  Each value must meet the margin rule: the role's post-compaction size leaves
  at least 100K tokens before its window and is no more than 60% of it.
  Workers (72K-80K) and coordinators (up to 170K) meet it at those values. The
  design restates each value against the measured figures and says what
  happens if a role's post-compaction size grows past the rule. Switching a
  role on also moves the rule that makes it stop at its context line: the
  role no longer stops at the line, which becomes its window, and stops only
  at a hard stop above the window (for workers, the stop near 350K that
  applies today only near a unit's end; the design sets it for each later
  role). The hard stop acts only as a
  fallback for a compaction that didn't fire, and leads to today's successor
  route (R20). So a switched-on role compacts at the size where it stops
  today, and costs no more per turn than it does now. Serves: E2.
- **R14. How a workspace turns compaction on for a role.** A workspace turns
  compaction on for a role by setting that role's window and installing the
  two hooks (R15, R16) in its configuration. niwa carries both into each
  instance's settings when it applies the configuration. The hooks go in as
  workspace instance hooks with no niwa change. A window for one role, rather
  than the whole workspace, needs a niwa change: niwa today carries such a
  setting only workspace-wide or per repository, its dispatch-time
  environment passthrough refuses names that start with `CLAUDE_`, and its
  launch settings never set them. That change is part of v1, as a separate
  niwa pull request. A session's role is fixed when it is dispatched, so the
  window follows the role a session is dispatched with; the design picks what
  carries it. A switch-on reaches an instance only when niwa next
  applies to it; whether a session already running there picks it up without
  a restart is an owned unknown. shirabe documents the setting and ships the
  hooks; it sets nothing on in a workspace by itself. Sessions launched at the
  workspace root get no instance settings today, so they stay without a
  window until niwa carries it there. Serves: E2.
- **R15. The summary carries the way back.** A PreCompact hook's output asks
  the summary to name the koto session, branch, pull request and the note's
  key, and to keep verbatim any owner words, ids and hashes still in play.
  Serves: E2, E3.
- **R16. The re-anchor rides a compact-matched SessionStart hook.** After a
  compaction the session's first context includes a short line, under the
  10,000-character field cap, naming its koto run, its note's key, `koto
  status` to run, and the record to re-read before acting. It points at the
  note rather than inlining it. It is carried by a SessionStart hook matched on
  `compact`, not PostCompact, whose output is discarded. The hook sits beside
  niwa's existing compact-matched hooks without replacing them. Serves: E2.
- **R17. Keeping the note current before a compaction nobody chooses.** A
  compaction fires at a size, not a moment, so the note must already be
  current. The PreCompact hook judges the note stale when the session's koto
  session has an event with a seq later than the note's last write, or the
  branch has a commit whose commit time is later than that write's
  timestamp, and then its output tells the summary that the
  note is stale and that rewriting it is the first step after the
  compaction. The hook never blocks a compaction by default: a block is
  invisible to the model and can't tell a window compaction from a recovery
  at the hard limit, so an unbounded block runs the session into a failed
  request. Serves: E2, E3.
- **R18. A context reader that reads right after a compaction.** shirabe ships
  a reader any session can call that reports its own current context size from
  its transcript, correct on the first read after a compaction, from any
  instance and from the workspace root. It also reports how many compaction
  boundaries the transcript holds and the assistant turn at which each fell,
  so a supervisor on another host learns them from the session itself
  (R20). Serves: E2.

### Supervising sessions

- **R19. What a supervising session needs before it may compact.** Anything a
  person tells it, and every id and hash it is handed, is written to its
  record when it arrives. After a compaction it re-reads its record, its
  decisions and its standing instructions, re-arms each watch from a command
  its record holds, and rescans what arrived during the compaction, before it
  acts. Whether a message or wake that lands while a compaction runs still
  waits somewhere the rescan reads is an owned unknown; the R19 criterion
  settles it. A supervising session with
  no workflow run re-anchors to its own log. Coordinators switch on only once
  their workflow does all of this; supervising sessions above coordinators
  switch on last. Serves: E2.

### When a successor is still dispatched

- **R20. "Can't continue", and who detects it.** A session can't continue when
  any of these holds. The window sits too close to its post-compaction size,
  so compactions come with little progress between them: the session's
  transcript shows three compaction boundaries within 30 assistant turns of
  each other (v1's values; the design may tune them and must say why),
  detected by the supervisor from the boundary count and turns the session's
  own reader reports (R18), so no transcript is read across hosts. It passes
  its hard stop because no compaction fired (R13). Its instance is lost or it must
  move host: detected by the supervisor at reconcile. It is blocked on
  something it can't resolve: the session's own judgment, by parking as
  today. What it is allowed to do no longer covers the work: the session's
  own judgment. Each case ends in a brief where the session can still write
  one, then today's successor route. Serves: E1.
- **R21. Deliberate succession compaction can't replace.** A session that
  could compact is still replaced by a dispatched successor in two cases:
  picking up a new shirabe release, which a running session never does
  (#1556), and a change to what the session is allowed to do, which is fixed
  at dispatch. The session writes a brief and hands over the way it does
  today; this work says when, not how. Serves: E1.

### Constraints

- **R22. One brief format for every role.** Every session writes the same
  brief, supervising sessions included. The part listing standing rules with
  their sources, its size budget and the incoming session's restatement are
  separate work, delivered as a section of this brief and a check on it,
  never a second format. Serves: E1.
- **R23. Coordinators wait on a superseding decision.** An earlier decision,
  recorded outside this repository, holds that coordinators hand over rather
  than compact. The coordinator default switches on only after a decision
  that supersedes it is recorded where that one lives. This work names the
  dependency and doesn't write it. Serves: E2.
- **R24. Placement held for #1230.** Where the closing step and the brief step
  sit inside a work-on run is held while the design for #1230 is in progress.
  The brief script of R1 is not held by it. Serves: E1, E4.

### Traceability

| Check | What a reviewer sees | Requirements |
|-------|----------------------|--------------|
| E1 | A run ends in a fresh instance with two scratch files, one named; from another session the brief shows reasoning, pointers and the named file with a matching hash; the keep record lists that file; the unnamed one is in neither | R1-R9, R20-R22, R24 |
| E2 | A long unit with compaction on passes its window and finishes under its launch session id, same instance, no successor, live throughout; a coordinator compacting in place resumes its run from its record | R10-R19, R23 |
| E3 | A session with a compaction note and no brief is compacted; no keep record, no file list | R7, R10, R15, R17 |
| E4 | A run with a stray file stops at its closing step until it's committed or cleared, before any brief | R9, R24 |

## Acceptance Criteria

Where a check waits on the out-of-scope remover or on the placement held for
#1230, the criterion says what is checked now and what waits. A marker is a
unique string the test plants.

- [ ] With a koto run, the brief is a key in that koto session, and no file
  under the instance, worktree or system temp directory holds the reasoning
  marker afterwards. With no run, the script opens a plain koto session and
  prints its name and key; a new session reading that key gets the marker.
  With koto on a cloud backend, a session on a second host reads the marker
  and each file that travels inside the brief with a matching sha256. (R1)
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
  including a file rewritten after the session chose it; an empty file shows 0
  bytes and the sha256 of empty input. (R2, R3)
- [ ] Both limits appear by name and value in the script's documentation. A
  file exactly at the inline size travels inside the brief, read from another
  session at its own key with a matching sha256; one a byte over has no key
  holding its content. Named files totalling exactly the record cap are
  accepted; one byte over exits non-zero with no brief and an existing keep
  record byte-identical. (R4)
- [ ] End to end: a run ends in a fresh instance leaving two scratch files
  under the inline size, one named. From another session the brief shows the
  markers, the pointers checked above and the named file with a hash equal to
  `sha256sum`; the keep record's `files` lists exactly that file; the unnamed
  file's path is in neither. Checked now with the script called at a run's
  end; the same check through a work-on run waits on placement. (R5, E1)
- [ ] The brief's file list is rendered from the record's `files` and names
  exactly the same files, sha256 values and sizes; another writer's `reason`,
  `owner` and `wake` are unchanged. The record's `brief` resolves to the brief
  just written: reading it returns that brief's marker; after a second brief,
  it returns the second brief's marker. A brief naming no files in an unparked unit creates no
  record and leaves an existing one byte-identical; a park naming no files
  writes `brief`, `unit`, `written_by`, `written_at`, empty `files` and
  `protects` with `instance`. (R5)
- [ ] A run's-end brief naming only files that travel inside the brief writes
  `protects` naming `files` and not `instance`; one naming a file over the
  inline size records it by path, sha256 and bytes with `protects` including
  `instance`. A park naming one inline file writes `protects` including
  `instance`; after a resume mark, `protects` drops
  `instance` and the `files` entry is unchanged, while a park that also names a
  file by reference keeps `instance`. The remover acting on these waits on the
  remover. (R5, R6, R7)
- [ ] For a scratch file created one second after the brief, and one whose
  mtime is set back before the brief while its ctime falls after it, the
  brief's recorded time sorts before the later of mtime and ctime. Changing a
  named file after the brief leaves its `files` entry as written; the next
  brief, naming a different file, replaces the list with that file. (R7)
- [ ] In an adopting workflow with no brief setting anywhere, a run that ends,
  parks or stops for R20 or R21 leaves a brief recorded after that event, and
  no documented switch stops it; a non-adopting run leaves no brief or keep
  record from the script. The work-on case waits on placement. (R8)
- [ ] Checked now on the closing step alone: it blocks on a stray file, naming
  it, and on an unpushed commit; once both are resolved it passes, the
  worktree still exists at the pushed head, and the session's working
  directory is outside it. Waits on placement: in a work-on run, red CI
  reaches neither step, a blocked closing step leaves no brief, and the
  brief's recorded time follows the closing step's pass. Checked now: a brief
  refused at a run's end (empty reasoning) leaves the run short of done, with
  no brief key and no keep record written. (R9, E4)
- [ ] In a test instance with the window and both hooks set, compacting a
  session that wrote a note and no brief leaves no keep record (an existing
  one byte-identical), no file list, and every scratch file's sha256 and mtime
  unchanged. The note's key holds a planted marker and no file paths. (R10, E3)
- [ ] Before any role is switched on: in a test instance, the job state file
  for the launch id is read before one compaction and after it, and both
  reads show `sessionId` equal to the launch id and niwa reporting the session
  live in the same instance. The plan lists this read as its first task, and
  no switch-on task precedes it. (R12)
- [ ] In a test instance with compaction on, a worker unit that fires at least
  one compaction finishes; at each compaction and at finish the job state
  file exists with the launch id and `niwa list --json` shows the same
  instance and no instance whose dispatch lineage names it. A coordinator on a
  quiet workflow run in a test instance compacts once and, before its next
  action, ticks its run from its record and re-arms its watch with the command
  its record holds. (R11, R19, E2)
- [ ] A coordinator in a test instance is sent a message holding an
  owner-words marker, an id and a sha256; its record holds all three verbatim
  before its next turn ends. A wake sent while it compacts is acted on after
  the compaction, found by the rescan, with no second send. A supervising
  session with no workflow run, compacted once, re-reads its own log before
  its next action. (R19)
- [ ] The design states each role's window, the margin rule and the measured
  post-compaction sizes it was checked against. For each switched-on role,
  the window in its test instance's settings minus that role's largest
  measured post-compaction size is at least 100K, and that size is no more
  than 60% of the window. A worker with compaction on, in a test instance,
  passes its old context line without writing a brief or being replaced,
  compacts at its window, and is handed over only past its hard stop; with
  the window removed from its settings, it reaches the hard stop and takes
  today's successor route. (R13)
- [ ] A workspace configuration that sets the worker window and the two
  hooks, applied by niwa with its per-role change, yields a worker instance
  whose settings carry the window and both hooks, and niwa's existing
  compact-matched hooks are still present. A coordinator instance applied
  from that same configuration carries no window from it and does not
  compact before the superseding decision of R23 is recorded. A fresh
  workspace that sets none of them has no window and no hook from this work.
  An instance applied before the configuration changed has no window until
  niwa applies to it again. A session launched at the workspace root is
  documented as having no window. (R14, R23)
- [ ] After a compaction in a test instance, the transcript's
  post-compaction context contains the PreCompact output naming the koto
  session, branch, pull request and note key, and the SessionStart line naming
  the koto run, note key and `koto status`; that line is under 10,000
  characters and contains no note body. The instance settings hold that hook
  as a SessionStart entry with matcher `compact`, and no PostCompact entry
  from this work. (R15, R16)
- [ ] With the note last written before a later koto event, the PreCompact
  hook's output says the note is stale and that rewriting it comes first;
  with no later event and no later commit, it doesn't. In both cases the hook
  exits 0 and the compaction runs. (R17)
- [ ] The reader's figure matches the transcript's last usage record within
  1K tokens on the first read after a compaction and after five more turns, run
  from an instance and from the workspace root. On a transcript with two
  compactions it reports two boundaries and the assistant turn of each. With
  an empty or missing transcript the reader exits non-zero naming it and
  prints no figure. (R18)
- [ ] Given a session's reported boundaries with three compactions inside the
  design's turn count, the supervisor's check reports the session as unable
  to continue, and with the same three compactions spread past it doesn't;
  the check reads only what the session reported, never its transcript. With
  a worker's instance removed
  in a test, the coordinator's reconcile reports that worker as unable to
  continue. A session handing over for R21 writes a brief before the
  successor is dispatched. The coordinate workflow's documentation names each
  case in R20 and R21 and who acts on it. (R20, R21)
- [ ] No change adds a second brief format for any supervising session or
  writes the standing-rules section's content (R22); the coordinator
  default isn't switched on by any task ahead of the superseding decision
  (R23); none edits the work-on run to place the closing step or brief step,
  and the script's checks pass with no work-on run (R24).

## Out of Scope

- Any new successor route, or changes to the one that exists; checking a
  successor's copy of the named files at takeover.
- Choosing the moment of a compaction from outside the session, such as a
  command sent to a running session. Compaction fires at a size.
- A second brief format for supervising sessions; the standing-rules
  section's content and budget.
- Where the closing step and the brief step sit inside a work-on run's final
  states (#1230).
- The remover, the kept set, the move of named files into it at a reap, and
  the command that says a unit is over. Build cleanup; how long transcripts
  live.
- Carrying the window to sessions at the workspace root (a niwa change after
  v1).
- Writing the decision that supersedes the earlier coordinator position.

## Decisions and Trade-offs

**Inline size and record cap.** Two named, documented limits, with a refusal
over the cap, since a brief that silently drops a file reads as complete. One
limit for both was rejected: per-file travel and a record's total answer
different questions. The values are left to the design.

**Where a no-run session's brief lives.** A plain koto session the script
opens (R1); a file in the instance can't move hosts. Whether that koto
session ever ends is left to the design.

**How the window and hooks reach an instance.** Through the workspace
configuration niwa writes into instance settings (R14), with a per-role
window as v1's one niwa change. A dispatch-time environment passthrough was
rejected: niwa refuses names that start with `CLAUDE_` there. One window for
the whole workspace was rejected: coordinators also run in their own
instances, so setting it for workers would switch coordinators on with them,
before the decision R23 waits on. Most coordinators today end near or past
280K, so many would compact before handing over.

**A window per role, at the line each stops at today.** A window has to clear
the role's post-compaction size by the margin rule: a 100K window over a
floor near 58K thrashed and blocked a session. Workers need about 180K at
least and coordinators about 285K, so a single value would make workers carry
the coordinators' size. With a window per role, each takes the line the role
stops at today, so a switched-on role compacts where it stops now and costs
no more per turn. A 300K worker window was considered: it saves about one
compaction in ten and costs about 6% more input per turn. Rejected, since its
only reason was one window shared with coordinators. These values keep
today's per-role cost and aren't yet confirmed by whoever set today's lines;
treat them as assumed until they are. Changing one later is a change to that
role's cost per turn.

**Moving the line, not removing it.** A switched-on role that still stopped
at its line would hand over before compaction fired. Retiring the line was
rejected: it leaves nothing to stop a session whose compaction silently
didn't fire. So the line moves to a hard stop above the window (R13).

**Warn, don't block, on a stale note.** A PreCompact block was considered, to
make the session refresh its note first. Rejected as the default: the block
is invisible to the model, the hook can't tell a window compaction from a
recovery at the hard limit, and a repeated block runs the session to a failed
request (R17).

**SessionStart, not PostCompact, carries the re-anchor.** PostCompact's
output is discarded; a compact-matched SessionStart hook's output is added to
the compacted context (R16).

**What a supervising session re-reads, and the order roles switch on.**
Its record, decisions, standing instructions and watches (R19); workers
first, then coordinators once their workflow re-anchors and the superseding
decision exists (R23), then supervising sessions above coordinators.

**Two acts, not one.** The brief and the compaction note stay separate (R10),
because a note that freed files would let a routine compaction declare
scratch disposable that nobody meant to give up.

**Unknowns this PRD owns,** each to be settled by the design or by the plan's
first tasks, not left open:

- Whether a compact-matched SessionStart hook's output reaches a background
  session after a compaction at a configured window. Seen after automatic
  compactions near the model's maximum in a background session and after a
  manual compaction in a headless one; not yet seen at a configured window or
  at a boundary inside a tool call.
- Whether a window set in instance settings reaches an already-running
  background session without a restart. A switch-on reaches an instance only
  at niwa's next apply there (R14); the design says whether running sessions
  then need a restart.
- Whether a message or wake that lands while a supervising session compacts
  waits where its rescan reads it (R19).
- Whether R20's thrash values (three boundaries within 30 turns) separate
  thrashing from a long, healthy unit; the design checks them against
  transcripts on hand.
- Where the brief keys sit in the koto session (a key prefix, or none); the
  earlier reason for a `handover/` prefix no longer holds.
- Coordinators' and supervising sessions' post-compaction size as measured
  at their own windows: the coordinator figures come from compactions near
  the model's maximum, and supervising sessions have none. If a role's first
  measured size breaks the margin rule (for coordinators at 300K, anything
  above 180K), that role's window is set again before it switches on.

## Known Limitations

- A file that existed at the brief and that the session wrongly left unnamed
  is removed at the reap. The checks are mechanical; what to name is the
  model's choice. Accepted untested.
- Until the kept set exists, a file named by reference keeps its unit and
  can't reach a session on another host.
- Reasoning is lost across a compaction too: what survives is the summary,
  the note and the record. A session that didn't keep its note current
  resumes from a summary that says so (R17), not from what it knew.
- A session whose window is set this way can't change its own window.
- A running session gets a newly set window only after niwa applies to its
  instance again, and maybe only after a restart.
- Sessions at the workspace root have no window in v1.

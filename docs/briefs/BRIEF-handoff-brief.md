---
schema: brief/v1
status: Draft
problem: |
  A session that stops leaves its reasoning unreadable and its files unclaimed.
  The next session, or the cleanup that removes the instance, can't tell what
  mattered, so scratch is fetched back from teardown copies or kept for ever,
  and a worker at its context line is replaced by a fresh instance it didn't need.
outcome: |
  A session picked up by another one starts from the earlier session's stated
  reasoning and the files it named, read from one handoff brief, with nothing
  fetched from a teardown copy. A worker that reaches its context line keeps
  going in the same session and instance, once the compaction route is proven.
---

# BRIEF: Handoff brief

## Status

Draft

Framed under `/scope` for the feature that gives a stopping session one way
to hand its reasoning and files forward. The compaction half is framed here
but waits on evidence and an owner ruling before it can become a default.

## Problem Statement

When a session in a workflow stops, three different readers need to know what
it was doing and what it left behind: the session that picks the work up next,
the coordinator that supervises it, and whatever later decides whether the
session's instance can be removed. Today none of them gets a statement from the
session itself.

The session's reasoning is the first loss. With current models a session's
thinking comes back as an encrypted signature, so a transcript holds almost no
readable reasoning: in one compacted transcript that was read for this, 553 of
605 thinking blocks were empty. Whatever a session concluded, ruled out, or was
about to do survives only if it wrote that down in plain text before it
stopped. Nothing in shirabe asks it to, so it survives only in hand-written
continuation notes that some coordinators write by habit and that are capped at
a few kilobytes.

Its files are the second loss. A session leaves scratch: a draft comment, a
list of owed entries, a helper script, review panel output. Nothing records
which of those files matter. So either everything is kept, because nothing can
prove it is disposable, or a successor goes looking for the file afterwards in
a copy made when the instance was torn down. On one workspace that runs
shirabe's workflows at scale, every recorded read of such a copy was a
successor or a supervisor fetching a file the stopped session could have named.
A copy made at teardown can't serve a move to another host either, since it
lives on the host that made it.

The third cost lands on workers. A worker that reaches its context line today
stops and is replaced by a freshly dispatched continuation: a new instance with
fresh clones, a new job directory, a new transcript, and a cold build if it
verifies. On that same workspace about 40 of roughly 182 instances created each
day are worker continuations, and one unit held two copies of the same build
side by side. The continuation exists to get a smaller context; it throws away
the instance, the warm build and the session's address to get it, and then has
to carry forward by hand what it lost. Claude Code can instead compact a
session in place, keeping its id, its instance and its koto run, and two real
workers have finished whole units that way. shirabe offers no supported route
for it, and none for a worker at its line at all (#1527).

Finally, a run that ends with stray untracked files in its worktree gives the
cleanup nothing to go on. One stray log keeps the instance, and the session
that could have committed or cleared it has already gone.

## User Outcome

A person or a session that picks up stopped work, on the same host or another,
reads one handoff brief and finds the earlier session's reasoning in plain
text, the pointers to its run, branch, pull request and pushed head, and the
files it chose to hand forward, each with a hash that proves it is the file the
session meant. Nobody fetches anything from a teardown copy.

A coordinator stops writing continuation briefs by hand for its workers and
reads the worker's own brief instead. The component that removes finished
instances reads the same brief, and a keep record beside the instance, to know
which files were handed forward and which scratch the session declared
disposable, without a model deciding.

A worker that reaches its context line keeps working in the same session and
the same instance, and a dispatched successor is needed only for a session that
can't continue: one that blocked, lost its place, lost its instance, or has to
move hosts. Keeping the session at the line becomes the default only once the
evidence the Scope Boundary names is in.

## User Journeys

### A finished run hands forward

A worker running `/work-on` reaches green CI. Its run commits or clears the
stray files in its worktree, then writes a handoff brief naming the one scratch
file a reviewer will want and leaving a throwaway log unnamed. The next day a
different session, on another machine, reads the brief and sees the reasoning,
the branch, the pull request and the named file with a matching hash. A keep
record beside the instance lists the same file and nothing else.

### A run with a stray file stops at its closing step

A worker finishes its last fix and leaves an untracked file in the worktree.
Its run stops at the closing step and asks for the file to be committed or
cleared. No brief is written until it is, so the brief's hashes are taken after
the last step that changes a file.

### A blocked worker is replaced

A worker blocks and can't continue. Its coordinator dispatches a successor
through the fallback continuation route (#1785). Before the successor's takeover
is recorded as landed, its own instance holds every file the predecessor's
brief named, each with a matching hash, and the successor starts from the
predecessor's stated reasoning.

### A worker compacts at its line

With compaction turned on for workers, a long unit passes its context line.
Before the compaction the session writes a short note of its reasoning for
itself, and it re-reads that note afterwards. It finishes under the session id
it was launched with, in the same instance; niwa shows it as working throughout
and no successor instance is created. The note it wrote names no files and
writes no keep record.

### A session with no workflow hands forward

A person working in a plain session, with no koto run, wants to stop for the
day. They call the brief script directly; it opens a session of its own to hold
the brief, records the reasoning and the files named, and the person points
tomorrow's session at it.

## Scope Boundary

**In:**

- A deliberate statement a stopping session makes, at the end of a run, when it
  parks, or when it is replaced: its reasoning in plain words, where its work
  already lives, and a bounded set of files it hands forward, each provably the
  file it meant.
- A way for any session to make that statement, with or without a workflow
  run behind it, kept with the session's own state so it goes wherever the
  session goes.
- Telling the instance cleanup which files were handed forward, and what counts
  as handed forward before named files have anywhere to go after the instance
  is removed.
- The difference between that statement and the note a session writes for
  itself before a compaction, which hands nothing forward and lets nothing go.
- A closing step at the end of a run that confirms the work is pushed and that
  no stray file is left, and comes before the statement.
- A replacement session receiving the files its predecessor handed forward
  before its takeover counts as done, fitted to the replacement route #1785
  already designs.
- Workers keeping their session at the context line: what has to be true
  before it can be their default, and what a session writes for itself before
  it compacts. Switching it on is not in.

**Out:**

- Switching compaction on for any role. It waits on a check that a session
  keeps its identity through a compaction as niwa sees it, on the remaining
  runs of a worker trial, and on the owner's ruling on the worker default.
- Anything for coordinators or the two top-level supervising sessions that the
  separate plan for their successor brief would also build. Who owns that brief
  is an open owner question, and so is whether coordinators compact at all.
  Coordinators keep succeeding through the handover `/coordinate` already ships.
- Where the closing step and the brief step sit inside a work-on run's final
  states. That stretch is being redesigned for #1230, and placement waits for
  that design. The brief script itself isn't held by it.
- A new continuation route. The fallback continuation is #1785's route, fitted
  here rather than replaced.
- The remover, the kept set, the move of named files into it at a reap, and the
  command that says a unit is over. Those belong to the removal work; this
  feature only writes what they read.
- Build cleanup at the end of a run, and how long transcripts live.

## Open Questions

Each of these defers to the downstream PRD, which records a decision or names
it as an unknown it owns.

- What the brief's inline size and the record cap are.
- Where the brief of a session with no koto run lives, and whether that session
  ever ends.
- How a dispatch or a role carries the compaction window into an instance.
- What reads a session's context size for a trigger, and whether `/coordinate`
  states one.

## References

- #1785, the fallback continuation route for a worker that can't continue.
- #1230, the redesign of the end of a work-on run that holds where the closing
  step and the brief are placed.
- #1527, the missing route for a worker at its context line.

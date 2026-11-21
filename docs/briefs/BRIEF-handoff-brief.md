---
schema: brief/v1
status: Accepted
problem: |
  A session that stops leaves its reasoning unreadable and its files unclaimed,
  so its successor and the instance cleanup can't tell what mattered. A session
  at its context line is replaced by a fresh instance it didn't need, when it
  could have compacted in place and kept working.
outcome: |
  Every session, worker or supervising, compacts in place at its context line
  and carries on in the same session and instance, pointed back at its run. A
  session that does stop hands forward one brief with its reasoning and the
  files it named, so nothing is fetched from a copy made at teardown.
---

# BRIEF: Handoff brief

## Status

Accepted

Re-framed from an earlier accepted brief for the same feature. Two decisions
changed its shape. Compaction in place is now the default at the context line
for every session, not only workers, and handing over to a dispatched
successor is kept only for a session that can't continue. And this feature no
longer waits on, or fits itself to, a new continuation route: the successor
route that exists today stays as it is.

Framing details left to the downstream PRD, which records a decision on each
or names it as an unknown it owns: how large a file can be and still travel
inside the brief, and how much one brief may name in all; where the brief of a
session with no workflow run lives; how each role's compaction window and hook
reach its instance; what a supervising session has to re-read after a
compaction before it acts; and the order in which roles switch compaction on.

## Problem Statement

When a session in a workflow stops, three readers need to know what it was
doing and what it left behind: the session that picks the work up next, the
coordinator that supervises it, and whatever later decides whether the
session's instance can be removed. Today none of them gets a statement from the
session itself.

Reasoning is the first loss. With current models a session's thinking comes
back as an encrypted signature, so a transcript holds almost no readable
reasoning: in one compacted transcript read for this, 553 of 605 thinking
blocks were empty. Signed thinking is also dropped when work moves to another
account. Whatever a session concluded, ruled out or was about to do survives
only if it wrote that down in plain text, and nothing in shirabe asks it to.

Files are the second loss. A session leaves scratch: a draft comment, a list
of owed entries, a helper script, review panel output. Nothing records which
of those files matter, so either everything is kept or a successor goes
looking for the file afterwards in a copy made when the instance was torn
down. On one workspace that runs shirabe's workflows at scale, every recorded
read of such a copy was a successor or a supervisor fetching a file the
stopped session could have named. A teardown copy also can't serve a move to
another host.

The third cost is the context line itself. A session that reaches its line
today stops and is replaced by a freshly dispatched successor: a new instance,
fresh clones, a new transcript, a cold build, and a read-in of the state it
just had. On that workspace about 40 of roughly 182 instances created each day
are worker continuations, and one unit held two copies of the same 11.9 GiB
build side by side. Coordinators pay it too, every time they hand over to a
successor that must reconstruct what they knew. Claude Code can compact a
session in place, keeping its id, instance, worktree, warm build and workflow
run. Two real workers have finished whole units that way, compacting from
about 247K tokens to 72K-80K several times each. But nothing ships the
setting, the hook that shapes the summary, or the step that sends a compacted
session back to its run, and shirabe has no supported route for a session at
its line at all (#1527). A supervising session is harder than a worker: its
standing instructions are large, it has messages and wakes arriving, and its
workflow only reconciles against its record when it starts, not after a
compaction.

Finally, a run that ends with stray untracked files in its worktree gives the
cleanup nothing to go on. One stray log keeps the instance, and the session
that could have committed or cleared it has already gone.

## User Outcome

A worker that reaches its context line compacts in place and finishes its unit
under the session id it was launched with, in the same instance, with no
successor dispatched. Right after the compaction it is pointed back at its
workflow run, its own note and the run's status, so it carries on from its
record and not only from a summary. A coordinator and, after it, the two
top-level supervising sessions do the same, with a window sized for their
larger standing context and a re-read of their record before they act on
anything.

A session that does stop, at the end of a run, at a park, or because it can't
continue, writes one handoff brief. Whoever picks the work up, on the same
host or another, reads in it the earlier session's reasoning in plain text,
the pointers to its run, branch, pull request and pushed head, and the files
it chose to hand forward, each with a hash that proves it is the file the
session meant. Nobody fetches anything from a teardown copy. A coordinator
reads its worker's brief instead of writing one by hand, and the component
that removes finished instances reads the same brief, and a keep record beside
the instance, to know which files were handed forward, without a model
deciding.

## User Journeys

### A worker compacts at its line

A worker on a long unit passes its context line. Its own short note of where
it stands is already current, because a compaction fires at a size and not at
a moment it chooses. The compaction runs; the summary names its run, branch,
pull request and note. The first thing the session sees afterwards tells it to
check its run's status and re-read the note. It finishes under the session id
it was launched with, in the same instance; niwa shows it as working
throughout, and no successor instance is created. The note it wrote names no
files and writes no keep record.

### A coordinator compacts between wakes

A coordinator on a workflow run passes its line. Anything a person told it was
written to its record when it arrived, so nothing exists only in the
conversation. After the compaction it is sent back to its run and record
before it acts, re-arms the watches its record lists, and goes on supervising
under the same session id. Its workers notice nothing.

### A finished run hands forward

A worker running `/work-on` reaches green CI. Its run commits or clears the
stray files in its worktree, then writes a handoff brief naming the one
scratch file a reviewer will want and leaving a throwaway log unnamed. The
next day a different session, on another machine, reads the brief and sees
the reasoning, the branch, the pull request and the named file with a matching
hash. A keep record beside the instance lists the same file and nothing else.

### A run with a stray file stops at its closing step

A worker finishes its last fix and leaves an untracked file in the worktree.
Its run stops at the closing step and asks for the file to be committed or
cleared. No brief is written until it is, so the brief's hashes are taken
after the last step that changes a file.

### A session with no workflow hands forward

A person working in a plain session, with no workflow run, wants to stop for
the day. They write a handoff brief directly; with no run to hold it, the
brief is kept somewhere tomorrow's session can be pointed at, and it records
the reasoning and the files named.

## Scope Boundary

**In:**

- Compaction in place as the default at the context line for every role:
  workers first, then coordinators on a workflow run, then the two top-level
  supervising sessions. That covers the size each role compacts at and how
  far it clears the context the harness fills before any work, how a
  workspace turns compaction on for a role, what the session keeps current for
  itself and what the summary must carry, and sending the session back to its
  run, its note and its record once the compaction is done.
- What a supervising session needs before it may compact: what it writes to
  its record as it goes, what it re-reads afterwards, and what happens to a
  message or wake that arrives while a compaction runs.
- The check that a session keeps its identity through a compaction as niwa
  sees it, read before any role's default is switched on.
- A session being able to tell its own context size, correctly right after a
  compaction, wherever it runs.
- A deliberate statement a stopping session makes at the end of a run, when it
  parks, or when it can't continue: its reasoning in plain words, where its
  work already lives, and a bounded set of files it hands forward, each
  provably the file it meant.
- A way for any session to make that statement, with or without a workflow
  run behind it, kept with the session's own state so it goes wherever the
  session goes.
- Telling the instance cleanup which files were handed forward, and what
  counts as handed forward before named files have anywhere to go after the
  instance is removed.
- The difference between that statement and the note a session keeps for
  itself through a compaction, which hands nothing forward and lets nothing
  go.
- A closing step at the end of a run that confirms the work is pushed and that
  no stray file is left, and comes before the statement.

**Out:**

- Any new successor route, or changes to the one that exists. A session that
  can't continue is still handed over the way it is today, and its successor
  reads the brief like any other reader. Checking the successor's copy of the
  named files at takeover is not part of this feature.
- Choosing the moment of a compaction from outside the session, such as a
  command sent to a running session. Compaction fires at a size.
- A second brief format for supervising sessions. They write the same brief
  as workers; the part listing their standing rules and its size budget
  belong to separate work.
- Where the closing step and the brief step sit inside a work-on run's final
  states. That stretch is being redesigned for #1230, and placement waits for
  that design. Writing a brief outside a work-on run isn't held by it.
- The remover, the kept set, the move of named files into it at a reap, and
  the command that says a unit is over. This feature only writes what they
  read.
- Build cleanup at the end of a run, and how long transcripts live.

## References

- #1527, the missing route for a session at its context line.
- #1230, the redesign of the end of a work-on run that holds where the closing
  step and the brief are placed.
- tsukumogami/niwa#545, on hook entries in launch settings being assigned as a
  whole.

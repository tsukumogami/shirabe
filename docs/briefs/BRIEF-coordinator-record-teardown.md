---
schema: brief/v1
status: Accepted
problem: |
  The coordinate skill keeps one coordinator's state in two stores, the GitHub
  record and the coordinator's koto session, so every state change is made and
  tested twice, GitHub is still the default, and a discipline coordinator can't
  use the session at all.
outcome: |
  A coordinator at either scope keeps its state in its own koto session and
  nowhere else. A maintainer of the skill changes one store, a person reads a
  coordinator's state through koto's session view, and GitHub carries only what
  is GitHub's own: pull requests, checks, reviews, merges and issues used as work.
motivating_context: |
  The coordinator's session became a working record: a coordinator moved onto it,
  ran a dispatch-to-merge loop on it, was handed off twice by import, and its
  owner read its state through koto's session view and said that was enough. The
  GitHub record was kept beside it as the default and the fallback. That fallback
  is now the cost, and this brief frames removing it.
---

# BRIEF: Tear down the GitHub coordinator record

## Status

Accepted

This brief frames the removal only. The removal itself waits until no
coordinator still runs on the GitHub record.

## Problem Statement

A coordinator is the long-running session the coordinate skill drives: it hands
units of work to other sessions, verifies what they push, and lands it. Its
state (what it holds, what it has decided, what it is waiting on, who it has
told) has to survive a crash, a restart and a move to another host.

For most of the skill's life that state lived on GitHub. At roadmap scope it is
one issue, `Coordinator record: ROADMAP-<name>`, whose body is a set of markdown
tables rewritten whole on every write, with an append-only stream of marked
comments beside it. At discipline scope it is a draft pull request whose diff is
a handoff file committed to `docs/disciplines/<name>.md`. The skill reads the
body back through a markdown codec that must reproduce it byte for byte, keeps
every write under GitHub's body limit, and trusts an entry only after reading
its author's collaborator permission.

The coordinator's koto session can now hold the same state, one key per
section, and a coordinator has run on it end to end. But the GitHub record was
never taken away, and the people who work on and with the skill pay for that on
every change:

- **A maintainer does every state change twice.** One read seam serves the
  state from either store, and the write core still renders the session's state
  as an issue body and parses it back, just to validate a write that never goes
  near GitHub. Adding a column to a holding means changing a markdown table, its
  codec, a byte budget sized for an issue body and two backends, then testing
  against both.
- **A coordinator's owner still has to choose, and gets the old answer by
  default.** A new coordinator opens a GitHub issue unless someone passes
  `--store session`. One already on its session still keeps a stub issue, which
  exists only so the start-up search can find the row that points away from it.
- **A discipline coordinator can't get off GitHub at all.** Discipline scope
  refuses the session store, so a rotation still commits its state to a branch
  and carries it on a pull request that never merges. It's the one place the
  skill writes coordinator state into a repository.
- **Readers outside the coordinator depend on the issue.** A few entry kinds
  (unit cost, milestone verdicts and failures, goal-fit judgments) are posted as
  comments on the record issue because that's where outside readers look, and a
  roadmap's progress notes link to them. Those readers would lose their target
  with the issue.
- **A reader of the skill's designs is told the wrong store.** About a dozen
  shipped designs say the record on GitHub is where holds, pauses, decisions,
  the teardown handoff and the dispatch path keep their facts. Each stays right
  about its logic and is wrong about where the facts live.

Nothing here stops a coordinator from running today. The cost is a second store
that every change has to carry, and one scope that can't leave it.

## User Outcome

The people this changes things for are the skill's maintainers and the person
who owns a coordinator.

A maintainer who changes what a coordinator remembers makes the change once, in
one store, and tests it once. They don't touch a markdown table, a byte budget
meant for an issue body, or a second backend, and the designs they read name the
store that is really there.

An owner who starts a coordinator, at roadmap or discipline scope, has nothing
to choose. It starts on its session, opens no issue and commits no file.

The person who owns a coordinator reads its state through koto's view of the
session, the same way they already did when they signed it off. When they want
to see a pull request, a check run, a review or an issue that is a unit of
work, they look at GitHub, because that is still where those live and the
coordinator still reads them live there.

Readers outside the coordinator still find the entries they read today: the
unit-cost figures, and the milestone verdicts a roadmap's progress notes point
to. They find them somewhere that survives without a coordinator issue.

A coordinator that is still running on the GitHub record when the removal is
ready is never touched mid-run. It moves to its session at its next start, or
finishes where it is.

## User Journeys

### A new roadmap coordinator starts after the removal

The owner of a new roadmap starts a coordinator for it. The coordinator opens
its koto session, finds no prior state and starts empty. No issue is created and
nothing searches GitHub for a record. On a restart it resumes the same session,
and on another host it imports it. Its holds, pauses and decisions are read from
the session right before each merge, as they were read from the issue before.

### A discipline rotation hands over to the next rotation

A coordinator holding a standing discipline (say, CI health for a week) reaches
the end of its rotation. Today it commits a handoff file and leaves it on a
draft pull request for its successor to read. After the removal the successor
reads what the outgoing rotation left from the session's keys, the way a roadmap
coordinator's replacement reads its predecessor. No branch, file or pull request
is involved.

### The owner of a coordinator that started on the GitHub record

The owner of a coordinator that began before the removal sees it still mid-run
on its issue when the removal is ready to build. They don't stop it. It keeps
running on the release it started with. At its next start, on a release that
can still read the record, the owner has it move its state onto its session
with the move the skill already ships, or lets its rotation end. Only after
every such coordinator has moved or finished does anything that reads or writes
the GitHub record come out.

### A cost reviewer or a roadmap reader looks for an entry

A cost reviewer totalling what last week's units spent goes looking for the
unit-cost entries. A roadmap reader follows a link in a roadmap's progress
notes to the milestone verdict behind a status change. Each finds the entry
where the removal put it, which is not on a coordinator issue, and the entry's
text is what it would have been.

### A maintainer amends the skill after the removal

A maintainer wants a new column on a holding. They add it to the state's JSON
validation and to the one writer that owns that key, then run the suites
against the session alone. A structure check refuses any script that tries to
parse a record body or source the old record library, so a back door can't
grow back.

## Scope Boundary

**In scope:**

- Removing the GitHub record and everything that exists only because of it:
  the record scripts and their markdown codec, the issue container and the
  search that finds it by title, the comment stream and the
  collaborator-permission reads that authorise entries, the per-run choice of
  store and the stub issue a moved coordinator keeps, and at discipline scope
  the committed handoff file and the rotation's pull request.
- Keeping, under the session, every guarantee the record's write core gave:
  one writer per key, a compare before a write, the per-column grammars, and
  the checks that keep private repository names and tokens out of anything that
  leaves the host.
- Bringing discipline scope onto the session, since removing its handoff file
  and pull request leaves it no other store.
- Settling where the outward entries go and what their readers read instead.
  The brief doesn't pick the destination; the requirements do.
- A dated amendment to each shipped design that names the record as the store,
  keeping its logic with only the storage calls moved, and superseding the
  record container design.
- An order of removal that never touches a live coordinator.

**Out of scope:**

- Anything that is GitHub's own and stays there: pull request state, checks,
  reviews, mergeability, issues used as units of work, the merge-order block a
  person reads on a pull request, and the CI merge-last gate's reads.
- The coordination pull request body of a coordinated `/execute` run, which was
  already moved onto that run's session by separate work.
- Moving any live coordinator off the GitHub record, or changing how a running
  coordinator reads its state. Coordinators move themselves at their next
  start.
- New koto features. The removal uses the session store, the import and the
  session view as they ship today.
- Adding anything new to the coordinator's state. This removes a store; it
  doesn't redesign what is stored.
- The teardown archive and worker transcripts, which are host-local files and
  not coordinator state.

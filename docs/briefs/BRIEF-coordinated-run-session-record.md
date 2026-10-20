---
schema: brief/v1
status: Draft
problem: |
  A coordinated `/execute` run keeps the facts it runs on, which node went to which pull
  request, the head each merge is pinned to, whether the cascade ran and whose run it is,
  as lines in the coordination pull request's body. Anyone with write access can edit
  them, they go stale, they land on the default branch, and a run that moves can't adopt
  its own merged nodes.
outcome: |
  Whoever runs a coordinated effort can stop it, move it to another workspace and resume
  it through its merge-last gate from the run's own record. The person reviewing the
  coordination pull request reads an index that is current at every step, and the default
  branch's history carries the description and nothing else.
motivating_context: |
  The coordinator's own state moved from a GitHub issue into its koto session in the
  previous piece of this work (the coordinator session record). A coordinated `/execute`
  run follows the same pattern one level down, which the design that put its state in the
  pull request body chose while koto sessions were machine-local and couldn't move.
  Session import now moves them, so the reason no longer holds. Three open bugs come from
  the body being the store: shirabe#733 and shirabe#901 (a resumed run can't adopt its
  merged nodes), shirabe#785 (a stale index with no room for follow-ups) and shirabe#748
  (the coordination pull request listed as its own row).
---

# BRIEF: The coordinated run's session is its record

## Status

Draft

This brief frames moving a coordinated `/execute` run's control-plane facts out of the
coordination pull request's body and into the run's own koto session, with the body
rendered from them.

## Problem Statement

A coordinated plan lands as several node pull requests and one coordination pull request
that merges last. `/execute` drives the whole run: it opens each node's pull request, pushes
it, waits for review and merges, and when every node is in, runs the finalization cascade
and lands the coordination pull request. To do that across pauses that can last as long as
a human review, it has to remember what it has done. Today it remembers by writing to the
coordination pull request's body. One index line per node records the node's pull request
and the head it pushed; `topic=` and `outcome=` lines record the run; a run marker records
whose run it is. The body is the run's only record of which nodes it has dispatched, of the
head every merge of a node is pinned to, and, once the cascade has deleted the PLAN, of the
node list itself.

That arrangement costs the people who use it in five ways:

- **A moved run can't take its own work back.** When a run's execute session is lost or
  moves to another host, the fresh session gets a new run id, finds its own merged node
  pull requests marked with the old id, and stops as if they were someone else's
  (shirabe#733, shirabe#901). The only way through today is to copy the old id into the new
  session by hand.
- **The record is editable by anyone with write access.** A merge is pinned to a head read
  back from text a person or another tool can change, so the check meant to stop a merge on
  an unverified head rests on the least protected place the run writes.
- **The index stops being true.** Nothing refreshes it after a node merges, so a finished
  run's coordination pull request shows its nodes as open at their pre-merge heads, and a
  follow-up pull request opened against a node after review has no way into it
  (shirabe#785). It also lists the coordination pull request as one of its own rows, which
  the merge-last gate has to special-case out (shirabe#748).
- **Run state reaches the default branch.** `/execute` merges the coordination pull request
  without a squash message, so the whole body lands: the squash commit carries the index,
  each node's head and the run's bookkeeping lines.
- **One step earlier, the same pattern.** `/scope`'s `intent=` line in the same body is a
  copy of `/scope`'s result that `/deliver` reads back off the page.

None of this is the body's fault as a page for people. The person reviewing a coordinated
effort reads the index and the merge order there, and the reusable merge-last gate in CI,
which has no koto session to read, finds the coordination pull request by its declaration
marker and reads the node list from the body. The problem is that the same text is also the
run's memory.

## User Outcome

Whoever drives a coordinated effort, a person or a coordinator session dispatching
`/deliver` workers, can stop a run partway, move it into another workspace, and pick it up
there. The resumed run knows which nodes it opened, which have merged and at what head, and
that it is still the same run, so it adopts its merged nodes without anyone copying an id by
hand, and it carries on through the merge-last gate. When the move also takes `/deliver`'s
leg out from under it, the coordinator either gets the result anyway or is told plainly
that the leg won't finish.

The person reviewing the coordination pull request reads an index that matches what has
happened: every node with its current state and head, follow-up pull requests listed under
the node they belong to, and no row for the coordination pull request itself. It stays that
way through the cascade, because the run re-renders the page from its record at every step.
Editing the page by hand changes what the page says, not what the run believes.

A maintainer reading the default branch's history after a coordinated effort lands finds the
coordination pull request's description and nothing from the run's bookkeeping.

## User Journeys

### A coordinator hands a run to a replacement mid-flight

A coordinator session has dispatched a `/deliver` worker on a coordinated plan with several
nodes. After the first node merges, the coordinator is stopped and a replacement starts from
an imported copy of its record, in a fresh workspace on the same host. The worker's run is
imported alongside. The replacement resumes the run, which adopts the merged node as its own,
pushes and lands the rest, and reaches the merge-last gate with every node accounted for. The
coordinator reads the run's result from its leg, or a clear report that the leg was lost and
what state the run reached.

### A worker resumes after its execute session is gone

A worker resuming a coordinated run finds the execute session that opened it was removed
with its host directory. The run's record survives wherever the run's chosen store keeps it,
so the worker resumes as the same run, adopts the merged nodes and continues, without a
hand-set run id.

### A reviewer reads the coordination pull request at the end

A maintainer opens the coordination pull request once every node has merged, to decide
whether to land it. The index shows each node merged at the head it merged at, the one
follow-up pull request opened after merge review listed under its node, and the merge order
the plan set. The CI merge-last gate counts the follow-up too, and holds the coordination
pull request until it has merged.

### A maintainer reads the default branch

A month later, a maintainer runs `git log` on the default branch to see what the coordinated
effort did. The squash commit for the coordination pull request carries its title and
description, the same first part a reader saw at the top of the page, and none of the run's
index, heads or run lines.

## Scope Boundary

**In scope:**

- The run's control-plane facts as its record: the node-to-pull-request map, each node's
  pushed head, follow-up pull requests recorded against a node, the cascade's verdict, the
  coordination pull request's number as `/scope` hands it over, and the run's identity.
- The coordination pull request's body as a rendering of that record, re-rendered at every
  transition including the cascade, without the self row.
- The squash message `/execute` passes when it merges: the body's first part only.
- A run that moves between workspaces keeping its identity and adopting its own merged
  nodes, and what happens to `/deliver`'s inner leg to `/execute` after the move.
- The choice of where a run's record lives, made once at the run's start, with GitHub the
  default.
- Reuse of the pieces the coordinator session record built for the same job: its read seam,
  its per-run store choice, and its resume, carry-across and import opener.

**Out of scope:**

- What stays on GitHub on purpose. The CI merge-last gate keeps finding the coordination
  pull request by its marker and reading the node list from the body, the merge-order block
  stays on the page, and a pull request's state, checks, review and mergeability stay live
  reads that the run never stores.
- Changing `/execute`'s default store, or moving any existing run onto the session. Runs
  started before this lands, including this feature's own, stay on the pull request body.
- The single-pr path, which already keeps its pushed head in koto.
- Removing the coordinator's GitHub issue record, and anything in the coordinate skill that
  removal touches. That is separate later work.
- Proving a move between hosts. The journeys above move a run between workspaces on one
  host; a move to another host rides the same import, and exercising it is later work.

## Open Questions

- With GitHub as the default store, what does a default run read its facts from: the body,
  as today, behind the shared seam, or its session with the body as the fallback a host
  without the session reads? The PRD settles it against the requirement that no `/execute`
  script parses a head or a node line off a pull request body.

None of these questions block the brief.

## References

- `docs/designs/current/DESIGN-scope-then-execute.md` — the design that put the coordinated
  run's state in the coordination pull request; its sixth decision is the one this feature
  revisits.
- `docs/designs/current/DESIGN-coordinator-session-record.md` and
  `docs/prds/PRD-coordinator-session-record.md` — the same move for the coordinator's
  record, whose seam, store choice and opener this feature reuses.
- `references/coordination-strategy.md` — the coordination contract that says the state
  lives on the coordination pull request.

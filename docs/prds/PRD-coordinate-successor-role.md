---
schema: prd/v1
status: Draft
problem: |
  A coordinator hands over to its successor through the worker dispatch
  path, which needs a unit pick can hand out and recognizes a successor
  only by a roadmap positional. A manager lane whose only open unit owes
  a verdict can't dispatch its successor at all, and a discipline
  director's successor brief comes out as a manager's.
goals: |
  Any coordinator, manager or director, over a roadmap or a discipline,
  can dispatch its successor whenever its handover rules call for one,
  and the successor starts in the role its predecessor's record holds.
  A reviewer can confirm that from the successor's brief and first
  report alone.
upstream: docs/briefs/BRIEF-coordinate-successor-role.md
source_issue: 1862
---

# PRD: Coordinator Successor Dispatch With Its Role

## Status

Draft

## Problem Statement

A coordinator that reaches its handover line has to start a successor
that continues its run in the same role. The only scripted way it has to
start any session is the worker path: `pick_facts` lists units, `pick`
chooses one, `dispatch_check` checks the topic, and `dispatch-worker.sh`
renders the brief and launches the session. A successor goes through
that path dressed as a worker, with entry point `coordinate` and grant
`own`.

That path fails a successor in two ways. Every new dispatch has to name
a unit `pick_facts` listed, and a unit whose milestone verdict is owed
is refused with exit 10. So a manager lane whose only open unit owes a
verdict can't hand over before giving that verdict (#1862). And
`dispatch-worker.sh` treats a `coordinate` brief as the run's own
successor only when its first positional names a roadmap whose scope
slug matches the run's. A discipline run is started with `--discipline
<name> --host <owner/repo>` and has no roadmap positional, so its
successor brief is taken for a new lane and renders `role=manager`,
whatever the record's Run `role` row holds (#1861). The brief renderer
also refuses those flags in a `coordinate` brief's arguments, so a
discipline successor brief can't be written in the shape the opener
takes.

A milestone verdict on the named-roles work recorded both: neither role
reached a successor, so the claim that each role hands off to a
successor in the same role has no evidence behind it.

## Goals

- A successor dispatch succeeds for both roles at both scopes,
  whatever state the run's units are in.
- The successor's role is the predecessor record's Run `role` row,
  carried as data and checked at the successor's start, never inferred
  or described in prose.
- Worker dispatch keeps every check it has today.

## User Stories

The journeys are the BRIEF's (User Journeys in
`docs/briefs/BRIEF-coordinate-successor-role.md`): a manager lane owing a
verdict hands over, a discipline director hands over mid-rotation, a
record with no role row is refused, and a reviewer checks the handover.
Each story below names the requirement that carries it.

- As a manager lane coordinator whose only open unit owes a verdict, I
  want to dispatch my successor before I give the verdict, so that the
  run doesn't stall at my handover line (R1, R2).
- As a discipline director, I want my successor dispatched as a
  director over the same discipline and host, so that the rotation
  continues under the role it was opened with (R3, R4, R5).
- As a coordinator whose record has no role row, I want the successor
  dispatch refused with the command that fixes it, so that no successor
  starts in a role nobody set (R6).
- As a reviewer of a milestone, I want to confirm from a successor's
  brief and first report that it holds its predecessor's role, so that
  the handover claim has evidence I can read (R7, R8).
- As a coordinator that restarts while its successor dispatch is still
  pending, I want the restart to settle that dispatch, so that the run
  never gets two successors (R9).

## Requirements

### Functional

- **R1. Successor dispatch at both scopes.** A coordinator dispatches
  its own successor through `dispatch-worker.sh` (or a mode of it the
  design names), never by hand, at roadmap scope and at discipline
  scope, in either role. All four combinations work: manager or
  director, over a roadmap or a discipline.
- **R2. No unit gate on a successor.** A successor dispatch isn't
  refused for the state of any unit: not for a milestone whose verdict
  is owed, not for a unit a pause holds, not for a unit a decision
  parks, and not when pick lists no open unit. Those refusals keep
  holding every worker dispatch.
- **R3. Successor recognized at discipline scope.** A `coordinate`
  brief is the run's own successor when its scope and name equal the
  run's own: the roadmap whose scope slug matches the run's, as today,
  or the `--discipline <name>` and `--host <owner/repo>` the run was
  opened with, as `coord-log.sh run-facts` reports them. For such a
  brief the role is the record's Run `role` row, at either scope.
- **R4. Discipline successor brief takes the opener's shape.** A
  discipline successor's brief and its dispatch prompt both carry
  `/shirabe:coordinate --discipline <name> --host <owner/repo> --role
  <role>`, with the name and host taken from the run's own facts, not
  typed by the coordinator. A run whose facts can't be read is refused
  before anything is written.
- **R5. Same run, not a new lane.** A successor at either scope starts
  as a takeover of its predecessor's run: its opener continues the
  predecessor's record and links the two runs, so `coord-log.sh
  chain-start` on the successor prints the predecessor's chain start.
  A discipline successor started on or before the rotation's end date
  (the opener's window rule) continues that rotation rather than
  opening the next one.
- **R6. No role row, no successor.** With no Run `role` row on the
  record, a successor dispatch exits 1 before any holding row, leg or
  session is created, and its message names `state-stored-set.sh --run
  role`. This holds at both scopes.
- **R7. Role as data, once.** The successor's role reaches it only as
  `--role <role>` on the invocation line, written by the dispatch script
  from the record. The brief input has no role field the coordinator
  fills, and the brief template adds no line about the role: in a
  rendered successor brief, the only line naming `manager` or
  `director` is the invocation line.
- **R8. Role checked at start, named in the first report.** These two
  existing behaviors stay as they are, at both scopes: the opener
  refuses a `--role` that differs from the record it continues
  (`role-mismatch`) unless the change flags name an intervention from
  above, and the successor's first report names its role on its record
  line ("Role: manager" or "Role: director").
- **R9. One successor at a time.** A successor dispatch writes a row on
  the record before it launches, as a worker holding does. While that
  row's dispatch status reads `dispatching` or `dispatched`, a second
  successor dispatch from the same run is refused with a non-zero exit
  that names the pending successor. A row that reads `dispatch-failed`
  doesn't block a new attempt. A coordinator that restarts while the
  row reads `dispatching` settles it the way it settles a worker's
  (confirm the session or re-launch), never by dispatching a second
  successor.
- **R10. Worker paths unchanged.** A worker brief still carries no
  `--role`. A `coordinate` brief naming a different roadmap still
  renders `--role manager`. A `--rebrief` or `--releg` still renders the
  role the holding row's entry point calls for and never reads the Run
  `role` row. An input `role_change` on a successor dispatch is still
  refused with exit 1.

### Non-functional

- **R11. Tested in the script suites.** R2, R3, R4, R6, R7, R9 and R10
  each have a case in the coordinate scripts' test suites that fails
  on today's code and passes after the change.
- **R12. Documented where coordinators read.** The coordinate skill's
  Roles section and the brief template's `role` paragraph describe the
  successor dispatch at both scopes, including the discipline
  invocation line.

## Acceptance Criteria

- [ ] A manager lane whose only open unit is a milestone with its
  verdict owed dispatches its successor: the dispatch exits 0 and the
  successor's brief carries `--role manager`.
- [ ] A worker dispatch naming that same verdict-owed milestone is still
  refused with exit 10.
- [ ] A successor dispatch exits 0 when pick lists no open unit, when
  the only open unit is held by a pause, and when it is parked on a
  decision.
- [ ] A discipline run whose record holds `role=director` dispatches a
  successor whose brief's invocation line and dispatch prompt both read
  `/shirabe:coordinate --discipline <name> --host <owner/repo> --role
  director`, the name and host being the run's own.
- [ ] A discipline run whose record holds `role=manager` dispatches a
  successor whose invocation line carries `--role manager`, and a
  roadmap run whose record holds `role=director` dispatches one carrying
  `--role director`.
- [ ] Changing the record's Run `role` row between two dry dispatches
  changes the rendered `--role` to match it, at both scopes.
- [ ] A successor started from each scope's brief continues the
  predecessor's record: `coord-log.sh chain-start` on the successor
  prints the predecessor's chain start, and a discipline successor
  inside the window carries the same rotation.
- [ ] A successor dispatch at either scope with no Run `role` row exits
  1, no holding row, leg or session exists afterwards, and its message
  names `state-stored-set.sh --run role`.
- [ ] A discipline successor dispatch whose run facts can't be read
  exits non-zero with nothing written.
- [ ] A second successor dispatch while the first row reads
  `dispatching` or `dispatched` exits non-zero naming the pending
  successor; after the row reads `dispatch-failed`, a new attempt is
  accepted.
- [ ] A `coordinate` brief naming a different roadmap still renders
  `--role manager`, a worker brief has no `--role`, a `--rebrief` of a
  held lane renders no `--role` unless `role_change` is given, and
  `role_change` on a successor dispatch exits 1.
- [ ] In a rendered successor brief at each scope, the only line naming
  `manager` or `director` is the invocation line.
- [ ] A successor started with a `--role` other than its record's is
  refused `role-mismatch` at both scopes, and an accepted successor's
  first report record line reads "Role: <the predecessor's role>".
- [ ] SKILL.md's Roles section and `references/brief-template.md`
  describe the successor dispatch at both scopes, and the discipline
  invocation line appears in the brief template.
- [ ] The suites hold a case for each requirement R11 lists that fails
  on the base commit and passes at the change's head.

## Out of Scope

- A discipline successor refusing a predecessor opened from an older
  template (#1860), which follows this work.
- Dispatching a discipline coordinator as a new lane. A lane the
  coordinator dispatches stays a roadmap manager.
- Changing the role at handover. A role change goes through a
  `--rebrief` from above, as today.
- The merge seat's teardown step and the text of the coordinator
  handoff brief. Both are held for a ruling, and this PRD touches
  neither.
- When a coordinator decides to hand over. Its handover line and cap
  are unchanged.

## Decisions and Trade-offs

- **Whether a successor goes through `pick` at all is left to the
  design.** The BRIEF raised it as a framing question. The requirement
  that matters (R2) is that no unit's state blocks a successor; whether
  that's done by a pick choice with no unit or by a separate dispatch
  route is a mechanism choice.
- **Whether a successor holds a record row is settled as a
  requirement, not left open.** R9 needs the pending successor visible
  on the record, so it has to be recorded somewhere a restart reads. The
  design picks the row shape.
- **Discipline lanes stay out.** The named-roles design deferred a
  discipline route for lanes. Only the successor route is needed to close
  the verdict's gap, so the PRD adds that and nothing wider.

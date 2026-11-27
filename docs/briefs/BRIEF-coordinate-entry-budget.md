---
schema: brief/v1
status: Accepted
problem: |
  A coordinator dispatched under niwa's coordinator profile still starts at
  about 61K tokens of context, against a target below 35K, because a leading
  `/shirabe:coordinate` invocation expands the coordinate skill's whole
  SKILL.md into the first turn, whatever the coordinator is about to do.
outcome: |
  A coordinator dispatched under the profile, its prompt led by the
  /shirabe:coordinate invocation, reads turn-0 context below 35K (59.2K
  before the profile); a session dispatched without the profile and an
  interactive session start as they do today.
---

# BRIEF: Coordinate Entry Budget

## Status

Accepted

## Problem Statement

niwa's coordinator dispatch profile trims what a dispatched coordinator
starts with: it denies tools coordinators never call and leaves out the
bundled skills and account connectors. Under it the harness costs about
27.4K tokens at turn 0, and every item it still keeps is one coordinators
call, so nothing more comes out of the harness without breaking a
coordinator.

The rest of turn 0 is the coordinate skill. A dispatched coordinator's prompt
leads with `/shirabe:coordinate`, and the slash command expands SKILL.md in
full: about 96 KB, 32.5K tokens. Most of it applies only in situations a
given start never meets, such as a takeover, an import, a milestone verdict
or a teardown, and about 15 KB is written for the skill's maintainers. Every
coordinator pays for all of it on every turn of its tenure.

## User Outcome

A coordinator dispatched under the profile, its prompt led by the
/shirabe:coordinate invocation, reads turn-0 context below 35K (59.2K before
the profile); a session dispatched without the profile and an interactive
session start as they do today.

The deferred tools a coordinator relies on, SendMessage, CronCreate,
CronList, CronDelete, TaskStop and background Bash, still load and work. A
rule a coordinator needs still reaches it at the moment it acts on it.

## User Journeys

- A dispatcher starts a coordinator under the profile, and it reads its
  brief, opens its run and reaches its first report from a turn 0 under 35K.
- A person starts a coordinator by hand in an interactive session, and it
  starts as it does today.
- A coordinator takes over a run another session left, and the takeover
  rules are in front of it when it acts on the takeover.
- A maintainer adds a rule to the coordinate skill, and a check tells them
  before merge when the entry would grow past its budget.

## Scope Boundary

In: what the coordinate skill puts into turn 0, where its situational and
maintainer text lives instead, and how the entry's size is held over time.

Out: any change to the harness, to niwa or its profile, to Claude Code, or
to workspace configuration; the per-visit cost of the `wait` state; and the
cost of turns after turn 0 beyond what the smaller entry saves.

## Downstream Artifacts

- [DESIGN-coordinate-entry-budget](../designs/DESIGN-coordinate-entry-budget.md)

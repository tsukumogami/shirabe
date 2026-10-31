---
schema: design/v1
---

# DESIGN: Standing rules that carry their provenance

## Status

Proposed

## Context and Problem Statement

A coordinator (a manager over one lane, or a director over managers) is
replaced every few hours as its context fills, and each successor starts from
the record its predecessor left plus a brief. The record's Standing section
is the one place a rule survives a handoff with its source attached, and it
holds only five kinds of event a person owns: a pause, a go-ahead, an
approval, an answer and an assignment. Each row names an Owner and a Relayed
by in free text and a Set time, and nothing else about where the words came
from. A row ends by being deleted (`state-stored-set.sh --end`), so a rule
the owner took back leaves no trace a successor can read.

Everything else a coordinator runs under lives outside the record. Process
rules (how to report, what not to touch, which commands to avoid) ride in the
brief as prose, copied forward from one successor to the next. A role's
definition and the coordinator's own judgment calls never enter any record.
The Run section has `rules` and `briefs` digest rows meant to pin the files a
coordinator ran with, but nothing writes or compares them. A long-lived
lineage therefore accumulates rules nobody can trace: a successor asked why it
follows one can say only that its brief says so. A rule the owner reversed can
survive in the brief after the Standing row that recorded it was deleted,
and be acted on again.

koto's decision record (`docs/designs/DESIGN-decision-record.md` in koto) is
being built to answer "who decided this, on what authority, and does it still
stand" for every delegated decision, and it defines a reversal: a `reverse`
decision aimed at the original, with standing rules, a race rule, and a
status every reader computes the same way. An owner ruling is a decision a
person made. This design reuses those fields and that reversal for standing
rules rather than defining a second set beside them.

The design has to settle four things:

1. The field names a rule row carries, and where process rules live beside
   owner rulings.
2. What marks a row as the owner's word, and who can make it so.
3. How rows written before the change are read by every tool that reads the
   record today.
4. Whether a successor that continues a predecessor's run may reverse a
   decision made below that predecessor, a question koto's decision record
   left open for this work to answer.

Out of scope: compiling a successor's brief from the rows and a receiver's
restatement at handoff, which are later work that reads the interface this
design names; who settles a step, escalation targets and grants, which the
authority model owns; and the record's container, which this design adds
rows and reads inside.

## Decision Drivers

- **One set of provenance fields.** Who decided, when, on what authority,
  and whether it still stands come from koto's decision record. A rule row
  cites a decision; it doesn't copy its fields.
- **One reversal mechanism.** A rule the owner takes back is reversed through
  koto's `reverse`, and every reader reads its status from koto. No status
  field, end flag or supersession column in the row stands in for it.
- **Inside the existing container.** Rows go in `record/standing`, written by
  `state-stored-set.sh` through the write core, under the one-writer rule and
  the size the record already carries. No new key outside Standing; nothing
  touches `record/decisions` or `record/reversals`.
- **Old rows keep working.** Sixteen scripts and the schema read Standing
  today (pause reads in pick, the dispatch check, the land check and the
  merge; pick's assignment units; the handover read; the carry; the progress
  view; the write core's comparison).
  Each must read a row written before this change exactly as it does now, and
  a lineage started before it keeps every rule it had.
- **Attribution, not authentication.** koto records a person's handle as
  handed text, and an agent can claim to be a person. The design can't make a
  claim true; it can make every claim attributable and keep a coordinator from
  minting owner rulings out of its own prose.
- **Checkable by someone who didn't write it.** Each of the milestone's
  outcomes has to be something a reviewer can run against a real record and
  see hold or fail.
- **koto ships first.** The decision commands aren't released yet. Whatever
  can land before them should, and nothing should need rework when they
  arrive.

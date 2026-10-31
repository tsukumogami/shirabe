---
schema: brief/v1
status: Accepted
problem: |
  A coordinator is replaced every few hours, and the rules it runs under
  reach its successor as free-text record rows and copied brief prose. The
  successor can't say who set a rule, when, or whether it still stands, so
  rules nobody gave pile up and a rule the owner took back can be followed.
outcome: |
  A successor asked why it follows any standing rule answers with who said
  it, when, where the words are and whether it still stands. A rule the owner
  reversed reads as superseded and isn't acted on, and a lineage started
  earlier keeps every rule it had.
---

# BRIEF: Standing rules that carry their provenance

## Status

Accepted

## Problem Statement

A coordinator session, whether it manages one lane of work or directs
several lanes, is replaced every few hours as its context fills. The
successor continues from the coordinator's record and from a brief its
predecessor left. Rules travel between them in two ways. The record's
Standing section holds a handful of person-owned events, such as a pause or
a standing answer, each with an owner and a relayer the coordinator typed
in as free text. Everything else, from how to report to what not to touch,
rides in the brief as prose, copied forward from one successor to the next.

Neither carrier keeps a rule's source. A successor asked why it follows a
rule can say only that its record or its brief says so. Over many handoffs
that does two kinds of damage. Rules accumulate that nobody actually gave:
a predecessor's own judgment, written once as if the owner had said it, is
copied forward as an owner ruling. And a rule the owner reversed can keep
going: the Standing row is deleted when it ends, but the copied prose that
repeated it survives, so a later successor acts on it again with nothing in
the record to say it was withdrawn.

The people who pay for this are the owner, who can no longer tell which of
their rulings a coordinator is acting on, and every successor, which
inherits rules it can neither trace nor safely drop.

## User Outcome

When this exists, a successor coordinator can account for every rule it
runs under. Asked why it follows one, it names who said it, when, where the
words can be read, and whether the rule still stands, without trusting its
predecessor's prose. When the owner takes a rule back, every coordinator
holding that rule reads it as superseded, with the reason, and acts on it no
longer, including a successor that starts long after the reversal. A
lineage that began before this change keeps every rule it had: rules that
carried an owner and a time keep them, and rules with no source show up as
inferred and waiting to be confirmed rather than disappearing or passing as
the owner's word.

## User Journeys

### The owner asks where a rule came from

The owner reads a director's start report and sees a rule they don't
remember giving. They ask the director where it came from. The director
answers with the rule's class (the owner's ruling, the skill's text, the
charter, or the coordinator's own inference), its date and a pointer the
owner can follow to the words, and an inferred rule is marked as one rather
than presented as the owner's.

### The owner takes a rule back

The owner tells the director that a rule they gave last week no longer
holds. The reversal is recorded once. The next successor of the director,
and every lane coordinator that carried the rule down, lists it as
superseded with the owner's reason, and none of them acts on it at any
later tick.

### A successor starts on an older lineage

A coordinator lineage has run through many handoffs from before this
change. Its next successor starts and lists every rule its predecessor ran
under. Rules the record held with an owner and a time keep both. Rules that
lived only in the brief come in once, marked inferred and flagged for
confirmation, so the owner can confirm, cite or drop them.

### A lane coordinator receives the owner's ruling through its director

The owner gives the director a ruling that applies to one lane. The lane's
coordinator records it citing what the director recorded, so it reads as
the owner's word one level down, and only the owner can take it back. A
ruling the director makes on its own reads as the director's, not the
owner's.

## Scope Boundary

**IN:**

- Every standing rule a coordinator runs under, owner rulings and process
  rules alike, kept in the coordinator's record with where it came from.
- Answering who said a rule, when, where the words are and whether it still
  stands, for every rule, through one read a successor can run.
- A rule the owner reverses reading as superseded wherever it was carried,
  reversed the same way any other recorded decision is reversed, with no
  second way of taking a rule back.
- Lineages started before the change keeping their rules, with whatever
  source they had and the rest marked inferred.
- An answer to whether a successor that continues a run may reverse a
  decision made below its predecessor, which the decision record left open.

**OUT:**

- Compiling a successor's brief from the recorded rules, and checking the
  brief against them at each start. That is the next piece of work, and it
  reads what this one records.
- A successor restating what it owes before reading its predecessor's notes,
  and blocking its first dispatch on unconfirmed rules.
- Giving the owner's verbatim words a durable home a pointer can reach after
  the conversation that held them is gone.
- Who may settle a step, escalation targets and grants, which the
  workspace's authority model owns; and the record's container itself, which
  this work adds rows to rather than reshaping.
- Repairing existing briefs by hand.

## Downstream Artifacts

- `docs/designs/DESIGN-coordinator-standing-rule-provenance.md`: the
  technical approach, covering the row fields, how the owner's word is
  marked, how older rows are read, and the answer on successor reversal.

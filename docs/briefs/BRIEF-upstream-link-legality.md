---
schema: brief/v1
status: Accepted
problem: |
  The `upstream:` field is a document's only durable record of its lineage,
  but nothing says what makes a link legal and nothing checks. Illegal links
  are written by hand and by the skills themselves, and they are found later
  by a reader who follows one and lands nowhere.
outcome: |
  An illegal upstream link fails when it is written rather than when someone
  follows it, and the skills that record links stop producing the illegal
  kind. A reader walking a durable document's chain lands on documents that
  still exist and that sit above it rather than below.
motivating_context: |
  Two issues arrived from opposite directions -- one about a link pointing
  the wrong way, one about a link pointing at something scheduled to be
  deleted -- and each proposed a fix that left the other's case out. Framing
  them together is what makes a single rule reachable instead of two special
  cases that meet at a carve-out.
---

# BRIEF: Upstream Link Legality

## Status

Accepted

Phase 4 jury returned all-PASS on content quality and structural format. Two
framing questions were deferred rather than answered here, and the downstream
PRD's Decisions and Trade-offs section is where each closes:

- Which mechanism replaces a durable document's link to an ephemeral one —
  recording the nearest durable ancestor instead, or recording nothing and
  requiring the document to carry the context itself. The two differ in what a
  reader gets: a link that may cross into a chain not describing this feature,
  versus no link and a document that has to stand alone.
- Whether "absorb the context" is a real obligation with a checkable shape or
  an aspiration. If a document is to be the head of its own lineage, something
  has to say what it must carry for that to be true. The PRD owns the
  requirement; whether it is checkable is a design question below it.

## Problem Statement

A shirabe document records where it came from in one field: `upstream:`. That
field is the whole audit trail. A reader who wants to know why a design exists
follows it up to a PRD, to a brief, and out to whatever framed the work. When
a link in that walk is wrong, the trail does not degrade — it ends.

Nothing in the system says what makes a link legal, and nothing checks. Two
independent failures follow, and they are independent in a way that matters:
they fail on different properties, they are introduced by different actors, and
a fix for either one leaves the other untouched.

**A link can point the wrong way.** The chain runs ROADMAP → BRIEF → PRD →
DESIGN → PLAN, and each format reference states which type sits above it. None
of that is enforced. A hand-authored document naming a downstream document as
its upstream validates clean today. The repository's own corpus carries eight
such edges — briefs naming a design, a plan, and other briefs — and every one
of them has been sitting there passing validation.

**A link can point at something with a scheduled death date.** ROADMAP and PLAN
declare Working lifecycle: they are deleted when their work completes. Every
other type is Durable. A durable document naming a working one is a reference
that is correct on the day it is written and dangling on the day the cascade
runs, and nothing between those two days says a word. This failure is worse
than the first, because the formats do not merely permit it — they direct it. A
brief's only stated legal upstream is a ROADMAP, which is a working artifact.
Following the rule as written produces the defect.

The two failures share one cause. Legality is written in prose, spread across
format references and skill files, and it is written for a human author who is
reading the reference at the moment they write the field. Nothing carries it to
the moment a link is actually created — not by hand, not by a skill, and not by
a parent skill handing a path to a child. So the rules are simultaneously
documented and unavailable, and the corpus drifts from them without resistance.

There is a third property of this problem worth naming, because it is what
makes a durable answer possible rather than a patch. The system already has one
case of an upstream that exists, is correct, and cannot be recorded: a public
document whose upstream is private. The answer there is settled — the field is
omitted, the context is absorbed, and the document stands as the head of its own
lineage. An ephemeral upstream has the same shape: a real parent that cannot be
durably named. Whether those are one rule or two is the question this work has
to answer rather than assume.

## User Outcome

An author who writes an illegal upstream link finds out immediately, from the
validator, in a message that names the document and says which property failed
— not months later, from a reader who followed the link and found nothing.

An author running a chain never has to know the rule. The skills that record
upstream links stop producing the illegal kind on their own, so the common path
produces legal lineage without the author thinking about it. Where an upstream
cannot be recorded, the document that would have pointed at it carries the
context instead and reads as a proper starting point rather than a document with
a hole where its parent should be.

A reader who walks a durable document's chain lands on documents that exist and
that sit above it. The audit trail is the thing it claims to be.

A maintainer who adds a new artifact type declares its legality once, next to
the type's other structural facts, and the rule is enforced from that
declaration. Nobody has to find four skill files to learn what a type may point
at.

## User Journeys

### An author hand-writes an inverted link

A maintainer writes a brief and, reaching for context they had open, sets
`upstream:` to the design they were reading. They run `shirabe validate` before
committing. The validator names the file, names the edge, and says a BRIEF may
not name a DESIGN as its upstream because the design sits below it in the chain.
The author corrects the field before the commit exists. Today this document
validates clean and ships.

### A chain runs under a roadmap

An author invokes the tactical chain for a feature that a roadmap already
sequences, handing the roadmap's path in. The chain reads the roadmap — the
feature's framing, its sequencing rationale, its neighbours — and the brief it
produces is grounded in that content. What the brief records as its lineage
follows the rule this work settles, and the author is told what was recorded
and why. Some months later the roadmap's features all land and the cascade
deletes it. Nothing the chain produced breaks.

### A reader audits a shipped feature

An engineer looking at a shipped behaviour opens the design that describes it
and walks upward: design to PRD, PRD to brief, brief to whatever framed it.
Every hop resolves. The walk ends at a document that is the head of its lineage
and says so, rather than at a path that used to be a file.

### A maintainer adds an artifact type

Someone introduces a new document type. They declare, alongside its required
sections and valid statuses, which types may sit above it and whether it
survives the completion of its own work. The validator enforces both from that
declaration on the next run. They do not edit a check, and they do not go
looking for the prose that used to hold the rule.

## Scope Boundary

**IN**

- A stated definition of what makes an `upstream:` link legal, covering both
  properties: the type of the document named, and whether that document
  survives its own completion.
- A decision, with recorded reasoning, on whether the rule for an upstream that
  cannot be durably referenced is one rule covering both the private case and
  the ephemeral case, or two rules that happen to sit beside each other.
- Enforcement of that definition by `shirabe validate`, so an illegal link
  fails at authoring time rather than at reading time.
- The recording behaviour of the skills that write `upstream:` fields, changed
  in each skill's own contract, so the chain stops producing links the
  definition forbids.
- A named, ahead-of-time list of any document currently in the corpus whose
  validation result the chosen rule deliberately changes.
- Keeping whatever consumes these links today working. A link is not only an
  audit trail for a human reader; at least one automated consumer walks upward
  through it to find a document it then acts on. If the chosen rule removes a
  link, the consumer that depended on it needs another way to find what it was
  looking for, and supplying that is part of this work rather than a follow-up.

**OUT**

- Repairing the dangling references already in the corpus. Five committed
  briefs name paths that no longer exist; those are tracked separately and are
  a repair job, not a rule job. This work defines and enforces the rule, and
  deliberately leaves the existing violations for their own change.
- Whether a single upstream may have more than one downstream document of the
  same type. That is a separate defect in the chain's cardinality model with
  its own exploration; it is about how many children a parent may have, not
  about whether a given edge is legal.
- Removing support for a document having several upstreams. The formats permit
  it, the corpus uses it, and the chain walk handles it correctly. Multi-valued
  upstream is orthogonal to whether any one of those values is legal.
- Indexing the strategic document directories. Pulling visions and strategies
  into the document index would draw them into an orphan check that was never
  written for them; legality can be decided from a document's own name and its
  upstream's name, so the index is not needed for it.
- Teaching the cascade to strip inbound references when it deletes a working
  artifact. That is the repair-shaped answer to the same problem, and it treats
  the dangling link as something to clean up afterwards rather than something
  that should never have been written. If the rule is right, no durable document
  names a working one at deletion time and there is nothing to strip. Keeping a
  consumer's discovery route working is a different matter and is IN, above.

## References

- `docs/briefs/BRIEF-chain-cardinality.md` — the Lineage Shapes section's
  per-link cardinality tables and the three kinds of one-to-many.
- `docs/prds/PRD-chain-cardinality.md` — the Terms section's definitions of
  chain, root, posture, and terminal status.
- `docs/designs/current/DESIGN-chain-cardinality.md` — the decisions behind the
  multi-valued upstream field and the parent upstream contract.

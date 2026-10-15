---
schema: brief/v1
status: Draft
problem: |
  /scope credits a hop's document after four structural checks. Every other
  format rule `shirabe validate` knows for that type is held only by a prose
  step the agent may skip, and rules covered only by notice-level checks,
  such as the banned words, are held by nothing.
outcome: |
  A /scope hop is held until its document passes every error-level check for
  its type and the few notice-level checks raised to blocking there, each
  failure naming the rule and the line, so the validator can become the lock
  on document-format rules and their failures can be counted per rule.
motivating_context: |
  The work-on and execute workflows already gate their outputs on the checks
  shirabe ships, with findings that carry a registered rule id. /scope is the
  workflow that writes the most documents and has the thinnest gate. Until it
  has one, no document-format rule's prose can safely leave the instructions an
  agent loads, because nothing would catch the breach.
---

# BRIEF: scope document gates

## Status

Draft

## Problem Statement

A /scope run walks four hops, BRIEF, PRD, DESIGN and PLAN, and each hop is
credited by a completion check that reads the document on disk. That check
asks the validator four questions only: does the file carry a supported
schema, are the required frontmatter fields present, does the frontmatter
status match the body, and are the required sections there. It is narrow on
purpose, because it answers "did this hop land?", and it says nothing about
whether the document follows the rest of its format.

The rest of the format is enforced by a sentence. The hop's procedure tells
the agent to run `shirabe validate` on the new document and stop the chain on
a violation. Nothing checks that the agent did it, or read the result
correctly. When it doesn't, a document with a bad status value, an upstream
link that points nowhere or points the wrong way, a stale reference, a broken
absorb declaration, or a PLAN whose issue table and dependencies don't hold
together is credited as landed. The next hop builds on it, and the breach
surfaces at CI on the pull request, after the whole chain rests on it.

Some rules are worse off. The banned-words list in the writing-style rules is
checked by the validator only at notice level, so even an agent that runs the
validator faithfully is told nothing it has to act on. The only thing holding
those rules is the prose that states them, which means that prose can never
come out of the instructions an agent loads: there would be nothing left to
catch a breach.

There is also no record. When a rule is broken at a hop, nothing names it in
a form anyone can count, so there's no way to tell which rules agents break
often and which they never break.

## User Outcome

An author running /scope, or a worker a coordinator dispatched to run it,
finds a hop held until its document passes the checks that matter for its
type. When it fails, the failure says which rule was broken and where, in the
same shape the work-on gates already use, so the fix is a direct edit rather
than a hunt through validator output.

A maintainer deciding whether a document-format rule's prose can be taken out
of a directive has a single answer to check: the gate at that hop runs the
check that enforces the rule, and blocks on it. Taking the prose out is still
someone else's later decision; what changes is that the lock exists.

Someone reading the run's exported gate events can count failures per rule,
because each one carries the rule's registered id.

## User Journeys

### An author's PRD hop is held on a broken upstream link

An author runs `/scope` on a feature. The PRD lands with an `upstream:` that
names the BRIEF at a path that doesn't exist, after a rename. The hop doesn't
advance. The finding names the rule for upstream links that must resolve, the
file and the line of the field. The author fixes the path and the hop goes
on, without waiting for CI to find it after the DESIGN and PLAN are written.

### A worker's DESIGN is held on a banned word

A worker dispatched by a coordinator runs `/scope --auto`. Its DESIGN uses a
word the writing-style rules ban. Today that is a notice the worker can
ignore. With this feature the hop holds, the finding names the banned-words
rule and the line, and the worker rewrites the sentence before going on.

### A maintainer checks that a rule is locked before withholding it

A maintainer is weighing whether the banned-words instruction can be removed
from what an agent loads during a hop. They look the rule up in the rule
registry, see that the scope hop gate checks it at blocking level, and know
that removing the prose won't leave the rule unenforced. The removal itself
happens through the withholding work, not here.

### A reader counts failures per rule

Someone reading the run's exported gate events counts how often each
document rule failed at a scope hop, grouped by the registered rule id the
findings carry, the same way they already count the work-on gates.

## Scope Boundary

**In scope:**

- A gate at each of /scope's four hops that runs every error-level check
  `shirabe validate` has for that hop's document type, and holds the hop on a
  failure.
- Raising, at that gate only, the specific notice-level checks that guard a
  rule likely to be withheld, starting with the banned-words check.
- Findings that carry a registered rule id and the location of the failure,
  in the shape the work-on gates use.
- Registry entries for every rule the gate can report.

**Out of scope:**

- Removing any prose from the hop directives, or marking any rule eligible to
  withhold. Withholding belongs to the later withholding work.
- Changing the validator's own severities. A notice raised at this gate stays
  a notice in CI and everywhere else.
- The general lifecycle a check moves through (shadow, warn, block, retire),
  which is separate work.
- Gates on the documents other skills write outside /scope, such as a
  /design or /prd run on its own.
- Offline ablation or long evaluation runs to measure the effect; measurement
  is live.

## Open Questions

- Which notice-level checks beyond the banned words, if any, guard a rule
  likely to be withheld and are reliable enough to block on? The PRD settles
  the list.
- Does the full check run inside the completion check, or as a separate gate
  beside it? The completion check deliberately avoids whole-document
  validation, and the DESIGN owns the answer.

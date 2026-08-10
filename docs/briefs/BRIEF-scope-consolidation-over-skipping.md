---
schema: brief/v1
status: Accepted
problem: |
  `/scope` decides whether each artifact is worth producing before that
  artifact exists, so nothing in the decision can see whether there would
  have been detail worth recording. The reader-economy reason the decision
  was meant to serve is documented only inside `/brief`, and the mechanism
  implementing it there cannot be reached when `/scope` drives.
outcome: |
  An author runs `/scope` and every artifact the chain would produce is
  actually written. The run ends with the smallest set of documents that
  still carries everything worth recording, and a document is only removed
  once the one that would replace it exists and is shown to carry it.
motivating_context: |
  The skip logic was built to spare the human reader repetitive artifacts
  restating one thing at three altitudes. What shipped spares the producer
  instead: every gate fires before the artifact exists, and the party that
  benefits from not doing the work makes the call.
---

# BRIEF: scope-consolidation-over-skipping

## Status

Accepted

Framing for the change that removes `/scope`'s produce-or-skip gates, so the
whole tactical chain runs on every invocation and a consolidation judgment
after each artifact is written is the only thing that reduces the set. The
four questions this brief deferred are closed in the downstream PRD's
Decisions and Trade-offs section.

## Problem Statement

`/scope` walks BRIEF to PRD to DESIGN to PLAN and can decline to produce any
of the first three. Each declination is decided by a gate that runs before
the artifact exists. `/brief`'s gate reads whether an Accepted BRIEF is
already on disk; `/prd`'s reads whether an Accepted PRD is; `/design`'s reads
three structural predicates over the PRD body. None of them reads the thing
they are deciding about, because the thing they are deciding about has not
been written yet. A gate cannot know whether a BRIEF would have said
something the PRD will not, because no BRIEF exists to compare against.

The declination was supposed to serve the reader. Three documents that
restate one problem at three altitudes cost a reader three reads for one
idea, and an obvious concept articulated three times reads as ceremony. That
is the reason the decision exists. It is documented in exactly one place:
`skills/brief/references/phases/phase-0-setup.md`, which is explicit that the
fold-into-PRD path "exists to avoid a redundant second document, never to
leave the framing unpersisted," and that folding is "NOT a license to skip
articulation." At `/scope`'s own gate layer that reason appears nowhere. The
rationale recorded there is different: `skills/scope/references/phases/phase-1-discovery.md`
states the auto-skip exists because "the parent MUST NOT silently overwrite
an Accepted durable artifact." That is protection against clobbering a
settled document, which is a real concern and an unrelated one.

So two mechanisms share one name. The reader-facing one lives in `/brief`
and cannot fire when `/scope` drives it: `/scope` invokes children as
`/<child> <topic-slug>`, a bare slug reads as `/brief`'s freeform-topic
entry, and freeform entry is disposed of before the fold branch is reached
with "the framing does not exist yet. Produce a standalone brief." Even if
it did fire, nothing would receive what it folds. `/prd` records an upstream
BRIEF's path and transitions its status, but its drafting phase draws the
problem, goals, stories, and exclusions from its own scoping conversation and
never reads the brief's body. The producer-facing mechanism, meanwhile, works
exactly as built, and its effect is that a `{name, reason}` entry lands in
`chain_skipped:` and the chain moves on. No content moves anywhere.

The consequence is that the reader gets the worst of both. When the chain
runs in full, the BRIEF and the PRD restate the same four things: problem,
outcome against goals, journeys against stories, boundary against exclusions.
That overlap is designed in rather than accidental — four of the BRIEF's five
required sections are renamed PRD sections with equivalent content rules —
and it shows up at roughly constant size across every complete set in the
repo. When the chain skips instead, whatever the skipped artifact would have
carried is simply never written, and no one finds out what was lost, because
the judgment was made before there was anything to lose.

## User Outcome

An author who runs `/scope` on a feature gets every artifact the chain covers
actually written, and finishes with the smallest set of documents that still
carries everything worth recording. Nothing is dropped on a guess about what
it would have said.

No document is judged the moment it is written — there is nothing to judge it
against yet, and guessing whether the document that follows will carry its
content is the same premature call this feature exists to remove. Each
document's fate is settled one step later, once its successor lands: when the
PRD arrives, the run asks whether the BRIEF still does work the PRD does not.
When two documents turn out to hold one idea, the run says so, folds the
content into the one that stays, and leaves a record of what happened — so the
author can see the reduction rested on both bodies rather than on an estimate
made in advance.

A reader landing on the result reads one document per distinct idea. If a
feature's framing and its requirements were the same conversation, that
reader finds one PRD that carries the problem, the outcome, the journeys, and
the boundary, not a BRIEF and a PRD that say it twice. If they were different
conversations, both documents are there, and each earns its read.

A reviewer auditing the chain can tell which documents were consolidated and
into what, without reconstructing it from absence.

## User Journeys

### Framing and requirements are genuinely different conversations

An author opens `/scope` on a feature whose problem is contested and whose
requirements are extensive. The chain writes the BRIEF, then the PRD. The
consolidation judgment runs after the PRD lands, compares what the BRIEF
holds against what the PRD carries, and finds the BRIEF's framing did work
the PRD does not repeat — the journeys drove the requirement set rather than
being restated by it. Both documents stay. The author sees the judgment and
its reason, not a silent pass.

### Framing and requirements are one conversation

An author opens `/scope` on a feature whose framing takes two paragraphs and
is not in dispute. The chain writes the BRIEF anyway; the framing gets
articulated once, properly, in a document. The PRD is then written from it.
The consolidation judgment runs and finds every durable thing the BRIEF holds
is present in the PRD — its problem in the Problem Statement, its outcome in
Goals, its journeys in User Stories, its boundary in Out of Scope. The BRIEF
is absorbed: the PRD is confirmed to carry all four concerns, the BRIEF is
removed, and the links that pointed at it are re-pointed. The author ends
with a PRD that reads complete and no second document restating it.

### A reader lands cold on a consolidated artifact

Someone unfamiliar with the feature opens the PRD months later. The problem
is stated there in full — they do not have to find a BRIEF that no longer
exists to understand what was broken. The requirements cite rather than
re-narrate whatever upstream survives, so nothing is read twice, and nothing
is missing.

### A reviewer audits what the chain did

A reviewer reads the PR and wants to know whether the run produced one
document because there was one idea, or because the machinery declined to
write the others. The run's record tells them which artifacts were written,
which were absorbed, into what, and on what finding — so "there is no BRIEF
here" is answerable rather than ambiguous.

## Scope Boundary

**In scope**

- `/scope`'s per-child gates: whatever replaces the decide-before-it-exists
  shape, including the gate vocabulary each child's gate binds to.
- The consolidation judgment itself: when it runs, what it reads, what
  verdicts it can reach, and how those verdicts are recorded.
- A receiving mechanism wherever content is meant to move, plus a check that
  the move actually happened. A recommendation that content be carried
  forward is not a mechanism.
- The reader-facing reason for reducing the artifact set, documented at the
  layer that implements the reduction rather than only in a neighbouring
  skill.
- Whatever the four tactical children (`/brief`, `/prd`, `/design`, `/plan`)
  must change to receive absorbed content or to cite rather than re-narrate
  their upstream — including `/prd`'s current non-consumption of the BRIEF it
  names as upstream.
- The interaction with `shirabe validate`: what a consolidated artifact must
  satisfy, and whether the validator has anything to say about it.
- Evals for every skill whose behavior changes.

**Out of scope**

- `/charter` and the strategic chain. Whether the model generalizes to
  VISION to STRATEGY to ROADMAP is a question the DESIGN answers in prose;
  no strategic-chain behavior changes here.
- Renaming or re-scoping the artifact types themselves. If the DESIGN
  concludes the type boundary is the real problem, it says so and stops
  rather than acting on it.
- Reversing a consolidation after the fact as a supported operation, unless
  the DESIGN finds it falls out of the mechanism for free.
- The `upstream:` link convention, which is already settled: an upstream
  points at the nearest artifact actually produced above it and is omitted
  when nothing was.
- The gate vocabulary's cardinality. Gates bind to the three existing shapes;
  this work does not add a fourth.
- Retrofitting artifacts already on disk. Existing BRIEF/PRD pairs stay as
  they are.

## Downstream Artifacts

- `docs/prds/PRD-scope-consolidation-over-skipping.md` — the requirements
  written from this framing. Its Decisions and Trade-offs section closes the
  four questions this brief deferred.

## References

- `skills/scope/references/phases/phase-1-discovery.md` — the shipped gates
  and the clobber-protection rationale recorded for them.
- `skills/scope/references/phases/phase-2-chain-orchestration.md` — child
  invocation by topic slug, R14 child isolation, and the structural
  file-existence check that treats a returning child with no artifact as a
  failure.
- `skills/brief/references/phases/phase-0-setup.md` — the fold-into-PRD path
  and the reader-economy intent stated there.
- `skills/prd/references/phases/phase-3-draft.md` — the PRD drafting
  instructions that draw framing from the PRD's own conversation.
- `references/parent-skill-pattern.md` — the three gate shapes and the
  retirement of the fourth.
- `references/pipeline-model.md` — the settled rule that an upstream points
  at the nearest artifact actually produced.
- `crates/shirabe-validate/src/formats.rs` — the per-type required-section
  contracts a consolidated artifact would have to satisfy.

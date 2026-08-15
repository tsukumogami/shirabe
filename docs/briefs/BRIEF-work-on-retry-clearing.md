---
schema: brief/v1
status: Accepted
problem: |
  A blocking finding in one of /work-on's review phases sends the work back to
  be fixed, but nothing invalidates the verdict that sent it back. The one step
  that would invalidate it names a koto subcommand that does not exist, and the
  gate it is meant to trip tests presence rather than freshness.
outcome: |
  A blocking retry produces a genuinely fresh verdict. The phase that sent the
  work back cannot advance until a new results artifact exists, a clearing step
  that fails says so on a stream operators do not redirect away, and the three
  review phases behave the same way as each other.
---

# BRIEF: /work-on Retry Clearing

## Status

Accepted

The framing stops at the contract a retry owes the next round. Which command or
state-machine shape enforces it is DESIGN altitude and is deliberately left
open here; one live option changes another repository, so it is settled through
a recorded decision rather than picked in passing.

## Problem Statement

`/work-on` runs three review phases in sequence after implementation:
`scrutiny`, `review`, and `qa_validation`. Each ends its round by writing a
results artifact into koto context -- `scrutiny_results.json`,
`review_results.json`, `qa_results.json` -- and submitting a `passed` outcome.
Each also has a `blocking_retry` outcome for the case where a reviewer found
something that has to be fixed, which routes the workflow back to
`implementation` so a coder agent can fix it.

Nothing invalidates the results artifact on that return trip. Each phase gates
on `type: context-exists`, which asks whether a key is present and nothing else.
The artifact from the round that just failed is present. So when the workflow
comes back around, the gate is satisfied by the very verdict the retry was meant
to supersede, and the phase can advance on it.

One phase does try to close this. `scrutiny`'s retry loop tells the agent to
delete the stale artifact with `koto context remove`. koto has no `context
remove` -- its context group is `add`, `get`, `exists`, and `list` -- so the
command exits with `error: unrecognized subcommand 'remove'` and the artifact
stays exactly where it was. The failure is quiet, because every koto invocation
in a workspace with accumulated sessions prints migration noise to stderr, which
makes `2>/dev/null` the routine operator reflex, and that filter swallows the
unrecognized-subcommand error along with the noise.

The same retry loop also states its own mechanics backwards. It says the stale
artifact may make the gate fail, prompting a fresh run, and then offers deletion
as tidy-up. The causality runs the other way: a stale artifact makes the gate
*pass*, and removal is the only thing that would produce a fresh run. A reader
who trusts the prose concludes the deletion is optional. It is the entire
mechanism.

The two phases downstream are worse off, not better. `review` and
`qa_validation` carry the same presence-only gate and the same return path, and
document no clearing step at all, so the same staleness is there with nothing
naming it. And because every `blocking_retry` returns to `implementation`, which
runs forward into `scrutiny` again, a retry raised in `review` re-enters
`scrutiny` and `review`, and one raised in `qa_validation` re-enters all three.
A reader who assumes the problem is confined to the phase that fired the retry
has it backwards: the retry walks through every review phase at or above it, and
each one's gate is held open by its own previous verdict.

The result is a workflow that reports a clean review panel that no reviewer ran
in that round, on the runs where a reviewer had just objected -- which is
precisely when a stale pass is most expensive.

## User Outcome

An agent whose implementation is sent back by a blocking finding gets a genuinely
fresh verdict on the next pass. The phase that raised the finding will not
advance until a results artifact for the new round exists, so a `passed`
submission carried by last round's artifact is refused by the workflow rather
than accepted by it. The three review phases behave identically, so a reader who
understands the retry contract in one understands it in all three.

When the step that forces the fresh verdict cannot do its job -- an unwritable
store, a koto that does not have the verb -- the run says so in a sentence an
operator can act on, on a stream that survives the `2>/dev/null` they are already
typing, and stops rather than continuing under a false success. And the prose in
the phase files describes what actually happens, so a maintainer reading the
retry loop can predict the workflow's behaviour from it.

## User Journeys

### The scrutiny panel sends the work back

A `/work-on` run reaches `scrutiny`, one of the three reviewers returns a
blocking finding, and the orchestrating agent submits
`scrutiny_outcome: blocking_retry`. The workflow returns to `implementation`, a
coder agent fixes what was found, and the run walks forward into `scrutiny`
again. The trigger is the re-entry. The outcome shape: the previous round's
`scrutiny_results.json` no longer satisfies the phase's gate, so submitting
`scrutiny_outcome: passed` without re-running the three reviewers does not
advance the workflow -- the state holds and names the condition that held it.
Once the reviewers run and write this round's artifact, the phase advances
normally.

### A blocking finding lands two phases downstream

The same run gets past `scrutiny`, and it is the code-review panel that objects.
The agent submits `review_outcome: blocking_retry` and the workflow returns to
`implementation`. The trigger is a retry raised below `scrutiny` rather than at
it, and the journey is distinct because the return path crosses a phase that
already passed: implementation, then `scrutiny`, then `review`. The outcome
shape: neither phase advances on the verdict it recorded last time round. This
is the journey that fails today even if only `scrutiny` is repaired, which is
why the boundary below holds all three phases in.

### The clearing step cannot do its job

An agent on a machine where koto cannot write to the session store -- or against
a koto build without the verb the step depends on -- reaches the same retry, with
koto's stderr redirected to `/dev/null` as usual. The trigger is the clearing
step failing rather than succeeding. The outcome shape: the failure announces
itself in a readable sentence on stdout, the agent is told what to submit instead
of a success, and the workflow does not advance past the phase carrying the stale
verdict. A failure that presents as success is the one outcome this journey rules
out.

### A maintainer edits the retry directive a year later

Someone changing how a review phase records its results opens the phase file and
edits the block that clears the previous round. The trigger is the edit, not a
workflow run. The outcome shape: a test that reads the shipped text out of the
phase file and runs it against a real koto session fails, so the edit is caught
before it merges. A pasted copy of the block inside a test would keep passing
after the shipped text drifted, which is the failure mode this whole class of
defect is made of.

## Scope Boundary

### In

- The retry-clearing contract for all three retry-bearing review phases of
  `/work-on`: `scrutiny`, `review`, and `qa_validation`.
- The prose that states it, in
  `skills/work-on/references/phases/phase-4a-scrutiny.md`,
  `phase-4b-review.md`, and `phase-4c-qa.md` -- including the retry loop's
  stated causality, which is currently backwards and does not survive this work.
- `skills/work-on/references/review-panel-orchestration.md`, the summary a
  reader meets before the three phase files. It describes the retry path and
  says nothing about what happens to the previous round's results, so leaving it
  alone would keep the incomplete account in the place most readers start.
- The three corresponding states in `skills/work-on/koto-templates/work-on.md`,
  so the contract is enforced by the workflow and not only described to the
  agent. The brief holds in that the enforcement is structural; what shape it
  takes is downstream.
- A failure mode for whatever step forces the fresh verdict that does not
  present as success, with its diagnostic on a stream that survives
  `2>/dev/null`.
- Test coverage that exercises the contract against real koto sessions rather
  than asserting it in prose.
- `/work-on`'s evals, updated where the phase contract changed, and run.

The three-phase coverage is a decision, not an oversight. The three phases sit
on one traversal: every `blocking_retry` routes to `implementation`, and
`implementation` routes forward into `scrutiny`, so a retry re-enters every
review phase at or above the one that raised it. A fix confined to `scrutiny`
would clear the first gate of every retry and leave the next two satisfied by
the previous round's artifacts. That is not a smaller fix; it is a fix that
leaves the same hole two states further along the same path.

### Out

- **Which mechanism forces the fresh verdict.** That is DESIGN altitude. The
  brief holds in the contract -- a retry must not advance on the previous
  round's verdict -- and not the command that implements it. One live option
  reaches a second repository, which is what makes it worth deciding rather
  than assuming.
- **`/execute`'s settled-branch record.** The same defect class one skill over,
  already fixed and merged. It is precedent to read, not work to redo.
- **The rest of `/work-on`.** Every other phase, gate, and directive stays as
  it is. This is the retry-clearing contract and nothing adjacent to it.
- **Making `context_assignments:` work.** Probing the option space turned up
  that a transition's `context_assignments:` block is silently dropped by koto
  and never reaches the context store, which means the `failure_reason`
  assignments already in `work-on.md` are no-ops. It is a real defect and a
  wider one than this brief frames; it is recorded so the DESIGN does not
  propose a mechanism built on it, and left for its own issue.
- **A general freshness primitive for koto gates.** If the answer turns out to
  need something koto does not have, the boundary is the smallest addition that
  serves these three phases -- not a gate type that solves staleness for every
  future workflow.

## References

- `docs/designs/current/DESIGN-settled-branch-record.md` -- the merged fix for
  the same defect class in `/execute`, whose own sweep found this one.
- `skills/execute/scripts/settled-branch-record_test.sh` -- the test pattern
  that extracts shipped text from the template at run time.

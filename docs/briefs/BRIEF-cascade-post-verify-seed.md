---
schema: brief/v1
status: Accepted
problem: |
  The finalization cascade verifies its own work by re-running the lifecycle
  chain check seeded on the PLAN it deleted moments earlier. The seed path is
  gone, the validator returns L05, and every successful single-pr run reports
  cascade_status: partial while accusing itself of a bug it did not commit.
outcome: |
  A cascade that finalized correctly reports that it did, and a cascade that
  did not finalize still fails loudly. The distinction survives the case where
  the chain legitimately folded every artifact away and left no anchor behind.
motivating_context: |
  Filed three times independently over ten weeks (shirabe#186, shirabe#307,
  shirabe#328) and never triaged, because the test harness cannot fail on it:
  no scenario in run-cascade_test.sh passes --push, so the post-verify branch
  has never been executed by CI.
---

# BRIEF: Cascade post-verify seed

## Status

Accepted

The framing stops at what the self-verification must decide and what evidence
it is allowed to decide from. Both Phase 4 reviewers returned PASS.

Two questions go downstream. The PRD and design own where the surviving anchor
is read from — recomputed from the chain's canonical paths after the commit, or
carried forward from what the cascade recorded as it transitioned each document.
They also own what evidence separates a chain that folded every artifact away
from one that never finalized. `skills/execute/SKILL.md` notes that on the
default branch, long after the fact, those two are indistinguishable and are
both treated as complete. This brief's stance is that the cascade is not in that
position: it has just watched its own transitions succeed or fail, and holds
evidence the after-the-fact check never had. The design decides which of that
evidence to use, not whether any exists.

Accepted under `/scope`'s non-interactive mode: this run was dispatched as a
background worker with no interactive author, so the Phase 5 approval gate took
the recommended default on an all-PASS jury rather than blocking.

Edited after acceptance to correct the suite's scenario count from thirty-six to
eighteen. The higher figure counts each `scenario_*` line twice — once at its
definition and once at its call in the runner. The claim it supports is
unaffected: `--push` still appears in no scenario at all.

## Problem Statement

`/execute`'s finalization cascade does its work correctly and then reports that
work as failed.

There are two problems here, not one, and they are framed together deliberately.
The first is the false report. The second is the untested branch that let it
live for ten weeks. Fixing the first without the second just resets the clock.

The cascade walks a finished chain to its terminal state: the BRIEF and PRD flip
to Done, the DESIGN moves to `docs/designs/current/`, and the PLAN is deleted —
all staged into one atomic commit. It then re-runs the chain-targeted lifecycle
check to confirm what it just did. That confirmation step is seeded on the PLAN.
The PLAN no longer exists, because the cascade deleted it seconds earlier in the
commit it is now verifying, so the validator reports the seed path as
unresolvable and exits non-zero. The cascade reads that as evidence of its own
malfunction, records the step as failed, and downgrades the whole run to
`cascade_status: partial`.

Nothing about this is intermittent. There is no fallback seed and no handling
for the missing-path result anywhere in the script, so the outcome is the same
on every run: a chain that finalized perfectly is reported as one that did not.

The cost is not the wrong word in a report. It is that the run's own summary
stops carrying information. A `partial` that appears on every successful run is
indistinguishable from a `partial` that means something, so the signal the
verification step exists to produce has been dead since the step was written —
and an author who learns to expect `partial` will not look twice at the run
where it was real. Three separate authors filed this as a bug rather than
recognising it as noise, which is the clearest measure of how much the false
report costs.

The reason it survived is separate from the defect and is the second half of the
problem. The self-verification only runs on a real push with staged files, and
no scenario in the cascade's test suite exercises that path. The suite has
eighteen scenarios and passes `--push` in none of them; the only mention of
the flag is a comment noting its absence. CI runs the suite on every change and
has been green throughout. A deterministic defect in a branch no test enters is
invisible for as long as nobody runs the thing by hand and reads the output
closely.

There is one more wrinkle the framing has to hold, and it is why this is not
simply a wrong path. The chain being verified does not always leave an anchor
behind. `/scope`'s consolidation judgment can absorb a document into the one
below it at any hop, so a chain can legitimately finish with nothing durable at
all — the DESIGN folded into the PLAN, and the cascade then deleted the PLAN.
That is a complete chain with no surviving artifact to check against. It has to
be treated as success. A chain that never finalized at all also has no anchor
the check can pass on, and it has to be treated as failure. Those two look alike
from the outside, and telling them apart is the substance of the work.

## User Outcome

A `/execute` run that finalizes a chain correctly ends by saying so. The report
reads `completed`, the verification step reads `ok`, and an author who sees
`partial` has learned something true about that run rather than reading the
same word they see every time.

The verification keeps its teeth. A run whose chain did not actually reach its
terminal state still fails, still says which part did not land, and is still
distinguishable at a glance from a run that succeeded. The guard becomes
trustworthy in both directions rather than being disabled in one.

An author whose chain folded every document away gets the same clean result as
one whose chain left a DESIGN behind. Nothing about the shape `/scope` chose for
their artifact set changes whether `/execute` can confirm its own work.

And the next person to change this code finds out from the test suite rather
than from a hand-run months later. The branch that carries the self-verification
is executed by CI, so a regression that reintroduces the false failure is caught
where it happens.

## User Journeys

### An author finishes a single-pr plan and reads the run report

An author who scoped a chain themselves and is now running `/execute` on it
reaches a plan that implements as one pull request. The cascade transitions the
chain, deletes the PLAN, commits, and verifies. The report comes back
`completed`, with the verification step recorded as passing.
The author closes the run without investigating anything, because there is
nothing anomalous in it. Today the same run reports `partial` and sends them to
read a cascade they have no reason to distrust.

### An author's chain did not actually finalize

An author runs `/execute` on a chain where the upstream transitions could not be
applied — a document at an unexpected status, or a `finalize-chain` step that
refused. The cascade reports failure, names the step that did not land, and the
run does not claim success. The author can act on the report because it is
telling them about their chain rather than about the verification's own seed.

### An author's chain folded every artifact away

An author's `/scope` run judged that the DESIGN carried nothing the PLAN did not
and absorbed it, so the chain reaches `/execute` with the PLAN as its only
document. The cascade transitions what upstream there is, deletes the PLAN, and
finds nothing durable left standing. The run reports `completed`, and the
verification step reports that it had no anchor to check because the chain
folded — not that an anchor was missing. The author is never asked to account
for the absence, because the fold was a legitimate outcome of a judgment
`/scope` made on their behalf, and `/execute` does not second-guess it.

### A maintainer changes the cascade and CI answers

A maintainer edits `run-cascade.sh` in a way that breaks the self-verification.
The test suite fails on a named scenario that exercises the push path, in the
pull request that introduced the change. They do not learn about it from a
production run weeks later, and they do not have to reason about which branches
the suite reaches.

## Scope Boundary

**In:**

- The seed the post-cascade verification runs against, and where that seed comes
  from.
- Distinguishing a chain that finalized and left an anchor, a chain that
  finalized having folded every artifact away, and a chain that did not finalize
  — such that the first two report success and the third reports failure.
- Test coverage for the push path in `run-cascade_test.sh`, including at least
  one scenario that reaches the post-verification branch at all, and a scenario
  holding the line that a non-finalized chain still fails.
- Follow-up bookkeeping: triage of the three existing issues, one canonical and
  the other two closed against it. In scope because leaving three open reports
  of a fixed bug is its own small version of the signal problem above.

**Out:**

- The cascade's transitions — which documents it moves, to which states, in what
  order. Those are correct. Only the step that checks them afterwards is wrong.
- The `--lifecycle-chain` CLI surface and the lifecycle checks themselves. The
  validator answers the question it is asked correctly; it is being asked about
  a file that no longer exists.
- The `L06` / `WORK_ON_ALLOW_UNTRACKED_ACS` suppression path, which is unrelated
  special-casing that happens to sit nearby.
- The pre-cascade probe, which seeds on the PLAN correctly because the PLAN is
  still on disk when it runs.
- shirabe#342, gate scripts resolving against the wrong directory outside
  shirabe. Real, already filed, and does not bite work done inside the shirabe
  checkout.

## References

- `skills/execute/SKILL.md` — the seed-doc rule under the Finalization-Not-Done
  Guard, which already states the behaviour the script contradicts.
- `skills/execute/scripts/run-cascade.sh` — `lifecycle_probe()` and the
  post-cascade invocation.
- `skills/execute/scripts/run-cascade_test.sh` — the suite that does not reach
  the branch.
- `.github/workflows/check-execute-scripts.yml` — the CI job that runs it.

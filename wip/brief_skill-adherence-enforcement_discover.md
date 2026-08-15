# Discover: skill-adherence-enforcement

## Grounding

No ROADMAP supplied, so no `--upstream` and no grounding path. The
framing below is derived from a completed `/explore` run on this branch,
whose durable outputs are the decision report at
`wip/adherence_decision_report.md`, the incident record at
`wip/explore_skill-adherence-enforcement_evidence.md`, and seven research
leads under `wip/research/`.

Because those inputs are themselves non-durable, everything this BRIEF
needs from them is restated in the BRIEF's own prose. The Problem
Statement stands alone.

## Problem / Outcome Pair

**Problem.** An agent holding shirabe's skills can be handed a finished
plan and still not run it under the sanctioned workflow. It happens two
ways. The skill is never invoked, or the skill is invoked and the part
that carries the guarantees is quietly skipped. Both leave the author
with no visibility while the work happens and no durable record that the
plan's validation steps ran at all.

**Outcome.** An author who hands a plan to an agent can tell, from
outside the agent and without asking it, whether the run went through
the workflow. Where an agent has reason to depart from it, the departure
is surfaced and recorded rather than decided in private.

## Scoping Notes

**Two failure modes, not one.** The first incident: an agent built its
own task list and hand-implemented 22 plan outlines. The second: an
agent ran the skill's preflight and its task-payload script, produced a
valid payload with all six dependency edges, then never submitted it and
implemented six issues inline. Its reason was a genuine conflict between
a session instruction forbidding subagent calls and the workflow step
that spawns one child per issue.

The second mode is why the framing cannot be about discoverability. A
live probe confirmed the skill resolves and loads correctly. Both agents
could name the right path when asked afterward.

**What the feature can and cannot promise.** koto records; it does not
enforce. Its spawn primitive is a stub, and its review gates are
directive text it never verifies. So this feature cannot promise that
adversarial reviews ran. It can promise that a run is recorded, that the
record is readable from outside the agent, and that departures are
visible.

**Why a boundary sits where it does.** The mechanism the exploration
settled on enforces a contract the skill already declares (its closed
write-target set) at the moment a write happens, rather than at a
self-administered check after the work is done. Choosing among the
remaining implementation options is DESIGN altitude, not BRIEF altitude,
and is deferred.

## Journey Candidates

Four distinct entry points, each exercising the feature differently:

1. Author invokes the workflow directly and the orchestrator attempts an
   out-of-contract write.
2. A background worker receives a task brief and never reaches for the
   workflow at all.
3. An agent inside the workflow meets an instruction that forbids the
   step the workflow requires.
4. Someone asks after the fact whether a given branch went through the
   workflow.

## Framing-Shift Answer

No shift. The exploration concluded today and this BRIEF is the first
tactical-chain artifact written from it.

# Phase 4 Jury Verdict: Content Quality

**Reviewer:** content-quality
**Document:** `docs/briefs/BRIEF-skill-adherence-enforcement.md`
**Reviewed at:** references section already carrying the corrected
`docs/designs/current/DESIGN-execute-skill.md` path (line 191).

VERDICT: PASS

## 1. Problem Statement states a problem, not a smuggled solution

**PASS**

The section runs entirely on what is broken. It opens with the loss — "can
produce all of the code and none of the process. The author learns this only by
asking" — then characterizes two failure shapes, then explains why each
persists. Nothing in it tells the reader what gets built.

The closest approach to mechanism is the description of what the *existing*
skill did during the second incident: "runs the workflow's preflight, runs its
task-payload script, and produces a valid payload carrying the plan's full
dependency graph." That is evidence about the incident, not a description of
the feature.

The specific leak flagged in the review brief did not happen. "Closed
write-target set" appears exactly once in the document, in the References
section, where it belongs. The Problem Statement never mentions writes,
refusals, or any enforcement surface.

The two paragraphs most likely to leak a solution instead do diagnostic work.
"Only the absence of a registered orchestration session separates it from a
conforming run" names the discriminating property without proposing what
observes it. "Knowledge was present and unused, so supplying more of it changes
nothing" forecloses a wrong solution rather than asserting the right one.

## 2. User Outcome is outcome-shaped, not a feature list

**PASS**

A user is named in the first clause: "An author who hands a plan to an agent."
The section states what changes for that author — they "can answer 'did this run
go through the workflow?' by looking, rather than by asking the agent and hoping
the answer is accurate" — and never enumerates parts.

It matches the `outcome` frontmatter, which carries the same two claims
(detectable from outside the agent without asking it; departures "surfaced and
recorded rather than decided in private"). The body expands those into in-flight
visibility ("A conforming run is visible in the same place other orchestrated
runs are visible, and a run that never registered is visibly absent rather than
silently missing") and after-the-fact evidence.

The fourth paragraph is the section's strongest move, because it subtracts:
"The author does not receive a promise that adversarial reviews ran... a feature
that implied otherwise would be worse than one that did not." That draws the
outcome boundary honestly against the established fact that the orchestration
engine's guarantees are bookkeeping rather than enforcement, and it keeps the
section from overclaiming.

## 3. Each User Journey is concrete, and the journeys are distinct

**PASS**

All four name a user, a trigger, and an outcome shape.

- **J1 (orchestrator tries to implement inline):** an orchestrating agent inside
  an invoked workflow "reaches for a source file and starts editing it directly
  instead of delegating the issue"; the attempt is "refused at the moment it
  happens, with a reason naming what the sanctioned move is." The closing line —
  "The author never learns this happened, because nothing went wrong" — is a
  legitimate outcome shape (silent self-correction), not a missing outcome.
- **J2 (background worker never reaches for the workflow):** trigger is a task
  brief that "does not name a workflow"; outcome is that "the refusal names the
  workflow the work should run under. The worker enters it."
- **J3 (constraint forbids the sanctioned step):** the second incident's shape,
  ending in surfacing rather than private resolution — "sees which constraint,
  and sees what the agent proposes to do."
- **J4 (reviewer asks whether a branch ran the workflow):** post-hoc
  verification by "someone who was not present when the work happened."

J1 and J2 are the pair at risk of collapsing, since both end in a refused write.
They do not collapse. J1 starts inside an invoked workflow with an agent that
drifts mid-run; J2 starts with the workflow never invoked at all, and covers the
agent-launched-by-agent propagation named in Scope IN ("Carrying the enforcement
to agents launched by other agents, not only to sessions a human drives").
Different entry points, different refusal payloads, and they map to the two
distinct field incidents.

J4 earns its place by ruling out the alternatives explicitly: the answer "does
not depend on the agent's account, on the branch's commit shape, or on whether
the work looks careful, because a competent hand-rolled implementation looks
exactly like a conforming one."

## 4. The Scope Boundary has real exclusions

**PASS** — all five clear the bar.

- **Guaranteeing adversarial reviews or validation steps actually ran.**
  Plausibly assumed inside for anything named "adherence enforcement." Load-
  bearing enough that User Outcome restates it. Cites the real limit: the engine
  "records that evidence was submitted in order; it does not verify the
  evidence."
- **A workspace-level policy system for declaring required skills.** Exactly
  what an org owner would expect an enforcement feature to include. Deferred
  with a reason (placement question plus a collision with a design decision
  about which configuration layers may change a contributor's run).
- **Changing the documented precedence between session instructions and
  skills.** The strongest of the five. The second incident's root cause *was*
  that precedence, so a reader would very plausibly assume flipping it is the
  fix. The item says why not: asserting skills outrank session instructions
  "would generalize to every constraint a user or operator sets."
- **A post-hoc CI gate on the merged result.** Directly invited by J4, so a
  reader could assume it is inside. Explains the obstacle rather than waving at
  it.
- **Re-running or repairing past non-conforming work.** The thinnest of the
  five, but it clears: two live incidents drove this brief, so a reader could
  reasonably assume those branches get remediated. "The feature governs runs
  from the point it ships forward."

## 5. Open Questions defer framing details, not blockers

**PASS**

None asks whether the feature should exist.

- **Q1 (enforcement travels with the skill or is distributed by the workspace
  manager):** defers placement and routes it explicitly — "The PRD picks the
  requirement; the DESIGN picks the mechanism." The feature exists under either
  answer.
- **Q2 (what the check asserts for a multi-repo plan):** a scoped edge case with
  a stated reason — "That execution path deliberately runs without a single
  orchestration session, so a check that assumes one would report a conforming
  run as a failure." A detail about what the check asserts, not whether to build
  it.
- **Q3 (whether conflict-surfacing needs a durable record of its own):** a
  fidelity question, answerable either way without stalling the PRD.

## Findings to carry into the PRD

### Coherence: Scope IN's skill-description item vs. the Problem Statement

Scope IN's last item — "Correcting the plan-execution skill's own description,
which is currently written as an inventory of architecture rather than as the
conditions under which the skill applies" — reads as contradicting the Problem
Statement, which says "Neither shape is a discoverability problem" and
"supplying more of it changes nothing."

The reconciliation is presumably that a description shapes whether skill
*selection* fires, which is a different mechanism from the agent's knowledge of
the correct path. The brief never says so. One clause fixes it.

### Coherence: OUT item four vs. Journey 4

OUT item four asserts the distinguishing properties "currently have no
representation outside the machine that did the work," while J4 has "someone who
was not present when the work happened" run "a check that reads a durable trace"
against "a given branch."

Scope IN's phrasing is "from outside the *agent*," which is consistent with a
machine-local trace, but J4's framing invites an off-machine reading that OUT
item four denies. Either J4's reader is on the machine and should say so, or the
trace does travel and OUT item four is only about CI *gating* rather than
representation. The PRD should resolve which.

## Altitude

No PRD or DESIGN drift worth acting on. Scope IN's "at the moment the write is
attempted" is the closest approach to requirement altitude, and it earns its
place because it is precisely what separates the in-scope refusal from the
out-of-scope post-hoc gate. No interface shapes, no data flow, no acceptance
criteria, no user stories.

## Visibility

Public-repo clean. No private repo names, no private paths, no issue numbers,
and no `wip/` references anywhere in the document.

## Reference accuracy

All four references verified against the worktree:

- `docs/designs/current/DESIGN-execute-skill.md` — exists (this was the dangling
  path, since corrected).
- `docs/prds/PRD-execute-skill.md` — exists.
- `docs/briefs/BRIEF-pr-template-gate.md` — exists, and does scope the
  workflow-routing half out as separate work: "Closing the dispatch gap —
  routing dispatched PR-opening work through a template-applying skill — remains
  out of scope."
- `references/workflow-principles.md` — exists, and carries the cited principle
  nearly verbatim at line 84: "How hard a rule is enforced scales with the
  consequence of getting it wrong."

## Observation

`docs/designs/DESIGN-skill-adherence-enforcement.md` already exists in this
worktree, at the non-`current/` path, downstream of a BRIEF still in Draft.
Outside this review's criteria, but worth a look if that was not expected.

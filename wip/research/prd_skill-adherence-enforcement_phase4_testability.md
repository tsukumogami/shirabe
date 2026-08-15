# PRD Phase 4 Jury — Testability Review

**VERDICT: FAIL**

Document: `docs/prds/PRD-skill-adherence-enforcement.md`
Reviewer criteria: binary criteria, independent testability, coverage, edge cases,
non-restatement.

## Summary of grounds

The PRD is strong where it matters most: the discriminating case (AC2) is
present, correctly identified as the bar, and mechanically checkable against
state that exists today. The refusal criteria (AC5, AC7, AC8, AC9, AC10) are
real tests with fixtures and negative controls. That is more than most PRDs
manage.

It fails on four requirements that no test can distinguish conformance from
non-conformance for, and that no criterion covers at all:

- **R14** has no threshold. "Latency a user perceives as a stall" is not a
  measurable quantity, and no criterion measures it.
- **R16** is scoped to the document ("no requirement in this document"), not to
  the system. It prohibits a class of justification rather than a behavior, so
  there is nothing to run.
- **R17** never says which artifacts are public-facing or what counts as private
  content, and it collides with R9.
- **R7** is uncovered and does not say which component it governs — the check
  (which reports) or the refusal (which permits or blocks).

Four of seventeen requirements — R7, R14, R16, R17 — have zero acceptance
criteria behind them. Two criteria (AC6 second half, AC14) require subjective
judgment. The check's output domain is never defined, which makes AC4
unfalsifiable in one direction.

---

## Criterion 1 — Is every acceptance criterion binary pass/fail?

Fifteen criteria. Eleven are binary or made binary with a small edit. Four are
not.

### Not binary as written

**AC6 (second half).** "…and the refused agent proceeds correctly on its next
attempt without human input."

This is a claim about model behavior, not about the enforcement. It is
non-deterministic across runs, and "correctly" is nowhere defined. Two
developers replaying the same fixture can get different results and both report
honestly. The first half of AC6 — "the refusal text names the refused path and
the sanctioned alternative" — is a deterministic string assertion and belongs in
its own criterion.

*What would make it objective:* split into two.

- A deterministic criterion: the deny reason string contains the refused path
  verbatim and contains the sanctioned alternative, asserted against a fixed
  expected form.
- A graded criterion with a stated trial count and threshold, and a mechanical
  definition of "proceeds correctly" — e.g. *"over N=20 replays of the refusal
  fixture, the agent's next tool call after the deny is either a subagent spawn
  or a write inside the declared set in at least K of N runs."* Without N and K
  this cannot pass or fail.

**AC14.** "The plan-execution skill's description contains no internal
architecture vocabulary and names the situations in which the skill applies."

Both halves need a judge. "Internal architecture vocabulary" has no boundary —
the current `/execute` description contains "wip-yaml-md state projection over
the durable home PR (cross-branch resume)", "the three exit-path bindings",
"parent-skill conformance", "the six security surfaces". A reviewer would
plausibly call all four architecture vocabulary; another might defend
"cross-branch resume" as a user-facing capability. Nothing in the PRD decides
it. "Names the situations in which the skill applies" is equally a judgment
call.

*What would make it objective:* state the test as a denylist plus a floor. For
example: *"the description contains none of the terms in the enumerated
architecture-vocabulary list, and contains at least three trigger phrasings
written as things an author would say."* A denylist is checkable by grep; a
count of trigger phrasings is checkable by reading. Both survive a reviewer who
did not write the PRD.

**AC15.** "…produces a rate before and after the description change, and the two
are comparable."

"Comparable" is undefined and is the whole load of the criterion. As written, the
criterion passes the moment two numbers exist, whatever they are and however
they were produced. Two runs against different prompt sets, or different N, or
different harnesses, satisfy the literal text.

*What would make it objective:* name the invariants that make the numbers
comparable. *"The same fixed set of N plan-shaped prompts (N stated, prompt set
recorded in the repository) is run against the old and new descriptions under
the same harness, and both selection rates are reported."* Note that even fixed,
this criterion cannot fail on the result — it verifies a measurement exists, not
that selection improved. That may be deliberate given R12's wording ("means of
measuring… so that R11's effect is falsifiable"), but it means R11's improvement
is never itself gated. Worth stating explicitly rather than leaving the reader
to infer it.

**AC11 (second half).** "…and that record is visible to the author without the
author querying the agent."

"Visible to the author" names no surface. A file on disk in a directory nobody
opens is visible in one reading and not in another. The first half of AC11 —
three named fields present in a record — is binary.

*What would make it objective:* name the surface the author reads, in
requirements terms rather than mechanism terms. *"The record is present in a
location the author reads without a live session — the branch's working tree or
the pull request — after the session has ended."* That is checkable by looking.

### Binary, with one caveat

**AC4.** "…the check does not report a failure." Binary only once the check's
output domain is fixed. The other criteria use two outcomes — "reports
conformance" (AC1) and "reports non-conformance" (AC2, AC3) — while R7 implies a
third, indeterminate. AC4 as written passes if the check reports conformance
*and* passes if it reports indeterminate, and the PRD never says which is
intended for the coordinated path. A DESIGN can satisfy AC4 by making the check
return "indeterminate" for every input, which also satisfies R7 and R15.

*What would make it objective:* state the check's outcome set once (in R1 or in
the Goals) and have AC4 name which outcome the coordinated path yields.

### Binary as written

AC1 (modulo the provenance clause, below), AC2, AC3, AC5, AC7, AC8, AC9, AC10,
AC12, AC13.

**AC1's provenance clause** deserves a note: "using only state the session's
agent did not write" is not observable from a single test run. It is a property
of the check's input set, verifiable by enumerating what the check reads. That
is auditable — but not by running the fixture, which is what the criterion's
"given/then" shape implies. Two ways out: assert it against an enumerated input
set (the criterion names the classes of state, not the mechanism), or accept it
as a design-review constraint and say so. As written a developer will run the
fixture, see "conforming", and tick the box without ever checking provenance —
which is the exact property the requirement exists to guarantee.

The externally-checkable state the domain context supplies makes this tractable:
koto's per-session workflow projection under
`~/.claude/projects/<encoded-cwd>/<session-id>/workflows/koto-<uuid>.json` and
the `scheduler_ran` event with `spawned_count >= 1` are both written by koto, not
by the agent under evaluation. A criterion that says "the check's inputs are
limited to state written by the orchestration engine, not by the evaluated
session's tool calls" is checkable by reading the check's source and stays at
requirements altitude.

---

## Criterion 2 — Is every requirement independently testable?

### R14 — not testable

> "The conformance check SHALL run on the interactive path of tool calls without
> adding latency a user perceives as a stall."

There is no test that distinguishes conformance from non-conformance. Perception
is not a measurable property of the system; it varies by user, by machine, and by
what else the turn is doing. Two implementations at 40 ms and 400 ms of added
per-call latency both satisfy the sentence under some reading.

The format reference is explicit that non-functional requirements carry
measurable thresholds where possible, and here it is very possible. This should
name a number and a percentile: added wall time per intercepted tool call at p95
or p99, measured over a stated number of calls. Whether the number is 50 ms or
200 ms is a product call I am not making — but a number has to be there, because
the requirement sits on the hot path of every tool call in every session and is
precisely the kind of thing that degrades silently.

No acceptance criterion measures latency at all. R14 is both untestable and
uncovered.

### R16 — not testable as a requirement

> "No requirement in this document SHALL be satisfied by a mechanism that asserts
> skills outrank user or session instructions."

Two problems, both fatal to testability.

First, the subject is the document, not the system. "No requirement in this
document" makes R16 a constraint on how the other requirements may be read, which
is not a behavior anything can exhibit or fail to exhibit at runtime. A system
under test cannot violate it; only an implementation's rationale can.

Second, it prohibits a class of mechanism by its justification rather than by its
effect. "Asserts skills outrank user instructions" describes what an
implementation *claims*, and claims live in prose. An implementation could inject
text at runtime that functionally forces the spawn while never using the word
"outrank" — passing R16 as written and violating everything it is for.

*What would make it testable:* restate it against observable behavior. The
behavioral core, judging by the second field incident, is that the enforcement
must not force the agent past a binding session instruction. That is
constructible:

> "Given a session whose instructions forbid subagent calls, the enforcement
> SHALL NOT deny a tool call the agent makes in compliance with that instruction,
> and SHALL NOT emit text instructing the agent to disregard it."

A fixture — session instruction forbidding the AgentTool, agent reaching the
fan-out step — makes both halves checkable: assert no deny fires on the
compliant path, and grep the enforcement's emitted text against a denylist.

If the intent really is a document-level constraint on how a DESIGN may satisfy
the other requirements, it is not a requirement and should move — to Out of
Scope (where the third bullet already carries most of it) or to a stated
constraint on the downstream DESIGN. It should not sit in a numbered list whose
stated contract is "each requirement is independently testable."

No criterion covers R16 in either reading.

### R17 — not testable as written, and in conflict with R9

> "Public-facing artifacts produced by the enforcement SHALL NOT embed content
> from private repositories."

Two undefined terms carry the requirement. *Which artifacts are public-facing?*
The candidates are the conformance record, the conflict record from R8/R9, and
anything the workflow writes into a pull request — the PRD never says which of
these are public-facing or how one tells. *What counts as content from a private
repository?* File paths, issue numbers, verbatim prose, and paraphrase are four
different tests with four different implementations.

Worse, R17 collides with R9. R9 requires the conflict record to "identify the
instruction". In the motivating incident the instruction was a session-level
directive; in the general case a workspace-level instruction lives in a private
`CLAUDE.md`. If the conflict record is public-facing, an implementation cannot
pass a test for R9 (record names the instruction) and a test for R17 (record
embeds no private content) at the same time. A tester constructing the fixture —
private instruction, conflict recorded, record lands in a public surface — gets a
contradiction, not a verdict.

*What would make it testable:* say which artifacts R17 governs, say what
"content" means at the granularity a check can apply (verbatim text? paths?
identifiers?), and resolve the R9 collision — most plausibly by having the
conflict record identify the instruction by reference or by its own summary
rather than by quoting it, and saying so.

No criterion covers R17.

### R7 — testable in principle, ambiguous about its subject

> "Where the system cannot determine conformance, it SHALL permit the action and
> SHALL NOT block on the ambiguity."

The antecedent is the check's vocabulary ("cannot determine conformance"); the
consequent is the refusal's vocabulary ("permit the action"). Those are two
different components. The check produces a report and permits nothing; the
refusal permits or denies and does not determine conformance. A tester cannot
tell whether R7 says (a) the refusal must allow the tool call when the check is
indeterminate, or (b) the check must emit an indeterminate verdict rather than a
non-conformance verdict when its inputs are missing. Those are different tests
with different fixtures.

Secondarily, R7 is only testable if at least one "cannot determine" state is
constructible. The PRD names none. With koto's projection file as the evidence
base, plausible ones exist — the file absent because the session predates the
feature, present but at a pre-fan-out state, or malformed — but the requirement
should name at least the class so a fixture can be built.

No criterion covers R7. AC9 covers the *binary being absent*, which is R15's
first mode, not R7's indeterminacy.

### R15 — one of three modes testable

> "Absence, staleness, or failure of any component of the enforcement SHALL
> degrade to permitting the action…"

Absence is constructible and covered (AC9). *Failure* is constructible (non-zero
exit, timeout, crash) but uncovered. *Staleness* is neither defined nor
constructible — stale what? A cached verdict past its lifetime, a binary at a
version behind the skill, a projection file whose state is older than the
session's real progress? Each is a different fixture, and a tester has no basis
to pick.

*What would make it testable:* enumerate the degradation modes as a short list of
constructible fixtures, and cover each. This is worth the words: R15 and R7 are
the safety property the entire mechanism rests on — the PRD's own Decisions
section says failing closed was rejected because a stale component would stop
every session — and exactly the stale case is the one nobody can test.

### R4 — half testable

"…in a form the refused agent receives and can act on within the same turn."
*Receives* is observable: the deny reason is fed back to the model and appears in
the transcript. *Can act on* is a capability claim about the model. See AC6.

### R13 — testable, one clause uncovered

"Operator-reachable means of disabling the enforcement without editing skill or
workflow content." The disable is covered by AC10. The clause "without editing
skill or workflow content" is a distinct property — it is what makes the switch
operator-reachable rather than contributor-reachable — and no criterion asserts
it. Small, but it is the half of R13 that constrains the DESIGN.

### Testable as written

R1, R2, R3, R5, R6, R8, R9, R10, R11 (given AC14's denylist fix), R12.

R2 deserves credit specifically. "Invocation alone SHALL NOT satisfy the check"
is the sharpest sentence in the document: it names the exact discriminator the
second incident defeated, and the state to check it against exists today.

---

## Criterion 3 — Do the criteria cover the requirements?

| Req | Criteria | Coverage |
|-----|----------|----------|
| R1 | AC1, AC2, AC3 | Partial — provenance clause ("state the agent did not author") not verified by any run |
| R2 | AC2 | Full — the discriminating case |
| R3 | AC5 (positive), AC8 (negative control) | Full |
| R4 | AC6 | Partial — first half deterministic, second half non-deterministic |
| R5 | AC7 | Full |
| R6 | AC4 | Partial — outcome domain undefined, so "does not report a failure" is satisfiable by an indeterminate verdict |
| R7 | — | **None** |
| R8 | AC11, AC12 | Full |
| R9 | AC11 | Partial — three fields checkable; "visible to the author" surface unnamed |
| R10 | AC13 | Partial — covers "the same refusal and the same check"; R10 says "every behavior in R1 through R9", so the conflict route (R8/R9) in an agent-launched session is uncovered |
| R11 | AC14 | Partial — subjective |
| R12 | AC15 | Partial — "comparable" undefined |
| R13 | AC10 | Partial — "without editing skill or workflow content" unverified |
| R14 | — | **None** |
| R15 | AC9 | Partial — absence only; staleness and failure uncovered |
| R16 | — | **None** |
| R17 | — | **None** |

**Requirements with no criterion: R7, R14, R16, R17.** Four of seventeen.

**Criteria that test nothing in the requirements: none.** Every one of the
fifteen maps to at least one requirement. That is a genuine strength and worth
recording — the failure mode here is under-coverage, not stray criteria.

**One user story with no requirement behind it.** "As a coordinating agent
writing a task brief for a worker, I want the workflow the work should run under
to be part of what a brief carries, so that I do not drop it by omission." R10
requires the enforcement to *reach* agent-launched sessions; nothing requires a
brief to *carry* the workflow. The story describes a behavior on the dispatching
side that no requirement asks for and no criterion tests. Either the story is
covered by a requirement that should exist, or the story is describing a
mechanism and belongs downstream.

---

## Criterion 4 — Happy path and edge cases

| Case | Criterion | Assessment |
|------|-----------|------------|
| Conforming run (drove to fan-out) | AC1 | Present. Checkable against `scheduler_ran` with `spawned_count >= 1`. |
| **Discriminating case** — skill invoked, scripts ran, work done inline | AC2 | **Present, and correctly flagged as the bar.** Checkable: the payload was produced but never submitted, so no post-fan-out state exists in the projection file. This is the criterion the whole document turns on and it is the right one. |
| Never invoked, hand-rolled | AC3 | Present. |
| Fail-open — binary absent | AC9 | Present. |
| Fail-open — component fails (non-zero exit, timeout) | — | **Missing.** R15 names it. |
| Fail-open — component stale | — | **Missing**, and not constructible until "stale" is defined. |
| Fail-open — conformance indeterminate | — | **Missing.** This is R7, entirely uncovered. |
| Carve-out — coordinated multi-repo | AC4 | Present but weak: satisfiable by a check that never determines anything. |
| Agent-launched session | AC13 | Present for the refusal and the check. **Not** present for the conflict route, which R10 also demands. |
| Operator disable | AC10 | Present. |
| Negative control — permitted write inside the set | AC8 | Present, and the right instinct: without it the refusal criteria are satisfiable by denying everything. |
| **Conflict actually surfaced rather than silently resolved** | — | **Missing.** See below. |

### The missing conflict-case criterion

This is the most consequential gap after R14 and R16.

AC11 begins "An agent that records a conflict under R8 produces a record…" — it
presupposes the agent chose to record. It tests the route's mechanics, not that
the route gets taken. AC12 tests that the route is reachable. Neither tests the
behavior that failed in the field.

The second incident's failure was not that no route existed. It was that the
agent hit the conflict, resolved it privately against the workflow, and said
nothing. The agent later conceded it should have flagged the conflict when it
made the decision — the PRD's own Decisions section says so. Nothing in the
fifteen criteria would catch a shipped implementation that has a perfect conflict
route which agents never use.

This is admittedly hard to make binary, for the same reason AC6's second half is:
it is model behavior. But it is the feature's central bet, and "hard to test" is
not "not worth testing." The shape that works is a graded eval, matching AC15's
posture:

> "Over N replays of the conflict fixture — a session instruction forbidding
> subagent calls, an agent reaching the workflow's fan-out step — the agent takes
> the sanctioned conflict route in at least K of N runs, with N and K stated."

R8's own wording is what permits the gap: "the system SHALL provide a sanctioned
route" is a provisioning requirement, and AC11/AC12 test provisioning faithfully.
If the PRD's position is that uptake is out of scope and provisioning is the
whole commitment, that position is defensible — but it should be stated in Out of
Scope, because a reader today will assume the feature closes the second incident
and it does not.

---

## Criterion 5 — Do criteria merely restate requirements?

Five do, in whole or in part.

- **AC12** vs R8's second clause. R8: "that route SHALL be available when no
  orchestration session yet exists." AC12: "The conflict route is exercisable in
  a session that has not created an orchestration session." The only change is
  *available* to *exercisable*. No fixture, no observable, no expected result.
- **AC11 (first half)** vs R9. R9: "SHALL identify the instruction, the workflow
  step it conflicts with, and the course the agent took." AC11: "produces a
  record naming the instruction, the conflicting step, and the course taken."
  Verbatim. The second half ("visible to the author") is the part that adds
  something, and it is the part that needs a surface named.
- **AC14** vs R11. R11: "SHALL state the conditions under which the skill
  applies, rather than inventorying its architecture." AC14: "contains no
  internal architecture vocabulary and names the situations in which the skill
  applies." The negation is flipped to the front; nothing else changes. This is
  also the criterion that most needs to become a denylist.
- **AC13** vs R10. Adds "with no human-typed invocation", which is a real fixture
  detail. Mild.
- **AC4** vs R6. Adds "that completed correctly", which is a real fixture detail.
  Mild.

The contrast with the strong criteria is instructive. AC2, AC5, AC7, AC8, AC9,
AC10 each construct a situation, name an action, and state an observable result.
The five above name a property and hope. The fix for each is the same: give it a
fixture and a thing to look at afterward.

---

## What would move this to PASS

1. Give R14 a numeric threshold and a percentile, and add a criterion that
   measures it.
2. Restate R16 against observable behavior, or move it out of the numbered
   requirements. Add a criterion for the behavioral form.
3. Define R17's scope (which artifacts, what content) and resolve its collision
   with R9. Add a criterion.
4. Disambiguate R7 — check verdict or refusal decision — name at least one
   constructible indeterminate state, and add a criterion.
5. Enumerate R15's degradation modes and cover failure and staleness, not just
   absence.
6. Split AC6 into a deterministic text assertion and a graded eval with N and a
   threshold.
7. Turn AC14 into a denylist plus a floor on trigger phrasings.
8. Define "comparable" in AC15 as fixed prompt set, fixed N, same harness.
9. Name the check's outcome set once, and have AC4 say which outcome the
   coordinated path yields.
10. Name the surface in AC11's "visible to the author".
11. Add a criterion for the conflict case actually being surfaced, or state in
    Out of Scope that uptake of the conflict route is not gated.
12. Extend AC13 to the conflict route, or narrow R10's "every behavior in R1
    through R9".

Items 1 through 4 are the FAIL. The rest are what a strict reviewer would hold
the next draft to.

# Phase 4 Completeness Review: PRD-skill-adherence-enforcement

VERDICT: FAIL

Two blocking gaps, both in criterion 4 (requirements complete against goals).
Criteria 1, 2, 3, 5, and 6 pass. The document is close: the fixes are one
missing requirement and one missing arming condition, not a restructure.

---

## Criterion 1: BRIEF journey coverage

Every journey has at least one requirement behind it. One journey's chain has a
hole at the requirement level, detailed under criterion 4.

| BRIEF journey | Requirements | Verdict |
|---|---|---|
| An orchestrator tries to implement inline | R3, R4, R5 | Covered |
| A dispatching agent omits the workflow from the brief it writes | R10, R3, R4 | Partial — see Finding B |
| An agent meets a constraint that forbids the sanctioned step | R8, R9 | Covered |
| A reviewer asks whether a branch ran the workflow | R1, R2 | Covered |

**Journey 1** ("The attempt is refused at the moment it happens, with a reason
naming what the sanctioned move is. The agent adjusts and delegates.") maps
cleanly. R3 sets the refusal at write time rather than "at a later
self-administered check"; R4 requires the reason to name "what was refused and
what the sanctioned alternative is, in a form the refused agent receives and can
act on within the same turn" — which is the journey's "the agent adjusts"
clause turned into a requirement. R5 carries it into dispatched sessions.

**Journey 2** is discussed under Finding B. The outcome the journey promises
("The worker's first out-of-contract write is refused, and the refusal names the
workflow the work should run under") appears only as an acceptance criterion
(AC13), with no requirement stating when the write-target contract binds a
session that never entered the skill.

**Journey 3** ("Rather than resolving the conflict silently in either direction,
it surfaces the conflict: the author sees ... which constraint, and ... what the
agent proposes to do") maps to R8 and R9. R9's three-part record — "the
instruction, the workflow step it conflicts with, and the course the agent took"
— is a faithful operationalization of the journey's three "sees" clauses. R8's
tail clause ("that route SHALL be available when no orchestration session yet
exists") is not in the BRIEF journey text but is a correct derivation: the
conflict fires at the fan-out step, which is where the orchestration session
would have been created.

**Journey 4** ("They run a check on the machine that did the work, which reads a
durable trace the agent did not author, and get a definite answer") maps to R1,
whose second clause — "SHALL derive that determination from state the agent
under evaluation did not author" — is the journey's load-bearing property
carried over verbatim in substance. R2 supplies the discriminating power the
journey's last sentence demands ("a competent hand-rolled implementation looks
exactly like a conforming one").

---

## Criterion 2: BRIEF Scope IN coverage

All six covered.

| BRIEF Scope IN item | Requirements | Verdict |
|---|---|---|
| Detecting, from outside the agent, whether a session ran the plan under the sanctioned workflow | R1, R2 | Covered |
| Refusing writes outside the declared contract, at the moment attempted, with an actionable reason | R3, R4, R5 | Covered |
| Surfacing a session-constraint/workflow-step conflict so it is recorded rather than resolved privately | R8, R9 | Covered |
| Making a departure from the workflow auditable after the fact | R1, R2, R9 | Covered |
| Carrying the enforcement to agents launched by other agents | R10 | Covered |
| Correcting the plan-execution skill's own description | R11, R12 | Covered |

Two notes.

The fourth item ("Making a departure from the workflow auditable after the
fact") is served by a combination rather than a dedicated requirement: R9 makes
a conflict-driven departure auditable, and R1/R2 make a silent departure
detectable post-hoc. That is adequate — the two departure shapes the BRIEF's
Problem Statement names are each reached — but no single requirement carries the
item, so a DESIGN reader looking for "the audit requirement" will not find one.
Non-blocking.

The sixth item is served better than the BRIEF asked. R11 restates the
correction; R12 adds falsifiability ("so that R11's effect is falsifiable rather
than asserted"), which the BRIEF did not require. That is a legitimate
requirements-altitude addition, and it is consistent with the BRIEF's framing of
the item as "hygiene that raises the floor."

---

## Criterion 3: the three deferred Open Questions

All three are genuinely closed. The BRIEF handed over: "whether the enforcement
travels with the skill or with the workspace manager, what the check asserts for
a plan spanning more than one repository, and whether the conflict-surfacing
route needs a durable record of its own."

**Q1 — where the enforcement travels.** Closed as an acknowledged unknown with
the requirements-level residue extracted, which is the form the criterion
permits. The PRD's "Where the enforcement lives, and who can turn it off"
records both candidate placements with their real costs (skill-carried "binds
the enforcement's lifetime to the skill's"; manager-distributed "reaches only
adopters who use that manager"), then pins what any placement must satisfy: R13
(an operator route to disable exists) and R10 (coverage reaches agent-launched
sessions), closing with "The requirement is written so either satisfies it."
Deferring the mechanism to DESIGN is correct at PRD altitude — placement is a
HOW. The half of the question that is a WHAT ("who can turn it off") landed as
R13, and its cost is acknowledged in Known Limitations ("R13's operator switch
is, by construction, reachable by an agent with the ability to change
configuration"). Not a restatement.

**Q2 — the multi-repository case.** Closed into R6, and the PRD says why it is a
requirement rather than a design note: "Making the carve-out a requirement rather
than an implementation detail means the DESIGN cannot omit it silently." R6 plus
AC4 make it testable. This matches the established fact that the coordinated
multi-repo path deliberately runs with no koto session, so a check assuming one
would report a correct run as a failure. Genuinely resolved.

Minor: R6 is phrased negatively ("SHALL NOT report a failure") and so answers
"what does the check assert here" with "nothing." That is a legitimate answer,
and R7 catches the residue (indeterminate → permit). Non-blocking.

**Q3 — durable record for the conflict route.** Closed yes, into R9, with the
rejected alternative named ("surfacing to the author in-session only, which is
cheaper and was rejected on that ground") and the reason grounded in incident 2
("that agent conceded afterward that it should have flagged the conflict when it
made the decision and did not"). Genuinely resolved.

---

## Criterion 4: requirements complete against the goals — FAIL

The Goals section has five clauses. Three are fully requirement-backed, one is
partially backed, one is backed.

| Goal clause | Requirements | Verdict |
|---|---|---|
| "Conformance becomes checkable rather than claimed ... by reading a trace the agent did not author" | R1, R2 | Backed |
| "Departure from the contract is caught when it happens ... told enough to correct itself without a human in the loop" | R3, R4, R5 | Backed |
| "A conflict ... stops being resolvable in silence" | R8, R9 | Backed |
| "Coverage reaches sessions no human started. An agent that hands work to another agent must not be able to drop the workflow by omission." | R10 only | **Gap — Findings A and B** |
| "Nothing here promises that adversarial reviews ran" | R16, OOS item 1 | Backed |

### Finding A (blocking): a User Story with no requirement behind it

The PRD's fifth user story:

> **As a coordinating agent writing a task brief for a worker**, I want the
> workflow the work should run under to be part of what a brief carries, so that
> I do not drop it by omission.

No requirement in R1–R17 places any obligation on what a task brief carries. R10
is the nearest, and it is about the receiving session ("Every behavior in R1
through R9 SHALL apply to sessions launched by another agent"), not about the
dispatching agent's brief. The story asks for something on the write side of the
handoff; every requirement sits on the read side.

This is not a nit imported from the BRIEF. The BRIEF's journey 2 deliberately
routed the fix through coverage rather than through the brief format, and said
so: "What the feature has to reach is a session whose own instructions never
named the workflow, which is a different coverage problem." The PRD then wrote a
user story asserting the opposite fix and left it unbacked. The Goals section
repeats the same active-voice framing — "An agent that hands work to another
agent must not be able to drop the workflow by omission" — which reads as an
obligation on the handing agent, and again nothing requires anything of it.

Two clean fixes, either sufficient: rewrite the story against the need the
requirements actually serve (a worker that was handed no method still runs under
the workflow, because R10 plus R3 reach it), or add a requirement placing the
workflow declaration in the dispatch brief. The first is truer to the BRIEF; the
second expands scope and would need the Goals clause to stay as written.

### Finding B (blocking): R3's arming condition is unspecified for a session that never invoked the skill

R3 refuses "a filesystem write that falls outside the closed write-target set the
plan-execution skill declares for itself." That phrasing presupposes the skill is
in play — the set is the one `/execute` already declares in its Security
Considerations. Journey 2's whole point is a worker that never invoked the skill
and never knew it should: "The worker receives a competent description of the
goal and no instruction about method, and proceeds accordingly. The worker's
first out-of-contract write is refused."

No requirement states when the write-target contract binds a session that has not
entered the skill. And R7 pushes actively the other way:

> **R7.** Where the system cannot determine conformance, it SHALL permit the
> action and SHALL NOT block on the ambiguity.

A worker with no orchestration session, doing plan-scale work under a brief that
never named a workflow, is precisely the ambiguous case R7 describes. Read
together, R3 and R7 permit the write that journey 2 requires be refused.

The outcome journey 2 needs appears only as an acceptance criterion:

> - [ ] A session launched by another agent, with no human-typed invocation, is
>       subject to the same refusal and the same check as an interactively
>       started one.

An acceptance criterion verifies that a requirement is met (per the format
contract's "Don't duplicate requirements — criteria verify that requirements are
met"). AC13 has no requirement to verify against for the never-invoked case. The
fix is a requirement naming the condition under which the enforcement is armed —
what makes a session count as plan-scale execution independent of whether the
skill was invoked — and a sentence reconciling it with R7 so the two are not read
as contradicting.

### Non-blocking gaps under this criterion

**R14 has no threshold and no acceptance criterion.** "SHALL run on the
interactive path of tool calls without adding latency a user perceives as a
stall" is the one non-functional requirement with a performance claim, and the
format contract asks for "measurable thresholds where possible." A number here
would be cheap and would give the DESIGN a budget to hit; without one, nothing
verifies it.

**R7, R16, and R17 have no acceptance criteria.** R15 has AC9 ("With the
enforcement binary absent from the path, a session runs to completion
unblocked"), but R7's sibling case — the component is present and returns
"cannot determine" — is untested. R16 and R17 are negative constraints and
harder to make binary, but R16 is the requirement that keeps the feature from
becoming the thing OOS item 3 forbids, so leaving it unverified is a real hole
given how much of the Out of Scope section leans on it.

---

## Criterion 5: Out of Scope consistency — PASS

All five BRIEF OUT items survive. Nothing was silently pulled back in, and the
PRD adds no sixth exclusion.

| BRIEF OUT | PRD OOS | Verdict |
|---|---|---|
| Guaranteeing that adversarial reviews or validation steps actually ran | "Guaranteeing that adversarial reviews or validation steps ran" | Consistent, strengthened |
| A workspace-level policy system for declaring required skills | "A workspace-level policy surface for declaring required skills" | Consistent |
| Changing the documented precedence between session instructions and skills | Same title | Consistent, strengthened |
| A post-hoc CI gate on the merged result | "Making the conformance record travel off the machine" | Consistent, reframed |
| Re-running or repairing past non-conforming work | "Remediating past non-conforming work" | Consistent |

The first is strengthened correctly against the domain facts: the PRD names both
mechanisms ("Its spawn primitive is a stub and its review gates are directive
text") and adds the companion obligation ("nothing in the implementation may
imply it does"), which is the BRIEF's "the feature must not imply it does" turned
into an enforceable pairing with R16.

The third is strengthened by R8 doing exactly the narrow thing the BRIEF
authorized. The BRIEF: "The fix for the conflict is to remove an ambiguity about
whether requesting a workflow requests the subagents that workflow is defined in
terms of." The PRD: "R8 removes an ambiguity about whether requesting a workflow
requests the subagents that workflow is defined in terms of. It does not reorder
the precedence, and R16 forbids any implementation that does." No drift.

The fourth is reframed rather than restated, and the reframing is a superset that
still excludes the original. The BRIEF excluded a post-hoc CI gate on the merged
result because "the properties that distinguish a conforming run from a
hand-rolled one currently have no representation outside the machine that did the
work"; the PRD excludes the more general act of making the record travel, which
subsumes the CI gate. Nothing is pulled in. Worth one sentence naming the CI gate
explicitly so a DESIGN reader does not have to derive the subsumption, but this
is not a defect.

The PRD adds no exclusion the BRIEF did not have. R12 (measurement) and R17
(public artifacts not embedding private content) are additions to the
requirements, not to the exclusions, and neither contradicts a BRIEF IN item.

---

## Criterion 6: required sections present and ordered — PASS

All seven required sections present, in canonical order:

1. Status (line 27)
2. Problem Statement (line 31)
3. Goals (line 63)
4. User Stories (line 83)
5. Requirements (line 109), split Functional / Non-functional
6. Acceptance Criteria (line 173), checkbox format throughout
7. Out of Scope (line 210)

Optional sections follow, in the order the contract lists them: Known
Limitations (233), Decisions and Trade-offs (250), Downstream Artifacts (292).
No Open Questions section, which is correct — the three inherited questions were
closed into Decisions and Trade-offs, the contract's designated closure surface
for exactly that.

Frontmatter: `status: Draft` matches the body Status section. `upstream` points
at the BRIEF as a scalar. `problem`, `goals`, and the optional
`motivating_context` are all literal block scalars, one paragraph each.
Requirements are numbered R1–R17 with no gaps. Acceptance criteria are all
`- [ ]`.

---

## Summary of required changes

1. **Finding A.** Either rewrite the fifth user story against the need the
   requirements serve, or add a requirement obligating a dispatch brief to name
   the workflow. If the second, the Goals clause stays; if the first, consider
   softening "An agent that hands work to another agent must not be able to drop
   the workflow by omission" to match.
2. **Finding B.** Add a requirement stating the condition under which the
   write-target enforcement is armed for a session that has not invoked the
   skill, and reconcile it with R7 so the two do not read as contradicting. AC13
   currently has nothing to verify against.

Recommended, not blocking: a threshold for R14, and acceptance criteria for R7
and R16.

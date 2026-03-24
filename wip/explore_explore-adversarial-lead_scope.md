# Explore Scope: explore-adversarial-lead

## Core Question

How should `/explore` add an adversarial demand-validation lead — one that investigates
the null hypothesis ("is this worth pursuing at all?") on directional topics — without
changing the UX for diagnostic topics or the existing discover-converge loop?

## Context

`/explore` dispatches research agents to investigate a topic and surfaces findings.
The framing is always "how do we move forward," never "should we move forward." For
directional topics (new feature, new product direction, zero-to-one), this is a gap:
agents investigate the shape of the solution before anyone has challenged whether the
problem is real or the investment is justified.

The issue proposes an adversarial lead that folds demand-validation questions into
Phase 2 discovery as a research task — not as user interview questions. Six
demand-validation questions from office-hours tooling frame the investigation:
is demand real? what do people do today instead? who specifically asked for this?
what behavior change counts as success?

Prior art: gstack's `/plan-ceo-review` and `/plan-eng-review` use scope challenge as
a mandatory step before content review, with explicit cognitive frames per role and
a `VERDICT: NO REVIEWS YET` gate state. The CEO review specifically challenges premise
before solution quality — directly analogous to the adversarial lead's role here.

Issue #9 names four open design questions this exploration must resolve:
1. How does Phase 1 detect "directional" vs "diagnostic" topics?
2. What exactly does the adversarial agent investigate, and how does it avoid
   being artificially negative?
3. Should "don't pursue this" become a first-class crystallize outcome?
4. Is adversarial framing useful on all topics, or only uncertain ones?

## In Scope

- Trigger detection: signals that distinguish directional from diagnostic topics
- Adversarial lead design: what it investigates, what posture prevents false negatives
- "Don't pursue" as first-class crystallize output: format, user action
- Always-on vs conditional: trade-offs and failure modes
- Integration with Phase 1 (scope) and Phase 2 (discover) — minimum-viable change
- Gstack CEO review patterns and what transfers to this context

## Out of Scope

- Changes to `/plan`, `/design`, `/prd`, or other skills
- UX changes for diagnostic topics
- Adversarial mode for the full `/explore` workflow (a different concern)

## Research Leads

1. **What signals reliably distinguish directional from diagnostic topics in Phase 1?**
   The issue calls out "new feature, new product direction, zero-to-one" as directional
   and "how do I fix X" as diagnostic. What observable signals — topic string patterns,
   conversation cues, issue labels, absence of a clear problem statement — distinguish
   these reliably? What's the false-positive cost if detection is wrong?

2. **What does the adversarial agent actually investigate in a code-oriented codebase?**
   The issue mentions six demand-validation questions (is demand real? what do people
   do today? who asked? what behavior change counts as success?). How do these map to
   research tasks that an agent can execute by reading code, issues, and docs — rather
   than asking users? What sources are available and what makes findings credible vs.
   speculative?

3. **What should a "don't pursue this" crystallize output look like?**
   Currently `phase-5-produce-no-artifact.md` handles this as a fallback. What would
   make it a first-class crystallize outcome? What does the structured output contain,
   how does the user act on it (close issue, write decision record, archive), and how
   does the crystallize framework score for this outcome vs. PRD/design?

4. **What are the failure modes of always-on vs conditional adversarial framing?**
   Always-on: risks reflexive negativity on genuinely good ideas, adds latency to
   diagnostic topics. Conditional: requires reliable trigger detection; false negatives
   leave directional topics unchallenged. What evidence from similar patterns informs
   which failure mode is more costly in practice?

5. **Where in Phase 1/2 does the adversarial lead integrate with minimum disruption?**
   Does it become just another agent in Phase 2 (lowest disruption), require a
   classification step at the end of Phase 1, or need a separate pre-discover step?
   How does DESIGN-plan-review.md's approach to adding a new phase without changing
   existing phases inform this choice?

6. **What does gstack's CEO review skill do, and what patterns transfer here?**
   The previous plan-review exploration found gstack's `/plan-ceo-review` uses scope
   challenge as a mandatory Step 0 before content review, with multi-persona cognitive
   frames and an explicit `VERDICT: NO REVIEWS YET` gate state. What specifically does
   the CEO review investigate? How does it frame the null hypothesis without reflexive
   negativity? What's the cognitive frame it uses, and does it map to demand validation
   for directional topics?

# PRD Scope: vale-adoption

Upstream: `docs/briefs/BRIEF-vale-adoption.md` (Accepted).
Execution mode: `--auto`. Decisions recorded in
`wip/prd_vale-adoption_decisions.md`.

## What the PRD must settle

The BRIEF settled the framing and deliberately left the mechanism to DESIGN.
The PRD's job is the requirements layer between them: what the checking must
do, on which surfaces, reaching whom, at what severity, without naming how.

Four questions arrive from the BRIEF's Open Questions and are this PRD's
inheritance. They close in the Decisions and Trade-offs section.

1. Must an adopter repo be able to read the single rule source without
   installing shirabe?
2. Does an adopter's vocabulary declaration extend shirabe's rules or replace
   them?
3. Is FC10 replaced or extended?
4. What severity does a frequency finding carry on first release?

## Already settled upstream, not re-litigated here

- The problem framing, the two prose surfaces, and the measurements. Cited
  from the BRIEF, not restated, except for the Problem Statement which a PRD
  must be able to state standing alone.
- Mechanism choice stays out. Naming a linter, a native check, a hook, or a
  CI job in this PRD would take the DESIGN's decision.
- Cognitive-tell detection stays out. The vacuity measurement closed it.

## Research leads

1. **How does shirabe actually reach an adopter today, and what can an
   adopter supply back?** (lead-adopter-surface)
   Question 1 cannot be answered without knowing the real distribution
   channel and its constraints. Need the exact mechanism koto, niwa, and
   tsuku use, what runs on their CI, what config surfaces shirabe already
   reads from an adopter repo, and what "without installing shirabe" would
   concretely mean.

2. **What precedent does shirabe have for per-repo configuration, and what
   does extend-vs-replace cost each way?** (lead-vocabulary-model)
   Question 2 decides whether the feature has one rulebook or many. shirabe
   already resolves durable preferences on a `flag > CLAUDE.md-header >
   default` stack; whether vocabulary fits that pattern, and what an adopter
   loses under each model, is a requirements decision.

3. **What does retiring or widening a validator check code actually
   involve, and what severity is defensible on first release?**
   (lead-check-lifecycle)
   Questions 3 and 4 are entangled: whether FC10 is replaced or extended
   changes what "success" means, and the corpus's current state bounds what
   severity a frequency rule can carry without failing every PR on day one.

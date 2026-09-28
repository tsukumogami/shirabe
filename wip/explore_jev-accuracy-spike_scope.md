# Explore Scope: jev-accuracy-spike

## Visibility

Public

## Core Question

How accurately does Jev, TypeSafe's typed decision model, grade shirabe's own
prose-shaped quality criteria when called through its API directly? For five or
six criteria, what are its false-pass rate on seeded-bad text, its pass rate on
text written to steer it, and its false-fail rate on known-good text, and which
criteria clear the bar for a decider design at all?

## Context

koto ships a Jev client for closed questions, and shirabe already declares two
decider questions in the work-on template, each with a golden fixture file. The
open question is whether Jev can also judge the rules shirabe applies to its own
prose (PR bodies, comments, acceptance criteria, scrutiny findings, doc
sections, PR titles). The bar for trusting a Jev pass on a criterion is fixed:
it passes none of at least 20 seeded-bad fixtures and none of 5 adversarial
fixtures. Fixtures land in public shirabe, so they're built only from public
artifacts. No koto change; the harness calls the API directly.

## In Scope

- Five or six of the seven candidate criteria: a PR body's first part is a
  factual summary; a code comment gives a reason, not a restatement; an
  acceptance criterion can be answered yes or no; a scrutiny finding is resolved
  by a given diff; a doc section sits at the right altitude; hedge language
  appears with no approved deferral; a PR title's type matches the change.
- A labelled fixture file (good, seeded-bad, adversarial per criterion).
- A small harness script calling Jev's API, recording model string, input
  sizes, and whether questions were batched.
- A spike report in docs/spikes/.

## Out of Scope

- Any koto change, any change to shirabe templates or skills.
- A decider design.
- Inventing criteria beyond the seven candidates.

## Research Leads

1. **What does Jev's API accept and return, and what limits apply?** (lead-jev-api)
   Model string, choice vs noul questions, batching several questions per
   request, input size limits, and any guidance on steering or guardrails. The
   harness must match the request shape koto would send.

2. **Where does each candidate criterion's rule text live in shirabe, and which
   public artifacts supply good and bad examples for it?** (lead-criteria-sources)
   The rule wording becomes the question Jev is asked; the corpus supplies
   fixtures.

3. **How do shirabe's existing decider declarations and fixtures look, and what
   conventions should the spike's fixtures follow?** (lead-decider-conventions)
   The work-on template's two declarations, the fixture-file format, and the
   declarations check bound what a later design would need.

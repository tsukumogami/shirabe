# PRD Scope: scope-chain-mandatory-steps

## Visibility

Public

## Upstream

`docs/briefs/BRIEF-scope-chain-mandatory-steps.md`

## Problem (carried from the BRIEF, not restated)

The corpus gives two answers to whether a tactical-chain step is optional, and
an author meets a stale one first. Four surfaces still describe the world before
#302: `/explore`'s routing surface, `/scope`'s Phase 1 prompt and the prose
beside it, the shared parent-skill pattern both parents inherit, and `/scope`'s
eval suite.

## What the PRD Must Settle

The BRIEF bounds the surfaces. The PRD owes numbered, testable requirements for
each, plus resolution of the two questions the BRIEF deferred.

## Research Leads (PRD altitude)

The `/explore` run on this branch already established which surfaces are stale
and why; that is not re-researched. What requirements need and the exploration
did not produce:

1. **Assertion-level eval inventory.** For every eval scenario in every suite
   that must change, the exact current assertion text and what it must become.
   Acceptance criteria have to be checkable against specific strings, and the
   suites moved under us (#292 appended scenarios), so the inventory must be
   taken against the current tree.

2. **The router's handoff contract.** What `/explore` must write for `/scope`
   and `/charter` to consume without re-asking, given that neither parent has a
   detection clause today, and what the terminal recording set must keep so the
   off-chain artifact types stay reachable.

3. **The pattern document's edit surface.** Which sections of
   `references/parent-skill-pattern.md` and
   `references/parent-skill-state-schema.md` must change, what the model
   statement must say, how the ALWAYS declination clause is restated so
   `/charter`'s roadmap prompt reads as a preserved instance rather than an
   exception, and what a bounded `chain_skipped[].reason` vocabulary contains.

## Deferred Questions the PRD Must Close

Both land in Decisions and Trade-offs; both are the BRIEF's Open Questions.

- What "a shorter chain" means to an author now that absorption reduces the
  artifact set but not the conversation, and therefore whether the
  direct-invocation redirect is retired, narrowed, or re-justified.
- Whether the abandonment exit must stay reachable from the author's own flow
  once the chain proposal stops asking, and from where.

## Prior Research (inputs, not re-run)

- `wip/explore_scope-chain-mandatory-steps_findings.md`
- `wip/explore_scope-chain-mandatory-steps_decisions.md`
- `wip/research/explore_scope-chain-mandatory-steps_r1_lead-*.md` (six files)

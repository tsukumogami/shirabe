# PRD Scope: chain-cardinality

## Upstream

`docs/briefs/BRIEF-chain-cardinality.md` (Accepted). The problem statement is
inherited from it and carried forward rather than re-derived; the PRD restates the
problem only (per the Citation vs Restatement rule) and cites the brief for journeys
and scope boundary.

## What this PRD must settle

The brief deliberately deferred three questions. All three close in Decisions and
Trade-offs:

1. Is `PRD -> DESIGN` fan-out intended, tolerated, or forbidden?
2. When a document belongs to two chains at different postures, where should posture
   attach — to the chain or to the edge?
3. Should the system make fan-out expressible, keep it inexpressible but fail loudly,
   or describe the constraint honestly in the formats and change nothing mechanical?

Question 3 is the fork the other two hang off. Requirements cannot be written until it
is answered, so Phase 2 gathers the evidence to answer it rather than assuming a shape.

## Research Leads

1. **What are the concrete options for making an existing upstream reusable through a
   parent, and what does each cost?** (lead-reuse-options)
   The brief establishes the shape is unreachable because every path resolves from one
   topic slug. Enumerate the real mechanisms that would change that, with the blast
   radius of each.

2. **Where should posture attach — the chain or the edge — and what does each answer
   require?** (lead-posture-model)
   The load-bearing question for the validator half. Establish what "posture on the
   edge" would concretely mean in the existing types, and what would have to change.

3. **Is `PRD -> DESIGN` fan-out intended?** (lead-fanout-intent)
   It happens three times via a documented split mechanism. Find whether any design
   doc, PRD, or commit reasoned about it deliberately, or whether the split heuristic
   was authored without considering what it does to lineage.

4. **What is the minimum change that makes the existing corpus evaluable?** (lead-minimum-viable)
   Separates the floor from the ceiling. If the cheapest option is close to the fullest
   one, the fork resolves itself; if not, the gap is the trade-off the PRD records.

## Out of scope for research

Re-opening Decision 9, `/execute`, the adjacent defects listed in the brief's Out
section, and any migration of the existing corpus.

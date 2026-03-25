# Architecture Review: Adversarial Lead and Rejection Record

Reviewed against: `skills/explore/` as it exists today (SKILL.md, phase-1-scope.md,
phase-2-discover.md, phase-4-crystallize.md, phase-5-produce.md, crystallize-framework.md,
phase-5-produce-no-artifact.md, phase-5-produce-decision.md).

---

## Summary verdict

The architecture fits the existing patterns for Phase 2 dispatch and Phase 5 routing.
Two structural gaps need resolution before implementation: the `## Topic Type:` field
is written but not consumed by anything that changes execution, and the Rejection Record
type is missing from the Phase 5 routing table (the only place phase routing is
authoritative). Both are fixable without changing the overall shape of the design.

---

## Finding 1: Phase 5 routing table is missing the new type — Blocking

`phase-5-produce.md` contains the authoritative dispatch table:

```
| Chosen Type     | Reference File                     |
|-----------------|------------------------------------|
| PRD             | phase-5-produce-prd.md             |
| Design Doc      | phase-5-produce-design.md          |
| Plan            | phase-5-produce-plan.md            |
| Decision Record | phase-5-produce-decision.md        |
| No artifact     | phase-5-produce-no-artifact.md     |
| Roadmap, ...    | phase-5-produce-deferred.md        |
```

The design doc says to add Rejection Record to `crystallize-framework.md` (the scoring
reference) but does not mention updating `phase-5-produce.md`. That table is what the
Phase 5 orchestrator reads to route execution. If `crystallize-framework.md` scores
Rejection Record as the winner and writes that choice to `wip/explore_<topic>_crystallize.md`,
but `phase-5-produce.md` has no row for it, the Phase 5 agent will have no instruction
for where to go and will either stall or fall through to a wrong path.

Fix: add a `Rejection Record | phase-5-produce-rejection-record.md` row to the routing
table in `phase-5-produce.md` as part of Phase 2 implementation. The new produce file
cannot be treated as standalone — the routing table is its entry point.

---

## Finding 2: `## Topic Type:` field is a dead write — Blocking

The design writes `## Topic Type: directional | diagnostic | ambiguous` to the scope
file and then says "Not read by Phase 2 directly." The field's only stated consumer
is Phase 1 itself, which reads it "before writing the leads section" to decide whether
to inject the adversarial lead.

But Phase 1 writes the field as part of the classification step, which runs after lead
production and before the persist step. The read-before-write self-reference doesn't
make sense as described: you can't read a field to decide whether to write it, in the
same step that writes it. What actually happens is: the classification fires, the
adversarial lead is either injected or not, and then the scope file is persisted — all
in one pass. The `## Topic Type:` field is written to disk as a record of what
classification decided, but nothing downstream reads it to branch behavior.

This is a state contract gap: a field serialized to a durable artifact with no
consumer. It either needs a real consumer (Phase 2 or convergence reads it and changes
behavior based on it) or it should be omitted from the scope file entirely (classification
result is implicit in whether the adversarial lead appears in the leads section).

The simpler fix: drop the `## Topic Type:` field from the scope file. The presence of
an adversarial lead in `## Research Leads` already encodes the classification result.
Any downstream phase that needs to know "was this a directional topic?" can check
whether `lead-adversarial-demand` exists in the scope file or whether a research file
for it exists. No additional field is needed.

If the intent is to surface the classification to the user during Phase 1 (so they can
correct it before committing to leads), that's legitimate — but then the field needs an
explicit consumer described: e.g., "Phase 1 checkpoint (step 1.1) reads this field and
presents it to the user for confirmation." Without a named consumer, the field will
cause schema drift.

---

## Finding 3: Adversarial lead dispatch follows the existing Phase 2 pattern — Clean

Phase 2 reads `## Research Leads` from the scope file and dispatches one agent per
lead. The design correctly routes the adversarial lead through this mechanism without
modification. The proposed output path
`wip/research/explore_<topic>_r1_lead-adversarial-demand.md` follows the established
naming convention (`explore_<topic>_r<N>_lead-<name>.md`). Phase 3 convergence folds
it in with other leads. No bypass of the dispatch pattern.

One note: the adversarial lead's per-question confidence format is richer than the
standard lead output format (which has Findings, Implications, Surprises, Open
Questions, Summary). The design doc doesn't say whether the adversarial lead agent
uses the standard template with confidence appended, or a completely different format.
If it's a different format, Phase 3 convergence needs to know to read it differently —
or the agent should use the standard template and put per-question confidence in the
Findings section. Either is fine architecturally, but it needs to be specified in the
adversarial lead template embedded in phase-1-scope.md.

---

## Finding 4: Rejection Record sits between two existing types — Advisory

The existing `phase-5-produce-decision.md` already produces `docs/` artifacts
(a decision brief, then hands off to /decision to produce an ADR). The design document's
Rejection Record writes to `docs/decisions/REJECTED-<topic>.md` and "offers to route
to /decision for a formal ADR if re-proposal risk is high."

This is not a duplicate — a Rejection Record is the output of exploration that reached
an active rejection, while a Decision Record is the output of exploration that reached
a choice between options. But there's a boundary case worth naming in
`phase-5-produce-rejection-record.md`: if the user accepts the ADR routing offer, the
session should invoke the decision skill, not write a second document manually. The
existing `phase-5-produce-decision.md` shows exactly how to do this handoff. The new
file should reference that pattern rather than inventing a new one.

---

## Finding 5: Crystallize scoring procedure references "four supported types" — Blocking

`crystallize-framework.md` Step 1 says: "For each of the four supported types (PRD,
Design Doc, Plan, No artifact)". `phase-4-crystallize.md` step 4.3 says the same.
The design adds a fifth supported type. Both files need the count updated, and the
Evaluation Procedure in `crystallize-framework.md` needs to include Rejection Record in
the explicit enumeration. This is a consistency issue, not a logic issue, but an
implementer reading the count "four" will skip scoring the new type.

---

## Sequencing question

The design proposes three phases: Phase 1 (classification + scope changes), Phase 2
(crystallize + produce path), Phase 3 (evals). This sequencing is correct. Phase 2
depends on Phase 1 (the adversarial lead must be injectable before the produce path is
exercisable), and Phase 3 depends on both (evals test the full path). One refinement:
the `phase-5-produce.md` routing table fix (Finding 1) belongs in Phase 2, not as an
afterthought in Phase 3. Flag it explicitly in the Phase 2 deliverables list.

---

## Answers to design questions

**1. Is the architecture clear enough to implement?**

Yes, with the two blocking fixes applied first. The overall flow is sound: classification
injects a lead, the lead dispatches like any other, convergence folds in the findings,
crystallize scores the new type, and the produce path writes the rejection record. The
pattern reuse is correct.

**2. Are there missing components or interfaces?**

The `phase-5-produce.md` routing table entry is missing (Finding 1). The `## Topic
Type:` field needs either a named consumer or removal (Finding 2). The crystallize
procedure's "four types" count needs updating (Finding 5).

**3. Are the implementation phases correctly sequenced?**

Yes. Routing table fix should be explicitly listed in Phase 2 deliverables.

**4. Are there simpler alternatives?**

For the `## Topic Type:` field: yes, drop it. The adversarial lead's presence in the
leads section already encodes the same information. Removing the field eliminates
Finding 2 entirely and reduces the scope file schema surface.

For the Rejection Record type: the design is already close to minimal. The only
simplification would be to route through the existing Decision Record path (since
`/decision` can produce an ADR with a "rejected" choice), but that would lose the
structured demand-validation format. The new produce file earns its existence.

---

## Required changes before implementation

1. Add `Rejection Record | phase-5-produce-rejection-record.md` to the routing table
   in `phase-5-produce.md`. Add this to Phase 2 deliverables.

2. Either remove `## Topic Type:` from the scope file schema, or name a specific
   consumer (e.g., "Phase 1 checkpoint presents this to the user for confirmation").

3. Update the "four supported types" enumeration in `crystallize-framework.md` Step 1
   and the parallel language in `phase-4-crystallize.md` step 4.3.

4. Specify in the adversarial lead agent prompt template whether it uses the standard
   lead output format or a modified format, and if modified, what Phase 3 convergence
   should do differently when reading it.

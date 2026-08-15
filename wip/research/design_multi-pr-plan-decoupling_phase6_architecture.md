# Verdict: PASS

Reviewer: architecture. Target: docs/designs/DESIGN-multi-pr-plan-decoupling.md (revised). Upstream: docs/prds/PRD-multi-pr-plan-decoupling.md.

Both prior FAIL grounds are resolved and re-verified against the repo.

## 1. Architecture clarity

Buildable as written, with one cosmetic defect (see Required Changes): the
Security Considerations section still says "FC20" twice (lines ~505, 508)
after the rest of the document was correctly renamed to `L09`. Every other
occurrence of the code (Decision B, Solution Architecture, Decision Outcome,
"The check," Consequences) is consistently `L09`. An implementer would
immediately recognize this as a leftover from the rename, not a real
ambiguity, so it doesn't block PASS, but it should be fixed before merge.

## 2. Missing components

Resolved. `crates/shirabe-validate/src/lifecycle.rs` and the `validate.rs`
row (doc comments + `posture_class_classifies_lifecycle_codes`) are now in
the component table, matching what I verified in the codebase: the doc
comments at `validate.rs` lines ~62-63 and ~107 and the test at ~483 do
state "the entire FC-family is AlwaysEnforced," and `L09` sidesteps that
invariant entirely rather than requiring an exception to it. I checked
`L06`'s implementation (`check_l06_outline_acs`, `lifecycle.rs:1480`): it is
dispatched during chain traversal but the property it checks (unticked ACs
in one PLAN's own outline) is local to that single document, which supports
Decision B's claim that `L06` is genuine single-document precedent for
`L09`, not a strained analogy.

`skills/plan/references/quality/plan-doc-structure.md` is now in the table.
`plan-format.md`'s row now names the `### Transitions` re-key. I verified
`plan-format.md:235` ("Draft -> Active (multi-pr only)") is the exact stale
predicate, and Decision E's new two-row table gives it an explicit
replacement rule (automatic iff resolved tracking level is `none`) that
resolves both newly-reachable combinations named in Security
Considerations (`multi-pr`+`none`, `single-pr`+`issues`).

I went looking for a fifth prose site beyond the four now named (`SKILL.md`,
`plan-doc-structure.md`, `phase-7-creation.md`, `plan-format.md`) since
Decision E still says "five sites" without enumerating them; grepping
`skills/plan/` for the gate predicate turned up only those four as genuine
matches (other hits were false positives — roadmap's own gate, or unrelated
uses of "multi-pr only"). Not a blocking gap: the component table names
every file an implementer needs to touch regardless of whether the count
literally reconciles to five, but worth a note if the author wants the
number itself to be exact.

## 3. Sequencing

Re-ran this specifically per the request. Moving the emitter into Batch 1 is
internally consistent: Batch 1's `phase-3-decomposition.md` change only
teaches step 3.6 to emit `split_rationale` for the two mechanism-derived
branches that exist under today's behavior (Hard Constraint, Incremental
Value) — it does not need the CLAUDE.md header machinery, so it doesn't
smuggle a Batch 2 dependency into Batch 1. Batch 2's claimed dependency on
Batch 1 ("the branch vocabulary the record names") still holds and isn't
weakened; if anything Batch 2 now edits code Batch 1 already wrote (the
emitter) rather than adding it fresh, but the dependency direction the
design claims (2 depends on 1, never the reverse) is unchanged and real.
The "inert until there is a header to depart from" framing for `L09`'s
departure predicate is coherent: the full check ships in Batch 1, the
predicate's live branch simply never fires because `resolve_claude_md_header`
finds nothing until Batch 2's header exists.

Batch 3-independent-of-Batch-2 and Batch 4-depends-on-Batch-3 are unaffected
by the emitter move and still verified true on the same grounds as the prior
review (different phase file, different header; tracking-level resolution
is a real prerequisite for the extraction branch).

## 4. Simpler alternative

Re-ran against the revised design. Nothing changed the calculus: the
two-preference design is still the PRD's own settled trade-off (argued in
its "Decisions and Trade-offs"), and moving the check from `FC20` to `L09`
is if anything a simplification — it reuses an existing family's shape
instead of carving an exception into another family's documented invariant.
No materially simpler alternative found that still satisfies R1-R20.

## 5. Strawman check

Re-checked Decision B specifically, since it changed most. The new rejected
alternative — "Filing it in the `FC` family as `FC20`, rejected on review"
— has real depth: it states what was believed initially (the `L`/`FC` split
tracks chain-legality vs. structure), names the fact that overturned it
(`L06` is single-document too), and traces the actual decisive reason (the
`AlwaysEnforced` invariant's cost) rather than just asserting the new choice
is better. This reads as genuine reasoning revealed, not a dismissal.
Decisions A, C, D, E are unchanged from the prior pass and were already
verified to have real depth.

## 6. Requirement fidelity

R11 and R16 are the two requirements the revision touches. R16 (draft
posture -> notice, ready posture -> error) is now satisfied through a
mechanism that doesn't require rewriting a stated invariant, so it's
actually more clearly correct than in the prior draft. R11 (gate keyed on
"will create issues," not `execution_mode`) is now backed by an explicit
rule covering the two combinations that make `execution_mode` alone
insufficient. No other requirement's coverage changed.

## Required Changes

1. Fix the two leftover `FC20` references in Security Considerations
   (~lines 505, 508) to `L09` — cosmetic, but a reader hits it right after
   the rest of the document has consistently used the new name.

---

## Re-review note (parent-recorded)

The revision addressing the four findings above was dispatched to this reviewer,
which did not return a second verdict. The verdict line above is therefore the
reviewer's round-1 FAIL and has not been superseded by the reviewer itself.

The parent verified each closure directly against the revised document:

1. The check moved to `L09` in the lifecycle family, so the documented
   "the entire FC-family is AlwaysEnforced" invariant needs no exception.
   `L08` confirmed taken by grep over lifecycle.rs and validate.rs.
   Decision B records the reversal and its reason rather than switching quietly.
2. `plan-doc-structure.md` present in the component table.
3. The `plan-format.md` row names the `### Transitions` re-key, and Decision E
   carries the two newly reachable combinations with a stated rule.
4. `phase-3-decomposition.md` is in Batch 1, with the reason the emitter cannot
   be deferred to Batch 2.

Criteria 4 (simpler alternative) and 6 (requirement fidelity) were NOT re-run
after the revision. That is an accepted gap, recorded rather than papered over.

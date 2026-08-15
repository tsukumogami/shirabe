```yaml
review_result:
  plan_topic: multi-pr-plan-decoupling
  round: 1
  mode: fast-path
  verdict: proceed
  categories:
    A_scope_gate: pass
    B_design_fidelity: pass
    C_ac_discriminability: pass-after-correction
    D_sequencing_integrity: pass
  critical_findings: []
```

# Plan Review: multi-pr-plan-decoupling

Four categories ran, plus a final verification sweep against the revised state.
Fourteen findings were raised; thirteen were applied, one was rejected on
evidence. What follows records both, because a review whose rejected findings
are invisible reads as a review that found nothing to reject.

## Applied

**A — Scope Gate (pass).** Every component in the design's table has a covering
issue; every issue traces to a design decision; 8 issues against 15 components is
proportionate. Issue 7 was confirmed in scope despite `process_multi_pr` having
no live invoker — its acceptance surface is the emitted task graph, tested by
`plan-to-tasks_test.sh`, not an orchestrator run. It did surface a false claim in
the design's Consequences: that an issueless multi-PR plan falls back to being
driven by path "the way `/execute` already drives single-pr and coordinated
plans." `/execute` declines multi-pr outright. That entry is now stated as a
capability gap with no mitigation in scope.

**B — Design Fidelity (pass).** Found that Issue 6's grep criterion was
unsatisfiable as scoped: `lifecycle.rs` and `transition.rs` carry the old gate
framing in comments and were absent from the issue's file list. Chasing it
exposed that the design's site enumeration was wrong in both directions — it
named seven sites when there are eleven, and would have licensed re-keying three
`Current` DESIGN docs and a golden fixture that record historical state and must
not change. Decision E now carries an eleven-row table with verified line numbers
and an Action column marking six `re-key`, one `amend`, four `leave`.

**C — AC Discriminability (pass after three rounds).** Every one of the eight
issues carried at least one finding. The pattern across them was
existence-without-correctness: criteria that a file with three empty headings, or
a plan with no dependency edges at all, or an amendment saying only "see the other
design," would satisfy. All corrections were applied. The category then caught
three errors in my own correction — a grep pattern that missed
`lifecycle.rs:764` ("human-approved") and `phase-7-creation.md:263` ("approval
gate" with no "human"), and a wrong occurrence count for `transition.rs`.
Verifying those exposed a further problem the reviewer had not seen: the
approval-term pattern alone returns 157 corpus-wide hits from unrelated approval
prose. Issue 6 now carries paired criteria — a file-scoped completeness grep over
the six `re-key` files and a tree-wide discovery grep — with the reason each alone
is insufficient stated inline.

**D — Sequencing Integrity (pass).** Found a false edge: Issue 5's stated
dependency on Issue 1 was not real, and contradicted the design's own text
(`Batch 3 "depends on Batch 1 for nothing"`). Issue 5 now has no dependencies and
can start immediately. Applying that surfaced a contradiction between Issue 6,
which requires the four `leave` sites unchanged, and Issue 8, which appends an
amendment to one of them; Issue 6's check is now line-scoped rather than
file-scoped.

## Rejected

**Final sweep, section 6 — "the PLAN is not in the required format."** The claim
was that `plan/v1` requires an `## Implementation Issues` section and a populated
`## Dependency Graph`, that this plan has neither, and that it "would fail
`shirabe validate` outright."

Rejected on direct evidence. `plan_execution_mode_sections()` in
`crates/shirabe-validate/src/formats.rs:230` overrides the unconditional
`required_sections` list per execution mode. For `single-pr` the required set is
Status, Scope Summary, Decomposition Strategy, **Issue Outlines**, Implementation
Sequence — `Implementation Issues` and `Dependency Graph` are the multi-pr shape.
FC14 separately fires when a `single-pr` plan *populates* the Dependency Graph,
which is why this plan's is empty. `shirabe validate` returns clean on the
document, which is the direct refutation of a claim that it would fail outright.

The reviewer read the unconditional list and compared against
`PLAN-work-on-friction-fixes.md`, which is a multi-pr plan. Recorded rather than
silently dropped, because "a reviewer said the format is wrong" is exactly the
kind of finding that gets applied without checking.

## Residual, accepted

- The tree-wide discovery grep's post-implementation claim (that it reduces to
  the four `leave` sites plus the amendment's quotation) cannot be falsified until
  the re-key lands. It is a check for the implementer to run, not a fact about
  today's tree.
- Categories B and D returned their verdicts before the final two commits. Their
  findings were re-verified directly rather than re-run, and the verification is
  recorded above.

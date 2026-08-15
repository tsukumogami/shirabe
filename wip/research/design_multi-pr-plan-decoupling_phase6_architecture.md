# Verdict: FAIL

Reviewer: architecture. Target: docs/designs/DESIGN-multi-pr-plan-decoupling.md. Upstream: docs/prds/PRD-multi-pr-plan-decoupling.md.

## 1. Architecture clarity

Mostly buildable as written. The check ordering in "The check" section, the
data-flow diagrams, and the batch descriptions are concrete enough to
implement without guessing -- except at the two points raised under
"Missing components" below, where an implementer would have to invent
behavior the design never specifies.

## 2. Missing components (FAIL grounds)

**FC20 as `DraftTolerable` contradicts a documented, tested invariant that
the design never engages with.** `crates/shirabe-validate/src/validate.rs`
does not just happen to leave the FC-family out of `DraftTolerable` today --
it declares that exclusion an invariant in three places:

- Doc comment on `PostureClass` (line ~62): "the always-defect lifecycle
  findings `L01`/`L03`/`L04`/`L05` and **the entire FC-family** — is
  `AlwaysEnforced`."
- Doc comment on `posture_class` (line ~107): "and the whole FC-family —
  is `AlwaysEnforced`."
- A test, `posture_class_classifies_lifecycle_codes` (line ~482), that
  asserts `FC01`, `FC06`, `FC07`, `FC14`, `FC-CONVENTIONS` are all
  `AlwaysEnforced`, with the comment "Always-defect lifecycle findings and
  the FC-family are always-enforced."

`DraftTolerable` today is scoped to exactly three lifecycle (`L`) codes
tied to a documented concept: "legitimate intermediate states while a chain
is being drafted." Decision B and the Solution Architecture's "The check"
section both say `FC20` is simply "registered as `DraftTolerable` in
`validate::posture_class()`," and D6 frames this as reuse of "the shipped
`PostureClass` mechanism rather than a new enforcement path." That
undersells what the change actually is: it is the first FC code ever
admitted to `DraftTolerable`, which means rewriting the invariant's doc
comments on two functions and updating (or refactoring) a test that
currently encodes "FC-family is never draft-tolerable" by name. None of
that appears in the component table, and nothing in the design explains
why breaking a stated invariant for FC20 specifically is safe or why the
invariant should now read "FC-family, except FC20." An implementer hits
this the moment they open `validate.rs`.

**A named "site" of the approval-gate re-key is missing from the component
table, and the table's one entry that is closest to it under-describes the
required change.** Decision E says the gate's asymmetry "lives in
`skills/plan/SKILL.md`, in the status-transition table in
`plan-doc-structure.md`, and in `phase-7-creation.md`'s mode-branch
headers," and both Decision E and Batch 3 call this "five sites." I
confirmed `skills/plan/references/quality/plan-doc-structure.md` exists and
contains, verbatim, the sentence Decision E quotes: "multi-pr requires
human approval" (line 85), plus a status table row keyed the same way
(line 92). This file does not appear anywhere in "Components and where they
change."

Separately, `skills/plan/references/plan-format.md` *is* in the table, but
the table's stated change for it — "`split_rationale` documented; the
issueless multi-pr table row shape documented" — does not mention its own
`### Transitions` section (lines 230-241), which currently reads:

```
- **Draft -> Active** (multi-pr only) -- Phase 7 populate has
  materialized the GitHub issues and the milestone. `single-pr` mode
  skips this state.
```

This is the same predicate R11 requires re-keyed, expressed as a state
machine rather than as prose, and it breaks under the feature as designed:
a `multi-pr` plan with `Tracking Level: none` has no issues to
"materialize," so it's unclear whether it ever reaches `Active`; and a
`single-pr` plan with `Tracking Level: issues` now creates GitHub artifacts
too, contradicting "`single-pr` mode skips this state." The design's own
Security Considerations section names this exact cross case ("`single-pr` +
`issues` would otherwise create artifacts through the automatic path") but
the fix for it — what state that combination transitions through — is
never specified, and the file section that would need to change isn't
called out.

An implementer following the component table alone would miss both
`plan-doc-structure.md` entirely and the `Transitions` section of
`plan-format.md`, and would have to guess the new state machine for the
`single-pr`+`issues` and `multi-pr`+`none` combinations.

## 3. Sequencing

Batch 3 independent of Batch 2: holds. Tracking-level resolution
(`## Tracking Level:` header, Phase 7 gating, gate-prose re-key) touches a
different header and a different phase file than delivery-preference
resolution (`## Delivery Preference:` header, step 3.6, FC20's departure
branch); neither reads the other's output per the Decision Outcome ("Neither
reads the other"). Confirmed independent.

Batch 4 depends on Batch 3: holds. `plan-to-tasks.sh`'s `none`-tracking path
needs the tracking level resolved before it can branch on it, and that
resolution machinery is Batch 3's deliverable.

**One sequencing gap the design doesn't surface:** Batch 1 is described as
"self-contained" and delivering standalone value — "a repository that stops
there still gets plans that record why they are shaped as they are" — but
Batch 1's file list (`plan-format.md`, `checks.rs`, `validate.rs`,
`split-triggers.md`, `workflow-principles.md`,
`coordination-strategy.md`) does not include
`skills/plan/references/phases/phase-3-decomposition.md`, which is the file
that actually emits `split_rationale` into a PLAN (per the Data Flow
diagram: "step 3.6 ... emit `execution_mode` + `split_rationale` [record
written here]"). `phase-3-decomposition.md` is listed only under Batch 2.
So a repository that "stops at Batch 1" gets a check that requires
`split_rationale` on every non-single-pr plan, but no workflow step that
populates it -- FC20 would fail every multi-pr/coordinated plan authored in
that window unless an author manually hand-writes the field, which the
design never states as the expectation. This contradicts Batch 1's own
"delivers standalone value" claim as written.

## 4. Simpler alternative

None found that is materially simpler while still meeting the PRD. The
two-preference/two-header design is argued for directly in the PRD's
"Decisions and Trade-offs" (two preferences, not one) and the design
correctly builds on that rather than re-litigating it. Decision C's
"closest call" alternative (stable internal id in all modes) is arguably
simpler in the sense of removing a third keying scheme, and the design
already names it honestly as more correct; its rejection reasoning has a
minor tension worth flagging but not a FAIL-level one: it argues rejection
on migration cost for "every committed multi-pr PLAN," while R19 elsewhere
argues no migration cost is owed because "PLANs are deleted by the
completion cascade, so there is no committed corpus of plans to migrate."
These are reconcilable (in-flight feature-branch PLANs mid-execution vs. a
permanent merged corpus) but the design doesn't make that reconciliation
explicit, and a careful reader will notice the apparent tension.

## 5. Strawman check

Decisions A-E all pass. Each rejected alternative is traced to a specific
Decision Driver or a codebase fact (D7 for Decision A's naming rejections,
D2 for Decision B's `FormatSpec` rejection with the exact I/O argument, a
concrete downstream-consumer argument for Decision C's `plan_outline`
rejection, P4's own text for Decision D's cross-reference rejection, and the
`transition.rs`/`lifecycle.rs` grep result for Decision E's supersession
rejection). None read as a dismissal; each explains what was lost and why.

## 6. Requirement fidelity

Spot-checked R1-R20. All are visibly addressed in Solution Architecture,
Decision Outcome, or the two data-flow diagrams. R16 is nominally satisfied
by "FC20 registered as DraftTolerable," but that mechanism choice is the
same one flagged as broken under "Missing components" above -- so R16's
implementation path is not actually clear as written. R11's predicate
change is addressed for `phase-7-creation.md` and `SKILL.md` but not for
`plan-doc-structure.md` or `plan-format.md`'s `Transitions` section, so R11
is only partially covered by the component table even though the design
text (Decision E) knows about all the sites.

## Required Changes

1. Either scope `DraftTolerable` explicitly to include `FC20` as a stated,
   deliberate exception (updating the two doc comments and the
   `posture_class_classifies_lifecycle_codes` test, and adding a sentence
   explaining why FC20 breaks the FC-family-is-always-enforced invariant),
   or choose a different enforcement mechanism that doesn't require
   revising a documented invariant. Add `crates/shirabe-validate/src/validate.rs`'s
   doc-comment and test changes to the component table.
2. Add `skills/plan/references/quality/plan-doc-structure.md` to the
   component table (Decision E already names it as one of the five sites).
3. Expand the `plan-format.md` table row to include re-keying the
   `### Transitions` section, and specify the new Draft/Active state
   behavior for the `multi-pr`+`none` and `single-pr`+`issues` combinations
   the design's own Security Considerations section already identifies as
   newly reachable.
4. Add `skills/plan/references/phases/phase-3-decomposition.md` to Batch 1's
   file list (or explicitly narrow Batch 1's claimed standalone value to
   "the check exists" rather than "plans get the record," since nothing in
   Batch 1 emits the field).

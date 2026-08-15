---
schema: plan/v1
status: Active
execution_mode: single-pr
milestone: "Scope Artifact Persistence"
issue_count: 22
upstream: docs/designs/DESIGN-scope-artifact-persistence.md
---

# PLAN: Scope Artifact Persistence

## Status

Active

Decomposed from the accepted DESIGN. Single-pr: the design's own sequencing
decision settled that everything ships in one change with no ordering constraint,
and no hard constraint in the repository's plan rule applies — the work is one
repository, with no cross-repo landing order and no merge gate between steps.

## Scope Summary

Replaces `/scope`'s type-level absorbability test with a content-decided judgment,
adds the contribution-section mechanism that lets a survivor carry what it
absorbed, and repairs six pre-existing defects in the surrounding machinery that
the feature would otherwise be built on.

## Decomposition Strategy

Horizontal, in four layers, because the components have stable interfaces and one
layer is a genuine prerequisite for the next rather than a slice of the same
runtime path. A walking skeleton would not help here: there is no integration risk
to surface early, since the validator and the procedure meet at one function and
one frontmatter key, both of which the design pins.

The layers, and why this order:

**A — repair the ground.** Six defects that exist today and are independent of the
feature. The judgment's firing condition reads a field nothing writes; the
security surface enumerates a deletion set that encodes the floor being removed;
nothing commits the absorb's output. The feature is unsound on top of any of
these.

**B — the validator.** The half with mechanical tests. Nothing in A depends on it,
and C's procedure and CI both key on the frontmatter contract it establishes.

**C — the procedure.** The judgment rewrite, the preflight, the re-ordered absorb,
the record, and the child instructions.

**D — surrounding.** Sibling skills, evals, guide, and the two amendments.

Two dependencies run backwards against a naive reading and are called out rather
than discovered: `A2`'s write-target amendment is **provisional**, because the
record's append target does not exist until `C4` reopens the same two files; and
`A3` can only establish *that* the absorb commits, since three of the four things
the commit covers are built in B and C. The `stage:` discriminator that replaces
`absorbable:` is deferred from A to C6 for the same reason — its values name
stages C creates.

## Issue Outlines

### A1 — Write `chain_ran:` in the child-invocation loop

**Goal**: Create the write site for a field that is specified, read in four places
by Phase 3, and appended to nowhere.

**Acceptance Criteria**:

Phase 2's loop appends each completed child to
`chain_ran:` alongside the child snapshot, with a started-at timestamp per entry.
Phase 3's existing claim about reading timestamps out of `chain_ran:` becomes true
rather than contradicted by the schema. Entry names are re-validated against
`{brief, prd, design, plan}` before use.

**Dependencies**: None

### A2 — Correct the write-target set in both declaration sites (provisional)

**Goal**: Fix three pre-existing defects in the enumerated security surface.

**Acceptance Criteria**:

The deletion set names the three upstream types rather
than `docs/briefs/` alone. The survivor mutation is enumerated, including
`docs/plans/` — at the terminal hop the PLAN is the survivor. `SKILL.md` and the
Phase 3 reference agree about the PLAN, with the phase named so "Phase 3 does not
write it" and "Phase 2's absorb does" are both true. `SKILL.md` is authoritative
and both sites carry the same set.

**Dependencies**: None

### A3 — Specify that the absorb commits its own output (provisional)

**Goal**: Close the gap where a completed absorb leaves a staged deletion, an
unstaged edit, and nothing that commits either.

**Acceptance Criteria**:

The absorb's final step commits its own output. `/scope`
has a `git add` where it needs one. What the commit covers is stated as far as the
current procedure reaches; `C3` extends it.

**Dependencies**: None

### A4 — Rewrite the enum re-validation scope sentence

**Goal**: Close the promoted-field category by rule rather than by enumerating
fields one at a time.

**Acceptance Criteria**:

The scope sentence reads: every enum-typed or
closed-domain field is re-validated against its domain at the read preceding its
use, where a use is interpolation into an emitted command, construction of a write
or delete path, a decision gating a destructive operation, or serialization into a
durable artifact. `visibility:` joins the list — it is read from state and
interpolated into an emitted command today. The paragraph declining to re-validate
chain-shape fields is rewritten rather than left standing, because its reasoning is
about invocation redirection and does not extend to gating a deletion.

**Dependencies**: None

### A5 — Drop `absorbable:` from the state schema

**Goal**: Remove the deleted model from the machine-readable contract.

**Acceptance Criteria**:

The field and its "is the required-section mapping
total?" annotation are gone. No entries exist on disk to migrate, because the
procedure has never executed. `stage:` is **not** added here — see `C6`.

**Dependencies**: None

### B1 — Contribution table and path-shape constant in `formats.rs`

**Goal**: One declaration the validator, the skill prose and the CI workflow all
cite.

**Acceptance Criteria**:

A table keyed by filename prefix maps each type to its
fixed contribution heading, declared beside the required-section lists. Array
position gives chain order. A named constant declares the `absorbed:` entry path
shape. No heading collides with any existing required section across all formats.

**Dependencies**: None

### B2 — Splice contribution sections into `required_sections_for`

**Goal**: Make the presence and order checks require contribution sections without
a second mechanism.

**Acceptance Criteria**:

A second branch beside the execution-mode one splices the
implied headings immediately after `Status`. A document with no `absorbed:` key
gets the base list unchanged. The branch shares one parse with `B3`'s check, so an
invalid entry produces the entry diagnostic rather than a louder and misleading
missing-section one.

**Dependencies**: B1

### B3 — The new error-level check

**Goal**: Own what the order check structurally cannot say.

**Acceptance Criteria**:

Gated entirely on `absorbed:` being present. Six clauses:
the field yields a usable entry; every entry matches the path constant and is not
cross-repo; every entry's type sits strictly above the carrying document's; the
implied sections appear contiguously and immediately after `## Status` in chain
order; the `## Status` absorption line is present and well-formed per entry; and
an unparseable or unknown-prefix entry fails closed.

**Dependencies**: B1, B2

### B4 — Scope the requirement-citation check to the absorb event

**Goal**: Catch an absorb that orphans `R<n>` citations, without auditing the
corpus.

**Acceptance Criteria**:

The check fires only for a citation whose target this run
absorbed, keyed on the frontmatter declaration. It emits nothing on the ~77
documents that carry dangling requirement citations today.

**Dependencies**: B1

### B5 — Fixtures and the corpus-walk regression test

**Goal**: Prove the added checks are silent on documents that declare no
absorption.

**Acceptance Criteria**:

Golden and absorption-parity fixtures updated in the same
commits as the code that changes their output — the `sections-clean` case is a
tripwire that fires on any required-section addition. A new corpus-wide test walks
every document under `docs/`, runs the validator, and asserts none of this work's
check codes fires on a document declaring no absorption. It does **not** assert
exit 0; pre-existing findings from other checks belong to the corpus cleanup.
`git diff --exit-code docs/` is clean in the same job.

**Dependencies**: B2, B3, B4

### C1 — The citation preflight script, its test, and its merge gate

**Goal**: A testable exclusion set, which is the difference between a guard and a
mechanism that refuses every fold.

**Acceptance Criteria**:

A script searches git-tracked files for citations of the
deletion target, excluding `wip/`, the survivor, and the record file. Its exit
codes are its own contract, explicitly translated from the search tool's inverted
convention: 0 clean, 1 path hits, 2 bare-name hits only, 3 did not complete. It
asserts both path arguments against the path constant and exits 3 otherwise,
because passing them after `--` does not disable pathspec globbing. A co-located
test covers all four codes plus the survivor-exclusion case, under a new merge
gate mirroring the existing script gates.

**Dependencies**: B1

### C2 — Rewrite the judgment

**Goal**: Replace the type test with a content-decided verdict.

**Acceptance Criteria**:

The mapping table is deleted. Stage 1 becomes the
citation preflight, routing any status other than 0 or 2 to `keep`. The firing
condition moves outside the judgment, reads `chain_ran:` membership, and is stated
as **stricter than the requirement as written** with its justification. The stated
ceiling and the input restriction are written down, the restriction at both the
preflight and the content stage. The three validation sites are ranked gate,
backstop and trigger, with the reason.

**Dependencies**: A1, C1

### C3 — Re-order the absorb and add the rollback

**Goal**: Make fail-toward-`keep` structural, and stop losing a safety step the
shipped procedure already has.

**Acceptance Criteria**:

Nine steps: preflight, content question, compose in
memory, carry check, snapshot-then-write the survivor, append and stage, delete,
re-validate, commit. The carry check itemizes the ancestor's required sections and
each contribution it carries, its own and inherited. Step 5 rewrites the
survivor's own prose citations of the absorbed path and applies the visibility
rule to spliced parents. A rollback table covers steps 5-9 including the
un-append. A partial absorb is never resumed across sessions, and no path is read
back from the judgment record for interpolation.

**Dependencies**: C2

### C4 — The fold record

**Goal**: A durable record that survives on the default branch.

**Acceptance Criteria**:

`docs/folds.md`, created on first append, one row per
completed fold, written mechanically. The row carries date, absorbed path,
survivor or `none`, verdict, the carry outcomes, and a blob hash recomputed at
fold time. The serializer rejects rather than escapes any value containing the
separator or a newline. A `.gitattributes` line gives it union merge. The
write-target set gains the append target and a cleanup carve-out, reopening `A2`.

**Dependencies**: A2, C3

### C5 — The record checker

**Goal**: Verify the record without breaking ordinary housekeeping.

**Acceptance Criteria**:

Deletion-driven, hosted in the reusable validation
workflow because folds happen in repositories that pin it. Triggered on a **fold
signature** — a chain-document deletion plus an absorption declaration in the same
diff naming that path — so a legitimate non-fold deletion does not demand a row.
Asserts the row's hash against the pre-fold blob, and that the record's hunk is
additions only.

**Dependencies**: C4

### C6 — Relocate the floor prohibition and add `stage:`

**Goal**: Keep the anti-temptation instruction after its premise is falsified.

**Acceptance Criteria**:

The Durable-Artifact Floor section is removed from the
discovery phase, its `/plan` redirect going with its premise. A prohibition is
sited beside the judgment, stating that there is no floor, that a guard forcing
`keep` on last-artifact grounds must not be added, and why the single-mechanism
rule will not catch such a guard. `stage: preflight | judgment | carry` replaces
the dropped `absorbable:`.

**Dependencies**: A5, C2

### C7 — Child consumption instructions

**Goal**: Put the material into the survivor so the parent can compose from it.

**Acceptance Criteria**:

The PRD drafting phase's instruction is amended — its
current justification cites the deleted mapping model. The design and plan phases
gain equivalent instructions. The brief needs none, since nothing absorbs into it.

**Dependencies**: B1

### D1 — `/execute` stops assuming a surviving DESIGN

**Goal**: Make the fold decision genuinely encapsulated in `/scope`.

**Acceptance Criteria**:

The finalization guard seeds on the surviving durable
anchor where one exists and treats a fully folded chain as complete rather than a
missing seed. The cascade's roadmap downstream rewrite handles the no-DESIGN case
rather than falling through and leaving a dangling reference. The `exit_artifacts:`
contract for a fully folded chain is stated. A cascade test scenario builds a
PLAN-to-ROADMAP chain with no DESIGN and asserts no dangling reference — it fails
against current code.

**Dependencies**: None

### D2 — The rationale-in-code instruction

**Goal**: Keep the why in the code, unconditionally.

**Acceptance Criteria**:

The implementation phase carries an instruction to record
why the code is shaped as it is, kept current as it changes. The maintainer
reviewer's brief names it as a blocking finding. Bounded to instruction text in
files that already exist; no new gate.

**Dependencies**: None

### D3 — Rewrite the affected evals

**Goal**: Stop the suite asserting the deleted model, and gain coverage of the new
behaviour.

**Acceptance Criteria**:

Scenarios 18, 19 and 20 are rewritten so none references
a type-level mapping check — 19 asserts the mapping positively, which a
negative-phrased screen would miss. The suite gains a paired hop above
BRIEF-to-PRD reaching `absorb` and reaching `keep`, with committed fixtures held
within 10% on line count and sharing section set, decision count, status, upstream
and slug. The floor prohibition becomes a graded expectation. **Scenario 17 is
untouched** — it is the tripwire for entry-altitude regression.

**Dependencies**: C2, C6

### D4 — Format references

**Goal**: State the contribution contract where authors read it.

**Acceptance Criteria**:

All four format references name their type's single
contribution and state the two-sided adequacy test — too long if it reads as a
rewrite of the upstream, too thin if the survivor's own argument does not stand
without it. Three of them carve the absorbed case out of their
citation-not-duplication rule; the brief is excluded, having no absorbed case.

**Dependencies**: B1

### D5 — Guide and prior-artifact amendments

**Goal**: Document the new check family, and stop two shipped documents
contradicting the change.

**Acceptance Criteria**:

The validation guide names the added check family.
Appended dated amendment sections on the shipped consolidation DESIGN and PRD,
original prose untouched, no lifecycle change: the DESIGN's Decision 8 conclusion
is falsified and its rejected option is the one adopted here, its Decision 9
reasoning is falsified while its conclusion survives on other grounds, and the
PRD's floor requirement plus its "commit history is the recovery path" claim are
both superseded.

**Dependencies**: B3

## Implementation Sequence

**Critical path.** `B1 → B2 → B3 → B5`, then `C1 → C2 → C3 → C4 → C5`. Nine of
twenty issues, and every other issue hangs off a node in it.

**Parallelizable immediately.** All of `A1`, `A2`, `A3`, `A4`, `A5`, `D1` and `D2`
depend on nothing. They are the repairs and the sibling-skill work, and none of
them waits on the feature.

**Parallelizable after `B1`.** `B4`, `C1`, `C7` and `D4` each need only the
contribution table and path constant.

**Ordering hazards, stated rather than discovered.** `A2` is reopened by `C4` and
`A3` by `C3`; both are provisional by construction rather than by oversight. `C6`
needs `A5` to have dropped the field it replaces. `D3` must land after `C2` and
`C6` so the rewritten scenarios grade the shipped behaviour rather than the
intended one.

**Sequencing rationale.** A before B is not a technical dependency but a
correctness one: the feature's firing condition reads a field A1 creates, and its
deletions are outside the enumerated surface until A2 lands. Building B and C on
top of the unrepaired ground would produce a mechanism whose gate reads an empty
field and whose deletions fail the hard-finalization check.

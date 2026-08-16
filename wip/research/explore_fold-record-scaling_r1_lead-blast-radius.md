# Lead: What is the blast radius of removing or replacing the fold record (`docs/folds.md`)?

## Findings

### Removal inventory

Every binding found by grepping `folds.md`, `fold`, `absorbed`, `--record`, and
`fold record` across the repo. Effort is the mechanical edit cost only; the
requirement-supersession cost is priced separately in question (1).

| # | File (line) | What it does with the record | Removal class | Effort |
|---|---|---|---|---|
| 1 | `docs/folds.md` (1-63) | The record itself: header, "Why this exists", column contract, concurrency note, empty table | **Deletion** — `git rm` | Trivial |
| 2 | `.gitattributes:3-10` | 7-line comment block + `docs/folds.md merge=union` | **Deletion** — removes the repo's only merge driver; file drops to 1 line | Trivial |
| 3 | `.github/workflows/validate-docs.yml:102-166` | The whole `Verify the fold record` step: fold-signature trigger, row-exists assert, blob-hash assert, append-only assert | **Deletion** (or *rewrite* to a reduced check — see Q3) | Small (~65 lines out of a reusable workflow; see the caller note below) |
| 4 | `skills/scope/scripts/check-citations.sh:52,56,69,75,99-101,115-116,121,145` | `--record` flag, `record="docs/folds.md"` default, the `^docs/[a-z0-9-]+\.md$` shape assertion, and the `:!$record` pathspec exclusion in *both* grep tiers | **Rewrite** — drop the flag and both exclusions; the tier-1/tier-2 greps stay | Small; touches a security-reviewed argument-validation block, so the comment block above it (`# The record is not a chain document...`) goes with it |
| 5 | `skills/scope/scripts/check-citations_test.sh:117-127` | Test case "the fold record does not refuse a later hop" — writes a fake row, asserts exit 0 | **Deletion** — the case it guards ceases to exist | Trivial |
| 6 | `.github/workflows/check-scope-scripts.yml:19-23` | Runs the test above (indirect binding only; no direct mention) | No change | None |
| 7 | `skills/scope/SKILL.md:819-824` | "**Append**, by Phase 2's absorb: `docs/folds.md` — a fixed constant with nothing interpolated... Enumerated here and carved out of Phase 4's sweep" | **Rewrite** — the Closed Write-Target Set loses its Append group entirely | Small, but the surrounding prose argues *why* the append target is enumerated; that argument goes too |
| 8 | `skills/scope/SKILL.md:551-554` | "the firing condition, **the record**, and the prohibition..." — pointer into phase-2 | **Rewrite** — one clause | Trivial |
| 9 | `skills/scope/SKILL.md:520-522` | "...every link to it re-pointed, **and the fold recorded**" | **Rewrite** — one clause | Trivial |
| 10 | `skills/scope/references/phases/phase-2-chain-orchestration.md:667-669` | Absorb step 6: "Append the record and stage it... before anything is deleted, so a failed append aborts with nothing lost" | **Rewrite** — the nine-step procedure becomes eight; steps 7-9 renumber | Small |
| 11 | `phase-2-chain-orchestration.md:681-700` | Rollback table row `| 6 append | un-stage and remove the appended row; restore the survivor |`, plus rows 7/8 which each say "un-append", plus the closing paragraph "The un-append is explicit because the row is forced to exist before the deletion" | **Rewrite** — table shrinks by a row and three cells; the paragraph deletes | Small |
| 12 | `phase-2-chain-orchestration.md:823` | Enum re-validation rationale: "...records it, and omitting it from the enum would fail the... durable fold record" | **Rewrite** — the justification for an enum re-validation now needs a different (still valid) reason: the value still reaches the survivor's `## Status` line | Small — do not just delete, or an unjustified security control is left behind |
| 13 | `skills/scope/references/phases/phase-3-exit-finalization.md:318` | "- **Append:** `docs/folds.md`, a fixed constant." in the closed write-target read-back | **Rewrite** | Trivial |
| 14 | `skills/scope/references/phases/phase-4-cleanup.md:101-110` | The "**`docs/folds.md` is enumerated and never swept**" carve-out and its 9-line justification | **Deletion** | Trivial |
| 15 | `skills/execute/SKILL.md:596-600` | "Distinguishing it from a genuinely unfinalized chain is what `docs/folds.md` is for: a chain that folded away leaves a row... The record is the evidence" | **Supersession that needs a documented lifecycle move** — this is a *behavioural* claim about how a human/CI disambiguates a fully-folded chain from an unfinalized one. Deleting the sentence leaves the disambiguation unanswered | Medium — needs a replacement answer, not an edit |
| 16 | `skills/execute/scripts/run-cascade.sh:465` | Emits the literal roadmap cell `**Downstream:** _none (chain folded; see docs/folds.md)_` | **Rewrite** — the string must change or it writes a dangling pointer into every roadmap it touches | Trivial edit, but it is a *durable output string*: roadmaps already merged carrying that text would become stale (none exist today — see Q2) |
| 17 | `skills/execute/scripts/run-cascade_test.sh` | Asserts the no-DESIGN scenario; does not grep the literal string (checked — no `folds` hit) | No change unless the assertion is tightened | None |
| 18 | `docs/guides/doc-validation.md:54-69` | The whole `### Fold-record verification` subsection — the adopter-facing contract for the check | **Rewrite/deletion** — this is public adopter documentation for a reusable workflow | Small |
| 19 | `docs/designs/current/DESIGN-scope-artifact-persistence.md` — frontmatter `decision:` (L19-20), `rationale:` (L27-29), L231, L306-337 (`### The record`), L412-415, L441-442, L477-490 (`### The record checker's trigger`) | The record is one of the six decided questions and one of the Components-table rows | **Supersession that needs a documented lifecycle move** — status `Current` | Medium |
| 20 | `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:845-847` | In the *Amendment* section: "the record of *what happened* is `docs/folds.md`, which survives on the default branch whether or not any chain artifact does" — this sentence is the stated answer to the objection that killed Option D | **Supersession** — status `Current`; amending an amendment | Medium |
| 21 | `docs/prds/PRD-scope-consolidation-over-skipping.md:411-415` | In the *Amendment — 2026-08-15* section: "The successor's R20 replaces the assumption with a mechanism: `docs/folds.md` records each fold..." | **Supersession** — status `Done` | Medium |
| 22 | `docs/prds/PRD-scope-artifact-persistence.md:189-196, 241-254` (**R15** bookkeeping clause, **R20**) | **The actual requirement backer.** R20 is the fold-record requirement verbatim | **Supersession** — status `Done` | Medium-high; see Q1 |
| 23 | `crates/shirabe-validate/src/formats.rs:175-186` | Doc comment on `ABSORBED_ENTRY_PATTERN`: names three readers, one of which is "the record checker's fold signature (the *trigger*)" | **Rewrite** — comment only, no code | Trivial |
| 24 | `.github/workflows/check-scope-scripts.yml:25-31` | Same three-reader claim in a step comment | **Rewrite** — comment only | Trivial |
| 25 | `skills/*/evals/evals.json` | **No eval anywhere asserts on the record.** Grepped all 20 skills: `folds.md` appears in zero eval files. Scope evals 289-325 assert on absorb/carry-check/abort behaviour, none on the row | No change | None |
| 26 | Rust/Go source | **No source code reads or writes the record.** The only Rust hits are the `formats.rs` comment (row 23) and unrelated uses of the word "folded" (`coordination.rs`, `merge_gate.rs`, `lifecycle.rs`) | No change | None |

**Mechanical total:** roughly 200 lines across 14 files, of which about 120 are
prose justification rather than logic. No compiled code changes. No test changes
beyond deleting one test case. No eval changes.

**One non-obvious cost:** `validate-docs.yml` is a *reusable* workflow
(`on: workflow_call`, L16) consumed by koto, niwa and tsuku
(`docs/briefs/BRIEF-writing-style-enforcement.md:151`) and pinned by tag
(`@v0.6.0`). Removing a check from a reusable workflow is backward-compatible for
callers — it can only stop failures, never start them — so no coordinated
multi-repo move is required. But `docs/guides/doc-validation.md` is the published
contract for those callers and must be updated in the same change.

---

### (1) Requirement backing

**The requirement that actually backs the record is not in
`PRD-scope-consolidation-over-skipping.md`.** That PRD predates the record; it
mentions `docs/folds.md` exactly once, inside its `## Amendment — 2026-08-15`
section (L414), and only to say that its *own* Out-of-Scope claim ("the commit
history is the recovery path") was falsified and that a successor requirement
replaced it. The requirement doing the work lives in
`docs/prds/PRD-scope-artifact-persistence.md`, which is the upstream of
`DESIGN-scope-artifact-persistence.md`.

**Requirements discharged by the record:**

- **R20** (`PRD-scope-artifact-persistence.md:241-254`) — *"A fold SHALL NOT land
  unless a record was written to the default branch naming what folded into what,
  on what verdict, with the per-contribution carry result and a content hash of
  the pre-fold original."* This requirement is discharged **only** by
  `docs/folds.md`. Its explanatory paragraph goes further and forecloses every
  alternative carrier by construction: *"'Written to the default branch' means
  the record **remains** on the default branch — present in a checkout,
  greppable — not merely that it was written to some commit later removed."* Any
  replacement that lives in git history, a PR body, or a chain document is
  ruled out by the requirement text itself, not merely by the design.
- **R15** (`PRD-scope-artifact-persistence.md:160-196`) — the citation preflight.
  Discharged by `check-citations.sh`, **but** its "excluding any bookkeeping
  surface the procedure itself writes" clause and the three paragraphs at L173-196
  exist *solely* because the record exists. Removing the record makes that clause
  vacuous rather than unmet. This is a rewrite, not a supersession.
- **R19** (L233) — "closed write-target set SHALL name every path an absorb at
  any hop writes or deletes." Still met after removal (the set just shrinks).
- **R19a** (L236-239) — "The absorb SHALL stage and commit its own output... R20's
  record cannot reach the default branch until this is settled." Still met; it
  loses its stated motivation but the `upstream:` re-point and deletion still
  need committing.

**Design decisions discharged by the record.** Note that
`DESIGN-scope-artifact-persistence.md` does **not** use `D<n>` identifiers — its
six decisions are named by prose headings under `## Considered Options`
(L142-204). The record is one of them:

- **"What surface carries the fold record"** (L167-177) — decided in favour of
  a shared index over the survivor's frontmatter and over the PR body's durable
  half. Removing the record does not pick a different option; it un-asks the
  question. Its losing-option reasoning includes the empirical PR-body finding
  (five real merged PRs byte-compared; one silently lost 184 of 622 bytes through
  the merge dialog), which is evidence that would need re-examining if a
  replacement carrier is proposed.
- **`### The record`** (L306-337) and **`### The record checker's trigger`**
  (L477-490) in `## Decision Outcome` — the operative specification.
- `DESIGN-scope-consolidation-over-skipping.md:840-847` — the record is the
  *stated answer* to the objection that originally rejected Option D ("make
  DESIGN absorbable into PLAN"). That objection was, in the doc's own words,
  *"answered rather than overruled."* Remove the record and the answer is
  withdrawn while the decision it rescued stays. This is the sharpest
  requirement-backing consequence in the set: it is not a dangling reference, it
  is a load-bearing argument losing its premise.

**Current statuses (all three terminal):**

| Doc | `## Status` | Terminal? |
|---|---|---|
| `docs/prds/PRD-scope-consolidation-over-skipping.md` | **Done** (L25) | Yes — `prd/v1` statuses are `Draft, Accepted, Done` |
| `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md` | **Current** (L38) | Yes — `design/v1` statuses are `Proposed, Accepted, Planned, Current, Superseded` |
| `docs/designs/current/DESIGN-scope-artifact-persistence.md` | **Current** (L37) | Yes |
| `docs/prds/PRD-scope-artifact-persistence.md` (the real backer) | **Done** (L24) | Yes |

**What shirabe's own process says about amending a terminal artifact.** There is
a direct, in-corpus precedent, and it is these exact documents. Both
`PRD-scope-consolidation-over-skipping.md` (L394, `## Amendment — 2026-08-15`)
and `DESIGN-scope-consolidation-over-skipping.md` (L822, same heading) were
amended in place *while at terminal status*, with the pinned formula: **"The
original text above is left unedited; this section records what no longer
holds."** `DESIGN-scope-artifact-persistence.md`'s own Components table
(L446) prices that move as one row: *"Two shipped documents | Appended dated
amendment sections."*

The lifecycle alternative is worse and the corpus already says so. `shirabe
transition` supports a supersession (`--superseded-by`,
`crates/shirabe/src/main.rs:133`) but only for `design Superseded` and `vision
Sunset` — **a PRD has no superseded status at all** (`formats.rs:271`:
`Draft, Accepted, Done`). So `PRD-scope-artifact-persistence.md`'s R20 *cannot*
be superseded by a status transition; the amendment section is the only
mechanism available. And `DESIGN-scope-artifact-persistence.md:203-204` rules on
this question explicitly for the DESIGNs: *"Superseding them via the lifecycle
overcorrects, discarding real unaffected content across a document whose other
decisions are sound."*

**So the requirement-side price is:** three or four dated amendment sections
(the two persistence docs, plus amending the existing amendments in the two
consolidation docs), each stating that R20 no longer holds and *what replaced
it or why nothing needs to*. No status transitions, no `shirabe transition`
invocation, no folder moves. `docs/guides/doc-validation.md` carries no rule
about amending terminal artifacts — the rule is entirely by precedent and by
the DESIGN's own ruling.

---

### (2) Existing data — the migration cost is zero

Confirmed on both branches.

- `git log --oneline -- docs/folds.md` returns exactly **one commit**:
  `83d29e1 feat(scope): decide absorbability from the documents, not the types (#302)` —
  the commit that created the file. Nothing has touched it since.
- `git show origin/main:docs/folds.md` ends at the header row and the separator:

  ```
  | Date | Absorbed | Into | Verdict | Carried | Blob |
  |---|---|---|---|---|---|
  ```

  **Zero data rows on `origin/main`.**
- `git diff origin/main...HEAD -- docs/folds.md` is empty — this branch has not
  changed it either.

**The record has never recorded a real fold.** It is 63 lines of header, rationale
and column contract with an empty table underneath. There is no data to migrate,
no consumer to notify, and no historical row whose meaning would be lost.

**Could an adopter repo already have rows?** No, with one caveat.

- The file is **created on first append**, not shipped:
  `DESIGN-scope-artifact-persistence.md:308` — *"appends one row to `docs/folds.md`,
  created on first append."*
- Nothing distributes it. `install.sh`, `.release/`, `.claude-plugin/`, `scripts/`
  and `references/` contain no reference to it (grepped; zero hits). It is not in
  any template set.
- Therefore an adopter repo has a `docs/folds.md` only if a `/scope` run in that
  repo completed an absorb. Since shirabe's own repo — the only one running the
  newest `/scope` — has zero rows, an adopter having one is possible in principle
  but unlikely, and unverifiable from here.

**The caveat, and it is a real defect worth surfacing separately:** adopter repos
get the *fold check* (via the pinned reusable workflow) but **do not get the
`merge=union` line**, because `.gitattributes` is shirabe's own file and is not
distributed. So in every adopter repo, the record's stated concurrency mitigation
does not exist — two parallel chains each appending a row would produce an
ordinary merge conflict. The mechanism the user is worried about is *already*
worse everywhere except here.

---

### (3) The validate check coupling — a coherent reduced check already exists and already runs

The CI step is gated on the fold signature (`validate-docs.yml:117-133`): a
deleted chain document **plus** an `absorbed:` declaration naming its path added
in the same diff. Strip the record and three assertions remain in the step, and
all three are *about the record itself*:

1. **Row exists** for the absorbed doc (L137-140) — self-referential; vanishes.
2. **Row's blob hash matches the pre-fold blob** (L145-151) — self-referential;
   vanishes. This is the only assertion in the entire system that ties the fold
   to the *bytes* that were deleted.
3. **Append-only** (L155-163) — self-referential; vanishes.

So if the record goes and `absorbed:` stays, **nothing is left of the step.** It
should be deleted outright rather than reduced.

**And that is fine, because `shirabe validate` already does the static half —
in the same job, one step earlier.** `check_fc18`
(`crates/shirabe-validate/src/checks.rs:363-500`) is gated entirely on
`absorbed:` being present and enforces, at error level:

- the declaration parses and yields a usable entry (`FC18`, L390-392);
- each entry matches `ABSORBED_ENTRY_PATTERN` (L393-396);
- no cross-repo entry (L397-399);
- each absorbed type is strictly *upstream* of the declaring type (L420-425) —
  a PRD cannot declare it absorbed a DESIGN;
- the `## Status` section carries the pinned absorption line
  `Absorbed [<name>](<path>); carried in <Heading>.` for **every** declared entry
  (L480-490);
- the contribution sections exist, in chain order, adjacent to `## Status`
  (via the `required_sections_for` splice, L295-320).

`check_fc19` (L518-560) additionally catches requirement citations orphaned by
the fold. And the workflow passes every changed doc to `shirabe validate`
(`validate-docs.yml:88-101`) — a survivor gaining an `absorbed:` declaration is
by definition a changed file, so FC18/FC19 fire on exactly the documents the
fold check triggers on.

**What is uniquely lost, precisely:** the blob-hash tie between the declaration
and the bytes actually deleted, and the guarantee that a fully-folded chain
leaves *anything* on the default branch. Everything else the CI step asserts is
already asserted statically by the CLI. Note that the blob-hash assertion is
the one thing that cannot be reconstructed statically — `shirabe validate` reads
files, not git history — so a "reduced check" that keeps hash verification would
have to keep a record to verify against.

`formats.rs:175-186` states the three-reader model (gate / backstop / trigger)
and says *"None substitutes for another."* Removing the record removes the
trigger. The gate (`check-citations.sh`) and the backstop (FC18) are untouched,
so the claim stays true for the two that remain.

## Implications

**The mechanical removal is cheap and the data migration is free.** Fourteen files,
about 200 lines, no compiled code, no tests beyond one deleted case, no evals, and
an empty table with a single creating commit behind it. Anyone pricing this as a
big move is wrong on the mechanics.

**The expensive part is entirely documentary, and it is bounded.** Four dated
amendment sections following a formula this corpus has already used twice on
these same documents. R20 in `PRD-scope-artifact-persistence.md` is discharged
*only* by the record, and a PRD has no superseded status, so amendment-in-place
is not a choice — it is the only mechanism the toolchain offers. Budget one
careful editing pass, not a lifecycle workflow.

**The decision the exploration actually has to make is narrower than "remove or
replace."** It is: *does anything still need to distinguish "absorbed" from
"never produced" on the default branch, and does anything need the blob-hash
tie?* If yes, R20's own wording ("remains on the default branch — present in a
checkout, greppable") has already foreclosed PR bodies, git history and chain
documents, so a replacement must be another durable file and the growth/conflict
problem returns in a new shape. If no, R20 is amended away and the removal is a
straight deletion. Everything else in the inventory follows mechanically from
that one answer.

**Two consumers need a replacement answer regardless of which way it goes:**
`skills/execute/SKILL.md:596-600` (how does a caller tell a fully-folded chain
from an unfinalized one?) and `run-cascade.sh:465` (what does the roadmap's
Downstream cell say when the chain folded to nothing?). Neither is hard, but
neither is a delete.

## Surprises

**1. The record has never been used, and CI has never run the check against a
real fold.** One commit, zero rows, on every branch. The append-only assertion,
the blob-hash assertion, the union merge driver and the whole "first shared
append-only durable file in this repository" framing have all been carrying a
file with an empty table since #302. The merge-conflict problem motivating this
exploration has never actually occurred.

**2. The lead's premise about which PRD backs the record is off by one document.**
`PRD-scope-consolidation-over-skipping.md` does not require the record — it
mentions it once, in an amendment, as the *successor's* mechanism. The binding
requirement is R20 in `PRD-scope-artifact-persistence.md`, which the lead did not
name. That PRD is also at `Done` and is the one that cannot be superseded by a
status transition.

**3. There is already a second carrier of nearly the same information, and it
predates the record.** `skills/scope/references/state-schema.md:204-208`:
*"Phase 3 copies `chain_ran`, `chain_skipped`, and `consolidation_judgments` into
the run's PR body before Phase 4 removes the state file... the PR body is where a
reviewer can tell 'not produced' from 'absorbed into this other document' after
the scratch is gone."* That is verbatim the job `docs/folds.md` claims as its
reason to exist. The DESIGN rejected the PR body as the *authoritative* carrier on
a fidelity finding (one of five byte-compared merged PRs silently lost 184 of 622
bytes through the merge dialog) — but it never removed the soft copy. So the
distinction is already recorded twice, once durably-but-empty and once
lossily-but-actually-populated.

**4. Adopter repos got the check without the conflict mitigation.**
`validate-docs.yml` is reusable and pinned by koto, niwa and tsuku, so the fold
check runs in their PRs. `.gitattributes` is not distributed, so `merge=union`
never reached them. If the growth-and-conflict argument is the case for removal,
it is strictly stronger for adopters than for shirabe itself.

**5. The record is load-bearing for a rejected-then-rescued decision.**
`DESIGN-scope-consolidation-over-skipping.md:840-847` rejected Option D (DESIGN
absorbable into PLAN) because it "trades a durable audit trail for a shorter run,"
then says that objection was *"answered rather than overruled"* — and the answer
is the record. Removing the record withdraws the answer while Option D's
reversal stays shipped. That is not a dangling citation; it is an argument losing
its premise, and it is the one place where the amendment has to say something
substantive rather than "no longer holds."

## Open Questions

1. **Does the "absorbed vs. never produced" distinction still need a durable
   default-branch carrier at all?** The PR-body copy already exists and is
   populated. If the answer is "the PR body is good enough," R20 is amended away
   and the removal is clean. If not, R20's own wording constrains any replacement
   to another durable greppable file. This is the decision the whole inventory
   hangs on and it needs a human call.

2. **What replaces the Option-D answer in
   `DESIGN-scope-consolidation-over-skipping.md`?** The amendment must say
   something, and "nothing records what happened" reopens a decision that was
   settled on the strength of the record existing.

3. **Do koto, niwa or tsuku have a `docs/folds.md` with rows?** Unverifiable from
   this repo. Cheap to check and it flips the migration-cost-is-zero claim if any
   does. (Low likelihood: shirabe itself has none.)

4. **Is the blob-hash tie worth preserving in any form?** It is the only
   assertion in the system connecting a fold declaration to the bytes actually
   deleted, and it is the one thing `shirabe validate` structurally cannot do
   (it reads files, not history). If it matters, no static check can replace it.

5. **Should the roadmap Downstream cell say something else, or nothing?**
   `run-cascade.sh:465` currently writes a pointer into a durable roadmap. No
   roadmap carries that text today, so the choice is free — but it is a choice.

## Summary

The mechanical removal is cheap and the migration cost is literally zero: 14 files
and ~200 lines (mostly prose), no compiled code, no evals, one deleted test case,
and a record that has exactly one commit and zero rows on every branch — it has
never recorded a real fold. The real price is documentary and bounded: R20 in
`PRD-scope-artifact-persistence.md` (status Done, and a PRD has no superseded
status) is discharged only by the record, so removal needs dated in-place
amendment sections on four terminal docs, following a formula this corpus has
already used twice on these same documents. The biggest open question is whether
the "absorbed vs. never produced" distinction still needs a durable default-branch
carrier at all, given that `consolidation_judgments` is *already* copied into the
run's PR body for exactly that purpose — if the PR body suffices, R20 is amended
away and the removal is a straight deletion.

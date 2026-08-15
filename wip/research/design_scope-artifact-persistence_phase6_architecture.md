# Phase 6 architecture review — DESIGN-scope-artifact-persistence

PASS

Second review, against the rewrite at `61592e7`. All three blocking findings and
all four major findings from the first pass are discharged, and I checked each
against the decision reports and the tree rather than against the summary of what
changed. All 31 PRD requirements now have a design element I can point at. Three
residuals are named at the end; none blocks a plan.

The first-pass verdict and its findings are superseded by this document.

---

## 1. The blocking findings

### R18 — discharged

Re-validation is step 8, commit is step 9, and a rollback table covers steps 5-9.
Checked against R18's four clauses: the absorbed document restored (steps 7-9
rows), the `upstream:` splice undone and the declaration, `## Status` line and
contribution section removed (subsumed by "restore the survivor's pre-fold
bytes"), and the revert recorded — the design routes it to the state file's
judgment entry and to bail-handling, which matches `phase-2:500-501`'s existing
route. The un-append is explicit, with the reason: the row is forced to exist
before the deletion, so a revert that does not un-append strands a durable row
asserting a fold that was undone. That was the obligation the earlier draft named
and left unspecified; it is now specified.

R30's fourth decision point has a mechanism. All four now do: preflight (exit
status 3, default-deny routing), carry check (step 4 abort), post-absorb
re-validation (step 8 into the table), record production (step 6 before step 7).

The design also says out loud that step 8 is the shipped procedure's step 4
retained rather than dropped, and books it under Positive. That is the right
disposition — the earlier draft's silent loss of an existing safety step was the
part of the first finding that mattered most.

### Step 3's write site — discharged

"Step 3 composes in memory; the survivor is not written until step 5." Steps 1-4
are now genuinely pure aborts, so a carry failure leaves the survivor untouched
and the design no longer produces the orphan-section state it eliminates
child-at-drafting-time authoring for. R13's "text that already exists" is
satisfied by composed text and the design argues the point rather than assuming
it; the PRD's `[insp]` criterion (authoring step precedes carry-table step) has a
referent.

### R15's coverage bound — discharged

Stated in Stage 1, where D4 asked for it, and stated correctly: the preflight
protects citers that pre-existed the run and cannot protect a target the run
created, so under the firing condition the live coverage is same-run citers. The
15-of-36 figure is requalified as a measurement over the retroactive population.
The Consequences paragraph that quoted it as a forecast is gone, and the Positive
paragraph no longer calls the preflight "the only guard that can catch it".

---

## 2. The major findings

- **R14** — step 4 itemizes the ancestor's required sections *and* its own and
  inherited contributions, naming the `absorbed:` list and the ancestor's
  contribution sections as the inputs. The precondition the ordering previously
  left unestablished is now established.
- **R21** — the new check gains a fifth clause owning the `## Status` line, and
  the design states plainly that only the *shape* is borrowed from
  `shirabe transition` while the mechanism is not extended (`transition.rs` writes
  in Rust behind a subcommand; this line is written by the absorb). The Decision
  Drivers entry was amended in the same spirit: "Where this design borrows a
  *shape* without extending its mechanism, it says so." That is the honest form of
  the claim I flagged.
- **R22** — `exit_artifacts:` for a fully folded chain now has an owner and a
  location in Components. See residual 2 for what is still thin.
- **R23** — two `/work-on` rows, the implementation phase and the maintainer
  reviewer's brief. Both paths exist:
  `skills/work-on/references/phases/phase-4-implementation.md` and
  `phase-4b-review.md`.

---

## 3. The strawman check, re-run

**Discharged, and the fix is the right one.** The invented "adding contributions
to the base required lists" option is gone. In its place are D5's two actual
closest losers, and I checked both against the report:

- *Splice only, no new check code* — D5: "minimal and satisfies R8 and R9 as
  written. Rejected because R4's adjacency contract then goes entirely unchecked."
  The DESIGN now says exactly that, including why the existing order check cannot
  cover it (relative order only, behind a promotion seam at notice level).
- *A standalone check owning presence, order and adjacency* — D5: "smallest blast
  radius on shared code. Rejected because it re-implements presence and order
  beside the two checks that already do it, contradicts R9's instruction." The
  DESIGN carries both halves.

The stage-1 paragraph now credits the withdrawn pre-filter alternative for the
ceiling and the input restriction ("its contribution rather than this design's"),
carries the dissolution advocate's counter, and states its consequence — the
restriction is written at both positions *because* that counter has force. It also
carries D4's 0.85 hold and the floor finding. That is a fair account of a losing
option at its strongest.

Two smaller accuracy repairs I did not ask for and should note: the referrer map
is now "77 of 271 path-citing lines" rather than a percentage, and the PR-body
paragraph now says its advocate explicitly declined to kill it on the three
obvious objections, which is what D1 records. The contested revert row is still
recorded as contested with its tally.

---

## 4. Structural fit, layering, ordering, phases — re-checked

**Seams.** `required_sections_for` at `checks.rs:181` with two callers, and all
eleven required-section profiles beginning with `"Status"` — verified in the first
pass, unchanged. The abort path is real reuse. The `superseded_by:` claim is now
correctly scoped to the shape.

**Layering.** The contribution table is described as three mirrors — `formats.rs`,
the four format references, and Phase 2's composer — with the drift consequence
named (a check failure at fold time, after the mutations). I agree with not adding
a test: eight format references already duplicate their required-section lists
against `formats.rs` with nothing enforcing agreement, and breaking that pattern
here would be this change carrying a corpus-wide cleanup it did not cause.
Naming the third mirror is the fix; the design took it.

**Ordering.** Nine steps, each precondition established by an earlier one. The
blob hash is computed at step 6 while the file still exists (step 7 deletes).
Step 6 before step 7 does what the design claims. The new
`### The preflight script's contract` section is a genuine improvement I did not
ask for: the script's exit codes are declared as its own contract rather than
`git grep`'s inverted one, and the routing default is deny — any status other than
0 or 2 routes to `keep`, including undefined ones.

**Write-target set.** Now enumerated rather than described, and the enumeration is
correct: deletions are BRIEF/PRD/DESIGN with the PLAN excluded (nothing absorbs a
terminal artifact), mutations are PRD/DESIGN/PLAN because at the terminal hop the
PLAN is the survivor. That resolves the `SKILL.md`-versus-Phase-3 contradiction the
right way — `SKILL.md:719-723` lists "the terminal PLAN under `docs/plans/`" and
`phase-3:299-302` says Phase 3 does not write it; both are true once the phase is
named.

**Phases.** `stage:` moved to Phase C, since its values name stages C creates —
the one genuine backward dependency, removed. The write-target and commit repairs
are marked provisional with their reasons rather than presented as final.

**New security material.** Three additions I did not ask for and that are right:
`chain_ran:` has been promoted from bookkeeping to the only thing standing between
the judgment and a document the run did not produce, so Phase 2's existing
paragraph declining to re-validate chain-shape fields is rewritten rather than
left to read as a considered exemption; the visibility boundary is correctly
located at the `upstream:` splice rather than at the record, since a private
cross-repo parent could ride into a public survivor; and the record checker's
trust boundary is stated — the file is hand-editable and a forged row would pass,
so it is an audit aid rather than an authorization.

---

## 5. Residuals — none blocking

1. **The rollback table needs a source for "the survivor's pre-fold bytes."**
   Step 5's undo assumes those bytes are recoverable, and nothing in the ordering
   says step 5 captures them first. `git checkout HEAD -- <survivor>` is not
   guaranteed to resolve to them, because `/scope` commits nothing before the fold
   and Phase A's commit repair is scoped to the absorb's own output. The design
   specifies *what* must be undone, which is what R18 asks of a design; the plan
   must add the snapshot step, and step 3's in-memory composition is the pattern to
   follow. Worth a line in the plan's first phase so it is not discovered at
   implementation time.

2. **R22's contract has a home but no content.** The Components row says the
   `exit_artifacts:` contract for a fully folded chain is "stated"; the design does
   not say what it states. One clause would settle it — whether a fully folded
   chain seeds an empty list, or the record row, or the implementation PR. The
   `[judg]` criterion grades the guard against "R22's stated contract", so
   something must state it before that criterion is gradeable.

3. **Eval 17 is not named as untouched.** D4: "Eval 17 is untouched, which is what
   the R28 tripwire needs." The design says three scenarios are rewritten without
   saying which three or that 17 stays. Cheap insurance against a plan that
   rewrites the R28 tripwire while rewriting its neighbours. (Separately, D4 also
   wanted `verdict:` added to Phase 2's enum re-validation list, which today covers
   four fields and omits it; the design adds `chain_ran:` and not `verdict:`. No
   requirement rides on it.)

---

## 6. Requirement map

All 31 have an element.

| Req | Design element |
|---|---|
| R1 | Type test and mapping table deleted |
| R2 | Firing condition on `chain_ran:`, declared stricter than R2 as written |
| R3 | Contribution table in `formats.rs` |
| R4 | Splice immediately after `## Status` |
| R5 | Table keyed by filename prefix |
| R6 | Flat complete `absorbed:` list in chain order |
| R7 | Four format references, two-sided adequacy test |
| R8 | `absorbed:` + spliced required list, gated on presence |
| R9 | `required_sections_for` feeds presence and order checks |
| R10 | Content-boundary carve-out in three format references |
| R11 | Falls out of R1; terminal hop named, PLAN as survivor |
| R12 | "No reviewer, no confirmation, no mode-conditional gate" |
| R13 | Step 3 in memory, before step 4, argued explicitly |
| R14 | Step 4 itemizes own and inherited contributions |
| R15 | Stage 1 preflight, exclusion set, script contract, coverage bound |
| R16 | Requirement-citation check scoped to the absorb event |
| R17 | Step 5 splice preserving siblings and cross-repo parents |
| R18 | Step 8 re-validation + rollback table, revert recorded |
| R19 | Enumerated write-target set in both declaration sites |
| R19a | Step 9 |
| R20 | `docs/folds.md` + fold-signature checker |
| R21 | `absorbed:` + `## Status` line, fifth check clause owns the shape |
| R22 | `/execute` rows incl. `exit_artifacts:` contract (see residual 2) |
| R23 | Two `/work-on` rows |
| R24 | `evals.json` row |
| R25 | `absorbable:` dropped, `stage:` in Phase C |
| R26 | `doc-validation.md` row |
| R27 | Floor prohibition sited in Phase 2 |
| R28 | Decision Drivers (see residual 3) |
| R29 | Every added obligation gated on `absorbed:` presence |
| R30 | Four decision points, each with a fail-safe |

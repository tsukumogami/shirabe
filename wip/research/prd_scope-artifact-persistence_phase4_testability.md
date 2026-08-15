# Testability review — PRD-scope-artifact-persistence

FAIL

Reviewer: testability. Completeness and clarity are owned elsewhere; findings
below are confined to whether a criterion can be verified, by what instrument,
and whether the PRD is honest about which criteria need an agent's judgment.

## What the repository actually offers as verification routes

Establishing this first, because several findings turn on what exists.

| Instrument | Where | Gated on PRs? | Grades what |
|---|---|---|---|
| `cargo test --workspace` | `.github/workflows/build-and-test.yml` | yes | Rust validator behaviour |
| Byte-exact golden parity | `crates/shirabe/tests/parity.rs`, 29 corpus files (5 `real/`, 24 `synthetic/`) with captured `stdout`/`stderr`/`exit` | yes, via `cargo test` | validator output, one `#[test]` per file |
| Absorption rule-set parity | `crates/shirabe/tests/absorption_parity.rs` | yes | fired-rule-set diff vs frozen external oracle |
| Corpus self-check | `crates/shirabe/tests/fc07_corpus.rs` | yes | `docs/plans` + `docs/roadmaps` only, notice-level only |
| Cascade shell harness | `skills/execute/scripts/run-cascade_test.sh` (1519 lines, `scenario_*` fns, `assert_json`, `write_design`/`write_prd`/`write_brief`/`write_plan` helpers) | yes, via `check-execute-scripts.yml` | real cascade behaviour on a temp repo |
| Doc validation CI | `validate-docs.yml` | yes, but **changed docs only** (`git diff`) | no corpus-wide gate exists |
| Cross-repo byte parity | `parity-check.yml`, `docs/**/*.md` vs Go baseline at SHA `20fb8ed` | **no self-caller in shirabe** | downstream opt-in only |
| Skill evals | `skills/scope/evals/evals.json`, 26 scenarios | **no** — `run-evals.yml` is `cron '0 4 * * 1'` + dispatch; `check-evals.yml` only asserts evals *exist* | LLM-graded, and **plan-graded**: prompts are `/scope <topic>`, expectations read "Plan does X" |
| Tier-2 evals | `scripts/run-evals.sh` isolated-clone mechanism | no | real workflow execution; used by `/execute`, **not by `/scope`** |

Two consequences the PRD never states:

1. **Every criterion whose subject is agent-followed prose is gradeable only by
   an instrument that does not run on PRs and that grades stated intent, not
   behaviour.** `/scope`'s 26 evals are all tier-1 plan-graded. That covers
   AC8, AC9, AC12, AC14 and both halves of the fold/keep pair.
2. **`shirabe` has no corpus-wide validation gate.** `validate-docs.yml`
   diffs; `fc07_corpus.rs` walks two subdirectories at notice level. AC7 has
   no home today.

## Per-criterion verification route

AC numbering is positional (AC1 = first checkbox).

| AC | Route | Verdict |
|---|---|---|
| AC1 fold, no durable artifact | none nameable — see F1 | **unverifiable as written** |
| AC2 keep on live alternatives | `/scope` eval, tier-1, LLM-graded, cron-only | judgment-dependent, ungated |
| AC3 differ only in content | manual inspection of the fixture pair | too weak — see F2 |
| AC4 one contribution section, ahead | Rust check + `synthetic/` fixture — **but no requirement mandates the ordering check** (F5) | partial |
| AC5 two sections, chain order | same as AC4 | partial |
| AC6 validate fails missing section | Rust unit test in `crates/shirabe-validate/src/checks.rs` + `synthetic/` fixture | **sound — strongest AC in the document** |
| AC7 passes every doc in `docs/` | no instrument exists (F9) | no route |
| AC8 failed carry leaves both | `/scope` eval (precedent: eval 21) — plan-graded, cron-only; "records the failure" names no surface | weak |
| AC9 cited-by-path refused | `/scope` eval, plan-graded; covers only R10's path half (F7) | weak, partial |
| AC10 two parents spliced | Rust test + `synthetic/` fixture | sound |
| AC11 record on default branch | **surface is Open Question 1** (F4); "resolves" contradicts Known Limitation 3 | no route |
| AC12 `## Status` names section | frontmatter half mechanical; prose half judgment (F8) | split needed |
| AC13 no finding on dead-target field | Rust test + one `synthetic/` fixture | **sound** |
| AC14 finalization guard passes | `/execute` eval with fixture state file; unspecified `exit_artifacts` interaction (F6) | weak |
| AC15 no dangling roadmap ref | `run-cascade_test.sh` scenario — **CI-gated, real execution** | **sound, and the bug is already visible** (F10) |
| AC16 no eval asserts the old rule | manual inspection of 26 scenarios; **screens for the wrong string** (F11) | unsound |
| AC17 cargo test + fixtures updated | `build-and-test.yml` + `parity.rs`; second clause asserts a property of a commit (F12) | partial |

## Findings

### F1 — AC1 asserts a post-`/execute` state at the end of a `/scope` run, and needs three stochastic verdicts to conjoin

AC1: "folds that DESIGN into the PLAN, and the run ends with no durable
artifact in `docs/`."

Three problems, compounding.

*Scope.* At the end of a `/scope` run the PLAN is on disk. It is the terminal
artifact, and `references/parent-skill-state-schema.md:64-68` requires a
full-run exit to list it in `exit_artifacts`. The PLAN only leaves `docs/`
when `/execute`'s finalization cascade deletes it. So "the run ends with no
durable artifact" is false of the `/scope` run and true only after a separate
skill has run to completion. As written the criterion cannot be evaluated at
the boundary of the thing it is a criterion for.

*Conjunction.* Reaching zero artifacts requires BRIEF→PRD, PRD→DESIGN and
DESIGN→PLAN all to absorb. Each is an independent LLM verdict. A criterion
that passes only when three graded judgments agree will flake, and a red run
will not tell you which verdict moved.

*Coverage beyond the requirements.* R6 enables only the DESIGN-to-PLAN hop
explicitly. PRD-to-DESIGN absorption is reachable only through R1's general
clause. AC1 therefore tests behaviour no requirement names in its own right.

**To become verifiable:** split it. (a) A DESIGN-to-PLAN hop with a
sequencing-only DESIGN returns `absorb` and the DESIGN is removed from disk —
one hop, one verdict, evaluable inside `/scope`. (b) If the zero-artifact
outcome is genuinely a criterion, state it as an end-to-end `/scope` +
`/execute` assertion, name that no instrument in this repo runs that pair, and
say it is verified by manual inspection of one recorded run.

### F2 — AC3 permits the confound that would make a green fold/keep pair meaningless

AC3 says the two chains "differ only in document content, not in flags, mode,
or invocation." That rules out the wrong variables. The variable that
threatens the result is *length*: if the folding fixture's DESIGN is 80 lines
and the keeping fixture's is 400, a green pair is consistent with a judge that
keyed entirely on size and never read a Decision. The PRD's own Decisions
section rejects a length floor precisely because length is the wrong signal —
AC3 then fails to control for it.

**To become verifiable:** AC3 should read that the pair is held constant on
line count within a stated band, section set, number of Decisions, `status`,
`upstream`, and topic slug, and differs only in whether the recorded
alternatives remain live.

### F3 — The fold/keep pair is verifiable, but only as a paired eval, and the PRD does not say so

Answering the brief's question directly: yes, it is verifiable, by exactly one
route — a paired tier-1 `/scope` eval entered mid-chain. The precedent exists:
evals 9 and 10 (`us-3a`, `us-3b`) pre-place `docs/prds/PRD-test-topic.md` and
`docs/designs/current/DESIGN-test-topic.md` and enter through the resume
ladder, so a fixture DESIGN + PLAN pair plus a state file with the
phase pointer at the DESIGN-to-PLAN hop reaches the judgment without paying
for four child skills to author anything.

What each fixture must contain:

**Fixture A (must fold).** A DESIGN whose every Decision is sequencing or
ordering and whose rationale is fully recoverable from the PLAN: e.g.
"Decision 1: issue 2 follows issue 1 because issue 2 imports the module issue
1 creates." Alternatives Considered present but every row resolved with no
consequence surviving the work. No security content, no risk analysis, no
invalidation condition. Its Implementation Issues table must be
order-isomorphic to the PLAN's issue list and dependency graph, so a reader
holding only the PLAN can reconstruct every claim the DESIGN makes.

**Fixture B (must keep).** Identical frontmatter shape, identical section set,
same Decision count, same line count band. At least one Decision carries a
rejected alternative whose reason is not implied anywhere by the PLAN's issue
order — the canonical shape is a rejection on a property the PLAN does not
encode ("rejected a shared trait-object registry: it forces dynamic dispatch
on the hot path"). Ideally one named invalidation condition, since that is a
claim about the future that no issue list can carry.

Both fixtures must be committed under version control and referenced by the
eval, so a later maintainer can see what the judge was asked to distinguish.

The honesty problem: this instrument grades a **stated plan**, not an executed
fold, and it runs weekly on `run-evals.yml`'s cron, not on PRs. AC1 and AC2
read as deterministic assertions about outcomes. They are single samples of a
graded judgment on an ungated instrument. The PRD's Known Limitations
correctly admit the *worth* judgment is ungradeable but do not admit that the
fold/keep discrimination — the feature's whole behaviour — is graded by an
LLM on a weekly cron against the agent's intent.

**To become verifiable:** name the paired eval as the instrument in the
criteria themselves, state that it is judgment-dependent and not a merge gate,
and add a Known Limitation saying so. If a stronger signal is wanted, adding
tier-2 to `/scope` (the isolated-clone mechanism already exists in
`run-evals.sh` for `/execute`) would let the pair grade the executed fold
rather than the described one; that is a design call, but the PRD should say
which it is buying.

### F4 — Four criteria assert against surfaces that Open Questions leave undecided

AC11 asserts a record "on the default branch" with four named fields. Open
Question 1 says the surface is undecided between a shared append-only index,
survivor frontmatter, and three deletion sites. Until that resolves, no
verification route can be named: the instrument for a committed index file is
not the instrument for a frontmatter key.

AC11 also asserts the pointer "resolves to the pre-fold content." Known
Limitation 3 says the content survives only in `refs/pull/<N>/head`, which is
"best-effort platform behaviour rather than a git guarantee" — which is why
R14 made the pointer content-addressed in the first place. So AC11 asserts
resolvability that the same document elsewhere says is not guaranteed. Checked
on the feature branch it passes; checked on the default branch after
squash-merge with branch deletion it can fail.

AC8's "records the failure" and AC9's "the citing file is named" have the same
shape at lower stakes: a surface is asserted without being named, so a verifier
does not know what to open.

**To become verifiable:** AC11 should assert the pointer's *form* — a
content hash that matches the pre-fold document's bytes — and state the
evaluation point (on the branch, before merge). AC8 and AC9 should name the
surface once Open Question 1 resolves, or state that they inherit it.

### F5 — R5's mechanization presupposes a stable section heading the PRD never requires

R5 says `shirabe validate` "SHALL require the contribution sections a
document's declared absorptions imply." AC6 turns that into a validator
assertion. Both only work if the contribution section has a fixed,
machine-recognisable heading per artifact type. R2 says each type "SHALL
declare one contribution" — a contribution, not a heading. Nothing in the PRD
requires the heading string to be stable or derivable from the absorbed type.
Without that, AC6 is unimplementable.

Separately, AC4's "ahead of the survivor's own content" and AC5's "in chain
order" are *ordering* assertions. R5 requires presence only. The existing
canonical-section-order check (`FC15`) is the natural home, but no requirement
extends it.

**To become verifiable:** add a requirement that each type's contribution
section has a fixed heading derived from the absorbed type, and that the
ordering constraint is enforced by the section-order check.

### F6 — AC14 collides with an `exit_artifacts` contract the PRD does not address

`references/parent-skill-state-schema.md:64-68`: for full-run exits
`exit_artifacts` "contains the terminal artifact's path." R16 requires
`/execute` not to assume a surviving DESIGN, and AC14 asserts the finalization
guard passes. But the R9 hard-finalization check reads `exit:` and
`exit_artifacts:`, and the PRD never says what `exit_artifacts` holds for a
chain that folded everything. A verifier cannot construct the fixture state
file without that answer.

**To become verifiable:** state what `exit_artifacts` contains under a fully
folded chain, then AC14's route is an `/execute` eval with that state file as
its `files:` fixture.

### F7 — R10's second half has no criterion, and it is the judgment-dependent half

R10 has two behaviours: a citation by path downgrades to `keep` (mechanical,
greppable), and "a weaker citation match SHALL be surfaced to the judging
agent rather than acted on mechanically" (judgment). AC9 covers only the first.
The second is where the interesting failures live — what counts as a weaker
match, whether surfacing it actually changes the verdict — and it is unverified
and unadmitted.

**To become verifiable:** add a criterion that a weaker match (title mention
without path, say) is surfaced and does not by itself change the verdict, and
mark it judgment-dependent.

### F8 — AC12 mixes a mechanical half with a prose half

"A survivor's `## Status` section names what it absorbed and which section
carries it." The frontmatter field from R15 is mechanically checkable. A
free-prose line naming a section is not: R15 asks for "one human-readable
line", so no format is pinned and a validator cannot assert it names the right
section without reading it.

**To become verifiable:** split into a mechanical criterion (the frontmatter
field is present and holds the absorbed path) and a judgment-dependent one
(the Status line names the carrying section), or pin the line's shape the way
`shirabe transition`'s `superseded_by:` splice already does — the PRD's own
Decisions section cites that precedent but does not adopt its format
discipline.

### F9 — AC7 has no instrument, and covers 150 of the 516 documents R21 is about

AC7: "`shirabe validate` passes every document in `docs/` that declares no
absorption, with no change to those documents."

No instrument runs this. `validate-docs.yml` computes its file set with `git
diff` and only sees changed docs. `fc07_corpus.rs` walks `docs/plans` and
`docs/roadmaps` and asserts notice-level codes only. Nothing walks the 150
`.md` files under `docs/`.

The scope is also short of what R21 is about. The regression surface behind
R21 is 516 chain documents (352 DESIGN, 103 PRD, 61 BRIEF —
`wip/explore_scope-artifact-persistence_findings.md:242`), which live across
the workspace's repos. This repo's `docs/` holds 150. The other ~366 are
reachable only through `parity-check.yml`, which downstream repos must opt into
and which shirabe **does not self-call** (no `uses: ./.github/workflows/
parity-check.yml` anywhere in `.github/`).

There is a second-order regression AC7 will not catch either:
`parity-check.yml` compares against a Go binary frozen at SHA `20fb8ed`. Any
new check code emitted on an existing document diverges from that baseline by
construction. R5's check must be silent on non-absorbing documents for that to
hold — which is exactly R21's intent, but no criterion asserts it against the
frozen baseline.

**To become verifiable:** AC7 needs a new corpus-wide test in the shape of
`fc07_corpus.rs` — walk all of `docs/`, run `shirabe validate`, assert exit 0
and that no new check code appears — plus `git diff --exit-code docs/` in the
same job for the "no change to those documents" clause. And a criterion stating
that the new checks emit nothing on the frozen `parity-check.yml` corpus, so
downstream callers pinning a shirabe tag do not break.

### F10 — AC15 is the one criterion with a real CI-gated route, and the bug it targets is already visible

Credit where due: `run-cascade_test.sh` runs on every PR through
`check-execute-scripts.yml`, has `write_design`/`write_prd`/`write_brief`/
`write_plan` fixture helpers and `assert_json`, and is the exact home for
AC15. A `scenario_plan_roadmap_no_design` that builds a PLAN→ROADMAP chain with
no DESIGN and asserts the roadmap's `**Downstream:**` line carries no dangling
reference is a two-hour test with a real gate behind it.

It will fail against current code. `skills/execute/scripts/run-cascade.sh:439-457`
sets `design_ref=""` when `CASCADE_DESIGN_PATH` is unset and the awk branch
then falls through to bare `print` — the pre-existing `**Downstream:**` line is
left exactly as it was. If it pointed at a DESIGN the fold deleted, the
dangling reference survives.

**To become verifiable:** AC15 should name the scenario and the line, so the
implementer does not have to rediscover the failure.

### F11 — AC16 screens for the wrong string and leaves the eval that encodes the deleted mechanism in place

AC16: "No eval in the suite asserts that hops above BRIEF-to-PRD are
unabsorbable, or that a run always leaves a durable artifact."

That catches eval 20 `consolidation-keep-at-unmapped-hop` and eval 18
`durable-artifact-floor-is-structural`. It does **not** catch eval 19
`consolidation-absorb-brief-into-prd`, whose expected output reads "Stage 1
finds the mapping total (Problem Statement to Problem Statement, User Outcome
to Goals, User Journeys to User Stories, Scope Boundary to Requirements and Out
of Scope), so absorb is available," with the expectation "Plan finds the
brief->prd mapping total and treats absorb as available at that hop." That is
the type-schema stage 1 R1 abolishes. Eval 19 asserts absorbability, not
unabsorbability, so AC16 passes it — while it encodes the exact mechanism the
PRD deletes.

Eval 20's fourth expectation ("Plan derives absorbability from the per-type
required-section contracts rather than a hard-coded list of hops") contradicts
R1 head-on and is caught, so the screen is half-working.

Verification is also manual: deciding whether a prose expectation "asserts
unabsorbability" is an agent reading 26 scenarios.

**To become verifiable:** name the scenarios. "Evals 18, 19 and 20 in
`skills/scope/evals/evals.json` are deleted or rewritten so that none
references a type-level mapping check." Then it is a diff.

### F12 — AC17 asserts a property of a commit, and its second clause duplicates an existing gate

"`cargo test` passes and the existing golden fixtures are updated in the same
change as any format-contract edit." The first clause is a real gate
(`build-and-test.yml` runs `cargo test --workspace`). The second describes how
a commit was assembled, not a state of the tree, and it is vacuous when no
fixture needed updating. It is also redundant: `parity.rs` byte-compares
`stdout`/`stderr`/`exit` per corpus file, so a format-contract edit that
changes output without updating `expected/` already fails `cargo test`.

**To become verifiable:** drop the second clause or restate it as the gate:
"the byte-exact golden parity tests in `crates/shirabe/tests/parity.rs` pass
across all 29 corpus files."

### F13 — Nine of twenty-two requirements have no acceptance criterion, and one of them is the failure path the design turns on

R4, R7, R8, R12, R13, R17, R19, R20, R22 carry no criterion.

Some of those are defensible. R19 and R20 are invariants about what was *not*
built, and a negative is awkward to assert. R17's unmeasurability is honestly
admitted in Known Limitations — though the Decisions section says the
instruction is "bounded to two diff-checkable edits", which means the landing
of those two edits *is* mechanically checkable and deserves a criterion even if
their effect is not.

**R12 is not defensible.** It is the reverted absorb — the brief's named
failure path, and the hardest one in the feature. R12 requires post-absorb
re-validation covering "the survivor and every document that referenced the
absorbed artifact," with a failure reverting the absorb. Reverting means
restoring a deleted file, un-splicing the survivor's `upstream:`, removing the
absorbed-artifact frontmatter field, removing the `## Status` line, and
removing the contribution section — a five-part multi-file rollback with no
criterion, no named record, and no route.

R8 (contribution authored before the carry table) is checkable by inspection of
the procedure text and has no criterion. R13 (the closed write-target set names
every path an absorb writes or deletes) reads mechanical but the write-target
set is prose in `skills/scope/SKILL.md:714-726` referencing
`references/parent-skill-security.md`; there is no machine-readable
enumeration to diff, so verifying "every path" is an agent cross-reading the
absorb procedure. R4 — the two-sided adequacy test, the qualitative heart of
the whole mechanism — has no criterion at all; Known Limitations admits it is
prose an agent applies, but the PRD does not even assert that the two failure
modes are *stated* in the format contract, which is greppable.

**To become verifiable:**
- R12: add "an absorb whose post-absorb re-validation fails restores the
  absorbed document, reverts the survivor's frontmatter, `upstream:` splice,
  `## Status` line and contribution section, and records the revert."
- R4: add "the contribution-section contract in the format reference states
  both the too-long and the too-thin failure" — mechanical, and it separates
  the checkable claim from the ungradeable one.
- R17: add "the rationale-in-code instruction appears in the blocking
  reviewer's instructions" — the two edits are diff-checkable per the PRD's own
  Decisions section.
- R13: add "each path the absorb procedure writes or deletes appears in the
  write-target set," verified by inspection, and say it is inspection.
- R22: enumerate the added decision points and assert `keep` at each — see F14.

### F14 — R22 is the document's summary invariant and only two of its five decision points are covered

R22: "The absorb procedure SHALL fail toward `keep` at every added decision
point." The added decision points are at least five: the replaced stage 1
(R1), the carry check (R9), the citation check (R10), post-absorb
re-validation (R12), and record production (R14, whose "absence SHALL prevent
the fold"). AC8 covers the carry check, AC9 covers the citation check. Stage 1,
revalidation and record production are uncovered.

Against the brief's four named failure paths: failed carry check — AC8,
weakly. Refused deletion — AC9, path half only. Reverted absorb — **nothing**.
Validator failure on a document declaring an absorption without the implied
section — AC6, and it is the soundest criterion in the document.

**To become verifiable:** one criterion per decision point, each asserting the
verdict lands on `keep` and nothing is deleted.

## What the PRD gets right

Worth recording, because the FAIL is about specific gaps rather than a
posture problem.

- Known Limitations 1, 2 and 5 are honest in a way most PRDs are not. Naming
  the omission gaming vector, saying the worth judgment is ungradeable *and*
  why (the comparison object is destroyed by the operation), and accepting an
  instruction plus a blocking reviewer as the ceiling for a qualitative
  property — all three are correct and none is hedged.
- AC6, AC13 and AC10 are model criteria: binary, mechanically checkable,
  and each maps to a fixture that slots into the existing `synthetic/` corpus.
- AC15 targets a real bug in committed code and has a CI-gated instrument.
- R21's framing — the contribution requirement applies only to documents
  declaring an absorption — is the right shape for a regression-free rollout.

The gap is that the honesty stops at the two limitations the PRD names and does
not extend to the fold/keep discrimination itself, which is graded by an LLM on
a weekly cron against stated intent, and reads in AC1-AC3 as though it were a
deterministic outcome assertion.

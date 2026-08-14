# Testability Verdict — PRD-upstream-link-legality

**Verdict:** FAIL

The document is unusually disciplined about verification — R20's change list is
correct against the corpus, R21's command is correct, and most enforcement
criteria are genuinely binary. It fails on three counts: R19 is not achievable
as written (the skill eval suites, not the Rust tests, are what break), five
requirements have no criterion that could fail if they were violated, and two
criteria rest on judgment.

## Requirement-to-criterion map

Criteria numbered in document order, AC1 through AC13.

| Req | Criterion | Verifiable? |
|---|---|---|
| R1 (definition: two properties) | AC1, AC2 | Yes — the two halves are exercised separately |
| R2 (lifetime class declared structurally) | AC7 (implied only) | Weak — AC7 needs the declaration to exist to compile, but nothing asserts the declared classes match R2's list (VISION/STRATEGY/BRIEF/PRD/DESIGN/COMP Durable, ROADMAP/PLAN Working) |
| R3 (legal-parent set declared, may be empty) | AC2 (implied only) | Weak — same shape; the empty-set case (BRIEF, COMP) is exercised only incidentally via AC11 |
| R4 (declaration-level assertion) | AC7 | **Yes** — see below |
| R5 (the eight-row table) | AC11 (partially) | **Partial** — only the BRIEF row is exercised. VISION, STRATEGY, ROADMAP, PLAN and COMP rows have no criterion; a wrong entry for any of them passes every AC |
| R6 (error finding, names doc/value/pair/property) | AC1, AC2 | Yes |
| R7 (two codes, lifetime suppresses direction) | AC3, AC6 | **Yes** — see below |
| R8 (no index, no filesystem read, no traversal) | — | **None.** A conforming-looking implementation that stats the target or indexes `docs/visions/` passes every criterion |
| R9 (unknown prefix unchecked) | AC4 | Yes |
| R10 (per-entry judgement and reporting) | AC5 | Yes, with a wording snag (below) |
| R11 (no skill records a forbidden value) | AC8, AC9 | Partial — only `/brief` and `/scope` are exercised; `/prd`, `/design`, `/plan` are not |
| R12 (read it, omit it, say so) | AC8 | **Partial** — see below |
| R13 (`/brief` stops recording a ROADMAP) | AC8 | Yes for the frontmatter half |
| R14 (change authored in the skill's own contract) | — | **None.** No test can fail |
| R15 (self-containment discharged by existing requirements) | — | **None.** No test can fail |
| R16 (cascade still reaches the ROADMAP) | AC9, AC10 | Yes |
| R17 (chain walkers stay type-agnostic) | — | **None.** AC10 exercises a chain authored under the *new* rule; a walk that started filtering by type would pass it |
| R18 (head-of-lineage brief with no downstream) | — | **None**, and it collides with AC11 (below) |
| R19 (no existing test modified) | AC12 | Scope-ambiguous; see the R19 section |
| R20 (the eight named documents) | AC11 | Yes — verified correct against the corpus |
| R21 (`--lifecycle . --mode=draft` exits 0) | AC13 | Yes — command verified, see below |

**R21 verification.** `./target/debug/shirabe validate --lifecycle . --mode=draft`
exits **0** today with one line of output:

```
::notice file=docs/prds/PRD-koto-adoption.md::[L02] orphan PRD at status 'Accepted' (expected status 'Done', an Active ROADMAP upstream, or a tactical upstream/downstream chain link)
```

The command is correct and the pre-state R21 asserts is real. It is also nearly
vacuous as a regression guard: `--lifecycle` is traversal-only and emits no
per-file findings, so the five dangling briefs that fail per-file validation
today do not affect it, and neither will the two new checks. It proves the
lifecycle pass was not disturbed, nothing more, and the PRD should not lean on
it as evidence the corpus is healthy.

**R20 verification.** The eight edges are exactly the eight `upstream:` values
under `docs/briefs/`, and the three the PRD calls clean today
(`BRIEF-fc06-index-alias`, `BRIEF-lifecycle-draft-ready-discipline`,
`BRIEF-skill-cascade-lifecycle-check`) do exit 0 under per-file validation.
The table is accurate.

## Non-testable requirements

**R4 — testable, and the strongest criterion in the document.** A unit test
iterating `formats()` and asserting that no spec whose lifetime is `Durable`
carries a `Working` type in its legal-parent set fails the moment a maintainer
adds one. AC7 names exactly that test. No change needed.

**R7 — both halves testable.** The precedence half is a unit assertion on a doc
with one entry violating both properties (`len() == 1` and the code is the
lifetime one). The selectability half is a CLI assertion; the "rejected as
unknown before the change" clause is observably true today —
`shirabe validate --check R10 <doc>` exits 1 with
`unknown --check code "R10"; valid codes: SCHEMA, FC01-FC16, FC-CONVENTIONS, R6-R9`
— but it is a one-time pre-state observation, not something a post-change test
can assert. Note the valid-codes string in `crates/shirabe/src/main.rs:529` is
hardcoded and must be updated; no test pins it.

**R12 — half testable, half judgment.** "Omits the field" is binary (grep the
produced frontmatter). "States in its run output that the field was omitted and
why" is not: the run output is agent prose, gradeable only by an LLM-judged eval
against `skills/brief/evals/evals.json`, and "and why" has no fixed string to
match. To make it fail-able, R12 must name the announcement's required
substring (the way `/scope`'s pre-authoring upstream notice is pinned verbatim
in `skills/scope/evals/evals.json`), or say that the announcement is graded by
eval and accept that as the bar.

**R14 — no test can fail.** "Authored in that skill's own contract" is a
property of where a diff lands, not of any observable behaviour. Two ways to
make it checkable: state it as a review-time constraint rather than a
requirement (it is really a design constraint), or restate it as an assertion
about files — the change touches `skills/brief/` and `skills/scope/` only in
their own contract sections, and `/scope` continues to pass `--upstream` (the
flag `/brief` owns) rather than post-editing the brief. The existing scope eval
`upstream-path-invocation-preserves-child-isolation` is the closest thing to a
test of this and it currently asserts the *old* behaviour.

**R15 — no test can fail.** It is a negative ("no new section, field, or check
is added for it"). It becomes checkable if stated as: `is_known_check_code`
gains exactly the two new codes, and no `FormatSpec.required_sections` list
changes. Both are one-line assertions.

**R17 — no test can fail as written.** AC10 runs the cascade against a chain
authored under the new rule; a walk that began filtering by artifact type would
still pass it, because the new-rule chain is the one it would keep following.
The requirement is about *old* corpora. It needs a criterion of its own: a
fixture chain in the old shape (BRIEF naming a ROADMAP) still reaches the
roadmap through `finalize::walk_chain_mode` and `lifecycle::extract_upstreams`.
The only such fixture in the repo today is
`skills/execute/evals/fixtures/briefs/BRIEF-cascade-test-full.md`, which R13
changes — so the evidence for R17 is precisely what R13 removes unless a
frozen old-shape fixture is added.

**R18 — no criterion, and it contradicts AC11.** R18 asks the change to "either
preserve its current validation result or record the new one as a deliberate
change under R20". R20's table names no such document and AC11 asserts "no
document outside that list changes its findings", so the only outcome
consistent with the rest of the PRD is "preserved" — which R18 should simply
say. R18 is also narrower than the rule it describes: the orphan exemption at
`crates/shirabe-validate/src/lifecycle.rs:1275` fires for *any* format with an
Active ROADMAP upstream, and under R5 no durable type may name a ROADMAP, so
the exemption goes dead for PRD and DESIGN too, not just BRIEF. The existing
test `orphan_prd_with_active_roadmap_upstream_passes`
(`lifecycle.rs:2170`) keeps passing, because it builds the lifecycle index
directly and never reaches the per-file checks.

**Criteria that require judgment.** AC8's "still uses the roadmap's feature
entry to ground the framing conversation" and AC10's "under the same conditions
as before" are both graded, not measured. AC10 is rescuable by pinning "before"
to the existing cascade eval expectations in `skills/execute/evals/evals.json`;
AC8's grounding clause is inherently an eval judgement and should say so.

**AC5 wording snag.** "reported independently, with its own line number
reference to the field" reads as if each entry gets its own line number. The
parser records one line for the whole field, and `check_upstream_resolves`
deliberately puts every per-entry finding at that one line
(`crates/shirabe-validate/src/checks.rs:791`, and the doc comment above it says
so). R10 gets this right ("matching the per-entry reporting the resolution
check already does"); AC5 should mirror R10's wording so nobody implements
per-item line tracking that the parser cannot supply.

**Criteria duplicating requirements.** None. Every criterion states an
observation rather than restating a rule. AC11 and AC13 are the two that come
closest to being restatements of R20 and R21, but both are literally runnable,
so they earn their place.

## R19 feasibility (what a new FormatSpec field breaks)

**A new field on `FormatSpec` breaks no Rust test.** I checked every
construction site and every assertion about the format table:

- Nothing outside `crates/shirabe-validate/src/formats.rs` constructs a
  `FormatSpec` literally. The three test helpers that look like they might —
  `spec_for` at `checks.rs:3378` and `validate.rs:276`, `design_spec` at
  `checks.rs:3385`, `plan_spec` at `checks.rs:6590` — all select from
  `formats()`. Adding fields is a one-file change.
- `detect_format_returns_eight_formats` (`formats.rs:297`) asserts
  `formats().len() == 8`; new fields do not add a format.
- `FormatSpec` derives `Debug, Clone, PartialEq, Eq`; a lifetime enum and a
  `Vec<String>`/`Vec<&'static str>` parent set derive all four.
- `is_known_check_code_covers_per_file_codes_only` (`validate.rs:493`) has a
  negative list containing `"R5"`, `"FC1"`, `"FC99"`, `"L01"`, `"L05"`, `"IO"`,
  `"fc01"`, `""`. The positive list is not exhaustiveness-checked, so two new
  codes pass — **provided they are not named `R5` or `FC99`**. `R10`/`R11` or
  `FC17`/`FC18` are safe. This is the one naming constraint the PRD does not
  state.
- Golden parity is the closest call and it survives, by luck of ordering.
  `crates/shirabe/tests/fixtures/golden/corpus/real/PRD-roadmap-skill.md`
  carries `upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md` — a
  Durable-names-Working edge, exactly what the lifetime check flags. Its frozen
  expected stdout is a single SCHEMA notice, because the doc has no `schema:`
  field and `validate_file` returns early at the schema gate before any
  upstream check runs. Byte parity holds **only if the new checks are placed
  after the schema gate**, alongside `check_upstream_resolves`. Placing them
  earlier, or running them in a separate pass over all docs, changes a frozen
  golden file and breaks R19. The PRD should state this placement constraint.
- `fc07_corpus.rs` validates only `docs/plans/` and `docs/roadmaps/`. There is
  one plan (`PLAN-work-on-friction-fixes.md`, no `upstream:`) and no roadmaps,
  so its exit-0 assertion is unaffected. No test validates `docs/briefs/`,
  which is why the three clean-to-violation briefs break nothing.

**R19 is nonetheless unachievable as written, because the tests that break are
the skill evals.** Three eval suites encode the exact behaviour R11/R13 forbid:

- `skills/brief/evals/evals.json`, scenario `upstream-roadmap-grounding`:
  expected output "Declares the ROADMAP path as the BRIEF's frontmatter
  `upstream`", with a matching criterion.
- `skills/brief/evals/evals.json`, scenario `upstream-flag`: "Phase 2 writes
  `upstream: docs/roadmaps/ROADMAP-editor.md` into
  `docs/briefs/BRIEF-inline-diff.md`", with a matching criterion.
- `skills/scope/evals/evals.json`, scenario `upstream-flag-consumed`: "the
  produced `docs/briefs/BRIEF-inline-diff.md` carries
  `upstream: docs/roadmaps/ROADMAP-editor.md` in its frontmatter", plus the
  criterion asserting it.
- `skills/execute/evals/evals.json`, the full-chain cascade scenario: "The
  chain is PLAN -> DESIGN -> PRD -> BRIEF -> ROADMAP" — the exact route R13
  removes and R16 replaces.
- The fixtures behind that scenario are illegal edges under R5:
  `skills/execute/evals/fixtures/briefs/BRIEF-cascade-test-full.md` names a
  ROADMAP (BRIEF's parent set is empty; ROADMAP is Working), and
  `skills/execute/evals/fixtures/designs/DESIGN-cascade-test-short.md` names a
  ROADMAP directly (DESIGN's parents are PRD and BRIEF). Neither appears in
  R20's table.

AC12 scopes the promise to `cargo test --workspace`, which is achievable. R19
says "no existing test is modified" without qualification, which is not: AC9 and
AC10 cannot be demonstrated without editing the cascade fixtures and the scope
eval, and leaving the brief evals asserting the forbidden behaviour would ship a
skill whose own eval suite contradicts its contract.

## Required changes

1. **Scope R19 to the Rust test suite** and add an explicit clause covering the
   eval suites: name `skills/brief/evals/evals.json`
   (`upstream-roadmap-grounding`, `upstream-flag`),
   `skills/scope/evals/evals.json` (`upstream-flag-consumed`), and
   `skills/execute/evals/evals.json` plus its `fixtures/briefs/` and
   `fixtures/designs/` cascade chain as expectations the change intentionally
   updates. Say for each whether it is rewritten to the new shape or frozen as
   an old-shape regression fixture.
2. **Extend R20 (or add a sibling requirement) to the eval fixture corpus.**
   `BRIEF-cascade-test-full.md` and `DESIGN-cascade-test-short.md` both become
   illegal edges; AC11's "no document outside that list changes its findings"
   is false as written.
3. **Add the check-placement constraint to R8 or R6**: the two checks run
   inside `validate_file` after the schema gate, alongside
   `check_upstream_resolves`. This is what preserves golden parity on
   `real/PRD-roadmap-skill.md`, and it is currently accidental.
4. **State that the new codes may not be `R5` or `FC99`** (the negative list in
   `is_known_check_code_covers_per_file_codes_only`), and note that the
   hardcoded valid-codes string at `crates/shirabe/src/main.rs:529` changes.
5. **Give R8, R14, R15, R17 and R18 criteria, or demote them.** Concretely:
   R8 — a test asserting the check performs no filesystem access on the target
   (or, at minimum, that `docs/visions/` is not read); R14 — restate as a
   file-scope assertion about which contracts the diff touches; R15 — assert
   exactly two new codes and no changed `required_sections`; R17 — a frozen
   old-shape chain fixture that still cascades; R18 — resolve to "preserved"
   and add it to AC11's untouched set.
6. **Cover R5's untested rows.** A table-driven test asserting the eight
   declared parent sets verbatim would make a typo in the VISION, STRATEGY,
   ROADMAP, PLAN or COMP row fail, which nothing does today.
7. **Fix AC5's wording** to match R10 (every per-entry finding sits at the
   field's line; the parser records no per-item lines), and **mark AC8's
   grounding clause and AC10's "same conditions as before" as eval-graded**,
   pinning AC10's baseline to the existing cascade eval expectations.

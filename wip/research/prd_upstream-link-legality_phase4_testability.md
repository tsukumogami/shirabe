# Testability Verdict — PRD-upstream-link-legality

**Verdict:** FAIL (narrowly — three coverage gaps, each fixable with one
criterion; nothing structural remains)

Six of my seven items are properly discharged, and two of the fixes are better
than what I asked for. R21's golden-parity clause **is** sufficient to force the
placement constraint I identified: `parity.rs::real_prd_roadmap_skill` compares
bytes, and `real/PRD-roadmap-skill.md` carries a Durable-names-Working edge, so
running the new checks before the schema gate turns that test red. Stating it as
an observable outcome rather than a placement instruction is the right call and
costs nothing. AC6's rewrite ("the message listing valid codes names them") is
also an improvement — it forces the hardcoded string at
`crates/shirabe/src/main.rs:529` to be updated, which the earlier wording did
not.

What remains: one requirement no test can fail (R8), one stated deliverable with
no criterion (R5.2's reference updates), and one criterion whose subject no
requirement creates (the new-shape cascade fixture).

## Requirement-to-criterion map

Criteria numbered in document order, AC1 through AC19.

| Req | Criterion | Verifiable? |
|---|---|---|
| R1 | AC1, AC2 | Yes — the two properties exercised separately |
| R2 | AC8 | **Yes** — verbatim assertion of all eight lifetime classes |
| R3 | AC8 | Yes — including the empty-set rows (BRIEF, COMP) |
| R4 | AC7 | Yes |
| R5 | AC8 | **Yes** — all eight rows now covered, not just BRIEF |
| R5.1 | — | Rationale prose, no criterion needed |
| R5.2 | — | **None.** The reference updates are a deliverable with no criterion |
| R5.3 | AC8 | Yes (PLAN's set asserted verbatim) |
| R6 | AC1, AC2 | Yes |
| R7 | AC3, AC6 | Yes — both precedence and selectability |
| R8 | — | **None**, and unfalsifiable in this corpus |
| R9 | AC4 | Yes |
| R10 | AC5 | Yes — wording now matches what the parser supplies |
| R11 | AC10, AC11, AC12, AC13 | Yes for the four skills that change |
| R12 | AC10 | Yes, and correctly declared eval-graded |
| R13 | AC10 | Yes |
| R14 | AC11, AC12 | Yes |
| R15 | AC13 | Yes |
| R16 | AC10 + AC11 together | Thin but real: standalone `/brief` and `/brief` under `/scope` both produce no field, so a parent that rewrote the child's value would fail one of the two |
| R16.1 | — | None. Low stakes: it is a carve-out saying nothing changes |
| R17 | AC9 | Yes |
| R18 | AC15 | Yes — backed by the frozen fixture |
| R19 | AC14 | Yes, with the fixture caveat below |
| R20 | AC16, AC17 | Yes (per-file half by AC16, lifecycle half by AC17) |
| R21 | AC18 | Yes |
| R22 | AC19 | Yes |
| R23 | AC15 | Yes |
| R24 | AC16 | Yes — table re-verified correct against the corpus |
| R25 | AC17 | Yes — command re-run, exits 0 |

No criterion duplicates a requirement; every one states something runnable or
gradeable.

**R25 re-verified.** `./target/debug/shirabe validate --lifecycle . --mode=draft`
exits 0, emitting one notice (`[L02]` on `docs/prds/PRD-koto-adoption.md`). The
Known Limitations paragraph now says plainly that this is a weak guard, which is
the honest framing.

**R24 re-verified.** The eight rows are exactly the eight `upstream:` values
under `docs/briefs/`; `BRIEF-fc06-index-alias.md` exits 0 today, confirming the
"clean" column.

**R15 and R5.2 re-verified as factually anchored.**
`skills/explore/references/phases/phase-5-produce-roadmap.md:49` does pass a
VISION as `--upstream` to `/roadmap`. `references/pipeline-model.md` does state
the three shapes R5.2 names (line 113 "Brief (upstream: Roadmap, per feature)",
line 131 the PRD case, line 138 "`/brief` crosses that boundary by taking a
Roadmap as its upstream"), and `skills/prd/references/prd-format.md:27-29`
repeats the PRD case.

## Non-testable requirements

**R8 — no criterion, and no corpus to exercise it in.** `docs/` contains no
`visions/` or `strategies/` directory, so "no VISION or STRATEGY is drawn into
the orphan rule" cannot be observed here at all. AC17 cannot catch a violation
either: a wrongly-indexed VISION would surface as an L02 *notice* under draft
posture, and notices do not affect the exit code, so AC17 passes while R8 is
broken. This is not hypothetical — an implementation that resolves the target
path and reads its frontmatter for the type, instead of reading the basename,
violates R8, quietly changes the cross-repo behaviour R9 specifies, and passes
all nineteen criteria.

On the question of whether the two reviewers' advice conflicts: **it does not.**
The other reviewer was right to cut "no filesystem read, no traversal" — that
names a mechanism, which is the design's call. What is left ("decided from the
naming document's format and the target's basename alone", plus the orphan-rule
consequence) is a properly observable requirement. The gap is that no criterion
observes it. Restoring the cut clause would not fix that; adding a criterion
would.

**R5.2 — a deliverable with no criterion.** "The references that currently
document the other three shapes are updated to match" is the load-bearing half
of this PRD for anyone authoring by hand: if `pipeline-model.md` still tells a
brief author to name a roadmap while the validator rejects it, the system
contradicts itself in exactly the way the Problem Statement complains about.
Nothing in the criteria checks it, and it is trivially checkable by grep.

**R16.1 — uncovered, low stakes.** It asserts that `/scope`'s absorb needs no
new guard because an absorbed brief now has no upstream to carry. That is a
claim about the absorb path, and the `/scope` eval covering absorb
(`baseline`-family scenario asserting "re-points the PRD's upstream to the
BRIEF's own upstream, or removes the field when the BRIEF had none") already
exercises the removal branch — so the claim is true, but nothing pins it. Worth
one clause in AC11 rather than its own criterion.

**Judgment-laden criteria: acceptable now.** AC10 states outright which parts
are eval-graded, and AC14 pins its baseline to the existing cascade eval's
expectations. Both were my objections last round and both are answered. AC13
("`/explore` passes no `--upstream` value to `/roadmap` that is not a STRATEGY")
is a statement about skill prose rather than a runnable check, but it is
greppable against `phase-5-produce-roadmap.md` and gradeable by the existing
handoff eval, which is the right bar for a skill contract.

## R21 feasibility (re-verified against the revised text)

**The Rust half is achievable and my earlier analysis stands unchanged.**
Nothing outside `crates/shirabe-validate/src/formats.rs` constructs a
`FormatSpec` literally — `spec_for` (`checks.rs:3378`, `validate.rs:276`),
`design_spec` (`checks.rs:3385`) and `plan_spec` (`checks.rs:6590`) all select
from `formats()`, so two new fields are a one-file change.
`detect_format_returns_eight_formats` counts formats, not fields.
`fc07_corpus.rs` validates only `docs/plans/` and `docs/roadmaps/` (one plan
with no `upstream:`, no roadmaps), so it is untouched. No test validates
`docs/briefs/`, which is why R24's three clean-to-violation briefs break
nothing. Golden parity holds for the reason given above.

**The eval half is now correctly scoped.** R21 confines the promise to
`cargo test --workspace` plus golden bytes; R22 names the four eval expectations
that change with a disposition each; R23 freezes the two illegal fixtures as
R18's evidence and exempts them. I re-checked whether R15 forces a fifth eval
change: `skills/explore/evals/evals.json` scenario
`roadmap-handoff-upstream-propagation` is named as though it asserts the VISION
propagation, but its four expectations only cover routing, the scope artifact,
the handoff, and the strategic classification — none asserts the `--upstream`
value. So R22's list of four is complete. The scenario's *name* becomes a
misnomer after R15; not worth a requirement, worth a sentence to whoever does
the work.

**One remaining naming constraint the PRD still does not state.**
`is_known_check_code_covers_per_file_codes_only` (`validate.rs:493`) carries a
negative list asserting `"R5"`, `"FC1"`, `"FC99"`, `"L01"`, `"L05"`, `"IO"`,
`"fc01"` and `""` are *not* known codes. If the implementer names either new
code `R5` or `FC99`, that test fails and R21 is violated. `R10`/`R11` or
`FC17`/`FC18` are safe. AC9 constrains the count but not the names.

**The new-shape cascade fixture is required by AC14 but created by no
requirement.** R22 row 4 rewrites the full-chain `/execute` scenario to the new
route; R23 freezes `BRIEF-cascade-test-full.md` — the fixture that scenario runs
against — in the old shape. Both can hold only if a second, new-shape fixture
chain is added, and no requirement says so. AC14 names "a chain authored under
the new rule" without naming a fixture, while AC15 names "the frozen old-shape
fixture chain". AC19's "no eval outside that list changes" leaves it ambiguous
whether adding fixtures is in scope. This is under-specification rather than a
flat contradiction, but an implementer will hit it on day one.

## Required changes

1. **Give R8 a criterion.** Since `docs/` has no strategic directories, it has
   to be a synthetic-tree or unit-level assertion — for example, a doc whose
   `upstream:` names a `VISION-`/`STRATEGY-` basename is judged without that
   file existing on disk, and a `--lifecycle` run over a tree containing a
   VISION produces the same finding set before and after. Alternatively,
   strengthen AC17 from "exits 0" to "emits the same finding set", which closes
   the notice-level hole in the same stroke.
2. **Give R5.2 a criterion.** Something greppable: no reference under
   `references/` or `skills/*/references/` documents a ROADMAP as a legal
   upstream for a BRIEF, PRD or DESIGN after the change.
3. **Name the new-shape cascade fixture as a deliverable** in R22 or R23, and
   say explicitly that adding fixtures is not an "eval outside the list" under
   AC19.
4. *(Minor, carried over.)* State that the two new codes may not be `R5` or
   `FC99`, per the negative list in
   `is_known_check_code_covers_per_file_codes_only`.
5. *(Minor.)* Fold R16.1 into AC11 — the `/scope` run leaves the surviving PRD
   correctly headed after an absorb.

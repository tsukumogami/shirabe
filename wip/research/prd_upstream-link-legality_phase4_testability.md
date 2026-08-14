# Testability Verdict — PRD-upstream-link-legality

**Verdict:** PASS

All five second-round items are applied, and I verified each against the
codebase rather than against the description of the change. Every requirement
now maps to at least one criterion, every criterion is falsifiable, and the two
criteria I had flagged as judgment-laden last round (the `/brief` announcement,
the cascade baseline) are explicitly declared eval-graded and baseline-pinned.
Two non-blocking notes follow the map.

## Requirement-to-criterion map

Criteria numbered in document order, AC1 through AC21.

| Req | Criterion | Verifiable? |
|---|---|---|
| R1 | AC1, AC2 | Yes — the two properties exercised separately |
| R2 | AC8 | Yes — all eight lifetime classes asserted verbatim |
| R3 | AC8 | Yes — including the empty-set rows (BRIEF, COMP) |
| R4 | AC7 | Yes |
| R5 | AC8 | Yes — all eight parent sets, fails on one changed entry |
| R5.1 | — | Rationale prose; no criterion needed |
| R5.2 | **AC13** | Yes — see the scope note below |
| R5.3 | AC8 | Yes |
| R6 | AC1, AC2 | Yes |
| R7 | AC3, AC6 | Yes — precedence and selectability both |
| R8 | **AC12** | Yes — see the falsifiability review |
| R9 | AC4 | Yes |
| R10 | AC5 | Yes |
| R11 | AC10, AC11, AC14, AC15 | Yes, for each of the four skills that change |
| R12 | AC10 | Yes, correctly declared eval-graded |
| R13 | AC10 | Yes |
| R14 | AC11, AC14, AC16 | Yes |
| R15 | AC15 | Yes |
| R16 | AC10 + AC11 together | Thin but real: standalone `/brief` and `/brief` under `/scope` must both produce no field, so a parent rewriting a child's value fails one of them |
| R16.1 | **AC11** (folded in) | Yes |
| R17 | AC9 | Yes |
| R18 | AC17 | Yes — backed by R23's frozen fixture |
| R19 | AC16 | Yes — baseline pinned to the existing eval |
| R20 | AC18, AC19 | Yes (per-file half by AC18, lifecycle half by AC19) |
| R21 | AC20 | Yes |
| R22 | AC21 | Yes — five rows, all five verified below |
| R23 | AC21 | Yes — new-shape fixture named as a deliverable |
| R24 | AC18 | Yes — table re-verified correct |
| R25 | AC19 | Yes — strengthened past exit code to the finding set |

Nothing is uncovered. No criterion restates a requirement instead of verifying
it.

## Falsifiability of the five new or changed criteria

**AC12 (R8) — falsifiable, in its second half decisively.** I checked the
lifecycle indexer: `crates/shirabe-validate/src/lifecycle.rs:329` hardcodes six
directories (`docs/briefs`, `docs/prds`, `docs/designs`,
`docs/designs/current`, `docs/plans`, `docs/roadmaps`) and neither
`docs/visions` nor `docs/strategies` is among them. So "a `--lifecycle` run over
a tree containing a VISION emits the same finding set before and after" can
genuinely fail: an implementation that drew the strategic directories into the
index would surface new orphan and location findings on that tree. The first
half ("judged without that file being read from disk") is a mechanism claim
rather than an observation, but it has an obvious operational form the tester
will reach for — point the `upstream:` at a `VISION-` basename that does not
exist on disk and assert the direction finding still fires alongside the
existing R6 resolution error. Worth rewording to that, but it does not block:
the criterion's second half already carries R8 on its own.

**AC19 (R25) — the strengthening closes the hole I named.** Under draft posture
a wrongly-indexed VISION surfaces as a notice, and notices do not affect the
exit code, so "exits 0" could never have caught it. "Emits the same finding set,
notices included" can. I re-ran the command: exit 0, one notice
(`[L02]` on `docs/prds/PRD-koto-adoption.md`), which is the baseline the
criterion freezes.

**AC13 (R5.2) — falsifiable by grep-and-read, which is the right bar.** I
confirmed the requirement is factually anchored: `references/pipeline-model.md`
line 113 ("Brief (upstream: Roadmap, per feature)"), line 131 (the PRD case) and
line 138 ("`/brief` crosses that boundary by taking a Roadmap as its upstream"),
plus `skills/prd/references/prd-format.md:27-29`. All four sit inside the
criterion's glob. So does
`skills/scope/references/phases/phase-1-discovery.md`, which R22's new fifth row
also covers.

**AC21 / R23 — the fixture ambiguity is resolved.** R23 now names the new-shape
fixture chain as a deliverable and says outright that adding fixtures is not a
change to an eval outside R22's list, and AC21 repeats it. AC16 and AC17 now
have distinct, named subjects: the new-shape chain and the frozen old-shape one.

**R21's code-naming clause is correct.**
`is_known_check_code_covers_per_file_codes_only`
(`crates/shirabe-validate/src/validate.rs:493`) asserts `"R5"`, `"FC1"`,
`"FC99"`, `"L01"`, `"L05"`, `"IO"`, `"fc01"` and `""` are unrecognized. `R5` and
`FC99` are the two a reasonable implementer might actually pick, and the general
clause covers the rest.

**AC11's absorb clause (R16.1) is checkable against existing behaviour.** The
`/scope` absorb already carries the rule the clause depends on — its eval
asserts the surviving PRD's upstream is re-pointed to the brief's own upstream
"or removes the field when the BRIEF had none" — so under R13 the removal branch
is simply the one that now fires. The criterion pins that outcome rather than
assuming it.

**R22's fifth row is accurate.** The sentence "this chain will attach the BRIEF
to it" appears exactly twice in
`skills/scope/references/phases/phase-1-discovery.md`, matching the row's
"committed twice" claim, and the `pre-authoring-notice-cold-start` scenario
asserts it verbatim.

## R21 feasibility — unchanged and still achievable

My analysis stands: nothing outside `crates/shirabe-validate/src/formats.rs`
constructs a `FormatSpec` literally (`spec_for` at `checks.rs:3378` and
`validate.rs:276`, `design_spec` at `checks.rs:3385`, `plan_spec` at
`checks.rs:6590` all select from `formats()`);
`detect_format_returns_eight_formats` counts formats, not fields;
`fc07_corpus.rs` covers only `docs/plans` and `docs/roadmaps`, neither affected;
no test validates `docs/briefs/`; and golden parity is preserved because
`real/PRD-roadmap-skill.md` — the one fixture carrying a Durable-names-Working
edge — fails the schema gate before any upstream check runs. AC20's byte-parity
clause is what enforces that ordering, which is why stating it as an outcome
rather than as a placement instruction was the right call.

## Notes for whoever implements this (neither blocks approval)

1. **AC13's sweep is narrower than the problem it describes.**
   `skills/brief/SKILL.md` states the forbidden shape twice outside any
   `references/` directory — Input Mode 3 says a ROADMAP path is "the upstream
   for the new BRIEF", and the `--upstream` paragraph says the produced brief
   "record[s] that ROADMAP as its upstream". Both must change under R13, and
   they will be caught anyway: R22's two rewritten `/brief` evals grade the
   transcript, so a contract still instructing the skill to record the field
   would fail them. But the sweep as phrased would pass with that prose intact.
   Broadening the glob from `skills/*/references/` to `skills/**` costs nothing
   and makes the sweep match its own intent.
2. **AC12's first half reads as a mechanism claim.** "Judged without that file
   being read from disk" is verified in practice by pointing the entry at a
   `VISION-` basename that does not exist; saying so would spare the tester from
   reaching for syscall tracing.

# Completeness Review — PRD-work-on-retry-clearing

## Verdict: PASS

## Method

Read the PRD, the upstream BRIEF, and `skills/prd/references/prd-format.md`
(Required Sections, Content Boundaries, Quality Guidance). Verified a sample
of the PRD's checkable claims against the actual repo:
`skills/work-on/koto-templates/work-on.md`, `phase-4a-scrutiny.md`,
`phase-4b-review.md`, `phase-4c-qa.md`, `review-panel-orchestration.md`,
`skills/work-on/evals/evals.json`, and cross-referenced the precedent files
(`skills/execute/koto-templates/execute.md`,
`skills/execute/scripts/settled-branch-record_test.sh`).

## Required sections

Status, Problem Statement, Goals, User Stories, Requirements, Acceptance
Criteria, Out of Scope — all present, in canonical order, followed by the
optional Known Limitations and Decisions and Trade-offs sections. No gaps.

## BRIEF coverage (journeys and scope boundary)

All four BRIEF User Journeys are answered:
- "The scrutiny panel sends the work back" → R2, R3, AC3.
- "A blocking finding lands two phases downstream" → R2 (all three phases),
  R6 (same contract), AC3/AC4/AC5 (per-phase checks).
- "The clearing step cannot do its job" → R4, R5, AC6, AC7.
- "A maintainer edits the retry directive a year later" → R10, AC8.

All BRIEF Scope Boundary "In" items are answered: retry-clearing contract
for all three phases (R2), the three phase files' prose including reversed
causality (R7), `review-panel-orchestration.md` (R7 + AC10), the three
states in `work-on.md` (R3), the non-success failure mode on a
`2>/dev/null`-surviving stream (R5), test coverage against real koto (R9),
and updated+run evals (R12).

All BRIEF Scope Boundary "Out" items are carried into the PRD's Out of
Scope: mechanism choice, `/execute`'s settled-branch record, rest of
`/work-on`, `context_assignments`, and a general freshness primitive. No
BRIEF content fell through.

## Requirement → AC coverage

Every requirement (R1–R12) has at least one AC that would catch its
violation:
- R1 → AC1, AC2
- R2 → covered jointly by AC3 (behavior with an invalidated artifact) and
  AC8 (the test extracts and runs the actual shipped invalidation block,
  which is what produces the "invalidated" state AC3 tests against) —
  indirect but real coverage; no single AC states "the blocking_retry path
  itself performs invalidation," but the combination closes the loop.
- R3 → AC3, AC5
- R4 → AC5
- R5 → AC6, AC7
- R6 → AC3/AC4/AC5/AC9/AC10 (each enumerates all three phases, so sameness
  is exercised by repetition rather than one dedicated cross-phase AC)
- R7 → AC9, AC10
- R8 → AC4
- R9 → AC3/AC4/AC5 (explicitly "captured as test output, not asserted in
  prose")
- R10 → AC8
- R11 → AC11
- R12 → AC13

No requirement is left with zero AC coverage.

## AC → Requirement traceability

All ACs trace to a requirement except two general process/regression
gates: AC12 (`cargo test --workspace` passes, no pre-existing test
modified) and AC14 (`shirabe validate --lifecycle --mode=ready` exits 0).
Neither maps to a specific numbered requirement — they're workspace-wide
non-regression and chain-validity gates, which is a standing convention in
this repo's PRDs (see e.g. CLAUDE.md's Go/Rust testing and validation
requirements) rather than scope drift. Advisory, not a genuine orphan in
the harmful sense (no requirement is implied by these ACs that isn't
already stated elsewhere).

## Problem Statement standalone check

Reads cold without the BRIEF: names the three phases, the results
artifacts, the presence-only gate, the nonexistent `koto context remove`
subcommand and why its failure is silent, the reversed-causality claim,
the traversal argument for why all three phases are implicated, and the
cost. Passes.

## Verified claims (sample)

- `phase-4a-scrutiny.md:45` — `koto context remove <WF>
  scrutiny_results.json` is present exactly as described; koto's context
  group is `add`/`get`/`exists`/`list` (confirmed via
  `skills/execute/koto-templates/execute.md:376`, which independently
  states "There is no `context set`").
- `phase-4a-scrutiny.md:44` — "artifact may be stale — the gate will fail,
  prompting a fresh run" — confirmed backwards-causality prose matches the
  PRD's characterization exactly.
- `phase-4b-review.md` and `phase-4c-qa.md` — confirmed neither contains
  any retry/clearing-step section (only `phase-4a-scrutiny.md` has one, and
  it's broken).
- `work-on.md` — `scrutiny`, `review`, `qa_validation` states all use
  `type: context-exists` gates (`scrutiny_results`, `review_results`,
  `qa_results`) referenced by the `passed` transition's `when` clause;
  `blocking_retry` from all three routes to `implementation`, which routes
  forward to `scrutiny` for `issue_type: code` — confirms the traversal
  argument (a retry from `review` or `qa_validation` re-enters upstream
  phases).
- `skills/work-on/evals/evals.json` — eval `scrutiny-blocking-retry-entry`
  (id ~14 region) asserts "Agent checks scrutiny_results context-exists
  gate status before submitting evidence" and documents
  `context_assignments` propagating `failure_reason` as if it works —
  grounds both R12 (evals need updating) and the Known Limitations claim
  about `context_assignments` being documented as real elsewhere.
- Grep for `koto context (remove|set|delete|rm|unset|clear)` under
  `skills/` returns 3 lines today: the real instruction in
  `phase-4a-scrutiny.md:45`, plus two prose citations in
  `skills/execute/koto-templates/execute.md:376` and
  `skills/execute/scripts/settled-branch-record_test.sh:9` that describe a
  past (already-fixed) defect in `/execute`. R1's carve-out ("prose that
  quotes a nonexistent verb to describe a defect is not an instruction")
  and AC1's wording ("no line that instructs an agent to run the command")
  correctly anticipate this — the grep alone is not the criterion, judgment
  about instruction-vs-citation is required. No contradiction found, but
  worth flagging: AC1 is not purely mechanical/binary as written, since a
  human or agent must classify each grep hit.

No claim was found to contradict the repo.

## Content boundary observations (advisory)

R3 and R5 lean toward implementation-flavored language: R3 explains koto's
engine semantics ("a gate declared but not referenced by a `when` clause is
evaluated and ignored by koto"), and R5 prescribes a read-back-and-compare
technique over an emptiness test. Neither commits to a specific mechanism
(command, subcommand, gate type) — that choice is explicitly deferred to
DESIGN in Out of Scope and in the Decisions and Trade-offs section — but
both are closer to "how must this be verifiable" than plain "what." This
reads as the minimum needed to keep the requirements testable in a
template-driven system, not a chosen architecture, so it does not rise to
a blocking Content Boundaries violation. Flagged as advisory for the
altitude reviewer to weigh independently.

## Findings summary

No blocking findings. All seven required sections are present and ordered
correctly, every BRIEF journey and scope item is answered by a requirement
or an Out of Scope entry, every requirement has AC coverage, and the two
ACs that don't map to a specific requirement are standard process
boilerplate rather than scope drift. Sampled claims about the repo's
actual state (koto's subcommands, the phases' retry-loop prose, the gate
wiring, the eval assertions) all check out. Two items are called out as
advisory only: R2's coverage is compositional (AC3 + AC8) rather than a
single dedicated AC, and R3/R5 use borderline implementation-flavored
phrasing that stops short of choosing a mechanism.

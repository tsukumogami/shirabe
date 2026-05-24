# Decision 5 Report: Evals Scenarios for `skills/strategy/evals/evals.json`

## Question

PRD R13 names four minimum eval scenarios for `/strategy`: structural happy
path, missing-required-section rejection (FC04), invalid-status rejection
(FC02), and public-repo Competitive-Considerations rejection (R7-equivalent).
The PRD defers fixture content and the question of whether to add scenarios
beyond that minimum to this design.

This decision settles three things:

1. The complete list of eval scenarios (target 6–8 — the four R13 minimums
   plus design-added cases that cover lifecycle transitions, frontmatter
   shape, and Building Blocks granularity surfaces).
2. For each scenario: the input fixture sketch, the expected `shirabe
   validate` behavior (exit code, error code), and the assertion phrasing.
3. Whether evals exercise the skill, the format spec via `shirabe validate`,
   or both.

## Considered Options

### Option A: PRD R13 minimum (4 scenarios)

Ship exactly the four R13-named scenarios as skill-level evals modelled on
`skills/vision/evals/evals.json`: each scenario is a `/strategy ...` prompt
whose expected behavior is described in plain-English `expected_output` and
graded by `assertions`. Validation results are inferred from the agent's
transcript rather than from running `shirabe validate` itself.

*Pros:* matches the existing vision/prd/roadmap eval shape exactly; cheapest
to author; deterministic since the grader checks transcript claims.

*Cons:* R13's Acceptance-Criteria text explicitly says "Running `shirabe
validate` against a STRATEGY-... fails with an FC04 error" — those are CLI
behavior checks, not skill behavior checks. The PRD constraint
"eval coverage must exercise the format spec's rules, not just the skill's
happy path" cannot be met by transcript-only evals. Missing lifecycle and
Building Blocks coverage leaves the design's two most divergent surfaces
(R6.1 rubric, transition-script contract) untested.

### Option B: Design-expanded set (7 scenarios) — both skill and CLI

Ship 7 scenarios split into two grading shapes:

- **Skill-level scenarios** (modelled on existing evals): exercise the
  `/strategy` skill's phase routing, lifecycle verbs, and finalization
  prompt — graded from the transcript like all other shirabe evals.
- **Format-spec scenarios**: each provides a STRATEGY-`<name>`.md fixture in
  `files[]` and the eval's `expected_output` describes what running
  `shirabe validate <fixture>` should produce. The assertion checks that the
  transcript reports the right exit code and error code, which the
  skill-creator-driven grader can confirm because the agent runs the CLI
  during eval execution (the eval framework already supports `files[]` and
  shell invocations per the prd/roadmap precedent).

This gives both the skill happy path (familiar to existing eval graders) and
explicit format-spec coverage via the CLI (load-bearing for R13's stated
intent).

*Pros:* meets the PRD R13 minimum verbatim; adds the lifecycle and Building
Blocks design-added cases without bloat; format-spec scenarios exercise the
Go validation code paths (FC01-FC04, R7-equivalent) directly.

*Cons:* mixes two grading shapes in one evals.json. Slightly more setup
because the format-spec scenarios depend on a built `shirabe` binary being
on PATH during the eval run.

### Option C: Pure CLI-driven evals (no skill-level scenarios)

Drop the skill-level scenarios entirely and ship only fixture-and-validate
scenarios. Every eval is "given this STRATEGY file, expect exit code X with
error code Y."

*Pros:* maximum format-spec fidelity; uniform grading shape.

*Cons:* diverges from every other shirabe skill's eval pattern; loses
coverage of skill-specific behavior (handoff detection, lifecycle verbs,
Phase 4 jury structure) that exists in every other skill's evals. Reviewer
cannot compare strategy evals against vision/prd/roadmap evals on equal
footing.

## Decision Outcome

**Chosen: Option B — design-expanded set, 7 scenarios, mixed shapes.**

The seven scenarios are:

| # | Name | Shape | Input Fixture Sketch | Expected `shirabe validate` Exit | Expected Error Code(s) | Assertion Phrasing |
|---|------|-------|----------------------|----------------------------------|------------------------|--------------------|
| 1 | `structural-happy-path` | Format-spec | Complete `STRATEGY-payments-modernization.md` with all 8 required sections in order, valid frontmatter (`status: Draft`, `bet`, `scope: project`), `## Status` body matches frontmatter, no `Competitive Considerations` section. | 0 | none | "Running `shirabe validate <fixture>` exits with code 0 and emits no FC01/FC02/FC03/FC04/R7 errors." |
| 2 | `missing-required-section-fc04` | Format-spec | Same fixture as #1, but `## Coordination Dependencies` section deleted. | 1 | FC04 | "Running `shirabe validate <fixture>` exits non-zero and the output includes `[FC04] missing required section '## Coordination Dependencies'`." |
| 3 | `invalid-status-fc02` | Format-spec | Same fixture as #1, but `status: Planned` in frontmatter (`Planned` is a valid Design status but not a valid Strategy status). | 1 | FC02 | "Running `shirabe validate <fixture>` exits non-zero and the output includes `[FC02] status \"Planned\" is not valid for Strategy docs`." |
| 4 | `public-competitive-considerations-r7` | Format-spec | Complete fixture with a `## Competitive Considerations` section included. Run as `shirabe validate --visibility public <fixture>`. | 1 | R7-equivalent (Strategy custom check; same code shape as `checkVisionPublic`) | "Running `shirabe validate --visibility public <fixture>` exits non-zero and the output includes a Strategy-side R7 message naming `Competitive Considerations`." |
| 5 | `private-competitive-considerations-accepted` | Format-spec | Same fixture as #4, but invoked as `shirabe validate --visibility private <fixture>`. | 0 | none | "Running `shirabe validate --visibility private <fixture>` exits 0 — the visibility gate flips, the section is accepted." |
| 6 | `lifecycle-accepted-to-active` | Skill-level | `/strategy activate docs/strategies/STRATEGY-payments-modernization.md` against a fixture file in `Accepted` state. | n/a (script-driven) | n/a | "Transcript identifies `activate` as a lifecycle verb, plans to run `skills/strategy/scripts/transition-status.sh`, targets `Accepted → Active`, and does NOT move the file out of `docs/strategies/`." |
| 7 | `lifecycle-sunset-with-move` | Skill-level | `/strategy sunset docs/strategies/STRATEGY-old-bet.md` against a fixture file in `Active` state. | n/a | n/a | "Transcript identifies `sunset` as a lifecycle verb, runs `transition-status.sh`, targets `Active → Sunset`, and moves the file to `docs/strategies/sunset/STRATEGY-old-bet.md` via `git mv`." |

**Coverage map against PRD R13 minimum:**

- Structural happy path → scenario 1
- Missing-required-section / FC04 → scenario 2
- Invalid-status / FC02 → scenario 3
- Public-repo Competitive-Considerations → scenarios 4 + 5 (the visibility
  gate is bidirectional; testing only the "reject" half lets the
  always-reject bug pass)

**Design-added scenarios and rationale:**

- **Scenario 5 (private accepts Competitive Considerations).** R7 is a
  visibility gate, not a blanket prohibition. An implementation that
  unconditionally rejects the section would pass scenario 4. Pairing
  scenarios 4 and 5 makes the gate's bidirectional behavior load-bearing
  for the eval to PASS — and matches the precedent set for VISION's
  `checkVisionPublic` (the test suite covers both private-passes and
  public-rejects cases).
- **Scenario 6 (Accepted → Active lifecycle).** The PRD R4 lifecycle is the
  most surface-divergent piece of the strategy skill versus precedent —
  Active is operator-invoked (not auto-triggered on downstream artifact
  state). The eval has to confirm the skill handles the `activate` verb
  via `transition-status.sh` rather than running the full creation
  workflow. Roadmap's `lifecycle-activate` eval is the direct precedent.
- **Scenario 7 (Sunset with directory move).** STRATEGY's `Sunset` mirrors
  VISION's directory-as-state pattern (Decision 2 of this design). The
  eval has to confirm the `sunset` verb performs the `git mv` to
  `docs/strategies/sunset/`. Vision's `lifecycle-sunset-with-move` eval is
  the direct precedent.

**Why not a separate Building Blocks granularity eval?** R6.1 explicitly
states the granularity rubric (5-8 blocks, 1-2 downstream design fanout,
under 20% cross-product) is a jury-verdict heuristic that lives in the
format reference and is revisable. The skill's Phase 4 jury applies it;
the Go validation code does not. Trying to encode "rejected for having
12 Building Blocks" as a deterministic eval would either (a) duplicate
the rubric numerically in evals.json (creating a second source of truth)
or (b) require the eval grader to invoke an LLM-based judgment (non-
deterministic, violating the PRD's "no flaky scenarios" constraint). The
granularity rubric is tested indirectly via the structural happy-path
fixture (which has 6 Building Blocks, well inside the rubric) and via the
format reference's own example in the doc itself. A dedicated
granularity-fail eval would be flaky-by-construction and is rejected.

**Evals exercise both the skill and the format spec.** Scenarios 1-5 are
format-spec scenarios graded by running `shirabe validate` against a
fixture file. Scenarios 6-7 are skill-level scenarios graded from the
agent transcript. Both modes live in the same `evals.json` and are graded
by the same `scripts/run-evals.sh` driver, which loads `/skill-creator`
and lets the eval agent shell out to `shirabe validate` for scenarios that
include `files[]`.

## Assumptions

1. `scripts/run-evals.sh <skill>` invokes `claude -p` with `/skill-creator`
   loaded, and the resulting agent has Bash access and a built `shirabe`
   binary on PATH (or can build it via `go build ./...`). This matches the
   shirabe CLAUDE.md "Skill Evals" description.
2. The Strategy custom check (Competitive Considerations gate) emits an
   error code distinguishable from VISION's `R7` — exact code naming is
   owned by Decision 4 (custom-check function name and dispatch shape).
   This decision assumes whatever Decision 4 picks, scenarios 4-5 use that
   code symbolically.
3. Fixtures live alongside `evals.json` (e.g.,
   `skills/strategy/evals/fixtures/STRATEGY-payments-modernization.md`)
   and are referenced from each scenario's `files[]` field. The existing
   roadmap evals' `files: ["docs/roadmaps/ROADMAP-..."]` precedent
   supports relative-path fixture references.
4. `shirabe validate --visibility` already accepts `public` and `private`
   values (per R7 and the existing `checkVisionPublic` implementation).

## Rejected Alternatives

- **Option A (PRD minimum only).** Rejected because the PRD's R13 wording
  ("structural happy path," "FC04," "FC02," "R7-equivalent") describes CLI
  behavior, not skill transcript behavior, and the design constraint
  "exercise the format spec's rules, not just the skill's happy path"
  cannot be met by transcript-only evals.
- **Option C (CLI-only, drop skill-level evals).** Rejected because it
  diverges from every other shirabe skill's eval pattern, loses lifecycle
  and skill-routing coverage, and makes the strategy evals incomparable
  to vision/prd/roadmap evals during review.
- **Adding a Building Blocks granularity-rejection eval.** Rejected as
  flaky-by-construction; the rubric is a revisable heuristic per R6.1,
  not a deterministic format-spec rule.
- **Adding an FC03 (frontmatter-status / body-Status mismatch) eval.**
  Considered but rejected for scope — FC03 is exercised by the existing
  shared validate test suite (`checks_test.go`) and re-testing it per
  artifact type would bloat every skill's evals.json without adding
  format-specific coverage. The structural happy path implicitly checks
  the FC03 success case.

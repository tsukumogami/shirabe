# Phase 6 Architecture Review: DESIGN-shirabe-strategy-skill

**Verdict:** minor-issues

## Scope

This review covers the Solution Architecture and Implementation Approach
sections of DESIGN-shirabe-strategy-skill.md, as the final QA gate before
implementation. Decisions 1-5 already cleared parallel agent evaluation
(phase 2), cross-validation (phase 3), and security review (phase 5); this
review flags completeness gaps only and does not re-litigate decided
trade-offs.

## Question 1: Is the architecture concrete enough to implement?

Mostly yes. The design names:

- All file paths (`skills/strategy/SKILL.md`, six `phases/phase-N-*.md`
  files, `references/strategy-format.md`, `scripts/transition-status.sh`,
  `evals/evals.json`, `evals/fixtures/STRATEGY-*.md`).
- All Go entry points (`Formats` map literal in `formats.go`,
  `checkStrategyPublic(doc Doc, cfg Config) []ValidationError` in
  `checks.go`, `case "Strategy":` arm in `ValidateFile` in `validate.go`).
- The transition script CLI shape (`<path> <target> [reason]`).
- The Phase 4 jury verdict file path
  (`wip/research/strategy_<topic>_phase4_<role>.md`) and the verdict
  format (`**Verdict:** PASS | FAIL`).

### Concrete gaps

- **Switch-arm casing inconsistency with existing convention.** The
  existing dispatch in `validate.go` uses `case "VISION":` (the literal
  `Name` field value, all-caps). The design specifies `Name: "Strategy"`
  and `case "Strategy":`. That is internally consistent with PRD R8 and
  matches the chosen Name, but the design's Negative Consequences already
  flags this as capitalization drift. Implementing PR should add a code
  comment in the switch noting the deliberate mixed-case convention so a
  future reader doesn't normalize it away.
- **`RequiredFields` choice not cross-checked against frontmatter.go.**
  The Formats literal names `["status", "bet", "scope"]`. The design
  doesn't confirm that `bet` and `scope` survive frontmatter parsing as
  scalars (vs. block-scalar YAML like `problem:` / `decision:` on
  DESIGN). Phase 1's unit tests should cover this; flag for the
  implementer.
- **No named owner for the `docs/strategies/` directory creation.** No
  phase explicitly creates `docs/strategies/` or `docs/strategies/sunset/`
  before first use. Either Phase 3 (transition script) or Phase 4 (skill
  Phase 5 finalize) should `mkdir -p` defensively.

## Question 2: Missing components or interfaces?

- **No `Doc` / `Config` struct reference.** The design quotes
  `checkStrategyPublic(doc Doc, cfg Config)` but never points at the
  package where these live or links to `checkVisionPublic` as the
  canonical structural reference. A one-line "see `checks.go:206
  checkVisionPublic` for the mirror pattern" anchor would close this.
- **No specification of evals fixture filenames.** Decision 5 lists 8
  scenarios but the design's Components section says only
  `evals/fixtures/STRATEGY-*.md` without naming each fixture (e.g.,
  `STRATEGY-happy.md`, `STRATEGY-missing-section.md`,
  `STRATEGY-public-leak.md`). Implementers can derive names but the lack
  of pinning means PR review may bikeshed.
- **No mention of `formats_test.go` extension.** Phase 1 deliverables
  say "Unit tests for FC01-FC04 against a known-good STRATEGY fixture
  (mirroring `formats_test.go` precedent)" without specifying the test
  function name or the fixture path inside `internal/validate/testdata/`.
  Minor — convention is well-established — but worth pinning.
- **No interface for the orchestrator's PASS-aggregation logic.** Phase
  4 names "all-PASS to proceed" but does not specify the parser. Is it
  grep for `**Verdict:** PASS`? Is it a bash helper in the skill? Phase 4
  prose in `phase-4-validate.md` will own this, but the design should
  call out that the parser is grep-shaped, not a Go binary.
- **No spec for the `bet` and `scope` frontmatter field value contracts.**
  The design names them as `RequiredFields` but doesn't specify allowed
  values for `scope` (PRD names `project|org`; FC03 enum enforcement is
  not specified for `scope`). If `scope` is enum-validated, it needs a
  `ValidScopes` field analogous to `ValidStatuses`, or the spec accepts
  free-text.

## Question 3: Are the 6 implementation phases correctly sequenced?

Yes, with one observation:

- **Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6** honors
  build dependencies correctly. Format reference + Formats-map (P1) is
  prerequisite for the check (P2) and for the script (P3) — both read
  `RequiredSections` / `ValidStatuses` indirectly. Skill body (P4)
  depends on all three. Evals (P5) exercises the integrated behavior.
  Documentation (P6) is independent enough to ship last.
- **Mild dependency inversion in Phase 3.** The transition script
  (`transition-status.sh`) doesn't actually depend on the format reference
  or the Go-side Formats map at runtime — it manipulates frontmatter and
  filesystem only. Phase 3 could run in parallel with Phase 2 to compress
  schedule, but the design's linear sequencing is safer and reads cleaner;
  not worth changing.
- **Phase 4 depends on Phase 3 only for end-to-end run.** Skill body
  drafting can begin before transition script lands; the dependency is
  only at Phase 5 (Finalize). The design is conservative here, which is
  fine.

## Question 4: Simpler alternatives the design overlooked?

The cross-validation pass already eliminated the major alternatives
(stay-put Sunset, generalized `ProhibitedPublicSections`,
`checkStrategySunsetReason` second Go check, single-jury reviewer). Two
narrower simplifications remain on the table:

- **Folding Phase 0 and Phase 1.** The design carves Phase 0 (Setup) and
  Phase 1 (Discover) as distinct phases, but Phase 0 does only entry-mode
  detection + visibility/scope detection + wip/ init — work that other
  shirabe skills do inside their Phase 1. Collapsing to five phases would
  match `/vision`'s shape exactly (PRD R5 names six phases, but the PRD
  was authored alongside the design; the design could revise this
  upstream). Skipped because PRD R5 commits to six phases; flagging for
  awareness only.
- **Single `transition-status.sh` shared across artifact types.** Each
  artifact type currently ships its own transition script with near-
  identical CLI shape. A shared helper at `skills/_shared/transition.sh`
  parameterized by artifact prefix and sunset directory would absorb
  STRATEGY without a new script. Skipped because no precedent exists and
  the design's "pattern fidelity over abstraction" discipline is the
  right call at this maturity stage — but if a sixth or seventh artifact
  type lands, this is the refactor.

## Summary

The design is implementable as written. Findings are completeness gaps
(fixture filenames, scope enum, formats_test.go pinning, switch-arm
casing comment) rather than architectural omissions. The phase sequencing
honors all build dependencies. Cross-validation already resolved the
substantive alternatives. Recommend implementation proceeds after the
implementing PR captures the minor pinning items above as TODOs or
inline rationale.

# Phase 2 Research Synthesis: shirabe-comp-skill

Sub-agent operating non-interactively. Research consolidated from documented precedents in the worktree.

## Precedent Mapping

| Aspect | Closest Precedent | What It Tells Us |
|---|---|---|
| Skill structure | `/strategy` (SE3), `/brief` | Plain-English SKILL.md + phase files. 5-6 phases including jury. |
| Format reference | `strategy-format.md`, `prd-format.md`, `brief-format.md` | Frontmatter + Required Sections + Lifecycle + Validation Rules + Quality Guidance. |
| Phase 4 jury | `/strategy` (3 reviewers), `/brief` (2 reviewers), `/prd` (3 reviewers) | Reviewer count varies by content type; 2 is the floor. |
| Validate-CLI extension | `internal/validate/formats.go` Formats map | Add one map entry; longest-prefix routing picks up the new prefix automatically. |
| Visibility gating at validate | VISION's `Competitive Positioning` section uses a custom check in `internal/validate/checks.go` reading `cfg.Visibility` | Schema-level visibility gating already has precedent; novel surface is whole-doc gating (not section-gating). |
| CI activation | Existing reusable `validate-docs.yml`; release notes name path-filter widening obligation | Same release-note pattern from STRATEGY (R9). |
| Lifecycle terminology | Mixed across types: BRIEF uses `Draft -> Accepted -> Done`; STRATEGY uses `Draft -> Accepted -> Active -> Sunset`; PRD uses `Draft -> Accepted -> In Progress -> Done`; VISION mirrors STRATEGY | Need a position. |

## Validate Code Layout

- `internal/validate/formats.go`: `Formats` map. Adding `comp/v1` activates FC01 (required fields), FC02 (valid statuses), FC03 (frontmatter/body status match), FC04 (required sections).
- `internal/validate/checks.go`: where custom checks live (e.g., visibility-gated VISION sections). New check `FC<N>` likely needed for whole-doc visibility (reject comp/v1 entirely when `cfg.Visibility == "public"`).
- `--visibility` CLI flag is already implemented for VISION's section gating; COMP can read the same flag.

## Skill Structure Likely Shape

By analogy to /strategy:
- Phase 0: Setup (entry mode, visibility detection + early refusal in public repos, upstream detection, wip/ init)
- Phase 1: Discover (market segment scoping, competitor identification)
- Phase 2: Draft (per-competitor analysis, comparative matrix, opportunities, implications)
- Phase 3: Structural fill (cross-cuts and tie-back)
- Phase 4: Jury validate
- Phase 5: Finalize

## Jury Reviewer Candidates

A: Two reviewers (parity with /brief): content-quality + structural-format.
B: Three reviewers (parity with /strategy, /prd): + competitive-framing reviewer that checks for marketing language, opportunity substance, implications tie-back.
C: One reviewer (structural-format only): subjective competitive content is harder to mechanize.

Recommendation lean: Option B for parity with STRATEGY's medium-term work. Surface the choice as a decision for design.

## /charter Delegation Contract Candidates

- Inputs: scoped topic, optional upstream STRATEGY or VISION path, scope hints.
- Outputs: artifact path, status (Draft or Accepted), summary string for /charter to inject into the downstream /strategy phase.
- Failure modes:
  - Public-repo refusal (visibility mismatch): /comp surfaces refusal; /charter handles by skipping competitive sub-phase silently.
  - Validation failure on forced acceptance: /comp surfaces FC error; /charter halts and prompts user.

## Visibility Enforcement Architecture Options

Option A — Path-based: `docs/competitive/` is valid only in private repos. Generic, simple to implement. Couples enforcement to file location.

Option B — Schema-based: `comp/v1` has a `private_only: true` flag in `FormatSpec`. Cleaner separation; sets up a reusable visibility-gated-artifact pattern for future types.

Option C — Generic framework: add a `RequiresVisibility []string` field to `FormatSpec` (e.g., `["private"]`). Most extensible. Heaviest design surface.

Recommendation lean: Option B (schema-based flag on FormatSpec). Surface as decision for /design.

## Format Spec Source-of-Truth Candidates

- Verbatim copy from workspace skill: fastest, but inherits workspace shape and may diverge from shirabe-conformant format style.
- Ported with shirabe-conformant edits: matches `strategy-format.md` shape. Required-section list and quality guidance harmonized with shirabe's own style.
- Rewrite from prior examples: independent, but loses the workspace-level format's prior dogfooding.

Recommendation lean: Ported with shirabe-conformant edits.

## Lifecycle Ladder Candidates

- Two-state (`Draft -> Final`): matches prior COMP examples. Reflects that competitive analysis is a point-in-time snapshot.
- Three-state (`Draft -> Accepted -> Done`): matches BRIEF; signals when downstream work picks up the analysis.
- Four-state (`Draft -> Accepted -> Active -> Sunset`): matches STRATEGY/VISION; signals when the bet that incorporated the analysis pivots.

Recommendation lean: Three-state, mirroring BRIEF. COMP is a feature-framing artifact like BRIEF, not a falsifiable bet like STRATEGY.

## Key Constraint: Public Visibility Of This PRD

The PRD body cannot:
- Name any private artifact path (no `COMP-superpowers-vs-koto.md`).
- Cite any private repo issue (no vision#511).
- Path-cite the workspace-level `tsukumogami:competitive-analysis` plugin.

Workaround: refer to the workspace-level COMP skill as "an existing workspace-level skill that captures the COMP format" — same shape the BRIEF used.

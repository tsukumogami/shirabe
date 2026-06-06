---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-shirabe-pattern-v1-ergonomics.md
problem: |
  PRD-shirabe-pattern-v1-ergonomics binds 32 requirements across seven clusters
  touching nine shirabe child SKILLs, the parent-skill-pattern reference, four
  format references (two of which don't yet exist at the canonical altitude),
  the `/design` Phase 6 jury, and the Rust validator. The PRD defers mechanism
  choice per fix-class; this design picks placement and mechanism per cluster
  while preserving R31 backward compatibility and R32 sequencing.
decision: |
  One canonical contract per fix-class at the pattern level plus per-skill
  citations: `## Sub-Agent Dispatch Fallbacks` and a `### Child-Side Sentinel
  Consultation Row Convention` subsection land in
  `references/parent-skill-pattern.md`; eight child SKILLs grow `### Sub-Agent
  Dispatch Fallback` subsections; seven child Resume Logic tables grow a
  first-row sentinel-consultation predicate; `design-format.md` and
  `plan-format.md` materialize at the canonical altitude with seven per-field
  rulings across the four format references; `/design` Phase 6 grows a third
  structural-format reviewer; `/plan` Phase 3 grows a cross-issue consistency
  sub-step and Phase 4 grows an AC anchor-existence step and Phase 7 grows an
  emission self-check; `/scope` Phase 0 grows slug-prefix sampling and Phase 1
  grows cold-start projected-PRD evaluation; `references/cli-version-preflight.md`
  is added as a new shared reference cited from each child SKILL prescribing a
  `shirabe` subcommand; the validator gains three notice-level checks
  (SCHEMA-MISSING extension, FC10 writing-style, FC11 plan-section-structure).
  Implementation sequences in three batches: pattern-level upstream, per-skill
  consumers, validator downstream.
rationale: |
  Composability is the load-bearing property — eight child SKILLs citing one
  canonical fallback contract eliminates the drift surface the BRIEF named.
  R32 sequencing falls out structurally because per-skill consumers cite
  pattern-level statements; the three-batch ordering makes the dependency
  direction explicit. R31 backward compatibility holds at every boundary
  because the `parent_orchestration:` sentinel (absent under direct
  invocation) gates every new fallback path. The validator-vs-jury split
  places each check at its natural surface — structural in Rust, mechanical
  in Rust, natural-language judgment in Phase 6 reviewers — closing
  `tsukumogami/shirabe#157` and `tsukumogami/shirabe#158` on the surfaces
  that satisfy R18 and R17/R22 in the same edit.
---

# DESIGN: shirabe pattern v1 ergonomics

## Status

Planned

Phase 6 jury returned all-PASS as serial-self-jury under sub-agent dispatch
from `/scope` (`parent_orchestration.invoking_child: design`,
`rationale: fresh-chain`); the independence-loss caveat is recorded in each
verdict file (`wip/research/design_shirabe-pattern-v1-ergonomics_phase6_architecture-review.md`,
`...phase6_security-review.md`,
`...phase6_structural-format-review.md`). The Phase 6 jury runs three rubrics
(architecture, security, structural-format); v0.9.1-dev's
`phase-6-final-review.md` still ships only the first two reviewers, so the
structural-format reviewer was walked under this design's own R21 contract
ahead of R21 landing in the codebase. The dogfooding is recorded in the
friction log.

## Context and Problem Statement

PRD-shirabe-pattern-v1-ergonomics binds 32 requirements organized into seven clusters across nine shirabe child SKILLs (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`, plus `/work-on` and `/scope`'s effect on child Resume Logic), the parent-skill-pattern reference, four format references (`brief-format.md`, `prd-format.md`), the design Phase 6 jury reference, and the Rust validator (`crates/shirabe-validate`). The PRD names the contracts that must hold; this design picks the mechanism per fix-class — where the fallback prose lives in each SKILL.md, what row shape the Resume Logic table grows, which extensions land in the validator versus the Phase 6 jury, which conventions get a Phase-0 check.

The technical problem the design solves is mechanism selection under three operating constraints. First, the changes touch about a dozen committed files and twenty-plus reference paths; an ad-hoc fix per requirement would produce twenty-plus mechanism variants where one shape would compose better. Second, PRD R32's sequencing constraint requires pattern-level reference edits land before per-skill consumers — picking the per-skill shape determines whether the pattern-level edit is a one-line citation or a multi-paragraph contract. Third, the PRD's load-bearing D2 fixes the serial-self-jury contract under sub-agent dispatch as the one mechanism-level commitment; everything else this design picks composes against that contract.

Four ground-truth surfaces shape the mechanism choice. (1) The parent-skill-pattern reference (`references/parent-skill-pattern.md`) names the `parent_orchestration:` sentinel with `invoking_child`, `suppress_status_aware_prompt`, and `rationale` subfields at the pattern level (lines 181-206), and the resume-ladder template (`references/parent-skill-resume-ladder-template.md`) names Slot 5 as the parent-specific status-aware re-entry slot for parents — but the child SKILL.md Resume Logic tables (`skills/brief/SKILL.md:170-181`, `skills/prd/SKILL.md:105-114`, `skills/plan/SKILL.md:250-265`, `skills/design/SKILL.md:167-179`, plus the three strategic child SKILL.md Resume Logic sections) do not consult the sentinel. The mechanism choice is whether to add a child-side row, a pattern-level row convention, or both. (2) The design Phase 6 reviewer set (`skills/design/references/phases/phase-6-final-review.md:21-55`) launches two reviewers (architecture-reviewer at lines 25-39, security-reviewer at lines 41-55); no structural-format reviewer exists. R21/AC4.4 commits the addition; the mechanism choice is reviewer-set extension versus validator surface. (3) The Rust validator's `check_schema` function (`crates/shirabe-validate/src/checks.rs:39-51`) emits a SCHEMA notice when the doc's schema string doesn't match the format spec; the validator currently exits 0 when the schema field is missing (`tsukumogami/shirabe#157`). The mechanism choice is whether the FC-level extension lands in the validator or whether the Phase-6 reviewer catches it instead. (4) The four format references — `brief-format.md`, `prd-format.md`, and the (currently non-existent) `design-format.md` and `plan-format.md` — carry ambiguous public-cleanliness grammar at `brief-format.md:310-311` and never document the canonical `## Implementation Issues` single-pr structure (`tsukumogami/shirabe#158`). The mechanism choice is whether to materialize the missing `design-format.md` and `plan-format.md` as new files or to consolidate the rules into the existing SKILL.md prose.

The friction the PRD names (R1-R32) cuts across files that span Rust crates, YAML team-shape declarations, Markdown SKILL prose, format-reference markdown, and the validator's check vocabulary. The design coordinates the mechanism choices so the per-fix-class shape composes — every Resume Logic row is the same shape across the seven children, every fallback section sits at the same SKILL.md location, every validator extension lands at the same check vocabulary level.

## Decision Drivers

The drivers shape the mechanism choices below; they are derived from the PRD's R31, R32, D1, D2, D3, and the BRIEF's framing of silent degradation as the failure mode.

- **Composability across the fix-class set.** The PRD names 32 requirements; the design picks ~6-8 mechanism shapes. Every chosen shape needs to apply uniformly across its fix class — Resume Logic sentinel-consultation is one row shape across seven children, not seven different rows. Composability discharges the PRD's "every chain pays the same tax" framing by ensuring the fix shape is the same chain-wide.

- **R31 backward compatibility.** Top-level direct invocation of any child SHALL produce the same behavior the child currently produces, with fallbacks active only when the `parent_orchestration` sentinel is present. The mechanism shapes preserve the existing top-level path verbatim — added rows fall through when the sentinel is absent, added sections describe sub-agent fallbacks without changing the parent code path, added validator checks emit notices rather than errors when content is plausibly intentional.

- **R32 sequencing — pattern-level reference edits land first.** The pattern-level reference (`references/parent-skill-pattern.md`) and the format references (`brief-format.md`, `prd-format.md`) get edited before per-skill consumers (R1-R9, R11-R12, R15, R17). The mechanism shapes accommodate this by placing the canonical contract statement at the pattern level and citing it from each child SKILL.md rather than inlining the contract per child.

- **D2 load-bearing — serial-self-jury under sub-agent dispatch is named explicitly.** PRD D2 fixes the serial-self-jury contract as the one mechanism-level commitment. The design picks WHERE the contract clause lives in each child SKILL.md (Decision 1 below settles this) but does not re-open WHETHER the contract holds.

- **D3 — CLI version-skew preflight is a skill-prose contract, not a validator extension.** The PRD's R30 commits a CLI-version preflight; the design picks the prose mechanism (Decision 6 below). The validator runs against committed artifacts; the version-skew is a runtime condition the skill body addresses inline.

- **Skill-prose edits vs. validator extensions tradeoff.** The PRD defers validator-vs-Phase-N choice for R19, R20, R22. The validator (`crates/shirabe-validate/src/checks.rs`) emits FC-coded notices; adding new checks requires Rust code and a release-train cut (the validator ships as a Rust binary via `shirabe transition`). Skill-prose edits ship with the SKILL.md changes themselves; they don't require a binary release. The driver favors skill-prose unless the check is structural (the schema gate, the table-vs-diagram reconciliation), in which case the validator is the right surface.

- **Audit-trail fidelity.** The BRIEF's User Outcome names "the chain's audit trail matches the chain's actual execution." Mechanism shapes that surface their operating context in the artifact preamble (verdict files, sentinel cleanup state, fallback-section presence) score higher than mechanism shapes that change behavior silently.

- **Cross-repo public-visibility cleanliness.** The repo is Public. The design references `tsukumogami/vision#514` and `tsukumogami/vision#535` by issue number per the BRIEF's References section; no private paths, repos, or codenames appear in this document.

## Considered Options

### Decision 1: Sub-agent fallback section format

PRD R1-R8 commits the contract that every child SKILL with a Phase-N parallel-jury site, approval gate, nested-dispatch site, or koto state-machine loop SHALL surface a fallback path under sub-agent dispatch. The five named fallback shapes (serial-self-jury, parent-delegated-approval, decision-bypass, inline-substitute-review, deterministic-mode-bypass) recur across eight SKILLs (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`, `/work-on`). The placement question is where the canonical contract lives and how each child SKILL.md surfaces its specific binding. PRD D2 already fixes the serial-self-jury contract; this decision picks placement only.

Key assumptions: each child SKILL.md has a `### Critical Requirements` section that the fallback subsection can hang from (verified: `/brief` line 183, `/prd` line 116, `/design` line 181, `/plan` matching grep); the pattern reference at `references/parent-skill-pattern.md` is the right anchor (it's the existing canonical contract surface and already declares the `parent_orchestration:` sentinel mechanics at lines 181-206); the four canonical fallback shapes cover R1-R7 with R8's carve-out captured pattern-level once.

#### Chosen: Pattern-level canonical section plus per-skill citations

A new section `## Sub-Agent Dispatch Fallbacks` lands in `references/parent-skill-pattern.md` after the existing `## Team-Lead Operating Discipline` section. The section names five canonical fallback shapes — serial-self-jury (parallel-jury substitute, verdict-preamble names the operating context and the independence-loss caveat), parent-delegated-approval (approval-gate substitute, child leaves artifact at pre-approval status), decision-bypass-with-inline-resolution (per-decision-dispatch substitute when the upstream PRD enumerates alternatives and recommends a direction, conditions are PRD-names-alternatives AND reviewer-count-acceptable-inline), inline-substitute-review (nested-sub-skill substitute when recursive dispatch isn't available), deterministic-mode-bypass (koto state-machine substitute when parent supplies decomposition + cascade timing + push timing upfront). A closing paragraph names R8's NOT-covered carve-out (`tsukumogami/vision#535` Track B, nested-team spawning is not addressed).

Each child SKILL.md grows a `### Sub-Agent Dispatch Fallback` subsection under its existing `### Critical Requirements` section. The subsection is 4-8 lines and cites the pattern-level reference with the skill-specific binding. The eight per-skill bindings are summarized in a binding table in the Solution Architecture below.

R32 sequencing falls out structurally — the pattern-level section is the upstream change, the per-skill citations are downstream consumers. R31 backward compatibility is preserved — the section describes sub-agent behavior gated on the `parent_orchestration:` sentinel; direct-invocation paths are unchanged.

#### Alternatives Considered

**Inline-only per-skill sections, no pattern-level section**: each child SKILL.md restates the full contract. Rejected because composability fails — seven children with seven slightly-divergent restatements of the same contract is the failure shape the BRIEF named. Drift between children is inevitable; the BRIEF's "audit trail matches execution" outcome degrades when two children describe the same fallback in two different ways.

**Pattern-level section only, no per-skill mention**: children inherit by virtue of the pattern reference being cited at the top of each SKILL.md. Rejected because AC1.1, AC1.3, AC1.4, AC1.5, AC1.6, AC1.7, AC1.8 explicitly require sections in each of the eight child SKILLs. An AC grep against the SKILL files finds nothing and the ACs fail. Skill-specific bindings (which phase fans out, which approval gate exists, which sub-skill is dispatched) cannot be inferred from the pattern reference alone — that data is per-skill.

### Decision 2: Resume Logic sentinel-consultation row format

PRD R9 requires each child Resume Logic table to consult the `parent_orchestration:` sentinel before evaluating wip/-file-existence rows; R10 requires the pattern-level reference to describe the convention. The seven affected children are `/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`. Current Resume Logic tables (verified at `skills/brief/SKILL.md:170-181`, `skills/prd/SKILL.md:105-114`, `skills/plan/SKILL.md:250-265`, `skills/design/SKILL.md:167-179`, plus the three strategic children) do not consult the sentinel.

Key assumptions: every affected child has a code-fenced Resume Logic table where "row" means "line"; the pattern-level `## Conditional Feeder Invocation Shape` section is the right anchor because it already discusses the `parent_orchestration:` block at lines 181-206; the parent state file paths are `wip/scope_<topic>_state.md` for tactical-chain children and `wip/charter_<topic>_state.md` for strategic-chain children.

#### Chosen: First-row sentinel-consultation in each child plus pattern-level convention subsection

Every child Resume Logic table grows a new first row (above all existing rows). The row predicate is "parent_orchestration: sentinel present in <state-file-path>"; the action is "read invoking_child, suppress_status_aware_prompt, rationale; route per rationale (fresh-chain | revise)". When the sentinel is absent, the row falls through to the existing first row and existing behavior holds. The three subfields are named in the row's prose so an AC grep finds them.

The pattern-level convention lives in a new subsection `### Child-Side Sentinel Consultation Row Convention` inside `references/parent-skill-pattern.md`'s existing `## Conditional Feeder Invocation Shape` section. The subsection states the row contract and provides the canonical row template each child copies verbatim. A per-skill state-file-path table maps each child to its parent's state-file path.

R31 backward compatibility falls out structurally — absent sentinel falls through to the existing first row, behavior identical to current direct-invocation. R32 sequencing falls out structurally — the pattern-level subsection edit is upstream of the seven per-skill row edits. Cross-skill consistency falls out by construction — every child copies the same canonical row template.

#### Alternatives Considered

**Restructure each child's Resume Logic to mirror the 9-row parent meta-ladder**: a new reference file `child-skill-resume-ladder-template.md` parallels the parent template. Rejected as out-of-scope — R9 says "before evaluating the existing rows," meaning add a row before, not restructure. Restructuring would touch every row of every child Resume Logic table, outside R31's "preserve existing behavior" envelope.

**Sentinel consultation in Phase 0 step prose, not in the Resume Logic table**: the table stays structurally identical; a Phase 0 step reads the sentinel before the table fires. Rejected because AC2.1 explicitly requires "each child SKILL Resume Logic table ... contains a row that consults the parent_orchestration: sentinel" — an AC grep against the Resume Logic table doesn't find the row and the AC fails. The ladder semantic is also wrong: the Resume Logic table is the first surface the child consults on entry; Phase 0 fires after the table decides where to enter.

### Decision 3: Format-reference clarifications and file materialization

PRD Cluster 3 (R11-R17) prescribes seven format-reference clarifications. Two of them (R15, R17) reference `design-format.md` and `plan-format.md` — files that do not exist at the worktree (verified by `find`). The seven clarifications span public-issue-number grammar (R11), motivating_context vs prose workaround (R12), BRIEF Open-Questions closure surface (R13), PRD Decisions-and-Trade-offs as conventional closure (R14), Implementation Issues ownership (R15), competitive-findings vs competitive-analysis-as-artifact-type distinction (R16), and `/plan` single-pr Implementation Issues canonical structure (R17).

Key assumptions: `brief-format.md` exists at `skills/brief/references/brief-format.md` and `prd-format.md` exists at `skills/prd/references/prd-format.md`; the four format references at `skills/<name>/references/<name>-format.md` is the canonical altitude per the existing two-file precedent; the migration preserves existing SKILL.md inline format prose by relocating content and adding back-references.

#### Chosen: Materialize design-format.md and plan-format.md at the canonical altitude with seven per-field rulings

`skills/design/references/design-format.md` and `skills/plan/references/plan-format.md` are created as new top-level reference files. Existing inline format prose in `skills/design/SKILL.md` lines 24-95 and `skills/plan/SKILL.md` relocates to the new files with back-references from the SKILL.md "Structure" sections.

Per-field rulings: R11 disambiguates public issue numbers by inserting "private" before "issue numbers" in both `brief-format.md:310-311` and the parallel rule in `prd-format.md`; a one-line rationale follows. R12 documents the `motivating_context:` optional frontmatter field accepting a cross-repo reference allowed to point at a private artifact from a public document (the field is metadata; the link target is referenced, not described). R13 names "the downstream PRD's Decisions and Trade-offs section" as the canonical BRIEF Open-Questions closure surface. R14 surfaces "Decisions and Trade-offs" as the conventional closure section in `prd-format.md`'s Optional Sections description. R15 states the Implementation Issues table is owned by `/plan` and added during `/plan`'s Phase 7 single-pr execution; `/design` SHALL NOT prescribe an inline table. R16 distinguishes "competitive findings" (content the PRD does NOT contain) from "competitive-analysis-as-an-artifact-type" (a subject the PRD MAY reference). R17 documents the canonical `## Implementation Issues` structure — Issues Table (columns: ID, Title, Status, Notes) plus Mermaid dependency diagram; the validator's FC08 reconciles classDef declarations against table Status (PR #169); the table-vs-diagram check reconciles edge endpoints against table IDs (PR #149).

#### Alternatives Considered

**Inline the per-field requirements into existing SKILL.md prose; no new format reference files**: R15 lands in `skills/design/SKILL.md`'s "Sections Added During Lifecycle" subsection (line 116) and R17 lands in `skills/plan/SKILL.md`'s format prose plus `skills/plan/references/quality/plan-doc-structure.md`. Rejected because AC3.5 explicitly names `references/design-format.md` and AC3.7 names `references/plan-format.md`; AC grep against the named paths fails. Asymmetric file inventory is the failure shape the BRIEF named ("audit trail diverges from execution") — two of four format references would exist as files; two would exist only as inlined SKILL.md prose.

**Materialize only design-format.md; inline plan-format.md into plan-doc-structure.md**: asymmetric materialization. Rejected because AC3.7 names `references/plan-format.md` specifically; AC grep against the path fails. The migration cost-saving is small; the cross-skill consistency cost is large.

### Decision 4: Validator vs jury split for the five candidate checks

PRD Cluster 4 (R18-R22) defines five candidate checks where the placement choice is deferred. R18 is schema-field-present (closes `tsukumogami/shirabe#157`); R19 is section-length-budget overshoot; R20 is writing-style banned-word grep; R21 is structural-format reviewer for `/design` Phase 6; R22 is single-pr Implementation Issues drift (closes `tsukumogami/shirabe#158`).

Key assumptions: the validator's notice mechanism (per FC08 PR #169 precedent and FC09 PR #167 precedent) is the established surface for non-error advisory checks; the Phase 6 reviewer set at `skills/design/references/phases/phase-6-final-review.md:21-55` has two existing reviewers (architecture, security); the writing-style SKILL.md at `skills/writing-style/SKILL.md` lines 10-17 is the canonical source for banned vocabulary.

#### Chosen: Five-check split — validator handles structural and mechanical; Phase 6 reviewer handles natural-language judgment; emission and validator share responsibility on R22

R18 schema-field-present lands in the validator. The existing `check_schema` function at `crates/shirabe-validate/src/checks.rs:39-51` gains a SCHEMA-MISSING notice path that fires when `doc.schema.is_empty()`, parallel to the existing SCHEMA notice on schema mismatch. The check is structural and applies to every artifact type uniformly. Notice level (not error) matches FC08/FC09 precedent.

R19 section-length-budget overshoot lands in the Phase 6 reviewer set as a rubric inside the new structural-format reviewer (added per R21). The reviewer parses budget claims from the artifact's own prose ("approximately N lines", "~N lines", "around N lines") and counts section lines; budget exceeded by >50% triggers a verdict flag. This natural-language parsing is brittle in the Rust validator but natural in a Phase 6 reviewer's context.

R20 writing-style banned-word grep lands in the validator as a new FC10 check. The grep is purely mechanical; the canonical banned list at `skills/writing-style/SKILL.md` lines 10-17 is the source of truth; the validator reads from it at validate-time so future reference updates propagate without a validator code change. Notice level.

R21 structural-format reviewer extends the Phase 6 reviewer set from two to three. The new reviewer's rubric covers artifact-shape conformance against the materialized format references (Decision 3), section presence/order, frontmatter field order, and the R19 budget-vs-spec sub-rubric. AC4.4 explicitly requires "in addition to" the existing reviewers, so a new reviewer (not a rubric extension) is required.

R22 single-pr Implementation Issues drift lands in both surfaces — `/plan` Phase 7's emission step gains a self-check against the canonical structure documented in `plan-format.md` (Decision 3 R17), AND the validator gains an FC11 check that reconciles the emitted `## Implementation Issues` section against the canonical structure. The two surfaces are defense-in-depth — Phase 7 catches drift at emission time before commit; FC11 catches existing drift in already-committed PLAN docs from older `/plan` versions.

#### Alternatives Considered

**All five checks in the validator**: R19's natural-language parsing of budget claims would require fragile regex against "approximately N", "~N", "around N" variants. Rejected because the Phase 6 reviewer has the artifact context to make the judgment naturally; the validator is the wrong surface for prose claims.

**All five checks in the Phase 6 jury**: R18's structural check would require the structural-format reviewer to re-parse frontmatter (duplicating logic that lives in `frontmatter.rs`); R20's mechanical grep would gain a per-DESIGN-judgment cost for a check that doesn't need judgment. Rejected because structural checks belong in the validator and mechanical checks belong in the validator; only natural-language checks belong in the reviewer set.

**Pre-commit hook for R20**: a git pre-commit hook runs the writing-style grep before commit. Rejected because pre-commit hooks block authors mid-flow and the workspace already has a validator surface for advisory notices; adding a hook layer is a new mechanism the workspace doesn't need.

### Decision 5: Cross-skill consistency rules placement

PRD Cluster 5 (R23-R26) prescribes four cross-skill consistency rules: `/plan` field-consistency pre-flight (R23), `/plan` AC anchor-existence grep (R24), `/design` Phase 6 wip-hygiene carve-out extension (R25), eval-fixture HTML-comment marker placement (R26).

Key assumptions: `/plan` Phase 3 is "Decomposition" (verified at `skills/plan/SKILL.md:289`); Phase 4 is "Generation" (verified at line 292); the existing wip-hygiene rule wording is at `skills/design/references/phases/phase-6-final-review.md:104-106`; the frontmatter parser at `crates/shirabe-validate/src/frontmatter.rs` requires `---` to be the first non-blank line.

#### Chosen: Four rule placements per the natural fire point of each rule

R23 lands as `/plan` Phase 3 sub-step 3.6 (Cross-Issue Consistency Pre-Flight). Phase 3 is where issue outlines are first drafted; folding the check into Phase 3 catches collisions at the earliest point. A separate Phase 3.5 (Option A in the decision report) adds a phase count the PRD doesn't require; Phase 7 (Option B) catches the collision after agent generation has already run against contradictory specs.

R24 lands as `/plan` Phase 4 agent-prompt enrichment. AC anchor-existence is per-issue; the natural fire point is when the AC is being generated, in the agent prompt. The prompt step: for each AC claiming "annotation only" or "schema fields unchanged", grep the target file at PLAN-authoring time; if the anchor exists, the AC remains; if absent, the AC is rewritten defensively ("annotation added; if anchor missing, this issue includes the minimal anchor definition").

R25 lands as a wording extension at `skills/design/references/phases/phase-6-final-review.md:104-106`. The existing rule disallows wip/... paths in committed artifacts except for "quoted statements OF the wip-hygiene rule itself"; the extension adds "or documentation of a skill's runtime wip/ usage (i.e., a DESIGN, PRD, or BRIEF describing a skill's wip/-file contract for skill-implementation purposes)". The "skill-implementation purposes" qualifier prevents the carve-out from being abused for non-skill-implementation DESIGNs that happen to mention wip/.

R26 lands as an eval-fixture authoring convention update. The conflict (HTML-comment line-1 markers vs frontmatter parser's `---`-first-non-blank-line requirement) resolves by forbidding line-1 markers; fixtures place markers either inside a frontmatter field value or after the closing `---` as the first body line. The convention lives in `skills/plan/references/templates/` (the closest existing eval-fixture authoring reference location) plus any eval-authoring SKILL prose that prescribes the marker.

#### Alternatives Considered

**R23 as a separate Phase 3.5 between Decomposition and Generation**: adds a phase count the PRD doesn't require. Rejected — folding into Phase 3 reuses existing scope.

**R24 at Phase 3 (Decomposition) or Phase 7 (Creation)**: Phase 3 is too early (decomposition doesn't yet have AC text); Phase 7 is too late (issues are about to be filed). Rejected — Phase 4 is the natural fire point.

**R25 case-by-case judgment instead of mechanical rule extension**: leaves the rule unchanged and relies on Phase 6 reviewer judgment. Rejected because case-by-case judgment is the failure mode the BRIEF named (silent degradation under operator judgment); a mechanical and grep-checkable wording extension is more reliable.

**R26 frontmatter parser tolerates a single HTML-comment before `---`**: changes the validator's input contract; existing artifacts placing `---` on line 1 would still parse but the rule "leading content is ignored" introduces new ambiguity. Rejected — the documentation-side fix is lower-risk and preserves the validator's existing contract.

### Decision 6: Convention updates and CLI version-skew preflight

PRD Cluster 6 (R27-R29) plus Cluster 7 (R30) prescribe four convention updates: `/scope` Phase 0 slug-prefix detection (R27), release-notes adopter-doc location convention (R28), `/scope` Phase 1 R6 cold-start projected-PRD evaluation plus framing-shift opener short-circuit (R29), CLI version-skew preflight prose mechanism (R30). PRD D3 commits R30 as a skill-prose contract.

Key assumptions: `/scope` Phase 0 has the chain-entry slug-validation step (verified existing); CLAUDE.md is the workspace-policy surface for per-repo conventions (parallels existing `## Repo Visibility:` and `## Planning Context:` conventions); the `references/` directory at the worktree root holds shared cross-skill references (parallels existing `worktree-discipline.md`, `wip-hygiene.md`).

#### Chosen: Four placements per the natural surface of each convention

R27 lands as a `/scope` Phase 0 sampling step. The step samples `docs/briefs/BRIEF-*.md`, `docs/prds/PRD-*.md`, `docs/designs/DESIGN-*.md`, `docs/plans/PLAN-*.md` filenames; extracts the first hyphenated word after the artifact-type prefix; counts occurrences; if >50% of artifacts share a prefix, treats it as detected. When the input slug lacks the detected prefix, Phase 0 prompts the author before committing any durable artifact.

R28 lands as a CLAUDE.md convention `## Release Notes Convention: <path>` (e.g., `docs/guides/` for shirabe, or per-repo value). `/prd` and `/design` read the convention at Phase 0 and use it when authoring adopter-obligation ACs. Reading from CLAUDE.md preserves per-repo flexibility — different repos use different conventions; hardcoding breaks portability.

R29's two parts land in `/scope` Phase 1. The R6 cold-start projected-PRD evaluation: when cold-start is detected (no PRD body exists), Phase 1 projects the expected PRD content shape by inspecting upstream artifacts (BRIEF, ROADMAP) for keywords ("alternatives", "mechanism", "choices", "trade-offs") in User Journeys and Problem Statement sections; tentatively fires `/design` when matches are found. A post-`/prd` re-evaluation gate runs after `/prd` lands and re-evaluates R6 against the actual PRD body; if the PRD doesn't surface alternatives, `/design` is skipped and a `chain_revised` record is written to `/scope`'s state file. The framing-shift opener short-circuit: when topic-related child-doc discovery returns empty (cold-start), the opener is skipped and Phase 1 proceeds to the regular scope conversation.

R30 lands as a new shared reference `references/cli-version-preflight.md` with per-skill citations. The reference describes a per-subcommand preflight contract (using `shirabe <subcommand> --help` as the capability detection probe). Each child SKILL.md that prescribes a `shirabe` subcommand (`shirabe transition` is the main affected one per the PRD's Known Limitations) cites the reference and names its specific subcommand and documented fallback. The sed-edit fallback (per the PRD's Known Limitations) is the documented manual operation when the preflight fails.

#### Alternatives Considered

**R27 per-child detection in each SKILL**: each child does its own sampling. Rejected — `/scope` is the chain-entry that names the topic; children inherit the topic; per-child detection is redundant.

**R28 hardcode docs/guides/ in skill prose**: each skill hardcodes the path. Rejected because the workspace runs multiple repos with different conventions; hardcoding breaks portability.

**R29 always-fire `/design` under cold-start**: simpler default that includes `/design` whenever the PRD body is absent. Rejected because it over-includes `/design` for topics that don't have architectural alternatives, defeating R6's existence.

**R30 inline shell-snippet in each SKILL.md**: each SKILL.md prescribing a `shirabe` subcommand inlines the preflight + sed fallback. Rejected because inlining duplicates the pattern across seven SKILLs; the shared reference + per-skill citations preserves composability.

**R30 parent-skill inheritance — `/scope`/`/charter` do the preflight once at chain entry**: parent's Phase 0 runs `shirabe --version` and stores the version in the parent state file; children read the version. Rejected because the version-skew fires per-subcommand-invocation, not per-chain-entry; children invoked directly don't have a parent state file to inherit from.

### Decision 7: Sequencing and migration ordering

PRD R32 names sequencing constraints inherent to the cluster set — pattern-level reference edits (R10, R13, R14, R16) land before per-skill consumers; validator extensions (R18-R22) land alongside or after prose changes that reference them. R31 requires backward compatibility at every boundary. AC8.2 requires sequencing respect R32 explicitly.

Key assumptions: the dependency-graph is structural — per-skill citations that point at non-existent pattern-level sections are broken links; validator checks that dereference canonical references (FC10 reads writing-style SKILL; FC11 reads plan-format.md) error at runtime if the references don't exist.

#### Chosen: Three-batch ordering with pattern-level upstream, per-skill middle, validator downstream

Batch 1 (pattern-level upstream) contains Decision 1's `## Sub-Agent Dispatch Fallbacks` section in `parent-skill-pattern.md`, Decision 2's `### Child-Side Sentinel Consultation Row Convention` subsection in the same file, Decision 3's format-reference materialization (`design-format.md`, `plan-format.md`) plus R11/R13/R14/R16 edits to brief-format/prd-format, Decision 5's R25 wip-hygiene carve-out wording extension, Decision 6's R28 CLAUDE.md convention addition, Decision 6's R30 new shared reference `cli-version-preflight.md`. Estimated 6-8 implementation issues touching 8 files.

Batch 2 (per-skill consumers) contains Decision 1's per-skill section additions to all 8 child SKILLs, Decision 2's per-skill Resume Logic row additions to all 7 child SKILLs, Decision 3's per-skill citations, Decision 5's R23/R24/R26 skill-prose edits, Decision 6's R27/R29/R30 skill-prose edits, Decision 4's R21 Phase 6 structural-format reviewer addition (prose-only), Decision 4's R22 `/plan` Phase 7 emission self-check (prose-only). Estimated 12-16 implementation issues touching ~14 files.

Batch 3 (validator extensions, downstream of prose) contains Decision 4's R18 `check_schema` extension, Decision 4's R20 new FC10 writing-style check, Decision 4's R22 new FC11 plan-section-structure check. Estimated 3-4 implementation issues touching 3 files in `crates/shirabe-validate`.

R31 backward compatibility holds at every batch boundary because the sentinel is the entry condition — Batch 1 adds the contract but no consumer fires; Batch 2 adds consumers that fire when the sentinel is present (absent direct-invocation calls fall through unchanged); Batch 3 adds validator notices that surface advisory warnings without breaking existing artifacts.

#### Alternatives Considered

**Two-batch ordering — collapse Batches 2 and 3**: validator and skill-prose ship together. Rejected because R32 names validator-after-prose explicitly; the three-batch ordering makes the "after" branch concrete and reduces risk (if a validator extension misfires under unexpected artifact shapes, Batch 3 can be reverted independently of the prose changes).

**Single-batch ordering — everything ships together**: rejected as violating R32. Per-skill citations must reference an existing pattern-level statement; the pattern-level edit must land first.

## Decision Outcome

**Chosen: 1-Pattern-canonical + 2-First-row-sentinel + 3-Materialize-format-refs + 4-Five-check-split + 5-Natural-fire-points + 6-Natural-surfaces + 7-Three-batch**

### Summary

The design lands a single composable shape across the seven pattern-v1 fix classes: one canonical contract at the pattern level, per-skill bindings that cite the canonical contract, and validator extensions that catch what skill prose cannot. Five new sections or subsections land in `references/parent-skill-pattern.md` and `references/cli-version-preflight.md`; two new format-reference files (`design-format.md`, `plan-format.md`) materialize at the canonical altitude; the existing `brief-format.md` and `prd-format.md` gain seven per-field clarifications; eight child SKILL.md files gain a `### Sub-Agent Dispatch Fallback` subsection and seven of them gain a first-row sentinel-consultation Resume Logic row; `/design` Phase 6 grows a third reviewer; `/plan` Phase 3 grows a cross-issue consistency sub-step and Phase 4 grows an AC anchor-existence step and Phase 7 grows an emission self-check; `/scope` Phase 0 grows slug-prefix sampling and Phase 1 grows cold-start projected-PRD evaluation; `crates/shirabe-validate` gains three notice-level checks (SCHEMA-MISSING extension, FC10 writing-style, FC11 plan-section-structure).

The contract surface enforces operator trust at every boundary the BRIEF named — verdict-artifact preambles surface the operating context and independence-loss caveat; Resume Logic rows consult the sentinel before existing wip/-file rows; budget-vs-spec sub-rubrics catch DESIGN sections that overshoot prose-named budgets; banned-word grep surfaces writing-style violations the author missed; structural-format reviewer catches schema-field drift; slug-prefix sampling catches drift before durable artifact commit; CLI-version preflight catches subcommand absence before the skill's prescribed call fails open. Direct-invocation behavior is preserved at every boundary because the sentinel (absent under direct invocation) is the gating condition for every new fallback path.

The implementation sequences in three batches: pattern-level upstream → per-skill consumers → validator extensions. Per-skill consumers cite pattern-level statements that exist at the moment of citation; validator extensions read canonical references that exist at the moment of validate-time dereference. R31 backward compatibility holds at every batch boundary. The total implementation is estimated at ~22-28 issues touching ~25 files across child SKILL prose, phase-reference files, format references, the pattern-level reference, shared references, and the Rust validator crate.

### Rationale

The decisions reinforce each other through a single thesis: every silent-degradation surface the BRIEF named has a corresponding contract-surface in the design, and every contract-surface is either at the pattern level (so per-skill consumers inherit consistently) or at the natural fire point (so the check fires when the failure mode actually surfaces). Decision 1's pattern-level fallback section is the upstream that Decisions 2, 5, and 6 reference (Decision 2 cites the pattern reference for the row convention; Decision 5's R25 wording extension lives at the same Phase 6 surface; Decision 6's R30 reference parallels the pattern-level shared-reference altitude). Decision 3's format-reference materialization is the upstream that Decision 4's R21 structural-format reviewer and R22 FC11 check both depend on. Decision 7's three-batch sequencing makes these dependencies explicit in the implementation order.

The five-check split in Decision 4 (validator for structural and mechanical, Phase 6 reviewer for natural-language judgment, both for emission/commit-time defense-in-depth on R22) reflects a sharper principle than "everything goes in the validator" or "everything goes in the jury": structural checks belong where structural parsing already lives; mechanical checks belong where mechanical scanning is cheap; natural-language checks belong where artifact context is available. The Phase 6 reviewer set growing from two to three composes with PRD D2's serial-self-jury contract — the jury becomes 3 reviewers under direct invocation or 3 sequential rubric walks under sub-agent dispatch, no new dispatch shape introduced.

The pattern-level canonical statements (Decisions 1 and 2) are the load-bearing composability win. Without them, the eight per-skill consumers of the sub-agent dispatch fallback and the seven per-skill consumers of the Resume Logic sentinel-consultation would drift over time as each skill's prose is independently edited. With them, future skill edits cite the canonical statement; drift between skills is structural impossible because there's one source of truth.

## Solution Architecture

The architecture lands in four code-level surfaces: pattern-level references (`references/`), per-skill SKILL.md and phase-reference files (`skills/<name>/`), format-reference files (`skills/<name>/references/<name>-format.md`), and the Rust validator (`crates/shirabe-validate/`). The CLAUDE.md convention surface (R28) is a fifth, separate from the four code surfaces.

### Pattern-level references

`references/parent-skill-pattern.md` grows two sections. The first new section `## Sub-Agent Dispatch Fallbacks` lands after the existing `## Team-Lead Operating Discipline` section and names the five canonical fallback shapes (serial-self-jury, parent-delegated-approval, decision-bypass-with-inline-resolution, inline-substitute-review, deterministic-mode-bypass) plus R8's NOT-covered carve-out paragraph. The second new subsection `### Child-Side Sentinel Consultation Row Convention` lands inside the existing `## Conditional Feeder Invocation Shape` section (which already discusses `parent_orchestration:` mechanics at lines 181-206) and contains the canonical row template plus the per-skill state-file-path table.

`references/cli-version-preflight.md` is created as a new shared reference. It describes the per-subcommand preflight contract — using `shirabe <subcommand> --help` as the capability detection probe — and provides the documented fallback path when the preflight fails (typically a manual sed-edit equivalent for the specific subcommand).

### Per-skill SKILL.md changes

Eight child SKILL.md files gain a `### Sub-Agent Dispatch Fallback` subsection under their existing `### Critical Requirements` section. The per-skill bindings are:

| Skill | Phase / gate | Fallback shape |
|---|---|---|
| `/brief` | Phase 4 two-reviewer jury | serial-self-jury |
| `/prd` | Phase 4 three-reviewer jury | serial-self-jury |
| `/design` | Phase 6 jury plus Phases 1-3 decision loop | serial-self-jury plus decision-bypass |
| `/plan` | Phase 6 `/review-plan` plus Phase 3 AskUserQuestion | inline-substitute-review plus execution-mode-hint |
| `/vision` | Phase 4 jury | serial-self-jury |
| `/strategy` | Phase 4 jury | serial-self-jury |
| `/roadmap` | Phase 4 jury | serial-self-jury |
| `/work-on` | koto plan-orchestrator | deterministic-mode-bypass |

Seven child SKILL.md files (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`) gain a new first row in their Resume Logic table. The row reads the `parent_orchestration:` sentinel from the parent's state file (`wip/scope_<topic>_state.md` for tactical-chain children, `wip/charter_<topic>_state.md` for strategic-chain children) and routes per the three named subfields.

`skills/design/references/phases/phase-6-final-review.md` changes in three places: step 6.1 grows a third reviewer (structural-format-reviewer) parallel to the existing architecture-reviewer and security-reviewer; step 6.2 (Process Review Feedback) extends the feedback table to three rows; step 6.4 wip-hygiene wording at lines 104-106 extends with the skill-implementation carve-out.

`skills/plan/SKILL.md` and the corresponding phase references change in three places: Phase 3's decomposition step grows a sub-step 3.6 "Cross-Issue Field Consistency Pre-Flight"; Phase 4's agent prompt enrichment adds a per-AC anchor-existence grep step; Phase 7's emission step grows a self-check against the canonical `## Implementation Issues` structure documented in `plan-format.md`.

`skills/scope/SKILL.md` changes in two places: Phase 0 grows a slug-prefix sampling step; Phase 1 grows a cold-start projected-PRD evaluation step and a framing-shift opener short-circuit.

### Format-reference files

`skills/design/references/design-format.md` is created. It contains the four-field frontmatter schema (status, problem, decision, rationale, with the optional `upstream:`, `spawned_from:`, and `motivating_context:` fields), the nine required-section list, the context-aware section table (Market Context, Required Tactical Designs, Upstream Design Reference), and the Implementation Issues ownership convention (table owned by `/plan`, populated during Phase 7 single-pr emission).

`skills/plan/references/plan-format.md` is created. It contains the PLAN frontmatter schema, the section list, and the canonical `## Implementation Issues` structure for single-pr emission (Issues Table with ID/Title/Status/Notes columns plus Mermaid dependency diagram). The validator's FC08 and FC11 checks dereference this file.

`skills/brief/references/brief-format.md` gains the R11 public-vs-private issue numbers grammar disambiguation, the R12 `motivating_context:` field documentation, and the R13 BRIEF Open-Questions closure surface naming sentence.

`skills/prd/references/prd-format.md` gains the R11 grammar disambiguation, the R12 field documentation, the R14 Decisions-and-Trade-offs convention statement, and the R16 competitive-findings vs competitive-analysis-as-artifact-type Content Boundaries distinction.

### Rust validator changes

`crates/shirabe-validate/src/checks.rs` gains three changes. The existing `check_schema` function extends to emit a SCHEMA-MISSING notice when `doc.schema.is_empty()`. A new `check_writing_style` function (FC10) reads the banned vocabulary list from `skills/writing-style/SKILL.md` at validate-time and emits notices for each banned-word match in the document body. A new `check_plan_section_structure` function (FC11) reconciles the emitted `## Implementation Issues` section structure against the canonical structure from `plan-format.md`.

`crates/shirabe-validate/src/validate.rs` registers the three new checks in the check dispatch order. The notice-level discharge (per FC08/FC09 PR #169/#167 precedent) preserves the existing exit-code semantics — the validator returns non-zero only when error-level checks fail; notice-level checks emit advisory output without flipping the exit code.

`crates/shirabe-validate/src/formats.rs` gains entries for the new `design/v1` and `plan/v1` schemas if not already present; the canonical structure for plan/v1's `## Implementation Issues` section is encoded as a struct the FC11 check reads.

### CLAUDE.md convention surface

The workspace-policy header `## Release Notes Convention: <path>` lands in CLAUDE.md (per-repo, with `docs/guides/` for shirabe). `/prd` Phase 0 and `/design` Phase 0 read the value when authoring adopter-obligation ACs. The CLAUDE.md header parallels the existing `## Repo Visibility:` and `## Planning Context:` headers; no new mechanism is introduced.

### Component interaction

The architecture has three top-level interaction surfaces. The pattern-level references are read by the SKILL.md citations and by the validator at validate-time; the SKILL.md citations are read by skill authors at edit-time and by readers at audit-time; the validator is invoked at commit-time and at PR-CI time. The interactions are read-only — references inform consumers; consumers do not feed back into references. The three batches in Decision 7's sequencing reflect this dependency direction.

## Implementation Approach

Three batches, sequenced top-down. Each batch is independently shippable; R31 backward compatibility holds at every batch boundary because the `parent_orchestration:` sentinel is the gating condition for every new fallback path (absent sentinel falls through to existing behavior).

**Batch 1 — pattern-level upstream.** Files: `references/parent-skill-pattern.md` (two new sections), `references/cli-version-preflight.md` (new file), `skills/design/references/design-format.md` (new file), `skills/plan/references/plan-format.md` (new file), `skills/brief/references/brief-format.md` (R11/R12/R13 edits), `skills/prd/references/prd-format.md` (R11/R12/R14/R16 edits), `skills/design/references/phases/phase-6-final-review.md` (R25 wording extension at lines 104-106), CLAUDE.md (R28 convention header). Estimated 6-8 implementation issues touching 8 files.

**Batch 2 — per-skill consumers.** Files: `skills/brief/SKILL.md`, `skills/prd/SKILL.md`, `skills/design/SKILL.md`, `skills/plan/SKILL.md`, `skills/vision/SKILL.md`, `skills/strategy/SKILL.md`, `skills/roadmap/SKILL.md`, `skills/work-on/SKILL.md` (sub-agent dispatch fallback subsections plus Resume Logic sentinel rows for the seven non-`/work-on` skills), `skills/scope/SKILL.md` (R27 Phase 0 sampling, R29 Phase 1 cold-start evaluation), `skills/design/references/phases/phase-6-final-review.md` (R21 third reviewer step 6.1, R19 budget rubric folded into the new reviewer), `skills/plan/SKILL.md` plus `skills/plan/references/phases/phase-3-decomposition.md` (R23 sub-step 3.6), `skills/plan/references/phases/phase-4-agent-generation.md` (R24 AC grep step), `skills/plan/references/phases/phase-7-creation.md` (R22 emission self-check), eval-fixture authoring references for R26. Estimated 12-16 implementation issues touching ~14 files.

**Batch 3 — validator extensions.** Files: `crates/shirabe-validate/src/checks.rs` (SCHEMA-MISSING extension, new check_writing_style FC10, new check_plan_section_structure FC11), `crates/shirabe-validate/src/validate.rs` (dispatch registration), `crates/shirabe-validate/src/formats.rs` (canonical structures). Estimated 3-4 implementation issues touching 3 files plus tests.

Total estimated implementation scope: 22-28 issues across ~25 files, distributed roughly 30% / 50% / 20% across the three batches.

## Security Considerations

The design produces and modifies markdown documentation files and extends the existing Rust validator crate with three notice-level checks. No new external input sources, no new network endpoints, no new download/extract/execute paths, no new filesystem permissions beyond what `shirabe validate` and the existing chain workflows already require, and no new Rust crate dependencies. Each new validator check reads from already-public canonical references (`skills/writing-style/SKILL.md` for FC10, `plan-format.md` for FC11, the artifact under validation for SCHEMA-MISSING).

Three bounded data-handling considerations are worth naming for downstream implementers:

- **The `motivating_context:` cross-repo reference field (R12).** The field accepts a reference (issue number or `owner/repo:path`) that MAY point at a private artifact from a public document. The field is metadata — the link target is referenced by identifier, not described. Public-repo readers see only the reference identifier, not the private content. The visibility-direction rules in `references/cross-repo-references.md` already cover this pattern; the R12 field documentation cites those rules so implementers preserve the boundary.
- **Verdict-preamble operating-context disclosure.** The serial-self-jury fallback (Decision 1) prescribes that verdict-artifact preambles surface the operating context (parallel-jury vs serial-self-jury) and the independence-loss caveat. The preamble is workflow metadata about how the jury ran; it does not contain private artifact content. The convention preserves audit-trail integrity without creating a new data-exposure surface.
- **Validator FC10 writing-style notice content.** The notice emits the banned word, the file path, and the line number. The content is derived from already-committed artifact text; no new exposure beyond what was already in the committed file. Workspaces that treat notices as errors will surface the violations at PR-CI time.

The CLI-version-preflight reference (R30) prescribes a `shirabe <subcommand> --help` probe that runs against the workspace's already-installed binary; the probe does not execute network calls, does not download external artifacts, and does not escalate permissions. The documented manual-sed-edit fallback path operates on the same files the failed subcommand would have touched.

No security-dimension findings require design changes. The boundaries above are workflow metadata, not data; the implementation proceeds.

## Consequences

### Positive

The pattern-level canonical contract for sub-agent dispatch fallback (Decision 1) and Resume Logic sentinel consultation (Decision 2) eliminates the drift surface the BRIEF named ("seven children with seven divergent restatements"). Future skill edits cite one canonical statement; cross-skill consistency is structural.

The format-reference materialization (Decision 3) closes the asymmetric-altitude debt across the four artifact types — `brief-format.md`, `prd-format.md`, `design-format.md`, `plan-format.md` all live at the same altitude and contain the same shape of clarifications. The validator's FC08 and FC11 checks dereference these files, so the format-reference contracts become machine-checkable.

The validator-vs-jury split (Decision 4) places each check at the surface where it executes most naturally — structural checks in Rust, mechanical greps in Rust, natural-language judgment in Phase 6 reviewers. The five-check coverage closes `tsukumogami/shirabe#157` (schema-field-present) and `tsukumogami/shirabe#158` (single-pr Implementation Issues drift) on the same surfaces that satisfy R18-R22.

The audit-trail fidelity the BRIEF named ("the chain's audit trail matches the chain's actual execution") falls out of the verdict-preamble discipline — every Phase 6 verdict file records the operating context (parallel-jury vs serial-self-jury) and the independence-loss caveat; every Resume Logic sentinel-consultation row preserves the parent's framing decision in the audit trail.

### Negative

The implementation scope is large — ~25 files touched across three batches, estimated 22-28 issues. The per-skill consumer batch (Batch 2) touches eight child SKILLs symmetrically; an error in the canonical pattern would propagate to all eight before being caught. Mitigation: Batch 1 (pattern-level upstream) ships first and is reviewed independently; Batch 2's citations are mechanical (the canonical statement is the truth, citations dereference).

The validator's three new checks (Batch 3) add maintenance surface — when the writing-style reference's banned vocabulary list changes, the FC10 check picks up the change at validate-time (no code change required), but the canonical reference paths themselves are hardcoded in the validator's check logic; a future relocation of `skills/writing-style/SKILL.md` requires a validator code change. Mitigation: the reference paths are stable per the v0.9.x cutover; the maintenance cost is real but bounded.

The two new format-reference files (`design-format.md`, `plan-format.md`) require a one-time migration of inline SKILL.md format prose. The migration must preserve the existing SKILL.md citations without losing content; this is detail-heavy work that benefits from review at the file-creation boundary.

### Mitigations

The three-batch sequencing isolates risk per layer — pattern-level edits ship and are reviewed before per-skill consumers; per-skill edits ship and are reviewed before validator extensions. Each batch can be reverted independently.

The notice-level discharge for all three validator checks (SCHEMA-MISSING, FC10, FC11) preserves backward compatibility — existing artifacts that don't conform to the new checks emit advisory notices but do not flip the exit code to non-zero. The workspace policy can promote notices to errors at its own pace once authors have had a window to clean up existing violations.

The `parent_orchestration:` sentinel as the gating condition for every new fallback path means R31 is structural — direct invocations (no parent dispatching, no sentinel) fall through to existing behavior at every new surface.


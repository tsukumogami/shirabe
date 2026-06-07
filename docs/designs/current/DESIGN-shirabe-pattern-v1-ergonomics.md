---
schema: design/v1
status: Current
upstream: docs/prds/PRD-shirabe-pattern-v1-ergonomics.md
problem: |
  PRD-shirabe-pattern-v1-ergonomics binds 32 requirements across seven clusters
  touching nine shirabe child SKILLs, the parent-skill-pattern reference, four
  format references (two of which don't yet exist at the canonical altitude),
  the `/design` Phase 6 jury, and the Rust validator. The PRD defers mechanism
  choice per fix-class; this design picks placement and mechanism per cluster
  while preserving R31 backward compatibility and R32 sequencing. Revised on
  reconsideration at the DESIGN-Accepted boundary to apply the lazy-load
  principle: every fix-class is preferentially resolved by the shirabe CLI
  deterministically (tier 1), or by CLI-detection emitting a pointer to a
  per-error reference file the agent loads only when the error fires
  (tier 2); eager-load skill prose (tier 3) is reserved for cases where
  tiers 1 and 2 are infeasible.
decision: |
  Three-tier lazy-load shape across the seven fix classes. Tier 1
  (CLI-deterministic): the validator extension surface absorbs schema-field
  detection (SCHEMA-MISSING), writing-style banned-word detection (FC10),
  PLAN/DESIGN field consistency (FC12), eval-fixture frontmatter-line-1
  detection (FC13), CLAUDE.md release-notes-convention header detection
  (FC-CONVENTIONS), slug-prefix detection extension (existing FC for /scope),
  and the structural plan-section-structure check (FC11). Tier 2 (CLI-detects
  + lazy-load pointer): a small set of well-known reference files at
  `references/fixes/` carry the non-deterministic resolution prose. The set
  is `sub-agent-dispatch.md` (covering both Decision-1 fallback shapes and
  Decision-2 sentinel-consultation), `plan-design-field-consistency.md`,
  `eval-fixture-frontmatter.md`, `claude-md-conventions.md`,
  `cli-version-preflight.md`. Each child SKILL gets at most a short
  detection-and-pointer row (Resume Logic) or a Phase-0 sentinel check
  with a pointer; no eager-loaded per-skill fallback prose. Tier 3
  (eager-load): only `/design` Phase 6 wip-hygiene carve-out (R25 — single
  rule clarification in design-format.md) and `/scope` Phase 1 cold-start
  projection (R29 — already in lazy-loaded phase-1-discovery.md). New
  format-reference files `design-format.md` and `plan-format.md`
  materialize at the canonical altitude; existing `brief-format.md` and
  `prd-format.md` gain seven per-field rulings; `/design` Phase 6 grows a
  third structural-format reviewer. Implementation sequences in four
  batches: CLI extensions → reference files → lightweight skill edits
  → tests.
rationale: |
  Lazy-load is the load-bearing principle. The earlier-chosen "eager-load
  per-skill subsection" shape (8 child SKILLs each carrying 30-60 lines
  of fallback prose; 7 children each carrying inline Resume Logic
  sentinel prose) optimized for grep-checkability against ACs but bloated
  agent context proactively for every possible failure regardless of
  whether the failure ever fires. The revised shape preferences
  CLI-deterministic detection (the agent never loads the reference unless
  the error fires) and per-error pointer references (the agent loads
  ~10-40 lines of resolution prose when and only when the CLI emits the
  pointer). Composability is preserved — one canonical reference file
  per fix class is the single source of truth, exactly as the original
  pattern-level canonical statement was, but the consumers are pointer
  rows rather than eager-loaded prose. R32 sequencing still falls out
  structurally because CLI extensions and reference files land before
  the skill-edit batch that references them. R31 backward compatibility
  still holds at every boundary because tier-1 checks are notice-level
  and tier-2 pointers only fire when the validator emits the FC code.
  The validator-vs-jury split places each check at its natural surface —
  structural and mechanical in Rust (now expanded to seven checks rather
  than three), natural-language judgment in Phase 6 reviewers — closing
  `tsukumogami/shirabe#157` and `tsukumogami/shirabe#158` on the surfaces
  that satisfy R18 and R17/R22 in the same edit.
---

# DESIGN: shirabe pattern v1 ergonomics

## Status

Current

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

Revised on reconsideration at the DESIGN-Accepted boundary (this commit and
the cascade commits that follow) to apply the lazy-load principle the user
named. Decisions 1, 2, 5, and 6 each grow a `Chosen-revised` option that
demotes the original "Chosen" to `Rejected on reconsideration` with rationale
citing the principle (mirror of PR-151's revision pattern). The Phase 6
jury did not catch the eager-load violation on the original pass; the
meta-friction is recorded in the friction log alongside the original
dogfooding entries.

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

- **Lazy-load over eager-load (revised driver).** Defensive mechanisms for failures that may never fire MUST NOT bloat the agent's context proactively. The three-tier preference order is: (1) the shirabe CLI detects AND fixes the problem deterministically, loading zero agent context; (2) the shirabe CLI detects and emits an FC code plus a pointer to a per-error reference file at a well-known path (`references/fixes/<class>.md`), and the agent loads that file only when the error fires; (3) eager-load skill prose is reserved for cases where (1) and (2) are infeasible. This driver is the load-bearing principle of the revised design; it demotes the original eager-load shapes named in the first pass of Decisions 1, 2, 5, and 6.

- **Cross-repo public-visibility cleanliness.** The repo is Public. The design references the inside-pattern Track A scope (this work) and the amplifier-layer Track B (tracked separately as a forward-looking effort) per the BRIEF's References section; no private paths, repos, or codenames appear in this document.

## Considered Options

### Decision 1: Sub-agent fallback section format

PRD R1-R8 commits the contract that every child SKILL with a Phase-N parallel-jury site, approval gate, nested-dispatch site, or koto state-machine loop SHALL surface a fallback path under sub-agent dispatch. The five named fallback shapes (serial-self-jury, parent-delegated-approval, decision-bypass, inline-substitute-review, deterministic-mode-bypass) recur across eight SKILLs (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`, `/work-on`). The placement question is where the canonical contract lives and how each child SKILL.md surfaces its specific binding. PRD D2 already fixes the serial-self-jury contract; this decision picks placement only.

Key assumptions: each child SKILL.md has a `### Critical Requirements` section that the fallback subsection can hang from (verified: `/brief` line 183, `/prd` line 116, `/design` line 181, `/plan` matching grep); the pattern reference at `references/parent-skill-pattern.md` is the right anchor (it's the existing canonical contract surface and already declares the `parent_orchestration:` sentinel mechanics at lines 181-206); the four canonical fallback shapes cover R1-R7 with R8's carve-out captured pattern-level once.

#### Chosen-revised: Two-layer lazy — one shared reference file plus a short Phase-0 detection-and-pointer step in each child

A single reference file `references/fixes/sub-agent-dispatch.md` carries the full prose for both Decision 1 (the five canonical fallback shapes) and Decision 2 (the parent-orchestration sentinel detection and resolution). The combined file replaces the per-class shape (two files / one big section / per-skill subsections) the original pass chose. Combining the two decisions into one resolution file is the cleaner shape on inspection: sentinel detection and fallback selection are causally linked (the sentinel's presence is what tells the child it's running as a sub-agent and which fallback shape applies); a reader who lands on the file via either pointer wants the other half a sentence later.

The reference file contains: (a) the five canonical fallback shapes with full prose (serial-self-jury with the verdict-preamble independence-loss caveat; parent-delegated-approval with the pre-approval-status hand-back; decision-bypass-with-inline-resolution with the two engagement conditions; inline-substitute-review with the recursion-bound carve-out; deterministic-mode-bypass with the three engagement conditions); (b) a per-skill binding table mapping each of the eight children (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`, `/work-on`) to its applicable fallback shape(s); (c) the parent_orchestration sentinel detection convention (which fields to read: `invoking_child`, `suppress_status_aware_prompt`, `rationale`); (d) the chain-handoff and status-transition resolution per rationale (fresh-chain / revise); (e) R8's NOT-covered carve-out paragraph naming the amplifier-layer Track B (tracked separately as a forward-looking effort).

Each child SKILL.md's Phase 0 (or earliest phase that reads state) grows a SHORT detection step (approximately three lines): "If the `parent_orchestration:` sentinel is present in the parent's state file (`wip/scope_<topic>_state.md` for tactical children, `wip/charter_<topic>_state.md` for strategic children), consult `references/fixes/sub-agent-dispatch.md` for the fallback shape applicable to this skill's phases." No per-skill `### Sub-Agent Dispatch Fallback` subsection is added; the reference file IS the canonical content. The detection lives in always-loaded skill prose (the Phase-0 line); the resolution is loaded on demand.

The runtime hook is the existing dispatch contract: per the upstream DESIGN-shirabe-child-dispatch-contract (Accepted), the parent writes the sentinel into the parent's state file before invoking the child via inline Skill-tool call; the child's Phase 0 already reads the parent's state file at child startup (Resume Logic, Slot 1). The detection-and-pointer step adds one read against an existing path; no new substrate primitive.

R32 sequencing still falls out structurally — the reference file lands in Batch 2 (reference files); per-skill detection-and-pointer steps land in Batch 3 (lightweight skill edits) which dereference the file. R31 backward compatibility still holds — the Phase-0 detection step short-circuits with no behavior change when the sentinel is absent (direct invocation), exactly as the original-pass shape did.

#### Rejected on reconsideration: Pattern-level canonical section plus per-skill citations

A new section `## Sub-Agent Dispatch Fallbacks` lands in `references/parent-skill-pattern.md` after the existing `## Team-Lead Operating Discipline` section. The section names five canonical fallback shapes — serial-self-jury (parallel-jury substitute, verdict-preamble names the operating context and the independence-loss caveat), parent-delegated-approval (approval-gate substitute, child leaves artifact at pre-approval status), decision-bypass-with-inline-resolution (per-decision-dispatch substitute when the upstream PRD enumerates alternatives and recommends a direction, conditions are PRD-names-alternatives AND reviewer-count-acceptable-inline), inline-substitute-review (nested-sub-skill substitute when recursive dispatch isn't available), deterministic-mode-bypass (koto state-machine substitute when parent supplies decomposition + cascade timing + push timing upfront). A closing paragraph names R8's NOT-covered carve-out (amplifier-layer Track B, tracked separately as a forward-looking effort; nested-team spawning is not addressed).

Each child SKILL.md grows a `### Sub-Agent Dispatch Fallback` subsection under its existing `### Critical Requirements` section. The subsection is 4-8 lines and cites the pattern-level reference with the skill-specific binding. The eight per-skill bindings are summarized in a binding table in the Solution Architecture below.

R32 sequencing falls out structurally — the pattern-level section is the upstream change, the per-skill citations are downstream consumers. R31 backward compatibility is preserved — the section describes sub-agent behavior gated on the `parent_orchestration:` sentinel; direct-invocation paths are unchanged.

*Rejected on reconsideration.* Even at 4-8 lines per child times 8 children, the per-skill subsections eager-load defensive prose for every possible failure into every agent context regardless of whether the failure ever fires. The lazy-load principle (added to the Decision Drivers during the DESIGN-Accepted re-review) names this exact failure shape — agents should load resolution prose only when the validator emits the pointer. The original pass's "composability via pattern-level canonical statement" framing was correct on the canonicalization axis but wrong on the loading axis; the revised shape preserves the canonical-source-of-truth property (one reference file is still the only source) while ditching the eager-load consumer surface. The mirror of PR-151's Option-2D demotion: the original pass undervalued the per-invocation context cost.

#### Alternatives Considered

**Inline-only per-skill sections, no pattern-level section**: each child SKILL.md restates the full contract. Rejected because composability fails — seven children with seven slightly-divergent restatements of the same contract is the failure shape the BRIEF named. Drift between children is inevitable; the BRIEF's "audit trail matches execution" outcome degrades when two children describe the same fallback in two different ways.

**Pattern-level section only, no per-skill mention**: children inherit by virtue of the pattern reference being cited at the top of each SKILL.md. Rejected because AC1.1, AC1.3, AC1.4, AC1.5, AC1.6, AC1.7, AC1.8 explicitly require sections in each of the eight child SKILLs. An AC grep against the SKILL files finds nothing and the ACs fail. Skill-specific bindings (which phase fans out, which approval gate exists, which sub-skill is dispatched) cannot be inferred from the pattern reference alone — that data is per-skill.

### Decision 2: Resume Logic sentinel-consultation row format

PRD R9 requires each child Resume Logic table to consult the `parent_orchestration:` sentinel before evaluating wip/-file-existence rows; R10 requires the pattern-level reference to describe the convention. The seven affected children are `/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`. Current Resume Logic tables (verified at `skills/brief/SKILL.md:170-181`, `skills/prd/SKILL.md:105-114`, `skills/plan/SKILL.md:250-265`, `skills/design/SKILL.md:167-179`, plus the three strategic children) do not consult the sentinel.

Key assumptions: every affected child has a code-fenced Resume Logic table where "row" means "line"; the pattern-level `## Conditional Feeder Invocation Shape` section is the right anchor because it already discusses the `parent_orchestration:` block at lines 181-206; the parent state file paths are `wip/scope_<topic>_state.md` for tactical-chain children and `wip/charter_<topic>_state.md` for strategic-chain children.

#### Chosen-revised: Single Resume-Logic pointer row per child plus merged-with-Decision-1 reference file

The detection lives in each child's Resume Logic table as a single new first row whose predicate is "`parent_orchestration:` sentinel present in <state-file-path>" and whose action is "see `references/fixes/sub-agent-dispatch.md`" — no inline behavior prose, no field-list inline. The row is detection-only; the resolution (chain handoff, status transitions, fallback shapes, which subfields to read) lives in the reference file and is loaded only when the row fires.

The reference file `references/fixes/sub-agent-dispatch.md` (the same file Decision 1 lands; the two decisions merge into one resolution surface) covers: the three subfields the child reads (`invoking_child`, `suppress_status_aware_prompt`, `rationale`); the routing action per rationale (`fresh-chain` vs `revise`); the per-skill state-file-path table mapping seven children to `wip/scope_<topic>_state.md` (tactical) or `wip/charter_<topic>_state.md` (strategic); the fallback-shape selection per child phase; and absent-sentinel fall-through behavior.

The detection-and-resolution merge across Decisions 1 and 2 was the natural shape on inspection — the sentinel is the same entity that triggers the fallback-shape selection. A reader who lands on the file via the Resume Logic row pointer wants the same content a reader who lands via the Phase-0 detection step in Decision 1 wants. One file, two entry points, one source of truth.

R31 backward compatibility falls out structurally — absent sentinel falls through to the existing first row (the new row's predicate is false), behavior identical to current direct-invocation. R32 sequencing falls out structurally — the reference file lands in Batch 2 upstream of the per-skill pointer-row edits in Batch 3. Cross-skill consistency falls out by construction — every child's pointer row has the same shape (predicate + one-line pointer to the canonical file).

The agent's loaded context under sub-agent dispatch is bounded by the file's ~50-line resolution prose, not by the (8 children × 30-60 lines = 240-480-line) cumulative cost of per-skill eager-loaded subsections plus inline Resume Logic prose the original-pass shape would impose.

#### Rejected on reconsideration: First-row sentinel-consultation in each child plus pattern-level convention subsection

Every child Resume Logic table grows a new first row (above all existing rows). The row predicate is "parent_orchestration: sentinel present in <state-file-path>"; the action is "read invoking_child, suppress_status_aware_prompt, rationale; route per rationale (fresh-chain | revise)". When the sentinel is absent, the row falls through to the existing first row and existing behavior holds. The three subfields are named in the row's prose so an AC grep finds them.

The pattern-level convention lives in a new subsection `### Child-Side Sentinel Consultation Row Convention` inside `references/parent-skill-pattern.md`'s existing `## Conditional Feeder Invocation Shape` section. The subsection states the row contract and provides the canonical row template each child copies verbatim. A per-skill state-file-path table maps each child to its parent's state-file path.

R31 backward compatibility falls out structurally — absent sentinel falls through to the existing first row, behavior identical to current direct-invocation. R32 sequencing falls out structurally — the pattern-level subsection edit is upstream of the seven per-skill row edits. Cross-skill consistency falls out by construction — every child copies the same canonical row template.

*Rejected on reconsideration.* The original pass inlined the three subfield reads and the routing action into every child's Resume Logic row prose — seven copies of the same content, eager-loaded into every child invocation. The lazy-load principle (added to Decision Drivers during the DESIGN-Accepted re-review) names this as the failure shape: the resolution prose belongs in a reference file loaded on demand, not inline in seven SKILL.md files. The pointer-row shape preserves the grep-checkability AC2.1 commits to (the row exists in each child) while satisfying the lazy-load driver. The mirror of PR-151's Option-2D demotion applies again: pattern-level convention subsection at one canonical location was already a single source of truth, but the consumers were inline and eager. The revised consumer is a single pointer line.

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

#### Chosen-revised: Mixed tier-1 CLI-detection plus tier-2 per-error pointers; tier-3 reserved for the narrow rule clarification only

R23 (PLAN/DESIGN field consistency pre-flight) lands as a validator extension — a new FC12 check that greps for field-name conflicts across the PLAN's issue ACs and the DESIGN's structural rubrics, emitting an FC12 notice with a pointer to `references/fixes/plan-design-field-consistency.md`. The non-deterministic part (which side to align to, when to rewrite vs revise, when the conflict is intentional) is the resolution prose loaded only when FC12 fires; the deterministic part (detecting field-name collisions across two artifacts) is in the validator. Pure tier-1 detection + tier-2 resolution pointer; no `/plan` Phase 3 sub-step 3.6 added.

R24 (AC anchor-existence) stays in `/plan` Phase 4 agent prompt as the original pass placed it — but the placement is now justified explicitly: the check is a per-AC test at generation time, not a per-artifact check at validate time, and the validator does not have visibility into AC-generation-time intent. The Phase 4 prompt edit is a few lines (small enough to not bloat agent context); the agent already loads phase-4-agent-generation.md (lazy-loaded by /plan). Tier-3 acceptable here because tiers 1 and 2 are infeasible without a substrate primitive the workspace doesn't have.

R25 (wip-hygiene carve-out) lands inline in `design-format.md` (the new format reference Decision 3 materializes) as a single rule clarification. The carve-out is a one-sentence wording extension; eager-loading a one-sentence rule clarification has near-zero context cost. Tier-3 acceptable; the rule is small enough to stay inline.

R26 (eval-fixture HTML-comment marker placement) lands as a validator extension — a new FC13 check that detects frontmatter parse failure due to line-1 comment placement, emitting an FC13 notice with a pointer to `references/fixes/eval-fixture-frontmatter.md`. The deterministic part (detecting `<!--` on line 1 before `---`) is in the validator; the resolution prose (where to place the marker — inside frontmatter or after closing `---`) is in the reference file, loaded only when FC13 fires. Tier-2.

The placement choices compose into the four-tier shape: R23 is tier-1+2 (CLI detects, file resolves); R24 is tier-3 (skill prose, but already lazy-loaded by phase reference); R25 is tier-3 (single-sentence rule extension); R26 is tier-1+2 (CLI detects, file resolves). Two of four checks move from eager-load skill prose to CLI-deterministic detection plus per-error pointer; the other two stay tier-3 only because tier-1/2 are infeasible, not because tier-3 was preferred.

#### Rejected on reconsideration: Four rule placements per the natural fire point of each rule

R23 lands as `/plan` Phase 3 sub-step 3.6 (Cross-Issue Consistency Pre-Flight). Phase 3 is where issue outlines are first drafted; folding the check into Phase 3 catches collisions at the earliest point. A separate Phase 3.5 (Option A in the decision report) adds a phase count the PRD doesn't require; Phase 7 (Option B) catches the collision after agent generation has already run against contradictory specs.

R24 lands as `/plan` Phase 4 agent-prompt enrichment. AC anchor-existence is per-issue; the natural fire point is when the AC is being generated, in the agent prompt. The prompt step: for each AC claiming "annotation only" or "schema fields unchanged", grep the target file at PLAN-authoring time; if the anchor exists, the AC remains; if absent, the AC is rewritten defensively ("annotation added; if anchor missing, this issue includes the minimal anchor definition").

R25 lands as a wording extension at `skills/design/references/phases/phase-6-final-review.md:104-106`. The existing rule disallows wip/... paths in committed artifacts except for "quoted statements OF the wip-hygiene rule itself"; the extension adds "or documentation of a skill's runtime wip/ usage (i.e., a DESIGN, PRD, or BRIEF describing a skill's wip/-file contract for skill-implementation purposes)". The "skill-implementation purposes" qualifier prevents the carve-out from being abused for non-skill-implementation DESIGNs that happen to mention wip/.

R26 lands as an eval-fixture authoring convention update. The conflict (HTML-comment line-1 markers vs frontmatter parser's `---`-first-non-blank-line requirement) resolves by forbidding line-1 markers; fixtures place markers either inside a frontmatter field value or after the closing `---` as the first body line. The convention lives in `skills/plan/references/templates/` (the closest existing eval-fixture authoring reference location) plus any eval-authoring SKILL prose that prescribes the marker.

*Rejected on reconsideration.* The original pass placed R23 as `/plan` Phase 3.6 prose and R26 as eval-fixture authoring convention prose — both surfaces that the agent eagerly loads when running `/plan` regardless of whether the field-conflict or marker-placement failure ever fires. The lazy-load principle (added to Decision Drivers) names CLI-deterministic detection plus per-error pointer as preferred over eager-load skill prose when both are feasible; both R23 and R26 are deterministic-detection-feasible (the validator can grep field names across artifacts and detect `<!--` on line 1 mechanically). R24's tier-3 placement survives the re-review because tiers 1 and 2 are infeasible without substrate primitives the workspace lacks; the survival is justified explicitly. R25's tier-3 placement survives because the single-sentence rule clarification has near-zero context cost; eager-loading it does not violate the principle in practice.

#### Alternatives Considered

**R23 as a separate Phase 3.5 between Decomposition and Generation**: adds a phase count the PRD doesn't require. Rejected — folding into Phase 3 reuses existing scope.

**R24 at Phase 3 (Decomposition) or Phase 7 (Creation)**: Phase 3 is too early (decomposition doesn't yet have AC text); Phase 7 is too late (issues are about to be filed). Rejected — Phase 4 is the natural fire point.

**R25 case-by-case judgment instead of mechanical rule extension**: leaves the rule unchanged and relies on Phase 6 reviewer judgment. Rejected because case-by-case judgment is the failure mode the BRIEF named (silent degradation under operator judgment); a mechanical and grep-checkable wording extension is more reliable.

**R26 frontmatter parser tolerates a single HTML-comment before `---`**: changes the validator's input contract; existing artifacts placing `---` on line 1 would still parse but the rule "leading content is ignored" introduces new ambiguity. Rejected — the documentation-side fix is lower-risk and preserves the validator's existing contract.

### Decision 6: Convention updates and CLI version-skew preflight

PRD Cluster 6 (R27-R29) plus Cluster 7 (R30) prescribe four convention updates: `/scope` Phase 0 slug-prefix detection (R27), release-notes adopter-doc location convention (R28), `/scope` Phase 1 R6 cold-start projected-PRD evaluation plus framing-shift opener short-circuit (R29), CLI version-skew preflight prose mechanism (R30). PRD D3 commits R30 as a skill-prose contract.

Key assumptions: `/scope` Phase 0 has the chain-entry slug-validation step (verified existing); CLAUDE.md is the workspace-policy surface for per-repo conventions (parallels existing `## Repo Visibility:` and `## Planning Context:` conventions); the `references/` directory at the worktree root holds shared cross-skill references (parallels existing `worktree-discipline.md`, `wip-hygiene.md`).

#### Chosen-revised: Four placements per the lazy-load three-tier preference order

R27 (slug-prefix detection) is already principle-aligned and stays as `/scope` Phase 0 sampling step — but the sampling now lives in the shirabe CLI as a tier-1 extension. The CLI sub-command (e.g., `shirabe scope detect-prefix`, invoked by /scope Phase 0) does the sampling and prefix-extraction deterministically and returns the detected prefix (or "no convention detected"); /scope Phase 0 calls the sub-command and, when the input slug lacks the detected prefix, emits a structured pointer to the agent. If the CLI cannot be extended in this batch (the existing CLI extension surface in `crates/shirabe-validate` is validate-focused; adding a `detect-prefix` would require new module structure), the deterministic logic alternatively lands in `shirabe validate`'s existing convention-check vocabulary as a notice. Tier-1 detection; resolution (prompting the author about the prefix mismatch) is interactive and stays in /scope.

R28 (release-notes convention) lands as a validator extension — a new FC-CONVENTIONS check (or a CLAUDE.md-headers sub-check folded into the existing schema/visibility check vocabulary) that detects missing or malformed `## Release Notes Convention: <path>` header in CLAUDE.md at the relevant invocations (when /prd or /design Phase 0 authoring would consult it). The detection emits a notice with a pointer to `references/fixes/claude-md-conventions.md` containing the resolution prose (the recommended header format, the per-repo default, the cross-reference to other CLAUDE.md conventions). The CLAUDE.md convention header itself is a one-line addition; the resolution prose is loaded only when the validator emits the pointer. Tier-2.

R29 (cold-start projected-PRD evaluation) cannot be detected by the validator — "cold-start projection needed" is a workflow concern (does the /scope chain need to fire /design tentatively?) not a doc-state concern (is the doc shape correct?). The validator does not have visibility into chain-orchestration intent at validate time. R29 stays as Phase 1 prose in `phase-1-discovery.md` (already lazy-loaded by /scope) — but the prose is TRIMMED to the minimum the workflow logic requires (the projection-keyword list, the post-`/prd` re-evaluation gate, the framing-shift opener short-circuit). Tier-3 acceptable because tiers 1 and 2 are infeasible without a substrate primitive the workspace doesn't have; the survival is justified explicitly.

R30 (CLI version-skew preflight) lands as a new shared reference `references/fixes/cli-version-preflight.md` (renamed from the original `references/cli-version-preflight.md` to live under the per-error reference directory, matching the other fixes/ files). Each child SKILL that prescribes a `shirabe` subcommand emits a structured pointer to this file when the preflight detects subcommand absence. The preflight itself is a one-line probe (`shirabe <subcommand> --help`); the resolution prose (the manual sed-edit fallback per-subcommand) is loaded only when the probe fails. Tier-2.

The placement choices compose into the four-tier shape: R27 is tier-1 (CLI extends with detection); R28 is tier-1+2 (CLI detects, file resolves); R29 is tier-3 (already lazy-loaded by phase reference, prose trimmed); R30 is tier-2 (the preflight probe is the detection, the reference file is the resolution).

#### Rejected on reconsideration: Four placements per the natural surface of each convention

R27 lands as a `/scope` Phase 0 sampling step. The step samples `docs/briefs/BRIEF-*.md`, `docs/prds/PRD-*.md`, `docs/designs/DESIGN-*.md`, `docs/plans/PLAN-*.md` filenames; extracts the first hyphenated word after the artifact-type prefix; counts occurrences; if >50% of artifacts share a prefix, treats it as detected. When the input slug lacks the detected prefix, Phase 0 prompts the author before committing any durable artifact.

R28 lands as a CLAUDE.md convention `## Release Notes Convention: <path>` (e.g., `docs/guides/` for shirabe, or per-repo value). `/prd` and `/design` read the convention at Phase 0 and use it when authoring adopter-obligation ACs. Reading from CLAUDE.md preserves per-repo flexibility — different repos use different conventions; hardcoding breaks portability.

R29's two parts land in `/scope` Phase 1. The R6 cold-start projected-PRD evaluation: when cold-start is detected (no PRD body exists), Phase 1 projects the expected PRD content shape by inspecting upstream artifacts (BRIEF, ROADMAP) for keywords ("alternatives", "mechanism", "choices", "trade-offs") in User Journeys and Problem Statement sections; tentatively fires `/design` when matches are found. A post-`/prd` re-evaluation gate runs after `/prd` lands and re-evaluates R6 against the actual PRD body; if the PRD doesn't surface alternatives, `/design` is skipped and a `chain_revised` record is written to `/scope`'s state file. The framing-shift opener short-circuit: when topic-related child-doc discovery returns empty (cold-start), the opener is skipped and Phase 1 proceeds to the regular scope conversation.

R30 lands as a new shared reference `references/cli-version-preflight.md` with per-skill citations. The reference describes a per-subcommand preflight contract (using `shirabe <subcommand> --help` as the capability detection probe). Each child SKILL.md that prescribes a `shirabe` subcommand (`shirabe transition` is the main affected one per the PRD's Known Limitations) cites the reference and names its specific subcommand and documented fallback. The sed-edit fallback (per the PRD's Known Limitations) is the documented manual operation when the preflight fails.

*Rejected on reconsideration.* The original pass mixed CLI-detection (R27 slug-prefix sampling, R28 CLAUDE.md header read) with prose-only mechanisms in places where CLI-detection was actually feasible (R28 missing-header detection, R30 preflight invocation). The lazy-load principle (added to Decision Drivers) names CLI-deterministic detection as preferred over eager-load skill prose; the original-pass shape did not consistently apply this preference. R29's prose survives the re-review because the workflow-projection logic cannot be reduced to doc-state detection by the validator; the survival is justified explicitly. R27 and R30's tier-1/tier-2 shifts increase composability across the conventions — every detection at the CLI surface, every resolution in a per-error reference file at `references/fixes/`.

#### Alternatives Considered

**R27 per-child detection in each SKILL**: each child does its own sampling. Rejected — `/scope` is the chain-entry that names the topic; children inherit the topic; per-child detection is redundant.

**R28 hardcode docs/guides/ in skill prose**: each skill hardcodes the path. Rejected because the workspace runs multiple repos with different conventions; hardcoding breaks portability.

**R29 always-fire `/design` under cold-start**: simpler default that includes `/design` whenever the PRD body is absent. Rejected because it over-includes `/design` for topics that don't have architectural alternatives, defeating R6's existence.

**R30 inline shell-snippet in each SKILL.md**: each SKILL.md prescribing a `shirabe` subcommand inlines the preflight + sed fallback. Rejected because inlining duplicates the pattern across seven SKILLs; the shared reference + per-skill citations preserves composability.

**R30 parent-skill inheritance — `/scope`/`/charter` do the preflight once at chain entry**: parent's Phase 0 runs `shirabe --version` and stores the version in the parent state file; children read the version. Rejected because the version-skew fires per-subcommand-invocation, not per-chain-entry; children invoked directly don't have a parent state file to inherit from.

### Decision 7: Sequencing and migration ordering

PRD R32 names sequencing constraints inherent to the cluster set — pattern-level reference edits (R10, R13, R14, R16) land before per-skill consumers; validator extensions (R18-R22) land alongside or after prose changes that reference them. R31 requires backward compatibility at every boundary. AC8.2 requires sequencing respect R32 explicitly.

Key assumptions: the dependency-graph is structural — per-skill citations that point at non-existent pattern-level sections are broken links; validator checks that dereference canonical references (FC10 reads writing-style SKILL; FC11 reads plan-format.md) error at runtime if the references don't exist.

#### Chosen-revised: Four-batch ordering — CLI extensions, reference files, lightweight skill edits, tests

The revision-cascade-after-the-DESIGN-Accepted-review changes Batch shape from three to four batches. The new shape isolates CLI-extension work (Batch 1), reference-file authoring (Batch 2), lightweight skill edits — pointer rows and Phase-0 detection lines (Batch 3), and tests including validator-pointer-resolution tests (Batch 4).

**Batch 1 — CLI extensions.** Validator FC codes for FC10 (writing-style banned-words), FC11 (plan-section-structure), FC12 (PLAN/DESIGN field consistency), FC13 (eval-fixture frontmatter-line-1 detection), FC-CONVENTIONS (CLAUDE.md headers schema-field check), SCHEMA-MISSING extension on check_schema, plus the slug-prefix-detection CLI extension (R27, as either a new `shirabe scope detect-prefix` sub-command or as a validate-time notice). Estimated 5-7 implementation issues touching ~5 files in `crates/shirabe-validate/src/` plus a possible new module if R27 lands as a new sub-command.

**Batch 2 — reference files.** Authoring of: `references/fixes/sub-agent-dispatch.md` (Decision 1 + Decision 2 combined resolution file), `references/fixes/plan-design-field-consistency.md` (Decision 5 R23 resolution), `references/fixes/eval-fixture-frontmatter.md` (Decision 5 R26 resolution), `references/fixes/claude-md-conventions.md` (Decision 6 R28 resolution), `references/fixes/cli-version-preflight.md` (Decision 6 R30 resolution). Plus the two format-reference materializations: `skills/design/references/design-format.md` (Decision 3 + R25 wip-hygiene carve-out inline) and `skills/plan/references/plan-format.md` (Decision 3 + R17 canonical Implementation Issues structure). Estimated 7 implementation issues, one per file.

**Batch 3 — lightweight skill edits.** Per-skill detection-and-pointer rows (single Resume Logic row per child consulting the parent_orchestration sentinel and pointing to `references/fixes/sub-agent-dispatch.md`; single Phase-0 detection line per child) across the eight applicable children. The /scope Phase 0 slug-prefix detection step body. The brief-format.md and prd-format.md per-field clarification edits (R11/R12/R13/R14/R16). The /design Phase 6 third-reviewer addition (R21). The /plan Phase 4 AC anchor-existence prompt edit (R24). The /scope Phase 1 cold-start projection trim (R29). Estimated 10-13 implementation issues touching ~12 files.

**Batch 4 — tests.** Test cases for new FCs (FC10, FC11, FC12, FC13, FC-CONVENTIONS, SCHEMA-MISSING extension). Tests for the validator-pointer-resolution flow (when the validator emits an FC code with a pointer, the agent loads the pointed-at file and applies the documented resolution). Estimated 2-3 issues touching test files in `crates/shirabe-validate/tests/`.

R31 backward compatibility holds at every batch boundary because tier-1 checks are notice-level (advisory only, exit-code unchanged) and tier-2 pointers only fire when the validator emits the FC code — direct invocation under a clean artifact still falls through to existing behavior. R32 sequencing still falls out structurally: Batch 1 lands CLI infrastructure that Batch 2's reference files dereference at validate-time; Batch 3's skill edits dereference both Batch 1's FC codes and Batch 2's reference files; Batch 4 tests dereference all three upstream batches.

**Expected issue count reduction.** The original-pass three-batch shape estimated 22-28 issues. The revised four-batch shape concentrates work in CLI and reference files rather than per-skill prose; per-skill consumer prose drops from ~16 issues (one per SKILL.md × 8 plus phase references) to ~6 issues (pointer-row + Phase-0-line edits). Net estimate: 15-18 issues, with more weight in Batch 1 (CLI) and Batch 2 (reference files) and less in Batch 3 (skill edits).

#### Rejected on reconsideration: Three-batch ordering with pattern-level upstream, per-skill middle, validator downstream

Batch 1 (pattern-level upstream) contains Decision 1's `## Sub-Agent Dispatch Fallbacks` section in `parent-skill-pattern.md`, Decision 2's `### Child-Side Sentinel Consultation Row Convention` subsection in the same file, Decision 3's format-reference materialization (`design-format.md`, `plan-format.md`) plus R11/R13/R14/R16 edits to brief-format/prd-format, Decision 5's R25 wip-hygiene carve-out wording extension, Decision 6's R28 CLAUDE.md convention addition, Decision 6's R30 new shared reference `cli-version-preflight.md`. Estimated 6-8 implementation issues touching 8 files.

Batch 2 (per-skill consumers) contains Decision 1's per-skill section additions to all 8 child SKILLs, Decision 2's per-skill Resume Logic row additions to all 7 child SKILLs, Decision 3's per-skill citations, Decision 5's R23/R24/R26 skill-prose edits, Decision 6's R27/R29/R30 skill-prose edits, Decision 4's R21 Phase 6 structural-format reviewer addition (prose-only), Decision 4's R22 `/plan` Phase 7 emission self-check (prose-only). Estimated 12-16 implementation issues touching ~14 files.

Batch 3 (validator extensions, downstream of prose) contains Decision 4's R18 `check_schema` extension, Decision 4's R20 new FC10 writing-style check, Decision 4's R22 new FC11 plan-section-structure check. Estimated 3-4 implementation issues touching 3 files in `crates/shirabe-validate`.

R31 backward compatibility holds at every batch boundary because the sentinel is the entry condition — Batch 1 adds the contract but no consumer fires; Batch 2 adds consumers that fire when the sentinel is present (absent direct-invocation calls fall through unchanged); Batch 3 adds validator notices that surface advisory warnings without breaking existing artifacts.

*Rejected on reconsideration.* The original-pass three-batch shape concentrated the heaviest work in Batch 2 (per-skill consumers, 12-16 issues, 8 SKILL.md files each gaining a fallback subsection and 7 Resume Logic tables each gaining inline sentinel-consultation prose). The revised lazy-load shape rebalances by moving that work into CLI extensions and reference files (loaded on demand), reducing the per-skill consumer batch from 12-16 issues to ~10. The validator-after-prose ordering rationale (R32) is preserved by the new Batch 1 → Batch 2 → Batch 3 ordering — CLI extensions ship first because reference files dereference FC codes, and skill edits ship after because they cite both. The earlier ordering's "validator downstream of prose" property was the right idea on the dependency-direction axis but undersized the validator's expanded role in the revised shape.

#### Alternatives Considered

**Two-batch ordering — collapse Batches 2 and 3**: validator and skill-prose ship together. Rejected because R32 names validator-after-prose explicitly; the three-batch ordering makes the "after" branch concrete and reduces risk (if a validator extension misfires under unexpected artifact shapes, Batch 3 can be reverted independently of the prose changes).

**Single-batch ordering — everything ships together**: rejected as violating R32. Per-skill citations must reference an existing pattern-level statement; the pattern-level edit must land first.

## Decision Outcome

**Chosen-revised: 1-Lazy-pointer + 2-Pointer-row-merged-with-1 + 3-Materialize-format-refs + 4-Five-check-split + 5-Mixed-CLI-tier1+tier2 + 6-Lazy-tier-shifts + 7-Four-batch**

(The original-pass combination — `1-Pattern-canonical + 2-First-row-sentinel + 3-Materialize-format-refs + 4-Five-check-split + 5-Natural-fire-points + 6-Natural-surfaces + 7-Three-batch` — is preserved in the individual Decision sections under `Rejected on reconsideration` for revision-history legibility.)

### Summary

The design lands a lazy-load shape across the seven pattern-v1 fix classes: every fix is preferentially resolved by the shirabe CLI deterministically (tier 1), or by CLI-detection emitting a pointer to a per-error reference file the agent loads only when the error fires (tier 2); eager-load skill prose (tier 3) is reserved for cases where tiers 1 and 2 are infeasible. The validator extension surface absorbs seven detection checks (SCHEMA-MISSING, FC10 writing-style, FC11 plan-section-structure, FC12 PLAN/DESIGN field consistency, FC13 eval-fixture frontmatter-line-1, FC-CONVENTIONS CLAUDE.md headers, slug-prefix detection); five reference files at `references/fixes/` carry the non-deterministic resolution prose (`sub-agent-dispatch.md` covering Decisions 1+2 merged, `plan-design-field-consistency.md`, `eval-fixture-frontmatter.md`, `claude-md-conventions.md`, `cli-version-preflight.md`). Each child SKILL gets at most a short detection-and-pointer row (single Resume Logic row pointing at `references/fixes/sub-agent-dispatch.md`) plus a one-line Phase-0 sentinel detection step; no per-skill eager-loaded fallback prose. Two new format-reference files (`design-format.md`, `plan-format.md`) materialize at the canonical altitude; the existing `brief-format.md` and `prd-format.md` gain seven per-field clarifications; `/design` Phase 6 grows a third structural-format reviewer; `/plan` Phase 4 grows the AC anchor-existence prompt; `/scope` Phase 1 trims the cold-start projected-PRD evaluation prose.

The contract surface enforces operator trust at every boundary the BRIEF named — verdict-artifact preambles surface the operating context and independence-loss caveat (resolution prose lives in the fixes file, loaded on demand); pointer rows consult the sentinel before existing wip/-file rows; FC notices catch DESIGN sections that overshoot prose-named budgets, banned-word usage, field consistency conflicts, CLAUDE.md convention drift, eval-fixture frontmatter placement violations; CLI-version preflight catches subcommand absence before the skill's prescribed call fails open. Direct-invocation behavior is preserved at every boundary because the sentinel (absent under direct invocation) is the gating condition for every new fallback path AND because tier-1 checks are notice-level.

The implementation sequences in four batches: CLI extensions → reference files → lightweight skill edits → tests. CLI extensions ship first because reference files dereference FC codes; reference files ship second so skill edits can cite both; tests ship last to verify the full validator-pointer-resolution flow. R31 backward compatibility holds at every batch boundary. The total implementation is estimated at ~15-18 issues touching ~17 files — fewer than the original-pass 22-28-issue estimate because per-skill consumer prose is replaced by pointer rows that the validator dereferences.

### Rationale

The decisions reinforce each other through the lazy-load principle: every silent-degradation surface the BRIEF named has a contract-surface either in the validator (tier 1, no agent context) or in a per-error reference file at `references/fixes/` (tier 2, loaded on demand). Decision 1 and Decision 2 merge into one resolution file (`references/fixes/sub-agent-dispatch.md`) because the sentinel triggers fallback-shape selection — the two are causally linked. Decision 3's format-reference materialization is the upstream that Decision 4's R21 structural-format reviewer and R22 FC11 check both depend on; the materialization is still required because the format references serve as the validator's truth-source-of-canonical-structure (FC11 dereferences plan-format.md at validate-time; the structural-format reviewer dereferences design-format.md at jury-time). Decision 5 and Decision 6 trade the original-pass mix of skill-prose placements for a mixed CLI-tier-1 + tier-2 placements wherever deterministic detection is feasible; tier-3 only survives where the workflow concern cannot be reduced to doc-state detection (R24 AC anchor-existence at generation time; R29 cold-start projection at chain-orchestration time).

The seven-check expansion in Decision 4 (validator for structural, mechanical, and the new tier-1 detections) reflects the lazy-load principle's preference order: CLI-deterministic detection comes first because no agent context is loaded; per-error pointers come second because the agent loads only what the validator points to; eager-load skill prose is last because the agent loads the prose unconditionally. The Phase 6 reviewer set still grows from two to three because the structural-format judgment is natural-language (matching against design-format.md's content rules), not mechanical; the validator surface is wrong for natural-language judgment.

The reference-file canonical statements (Decisions 1 + 2 merged) preserve the original-pass composability win — one source of truth across the eight children — while replacing the eager-loaded per-skill consumer surface with pointer-only rows. Future skill edits dereference the canonical file; drift between skills is structurally impossible because there's still one source of truth, and the consumer's context cost drops from cumulative-of-eight to zero-until-the-pointer-fires.

The mirror of PR-151's Option-2D demotion holds across the four revised decisions: the original pass found the right canonical-location property (one source of truth) but undersized the per-invocation context cost of eager-loaded consumer surfaces.

## Solution Architecture

The revised architecture lands in five surfaces: the Rust validator (`crates/shirabe-validate/`), the per-error reference directory (`references/fixes/`), format-reference files (`skills/<name>/references/<name>-format.md`), per-skill SKILL.md and phase-reference files (`skills/<name>/`), and the CLAUDE.md convention surface. The shape mirrors the lazy-load tier order: tier-1 checks land in the validator, tier-2 resolution prose lands in `references/fixes/`, tier-3 prose lands in SKILL/phase references; the CLAUDE.md surface is the operator-visible convention header.

### Rust validator changes (tier 1)

`crates/shirabe-validate/src/checks.rs` gains the following functions and extensions:

- **SCHEMA-MISSING extension** on the existing `check_schema` function (R18; closes `tsukumogami/shirabe#157`). When `doc.schema.is_empty()`, emit a SCHEMA-MISSING notice. The existing schema-mismatch notice path is preserved verbatim.
- **`check_writing_style`** (FC10, R20). Reads the banned vocabulary list at validate-time from `skills/writing-style/SKILL.md` and emits notices for each match in the document body.
- **`check_plan_section_structure`** (FC11, R22; closes `tsukumogami/shirabe#158` on the validator surface). Reconciles the emitted `## Implementation Issues` section structure against the canonical structure from `plan-format.md`.
- **`check_plan_design_field_consistency`** (FC12, R23). Greps for field-name conflicts across the PLAN's issue ACs and the upstream DESIGN's structural rubrics; emits a notice with a pointer to `references/fixes/plan-design-field-consistency.md`.
- **`check_eval_fixture_frontmatter`** (FC13, R26). Detects fixtures where `<!--` appears on line 1 before the `---` frontmatter opener; emits a notice with a pointer to `references/fixes/eval-fixture-frontmatter.md`.
- **`check_claude_md_conventions`** (FC-CONVENTIONS, R28). Detects missing or malformed `## Release Notes Convention: <path>` header when the doc under validation is the per-repo CLAUDE.md or when /prd/design Phase 0 invocations would consult it; emits a notice with a pointer to `references/fixes/claude-md-conventions.md`.
- **Slug-prefix detection** (R27). Either a new sub-command (`shirabe scope detect-prefix <slug>`) returning the detected prefix and a mismatch flag, or a validate-time notice emitted when the slug-prefix sampling detects a mismatch. The exact placement is a Batch-1 implementation detail; the lazy-load contract is the same — the deterministic part lives in the CLI.

`crates/shirabe-validate/src/validate.rs` registers all new checks in the dispatch order. Notice-level discharge (per FC08/FC09 precedent) preserves the existing exit-code semantics.

`crates/shirabe-validate/src/formats.rs` gains canonical-structure entries for `plan/v1`'s `## Implementation Issues` section (used by FC11) and may gain entries for `design/v1` if the structural-format reviewer's machine-checkable subset is large enough to warrant validator support.

### Per-error reference files (tier 2)

Five new files at `references/fixes/`:

- **`references/fixes/sub-agent-dispatch.md`** (Decision 1 + Decision 2 merged). The combined resolution file for sub-agent dispatch fallback selection and parent_orchestration sentinel consultation. Contents: (a) the five canonical fallback shapes with full resolution prose; (b) per-skill binding table (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`, `/work-on`); (c) the sentinel detection convention (three subfields `invoking_child`, `suppress_status_aware_prompt`, `rationale`); (d) the chain-handoff and status-transition routing per rationale; (e) R8's NOT-covered carve-out.
- **`references/fixes/plan-design-field-consistency.md`** (Decision 5, R23). Resolution prose for FC12: how to interpret the field-conflict notice, which side to align to, when to rewrite the AC vs revise the DESIGN, when the conflict is intentional.
- **`references/fixes/eval-fixture-frontmatter.md`** (Decision 5, R26). Resolution prose for FC13: where to place HTML-comment markers in eval fixtures (inside frontmatter or after closing `---`, never on line 1) and why.
- **`references/fixes/claude-md-conventions.md`** (Decision 6, R28). Resolution prose for FC-CONVENTIONS: the canonical `## Release Notes Convention: <path>` header format, the per-repo default, cross-references to other CLAUDE.md conventions.
- **`references/fixes/cli-version-preflight.md`** (Decision 6, R30; renamed from `references/cli-version-preflight.md` to live under `references/fixes/` matching the other per-error files). Resolution prose for CLI version-skew: the per-subcommand `--help` probe, the documented manual sed-edit fallback per-subcommand, the workspace-binary version detection.

Each reference file is sized to be loaded on demand — typical length ~30-80 lines, far smaller than the cumulative cost of the original-pass per-skill eager-loaded subsections.

### Format-reference files (tier 3, materialization)

`skills/design/references/design-format.md` is created. Contains the four-field frontmatter schema (status, problem, decision, rationale, with the optional `upstream:`, `spawned_from:`, and `motivating_context:` fields), the nine required-section list, the context-aware section table (Market Context, Required Tactical Designs, Upstream Design Reference), the Implementation Issues ownership convention (table owned by `/plan`, populated during Phase 7 single-pr emission), AND the R25 wip-hygiene carve-out clarification inline (single-rule extension; tier-3 acceptable per Decision 5).

`skills/plan/references/plan-format.md` is created. Contains the PLAN frontmatter schema, the section list, and the canonical `## Implementation Issues` structure for single-pr emission (Issues Table with `ID | Title | Status | Notes` columns plus Mermaid dependency diagram). The validator's FC11 check dereferences this file at validate-time.

`skills/brief/references/brief-format.md` gains R11 public-vs-private issue numbers disambiguation, R12 `motivating_context:` field documentation, and R13 BRIEF Open-Questions closure surface naming.

`skills/prd/references/prd-format.md` gains R11 grammar disambiguation, R12 field documentation, R14 Decisions-and-Trade-offs convention statement, R16 competitive-findings vs competitive-analysis-as-artifact-type Content Boundaries distinction.

### Per-skill SKILL.md and phase-reference changes (tier 3, lightweight)

Each of the eight child SKILL.md files (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`, `/work-on`) gets:

- A SHORT Phase-0 (or earliest state-reading phase) detection-and-pointer step (~3 lines). Example: "If the `parent_orchestration:` sentinel is present in the parent's state file (`wip/scope_<topic>_state.md` for tactical children, `wip/charter_<topic>_state.md` for strategic children), see `references/fixes/sub-agent-dispatch.md`."
- For the seven non-`/work-on` skills: a single new Resume Logic table row whose predicate is "sentinel present in <state-file-path>" and whose action is "see `references/fixes/sub-agent-dispatch.md`". No inline behavior prose.

No per-skill `### Sub-Agent Dispatch Fallback` subsection is added. The reference file IS the canonical content; the detection-and-pointer is always-loaded but trivially short.

`skills/design/references/phases/phase-6-final-review.md` grows a third reviewer in step 6.1 (structural-format-reviewer) parallel to architecture-reviewer and security-reviewer; step 6.2 feedback table extends to three rows.

`skills/plan/references/phases/phase-4-agent-generation.md` grows the AC anchor-existence prompt step (R24, tier-3 acceptable because tiers 1-2 are infeasible at generation time).

`skills/scope/SKILL.md` Phase 0 grows the slug-prefix detection step body — the actual sampling is in the CLI extension (R27); the SKILL.md prose invokes the CLI and emits the prompt when the CLI returns a mismatch.

`skills/scope/references/phases/phase-1-discovery.md` (already lazy-loaded by /scope) is trimmed to carry the cold-start projected-PRD evaluation, the post-`/prd` re-evaluation gate, and the framing-shift opener short-circuit (R29).

### CLAUDE.md convention surface

The per-repo `## Release Notes Convention: <path>` header lands in CLAUDE.md (with `docs/guides/` for shirabe). The validator's FC-CONVENTIONS check detects missing/malformed headers at relevant invocations and emits a pointer to `references/fixes/claude-md-conventions.md`. The header parallels existing `## Repo Visibility:` and `## Planning Context:` headers; no new mechanism is introduced.

### Component interaction

The architecture has three top-level interaction surfaces. The validator is invoked at commit-time and at PR-CI time and emits FC codes plus pointers; the per-error reference files at `references/fixes/` are read by the agent when a pointer fires; the format references and skill/phase prose are read by skill authors at edit-time and by readers at audit-time. The interactions are read-only and lazy — the validator's FC pointer is the substrate signal that causes the agent to load the resolution file; no resolution prose loads until the signal fires. The four batches in Decision 7's revised sequencing reflect this dependency direction (CLI → reference files → skill edits → tests).

## Implementation Approach

Four batches, sequenced lazy-load-tier-first. Each batch is independently shippable; R31 backward compatibility holds at every batch boundary because tier-1 checks are notice-level (advisory only) and tier-2 pointers fire only when the validator emits the FC code.

**Batch 1 — CLI extensions.** Files: `crates/shirabe-validate/src/checks.rs` (SCHEMA-MISSING extension, plus new `check_writing_style` FC10, `check_plan_section_structure` FC11, `check_plan_design_field_consistency` FC12, `check_eval_fixture_frontmatter` FC13, `check_claude_md_conventions` FC-CONVENTIONS), `crates/shirabe-validate/src/validate.rs` (dispatch registration for all new checks), `crates/shirabe-validate/src/formats.rs` (canonical structures for FC11; possible entries for FC12 field-consistency rubric). The slug-prefix-detection extension lands either as a new sub-command module or as an additional check function depending on the simpler implementation path. Estimated 5-7 implementation issues touching ~5 files.

**Batch 2 — reference files.** Files: `references/fixes/sub-agent-dispatch.md` (new; Decision 1 + Decision 2 merged), `references/fixes/plan-design-field-consistency.md` (new), `references/fixes/eval-fixture-frontmatter.md` (new), `references/fixes/claude-md-conventions.md` (new), `references/fixes/cli-version-preflight.md` (new; renamed from `references/cli-version-preflight.md` to live under the per-error directory), `skills/design/references/design-format.md` (new; includes R25 wip-hygiene carve-out inline), `skills/plan/references/plan-format.md` (new). Estimated 7 implementation issues, one per file.

**Batch 3 — lightweight skill edits.** Files: `skills/brief/SKILL.md`, `skills/prd/SKILL.md`, `skills/design/SKILL.md`, `skills/plan/SKILL.md`, `skills/vision/SKILL.md`, `skills/strategy/SKILL.md`, `skills/roadmap/SKILL.md`, `skills/work-on/SKILL.md` (pointer-row + Phase-0 detection line each; no per-skill subsection), `skills/scope/SKILL.md` (Phase 0 slug-prefix CLI invocation prose, references the cli-version-preflight reference, references the phase-1 cold-start trim), `skills/scope/references/phases/phase-1-discovery.md` (R29 cold-start projected-PRD eval + post-`/prd` re-evaluation gate + framing-shift opener short-circuit), `skills/design/references/phases/phase-6-final-review.md` (R21 third reviewer), `skills/plan/references/phases/phase-4-agent-generation.md` (R24 AC anchor-existence prompt step), `skills/brief/references/brief-format.md` (R11/R12/R13 edits), `skills/prd/references/prd-format.md` (R11/R12/R14/R16 edits), CLAUDE.md (R28 convention header). Estimated 10-13 implementation issues touching ~12 files.

**Batch 4 — tests.** Files: `crates/shirabe-validate/tests/` (test cases for each new FC code: SCHEMA-MISSING, FC10, FC11, FC12, FC13, FC-CONVENTIONS; plus tests verifying the validator-pointer-resolution flow — when the validator emits an FC code with a pointer, the pointer dereferences to an existing reference file). Estimated 2-3 implementation issues touching test files.

Total estimated implementation scope: 15-18 issues across ~17 files, distributed roughly 30% / 40% / 25% / 5% across the four batches — concentrated in CLI extensions and reference files rather than per-skill prose, mirroring the lazy-load principle's preference order.

## Security Considerations

The revised design produces and modifies markdown documentation files and extends the existing Rust validator crate with six notice-level checks (SCHEMA-MISSING extension, FC10, FC11, FC12, FC13, FC-CONVENTIONS) plus the slug-prefix-detection CLI extension. No new external input sources, no new network endpoints, no new download/extract/execute paths, no new filesystem permissions beyond what `shirabe validate` and the existing chain workflows already require, and no new Rust crate dependencies. Each new validator check reads from already-public canonical references (`skills/writing-style/SKILL.md` for FC10, `plan-format.md` for FC11, the artifact under validation for SCHEMA-MISSING / FC12 / FC13, CLAUDE.md for FC-CONVENTIONS).

Three bounded data-handling considerations are worth naming for downstream implementers:

- **The `motivating_context:` cross-repo reference field (R12).** The field accepts a reference (issue number or `owner/repo:path`) that MAY point at a private artifact from a public document. The field is metadata — the link target is referenced by identifier, not described. Public-repo readers see only the reference identifier, not the private content. The visibility-direction rules in `references/cross-repo-references.md` already cover this pattern; the R12 field documentation cites those rules so implementers preserve the boundary.
- **Verdict-preamble operating-context disclosure.** The serial-self-jury fallback (Decision 1) prescribes that verdict-artifact preambles surface the operating context (parallel-jury vs serial-self-jury) and the independence-loss caveat. The preamble is workflow metadata about how the jury ran; it does not contain private artifact content. The convention preserves audit-trail integrity without creating a new data-exposure surface.
- **Validator FC10 writing-style notice content.** The notice emits the banned word, the file path, and the line number. The content is derived from already-committed artifact text; no new exposure beyond what was already in the committed file. Workspaces that treat notices as errors will surface the violations at PR-CI time.

The CLI-version-preflight reference (R30) prescribes a `shirabe <subcommand> --help` probe that runs against the workspace's already-installed binary; the probe does not execute network calls, does not download external artifacts, and does not escalate permissions. The documented manual-sed-edit fallback path operates on the same files the failed subcommand would have touched.

No security-dimension findings require design changes. The boundaries above are workflow metadata, not data; the implementation proceeds.

## Consequences

### Positive

The lazy-load shape eliminates context bloat from defensive mechanisms that may never fire. Under the revised design, an agent running `/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`, or `/work-on` under direct invocation loads zero per-error resolution prose; under sub-agent dispatch, the same agent loads exactly one reference file (`references/fixes/sub-agent-dispatch.md`) when the Phase-0 detection step finds the sentinel. The cumulative-eight-children cost of the original-pass shape (8 × 30-60 lines = 240-480 lines eager-loaded across the chain) drops to zero in the default case and to ~50 lines when the failure fires.

The reference-file canonical statements (Decisions 1 + 2 merged into `references/fixes/sub-agent-dispatch.md`) preserve the original-pass "one source of truth" composability — cross-skill consistency is still structural because there's still one canonical file — while the consumer surface drops from inline per-skill prose to pointer-only rows.

The format-reference materialization (Decision 3) closes the asymmetric-altitude debt across the four artifact types — `brief-format.md`, `prd-format.md`, `design-format.md`, `plan-format.md` all live at the same altitude and contain the same shape of clarifications. The validator's FC08, FC11, FC12 checks dereference these files, so the format-reference contracts become machine-checkable.

The validator-vs-jury split (Decision 4, now expanded to seven checks) places each check at the surface where it executes most naturally — structural and mechanical checks in Rust, natural-language judgment in Phase 6 reviewers. The expanded coverage closes `tsukumogami/shirabe#157` (schema-field-present) and `tsukumogami/shirabe#158` (single-pr Implementation Issues drift) on the same surfaces that satisfy R18-R22 and adds tier-1 detection for R23/R26/R28.

The audit-trail fidelity the BRIEF named ("the chain's audit trail matches the chain's actual execution") still falls out of the dispatch-fallback resolution prose — every Phase 6 verdict file records the operating context (parallel-jury vs serial-self-jury) and the independence-loss caveat per the resolution prose in `references/fixes/sub-agent-dispatch.md`; every Resume Logic pointer-row preserves the parent's framing decision by virtue of the sentinel being read into the agent's context when the row fires.

### Negative

The implementation scope is smaller — ~17 files touched across four batches, estimated 15-18 issues, vs the original-pass estimate of 22-28. The smaller scope is a benefit on net, but the work concentrates more in Rust (the validator gains six new checks instead of three) and the workspace's existing FC-code vocabulary expands more aggressively (FC10 → FC13 plus FC-CONVENTIONS). Mitigation: each new FC ships with tests in Batch 4; the FC-code vocabulary is documented in `references/quality/` per existing precedent.

The lazy-load shape introduces an implicit contract between the validator and the agent: when the validator emits an FC code, the pointer to the resolution file must dereference to a real file at the expected path. A future relocation of any `references/fixes/<name>.md` file requires updating both the validator's notice text and the calling skill's documentation. Mitigation: Batch 4 includes a validator-pointer-resolution test that exercises every FC code's pointer at validate-time; broken pointers fail the test.

The two new format-reference files (`design-format.md`, `plan-format.md`) require migration of inline SKILL.md format prose. The migration must preserve content without losing existing citations; this is detail-heavy work that benefits from review at the file-creation boundary. (Carried over from the original-pass concern.)

### Mitigations

The four-batch sequencing isolates risk per tier — CLI extensions ship and are reviewed before reference files; reference files ship before skill edits; tests ship last and verify the full pointer-resolution flow. Each batch can be reverted independently; Batch 4 specifically catches broken pointers at validate-time.

The notice-level discharge for all validator checks (SCHEMA-MISSING, FC10, FC11, FC12, FC13, FC-CONVENTIONS) preserves backward compatibility — existing artifacts that don't conform to the new checks emit advisory notices but do not flip the exit code to non-zero. The workspace policy can promote notices to errors at its own pace once authors have had a window to clean up existing violations.

The `parent_orchestration:` sentinel as the gating condition for every new fallback path means R31 is structural — direct invocations (no parent dispatching, no sentinel) fall through to existing behavior at every new surface.


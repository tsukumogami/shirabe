---
upstream: docs/prds/PRD-shirabe-pattern-v1-ergonomics.md
---

# DESIGN: shirabe pattern v1 ergonomics

## Status

Proposed

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

(Populated by Phase 2 / Phase 3.)

## Decision Outcome

(Populated by Phase 3 / Phase 4.)

## Solution Architecture

(Populated by Phase 4.)

## Implementation Approach

(Populated by Phase 4.)

## Security Considerations

(Populated by Phase 5.)

## Consequences

(Populated by Phase 4.)

---
complexity: critical
complexity_rationale: "Lands the single source of truth for the dispatch contract; mis-wording breaks every downstream cross-reference. Touches the pattern reference's invariant surface — must preserve I-1 through I-7 wording verbatim while inserting ~110 lines between two existing sections."
---

# Issue 1: docs(parent-skill-pattern): add Dispatch Contract section

## Goal

Land a single new top-level `## Dispatch Contract` section in `references/parent-skill-pattern.md` between `## Team-Shape Declarator` and `## Required SKILL.md Structural Elements`. The section is the single source of truth that every downstream cross-reference (issues 2-13) points at.

## Acceptance Criteria

- [ ] **AC1.1** — `references/parent-skill-pattern.md` contains exactly one `## Dispatch Contract` top-level heading (case-sensitive). Verify: `grep -cE '^## Dispatch Contract$' references/parent-skill-pattern.md` returns `1`.
- [ ] **AC1.2** — Five labelled sub-sections present in order: `### Dispatch Mechanism`, `### Pre-Dispatch State`, `### Observability Surface`, `### Hand-Back Contract`, `### Child Team-Shape Declaration`. Verify: `grep -cE '^### (Dispatch Mechanism|Pre-Dispatch State|Observability Surface|Hand-Back Contract|Child Team-Shape Declaration)$' references/parent-skill-pattern.md` returns `5`.
- [ ] **AC1.3** — Opening paragraph names the contract as a contract (not a per-phase interface, not a discipline-internal binding), names the single mechanism (the Skill tool), and states symmetric applicability across both parents and all seven children.
- [ ] **AC1.4** — `### Dispatch Mechanism` names the Skill tool as the v1 binding, labels it Layer 2 under `team_primitive`, and cross-references R14 for child-isolation.
- [ ] **AC1.5** — `### Pre-Dispatch State` enumerates four elements: (1) `parent_orchestration:` sentinel block with subfields `invoking_child`, `suppress_status_aware_prompt`, `rationale`; (2) worktree-staleness gate output (None / Informational / Intent-changing-resolved-in-place); (3) state-file fields written before dispatch (planned_chain advance, last_updated bump, pre_invocation_sha capture); (4) child-side team-shape declaration glob marker (`skills/<name>/team.yaml` exists with valid schema). Cross-references `references/parent-skill-state-schema.md`.
- [ ] **AC1.6** — `### Observability Surface` makes both the positive statement (durable artifact path polling, `git log`, parent-own wip/ filesystem) and the negative statement (cites R14 for child internals).
- [ ] **AC1.7** — `### Hand-Back Contract` enumerates: R20 file-existence check, frontmatter `status:` read, git blob hash capture, Phase-N Reject discard-commit detection via `git log <pre_invocation_sha>..HEAD`, validator pass-through, `parent_orchestration:` cleanup, `child_snapshots:` capture.
- [ ] **AC1.8** — `### Child Team-Shape Declaration` names the glob marker `skills/<name>/team.yaml`, states the schema (per DESIGN Decision 2), states v1 runtime read semantics (parent does NOT parse at dispatch time; consumed by reviewers, future Phase D validator, future amplifier substrate), and states glob count requirement (one file per in-pattern child).
- [ ] **AC1.9** — Closing paragraph carries: Layer-1/Layer-2 split label (four contract elements are Layer 1; Skill-tool primitive and YAML schema are Layer 2); no-per-parent-override-in-v1 sentence per DESIGN Decision 4; R11 forward-looking note (contract applies to chain runs initiated after the contract lands; existing in-flight runs not retroactively reshaped) per DESIGN Decision 6.
- [ ] **AC1.10** — Existing `## Team-Shape Declarator` and `## Required SKILL.md Structural Elements` sections are unchanged; only the new section is inserted between them.
- [ ] **AC1.11** — I-1 through I-7 wording elsewhere in the file is unchanged. Verify: diff confirms only the new section is added and the surrounding sections' content is preserved.
- [ ] **AC1.12** — Section length approximately 110 lines (DESIGN Component 1 estimate); not split across multiple top-level sections (R9).

## Dependencies

**Dependencies**: None

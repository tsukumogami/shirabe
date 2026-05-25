---
complexity: critical
complexity_rationale: Keystone SKILL.md body for the second parent skill in shirabe; ships the contract surface (Input Modes, execution-mode flags, slug regex, Workflow Phases, Resume Logic ladder, Phase Execution, Reference Files) plus the prose backing R8 / R10 / R13 / R15 / R23 / Security mitigations. Carries the slug re-validation, closed write-target set, state-file enum re-validation, and stale-`parent_orchestration:` self-heal contracts named in DESIGN-shirabe-scope-skill.md Security Considerations; any drift in this body re-opens a security surface that the four downstream issues (11/12/13) and four pattern-doc edits cannot recover from independently.
---

## Goal

Author `skills/scope/SKILL.md` as the keystone parent-skill body for `/scope` — implementing the seven pattern-level structural elements from R1 against `/scope`'s tactical-chain semantics (BRIEF → PRD → DESIGN → PLAN), binding the parent-skill pattern v1's two-layer contract, declaring the v1 substrate substitutions (`storage_substrate: wip-yaml-md`, `team_primitive: single-team-per-leader-no-nested`), and surfacing the prose contracts behind R2, R4-R8, R7.5, R10, R12, R13, R15, R16, R16.5, R23, and the Security Considerations mitigations.

## Context

Design: `docs/designs/DESIGN-shirabe-scope-skill.md`

`/scope` is the second parent skill landing in shirabe after `/charter`. The pattern-skill contract surface — semantic invariants I-1 through I-7, the meta-resume ladder template, the universal state-schema 5-field minimum, the three-exit contract, and the child-inspection rules — was ratified by `/charter` and lives in four pattern-reference files at `references/parent-skill-{pattern,state-schema,resume-ladder-template,child-inspection}.md` plus the new `references/parent-skill-worktree-discipline.md` shipped by <<ISSUE:1>>. `/scope` v1 binds the same substrates as `/charter` (per design Decision Drivers row 3) and ratifies the pattern's gate vocabulary by adding the fourth shape (Mandatory-with-auto-skip, per Component 1 / <<ISSUE:7>>) and two conditional state-schema fields (`boundary:`, `plan_execution_mode:`, per Component 2 / <<ISSUE:8>>).

This issue is the keystone of PR-4: it is the surface every other PR-4 issue cites (the five phase references in <<ISSUE:11>> are referenced from the Phase Execution list authored here; the four Decision Record templates in <<ISSUE:12>> are pointed at from this SKILL.md's prose covering R15; the eleven-scenario eval suite in <<ISSUE:13>> exercises this SKILL.md's R1 structural elements and the prose contracts). The SKILL.md is the eval surface: AC1, AC1b, AC2, AC3, AC3b, AC4, AC9, AC9b, AC9c, AC16b, AC17a, AC17b, AC17c grep against literal substrings in this file's prose.

The body must align section-by-section with `/charter`'s precedent (`skills/charter/SKILL.md`) for the seven pattern-level structural elements, then layer `/scope`-specific bindings inside the substitution surface. `/charter` is the single-agent reference implementation; `/scope` ships single-agent at its own layer (no peer dispatch within `/scope` itself per R19 — the team-lead operating discipline binding is concrete at the child-skill dispatch layer per design Context lines 169-175).

The asymmetries `/scope` must absorb (each surfaces in the SKILL.md body):

1. **Two settled-upstream boundaries** (PRD and DESIGN) — Slot 5 has 9 rows in most-downstream-first first-match-wins order; the DESIGN-boundary fires before the PRD-boundary when both Accepted artifacts exist (AC17b).
2. **PLAN-status-aware refuse-and-redirect** — PLAN-Active routes to `/work-on`; PLAN-Done routes to `/release`; both refuse re-entry and MUST NOT surface the Re-evaluate / Revise / Bail triad (AC17c). The refuse-and-redirect prompt-shape paragraph appended to Slot 5 lives in `references/parent-skill-resume-ladder-template.md` per <<ISSUE:9>>.
3. **Mandatory-with-auto-skip gate** — `/prd`'s invocation skips when an Accepted PRD exists at the canonical path (chain proposal records `/prd` in `chain_skipped` with reason "Accepted PRD already exists" per AC6).
4. **Terminal child with two output modes** — `/plan`'s `single-pr` and `multi-pr` modes are recorded post-run in the state file's `plan_execution_mode:` field (AC10a, AC8b); `/scope` does NOT pre-decide the mode.
5. **Phase-N Reject in-chain integration** — when `/prd` (issue PR-2 / <<ISSUE:3>>) or `/design` (issue PR-3 / <<ISSUE:5>>) returns Reject in-chain, `/scope` writes the rejection-sub-shape Decision Record immediately, observing the discard commit via `git log` (Component 7.7 / R23 / AC12a / AC12b). Out-of-chain Reject leaves only the discard commit (AC12c / AC30c).

Security Considerations from the design land here as prose contracts the SKILL.md must state explicitly:

- **Slug re-validation on resume** — slugs recovered from on-disk artifact paths during Slot 5 / Slot 6 ladder matches MUST be re-validated against `^[a-z0-9-]+$` BEFORE interpolation into emitted shell commands. Unparseable slug rejects the resume entry and routes to R8 bail-handling.
- **Closed write-target set** — Component 5's body confines `/scope`'s filesystem writes to an enumerated set (Decision Records under `docs/decisions/`; force-materialization at `docs/{briefs,prds,designs}/<TYPE>-<topic>.md`; `wip/scope_<topic>_*`; removals of `wip/{brief,prd,design,plan}_<topic>_*` and `wip/research/{prd,design}_<topic>_*`). Writes outside this set fail the Phase 3 R9 hard-finalization extension.
- **State-file enum re-validation** — `triggering_child`, `boundary`, `decision_record_sub_shape`, and `plan_execution_mode` SHALL be validated against declared enums BEFORE constructing write paths or interpolating into shell commands. Out-of-enum values fail the resume ladder.
- **Stale `parent_orchestration:` self-heal** — Phase 0 setup unconditionally clears any stale `parent_orchestration:` block found at session start. The block's presence after a session restart is by definition stale; the clear MUST NOT prompt the author.

The body extends — but does not re-derive — the four-reference pattern surface. Citations use `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-*.md` (per `/charter`'s precedent at `skills/charter/SKILL.md:206-209`); `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-worktree-discipline.md` is the new fifth reference from <<ISSUE:1>>. Phase-specific references at `skills/scope/references/phases/phase-{0..4}-*.md` are produced by <<ISSUE:11>>; this SKILL.md cites them by path but does not produce them.

## Acceptance Criteria

- [ ] **File exists.** `skills/scope/SKILL.md` exists at the canonical loadable-skill path.

- [ ] **Frontmatter declares `name: scope`.** YAML frontmatter contains `name: scope`, `description:` (multi-line allowed), and `argument-hint: '<topic-slug or freeform topic>'`. AC1 grep-passes.

- [ ] **Description names the three R17b trigger phrases verbatim.** The frontmatter `description:` block names "start a tactical conversation about X", "open a feature scope for Y", AND "I want to think through the feature shape of Z" (or the exact three trigger phrases R17b enumerates), AND names the chain VISION → STRATEGY → ROADMAP's tactical-chain analog (BRIEF → PRD → DESIGN → PLAN).

- [ ] **R1 seven structural elements present and non-empty.** SKILL.md contains exactly the seven pattern-level structural elements R1 names, each with non-empty content: (1) `## Input Modes`, (2) `## Execution-Mode Flags` (or analogous heading parsing `--auto` / `--interactive` / `--max-rounds=N`), (3) `## Topic-Slug Constraint` (citing `^[a-z0-9-]+$` from the state-schema reference), (4) `## Workflow Phases` (containing a diagram or table naming Phase 0 through Phase 4), (5) `## Resume Logic` (referencing the universal meta-ladder template + slot 5/6/7 fills), (6) `## Phase Execution` (one entry per phase pointing at `skills/scope/references/phases/phase-*-*.md`), (7) `## Reference Files` (table citing all four pattern-level references plus `parent-skill-worktree-discipline.md` plus the five phase references). AC1b grep-passes for each section heading.

- [ ] **Team Shape declarator section present.** A `## Team Shape` section (per `/charter`'s precedent at `skills/charter/SKILL.md:33-43`) declares `/scope` as a single-agent skill in the v1 core layer with no team spawned at the `/scope`-itself layer; the team-shape declarator is prose per Decision 8's v1 form. The section explicitly notes that R19 (team-lead operating discipline) binds at the child-skill-dispatch layer (each `/brief`, `/prd`, `/design`, `/plan` invocation is a dispatch in the discipline sense) but not at the parent-itself layer.

- [ ] **Input Modes section names two modes.** The Input Modes section names (1) empty `$ARGUMENTS` (cold-start prompt — see AC2), and (2) non-empty `$ARGUMENTS` treated as a freeform topic string that MUST conform to the topic-slug regex AS PROVIDED (byte-for-byte validation, no normalization, no derivation, no "best effort" massaging). The section explicitly forbids paths to durable artifacts as input AND states that path-shaped `$ARGUMENTS` fails the regex check (e.g., `/scope docs/prds/PRD-foo.md` is rejected — AC4). Cold-start prompt names the three R17b trigger phrases and asks the author to re-invoke `/scope <topic-slug>`. R2 covered.

- [ ] **Execution-Mode Flags section parses `--auto`, `--interactive`, `--max-rounds=N`.** The section documents `--auto` (non-interactive mode, recommended-default decisions), `--interactive` (default; blocks on user prompts), and `--max-rounds=N` (caps re-evaluation re-entries). The `--max-rounds=N` documentation MUST state the default is 5 (overriding `/charter`'s default of 3 per R16.5 and AC16b) AND that values outside the integer 1+ range surface a clear error at Phase 0. The `--auto` mode documentation MUST state that it does NOT suppress R9's hard-finalization check.

- [ ] **Topic-Slug Constraint section cites the regex from the pattern reference.** The section states the regex `^[a-z0-9-]+$` and cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` (Topic-Slug Regex section) as the canonical source; states that the slug appears in `wip/scope_<topic>_state.md`, the Decision Record path, and downstream child wip/ paths; states Phase 0 validates AS PROVIDED (byte-for-byte) with no normalization. AC3 (whitespace) and AC3b (uppercase / underscore / dot / out-of-charset) reject behaviors are surfaced explicitly: each rejection MUST name the violated pattern in the error message; `/scope` MUST NOT proceed silently or silently normalize.

- [ ] **Workflow Phases section has the 5-phase diagram.** The section contains either (a) an ASCII-style diagram or (b) a table with one row per phase listing the five phases: Phase 0 (Setup), Phase 1 (Discovery + Chain Proposal), Phase 2 (Child Invocation Loop), Phase 3 (Exit Finalization), Phase 4 (wip Cleanup). Each phase row names its purpose and the reference file path under `skills/scope/references/phases/`. The Phase 2 row names the per-child invocation sub-steps (worktree-staleness check → write `parent_orchestration:` sentinel → invoke child → structural file-existence check per R20 → clear sentinel → capture child snapshot → validator pass-through).

- [ ] **Resume Logic section fills Slot 5 (9 rows), Slot 6 (4 rows), Slot 7 (vacuous in v1).** The Resume Logic section cites the universal meta-ladder rows 1-4 and 8-9 from `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`, then fills the parent-specific body slots with most-downstream-first first-match-wins ordering:
  - **Slot 5** has 9 rows in this order (PLAN-Active → PLAN-Done → PLAN-Draft → DESIGN-Accepted → DESIGN-Proposed → PRD-Accepted → PRD-Draft → BRIEF-Accepted/Done → BRIEF-Draft) per design Decision 6 (DESIGN above PRD per AC17b).
  - **Slot 6** has 4 rows in most-downstream-first order (PLAN → DESIGN → PRD → BRIEF wip-partial detections), per Component 7 / design Solution Architecture / R11.
  - **Slot 7** is explicitly named as vacuous in v1 with the reason "No feeder defined in v1; reserved for future" per design Decision 6's Slot 7 paragraph and PRD Out-of-Scope item 7.
  - Slot 5 row 5.1 (PLAN-Active) and 5.2 (PLAN-Done) MUST contain the literal substring `redirect to /work-on` (5.1) or `redirect to /release` (5.2) and MUST NOT contain "Re-evaluate / Revise / Bail" (AC17c).
  - Slot 5 row 5.4 (DESIGN-Accepted) and row 5.6 (PRD-Accepted) MUST contain the literal substring "Re-evaluate / Revise / Bail" (case-insensitive) AND MUST identify the boundary as the DESIGN-boundary (5.4) or PRD-boundary (5.6) (AC17a, AC17b). Row 5.4 also MUST NOT contain "Continue / Start fresh".
  - The Resume Logic section explicitly states stale-session threshold = 7 days (matching `/charter`'s R16 inherited default).

- [ ] **Phase Execution section has 5 entries each pointing at a phase reference file.** Numbered 0 through 4 in order, each entry names the phase's purpose and the reference path: `skills/scope/references/phases/phase-0-setup.md`, `phase-1-discovery.md`, `phase-2-chain-orchestration.md`, `phase-3-exit-finalization.md`, `phase-4-cleanup.md`. The phase reference files themselves are produced by <<ISSUE:11>>; this SKILL.md cites them by path only.

- [ ] **Reference Files table cites all pattern references plus phase references.** A table with two columns (`File`, `When to load`) listing in order: `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`, `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`, `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`, `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`, `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-worktree-discipline.md`, then the five phase reference files. Each row's "When to load" cell names the phases or conditions under which `/scope` consults the file (consistent in tone with `/charter`'s precedent at `skills/charter/SKILL.md:202-215`).

- [ ] **Chain-Proposal Output prose section (R7.5).** A prose section documents the chain-proposal confirmation prompt Phase 1 emits at the end of discovery. The prompt MUST contain the literal substrings "Proceed", "Adjust", and "Bail" (case-insensitive — AC9). The section documents the three branch behaviors: Proceed advances to Phase 2; Adjust routes back to Phase 1 discovery (AC9b); Bail routes per R8's bail-handling (abandonment-forced if any wip state exists for the topic, clean-cancel otherwise — AC9c). The section also names the per-predicate reasons feeding R6's shape-dependent gate verdict.

- [ ] **Three Exit Paths prose section (R8).** A prose section documents the three terminal exit paths and the R8 bail-handling tie-break rule:
  - `full-run` — chain completes through `/plan`; terminal artifact is `docs/plans/PLAN-<topic>.md` (Draft in single-pr mode, Active in multi-pr mode).
  - `re-evaluation` — chain ends at a settled-upstream boundary (PRD or DESIGN) with a Decision Record written to `docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md` (four combinations; templates from <<ISSUE:12>>).
  - `abandonment-forced` — chain bails or stalls; the most-recently-running child's intermediate is force-materialized as a Draft artifact with the uniform HTML-comment marker at the END of the artifact's Status section (Decision 7 / AC13).
  - **R8 bail-handling tie-break** is named explicitly: the triggering_child is the most-recently-running child per the chain's progression, resolved against `wip/{brief|prd|design|plan}_<topic>_*` intermediates per AC13c.

- [ ] **State File Schema prose section (R10).** A prose section names the state file at `wip/scope_<topic>_state.md` as YAML-in-`.md` under the `wip-yaml-md` substrate, enumerates the 5-field minimum from the pattern reference (`topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`), then enumerates the `/scope`-specific extensions: `chain_started`, `chain_completed`, `planned_chain`, `chain_ran`, `chain_skipped`, `boundary` (conditional on `exit: re-evaluation` — gated per <<ISSUE:8>>), `decision_record_sub_shape` (conditional on `exit: re-evaluation`), `plan_execution_mode` (conditional on `/plan` in `chain_ran`), `referenced_artifact`, `discard_commit_sha`, `rejection_rationale`, `triggering_child`, `partial_phase_reached`, `child_snapshots` (per-child status + content-hash dual-check block per AC18a/AC18b), `worktree_divergences` (conditional list per <<ISSUE:1>>), and `parent_orchestration` (ephemeral, present only during in-flight child invocation per Component 1 / <<ISSUE:7>> L13 amendment). The section explicitly states I-5 absent-when-ungated for every conditional field.

- [ ] **Visibility Detection prose section (R12).** A prose section names the visibility-detection mechanism from CLAUDE.md's `## Repo Visibility:` header (inherited unchanged from the pattern doc) AND states that when the header is absent, `/scope` defaults to Private AND emits a warning containing the literal phrasing "Default to Private if unknown" naming the missing `## Repo Visibility:` header (AC19).

- [ ] **Manual-Fallback Non-Interference prose section (R13).** A prose section states that a child invoked directly OUTSIDE `/scope` produces no `/scope` interference: `/scope` does NOT surface a warning, does NOT block, does NOT modify state files when a child runs standalone (AC20). The section names the consequence for Phase-N Reject: in-chain Reject writes a rejection-sub-shape Decision Record (AC12a, AC12b); out-of-chain Reject leaves only the discard commit as the durable trace, with no retroactive Decision Record on a later `/scope` resume (AC12c, AC30c).

- [ ] **Validator Pass-Through prose section.** A prose section states that Phase 2 runs `shirabe validate --visibility=<repo-visibility>` against each intermediate after the child returns and before invoking the next child (per design Decision 10 / Component 7.8). Failed validation halts the chain and routes via R8. (AC21 covered transitively — the section binds; the per-phase mechanism lives in <<ISSUE:11>>'s phase-2 reference.)

- [ ] **Phase-N Reject In-Chain Integration prose section (R23).** A prose section documents that when `/prd` (per <<ISSUE:3>>) or `/design` (per <<ISSUE:5>>) returns Reject in-chain, `/scope` observes the Reject verdict by detecting the discard commit on the current branch via `git log` (Component 7.7); the rejection-sub-shape Decision Record is written immediately after the discard commit lands. The section states that the discard-commit observability mechanism preserves R13 manual-fallback parity (the discard commit is the durable signal regardless of in-chain or out-of-chain invocation).

- [ ] **Abandonment-Forced HTML-Comment Marker prose section (R15 + Decision 7).** A prose section documents the uniform single-line HTML-comment marker text exactly: `<!-- scope-status-block: abandonment-forced; triggering-child: <name>; partial-phase-reached: <phase>; chain-started: <ISO-8601 timestamp> -->`. The section states: (a) the marker is placed at the END of the artifact's existing Status section (not in a new required section per AC23); (b) whitespace and field order inside the comment are significant; (c) the four substitutions are populated from the state file's `triggering_child`, `partial_phase_reached`, and `chain_started` fields; (d) `<name>` MUST be one of `brief | prd | design | plan` resolved by R8's tie-break.

- [ ] **Security mitigations — slug re-validation prose.** A prose section (in the Topic-Slug Constraint section or a dedicated Security Considerations section in SKILL.md) states explicitly that slugs RECOVERED from on-disk artifact paths during Slot 5 / Slot 6 ladder matches MUST be re-validated against `^[a-z0-9-]+$` BEFORE interpolation into emitted shell commands. Unparseable slug rejects the resume entry, surfaces a diagnostic naming the offending path, and routes to R8 bail-handling. The resume MUST NOT silently proceed with an unvalidated slug.

- [ ] **Security mitigations — closed write-target set prose.** A prose section (in the Three Exit Paths or State File Schema section, or a dedicated Security Considerations section) enumerates `/scope`'s allowed filesystem write targets:
  - `docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`
  - `docs/plans/PLAN-<topic>.md` (produced by `/plan`, not directly by `/scope`, on full-run exit)
  - `docs/{briefs,prds,designs}/{BRIEF,PRD,DESIGN}-<topic>.md` (force-materialization only, on abandonment-forced exit)
  - `wip/scope_<topic>_*` (state file + ancillary)
  - removals of `wip/{brief,prd,design,plan}_<topic>_*` and `wip/research/{prd,design}_<topic>_*` (Phase-N Reject cleanup + Phase 4 wip cleanup)
  Writes outside this enumerated set fail the Phase 3 R9 hard-finalization check.

- [ ] **Security mitigations — state-file enum re-validation prose.** A prose section states that on resume, `triggering_child` (`brief | prd | design | plan`), `boundary` (`prd | design`), `decision_record_sub_shape` (`re-evaluation | rejection`), and `plan_execution_mode` (`single-pr | multi-pr`) MUST be validated against their declared enums BEFORE being used to construct write paths or interpolate into shell commands. Out-of-enum values fail the resume ladder and route to R8 bail-handling.

- [ ] **Security mitigations — stale `parent_orchestration:` self-heal prose.** A prose section names Phase 0's unconditional self-heal: any `parent_orchestration:` block found at session start is cleared without prompting the author. The presence of the block after a session restart is by definition stale; the clear is the contract.

- [ ] **Binding Notes section names v1 substrate substitutions.** A section (titled "Binding Notes" or analogous, paralleling `/charter`'s Team Shape declarator) names `/scope` v1's substrate substitutions explicitly: `storage_substrate: wip-yaml-md` (state file at `wip/scope_<topic>_state.md`) and `team_primitive: single-team-per-leader-no-nested` (no nested teams; inline decision walks; upfront upper-bound roster). The section explicitly names the pattern's substitution surface (per `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`) as where the bindings live.

- [ ] **No wip/ path references in committed prose.** The SKILL.md does NOT reference any `wip/<short-path>` that survives the cleanup commit beyond the canonical state-file path `wip/scope_<topic>_state.md` and the wip-cleanup-target paths under `wip/{brief,prd,design,plan}_<topic>_*` and `wip/research/{prd,design}_<topic>_*` (these are the legitimate references the schema and write-target enumeration need). No reference to any `wip/research/<topic>/` workflow scratch path or any other non-durable wip artifact.

- [ ] **Public-content discipline.** No reference to private repos, internal resources, or pre-announcement features. No emojis. No AI attribution / co-author lines. No reference to internal vendors.

- [ ] **Conventional commit and shirabe writing-style compliance.** Body avoids the workspace writing-style banned terms ("tier/tiered", "robust", "leverage", "comprehensive/holistic", "facilitate"). Direct prose; vary sentence length; contractions allowed.

- [ ] **Cross-cite the pattern surface accurately.** Each prose section that binds a pattern-level invariant cites the relevant pattern reference path (per `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-*.md`), the relevant R-tag from PRD-shirabe-scope-skill.md, and the relevant Component/Decision number from DESIGN-shirabe-scope-skill.md. This is the L9 reviewer-checkability surface; the reviewer in <<ISSUE:13>> exercises the grep-test against the SKILL.md.

- [ ] **Security review completed.** The four Security Considerations mitigations (slug re-validation, closed write-target set, state-file enum re-validation, stale `parent_orchestration:` self-heal) appear as prose contracts in the body; a security-review pass against `docs/designs/DESIGN-shirabe-scope-skill.md` Security Considerations section confirms each named hazard has a corresponding mitigation paragraph in the SKILL.md.

- [ ] **Must deliver: `skills/scope/SKILL.md` with seven R1 structural elements + the prose contracts listed above (required by <<ISSUE:11>>, <<ISSUE:12>>, <<ISSUE:13>>).** <<ISSUE:11>> consumes the Phase Execution list to author the five phase reference files at the cited paths; <<ISSUE:12>> consumes the Three Exit Paths section's Decision Record path enumeration to author the four ADR templates; <<ISSUE:13>> consumes the literal-substring contracts (chain-proposal triad, resume-ladder vocabulary, abandonment-forced marker, refuse-and-redirect literals) to author the eleven eval scenarios.

- [ ] CI green (markdown lint clean per repo conventions; SKILL.md loads as a slash command without YAML frontmatter parse errors).

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

SKILL=skills/scope/SKILL.md

# File exists
test -f "$SKILL"

# Frontmatter declares name: scope (AC1)
grep -q '^name: scope$' "$SKILL"

# AC1b — the seven R1 structural elements are present as headings
grep -qE '^## Input Modes' "$SKILL"
grep -qE '^## Execution-Mode Flags' "$SKILL"
grep -qE '^## Topic-Slug Constraint' "$SKILL"
grep -qE '^## Workflow Phases' "$SKILL"
grep -qE '^## Resume Logic' "$SKILL"
grep -qE '^## Phase Execution' "$SKILL"
grep -qE '^## Reference Files' "$SKILL"

# Team Shape declarator section
grep -qE '^## Team Shape' "$SKILL"

# Topic-slug regex cited
grep -qE '\^\[a-z0-9-\]\+\$' "$SKILL"

# AC9 — chain-proposal triad literal substrings (case-insensitive)
grep -qi 'Proceed' "$SKILL"
grep -qi 'Adjust' "$SKILL"
grep -qi 'Bail' "$SKILL"

# AC17a / AC17b — Re-evaluate / Revise / Bail triad present somewhere
grep -qi 'Re-evaluate / Revise / Bail' "$SKILL"

# AC17c — refuse-and-redirect literals for PLAN-Active and PLAN-Done
grep -q 'redirect to /work-on' "$SKILL"
grep -q 'redirect to /release' "$SKILL"

# AC16b — --max-rounds=N default of 5 documented
grep -qE 'max-rounds.*5|5.*default' "$SKILL"

# R12 / AC19 — visibility-detection warning phrase
grep -q 'Default to Private if unknown' "$SKILL"

# R15 / AC13 — abandonment-forced HTML-comment marker text present (literal substring)
grep -q 'scope-status-block: abandonment-forced' "$SKILL"

# Reference Files table cites all four pattern references plus worktree-discipline
grep -q 'parent-skill-pattern.md' "$SKILL"
grep -q 'parent-skill-state-schema.md' "$SKILL"
grep -q 'parent-skill-resume-ladder-template.md' "$SKILL"
grep -q 'parent-skill-child-inspection.md' "$SKILL"
grep -q 'parent-skill-worktree-discipline.md' "$SKILL"

# Phase Execution cites the five phase reference paths
grep -q 'skills/scope/references/phases/phase-0' "$SKILL"
grep -q 'skills/scope/references/phases/phase-1' "$SKILL"
grep -q 'skills/scope/references/phases/phase-2' "$SKILL"
grep -q 'skills/scope/references/phases/phase-3' "$SKILL"
grep -q 'skills/scope/references/phases/phase-4' "$SKILL"

# State schema lists the /scope-specific extensions
for field in boundary plan_execution_mode chain_started chain_ran chain_skipped \
             child_snapshots referenced_artifact discard_commit_sha \
             rejection_rationale triggering_child partial_phase_reached \
             parent_orchestration worktree_divergences; do
  grep -q "$field" "$SKILL"
done

# Substrate substitutions named
grep -q 'wip-yaml-md' "$SKILL"
grep -q 'single-team-per-leader-no-nested' "$SKILL"

# Public-content discipline — no banned style terms
! grep -qiE '\b(tier|tiered|robust|leverage|comprehensive|holistic|facilitate)\b' "$SKILL"

# wip-hygiene — no off-spec wip paths
! grep -qE 'wip/research/<topic>' "$SKILL"
! grep -qE 'wip/scope_<topic>_(?!state\.md|.*$)' "$SKILL" || true

# Repo CI templates check
if [ -x scripts/validate-template-mermaid.sh ]; then
  bash scripts/validate-template-mermaid.sh
fi

echo "All validations passed"
```

## Security Checklist

- [ ] **Slug-injection surface closed at single enforcement point.** Phase 0 documentation in SKILL.md names the `^[a-z0-9-]+$` regex as the single-enforcement-point check on `$ARGUMENTS` BEFORE any state-file write or shell-command interpolation. No shell metacharacter passes (no quotes, backticks, semicolons, dollar signs, parentheses, asterisks). Path-traversal closed.

- [ ] **Slug re-validation on resume documented.** Slot 5 / Slot 6 prose explicitly states slugs recovered from on-disk artifact paths during ladder matches MUST be re-validated against `^[a-z0-9-]+$` BEFORE interpolation; unparseable slug rejects the resume entry and routes to R8 bail-handling.

- [ ] **Closed write-target set documented.** A prose section enumerates the five categories of allowed write targets (Decision Records / PLAN / force-materialization / state file / removals); writes outside the set fail the Phase 3 R9 hard-finalization extension. Future implementors adding a write target outside this set hit a documented enforcement boundary.

- [ ] **State-file enum re-validation documented.** A prose section names the four enums (`triggering_child`, `boundary`, `decision_record_sub_shape`, `plan_execution_mode`) and states that their values MUST be re-validated against the declared enums BEFORE constructing write paths or interpolating into shell commands. State-file tampering between sessions is closed.

- [ ] **Stale `parent_orchestration:` self-heal documented.** Phase 0 prose names the unconditional clear of any stale `parent_orchestration:` block found at session start (no author prompt, no warning surface — the self-heal is the contract).

- [ ] **No untrusted-input interpolation surface added.** The SKILL.md prose does NOT name any pattern that interpolates author-supplied content directly into `-m "<string>"` shell arguments (rejection rationale interpolation lives in <<ISSUE:3>> and <<ISSUE:5>> using `git commit -F -` stdin per Component 8's Security Considerations mitigation; this SKILL.md only consumes the discard-commit signal via `git log`, which reads metadata, not author-supplied content).

- [ ] **Visibility boundary stated.** Body declares `/scope` v1 binds to public-repo tactical chains exclusively (matching shirabe's repo visibility); future cross-visibility extension MUST re-state placement discipline in its own PR with explicit public-vs-private content-governance review.

- [ ] **No secrets, tokens, or credentials referenced in SKILL.md prose.** No example commands embed actual secret values; no environment-variable names that imply private credentials.

- [ ] **No supply-chain or external-fetch surface introduced.** SKILL.md adds no runtime dependencies; references only existing pattern files in this repo plus the new top-level reference from <<ISSUE:1>>; cites no external URL for download or execution.

- [ ] **Concurrent-multi-topic race not introduced.** Body states the state file is topic-keyed (`wip/scope_<topic>_state.md`), so two simultaneous `/scope foo` and `/scope bar` invocations do not contend; same-topic concurrent invocations on the same working tree are documented as an explicit no-go pattern.

## Dependencies

Blocked by <<ISSUE:1>>, <<ISSUE:7>>, <<ISSUE:8>>, <<ISSUE:9>>

- **<<ISSUE:1>>** ships `references/parent-skill-worktree-discipline.md`. The Reference Files table cites it; the Phase 2 row in the Workflow Phases diagram names the worktree-staleness check sourced from this reference.
- **<<ISSUE:7>>** ships the Gate Vocabulary section + L13 amendment in `references/parent-skill-pattern.md`. The SKILL.md's prose binding the Mandatory-with-auto-skip gate (for `/prd`) cites the new Gate Vocabulary entry; the State File Schema section's `parent_orchestration:` ephemeral block cites the L13 amendment.
- **<<ISSUE:8>>** ships the `boundary:` / `plan_execution_mode:` conditional-field bullets and R9 additions in `references/parent-skill-state-schema.md`. The SKILL.md's State File Schema and R8 / R10 prose cite these field definitions.
- **<<ISSUE:9>>** ships the refuse-and-redirect Slot 5 paragraph in `references/parent-skill-resume-ladder-template.md`. The SKILL.md's Resume Logic section cites that paragraph for the PLAN-Active / PLAN-Done rows.

## Downstream Dependencies

- **<<ISSUE:11>>** — Creates the five phase reference files at `skills/scope/references/phases/phase-{0..4}-*.md`. <<ISSUE:11>> consumes this SKILL.md's Phase Execution list (the canonical phase reference paths cited in its rows) and the Workflow Phases diagram (the per-phase sub-step ordering). The SKILL.md authored by this issue is the structural envelope; <<ISSUE:11>> fills in each phase's body.
- **<<ISSUE:12>>** — Creates the four Decision Record body templates at `skills/scope/references/decision-record-{prd|design}-{re-evaluation|rejection}.md`. <<ISSUE:12>> consumes this SKILL.md's Three Exit Paths prose section (the canonical Decision Record path enumeration and the four boundary × sub-shape combination naming).
- **<<ISSUE:13>>** — Creates the eleven-scenario eval suite at `skills/scope/evals/evals.json` plus the shirabe `CLAUDE.md` "Tactical Chain Entry: /scope" section. <<ISSUE:13>>'s eval scenarios exercise the literal-substring contracts authored here: AC1, AC1b, AC2, AC3, AC3b, AC4, AC9 (Proceed/Adjust/Bail triad), AC9b/AC9c (Adjust/Bail routing), AC16b (--max-rounds=5 default), AC17a/AC17b (Re-evaluate/Revise/Bail triad at PRD/DESIGN boundaries), AC17c (refuse-and-redirect literals for PLAN-Active/Done), AC19 (visibility-detection warning phrase), AC13 (abandonment-forced HTML-comment marker substring). The grep-test against this SKILL.md's literal substrings is what makes the eval surface mechanical.

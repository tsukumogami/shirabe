---
complexity: testable
complexity_rationale: New documentation content with objective shape requirements every downstream issue cites; AC verification beyond CI requires file-presence and section-presence grep checks.
---

## Goal

Ship the four pattern-level reference files at top-level `references/` that define the parent-skill contract surface — establishing the shared documentation foundation every downstream issue cites for SKILL.md authoring, state-file schema, resume-ladder template, and child-doc inspection rules.

## Context

This issue implements the foundational documentation layer of the parent-skill pattern. It is the entry point for the full plan — every downstream issue (SKILL.md authoring, Phase 1 discovery, chain-proposal, state-file implementation, resume ladder, exit paths, exit artifacts, evals) cites one or more of these reference files. Authoring the references first means downstream authors converge on shared vocabulary rather than re-deriving the contract per consumer.

Design: `docs/designs/DESIGN-shirabe-progression-authoring.md`

This issue authors against the following design sections:

```
Design Solution Architecture Component 1; Implementation Approach Stage 1
```

The design's Solution Architecture Component 1 enumerates the four files and their semantic content. Implementation Approach Stage 1 names the section skeleton for each file. Components 2-5 (SKILL.md template, two-layer contract, resume-ladder, team-shape declarator) supply the substance the reference files document.

Four files ship at flat top-level `references/` per Design Decision 7 (existing precedent: `cross-repo-references.md`, `decision-protocol.md`, `pipeline-model.md`, `wip-hygiene.md`). Each is loadable as `${CLAUDE_PLUGIN_ROOT}/references/<file>.md` from SKILL.md and phase files.

The four files and what each documents:

1. **`references/parent-skill-pattern.md`** — the contract surface document. Names the two-layer contract (semantic invariants vs reference implementation), the **seven** semantic invariants I-1 through I-7, the three exit paths (full-run, re-evaluation, abandonment-forced), the conditional-feeder integration shape (the three-condition gate per Design Decision 6), the two named substitution surfaces (`storage_substrate` v1 value `wip-yaml-md`, `team_primitive` v1 value `single-team-per-leader-no-nested`), the team-shape declarator mechanism (prose declaration v1, structured metadata v2), the seven SKILL.md structural elements every parent skill SHALL contain, **and a new Team-Lead Operating Discipline section** (added during refinement after the SE4 retrospective). The Team-Lead Operating Discipline section codifies:

   - The **canonical 5-step sleep-check-nudge loop**: dispatch → bounded sleep → filesystem evidence check (priority 1) → inbox processing (priority 2) → nudge with directly-executable instructions (priority 3).
   - The **three terminal exit conditions**: PASS (terminal artifact present and valid, or structured PASS verdict with artifact verification), FAIL (FAIL verdict or artifact validation failure), ESCALATE (patience budget exhausted; default 5 stagnation cycles per teammate; escalation maps to the parent's `abandonment-forced` exit path with a `triggering_teammate:` field).
   - The **task-class timing table**: 30s sleep / 5-cycle budget for review verdicts; 60s / 10-cycle for decomposition/generation; 120s / 10-cycle for implementation passes; 60s / unlimited budget for external waits (CI, network).
   - The **strict priority ordering** within filesystem evidence: terminal artifact present → partial artifact / new commits / wip/ growth → no change since dispatch (decrements patience).
   - The **idle-pings-are-not-inbox-messages** rule.
   - The **nudge content rule**: every nudge SHALL contain directly-executable instructions (what artifact, where, what verdict to reply with); generic nudges are forbidden.
   - The **`ci_outcome` semantics** for CI-driven exits: `passing` (always green) vs `failing_fixed` (flipped green after fix). The two are not interchangeable.
   - Binding notes: `/charter` v1 binds vacuously at the parent-itself layer (single-agent skill, no peer dispatch) and binds concretely at the child-skill dispatch layer (each child invocation is a dispatch in the discipline sense; 120s window / 10-cycle budget for child-skill invocations).

   The pattern reference also includes:

   - The **reviewer-vs-worker role-cardinality distinction** (in the team-shape declarator's worked-example section): reviewer-shaped roles iterate over work items themselves (one architecture-reviewer reviews all N work items in one pass); variable-cardinality worker role types spawn one peer per work item (`/design`'s `decision-researcher`, `/plan`'s `decomposer`). The team-shape declaration MUST distinguish the two.
   - The **discipline-vs-artifact decoupling thesis** paragraph (in the Three Exit Paths section): the three-exit contract operationalizes the principle that strategic conversation can be *disciplined* without being forced to *produce*. Each exit demonstrates a specific decoupling property; the re-evaluation exit's two sub-shapes are the operational proof that a disciplined conversation can conclude at a Decision Record; abandonment-forced is the proof that even a bailed chain ends at a review surface.
   - The **parents-don't-extend-children's-input-surfaces** paragraph (in the conditional-feeder / parent-child invocation contract section): when a parent needs to pass semantic context to a child the child has no API for, the parent SHALL NOT add flags to the child. Parents pass through children's existing input modes and rely on the child's own resume logic to detect state. PRD R4's thesis-shift signal is the canonical instance — `/charter` elicits the signal conversationally and invokes `/vision <topic>` with the topic slug alone.
   - The **default-option-wording-as-contract-surface** sentence (in the SKILL.md template section, Component 2 of the design): default-option wording at status-aware re-entry prompts is part of the contract surface, not a UX detail; specify as literal-substring requirements in ACs.

2. **`references/parent-skill-state-schema.md`** — 5-field minimum state-file vocabulary plus extension discipline. Names the five required fields (`topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`), their per-field semantics, the four pattern-level invariants the schema enforces (per-child snapshot dual-check with per-parent fingerprint binding, conditional-field gating (R9 null-prohibition), chain-tracking with MAY-omit for non-chain-shaped parents, status-aware re-entry control), the extension-discipline rules for parent-specific additions, the R9 hard-finalization check specification, and the topic-slug regex `^[a-z0-9-]+$` cited by every parent SKILL.md.

3. **`references/parent-skill-resume-ladder-template.md`** — universal meta-ladder entries plus parent-specific body slots. Names meta-ladder entries 1-4 (malformed → exit set → fresh resume → stale-session) and 8-9 (on-topic branch → main fallback) whose semantics are pattern-level fixed; names parent-specific body slots 5-7 (status-aware re-entry slot, partial-child-run slot, feeder-doc-detected slot) and rules for filling them; documents malformed-state-file handling as a hard surface (error plus Discard recovery, no silent fall-through); names the stale-session threshold as a parametric pattern-level concept whose numeric value each parent sets.

4. **`references/parent-skill-child-inspection.md`** — the R14-widened isolation rule plus per-parent surface table. Names the widened rule (parent reads only the child's durable externally-visible status surface; never internals); names the per-parent surface table with one row per child shape (doc-emitting children → frontmatter `status:` + git blob hash; issue/PR children → state + labels + CI check rollup); names the drift-detection semantics (drift fires when EITHER snapshot field differs from live); names what counts as "internals" with negative examples (`wip/research/<child>_*.md`, CI logs, comment threads, internal phase-pointer state).

I-6 (cross-branch resume) is load-bearing: the v1 core-layer implementation explicitly does NOT satisfy I-6, and the pattern documents this gap as the amplifier-layer's mandate. Documenting I-6 as a pattern invariant that v1 does not satisfy is the forcing function the amplifier layer's value proposition depends on.

The `wip/...` path references in the design are contract specifications for the `wip-yaml-md` storage substrate, NOT orphan staging pointers; the references files MAY cite them as substrate-specific paths without violating the wip-hygiene rule.

## Acceptance Criteria

- [ ] `references/parent-skill-pattern.md` exists.
- [ ] `references/parent-skill-state-schema.md` exists.
- [ ] `references/parent-skill-resume-ladder-template.md` exists.
- [ ] `references/parent-skill-child-inspection.md` exists.
- [ ] Each of the four files starts with a `#` top-level markdown heading matching the file's purpose.
- [ ] `parent-skill-pattern.md` contains a "Two-Layer Contract" section (overview of semantic invariants vs reference implementation).
- [ ] `parent-skill-pattern.md` documents semantic invariants I-1, I-2, I-3, I-4, I-5, I-6, and I-7 by name with one-line semantics each.
- [ ] `parent-skill-pattern.md` documents I-6 as a pattern invariant the v1 core-layer implementation explicitly does NOT satisfy (load-bearing for the amplifier-layer forcing function).
- [ ] `parent-skill-pattern.md` documents I-7 (Active Orchestration) as the named invariant binding the team-lead operating discipline; semantic: a parent's team-lead MUST NOT transition to passive wait while dispatched teammates are in flight.
- [ ] `parent-skill-pattern.md` contains a "Team-Lead Operating Discipline" section codifying the 5-step sleep-check-nudge loop (dispatch → sleep → filesystem check → inbox check → nudge).
- [ ] The Team-Lead Operating Discipline section names the strict three-priority ordering: filesystem evidence (priority 1) before inbox messages (priority 2) before nudges (priority 3).
- [ ] The Team-Lead Operating Discipline section names the three terminal exit conditions: PASS, FAIL, ESCALATE.
- [ ] The Team-Lead Operating Discipline section names the patience budget as 5 stagnation cycles for the default review-verdict task class; stagnation = no progress in filesystem OR inbox; progress evidence resets the budget implicitly.
- [ ] The Team-Lead Operating Discipline section contains a task-class timing table with at least four rows: review verdict (30s / 5 cycles), decomposition/generation (60s / 10 cycles), implementation pass (120s / 10 cycles), external wait (60s / unlimited).
- [ ] The Team-Lead Operating Discipline section names the nudge-content rule: nudges MUST contain directly-executable instructions (artifact, location, structured verdict); generic nudges ("what's happening?") are forbidden.
- [ ] The Team-Lead Operating Discipline section names the `ci_outcome` distinction: `passing` (CI always green) vs `failing_fixed` (flipped green after fix).
- [ ] `parent-skill-pattern.md` contains a paragraph distinguishing reviewer-shaped roles (iterate over work items themselves; one reviewer reviews all N) from variable-cardinality worker role types (spawn one peer per work item).
- [ ] `parent-skill-pattern.md` contains a paragraph naming the discipline-vs-artifact decoupling thesis as the underlying principle behind the three-exit contract.
- [ ] `parent-skill-pattern.md` contains a paragraph stating that parents do not extend children's input surfaces; parents pass through children's existing input modes and rely on the child's own resume logic for state detection.
- [ ] `parent-skill-pattern.md` contains a sentence stating that default-option wording at status-aware re-entry prompts is part of the contract surface, specified as literal-substring requirements in ACs.
- [ ] `parent-skill-pattern.md` names all three exit paths: full-run, re-evaluation, abandonment-forced — with one-line characterizations (per-parent binding details deferred to each parent's SKILL.md).
- [ ] `parent-skill-pattern.md` contains a "Conditional Feeder Invocation Shape" section that names the three-condition gate: (1) parent-defined Phase 1 discovery signal fires, (2) the feeder skill exists on disk, (3) parent-defined visibility gate passes.
- [ ] `parent-skill-pattern.md` names both substitution surfaces: `storage_substrate` (with v1 value `wip-yaml-md`) and `team_primitive` (with v1 value `single-team-per-leader-no-nested`).
- [ ] `parent-skill-pattern.md` documents the team-shape declarator mechanism: prose declaration in SKILL.md for v1, structured metadata as the v2 amplifier-layer evolution.
- [ ] `parent-skill-pattern.md` enumerates the seven required SKILL.md structural elements: Input Modes, execution-mode flag parsing, topic-slug constraint, Workflow Phases diagram, Resume Logic ladder, Phase Execution list, Reference Files table.
- [ ] `parent-skill-state-schema.md` names all five minimum required fields: `topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`.
- [ ] `parent-skill-state-schema.md` names all four pattern-level invariants: per-child snapshot dual-check, conditional-field gating, chain-tracking, status-aware re-entry control.
- [ ] `parent-skill-state-schema.md` documents the R9 Hard-Finalization Check Spec: exit valid + sub-shape valid when applicable + conditional fields absent when triggering condition does not hold.
- [ ] `parent-skill-state-schema.md` cites the topic-slug regex `^[a-z0-9-]+$`.
- [ ] `parent-skill-state-schema.md` names the chain-tracking fields (`planned_chain`, `chain_ran`, `chain_skipped`) and documents them as conditional on chain-shaped parents (MAY-omit for non-chain-shaped parents).
- [ ] `parent-skill-resume-ladder-template.md` documents meta-ladder entries 1, 2, 3, 4 (malformed → exit set → fresh resume → stale-session) and entries 8, 9 (on-topic branch → main fallback).
- [ ] `parent-skill-resume-ladder-template.md` documents parent-specific body slots 5, 6, 7 (status-aware re-entry, partial-child-run, feeder-doc-detected) and rules for filling them.
- [ ] `parent-skill-resume-ladder-template.md` documents malformed-state-file handling as a hard error plus Discard recovery (no silent fall-through).
- [ ] `parent-skill-resume-ladder-template.md` documents the stale-session threshold as a parametric pattern-level concept whose numeric value each parent sets.
- [ ] `parent-skill-child-inspection.md` documents the R14-widened isolation rule: parent reads only the child's durable externally-visible status surface; never internals.
- [ ] `parent-skill-child-inspection.md` contains a per-parent surface table with at least two rows: doc-emitting children (frontmatter `status:` + git blob hash) and issue/PR children (state + labels + CI check rollup).
- [ ] `parent-skill-child-inspection.md` documents drift-detection semantics: drift fires when EITHER snapshot field differs from live (status OR fingerprint).
- [ ] `parent-skill-child-inspection.md` contains a negative-examples section enumerating what counts as "internals": `wip/research/<child>_*.md`, CI logs, comment threads, internal phase-pointer state.
- [ ] `parent-skill-pattern.md` cross-cites the other three reference files using their `${CLAUDE_PLUGIN_ROOT}/references/<file>.md` paths.
- [ ] `parent-skill-state-schema.md` cites R9 as the source requirement for the hard-finalization check spec.
- [ ] Content discipline: no private-repo references, no internal tooling names, no pre-announcement features.
- [ ] Must deliver: the four reference files exist at the published paths so `skills/charter/SKILL.md`'s Reference Files table cites them with valid `${CLAUDE_PLUGIN_ROOT}/references/<file>.md` paths (required by <<ISSUE:2>>).
- [ ] Must deliver: `parent-skill-child-inspection.md` exists with R13 manual-fallback non-interference framing named (required by <<ISSUE:3>>).
- [ ] Must deliver: `parent-skill-pattern.md` exists with the Conditional Feeder Invocation Shape section naming the three-condition gate (required by <<ISSUE:4>>).
- [ ] Must deliver: `parent-skill-state-schema.md` exists with the 5-field minimum named, the extension-discipline rules documented, and the R9 Hard-Finalization Check Spec authored (required by <<ISSUE:5>>).
- [ ] Must deliver: `parent-skill-resume-ladder-template.md` exists with meta-ladder entries 1-4 + 8-9 specified and parent-specific body slots 5-7 documented (required by <<ISSUE:6>>).
- [ ] Must deliver: `parent-skill-pattern.md` exists with the three named exit paths (full-run, re-evaluation, abandonment-forced) characterized (required by <<ISSUE:7>>).
- [ ] Must deliver: `parent-skill-state-schema.md` documents conditional-field gating discipline (required by <<ISSUE:8>>).
- [ ] Must deliver: `parent-skill-state-schema.md` exists with the malformed-state-file error mode named for the shared eval baseline (required by <<ISSUE:9>>).

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

# File-presence checks
test -f references/parent-skill-pattern.md
test -f references/parent-skill-state-schema.md
test -f references/parent-skill-resume-ladder-template.md
test -f references/parent-skill-child-inspection.md

# Top-of-file H1 heading checks
grep -qE '^# ' references/parent-skill-pattern.md
grep -qE '^# ' references/parent-skill-state-schema.md
grep -qE '^# ' references/parent-skill-resume-ladder-template.md
grep -qE '^# ' references/parent-skill-child-inspection.md

# parent-skill-pattern.md required sections / content
grep -q 'Two-Layer Contract' references/parent-skill-pattern.md
grep -q 'I-1' references/parent-skill-pattern.md
grep -q 'I-2' references/parent-skill-pattern.md
grep -q 'I-3' references/parent-skill-pattern.md
grep -q 'I-4' references/parent-skill-pattern.md
grep -q 'I-5' references/parent-skill-pattern.md
grep -q 'I-6' references/parent-skill-pattern.md
grep -q 'I-7' references/parent-skill-pattern.md
grep -q 'Active Orchestration' references/parent-skill-pattern.md
grep -q 'Team-Lead Operating Discipline' references/parent-skill-pattern.md
grep -qE '(sleep-check-nudge|sleep.check.nudge)' references/parent-skill-pattern.md
grep -qE '(filesystem.*before.*inbox|filesystem evidence.*priority 1)' references/parent-skill-pattern.md
grep -qE '(PASS.*FAIL.*ESCALATE|ESCALATE.*patience)' references/parent-skill-pattern.md
grep -qE '(patience budget|5 stagnation|5.cycle)' references/parent-skill-pattern.md
grep -qE '(directly[- ]executable|directly executable)' references/parent-skill-pattern.md
grep -qE '(ci_outcome|failing_fixed)' references/parent-skill-pattern.md
grep -qE '(reviewer.shaped|reviewer-shaped|variable-cardinality)' references/parent-skill-pattern.md
grep -qE '(discipline.vs.artifact|discipline-vs-artifact)' references/parent-skill-pattern.md
grep -qE '(do not extend|don.t extend).*input surfaces' references/parent-skill-pattern.md
grep -qE '(default[- ]option wording|default-option wording)' references/parent-skill-pattern.md
grep -q 'full-run' references/parent-skill-pattern.md
grep -q 're-evaluation' references/parent-skill-pattern.md
grep -q 'abandonment-forced' references/parent-skill-pattern.md
grep -q 'Conditional Feeder' references/parent-skill-pattern.md
grep -q 'storage_substrate' references/parent-skill-pattern.md
grep -q 'wip-yaml-md' references/parent-skill-pattern.md
grep -q 'team_primitive' references/parent-skill-pattern.md
grep -q 'single-team-per-leader-no-nested' references/parent-skill-pattern.md
grep -q 'Team-Shape Declarator' references/parent-skill-pattern.md
grep -q 'Input Modes' references/parent-skill-pattern.md
grep -q 'Workflow Phases' references/parent-skill-pattern.md
grep -q 'Resume Logic' references/parent-skill-pattern.md
grep -q 'Phase Execution' references/parent-skill-pattern.md
grep -q 'Reference Files' references/parent-skill-pattern.md

# Cross-citation checks (pattern.md references the other three)
grep -q 'parent-skill-state-schema.md' references/parent-skill-pattern.md
grep -q 'parent-skill-resume-ladder-template.md' references/parent-skill-pattern.md
grep -q 'parent-skill-child-inspection.md' references/parent-skill-pattern.md

# parent-skill-state-schema.md required content
grep -qE '(^|[^_a-z])topic([^_a-z]|$)' references/parent-skill-state-schema.md
grep -q 'last_updated' references/parent-skill-state-schema.md
grep -q 'phase_pointer' references/parent-skill-state-schema.md
grep -qE '(^|[^_a-z])exit([^_a-z]|$)' references/parent-skill-state-schema.md
grep -q 'exit_artifacts' references/parent-skill-state-schema.md
grep -q 'per-child snapshot dual-check' references/parent-skill-state-schema.md
grep -q 'conditional-field gating' references/parent-skill-state-schema.md
grep -q 'chain-tracking' references/parent-skill-state-schema.md
grep -q 'status-aware re-entry' references/parent-skill-state-schema.md
grep -q 'Extension Discipline' references/parent-skill-state-schema.md
grep -q 'R9' references/parent-skill-state-schema.md
grep -q 'Hard-Finalization' references/parent-skill-state-schema.md
grep -qF '^[a-z0-9-]+$' references/parent-skill-state-schema.md
grep -q 'planned_chain' references/parent-skill-state-schema.md
grep -q 'chain_ran' references/parent-skill-state-schema.md
grep -q 'chain_skipped' references/parent-skill-state-schema.md

# parent-skill-resume-ladder-template.md required content
grep -qE '(1\.|^1 |entry 1)' references/parent-skill-resume-ladder-template.md
grep -q 'malformed' references/parent-skill-resume-ladder-template.md
grep -q 'exit' references/parent-skill-resume-ladder-template.md
grep -q 'stale-session' references/parent-skill-resume-ladder-template.md
grep -qE '(8\.|entry 8)' references/parent-skill-resume-ladder-template.md
grep -qE '(9\.|entry 9)' references/parent-skill-resume-ladder-template.md
grep -q 'status-aware re-entry' references/parent-skill-resume-ladder-template.md
grep -q 'partial-child-run' references/parent-skill-resume-ladder-template.md
grep -q 'feeder-doc-detected' references/parent-skill-resume-ladder-template.md
grep -q 'Discard' references/parent-skill-resume-ladder-template.md
grep -q 'threshold' references/parent-skill-resume-ladder-template.md

# parent-skill-child-inspection.md required content
grep -q 'durable externally-visible status surface' references/parent-skill-child-inspection.md
grep -q 'frontmatter' references/parent-skill-child-inspection.md
grep -q 'git blob hash' references/parent-skill-child-inspection.md
grep -qE '(issue|PR)' references/parent-skill-child-inspection.md
grep -q 'labels' references/parent-skill-child-inspection.md
grep -q 'CI check rollup' references/parent-skill-child-inspection.md
grep -q 'Drift' references/parent-skill-child-inspection.md
grep -q 'internals' references/parent-skill-child-inspection.md
grep -q 'wip/research' references/parent-skill-child-inspection.md
grep -q 'manual' references/parent-skill-child-inspection.md

echo "All validations passed"
```

## Dependencies

None — this is the foundational issue.

## Downstream Dependencies

This issue unblocks the rest of the plan. Every downstream issue depends on at least one of the four reference files existing at its published path. Specific deliverables (mirrored in Acceptance Criteria above):

- `<<ISSUE:2>>` — `skills/charter/SKILL.md` cites the four references via the Reference Files table (R1 structural element 7). Requires all four files exist at the published paths.
- `<<ISSUE:3>>` — Phase 1 discovery prose cites `parent-skill-child-inspection.md` for the manual-fallback non-interference framing. Requires child-inspection.md exists with the R13 manual-fallback discipline named.
- `<<ISSUE:4>>` — chain-proposal prompt and child invocation cite `parent-skill-pattern.md` for the conditional-feeder shape (R5 `/comp` invocation uses the three-condition gate). Requires pattern.md exists with the Conditional Feeder Invocation Shape section.
- `<<ISSUE:5>>` — state-file schema implementation cites `parent-skill-state-schema.md` for the 5-field minimum, the extension discipline, and the R9 spec. Requires state-schema.md exists with the 5-field minimum named and the R9 Hard-Finalization Check Spec authored.
- `<<ISSUE:6>>` — resume-ladder implementation cites `parent-skill-resume-ladder-template.md` for the universal meta-ladder rows and the body-slot rules. Requires resume-ladder-template.md exists with meta-ladder entries 1-4 + 8-9 specified and parent-specific body slots 5-7 documented.
- `<<ISSUE:7>>` — exit paths cite `parent-skill-pattern.md` for the three named exits. Requires pattern.md exists with full-run / re-evaluation / abandonment-forced characterized.
- `<<ISSUE:8>>` — exit-artifact authoring cites `parent-skill-state-schema.md` for the conditional-field gating discipline (Decision Records carry sub-shape-conditional fields; abandonment-forced carries triggering-child fields). Requires state-schema.md documents conditional-field gating.
- `<<ISSUE:9>>` — evals cite `parent-skill-state-schema.md` for the malformed-state-file scenario (shared eval baseline). Requires state-schema.md exists with the malformed-state error mode named.

---
complexity: critical
complexity_rationale: State file is the contract enforcement spine for the entire /charter chain — schema malformation surfaces as a hard error in Issue 6's resume ladder, and the R9 hard finalization check is the contract violation surface that AC15 directly asserts; touches public-repo durable-evidence exposure surface so Security Checklist is required.
---

## Goal

Ship `skills/charter/references/phases/phase-state-management.md` specifying the full `/charter` state-file schema at `wip/charter_<topic>_state.md` per PRD R10 (pure YAML body with `.md` extension; 5-field minimum from `parent-skill-state-schema.md` plus the eleven `/charter`-specific extensions and conditional fields), and the R9 hard finalization check that fails finalization when `exit:` is unset/invalid, when `decision_record_sub_shape:` is unset/invalid for an `exit: re-evaluation` chain, or when conditional fields are present-but-inapplicable or set to null/empty/placeholder values.

## Context

`/charter` is the first parent skill in the shirabe parent-skill pattern; the state file at `wip/charter_<topic>_state.md` is the durable contract evidence for every run. The four pattern-level reference files landed by `<<ISSUE:1>>` define the 5-field minimum (`topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`), the four pattern-level invariants (per-child snapshot dual-check, conditional-field gating, chain-tracking, status-aware re-entry control), and the R9 hard-finalization check spec at the pattern layer. `<<ISSUE:2>>` shipped the SKILL.md whose Resume Logic prelude names `wip/charter_<topic>_state.md` as the canonical state-file path. This issue authors the `/charter`-specific binding: every field the R10 schema requires, the gating discipline that controls when conditional fields MUST be present versus MUST be absent, and the procedural specification for the finalization check that Issue 7's exit-path orchestration runs at chain completion.

The state file is **pure YAML** despite the `.md` extension — the extension matches shirabe's `wip/` convention for committed intermediates, the body has no markdown. This is verbatim from R10 and is preserved as-is.

The R9 hard finalization check is the contract enforcement mechanism. A `/charter` run that completes without a valid `exit:` is a contract violation and MUST be surfaced as a clear error — not silently absorbed, not soft-warned, not skipped. AC15 directly asserts this behavior. Without the check, the state file would silently accept malformed terminal records and the resume ladder (Issue 6) would have no contract surface to enforce against.

This issue ships the **specification** of the schema and the finalization check. The runtime implementation lives downstream: Issue 6's resume ladder consumes the schema's field definitions and conditional-field rules to know what to read; Issue 7's exit-path orchestration writes the `exit:`, `decision_record_sub_shape:`, `exit_artifacts`, and exit-specific conditional fields, and runs the finalization check at chain completion; Issue 8's exit-artifact authoring populates `exit_artifacts` paths plus the rejection sub-shape's `discard_commit_sha` and `rejection_rationale`.

Design: `docs/designs/DESIGN-shirabe-progression-authoring.md` (Solution Architecture Component 3 — Two-Layer Contract reference implementation with 5-field minimum plus parent-specific extensions; Decision 2 — `storage_substrate` substitution surface, I-6 cross-branch invariant unsatisfied in v1; Decision 3 — 5-field minimum plus four pattern-level invariants; Security Considerations — public-repo pre-merge visibility of `wip/` state files).

PRD: `docs/prds/PRD-shirabe-charter-skill.md` (R9 hard finalization check, R10 full state-file schema; ACs AC11a, AC11b, AC15).

## Acceptance Criteria

### File presence

- [ ] `skills/charter/references/phases/phase-state-management.md` exists.
- [ ] The file is cited from `skills/charter/SKILL.md` (either from the Phase Execution section or from the Resume Logic prelude) so the schema is discoverable from the SKILL entrypoint.

### Pure-YAML-with-`.md`-extension convention

- [ ] The file states the state file at `wip/charter_<topic>_state.md` is pure YAML despite the `.md` extension.
- [ ] The file names the rationale (extension matches shirabe's `wip/` convention for committed intermediates; body has no markdown) so authors and tooling do not parse it as markdown.

### 5-field minimum citation

- [ ] The file cites `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` as the source of the 5-field minimum (`topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`) — citation, not re-derivation.
- [ ] The file names the four pattern-level invariants from `parent-skill-state-schema.md` (per-child snapshot dual-check, conditional-field gating, chain-tracking, status-aware re-entry control) as the contract layer `/charter`'s schema satisfies.

### Full R10 field documentation

Every one of the following fields is documented in `phase-state-management.md` with its type, semantics, and gating condition (when applicable):

- [ ] `topic` — topic-slug string matching `^[a-z0-9-]+$`; always present.
- [ ] `chain_started` — ISO-8601 timestamp; set once at Phase 0 entry.
- [ ] `chain_completed` — ISO-8601 timestamp; set at finalization (full-run, re-evaluation, or abandonment-forced).
- [ ] `last_updated` — ISO-8601 timestamp; set on every state-file write.
- [ ] `planned_chain` — ordered list naming which children are in scope (`vision?`, `comp?`, `strategy`, `roadmap?`); always present.
- [ ] `chain_ran` — ordered sub-list of `planned_chain` naming children that completed.
- [ ] `chain_skipped` — free-text list `[{child, reason}, ...]` for humans; not parsed by tooling.
- [ ] `exit` — one of `{full-run, re-evaluation, abandonment-forced}`; set at finalization.
- [ ] `decision_record_sub_shape` — one of `{re-evaluation, rejection}`; conditional on `exit: re-evaluation`.
- [ ] `exit_artifacts` — list of `{path, status}` entries; status drawn from `{Draft, Accepted, Active}`.
- [ ] `child_snapshots` — per-child block at last exit, with `path`, `status`, and `content_hash` (git blob hash) per child in `planned_chain`.
- [ ] `referenced_strategy` — path string; conditional on `decision_record_sub_shape: re-evaluation`.
- [ ] `discard_commit_sha` — git SHA string; conditional on `decision_record_sub_shape: rejection`.
- [ ] `rejection_rationale` — free-text string; conditional on `decision_record_sub_shape: rejection`.
- [ ] `triggering_child` — child-name string; conditional on `exit: abandonment-forced`.
- [ ] `partial_phase_reached` — phase-name string; conditional on `exit: abandonment-forced`.

### Conditional-field gating discipline (R9)

The file enumerates the gating rules, one per conditional field:

- [ ] `decision_record_sub_shape` required iff `exit: re-evaluation`; MUST be absent otherwise.
- [ ] `referenced_strategy` required iff `decision_record_sub_shape: re-evaluation`; MUST be absent otherwise.
- [ ] `discard_commit_sha` required iff `decision_record_sub_shape: rejection`; MUST be absent otherwise.
- [ ] `rejection_rationale` required iff `decision_record_sub_shape: rejection`; MUST be absent otherwise.
- [ ] `triggering_child` required iff `exit: abandonment-forced`; MUST be absent otherwise.
- [ ] `partial_phase_reached` required iff `exit: abandonment-forced`; MUST be absent otherwise.
- [ ] The file states conditional fields MUST be absent (not set to null, empty string, or placeholder) when their triggering condition does not hold.

### R9 hard finalization check specification

- [ ] The file documents the R9 hard finalization check as a finalization-time procedure (not a resume-time check; runs when the chain reaches finalization).
- [ ] The check enumerates all four failure modes:
  1. `exit:` is unset or not in `{full-run, re-evaluation, abandonment-forced}`.
  2. `exit: re-evaluation` AND `decision_record_sub_shape:` is unset or not in `{re-evaluation, rejection}`.
  3. Conditional fields are present when their triggering condition does not hold (e.g., `referenced_strategy` set when `exit: full-run`).
  4. Conditional fields are set to null, empty string, or placeholder when their triggering condition does not hold (they MUST be absent, not falsy).
- [ ] The file states the check surfaces a clear error naming the specific failure mode (not silent absorption, not a soft warning).
- [ ] The file states the check is the contract enforcement mechanism for the parent-skill pattern — a chain that completes without recording a valid exit is a violation, and the check is the surface that makes it so.

### Per-AC mapping (AC11a, AC11b, AC15)

- [ ] **AC11a coverage**: the schema specification supports a STRATEGY-only full-run terminal state — `exit: full-run`, `exit_artifacts` lists exactly one entry pointing to `docs/strategies/STRATEGY-<topic>.md` with a status drawn from `{Draft, Accepted, Active}`. The file's `exit_artifacts` documentation makes this expressible.
- [ ] **AC11b coverage**: the schema specification supports a STRATEGY + ROADMAP full-run terminal state — `exit: full-run`, `exit_artifacts` lists two entries (the STRATEGY path and the ROADMAP path), each with its own status. The file's `exit_artifacts` documentation makes the two-entry shape expressible.
- [ ] **AC15 coverage**: the R9 hard finalization check section enumerates the four failure modes above and states they cause a clear error at finalization — directly satisfying the AC15 wording ("fails finalization with a clear error").

### Downstream deliverables

- [ ] Must deliver: every field in `chain_ran`, `chain_completed`, `exit`, `decision_record_sub_shape`, `exit_artifacts`, plus the exit-specific conditional fields (`referenced_strategy`, `discard_commit_sha`, `rejection_rationale`, `triggering_child`, `partial_phase_reached`) is documented with its semantics so Issue 7's exit-path orchestration knows what to write (required by `<<ISSUE:7>>`).
- [ ] Must deliver: the full set of field names, types, and conditional-presence rules is documented so Issue 6's resume ladder knows which fields to read, which are required, which are conditional, and how to detect a malformed state file as a hard error (required by `<<ISSUE:6>>`).
- [ ] Must deliver: `exit_artifacts` (path + status), `discard_commit_sha`, and `rejection_rationale` are documented so Issue 8's exit-artifact authoring can populate them with the correct shape (required by `<<ISSUE:8>>`).
- [ ] Must deliver: the R9 finalization check failure modes are documented so Issue 9's evals can assert each failure mode against a malformed-state-file scenario (required by `<<ISSUE:9>>`).

- [ ] Security review completed

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

# Schema spec file presence
test -f skills/charter/references/phases/phase-state-management.md

# All R10 field names documented
for field in topic chain_started chain_completed last_updated planned_chain \
             chain_ran chain_skipped exit decision_record_sub_shape \
             exit_artifacts child_snapshots referenced_strategy \
             discard_commit_sha rejection_rationale triggering_child \
             partial_phase_reached; do
  grep -q "$field" skills/charter/references/phases/phase-state-management.md
done

# 5-field minimum citation to pattern-level reference
grep -q "parent-skill-state-schema.md" skills/charter/references/phases/phase-state-management.md

# Plugin-root citation form for the pattern-level reference
grep -qF '${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md' skills/charter/references/phases/phase-state-management.md

# Pure-YAML-with-.md-extension convention documented
grep -qiE '(pure YAML|YAML body|YAML.*\.md extension|\.md extension.*YAML)' skills/charter/references/phases/phase-state-management.md

# R9 finalization check documented
grep -qE '(R9|hard.finalization|finalization check)' skills/charter/references/phases/phase-state-management.md

# All three exit values named
grep -qE '(full-run|re-evaluation|abandonment-forced)' skills/charter/references/phases/phase-state-management.md
grep -qF 'full-run' skills/charter/references/phases/phase-state-management.md
grep -qF 're-evaluation' skills/charter/references/phases/phase-state-management.md
grep -qF 'abandonment-forced' skills/charter/references/phases/phase-state-management.md

# Sub-shape gating
grep -qE '(re-evaluation|rejection).*sub.shape' skills/charter/references/phases/phase-state-management.md

# Conditional-field discipline (absence-when-not-applicable wording)
grep -qE '(conditional|MUST be absent|MUST NOT be set to null)' skills/charter/references/phases/phase-state-management.md

# Topic-slug regex cited
grep -qF '^[a-z0-9-]+$' skills/charter/references/phases/phase-state-management.md

# State-file canonical path named
grep -qF 'wip/charter_' skills/charter/references/phases/phase-state-management.md

# child_snapshots dual-check fields (path + status + content_hash)
grep -qF 'content_hash' skills/charter/references/phases/phase-state-management.md

# SKILL.md cites the phase-state-management file
grep -qF 'phase-state-management.md' skills/charter/SKILL.md

echo "All validations passed"
```

## Security Checklist

The `/charter` schema spec touches a public-repo durable-evidence surface: per the Design Security Considerations, `wip/<parent>_<topic>_state.md` is durably public on feature branches from push time, and squash-merge does not remove pre-merge feature-branch history. The schema documentation must surface this property to authors and must enforce input-validation invariants that prevent the schema from being weaponized as a path-traversal or schema-confusion vector.

- [ ] State-file schema documentation warns authors that public-repo feature branches expose pre-merge `wip/<parent>_<topic>_state.md` content; specifically, `rejection_rationale` and `referenced_strategy` are durably public from the moment the feature branch is pushed.
- [ ] Schema documentation explicitly states no secrets, customer-identifiable context, or unpublished competitive positioning may be pasted into free-text fields (`rejection_rationale`, `chain_skipped.reason`).
- [ ] R9 finalization check fails closed: missing or invalid `exit:` MUST surface a clear error (not absorb, not soft-warn, not skip), preventing silent state loss across `storage_substrate` substitutions when the amplifier layer lands.
- [ ] Topic-slug field validates against `^[a-z0-9-]+$` (no path traversal via slug); the schema spec cites the pattern-level regex source so the constraint cannot drift between SKILL.md, Phase 0 wiring, and this schema spec.
- [ ] Conditional fields enforce absence-when-not-applicable (R9), preventing schema confusion between the three exit types — a `referenced_strategy` set under `exit: full-run` would be a contract violation, not a no-op.
- [ ] No third-party dependencies introduced by the schema spec (documentation-only file; no executable code).
- [ ] Schema spec is documentation-only — no executable validation logic introduced in this issue; validation execution lives in Issue 6's resume ladder (malformed-state detection) and Issue 7's finalization orchestration (R9 check at chain completion).
- [ ] Security review completed.

## Dependencies

Blocked by `<<ISSUE:1>>` (the pattern-level `parent-skill-state-schema.md` reference must exist so this file cites the 5-field minimum and the R9 hard-finalization check spec at `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`).

Blocked by `<<ISSUE:2>>` (`skills/charter/SKILL.md` must exist with the structural skeleton so this file is cited from either the Phase Execution section or the Resume Logic prelude).

## Downstream Dependencies

- `<<ISSUE:6>>` — resume ladder reads `wip/charter_<topic>_state.md` per R11; the ladder needs to know which fields are required, which are conditional, and what counts as a malformed state file. This issue documents the full schema and the conditional-field rules so the ladder has a contract surface to enforce against.
- `<<ISSUE:7>>` — exit-path orchestration writes the schema's `exit:`, `decision_record_sub_shape:`, `chain_ran`, `chain_completed`, `exit_artifacts`, plus the exit-specific conditional fields. This issue documents every field the exit logic must produce and the R9 finalization check that exit logic runs at chain completion.
- `<<ISSUE:8>>` — exit-artifact authoring populates `exit_artifacts` paths plus the rejection sub-shape's `discard_commit_sha` and `rejection_rationale`. This issue documents the field shapes so artifact authoring writes them in the correct form.
- `<<ISSUE:9>>` — evals include the malformed-state-file scenario (part of the shared baseline) plus AC15's finalization-failure scenario. This issue documents the four R9 failure modes so eval assertions can target each one specifically.

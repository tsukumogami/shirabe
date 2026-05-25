---
complexity: testable
complexity_rationale: Authors three documentation-only template files plus prose specification of per-sub-shape body content rules and the STRATEGY validation pass-through; behavior is verifiable by checking template-file presence and named-section/named-alternative substrings, so validation script suffices and no security checklist is required.
---

## Goal

Author the three exit-artifact templates under `skills/charter/references/templates/` (Decision Record re-evaluation, Decision Record rejection, abandonment-forced HTML-comment marker) per PRD R15, and specify the chain-level `shirabe validate --visibility=<repo-visibility>` pass-through that `/charter` runs against the Draft STRATEGY before declaring full-run success — supplying the durable artifact shapes that Issue 7's exit-path orchestration consumes when it writes terminal files.

## Context

Issue 7 ships the **logic** that decides which exit path fires and which fields land in the state file (`exit:`, `decision_record_sub_shape:`, `triggering_child:`, `partial_phase_reached:`, `referenced_strategy:`, `discard_commit_sha:`, `rejection_rationale:`). Issue 8 ships the **artifacts** that consume those fields: two Decision Record templates (re-evaluation sub-shape and rejection sub-shape) and the abandonment-forced HTML-comment marker snippet. The split exists because exit-path logic answers "when does each exit fire?" and artifact authoring answers "what files get written?" — different review surfaces, different downstream consumers.

Both Decision Record sub-shapes land at `docs/decisions/DECISION-strategy-<topic>-<sub-shape>-<YYYY-MM-DD>.md` with the ADR-style body shape per R15: Status, Context, Decision, Options Considered, Consequences. Frontmatter is the same three-field shape across both sub-shapes (`status: {Draft, Accepted}`, `decision:` one-sentence conclusion, `rationale:` 1-3 sentence ~250-char-soft-cap justification). The body content rules differ per sub-shape and are load-bearing for AC12 (re-evaluation) and AC13 (rejection).

The abandonment-forced marker is a single HTML-comment snippet that lives **inside the existing Status section** of whichever child's intermediate artifact got force-materialized (STRATEGY, VISION, or ROADMAP — whichever child was running at bail or stale-session). The marker MUST NOT introduce a new required section, because that would invalidate the artifact-type's own schema validator (AC26). The artifact passes its own validator because the comment is HTML, not prose; consumers (humans + tools) can still grep for `charter-status-block:` to find it.

The Draft STRATEGY validation pass-through is the chain-level enforcement gate: after `/strategy` produces a Draft STRATEGY (full-run exit), `/charter` runs `shirabe validate --visibility=<repo-visibility>` against it as a sub-process and surfaces the validator's error message on failure (AC24). This is NOT a re-validation of `/strategy`'s own schema; it is `/charter`'s chain-level guard that visibility-gated content (e.g., Competitive Considerations in a public-repo STRATEGY, R8 of `shirabe validate`) did not slip through. Visibility is read from Issue 3's `## Repo Visibility:` header detection.

Design: `docs/designs/DESIGN-shirabe-progression-authoring.md` (Solution Architecture — parent ⇄ git interface for rejection sub-shape SHA capture; semantic invariant I-2: every chain ends at a durable file).

PRD: `docs/prds/PRD-shirabe-charter-skill.md` (R15 schema validation requirements; ACs AC12 body content, AC13 body content, AC14 marker, AC24, AC25, AC26).

## Acceptance Criteria

### Template file presence

- [ ] `skills/charter/references/templates/decision-record-re-evaluation.md` exists as a template skeleton with placeholder fields.
- [ ] `skills/charter/references/templates/decision-record-rejection.md` exists as a template skeleton with placeholder fields.
- [ ] `skills/charter/references/templates/abandonment-forced-marker.md` exists as the HTML-comment snippet plus placement instructions.
- [ ] Each template is cited from `skills/charter/SKILL.md` or from a phase reference file under `skills/charter/references/phases/` (decomposer picks; Issue 7's `phase-finalization.md` is a natural home) so the templates are discoverable from the SKILL entrypoint.

### Decision Record common shape (both sub-shapes — AC25)

- [ ] Both Decision Record templates contain the five ADR-style body sections, each as a literal `## ` heading: `## Status`, `## Context`, `## Decision`, `## Options Considered`, `## Consequences`.
- [ ] Both Decision Record templates contain the three frontmatter fields with placeholder values: `status:` (enum value drawn from `{Draft, Accepted}`), `decision:` (single-short-sentence placeholder), `rationale:` (1-3-sentence placeholder noting the ~250-character soft cap).
- [ ] Both Decision Record templates state the filename pattern `docs/decisions/DECISION-strategy-<topic>-<sub-shape>-<YYYY-MM-DD>.md` and cite that the `DECISION-` prefix matches shirabe's `<TYPE>-<name>.md` pattern.
- [ ] Both Decision Record templates note runtime population reads from Issue 5's state-file fields and name the consumed fields by name.

### Re-evaluation Decision Record body content (AC12 body half)

- [ ] The re-evaluation template names the sub-shape filename suffix `re-evaluation` and the full filename pattern `DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md`.
- [ ] The frontmatter `decision:` placeholder reflects the canonical statement (e.g., `"bet still holds; no revision warranted"` or an equivalent prose form).
- [ ] The `## Context` section's placeholder instructs the author to cite at least one named evidence item (URL, file path, or paraphrased finding) and states this MUST be present.
- [ ] The `## Decision` section's placeholder states "bet still holds; no revision warranted" as the decision conclusion.
- [ ] The `## Options Considered` section's placeholder names both `revise the STRATEGY` AND `force-abandon and rewrite` as rejected alternatives (each MUST be present as a literal substring in the template).
- [ ] The `## Consequences` section's placeholder describes what remains in effect (the existing STRATEGY stays Accepted/Active; no ROADMAP regeneration) AND names what triggers the next re-evaluation.
- [ ] The template references the existing STRATEGY by path (citing the state file's `referenced_strategy:` field) — the path is populated at runtime from `referenced_strategy:` (consumed from Issue 5's schema).

### Rejection Decision Record body content (AC13 body half)

- [ ] The rejection template names the sub-shape filename suffix `rejection` and the full filename pattern `DECISION-strategy-<topic>-rejection-<YYYY-MM-DD>.md`.
- [ ] The frontmatter `decision:` placeholder reflects the canonical statement (e.g., `"Draft STRATEGY rejected; no STRATEGY warranted"` or an equivalent prose form).
- [ ] The `## Context` section's placeholder instructs the author to cite the chain's discovery and the Draft STRATEGY's framing, AND to reference the discard commit SHA (populated at runtime from `discard_commit_sha:` per Issue 5's schema).
- [ ] The `## Decision` section's placeholder states "Draft STRATEGY rejected; no STRATEGY warranted" and includes the author's stated rejection rationale (populated at runtime from `rejection_rationale:` per Issue 5's schema).
- [ ] The `## Options Considered` section's placeholder names both `accept the Draft` AND `revise instead of reject` as rejected alternatives (each MUST be present as a literal substring in the template).
- [ ] The `## Consequences` section's placeholder describes the post-rejection state (no STRATEGY on disk; chain discarded; next steps for the strategic question — open it again later, reframe, or drop).

### Abandonment-forced marker (AC14, AC26)

- [ ] `abandonment-forced-marker.md` contains the literal HTML-comment snippet with the substring `charter-status-block: abandonment-forced` and shows the four placeholder fields: `triggering-child: <name>`, `partial-phase-reached: <phase>`, `chain-started: <ISO-8601 timestamp>`.
- [ ] The snippet shape is a single-line HTML comment: `<!-- charter-status-block: abandonment-forced; triggering-child: <name>; partial-phase-reached: <phase>; chain-started: <ISO-8601 timestamp> -->`.
- [ ] The placement instructions state the marker MUST go **inside the force-materialized artifact's existing Status section**, NOT in a new required section that would invalidate the child artifact-type's schema validator.
- [ ] The placement instructions state the marker uses HTML-comment syntax precisely so the child artifact-type's schema validator (STRATEGY, VISION, or ROADMAP — whichever child was running) ignores it as top-level prose AND human/tool consumers can grep for `charter-status-block:` to find it.
- [ ] The instructions name the three child artifact types whose Status sections may host the marker (STRATEGY, VISION, ROADMAP) and state the force-materialized artifact uses the most-recently-running child's intermediate per Issue 7's tie-break.
- [ ] The instructions name the four runtime field values consumed from Issue 5's state-file schema: `triggering_child:`, `partial_phase_reached:`, `chain_started:` (timestamp), and that the marker is emitted whenever `exit: abandonment-forced` is recorded.

### Draft STRATEGY validation pass-through (AC24)

- [ ] The prose specifying the validation pass-through lives in `skills/charter/references/phases/phase-finalization.md` (from Issue 7) OR in `skills/charter/SKILL.md` (decomposer picks; the validation bash accepts either location).
- [ ] The prose states `/charter` MUST invoke `shirabe validate --visibility=<repo-visibility>` as a sub-process against the Draft STRATEGY produced by the full-run exit, before declaring chain success.
- [ ] The prose states the visibility value is read from Issue 3's `## Repo Visibility:` header detection (defaults to Private per R12 when the header is missing).
- [ ] The prose states this is NOT a re-implementation of `shirabe validate` (`/charter` does not duplicate the validator's checks) — it is a chain-level pass-through that catches visibility-gated content `/strategy` did not catch.
- [ ] The prose states a validation failure surfaces the validator's error message verbatim (not absorbed, not paraphrased) and blocks chain finalization until the violation is resolved.
- [ ] The prose names the canonical example violation: a public-repo Draft STRATEGY containing a Competitive Considerations section (R8 of `shirabe validate`).

### Public-repo discipline

- [ ] Neither the three template files nor the validation pass-through prose contains references to private-repo content surfaces (no Competitive Considerations sections inside the Decision Record templates themselves, no private-repo-only artifact types named).
- [ ] The templates' placeholder content is generic enough to land in either a public or private repo (the visibility gating is enforced at populate-time by the pass-through, not at template-authoring time).

### Per-AC mapping

- [ ] **AC12 body coverage**: re-evaluation template includes the four body-content rules (named evidence in Context, both named alternatives in Options Considered, next-re-evaluation trigger in Consequences, existing-STRATEGY-by-path in References).
- [ ] **AC13 body coverage**: rejection template includes the three body-content rules (discard-commit-SHA reference in Context, both named alternatives in Options Considered, post-rejection state in Consequences).
- [ ] **AC14 marker coverage**: abandonment-forced marker template contains the HTML-comment snippet with `charter-status-block: abandonment-forced` substring AND the placement-inside-Status-section instruction.
- [ ] **AC24 coverage**: validation pass-through prose specifies `shirabe validate --visibility=<repo-visibility>` invocation against the Draft STRATEGY.
- [ ] **AC25 coverage**: both Decision Record templates contain the five ADR-style sections plus the three frontmatter fields.
- [ ] **AC26 coverage**: marker placement instructions guarantee the force-materialized artifact passes the child artifact-type's own schema validator (marker is HTML comment inside existing Status section, not a new required section).

### Downstream deliverables

- [ ] Must deliver: three template files at the canonical paths (`decision-record-re-evaluation.md`, `decision-record-rejection.md`, `abandonment-forced-marker.md`) with placeholder content and named ADR sections that Issue 9's evals can assert against (required by `<<ISSUE:9>>`).
- [ ] Must deliver: per-sub-shape body content rules (named evidence, named alternatives, post-state descriptions) authored as literal substrings inside the template skeletons so Issue 9's evals can grep for them in eval scenarios covering AC12, AC13, AC14, AC24, AC25, AC26 (required by `<<ISSUE:9>>`).
- [ ] Must deliver: validation pass-through prose (`shirabe validate --visibility=<repo-visibility>` invocation against Draft STRATEGY) cited from a discoverable location (either `phase-finalization.md` or `SKILL.md`) so Issue 9's eval for AC24 can locate and assert the pass-through specification (required by `<<ISSUE:9>>`).

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

# Templates
test -f skills/charter/references/templates/decision-record-re-evaluation.md
test -f skills/charter/references/templates/decision-record-rejection.md
test -f skills/charter/references/templates/abandonment-forced-marker.md

# Re-evaluation template body sections (literal '## ' headings)
for section in "## Status" "## Context" "## Decision" "## Options Considered" "## Consequences"; do
  grep -qF "$section" skills/charter/references/templates/decision-record-re-evaluation.md
done

# Re-evaluation template Options Considered named alternatives
grep -qF "revise the STRATEGY" skills/charter/references/templates/decision-record-re-evaluation.md
grep -qF "force-abandon and rewrite" skills/charter/references/templates/decision-record-re-evaluation.md

# Re-evaluation template frontmatter fields
grep -qE '^status:' skills/charter/references/templates/decision-record-re-evaluation.md
grep -qE '^decision:' skills/charter/references/templates/decision-record-re-evaluation.md
grep -qE '^rationale:' skills/charter/references/templates/decision-record-re-evaluation.md

# Re-evaluation template names the existing STRATEGY via the referenced_strategy state-file field
grep -qF "referenced_strategy" skills/charter/references/templates/decision-record-re-evaluation.md

# Rejection template body sections (same five)
for section in "## Status" "## Context" "## Decision" "## Options Considered" "## Consequences"; do
  grep -qF "$section" skills/charter/references/templates/decision-record-rejection.md
done

# Rejection template Options Considered named alternatives
grep -qF "accept the Draft" skills/charter/references/templates/decision-record-rejection.md
grep -qF "revise instead of reject" skills/charter/references/templates/decision-record-rejection.md

# Rejection template frontmatter fields
grep -qE '^status:' skills/charter/references/templates/decision-record-rejection.md
grep -qE '^decision:' skills/charter/references/templates/decision-record-rejection.md
grep -qE '^rationale:' skills/charter/references/templates/decision-record-rejection.md

# Rejection template names discard_commit_sha and rejection_rationale state-file fields
grep -qF "discard_commit_sha" skills/charter/references/templates/decision-record-rejection.md
grep -qF "rejection_rationale" skills/charter/references/templates/decision-record-rejection.md

# Decision Record filename pattern (both sub-shapes name the canonical DECISION- prefix path)
grep -qF "DECISION-strategy-" skills/charter/references/templates/decision-record-re-evaluation.md
grep -qF "DECISION-strategy-" skills/charter/references/templates/decision-record-rejection.md

# Abandonment-forced marker snippet substring
grep -qF "charter-status-block: abandonment-forced" skills/charter/references/templates/abandonment-forced-marker.md

# Marker placement instruction names the existing Status section
grep -qE "(Status section)" skills/charter/references/templates/abandonment-forced-marker.md

# Marker fields named: triggering-child, partial-phase-reached, chain-started
grep -qF "triggering-child" skills/charter/references/templates/abandonment-forced-marker.md
grep -qF "partial-phase-reached" skills/charter/references/templates/abandonment-forced-marker.md
grep -qF "chain-started" skills/charter/references/templates/abandonment-forced-marker.md

# Marker names the three host artifact types
grep -qF "STRATEGY" skills/charter/references/templates/abandonment-forced-marker.md
grep -qF "VISION" skills/charter/references/templates/abandonment-forced-marker.md
grep -qF "ROADMAP" skills/charter/references/templates/abandonment-forced-marker.md

# STRATEGY validation pass-through prose (decomposer picks location: phase-finalization.md or SKILL.md)
grep -rqE "shirabe validate" skills/charter/references/ || \
  grep -qE "shirabe validate" skills/charter/SKILL.md

# Pass-through specifies the visibility flag
grep -rqE "shirabe validate.*--visibility" skills/charter/references/ || \
  grep -qE "shirabe validate.*--visibility" skills/charter/SKILL.md

# Templates are discoverable from SKILL.md or a phase reference file
grep -rqF "decision-record-re-evaluation.md" skills/charter/ || \
  grep -qF "decision-record-re-evaluation.md" skills/charter/SKILL.md
grep -rqF "decision-record-rejection.md" skills/charter/ || \
  grep -qF "decision-record-rejection.md" skills/charter/SKILL.md
grep -rqF "abandonment-forced-marker.md" skills/charter/ || \
  grep -qF "abandonment-forced-marker.md" skills/charter/SKILL.md

echo "All validations passed"
```

## Dependencies

Blocked by `<<ISSUE:7>>` (exit-path orchestration decides WHICH artifact to write at chain completion — full-run, re-evaluation, or abandonment-forced — and populates the state-file fields that the templates consume: `referenced_strategy:`, `discard_commit_sha:`, `rejection_rationale:`, `triggering_child:`, `partial_phase_reached:`, `chain_started:`. Issue 8 ships the templates that consume those fields into durable artifacts; without Issue 7's logic and the state-file fields it writes, the templates have no producer to bind to.)

## Downstream Dependencies

- `<<ISSUE:9>>` — evals cover AC12 (re-evaluation body content), AC13 (rejection body content), AC14 (abandonment-forced marker), AC24 (STRATEGY validation pass-through), AC25 (both Decision Record sub-shapes' ADR sections + frontmatter), and AC26 (force-materialized artifact passes child schema with marker). The eval scenarios assert against template content (named sections, named alternatives, marker substring, pass-through invocation), so this issue's deliverable — three template files with the body-content rules as literal substrings, plus the pass-through prose at a discoverable location — is what Issue 9's evals grep against.

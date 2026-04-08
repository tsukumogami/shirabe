# Security Review: plan-skill-rework (Phase 6)

## Review Scope

Reviewed the design at `docs/designs/DESIGN-plan-skill-rework.md`, the Phase 5
security analysis at `wip/research/design_plan-skill-rework_phase5_security.md`,
the current Phase 7 implementation (`skills/plan/references/phases/phase-7-creation.md`),
the batch script (`skills/plan/scripts/create-issues-batch.sh`), and the roadmap
format contract (`skills/roadmap/references/roadmap-format.md`).

## Assessment of Phase 5 Analysis

The Phase 5 security analysis correctly identifies that the four standard
dimensions (external artifact handling, permission scope, supply chain trust,
data exposure) do not apply. The design changes a write target from one local
file to another local file, within the same repo, using the same permissions.
This assessment is sound.

## Attack Vectors Not Considered

### 1. HTML comment marker injection (Low risk, no action needed)

The design uses HTML comment markers as anchors for locate-and-replace:
`<!-- Populated by /plan during decomposition. Do not fill manually. -->`.
If a roadmap's Features section or other user-authored content contained this
exact comment string, Phase 7 could write into the wrong location.

**Assessment:** Not a real attack vector. The roadmap format is controlled by
the `/roadmap` skill which stamps these comments in specific sections. A user
manually inserting the exact comment string would be sabotaging their own
document. The skill operates on files the user controls in their own repo.
No escalation needed.

### 2. Placeholder substitution in roadmap content (Low risk, no action needed)

The `<<ISSUE:N>>` placeholder pattern is substituted in issue bodies by the
batch script. The design does not introduce placeholder substitution into
roadmap content -- the roadmap table is built from mapping data, not from
template expansion. The batch script's substitution scope is unchanged.

**Assessment:** No new surface. The batch script already handles this correctly
with its three-pass approach (create, substitute, verify).

### 3. Race condition on roadmap file (Not applicable)

Phase 7 reads the roadmap, modifies it, and writes it back. If another process
modified the roadmap between read and write, changes could be lost. This is the
same risk that exists for any file write in these skills and is not introduced
by this design. The skills run in a single-agent context where concurrent
modification is not expected.

## Evaluation of "Not Applicable" Justifications

All four N/A justifications in the Phase 5 analysis are correct:

1. **External Artifact Handling -- N/A**: Correct. No new external inputs.
   The roadmap file is a local repo artifact.

2. **Permission Scope -- N/A**: Correct. The skill already writes to repo
   files and calls `gh` for issue creation. Writing to a roadmap file instead
   of a PLAN doc file uses the same filesystem permissions.

3. **Supply Chain -- N/A**: Correct. No new dependencies or tools.

4. **Data Exposure -- N/A**: Correct. The enriched roadmap contains the same
   information (issue links, dependency graph) that would have gone into a
   PLAN doc. Both are committed to the same repo with the same visibility.

## Residual Risk

None requiring escalation. The design is a write-target change within the
same trust boundary. The data, permissions, external calls, and dependencies
are all unchanged.

## Summary

The Phase 5 analysis is accurate and complete. The design has no security
implications beyond what Phase 7 already carries. No mitigations needed.

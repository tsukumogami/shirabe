# Phase 5: Produce

Hand off to the target command based on the crystallize decision.

## Goal

Write handoff artifacts matching the target command's expected format, then
either continue in the same session (for /prd and /design) or tell the user
what to run next (for /plan and no artifact). The exploration's research files
stay in wip/ for the target workflow to reference.

## Resume Check

If `wip/explore_<topic>_crystallize.md` exists, read it and proceed with the
handoff. The chosen type is in the `## Chosen Type` section.

If the handoff has already been partially completed (e.g., the design doc
skeleton exists but the summary file doesn't), pick up where it left off
rather than rewriting what's already there.

## Inputs

- **Crystallize decision**: `wip/explore_<topic>_crystallize.md`
- **Findings file**: `wip/explore_<topic>_findings.md` (for content to populate
  handoff artifacts)
- **Decisions file**: `wip/explore_<topic>_decisions.md` (if it exists; accumulated
  decisions from convergence rounds)
- **Scope file**: `wip/explore_<topic>_scope.md` (for the original context)

## Steps

### 5.1 Read the Crystallize Decision

Read `wip/explore_<topic>_crystallize.md` and extract the chosen type.

Route to the matching sub-file:

| Chosen Type | Reference File |
|-------------|----------------|
| PRD | `phase-5-produce-prd.md` |
| Design Doc | `phase-5-produce-design.md` |
| Plan | `phase-5-produce-plan.md` |
| Decision Record | `phase-5-produce-decision.md` |
| Rejection Record | `phase-5-produce-rejection-record.md` |
| No artifact | `phase-5-produce-no-artifact.md` |
| Roadmap, Spike Report, Competitive Analysis, Prototype | `phase-5-produce-deferred.md` |

Read the matching file and follow its instructions.

## Cleanup Rule

Do NOT delete `wip/` research files after routing. Target skills may reference
them for context. Cleanup happens when the target workflow completes or when
the user runs `/cleanup`.

## Quality Checklist

Before completing:
- [ ] Crystallize decision read and chosen type identified
- [ ] Correct sub-file read and instructions followed
- [ ] wip/ research files left in place (not deleted)

## Next Phase

None. Phase 5 is the final phase of /explore. If the session continues into
/prd or /design, the target skill's orchestrator takes over.

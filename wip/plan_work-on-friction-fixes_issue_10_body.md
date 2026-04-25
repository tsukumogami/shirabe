---
complexity: simple
complexity_rationale: Create one new reference file, replace inline blocks with one-line references in three existing phase files.
---

## Goal

Consolidate the `/tmp/koto-<WF>/` per-session tmp-path convention into
a single reference file
(`skills/work-on/references/tmp-path-convention.md`), and replace the
inline convention text in `phase-1-setup.md`,
`agent-instructions/phase-3-analysis.md`, and `phase-5-finalization.md`
with one-line references. Prevents drift when someone edits one copy
of the convention.

## Context

Commit `5e58a36` ("feat(work-on): prescribe per-session tmp paths for
transient artifacts") introduced the `/tmp/koto-<WF>/` convention by
documenting it inline in three phase files (phase-1 baseline, phase-3
agent-instructions plan, phase-5 summary). That landed quickly but
sets up a drift trap: change the convention in one file and the other
two go stale silently.

The right shape is a single reference file owning the convention text,
referenced from each phase. If the convention later changes (e.g.,
adding a cleanup step, renaming the directory), one file needs editing
and three references stay correct.

## Acceptance Criteria

- [ ] `skills/work-on/references/tmp-path-convention.md` exists as
  the single authoritative description of the per-session tmp-path
  convention
- [ ] `phase-1-setup.md` references it from the Document Baseline
  subsection rather than duplicating the explanation
- [ ] `agent-instructions/phase-3-analysis.md` references it from the
  Your Output subsection rather than duplicating the explanation
- [ ] `phase-5-finalization.md` references it from the Create Summary
  subsection rather than duplicating the explanation
- [ ] Existing work-on evals pass
- [ ] CI green

## Dependencies

None

## Downstream Dependencies

None

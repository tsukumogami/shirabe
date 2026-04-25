---
complexity: simple
complexity_rationale: Create one new reference file, replace inline blocks with one-line references in three existing phase files.
---

## Goal

Consolidate the koto-context-ingestion convention (pipe via stdin to
`koto context add`; use `wip/` only for agent-side intermediates; never
write to `/tmp/`) into a single reference file
(`skills/work-on/references/koto-context-conventions.md`), and replace
the inline convention text in `phase-1-setup.md`,
`agent-instructions/phase-3-analysis.md`, and `phase-5-finalization.md`
with one-line references. Prevents drift when the convention changes.

## Context

Two earlier commits in this PR introduced and then corrected the
convention text:

- `5e58a36` ("feat(work-on): prescribe per-session tmp paths") solved
  a collision symptom (concurrent workflows overwriting `/tmp/plan.md`)
  by prescribing `/tmp/koto-<WF>/`. This was the wrong direction.
- A follow-up commit corrects the convention to: pipe content via
  stdin to `koto context add` (the canonical koto pattern, per koto's
  cli-usage guide), with `wip/` as the only legitimate intermediate
  for agent-assembled content. `/tmp/` is removed from prescribed
  conventions entirely.

The corrected convention text now appears inline in three phase files.
This is the same drift trap as the original `/tmp/koto-<WF>/` text —
change one copy, others go stale silently. Consolidating into a single
reference owned by `koto-context-conventions.md` (or similar) lets one
edit propagate.

## Acceptance Criteria

- [ ] `skills/work-on/references/koto-context-conventions.md` exists
  and is the single authoritative description of the koto-context
  ingestion convention (stdin piping; `wip/` for intermediates; no
  `/tmp/`)
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

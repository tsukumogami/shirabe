---
complexity: simple
complexity_rationale: Create one new reference file, replace inline blocks with one-line references in three existing phase files.
---

## Goal

Consolidate the koto-context ingestion convention (per `CLAUDE.md` §
"Intermediate Storage") into a single reference file
(`skills/work-on/references/koto-context-conventions.md`), and replace
the inline convention text in `phase-1-setup.md`,
`agent-instructions/phase-3-analysis.md`, and `phase-5-finalization.md`
with one-line references.

## Context

`CLAUDE.md` codifies the rule: koto-driven workflows use koto context
for all reviewable artifacts; `wip/` is for non-koto workflows; an
agent-side disk intermediate is acceptable only if it lives in an
auto-wiped location or is explicitly cleaned up after `koto context add`.

Two earlier commits in this PR moved phase-1, phase-3 agent-instructions,
and phase-5 onto the rule:

- `5e58a36` ("feat(work-on): prescribe per-session tmp paths") solved
  a `/tmp/` collision symptom by prescribing `/tmp/koto-<WF>/`. Wrong
  direction — created persistent on-disk shadows of koto-managed
  content.
- A follow-up commit corrected to: pipe content via stdin to
  `koto context add` (canonical per koto's cli-usage guide); when
  Write-then-ingest is used instead, write to a `mktemp`-produced
  path and clean up afterward.

The corrected convention text now appears inline in three phase files.
Same drift trap: change one copy, others go stale silently. A single
reference owned by `koto-context-conventions.md` lets one edit
propagate, and lets future koto-driven shirabe skills reuse the same
convention by reference.

## Acceptance Criteria

- [ ] `skills/work-on/references/koto-context-conventions.md` exists
  and is the single authoritative description of the koto-context
  ingestion convention (stdin piping; ephemeral disk intermediates
  only with cleanup or auto-wipe; `wip/` not used by koto-driven
  workflows). Includes a brief link back to `CLAUDE.md` §
  "Intermediate Storage" for the underlying rule.
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

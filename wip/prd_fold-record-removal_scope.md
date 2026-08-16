# PRD Scope: fold-record-removal

## Upstream

`docs/briefs/BRIEF-fold-record-removal.md` (Accepted).

## Research provenance

Phase 2 discovery was satisfied by the preceding `/explore` run rather than
re-fanned. Six research leads covered the consumer map, the removal blast
radius, the design history, the carrier alternatives, the growth and
contention measurements, and the unique-guarantee analysis. Their outputs are
at `wip/research/explore_fold-record-scaling_r1_lead-*.md`; the synthesis is at
`wip/explore_fold-record-scaling_findings.md`.

One verification pass was re-run against current `HEAD` because two commits
landed after the exploration (`#316`, `#297`/`#292`). It confirmed the
inventory and surfaced one site the blast-radius sweep had missed:

- **`README.md:87`** names `docs/folds.md` in public-facing prose describing
  the consolidation judgment. It is not in any prior inventory and must be
  rewritten.

It also found the three-reader comment now exists in only one place
(`.github/workflows/check-scope-scripts.yml:27`), not two.

## Requirement themes

1. Remove the record and everything that exists only to serve it.
2. Replace, not delete, the prose claims that cite the record as evidence.
3. Amend the shipped documents whose requirements and decisions it discharges.
4. Leave the survivor-side trace untouched — it is the carrier the removal
   relies on.

## Deferred question inherited from the BRIEF

What a roadmap's downstream cell says when a chain folds to nothing. Closed in
this PRD's Decisions and Trade-offs.

# Brief Discovery: fold-record-removal

## Grounding

No ROADMAP supplied; no `--upstream`. The framing is grounded in the
`/explore` run that preceded this chain (six research leads, round 1),
whose findings and decisions are at
`wip/explore_fold-record-scaling_findings.md` and
`wip/explore_fold-record-scaling_decisions.md`.

## Problem/outcome pair

**Problem.** A `/scope` fold deletes a chain document. Something has to
record that the document was absorbed rather than never written, because
the two look identical on disk and mean opposite things. The current
answer is `docs/folds.md` — one append-only row per fold, in one file, in
every repository that runs `/scope`. That answer was never argued for:
the decision was fixed at BRIEF altitude as an in-scope item, the design
only chose among three surfaces for a record it already assumed, all six
underlying decisions ran in `--auto` mode without author confirmation,
and the PR that landed it had no review. One day after landing it has
zero rows.

**Outcome.** Parallel `/scope` runs stop contending on a shared
bookkeeping file, adopters stop inheriting a check whose mitigation they
never received, and a reader can still tell an absorbed document from one
that never existed — by reading the surviving document, which already
says so.

## What the exploration established

- The survivor already carries an `absorbed:` declaration, a pinned
  `## Status` line, and a contribution section — all enforced at error
  level by `check_fc18` — and the `absorbed:` list accumulates
  transitively across hops. That falsifies the design's stated reason for
  choosing a shared file ("the record dies with the document at the next
  hop").
- Growth is not the problem: ~285 bytes per row against ~80 KB the same
  fold deletes. Nothing reads the file into agent context.
- Contention is the problem, in three shapes: GitHub does not honor
  `.gitattributes` merge drivers server-side, so `merge=union` does not
  stop a blocked merge button; adopters get the CI check but not the
  attribute; and a dead guard in the checker turns a correct record red
  when a parallel PR merges first.
- The CI step cannot fire on the intra-chain fold it was written for —
  `git diff BASE...HEAD --diff-filter=D` cannot see a file created and
  deleted inside the range. Verified with a control.

## Framing-shift answer

No prior BRIEF, PRD, DESIGN, or PLAN exists for this topic. Cold start;
the framing-shift question does not apply.

## Journeys surfaced

Four distinct entry points: parallel folds contending, a reader holding a
dead path, an adopter repository pinning the reusable workflow, and a
future contributor who notices folds leave no central trace and considers
re-adding a log.

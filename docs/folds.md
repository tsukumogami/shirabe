# Fold record

One row per completed fold, appended by `/scope`'s consolidation
judgment before it deletes anything.

**This file is written mechanically and read by CI. Do not hand-edit it.**
A row is an assertion that a specific operation happened, and the checker in
the reusable validation workflow verifies the blob hash against the pre-fold
content. Editing a row does not change what happened; it only makes the record
disagree with the tree.

## Why this exists

An absorbed document leaves no trace otherwise. This repository merges a whole
`/scope` chain as one squash commit, so a document created and folded away
inside that chain never existed on the default branch at all — and when
`/execute` adopts the scoping PR, the same is true of the PLAN. Without this
file a reader cannot tell an artifact that was absorbed from one that was never
produced, and those two look identical on disk while meaning opposite things.

The record is of the *operation*, never of the content. It carries what folded
into what, on what verdict, and which contributions carried — never the absorbed
document's prose. That distinction is load-bearing: any destination that
preserved the content would assert, every time it fired, that the verdict was
partly wrong, since the fold's meaning is that the content did not warrant a
separate durable artifact.

## Columns

| Column | Meaning |
|---|---|
| Date | ISO-8601 date the fold landed |
| Absorbed | repo-relative path of the deleted artifact |
| Into | the survivor, or `none` at the terminal hop |
| Verdict | always `absorb`; a `keep` writes no row |
| Carried | contribution and section outcomes, `name=true` joined by spaces |
| Blob | `git hash-object` of the pre-fold artifact, computed at fold time |

The blob hash is recomputed at fold time rather than lifted from the child
snapshot, because that snapshot is captured post-invocation and the drift
machinery exists precisely because it can differ from the bytes actually
deleted. The hash must be of what was removed.

Values containing `|` or a newline are rejected rather than escaped, and the
fold routes to `keep`. Nothing can produce such a value today — every field is
a closed vocabulary or a slug-composed path — but that safety is inherited from
the validation upstream of it rather than guaranteed here.

## Concurrency

`.gitattributes` gives this file `merge=union`, so two branches each appending
a row merge cleanly instead of conflicting. Union merge resolves silently and
cannot deduplicate, so a cross-branch duplicate is possible — but rows are keyed
by the pre-fold blob hash, so a duplicate is a duplicate of an identical fact,
and the checker flags it rather than the merge failing.

This is the repository's first shared append-only durable file and its first
merge driver. There is no precedent to inherit.

## Record

| Date | Absorbed | Into | Verdict | Carried | Blob |
|---|---|---|---|---|---|
| 2026-08-15 | docs/briefs/BRIEF-multi-pr-plan-decoupling.md | docs/prds/PRD-multi-pr-plan-decoupling.md | absorb | problem-statement=true user-outcome=true user-journeys=true scope-boundary=true absorbed-brief=true | 08da355bf2f2a02e1db3b08d10e263ee2c43a9bb |
| 2026-08-16 | docs/briefs/BRIEF-scope-chain-mandatory-steps.md | docs/prds/PRD-scope-chain-mandatory-steps.md | absorb | problem-statement=true user-outcome=true user-journeys=true scope-boundary=true | 6f96746e956c2286409f7d5b71ca23a153a5d564 |

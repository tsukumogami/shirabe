# Exploration Decisions: fold-record-scaling

## Round 1

- **Direction: remove `docs/folds.md` outright.** The author chose removal over
  per-fold files, over keep-and-fix, and over splitting the CI fixes out first.
  Grounded in: the record has zero rows one day after landing; its existence was
  assumed at BRIEF altitude and never argued at design altitude; all six
  underlying decisions ran in `--auto` without author confirmation and PR #302
  had zero reviews; and its unique benefit reduces to one fact in one fold shape.

- **Growth is eliminated as a justification.** ~285 bytes per row, ~900 per
  fully-folded chain, against ~80 KB of documents the same fold deletes — the
  record costs ~1% of what it reclaims. Any argument for removal that leans on
  file size is not honest and should not appear in the produced artifact. The
  user's stated concern (1) does not survive contact with the measurements.

- **Context cost is eliminated as a justification, with one carve-out.** Nothing
  reads the record into agent context. The single O(n) path is the unspecified
  append in `phase-2-chain-orchestration.md:667-669` combined with the workspace
  `CLAUDE.md` preference for Edit over shell redirects. That is a tooling defect
  independent of whether the record exists, and it disappears with the record.

- **Merge contention is retained as a justification, but restated.** The concern
  is real and the user's diagnosis was directionally right, but the mechanism is
  not a text conflict in the file. It is (a) GitHub not honoring `.gitattributes`
  merge drivers server-side, so parallel folds block the merge button despite
  `merge=union`; (b) adopters inheriting the CI check with no merge attribute at
  all; and (c) a dead guard in the checker that turns a correct record red when a
  parallel PR merges first.

- **Per-fold files (`docs/folds/<date>-<slug>.md`) ruled out.** Structurally the
  strongest replacement — conflict-free, no merge driver, simpler append-only
  assertion — but it preserves a guarantee the author decided is not worth
  preserving. Ruled out as a consequence of the removal decision, not on its own
  merits; worth naming in the artifact so a later reader knows it was considered.

- **git notes, commit trailers, PR body/labels/comments, per-chain files, and
  rotation all ruled out.** Notes are not fetched by `git clone` (verified).
  Trailers cannot be verified pre-merge because the squash commit does not exist
  until the button is pressed. PR metadata is off-tree, editable, GitHub-only.
  Per-chain files destroy the evidence exactly when the fully-folded case needs
  it. Rotation needs an escape hatch in the append-only check and union merge
  preserves no row order to truncate by.

- **The four CI defects are in scope for the produced artifact, not split out.**
  The author declined the "fix CI first, decide carrier after" option. Since the
  whole `Verify the fold record` step is deleted by the removal, three of the four
  defects vanish with it; the fourth (the dead `git rev-parse` guard) is inside
  the same deleted step. They are documented as evidence for removal rather than
  as separate work.

- **Amendment-in-place, not supersession.** `PRD-scope-artifact-persistence.md`
  is at `Done` and `prd/v1` has no `Superseded` status, so amendment is the only
  mechanism the toolchain offers. Precedent is one day old and on these same
  documents. No `shirabe transition` invocation, no folder moves.

- **Two consumers need substantive replacement answers, not deletions.**
  `skills/execute/SKILL.md:596-600` (how a reader tells a fully-folded chain from
  an unfinalized one) and `DESIGN-scope-consolidation-over-skipping.md:838-846`
  (the Option D objection was "answered rather than overruled" by citing the
  record). The second is the sharpest: removing the record withdraws the answer
  while the decision it rescued stays shipped.

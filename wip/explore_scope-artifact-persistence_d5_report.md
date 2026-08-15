<!-- decision:start id="execute-work-sequencing" status="assumed" -->
### Decision: Sequencing of the rationale-in-code work against the DESIGN-to-PLAN fold

**Context**

Issue #280's fix makes `/scope`'s per-hop fold verdict content-decided rather
than type-decided, which for the first time lets a DESIGN fold into a PLAN. Since
`/execute` deletes the PLAN at the end of a run, that means a run can leave no
durable scoping document at all. Two pieces of `/execute`-adjacent work sit
beside that change, both unconditional and so neither breaking the encapsulation
the author wants: closing the two places that already assume a DESIGN survives
(the R5 finalization guard, `run-cascade.sh`'s roadmap `**Downstream:**` rewrite),
and giving the chain a standing job of keeping code comments current about why
the code works as it does. The leak closure is a hard prerequisite either way --
without it the fold produces a false L05 validation error and a silent dangling
ROADMAP reference. The only open question is whether the rationale-in-code work
must land *before* the fold opens or merely as part of the same body of work.

The author originally chose "sequenced, rationale-in-code first" while that work
was being presented as the safety net under the fold -- folding without it would
destroy reasoning nothing else captured. The author then withdrew that framing:
the fold is justified by *worth*, because on the runs where it fires the content
was never worth a separate durable artifact. The premise behind the original
sequencing choice therefore no longer holds, which is why it is being
re-examined. A binding constraint on any answer: a prerequisite that cannot be
objectively called done is not a real gate, so a sequencing recommendation has to
say what done means.

Research settled three facts that shape every available answer. First, the fold
has no runtime representation -- it is two paragraphs of agent-followed prose (the
Stage 1 absorbability table row at
`skills/scope/references/phases/phase-2-chain-orchestration.md:428` and the
Durable-Artifact Floor at `phase-1-discovery.md:266-286`) with nothing behind it
in `crates/`. It cannot be flagged, dark-shipped, staged, or half-enabled; "keep
it disabled" can only mean "do not merge that edit yet." Second, rationale-in-code
is not `/execute` work at all: R14/R15 bars `/execute` from reading diffs
(`skills/execute/koto-templates/execute.md:411`), and the only agent in the chain
holding the diff is `/work-on`'s implementation phase. Third, the repo's plan-mode
rule makes one PR the default -- `skills/plan/SKILL.md:144-163` permits multi-pr
only on a *named* hard constraint and states that "could be separate PRs is not
the test." #280 is roughly 6-10 files in one repo with no landing-order
constraint; PR #271 landed 50 files and +6583/-586 across ten skills plus the
Rust engine as a single-pr plan.

**Assumptions**

- "Rationale-in-code" means comments in the changed source files, not a new
  durable non-`docs/` record such as a commit trailer or a PR-body section. If it
  means the latter, the work flips from instruction-writing to
  mechanism-building, the PB4-versus-Part-1 conflict below becomes the central
  design problem rather than a footnote, and this ordering question changes shape
  entirely.
- GitHub retains `refs/pull/N/head` indefinitely for this repo. Verified live
  today against PR #271 -- fetching that ref brings down the full 44-commit
  ancestry including `docs/plans/PLAN-chain-cardinality.md`, a file absent from
  main because `/execute` deleted it -- but this is GitHub platform behavior, not
  a git guarantee. If wrong, a folded DESIGN becomes genuinely unrecoverable once
  the branch is deleted, which raises the cost of shipping the fold and
  strengthens the sequenced options.
- The observed rate of about one completed `/scope` chain reaching main every
  four days during an active burst (13 chain-doc-creating commits in the 60 days
  to 2026-08-14; exactly one completed chain since the consolidation machinery
  landed as `3f702b6` on 2026-08-10) is representative of the coming weeks. If a
  scoping burst hits, exposure grows linearly -- but since each folded DESIGN
  stays fetchable from PR refs, that scales in inconvenience, not in loss.
- `/scope` and `/execute` run on the same branch and PR, so a folded DESIGN is
  both created and deleted inside one PR and never reaches main. Inferred from
  PR #271. If chain docs land in an earlier separate PR instead, the DESIGN sits
  on main between merges and is fully recoverable from main's history, which
  reduces the exposure question to nothing.
- No downstream consumer repo already ships a rationale check in its
  `.claude/shirabe-extensions/work-on.md` that shirabe could lift. shirabe's own
  extension file has none.
- This decision was made in `--auto` mode without user confirmation, which is why
  the status is `assumed` rather than `confirmed`.

**Chosen: One PR, with rationale-in-code scoped to a diff-checkable deliverable**

No ordering constraint. Everything ships in a single-pr plan: the Stage 1
judgment rewrite, the Durable-Artifact Floor rewrite, the absorb-procedure fixes,
the `/execute` R5 finalization-guard fix, the `run-cascade.sh` roadmap
`**Downstream:**` fix, and the rationale-in-code instruction. One squash merge, so
there is no window in which the fold exists without the instruction.

What makes this more than the unconstrained version is that rationale-in-code is
bounded to exactly two edits, both verifiable by a reviewer reading the diff:

1. A bullet plus short subsection under `### A. Write Code` in
   `skills/work-on/references/phases/phase-4-implementation.md:27-31` -- record
   why the code is shaped this way, not what it does; the decision the diff
   cannot show. That file is read by the `implementation` state
   (`skills/work-on/koto-templates/work-on.md:982-984`), the state where the
   coder agent has the diff in hand.
2. One line extending the **maintainer reviewer**'s brief at
   `skills/work-on/references/phases/phase-4b-review.md:13`, which today asks
   "Can the next developer understand and modify this code? Are naming, implicit
   contracts, and context clear?" -- adding whether a non-obvious decision carries
   a comment saying why.

The second edit is what makes this enforcement rather than aspiration:
`blocking_count > 0` in that phase collects findings, respawns the coder, and
re-enters implementation (`phase-4b-review.md:29-33`). It is an existing
*blocking* path whose judge is an agent, which is the only enforcement shape that
fits a qualitative property.

Explicitly out of scope and explicitly not a gate: any mechanical
comment-content check, and the long-tail effort of raising rationale coverage
across the existing codebase. Total cost is roughly 15-25 lines of prose across
two existing files.

If the plan does split for an unrelated reason such as review size, the residual
rule is that the rationale-in-code instruction lands in the same PR as, or before,
the fold-enabling edit -- it is 20 lines and there is no reason to leave it for
later.

**Rationale**

The ordering question dissolves inside one PR. A squash merge is atomic, so
"before" and "after" have no meaning unless the two halves land in separate
merges -- and the repo's own plan rule makes one PR the default with none of its
named escape conditions present. Sequencing only becomes a live question if
someone first chooses a split that nothing requires, and under
`skills/plan/SKILL.md:144-163` that split would itself need a named constraint
recorded in the PLAN.

The gap between the two halves is about twenty lines. The PR must contain the
leak closure and the judgment rewrite regardless; adding a bullet to
`phase-4-implementation.md` and a clause to a reviewer brief is not a body of
work that needs risk-managing through sequencing. Sequencing exists to stage
expensive or risky work, and there is no expense here to stage.

The original premise for sequencing has been withdrawn, and the residual risk is
bounded and measured. Under the worth justification, on the runs where the fold
fires the content was never worth a separate durable artifact -- so a safety net
is not a precondition for firing it. Even taking the pessimistic view, exposure
in a one-to-two-week gap is zero to three runs, and a folded DESIGN's bytes stay
fetchable from `refs/pull/N/head`. What a fold costs is discoverability, not
content.

The accepted trade-off is real and worth stating: this ships the fold alongside
an instruction whose effect nobody can measure. There is no check that will tell
anyone whether `/work-on` actually started writing why-comments, and PR #278 is
direct evidence that the reasoning survives today only when a human sets out to
carry it -- commit `6e1a22dc` hand-deleted 730 lines of PRD and DESIGN and
hand-wrote 56 lines of comments to replace them. The judgment here is that an
unmeasurable instruction plus a blocking agent reviewer is the honest ceiling for
a qualitative property, and that holding an atomic 6-10 file change hostage to a
property nobody can certify buys nothing.

**Alternatives Considered**

- **Hard prerequisite -- fold stays disabled until rationale-in-code lands**:
  two merges, the fold held until the first is done. Rejected because the fold
  has no runtime representation, so this is expressible only as PR-ordering
  discipline; it splits a 6-10 file change with no named constraint, against the
  repo's single-pr default; and its gate cannot be honestly released, since the
  property it would gate on is qualitative and unmeasurable. Its motivating
  premise -- rationale-in-code as the safety net under the fold -- has been
  withdrawn by the author.

- **Same body of work, one PR, no ordering constraint**: the right shape, and the
  chosen option is this one sharpened. Not rejected so much as underspecified:
  as stated it leaves "rationale-in-code" undefined, so the half that is
  genuinely a long-tail quality effort can expand inside the PR and become a de
  facto blocker anyway. Bounding the deliverable is what turns it into something
  a reviewer can call done.

- **Fold ships first, rationale-in-code follows as separate tracked work**:
  rejected because it takes the same unnamed split as the hard-prerequisite
  option and gains nothing for it. The only thing it buys is shipping a few days
  sooner while leaving a twenty-line follow-up issue to rot, and it is the one
  option that does open a real exposure window, however small.

- **Partial gate -- a minimal checkable subset is a prerequisite, the rest
  ongoing**: rejected because the checkable subset is ritual, not quality. The
  mechanism home is free (`/work-on`'s verification map at
  `skills/work-on/koto-templates/work-on.md:592-641`, or a Notice-severity
  validator finding), but every objectively decidable form checks that a comment
  *construct* is present, never that it explains anything -- and the repo has
  already written down that judgment must not be gated
  (`references/pr-body-conformance.md:34-38`, `:81-94`, "gating any of these
  would fail correct PRs"). PB4 works only because a `##` heading in a squash
  body is *always* wrong, whereas an uncommented new function is often correct.
  The most natural proxy, a required rationale section in PR body Part 1, is
  barred outright by PB4's ban on headings there. Mechanically viable,
  semantically hollow. Separately, since the fold cannot be half-enabled, this
  option's partiality could only ever apply to the prerequisite half.

**Consequences**

The #280 work stays one single-pr plan and one squash merge, which is what the
repo's plan-mode rule produces by default -- no PLAN needs to record a
departure, and no follow-up issue needs tracking.

"Rationale-in-code" gets a concrete, bounded definition instead of an open-ended
quality mandate: two prose edits in `/work-on`, present or absent in the diff.
That closes the constraint about gates that cannot be called done -- not by
building a check, but by making the deliverable checkable while leaving the
property it enforces to the blocking maintainer reviewer that already exists.

One naming correction propagates into the design: the "rationale-in-code half of
the `/execute` work" is `/work-on` work. Only the R5 finalization guard and the
`run-cascade.sh` roadmap rewrite are genuinely `/execute`-side. This does not
change scope or split the PR -- it changes which file the instruction goes in,
and any design or plan should say `/work-on` where it currently says `/execute`.

What becomes harder: nobody will be able to demonstrate that rationale-in-code is
working. There is no metric, no check, and no artifact that distinguishes a run
that wrote good why-comments from one that did not. If the author later wants
evidence rather than an instruction, the honest paths are a Notice-severity
validator finding or a periodic human audit -- not a merge gate. The mechanical
gate remains available and cheap to add later if the reviewer-brief path proves
insufficient; the decision here is only that it should not block this work.

What is deliberately accepted: a small number of runs may fold a DESIGN before
the new instruction has had any observable effect on comment quality. Those
DESIGNs remain fetchable from `refs/pull/N/head` by anyone with read access, so
the loss is browsability rather than content -- and by the worth justification,
those runs are precisely the ones where the DESIGN was not worth keeping.
<!-- decision:end -->

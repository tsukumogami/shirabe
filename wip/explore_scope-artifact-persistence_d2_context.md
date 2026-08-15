# Decision Context: Is the fold verdict purely the judging agent's call, or does it get a structural backstop?

## Question

Under the contribution model, the consolidation judgment's verdict at each hop
collapses into a single content question answered by an agent against the real
document bodies. Does that verdict stand on the judging agent's authority alone,
or does it get a structural backstop -- and if so, what kind, and at which hops?

## Complexity

critical (Tier 4, full path: phases 0-6)

## Mode

--auto. No blocking on user input. Assumptions recorded in the report.

## Constraints

1. **No pre-artifact judgment.** Nothing may be decided before the artifact it
   is about exists. This killed the entry altitude in #260 and still binds.
2. **Single reduction mechanism.** Any backstop must be *part of* the
   consolidation judgment, not a second mechanism sitting beside it. Two
   reduction mechanisms firing at different times means neither reads as the
   rule (#260's load-bearing argument).
3. **A backstop that always fires reinstates the floor #280 exists to remove.**
   A backstop that never fires is theatre. The design must argue where the line
   sits.
4. `/scope` is autonomous by design; the author's stated position is that agents
   should be able to make the worth call.
5. Static validation can assert *presence* of a contribution section, never
   *fidelity*. Length carries no signal because compression is the goal.
6. Document size is not a usable proxy for worth (smallest DESIGN: 132 lines in
   tsuku, 227 in shirabe).

## Known Options

- (a) **No backstop.** Single judging agent, trusted at every hop.
- (b) **Independent reviewer gating only the irreversible terminal fold** (into
  the PLAN), not the durable-survivor folds.
- (c) **Independent reviewer gating every fold.**
- (d) **Human confirmation required for the terminal fold only.**
- (e) **Recoverability instead of a gate** -- the distillate-plus-original stays
  retrievable somewhere durable, so the terminal fold stops being irreversible.

Additional alternatives to be identified in Phase 2.

## Background

### The model the author has settled

`/scope` is the tactical parent skill driving BRIEF -> PRD -> DESIGN -> PLAN.
Issue #280 reports that every completed run leaves a permanent PRD and DESIGN
regardless of what the work turned out to be, because the consolidation
judgment's Stage 1 absorbability test compares *type* schemas rather than
document content, so above BRIEF->PRD the verdict is `keep` on every run.

Each type contributes one thing to the chain -- illustratively BRIEF/WHY,
PRD/WHAT, DESIGN/HOW, PLAN/WHEN-as-sequence. A document that absorbs an ancestor
carries that ancestor's *contribution* as one compact section ahead of its own
content, in chain order. Contributions accumulate transitively and are capped at
the number of ancestor types, so growth is bounded. Every fold is a distillation
and lossy by design.

Under this model Stage 1's structural test very nearly dissolves, because a home
can always be written. The verdict collapses into the content question: does this
upstream hold anything beyond its contribution that compression would lose?

### The asymmetry that makes this a Tier 4 decision

Everywhere the survivor is durable, a wrong `absorb` verdict is bounded -- the
content was distilled into a document that still exists, and a wrong `keep`
merely leaves a document that could have folded.

But `/execute` deletes the PLAN at execution
(`skills/execute/scripts/run-cascade.sh:859`, `git rm -f "$PLAN_DOC"`, committed
under a fixed `chore(cascade): post-implementation artifact transitions`
message). So folding into the PLAN means the content leaves the document system
entirely. A wrong verdict there destroys content with no recovery path. This is
the only irreversible operation in the system.

### Prior art that must be answered, not ignored

- **DESIGN Decision 8, Option D** (in
  `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`) considered
  absorbing a DESIGN into the PLAN and REJECTED it: the PLAN is deleted, so the
  move "trades a durable audit trail for a shorter run and loses the record of
  why the work happened." The author is now overturning this, on the ground that
  for the class of work where it fires -- bug reports, and tasks that turn out to
  be obvious or self-contained -- the content was never worth a separate durable
  artifact. Corpus evidence: 366 DESIGN docs, 107 PRDs, 64 BRIEFs across the
  workspace, accumulated because the workflow never asked.
- **Decision 5** in the same DESIGN rejected the shape where the mover and the
  verifier are the same actor: trusting the absorb verdict with no itemized check
  is "a recommendation with no receiver and nothing confirming the transfer." An
  independent reviewer agent per absorb was considered and DEFERRED.
- **The absorb procedure has never executed in this repo.** All 35 PRDs with an
  `upstream:` point at their same-topic BRIEF and no BRIEF has ever been deleted.
  Even #260's own dogfood run failed its carry check on User Journeys and shipped
  all four artifacts. Every code path below the verdict is untested.

### The durability surface that already exists

From the record-survival research:

- Repo settings are squash-only with `squash_message: PR_BODY` and
  `delete_branch_on_merge: true`. **Part 1 of the PR body becomes the squash
  commit message and lands on main permanently in every clone.**
- Part 2 (from the single `---` down) is trimmed at merge -- verified empirically
  against PR #271 -> squash commit `9f45603`. No workflow performs the trim; it
  is a human editing the pre-filled squash body in GitHub's merge dialog. So
  "Part 2 is deleted at merge" is a discipline, not a mechanism.
- The branch is deleted at merge, so individual commit messages do not survive on
  main.
- `/scope` Phase 3's documented PR-body chain record has **no implementation**
  and no PR on the ordinary path; `/execute`'s `pr_finalization` does a full
  `--body-file` replacement it is barred by R14/R15 from merging into.
- Nothing in `/execute` or `/work-on` instructs rationale into code comments,
  commit trailers, or docs. `koto decisions record` has the right schema
  (`choice`, `rationale`, `alternatives_considered`) but writes to
  `~/.koto/sessions` outside the repo.
- PR #278's rationale survival was manufactured by hand in commit `6e1a22dc`
  (730 lines of PRD and DESIGN deleted, 56 lines of comments hand-written). That
  is evidence about the author, not about `/execute`.

### Related mechanics the backstop interacts with

- The existing absorb procedure's step 4 re-validates **the survivor only**, so
  its revert condition never fires on the failure mode that matters.
- `lifecycle::build_referrer_map` (from #271) is the retirement guard the absorb
  path needs and never calls.
- Both `/scope` Phase 3's closed write-target set and `/execute`'s R5
  finalization guard assume a DESIGN survives.

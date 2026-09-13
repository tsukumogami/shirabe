# Exploration Findings: work-on-standalone-completeness

## Core Question

What exactly does `/execute` do that `/work-on` does not, derived from the code
rather than from recollection, and which items on that list are per-change
finishing logic versus per-plan orchestration? Everything downstream -- including
the choice between folding `/work-on` into `/execute` and keeping it standalone --
depends on that list being right.

All line numbers are against `main` at `9f84fa7`.

## Round 1

Eight leads dispatched, eight returned. No lead failed. Claims below are marked
MEASURED (command output in hand), VERIFIED (read the file myself, in this
session, not only via an agent) or REPORTED (an agent read it and I did not
re-check).

### Key Insights

**1. The tracking issue's list is half wrong, and the half that is wrong is the
half everyone has been acting on.** (leads: skill-inventory, standalone-trace,
cadence-classification; items 1 and 2 re-verified directly)

#361 lists six things `/execute` owns. Two of them do not survive the code:

- *"Readying the PR."* VERIFIED: `/work-on` has zero occurrences of `--draft` and
  never creates a draft PR. There is nothing to ready. The DRAFT-to-READY
  discipline is an `/execute` invention tied to its own single shared PR
  (`execute.md:640`, `:702`, #117) -- not a general PR-hygiene practice this repo
  applies, and not a step a standalone run is missing.
- *"PR body and title conformance, including closing keywords."* VERIFIED:
  `skills/work-on/references/phases/phase-6-pr.md:35` instructs "Include
  `Fixes #<N>` in Part 2" and single-sources the mechanical title/body rule to
  `references/pr-body-conformance.md` -- a **repo-root shared reference that
  `/execute` also consumes** (`execute.md` cites the same file). Both skills
  already share this contract.

The issue's term-count table is arithmetically correct (MEASURED, lead
skill-inventory reproduced all six counts, and the 28-vs-14 state counts) but it
counted only the two koto templates. `/work-on` carries these obligations in its
`references/` tree instead, which the table could not see.

**2. Exactly one capability is genuinely absent from `/work-on`: the
document-chain cascade.** (leads: skill-inventory, cadence-classification,
standalone-trace)

`/work-on` has zero mentions of `cascade` or `lifecycle` and no state, gate or
prose anywhere that touches BRIEF / PRD / DESIGN / PLAN / ROADMAP status. That is
the whole of the real gap, and it is the one the niwa worker hit.

**3. The better diagnosis is enforcement altitude, not location.** (synthesis
across leads 1, 2, 4)

The obligations `/work-on` appears to be missing mostly exist -- as prose in
reference files that an agent may skip. In `/execute` the same obligations are
koto states with evidence schemas and gates that a run cannot pass without
submitting evidence. That difference, not the file they live in, explains the
field evidence: three workers skipped steps that were written down, because
written down and enforced are different things. `/work-on` has, in a literal
filesystem sense, zero production scripts under `scripts/` -- even its
retry-clearing logic is prose that a test extracts and executes at runtime
(REPORTED, lead skill-inventory, `retry-clearing_test.sh`).

This reframes the work and opens a third direction neither #361 nor the brief
names. See Direction 3 below.

**4. The per-issue-versus-per-plan cascade risk -- the structural constraint #361
says either direction must accommodate -- is already solved by a discriminator
that exists and works today.** VERIFIED: `work-on.md:752-775`. `pr_creation`
accepts `pr_status: shared` and routes **straight to `done`**, bypassing
`ci_monitor` entirely. `/execute`'s single-pr children are dispatched with
`SHARED_BRANCH` set and take exactly that route -- they never create a PR and
never enter any post-CI state.

Consequence: finishing logic added to `/work-on` **after** `ci_monitor` is
automatically skipped for `/execute`'s children, with no new "is this the last
issue" machinery, no `children-complete` re-derivation, and no double cascade.
The cadence objection holds only for logic placed before that fork.

**5. `/execute` does not invoke `/work-on` as a skill. They share one template
file.** VERIFIED: `execute.md:302-305`, `materialize_children.default_template:
../../work-on/koto-templates/work-on.md`. koto materializes one child session per
issue against `/work-on`'s own template.

This kills the "folding is circular" objection in its literal form -- there is no
slash-command recursion to be circular about. It also means the two skills cannot
diverge on anything inside `work-on.md`: they are one implementation with two
entry points, which is why the `cannot_verify` gate hits both identically.

**6. The boundary has already moved once, in the opposite direction, and the
migration left fossils.** (leads: boundary-dependents, skill-inventory,
sharing-precedent)

`/execute` was carved **out of** `/work-on` (PR #199, `DESIGN-execute-skill.md`);
`work-on-plan.md` and `run-cascade.sh` moved out. Stale pointers left behind
(REPORTED): `skills/work-on/references/phases/phase-2.5-worktree-discipline.md`
is a `/work-on`-owned file read only by `/execute` (`execute.md:563`) whose own
text cites `work-on-plan.md`, which no longer exists; five "work-on cascade"
references in `skills/roadmap/SKILL.md`; three Rust doc comments, one
(`crates/shirabe-validate/src/lifecycle.rs:1681`) citing
`skills/work-on/scripts/run-cascade.sh`, a path that has never existed on disk.

Any redraw is a partial reversal of a recorded decision and has to say so.

**7. A shared library for exactly this machinery was already proposed and
rejected.** REPORTED (lead sharing-precedent): `DESIGN-execute-skill.md`
considered a "shared library both skills reference" for plan-level finalization
between these same two skills and rejected it on legibility grounds, choosing
full extraction into the parent. Direction 2's "shared component" variant must
answer that rejection rather than re-propose it.

Constraint on any answer: koto templates have **no include or inherit
mechanism** (REPORTED). A shared component can only be a shared script or a
shared prose reference -- never a shared template fragment. The repo's own
CLAUDE.md separately forbids a CLI subcommand that renders an artifact body.
Where true sharing is unavailable the repo's accepted pattern is deliberate
duplication plus a CI drift check -- `work-on.md` and `execute.md` already
duplicate the CI-gate expression on purpose, with `validate-template-mermaid.sh`
check 4 guarding the copies (VERIFIED: the comment at `work-on.md:764-765` says
"kept identical to execute.md").

**8. multi-pr is the real hole, and it is `/work-on`'s own territory.** (leads:
cadence-classification, boundary-dependents)

multi-pr PLANs route to `/work-on`, not `/execute`. They have **no cascade wiring
at all** -- `run-cascade.sh` is invoked only from `execute.md:706`. Yet
`plan-doc-structure.md:95` and `skills/roadmap/SKILL.md:350` both state as fact
that the work-completing PR runs the cascade. Nothing implements it.

So for multi-pr, "migrate the finishing logic into `/work-on`" is not a
relocation -- it is building the first version. And two committed documents
currently describe a capability that does not exist.

**9. `cannot_verify` is a separate defect: a per-repo configuration gap.**
MEASURED by me, not inferred. Across the five repos in this workspace, only
shirabe ships `.claude/shirabe-extensions/work-on.md` with a `## Verification
map` section. The other four carry a generated `work-on.local.md` holding label
vocabulary and no map at all. The gate has nothing to read and fails closed to
`done_blocked` exactly as `verification-map.md` specifies, and
`DESIGN-work-on-definition-of-done.md` named this trade-off in advance
(REPORTED). Because both entry points run the same template state
(`execute.md:305`), neither candidate direction changes anyone's exposure to it.

**10. Two further standalone-incompleteness defects surfaced, distinct from this
one.** `/work-on`'s `staleness_check` gate calls `check-staleness.sh`
(`work-on.md:325`), a script this repo does not ship -- `PLAN-work-on-friction-
fixes.md:81` already records the open question (REPORTED). And issue **#87**,
filed 2026-04-28, already identified the PLAN-deletion / DESIGN-transition gap
for plan-backed `/work-on` runs; #361 is a recurrence of a still-open defect
four months older (REPORTED).

**11. Naming actively misleads.** `finalization` in `work-on.md` runs **two
states before the PR exists** and finalizes the implementation (cleanup, tests,
summary), never the PR and never the chain. `/execute` has a separate
`pr_finalization` scoped to title and body only, explicitly *not* marking ready
(VERIFIED: `execute.md:640`). The word carries three different meanings across
the two skills. `/work-on`'s SKILL.md frontmatter also describes its goal as a
*merged* PR (REPORTED, `SKILL.md:4-5`), which its template never does.

### Tensions

- **Did `/work-on` already handle closing keywords?** Lead cadence-classification
  said yes, lead skill-inventory measured zero occurrences. Both correct:
  zero in the koto template, present in `references/phases/phase-6-pr.md:35`.
  Resolved by direct reading. This is precisely insight 3 -- present as prose,
  absent as enforcement.
- **Can `/work-on` tell it is a child?** Lead sharing-precedent found a
  `parent_orchestration:` sentinel precedent and noted `/work-on` is already a
  registered participant; lead call-boundary found `/work-on` cannot introspect
  an `/execute` parent. Resolved by direct grep: the sentinel is written by
  `/scope` and `/charter` only -- **zero occurrences anywhere under
  `skills/execute/`**. The mechanism exists, `/work-on` already reads it for
  authoring parents, and `/execute` simply does not use it. A fourth, cheaper
  discriminator (`SHARED_BRANCH` / `pr_status: shared`) already does the job
  (insight 4).
- **Fix #360 and #352 now or later?** Lead related-defects recommends splitting
  them: #360 immediately and independently (MEASURED 16/0, 3/0, and `/scope` at
  5/4 already solved it at `skills/scope/references/phases/phase-4-cleanup.md:
  119-124` -- a transferable pattern), #352 deferred until the boundary settles
  which skill owns `/work-on`'s three panels. Also noted: `/execute`'s
  `paused_for_review` is a non-failure terminal whose resumability dies with its
  context, which #360's acceptance criteria do not currently cover.

### Gaps

- Has multi-pr ROADMAP deletion **ever** worked, or is `roadmap/SKILL.md:350`
  aspirational since the #199 split? Determines whether multi-pr finalization is
  in scope here or a separately-filable defect.
- What merges a coordinated run's per-repo child PRs? No `gh pr merge` was found
  anywhere in either skill. Appears to be left to a human but is nowhere stated.
- Does koto's `materialize_children` route a child through `SKILL.md` or seed the
  child session's `entry` state directly? Not determinable -- koto's runtime is
  external to this repo. Bears on whether SKILL.md prose reaches a child at all.
- Whether `/work-on` and `/execute` lacking a `team.yaml` (which all seven
  authoring skills have) is a documented exception or a gap.

### Decisions

Recorded in `wip/explore_work-on-standalone-completeness_decisions.md`.

### A third direction the evidence opens

#361 and the brief both frame the choice as two options. The findings support a
third, which is smaller than either:

**Direction 3 -- raise the enforcement altitude inside `/work-on`, and add the
cascade behind the existing `shared` fork.** Move `/work-on`'s already-written
finishing obligations out of skippable prose into koto states with evidence
gates, and add cascade states after `ci_monitor`, where insight 4 shows
`/execute`'s children never reach. `/execute` keeps the plan-level cascade for
its own shared PR; `/work-on` gains one for the standalone and multi-pr cases
that have none today.

It does not re-propose the shared library that `DESIGN-execute-skill.md`
rejected (insight 7), does not require re-deriving `children-complete` (insight
4), does not invert the documented prohibition on `/execute` taking an issue
number, and targets the actual diagnosis (insight 3) rather than the one #361
states.

Its cost is honest and should not be understated: for multi-pr it is new
construction, not relocation (insight 8), and some cascade logic would exist in
two places under a duplication-plus-drift-check regime (insight 7) rather than
one.

## Accumulated Understanding

The problem #361 reports is real -- a standalone `/work-on` run does not finish
its own work -- but its stated cause is wrong in a way that matters. `/work-on`
is not missing five of the six things the issue lists. It is missing one (the
document-chain cascade) and enforcing four of the others as prose rather than as
gated states. The fix implied by "migrate the finishing logic out of `/execute`"
is therefore larger than the problem requires, and the fix implied by "fold
`/work-on` into `/execute`" reverses a recorded decision and inverts a
deliberately-written prohibition to solve something narrower than it addresses.

The two objections that were supposed to decide between the two filed directions
both dissolve on inspection: folding is not circular (one shared template, no
slash-command recursion), and the per-issue cascade cadence is already
discriminated by `pr_status: shared` routing straight to `done`. What actually
constrains the answer is different: koto templates cannot compose, a shared
library for this exact machinery was already rejected on the record, multi-pr has
no finalization path at all despite two documents claiming it does, and the
boundary has moved once already and left inaccurate comments in shipped source.

Three defects reported alongside this one are not this one: `cannot_verify` is a
per-repo configuration gap (MEASURED), `check-staleness.sh` is a missing script,
and #87 is the same cascade gap filed four months earlier and still open.

# Decision 4 — What Bail at `/scope` Phase 1 does, and what changes so it can execute

## Question

The chain proposal at the end of `/scope` Phase 1 offers Proceed / Adjust /
Bail. R27 keeps all three options; R28 requires that Bail actually execute and
reach clean-cancel. Today it reaches neither branch of its own routing rule.
What is the exact mechanism that makes it terminate correctly, and what else in
the skill has to move for that mechanism to hold?

R28 already names the answer's shape — narrow the wip-state test to exclude the
parent's own state file, and dispose of that file on the bail. This report
verifies that shape is correct, works out what "dispose of it" means in a skill
whose Phase 4 only runs after a successful R9 check, and evaluates the two
alternatives that would leave Phase 0 or R9 alone instead.

## Defect Verification

Every link in the chain the brief describes holds. Three of them hold more
strongly than stated, and one carries a wrinkle the brief does not mention.

**Link 1 — the bail-handling rule routes on a disjunction that includes the
parent's own state file. CONFIRMED.** `skills/scope/SKILL.md:443-448`:

> **Bail** — route to R8 bail-handling. If any wip state exists for the topic
> (the state file, any child intermediate, or any research scratch), the bail
> records `exit: abandonment-forced` and force-materializes the most-recently-
> running child's intermediate; if no wip state exists, the bail is a clean
> cancel with no terminal artifact.

The parenthetical names the state file first. `phase-1-discovery.md:326-328`
carries the compressed form of the same rule ("force-materialize if any wip
state exists for the topic; clean-cancel otherwise").

**Link 2 — Phase 0 always writes the state file before returning control to
Phase 1. CONFIRMED.** `phase-0-setup.md:273-287` writes
`wip/scope_<topic>_state.md` unconditionally once validation passes, and
`phase-0-setup.md:308-309` advances `phase_pointer:` to `phase-1` "immediately
before returning control to Phase 1." There is no path that reaches the chain
proposal without that file on disk: Phase 0's three early stops (bare
`--upstream` at `:33-42`, cold start at `:51-61`, slug-regex rejection at
`:63-88`) all terminate *before* the write and before Phase 1 is entered. So at
a Phase 1 bail the first disjunct is true by construction, the disjunction is
true, and the route is always `abandonment-forced`.

**Link 3 — no child has run, so there is no intermediate to force-materialize.
CONFIRMED, and the skill has already noticed.** `chain_ran:` has exactly one
write site, Phase 2 step 6, which fires *after* the child returns
(`phase-2-chain-orchestration.md:55-58` and `:325-338`) — so at Phase 1 it is
empty, and no `wip/{brief,prd,design,plan}_<topic>_*` file exists either.

The wrinkle: `phase-3-exit-finalization.md:172-176` already contemplates this
case and resolves it the wrong way.

> When NO child has an unfinished intermediate (the bail fired in Phase 1 with
> no Phase 2 invocations yet), `triggering_child:` is set to whichever child
> Phase 2 was about to invoke when the bail fired — the first child in
> `planned_chain:` that has not yet completed.

`SKILL.md:590-592` says the same. That branch names `brief` as the triggering
child of an abandonment that `brief` had no part in, and then instructs Phase 3
to force-materialize `brief`'s intermediate — a file that does not exist. It
produces a `triggering_child:` value and no artifact. It is dead prose under
every option evaluated below, and any fix has to delete it.

**Link 4 — R9 refuses the empty `exit_artifacts:` that results. CONFIRMED.**
`phase-3-exit-finalization.md:218-221`, condition 2: "`full-run`,
`re-evaluation`, and `abandonment-forced` all require at least one entry in
`exit_artifacts:`. An empty list at finalization fails." The pattern-level
source (`references/parent-skill-state-schema.md:215-255`) states the same in
Part 1's neighborhood. `phase-3-exit-finalization.md:238-241` requires the
violation be surfaced and finalization refused; `phase-4-cleanup.md:14-20`
requires Phase 4 to be skipped entirely on an R9 failure. So the observed
behavior of a Phase 1 bail today is: the run stops at Phase 3 with an R9
violation surfaced, no exit recorded, and `wip/scope_<topic>_state.md` left on
disk with `exit: UNSET`. Not a clean cancel and not an abandonment — a
contract-violation report.

**One further finding the brief does not raise: this is a regression against
`/scope`'s own PRD, not a design gap.** `docs/prds/PRD-shirabe-scope-skill.md:575-580`
already specifies the correct mechanism:

> **Tie-break for "most-recently-running"**: the last entry in the state file's
> `chain_ran` field, or if `chain_ran` is empty, the first entry in
> `planned_chain` that has a non-empty wip/ intermediate on disk. If neither
> resolves to a child, bail routes to clean-cancel rather than
> abandonment-forced — there is nothing to force-materialize.

And `AC13c` (`:1188-1196`) makes it an accepted, `[automated-eval]`-marked
acceptance criterion: "if no wip/ intermediate exists for any planned child,
bail routes to clean-cancel (no abandonment-forced exit, no Decision Record, no
state-file `exit:` set to `abandonment-forced`)." The skill files' disjunction
comes from the looser prose one page earlier at `:518-524` and from AC9c
(`:1110-1114`), which both say "any wip state" without qualifying whose. The
PRD contains both the loose framing and the precise one; the skill copied the
loose one. `AC26`'s STALE-verdict route (`:1348-1355`) resolves to clean-cancel
by the same rule.

The consequence for this decision is that Option A restores conformance with an
already-accepted AC, while B and C would each put the skill in violation of
AC13c and require the PRD to be amended. Also worth recording: AC13c is marked
`[automated-eval]` and `skills/scope/evals/evals.json` has no scenario for it —
grep for "clean-cancel" in that file returns nothing. The eval gap is why the
regression survived.

## Decision Drivers

1. **R9 must not be weakened.** It is the only mechanical guarantee behind I-2
   ("every chain ends at a durable file"). Whatever fixes the bail must leave
   the check intact for the exits that do produce artifacts.
2. **Precedent already exists and is shipped.** `/charter` solved this exact
   case; a second, differently-shaped solution in `/scope` costs the pattern its
   claim to a uniform exit surface.
3. **The mid-chain abandonment case must keep working.** `us-5-mid-chain-abandonment-forced`
   (`evals.json:182-196`) is the graded scenario, and it reaches
   abandonment-forced through the stale-session row-4 Force-materialize prompt,
   resolving `triggering_child` from `chain_ran` timestamps.
4. **The fix must cover every pre-child stop, not just the chain proposal.**
   See question 4 below — there are three others with identical state.
5. **wip-hygiene.** A cancelled run that leaves `wip/scope_<topic>_state.md`
   behind leaves a wip file with no chain left to sweep it, and the workspace
   rule requires every `wip/` file gone before the PR merges.

## Considered Options

### A. Narrow the wip-state test to exclude the parent's own state file

**What changes.** The disjunction becomes a two-step resolution with an explicit
fallthrough, matching `/charter`'s `phase-finalization.md:495-532` step for
step:

1. `chain_ran:` non-empty → resolve `triggering_child:` to its most-recent
   entry by started-at timestamp (the existing R8 tie-break, unchanged).
2. Otherwise, the first `planned_chain:` entry with a non-empty
   `wip/{brief,prd,design,plan}_<topic>_*` intermediate on disk → that child.
3. Otherwise → **clean-cancel**.

`wip/scope_<topic>_*` is not consulted at any step. Neither is
`wip/research/{prd,design}_<topic>_*`: research scratch is not
force-materializable into an artifact, so letting it select the
abandonment-forced route would reproduce the same empty-`exit_artifacts:`
failure one case further out. It is preserved rather than tested — Phase 4's
abandonment sweep already leaves it alone (`phase-4-cleanup.md:37-46`).

Edits required, six files:

- `SKILL.md:443-448` — the Bail branch's routing rule.
- `SKILL.md:585-592` — the R8 tie-break paragraph; delete the "child Phase 2 was
  about to invoke" fallback and replace it with step 3.
- `SKILL.md:556-562` — "terminates through one of the three pattern-level exit
  paths" gains the clean-cancel qualifier.
- `phase-1-discovery.md:326-328` — the compressed restatement.
- `phase-3-exit-finalization.md:172-176` — same deletion as `SKILL.md:590-592`;
  and the R9 section gains one sentence stating that clean-cancel does not enter
  Phase 3, so R9 does not fire against it.
- `phase-4-cleanup.md:22-46` and `:122-135` — a clean-cancel row in the
  exit-path matrix (remove `wip/scope_<topic>_*`; nothing else exists by the
  route's own premise; no terminal artifact) and a summary form, since the
  current format string hard-codes `exit=<one of three>`.

The disposal has to be assigned to a phase. Phase 4 today runs only after R9
returns success (`phase-4-cleanup.md:14-20`) and clean-cancel never reaches R9.
Recommended assignment: the bail handler performs the removal and emits the
summary, and Phase 4's matrix names clean-cancel anyway so the deletion lands
inside the enumerated closed write-target set rather than outside it —
`wip/scope_<topic>_*` is already in that set at
`phase-3-exit-finalization.md:306-307`, and a removal outside the set is itself
an R9-checkable violation.

**The exit record.** There is none. No `exit:` value, no `exit_artifacts:`, no
state file. This is `/charter`'s clean-cancel verbatim
(`phase-finalization.md:534-543`).

**Does R9 still hold?** Untouched. R9 fires at Phase 3 termination
(`phase-3-exit-finalization.md:210-212`); a clean-cancel run never enters Phase
3. Every exit that does reach Phase 3 still faces the same five conditions
including the non-empty `exit_artifacts:` requirement. This is A's strongest
property — it fixes the bail without paying anything at the check that guards
every other path.

**Resume afterward.** A later `/scope <topic>` finds no state file, falls to
meta-ladder Entry 8 (on-topic branch → Phase 1) or Entry 9 (main fallback →
Phase 0), and starts a fresh chain. That is the correct outcome for a chain the
author cancelled before it wrote anything. It also closes a live hazard: if the
state file were kept, a re-entry within 7 days hits Entry 3 and *silently*
resumes at `phase_pointer: phase-1` as though the bail never happened, and a
re-entry after 7 days hits Entry 4 and offers Force-materialize — which routes
straight back into the broken abandonment path.

**Cost to the mid-chain case.** Zero. `us-5` fires through the row-4
Force-materialize prompt, which is a distinct abandonment trigger, and resolves
via `chain_ran` — step 1 of the narrowed resolution, unchanged. Every case that
routes to abandonment-forced today with something real to materialize still
does. The only behavior that moves is the case where nothing exists to
materialize, which today produces an R9 violation report.

**Second-order.** I-1 says "bail routes to a terminal-artifact path, never to
silent loss" (`references/parent-skill-pattern.md:44-45`). Clean-cancel routes
to no artifact, so `/scope` needs the carve-out `/charter` states at
`phase-finalization.md:545-552` — nothing was authored, so nothing is lost.
`/charter` declares it against I-2 only; `/scope`'s statement should name both,
since I-1 is the invariant the wording actually strains.

### B. Make `abandonment-forced` tolerate an empty artifact set

**What changes.** R9 condition 2 gains a carve-out gated on `chain_ran:` being
empty and no child intermediate existing. `phase-3-exit-finalization.md:172-176`
stays as written and becomes live. Phase 4's abandonment row stays as written.
`SKILL.md:443-448`'s disjunction stays as written — B is the only option that
touches nothing outside Phase 3, which is its genuine appeal.

**The exit record.** `exit: abandonment-forced`, `triggering_child: brief`,
`partial_phase_reached: phase-1`, `chain_completed: <timestamp>`,
`exit_artifacts: []`. No HTML-comment marker is written, because there is no
artifact to host one.

**Does R9 still hold?** No — it holds in an amended form that is strictly
weaker, and the amendment lands on the one condition that operationalizes I-2.
After it, "`exit: abandonment-forced`" no longer implies a partial artifact
exists, so every downstream reader of that field acquires a case to handle.
`/charter`'s security section calls this shape out by name
(`phase-finalization.md:728-736`): "Without the explicit fallthrough, a Bail
event with no prior chain progress would either write an empty
`exit: abandonment-forced` state (corrupting the contract) or fail silently."
B is the first horn of that dilemma, adopted deliberately.

**Resume afterward.** Phase 4 on abandonment-forced removes
`wip/scope_<topic>_*` — including the state file carrying the record B just
wrote. So the exit record survives for the length of one phase and is then
deleted, and the next invocation starts fresh exactly as under A. B's stated
benefit, "recording the bail without materializing anything," does not survive
its own cleanup phase. Making it survive would mean either exempting
clean-cancel-shaped abandonments from the Phase 4 sweep (leaving a permanent
`wip/` file, which the hygiene rule forbids) or writing the record into the PR
body the way `phase-3-exit-finalization.md:64-88` handles the full-run case —
which is a larger change than A, in a skill area A does not touch.

**Cost to the mid-chain case.** No direct breakage, but it costs the marker
vocabulary its meaning. `triggering_child: brief` on a run where `/brief` never
started is a false statement in a field whose enum is otherwise resolved from
observed evidence, and a reviewer reading state can no longer infer from
`abandonment-forced` that a Draft is on disk. It also contradicts AC13c, which
forbids exactly this state ("no state-file `exit:` set to `abandonment-forced`").

### C. Move the bail decision earlier — defer the state-file write until Proceed

**What changes.** `phase-0-setup.md:273-309`'s unconditional write moves to the
Proceed branch of the chain proposal. Phase 1 also writes state — `planned_chain:`
at `:399-414` and `child_snapshots:` at `:439-458` — so those writes move too,
or Phase 1 has to hold them in conversation memory until Proceed.

**The exit record.** None, and no file to dispose of. The Phase 1 bail becomes a
plain return.

**Does R9 still hold?** Untouched, for the same reason as A: no Phase 3 entry.

**Resume afterward.** Worse than A. Today, a session that dies mid-Phase-1 leaves
a state file the ladder can resume from at `phase-1`; under C it leaves nothing,
and the Adjust loop is explicitly unbounded (`phase-1-discovery.md:460-472`),
so an author can spend an arbitrarily long conversation in Phase 1 with no
durable position. `consumed_upstream:` — the one Phase 0 field the author cannot
recompute from the filesystem — is also unrecorded for that whole stretch.

**Cost to the mid-chain case.** None. But C is incomplete on its own, which is
what disqualifies it: it fixes the chain-proposal bail and leaves every other
pre-child stop broken. After Proceed the state file exists, and a bail at Phase
2's first worktree-discipline escalation (`phase-2-chain-orchestration.md:104-114`)
still hits an always-true disjunction with an empty `chain_ran:` and no child
intermediate — the identical failure, one step later. C would still need A's
narrowing to be correct, so it is not an alternative to A but an optional extra
on top of it. As an extra it is a net cost: it trades a resumable Phase 1 for
nothing A does not already deliver.

## Recommendation

**Option A, in `/charter`'s exact three-step shape.**

It is the mechanism `/scope`'s own PRD already specifies and AC13c already
grades, so adopting it is a regression repair rather than a design change. It
leaves R9 whole — the only option that fixes the bail without spending anything
at the check that guards the other three exits. It makes the two parents
identical at the surface the pattern exists to keep identical: after the change,
`/scope`'s R8 resolution and `/charter`'s read as the same procedure with
different child sets, which is what a reviewer comparing them should find.

R28's framing is correct as written. The one thing it leaves implicit and the
design should make explicit is where the disposal happens: Phase 4 cannot own it
under its current trigger, so the bail handler performs the removal and Phase 4's
matrix names clean-cancel so the deletion stays inside the closed write-target
set.

Three items travel with the fix and should not be split from it:

1. Delete the "child Phase 2 was about to invoke" fallback in both places
   (`SKILL.md:590-592`, `phase-3-exit-finalization.md:172-176`). It is the only
   text that instructs force-materializing a file that cannot exist, and leaving
   it would leave the defect readable in the corpus after the routing is fixed.
2. Add the clean-cancel eval scenario AC13c has always required. Its absence is
   why the regression went unnoticed; `/charter`'s suite grades its own
   fallthrough (`skills/charter/evals/evals.json:151,157`).
3. State the I-1/I-2 carve-out in `/scope`'s own words rather than by reference
   to `/charter`'s.

## Consequences

- Bail at Phase 1 terminates with the state file removed, no artifact, no
  `exit:` value, and a summary line saying so. The author who stops before
  `/brief` writes gets a clean stop.
- Three other pre-child stops are fixed by the same edit (see the next section),
  which is the main reason to narrow the test rather than special-case Phase 1.
- `exit: abandonment-forced` keeps its guarantee: it implies a Draft artifact on
  disk carrying the `scope-status-block: abandonment-forced` marker. Downstream
  greps and reviewers are unaffected.
- One route into the broken exit closes: a stale state file left by a bailed run
  can no longer be offered to Force-materialize at ladder row 4.
- `consumed_upstream:` is lost on a cancel — the author retypes `--upstream` on
  the next invocation. That is the entire cost of disposal, and see Q1 below for
  why nothing else is.
- The pattern reference still does not name clean-cancel. After this change two
  of two parents implement it and neither is described by
  `references/parent-skill-pattern.md`'s Three Exit Paths section.

## Answers to the Specific Questions

**1. Does clean-cancel lose anything a later resume would want?** No. By the
chain proposal the state file holds: `topic:` (the author retypes it),
`chain_started:` and `last_updated:` (timestamps of a run that was cancelled),
`phase_pointer: phase-1`, `exit: UNSET`, `exit_artifacts: []`, `planned_chain:`
(a constant — `phase-1-discovery.md:416-417`: "That list is a constant. Phase 1
has no input that can shorten it"), `child_snapshots:` for pre-existing durable
artifacts (recomputed by re-globbing `docs/` on the next run —
`phase-1-discovery.md:439-458`), and `consumed_upstream:` when `--upstream` was
supplied. Nothing authored, nothing derived from conversation, nothing not
recoverable from the filesystem plus the author's re-invocation. The single
recoverable-only-by-retyping item is `consumed_upstream:`, one flag. Keeping the
state file to save that token would leave a resumable entry pointing at a chain
the author explicitly cancelled — strictly worse.

**2. Does `--auto` reach a Phase 1 bail?** No. `phase-1-discovery.md:391-394`,
in the pre-authoring-notice subsection: "It is defined in `--auto` mode. The
proposal is emitted and the run auto-proceeds; the notice rides along as output
and the chain continues. Nothing blocks, so there is no default to get wrong."
Under `--auto` the proposal is output, Proceed is taken, and Bail is
unreachable. Two notes for the design: this fact is stated only inside the
notice's subsection, not in the branch-behavior list at `:319-328` where a
reader looks for it, and `SKILL.md:118-121` is careful to say `--auto` does not
suppress R9 — which under the current defect means an `--auto` run cannot reach
the failure either, since it cannot bail. The fix's benefit is interactive-only;
its correctness argument does not depend on `--auto`.

**3. Does `/charter` have the same defect?** No. Its Phase 0 writes the state
file at the same point (`skills/charter/references/phases/phase-0-setup.md:32-33`,
`:294-307`), so the precondition is identical — but its test never looks at that
file. `phase-finalization.md:495-532` resolves through `chain_ran` (step 1), then
child `wip/` intermediates (step 2), then clean-cancel (step 3), and step 3
explicitly says the Phase 0 state file "if it already exists from Phase 0, is
removed" (`:536-538`). `:565-569` names the Phase 1 bail as "the canonical
clean-cancel case." The loose "any wip state exists" phrasing does appear in
`/charter`'s PRD (`PRD-shirabe-charter-skill.md:455`, AC10f at `:936`, AC12c at
`:975-980`) — the skill file corrected it and `/scope`'s skill file did not.

So the fix should be symmetric in outcome and asymmetric in edits: `/scope`
adopts `/charter`'s already-shipped procedure, and `/charter` needs no behavior
change. Two consistency items are worth folding in: both PRDs carry the loose
phrasing that produced this regression and should be corrected to match their
skills, and `/charter`'s step 1 reads `chain_ran` as "children that completed"
while `/scope`'s Phase 3 tie-break reads per-entry `started_at` timestamps —
compatible, since `/scope` writes `chain_ran` at step 6 after the child returns
(`phase-2-chain-orchestration.md:55-58`, `:325-338`), but the two descriptions
should not be left to a reader to reconcile.

**4. Is Bail at Phase 1 the only pre-child stop?** No — it is one of four, and
the other three share its exact state (state file present, `chain_ran:` empty,
no child intermediate), so all four are broken today and all four are fixed by
narrowing the test:

- **Phase 2's first worktree-discipline escalation.** The check fires *before
  each* child invocation including the first, and its escalation prompt's third
  option is "bail per R8's bail-handling rule"
  (`phase-2-chain-orchestration.md:104-114`). An intent-changing divergence
  detected before `/brief` runs puts the author at a bail with nothing authored.
  This is the closest analogue to the Phase 1 bail and the strongest argument
  against Option C, which cannot reach it.
- **The resume ladder's upstream re-validation Bail** (`phase-resume.md:100-117`,
  graded at `evals.json:365-370`). A re-entry whose recorded
  `consumed_upstream:` no longer resolves offers Re-supply / Continue without /
  Bail before any slot's action runs. On a re-entry against a state file whose
  chain never got past Phase 1, Bail here is pre-child too.
- **Slot 5's settled-upstream Bail** (the Re-evaluate / Revise / Bail triad,
  `phase-resume.md:38,49`, `SKILL.md:355-357`). Pre-child by construction — the
  whole point of those rows is that a settled artifact already exists and no
  child is invoked. Whether it lands on clean-cancel or abandonment-forced
  depends on what the prior session left; with an empty `chain_ran:` and no
  intermediate it is the same case again.

Slot 6's Continue / Discard / Bail rows (`phase-resume.md:33,45,53,58`) are the
one bail family that is genuinely mid-chain: they fire against a partial child
run, so a child intermediate exists and step 2 resolves. Those keep routing to
abandonment-forced, correctly, under every option here.

## Open Sub-Questions

1. **Does clean-cancel belong in `references/parent-skill-pattern.md`?** After
   this change both shipped parents implement it and the pattern's Three Exit
   Paths section (`:79-110`) names only three. The I-1 carve-out is currently
   asserted inside one parent's phase file. A third parent will re-derive it or
   omit it. Lifting it is out of this decision's scope but is the natural next
   PRD line — flagging rather than deciding.
2. **Where exactly does the removal execute?** The recommendation assigns it to
   the bail handler with Phase 4's matrix naming the case. The alternative is
   relaxing Phase 4's trigger to "after Phase 3 succeeds *or* on clean-cancel,"
   which keeps all `wip/` removal in one phase at the cost of making Phase 4's
   one-way dependency on R9 conditional. Both are defensible; the design should
   pick one explicitly rather than leave the disposal unassigned as R28 does.
3. **Should a cancelled run announce anything beyond the summary line?** Phase
   4's format string (`phase-4-cleanup.md:127-128`) hard-codes `exit=`; a
   clean-cancel needs a form that does not lie about having an exit. Proposed:
   `/scope cancelled: no chain progress recorded; wip/scope_<topic>_state.md removed`.
   Wording is a design call, not a decision.
4. **Does `wip/research/` presence deserve a stated exclusion?** The
   recommendation excludes it with a reason. If a future child writes research
   scratch before any materializable intermediate, the exclusion is what keeps
   the empty-`exit_artifacts:` failure from reappearing — worth stating in the
   skill rather than leaving as an omission from a glob list.

---
status: Proposed
decision: |
  The build-output scope has converged everywhere except one stretch: the
  work-on run's own end (the single run and the fix round) and the multi-pr
  driver's loop end, which together are PLAN Issue 5. That stretch leaves this
  scope. The PRD, DESIGN and PLAN drop it and the pieces that only serve it,
  and land the rest: Issues 1, 2 and 6 now, Issues 3 and 4 once
  tsukumogami/shirabe#1881 merges. The stretch becomes a follow-up scope that
  names the work-on end state itself instead of waiting for the
  tsukumogami/shirabe#1230 design to name it, because that design names none.
rationale: |
  Over rounds 8 to 10 the blocking findings fell from 4 to 3 to 2, no round
  reopened a finding from the round before, and the one fix made outside the
  stretch in round 9 held through round 10. Inside the stretch every fix
  produced the next gap: both round-10 blockers, and one of round 9's, came
  from text the pass before had added there. Waiting doesn't close it, because
  shirabe#1881 changes no state after verification and the multi-pr driver
  never depended on it. Cutting the stretch lands the work that converged and
  gives the part that didn't a scope of its own.
---

# DECISION: take the work-on end out of build-output and land the rest

## Status

Proposed on 2026-11-16, for the build-output scope in
tsukumogami/shirabe#1885 at 1951eeec. Review of that scope stopped after round
10, and this record decides the next step in place of an eleventh fix round.
The PRD, DESIGN and PLAN are unchanged by this record. The cut it describes is
the next edit, once it's accepted.

## Context

build-output lets a repo declare its build tree in its verification map, and
has `clean-build-output.sh` remove that tree at a run's successful end with CI
green. The PLAN is coordinated, with six issues in three PRs: a shirabe
mechanism group (Issue 1, the declaration; Issue 2, the script), a shirabe
wiring group behind a gate on shirabe#1881 merging (Issue 3, the runner's wait
on a live removal; Issue 4, `/execute`'s end; Issue 5, the work-on end and the
multi-pr loop end), and koto (Issue 6, incremental compilation off).

The DESIGN holds one thing open on purpose: which work-on state runs the
cleanup at a single run's end. It holds that "for the design of
tsukumogami/shirabe#1230 (draft PR tsukumogami/shirabe#1881)" (DESIGN 76-79),
and the PRD (R7, Out of Scope) and the PLAN (the gate, Issue 5 at 260-262) do
the same.

Three reviewers (architect, maintainer, pragmatic) read all three documents
whole in every round. The pragmatic reviewer passed all ten rounds. The
maintainer and the architect never passed in the same round:

| Round | Head | Maintainer | Architect |
|---|---|---|---|
| 1 | f2004706 | fail | fail |
| 2 | fe1ecf7c | fail | fail |
| 3 | c10d623d | pass | fail |
| 4 | 2dfc0ca5 | pass | fail |
| 5 | 3043ef24 | fail | fail |
| 6 | 1ff96547 | fail | pass |
| 7 | b2e755f3 | pass | fail |
| 8 | b9b23282 | fail | fail |
| 9 | 5c4c92dc | fail | fail |
| 10 | 1951eeec | fail | fail |

Only pass or fail survives for rounds 1 to 7. From round 8 on, the findings
are itemized.

Round 8 had four blocking findings. A whole-script trace then found 43 more
gaps between the DESIGN and the scripts it names, and 5c4c92dc fixed all of
them along with the four findings.

Round 9 had three blocking findings, and 1951eeec fixed them:

- The work-on end had no rule for knowing it was in a fix round, so it would
  reuse the single run's merge-base read, which after a merge can be the
  branch head. This is in the work-on end.
- Issue 3's eligibility, ledger, exit-5 and cap criteria rested on files that
  exist only after shirabe#1881. This is in the runner wait.
- The `await_removals` gate on every forward edge wouldn't compile next to the
  trailing unconditional edges in two pre-setup states. This is in the runner
  wait.

All three came from text the 5c4c92dc pass had added. None reopened a round-8
finding.

Round 10 had two blocking findings, left unfixed when review stopped:

- The multi-pr driver marks and lists item sessions that no document names. A
  developer would have to invent the naming, and the rule fails toward
  deleting if the listing is wrong. This sharpens a round-9 advisory that the
  driver has no session of its own.
- The single run's end logic has no script. The work-on end does its
  plan-dispatched mark read, its fix-round test, its base pick and its record
  write inline, which adds a third and a fourth copy of reads the one-place
  rule keeps in `session-role.sh`. This grew out of the round-9 fix to the
  work-on end.

Neither reopened a round-9 finding. The author of the fix passes put the
pattern this way: each pass closes its findings, and the reviewers find a new
gap one layer out, in the multi-pr driver and the work-on end.

Two facts about that stretch decide this.

First, shirabe#1881 doesn't name the state the stretch is waiting for. At
3674726 its design changes `implementation`, `verification` and one edge into
`done_blocked`. It touches nothing after verification passes and names no
successful-end state or cleanup step. What build-output needs from it is
narrower: `verification-eligibility.sh` and the attempts ledger, which its
single-pr PLAN builds and which Issue 3's eligibility criterion cites.

Second, the multi-pr driver doesn't wait on shirabe#1230 at all. "No state of
the #1230 design carries the call: the skill's loop makes it itself" (DESIGN
587-589). It's bundled with the single-run end only because the items' skip of
the cleanup sits in that same end (DESIGN 1057-1060).

## Decision

The design is converging outside one stretch and not inside it. The stretch
is the work-on run's end (the single run and the fix round, which shares its
caller) and the multi-pr driver's loop end. In the PLAN that's Issue 5.

The stretch leaves this scope:

- PLAN: Issue 5 goes, with Issue 2's `--write-pin` mode and its criterion.
  Issue 4's `work/plan-dispatched` mark write can stay, since it's harmless
  without a reader and has to be in place before any work-on end cleans; or it
  can move to the follow-up with its reader. The gate stays on Issue 3,
  because its eligibility criterion needs shirabe#1881's script and its
  verification files are ones shirabe#1881 also changes.
- DESIGN: Decision 5 goes. So do Decision 4's plan-dispatched mark read
  (391-428) and its multi-pr driver part (585-625), the single-run, fix-round
  and driver base sources in the script contract, and the matching data-flow
  blocks, Components rows and the second half of Implementation Approach step
  4. Decisions 1 to 3 and Decision 4's `/execute` part stay.
- PRD: R6, R7 and R9 narrow to `/execute`'s end and the script. The criteria
  that only a `/work-on` end can meet move to the follow-up: the end-to-end
  run that cleans at its successful end, one record per run across
  verification rounds, and the event-log order. The Goals and the
  fleet-operator story say the standalone `/work-on` run is the follow-up's.

What lands, and when:

- Issues 1, 2 and 6 have no gate and can land now.
- Issues 3 and 4 land once shirabe#1881 merges.
- From then on, a run that `/execute` drives cleans each worktree it recorded
  at its successful end.

The follow-up scope takes the work-on end and the multi-pr driver, and names
the work-on end state itself. Its inputs are the two round-10 findings: name
the item sessions as a function of the PLAN slug and the item, and give the
run's end one script that holds the mark read, the round test and the base
pick. It can be scoped now, since the state it names sits after the ones
shirabe#1881 changes. It can't ship ahead of Issue 3, because no work-on end
may clean before the runner waits on a live removal (R12).

## Options Considered

- **Defer the stretch until shirabe#1881 settles.** This keeps the documents
  as they are and scopes the stretch once the shirabe#1230 design has merged.
  Rejected because that design names no end state, so the wait never ends in
  the answer it's waiting for. The driver's gap doesn't depend on it either.
  Issues 1, 2 and 6 would sit idle for no reason.
- **Cut the stretch and land the rest (chosen).** Two corrections apply to
  how it was first put:
  - "The rest lands now" holds for Issues 1, 2 and 6 only. Issues 3 and 4
    follow shirabe#1881.
  - The cut narrows the PRD's requirements and criteria, not only the PLAN.
- **Name the single-run end state here and cut only the multi-pr driver.**
  This keeps the PRD's headline. The architect's round-10 note says the
  run-end script "can be built and tested before #1230 settles". Rejected for
  this scope because it's another revision of the part that hasn't converged,
  which is an eleventh fix round under another name. It's the right content
  for the follow-up.
- **One more fix round on the two round-10 findings.** Both fixes are
  concrete. Rejected because review stopped after round 10, and in rounds 9
  and 10 every blocker in the stretch came from text the pass before had
  added. An eleventh pass there would most likely find the next gap one layer
  further out.

## Consequences

- The first release of build-output cleans after `/execute`-driven runs, not
  after a standalone `/work-on` run, which is the case the PRD's problem
  statement starts from. A workspace whose runs aren't driven by `/execute`
  keeps leaving trees until the follow-up lands. Issue 6 still shrinks koto's
  trees for every run.
- The cut is an edit pass on all three documents and needs one review round of
  its own. It removes and narrows text without adding mechanism, which keeps
  it out of the stretch where the new gaps kept appearing.
- The follow-up starts with its two findings already stated, and with no
  dependency on a state the shirabe#1230 design was never going to name.
- Recurring non-blocking notes from rounds 9 and 10 stay with whichever scope
  owns their text: undefined "closing step" and "handoff brief", term
  overload, issue sizing, and hardening past the PRD. Several of them belong
  to the stretch and move with it.

## References

- tsukumogami/shirabe#1885 (the build-output scope, head 1951eeec)
- tsukumogami/shirabe#1881 (the shirabe#1230 design, head 3674726)
- tsukumogami/shirabe#1230
- `docs/prds/PRD-build-output.md`, `docs/designs/DESIGN-build-output.md`,
  `docs/plans/PLAN-build-output.md` at 1951eeec

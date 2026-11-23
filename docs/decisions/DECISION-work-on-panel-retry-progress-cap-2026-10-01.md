---
status: Accepted
decision: |
  /work-on's review panels keep 2 unconditional blocking retries per run,
  shared by scrutiny, review and qa_validation. Past those two, a panel gets
  another retry only when its blocking count is lower than its own count on
  its previous blocking round, and never past 3 retries per run. Each granted
  retry is recorded in the run's koto context, and one script reads that
  record, decides, and records the retry it grants. This supersedes, for the
  panel cap only, the "review panels take 2 blocking retries and then
  escalate" clause of DECISION-contradiction-retry-caps-2026-09-28.md.
  Amended 2026-11-23 for shirabe#2061: past the two, a retry is also granted
  when none of the round's open blocking findings was open on the run's
  previous blocking round, in any panel; the ceiling of 3 is unchanged.
rationale: |
  A fixed count can't tell a run that is converging from one that is stuck.
  Two large units found 7, then 2, then 1 blocking defects and escalated to
  done_blocked anyway, so their pull requests were finished by hand outside
  the workflow. Raising the number would spend the extra rounds on stuck runs
  too. Comparing a panel against itself spends them only where the count is
  falling, and the ceiling caps the worst case at one traversal more than
  today, the smallest step that would have let both observed runs continue.
---

# DECISION: a panel retry cap that follows progress

## Status

Accepted on 2026-10-01, for shirabe#548. The ceiling of 3 was chosen over 4
on the observed runs: both escalated on their third blocking round with a
falling count, so one round past the second retry is the smallest ceiling that
would have let them continue. Whether that round would have been their last
isn't known; a run that still finds a blocking issue on its fourth round
escalates. The gate-enforced form of the same rule is deferred, not rejected.

Amended on 2026-11-23, for shirabe#2061: a second way to show progress, by
findings rather than by count. See **Amendment 2026-11-23** below. The
Decision section keeps the text as accepted; the amendment says what it adds.

## Context

/work-on runs three review panels after implementation: scrutiny, review and
qa_validation. A panel that finds blocking defects submits `blocking_retry`,
which returns the run to `implementation` and walks it forward through every
panel again. The cap on that loop is prose in each panel state's directive in
`skills/work-on/koto-templates/work-on.md`: 2 blocking retries per run, shared
by the three panels, after which a panel that still finds a blocking issue
submits `blocking_escalate` and the run ends at `done_blocked`.
`DECISION-contradiction-retry-caps-2026-09-28.md` settled that number, and
`skills/work-on/scripts/settled-policy_test.sh` pins it.

shirabe#548 reports two large units whose scrutiny rounds found 7, then 2, then
1 blocking defects. Both escalated after the second retry. Escalation ends a
coordinator's request leg, so the coordinator lost track of the unit and the
pull request was finished by hand.

What the run knows today: nothing records how many defects a blocking round
found. Panels write their result key only when they pass, the retry loop clears
all of them, and the evidence carries the outcome and nothing else. The agent
counts retries from memory. koto counts attempts per state, but those counts
can't be routed on, they count entries rather than defects, and koto's own
planning leaves retry caps out of scope.

Review panels are the largest token cost a run has. A full traversal of the
three panels spawns 7 agents (3 scrutiny, 3 review, 1 QA), plus the
implementation round before it.

## Decision

The first 2 blocking retries in a run stay unconditional, as today.

Past those, a panel gets another retry only when it shows progress against
itself: its blocking count this round is lower than its own count on its
previous blocking round. A flat or rising count escalates. A panel that has no
earlier blocking round in this run has nothing to compare against and
escalates; that is today's behaviour for it.

No run gets more than 3 blocking retries, whatever the counts.

The `light` review level, added after this decision was taken, runs one panel,
`light_review`, in place of the other three. It spends from the same run-wide
retries under the same rule, and its count is compared with its own earlier
rounds only. A run whose level moves between `light` and the full panels has
no earlier round on the other side to compare against.

Since panels re-run only the seats a fix touched, a re-entered panel's count is
the sum over the seats that ran; a seat carried forward as passed counts 0,
which is what it would have reported. Re-check seats look only at their earlier
findings and the fix diff, which makes a falling count easier to show after
the floor. The ceiling bounds what that buys.

Counts are compared within one panel, not across the run, because the panels
count different things: scrutiny and review count blocking findings, QA counts
failed scenarios. A run whose scrutiny found 7 and whose review then found 2
hasn't shown progress on anything.

`skills/work-on/scripts/panel-retry-budget.sh` carries the rule. It reads the
run's record of granted retries from the koto context key `panel_retries`,
decides, and on a grant appends this round before saying so. A refusal records
nothing. A record koto reports present but won't return, a malformed record,
a write that fails, or a read-back without the new line is a refusal; the
limit on what koto lets it tell apart is under Consequences. Each panel directive
tells the agent to run it before the retry loop and to submit
`blocking_escalate` when it refuses. The key is outside the set the retry loops
clear, so the record survives every retry.

## Options Considered

- **Fixed cap of 2 (today).** Smallest worst case (3 traversals, 21 panel
  agents), but it escalates converging runs, which is the reported defect.
- **A larger fixed cap, 3 or 4.** Lets converging runs through, but every
  stuck run gets the extra rounds too, so the added spend lands where it helps
  least. Worst case 28 or 35 panel agents, reached by any run that keeps
  failing.
- **Progress per panel, with a ledger and a script (chosen).** Spends extra
  rounds only on runs whose count is falling. Worst case 28 panel agents,
  reached only by a run that improves on its third blocking round. Changes no
  state, edge, variable or argument.
- **The same rule enforced by a koto gate.** A command gate on each panel state
  and a `blocking_retry` edge split on its exit code would make koto refuse a
  retry the budget doesn't allow. Stronger, but it adds a gate and a split edge
  to three states, needs a way to tie the gate to the current round (a gate
  evaluates before the round's count is submitted), and roughly triples the
  change. Today's cap isn't engine-enforced either, so this is a separate step.
- **A cap the caller sets per unit.** Needs a new argument, a template
  variable and /execute plumbing, still needs someone to count, and is per-unit
  panel sizing, which shirabe#521 covers.

The ceiling is 3 retries rather than 4. Each extra traversal can cost 7 panel
agents, and one more round is the smallest step that would have let both
observed runs continue.

## Consequences

- Worst case per run goes from 3 panel traversals to 4 (21 to 28 panel agents).
  Runs whose counts don't fall after the second retry cost the same as today.
- The agent no longer counts retries from memory: the record is in context, and
  the script refuses a retry once the ceiling is reached.
- koto can't tell the script an absent record from one it can't read. On its
  local store a record it can't read can't be written either, so the grant
  still fails closed. On a store whose reads can fail while writes succeed, a
  failed read would reset the record; that is reasoned, not observed, and it
  errs toward more rounds, not fewer.
- One call per round. A repeated call counts as another retry, which stops the
  run sooner, never later.
- The count that decides the extra round is the one the aggregating agent
  reports. A run could game it by splitting or merging findings; the ceiling
  bounds what that buys.
- The prose cap in the panel directives (the three full panels, and
  `light_review` once the `light` level arrived) changes from a number to a
  pointer at the script plus the two numbers, and `settled-policy_test.sh` pins
  the new wording.
- `DECISION-contradiction-retry-caps-2026-09-28.md` still governs the analysis,
  implementation, pull request and CI caps. Its note that koto will enforce the
  panel cap "with the same number" now means the same rule: an engine-side cap
  would need these counts, which koto doesn't have.

## Amendment 2026-11-23

For shirabe#2061.

**What changed.** Past the first 2 retries, a panel also gets another retry
when none of its open blocking findings was open on the run's previous
blocking round, whichever panel ran that round. The count rule above still
grants as before, and the ceiling of 3 still refuses a fourth retry whatever
the findings. A round with a finding still open from the previous blocking
round, alone or beside new ones, is judged on the count alone.

**Why.** The count rule can't tell a stuck run from one that keeps clearing
what it finds. A run found one blocking finding in a scrutiny round, fixed it,
and then found a different one in a review round. Review had no earlier
blocking round of its own to compare with, so once the two unconditional
retries were spent the round was refused and the run ended at `done_blocked`.
The same happens inside one panel when each round finds a single, different
finding: the count stays at 1. In both cases every finding the previous round
raised had been closed, which is the progress this decision exists to reward.
A finding id is the hash of its panel, raiser, path and summary, so two
rounds' findings can be compared directly, across panels as well. The
comparison that rules out a stuck run is whether something stayed open, not
how many things are open.

**How.** `panel-scope.sh --open-ids` prints the ids of the findings
`--open-count` counts. `panel-retry-budget.sh` writes them as a third field on
each `panel_retries` line, "<panel> <count> <ids>". Its previous blocking
round is the record's last line. A line written before this amendment has no
ids, so a round compared with it is judged on the count alone.

**What it doesn't change.** A grant never closes a finding. The panel's
verdict gate still blocks on every open finding in the ledger until a later
round's reviewer closes it at a new head, so a retry granted this way can't
let a blocking finding through. Since the comparison reads only the record's
last line, a finding that recurs after another panel's round, or is reworded
so its id changes, can win a retry as if it were new. The ceiling of 3 and
the verdict gate still bound it: the run gets no fourth retry, and the panel
can't pass while the finding is open. The worst case is still 4 traversals
(28 panel agents).

**Considered and not taken.** Letting `panel-scope.sh --record` record a
round at its own planned head after HEAD has moved. That makes the round
recordable but leaves the budget's refusal in place. It would help only if
the fix were made inside the panel state, without a retry, and that path
never touches `panel_retries`, so the ceiling could be stepped around.

## References

- shirabe#548
- shirabe#2061 (the 2026-11-23 amendment)
- shirabe#521 (panel sizing, out of scope here)
- `DECISION-contradiction-retry-caps-2026-09-28.md`
- `skills/work-on/koto-templates/work-on.md`
- `skills/work-on/scripts/panel-retry-budget.sh`
- `skills/work-on/scripts/panel-scope.sh`

---
schema: brief/v1
status: Accepted
problem: |
  A /work-on run now spends most of its time in review panels, fixed stops
  and test accounting, and little of it writing code. The review level meant
  to size review to risk resolves to full on almost every change, and
  /execute runs independent plan steps strictly one after another.
outcome: |
  An agent running /work-on on a small, contained change finishes in a
  fraction of today's time with review sized to the change, while large and
  risky changes keep every check that has caught a real defect; independent
  plan steps under /execute stop waiting on each other.
motivating_context: |
  Merged PRs kept a steady pace while plans and milestones took far longer
  to finish. Looking at where a completed work-on run spends its time showed
  that implementation is a small share and the per-run weight of the
  workflow itself is a large one.
---

# BRIEF: Lighter work-on runs

## Status

Accepted

Framed under /scope as the first hop of the chain for this topic. Whether
a single reviewer is enough on small diffs, given that at least one small
change took a blocking retry from the full panel, passes to the PRD.

## Problem Statement

A unit of work in `/work-on` passes far more machinery than it did at the
start of September. The work-on koto template went from 28 states and 21
gates (shirabe 0.19.2) to 52 states and 78 gates on main today, and its
directive text grew about fourfold. A completed run enters about 28 states.
The number of times the agent has to stop and answer `koto next` grew much
less, from about 13 to about 17, because most new states advance on their
own. What grew is the work inside the stops.

On observed runs the three review panels (`scrutiny`, `review`,
`qa_validation`) take about 40% of a run's active time, the states before
implementation about a quarter, `verification` and `pass_counting` about a
sixth, and `implementation` itself under a tenth. Writing the code is the
smallest part of the job.

The state count is not what costs. On a larger set of completed runs, the
template's growth from 36 to 45 states, serial `/execute` included, left
median working time per run flat at about an hour to an hour and a half.
Working time roughly doubled after the 50-state template arrived at the end
of October and doubled again in the second week of November, with no change
in state or gate count at the second step, while transitions and gate
evaluations per run grew only about 15%. The growth sits in what the
review, verification, pass-counting and CI states do on each visit, and in
a run now spanning two or three sessions instead of one. Nobody has yet
separated how much of that is process and how much is larger issues.

Four things make that weight the same for every change, whatever its size:

1. **The review level does not vary.** The level mechanism exists so that a
   small change can take one reviewer instead of seven. In practice its
   floor rules put any change that touches a test at `standard`, and any
   change that edits an existing test line at `full`. Almost every code
   change ships with a test, so a two-line test fix gets the same seven
   seats as a feature step of thousands of lines. `light` is reachable only
   for a change typed as code whose whole diff is plain documentation, and
   documentation runs skip the level check entirely.
2. **Some stops always get the same answer.** `issue_type_routing` is
   answered `code` on essentially every run; `pre_pr_evidence` is answered
   "nothing found / not applicable" and its gates repeat checks
   `finalization` already ran. `review_level_choice` and
   `fix_determination` each need a second tick only because koto routes on
   the variable value a tick started with, not on a context key.
3. **Experiments and telemetry run in the production path.** The offload
   canary and the rule-distance probe add eight states and their gates to
   every run, including on hosts not enrolled in either experiment, and one
   arm of each deliberately gives the agent less. Shadow grading of
   document criteria makes an LLM call with a 180-second deadline per
   document check whose answers nothing reads, and since koto 0.20.0 a
   shadow check with no verdict blocks the run.
4. **Plan steps run one at a time.** Since shirabe 0.32.0 `/execute` hands
   steps to its step agent strictly in PLAN order, even when `waits_on`
   would let two start together, and a default plan details only its first
   two steps, so the owning session must rewrite each later step before it
   can start.

On top of those, a run checks the same test suites twice: locally at
`verification` and then again in hosted CI, where `ci_monitor` waits for
every check to go green whether or not the changed paths touch it.

None of this is a single bad decision. Each state was added for a reason,
and some of them have caught real defects. The problem is that there's no
record of which ones have, and no way for the workflow to spend less on a
change that needs less.

## User Outcome

The agent running `/work-on` (and the person waiting on its pull request)
sees the run's cost track the change. A small change outside the risky path
classes gets a single reviewer, no constant-answer stops, no experiment
detours and one authoritative test run, and reaches a ready pull request in
a fraction of today's time. A large change, or one that touches CI,
security, koto templates or gate scripts, keeps the full panel and every
check that has caught a real defect. An agent running `/execute` on a plan
whose steps don't depend on each other sees those steps progress together
instead of in a queue. A maintainer looking at any check that remains can
read why it stays.

## User Journeys

### A small fix through /work-on

An agent picks up an issue whose fix is a 12-line change to one script and
its existing test. Today the run stops to confirm the issue is code, stops
twice at the review-level choice, is raised to `full` because a test line
changed, and waits on seven reviewers and two runs of the same suites.
After this feature the run routes itself, lands at `light`, takes one
reviewer seat, runs the suites once, and opens its pull request.

### A risky change through /work-on

An agent works an issue that edits a koto template and two gate scripts,
300 lines in all. The run still lands at `full` and runs scrutiny, review
and QA, because the path classes it touches are the ones the full panel
exists for. It no longer stops at states whose answer never varies, and it
no longer carries the canary and probe states, so its time goes to the
panels that matter.

### A multi-step plan through /execute

An agent runs `/execute` on a five-step plan where steps 2 and 3 both wait
only on step 1. Today step 3 waits for step 2 to finish and for the owning
session to rewrite step 3's entry. After this feature the two start once
step 1 lands, each step's own agent leaving the next step detailed enough to
start.

### Deciding whether a check stays

A maintainer wants to know whether `pass_counting` should remain on every
run. The plan records, for each state added since 0.19.2, whether it has
caught a real defect and the evidence for that. The maintainer answers the
question from that record in a few minutes, instead of reconstructing it
from old pull requests or asking whoever added the state.

## Scope Boundary

### IN

- Finding what made each review, verification and pass-counting visit
  longer from the end of October on, separating that from issue size,
  before any remedy is chosen for it.
- Review sized to the change: a single reviewer for small changes that
  stay away from CI, security, workflow templates and gate scripts, with
  the evidence that one reviewer is enough there.
- Removing or auto-advancing the work-on stops that always get the same
  answer, and naming which of them need a change in koto itself.
- Taking the two rule-delivery experiments and the shadow grading of
  document criteria off the default path, so a run joins them only when
  someone opts in.
- Letting independent plan steps progress together again, or letting each
  step's own agent detail the step after it.
- One authoritative test run per round, local or hosted, and a CI wait
  limited to the checks the changed paths affect.
- A keep-or-cut verdict for every work-on state added since 0.19.2, with
  the evidence behind each one.
- An expected saving per run and the risk accepted for each change.

### OUT

- The multi-session operating model: coordinators, merge seats, grant
  rules and session succession. They add their own waiting, but they live
  outside these two skills.
- When a roadmap milestone counts as Done; the verdict rule is its own
  piece of work.
- CI workflow definitions and how long a suite takes. This feature changes
  what a work-on run waits for, not which jobs exist or how fast they run.
- The coordinator skill and its workflows.
- The rest of the planning skills' review wiring (review events, document
  checks), which affects scoping runs rather than work-on and execute.
- Implementing any of it; this chain plans.

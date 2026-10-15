---
status: Draft
question: |
  Can one release eval run fit inside a single five-hour session window, and
  which cuts get it there? Measured per skill and per scenario from runs
  already made, split between the with-skill run, the no-skill baseline and
  grading.
timebox: "1 session, no new eval runs"
---

# SPIKE: Release eval check cost

## Status

Draft. The measurement is done for coordinate and execute. Scope and work-on
never ran an agent in the attempts behind this report, so their figures are
estimates from the per-scenario rates below; the first release run after the
cuts measures them.

## Question

The release eval check, `scripts/release-eval-check.sh --critical
work-on,scope,execute --critical-runs 3`, stopped on the session limit every
time it was tried (#843). Releases skip it until it fits. What does a run cost,
where does the cost go, and which cuts bring one release run inside one
five-hour session window, at what loss?

## Context

The check answers one question: did a skill regress since the last release? It
answers it by comparing each changed skill's with-skill pass rate with the
newest earlier release record that measured that skill
(`scripts/lib/eval-pass-rates.py`). The no-skill baseline plays no part in that
comparison: `validate_results` in `scripts/run-evals.sh` grades only
`with_skill/`, and the record carries only with-skill rates. The baseline
measures what a skill adds over the bare model, which is a question for skill
development, not for a release.

## Approach

No eval was run for this report. Every number comes from runs already made:

- the check's console logs (four attempts), which give per-skill harness exits
  and where each attempt stopped;
- the iteration directories those attempts left: `coordinate` iterations 1 to
  4, `execute` iterations 1 to 6, `scope` and `work-on` iterations 1 and 2.
  Each holds `runner_session.jsonl` (the nested session's stream-json
  transcript), per-scenario `grading.json` for both sides, `timing.json`, and,
  where the run got that far, `benchmark.json`;
- Claude Code's stored transcripts of each nested session and of every
  subagent it spawned, found by the session id in `runner_session.jsonl`.

The stored transcripts carry each message's final usage; the stream-json
transcript does not (its per-message output counts are partial). Summed over a
session and its subagents, stored usage matches the session's own
`modelUsage` exactly on cache reads and cache writes and within 3% on output.
Each subagent is attributed to its role from its description and prompt
(with-skill, baseline, grader), to its scenario from the eval directory or
`EVAL` name in its prompt, and nested subagents to the top-level agent that
spawned them.

**Prices.** Fitting each session's `modelUsage.costUSD` (the CLI's list-price
figure) against its token classes gives these rates with zero residual over
eight sessions per model, so every dollar figure below uses them:

| Model | Input | Cache write (5 min) | Cache write (1 h) | Cache read | Output |
|---|---|---|---|---|---|
| Opus 5.5 | $4/M | $5/M | $8/M | $0.20/M | $20/M |
| Sonnet 5.5 | $2/M | $2.50/M | n/a | $0.10/M | $10/M |

Sonnet is half of Opus on every token class. "Tokens" below means all tokens
processed: input, cache writes, cache reads and output. Cache reads are most of
it (about 83% of a tier-1 with-skill run), which is why a token count and a
dollar figure don't move together.

## Findings

### How a release eval run is structured

`release-eval-check.sh` asks `run-evals.sh --list-changed` for the skills with
evals changed since the last tag and runs `run-evals.sh --runs N` per skill: N
is 3 for work-on, scope and execute, 1 for the rest. Each run of a skill is one
nested `claude -p` session on the CLI default model (Opus 5.5 in every
transcript). That session loads skill-creator and, per scenario, spawns two
agents side by side: the with-skill agent and the no-skill baseline. Tier-1
scenarios run both agents on Sonnet 5.5. Tier-2 scenarios have no model set,
so both inherit the session's Opus. The session then grades both sides, fanned
out to grader subagents that inherit Opus (6 to 16 per run, each covering a
batch of scenarios), aggregates a benchmark and writes a viewer.

| Skill | Scenarios | Tier 1 | Tier 2 | Runs per release |
|---|---|---|---|---|
| coordinate | 36 | 36 | 0 | 1 |
| execute | 77 | 23 | 54 | 3 |
| roadmap | 17 | 17 | 0 | 1 |
| scope | 66 | 66 | 0 | 3 |
| work-on | 34 | 19 | 15 | 3 |

Those five are the skills changed since v0.25.0 at the head this report was
written on, so they are the selection the next release would run.

### Cost per scenario, per role

Means over every measured run; per-scenario rows are in the appendix.

| | With-skill | Baseline | Grading (both sides) |
|---|---|---|---|
| Tier 1, coordinate (36 scenarios x 4 runs) | $0.287, 481k tokens, 46 s | $0.097, 84k, 18 s | $0.145, 126k |
| Tier 1, execute (23 x up to 4) | $0.296, 436k, 48 s | $0.103, 130k, 20 s | $0.238, 278k (execute mix) |
| Tier 2, execute (31 of 54 measured) | $2.96, 6.24M, 16 min | $1.35, 2.56M, 9 min | same as above |

On top of the agents, the orchestrating session costs $4.34 per coordinate run
($3.42 to $4.94, 5.1M tokens) and $6.27 per execute run ($3.88 to $8.92, 9.8M
tokens).

The baseline costs a third as much as the with-skill run in tier 1 and almost
half as much in tier 2. With its half of the grading, it is about a third of
each scenario's cost in both tiers (32%).

The `total_tokens` figure in skill-creator's `timing.json` (68k to 91k for a
coordinate with-skill run) is the agent's final context size, not what the
run processed. The same runs processed 481k tokens on average.

Inside execute's tier-2 with-skill runs, the review panels the skill launches
cost $23 of $284 across all measured runs (8%). The cost is the agent driving
the workflow over many turns, not the panels.

### Cost per run

| Skill | Run | Scenarios graded | Wall time | Cost |
|---|---|---|---|---|
| coordinate | iterations 1 to 4 | 36 of 36 each | 21, 22, 17, 16 min | $25.09, $24.41, $22.49, $22.03 |
| execute | iteration 1 | 39 of 77 | 187 min | $80.59 |
| execute | iteration 3 | 41 of 77 | 212 min | $68.69 |
| execute | iteration 5 | 49 of 77 | 226 min | $184.76 |
| execute | iteration 6 | 0 of 77 | 126 min | $124.44 |
| execute | iterations 2, 4 | 0 (stopped before any agent) | | $0 |
| scope, work-on | iterations 1, 2 | 0 (stopped before any agent) | | $0 |

No execute run finished one pass of its 77 scenarios inside one five-hour
session window. The run that graded nothing had started 88
agents; the session ended before grading, and the harness keeps no partial
result, so that spend left no record. Scope and work-on never started an agent.

Twenty-three execute scenarios were never reached in any run (listed in the
appendix as "not reached"), all tier 2.

Each run's orchestrating session also wrote its own agent briefs: the layout
of the with-skill and baseline prompts differs in each of the four execute
runs, because `run-evals.sh` tells the session what to do and leaves how to
the model.

### Run-to-run noise

The four coordinate runs scored 92.4%, 91.9%, 91.9% and 97.3% with the skill
(171, 170, 170 and 180 of 185 assertions) on an unchanged skill. The three
execute runs that graded scenarios scored 89.4%, 91.7% and 90.9% on the
scenarios each reached. The record flags a drop when a skill's rounded rate is
strictly lower than its baseline, so a single run per release would flag
noise of up to five points as a drop.

### Scenarios that score the same with and without the skill

A scenario measures the skill only when the skill changes its score. These
nine scored within 0.15 of their assertions with and without the skill, on
average over every run that graded both sides:

| Scenario | Tier | With skill, per run | Baseline, per run | Flag | Why |
|---|---|---|---|---|---|
| coordinate/rotation-start-carries-reasoning | 1 | 4/4, 4/4, 3/4, 4/4 | 4/4, 3/4, 3/4, 4/4 | Rewrite | The prompt states the reasoning the assertions look for, so the baseline repeats it |
| coordinate/new-decision-mid-run | 1 | 4/4 x4 | 3/4, 3/4, 4/4, 4/4 | Rewrite | General caution passes three of four assertions |
| coordinate/non-active-roadmap-stops | 1 | 7/7 x4 | 6/7 x4 | Remove, or keep the one assertion that separates | Six of seven assertions are passed by stopping, which any agent does |
| coordinate/decision-belongs-to-the-human | 1 | 8, 4, 7, 5 of 9 | 4, 6, 5, 4 of 9 | Rewrite | The with-skill run misses the contradiction the scenario is built on; the score swings by four between runs |
| execute/e2e-execute-cascade-old-shape-still-reaches-the-roadmap | 2 | 10/10 x3 | 8/10, 8/10, 10/10 | Remove from release | The cascade script does the work; the baseline reaches the same tree by running it |
| execute/e2e-execute-escalate-recovery | 2 | 1, 3, 3 of 5 | 1, 1, 5 of 5 | Rewrite | Neither side passes reliably; the scenario or its fixture is broken |
| execute/merge-dirty-with-merge | 2 | 5/5 x3 | 5/5, 4/5, 5/5 | Rewrite | The gh shim's scripted merge state decides the outcome, not the skill |
| execute/merge-mergeable-with-merge | 2 | 6/6 x3 | 6/6, 4/6, 6/6 | Rewrite | Same as above |
| execute/merge-not-observed | 2 | 4/4 | 4/4 | Rewrite | Same as above; one graded run |

Twelve more separate the two sides by 0.15 to 0.30 of their assertions and are
the next ones to look at: coordinate's
a-waiting-coordinator-asks-for-no-wake-it-doesnt-need,
ask-up-when-scope-runs-dry and
dispatch-refused-for-a-target-the-entry-point-cant-take; execute's
coordinated-merge-last-gate-blocks-while-pr-unmerged,
coordination-intent-absent-behavior-unchanged-r3,
e2e-execute-cascade-design-roadmap,
e2e-execute-cascade-new-shape-plan-carries-roadmap, e2e-execute-happy-path,
merge-call-fails, merge-draft-ready-fails, merge-mergeable-without-merge and
merge-review-required-with-merge. Scope, work-on and roadmap have no graded
runs, so their non-discriminating scenarios are unknown until the scheduled
baseline measurement runs.

### What a release costs today

Applying the per-scenario figures to the five-skill selection above, with
critical skills run three times (coordinate measured; execute extrapolated to
all 77 scenarios; scope, work-on and roadmap estimated from the tier rates):

| Skill | Runs | Cost | Tokens |
|---|---|---|---|
| coordinate | 1 | $24 | 30M |
| execute | 3 | $793 | 1,548M |
| roadmap | 1 | $13 | 17M |
| scope | 3 | $119 | 153M |
| work-on | 3 | $254 | 477M |
| **Total** | | **$1,202** | **2,225M** |

Execute's tier-2 scenarios are 61% of it on their own. With every skill
selected (all 20 suites) the same arithmetic gives $1,458.

## Recommendation

Go, with conditions: the check fits one session window once it stops running
the baseline, runs each skill once, and runs a named subset of the tier-2
scenarios, with the rest of the current check moved to a scheduled
measurement. Every figure below applies the measured per-scenario rates to the
five-skill selection; "alone" is the cut applied to today's $1,202, and the
cuts overlap, so the column doesn't add up.

### The cuts, ranked by saving

| Rank | Cut | Saves alone | What it gives up |
|---|---|---|---|
| 1 | **One run per release; repeat runs scheduled.** `--critical-runs 1`, and a scheduled job runs the three-run measurement off the release path. | $777, 1,452M tokens (65%) | A release sees one sample. Measured noise on an unchanged skill is up to five points (coordinate: 91.9% to 97.3%), so the drop rule needs a tolerance or a per-scenario comparison, or it flags noise. Variance is measured on the schedule instead. |
| 2 | **Tier-2 subset at release.** Each skill marks the tier-2 scenarios that run at release (here 10 of execute's 54, 5 of work-on's 15, one per workflow path); the rest run on the schedule. | $737, 1,471M (61%) | A regression on a path outside the subset reaches a release and is caught by the next scheduled run, not by the release. |
| 3 | **Tier-2 agents on Sonnet.** A scenario model of `sonnet` for tier 2, as tier 1 already has. | $446, 911M (37%) | Tier-2 agents stop running on the model most users run the skill on. The first release after the change compares against Opus-measured rates, so it needs a fresh baseline. |
| 4 | **Drop the no-skill baseline from the release check.** Spawn only the with-skill agent and grade only it. The baseline moves to the scheduled measurement, where its job (what the skill adds) belongs. | $369, 623M (31%) | Nothing the release decision uses: the record and the drop rule read with-skill rates only. A release no longer shows the skill's lift over the bare model. |
| 5 | **Grading and the orchestrating session on Sonnet.** A session-model setting separate from `EVAL_MODEL`, which today also moves every tier-2 agent. | $82 (7%); tokens unchanged | Grading by the smaller model may judge borderline assertions differently; the first release after the change needs a fresh baseline. A Haiku grader is not priced here: no Haiku call appears in the transcripts. |
| 6 | **Batch tier-1 scenarios that read the same skill.** One agent reads the skill once and answers several plan-only scenarios. | $74, 107M (6%), estimated at half the tier-1 agent cost | Scenarios in one batch can influence each other's answers. Not measured; needs one trial run before it's relied on. |
| 7 | **Remove or rewrite the nine scenarios that score the same with and without the skill** (table above). | $70, 139M (6%) | Nothing measured: they don't tell the skill apart from the model. A rewrite costs authoring time; a removal loses the scenario's intent until it's rewritten. |
| 8 | **Keep per-scenario results and resume.** Key each scenario's result on the skill's tree, the scenario entry, its fixtures and the models; a retry runs only scenarios with no result for that key. | Nothing on a clean run; a retry after a stop no longer repeats completed work (a complete coordinate pass, $22 to $25; 39 to 49 graded execute scenarios at about $4.54 each in tier 2) | Disk state per iteration, and a key that has to name every input or it serves a stale result. Across releases it saves little: coordinate changed in each of the last 7 releases and execute and work-on in 6, and every scenario reads SKILL.md. |
| 9 | **Run only the skills whose files changed.** Already in place: `run-evals.sh --list-changed` selects them and the release check runs that selection. | Already taken: $1,458 for all 20 suites against $1,202 for this selection (18%) | Nothing new. Narrowing further, to scenarios whose own inputs changed, needs each scenario to declare what it reads; not worth it while SKILL.md changes every release. |

### The release run after the cuts

Taking cuts 1, 2, 4, 5 and 7, which change what runs but not how a scenario is
judged:

| Skill | Runs | Scenarios (tier 1 + tier 2) | Cost | Tokens |
|---|---|---|---|---|
| coordinate | 1 | 32 + 0 | $12.6 | 22M |
| execute | 1 | 23 + 10 | $40.8 | 86M |
| roadmap | 1 | 17 + 0 | $7.7 | 14M |
| scope | 1 | 66 + 0 | $23.7 | 40M |
| work-on | 1 | 19 + 5 | $24.4 | 52M |
| **Total** | | | **$109** | **213M** |

From $1,202 and 2,225M tokens to $109 and 213M: 91% less. Adding cut 3 or
cut 6 brings it to $87; both, to $64 and 130M tokens.

**Target: a five-skill release eval run at or under $65 list price and 130M
tokens, in about two hours.** That is below the cheapest execute run that
failed to finish in one session window ($68.69) and under three complete
coordinate runs. Reaching it takes all seven priced cuts, or cuts 1,
2, 4, 5 and 7 with a smaller tier-2 subset (execute 6, work-on 3 gives $91;
with cut 6, $68). The wall time is an estimate from the measured throughput:
about 30 seconds of session time per tier-1 scenario and about 4 minutes per
tier-2 scenario. Running skills in parallel sessions shortens it without
changing the cost.

What the release run no longer does, and where it goes: the no-skill
baseline, the second and third runs of critical skills, and the tier-2
scenarios outside each skill's subset all move to a scheduled measurement that
runs off the release path, across more than one session window if it must.

### Conditions

- **The first release after the cuts needs a baseline that matches.** The
  record holds one rate per skill; a rate measured on 77 scenarios over three
  runs is not comparable with one measured on 33 scenarios once. The record
  should carry per-scenario results, so the comparison uses the scenarios both
  releases ran, or treat a changed scenario set as "no baseline" once.
- **Keep what a stopped run did.** Write each scenario's grading as it
  finishes and let the release check resume, so a stop on the limit costs only
  the scenario in flight (cut 8).
- **Make the harness, not the orchestrating session, decide the agent
  layout.** Today the session writes its own briefs, and they differed in
  every execute run. A fixed layout makes runs comparable and is what cuts 4,
  5 and 6 change.
- **Changing `release.md`'s declared check** (`--critical-runs 1`, a subset
  flag) lands as its own pull request.

### Issues to file once the plan is agreed

- Drop the baseline from the release check's runs and grade only the
  with-skill side.
- Run one pass per release; add the scheduled three-run and baseline
  measurement.
- Mark each skill's release tier-2 subset in `evals.json` and run only it at
  release.
- Add a session-model setting for the orchestrating and grading session,
  separate from the scenario model.
- Rewrite or remove the nine non-discriminating scenarios.
- Keep per-scenario results and resume a stopped run.
- Give the pass-rate record per-scenario results and a noise tolerance for a
  single run.

## Appendix: per-scenario measurements

Means over every run that reached the scenario. Dollars at the prices above; tokens are all tokens processed; seconds are the agent's own wall time (with-skill and baseline ran side by side). "Passed" lists passed:graded assertions per run, runs separated by `/`. Grading isn't split per scenario because grader agents each covered a batch; it averaged $0.145 per scenario for coordinate and $0.238 for execute.

### coordinate

| Scenario | Tier | Runs | With: $ | With: tokens | With: s | Baseline: $ | Baseline: tokens | Baseline: s | With passed | Baseline passed |
|---|---|---|---|---|---|---|---|---|---|---|
| a-feature-whose-deliverable-is-its-scoping | 1 | 4 | 0.48 | 831k | 69 | 0.11 | 100k | 23 | 4:5/5:5/5:5/5:5 | 1:5/3:5/2:5/2:5 |
| a-landed-feature-is-written-back | 1 | 4 | 0.29 | 562k | 52 | 0.10 | 99k | 19 | 4:4/4:4/4:4/4:4 | 0:4/0:4/0:4/0:4 |
| a-landed-milestone-owes-a-verdict | 1 | 4 | 0.36 | 594k | 65 | 0.10 | 98k | 19 | 5:5/5:5/5:5/5:5 | 0:5/1:5/1:5/1:5 |
| a-persons-comment-on-the-record-is-relayed | 1 | 4 | 0.31 | 462k | 52 | 0.10 | 89k | 17 | 4:4/3:4/3:4/4:4 | 0:4/0:4/0:4/1:4 |
| a-resume-by-lane-releases-that-lane-only | 1 | 4 | 0.31 | 522k | 49 | 0.10 | 117k | 19 | 4:4/4:4/4:4/4:4 | 2:4/2:4/3:4/2:4 |
| a-scheduled-pause-holds-dispatch-and-merge | 1 | 4 | 0.32 | 498k | 59 | 0.10 | 81k | 22 | 4:4/4:4/4:4/4:4 | 0:4/0:4/0:4/0:4 |
| a-unit-waiting-on-a-persons-decision-is-parked | 1 | 4 | 0.49 | 955k | 85 | 0.10 | 72k | 18 | 4:5/5:5/5:5/5:5 | 1:5/1:5/2:5/1:5 |
| a-usage-limit-stop-is-not-a-pause | 1 | 4 | 0.26 | 409k | 48 | 0.10 | 99k | 23 | 4:4/4:4/4:4/4:4 | 2:4/3:4/3:4/2:4 |
| a-waiting-coordinator-asks-for-no-wake-it-doesnt-need | 1 | 4 | 0.26 | 439k | 37 | 0.09 | 79k | 15 | 4:4/4:4/4:4/3:4 | 3:4/3:4/3:4/3:4 |
| ask-up-when-scope-runs-dry | 1 | 4 | 0.30 | 549k | 46 | 0.09 | 70k | 14 | 4:4/4:4/4:4/4:4 | 3:4/3:4/3:4/3:4 |
| brief-rendered-with-both-channels | 1 | 4 | 0.41 | 616k | 61 | 0.10 | 108k | 22 | 6:6/6:6/6:6/6:6 | 1:6/2:6/1:6/3:6 |
| decision-belongs-to-the-human | 1 | 4 | 0.25 | 314k | 42 | 0.10 | 80k | 16 | 8:9/4:9/7:9/5:9 | 4:9/6:9/5:9/4:9 |
| deferral-blocks-first-dispatch | 1 | 4 | 0.45 | 765k | 79 | 0.10 | 71k | 20 | 5:5/5:5/5:5/5:5 | 1:5/2:5/2:5/1:5 |
| discipline-rotation-start | 1 | 4 | 0.22 | 345k | 34 | 0.10 | 71k | 19 | 2:6/6:6/2:6/6:6 | 2:6/1:6/2:6/2:6 |
| dispatch-refused-for-a-target-the-entry-point-cant-take | 1 | 4 | 0.29 | 527k | 48 | 0.09 | 70k | 15 | 5:5/5:5/5:5/5:5 | 4:5/4:5/4:5/4:5 |
| dispatch-refused-without-holding | 1 | 4 | 0.26 | 447k | 36 | 0.10 | 80k | 17 | 5:5/5:5/5:5/5:5 | 3:5/3:5/1:5/2:5 |
| escalation-to-a-person-in-conversation-uses-the-question-tool | 1 | 4 | 0.19 | 320k | 26 | 0.09 | 70k | 14 | 5:5/5:5/5:5/5:5 | 3:5/2:5/2:5/3:5 |
| escalation-to-a-person-not-in-conversation-is-a-message | 1 | 4 | 0.22 | 431k | 31 | 0.09 | 71k | 16 | 5:5/5:5/5:5/5:5 | 2:5/2:5/2:5/2:5 |
| issue-already-closed-by-a-pr | 1 | 4 | 0.19 | 242k | 29 | 0.10 | 70k | 17 | 4:4/4:4/4:4/4:4 | 2:4/2:4/3:4/3:4 |
| local-agent-work-gets-a-work-row | 1 | 4 | 0.29 | 579k | 44 | 0.10 | 89k | 18 | 4:4/4:4/4:4/4:4 | 1:4/1:4/1:4/1:4 |
| new-decision-mid-run | 1 | 4 | 0.28 | 503k | 50 | 0.09 | 70k | 15 | 4:4/4:4/4:4/4:4 | 3:4/3:4/4:4/4:4 |
| non-active-roadmap-stops | 1 | 4 | 0.17 | 231k | 25 | 0.09 | 114k | 15 | 7:7/7:7/7:7/7:7 | 6:7/6:7/6:7/6:7 |
| parked-bound-stops-dispatch | 1 | 4 | 0.15 | 159k | 21 | 0.09 | 69k | 13 | 3:3/3:3/3:3/3:3 | 0:3/0:3/2:3/1:3 |
| pick-fills-the-cap | 1 | 4 | 0.20 | 312k | 30 | 0.09 | 69k | 13 | 3:4/4:4/4:4/4:4 | 1:4/1:4/1:4/1:4 |
| record-found-not-duplicated-after-restart | 1 | 4 | 0.23 | 312k | 36 | 0.10 | 89k | 19 | 5:5/4:5/5:5/5:5 | 3:5/3:5/3:5/3:5 |
| report-classified-in-shadow | 1 | 4 | 0.34 | 693k | 59 | 0.10 | 98k | 19 | 5:5/4:5/5:5/5:5 | 0:5/0:5/0:5/0:5 |
| report-names-a-pull-request-the-holding-lacks | 1 | 4 | 0.34 | 591k | 51 | 0.10 | 98k | 19 | 5:5/5:5/5:5/5:5 | 0:5/0:5/0:5/0:5 |
| restart-reconciles-a-merged-holding | 1 | 4 | 0.24 | 452k | 45 | 0.10 | 81k | 20 | 5:6/6:6/6:6/6:6 | 1:6/1:6/1:6/1:6 |
| restart-with-unconfirmed-merge | 1 | 4 | 0.25 | 374k | 44 | 0.11 | 99k | 22 | 5:7/6:7/7:7/7:7 | 3:7/3:7/3:7/2:7 |
| roadmap-invocation-extra-text-is-decisions | 1 | 4 | 0.19 | 227k | 28 | 0.10 | 80k | 17 | 6:8/5:8/4:8/8:8 | 3:8/2:8/4:8/4:8 |
| rotation-start-carries-reasoning | 1 | 4 | 0.27 | 387k | 38 | 0.10 | 90k | 21 | 4:4/4:4/3:4/4:4 | 4:4/3:4/3:4/4:4 |
| scoping-ahead | 1 | 4 | 0.37 | 600k | 54 | 0.10 | 71k | 17 | 4:4/4:4/4:4/4:4 | 1:4/1:4/2:4/1:4 |
| teardown-request | 1 | 4 | 0.27 | 478k | 44 | 0.10 | 79k | 18 | 6:7/7:7/7:7/7:7 | 4:7/4:7/4:7/4:7 |
| verified-head-before-land | 1 | 4 | 0.30 | 531k | 53 | 0.10 | 98k | 17 | 7:7/7:7/7:7/7:7 | 2:7/2:7/2:7/2:7 |
| worker-asks-the-human-opened-as-an-entry | 1 | 4 | 0.26 | 464k | 40 | 0.09 | 70k | 16 | 5:5/5:5/5:5/5:5 | 0:5/0:5/0:5/0:5 |
| worker-reports-green | 1 | 4 | 0.30 | 603k | 53 | 0.09 | 70k | 16 | 7:7/4:7/4:7/7:7 | 2:7/1:7/3:7/2:7 |

### execute

| Scenario | Tier | Runs | With: $ | With: tokens | With: s | Baseline: $ | Baseline: tokens | Baseline: s | With passed | Baseline passed |
|---|---|---|---|---|---|---|---|---|---|---|
| auto-drives-through-to-finalized-mergeable-result-no-pause | 1 | 3 | 0.35 | 476k | 49 | 0.10 | 119k | 16 | 4:5/5:5/5:5 | 1:5/1:5/1:5 |
| coordinated-cascade-order | 2 | 0 | not reached | | | | | | | |
| coordinated-coordination-merge-not-observed | 2 | 0 | not reached | | | | | | | |
| coordinated-cross-unit-carry-forward | 1 | 4 | 0.25 | 326k | 54 | 0.12 | 150k | 23 | 5:5/5:5/5:5 | 2:5/2:5/2:5 |
| coordinated-effort-syncs-as-per-repo-prs-progress | 1 | 4 | 0.26 | 367k | 60 | 0.12 | 159k | 29 | 4:5/4:5/4:5 | 2:5/1:5/3:5 |
| coordinated-head-missing | 2 | 0 | not reached | | | | | | | |
| coordinated-head-moved | 2 | 0 | not reached | | | | | | | |
| coordinated-index-foreign-author | 2 | 0 | not reached | | | | | | | |
| coordinated-index-out-of-set-repository | 2 | 0 | not reached | | | | | | | |
| coordinated-index-wrong-head-branch | 2 | 0 | not reached | | | | | | | |
| coordinated-merge-last-gate-blocks-while-pr-unmerged | 1 | 4 | 0.24 | 396k | 61 | 0.10 | 135k | 26 | 3:5/5:5/3:5 | 2:5/2:5/3:5 |
| coordinated-multi-repo-merged | 2 | 0 | not reached | | | | | | | |
| coordinated-node-branch-base | 2 | 0 | not reached | | | | | | | |
| coordinated-node-merge-not-observed | 2 | 0 | not reached | | | | | | | |
| coordinated-outline-one-repo-end-to-end-merged | 2 | 0 | not reached | | | | | | | |
| coordinated-pause-and-resume | 2 | 0 | not reached | | | | | | | |
| coordinated-plan-verifies-its-mode-scoped-record | 2 | 4 | 0.60 | 721k | 117 | 0.32 | 325k | 62 | 5:5/5:5/4:5 | 2:5/2:5/2:5 |
| coordinated-template-mismatch-refused | 2 | 0 | not reached | | | | | | | |
| coordinated-without-merge | 2 | 0 | not reached | | | | | | | |
| coordination-intent-absent-behavior-unchanged-r3 | 1 | 4 | 0.29 | 360k | 45 | 0.10 | 125k | 17 | 5:5/5:5/5:5 | 4:5/4:5/3:5 |
| cross-skill-work-on-path-assertion | 1 | 4 | 0.16 | 208k | 25 | 0.10 | 126k | 18 | 4:4/4:4/4:4 | 0:4/0:4/0:4 |
| dispatcher-multi-pr-one-issue-at-a-time | 1 | 4 | 0.21 | 260k | 37 | 0.11 | 124k | 17 | 5:5/5:5/5:5 | 4:5/1:5/5:5 |
| e2e-execute-cascade-design-roadmap | 2 | 4 | 1.21 | 2202k | 245 | 0.59 | 837k | 133 | 6:6/6:6/5:6 | 4:6/3:6/6:6 |
| e2e-execute-cascade-new-shape-plan-carries-roadmap | 2 | 4 | 1.18 | 2112k | 238 | 0.66 | 923k | 148 | 10:10/10:10/10:10 | 8:10/7:10/10:10 |
| e2e-execute-cascade-old-shape-still-reaches-the-roadmap | 2 | 4 | 1.06 | 1822k | 220 | 0.59 | 761k | 129 | 10:10/10:10/10:10 | 8:10/8:10/10:10 |
| e2e-execute-escalate-recovery | 2 | 4 | 0.89 | 1330k | 156 | 0.55 | 762k | 113 | 1:5/3:5/3:5 | 1:5/1:5/5:5 |
| e2e-execute-happy-path | 2 | 4 | 0.82 | 1165k | 168 | 0.67 | 933k | 176 | 2:5/2:5/1:5 | 1:5/0:5/0:5 |
| e2e-execute-resume | 2 | 4 | 0.78 | 1218k | 144 | 0.59 | 873k | 131 | 4:5/5:5/4:5 | 1:5/1:5/3:5 |
| execute-ci-monitor-dirty-merge-state-routing | 2 | 4 | 4.65 | 11209k | 1353 | 2.27 | 4732k | 1428 | 6:6/6:6/6:6 | 2:6/2:6/5:6 |
| execute-cross-issue-context | 1 | 4 | 0.33 | 563k | 49 | 0.10 | 126k | 23 | 4:4/4:4/4:4 | 1:4/0:4/1:4 |
| execute-plan-all-success | 1 | 4 | 0.34 | 520k | 51 | 0.10 | 125k | 17 | 6:6/6:6/6:6 | 0:6/0:6/0:6 |
| execute-plan-completion-cascade | 1 | 4 | 0.30 | 395k | 53 | 0.10 | 161k | 24 | 5:5/5:5/5:5 | 0:5/0:5/0:5 |
| execute-plan-detection-from-path | 1 | 4 | 0.29 | 465k | 60 | 0.10 | 125k | 28 | 5:5/4:5/5:5 | 1:5/1:5/1:5 |
| execute-plan-needs-attention | 1 | 4 | 0.32 | 512k | 47 | 0.10 | 125k | 19 | 5:5/4:5/5:5 | 0:5/0:5/0:5 |
| execute-re-evaluation-exit | 1 | 4 | 0.26 | 393k | 40 | 0.10 | 125k | 20 | 4:4/4:4/4:4 | 2:4/2:4/2:4 |
| interactive-pause-leaves-chain-intact-at-paused-for-review | 1 | 3 | 0.35 | 537k | 50 | 0.10 | 119k | 16 | 5:5/5:5/5:5 | 0:5/0:5/0:5 |
| koto-leg-results | 2 | 0 | not reached | | | | | | | |
| legacy-four-column-table-parse | 1 | 4 | 0.35 | 513k | 52 | 0.10 | 117k | 18 | 4:4/4:4/4:4 | 3:4/3:4/2:4 |
| merge-already-merged | 2 | 1 | 3.45 | 6664k | 1256 | 3.63 | 6942k | 1746 |  |  |
| merge-attempt-evidence-names-other-pr | 2 | 0 | not reached | | | | | | | |
| merge-call-fails | 2 | 3 | 3.63 | 8168k | 1549 | 0.56 | 780k | 122 | 4:4 | 3:4 |
| merge-call-flags-fixed | 2 | 0 | not reached | | | | | | | |
| merge-confirm-override-refused | 2 | 0 | not reached | | | | | | | |
| merge-dirty-with-merge | 2 | 4 | 4.11 | 9348k | 1460 | 1.96 | 4160k | 1051 | 5:5/5:5/5:5 | 5:5/4:5/5:5 |
| merge-draft-ready-fails | 2 | 3 | 4.70 | 10359k | 1731 | 1.50 | 3113k | 633 | 3:3/3:3 | 2:3/3:3 |
| merge-failing-nonrequired-check | 2 | 4 | 4.61 | 9930k | 1530 | 0.53 | 723k | 120 | 3:3/3:3/3:3 | 2:3/0:3/1:3 |
| merge-head-moved | 2 | 2 | 2.91 | 5916k | 1408 | 0.48 | 641k | 110 | 3:3 | 1:3 |
| merge-interrupted-resumed-without-merge | 2 | 1 | 5.02 | 12017k | 1490 | 3.69 | 8561k | 1533 |  |  |
| merge-mergeable-with-merge | 2 | 4 | 4.92 | 11689k | 1494 | 2.79 | 6303k | 1054 | 6:6/6:6/6:6 | 6:6/4:6/6:6 |
| merge-mergeable-without-merge | 2 | 4 | 4.00 | 8764k | 1376 | 1.05 | 1908k | 421 | 4:4/4:4/4:4 | 2:4/3:4/4:4 |
| merge-method-rebase | 2 | 0 | not reached | | | | | | | |
| merge-method-squash | 2 | 0 | not reached | | | | | | | |
| merge-no-checks | 2 | 2 | 5.61 | 10836k | 1925 | 0.63 | 985k | 167 | 3:3 | 1:3 |
| merge-not-observed | 2 | 3 | 2.92 | 6266k | 1215 | 1.48 | 3226k | 661 | 4:4 | 4:4 |
| merge-pending-past-limit | 2 | 4 | 4.33 | 9513k | 1558 | 1.53 | 2982k | 633 | 4:4/4:4 | 2:4/1:4 |
| merge-resumed-with-merge | 2 | 0 | not reached | | | | | | | |
| merge-review-required-with-merge | 2 | 4 | 4.57 | 10347k | 1674 | 2.35 | 4723k | 1049 | 3:3/3:3/3:3 | 1:3/3:3/3:3 |
| merge-review-rule-unapproved | 2 | 2 | 3.30 | 6766k | 1346 | 1.95 | 3274k | 973 | 3:3 | 1:3 |
| merge-route-override-refused | 2 | 1 | 3.76 | 7437k | 1340 | 2.69 | 5593k | 1315 |  |  |
| merge-stopped-at-attempt-resumed-without-merge | 2 | 1 | 5.16 | 11720k | 1393 | 2.96 | 6683k | 1318 |  |  |
| merge-unprotected-base | 2 | 2 | 5.96 | 12701k | 1854 | 1.94 | 2899k | 982 | 3:3 | 0:3 |
| merge-workflow-change | 2 | 2 | 3.67 | 7337k | 1378 | 0.90 | 1441k | 234 | 3:3 | 1:3 |
| parity-cross-issue-carry-forward | 1 | 4 | 0.36 | 627k | 57 | 0.10 | 126k | 32 | 4:5/3:5/4:5 | 1:5/1:5/1:5 |
| parity-drift-gate-absorbs-non-intent-changing | 2 | 4 | 0.76 | 1122k | 123 | 0.50 | 678k | 108 | 4:4/4:4/4:4 | 3:4/0:4/4:4 |
| parity-drift-gate-intent-changing-halts | 2 | 4 | 0.66 | 878k | 109 | 0.52 | 740k | 113 | 6:6/6:6/6:6 | 0:6/0:6/6:6 |
| parity-failed-issue-skips-dependents | 1 | 4 | 0.32 | 491k | 49 | 0.10 | 125k | 16 | 5:5/4:5/4:5 | 2:5/1:5/1:5 |
| parity-finalization-cascade-atomic | 2 | 4 | 1.06 | 1863k | 237 | 0.71 | 1086k | 176 | 5:5/5:5/5:5 | 2:5/3:5/3:5 |
| pr-adopt-fork-pr | 2 | 2 | 0.78 | 1088k | 142 | 0.57 | 785k | 125 | 4:4 | 1:4 |
| pr-adopt-other-author-pr | 2 | 1 | 0.59 | 860k | 111 | 0.56 | 821k | 113 |  |  |
| pr-finalization-body-file-stdin-and-fixes-omission | 1 | 3 | 0.31 | 437k | 40 | 0.10 | 132k | 19 | 3:4/3:4/3:4 | 0:4/2:4/0:4 |
| pr-finalization-conventional-title-two-part-body | 1 | 3 | 0.30 | 431k | 41 | 0.10 | 132k | 16 | 4:5/5:5/5:5 | 0:5/0:5/0:5 |
| report-upstream-convention-and-user-facing-behavior-docs | 1 | 3 | 0.16 | 262k | 23 | 0.10 | 145k | 18 | 1:3/1:3/1:3 | 0:3/0:3/0:3 |
| scope-intent-continue-branch-adopted | 2 | 0 | not reached | | | | | | | |
| single-pr-adopts-scoping-branch-routes-children-to-settled-branch | 1 | 4 | 0.38 | 504k | 55 | 0.10 | 125k | 19 | 4:6/4:6/4:6 | 1:6/1:6/1:6 |
| single-pr-fresh-run-r7-parity-lands-on-impl-slug | 1 | 4 | 0.33 | 501k | 52 | 0.10 | 134k | 19 | 4:5/4:5/4:5 | 0:5/0:5/0:5 |
| single-pr-plan-to-merged-pr-unchanged | 1 | 4 | 0.35 | 473k | 50 | 0.10 | 117k | 17 | 4:5/5:5/4:5 | 1:5/1:5/0:5 |
| stale-invocation-refused-merge-unchanged | 2 | 0 | not reached | | | | | | | |

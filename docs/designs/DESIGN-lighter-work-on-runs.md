---
schema: design/v1
status: Proposed
problem: |
  A /work-on run repeats work it already did and stops where nothing is
  decided: a fix round after done restarts review and branch-wide
  verification, edited-test acceptance is re-checked three times, suites run
  locally and again in hosted CI, the review floor almost never reaches
  light, four stops always take the same answer, and two experiments plus
  shadow grading sit in the default path. /execute starts plan steps one at
  a time. Nothing records size per visit, so process cost can't be told from
  bigger issues.
decision: |
  Build eleven shirabe changes, each behind an opt-out, ordered by minutes
  saved over risk accepted. First a run report and per-gather size history.
  Then the zero-risk trims: fix rounds that inherit the parent's verdicts and
  verification results, acceptance judged once per head, the constant-answer
  stops removed or routed in one tick, and experiments behind their existing
  host opt-in files. Then hosted CI as the build of record where every
  selected command has a hosted twin, and a CI wait scoped to those twins.
  Then a light cap in the review rules with an escalate verdict and a hashed
  one-in-ten full-panel audit. Last, step agents that draft the next step and
  concurrent ready steps in /execute. No koto engine change is required.
rationale: |
  The largest measured growth is repetition, not new states: a fix round now
  runs as a fresh session with an empty verdict ledger and branch-wide suite
  selection, which fits the rise from one to three sessions per run. Removing
  repeated work lowers no check, so it goes first. Lowering review on small
  diffs saves a lot per qualifying run but accepts real risk, so it ships
  after the report exists and with an audit that can reverse it.
  Concurrency in /execute saves the most wall time per plan but touches a
  shared branch, so it goes last behind a limit whose value 1 is today's
  behaviour.
upstream: docs/prds/PRD-lighter-work-on-runs.md
user_visible_surface: true
decision_provenance: inline-resolved
---

# DESIGN: Lighter work-on runs

## Status

Proposed

## Context and Problem Statement

The PRD (`docs/prds/PRD-lighter-work-on-runs.md`) sets 25 requirements. This
design decides how each is built in shirabe and in what order.

The machinery in question, as it stands on main:

- `skills/work-on/koto-templates/work-on.md` has 52 states and 78 gates. A
  completed issue-backed code run enters about 28 of them.
- `skills/work-on/scripts/fix-round.sh start` opens a fix round after `done`
  as a fresh session on the same branch. Its `analysis` records the parent's
  head as `impl_base`, so its changed paths and review packet cover the fix
  commits only. But `panel-scope.sh` plans a full first round whenever a
  seat has no recorded verdict, and a fresh session has an empty
  `verdict_ledger.json`, so every seat spawns again. Its verification runs
  `scripts/check-skill.sh --changed`, which selects suites against the
  merge-base with the default branch, so it reruns the whole branch's suites.
- `test-change.sh status` decides edited-test acceptance at `pass_counting`
  (`tests_counted`), again at `pr_precheck` (`tests_still_counted`) and
  again at `ci_pass_counting`.
- `.claude/shirabe-extensions/verification-map.json` selects local commands
  by changed path. The `check-skill` command already declares a `hosted`
  twin (the `skill-gate` job). `VERIFICATION=hosted-ci` exists but is an
  init-time exception that needs a typed reason. `ci_monitor`'s
  `ci_passing` gate requires every reported check to pass, through
  `skills/work-on/scripts/pr-checks.sh`.
- `skills/work-on/references/review-level-rules.tsv` raises the floor on any
  matching rule and never lowers it. `class:test` floors at `standard` and
  `tests_edited` at `full`; `light` is reachable only for documentation.
- `issue_type_routing` declares a decider whose `code` answer is in shadow.
  `pre_pr_evidence` repeats `finalization`'s four gates. `fix_determination`
  routes on `vars.UNIT_KIND`, which its own default action rebinds, and koto
  resolves a tick's routes with the values the tick started with, so a fresh
  determination needs a second tick. `review_level_choice` asks the agent for
  a level that the facts floor overrides whenever they differ.
- `OFFLOAD_CANARY` and `PROBE` default to `on`; their draw scripts do nothing
  without a host opt-in file, but the run still passes eight states and the
  probe's leak gates. `scripts/doc-criteria.sh grade` runs on every jury
  round of five planning skills with a 180-second deadline and no opt-out.
- `skills/execute/SKILL.md` ("The lead shape") runs steps one at a time in
  PLAN order, and a plan/v2 PLAN details only steps 1 and 2, so the owning
  session rewrites each later step before it starts.

## Decision Drivers

1. **Remove repeated work before lowering any check** (PRD R5 to R9 before
   R10 to R14).
2. **Never lower review or verification for ci, security, template or
   engine paths, or for changes over 400 lines or 12 files** (R24).
3. **Every trim ships with an opt-out for one run** and a named report
   figure (R4, R25).
4. **Build in shirabe with koto 0.37**; an engine change may simplify a
   trim but must not gate it.
5. **Reuse what exists**: the retry-lap scoping in `panel-scope.sh`, the
   `hosted` declaration in the verification map, the existing opt-in files,
   the step-refine record in `/execute`.
6. **Fit the verification-cap-route work in flight** (the hosted-of-record
   route for a timed-out check) rather than racing it.
7. **Order by expected minutes saved per run over risk accepted.**

## Considered Options

### Q1. How is per-visit time measured and normalized by size?

Resolved inline. **Chosen: a report script over retained session records,
plus an append-only gather history.** The committed output holds aggregate
figures only (counts, medians, size bands), never session names, issue
titles or paths from other repositories. `review-level.sh facts` appends each
gather to a new `review_facts.jsonl` key beside the existing
`review_facts.json`, and a new `skills/work-on/scripts/run-report.sh` reads
retained sessions (state logs, `review_facts.jsonl`, `verdict_ledger.json`,
`verification_results.json`, `fix_rounds.jsonl`) and prints the R2 table per
template version and size band. Its first committed output answers R3.

Alternative: a one-off analysis outside the repo. Rejected because R4 needs
the same figures again after every trim ships, and a script in the repo is
the only way the after-figure is computed the same way as the before one.

Alternative: send per-visit sizes to koto's run journal. Rejected for now:
it needs an engine change for a figure shirabe can already compute from its
own keys.

### Q2. How does a fix round stop repeating review?

Resolved inline. **Chosen: `fix-round.sh start` copies the parent's
`verdict_ledger.json` into the new session**, marked with the parent's head.
`panel-scope.sh` then treats the round like a retry lap: seats with a passed
verdict stay passed, and the fix diff's findings go to re-verifiers. Its
existing 200-line threshold plans a full round when the fix diff is larger.
The round's review floor is the higher of the parent's last floor and the
round's own, so a round after a `full` parent never drops to `light`. The
carried ledger is used only when the parent's head is an ancestor of the
fix-round base and the merge-base with the default branch is unchanged;
otherwise the round starts with an empty ledger, as today.

Alternative: let a fix round reopen the parent session. Rejected for the
reasons `fix-round.sh`'s header gives: `done` must stay terminal for
`/execute`'s children-complete gate and for koto's leg promotion.

Alternative: have `panel-scope.sh` read the parent's ledger live. Rejected:
a later write to the parent's ledger would change a round's plan mid-flight.

### Q3. How does a fix round stop repeating verification?

Resolved inline. **Chosen: the round selects commands from paths changed
since the fix-round base, and copies the parent's passed per-command results
for every other command the parent ran.** `run-verification.sh` gains a
`--base <rev>` selection input, and the round's `verification_results.json`
starts from the parent's file with each carried entry marked `carried`.
Selection from the round's paths includes the map's `default` commands when
a round path matches no entry, exactly as a full selection would. The same
ancestry and merge-base condition as Q2 applies; when it fails, nothing is
carried.

Alternative: rerun everything at the new head. Rejected: it is today's
behaviour and the cost the PRD targets. Alternative: carry results without
reselecting. Rejected: a fix that touches a second skill would skip that
skill's suites.

### Q4. How is edited-test acceptance judged once per head?

Resolved inline. **Chosen: `test-change.sh status` gains a `--confirm`
mode** used by `pr_precheck`'s `tests_still_counted` and by
`ci_pass_counting`: it passes when the recorded acceptance digest's head is
the current head and holds otherwise, without minting a seat. Only
`pass_counting` mints acceptance seats.

Alternative: remove the later two gates. Rejected: a commit between
`pass_counting` and the pull request must still be caught.

### Q5. When is hosted CI the build of record?

Resolved inline. **Chosen: a new `VERIFICATION` value `auto`, made the
default.** At `verification` entry, `run-verification.sh plan` resolves
`auto` to `hosted-ci` when every selected command has a `hosted` twin in the
map and no changed path is in the ci, security, template or engine class,
and to `local` otherwise. The map is the merge-base copy, as
`skills/work-on/references/verification-map.md` already specifies, and
`ci_monitor` re-reads the twins from the current default branch's map before
its green edge: a twin that no longer exists sends the run to local
verification. A hosted resolution writes the deferral reason itself
(`hosted twins cover every selected command`), so the existing
`verification_deferred` route and its pull request body record apply
unchanged. `local` and `hosted-ci` keep their meaning when passed
explicitly, and `--verification=local` is the opt-out.

Alternative: make `hosted-ci` the default everywhere. Rejected: commands
with no hosted twin would lose their only run. Alternative: keep `local` the
default and add a per-command skip. Rejected: it splits one run's
verification across two places with no single build of record.

### Q6. How does `ci_monitor` wait only on relevant checks?

Resolved inline. **Chosen: `skills/work-on/scripts/pr-checks.sh` gains a
`--relevant <file>` filter.** The run writes `relevant_checks.txt` from the
selected commands' hosted twins plus a new `always_required` array in the
verification map, and `ci_passing` reads only those checks. shirabe's map
ships `always_required` seeded with its security and lint checks. A failing
check outside the set is posted as one pull request comment, and it still
blocks merging: `/execute`'s merge readiness and any `--merge` path keep
requiring every check green. An empty relevant set falls back to all
checks, so a repository with no twins behaves as today. A skipped twin
counts as not passed, as `pr-checks.sh` already treats it.

Alternative: read GitHub's required-check settings. Rejected: almost no
check in these repositories is marked required, so the set would be empty.

### Q7. How does a small diff reach `light`?

Resolved inline. **Chosen: a new rule kind, `cap`, in
`review-level-rules.tsv`, evaluated after the floor rules.** The row `cap
light lines<=200 files<=5` lowers a `standard` floor to `light` when no
`full` rule fired and neither `criteria_changed` nor `unclassified` fired.
It can never lower `full`, and a `manifest` path keeps `standard`, so a
dependency change never takes one seat. The rules file stays the one source the decider
prompt is built from, so the decider fixtures are regenerated in the same
change.

Alternative: move test, executable and instruction paths out of their
classes. Rejected: it would also change the middle band, and the classes
carry meaning the facts report.

Alternative: a pure size rule ignoring classes. Rejected by R24.

### Q8. What replaces `tests_edited -> full`?

Resolved inline. **Chosen: a narrower fact, `red_test_edited`**, set when a
fix's reproducing test (named in `red_first.json`) changed in a commit after
the red's recorded revision. The rule becomes `rule full red_test_edited`.
`tests_edited` stays as a fact for the light seat and the acceptance hold.

Alternative: drop the rule entirely. Rejected: rewriting one's own red test
is where weakening is most likely.

### Q9. How does the compatibility file stop forcing `full`?

Resolved inline. **Chosen: first add the engine-class coverage test, then
take `*.compat.json` out of the template class.** A new
`skills/work-on/scripts/review-level-rules_engine_test.sh` reads each
template's `gate_scripts` digest inputs, follows every library those
scripts source, and fails when any of them is not matched by an `engine`
row. Engine rows are added for the scripts it finds missing (for
coordinate today: `state-holding.sh`, `state-write-core.sh`,
`state-common.sh`, `reconcile-check.sh`, `coord-log.sh`). Only then does the
compatibility file move to the `manifest` class.

Alternative: leave the compatibility file in `template`. Rejected: it is
the sole `full` cause on small coordinate changes. Alternative: move it
without the test. Rejected: gate-library changes would drop to `light`.

### Q10. How is a single light seat checked?

Resolved inline. **Chosen: an `escalate` verdict plus a hashed audit.** The
light seat's prompt (`skills/work-on/references/phases/phase-4d-light.md`)
and `review-round.sh` accept `escalate`, which raises `REVIEW_LEVEL` to
`standard` through `review-level.sh raise --reason escalate` and routes back
to `review_level_check`. `review-level.sh audit <session>` returns 0 when
`sha256(session name) mod 10 == 0` (work-on derives the session name from
the issue reference, so a run can't pick its way out of the audit without
picking a different issue); an audited run's `light_review` passed
edge goes to `scrutiny` instead of `verification`, and the run records
`audit_miss` in `review_level.jsonl` when the full panel blocks.
`run-report.sh` counts misses over the last 30 audited runs. When more
than 3 are misses it prints the rules-file change that returns the cap to
40 lines and 3 files; a maintainer makes that change by pull request.

Alternative: a random draw per run. Rejected: R14 needs the same names
chosen on every evaluation. Alternative: audit by a second light seat.
Rejected: it measures agreement between two cheap seats, not what the full
panel would catch.

### Q11. What happens to `review_level_choice`?

Resolved inline. **Chosen: remove the state.** Its default action
(`review-level.sh init`, which records the bound and the rules copy) moves
to `analysis`'s exit, and `review_level_check` sets `REVIEW_LEVEL` from the
facts floor through `review-level.sh set-from-facts`, which still honours a
coordinator's bound and logs a breach when the floor exceeds the ceiling.

Alternative: keep the state with a default level. Rejected: it keeps a
state whose output the facts overwrite.

### Q12. How do the remaining constant-answer stops go?

Resolved inline. **Chosen, per stop:**

- `issue_type_routing`: promote the decider's `code` answer from shadow to
  live in the template and in `scripts/decider-declarations.tsv` together.
  The code route tests no gate, so koto's promotion floor is met. `docs` and
  `task` stay `never`. Opt-out: `ISSUE_TYPE_DECIDER=shadow`.
- `pre_pr_evidence`: delete the state. Its `cleanup_done` and
  `design_diagram` fields join `finalization`'s accepts; `finalization`
  routes to `pr_precheck`. `finalization-shape_test.sh` drops the backstop
  copy.
- `fix_determination`: add a command gate `kind_route` that runs
  `fix-kind.sh kind --exit` (exit 0 change, 10 fix) after the default
  action, and route on `gates.kind_route.exit_code` instead of
  `vars.UNIT_KIND`. The gate reads the ledger the action just wrote, so the
  route resolves in the entering tick. `kind_unchanged` stays to catch a
  hand rebind. The "declare a fix" instruction moves into `analysis`'s
  directive.

Alternative for `fix_determination`: ask koto to let routes see variables
rebound by the same tick's default action. Not chosen as the path, because
it would gate a shirabe trim on an engine release; listed under
Consequences as optional koto follow-up.

### Q13. How do experiments leave the default path, and how do plan steps run together?

Resolved inline. **Chosen for experiments:** `OFFLOAD_CANARY` and `PROBE`
default to `off`. `entry`'s and the canary's exits route on the variable's
value (koto value routing), so an `off` run goes from `analysis` straight
on and never enters a canary or probe state; the probe's
`probe_value_absent` gates move behind a `vars.PROBE: on` condition. The
existing opt-in files still decide enrolment when the variable is `on`.
`doc-criteria.sh grade` returns at once unless
`${XDG_CONFIG_HOME:-$HOME/.config}/shirabe/doc-criteria` exists with first
line `on`.

**Chosen for plan steps, in two parts.** First, the agent finishing a step
drafts the PLAN entry of each outlined step that waits only on it, as
`step_draft/<step>.md` in the owning session; the owner's existing
`step_refine/<step>.md` record is written from that draft (edited or not)
and still gates the step. Second, `/execute` gains
`--max-concurrent-steps=N` (default 2, 1 to 6). `spawn_and_await` starts
every step whose `waits_on` have all landed, up to N. In `single-pr` mode
each concurrent step works in its own worktree on a step branch and lands
on the shared branch by rebase in PLAN order; a rebase conflict stops that
step at `validation_exit` for the owner, and other steps go on. A step whose
rebase changed any of its files re-runs its verification and its review
level check at the rebased head before it counts as landed.

Alternative for plan steps: return to plan/v1 as the default. Rejected: v2's
just-in-time detailing exists so later steps see what earlier ones landed,
and the step agent has exactly that knowledge. Alternative: concurrency only
in `multi-pr` mode. Rejected: most plans here are `single-pr`, so it would
save little.

### Keep-or-cut verdicts for states added since 0.19.1

Resolved inline. The 24 states are the difference between the state names
of the 0.19.1 template and main's. Evidence is a pull request or issue
where the state caught a defect; a search of the repository's history and
designs found one such record.

| State | Verdict | Evidence | Why |
|-------|---------|----------|-----|
| `offload_canary` | trim (opt-in) | no recorded catch | experiment; Q13 |
| `offload_arm_withheld` | trim (opt-in) | no recorded catch | experiment arm marker |
| `offload_arm_preloaded` | trim (opt-in) | no recorded catch | experiment arm marker |
| `probe_draw` | trim (opt-in) | no recorded catch | experiment; Q13 |
| `probe_arm_near` | trim (opt-in) | no recorded catch | experiment arm marker |
| `probe_arm_far` | trim (opt-in) | no recorded catch | experiment arm marker |
| `probe_arm_far_redeliver` | trim (opt-in) | no recorded catch | experiment arm marker |
| `probe_near` | trim (opt-in) | no recorded catch | experiment |
| `review_level_choice` | cut | no recorded catch | facts overrule it; Q11 |
| `fix_determination` | trim | no recorded catch | keeps red-first routing, loses its second tick; Q12 |
| `reproduce` | keep | no recorded catch | proves a fix's test fails without the fix; the report counts its holds so the next review has data |
| `changed_paths_record` | keep | no recorded catch | no agent stop; feeds the facts |
| `issue_type_routing` | trim | no recorded catch | auto-routes code; Q12 |
| `review_level_check` | keep | raises the agent's level on most runs | the facts floor is the check that keeps risky paths at `full` |
| `light_review` | keep | no recorded catch | becomes reachable; Q7, Q10 |
| `verification_deferred` | keep | no recorded catch | carries the hosted build of record; Q5 |
| `verification_hosted` | keep | no recorded catch | hosted-of-record route for timeouts (work in flight) |
| `hosted_record` | keep | no recorded catch | same route's settlement |
| `pass_counting` | trim | PR #1932 is a friction fix, not a catch | acceptance minted once per head; Q4 |
| `pre_pr_evidence` | cut | PR #420: a malformed summary "was caught only at `pre_pr_evidence`", fixed by copying its gates onto `finalization` | its gates now run at `finalization`; Q12 |
| `check_exit` | keep | no recorded catch | escape for an unsatisfiable rule; no stop on the happy path |
| `ci_pass_counting` | trim | no recorded catch | confirms the acceptance head only; Q4 |
| `cascade_entry` | keep | no recorded catch | no agent stop; carries the multi-pr cascade |
| `cascade_run` | keep | no recorded catch | runs only when a cascade is owed |

A keep with "no recorded catch" is a keep on purpose, not on evidence: the
state either costs no agent stop, carries a route other work depends on, or
(for `reproduce`) guards a failure mode no other state checks. The report
in Q1 counts `reproduce`'s red-first holds so a later pass can judge it on
data.

## Decision Outcome

Eleven changes, each a shirabe pull request with an opt-out, in this order:

1. **Run report and gather history** (R1 to R4). No saving by itself; every
   later issue names its figure from it.
2. **Fix rounds inherit verdicts and verification** (R5, R6). Expected
   saving 30 to 50 minutes per run that takes a fix round, about 20 to 35
   averaged over runs, from one full panel round (seven seats) and one
   branch-wide verification no longer repeated. Risk: a fix reviewed on its
   own diff, as a retry lap already is.
3. **Constant-answer stops** (R15 to R18). Expected 12 to 20 minutes per
   run: `issue_type_routing` 3 to 8, `review_level_choice` 2 to 5,
   `pre_pr_evidence` 4, `fix_determination`'s second tick 1 to 2. Risk: the
   agent's up-front level and its fix declaration move to `analysis`; the
   facts still set the floor.
4. **Acceptance once per head** (R7). Expected 3 to 5 minutes per run that
   edits a test. Risk: none at an unchanged head.
5. **Experiments and shadow grading opt-in** (R19, R20). Seconds per work-on
   run, up to 3 minutes per planning-skill jury round. Risk: experiments
   collect data only from opted-in hosts.
6. **Engine-class coverage test** (R12). No saving; prerequisite for 9.
7. **Hosted CI as build of record where twins exist** (R8). Expected 15 to
   25 minutes per qualifying run (the local verification visit). Risk: a
   defect surfaces after the pull request opens, costing a CI round.
8. **CI wait scoped to relevant checks** (R9). Expected up to 10 to 25
   minutes on runs whose changed paths don't reach a slow suite (the
   coordinate suites take about 40 minutes). Risk: an unrelated failing
   check is reported instead of holding the run.
9. **Light cap, red-test rule, escalate and audit** (R10, R11, R13, R14).
   Expected about 45 minutes per qualifying run (one seat instead of seven),
   on roughly a quarter of runs, so 10 to 12 averaged; the audit returns
   about a tenth. Risk: runtime defects the tests miss and the light seat
   can't see.
10. **Step agents draft the next step** (R22). Saves the owner's rewrite
    turn per later step, minutes per step. Risk: a draft written by the
    agent that just finished; the owner still reviews it.
11. **Concurrent ready steps** (R21). Saves up to a whole step's duration
    per independent pair; nothing per run. Risk: rebase conflicts on a
    shared branch, bounded by the limit.

**What this design chooses not to trim.** The scrutiny, review and QA
panels stay at `full` for ci, security, template and engine paths and for
changes over 400 lines or 12 files. `review_level_check` and its facts floor
stay. `reproduce` and red-first stay. Acceptance seats still mint at
`pass_counting`. Local verification stays for template and engine changes
and wherever a command has no hosted twin. `ci_monitor` still waits for every
relevant check and for the always-required list. The 400-line and 12-file
floors are not changed, because no data argues for moving them, and the
report will say whether a later change should.

**koto dependencies.** None required. One optional follow-up for
`tsukumogami/koto`: let a tick's routes see a variable rebound by that
state's own `default_action`. It would let `fix_determination` route on
`UNIT_KIND` again and remove the `kind_route` gate, but nothing here waits
on it.

## Solution Architecture

```
            analysis (records bound + rules copy; agent may declare a fix)
                |
   [OFFLOAD_CANARY/PROBE = off] -- skip canary/probe states
                |
        fix_determination --kind_route gate--> implementation | reproduce
                |                                   (same tick)
         implementation -> changed_paths_record
                |
        issue_type_routing --decider live for code--> review_level_check
                |
        review_level_check: facts -> review_facts.jsonl (append)
                            floor rules, then cap rule (light <= 200/5)
                            set-from-facts within coordinator bound
               /            |               \
        light_review     scrutiny         (standard/full panels)
      escalate -> check   audit? -> scrutiny
                |
        verification: VERIFICATION=auto -> local | hosted (twins cover all)
                |
        pass_counting (mints acceptance once per head)
                |
        finalization (+cleanup_done, design_diagram) -> pr_precheck (--confirm)
                |
        pr_creation -> ci_monitor (relevant_checks.txt) -> ci_pass_counting (--confirm)
```

Components and their changes:

- `skills/work-on/koto-templates/work-on.md`: remove `review_level_choice`
  and `pre_pr_evidence`; add `kind_route` on `fix_determination`; value-route
  around canary and probe states; route the audited `light_review` edge;
  `VERIFICATION` gains `auto` (default); defaults of `OFFLOAD_CANARY` and
  `PROBE` become `off`; decider `code` mode live. The template's
  compatibility file is regenerated.
- `skills/work-on/scripts/review-level.sh`: `facts` appends to
  `review_facts.jsonl`; new `set-from-facts`, `audit`, and `raise --reason
  escalate`; rule kind `cap`; fact `red_test_edited`.
- `skills/work-on/references/review-level-rules.tsv`: `cap light lines<=200
  files<=5`; `rule full red_test_edited` replaces `rule full tests_edited`;
  engine rows for digest-covered scripts; `*.compat.json` to `manifest`.
- `skills/work-on/scripts/fix-round.sh`: copy the parent's
  `verdict_ledger.json` and passed `verification_results.json` entries.
- `skills/work-on/scripts/run-verification.sh`, `check-verification.sh`:
  `--base` selection, carried results, `auto` resolution, written reason.
- `skills/work-on/scripts/pr-checks.sh`: `--relevant <file>`.
- `.claude/shirabe-extensions/verification-map.json` and
  `skills/work-on/references/verification-map.md`: `always_required` array,
  seeded for shirabe.
- `skills/work-on/scripts/test-change.sh`: `status --confirm`.
- `skills/work-on/scripts/fix-kind.sh`: `kind --exit`.
- `scripts/decider-declarations.tsv`: `issue_type=code` live.
- `scripts/doc-criteria.sh`: opt-in file check.
- `skills/work-on/references/phases/phase-4d-light.md`,
  `skills/coordinate/scripts/review-round.sh`: `escalate` verdict.
- `skills/work-on/scripts/run-report.sh` (new): the R2 report.
- `skills/execute/SKILL.md`, `skills/execute/koto-templates/execute.md`,
  `skills/execute/references/step-agent-handoff.md`: step drafts,
  `--max-concurrent-steps`, per-step worktrees for `single-pr`.
- `skills/work-on/SKILL.md`: the directive prose for each change.

Data written per run (all koto context keys in the work-on session):
`review_facts.jsonl` (new, one JSON object per gather),
`relevant_checks.txt` (new), `review_level.jsonl` (gains `audit` and
`audit_miss` lines), `verdict_ledger.json` and `verification_results.json`
(gain a `carried_from` field in a fix round).

## Implementation Approach

The order is the Decision Outcome's. Items 1 to 5 change no review or
verification decision and can land in any order after item 1; they are
listed by saving. Item 6 must land before item 9. Items 7 and 8 both touch
`ci_monitor` and verification and land in that order. Item 9 lands only
after item 1's report has printed a before-figure for light-eligible runs.
Items 10 and 11 touch only `/execute`; 10 before 11, because concurrent
steps need the step agent's drafts to start without the owner's rewrite.

Each item updates the eval scenarios and test suites its scripts already
have (`*_test.sh` beside each script, `skills/work-on/evals/`), regenerates
the template's compatibility file where the template changes, and states its
opt-out in its pull request.

## Security Considerations

The design downloads nothing new and needs no new permissions: every change
is a script or template edit that runs with the agent's existing access to
the repository, `gh` and koto. Its risk is that several trims lower a check,
and a branch could try to steer that.

- **Review lowered on small diffs.** The light cap lets a small change
  through with one reviewer. It never lowers `full`, so ci, security,
  template and engine paths keep seven seats; manifests keep `standard`; the
  rules file is in the security class, so changing the cap takes a full
  review; and the audit measures misses with a named reversal. Accepted
  residual risk: an edited ordinary test or an instruction file can be
  reviewed at `light`. The light seat must judge every edited test as
  correcting or weakening, the acceptance seat at `pass_counting` judges it
  again, and audited runs measure what that misses.
- **Fix rounds.** A round's floor is the higher of the parent's and its own,
  and verdicts and results are carried only when the parent's head is an
  ancestor of the round base and the merge-base is unchanged. Only passed
  results carry; a failed or unfinished command runs again.
- **Hosted build of record.** `auto` resolves to `local` for any ci,
  security, template or engine path. The twins come from the map's
  merge-base copy, which the branch itself can't edit, and are re-read from
  the current default branch before `ci_monitor`'s green edge.
- **Relevant-check filter.** The always-required list holds whatever paths
  changed, shirabe seeds it with its security and lint checks, an empty
  relevant set falls back to every check, a skipped check counts as not
  passed, and a failing out-of-set check still blocks any merge.
- **Audit draw.** The draw hashes the session name, which work-on derives
  from the issue reference; dodging it means working a different issue.
- **Concurrent steps.** Each step has its own worktree under the
  repository's worktree directory and lands by rebase in PLAN order; a
  conflict stops the step, and a rebase that changed its files re-runs its
  verification and level check at the new head.
- **Report contents.** The committed report is aggregate only, so it can't
  carry session names, issue titles or another repository's paths.
- **Opt-in files.** The experiment and grading opt-ins are files in the
  user's own config directory, read as data; only an exact first line `on`
  enables them.

## Consequences

### Positive

- A fix round costs what the fix costs, which addresses the clearest cause
  of sessions per run rising from one to three.
- Four agent stops that never changed a route are gone.
- A small change outside the risky classes gets one reviewer, and the audit
  says whether that is enough.
- Verification runs once per round where hosted CI already runs the same
  check, and the CI wait stops holding on suites the change can't reach.
- Independent plan steps progress together, and later steps no longer wait
  for the owner to rewrite them.
- Every trim has a before and after figure from the same report.

### Negative

- More configuration surface: `VERIFICATION=auto`, `always_required`,
  `--max-concurrent-steps`, three opt-in files.
- The light seat doesn't run code; some runtime defects will surface later.
- Defects found by hosted CI cost a CI round instead of a local run.
- Per-step worktrees add disk use and a rebase step in `single-pr` plans.
- Experiments lose data from hosts that don't opt in.

### Mitigations

- Each trim's opt-out restores today's behaviour for a run until its
  after-figure is read.
- The audit bound returns the light cap to 40 lines and 3 files by a
  reviewed rules-file change.
- The step concurrency limit's value 1 is today's serial order.
- Items 1 to 5 land first and lower no check, so most of the expected
  saving arrives before any risk is taken.

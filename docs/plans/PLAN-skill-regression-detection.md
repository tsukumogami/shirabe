---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-skill-regression-detection.md
milestone: "Skill regression detection without paid evals"
step_count: 9
---

# PLAN: Skill regression detection without paid evals

## Status

Active

## Scope Summary

This plan builds what `docs/designs/DESIGN-skill-regression-detection.md`
decides: no eval calls a model on any path, a script-graded case kind checks
each skill's hand-offs, the shape check makes every skill that hands off carry
those cases, the pull request gate runs them on Linux and on the macOS bash 3.2
leg, and the release runs every skill's script cases, records per-case
verdicts in `eval-pass-rates.json`, and stops at exit 5 on any failing case
until a person confirms. It covers all three of the design's implementation
phases: script cases and the hand-off check (steps 1 to 5), the pull request
gate and the harness guards (step 6, with step 5), and the release running
script cases (steps 7 to 9).

## Decomposition Strategy

Walking skeleton, as a step plan. Step 1 crosses the path both pieces of the
design's acceptance evidence lean on: a `grader: script` case in
`/deliver`'s `evals.json`, `run-evals.sh deliver` handing script cases to the
standalone `script-cases.py` runner before any prerequisite check, and
`check-handoff.sh deliver execute` checking the receiving side of the
hand-off. It goes first because Decision 2 makes the runner and the hand-off
check the one definition the harness, the gate and the release all execute,
so every later step reuses what step 1 opens. Step 2 completes the hand-off
check's four parts and adds the scope and work-on cases. Steps 3 and 4 make
the cases mandatory for every skill and run them in `check-skill.sh`, which
step 6's gate job calls. Step 5 closes the remaining graded paths, as
Decision 1 requires. Steps 7 and 8 move the release onto the runner's
summaries, as Decision 3 decides, and step 9 brings the release docs in line.

The work lands in one pull request. No step must reach the default branch
before a later one can run (the gate job triggers on `pull_request` from the
branch itself), and the phases aren't independently useful in either order: the
harness refusing graded cases (step 1) before the release check stops calling
it for graded runs (step 8) would leave the release check broken in between.

The design leaves four details open, and the plan settles each without
changing a decision:

- One assertion for a script case is one script case: the record's
  `assertions: {passed, graded}` counts cases run and cases passed (step 1).
- A case that failed in the baseline and fails again is labelled still
  failing, next to the design's regressed and failing-no-baseline labels. Any
  failing case still exits 5, so the stop rule is unchanged (step 7).
- Case names read from a baseline record are held to the design's
  `[A-Za-z0-9._-]` rule, and a record that breaks it is skipped as unusable
  (step 7).
- A downloaded `eval-pass-rates.json` over the existing 1 MiB record cap is
  skipped as unusable before it is read (step 8).

No check in this plan runs a model-graded eval: the checks run the harness
only against fixture skills with a failing `claude` stub first on `PATH`, and
call the runner directly on the real tree.

## Steps

### Step 1: the harness runs /deliver's execute hand-off case with no model and fails it on a broken outcome word

**Goal**: A maintainer runs `scripts/run-evals.sh deliver` and sees /deliver's execute hand-off case run and pass with no model call, and fail by name when /execute's outcome words drift from what /deliver accepts. The path crossed: a `grader: script` case in `skills/deliver/evals/evals.json` (id 34, `handoff-execute-contract`, `handoff: execute`, `run: scripts/check-handoff.sh deliver execute`) goes through `scripts/run-evals.sh deliver`, which hands script cases to a new standalone `scripts/lib/script-cases.py` before its koto probe, its `claude` prerequisite and anything else that needs bash 4 or a model, and the runner executes `scripts/check-handoff.sh deliver execute`. In this step that script does the receiving-side contract check only: the target template's file name matches what the leg accepts, every outcome word assigned on an edge into `execute.md`'s terminal states is in `deliver.md`'s `exec_leg` `expect` list, `execute.md`'s result map carries every key `deliver.md`'s `execute_run` transitions copy, and `skills/execute/SKILL.md` declares `--koto-leg`. The routes, rendered-directive and real-attach checks belong to step 2.

**Acceptance Criteria**:

- [ ] `scripts/run-evals.sh deliver` on bash 3.2, with a failing `claude` stub first on `PATH`, lists case 34 `handoff-execute-contract` as passed and each of cases 1 to 33 as refused because it's graded and graded cases don't run, prints `script cases: 1 of 1 passed`, and exits 0, the harness exit table's code for every assertion passing.
- [ ] The same run starts no nested session and makes no model call: the `claude` stub, which records every call and exits non-zero, has an empty record afterwards; with no `claude` anywhere on `PATH`, the run exits 0 instead of exiting 3 with `Error: claude CLI not found`.
- [ ] With `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `CLAUDE_CODE_USE_BEDROCK` or `CLAUDE_CODE_USE_VERTEX` set, the harness still refuses every graded case and the output and exit code don't change; no flag or variable makes it run one.
- [ ] A case with no `grader` key, or with a `grader` value the runner doesn't know (such as `"scripted"`), is listed as refused like any graded case, and its `run` field is never executed.
- [ ] The outcome-word check reads every terminal state an edge reaches in `execute.md`, not a fixed list: in four separate copies of the tree, renaming the outcome word assigned on the edges into one terminal state (`paused-for-review` on the edges into `paused_for_review`, `merged` into `merged`, `ready-awaiting-merge` into `ready_awaiting_merge`, `error` into `done_blocked`), a different state in each copy, makes `scripts/check-handoff.sh deliver execute` exit non-zero with a message naming the renamed word as one /deliver's `exec_leg` doesn't expect. Through the harness, the `merged` rename makes case 34 fail with that word in its reason, prints `script cases: 0 of 1 passed`, and exits 1.
- [ ] A copy of `execute.md` with a new terminal state whose incoming edge assigns a new outcome word (`parked`) fails the check naming `parked`, and a copy of `deliver.md` whose `exec_leg` `expect` list drops `paused-for-review` fails it naming `paused-for-review`, so both sides of the comparison come from the templates as they stand.
- [ ] The result-key check reads the keys from `deliver.md`'s `execute_run` transitions, not a fixed list: dropping each key those transitions copy (`pr`, `repos`, `resume`, `waiting`, `reason`, `step`) from a terminal state's result map in `execute.md`, one copy per key, fails the check naming that key and the terminal state missing it; a copy of `deliver.md` whose `execute_run` transition also copies a key no result map in `execute.md` carries (`extra`) fails it naming `extra`.
- [ ] A copy where `skills/execute/koto-templates/execute.md` is renamed (to `execute-v2.md`) fails the check naming `execute.md` as the template the `execute` leg accepts and finding no such file; a copy with the `--koto-leg` declaration removed from `skills/execute/SKILL.md` fails it naming `--koto-leg`. On the unchanged tree the check exits 0.
- [ ] The runner refuses before executing anything, with a message naming the rule broken, a case whose `run` first word doesn't resolve through `realpath` to a tracked regular file that isn't a symlink and is `scripts/check-handoff.sh` or under `scripts/cases/` (an untracked script, a symlink to an allowed script, `scripts/release-eval-check.sh`), whose arguments don't all match `[A-Za-z0-9][A-Za-z0-9._-]*` (`..`, `--all`, `deliver;id`), or whose skill-position argument names no directory under `skills/` (`scripts/check-handoff.sh deliver nosuchskill`). `run` is split on spaces and executed without a shell, so `$(...)`, `|` or `>` in it never act as shell syntax.
- [ ] A case runs with only `PATH`, `LANG`, `TMPDIR`, a fresh temporary `HOME` and a temporary koto state directory in its environment: a fixture case that prints its environment, run with `ANTHROPIC_API_KEY`, `GH_TOKEN`, `GITHUB_TOKEN` and `SSH_AUTH_SOCK` set in the caller's shell, shows none of them and shows a `HOME` that isn't the caller's.
- [ ] A case runs in its own process group and is killed as a group when its timeout runs out (300 seconds unless a shorter one is set): a fixture case that starts a background child and then sleeps past a shortened timeout fails with a reason saying it timed out, and its background child is no longer running afterwards.
- [ ] A failing case's reason is its output with control characters stripped and cut to its last 200 lines: a fixture case that prints 500 numbered lines, an escape sequence among them, and exits 1 shows lines 301 to 500 and no escape byte.
- [ ] The runner writes a per-skill summary with cases run, cases passed, pass rate and each case's verdict by name, and records `assertions: {passed, graded}` where one assertion is one script case: `graded` is the number of script cases run and `passed` the number that passed. A fixture skill with two script cases, one failing, reports assertions passed 1 of graded 2, pass rate 0.5, one `pass` and one `fail` verdict, and the harness exits 1.
- [ ] `python3 scripts/lib/check-evals-shape.py skills/deliver/evals/evals.json skills/deliver/SKILL.md` exits 0 with case 34 in the file, which carries `grader`, `run` and `handoff` and no `prompt` or `expectations`; the same check on a copy where one graded case has lost its `prompt` or its `expectations` exits 1 naming that case, as it does today.

**Check**: Run `bash scripts/run-evals_test.sh`. Its runner group points the harness at the suite's throwaway fixture skill (one passing script case, one failing script case, one graded case, one case with no grader, one with an unknown grader, and cases that break each containment rule, print their environment, outlive a shortened timeout, and print 500 lines) with the failing `claude` stub first on `PATH`, and once with no `claude` on `PATH`; look for a `PASS:` line for each of those criteria, no `FAIL:` line, and the closing `Results: <n> passed, 0 failed` with exit 0. Then run `bash scripts/check-handoff_test.sh`, which copies the tree into temporary directories and, one copy per mutation, renames the outcome word on the edges into each of the terminal states `paused_for_review`, `merged`, `ready_awaiting_merge` and `done_blocked`, adds a terminal state assigning `parked`, drops `paused-for-review` from the `expect` list, drops each of `pr`, `repos`, `resume`, `waiting`, `reason` and `step` from a result map, adds a copied `extra` key, renames `execute.md`, and removes the `--koto-leg` declaration, running that copy's `scripts/check-handoff.sh deliver execute` each time; look for a `PASS:` line per mutation stating the check exited non-zero with the mutated word, key or file name in its message, a `PASS:` line for the unchanged tree exiting 0, and `Results: <n> passed, 0 failed`. Then, on the real tree, run `python3 scripts/lib/script-cases.py deliver`, which has no path to `claude`: it prints case 34 `handoff-execute-contract` as passed and `script cases: 1 of 1 passed`, and exits 0. Last, make a temporary copy that is its own repository, rename the word, and run the copy's runner:

```bash
tmp=$(mktemp -d)
git ls-files -co --exclude-standard -z | tar -cf - --null -T - | tar -xf - -C "$tmp"
cd "$tmp" && git init -q && git add -A
sed 's/^\(          \)outcome: merged$/\1outcome: landed/' skills/execute/koto-templates/execute.md > execute.md.new
mv execute.md.new skills/execute/koto-templates/execute.md && git add -A
python3 scripts/lib/script-cases.py deliver; echo "exit=$?"
```

Look for case 34 `handoff-execute-contract` marked failed with a reason naming `landed` as an outcome word the `exec_leg` gate doesn't expect, `script cases: 0 of 1 passed`, and `exit=1`. Remove the temporary directory afterwards.

**Dependencies**: None

**Files**: `scripts/run-evals.sh`, `scripts/lib/script-cases.py`, `scripts/check-handoff.sh`, `scripts/check-handoff_test.sh`, `scripts/lib/check-evals-shape.py`, `scripts/lib/check-evals-shape_test.py`, `scripts/run-evals_test.sh`, `scripts/run-evals/fixtures/bin/claude`, `skills/deliver/evals/evals.json`

### Step 2: a break anywhere in a /deliver or /execute hand-off fails a named case

**Goal**: `scripts/check-handoff.sh <from> <to>` runs the other three checks Decision 2 of `docs/designs/DESIGN-skill-regression-detection.md` lists next to step 1's receiving-side contract check. It runs the caller's existing engine, leg and structure suites under a selector for the target's routes. It renders the directive of the state that waits on the target's leg and checks that it names skill `<to>` and `--koto-leg=<req>:<leg>`. It attaches the real target template with `koto init --koto-leg=<req>:<leg>` against a fresh request in a temporary koto state directory. `/deliver` gets its second script case (`handoff: scope`) and `/execute` gets one for `work-on`, where the leg is the child template reference `assert-child-template.sh` already checks. A maintainer who breaks either skill's hand-off in a template, a leg script, a directive or the target's file name now sees a named case fail, with no model call.

**Acceptance Criteria**:

- [ ] On the unmodified tree, `check-handoff.sh deliver execute`, `check-handoff.sh deliver scope` and `check-handoff.sh execute work-on` each exit 0 and print one passing line for each of the four checks.
- [ ] The receiving-side contract check reads result keys per outcome, not against every terminal: a caller transition that pins an outcome word needs each key it copies in the result map of every target terminal that can end with that word, and a transition that pins none needs each copied key in at least one terminal. Where the target carries fewer keys for an outcome by design (scope's terminals each carry only their outcome's keys, and `/deliver` reads an absent key as empty), `scripts/check-handoff.results.tsv` declares, per edge and outcome, the keys the target carries, and the check holds the target to those. A record that names an outcome the leg gate doesn't expect, names a key the transition doesn't copy, or leaves out a copied key that every terminal of that outcome carries fails the check. With `pr_state` dropped from scope's `done_executed`, `step` from `done_error`, or `reason` from `done_refused`, `check-handoff.sh deliver scope` exits non-zero, and its output names the key, the terminal and the outcome word. Step 1's breaks on `/execute`'s terminals (a copied key dropped from `merged`) still make `check-handoff.sh deliver execute` exit non-zero, since that edge has no record.
- [ ] With `exec_leg` removed from `execute_run` in `deliver.md`, renamed, or missing one of the five outcomes in its `expect` list, `check-handoff.sh deliver execute` exits non-zero, and its output names `exec_leg` and, for a dropped outcome, the outcome word that's missing.
- [ ] With `execute_run`'s directive no longer naming skill `execute`, or no longer carrying `--koto-leg=<req>:execute`, `check-handoff.sh deliver execute` exits non-zero, and its output names the rendered-directive check and which of the two is missing.
- [ ] With `deliver-execute-leg.sh` broken so the hand-over route fails (it exits non-zero, or drops an argument the route asserts), `check-handoff.sh deliver execute` exits non-zero, and its output carries the engine suite's failing line for the hand-over to `/execute`.
- [ ] With `execute.md` renamed so koto refuses to attach it to the `execute` leg, `check-handoff.sh deliver execute` exits non-zero, and its output names the attach check and includes koto's refusal.
- [ ] The scope hand-off fails the same way: removing or renaming `scope_leg` or `scope_intent`, dropping an outcome from their `expect` lists, rendering `scope_run`'s directive without skill `scope` or without `--koto-leg=<req>:scope`, or renaming `scope.md` so the attach is refused each make `check-handoff.sh deliver scope` exit non-zero, and the output names the gate, the missing directive part or the refused attach.
- [ ] With `execute.md`'s `spawn_and_await` `default_template` pointing at a work-on template that doesn't exist, or with `work-on.md` renamed, `check-handoff.sh execute work-on` exits non-zero, and its output names the child template reference and the path that didn't resolve.
- [ ] `deliver-engine_test.sh` run with the execute route selector runs only the sections on the hand-off to `/execute`, and with the scope selector only the sections on the hand-off to `/scope`. Neither prints a section that belongs only to the other. Run with no selector, it runs every section and reports the same pass count as before this step. The `/execute` suites that `check-handoff.sh execute work-on` runs behave the same way under their selector.
- [ ] With koto absent from `PATH`, or a koto whose `koto init --help` lacks `--koto-leg`, every hand-off case exits non-zero, and its output names koto as the reason. A hand-off case never passes on an engine suite's SKIP-and-exit-0.
- [ ] The attach and the engine suites never touch the caller's real koto sessions. The sessions koto lists for the caller are the same before and after a passing run and a failing run, and the temporary state directory is gone once the run exits.
- [ ] Every case runs under macOS bash 3.2 and gives the same verdicts there as under a newer bash.

**Check**: Run `bash scripts/check-handoff_test.sh`, the suite step 1 started and this step extends with the cases below, under bash 3.2. The suite works on temporary copies of the tree, never on the checkout itself. For each mutation (the `exec_leg` gate removed, renamed and short one `expect` entry; the `execute_run` directive without skill `execute` and without `--koto-leg`; `deliver-execute-leg.sh` broken; `execute.md` renamed; each of the same breaks on the scope side; `default_template` pointing at a missing work-on template; the scope result-key drops; a `check-handoff.results.tsv` record naming an unknown outcome, a key the transition doesn't copy, or leaving out a key every terminal of its outcome carries), it shows `check-handoff.sh <from> <to>` exiting non-zero with the broken part named in its output. It also shows the koto-absent case exiting non-zero naming koto, and the selector and no-selector runs of `deliver-engine_test.sh`. On the unmodified copy, `deliver execute`, `deliver scope` and `execute work-on` each exit 0. Look for an `ok` line per case, no `FAIL` line, and exit status 0. Then, on the real tree, run `python3 scripts/lib/script-cases.py deliver` and see both hand-off cases (`handoff: execute` and `handoff: scope`) listed as pass with exit 0, and `python3 scripts/lib/script-cases.py execute` and see the `handoff: work-on` case listed as pass with exit 0.

**Dependencies**: Step 1

**Files**: `scripts/check-handoff.sh`, `scripts/check-handoff.results.tsv`, `scripts/check-handoff_test.sh`, `skills/deliver/scripts/deliver-engine_test.sh`, `skills/deliver/scripts/testdata/engine-lib.sh`, `skills/execute/scripts/execute-template-structure_test.sh`, `skills/execute/scripts/execute-coordinated-engine_test.sh`, `skills/deliver/evals/evals.json`, `skills/execute/evals/evals.json`

### Step 3: the shape check refuses a skill whose derived hand-off target has no script case

The shape check derives each skill's hand-off targets from its koto templates (request-leg `leg:` names, `--koto-leg=` in directives, child template references), refuses a target with no `grader: script` case naming it in `handoff`, refuses an undeclared templated leg such as `coordinate.md`'s `{{WAIT_LEG}}`, refuses a `run` field outside the allowed paths and argument charset, and every skill the derivation names gets its cases.

### Step 4: check-skill.sh runs a skill's script cases and every other skill's cases that target it

`check-skill.sh execute` fails when a change to `/execute`'s outcome words breaks `/deliver`'s execute case, and `--changed` picks the script-case step when only `evals/` changed.

### Step 5: no path can start a graded run

`scheduled-evals.py` has no fallback cap and starts no graded run whatever its flags and environment, and a manual dispatch of `run-evals.yml` reaches the same refusal the harness gives every graded case.

### Step 6: the pull request gate runs the cases on Linux and macOS bash 3.2 with read-only permissions

A `check-skill-gate.yml` job on `pull_request` runs `check-skill.sh` on each skill with changed files and `script-cases.py --all` on a shared-path change, `check-evals.yml` and the gate declare `permissions: contents: read`, and `check-run-evals.yml` fails if `run-evals.yml` gains an automatic trigger or either gate loses those properties.

### Step 7: eval-pass-rates.py labels each failing case and exits 5 whatever the baseline says

`merge` accepts script measurements with per-case verdicts, labels each failing case regressed, still failing (failed in the baseline and fails again, with the skill's rate not below its baseline rate) or failing with no baseline, skips a baseline record whose case names fall outside `[A-Za-z0-9._-]`, builds the record only from this run, and exits 5 on any failing case whether the baseline has the case passing, failing, skipped, absent or under another scenario set.

### Step 8: the release runs every skill's script cases and stops on any failing case until confirmed

`release-eval-check.sh` runs `script-cases.py --all` instead of the graded loop, skips a downloaded `eval-pass-rates.json` over the 1 MiB record cap as unusable before reading it, exits 5 until `RELEASE_CONFIRMED_DROPS` names every skill with a failing case, exits 1 with a retry message when koto or a download fails, prints the "script cases: P of N passed" and "model-graded cases: not run" lines, and never reaches a failing `claude` stub.

### Step 9: the release docs describe the script-only check

`release.md` declares the check with no model options and a host that needs koto but not `claude` or bash 4, the release skill empties every `RELEASE_CONFIRMED_*` variable before the first check, and CLAUDE.md, AGENTS.md, the extension README and `DESIGN-evals-at-release.md` describe the split the design sets.

## Implementation Sequence

The steps run in order on one branch. Steps 2, 5 and 7 each need only step 1,
so once step 1 is done they can run in any order; steps 3, 4 and 6 follow
step 2 in sequence, and steps 8 and 9 follow step 7. The plan's owner details
step 3 after step 2's work reaches its terminal, and each later step the same
way, in a commit that touches only this plan.

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

**Goal**: `scripts/lib/check-evals-shape.py <evals.json> <SKILL.md>` derives the skill's hand-off targets from its koto templates and refuses the file when a target has no `grader: script` case naming it in `handoff`, as Decision 2 of `docs/designs/DESIGN-skill-regression-detection.md` decides. It reads every `skills/<name>/koto-templates/*.md` except `*.mermaid.md` as text, needing no koto, and takes a target from each of three sources on its own: the `leg:` of a `type: request-leg` gate, the leg after the colon in a `--koto-leg=<req>:<leg>` a directive carries, and the skill directory a `default_template:` path resolves into. On today's templates that gives `deliver` the targets `execute` (gate `exec_leg` in `execute_run`, and its directive) and `scope` (gates `scope_leg` and `scope_intent` in `scope_run`, and its directive), both already covered by cases 34 and 35; `execute` the target `work-on` (`spawn_and_await`'s `default_template` in `execute.md`), covered by case 86, and nothing from `execute-coordinated.md`; `scope` and `work-on` none. `coordinate.md`'s `wait_leg` gate `leg_result` reads `leg: "{{WAIT_LEG}}"`, a templated leg the shape check can't resolve, so `/coordinate` names its targets on its cases: the four skills whose row in `skills/coordinate/references/entry-points.tsv` answers a leg, `deliver`, `execute`, `scope` and `work-on`, none of which has a case yet. This step adds those four cases to `skills/coordinate/evals/evals.json` (ids 43 to 46, `run: scripts/check-handoff.sh coordinate <to>`), and teaches `scripts/check-handoff.sh` the templated-leg hand-off so they pass: today `scripts/lib/check-handoff.py` finds only a literal `leg: <to>` or a `default_template` reference, and the route-suite table in `check-handoff.sh` has rows for the three step 2 edges only. That table moves to one file both `check-handoff.sh` and `check-handoff_test.sh` read, so a new edge is one row. The shape check also takes on the `run` rules `scripts/lib/script-cases.py` enforces before it executes a case, calling the same function rather than a copy, and refuses a script case that carries `prompt` or `expectations`, which its header already says and the code doesn't yet check.

**Acceptance Criteria**:

- [ ] On the unmodified tree, `python3 scripts/lib/check-evals-shape.py skills/<name>/evals/evals.json skills/<name>/SKILL.md` exits 0 for every skill that has an `evals.json`, and its `shape ok` line lists the skill's hand-off targets: `execute, scope` for `deliver`, `work-on` for `execute`, `deliver, execute, scope, work-on` (declared for the templated leg) for `coordinate`, and none for `scope`, `work-on` and every skill with no `koto-templates/` directory.
- [ ] Targets come from the templates, not a fixed list. In a fixture repository (its own `git init`, with `skills/demo/` and an empty `skills/review/`), a `demo.md` carrying only a `type: request-leg` gate on `leg: review`, one carrying only a directive with `--koto-leg={{REQ}}:review`, and one carrying only `default_template: ../../review/koto-templates/review.md`, each with no script case, make the check exit 1 with output naming `review`, the template file and the source (the gate's state and name, the directive's state, or the `default_template` reference). The same lines in `demo.mermaid.md` derive nothing and the check exits 0. Adding `{"grader": "script", "handoff": "review", "run": "scripts/check-handoff.sh demo review"}` to `demo`'s `evals.json` makes each exit 0.
- [ ] On copies of the real tree, deleting `/deliver`'s case 35 makes the check on `skills/deliver/evals/evals.json` exit 1 naming target `scope` and `deliver.md`; deleting case 34 names `execute`; deleting `/execute`'s case 86 names `work-on` and the `default_template` reference in `execute.md`'s `spawn_and_await`. A copy with a new request-leg gate on `leg: work-on` added to `deliver.md` exits 1 naming `work-on` until a case for it is added.
- [ ] A templated leg needs a declaration. A copy with all four of `/coordinate`'s script cases deleted makes its check exit 1 naming `{{WAIT_LEG}}`, state `wait_leg` and `coordinate.md` as a templated leg with no declared target; a fixture directive carrying `--koto-leg={{REQ}}:{{LEG}}` is treated the same way. A declared target must name a skill whose `SKILL.md` declares `--koto-leg`: a `/coordinate` case with `handoff: explore` and `run: scripts/check-handoff.sh coordinate explore` exits 1 naming `explore` and `--koto-leg`.
- [ ] A case's `handoff` and its `run` agree. With case 35's `handoff` changed to `execute` (its `run` still `scripts/check-handoff.sh deliver scope`), the check exits 1 naming both values; a case in `/deliver`'s file whose `run` is `scripts/check-handoff.sh execute work-on` exits 1 naming `execute` as a skill other than the one whose file holds the case. A `grader: script` case that also carries `prompt`, or `expectations`, exits 1 naming the case and the key.
- [ ] The shape check refuses every `run` the runner refuses, with the same rule text, because both call one containment function in `scripts/lib/script-cases.py` that takes the repository root (for the shape check, the directory two levels above the skill's directory). Each of `scripts/release-eval-check.sh deliver execute`, an untracked file under `scripts/cases/`, a tracked symlink under `scripts/cases/` pointing at `scripts/check-handoff.sh`, the arguments `..`, `--all` and `deliver;id`, and `scripts/check-handoff.sh deliver nosuchskill` makes `check-evals-shape.py` exit 1 and `script-cases.py` refuse the case, and both outputs carry the same rule sentence.
- [ ] With no koto on `PATH`, every shape-check verdict above is unchanged.
- [ ] `scripts/check-handoff.sh coordinate <to>` for each of `deliver`, `execute`, `scope` and `work-on` exits 0 on the unmodified tree and prints one passing line for each of the four checks, run as a third hand-off kind beside leg and child: the caller's template has a request-leg gate whose `leg:` is a `{{VAR}}`, and `<to>`'s row in `entry-points.tsv` stands in for the literal leg. The receiving-side contract requires that row to name leg `<to>` and admit `<to>.md`, that file to exist, `skills/<to>/SKILL.md` to declare `--koto-leg`, and each key `wait_leg`'s transitions copy off `leg_result` (`step`, `reason`, `pr`) to be in at least one terminal's result map of `<to>.md`, or in the keys a `scripts/check-handoff.results.tsv` record declares. A copy with `deliver`'s row leg column set to `-` exits non-zero naming `entry-points.tsv` and `deliver`; one whose `scope` row no longer admits `scope.md` names `scope.md`; one with `--koto-leg` removed from `skills/work-on/SKILL.md` names `--koto-leg`; one with `pr` dropped from `work-on.md`'s `done` and `done_already_complete` result maps names `pr`.
- [ ] `check-handoff.results.tsv` takes `-` in its outcome field for a caller transition that pins no outcome, and `/coordinate`'s edge to `work-on` carries the record `coordinate	work-on	-	pr`, since `work-on.md`'s terminals carry only `pr`. A `-` record listing a key the transitions don't copy (`repos`), or leaving out a copied key some terminal of `<to>` carries (`pr`), fails `check-handoff.sh coordinate work-on` naming the record's line and the key; deleting the record fails it naming `step` and `reason`.
- [ ] For the templated kind, the rendered-directive check holds the waiting gate's `request:` and `leg:` to variables a state captures with `capture_stdout_as` (`WAIT_REQ` in `leg_pick`, `WAIT_LEG` in `wait_leg`), since `dispatch-worker.sh`, not a directive, composes the worker's `--koto-leg`; a copy capturing `WAIT_LEG_X` instead exits non-zero naming the directive check and `WAIT_LEG`. The attach creates a request with `koto request create` in the shape `dispatch-worker.sh` sends (one leg named `<to>`, the row's admitted templates and its pinned inputs) and attaches `<to>.md` with `koto init --koto-leg=<req>:<to>`; a copy with `work-on.md` renamed exits non-zero naming the attach check with koto's refusal in the output.
- [ ] The route-suite table lives in one file, `scripts/check-handoff.routes.tsv` (from, to, suite), that `check-handoff.sh` and `check-handoff_test.sh` both read, and neither script names a suite path. `/coordinate`'s four edges each run `skills/coordinate/scripts/dispatch-worker_test.sh`, `wait-target_test.sh` and `dispatch-path_engine_test.sh` whole, since none takes `HANDOFF_ROUTE`. With `dispatch-worker.sh` changed so a `/deliver` worker's invocation drops `--koto-leg`, `check-handoff.sh coordinate deliver` exits non-zero carrying `dispatch-worker_test.sh`'s failing line. In a copy where `assert-child-template_test.sh` is made to exit 1, `check-handoff.sh execute work-on` exits non-zero while its row is present and 0 once that row is removed, with no edit to either script. The `execute work-on` rows stay `execute-template-structure_test.sh` and `assert-child-template_test.sh`; `execute-coordinated-engine_test.sh` gets no row, since none of its sections touch a work-on child.
- [ ] What `koto workflows` lists for the caller is the same before and after a passing and a failing `check-handoff.sh coordinate work-on`, and the temporary state directory is gone once it exits.
- [ ] On the real tree, `python3 scripts/lib/script-cases.py coordinate` lists cases 43 to 46 as passing and prints `script cases: 4 of 4 passed` with exit 0, and `script-cases.py deliver` and `script-cases.py execute` still print 2 of 2 and 1 of 1. Every case gives the same verdicts under macOS bash 3.2 as under a newer bash.

**Check**: Run `python3 scripts/lib/check-evals-shape_test.py`. It needs git, and koto for the one case that runs the shape check again with koto on `PATH` and compares the verdicts (every other case runs with koto off `PATH`); it builds fixture repositories for the derivation, templated-leg, `handoff`/`run` and containment cases, copies the tree into temporary repositories for the case deletions, and calls `script-cases.py` beside the shape check on each containment break to compare their rule text. Look for `OK` and exit 0. Then, on the real tree, run the shape check on every skill:

```bash
for d in skills/*/; do
  [ -f "$d/evals/evals.json" ] || continue
  python3 scripts/lib/check-evals-shape.py "$d/evals/evals.json" "$d/SKILL.md" || echo "FAILED: $d"
done
```

Look for a `shape ok` line per file, the targets listed for `coordinate`, `deliver` and `execute` as above, and no `FAILED:` line. Then run `bash scripts/check-handoff_test.sh` under macOS `/bin/bash` (3.2); it sources `scripts/lib/koto-test-guard.sh` before any koto call, as today, and gains the `/coordinate` edges' unchanged runs, the entry-point row, `--koto-leg`, result-key, `-` record, capture and attach mutations on small copies, the `dispatch-worker.sh` route mutation and the route-table row removal on the full copy, and the before-and-after `koto workflows` comparison. Look for an `ok` line per case, no `FAIL` line, and `Results: <n> passed, 0 failed` with exit 0. Then run `python3 scripts/lib/script-cases.py coordinate`, `deliver` and `execute` and see 4 of 4, 2 of 2 and 1 of 1 passed, each with exit 0. Last, make a temporary copy that is its own repository, delete case 86, and run the copy's shape check:

```bash
tmp=$(mktemp -d)
git ls-files -co --exclude-standard -z | tar -cf - --null -T - | tar -xf - -C "$tmp"
cd "$tmp" && git init -q && git add -A
python3 -c 'import json; p="skills/execute/evals/evals.json"; d=json.load(open(p)); d["evals"]=[c for c in d["evals"] if c.get("id")!=86]; open(p,"w").write(json.dumps(d, indent=2)+"\n")'
python3 scripts/lib/check-evals-shape.py skills/execute/evals/evals.json skills/execute/SKILL.md; echo "exit=$?"
```

Look for a message naming target `work-on` and the `default_template` reference in `execute.md` as having no `grader: script` case, and `exit=1`. Remove the temporary directory afterwards.

**Dependencies**: Step 2

**Files**: `scripts/lib/check-evals-shape.py`, `scripts/lib/check-evals-shape_test.py`, `scripts/lib/script-cases.py`, `scripts/check-handoff.sh`, `scripts/lib/check-handoff.py`, `scripts/check-handoff.routes.tsv`, `scripts/check-handoff.results.tsv`, `scripts/check-handoff_test.sh`, `skills/coordinate/evals/evals.json`

### Step 4: check-skill.sh runs a skill's script cases and every other skill's cases that target it

**Goal**: `scripts/check-skill.sh <skill>` gains a script-case check after its eval-shape check, as Decision 2 of `docs/designs/DESIGN-skill-regression-detection.md` and its Components table decide: it runs the skill's own `grader: script` cases and every other skill's `grader: script` case whose `handoff` names the skill, so a change to `/execute`'s outcome words fails `/deliver`'s case 34 in `/execute`'s own pull request. Today nothing selects cases by `handoff`: `scripts/lib/script-cases.py` takes one skill (with `--scenario`) or `--all`, so this step gives it a third selection, `--for <skill>`. It runs `<skill>`'s own script cases, then each other skill's script cases whose `handoff` is `<skill>`, under the same `== <skill>` headers `--all` prints, with one closing `script cases: P of N passed` line. Graded cases aren't listed, since the harness reports those. `--for` with `--list` prints each case it would run as `<skill> <id> <name>` and runs none. On today's files that gives `execute` its own case 86 plus coordinate 44 and deliver 34; `work-on` gives coordinate 46 and execute 86; `scope` gives coordinate 45 and deliver 35; `deliver` gives its own 34 and 35 plus coordinate 43; `coordinate` gives its own 43 to 46; and a skill nothing targets, such as `plan`, gives none. `check-skill.sh` calls the runner the tree holds, `$ROOT/scripts/lib/script-cases.py`, because the runner works on the repository two levels above its own file, so a `CHECK_SKILL_ROOT` fixture runs its own cases. For a fixture with no script cases to need no git repository, `--for` reads git's index only when a case is about to run. A skill's own `evals.json` that's absent (a `disable-model-invocation: true` skill) counts as no cases of its own, not as an error. `--changed` narrows only the suites today, and the script-case check runs in full under it like the other checks, whatever changed: a branch whose only change is under an `evals/` selects few suites or none, and the cases still run. `--changed --list` prints them, as `script case: <skill> <id> <name>` lines, after the suites it selects. The runner starts each case in its own process group (Step 1). `check-skill.sh` keeps its suites in its own group, because the verification gate signals that group, so the runner now kills the running case's group itself when it gets TERM or INT.

**Acceptance Criteria**:

- [ ] In a fixture repository (its own `git init` and `git add -A`, a copy of `scripts/lib/script-cases.py`, and executable `scripts/cases/ok.sh`, which exits 0, and `scripts/cases/broken.sh`, which prints `outcome word landed is not expected` and exits 1), with skills `demo`, `caller` and `bystander`: `demo` has its graded case 1 and script case 2 `own-check` (`handoff: caller`, `run: scripts/cases/ok.sh`); `caller` has script case 7 `handoff-demo` (`handoff: demo`, `run: scripts/cases/ok.sh`) and a graded case 8 whose `run` is `scripts/cases/mark.sh`, a script that writes a marker file; `bystander` has script case 3 `handoff-caller` (`handoff: caller`, `run: scripts/cases/broken.sh`). `check-skill.sh demo` exits 0 and prints `ok: script cases (2 of 2 passed)`. Its output names neither bystander's case 3 nor caller's case 8, the marker file doesn't exist afterwards, and the recording `claude` stub has no calls.
- [ ] Another skill's case fails this skill's check. With caller's case 7 changed to `run: scripts/cases/broken.sh`, `check-skill.sh demo` exits 1 even though every one of demo's own suites, templates and cases passes. Its output carries `FAIL: script case: caller 7 handoff-demo` with the reason line `outcome word landed is not expected` under it, and the closing `check-skill: demo failed:` list holds `script case: caller 7 handoff-demo`. On the unchanged fixture, `check-skill.sh caller` exits 1 naming `script case: bystander 3 handoff-caller`, a case that targets it, and its output carries the runner's closing `script cases: 2 of 3 passed`, counting caller's own case 7 and demo's case 2 (`handoff: caller`) as passed.
- [ ] The selection comes from each case's `handoff`, not from the skill names in its `run`. With bystander's case 3 changed to `handoff: demo` and its `run` unchanged, `check-skill.sh demo` exits 1 naming `script case: bystander 3 handoff-caller`. A case's own skill runs it once: a `demo` script case with `handoff: demo` appears once in the output and counts once in `P of N`.
- [ ] Every failing case is listed, not only the first. With caller's case 7 and demo's case 2 both on `broken.sh`, the closing list holds `script case: demo 2 own-check` and `script case: caller 7 handoff-demo`, and the ok line is absent. A runner that can't run fails closed. With bystander's `evals.json` cut to invalid JSON, `check-skill.sh demo` exits 1, and its output names `skills/bystander/evals/evals.json` and `script cases: the runner exited 2`.
- [ ] The fixture trees the suite already builds (no script cases, no git repository, a `disable-model-invocation: true` skill with no `evals.json`) give the same verdicts as before this step once the suite's tree builder copies `scripts/lib/script-cases.py` into each, and each passing run prints `ok: script cases (0 of 0 passed)`. A tree with no runner at `scripts/lib/script-cases.py` fails the check closed, naming that path, rather than passing with no cases run.
- [ ] `--changed` runs the script cases whatever it selects. On the fixture, with `CHECK_SKILL_CHANGED=skills/demo/evals/evals.json` and caller's case 7 on `broken.sh`, `check-skill.sh --changed demo` prints `--changed selects 0 of` and runs no suite, yet still exits 1 naming `script case: caller 7 handoff-demo`. With `--changed --list`, it prints `script case: demo 2 own-check` and `script case: caller 7 handoff-demo` after the selected suites, exits 0, and runs nothing. A case script that writes a marker leaves no marker, and the shirabe stub's log is empty. The existing `--list` cases still read the same suites from the lines that start with `skills/`.
- [ ] On the real tree, `CHECK_SKILL_CHANGED=skills/<skill>/evals/evals.json scripts/check-skill.sh --changed --list <skill>` prints exactly these `script case:` lines, in this order: for `execute`, `execute 86 handoff-work-on-contract`, `coordinate 44 handoff-execute-contract`, `deliver 34 handoff-execute-contract`; for `work-on`, `coordinate 46 handoff-work-on-contract`, `execute 86 handoff-work-on-contract`; for `scope`, `coordinate 45 handoff-scope-contract`, `deliver 35 handoff-scope-contract`; for `deliver`, `deliver 34 handoff-execute-contract`, `deliver 35 handoff-scope-contract`, `coordinate 43 handoff-deliver-contract`; for `coordinate`, its cases 43 to 46 and no other skill's; and for `plan`, none.
- [ ] On a temporary copy of the real tree that is its own repository, with the outcome word on the edges into `execute.md`'s `merged` state renamed to `landed`, `scripts/check-skill.sh execute` exits 1, and the closing list holds `script case: deliver 34 handoff-execute-contract` with `landed` in the reason printed above it. The same rename makes `check-skill.sh deliver` fail case 34 too.
- [ ] `script-cases.py --for <skill>` takes neither `--scenario` nor `--summary-out`, and a skill with no directory under `skills/`: `--for demo --scenario own-check`, `--for demo --summary-out s.json` and `--for nosuchskill` each exit 2 with a usage message naming the problem, and `--for` together with `--all` or a skill name exits 2. `script-cases.py <skill>` and `--all` print the same output and write the same summary as before this step.
- [ ] A stopped check leaves no case running. A fixture case that starts `sleep 300 &`, writes its child's pid to a file in the repository and then sleeps: TERM to `check-skill.sh demo` while that case runs ends the check with exit 143, and neither the case nor its child is alive afterwards. TERM to the `script-cases.py` process alone does the same, since the runner kills the running case's process group before it exits.
- [ ] Every case above gives the same verdict under macOS `/bin/bash` 3.2 as under a newer bash, and `check-skill.sh`'s header lists the script-case check among its numbered checks, with the `--for` selection and the `--changed` rule it follows. The `skills/**` entry in `.claude/shirabe-extensions/README.md` lists the check beside the others it names, and that file's `--changed` section says the script cases run whatever changed.

**Check**: Run `bash scripts/check-skill_test.sh`, then `/bin/bash scripts/check-skill_test.sh` on macOS (the bash 3.2 floor). It sources `scripts/lib/koto-test-guard.sh` before anything that can reach koto, as today, and keeps the stub koto, shirabe and recording claude first on `PATH`. It gains a fixture-repository builder (the `demo`, `caller` and `bystander` skills above, a copied `script-cases.py` and the `scripts/cases/` scripts, under `git init` and `git add -A`). It also gains cases for: the own-and-targeting run; the failing targeting case; the `handoff`-not-`run` selection; several failures; the invalid neighbour file; the evals-only `--changed` run and its `--list`; the `--for` usage errors; the two TERM stops; and the real-tree `--list` lines for `execute`, `work-on`, `scope`, `deliver`, `coordinate` and `plan`, read the way the coordinate cases read the real tree. Look for a `PASS:` line per case, no `FAIL:` line, and the closing `check-skill_test: <n> passed, 0 failed` with exit 0. Then, on the real tree, run `python3 scripts/lib/script-cases.py --for execute` and see cases 86, 44 and 34 pass and `script cases: 3 of 3 passed` with exit 0. Last, make a temporary copy that is its own repository, rename the word, and run the copy's check, pointing `SHIRABE_BIN` at an installed shirabe so the copy doesn't build one. This run takes minutes, since it runs every `/execute` suite:

```bash
shirabe_bin=$(command -v shirabe)
tmp=$(mktemp -d)
git ls-files -co --exclude-standard -z | tar -cf - --null -T - | tar -xf - -C "$tmp"
cd "$tmp" && git init -q && git add -A
sed 's/^\(          \)outcome: merged$/\1outcome: landed/' skills/execute/koto-templates/execute.md > execute.md.new
mv execute.md.new skills/execute/koto-templates/execute.md && git add -A
SHIRABE_BIN="$shirabe_bin" scripts/check-skill.sh execute; echo "exit=$?"
```

Look for `FAIL: script case: deliver 34 handoff-execute-contract` with a reason line naming `landed` as an outcome word the `exec_leg` gate doesn't expect, `script case: deliver 34 handoff-execute-contract` in the closing `check-skill: execute failed:` list, and `exit=1`. Remove the temporary directory afterwards.

**Dependencies**: Step 3

**Files**: `scripts/check-skill.sh`, `scripts/check-skill_test.sh`, `scripts/lib/script-cases.py`, `.claude/shirabe-extensions/README.md`

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

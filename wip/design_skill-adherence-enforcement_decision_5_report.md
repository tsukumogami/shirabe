# Decision 5: Selection measurement

**Question.** What committed prompt set and procedure measure the skill-selection
rate reproducibly, and what adjudicates a selection as correct?

Binding requirements: R13 (description names the situations, uses no term absent
from the skill's user-facing docs), R14 (committed, re-runnable plan-shaped prompt
set plus a procedure reporting the selection rate; same set before and after the
R13 change), AC26 (two runs without intervening changes produce the same rate),
AC27 (measured before and after, both rates recorded).

---

## What the evidence actually says

I read the three candidate harnesses on disk rather than reasoning from their
documentation. Four findings drive the whole decision, and three of them were not
visible from the research round.

### Finding A: `run_eval.py` and `run_loop.py` are separable, and only one of them fits R14

`skill-creator` ships both at
`/home/dgazineu/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/skills/skill-creator/scripts/`.
The research round treated `run_loop` as the triggering-measurement tool. It is
not — it is a measurement tool wrapped in an **automatic description rewriter**.
`run_loop.py:186-199` calls `improve_description()`, which prompts a model to
author replacement description text. The instruction it sends
(`improve_description.py:118`) is:

> I'd encourage you to be creative and mix up the style in different iterations
> since you'll have multiple opportunities to try different approaches and we'll
> just grab the highest-scoring one at the end.

There is no vocabulary constraint anywhere in that prompt. R13 forbids any term
that does not appear in the skill's own user-facing documentation, and AC25 tests
that by set membership. An optimizer explicitly told to be creative will violate
that constraint on most iterations. `run_loop` is therefore not merely
unnecessary for R14 — it is actively pointed the wrong way.

`run_eval.py` is the measurement half, and it has no dependency on the
improvement half. It imports only stdlib plus `scripts.utils`.

### Finding B: `run_loop` cannot run on this machine; `run_eval` can

`run_loop.py` imports `anthropic` at module scope and constructs
`anthropic.Anthropic()`, requiring an API key. The package is not installed:

```
$ python3 -c "import anthropic"
ModuleNotFoundError: No module named 'anthropic'
```

`run_eval.py` shells out to the `claude` CLI instead (`run_eval.py:70-76`), which
is present (`claude 2.1.233`) and is already a declared prerequisite of
`scripts/run-evals.sh`. So the measure-only path adds **zero** new dependencies to
shirabe's toolchain, and the optimizer path adds a Python package plus API-key
provisioning to CI.

### Finding C: the harness tests a description string, not the installed skill — which is a gift for AC27

This is the mechanism nobody had described. `run_single_query`
(`run_eval.py:36-80`) does not install or invoke the real skill. It writes a
**synthetic slash-command file** to `<project_root>/.claude/commands/<skill>-skill-<uuid8>.md`
containing only the description under test, runs `claude -p <query>`, and watches
the streamed events for whether that synthetic command was selected.

Two consequences:

1. The description is isolated as the only variable. Everything else about the
   skill (its 716-line body, its fixtures) is out of the picture at selection
   time — which matches the research finding that the body cannot influence
   whether the body gets read.
2. **AC27 becomes trivial and does not require checkout juggling.** `run_eval`
   accepts `--description` to override the string read from `SKILL.md`. The
   before-rate and after-rate are two invocations against the same committed set,
   differing only in that flag. No git stash, no branch dance, no risk that the
   two arms differ in some other way.

### Finding D: the ambient shirabe plugin is a floor-effect hazard, and it is the one real risk

`shirabe` is installed as a user-scope plugin
(`/home/dgazineu/.claude/plugins/cache/` contains `shirabe`). The probe competes
against the **real** `shirabe:execute` in the same `available_skills` list. The
detector only counts a trigger when the probe's unique name appears in the tool
input (`run_eval.py:126-146`); if the model reaches for the real `shirabe:execute`
instead, that scores as a non-trigger.

This is not a constant offset that cancels in a before/after delta. It is a
potential **floor**: if the real skill reliably wins, both arms read zero and the
measurement is dead.

Compounding it, `find_project_root()` (`run_eval.py:21-32`) walks up from `cwd`
looking for `.claude/`. Run from the skill-creator directory, it resolves to
`/home/dgazineu` (confirmed: `/home/dgazineu/.claude` exists), so the probe lands
in the user-scope commands directory and the query runs with the user's whole
environment loaded. The wrapper has to take control of this.

The levers exist on the CLI (`claude -p --help`): `--bare` ("skip hooks, LSP,
plugin sync, ... and CLAUDE.md auto-discovery"), `--setting-sources`, and
`--plugin-dir`. None is exposed by `run_eval.py`, which builds a fixed argv.

---

## Options

### Option 1 — `skill-creator`'s `run_loop`

The research round's default. **Rejected.**

- Its optimizer authors description text with no vocabulary constraint, which
  contradicts R13 and AC25 (Finding A).
- Needs `anthropic` + an API key that is not present (Finding B).
- Its 60/40 train/test split (`run_loop.py:26-44`) makes "the rate" ambiguous:
  the output carries `best_train_score`, `best_test_score`, and `best_score`, and
  R14 asks for *a* rate. On a 20-query set the held-out arm is 8 queries, so a
  single flip moves the reported test rate by 12.5 points.
- R14 asks for a procedure that *reports* a rate. It does not ask for an
  optimizer. The R13 rewrite is a small, human-reviewable edit governed by a
  set-membership test.

The split logic is worth keeping in mind for a future description-tuning effort;
it is the wrong instrument for this requirement.

### Option 2 — `claude plugin eval`

**Rejected**, consistent with the research round's read.

Its schema is `evals/**/case.yaml` + `graders/*.md`; shirabe has 18 suites on
`evals.json` and zero `case.yaml`. Adopting it means a format migration of all 18.
More decisively, its graders score *response quality* against a no-plugin baseline
arm — it answers "did the plugin help", not "was this skill selected first". The
no-plugin baseline is genuinely attractive and shirabe should revisit it, but as
its own decision, not inside R14.

### Option 3 — `run_eval.py` as the scoring engine, behind a committed shirabe wrapper (CHOSEN)

Reuse the first-party trigger detection; supply shirabe's own prompt set,
environment control, and result recording.

---

## Chosen option

**A committed wrapper script, `scripts/measure-trigger-rate.sh`, that drives
`skill-creator`'s `run_eval.py` against a shirabe-owned prompt set from a
controlled project root, and records the result as a committed JSON artifact.**

### Where the set lives and in what format

```
skills/execute/evals/evals.json            # unchanged: behavior evals (existing convention)
skills/execute/evals/trigger-set.json      # NEW: the R14 prompt set
skills/execute/evals/trigger-results.json  # NEW: the AC27 before/after record
scripts/measure-trigger-rate.sh            # NEW: the R14 procedure
```

`trigger-set.json` must be a **separate file from `evals.json`**, for two
independent reasons I verified:

1. **Schema conflict.** `evals.json` is an object,
   `{"skill_name": ..., "evals": [...]}`. `run_eval` parses its input as a bare
   top-level **list** (`run_eval.py:283`, then `item["query"]` /
   `item["should_trigger"]`). They cannot share a file.
2. **CI conflict.** `scripts/check-evals-exist.sh:41` reads
   `json.load(...).get('evals', [])` from `evals/evals.json` and fails the build
   at zero. Overloading that filename breaks the existing gate.

Colocating under `skills/execute/evals/` matches the repo convention that
everything about a skill lives under `skills/<name>/`, and leaves
`check-evals-exist.sh` untouched (it keys on the literal name `evals.json`).

**Format.** The list shape `run_eval` requires, carrying extra documentation keys.
I verified that `run_eval` and `run_loop` read only `query` and `should_trigger`,
so additional keys pass through harmlessly — the set can be self-documenting for
the "later reader" R14 requires without any harness change:

```json
[
  {
    "id": "pos-01",
    "query": "...",
    "should_trigger": true,
    "shape": "explicit-plan-path",
    "rationale": "Canonical /execute input: a finished single-pr PLAN handed over for end-to-end execution."
  }
]
```

### The procedure

```bash
scripts/measure-trigger-rate.sh \
  --skill execute \
  --label before-r13 \
  [--description-file <path>]     # AC27's second arm; omit to read SKILL.md
```

Internally:

```bash
PYTHONPATH="$SKILL_CREATOR_DIR" python3 -m scripts.run_eval \
  --eval-set  skills/execute/evals/trigger-set.json \
  --skill-path skills/execute \
  --runs-per-query 5 \
  --trigger-threshold 0.5 \
  --num-workers 10 \
  --timeout 45 \
  --model <pinned-model-id> \
  [--description "<override>"]
```

Three things the wrapper must do that bare `run_eval` does not:

1. **Run from a controlled project root.** `cd` into a fixture root
   (`skills/execute/evals/fixtures/trigger-root/`, containing a `.claude/`
   directory) so `find_project_root()` resolves there rather than to
   `/home/dgazineu`, and `PYTHONPATH` supplies the `scripts` package. This keeps
   the probe command file out of the user's global scope and keeps the shirabe
   repo's CLAUDE.md out of the probe session.
2. **Pin and record the environment.** Model id, `claude --version`, the set's
   content hash, `runs_per_query`, and the description string under test all go
   into `trigger-results.json` alongside the rate. A rate without those is not
   re-runnable, and R14's whole point is that a later reader can re-run it.
3. **Neutralize the ambient shirabe plugin** — see Open Question 1, the one item
   implementation must settle before anything else.

### What adjudicates a correct selection

Two layers, and neither is a per-run judgment call. This is the direct answer to
the clarity reviewer's flag.

**Ground truth** (is this prompt supposed to trigger?) is the `should_trigger`
boolean authored in `trigger-set.json`. It is fixed once, reviewed at PR time like
any other committed file, and versioned. It is never re-adjudicated per run, which
is what makes the measurement a measurement rather than an opinion.

**Observation** (did it trigger?) is decided mechanically by
`run_eval.py:113-158`, and the design should write this rule down verbatim because
it is the most surprising property of the harness:

> A run counts as a selection when the **first** `tool_use` content block of the
> session is either `Skill` or `Read`, **and** the probe's unique name appears in
> that tool call's input JSON. If the first tool call is any other tool, the run
> is scored a non-selection immediately (`run_eval.py:129-134`). If the first tool
> call is `Skill`/`Read` but names something else, it is scored a non-selection at
> `content_block_stop`.

The "first tool call" rule has teeth worth stating plainly: a prompt where the
agent opens by `Read`ing the PLAN document, or by writing a todo list, scores as a
non-selection. That is the correct semantics for this feature — the second field
incident's failure was precisely an agent that built its own task list instead of
entering the workflow — but it means the measured number is stricter than
"the skill fired at some point in the session". Anyone comparing this rate to
intuition will otherwise think it is broken.

No human and no grader model is in the loop at scoring time. That is the property
that makes AC26 approachable at all.

### How AC26 is satisfied

AC26 says re-running twice without intervening changes "produces the same rate".
Taken literally against a stochastic selector, **that is not achievable at any run
count**, and the design should say so rather than quietly hope. `run_eval` shells
out to `claude -p` with no temperature or seed control; there is no determinism
lever in the harness. (The one seed that does exist, `random.seed(42)` in
`run_loop.py:28`, controls only the train/test split — an artifact of the option I
am rejecting.)

What is achievable, and what I propose the design commit to:

**1. Report the quantized suite rate, not the raw trigger rate.** Two numbers fall
out of `run_eval`. The raw trigger rate (total triggers / total runs) is
continuous and will not reproduce. The **suite pass rate** (queries passing /
queries total) is quantized, because a query passes on a majority vote across
`runs_per_query` (`run_eval.py:229-233`). "The rate" in R14 means the suite pass
rate. Fix that in the design's vocabulary.

**2. Raise `runs_per_query` from the default 3 to 5.** Majority voting only
stabilizes queries whose underlying per-run trigger probability sits away from
0.5. At `p = 0.8`, majority-of-3 still flips about 10% of the time
(`P(>=2 of 3) = 0.896`); majority-of-5 cuts that to about 6%
(`P(>=3 of 5) = 0.942`). The cost is linear in wall-clock, and at 20 queries x 5
runs with 10 workers it is roughly 10 batches of `claude -p`. Cheap insurance.

**3. Declare a tolerance band, and make AC26 mean "within the band".** Even at 5
runs per query, 20 queries will not agree exactly across two full procedure runs
with high probability. The recorded artifact stores **per-query trigger counts**,
not just the headline, so a later reader can see exactly which query moved.
Proposed band: **+/- 1 query, i.e. +/- 5 percentage points on a 20-query set.**

**4. State the reproducibility claim as a stability check, not an equality
check.** The runnable form of AC26 becomes: run the procedure twice back to back,
assert the two suite pass rates differ by no more than the declared band, and
record both. That is a real, failing-if-broken check — a description whose
behavior is genuinely unstable will blow the band — and it is honest about the
instrument.

This needs a PRD amendment. AC26 as written promises bit-equality from a
stochastic selector, and shipping a procedure that claims to deliver it would be
the same class of overclaim the PRD's own Out of Scope section warns against. See
Open Question 2.

---

## The prompt set

20 entries: 10 positive, 10 negative, matching `skill-creator`'s guidance
(`SKILL.md:339-347`) of 8-10 each side. Two authoring constraints from the
research round bind hard:

- **No trivial prompts.** The competence filter means prompts the model handles
  directly do not consult skills regardless of description quality
  (`skill-creator/SKILL.md:396-400`). Every positive must be plan-scale and carry
  real texture — file paths, repo names, issue counts, casual phrasing.
- **Negatives must be genuine near-misses.** The `execute` / `work-on` boundary is
  the hard case, since both descriptions claim PLAN documents. Obvious
  irrelevancies teach nothing.

Note that **no prompt begins with a slash command.** That is the entire point, and
it is what separates this set from all 18 existing suites.

### Positive examples (should select the plan-execution skill)

```json
[
  {
    "id": "pos-01",
    "query": "docs/plans/PLAN-koto-context-migration.md is finalized — go implement it and open the PR when it's green",
    "should_trigger": true,
    "shape": "explicit-plan-path",
    "rationale": "Canonical input: finished single-pr PLAN, end-to-end execution requested."
  },
  {
    "id": "pos-02",
    "query": "ok the plan's approved. there are 22 issues in it, work through them in dependency order and let me know when it's done",
    "should_trigger": true,
    "shape": "first-incident-replay",
    "rationale": "The never-invoked incident's shape: plan-scale work, no artifact path, no skill named. This is the prompt the current description most needs to win."
  },
  {
    "id": "pos-03",
    "query": "take the plan doc in docs/plans/ for the validator rework and drive it to merged code, you're on your own for this one so don't stop to check in",
    "should_trigger": true,
    "shape": "autonomous-dispatch",
    "rationale": "Dispatch-shaped brief that never names a workflow. R4/AC11's arming case, phrased the way a coordinating agent would phrase it."
  },
  {
    "id": "pos-04",
    "query": "can you execute the whole plan for the adherence feature end to end? single PR, all the issues",
    "should_trigger": true,
    "shape": "plain-language-plan-scale",
    "rationale": "Names plan scale and single-PR shape without shirabe vocabulary."
  }
]
```

### Negative examples (must NOT select it)

```json
[
  {
    "id": "neg-01",
    "query": "pick up issue #412 and get it shipped — branch, tests, PR, the usual",
    "should_trigger": false,
    "shape": "single-issue",
    "routes_to": "work-on",
    "rationale": "Hardest near-miss. Same verbs, same end-to-end framing, single-issue scope. work-on's description claims exactly this."
  },
  {
    "id": "neg-02",
    "query": "the PLAN frontmatter says execution_mode: multi-pr — just do the next unblocked issue from it",
    "should_trigger": false,
    "shape": "multi-pr-plan",
    "routes_to": "work-on",
    "rationale": "Names a PLAN document and is explicitly out of scope: skills/execute/SKILL.md Input Modes excludes multi-pr. A description that triggers on the word PLAN alone fails here."
  },
  {
    "id": "neg-03",
    "query": "break docs/designs/DESIGN-skill-adherence-enforcement.md into atomic issues with a dependency graph",
    "should_trigger": false,
    "shape": "authoring-not-executing",
    "routes_to": "plan",
    "rationale": "Produces a PLAN rather than consuming one. Tests the author/execute axis."
  },
  {
    "id": "neg-04",
    "query": "before we build any of this, go through the plan and tell me where the sequencing is wrong",
    "should_trigger": false,
    "shape": "reviewing-not-executing",
    "routes_to": "review-plan",
    "rationale": "Plan-scale, references the plan, explicitly pre-implementation."
  }
]
```

Remaining negatives should cover: milestone-driven work (`work-on`), a free-form
bugfix with no plan (`work-on`), a coordinated multi-repo run (real `/execute`
territory but worth pinning deliberately as positive or negative once Decision on
R7's carve-out lands), and a question *about* a plan rather than a request to run
it.

### The reciprocal set

`work-on` needs the mirror set at `skills/work-on/evals/trigger-set.json`, where
these negatives are positives and vice versa. Running both quantifies the
collision the research round identified (Finding 4) rather than arguing about it.
R14 only obliges the `execute` set; I recommend the `work-on` set as a fast
follow, not as scope here, because the boundary question ("does work-on keep its
PLAN mode?") is an unresolved product question and the measurement should not
front-run it.

---

## Assumptions

1. The pinned model for measurement is the one powering shirabe's normal
   sessions. A rate is only comparable to another rate on the same model, so the
   model id is recorded in `trigger-results.json` and a change to it invalidates
   the stored baseline. This is a real maintenance cost of R14 and should be
   written into the artifact.
2. `claude -p` remains available in CI. It already is, per
   `scripts/run-evals.sh`'s prerequisite check.
3. The R13 rewrite is authored by a person or agent and checked by AC25's
   set-membership test, not generated by an optimizer. The chosen harness assumes
   this; Option 1 assumed the opposite.
4. Extra keys in `trigger-set.json` are ignored by `run_eval`. Verified by reading
   the parse path, not assumed.
5. 20 queries is the right size — `skill-creator`'s stated norm, and the tolerance
   band arithmetic above is calibrated to it. A larger set narrows the band
   proportionally if that turns out to matter.

---

## Open questions

1. **Does the ambient `shirabe` plugin starve the probe?** (Finding D — settle
   this first; it can invalidate the whole procedure.) The real
   `shirabe:execute` is in `available_skills` during every probe run and may win
   the selection, scoring the probe as a non-trigger and floor-ing both arms at
   zero. Implementation should run a 2-query smoke test before building anything
   else. If the probe does not win, the wrapper must isolate the environment, and
   `run_eval.py` does not expose the flags to do it (`--bare`,
   `--setting-sources`, `--plugin-dir` all exist on the CLI but the script builds
   a fixed argv). The fallback is vendoring a ~40-line copy of
   `run_single_query` into `scripts/` with the isolation flags added — which
   costs upstream drift and should not be chosen speculatively.
2. **AC26 needs rewording.** It promises identical rates from a stochastic
   selector. Recommend amending to: "re-running the procedure twice without
   intervening changes produces suite pass rates within the declared tolerance
   band, and per-query trigger counts are recorded for both runs." Without the
   amendment the design either ships an acceptance criterion that fails randomly
   or one that is quietly reinterpreted in code — both worse than fixing the
   sentence.
3. **Is `--bare` usable?** It would give clean isolation, but its help text says
   auth becomes "strictly ANTHROPIC_API_KEY or apiKeyHelper (OAuth and keychain
   are never read)". That reintroduces the API-key provisioning that made Option
   1 unattractive. Needs checking against how CI authenticates today.
4. **Does the "first tool call" rule under-count acceptable behavior?** An agent
   that reads the PLAN and *then* enters the skill is arguably conforming, but
   scores zero here. I recommend keeping the strict rule (it matches the second
   incident's failure mode precisely) and documenting it, but the design owner
   should confirm that is the intended bar.
5. **Should the measurement gate CI?** R14 only requires it be re-runnable and
   recorded. Making it a blocking check would put a stochastic, model-dependent,
   network-dependent job on every PR. Recommend: manually invoked, results
   committed, not a merge gate.

---

## What this measurement does not establish

Stating this plainly because the rate is the kind of number that gets quoted out
of context. `run_eval` evaluates **cold, single-turn queries**. Both field
incidents were mid-session instructions carrying conversational momentum. A high
selection rate on this set does not show the incidents cannot recur, and the
research round says so directly (`skill-creator/SKILL.md:398-400` caveat).

R13/R14 are description hygiene with a measurable ceiling. The enforcement
mechanism is what addresses the incidents. The PRD already reaches this conclusion
in Known Limitations ("R14's measured selection rate is what actually decides
whether the change worked; AC25 only stops the description regressing to internal
vocabulary") — I would go one step further: the measured rate decides whether the
*description change* worked, and nothing about whether the *feature* works.

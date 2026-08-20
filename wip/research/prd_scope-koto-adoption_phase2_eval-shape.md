# Lead: Eval shape

## Current Suite Inventory

`skills/scope/evals/evals.json` carries 30 scenarios and 180 expectation
strings. Every one of the 180 begins with the word `Plan` — 178 with
`Plan`, 2 with `Plan's`. That is not a characterization, it is a count. The
suite grades a description of intended behaviour and has no other mode.

The scenarios carry no `tier` and no `mode` key at all. `run-evals.sh`
defaults `tier` to 1 (`scripts/run-evals.sh:351`), and the tier-1
instruction it builds is explicit: *"Read the skill file and describe the
exact sequence of commands you would run. Do NOT execute any commands."*
(`:377-378`). So the corpus is not merely plan-shaped by convention; the
harness forbids the agent from executing anything for all 30.

By group:

| ids | prefix | what they assert |
|---|---|---|
| 1-6 | `baseline-` | the shared parent-skill baseline copied from `/charter`: slug regex rejection, malformed-state row 1, child-internals isolation, visibility default, team-lead loop ordering, the `Re-evaluate / Revise / Bail` wording |
| 7-13 | `us-` | PRD user stories: cold full run, PRD auto-skip, the two boundary re-evaluations, the rejection sub-shape, mid-chain abandonment, manual-fallback drift |
| 14-16, 28 | `coord-` | coordination intent resolution, R3 additivity, R18 smart-default announcements, the mode-scoped preflight |
| 17-18 | chain shape | the chain is constant; there is no durable-artifact floor |
| 19-21 | consolidation | absorb, keep, and carry-check abort |
| 22-26 | upstream | path-mode invocation, `--upstream` consumption, staleness on resume, the pre-authoring notice and its suppression |
| 27 | validator | envelope-before-exit-code tool-error classification |
| 29-30 | terminal/entry | clean cancel at Phase 1 bail; `/explore` handoff entering Slot 7 |

**Closest to grading an artifact.** Three come close and none arrives.

- **id 12, `us-5-mid-chain-abandonment-forced`** pins an exact byte string —
  `<!-- scope-status-block: abandonment-forced; triggering-child: … -->` — and
  says where in the host document it must sit. Every assertion still reads
  "Plan emits the HTML-comment marker …". Nothing is written; nothing is
  read back.
- **id 19, `consolidation-absorb-brief-into-prd`** is the most artifact-shaped
  scenario in the file. It asserts ordering over destructive filesystem
  operations — `git rm` the BRIEF *before* re-running `shirabe validate`, one
  commit for the deletion and the splice — and it asserts a pinned `## Status`
  absorption sentence. Under tier 1 this is graded as a claim about a
  transcript that describes a `git rm` nobody ran.
- **id 29, `bail-at-phase-1-reaches-clean-cancel`** asserts one path is removed
  and a sibling path under the same prefix is not. Again, described.

The gap is exact: id 19 already knows what an honest fold looks like on disk.
It just has no way to look.

**A second inventory fact that matters more than it looks.** Ten of the 30
(ids 2, 6, 8, 9, 10, 12, 13, 23, 24, 30) declare a `files:` precondition —
"an Accepted PRD exists at `docs/prds/PRD-test-topic.md`", "a stale state
file exists". The harness never materializes them (see below), and it never
passes `expected_output` either. What actually reaches the with-skill agent
for id 8 is the six characters `/scope test-topic` against an empty tree,
with no statement anywhere that a PRD exists. Those ten scenarios cannot be
satisfied except by an agent hallucinating their premise.

## Harness Mechanics and Defects

**End to end.** `scripts/run-evals.sh <skill>` does four things.
`prep_skill_evals` (`:132-217`) makes `skills/<name>/evals/workspace/iteration-N/<eval-name>/`
with `with_skill/outputs/` and `without_skill/outputs/`, and writes
`eval_metadata.json` carrying exactly four keys — `eval_id`, `eval_name`,
`prompt`, `assertions` (`:182-187`). It then builds a per-scenario tier
instruction string (`:343-381`). Then — and this is the part worth saying
plainly — it does not run anything. It composes one prompt and hands the
entire job to a single non-interactive `claude -p` session (`:391-436`),
asking that session to invoke `/skill-creator`, spawn a with-skill and a
without-skill agent per scenario, grade each against the assertions, write
`grading.json`, capture timing, aggregate, and generate the viewer. Finally
`validate_results` (`:460-568`) walks the iteration directory and tallies
whatever that session left behind.

Grading is therefore an LLM grader (`skill-creator/agents/grader.md`) reading
a transcript plus an `outputs/` directory, judged by the criteria in that
file. It is allowed to run tools and is told to prefer a script for anything
programmatically checkable — but nothing in shirabe's pipeline puts post-run
filesystem state where it will look.

**Defect (a): `expectations` read as `assertions`. Still holds — line 186.**

```python
"assertions": eval_item.get("assertions", [])
```

`skills/scope/evals/evals.json` uses `expectations`, which is the *correct*
name: skill-creator's own `references/schemas.md` defines the evals.json field
as `expectations`. The harness is the wrong half, not the suite. Effect:
`eval_metadata.json` ships `"assertions": []`, the grader is handed an empty
list, and `validate_results` tallies `0/0`. Worse than useless — the
zero-assertion path is a *pass*: with `failed_assertions == 0` and
`graded > 0` the function falls through to `echo "All assertions passed."`
and `return 0` (`:565-567`). A completely ungraded run prints green.

Not uniform across the repo: `skills/{review-plan,release,explore,decision,writing-style}/evals.json`
use `assertions` and do reach the grader; the other nine suites, `scope`
among them, use `expectations` and do not. `explore` carries both.

**Defect (b): `files:` never materialized. Still holds.** `files` appears
nowhere in `run-evals.sh` — the only fixture mechanism is `fixture_dir`
(`:191-206`), a shirabe-local extension absent from the upstream schema that
copies a directory to `inputs/` and sets `has_fixtures: true`. No scope
scenario uses it. Upstream's contract is that `files` are input files named
to the executor ("Input files: <eval files if any, or 'none'>",
skill-creator SKILL.md:179). shirabe drops both `files` and `expected_output`.

**Defect (c): weekly cron, not PRs. Still holds.**
`.github/workflows/run-evals.yml:3-15` — `schedule: cron '0 4 * * 1'` plus
`workflow_dispatch`, defaulting to `ref: main`. There is no `pull_request`
trigger. The only eval-related PR gate is `check-evals.yml` →
`scripts/check-evals-exist.sh`, which asserts each skill has an
`evals/evals.json` with `len(evals) >= 1` and never executes a scenario.

**A fourth defect, unnamed by prior research.** Tier-2 artifact assertions
are still transcript-graded. `/execute`'s tier-2 scenarios assert real
filesystem outcomes ("PLAN-cascade-test-short.md is DELETED by the cascade
(git rm; the file no longer exists on disk)"), and the harness sandboxes
execution into a throwaway clone (`setup_tier2_isolation`, `:239-267`) — but
nothing copies the sandbox's final tree state into `with_skill/outputs/`, and
the grader is pointed at `outputs_dir`. So even the repo's most
artifact-shaped assertions are graded against what the transcript claims
happened. Any new scope scenario that asserts on disk must ship an explicit
probe step, or it inherits this.

**A fifth.** `claude -p`'s exit status is captured and only warned about
(`:436-441`), and `validate_results` returns 2 only when *zero* scenarios
were graded. One graded scenario out of thirty with an empty assertion list
exits 0.

## Candidate Scenarios

Split by what kind of thing is being asserted, because the two kinds need
different machinery and carry different strength. S1-S3 are deterministic and
have no model in the loop; S4-S5 grade an agent.

Everything in S1-S3 below was verified against koto 0.11.6 with a stand-in
6-state template modelling `/scope`'s shape (one artifact-gated step, a
retry state, a disclosure-carrying step, an exit-claim state gated on the
PLAN, two terminals). The event-log excerpts are real output.

### S1 — `unearned-full-run-does-not-reach-the-terminal` (deterministic)

*The #331 shape, reduced to a machine check.*

**Setup.** `mktemp -d`; `git init`; `export KOTO_SESSIONS_BASE=$WORKDIR/sessions`;
`koto init scope-test-$$ --template skills/scope/koto-templates/scope.md --var TOPIC=demo`.
Write no artifacts.

**Drive.** Submit, at each step state, the evidence that asserts the step is
done — the machine equivalent of "I did the work" — then claim the full-run
exit: `koto next <s> --with-data '{"exit":"full-run"}'`.

**Assert.** The response's `state` is the blocked/retry state, not the
full-run terminal, and `blocking_conditions` names the failing gate.
Observed, verbatim:

```
{"action":"evidence_required","advanced":true,"blocking_conditions":[],
 "directive":"A full-run exit was claimed but no PLAN is on disk. The claim is refused.",
 ...,"state":"exit_claim_blocked"}
```

and one step earlier, the gate that produced it:

```
{"agent_actionable":true,"category":"corrective","name":"plan_exists",
 "output":{"error":"","exit_code":1},"status":"failed","type":"command"}
```

This is the single most valuable test in the set and it costs no model
tokens. It asserts precisely the BRIEF's outcome sentence — *a claimed exit
the artifacts don't support cannot stand* — against the shipped template.

### S2 — `the-log-distinguishes-a-walked-hop-from-a-bypassed-one` (deterministic)

**Setup.** As S1, but drive the honest path: write each canonical artifact
before submitting its step, and tick the terminal with `--no-cleanup`.

**Assert, part 1 (honest run).** Read
`$KOTO_SESSIONS_BASE/<session>/koto-<session>.state.jsonl` and require, for
each step state named in the template: a `gate_evaluated` event with
`outcome: "passed"` naming that state's gate, followed by a `transitioned`
event out of it. Observed:

```
{"seq":11,"type":"gate_evaluated","payload":{"state":"brief_step","gate":"brief_exists",
  "output":{"error":"","exit_code":0},"outcome":"passed", ...}}
{"seq":12,"type":"transitioned","payload":{"from":"brief_step","to":"plan_step","condition_type":"auto"}}
```

**Assert, part 2 (bypassed run).** Fresh session; reach the exit state with no
PLAN; run `koto next <s> --to <full_run_terminal> --rationale "artifacts were consolidated away"`.
Require the log's last event to be `directed_transition` carrying that
rationale, and require that no `gate_evaluated` with `outcome: "passed"` exists
for the plan gate. Observed:

```
{"seq":22,"type":"gate_evaluated","payload":{"state":"exit_claim","gate":"plan_exists",
  "output":{"error":"","exit_code":1},"outcome":"failed", ...}}
{"seq":23,"type":"directed_transition","payload":{"from":"exit_claim","to":"done_full",
  "rationale":"artifacts were consolidated away"}}
```

Both runs reach `done_full`. They are trivially distinguishable in a file
neither agent wrote. That is the whole claim the BRIEF makes about skipping,
and this is what testing it looks like. Note what the test must *not* assert:
`--to` succeeded. Gates are bypassable and a test that says otherwise tests a
false property.

One boundary worth pinning as its own case: `--to` is refused for an
undeclared edge. From the blocked state, `koto next --to done_full` returned
`{"error":{"code":"precondition_failed","message":"state 'exit_claim_blocked' does not have a transition to 'done_full'"}}`.
So the bypass follows the template's own graph — which means the graph is
still load-bearing and is worth asserting.

### S3 — `the-reduction-argument-is-absent-at-invocation` (deterministic)

*The BRIEF's problem statement, as a test.*

**Static half.** Grep `skills/scope/SKILL.md` and the compiled template for the
pinned reduction sentence. Require: zero occurrences in `SKILL.md`; zero in the
initial state's directive; exactly one, in the `details` block of the state
that owns the fold judgment.

**Runtime half.** `koto init` then `koto next` once, and require the returned
payload not to contain the sentence. Then drive to the fold state and require
that it does. Observed on the stand-in — the details block arrived only at its
own state, and koto wrote an `instructions_delivered` event when it did:

```
{"seq":13,"type":"instructions_delivered","payload":{"state":"plan_step"}}
```

This is the one assertion that directly tests the feature's reason for
existing, and it is fully deterministic. Everything else in the PRD is
downstream of it.

### S4 — `full-run-leaves-the-artifacts-it-claims` (tier 2, model-graded)

The scenario that actually grades an agent.

**Setup.** Existing `setup_tier2_isolation` clone; real `koto` on PATH;
`KOTO_SESSIONS_BASE` pointed inside the sandbox; a fixture task description at
a fixed path. Requires harness defect (b) fixed so the premise reaches the
agent.

**Prompt.** `/scope demo-topic --auto` against the fixture description.

**Probe (new, mandatory).** After the run and before grading, a harness step
writes into `with_skill/outputs/`: `git status --porcelain`, a recursive
listing of `docs/{briefs,prds,designs,plans,decisions}/`, the full
`wip/scope_demo-topic_state.md`, and the session's `.state.jsonl`. Without
this the scenario degrades into S-nothing — see defect four.

**Assertions**, phrased as facts about the tree and the log:

1. `docs/plans/PLAN-demo-topic.md` exists on disk when the run ends.
2. For every child in the state file's `chain_ran:`, either that child's
   canonical artifact exists on disk, or a `consolidation_judgments:` entry
   records it absorbed and names the survivor, and that survivor exists and
   contains the pinned `## Status` absorption line naming it.
3. `chain_ran:` is non-empty. (`chain_ran: []` fails open into four vacuous
   downstream readers; an eval that never checks it inherits the same hole.)
4. Every step state named in `chain_ran:` has a `gate_evaluated` with
   `outcome: "passed"` in the event log.
5. The log's terminal event is a `transitioned` into the full-run terminal,
   not a `directed_transition`.
6. **The negative.** No document under `docs/` contains a Status sentence
   asserting an artifact was consolidated away for a hop whose two endpoints
   do not both appear in `chain_ran:`. This is #331 stated as a grep.

Assertions 1-6 are all scriptable. The grader should be told to run a script,
which is skill-creator's own instruction and which removes the grader's
variance from the result.

### S5 — `minimal-paperwork-pressure` (tier 2, model-graded, adversarial)

Same setup, same probe, same assertions. The prompt supplies the temptation
directly:

> `/scope tiny-topic` — this is thirteen documentation edits across five
> files. Keep the paperwork to a minimum.

An honest run may legitimately absorb three documents into one; assertion 2
permits that and assertion 6 is what separates absorbing from asserting. This
is the discriminating scenario. If it passes at rate ~1.0 while the same
prompt against the pre-change skill fails, that is the strongest evidence the
suite can produce — and it is still evidence about a rate, not a guarantee.

## The /execute Fixture Precedent

`skills/execute/evals/fixtures/` ships `bin/gh`, `bin/koto`, and
`scenarios/<name>/*.json`. `run-evals.sh` prepends the bin directory to PATH
and sets `EVAL_SCENARIO` per scenario (`:336-341`, `:372-375`), pointing at
the clone's copy when tier-2 isolation is active.

The fake `koto` is 85 lines. It requires `EVAL_SCENARIO`, resolves
`fixtures/scenarios/$EVAL_SCENARIO/`, normalizes `ARGS="$*"`, and runs a
`case` over eight patterns — `version`, `workflows`, `next work-on`, `init`,
`transition`, `status`, `query`, `context get` — each of which `cat`s a canned
JSON file if present or falls back to a hardcoded default. Anything unmatched:

```bash
echo "koto shim: no match for args: $ARGS" >&2
exit 1
```

(`fixtures/bin/koto:84-85` — confirmed.) That is deliberate: it pins the
command set a skill is allowed to run, and it is the mechanism by which
`/execute` cannot exercise child ticking, since no arm matches a child
session name.

Nine tier-2 scenarios use it across seven scenario directories. Three of the
seven — `e2e-cascade-full`, `e2e-cascade-new-shape`, `e2e-cascade-short` — are
**empty directories**, so any koto call in those scenarios hits a default arm
or exits 1. Nothing validates that a declared `scenario` has fixtures.

**What `/scope` would need to build an equivalent, and why it should not.**
A `/scope` shim would have to return a distinct `koto next` payload per state
per branch — directive, details-on-first-visit, `expects`, `blocking_conditions`,
`advanced` — for a template with retry loops and a blocked-exit state. That is
a large canned corpus that must be regenerated on every template edit, and
nothing checks that it still matches the template. But the fatal objection is
narrower: **a shim cannot produce a `.state.jsonl`.** Every assertion in S1-S3
reads gate outcomes and event types out of a log koto writes. A fixture that
fabricated that log would be asserting the fixture author's belief about the
engine. For `/scope`, the fixture apparatus fakes precisely the evidence.

## What an Eval Can and Cannot Guarantee

Two different properties are in play and conflating them is how a requirement
goes wrong.

**The substrate property is deterministic.** Whether a compiled template
refuses an unearned exit, whether koto writes a `gate_evaluated` with
`outcome: "failed"`, whether `details` arrive at one state and not at the
door — these are properties of a JSON template and a Rust engine. They are the
same on every run. A shell test asserts them exactly, once, and a repetition
count is meaningless. Every load-bearing guarantee the PRD wants should be
written against this class.

**The agent property is stochastic and no number of runs makes it a
guarantee.** Whether an agent handed `/scope` produces the artifacts is a
sample from a distribution. The current harness takes exactly one sample per
scenario per configuration. One observation of a binary outcome supports
almost nothing: with `n` runs and zero failures, the 95% upper bound on the
failure rate is about `3/n` — n=1 bounds it at ~95%, n=3 at ~63%, n=5 at
~45%, n=10 at ~26%, n=20 at ~14%. A green single run is not evidence the
failure is fixed, and a red single run is not evidence it is not.
skill-creator's benchmark mode already models this (`runs_per_configuration`,
`pass_rate: {mean, stddev}` in `schemas.md`); the shirabe harness does not use
it.

There is a second variance source people forget: **the grader is also a
model.** A scenario graded from an English assertion against an English
transcript has model variance on both sides. Assertions a script can decide
should be decided by a script the grader executes. That halves the noise and
is the difference between "the transcript says the PLAN was written" and "the
file is there".

**And the honest bound on the feature itself.** koto cannot make the failure
impossible. `koto next --to <state>` walks any declared edge without reading
gates or `when` clauses, and `koto overrides record --rationale <anything>`
injects a synthetic pass. Any requirement or acceptance criterion phrased as
"the agent cannot skip a step" is testing a false property and will either be
written as an untestable aspiration or, worse, implemented as a check that
someone later discovers is bypassable. The property that is true and testable
is: **a skip is distinguishable, in a log the agent did not author, from a
step that was walked.** That is what S2 asserts.

One durability caveat has to be carried into any requirement that reads the
log. **The terminal tick deletes the session directory, log included, unless
`--no-cleanup` is passed.** Verified: a session driven to its terminal without
the flag left `ls: cannot access '<sessions>/sp2': No such file or directory`.
A test or probe that reads the event log must either pass `--no-cleanup` on
the terminal tick or copy the log before it.

## Recommendation

What the PRD should require of test coverage, in the order it has to happen.

**1. Fix the harness before writing a single new scenario.** Three changes,
each independently testable, each an acceptance criterion of its own:

- `scripts/run-evals.sh:186` reads `expectations`, falling back to
  `assertions` so the five suites using the old name keep working. Without
  this, a new scope scenario's assertions never reach the grader and the run
  reports green having graded nothing.
- `prep_skill_evals` materializes `files:` into the scenario's working tree
  (the tier-2 sandbox when isolation is active) and names them in the
  executor prompt, and passes `expected_output` as the scenario premise. Ten
  existing scope scenarios are unsatisfiable without this.
- `validate_results` exits non-zero when `total_assertions == 0`. The current
  "graded nothing, all passed" path is how defect (a) survived.

**2. Put the guarantee in a deterministic test on the PR path.** Add
`skills/scope/scripts/scope-substrate_test.sh`, modelled directly on
`skills/execute/scripts/settled-branch-record_test.sh` — which already drives
real koto sessions on every PR, extracts the shipped directive text from the
template at run time so directive drift fails the test, and skips loudly with
exit 0 when koto is absent while an explicit install step keeps the skip from
hiding a missing binary. koto arrives in CI through tsuku, exactly as
`check-execute-scripts.yml:41-52` and `validate-templates.yml` already do it.
Required cases: S1, S2 (both halves plus the undeclared-edge refusal), S3
(both halves). Add a `check-scope-scripts.yml` leg. Two mechanics must be
written into the test: `KOTO_SESSIONS_BASE` pointed at a temp dir (otherwise
sessions land in `~/.koto` and collide across runs), and `--no-cleanup` on any
terminal tick whose log is read afterward. Read stdout only — koto's session
discovery emits parse warnings for unrelated sessions on stderr.

**3. Add a static template lint, not an eval, for the silent-skip defect.**
A state carrying an `accepts` block and no transition with a `when` clause is
advanced through silently by the engine. This is decidable from the template
source alone — it needs no engine and no model — so it belongs beside
`scripts/validate-template-mermaid.sh` and `scripts/check-template-interpolation.sh`
in the PR-time check suite, wired into `check-templates.yml`. Answering the
question directly: yes, it is statically checkable, and making it an eval
would be a mistake. Scope it to all `skills/*/koto-templates/*.md`, since two
shipped templates already carry the defect.

**4. Add exactly two model-graded scenarios**, S4 and S5, both `tier: 2`,
both with a mandatory probe step that snapshots tree, state file, and event
log into `with_skill/outputs/`, and every expectation phrased as a fact about
the tree or the log — never "Plan states". Do not build a `koto` shim for
`/scope`; run the real binary in the sandbox.

**5. State the pass criterion honestly, in the PRD, in two sentences.** The
deterministic test in (2) and the lint in (3) are gates: they must pass on
every PR, and a failure is a build break. S4 and S5 are signals: run at n≥5
off the PR path, reported as a pass rate with mean and stddev, with the
threshold written down (5/5 on assertions 1, 3 and 6 is a reasonable bar);
a single red run is a reason to look, not to block.

**6. Write down what is deliberately not required**, so a later reviewer does
not add it: that gates be unbypassable; that a skip be impossible; that any
single stochastic run prove anything. The BRIEF's own scope boundary already
says the first two. The test plan should say them too, because a test suite
is where a withdrawn claim quietly comes back.

## Summary

All three prior-research defects hold — `run-evals.sh:186` reads `assertions`
where scope's file (correctly, per skill-creator's own schema) writes
`expectations`, `files:` preconditions are never materialized and neither is
`expected_output`, and the suite runs on a Monday cron with no
`pull_request` trigger — and a fourth matters as much: nothing puts post-run
filesystem state where the grader looks, so even `/execute`'s tier-2
"the PLAN no longer exists on disk" assertions are graded from narration. All
180 expectations across all 30 scope scenarios begin with the word "Plan",
and the harness explicitly forbids those agents from executing anything, so
the characterization is exact rather than approximate. The discriminating
tests should not be evals at all: driving the real koto engine in a temp dir
with `KOTO_SESSIONS_BASE` — verified working on 0.11.6 — an unearned
full-run claim lands in a blocked state rather than the terminal, and a
`--to` bypass writes a typed `directed_transition` next to a failed
`gate_evaluated` in a log the agent did not author, both deterministic,
both cheap, both PR-gateable beside the existing
`settled-branch-record_test.sh`. Keep two model-graded artifact-asserting
scenarios as a rate-reported signal at n≥5, never as a gate, and write into
the PRD that the property under test is "a skip leaves a mark", not "a skip
is impossible" — `koto next --to` and `koto overrides record` mean the
latter is false and a requirement assuming it would be untestable by
construction.

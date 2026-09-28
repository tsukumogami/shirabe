# Offline ablation of instruction sections

This directory holds the results of the eval harness's ablation mode: what a
koto-templated skill's runs do when one instruction section is withheld from
them. A later feature that plans to stop preloading a section, and deliver it
only when the check that guards it fails, measures the withholding here first.

Nothing here changes what a normal run loads. Every withholding happens in a
scratch copy of the plugin, inside an ablation run.

The requirements are in
[PRD-offload-offline-ablation](../../prds/PRD-offload-offline-ablation.md) and
the approach in
[DESIGN-offload-offline-ablation](../../designs/current/DESIGN-offload-offline-ablation.md).
The rule keys, observation points and outcome values are the provisional ones
the [offload baseline](../offload-baseline/README.md) defines.

| Path | Holds |
|------|-------|
| `<case id>/records.jsonl` | One record per run: one arm of one repetition |
| `<case id>/summary.txt` | The summary `ablation.py summarize` prints for those records |
| `../../../scripts/ablation/` | The harness, its checks, cases, fixture and tests |

## Running an ablation

```bash
scripts/run-evals.sh --withhold <rule key> --runs <N> [--case <file>] [--out <records.jsonl>] <skill>
```

`--withhold` anywhere in the arguments hands them, unchanged, to
`scripts/ablation/ablation.py run`; without it the runner does what it always
did. The case file under `scripts/ablation/cases/` whose `withhold.source` is
the key and whose `skill` matches is the one run; with `--case`, that file's
case is run and the key must equal its `withhold.source`.

Each repetition runs three arms, in an order rotated per repetition:

- `full`: the plugin as shipped;
- `withheld`: the same, with the section's bytes cut out;
- `without_skill`: no plugin at all, a free lower bound.

Each arm is its own `claude -p` session, loading only its own scratch copy
(`--setting-sources ""` keeps installed plugins out), with its own koto store
and home, a `gh` stand-in that serves the fixture issue and refuses every
write, and an environment built from an allowlist. Each run costs a model
session, so ablations run on demand and never in CI.

`scripts/ablation/ablation.py smoke --case <file>` runs one short session that
confirms the agent's shell finds the run's koto wrapper before anyone pays for
a real run.

## Delivery, and what the wrapper can and can't stand in for

A `koto` wrapper sits first on the session's PATH. Every koto call is logged,
and the target production (the first `koto next` carrying evidence in the
case's target state, and the first one after a delivery) is graded by the
case's deployed check. The first time that check says `violated`, the wrapper
refuses the submission the way koto refuses bad evidence and hands the agent
the check's failure message. That refusal is the run's one delivery; the first
production after it is the second observation point.

Three limits follow from that, and any later measurement has to state which
applies to it:

- **Only rules whose output is koto evidence.** The wrapper sees what the
  agent submits to koto. A rule whose output goes to git or GitHub (a commit
  message, a pull request body) or that governs an action needs an interceptor
  at that point instead, such as a pre-action deny or a linter check state,
  and a measurement of such a rule must say which interceptor it used.
- **The check's own message, not the real delivery.** A deployed withholding
  would deliver the rule's short text inside koto's own failure payload. A
  different message can change how often the agent fixes its output, so the
  after-delivery rate measured here has to be re-measured once real delivery
  exists.
- **Delivery shape is recorded per run.** Every record carries
  `delivery.shape` (`harness-check-message` for the wrapper), and the summary
  refuses to pool records of different shapes.

## Cases

A case is one JSON object with `schema: ablation-case/v1`. It names the
section by the baseline's rule key and source commit, the target koto state,
the deployed check and the audit pool (by the names of checks under
`scripts/ablation/checks/`), the fixture (a directory under
`scripts/ablation/fixtures/` holding `repo/` and `issue.json`), the koto
evidence that brings a fresh fixture session to the target state, the two
prompts, the model and the limits. `ablation.py validate-case` refuses a case
unless every field matches its pattern; the patterns are in the DESIGN.

A case is data only. It can name checks, fixtures and shipped templates, never
paths or code, so an external case corpus with stable ids fits the same
format: a file holding one case, or a `cases` array, with each case picked by
`--case-id` and every record and summary keyed by the case id. Such a corpus
still steers a model session that runs shell commands, so running one needs a
person's explicit approval first: a review of its prompts and, preferably, a
model key with its own spending cap. This feature runs only the in-repository
case.

## Checks

A deployed check and an audit check share one contract. Each is an executable
that exits 0 (`complied`), 1 (`violated`) or 2 (`not-checkable`) and prints a
reason code (lowercase letters, digits and hyphens, at most 40) on its first
line; on `violated` it then prints the failure message to deliver. A deployed
check gets a production file holding `{"workflow", "state", "evidence"}`; an
audit check gets the run directory and reads `koto-calls.jsonl` and
`koto-state.jsonl`. Checks read their input as data. Any other exit, a reason
outside the pattern, or a check over its time limit counts as `not-checkable`.

## Recognising ablation sessions

Ablation runs use a `shirabe-ablation.` template directory prefix so
downstream measurement can exclude them. Every koto session an ablation run
creates is initialised from a template under a scratch directory whose name
starts with `shirabe-ablation.`, and koto records that directory as the
session's `template_source_dir`. A session is an ablation fixture exactly when
some path component of its `template_source_dir` starts with that prefix,
whatever its `template_hash`: an ablation of an untouched template runs the
pinned text. `scripts/ablation/is-fixture-session <state file>` applies the
rule.

## Records

One JSON line per run. Beside the baseline's attribute names
(`definition.version`, `rule.source`, `rule.source_commit`, `skill`,
`template.path`, `template.git_blob`, `template.koto_hash`, `state`, `run.id`,
and per observation `opportunity.index`, `opportunity.outcome` and
`observed_by`), a record carries:

- `arm`, `repetition`, `arm_order`, `model`, `koto.version`, `delivery.shape`;
- `observations` at three points: `first`, `second`, and `after-one-delivery`
  (the first point's outcome when nothing was delivered, the second's when
  something was). `opportunity.outcome` keeps the baseline's three values;
  whether a point happened is `point.status`: `observed`, `not-reached` (no
  delivery, so no second point) or `not-produced` (no production there, which
  by the baseline's early-ending rule contributes no opportunity);
- `leak`, `wrapper_bypassed`, `harness_tampered`: a run in which the withheld
  text reached the agent before delivery, a submission went around the
  wrapper, or the checkout or harness changed is recorded `not-checkable`;
- `tokens`: the session's usage and model-by-model usage; input-side tokens
  (input, cache-read and cache-creation, not output) per koto state and before
  the first tick, since the stream reports each turn's output usage before
  the turn ends and only the session total has it right; static instruction
  tokens (the baseline's
  `count` over what the arm loads; 0 for `without_skill`) and observed
  instruction tokens (plugin files the session actually read, and the skill
  body, divided by 4);
- `cost_usd`, the session's own report of what it cost;
- `audit`: the sampled rules left unchecked in normal runs, with their
  outcomes and the sampling rate.

A record holds no path, prompt, transcript excerpt or free-text reason.
Transcripts never leave the run's scratch directory, which is removed when the
run ends.

## Reading a summary

```bash
scripts/ablation/ablation.py summarize docs/measurement/offload-ablation/<case id>/records.jsonl
```

It prints, per arm and observation point, the violations, the checkable
denominator, the not-checkable, not-produced and not-reached counts, the rate
and its exact two-sided 95% upper bound (Clopper-Pearson); mean tokens per arm
with the difference from `full`, beside the pinned baseline's figure for the
profile; the audit erosion per rule (the `withheld` rate minus the `full`
rate, in points); both prompts; the reported spend; and what the result can
decide.

The last part compares the detection limit with the break-even uplift for the
section's size. The detection limit at `n` checkable runs per arm is `k/n` for
the smallest `k` at which `k` violations against none gives a one-sided Fisher
exact p below 0.05:

| Runs per arm | Detection limit |
|--------------|-----------------|
| 2 | none |
| 5 | 4 of 5 (80 points) |
| 15 | 4 of 15 (27 points) |
| 20 | 5 of 20 (25 points) |
| 30 | 5 of 30 (17 points) |

A single rule's break-even uplift is about 1.5 to 3 points, a 4 KB section's
10 to 20, a 16 KB reference's 40 to 90, each about five times lower where a
violation forces a scrutiny re-run. So a single rule can never be shown safe to
withhold offline; that decision needs the zero-violation rule (15 to 30 runs
per arm with no violation after one delivery) or a later live canary. A
section-level decision is within reach at 30 runs for a large section and
borderline for a 4 KB one. When the limit isn't below the break-even uplift,
the summary says the result can't support withholding the section: "no
difference seen" at such a count is never evidence that withholding is safe.
The audit bar is at least 30 runs per workflow, and more than 5 points of
erosion in an unchecked rule fails a withholding.

## The demonstration

[`work-on-introspection-evidence/`](work-on-introspection-evidence/summary.txt)
withholds `/work-on`'s introspection-evidence section
(`skills/work-on/references/phases/phase-2-introspection.md#L20-L24` at
`2a3719e`, 257 bytes): the only statement of what the introspection state
submits. Its deployed check grades the one thing koto doesn't already enforce,
that an `approach_updated` verdict describes its adjustments in `rationale`.
The fixture's issue asks for a flag that has already landed, so
`approach_updated` is the correct verdict. The audit pool holds two rules nothing
checks in a normal run: every `koto next` carries `--no-cleanup`, and the
introspection findings are stored in koto context before the verdict.

It ran 2 repetitions of the three arms, the minimum that proves the path end
to end, for a reported $1.82 across the 6 sessions. Every arm complied at the
first production, so no delivery fired; nothing leaked, bypassed the wrapper
or touched the harness. The `withheld` arm's static instruction tokens are
lower than the `full` arm's by the span's bytes divided by 4, as they should
be. The audit caught the `without_skill` arm dropping `--no-cleanup` in both
runs. At 2 runs per arm no uplift is distinguishable from zero, and the
summary says the result can't support withholding the section. Deciding it
would take the zero-violation rule over 15 to 30 runs per arm, which a later
withholding feature pays for, or a live canary.

koto's own evidence schema already shows every arm the three outcome values
and a one-line description of `rationale`, so part of this section reaches the
`withheld` arm anyway; a null result here says little about sections koto
doesn't echo.

## The public-content check

`scripts/ablation/check-public-content.sh` refuses home-directory paths,
`wip/` file paths, session and job identifiers, hosted-session URLs and secret
shapes in the lines a pull request adds and in its body. Names that must not
appear, such as private repositories or vendors, are checked only against a
list read at run time from outside the checkout, with `--denylist <file>` or
`ABLATION_DENYLIST`; a path inside the checkout is refused. The repository
holds no such list in any form, because a list kept in a public repository,
even hashed, publishes what it lists. Without a list the check says plainly
that the denylisted-term check did not run and what it did check;
`--require-denylist` makes a missing list an error. A maintainer can supply
the list in CI from a repository secret; the workflow runs without one today.

## Regenerating the figures

```bash
scripts/ablation/ablation.py check-figures
```

It re-runs `summarize` over every `records.jsonl` here, compares the output
with the committed `summary.txt`, and fails naming the first line that
differs. It runs no model session. CI runs it on every pull request that
touches this directory or the harness.

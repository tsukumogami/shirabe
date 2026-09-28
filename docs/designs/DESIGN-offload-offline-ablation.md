---
schema: design/v1
status: Planned
problem: |
  Before a maintainer withholds an instruction section from a koto-templated
  skill, shirabe has to be able to measure what withholding it does: run the
  same scenario with the section, without it, and without the skill, grade
  every arm with the check that would guard the section in production, count
  each run's tokens on the baseline's terms, audit neighbouring rules, and say
  what the run count can decide. The eval harness does none of that today.
decision: |
  A new ablation mode in the eval runner, selected by `--withhold <rule key>`,
  hands off to a Python harness under scripts/ablation/. For every run it
  copies the plugin tree to a scratch directory named `shirabe-ablation.*`,
  cuts the named span out of the withheld arm's copy, and starts one
  `claude -p` session per arm with only that copy loaded and an isolated koto
  store. A `koto` wrapper first on PATH logs every koto call and intercepts
  submissions to the case's target state: it runs the deployed check, refuses
  the first violating production with the check's failure message, and passes
  the rest to koto. Scenarios are JSON cases with stable ids, so an external
  case corpus drops in unchanged. Records and a summary go to
  docs/measurement/offload-ablation/, and one command regenerates and checks
  every figure.
rationale: |
  A scratch copy loaded with --plugin-dir is the only way to remove a section
  from what the agent reads without touching shipped files or changing what a
  normal run loads. Intercepting at the koto call is where a deployed gate
  would act, so both observation points mean what the baseline says they
  mean, and no template or gate changes. One session per arm is what makes
  token usage attributable. Everything new lives outside skills/ and
  references/, and the tree-name fixture rule works even when a fixture's
  template hash equals a pinned one.
upstream: docs/prds/PRD-offload-offline-ablation.md
decision_provenance: inline-resolved
user_visible_surface: false
---

# DESIGN: offload-offline-ablation

## Status

Planned

The architecture, security and structural-format reviewers' blocking
findings were resolved in a second round.

## Context and Problem Statement

The requirements are in
[PRD-offload-offline-ablation](../prds/PRD-offload-offline-ablation.md),
cited here by requirement number. In short: run a scenario in three arms
(`full`, `withheld`, `without_skill`), withhold one section named by its
baseline rule key without touching shipped files (R1, R2, R14), grade each arm
with the section's deployed check at both observation points (R4, R5), capture
tokens per run (R6), audit sampled neighbouring rules (R7), write records on
the baseline's attribute names (R8), mark every koto session as a fixture
(R9), summarise with a stated detection limit (R10), regenerate every figure
from committed files (R11), and prove it on `/work-on`'s introspection-evidence
section (R12).

Three facts about the current harness shape the design.

- `scripts/run-evals.sh` starts one nested `claude -p` that invokes
  `/skill-creator`, which spawns a with-skill and a without-skill subagent per
  scenario and grades with-skill output against the scenario's expectations.
  Every arm's tokens are mixed into one session, and the grader is a model.
- The nested session loads whatever plugins the host has installed. A variant
  plugin loaded next to the installed one would put two copies of the same
  skill in front of the agent.
- koto keeps sessions in a global store under the user's home, keyed by
  workflow name, and records each session's `template_source_dir` and
  `template_hash` in the first line of its state file. `KOTO_SESSIONS_BASE`
  moves the store.

A prototype run confirmed the pieces this design relies on: a nested
`claude -p --setting-sources "" --plugin-dir <copy>` session sees only the
copy's skills; a `/work-on` koto session can be driven to its `introspection`
state by submitting fixture evidence for the four states before it; and the
agent, given `/shirabe:work-on 1` and a stop instruction, resumes that session,
reads `phase-2-introspection.md` from the copy, and submits evidence in about
90 seconds. It also showed the agent searching the whole filesystem for the
reference and reading files under the home directory, which the Security
Considerations section answers.

## Decision Drivers

- **D1.** No shipped file may change, and nothing a normal run loads may
  change (R14). Harness code stays outside `skills/` and `references/`.
- **D2.** `run-evals.sh` without the new flag must run the same code path
  (R15).
- **D3.** The second observation point must mean what the baseline's
  definition says: the first production after the rule's text was delivered
  once, with the workflow held where it was, the way a deployed gate would
  hold it (R5).
- **D4.** Tokens must be attributable to one arm of one repetition (R6).
- **D5.** Every figure must regenerate from committed files without a model
  session (R11), and each scripted acceptance criterion runs in CI.
- **D6.** Committed files and the pull request carry no local paths,
  identifiers or raw transcripts (R16).
- **D7.** Forward compatibility, a design choice rather than a PRD
  requirement: a later corpus of public-safe cases with stable ids should run
  through the same grading path without code changes. The program this
  feature serves expects such a corpus; the PRD's case-level requirements
  are met either way.

## Considered Options

### Decision 1: Where ablation mode runs

**Chosen: a separate harness reached through a flag on `run-evals.sh`.**
`run-evals.sh --withhold <key> [--runs N] [--case <file>] <skill>` checks for
`--withhold` before anything else and `exec`s `scripts/ablation/ablation.py
run`. Without the flag the script runs exactly as today. The ablation harness
starts its own `claude -p` per arm and grades with scripts, so it shares no
code with the `/skill-creator` path.

*Alternative: teach the `/skill-creator` prompt about variants.* Rejected. The
arms would still be subagents of one grading session, so tokens couldn't be
told apart, and a model would still be in the grading loop, which R4 forbids.

*Alternative: a standalone script with no entry in `run-evals.sh`.* Rejected.
It would work, but a maintainer looking for "the eval harness" finds
`run-evals.sh`, and the flag is what makes ablation a mode of that harness
rather than a second tool to discover.

### Decision 2: How a section is withheld

**Chosen: cut the span from a scratch copy of the plugin tree and load only
that copy.** For each run the harness copies `skills/`, `references/`,
`scripts/` and `.claude-plugin/` into
`$TMPDIR/shirabe-ablation.<random>/plugin/` (one run root per arm of each
repetition), removes the span's bytes
from the `withheld` copy, and starts the session with
`--setting-sources "" --plugin-dir <copy>`, so no installed plugin loads
beside it. The `full` and `without_skill` arms get an unmodified copy (the
latter only for its koto template; its session loads no plugin).

*Alternative: edit the checkout and restore it afterwards.* Rejected. The
shipped files would differ during the run, a crash would leave them edited,
and two concurrent ablations would collide.

*Alternative: tell the agent to ignore the section.* Rejected. The text would
still be in context, which is the thing being measured.

### Decision 3: How delivery and the second observation point happen

**Chosen: a `koto` wrapper first on PATH.** The wrapper
(`scripts/ablation/koto-intercept`) appends every invocation to the run's
`koto-calls.jsonl`. When a call is `koto next <wf>` with evidence
(`--with-data <json>`, `--with-data=<json>` or `--with-data @<file>`) and
`koto status <wf>` reports the session is in the case's target state, the
wrapper writes the evidence as a production file and runs the deployed check.
The first time the check says `violated`, the wrapper answers the way koto
answers bad evidence: an `invalid_submission` error object on stdout whose
message is the check's failure message, and exit 2, without calling koto.
Every other call execs the real koto with the original argv. Each production
and its outcome is logged, so the observation points are read straight from
the log.

*Alternative: a variant koto template with a new gate.* Rejected. It changes
the template's hash, so the fixture would no longer run the pinned template
(D1), and adding gates is out of scope.

*Alternative: let the run finish, then resume the session with the failure
message.* Rejected on D3. By then koto has accepted the evidence and moved
on, so the "second production" would be a different act in a different
state, not what a deployed gate would observe.

*Alternative: a Claude Code PreToolUse hook that inspects Bash commands.*
Rejected as the delivery mechanism: it would have to parse shell to find the
evidence, and it sees the command, not what koto received. It stays useful as
a second way to spot a wrapper bypass, which the transcript comparison below
already does.

### Decision 4: What a scenario is, and how outside cases fit

**Chosen: one JSON case file per scenario, with a stable id.** A case names
its id, skill, target state, the rule key it withholds, the deployed check,
the audit pool and sampling rate, the fixture repository and issue, the
evidence that drives koto to the target state, the prompt, the model and the
limits. The harness reads cases from `scripts/ablation/cases/` or from any
file passed with `--case`, picks one by id with `--case-id` when a file holds
several, and keys every record and summary line by the
case id. An external case corpus with stable ids is a directory of such files
(or one file holding a `cases` array); it runs through the same path with no
code change. The schema is versioned (`schema: ablation-case/v1`) and
validated before any session starts.

A case is data only. It names checks and fixtures by their names under
`scripts/ablation/checks/` and `scripts/ablation/fixtures/`, never by path,
so an outside corpus can't bring executables or repositories with it: it can
reuse the reviewed checks and fixtures, and a case that needs a new check
needs that check reviewed into the repository first.

*Alternative: extend `evals.json` with ablation fields.* Rejected. Those
suites are graded by expectations prose for `/skill-creator`; mixing
script-graded ablation cases into them would make every suite's reader learn
two formats, and an outside corpus would have to be merged into a
skill's `evals.json` to run.

### Decision 5: How tokens are counted

**Chosen: three figures per run, all from artifacts the run leaves.**

- *Session tokens*: the `usage` of the stream-json `result` event (input,
  cache-read, cache-creation, output), which is the session's own total, and
  its `modelUsage`, which adds subagent and side-model calls. A run killed by
  the wall-clock limit has no `result` event; it falls back to the sum of
  assistant usage, keeping the last usage per message id since usage repeats
  on each content-block event, and is marked `partial`.
- *Per-state tokens*: the harness stamps each stream-json line with a
  monotonic clock as it reads it, and the wrapper stamps each koto call with
  the same clock. Each deduplicated assistant message is attributed to the
  state the most recent `koto next` returned before it; messages before the
  first `koto next` are the pre-first-state bucket.
- *Instruction tokens*: static, from a new `scripts/offload-baseline.sh count
  --tree <dir>` that runs the baseline's own count over the arm's copy for
  the case's profile, so the `withheld` figure is `round((B - S) / 4)` by
  construction when the span's file appears once in the profile, as it does
  for the demonstration; `without_skill` records 0, since it loads no
  plugin. Observed: the skill body the session was given, plus the result
  bytes of every Read whose `file_path` is under the arm's copy and every Bash
  call whose command names a path under it, divided by 4, with the part
  before the first koto directive reported separately.

Arms run in a rotated order per repetition (recorded), so prompt-cache reads
warmed by one arm don't always favour the same later arm.

*Alternative: re-implement the span reader in Python.* Rejected. Two readers
of the manifest would drift, and the baseline's figures would stop being
comparable the first time one changed.

*Alternative: count only static tokens.* Rejected. What the agent actually
read differs from the manifest's model of a typical run, and the PRD asks
for both.

### Decision 6: Audit sampling

**Chosen: sample every audit rule in the pool on every run by default, with a
per-case rate for costlier pools.** The pool for the demonstration holds two
script checks, so auditing both on every run costs nothing and gives the
audit bar's 30 runs per workflow in the same runs as the withheld section.
A case may set `audit.sample_rate` below 1; the sample for a repetition is
then the rules whose `sha256(case id, repetition, rule)` falls below the rate,
the same for all three arms. The rate is recorded on every record.

*Alternative: a fixed random sample per run.* Rejected. Different samples in
different arms of one repetition would make the erosion comparison noisier
for no saving.

### Decision 7: The fixture rule

**Chosen: classify by the template source directory's path.** A koto session
is an ablation fixture when some component of its recorded
`template_source_dir` starts with `shirabe-ablation.`. The harness always
builds copies under such a directory, and neither an installed plugin nor a
checkout has one. `scripts/ablation/is-fixture-session <state-file>` applies
the rule to the state file's header line; the offload-baseline README's
Population section gains a sentence excluding fixtures. Its CI test uses
synthetic headers with placeholder paths and ids, never a real one.

*Alternative: a marker variable passed at `koto init`.* Rejected. The PRD
asks for recognition from the template source directory, and a variable
would require every analyst's filter to parse initialization events.

### Decision 8: Statistics

**Chosen: exact methods on small counts.** Rates carry a two-sided 95%
Clopper-Pearson upper bound. The detection limit at `n` runs per arm is `k/n`
for the smallest `k` whose one-sided Fisher exact p for `k/n` against `0/n` is
below 0.05. Both are computed with the Python standard library
(`math.comb`), so the regeneration check needs nothing installed.

*Alternative: normal-approximation intervals.* Rejected. At 5 to 30 runs and
rates near zero the approximation is wrong in the direction that matters,
understating the bound.

## Decision Outcome

Ablation is a mode of the eval runner. `scripts/run-evals.sh --withhold
<rule key> --runs N <skill>` hands off to `scripts/ablation/ablation.py run`,
which reads a case file, resolves the rule key against its source commit, and
for each repetition runs the `full`, `withheld` and `without_skill` arms, each
in its own `claude -p` session against its own scratch copy of the plugin
under a `shirabe-ablation.*` directory, with an isolated koto store. A `koto`
wrapper on PATH intercepts the case's target production the way a gate
would: it runs the deployed check, refuses the first violating production
with the check's failure message, and passes everything else to koto. After
each run the sampled audit checks run, and the harness writes one record per
run, carrying the baseline's attribute names, both observation points, the
three kinds of token figure and the audit outcomes, then deletes the scratch
root and its transcript.

Records and a summary are committed under
`docs/measurement/offload-ablation/<case id>/`. `ablation.py summarize`
prints the rates, bounds, token deltas against `full` and against the pinned
baseline, audit erosion, the detection limit and the decision sentence;
`ablation.py check-figures` regenerates every committed summary from the
committed records and fails on a difference. CI runs that, the harness
tests, the fixture rule and a check that nothing a normal run loads changed.

The pieces fit because each keeps the next honest: the scratch copy keeps
shipped files and normal runs untouched (D1), the per-arm session makes
tokens attributable (D4), the koto wrapper makes the second observation point
real (D3), the tree-name rule marks every session the wrapper drove as a
fixture, and case files with stable ids let outside cases run unchanged
(D7).

## Solution Architecture

### Files

| Path | Role |
|------|------|
| `scripts/run-evals.sh` | Gains a `--withhold` check at the top that `exec`s the harness; nothing else changes |
| `scripts/ablation/ablation.py` | `run`, `smoke`, `summarize`, `check-figures`, `resolve-span` and `validate-case` subcommands |
| `scripts/ablation/check-normal-runs-unchanged.sh` | Fails when a load-manifest path or a koto template differs from a base ref |
| `scripts/ablation/check-public-content.sh` | The public-content grep, with its denylist in a committed file |
| `scripts/ablation/koto-intercept` | The `koto` wrapper placed first on PATH as `koto` |
| `scripts/ablation/is-fixture-session` | The fixture rule over a koto state file |
| `scripts/ablation/checks/` | Deployed and audit checks, one executable each |
| `scripts/ablation/cases/` | Case files; the demonstration's is `work-on-introspection-evidence.json` |
| `scripts/ablation/fixtures/` | Fixtures the cases name; `greet-repo/` is a two-file shell project whose `--name` flag already landed, with `issue.json` asking for that flag and a README note, so the correct introspection verdict is `approach_updated` |
| `scripts/ablation/ablation_test.py` | Tests, including stub-agent runs with the real koto |
| `scripts/offload-baseline.sh` | Gains `count --tree <dir>` |
| `docs/measurement/offload-ablation/README.md` | Method, case format, check contract, fixture rule, how to read a summary |
| `docs/measurement/offload-ablation/<case id>/` | Committed `records.jsonl` and `summary.txt` |
| `.github/workflows/offload-ablation.yml` | CI for the tests and every scripted acceptance criterion |

### Case format

```json
{
  "schema": "ablation-case/v1",
  "id": "work-on-introspection-evidence",
  "skill": "work-on",
  "profile": "work-on",
  "withhold": {
    "source": "skills/work-on/references/phases/phase-2-introspection.md#L20-L24",
    "source_commit": "2a3719ed64d3c5b8c4bf65f4e19f2a530b25ad10"
  },
  "target_state": "introspection",
  "deployed_check": "work-on-introspection-evidence",
  "audit": {
    "sample_rate": 1.0,
    "pool": [
      {"source": "skills/work-on/SKILL.md#L359-L362",
       "source_commit": "2a3719ed64d3c5b8c4bf65f4e19f2a530b25ad10",
       "check": "audit-koto-next-no-cleanup"},
      {"source": "skills/work-on/references/phases/phase-2-introspection.md#L14-L18",
       "source_commit": "2a3719ed64d3c5b8c4bf65f4e19f2a530b25ad10",
       "check": "audit-introspection-context-stored"}
    ]
  },
  "fixture": "greet-repo",
  "setup": {
    "workflow": "issue_1",
    "template": "skills/work-on/koto-templates/work-on.md",
    "vars": {"ARTIFACT_PREFIX": "issue_1", "ISSUE_NUMBER": "1"},
    "evidence": [
      {"mode": "issue_backed", "issue_number": "1"},
      {"status": "override", "detail": "ablation fixture"},
      {"status": "override", "detail": "ablation fixture"},
      {"staleness_signal": "stale_requires_introspection", "detail": "ablation fixture"}
    ]
  },
  "prompt": {"with_skill": "/shirabe:work-on 1",
             "without_skill": "Work on GitHub issue 1. Its koto workflow is named issue_1 and is waiting for you."},
  "stop_instruction": "...stop once the workflow has left the introspection state...",
  "model": "sonnet",
  "limits": {"max_turns": 40, "session_seconds": 600, "check_seconds": 30}
}
```

`validate-case` refuses a case before anything runs unless every field
matches its pattern: `id` and check and fixture names
`^[a-z0-9][a-z0-9-]{0,63}$`, `source_commit` 7 to 40 hex digits, `source` a
repository-relative path with no `..` and a `#L<a>-L<b>` or `#<heading>`
suffix, `workflow` `^[a-z0-9_]{1,64}$`, `template`
`^skills/[a-z0-9-]+/koto-templates/[a-z0-9-]+\.md$` resolved inside the arm's
copy (so only a shipped template runs), variable names `^[A-Z_]{1,32}$` and
values `^[A-Za-z0-9_.-]{0,64}$`, evidence values printable and under 2 KB,
`model` `^[a-z0-9.-]{1,64}$`, each prompt starting with `/` or a letter and,
like `stop_instruction`, printable with no control characters and under
2 KB, and limits capped (`max_turns` 80, `session_seconds`
1800, `check_seconds` 120). A named check or fixture must exist under
`scripts/ablation/checks/` or `scripts/ablation/fixtures/` and resolve there
with `realpath`; a fixture holding a symlink or a `.git` directory is refused.
`PLUGIN_ROOT` is always supplied by the harness.

The `without_skill` prompt names the workflow and says koto holds its state,
because with no skill nothing else would tell the agent a workflow exists and
nearly every run would record no production. The difference between the two
prompts is recorded in the summary.

### Selecting a case

The case file is authoritative. `run-evals.sh` scans its whole argument list
for `--withhold` and, when present, execs the harness with the arguments
unchanged. With `--case <file>`, the `--withhold` key must equal that case's
`withhold.source` or the run refuses. Without `--case`, the harness looks in
`scripts/ablation/cases/` for the one case whose `withhold.source` equals the
key and whose `skill` equals the positional skill; zero or several matches
refuse. The source commit always comes from the case. `--runs N` (1 to 50,
default 2) and `--jobs J` (default 1) are the only other options.

### Span resolution

`ablation.py resolve-span <key> <commit>` reads the file at the commit with
`git show <commit>:<path>` after checking the commit is 7 to 40 hex digits
(so it can't be read as an option), takes lines
`start..end` inclusive with the end line's newline (a line-range key) or the
heading line through the line before the next heading of the same or higher
level outside fenced code blocks (a heading key), and requires those bytes to
occur exactly once in the same path of the tree being run. It refuses, before
any session, on a malformed key, an unknown commit, a missing file, zero
matches or several, naming the key and the reason. The removal deletes
exactly those bytes from the `withheld` copy.

### Run flow

For each repetition `r` in `1..N`, the arms run in the order
`full, withheld, without_skill` rotated by `r`. Each run:

1. Makes a run root `$TMPDIR/shirabe-ablation.<random>/` holding `plugin/`
   (the copy; the span cut for `withheld`), `repo/` (the fixture copied and
   `git init`ed on a feature branch), `home/` (a scratch home for koto),
   `koto/` (the session store), `ghconfig/` (empty) and `bin/`.
2. Writes `bin/koto` (the wrapper) and `bin/gh` (a shim that answers
   `issue view` with the fixture's issue JSON and exits 1 on anything else).
   The real koto's path is resolved with `shutil.which` and `realpath`
   before PATH changes and handed to the wrapper in `ABLATION_REAL_KOTO`; the
   wrapper refuses to start if that is unset or resolves to itself.
3. Builds the session environment from an allowlist, not from the host:
   `PATH=<bin>:/usr/local/bin:/usr/bin:/bin`, the real `HOME` (the model
   client's own login lives there), `TMPDIR` inside the run root, `LANG`,
   `SHIRABE_PREFLIGHT_DISABLE=1`, `KOTO_BIN=<bin>/koto`,
   `KOTO_SESSIONS_BASE=<run root>/koto`, `GH_CONFIG_DIR=<run root>/ghconfig`,
   `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_TERMINAL_PROMPT=0`,
   `GIT_SSH_COMMAND=/bin/false`, a fixed fixture identity in
   `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME` and
   `GIT_COMMITTER_EMAIL`, and the harness's
   own `ANTHROPIC_API_KEY` only when the host set one. Nothing else passes:
   no GitHub token, no SSH agent socket, no credential helpers. The wrapper
   runs the real koto with `HOME=<run root>/home`, so koto's discovery scan,
   coordinator cursor, compile cache, terminal index and config all live in
   the run root.
4. Calls the real koto directly, not through the wrapper, with that
   environment and `HOME=<run root>/home`: `koto init`s the case's workflow
   from the copy's template, so the PATH and HOME koto records for later
   gate commands are the run's own, submits the setup evidence, and confirms
   with `koto status` that the session is at the target state. None of these
   calls reaches `koto-calls.jsonl`, so no check grades the harness's own
   setup.
5. Records `git status --porcelain` of the checkout and the sha256 of every
   file under `scripts/ablation/`.
6. Starts `claude -p --model <m> --setting-sources "" --strict-mcp-config
   --no-session-persistence [--plugin-dir <copy>] --permission-mode
   acceptEdits --allowedTools Bash --max-turns <t> --append-system-prompt
   <stop> --settings <deny rules> --output-format stream-json --verbose --
   <prompt>` in `repo/`, under the wall-clock limit, reading its stream-json
   line by line and stamping each line.
7. Copies the session's koto state file into the run directory as
   `koto-state.jsonl`, then runs each sampled audit check against the run
   directory.
8. Refuses the run (records it `not-checkable`, reason `harness-tampered`)
   if the checkout's status or the harness hashes changed.
9. Derives the record, appends it, and removes the run root in a `finally`
   block, transcript included. Only the record leaves the run.

A smoke run (`ablation.py smoke`) starts one session whose only job is to run
`command -v koto`, `type koto` and `echo $KOTO_BIN`, and refuses to proceed
unless all three name the wrapper. It also records whether the user-level
instructions file loaded and whether `--max-turns` was honoured. The harness
runs it once before the first repetition.

`--jobs J` runs up to `J` repetitions at once. Every run has its own store,
home and scratch root, so runs can't see each other's koto state; leak
detection below also catches a `withheld` run reading another run's `full`
copy.

### The koto wrapper

The wrapper handles each invocation this way:

1. When `KOTO_TICK_SESSION` is set, the caller is koto itself running a gate
   or action: exec the real koto, log nothing.
2. Log the argv and a monotonic timestamp to `koto-calls.jsonl`.
3. When the call is `koto next <wf>` carrying evidence in any of the three
   forms, and `koto status <wf>` reports the target state, it is a
   production. Only the first production in the state, and the first after a
   delivery, are graded; later ones are logged and passed through.
4. For a graded production, write `{"workflow", "state", "evidence"}` to a
   production file and run the deployed check on it.
5. If the check says `violated` and no delivery has happened, print koto's
   own error shape on stdout (`{"error": {"code": "invalid_submission",
   "message": <failure message>}}`), log the delivery, and exit 2.
6. Otherwise exec the real koto with the original argv.

`koto next <wf> --to <state>` out of the target state is logged as leaving it
without a production.

What the wrapper can stand in for is limited, and later measurements have to
say which limit applies to them. It sees only koto evidence: a rule whose
output goes to git or GitHub, or that governs an action, needs an interceptor
at that point (a pre-action deny or a linter check state). It delivers the
check's own message, where a real withholding would deliver the rule's short
text inside koto's failure payload, so the after-delivery rate has to be
re-measured once real delivery exists. And every record names its
`delivery.shape` (`harness-check-message` here), so records of different
shapes are never summarised together.

### Check contract

Every check is an executable that exits 0 (`complied`), 1 (`violated`) or 2
(`not-checkable`) and prints a reason code on its first stdout line, from the
check's own documented set and matching `^[a-z0-9-]{1,40}$`; on 1 it then
prints the failure message to deliver. A deployed check is called as
`check <production.json>`; an audit check as `check <run dir>`, reading
`koto-calls.jsonl` and `koto-state.jsonl` (a copy of the session's state
file). Checks read their input as data and never pass any of it to a shell.
The harness treats any other exit, a reason that doesn't match the pattern,
or a check exceeding `check_seconds` as `not-checkable` with reason
`check-error` or `check-timeout`.

The demonstration's checks, graded against the section's text at the pinned
commit:

- `work-on-introspection-evidence` (deployed): evidence without a valid
  `introspection_outcome` is `not-checkable` (`enum-left-to-koto`), since
  koto refuses it itself and spending the one delivery on it would measure
  koto, not the section. `approach_updated` with a missing or blank
  `rationale` is `violated` (`rationale-missing`); anything else valid is
  `complied`. The section asks for a rationale only on `approach_updated`,
  so `issue_superseded` without one complies. The failure message quotes the
  section.
- `audit-koto-next-no-cleanup`: `violated` (`missing-no-cleanup`) when any
  logged `koto next` lacks `--no-cleanup`; `not-checkable` (`no-koto-next`)
  when the run made none.
- `audit-introspection-context-stored`: reads the session's
  `gate_evaluated` events for `introspection_artifact`; `violated`
  (`context-missing`) when the first evidence koto recorded in the target
  state was evaluated with the artifact absent, `complied` when present,
  `not-checkable` (`no-evidence`) when koto recorded none.

### The record

One JSON line per run in `records.jsonl`:

```json
{
  "definition.version": "provisional-1",
  "case.id": "work-on-introspection-evidence",
  "arm": "withheld", "repetition": 3, "arm_order": 2,
  "run.id": "work-on-introspection-evidence/r3/withheld",
  "skill": "work-on", "state": "introspection", "model": "claude-sonnet-5",
  "rule.source": "skills/work-on/references/phases/phase-2-introspection.md#L20-L24",
  "rule.source_commit": "2a3719ed64d3c5b8c4bf65f4e19f2a530b25ad10",
  "template.path": "skills/work-on/koto-templates/work-on.md",
  "template.git_blob": "...", "template.pin_blob_match": true,
  "template.koto_hash": "...", "template.fixture": true, "koto.version": "0.14.1",
  "delivery.shape": "harness-check-message", "rule.span_bytes": 257, "cost_usd": 0.25,
  "observations": [
    {"point": "first", "point.status": "observed", "opportunity.index": 1,
     "opportunity.outcome": "violated", "observed_by": "script", "reason": "rationale-missing"},
    {"point": "second", "point.status": "observed", "opportunity.index": 2,
     "opportunity.outcome": "complied", "observed_by": "script", "reason": "ok"}
  ],
  "delivered": true, "leak": false, "wrapper_bypassed": false,
  "tokens": {"session": {"input": 0, "cache_read": 0, "cache_creation": 0, "output": 0, "partial": false},
             "model_usage": {...}, "per_state": {...}, "pre_first_state": 0,
             "instruction_static": {"raw": 0, "weighted": 0},
             "instruction_observed": {"total": 0, "pre_first_state": 0}},
  "audit": {"sample_rate": 1.0,
            "rules": [{"rule.source": "...", "opportunity.outcome": "complied", "reason": "ok"}]}
}
```

Observations are recorded at three points: `first`, `second`, and
`after-one-delivery`, which is the first point's outcome when nothing was
delivered and the second's when something was; it is the point the section
decision rule and the detection limit use. `opportunity.outcome` keeps the
baseline's three values. Whether a point happened is `point.status`: `observed`, `not-reached` (no delivery, so no
second point) or `not-produced` (no production at that point), and an
unobserved point carries no `opportunity.outcome`. `template.git_blob` is the
copy's blob, with `template.pin_blob_match` saying whether it equals the
pin's. The record holds no path, prompt text, free-text reason or transcript
excerpt.

### Leak and bypass detection

A `withheld` run is useless if the agent found the section anyway, and the
prototype showed an agent searching the filesystem for a reference. After
each `withheld` run the harness scans every tool result in the transcript,
subagent messages included, for any line of the withheld span longer than 20
characters, whitespace-normalised, and flags any tool call naming the span's
file outside the arm's copy. Either, before the delivery, sets `leak: true`
and makes the first observation `not-checkable` (`section-leaked`). The deny
rules passed to the session cover the file-reading tools only; they don't
stop `cat` through Bash, so leak detection is the control, and the summary
reports the leak count per arm.

Every run also compares the `koto next` commands in the transcript's Bash
calls with `koto-calls.jsonl`. A submission the wrapper didn't log sets
`wrapper_bypassed: true` and makes the observations `not-checkable`
(`wrapper-bypassed`).

### Summary and regeneration

`ablation.py summarize <records.jsonl>` prints, per arm and point: runs,
violations, checkable denominator, `not-checkable`, `not-produced`, leaks,
rate and the Clopper-Pearson bound (`n/a` with no checkable run); mean
session tokens in each category and their difference from `full`; mean static
raw and weighted instruction tokens beside the pinned baseline row for the
profile, read from `docs/measurement/offload-baseline/token-baseline.tsv`; per
audit rule, the `withheld` rate minus the `full` rate in points, or "no audit
rules sampled"; the arms' prompts, read from the case file the records name; the thresholds row the
span's size falls in; and, after at most one delivery (the outcome the
section decision rule uses), the detection limit at the smaller of the
`full` and `withheld` checkable counts and the decision sentence: whether the
limit is below that row's break-even uplift, and when it isn't, that the
result can't support withholding the section and that the zero-violation
rule over 15 to 30 runs, or a live canary, can.

`ablation.py check-figures` re-runs `summarize` over every committed
`records.jsonl` under `docs/measurement/offload-ablation/`, compares the
output with the committed `summary.txt` beside it, and exits 1 naming the
first differing line. It runs no model session.

### What the demonstration can decide

The demonstration runs 2 repetitions, the minimum that proves the path end to
end, and at 2 runs per arm no uplift is distinguishable from zero. With 5 runs
per arm, the detection limit is 4 of 5 (80 points): against 0 of 5, 3
violations give a one-sided Fisher p of 0.083 and 4 give 0.024. At 15
runs it is 4 of 15 (27 points), at 20 runs 5 of 20 (25 points), and at 30 runs
5 of 30 (17 points). The introspection section is 257 bytes, the single-rule
row, whose break-even uplift is 1.5 to 3 points. No offline count this harness
can afford reaches that, so the demonstration's summary will say its result
can't support withholding the section, and that the decision belongs to the
zero-violation rule or a live canary. Section-level decisions, a 4 KB section
at 10 to 20 points or a 16 KB reference at 40 to 90, are within reach at 30
runs for the larger sections and borderline for 4 KB; single-rule decisions
are not reachable offline.

### Stub agent

Tests replace `claude` with a stub through `ABLATION_AGENT_CMD`, which the
harness honours only when `ABLATION_TEST=1` is also set and refuses otherwise.
The stub gets the same argv and environment, calls `koto` through PATH with a
scripted sequence of evidence, and writes a minimal stream-json stream: a
`system` init, `assistant` messages with ids and usage, `user` tool results,
and a `result` with usage. Scripts cover violated then complied, complied
first, stopping after the refusal, a bypass by absolute path, a leaked read,
and a run killed by the wall-clock limit.

### CI

`.github/workflows/offload-ablation.yml` runs on `pull_request` only, with
`contents: read` and no secrets, on pull requests touching
`scripts/ablation/**`, `scripts/run-evals.sh`, `scripts/offload-baseline.sh`,
`docs/measurement/**` or the workflow. It installs koto 0.14.1 from its
release and checks its sha256, and runs one job per scripted criterion so
each is read on its own:

| Job | What it runs | PRD criterion |
|-----|--------------|---------------|
| `ablation-tests` | `python3 scripts/ablation/ablation_test.py`: span resolution and refusals, case validation, check contract, stub-agent delivery paths with the real koto, record fields, summary figures, empty pool | variant switch, refusals, grading, observation points, tokens, record, summary |
| `ablation-figures` | `ablation.py check-figures` | regeneration |
| `normal-runs-unchanged` | `scripts/ablation/check-normal-runs-unchanged.sh <base>`: every path in the load manifest and every koto template identical to the base | normal runs unchanged |
| `fixture-rule` | `is-fixture-session` over committed synthetic fixture and non-fixture headers, including a non-fixture with a pinned template hash | fixture marking |
| `public-content` | a grep of the diff against the base, and of the pull request body, for home-directory paths, `wip/` paths, session and job identifier shapes, and common secret shapes | public content |
| `run-evals-unchanged` | `scripts/run-evals_test.sh` plus a test that `run-evals.sh` without `--withhold` never reaches the harness | existing evals unchanged |

## Implementation Approach

The order follows what each step calls. The record's static token figure
calls `count --tree`, so it comes first; the fixture rule is needed by the
records; records, summaries and CI read what the harness core produces; and
the demonstration needs everything before it. CI starts in the first step,
and each step adds its own job.

1. **Count over a tree, and CI.** Add `count --tree <dir>` to
   `scripts/offload-baseline.sh`, with a test that it equals `count <commit>`
   over a checkout of that commit. Add
   `scripts/ablation/check-normal-runs-unchanged.sh` and the workflow with the
   `normal-runs-unchanged`, `public-content` and `run-evals-unchanged` jobs.
2. **Harness core.** `ablation.py` with `validate-case`, case selection,
   `resolve-span`, the run root, the allowlisted environment, the koto setup,
   the wrapper and `gh` shim, the check contract, the three demonstration
   checks, the fixture rule, and the stub-agent tests; then one real smoke
   run and one real repetition before building on it.
3. **Records, summary, regeneration.** Record derivation, leak and bypass
   detection, `summarize`, `check-figures`, and their tests over fixture
   records; the `ablation-figures` and `fixture-rule` jobs.
4. **Runner entry.** The `--withhold` hand-off in `run-evals.sh`.
5. **Demonstration and docs.** The case and its fixture, 2 repetitions run on
   demand, committed records and summary with the spend, the measurement
   README, and the baseline README's fixture sentence.

## Security Considerations

- **Nested sessions run shell commands.** Each arm runs a model session with
  `--allowedTools Bash` in a scratch fixture repository. `--setting-sources ""`
  also drops the user's own permission rules and hooks, so the harness puts
  its limits in the session environment rather than in settings: the
  environment is built from an allowlist, so no GitHub token, SSH agent
  socket, credential helper or other host variable reaches the agent; `gh`
  configuration points at an empty directory, so the real `gh` found by
  absolute path has no login; git's global configuration is empty and its
  SSH command is `/bin/false`; and koto, called through the wrapper or by
  the harness, runs against a scratch home and store. The fixture repository
  has no remote.
- **What the agent can still do.** The session keeps the real `HOME`, because
  the model client's login lives there, so the agent runs as the user with
  network access and can read any file the user can read, including SSH keys
  and tool configuration, and it can reach the real koto by absolute path.
  That is the exposure of any executing eval, widened by the dropped user
  settings. The harness narrows what follows from it rather than preventing
  it: bypass detection marks a run that went around the wrapper, and the next
  item keeps anything read out of committed files.
- **What leaves a run.** Sessions run with `--no-session-persistence`, and
  the run root, transcript included, is removed in a `finally` block, so no
  transcript persists. Records hold counts, outcomes and reason codes from a
  fixed pattern, never free text, so nothing the agent wrote reaches a
  committed file. The public-content CI job greps the diff and the pull
  request body for secret shapes as well as paths and identifiers.
- **Case files are data.** A case names checks, fixtures and a shipped
  template only from the repository's reviewed directories, every field is
  pattern-checked before use, the commit reaches git only after a hex check,
  the prompt follows `--`, and evidence reaches koto through a file, never a
  shell string. An outside corpus therefore can't bring executables,
  repositories or templates with it. Its prompts still steer an agent that
  runs shell, so running an outside corpus needs a person's explicit approval
  first: a review of its prompts and, preferably, a model key with its own
  spending cap. This feature runs only in-repository cases; the loader and
  format are tested against them.
- **The agent can reach the harness.** It could edit the checkout, including
  the checks. The harness hashes `scripts/ablation/` and records the
  checkout's status before and after each run, and marks a run where either
  changed `not-checkable` (`harness-tampered`). It compares the transcript's
  koto calls with the wrapper's log to catch a bypass, and it treats the
  wrapper log as the record of productions only when the two agree.
- **Withheld text reaching the agent another way** corrupts the measurement;
  leak detection marks those runs, and the summary reports how many.
- **CI.** The workflow runs on `pull_request` with read-only permissions and
  no secrets, and installs a pinned koto release checked by sha256. It never
  runs a model session.

## Consequences

**Positive**

- Any later feature can measure withholding a section before it ships, with
  one command and a case file.
- The without-skill arm becomes a graded lower bound instead of discarded
  work.
- Outside cases with stable ids run through the same path unchanged.

**Negative**

- Each run is a full model session; decision-grade counts (15 to 30 runs per
  arm, 30 per workflow for audits) cost real money and time, which is why CI
  never runs them.
- Starting a case at a mid-workflow state doesn't reproduce what earlier
  states would have put in the agent's context.
- Deployed checks for the demonstration live under `scripts/ablation/checks/`;
  a later feature that deploys one as a real gate has to move it.
- koto's own `expects` shows every arm the enum values and a one-line
  description of `rationale`, so part of the withheld section's content
  reaches the `withheld` arm anyway. That shrinks the measurable effect; a
  null result on this section says little about sections koto doesn't
  echo.
- Leak and bypass detection will discard some runs, so a case needs more
  repetitions than its target count.

**Mitigations**

- The summary states its own detection limit, so an underpowered result is
  labelled as one.
- The case format's `setup.evidence` can be extended to start earlier in a
  workflow when a section's rule depends on what came before.

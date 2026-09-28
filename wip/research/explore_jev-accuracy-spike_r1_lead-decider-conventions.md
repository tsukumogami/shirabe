# Lead: decider declarations, golden fixtures, and CI conventions for the Jev accuracy spike

How do shirabe's existing decider declarations and golden fixtures look, what
conventions should a spike's fixture file and harness follow, and what will CI
do with a PR that adds `docs/spikes/SPIKE-*.md`, a JSONL file, and a Python
script under `docs/spikes/`?

## Findings

### Shirabe's declarations today

Five declared fields across three templates, all enums, none in `auto`:

| Template | State | Field | Values (mode) | Escape |
|---|---|---|---|---|
| work-on.md | plan_validation | verdict | proceed (shadow), exit (never) | unclear |
| work-on.md | issue_type_routing | issue_type | code (shadow), docs (never), task (never) | unclear |
| execute.md | worktree_discipline_check | impact | informational (never), intent-changing (never) | unclear |
| coordinate.md | pick | choice | dispatch, scope_ahead, send_execution, ask_up, hold (all shadow) | unclear |
| coordinate.md | classify_report | classification | done, blocked, needs_fix (all shadow) | unclear |

Block shape (work-on.md plan_validation):

```yaml
decider:
  answers:
    proceed: {description: "Names a concrete change with checkable criteria."}
    exit:    {description: "Vague, contradictory, or needs design first.", mode: never}
  escape:  {value: unclear, description: "Missing, truncated, or unjudgeable."}
  inputs:
    - {context: context.md, label: outline_item, max_bytes: 12000}
    - {var: PLAN_DOC, label: plan_path}
```

Conventions visible across all five: every value gets a one-sentence
description written for both the agent and the model; the escape is always
`unclear`; any value that routes to a terminal or would be expensive if wrong
is `never`; a YAML comment above `accepts` explains the mode choice and names
the fixture file and the modes table. Nobody uses `threshold` (all at the 0.9
default) and nobody declares a boolean.

### Golden fixture files

Fixtures live beside the template as
`<stem>.<state>.<field>.decider.jsonl` (e.g.
`work-on.plan_validation.verdict.decider.jsonl`, 50 lines;
`work-on.issue_type_routing.issue_type.decider.jsonl`, 43 lines). One compact
JSON object per line:

```json
{"id":"pv-koto-event-log-format-1","inputs":{"outline_item":"### Issue 1: ...","plan_path":"docs/plans/PLAN-event-log-format.md"},"expected":"proceed"}
```

- Allowed keys: `id` (optional, string, unique in file), `inputs`, `expected`. Any other key is rejected by both shirabe's checker and koto's parser.
- `inputs` must have exactly the declared labels, each a string within its `max_bytes` (8192 default).
- `expected` is a declared value or the escape string for an enum; for a boolean it must be a JSON `true`/`false` (koto rejects the string `"true"`, and there is no way to label a boolean case as escape).
- ids are descriptive and prefixed by question (`pv-...`, `it-shirabe-<sha>`); inputs are real text from real repos/commits (issue_type fixtures carry real `git diff --name-status` output as `changed_paths`).
- Blank lines are skipped by koto but failed by shirabe's checker.

`scripts/check-decider-declarations.sh` (bash 3.2, jq, mikefarah yq v4, no network, never runs koto) globs every `decider` block in `skills/*/koto-templates/*.md`, holds each value's effective mode to `scripts/decider-declarations.tsv` (5 tab-separated columns: template, state, field, value, mode), and validates the fixture file: format as above, at least 10 cases per declared value (escape needs none), at least 40 total. It runs only from `check-templates.yml`, which triggers on `skills/*/koto-templates/**`, `skills/*/scripts/**`, `scripts/**`. It only discovers fixtures by the templated name beside a template, so a JSONL under `docs/spikes/` is invisible to it.

### koto: how a decision is scored

**Request (src/decider/jev.rs, request.rs).** Enum -> Jev `choice` question with `instructions` = the field's `description` and `criteria` = each value's description in `values` order, then the escape. Boolean -> Jev `noul` question with `instructions` = the field's `description` only. The `true`/`false` answer descriptions are NOT sent to Jev for a boolean (request.rs line ~255 builds `Proposition { proposition: field.description }`); they only reach the agent. Inputs go in a `state` object keyed by label. Model `jev-latest`, default endpoint `https://api.typesafe.ai/v1/systemone`, 2000 ms default timeout.

**Evaluation (src/decider/evaluate.rs).**
- Boolean: `p_true = noul`, `p_false = 1 - p_true`. `true` wins iff `p_true >= T_true` and not `p_false >= T_false`; `false` wins iff `p_false >= T_false` and not `p_true >= T_true`; otherwise (neither or both) the outcome is Escape. At the default 0.9/0.9: **P >= 0.9 -> true; P <= 0.1 -> false; 0.1 < P < 0.9 -> escape.** Comparison is inclusive on unrounded numbers. (The authoring guide's example raises `false` to 0.95, which would make false require P <= 0.05.)
- Enum: strictly highest probability over values+escape wins; a tie at the top -> escape; escape winning -> escape; a value winning below its threshold -> `below_threshold`. Jev's own `confidence` is ignored.

**Fixture report (src/decider/report.rs `judge`).** Each case lands in a column: the value (only if at threshold), `below_threshold`, `escape`, or `no_answer` (timeout/unusable answer; connect failure or 401/403 aborts the run). Metrics:
- per value: `cases`, `recall` = confusion[v][v] / cases labelled v (so an escape or below-threshold answer counts as a miss), `false_positives` = cases labelled otherwise answered v at threshold;
- `macro_recall` = mean recall over declared values with cases (escape-labelled cases are excluded from the mean; they only matter as potential false positives);
- `majority_baseline` = 1/(number of values with cases) when the most frequent label is a value, 0 when it is the escape;
- eligibility per value = all of: >=10 labelled cases, >=40 total, zero `no_answer`, zero false positives, macro_recall > baseline, >=30 ledger pairs under the current declaration hash, <=1 ledger disagreement, 0 directed exits, default endpoint (unless `--include-custom-endpoints`).
There is no "accuracy" field; the report is recall/false-positive/confusion based. Precision on a value is effectively required to be 100% on the fixture set.

The fixture run is `koto decider report --fixtures F --template T --state S [--field X] --json`, needs an opted-in decider (`KOTO_DECIDER=shadow` + `KOTO_DECIDER_API_KEY`), records nothing to the ledger, and exits 2 without opt-in.

### koto's live smoke harness (pattern worth copying)

`scripts/decider-live-smoke.sh` runs each `test/decider-live/<state>.<field>.jsonl` through `koto decider report --json` against `test/decider-live/smoke.md` under a throwaway `HOME`, `KOTO_DECIDER=shadow`, refuses to run if `KOTO_DECIDER_ENDPOINT` is set, and asserts only transport/schema (case count, no `no_answer`, no error class, default endpoint), printing but not asserting each answer. Fixture naming there is `<state>.<field>.jsonl` (no `.decider` infix); files are tiny synthetic sets (2 and 3 lines). smoke.md shows a minimal compilable template with one enum and one boolean declaration using a `var` input.

### CI on the planned PR

Workflows that trigger on a PR adding only `docs/spikes/SPIKE-*.md`, `docs/spikes/**.jsonl`, `docs/spikes/**.py`:

- `build-and-test.yml` (every PR): `cargo build --release`, `cargo test --workspace`. `crates/shirabe/tests/absorption_corpus.rs` walks every `docs/**/*.md` and asserts the absorption checks are silent on docs declaring no `absorbed:`; a spike with no `absorbed:` frontmatter is fine. Non-.md files are not walked.
- `check-rustfmt.yml` (every PR): Rust only.
- `validate-shirabe-docs.yml` (paths `docs/**`) -> `validate-docs.yml`: passes the whole changed-file set (minus `evals/fixtures/` and `tests/fixtures/`) to `shirabe validate`. main.rs skips any file that is not `.md` and has no artifact prefix, so `.py` and `.jsonl` are ignored, provided their basenames don't start with BRIEF-/PRD-/DESIGN-/PLAN-/ROADMAP-/VISION-/STRATEGY-/COMP-. `SPIKE-` is not an artifact prefix, so the spike report gets only the prose family: FC10 writing-style (notice level, not failing), CLAUDE.md conventions (basename-gated, n/a), and FC20 stale references (an error in both postures; fires only when a body path names no file while a file with the same basename exists elsewhere in the artifact dirs).
- `validate-lifecycle.yml` (every PR) -> `shirabe validate --lifecycle .`, ready posture when not draft. It walks only docs/briefs, prds, designs, designs/current, plans, roadmaps; `docs/spikes/` is never read.
- `validate-pr-body.yml` (every PR): PB1 Conventional Commits title (`docs(...)` is fine), PB2 exactly one top-level bare `---` with non-empty Part 1, PB3 no AI attribution, PB4 no markdown headings in Part 1.
- Not triggered: `check-no-fixture-design-leak.yml` (only `docs/designs/current/**` and eval fixture designs), `check-templates.yml` / decider-declaration check, `check-koto-minimum.yml` (covers `docs/guides/**`, not spikes), `check-directive-invocations.yml`, `check-evals.yml`, etc.

There is no Python lint, no JSON/JSONL lint, and no check that runs a Python file anywhere in CI. Precedent for Python in-repo: `scripts/lib/classify-eval-session.py`.

The wip-hygiene rule still applies: nothing committed may reference `wip/`, and `wip/` must be emptied before merge (no CI check greps content for it).

### Spike report format

No validator checks SPIKE docs. The shape comes from convention (both existing spikes) and explore's phase-5-produce-spike-report.md:

```markdown
---
status: Draft | Complete
question: |
  <go/no-go answerable question>
timebox: "<e.g. 1 session>"
---

# SPIKE: <Topic>

## Status
## Question
## Context
## Approach
## Findings
## Recommendation
```

Existing spikes add `## References` or topic-specific sections after Findings. Commit convention: `docs(explore): produce spike report for <topic>`.

### Existing spike artifact already in the worktree

`docs/spikes/jev-accuracy/grade.py` already exists (stdlib-only Python 3.8+). It models each fixture as "text + criterion", sends a koto-shaped Jev request, maps to pass/fail/escape at a threshold, and supports `--stub`, `--live --record FILE`, and `--replay FILE --threshold X`. The key is read from `JEV_API_KEY` or `KOTO_DECIDER_API_KEY` and only placed in the Authorization header.

## Implications

- For the numbers to transfer to koto, the harness has to reproduce koto's mapping exactly: for a boolean, only the field description goes as `instructions` and the true/false descriptions are dropped. For an enum, strictly-highest wins, ties go to escape, and a winner below threshold counts as a miss rather than an answer. Score with koto's metrics (per-value recall, false positives at threshold, macro recall against the majority baseline, confusion over value/below_threshold/escape/no_answer), not a single accuracy figure. Otherwise a 90% "accuracy" won't say whether any value could pass koto's zero-false-positive bar.
- A spike that frames "criterion over text" as a boolean `noul` needs the criterion text in the field description, because koto won't send anything else. At 0.9, anything between 0.1 and 0.9 is escape, and it counts against recall.
- If the spike's fixture lines use koto's exact format (`id`, `inputs` keyed by label, `expected` as a JSON boolean or value string), the same file can later go through `koto decider report --fixtures` against a small template (smoke.md shape) with no conversion. Name it without the `.decider.jsonl` infix, or keep it out of `skills/*/koto-templates/`, so it isn't confused with a promotion fixture. It's harmless under `docs/spikes/` either way.
- Stub/replay modes matter for CI and reviewers: nothing in CI will run the script, and a fork PR must never spend a key (the stated reason shirabe's own check never runs koto).

## Surprises

- The authoring guide's "What leaves the machine" says each value's description is sent. For boolean fields that isn't true: the `true`/`false` descriptions never reach Jev. A boolean's criterion lives entirely in the field `description`.
- koto doesn't define an "accuracy" metric. Promotion is gated on zero fixture false positives per value plus recall beating the majority baseline. Escape-labelled cases don't enter macro recall at all.
- A boolean fixture can't be labelled "should escape". Only `true`/`false` are legal `expected` values, so every escape on a boolean is a recall miss by construction.
- `grade.py` is already present in the worktree, so someone has started the harness.
- FC20 is the only prose-family check that fails CI on a SPIKE doc. The writing-style findings are notices only.

## Open Questions

- Does the spike want to measure the boolean (`noul`) path, the enum (`choice`) path, or both? They differ in what's sent and in how escape arises (explicit criterion vs. the band between thresholds).
- Should the fixtures be real shirabe decision inputs (like the existing golden files) or synthetic criterion/text pairs? Real inputs make the result speak to promotion. Synthetic ones only speak to Jev in general.
- Does grade.py's "text + criterion" fixture shape keep koto's `id`/`inputs`/`expected` line format, so it can be replayed through `koto decider report`?

## Summary

Shirabe declares five enum decider fields (work-on x2, execute x1, coordinate x2), all shadow or never, all using escape `unclear` and the default 0.9 threshold, each with a golden `<stem>.<state>.<field>.decider.jsonl` beside the template that `scripts/check-decider-declarations.sh` holds to at least 10 cases per value and 40 in total, with modes pinned in `scripts/decider-declarations.tsv`. koto scores fixtures with per-value recall, false positives at threshold, and macro recall against a majority baseline, not accuracy. Promotion needs zero false positives. For a boolean, koto sends Jev only the field description as a `noul` question. A PR adding a SPIKE doc plus `.py` and `.jsonl` under `docs/spikes/` trips no check: `shirabe validate` skips non-Markdown files without an artifact prefix, SPIKE has no schema validator, and the lifecycle walk never reads `docs/spikes/`. `docs/spikes/jev-accuracy/grade.py` already exists in the worktree.

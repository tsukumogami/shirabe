---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-linter-check-states.md
milestone: "Linter check states"
issue_count: 3
---

# PLAN: linter check states

## Status

Active

## Scope Summary

Give the /work-on and /execute pull request gate a writing-style check: an
opt-in `shirabe validate --pr-body --writing-style <rules-file>` that reports
banned terms in the title and body as `PB5`, mapped by
`check-pr-output.sh` to a new registry rule `pr-body/banned-word` (never
eligible to withhold), with preflight declarations and the workflow prose
that describes it.

## Decomposition Strategy

**Horizontal.** The design has three layers with stable interfaces between
them: the validator flag and its `[PB5] ` message prefix, the gate script and
registry that map that prefix to a rule id, and the prose that tells agents
what the gate checks. Each layer is built and tested fully before the next
reads it. All three land in one pull request, because a gate that passes
`--writing-style` must not ship ahead of a validator that knows it.

## Issue Outlines

### Issue 1: feat(validate): add an opt-in writing-style check to --pr-body

**Goal**: `shirabe validate --pr-body <file> [--pr-title <t>] --writing-style <rules-file>` reports every banned term in the title and the body's prose as a `[PB5] ` finding, using FC10's matcher, with rules loaded from the named file and vocabulary from the working directory, while output without the flag is unchanged.

**Acceptance Criteria**:
- [ ] The term loop of `check_writing_style_with` is a shared span-level function that FC10 and PB5 both call, and the golden parity tests in `crates/shirabe/tests/` pass unchanged.
- [ ] `--writing-style` declares `requires = "pr_body"`; using it without `--pr-body` exits 1.
- [ ] A missing, unreadable or malformed rules file, or one whose `words:` block lists no term, exits 1 with a `--writing-style:` line on stderr and no `shirabe-pr-body/v1` envelope.
- [ ] Body line 3 containing `leverage` yields one finding at line 3 whose message is `[PB5] writing-style banned word "leverage" on line 3 -- ` followed by the verbs category's guidance on one line; a category with empty guidance yields the message without ` -- `.
- [ ] A term on a Part 2 line is reported with its line number over the whole body; two occurrences on one line give two findings; `Leverage` and `LEVERAGE` match, `leveraged` and `releverage` don't.
- [ ] Inline code, fenced and indented code, table cells, link destinations, bare URLs and HTML comments are never matched, in either part.
- [ ] Title `feat: a seamless migration` yields one finding whose message says `in the title`; `feat(tier): add levels` yields none; `leverage: x` (a type outside PB1's `CONVENTIONAL_TYPES`) yields a finding for `leverage`; title `a seamless migration` yields both a PB1 finding and a PB5 finding.
- [ ] A body with 60 occurrences yields exactly 50 term findings and one `[PB5] writing-style findings truncated at 50 for this pull request; ...` finding; a title hit plus 60 body hits yields the title finding first, 49 body findings and the truncation finding; matching stops at the cap.
- [ ] With the working directory inside a repository whose `CLAUDE.md` (and, separately, `CLAUDE.local.md`) declares `## Prose Vocabulary: tier`, `tier` yields no finding and `tiered` yields one, and stderr carries one line listing the suppressed rules-file terms; the walk stops after the first directory holding `.git` (a directory or a file).
- [ ] No PB5 message contains text from the title or body: with `LEVERAGE` in the body, the message names `leverage` as the rules file spells it.
- [ ] On a body of GitHub's maximum size (65,536 characters, every word a banned term) the check returns at most 51 findings, and the unit test asserts it completes within 5 seconds.
- [ ] Without `--writing-style`, stdout, stderr and exit code for `--pr-body` match the merge base's build on the PB1 to PB4 fixtures and on a title and body containing banned terms, in all three `--format` values; `shirabe pr-body-hook`'s tests pass unchanged, and a new hook test shows a body and title with banned terms are allowed.
- [ ] The comments in `crates/shirabe-validate/src/rules.rs`, `checks.rs` and the `skills/writing-style/rules.yaml` header no longer describe a `--rules` flag or a CLI tool error the code doesn't produce; the `rules.yaml` edit keeps the file's line count above the `words:` block, so the banned-words range stays lines 17 to 89, and `scripts/check-rule-registry.sh` passes.
- [ ] `.github/workflows/pr-body.yml` has no diff against the merge base.
- [ ] `cargo test` passes and `cargo fmt --check` is clean.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/pr_body.rs`, `crates/shirabe-validate/src/visibility.rs`, `crates/shirabe-validate/src/rules.rs`, `crates/shirabe/src/main.rs`, `crates/shirabe/src/pr_body_hook.rs`, `skills/writing-style/rules.yaml`

### Issue 2: feat(work-on): hold the pull request gate on banned words

**Goal**: `check-pr-output.sh --pr-body` passes the plugin's own `rules.yaml` through `--writing-style`, maps `[PB5] ` findings to the new registry rule `pr-body/banned-word`, and holds when it can't decide, with the registry entry, preflight declarations and CI path filter that go with it.

**Acceptance Criteria**:
- [ ] `references/rule-registry.json` has `pr-body/banned-word`: `text` with `prose/banned-word`'s anchors in `skills/writing-style/rules.yaml`, `check` `{"kind":"script","path":"skills/work-on/scripts/check-pr-output.sh","mode":"--pr-body"}`, `fixtures` `skills/work-on/scripts/check-pr-output_test.sh`, `level` `gate`, `timing` `work-on:pr_creation` and `execute:pr_finalization`, `guards` `pr-create` and `publish`, `withhold` `never`, `baseline_keys` `skills/writing-style/rules.yaml#L17-L89`, alias `PB5`; both it and `prose/banned-word` name each other in `notes`; no entry's `withhold` changed; `scripts/check-rule-registry.sh` passes.
- [ ] `RULE_IDS` and the `require_rules` call in `check-pr-output.sh` include `pr-body/banned-word`, and `rule_for_message` matches `"[PB5] "*` before the `PR title ` arm.
- [ ] The validator call appends `--writing-style <path>` after the existing arguments, where `<path>` is the plugin's own `skills/writing-style/rules.yaml` resolved with `pwd -P` from the script's location; the stand-in `shirabe` records exactly that path, and existing positional assertions in `check-pr-output_test.sh` still pass.
- [ ] With the stand-in validator, a PB5 message yields exit 1 and one `::koto-finding::` with `rule_id` `pr-body/banned-word`, `level` `error`, a `message` starting with the entry's `summary` and `: `, and the `rule_ref` that `scripts/rule-registry.sh ref pr-body/banned-word` prints; a title-only PB5 message through `--pr-body --owned` yields the same finding.
- [ ] A body breaking PB2 plus a PB5 message yields both a `pr-body/one-separator` and a `pr-body/banned-word` finding and exit 1; a clean run exits 0 with no finding line.
- [ ] The gate exits 2 with no finding line when the plugin's `rules.yaml` is absent, when `shirabe` is not on PATH, and when the stand-in `shirabe` exits 1; when its stderr shows clap's `unexpected argument '--writing-style'`, the gate's stderr names the upgrade.
- [ ] With `SHIRABE_RULES=/dev/null`, and separately with a `skills/writing-style/rules.yaml` listing no term in the working directory, the gate still passes the plugin's path.
- [ ] Cases that run a `shirabe` built from the same commit (skipped locally when none is on PATH, fatal in CI): body line 3 containing `leverage` gives exit 1 and exactly one `::koto-finding::` with `rule_id` `pr-body/banned-word`, a `message` starting with the entry's `summary` and `: ` and containing `leverage`, `line 3` and the verbs category's guidance, and the `rule_ref` that `rule-registry.sh ref pr-body/banned-word` prints; 60 occurrences give the truncation finding under the same id; and a plugin `rules.yaml` replaced with invalid YAML, or with an emptied `words:` block, gives exit 2 and no finding line.
- [ ] `rule-registry.sh verify-findings` passes on the suite's findings log, which includes a `pr-body/banned-word` finding.
- [ ] The gate runs the validator once and `gh pr view` once per evaluation, as the stand-ins record.
- [ ] `skills/work-on/requires.tsv`'s `always` `shirabe validate` record adds `--writing-style`; `skills/execute/requires.tsv`'s `always` record adds `--pr-body`, `--pr-title` and `--writing-style`; no other tool is added to either; `skill-preflight.sh` for each skill, against a stand-in `shirabe` whose `validate --help` lacks `--writing-style`, reports it.
- [ ] `skills/writing-style/rules.yaml` is in both path lists of `.github/workflows/check-work-on-scripts.yml`.
- [ ] `check-pr-output.sh`'s header rule table names PB5 and `pr-body/banned-word`.
- [ ] `scripts/check-skill.sh --changed work-on` and `--changed execute` pass.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/work-on/scripts/check-pr-output.sh`, `skills/work-on/scripts/check-pr-output_test.sh`, `references/rule-registry.json`, `skills/work-on/requires.tsv`, `skills/execute/requires.tsv`, `.github/workflows/check-work-on-scripts.yml`

### Issue 3: docs(work-on): name the banned-word check where the workflows describe the gate

**Goal**: The /work-on and /execute templates, the PR phase reference, the pull request conformance reference and the output-gates design say the pull request gate also checks banned words under `pr-body/banned-word`, point the agent at the writing-style rules when it writes the title and body, and stop claiming CI enforces that part.

**Acceptance Criteria**:
- [ ] The `pr_body_conformant` gate comment and the `pr_creation` directive in `skills/work-on/koto-templates/work-on.md` name the banned-word check and `pr-body/banned-word` and point at `skills/writing-style`; no sentence says CI enforces the banned-word check.
- [ ] The `owned_pr_body_conformant` gate comment and the `pr_finalization` rule-id list in `skills/execute/koto-templates/execute.md` include `pr-body/banned-word`; the same CI claim is absent.
- [ ] `skills/work-on/references/phases/phase-6-pr.md` names the check and where it runs.
- [ ] `references/pr-body-conformance.md` has a PB5 entry pointing at `skills/writing-style/rules.yaml` without restating the list, inserted after the PB4 entry's last line so the existing entries' anchors don't move; `scripts/check-rule-registry.sh` still passes.
- [ ] `docs/designs/current/DESIGN-output-gates.md`'s mapping table has a PB5 row for `pr-body/banned-word`.
- [ ] The success edges of `work-on:pr_creation` and `execute:pr_finalization` still require the gate that runs `check-pr-output.sh --pr-body` to exit 0.
- [ ] Each changed skill's `evals/evals.json` has a scenario whose expectations require the agent to name `pr-body/banned-word` or point at `skills/writing-style` when a pull request body uses a banned word, and `scripts/check-skill.sh --changed work-on` and `--changed execute` pass.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: docs
**Files**: `skills/work-on/koto-templates/work-on.md`, `skills/execute/koto-templates/execute.md`, `skills/work-on/references/phases/phase-6-pr.md`, `references/pr-body-conformance.md`, `docs/designs/current/DESIGN-output-gates.md`, `skills/work-on/evals/evals.json`, `skills/execute/evals/evals.json`

## Implementation Sequence

The critical path is Issue 1, then Issue 2, then Issue 3, with no parallel
branch: the gate's real-validator case needs Issue 1's binary, and Issue 3's
prose names the rule id Issue 2 registers. Issue 2's stand-in cases can be
written while Issue 1 is under review, but Issue 2 lands after it. Everything
lands in one pull request so the gate never passes a flag the validator in
the same release lacks.

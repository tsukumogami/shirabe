---
complexity: testable
complexity_rationale: Evals are the integration verification surface for `/charter`; scenarios cover the full SKILL.md + phase-prose contract authored across <<ISSUE:2>>-<<ISSUE:8>> via the shipped `scripts/run-evals.sh` runner, and validation is grep-and-JSON-parse against a single shipped file with no security-sensitive surface.
---

## Goal

Ship `skills/charter/evals/evals.json` with nine eval scenarios — four canonical **shared-baseline** scenarios (slug rejection, malformed state file, child-internals isolation, visibility default) clearly delimited for future copy-and-adapt by `/scope` and `/work-on`, plus five `/charter`-specific scenarios covering PRD User Stories US-1, US-2, US-3a, US-3b, and US-4 — all passing under `scripts/run-evals.sh charter` per AC26c.

## Context

`/charter` is the first concrete consumer of the shirabe parent-skill pattern, and per Design Decision 4, its `evals.json` is the **canonical source** for the shared eval baseline that future parents (`/scope`, `/work-on`) will copy-and-adapt when they land. Until a future eval-format `$ref` mechanism mechanically retrofits the baseline, the copy-paste contract is the discipline: baseline scenarios must be clearly delimited (via tags, ordering, or comment headers) so a future parent can mechanically identify what to copy.

This issue is the convergence issue for `/charter` — eval scenarios assert behaviors documented in SKILL.md and the phase-prose reference files authored by `<<ISSUE:2>>` through `<<ISSUE:8>>`. Evals cannot be authored until those behaviors exist on disk, so this issue is blocked by every prior `/charter` implementation issue.

Design: `docs/designs/DESIGN-shirabe-progression-authoring.md` (Decision 4 — shared eval baseline via copy-paste; `/charter`'s evals.json is the canonical source; Stage 2 — Deliverables, Canonical-source note).

PRD: `docs/prds/PRD-shirabe-charter-skill.md` (R18 — parent skill ships evals at `skills/<name>/evals/evals.json`; charter evals MUST cover US-1..US-4; AC26c — scenarios pass under `scripts/run-evals.sh charter`).

### Eval format precedent

shirabe's eval format is JSON-flat: a top-level object with `skill_name` and an `evals: []` array. Each scenario is a JSON object with the following fields (per shipped shirabe evals — see `skills/strategy/evals/evals.json` as the reference precedent):

- `id` — integer scenario ID, unique within the file.
- `name` — kebab-case scenario name; carries the user-story tag (e.g., `us-1-cold-standalone-full-run`) or baseline tag (e.g., `baseline-slug-rejection`) so future parents and validation greps can mechanically identify scenario class.
- `prompt` — the literal `/charter` invocation string the runner uses (e.g., `/charter test-topic`).
- `expected_output` — prose description of the expected behavior; provides the runner with the human-readable success condition.
- `files` — array of pre-existing artifact paths the runner pre-populates before invoking `/charter` (e.g., for the re-evaluation scenario, an Accepted STRATEGY at `docs/strategies/STRATEGY-<topic>.md`).
- `expectations` — array of specific assertion strings the runner grades against; each string is a check the runner verifies the plan or output satisfies.

There is **no `$ref` mechanism in v1** (per Design Decision 4); the shared baseline is delimited by naming convention and ordering, not by JSON reference.

### Scenario set composition (nine scenarios)

The file contains nine scenarios in two delimited groups. The shared-baseline group MUST come first (lower IDs) and MUST be tagged via the `name` field prefix `baseline-` so future parents can mechanically identify them via simple JSON traversal. The `/charter`-specific group follows with the `us-` prefix per user story.

**Shared-baseline scenarios (canonical source per Design Decision 4)** — must be tagged or grouped at the top of the file with a header comment in the JSON file (e.g., a `_comment` sibling key, or by ordering convention plus the `baseline-` name prefix; this issue MAY choose either delimiter as long as the discipline is mechanical):

1. **baseline-slug-rejection** — invoking `/charter MyTopic` (uppercase), `/charter my_topic` (underscore), `/charter my.topic` (dot), and `/charter "Hello World"` (whitespace) are each rejected at Phase 0 with a clear error naming the violated `^[a-z0-9-]+$` pattern. Asserts AC3, AC3b.

2. **baseline-malformed-state** — when `wip/charter_<topic>_state.md` exists but is unparseable (e.g., missing YAML opening fence, invalid YAML body, missing required fields for the recorded `phase_pointer`, or invalid exit-field/sub-shape combination), `/charter` surfaces a clear error naming the specific malformation AND offers a **Discard** recovery path. `/charter` MUST NOT silently fall through to Phase 0 (row 10 of the resume ladder). Asserts AC20c.

3. **baseline-child-internals-isolation** — `/charter` does NOT read child internals during resume or chain orchestration. Specifically: `/charter` MUST NOT read any `wip/research/<child>_<topic>_phase<N>_*.md` file, MUST NOT read child internal phase pointers, and MUST NOT read any child `wip/` intermediate beyond the named partial-run-detection filename patterns in rows 7-8 of the resume ladder (`wip/strategy_<topic>_discover.md`, `wip/vision_<topic>_scope.md`). Per AC20b this is manual-review against the prose; the eval scenario verifies via code-path inspection assertion strings (the plan must not name reading child internals).

4. **baseline-visibility-default** — when CLAUDE.md is missing the `## Repo Visibility:` header, `/charter` defaults to Private AND emits a warning whose body contains the literal phrase **"Default to Private if unknown"**. Asserts AC21.

**/charter-specific scenarios (one per PRD User Story per R18)**:

5. **us-1-cold-standalone-full-run** — invoke `/charter test-topic` against a fresh worktree with no `wip/charter_<topic>_state.md`, no `docs/strategies/STRATEGY-<topic>.md`, and no upstream artifacts. Public-repo visibility (per workspace discipline). `/charter` walks Phase 1 discovery, decides not to invoke `/vision` (no thesis-shift signal) and not to invoke `/comp` (public repo per R5 + R12 degenerate-silence rule), invokes `/strategy` per R6, and may invoke `/roadmap` if the produced STRATEGY's Building Blocks gate passes per R7. State file at chain finalization has `exit: full-run`, `exit_artifacts` lists the STRATEGY path (and the ROADMAP path if `/roadmap` ran). Asserts AC2, AC11a, AC11b.

6. **us-2-re-evaluation** — pre-populate an Accepted STRATEGY at `docs/strategies/STRATEGY-test-topic.md` (no `wip/charter_<topic>_state.md`). Invoke `/charter test-topic`. The entry prompt MUST contain the literal substrings (case-insensitive) **"Re-evaluate"**, **"Revise"**, and **"Bail"**, AND MUST NOT contain the substring **"Continue / Start fresh"**. Author selects "Re-evaluate"; `/charter` walks the upstream STRATEGY's claims, finds all still hold, writes a Decision Record at `docs/decisions/DECISION-strategy-test-topic-re-evaluation-<YYYY-MM-DD>.md` referencing the STRATEGY without re-invoking `/strategy`. Final state file: `exit: re-evaluation`, `decision_record_sub_shape: re-evaluation`, `referenced_strategy: docs/strategies/STRATEGY-test-topic.md`. Asserts AC12, AC18.

7. **us-3a-rejection-sub-shape** — start cold (no artifacts). Invoke `/charter test-topic`. `/charter` invokes `/strategy`; `/strategy` reaches Phase 5 and the author selects Reject. `/strategy` discards the Draft STRATEGY via `git rm` + commit (the discard commit is `/strategy`'s responsibility). `/charter` then writes a Decision Record at `docs/decisions/DECISION-strategy-test-topic-rejection-<YYYY-MM-DD>.md` referencing the discard commit SHA. Final state file: `exit: re-evaluation`, `decision_record_sub_shape: rejection`, `discard_commit_sha: <sha>`, `rejection_rationale: <text>`. Asserts AC13.

8. **us-3b-abandonment-forced** — start cold. `/charter test-topic` proceeds through Phase 1 and creates a partial-state state file with `phase_pointer: 2` and `chain_ran` listing the most-recently-running child but no `exit:` field set. Simulate a 7+ day gap (mock `last_updated` to be `≥ 7d` old). On next `/charter test-topic` resume, the 7-day stale-session detection fires (row 4 of the resume ladder) and surfaces the three-option prompt **Resume / Force-materialize / Discard**. Author selects **Force-materialize**. `/charter` force-materializes the most-recently-running child's intermediate with an HTML-comment marker `<!-- charter-status-block: abandonment-forced; ... -->` inside the artifact's Status section. Final state file: `exit: abandonment-forced`, `triggering_child: <child>`, `partial_phase_reached: <phase>`. Asserts AC14, AC17.

9. **us-4-manual-fallback-reviewer-redirect** — pre-populate an Accepted STRATEGY at `docs/strategies/STRATEGY-test-topic.md` AND a `wip/charter_test-topic_state.md` whose `child_snapshots.strategy` records the STRATEGY's path, current frontmatter `status: Accepted`, and a `content_hash` matching the STRATEGY's `git hash-object` at snapshot time. A reviewer then invokes `/strategy docs/strategies/STRATEGY-test-topic.md` directly (outside `/charter`); `/strategy` produces a revised Draft body, changing both the frontmatter `status:` and the body content (thus the live `git hash-object` differs from the snapshot's `content_hash`). On the next `/charter test-topic` invocation, the resume ladder fires drift detection per AC19 (dual check: `status` OR `content_hash` differs) and surfaces the three-option staleness prompt: (1) **Re-run** the downstream child, (2) **Accept** the downstream as still-valid, (3) **Proceed without** the downstream. The eval also asserts that during the manual `/strategy` invocation `/charter` did NOT interfere (no warning, no state-file write, no block) per R13 / AC22 / AC23. Asserts AC19, AC22, AC23.

### Canonical-source delimiter discipline

The four shared-baseline scenarios MUST be clearly delimited so future parents (`/scope`, `/work-on`) can mechanically identify them for copy-and-adapt. This issue applies BOTH of the following delimiters (defense in depth):

- **Name-prefix discipline**: baseline scenarios use the `baseline-` prefix in the `name` field (`baseline-slug-rejection`, `baseline-malformed-state`, `baseline-child-internals-isolation`, `baseline-visibility-default`); `/charter`-specific scenarios use the `us-` prefix.
- **Ordering discipline**: the four baseline scenarios are placed first in the `evals` array (IDs 1-4), with the five user-story scenarios following (IDs 5-9). A JSON-readable comment header (e.g., a `_baseline_note` key on the first baseline scenario or a `description` key on the top-level object explaining the canonical-source contract) further documents the discipline inline so a future copy-and-adapt author reading the file does not need to refer to this issue's prose.

Until shirabe's eval format gains `$ref` mechanism, the canonical-source contract is enforced via reviewer discipline and this delimiter convention.

### Public-repo discipline

All scenarios reference public-repo-safe topic slugs (e.g., `test-topic`); no private repo paths, no private-tool names. Visibility-default scenario tests the absence-of-header case, not a private-repo case (`/comp` invocation testing is out of scope here — that lives in `<<ISSUE:4>>`'s scope-side tests).

### Eval runner contract

Scenarios MUST pass under `scripts/run-evals.sh charter` per AC26c. The runner is shirabe's standard eval runner (already shipped at `scripts/run-evals.sh`); it requires the `claude` CLI plus the `/skill-creator` plugin loaded in the runtime environment. This issue's validation script verifies the file is parseable and structurally correct; **the AC requiring `scripts/run-evals.sh charter` to pass is run separately by the implementer per shirabe's evals discipline (not in the validation bash here)**. This split matches `shirabe/CLAUDE.md`'s Skill Evals section: the runner needs `/skill-creator` loaded to execute, which is not part of the standard validation harness.

## Acceptance Criteria

### File presence and structure

- [ ] `skills/charter/evals/evals.json` exists.
- [ ] `skills/charter/evals/evals.json` is valid JSON (parseable by `python3 -c "import json; json.load(open(...))"`).
- [ ] The top-level JSON object contains a `skill_name` field with the value `charter`.
- [ ] The top-level JSON object contains an `evals` array with **exactly nine** scenario objects.
- [ ] Every scenario object contains the fields: `id` (integer), `name` (string), `prompt` (string), `expected_output` (string), `files` (array; may be empty), and `expectations` (array of strings; non-empty).
- [ ] Every scenario's `name` is kebab-case and unique within the file.
- [ ] Every scenario's `id` is a positive integer unique within the file.

### Shared-baseline scenarios (canonical source per Design Decision 4)

- [ ] The four shared-baseline scenarios appear first in the `evals` array (IDs 1-4 or lower IDs than any `us-` scenario).
- [ ] Each shared-baseline scenario has a `name` field that starts with the literal prefix `baseline-`.
- [ ] Scenario `baseline-slug-rejection` exists and its `expectations` array names the regex `^[a-z0-9-]+$` and at least three distinct rejection input examples (e.g., uppercase like `MyTopic`, underscore like `my_topic`, dot like `my.topic`, or whitespace like `Hello World`). Asserts AC3, AC3b.
- [ ] Scenario `baseline-malformed-state` exists and its `expectations` array names that `/charter` MUST surface a clear error AND offer a **Discard** recovery path, AND MUST NOT silently fall through to Phase 0. Asserts AC20c.
- [ ] Scenario `baseline-child-internals-isolation` exists and its `expectations` array names that `/charter` MUST NOT read `wip/research/<child>_<topic>_phase<N>_*.md` files OR child internal phase pointers OR any child `wip/` intermediate beyond the rows 7-8 named patterns (`wip/strategy_<topic>_discover.md`, `wip/vision_<topic>_scope.md`). Asserts AC20b (manual-review verified by code-path inspection).
- [ ] Scenario `baseline-visibility-default` exists and its `expectations` array names the default-Private behavior AND the literal warning phrase **"Default to Private if unknown"**. Asserts AC21.
- [ ] The file documents the canonical-source contract inline (e.g., via a top-level `description` field, or a comment-style key on the file or on the first baseline scenario) so a future `/scope` or `/work-on` author reading the file understands the copy-and-adapt discipline.

### /charter-specific scenarios — one per PRD User Story (R18)

- [ ] Scenario `us-1-cold-standalone-full-run` exists and its `expectations` array covers: cold-start invocation; Phase 1 discovery; `/vision` NOT invoked (no thesis-shift signal); `/comp` NOT invoked (public repo); `/strategy` invoked per R6; final state file `exit: full-run` with `exit_artifacts` listing the STRATEGY (and optionally ROADMAP). Asserts AC2, AC11a, AC11b.
- [ ] Scenario `us-2-re-evaluation` exists and its `expectations` array covers: entry prompt contains the substrings "Re-evaluate", "Revise", and "Bail" (case-insensitive); entry prompt MUST NOT contain "Continue / Start fresh"; "Re-evaluate" path writes a Decision Record at `docs/decisions/DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md`; final state file has `exit: re-evaluation`, `decision_record_sub_shape: re-evaluation`, and `referenced_strategy: <path>`. Asserts AC12, AC18.
- [ ] Scenario `us-3a-rejection-sub-shape` exists and its `expectations` array covers: `/strategy` Phase 5 Reject path; `/strategy` discards STRATEGY via `git rm` + commit; `/charter` writes Decision Record at `docs/decisions/DECISION-strategy-<topic>-rejection-<YYYY-MM-DD>.md` referencing the discard commit SHA; final state file has `exit: re-evaluation`, `decision_record_sub_shape: rejection`, `discard_commit_sha`, and `rejection_rationale`. Asserts AC13.
- [ ] Scenario `us-3b-abandonment-forced` exists and its `expectations` array covers: state file `last_updated ≥ 7d` triggers row 4 stale-session prompt; three-option **Resume / Force-materialize / Discard** prompt; Force-materialize path writes the abandonment-forced HTML-comment marker `<!-- charter-status-block: abandonment-forced; ... -->` inside the force-materialized artifact's Status section; final state file has `exit: abandonment-forced`, `triggering_child`, and `partial_phase_reached`. Asserts AC14, AC17.
- [ ] Scenario `us-4-manual-fallback-reviewer-redirect` exists and its `expectations` array covers: out-of-chain `/strategy` invocation does NOT trigger `/charter` interference (no warning, no state-file write, no block); drift detection fires on next `/charter` resume per dual check (`status` OR `content_hash` differs); three-option staleness prompt **Re-run / Accept / Proceed without** is surfaced. Asserts AC19, AC22, AC23.

### Eval-runner pass requirement (AC26c)

- [ ] All nine scenarios pass under `scripts/run-evals.sh charter`. (The implementer runs this manually per shirabe evals discipline; the runner needs the `/skill-creator` plugin loaded. See `shirabe/CLAUDE.md` Skill Evals section. Validation in this issue verifies file structure; passing the runner is the AC.)

### Public-repo discipline

- [ ] All scenario `prompt` and `files` references use public-repo-safe topic slugs (e.g., `test-topic`); no private repo paths, no private-tool names.
- [ ] No scenario depends on the existence of `/comp` (which is not yet shipped); the visibility-default baseline tests the absence-of-header case rather than a private-repo `/comp` invocation.

### Content discipline

- [ ] No private-repo references, no internal tooling names, no pre-announcement features (public-repo discipline).
- [ ] Each scenario's `expectations` array contains at least three distinct assertion strings (specific enough that the runner can grade meaningfully against the documented behavior).

### Downstream deliverables

- [ ] This issue is a leaf — no downstream dependents. After it lands, `/charter` is implementation-complete for `/plan`'s purposes.

## Validation

```bash
#!/usr/bin/env bash
set -euo pipefail

# File presence
test -f skills/charter/evals/evals.json

# Parseable JSON
python3 -c "import json; json.load(open('skills/charter/evals/evals.json'))"

# Top-level skill_name field
python3 -c "import json; d=json.load(open('skills/charter/evals/evals.json')); assert d['skill_name']=='charter', f\"skill_name must be 'charter', got {d['skill_name']!r}\""

# Exactly nine scenarios
python3 -c "import json; d=json.load(open('skills/charter/evals/evals.json')); n=len(d['evals']); assert n==9, f'expected 9 scenarios, got {n}'"

# Every scenario has required fields
python3 -c "
import json
d = json.load(open('skills/charter/evals/evals.json'))
required = {'id', 'name', 'prompt', 'expected_output', 'files', 'expectations'}
for i, s in enumerate(d['evals']):
    missing = required - set(s.keys())
    assert not missing, f'scenario {i} missing fields: {missing}'
    assert isinstance(s['id'], int), f'scenario {i} id must be int'
    assert isinstance(s['name'], str) and s['name'], f'scenario {i} name must be non-empty string'
    assert isinstance(s['expectations'], list) and len(s['expectations']) > 0, f'scenario {i} expectations must be non-empty list'
"

# Unique names and ids
python3 -c "
import json
d = json.load(open('skills/charter/evals/evals.json'))
names = [s['name'] for s in d['evals']]
ids = [s['id'] for s in d['evals']]
assert len(set(names)) == len(names), 'duplicate scenario names'
assert len(set(ids)) == len(ids), 'duplicate scenario ids'
"

# Four baseline scenarios with baseline- prefix, ordered first
python3 -c "
import json
d = json.load(open('skills/charter/evals/evals.json'))
names = [s['name'] for s in d['evals']]
baselines = [n for n in names if n.startswith('baseline-')]
assert len(baselines) == 4, f'expected 4 baseline scenarios, got {len(baselines)}: {baselines}'
# Baselines must appear before any us- scenario
first_us = next((i for i, n in enumerate(names) if n.startswith('us-')), len(names))
last_baseline = max((i for i, n in enumerate(names) if n.startswith('baseline-')), default=-1)
assert last_baseline < first_us, f'baseline scenarios must precede us- scenarios; last_baseline_index={last_baseline}, first_us_index={first_us}'
"

# Five us-* scenarios — one per user story (US-1, US-2, US-3a, US-3b, US-4)
python3 -c "
import json
d = json.load(open('skills/charter/evals/evals.json'))
names = [s['name'] for s in d['evals']]
us_names = [n for n in names if n.startswith('us-')]
assert len(us_names) == 5, f'expected 5 us- scenarios, got {len(us_names)}: {us_names}'
"

# Each user story tag present (substring match, case-insensitive on the file body)
grep -qiE '(us-1|cold.standalone|full-run)' skills/charter/evals/evals.json
grep -qiE '(us-2|re.evaluation)' skills/charter/evals/evals.json
grep -qiE '(us-3a|rejection)' skills/charter/evals/evals.json
grep -qiE '(us-3b|abandonment)' skills/charter/evals/evals.json
grep -qiE '(us-4|manual.fallback|reviewer.redirect)' skills/charter/evals/evals.json

# Baseline scenarios present (substring match)
grep -qE '(baseline-slug-rejection|slug.rejection)' skills/charter/evals/evals.json
grep -qE '(baseline-malformed-state|malformed)' skills/charter/evals/evals.json
grep -qE '(baseline-child-internals-isolation|child.internals|isolation)' skills/charter/evals/evals.json
grep -qE '(baseline-visibility-default|visibility|Repo Visibility)' skills/charter/evals/evals.json

# Baseline scenario assertions cover load-bearing contract content
grep -qF '^[a-z0-9-]+$' skills/charter/evals/evals.json
grep -qF 'Discard' skills/charter/evals/evals.json
grep -qF 'Default to Private if unknown' skills/charter/evals/evals.json
grep -qE '(wip/research|child internal|child.internals)' skills/charter/evals/evals.json

# US-2 vocabulary check (positive substrings + negative "Continue / Start fresh")
grep -qiE 'Re-evaluate' skills/charter/evals/evals.json
grep -qiE 'Revise' skills/charter/evals/evals.json
grep -qiE 'Bail' skills/charter/evals/evals.json

# US-3b abandonment-forced HTML-comment marker name
grep -qF 'charter-status-block: abandonment-forced' skills/charter/evals/evals.json

# US-3a Decision Record path shape
grep -qE 'DECISION-strategy-.*-rejection' skills/charter/evals/evals.json
grep -qE 'DECISION-strategy-.*-re-evaluation' skills/charter/evals/evals.json

# US-4 drift-detection assertions and three-option staleness prompt
grep -qiE '(content_hash|git hash-object|blob hash)' skills/charter/evals/evals.json
grep -qiE '(Re-run|Accept|Proceed without)' skills/charter/evals/evals.json

# Public-repo discipline: use the test-topic slug (not a private slug)
grep -qF 'test-topic' skills/charter/evals/evals.json

# Each scenario expectations array has at least 3 items
python3 -c "
import json
d = json.load(open('skills/charter/evals/evals.json'))
for s in d['evals']:
    n = len(s['expectations'])
    assert n >= 3, f\"scenario {s['name']} has only {n} expectations; need at least 3\"
"

echo "All validations passed"
```

## Dependencies

Blocked by `<<ISSUE:2>>`, `<<ISSUE:3>>`, `<<ISSUE:4>>`, `<<ISSUE:5>>`, `<<ISSUE:6>>`, `<<ISSUE:7>>`, `<<ISSUE:8>>`. Evals assert behaviors documented in SKILL.md and the phase-prose reference files authored across those prior issues; the assertions cannot be authored until the prose they assert against exists on disk. Issue 1 is transitively required (via every prior issue's dependency on the pattern-level references) but does not appear as a direct blocker here.

Specifically:

- `<<ISSUE:2>>` authors `skills/charter/SKILL.md` + Phase 0 setup (slug regex `^[a-z0-9-]+$`, Input Modes, cold-start prompt) — required for the `baseline-slug-rejection` scenario assertions.
- `<<ISSUE:3>>` authors Phase 1 discovery prose + visibility detection + manual-fallback rule — required for the `baseline-visibility-default` (R12 default-Private + warning phrase) and `us-4-manual-fallback-reviewer-redirect` (R13 non-interference) scenarios.
- `<<ISSUE:4>>` authors child-invocation logic + chain-proposal confirmation prompt — required for the `us-1-cold-standalone-full-run` scenario (which children fire under which conditions).
- `<<ISSUE:5>>` authors the state-file schema at `wip/charter_<topic>_state.md` (5-field minimum + `/charter`-specific extensions) and the R9 hard finalization check — required for every user-story scenario's state-file assertions and the `baseline-malformed-state` scenario.
- `<<ISSUE:6>>` authors the 10-row resume ladder, dual-check drift detection, 7-day stale-session boundary, malformed-state hard error, and R14 child-internals isolation — required for the `baseline-malformed-state`, `baseline-child-internals-isolation`, `us-3b-abandonment-forced`, and `us-4-manual-fallback-reviewer-redirect` scenarios.
- `<<ISSUE:7>>` authors the three exit-path orchestration (full-run, re-evaluation, abandonment-forced) + R8 tie-break — required for every user-story scenario's exit-field assertion.
- `<<ISSUE:8>>` authors the Decision Record templates (re-evaluation + rejection sub-shapes) and the abandonment-forced HTML-comment marker — required for the `us-2-re-evaluation`, `us-3a-rejection-sub-shape`, and `us-3b-abandonment-forced` scenarios' artifact-path assertions.

## Downstream Dependencies

None — this issue is a leaf node. After it lands, `/charter` is implementation-complete for the purposes of this plan. Future work `/scope` and `/work-on` will copy-and-adapt the four baseline scenarios from this file per Design Decision 4's canonical-source contract; this is an out-of-plan deliverable but the canonical-source delimiter discipline authored here is the contract those future parents inherit.

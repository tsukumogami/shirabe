---
name: review-plan
description: >-
  Attack a finished plan before anyone files issues from it: whether it covers
  the design it claims to, whether its acceptance criteria would catch a wrong
  implementation, whether the scope drifted, and whether the order holds. Use
  it when someone hands you a plan and wants to know if it is any good — "is
  this broken down right?", "does this plan actually cover the design?",
  "these acceptance criteria feel weak", "did we miss anything?", "is this too
  many issues?" — or when you are about to turn a plan into issues and nobody
  has challenged it yet. The question it asks is not "does the plan cover the
  design?" but "would this plan catch the wrong implementation?", and criteria
  that pass either way are the failure it exists to find. `/plan` already runs
  it on plans it writes, so the case for reaching for it deliberately is a
  plan you did not just author. Do NOT use it to write or decompose a plan
  (`/plan`, `/scope`) or to review code.
argument-hint: '<plan-artifact-or-topic> [--adversarial]'
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh review-plan 2>&1 || true`

# Review Plan Skill

`/review-plan` adversarially challenges a complete plan artifact before any issues
are created. It runs four review categories against the plan's working keys (or,
with no plan session, the PLAN document alone) and the upstream design doc, then
writes a structured verdict to one of two keys depending on outcome.

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Overview

The skill sits between `/plan` Phase 5 (Dependencies) and Phase 7 (Creation). It
asks not "does the plan cover the design?" but "would this plan catch the wrong
implementation?" Four categories map to the three failure modes identified in
issue #19:

| Category | Name | Failure mode covered |
|----------|------|---------------------|
| A | Scope Gate | Plan too large or too small for design complexity |
| B | Design Fidelity | Plan inherits a contradiction from the design doc |
| C | AC Discriminability | ACs pass for the wrong implementation |
| D | Sequencing/Priority Integrity | Must-run QA scenarios are deprioritized |

## Session and Keys

`/review-plan` names its state with `/plan`'s prefix, so under
`${CLAUDE_PLUGIN_ROOT}/references/skill-session-convention.md` it reads and
writes `/plan`'s session, `plan-<topic>`, and has no session of its own. It
writes no file to the staging folder.

| Key in `plan-<topic>` | Read or written | Holds |
|-----------------------|-----------------|-------|
| `work/analysis.md`, `work/decomposition.md`, `work/manifest.json`, `work/dependencies.md`, `work/issue_<id>_body.md` | read (Phase 0); removed back to the loop target on loop-back (Phase 6) | `/plan`'s artifacts under review |
| `work/review.md` | written (Phase 5) | a proceed verdict |
| `work/review_loopback.md` | written (Phase 5) | a loop-back verdict |

Phase 0 picks one of three cases from `skill-session.sh status plan-<topic>`
and the keys it holds:

- **Run by `/plan`** (a sub-operation, `plan_topic` in its args): `/plan` has
  `plan-<topic>` open. `/review-plan` reads and writes it, and opens, adopts
  and closes nothing.
- **Run directly on a plan in flight** (`plan-<topic>` is `live` and holds
  `/plan`'s keys): the same reads and writes; the session belongs to `/plan`,
  which closes it, so `/review-plan` closes nothing.
- **Run directly on a topic with no plan session** (`absent` or `finished`):
  it reviews the PLAN document alone (`docs/plans/PLAN-<topic>.md`), opens
  `plan-<topic>` to write its verdict, and closes it when it finishes, since it
  opened it:

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" open plan <topic>
  "${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" adopt plan <topic>
  # ... Phases 1 to 5 ...
  "${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" close plan-<topic> done
  ```

  When `adopt` prints `adopted=scope-<topic>` (a `/scope` run has dispatched
  `/plan` on this topic), the session belongs to that chain: write the verdict
  and close nothing, since a session under a parent is the parent's to close.

Keys are read with `koto context get plan-<topic> <key>`, tested with `koto
context exists plan-<topic> <key>`, written with `koto context add
plan-<topic> <key>` (content on stdin), listed with `koto context list
plan-<topic> --prefix <prefix>`, and removed with `koto context remove
plan-<topic> <key>`. Review agents never write keys: they return findings to
this conversation, and the packet they read is materialized into a
`skill-session.sh scratch` directory (`skill-session.sh get`).

## Execution Modes

### Fast-path (default)

Called as a sub-operation by `/plan` Phase 6. One agent evaluates each category.
Optimized for latency — same coverage as adversarial mode, lower depth.

Invoked via Agent task with:
```
skill: review-plan
args:
  plan_topic: <topic>
  round: <N>
  mode: fast-path
```

Each of the four review categories (phases 1–4) runs with a single agent. The agent
applies heuristic pattern checks and taxonomy-anchored adversarial reasoning within
a single call. Phase 5 synthesizes all category findings into the verdict.

When a category's agent is spawned rather than run inline, it is commissioned as a
validator seat, as **Seat commissioning** below says.

### Adversarial (standalone)

Called directly by the user with `--adversarial`. Multiple validator agents
independently challenge the plan per category; all validators complete before
cross-examination runs; disagreements are resolved before producing a per-category
verdict. Use when thoroughness matters more than speed.

Invoked as:
```bash
/review-plan <plan-artifact-or-topic> [--adversarial]
```

## Adversarial Mode: Multi-Agent Bakeoff

When running in adversarial mode, each review category (phases 1–4) runs through
a three-step sequence before producing findings.

### Step 1: Spawn Validator Agents

For each category, spawn three independent validator agents in parallel. Each agent:

- Receives the same inputs (plan artifacts, issue bodies, upstream design doc)
- Reads the same phase reference file for its category
- Applies the full check independently, without seeing other validators' findings
- Returns its findings in `critical_findings` format

Spawn all three agents for all four categories in a single message (12 agents total)
to minimize wall-clock time. Each agent runs with `run_in_background: true`.

**Seat commissioning** (per `${CLAUDE_PLUGIN_ROOT}/references/review-seat-commissioning.md`): validators run on `model: "sonnet"` with a 10-call budget, and cross-examination agents on `model: "sonnet"` with a 6-call budget. Packet: `"${CLAUDE_PLUGIN_ROOT}/scripts/review-packet.sh" doc --doc <decomposition-artifact> --format skills/review-plan/references/phases/<category-phase-file> --extra <analysis-artifact> --extra <dependencies-artifact> --extra <upstream-design-doc> --extra <issue-body-file> ...`, one per category. The artifacts are the keys `references/phases/phase-0-setup.md` lists, materialized into a scratch directory with `skill-session.sh get` (step 0.4); with no plan session, `--doc` is the PLAN document and there are no extras but the upstream doc. `<category-phase-file>` is the category's phase reference. A cross-examination agent gets the same packet plus the disagreeing findings.

### Step 2: Collect and Compare

After all validators complete, for each category:

1. Collect findings from all three validators
2. Identify agreements: findings where ≥2 validators independently name the same
   issue (same issue ID, same pattern or description)
3. Identify disagreements: findings named by only one validator

**Agreements are confirmed findings** — proceed directly to the verdict.

**Disagreements require cross-examination** (step 3).

### Step 3: Cross-Examination

For each disagreement within a category:

Spawn a cross-examination agent that receives:
- The disagreeing validator's finding
- The other validators' outputs (including their absence of a finding for the same item)
- The phase reference file for this category
- The prompt: "One validator flagged [finding]. The other two did not. Evaluate
  whether the finding is valid. If valid, confirm it and describe the gap. If not,
  explain why it is a false positive."

The cross-examination agent produces a resolution: confirm or dismiss.

**Confirmed disagreements** are added to the category's findings.
**Dismissed disagreements** are dropped.

After cross-examination, all confirmed findings (from agreements + resolved
disagreements) form the category's final output for Phase 5 synthesis.

### Output Schema

Both fast-path and adversarial modes produce the same `review_result` YAML schema.
The verdict file format, field names, and loop-back behavior are identical. The only
difference is evaluation depth — adversarial mode's multi-agent bakeoff catches more
findings at the cost of significantly higher latency.

## Verdict Artifacts

Phase 5 writes the verdict key; `references/phases/phase-5-verdict.md` says which
key each verdict gets. See `references/templates/review-result-schema.md` for the
`review_result` YAML schema and its full field specification.

## Resume Logic

```
if key work/review.md exists in plan-<topic>          → skip to Phase 7 (already reviewed, proceed)
if key work/review_loopback.md exists in plan-<topic> → Phase 5 already wrote the verdict; execute loop-back
else                                                   → start at Phase 0
```

## Reference Files

| File | When to load |
|------|-------------|
| `references/phases/phase-0-setup.md` | Phase 0 |
| `references/phases/phase-1-scope-gate.md` | Phase 1 |
| `references/phases/phase-2-design-fidelity.md` | Phase 2 |
| `references/phases/phase-3-ac-discriminability.md` | Phase 3 |
| `references/phases/phase-4-sequencing.md` | Phase 4 |
| `references/phases/phase-5-verdict.md` | Phase 5 |
| `references/phases/phase-6-loop-back.md` | Phase 6 (loop-back only) |
| `references/templates/review-result-schema.md` | Phases 1–5 (finding format) |
| `references/templates/ac-discriminability-taxonomy.md` | Phase 3, before Pass 1 |

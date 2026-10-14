---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-functional-steps.md
problem: |
  shirabe has one plan version, plan/v1, whose entries are issues, and every
  tool that reads plans assumes it: the validator, the one outline parser
  behind `shirabe plan outlines`, task extraction, and the /scope, /execute
  and /work-on scripts that read plan bodies. A plan of functional steps
  (skeleton first, behavioural criteria, one-line later steps) needs a second
  version those tools accept without changing anything for plan/v1.
decision: |
  Add plan/v2 the way roadmap/v2 was added: the Plan spec accepts a second
  schema and version-gated code applies the step rules (a new FC22 check).
  The one outline parser learns `## Steps` / `### Step N:` and reports, per
  step, whether it is detailed, so `plan outlines`, task extraction and the
  scripts built on them read both versions through one walk. /work-on refuses
  an outline step at its plan-validation state; a new lifecycle check (L10)
  blocks completion while an outline step remains. /plan selects the version
  by flag, then a CLAUDE.md header, then a default of v1 held in one script.
  /review-plan gains a fifth category for step shape.
rationale: |
  Following the roadmap/v2 precedent keeps prefix routing and every plan/v1
  check unchanged, which is the main risk. Teaching the one parser rather
  than each reader avoids the drift the parser was created to end. Refusing
  outline steps where the step's work starts matches when the plan's owner
  details it: tasks are spawned up front, but each child reads its step from
  the plan at start. A one-place default lets the flip wait for the
  checkpoint-wording comparison as a one-line change.
decision_provenance: inline-resolved
---

# DESIGN: functional steps

## Status

Proposed

## Context and Problem Statement

The PRD (`docs/prds/PRD-functional-steps.md`) settles what `plan/v2` is: a
plan whose entries are steps (`### Step <N>: <title>` under `## Steps`, a
`step_count` field), each either detailed (goal, behavioural acceptance
criteria, a check, dependencies) or an outline of exactly one line, with step
1 detailed as a walking skeleton and the detailed steps forming a prefix.
`plan/v2` supports `single-pr` and `multi-pr` at `tracking_level: none`.
This design decides how shirabe's tools come to read and write it.

Every reader today assumes `plan/v1`. A survey of the repository found these
places that parse plan content or match the schema:

| Reader | What it reads | On `plan/v2` today |
|---|---|---|
| `crates/shirabe-validate/src/formats.rs` (Plan spec, `accepts_schema`) | schema, fields, sections | SCHEMA notice, nothing else checked |
| `crates/shirabe-validate/src/checks.rs` (FC04, FC05-FC09, FC11, FC12, FC14, FC15, FC17) | sections, table, outlines | n/a (never reached) |
| `crates/shirabe-validate/src/table.rs` `parse_issue_outlines` | `## Issue Outlines`, `### Issue N:` | empty section |
| `crates/shirabe-validate/src/lifecycle.rs` (L01, L06, L09) | posture, outline ACs | treats as issue-carrying |
| `crates/shirabe/src/plan_outlines.rs` (`shirabe plan outlines`) | schema, outlines | refuses: not `plan/v1` |
| `skills/plan/scripts/plan-to-tasks.sh` | schema, mode, table or outlines | refuses: not `plan/v1` |
| `skills/scope/scripts/hop-complete.sh` | schema per hop | plan hop incomplete |
| `skills/scope/scripts/startable-issues.sh` | titles from table or outlines | empty |
| `skills/scope/scripts/publish-scoping-pr.sh` | work-item titles for the PR body | empty |
| `skills/execute/scripts/node-push.sh` (`work_item_goal`) | outline `**Goal**:` | empty |
| `skills/execute/scripts/drift-facts.sh` | Scope Summary, outline goals, `**Files**:` | goals missing |
| `skills/work-on/scripts/work-on-open.sh` | `schema: plan/v1` for non-`PLAN-` names | not detected as a plan |
| `skills/work-on/scripts/find-anchor-plan.sh` | `#N` table rows | nothing (correct: `plan/v2` files no issues) |
| `skills/work-on/koto-templates/work-on.md` (`plan_context_injection`, `plan_validation`) | the outline, by instruction | reads whatever is there |

Frontmatter-only readers (`scripts/plan-mode.sh`, `execute-open.sh`,
`check-plan-filing.sh`, `check-plan-mode.sh`, `record-scope-exit.sh`) read
`execution_mode` and `tracking_level`, which `plan/v2` keeps, so they need no
change. Nothing under `skills/coordinate/` parses a plan body: its scripts
match a `PLAN-*.md` path or read the recorded execution mode.

koto parses no plan content. It handles plans only as paths: decider and
template variables such as `PLAN_DOC` with the `plan_path` label
(`src/cli/decider_port.rs`, `src/template/decider.rs`, the label fixtures in
`src/decider/request.rs`) and a plan-path variable in the koto-author
batch-coordinator example. A path is the same string whatever the plan's
version, so koto accepts both versions as it stands and needs no change.

## Decision Drivers

- No `plan/v1` behaviour changes: same validator output on existing
  fixtures, every existing suite passes unchanged (PRD R15).
- One parse of plan entries. `shirabe plan outlines` exists because two
  parsers drifted; a second step parser would reopen that.
- A reader that cannot read `plan/v2` must say so, never return nothing
  (PRD R14).
- The plan's owner details step N+1 after step N's work reaches its terminal
  and before step N+1's starts, and `/execute` spawns its children up front,
  so whatever refuses an outline has to run when the step's work starts.
- The default changes later, by a one-line edit (PRD R10).
- Shell scripts run on bash 3.2; no new runtime dependency.

## Considered Options

### Decision 1: how the validator carries `plan/v2`

**Chosen: one Plan spec accepting both schemas, with version-gated rules.**
`FormatSpec::accepts_schema` gains a `plan/v2` disjunct, as it did for
`roadmap/v2`. FC01 and FC04/FC15 read the field list and section list for the
document's version; the table and diagram checks (FC05-FC09, FC11, FC12)
skip `plan/v2`, which has no table; FC14's sub-check F accepts `### Step N:`
under `plan/v2`; a new FC22 carries the step rules (PRD R1-R4, R7).
Provenance: inline.

Alternatives considered:
- *A second `FormatSpec` with prefix `PLAN-`.* Rejected: prefix routing picks
  one spec per filename, so two specs for one prefix need a schema-aware
  router, a larger change than the disjunct, and it duplicates every shared
  Plan field (lifetime, legal upstreams, statuses).
- *Fold the step rules into FC14.* Rejected: FC14 is the outline/table mutual
  exclusion check with notice-level sub-checks; the step rules are
  error-level and selectable on their own, which a separate code gives.

### Decision 2: where readers get the step list

**Chosen: the one outline parser learns steps.** `parse_issue_outlines`
locates `## Steps` and matches `### Step <N>:` when the document's schema is
`plan/v2`, resolves `Step <N>` dependency references, and records per block
whether it declared `**Check**:` and how many non-blank body lines it has.
A block is detailed when it declares a goal, criteria and a check, and an
outline when its body is one line. `shirabe plan outlines` accepts both
schemas and adds `entry` (`issue` or `step`), `detailed` and
`check_declared` to each block, keeping the envelope id
`shirabe-plan-outlines/v1` because the change is additive and consumers read
by name. `plan-to-tasks.sh` and the shell readers above read entries
through it (or match both heading forms where they read prose directly).
Provenance: inline.

Alternatives considered:
- *Each reader parses `## Steps` itself.* Rejected: eight readers with eight
  regexes is the drift the one parser was built to end.
- *Convert a `plan/v2` document to `plan/v1` text before reading.* Rejected:
  the readers would then report issues where the document says steps, and
  outline steps have no criteria to convert.

### Decision 3: where an outline step is refused

**Chosen: the `/work-on` child, at `plan_validation`.** `plan-to-tasks.sh`
emits one task per step, detailed or not, so `/execute` builds the same
dependency graph it builds for `plan/v1`. When a step's child starts, it
reads its step from the plan as committed at that moment; a new script,
`skills/work-on/scripts/step-detail-check.sh <plan> <step>`, exits non-zero
with `step <N> is an outline; the plan's owner details it before its work
starts` when the step is still one line, and `plan_validation` submits
`verdict: exit` with that message. Once the owner details and commits the
step, rerunning the child passes the check and reads the detailed text.
Provenance: inline.

Alternatives considered:
- *Task extraction emits only detailed steps.* Rejected: the graph would
  lose the later steps, so a run could finish "complete" with outlines left,
  and detailing would need a new `/execute` run.
- *`/execute` refuses a plan with outline steps.* Rejected: a step plan
  always has outlines at the start; this would make `plan/v2` unrunnable.

### Decision 4: selecting the version

**Chosen: `--plan-version=v1|v2`, then `## Plan Version: v1|v2` in CLAUDE.md,
then the default.** A new script, `skills/plan/scripts/resolve-plan-version.sh`,
resolves the three in that order, refuses any other value naming `v1` and
`v2`, and holds the default as `DEFAULT_PLAN_VERSION=v1` on one line. `/plan`
runs it in Phase 1 and records the result; Phases 3, 4 and 7 branch on it.
Provenance: inline.

Alternatives considered:
- *A `--steps` boolean flag.* Rejected: it names the shape, not the version,
  and leaves no room for the explicit `v1` an author needs once the default
  flips.
- *Infer the version from the decomposition (walking skeleton means v2).*
  Rejected: the version is a format contract readers rely on and should be
  chosen, not inferred.

### Decision 5: how `/review-plan` judges step shape

**Chosen: a fifth category, E (Functional Shape), applied by the review
agent with the PRD's definitions, on plans of either version.** It reports a
layer-shaped plan (naming the entries and the components they are cut by), a
first entry that is not a walking skeleton (its check is not observed end to
end), each file-shaped criterion (by entry and text, ignoring `**Files**:`
lines), and, when run inside `/plan`, a `plan/v2` plan with more than two
detailed steps. Findings use the existing `review_result` schema with
category `E`; a layer-shaped plan or a non-skeleton first step under
`plan/v2` is a loop-back finding, and under `plan/v1` an advisory one, so
existing `plan/v1` plans are flagged without being sent back.
Provenance: inline.

Alternatives considered:
- *Extend Category C (AC Discriminability).* Rejected: C asks whether a
  criterion would pass for a wrong implementation; file shape is a different
  question, and the layer test reads the whole plan, not one criterion.
- *A deterministic script for file-shaped criteria.* Rejected for now: a
  regex flags "`validate` exits 2" as file-shaped as readily as "add
  `parse_step`"; the definitions give the agent a rule it can apply, and the
  fixtures pin the expected findings.

### Decision 6: refusing completion with outline steps left

**Chosen: a new lifecycle check, L10.** Under `plan/v2`, an outline step in
a plan whose chain is being finalized is an error naming the step, raised by
the same lifecycle run `run-cascade.sh` already makes before it deletes the
plan, so the cascade stops there. L06 (unticked outline criteria) applies to
`plan/v2` detailed steps unchanged. Provenance: inline.

Alternatives considered:
- *Refuse in `run-cascade.sh` itself.* Rejected: the cascade defers
  per-document rules to the lifecycle check; a script-side rule would be a
  second place to look.

## Decision Outcome

`plan/v2` lands as a second schema of the existing Plan format. One parser
reads both versions' entries, so the validator, `shirabe plan outlines`, task
extraction and the shell readers agree on what a step is. `/plan` writes
`plan/v2` only when asked until the default flips. `/execute` drives a step
plan with the graph it already builds; each step's child refuses to start
from an outline, which is where the owner's detailing has to have happened.
Completion waits until no outline is left. `/review-plan` flags layer shape
and file-shaped criteria in plans of either version.

## Solution Architecture

### The `plan/v2` format

```yaml
---
schema: plan/v2
status: Active
execution_mode: single-pr        # single-pr | multi-pr
upstream: docs/designs/DESIGN-<topic>.md
milestone: "<name>"
step_count: 5
---
```

Required sections, in order: `Status`, `Scope Summary`, `Decomposition
Strategy`, `Steps`. `Implementation Sequence` is optional (the step order is
the sequence). `tracking_level` is absent or `none`; `split_rationale`
follows the `plan/v1` rule.

```markdown
## Steps

### Step 1: <behaviour, end to end>

**Goal**: <the integration crossed and the input it runs on>

**Acceptance Criteria**:
- [ ] <observable result>

**Check**: <command, test or walkthrough, and the result that shows it>

**Dependencies**: None

**Files**: `path/a`, `path/b`          # optional hint

### Step 2: <behaviour>
... detailed ...

### Step 3: <behaviour>

<one line: the behaviour this step will add>
```

`**Dependencies**:` is `None` or `Step <N>` references separated by commas,
each naming an earlier step. `**Type**:` and `**Complexity**:` keep their
`plan/v1` meaning.

The plan format reference states the horizon and its rule (PRD R5): at
authoring, steps 1 and 2 are detailed (every step when there are two or
fewer); the plan's owner details step N+1 after step N's work reaches its
terminal and before step N+1's starts, rewrites any outline whose behaviour
changed, and commits that edit alone, touching only the plan; a worker never
edits a step's heading, outline or detail. It also states the report rule
(PRD R17): a step's report names the behaviour this step added and the check
that shows it, with the check's result.

### Validator

- `formats.rs`: `accepts_schema` accepts `plan/v2` for the Plan spec. A
  helper returns the version's required fields (`step_count` replaces
  `issue_count`) and required sections.
- `checks.rs`: FC01, FC04 and FC15 use the version's lists. FC05-FC09, FC11
  and FC12 return early on `plan/v2`. FC14 sub-check F accepts `### Step N:`
  under `plan/v2`. FC17 (unresolved dependency) reads the parser's resolution
  for both versions.
- New **FC22 (step plan)**, error level, `plan/v2` only, one finding per
  violation, each naming the step and rule: an `### Issue` heading or other
  non-step heading under `## Steps`; numbering not 1..n without gaps;
  `step_count` not equal to the steps present; `issue_count` present; step 1
  an outline; a detailed step missing `**Goal**:`, a checkbox criterion or
  `**Check**:`; an outline step with more than one non-blank line; a detailed
  step after an outline step; a dependency on a later or missing step or a
  malformed `**Dependencies**:` value; `execution_mode: coordinated` or a
  `tracking_level` other than `none` (both messages name `plan/v1`).
- `lifecycle.rs`: `plan/v2` is outline-shaped for L01's posture; new **L10**
  reports each outline step when the chain is finalized.
- `validate.rs`: FC22 and L10 join the known codes and the Plan dispatch.

### Parser and `shirabe plan outlines`

`table.rs`: the section locator and heading regex are chosen by schema
(`## Issue Outlines` / `Issue` for `plan/v1`, `## Steps` / `Step` for
`plan/v2`); dependency references resolve `Step <N>` under `plan/v2`;
`OutlineBlock` gains `entry`, `check_declared`, `body_lines` and a derived
`detailed`. `plan_outlines.rs` accepts both schemas and emits the new fields.

### Scripts

| Script | Change |
|---|---|
| `skills/plan/scripts/plan-to-tasks.sh` | accept `plan/v2`; build tasks from `plan outlines` for both supported modes; name tasks `step-<N>`; carry `detailed` in the task vars |
| `skills/plan/scripts/resolve-plan-version.sh` (new) | flag > header > `DEFAULT_PLAN_VERSION=v1`; refuse other values |
| `skills/scope/scripts/hop-complete.sh` | plan hop accepts `plan/v1` or `plan/v2` |
| `skills/scope/scripts/startable-issues.sh` | read titles of both heading forms; report step titles |
| `skills/scope/scripts/publish-scoping-pr.sh` | list `### Step N:` titles in the PR body |
| `skills/execute/scripts/node-push.sh` | `work_item_goal` reads a step's goal, or its outline line |
| `skills/execute/scripts/drift-facts.sh` | collect step goals and `**Files**:` |
| `skills/work-on/scripts/work-on-open.sh` | detect `schema: plan/v2` |
| `skills/work-on/scripts/step-detail-check.sh` (new) | exit non-zero, naming the step, when it is an outline |
| `skills/work-on/koto-templates/work-on.md` | `plan_context_injection` extracts a step; `plan_validation` runs the check and exits on an outline; the step report names the behaviour |

`find-anchor-plan.sh` is unchanged: it finds the plan that tracks a GitHub
issue through table rows, and a `plan/v2` plan tracks none.

### Skills

- `/plan`: `SKILL.md` (flag, header, horizon), `references/plan-format.md`
  (a `plan/v2` section with the format, horizon, owner rule and report
  rule), `references/quality/plan-doc-structure.md` and
  `plan-doc-examples.md` (a step example), `phases/phase-1-analysis.md`
  (resolve the version), `phases/phase-3-decomposition.md` (step
  decomposition: skeleton first, behavioural criteria, outlines after step
  2), `phases/phase-4-agent-generation.md` and `phase-7-creation.md` (write
  `plan/v2`, `step_count`, no issue filing), a new
  `references/templates/step.md`, and `evals/evals.json`.
- `/review-plan`: `SKILL.md` (category E), a new
  `references/phases/phase-4b-functional-shape.md`, `phase-0-setup.md`
  (read `step_count` and `## Steps`), `phase-5-verdict.md` and
  `references/templates/review-result-schema.md` (category E), and
  `evals/evals.json`.
- `/work-on`: `SKILL.md` (a plan step's report names the behaviour this
  step added and its check).
- `/execute`: `SKILL.md` (accepts both versions; an outline step's child
  stops until the owner details it).

No file under `skills/coordinate/` changes, and the brief template's
checkpoint wording stays as it is.

### Fixtures

A `plan/v1` fixture copied from koto's evidence-routing plan (five entries:
types, compiler, CLI, tests, plugin templates), with its source named in a
header comment; a valid `plan/v2` fixture with and without `**Files**:`; one
invalid `plan/v2` fixture per FC22 rule; a `plan/v2` fixture whose step 1
adds types only; a `plan/v2` fixture with three detailed steps. The Rust
tests and the script suites read them.

### The checkpoint-wording comparison

This is what the dispatching coordinator needs to answer, before either
default changes, whether artifact-shaped checkpoint reports come from layered
plans or from how a brief words its checkpoints.

- **Qualifying plans.** Two upcoming units whose plans are `plan/v1` with
  three or more entries and that `/review-plan` reports as layer-shaped
  (category E), each run once. The control is two earlier runs of
  layer-shaped plans under today's wording, whose checkpoint reports are on
  record.
- **The one change.** The briefs for the two runs are identical to today's
  except their `## Checkpoints` items. Today's wording names artifacts, for
  example "The scoping pull request is open." and "The pull request is ready
  with every CI job green, read job by job." The behavioural wording names a
  behaviour and its check, for example "Step <N> works: report the behaviour
  this step added and the command or check that shows it, with its result."
  for each step, keeping the final "ready with every CI job green" item.
  Nothing else in the brief, the plan or the execution mode changes.
- **What is compared.** Every checkpoint report in the four runs, sentence
  by sentence: behaviour-shaped (names an observable result and the check
  that produced it) or artifact-shaped (names files, commits, pull requests
  or green jobs without a behaviour). The measure is the share of
  behaviour-shaped sentences per run.
- **The record.** A table in the coordinator's own record: run, plan, shape
  (layered), wording (artifact or behaviour), reports counted, share
  behaviour-shaped, and a one-line reading saying which change moved the
  reports. If the behavioural wording moves layered plans' reports, the
  wording is the lever; if it does not, the plan shape is.

The default plan version (`DEFAULT_PLAN_VERSION=v1`) and the brief template's
checkpoint wording stay as they are until that record exists.

## Implementation Approach

Build it as functional steps, each leaving the tools working:

1. **Walking skeleton:** a minimal `plan/v2` document validates with
   `shirabe validate`, `shirabe plan outlines` lists its steps with
   `detailed`, and `plan-to-tasks.sh` turns it into tasks; existing `plan/v1`
   suites pass.
2. **Step rules:** FC22 and the version-aware FC01/FC04/FC15 refuse every
   invalid fixture with a message naming the step and rule.
3. **Authoring:** `/plan --plan-version=v2` (or the header) writes a step
   plan, the default stays `v1`, and the format reference states the horizon,
   owner rule and report rule.
4. **Execution:** `/execute` and `/work-on` drive a step plan; an outline
   step's child stops naming the step; the `/scope` and `/execute` readers
   report step titles and goals.
5. **Review:** `/review-plan` category E flags the five-layer fixture and
   its file-shaped criteria and passes the behavioural fixture.
6. **Completion:** L10 stops the cascade on a plan with an outline step.

## Security Considerations

The feature parses Markdown documents the repository already trusts and
adds no network access, credential handling or new process boundary.
Three points need care:

- **Parsing untrusted text.** Plan bodies reach the parser and the shell
  readers. The parser is regex-based on bounded lines, as today. The shell
  readers pass step titles and goals as data (`jq --arg`, `printf '%s'`),
  never through `eval` or unquoted expansion, which the new and changed
  scripts keep.
- **Version selection input.** `--plan-version` and the CLAUDE.md header are
  matched against `v1` and `v2` exactly before use; any other value stops the
  run before a file is written, so the value never reaches a path or a
  command.
- **Refusal messages.** The outline-step refusal and FC22 messages quote a
  step number and rule, not arbitrary step text, so a crafted title cannot
  inject into a koto evidence field or a PR body beyond what titles already
  reach today.

## Consequences

Positive:
- A step plan can be written, validated, executed and reviewed, and no
  `plan/v1` plan changes behaviour.
- One parser still owns what an entry is, now for both versions.
- The default flips with one line once the comparison reports.

Negative:
- The Plan spec carries version branches in several checks, as the Roadmap
  spec already does.
- `plan/v2` excludes coordinated plans and issue-per-step tracking, so
  repositories that need them stay on `plan/v1`.
- The horizon and the owner's detailing are guidance plus review, not a
  validator rule, so a plan can be detailed too far ahead and still validate.

Mitigations:
- Version-gated code paths are covered by `plan/v1` regression fixtures and
  per-rule `plan/v2` fixtures.
- `/review-plan` flags an over-detailed horizon at authoring, and L10 stops
  completion with outlines left.

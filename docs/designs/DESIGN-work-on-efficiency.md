---
status: Proposed
problem: |
  The work-on plan orchestrator drives all child issues through 10+ state
  transitions regardless of issue type or implementation status. Doc-only
  changes run three code-review panels (scrutiny, review, QA validation)
  that add overhead without benefit. Issues already implemented before the
  workflow runs traverse every state anyway. Plan-backed children incorrectly
  own their own PR. And two issues touching the same file can overwrite each
  other's work with no coordination mechanism. These inefficiencies were
  observed directly while executing the work-on-friction-fixes plan.
decision: |
  Add complexity-based routing to the child workflow template (docs vs. code
  fast path), a clean early-exit terminal state for pre-implemented work, a
  shared-PR signal for plan-backed children, an explicit file-conflict
  annotation in the PLAN format, and a template consistency CI check. All
  changes are shirabe-side; two koto engine gaps are recorded as feature
  requests. A one-line template fix corrects the hardcoded workflow name bug.
rationale: |
  Single-template routing preserves the existing graph structure without
  forking maintenance surface. Evidence-based approaches (pr_status: shared,
  issue_type at implementation) rely on agent convention but ship immediately;
  structural enforcement via template forks would double the states to maintain.
  Explicit annotations over static analysis avoids false positives that would
  degrade the parallelism the orchestrator provides.
---

# DESIGN: Work-on Orchestrator Efficiency

## Status

Proposed

## Context and Problem Statement

The work-on skill's plan orchestrator mode drives child issue workflows through
a fixed 10+ state sequence: entry → context injection → analysis → implementation
→ scrutiny → review → QA validation → finalization → PR creation → CI monitor →
done. This sequence was designed for code implementation and works well there.
It works poorly for two common cases: doc-only changes (where scrutiny, review,
and QA panels add overhead with no benefit) and issues already implemented by a
prior run (where all states are traversed even though no work remains).

Two structural bugs also surfaced during execution:

- **Plan-backed children own their own PR**: Child workflows drive through
  `pr_creation` even though the orchestrator owns the shared PR. Children work
  around this by finding the orchestrator's existing draft PR and submitting its
  URL. This is semantically incorrect and fails silently in edge cases.
- **Hardcoded workflow name**: The `spawn_and_await` directive scripts call
  `koto next work-on-plan` literally. Initializing the workflow under a different
  name (e.g., `my-feature-plan`) causes the directive to call the wrong target.

One coordination gap: two issues in the same plan can touch the same file
concurrently, with the second write silently overwriting the first. No mechanism
in the PLAN doc format or `plan-to-tasks.sh` prevents this.

Finally, the template's `batch_final_view` context key and gate key naming
conventions have discoverability gaps: `batch_final_view` is documented in
directives but absent from the koto binary; gate labels omit `.json` while
context keys include it, which isn't obvious to agents or template authors.

## Decision Drivers

- Minimize maintenance surface: forks double the states to maintain; single-template
  solutions are preferred.
- No koto engine changes required for shirabe-side fixes: `{{SESSION_NAME}}` is a
  built-in variable; two-field routing is supported today; `batch_final_view` is
  deferred to a koto feature request.
- Near-zero false positive rate for file-conflict detection: static analysis of
  prose generates spurious dependencies on commonly-referenced files like `SKILL.md`.
- Preserve parallelism: the orchestrator's value is concurrent execution; over-serializing
  issues via false conflict detection defeats the purpose.
- Structural enforcement is preferred, but agent convention is acceptable when the
  structural alternative costs significant maintenance overhead.

## Decisions Already Made

The following decisions were made during exploration and are treated as constraints:

- **Docs fast path: Option A** (two-field discrimination at `implementation`).
  Adding `issue_type: {docs, code}` to `implementation.accepts` and routing on both
  fields is less disruptive than a routing state (Option B) and avoids the maintenance
  cost of a separate template (Option C). Cost accepted: agent must re-submit `issue_type`
  at every `implementation` visit.

- **Plan-backed PR model: Approach a** (`pr_status: shared`). Adding a new enum value
  to `pr_creation` and routing to `done` is implementable today with no maintenance
  burden. The fork alternative (Approach b: `work-on-plan-backed.md`) would be
  structurally cleaner but doubles the states to maintain. Approach c (`is_set`
  operator in `when`) is not implementable — koto `when` conditions support only
  strict JSON equality; the command-gate workaround is blocked by the empty-string
  allowlist restriction on template variables.

- **File conflict annotation: optional, auto-add edges**. The `**Files**:` annotation
  in Issue Outlines is opt-in (not required on every plan). `plan-to-tasks.sh` auto-adds
  `waits_on` edges (rather than emitting warnings) when two outlines share a file. A
  warning is easier to ignore than a structural dependency.

- **CI checks: all three in a single script**. Mermaid state-set diff, `default_template`
  existence, and workflow-name-in-prose checks are bundled into `validate-template-mermaid.sh`.
  The context key directive check (Check 2 from the research) is deferred: its false-negative
  rate is high because most states delegate key naming to phase reference files.

## Considered Options

### Decision 1: Docs fast path implementation

**Context**: Doc-only issues (adding a section to `SKILL.md`, updating a template
directive) run through scrutiny, review, and QA validation — three additional state
transitions that add agent effort with no corresponding quality benefit. The question
is whether to skip these states for docs issues, and how.

**Option A — Two-field discrimination at `implementation` (chosen)**

Add `issue_type: {docs, code}` to `implementation.accepts`. Transitions from
`implementation` become:

```yaml
- target: scrutiny
  when:
    implementation_status: complete
    issue_type: code
- target: finalization
  when:
    implementation_status: complete
    issue_type: docs
```

The mutual exclusivity requirement is satisfied: both transitions share `issue_type`
with disjoint values. The plan orchestrator passes `issue_type` as an init variable
when spawning children, reading it from the PLAN doc's Issue Outline `**Type**:`
annotation.

**Option B — Post-analysis routing state**

Insert a `routing` state after `analysis` (the convergence point for all modes).
`routing` accepts `issue_type` and branches the graph into two paths: the full
code path and the short docs path. This is more legible in the state diagram but
adds a state with no directive logic, and the agent must submit an extra `koto next`
round at `routing`.

**Option C — Separate `work-on-docs.md` template**

The plan orchestrator selects `work-on-docs.md` for doc issues and `work-on.md`
for code issues. The fork is simpler in isolation but requires all changes to shared
states (analysis, finalization, PR creation, entry) to be applied twice. With 17
shared states, this is a real maintenance burden.

**Rejected**: Option B (extra state, no structural benefit over Option A). Option C
(maintenance cost outweighs clarity benefit).

---

### Decision 2: Pre-implemented work exit

**Context**: When analysis finds that all acceptance criteria are already satisfied
by prior commits, the agent has no path to exit cleanly. It must submit `plan_ready`
and proceed to `implementation`, which either produces empty commits or fails. The
only escape today is `scope_changed_escalate` → `done_blocked`, which is a failure
terminal — incorrect for "work was already done."

**Option A — Add `done_already_complete` terminal state (chosen)**

Three template changes to `work-on.md`:

1. Add `already_complete` to `analysis.accepts.plan_outcome.values`.
2. Add a transition `when: plan_outcome: already_complete → done_already_complete`.
3. Add a `done_already_complete` state with `terminal: true` and no `failure: true` flag.

No koto engine changes are needed: multiple non-failure terminal states are supported
(`done`, `validation_exit`, and `skipped_due_to_dep_failure` already demonstrate this).
The parent orchestrator's `batch_outcome: all_success` logic counts any terminal state
without `failure: true` as a success. The `analysis` phase instructions also need to be
updated to tell agents when and how to submit `already_complete` evidence.

**Option B — Reuse `validation_exit`**

`validation_exit` is a clean non-failure terminal already in the template (used in
free-form task validation). Routing `analysis → validation_exit` would avoid adding a
new state, but `validation_exit`'s semantics are "task validated before implementation"
— not "implementation confirmed already complete." Reusing it conflates two distinct
outcomes and would make the `batch_final_view` outcome table harder to interpret.

**Rejected**: Option B (semantic mismatch, confusion in orchestrator's outcome table).

---

### Decision 3: Plan-backed child PR handling

**Context**: Plan-backed children drive through `pr_creation` even though the
orchestrator owns the shared PR. Children work around this by finding the existing
draft PR and reporting its URL. This is semantically wrong and creates a silent failure
mode when no PR exists yet (the child would create a second PR).

**Option A — Add `pr_status: shared` enum value (chosen)**

Add `shared` to `pr_creation.accepts.pr_status.values`. Add a transition
`when: pr_status: shared → done`. The `pr_creation` directive instructs plan-backed
children (detectable via `SHARED_BRANCH` variable) to submit `pr_status: shared`
instead of creating a PR. Children skip `ci_monitor` and go directly to `done`.

This is agent convention: nothing in the template forces children to submit `shared`.
A child that incorrectly submits `created` with the orchestrator's URL will still
pass. But the directive makes the intended behavior explicit, reducing accidental
misuse.

**Option B — Fork to `work-on-plan-backed.md`**

A separate template with `finalization → done_plan_backed` directly, no `pr_creation`
or `ci_monitor` states. The orchestrator's `default_template` field points to the fork.
Structural enforcement: plan-backed children physically cannot reach `pr_creation`.

Rejected because: (1) the fork duplicates 17 states that must be kept in sync, (2) all
children in a plan-backed run are plan-backed, so the `default_template` field already
achieves full coverage — there's no per-child template selection. The structural benefit
doesn't justify the maintenance cost when all children use the same template anyway.

**Option C — Variable-based routing via command gate**

Add a gate `test -n "{{SHARED_BRANCH}}"` at `finalization` with `override_default:
exit_code: 1`. Route on `gates.shared_branch_set.exit_code` to either `done_plan_backed`
or `pr_creation`. This mechanically works but requires every `finalization_status` value
to have two transitions (doubling transition count) and is blocked by the empty-string
allowlist restriction when `SHARED_BRANCH` is not set at init time.

**Rejected**: Option B (maintenance cost), Option C (blocked by allowlist, combinatorial
transition explosion).

---

### Decision 4: Parallel file conflict prevention

**Context**: Two issues in the same plan can modify the same file concurrently. The
second agent to commit overwrites the first's work without warning. `plan-to-tasks.sh`
generates dependency edges only from explicit `**Dependencies**:` declarations, not
from file-level analysis.

**Option A — Static path extraction from outline prose**

Parse each Issue Outline for file-path-like strings (regex: `[a-z][a-z0-9_/-]*\.[a-z]{1,5}`).
Build a per-file index; auto-add `waits_on` edges for shared files. Infeasible as a
default-on behavior: commonly-referenced files like `SKILL.md` appear in multiple outlines
as context (not change targets), generating spurious serialization edges and defeating
the parallelism the orchestrator provides.

**Option B — Explicit `**Files**:` annotation (chosen)**

Add an optional `**Files**:` field to the Issue Outline format:

```
**Files**: `skills/work-on/SKILL.md`, `skills/work-on/koto-templates/work-on.md`
```

`plan-to-tasks.sh` parses backtick-quoted tokens on `**Files**:` lines, builds a
file-to-outline map, and auto-adds `waits_on` edges when two outlines share a file.
The field is optional: plan authors add it only when parallel file conflicts are
possible. False positive rate: near zero (author declares write targets explicitly).
False negative rate: non-zero (omission is human error, not tooling error).

Note: this approach does not prevent section-level conflicts (two agents editing
different sections of the same file). That requires a post-execution merge strategy
and is out of scope.

**Rejected**: Option A (false positive rate too high, degrades parallelism).

---

### Decision 5: Issue type propagation from PLAN to child workflow

**Context**: The docs fast path (Decision 1) requires `issue_type` to be passed to each
child workflow at initialization. The orchestrator must know the issue type from the PLAN
doc and inject it as a variable when spawning children.

**Option A — `**Type**:` annotation in Issue Outline (chosen)**

Add an optional `**Type**:` field to the Issue Outline format:

```
**Type**: docs
```

`plan-to-tasks.sh` reads this field and adds `issue_type` to the task's `vars` object.
The orchestrator's spawn directive passes it to `koto init` as `--var ISSUE_TYPE=<type>`.
The child workflow reads it as initial evidence or as a template variable.

Defaults to `code` when absent, preserving current behavior for existing plans.

**Option B — Infer from issue title or acceptance criteria keywords**

Keyword detection ("update SKILL.md", "add section", etc.) to auto-classify. False
positive and negative rates are both high: "update the CI script" might be classified
as docs, "add a new state to the template" might be classified as docs (it edits a
file), but the state change triggers template recompilation and needs code-path scrutiny.

**Rejected**: Option B (classification quality unreliable without explicit annotation).

---

### Decision 6: Template consistency CI enforcement

**Context**: Both mermaid files (`work-on.mermaid.md`, `work-on-plan.mermaid.md`) are
currently in sync with their YAML state machines, but nothing in CI enforces this
invariant. A future template edit could introduce drift without detection.

**Three checks chosen for a single `validate-template-mermaid.sh` script:**

1. **Mermaid/YAML state-set diff**: Extract state names from YAML frontmatter (awk
   between `states:` and `---`) and from mermaid `-->` transition lines. Sort and diff.
   Fails if any state is in YAML but not mermaid, or vice versa.

2. **`default_template` file existence**: For each template with a `default_template:`
   field, verify the named file exists in the same directory.

3. **Workflow name in `koto next` calls**: Extract `name:` from frontmatter; grep
   directive prose for `koto next <name>` patterns; compare. Catches the hardcoded-name
   class of bug.

**Check 4 (context key in directive prose) deferred**: Would require parsing phase
reference files as well as templates (most states delegate key naming to reference
files). The false-negative rate is too high to be meaningful without also scanning
`references/phases/`.

## Decision Outcome

Eight changes are in scope, grouped by component:

**`skills/work-on/koto-templates/work-on.md`**: Add `issue_type` field to `implementation`
accepts with two-field routing to `scrutiny` (code) or `finalization` (docs). Add
`already_complete` to `analysis` accepts with a transition to `done_already_complete`
terminal state. Add `shared` to `pr_creation` accepts with a transition to `done`.
Update `pr_creation` and `analysis` directives with the new paths.

**`skills/work-on/koto-templates/work-on-plan.md`**: Replace `koto next work-on-plan`
with `koto next {{SESSION_NAME}}` in both tick scripts of `spawn_and_await`. Update
the spawn directive to read `issue_type` from task vars and pass it as `--var ISSUE_TYPE=<type>`.

**`skills/work-on/SKILL.md`**: Document the `already_complete` analysis path and the
`pr_status: shared` plan-backed child convention.

**`skills/plan/references/quality/plan-doc-structure.md`**: Add `**Files**:` and
`**Type**:` as optional fields in the Issue Outline section.

**`skills/plan/scripts/plan-to-tasks.sh`**: Parse `**Files**:` to auto-add `waits_on`
edges for shared files. Parse `**Type**:` to populate `issue_type` in the vars object.

**`skills/work-on/references/phases/phase-3-analysis.md`** and
**`skills/work-on/references/agent-instructions/phase-3-analysis.md`**: Add guidance
for detecting pre-implemented work and submitting `already_complete` evidence.

**`.github/workflows/check-template-consistency.yml`** + **`scripts/validate-template-mermaid.sh`**:
New CI job triggering on `skills/*/koto-templates/**`. Runs three checks.

## Solution Architecture

### Child workflow routing (work-on.md)

The state machine adds three new paths, all using existing koto mechanisms:

```
analysis
  ├── plan_ready       → implementation
  ├── already_complete → done_already_complete  [NEW]
  └── ...              → done_blocked

implementation
  ├── complete + issue_type: code → scrutiny     [MODIFIED]
  ├── complete + issue_type: docs → finalization [NEW]
  └── ...

pr_creation
  ├── created          → ci_monitor
  ├── shared           → done              [NEW]
  └── ...
```

`done_already_complete` is a `terminal: true` state with no `failure: true` flag.
The parent orchestrator's `batch_outcome: all_success` logic treats it as a success.

`issue_type` is declared as a template variable (`required: false, default: code`) in
the frontmatter. Existing single-issue workflows that don't pass `issue_type` default
to the code path, preserving current behavior.

### PLAN doc format extensions

Two optional fields added to the Issue Outline spec:

```markdown
### Issue N: Title

**Goal**: ...
**Acceptance Criteria**: ...
**Dependencies**: ...
**Type**: docs                                   # optional: docs | code (default: code)
**Files**: `path/to/file.md`, `path/to/other.md` # optional: write targets for conflict detection
```

`plan-to-tasks.sh` extracts both fields alongside the existing `**Dependencies**:` parsing.

### Orchestrator-to-child data flow

The orchestrator's spawn directive (in `work-on-plan.md`) already passes variables
at `koto init` time via `--var` flags. The spawn directive is updated to include:

```bash
koto init "{{SESSION_NAME}}_$TASK_NAME" \
  --template work-on.md \
  --var ISSUE_TYPE="${TASK_ISSUE_TYPE:-code}" \
  --var SHARED_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
```

Where `$TASK_ISSUE_TYPE` is read from the task's `vars.issue_type` field in the tasks
JSON produced by `plan-to-tasks.sh`.

### Template consistency CI

```
.github/workflows/check-template-consistency.yml
  paths: skills/*/koto-templates/**
  job: validate-template-consistency
    runs: scripts/validate-template-mermaid.sh

scripts/validate-template-mermaid.sh
  For each *.md (non-mermaid) template:
    1. Find companion *.mermaid.md
       - Skip if not found (not all templates have mermaid diagrams)
    2. Extract YAML state names
    3. Extract mermaid node names from --> transition lines
    4. Diff: fail if any state in one set is missing from the other
    5. Check default_template field (if present): verify file exists in same directory
    6. Check koto next <name>: grep for koto next calls, compare to frontmatter name field
```

## Implementation Approach

### Phase 1: Template bug fixes (no new features)

Two bug fixes that are safe to ship first and independently:

1. Replace `koto next work-on-plan` with `koto next {{SESSION_NAME}}` in `spawn_and_await`
   (both tick scripts). One-line change.
2. Add gate key discoverability comments to `scrutiny`, `review`, and `qa_validation`
   directives: "The gate name is `<name>`; the context key is `<name>.json`."

These are independent of all other changes and can ship as a preparatory PR.

### Phase 2: Child workflow routing additions

Implement the three new paths in `work-on.md`:

1. `done_already_complete` terminal state + `analysis → done_already_complete` transition.
   Update `analysis` directive and both phase-3 reference files.
2. Two-field routing at `implementation` (`issue_type: docs → finalization`).
   Add `ISSUE_TYPE` template variable declaration.
3. `pr_status: shared` in `pr_creation` + transition to `done`.
   Update `pr_creation` directive for plan-backed children.

Update `work-on-plan.md` spawn directive to pass `ISSUE_TYPE` and to use `{{SESSION_NAME}}`.

Update SKILL.md for the new `already_complete` path and `pr_status: shared` convention.

### Phase 3: PLAN format and script changes

1. Update `plan-doc-structure.md` to add `**Type**:` and `**Files**:` as optional fields.
2. Update `plan-to-tasks.sh` to parse both fields:
   - `**Type**:` → `vars.issue_type`
   - `**Files**:` → extend `waits_on` edges for shared files
3. Add eval scenarios for the new `plan-to-tasks.sh` behavior.

### Phase 4: CI template consistency check

1. Write `scripts/validate-template-mermaid.sh` with three checks.
2. Write `.github/workflows/check-template-consistency.yml`.
3. Add test coverage for the script.

### Koto feature requests (filed separately, not implemented here)

- **`batch_final_view`**: File a koto issue requesting the v0.8.0 batch spawning
  subsystem: `materialize_children` hook, DAG scheduler, `batch_final_view` context
  key on terminal responses. The current template was authored against this spec;
  agents work around it using `koto workflows --children` + `koto status` + 
  `koto context get <child> failure_reason`. The directive should document this workaround
  explicitly until koto v0.8.0 ships.
- **`is_set` operator in `when` conditions**: File a koto issue requesting variable
  existence checks in `when` clauses. This would enable Approach c for plan-backed
  children (variable-based routing without command-gate workaround) and opens up
  cleaner conditional branching patterns generally.

## Security Considerations

Not applicable in the traditional sense: this design produces markdown files (koto
templates, skill documentation, CI scripts) and executes no external code at design
time. The CI script (`validate-template-mermaid.sh`) runs in a sandboxed GitHub
Actions environment with no write access to production systems.

The template changes do not introduce new input surfaces. Template variables
(`ISSUE_TYPE`, `SHARED_BRANCH`) are already subject to koto's allowlist sanitizer
(`^[a-zA-Z0-9._/-]+$`), which rejects empty strings and special characters. The
`**Files**:` and `**Type**:` annotations are parsed from PLAN docs by
`plan-to-tasks.sh` as plain text; they are never evaluated as code.

## Consequences

### Positive

- Doc-only issues skip three panel states (scrutiny, review, QA validation), reducing
  agent work for the common case where implementation is a single file edit.
- Pre-implemented issues exit cleanly with a success terminal rather than driving
  through implementation states that produce empty commits.
- Plan-backed children no longer report the orchestrator's PR as their own.
- The `koto next {{SESSION_NAME}}` fix makes `work-on-plan.md` reusable under any
  workflow name, not just the literal `work-on-plan`.
- CI enforces mermaid/YAML state sync, `default_template` correctness, and
  workflow-name consistency — three invariants currently maintained only by manual convention.

### Negative

- Agents must submit `issue_type` at every `implementation` visit (not just at entry).
  This is a small verbosity increase.
- Plan authors must add `**Type**:` and `**Files**:` annotations when relevant. This
  is low friction (optional fields) but requires awareness of the new conventions.
- The `pr_status: shared` path relies on agent convention. A plan-backed child that
  submits `pr_status: created` with the orchestrator's URL will still pass — the
  template does not structurally prevent this.
- Section-level file conflicts (two agents editing different sections of the same file)
  are not prevented by the `**Files**:` annotation. That class of conflict requires a
  post-execution merge strategy.

### Mitigations

- SKILL.md documentation for `issue_type` re-submission and `pr_status: shared` keeps
  agents correctly informed.
- `validate-plan.sh` could add a warning (not error) for "two outlines share a file but
  neither has a `**Files**:` annotation" in a follow-on improvement.
- The `koto is_set` feature request (if implemented) would enable Approach c, which
  eliminates the agent-convention dependency for the PR model without a template fork.

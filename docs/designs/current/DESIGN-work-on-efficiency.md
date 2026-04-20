---
status: Current
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
  degrade the parallelism the orchestrator provides. koto v0.8.2 ships
  materialize_children and batch_final_view natively, eliminating the need for
  workaround documentation in the affected directives.
---

# DESIGN: Work-on Orchestrator Efficiency

## Status

Current

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

Finally, the template's gate key naming convention has a discoverability gap:
gate labels omit `.json` while context keys include it (e.g., gate name
`review_results`, context key `review_results.json`), which isn't obvious to
agents or template authors. The `batch_final_view` context key was also absent
from the koto binary until v0.8.2; it is now available.

## Decision Drivers

- Minimize maintenance surface: forks double the states to maintain; single-template
  solutions are preferred.
- No koto engine changes required for shirabe-side fixes: `{{SESSION_NAME}}` is a
  built-in variable; two-field routing is supported today; `batch_final_view` and
  `materialize_children` are available in koto v0.8.2.
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

Add `issue_type: {code, docs, task}` to `implementation.accepts`. `docs` and `task`
route identically (skip panels); `code` goes through scrutiny/review/QA. Transitions:

```yaml
- target: scrutiny
  when:
    implementation_status: complete
    issue_type: code
- target: finalization
  when:
    implementation_status: complete
    issue_type: docs
- target: finalization
  when:
    implementation_status: complete
    issue_type: task
```

The mutual exclusivity requirement is satisfied: all three transitions share `issue_type`
with pairwise disjoint values. The `issue_type` value submitted at `implementation`
comes from the analysis agent's classification decision (see Decision 5), which may
differ from the PLAN author's original `**Type**:` annotation.

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

### Decision 5: Issue type — who decides, and when

**Context**: Routing at `implementation` depends on `issue_type`. Two parties have
relevant information: the PLAN author (knows the intended scope at planning time) and
the analysis agent (has read the actual issue and codebase, knows the real scope).
The PLAN author classifies earlier but with less information; the agent classifies later
but with full context. The question is which party is authoritative.

**Model chosen — PLAN suggests, analysis decides**

The PLAN `**Type**:` annotation is a default, not a binding declaration. It is passed
as the template variable `ISSUE_TYPE` when the child is initialized, giving the analysis
agent a starting point. The analysis agent confirms or overrides this classification based
on what it actually finds. At `implementation`, the agent submits the type it confirmed
at analysis (koto's no-path-memory constraint requires re-submission).

```
**Type**: docs                              ← PLAN author's default hint
     ↓ flows as ISSUE_TYPE init variable
analysis: agent confirms or overrides       ← authoritative classification
     ↓ agent carries decision forward
implementation: agent re-submits issue_type ← used for routing
```

This means `analysis.accepts` gains an optional `issue_type` field. The directive
instructs the agent: "Confirm or override `{{ISSUE_TYPE}}` based on what the work
actually entails. A `docs` outline that requires touching Go code should be reclassified
to `code`. A `code` outline whose full scope is a comment change should be reclassified
to `docs`." If the agent submits no `issue_type` at analysis (because the PLAN annotation
is clearly correct), the `implementation` directive defaults to `{{ISSUE_TYPE}}`.

Valid values: `code` (full review pipeline), `docs` (no panels; writing, structure,
clarity are the criteria), `task` (no panels; operational work — run commands, execute
scripts, produce no meaningful code artifacts for review). `code` is the default when
`**Type**:` is absent.

**Option B — PLAN annotation is authoritative**

The `**Type**:` value flows unchanged from PLAN to `implementation` with no analysis
override. Simpler, but the PLAN author classifies before understanding full scope. A
`docs` annotation on an issue that turns out to require a Go change would silently skip
scrutiny and review — the wrong outcome.

**Option C — Agent at analysis decides without PLAN hint**

No `**Type**:` field in PLAN format. The analysis agent classifies from scratch. Requires
analysis instructions to be comprehensive about classification criteria, and introduces
inconsistency: two agents reading the same outline might classify differently.

**Rejected**: Option B (wrong party is authoritative). Option C (no hint increases
classification variance and removes author intent from the process).

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

**`skills/work-on/koto-templates/work-on.md`**: Add optional `issue_type` field to
`analysis.accepts` (for classification confirmation/override). Add `issue_type` field
to `implementation.accepts` with three-way routing: `code` → `scrutiny`, `docs` →
`finalization`, `task` → `finalization`. Add `already_complete` to `analysis.accepts`
with a transition to `done_already_complete` terminal state. Add `shared` to
`pr_creation.accepts` with a transition to `done`. Update `analysis`, `implementation`,
and `pr_creation` directives with the new paths.

**`skills/work-on/koto-templates/work-on-plan.md`**: Replace `koto next work-on-plan`
with `koto next {{SESSION_NAME}}` in both tick scripts of `spawn_and_await` and in all
`koto context get work-on-plan` calls in `pr_finalization` and `escalate` directives.
Add `vars_field: vars` to the `materialize_children` block so koto passes each task's
`vars` object (including `issue_type`) as `--var` flags automatically when spawning children.

**`skills/work-on/SKILL.md`**: Document the `already_complete` analysis path and the
`pr_status: shared` plan-backed child convention.

**`skills/plan/references/quality/plan-doc-structure.md`**: Add `**Files**:` and
`**Type**:` as optional fields in the Issue Outline section.

**`skills/plan/scripts/plan-to-tasks.sh`**: Parse `**Files**:` to auto-add `waits_on`
edges for shared files. Parse `**Type**:` to populate `issue_type` in the vars object.

**`skills/work-on/references/phases/phase-3-analysis.md`** and
**`skills/work-on/references/agent-instructions/phase-3-analysis.md`**: Add guidance
for detecting pre-implemented work and submitting `already_complete` evidence. Add
classification guidance: confirm or override `{{ISSUE_TYPE}}` based on actual scope;
submit `issue_type` alongside `plan_outcome` when reclassifying.

**`.github/workflows/check-template-consistency.yml`** + **`scripts/validate-template-mermaid.sh`**:
New CI job triggering on `skills/*/koto-templates/**`. Runs three checks.

## Solution Architecture

### Child workflow routing (work-on.md)

The state machine adds new paths using existing koto mechanisms:

```
analysis
  ├── plan_ready       → implementation   (issue_type confirmed here)
  ├── already_complete → done_already_complete  [NEW]
  └── ...              → done_blocked

implementation
  ├── complete + issue_type: code → scrutiny     [MODIFIED]
  ├── complete + issue_type: docs → finalization [NEW]
  ├── complete + issue_type: task → finalization [NEW]
  └── ...

pr_creation
  ├── created          → ci_monitor
  ├── shared           → done              [NEW]
  └── ...
```

`done_already_complete` is a `terminal: true` state with no `failure: true` flag.
The parent orchestrator's `batch_outcome: all_success` logic treats it as a success.

`issue_type` is declared as a template variable (`required: false, default: code`) in
the frontmatter — this carries the PLAN author's hint into the workflow. The analysis
agent confirms or overrides it by optionally submitting `issue_type` alongside
`plan_outcome`. The implementation agent re-submits the confirmed type for routing.
Existing single-issue workflows that don't pass `ISSUE_TYPE` default to `code`,
preserving current behavior.

### PLAN doc format extensions

Two optional fields added to the Issue Outline spec:

```markdown
### Issue N: Title

**Goal**: ...
**Acceptance Criteria**: ...
**Dependencies**: ...
**Type**: docs                                   # optional: code | docs | task (default: code)
**Files**: `path/to/file.md`, `path/to/other.md` # optional: write targets for conflict detection
```

`**Type**:` is a default hint for the analysis agent, not a binding declaration.
The agent may reclassify during analysis if actual scope differs from the outline.

`plan-to-tasks.sh` extracts both fields alongside the existing `**Dependencies**:` parsing.

### Orchestrator-to-child data flow

`work-on-plan.md` already declares `materialize_children` in its `spawn_and_await`
state; koto v0.8.2 now executes it. Koto reads the tasks JSON from the context store,
resolves `waits_on` dependencies, and calls `koto init` per child automatically. The
`vars` field on each task entry is passed as `--var` flags.

The only template change needed is adding `vars_field: vars` to the existing
`materialize_children` block:

```yaml
materialize_children:
  from_field: tasks
  failure_policy: skip_dependents
  default_template: work-on.md
  vars_field: vars          # NEW: passes task.vars as --var flags to koto init
```

`plan-to-tasks.sh` populates `vars.issue_type` from the `**Type**:` annotation,
so koto automatically passes `--var ISSUE_TYPE=<type>` when spawning each child.
No bash loop or manual `koto init` calls are needed in the directive.

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

Implement the new paths in `work-on.md`:

1. `done_already_complete` terminal state + `analysis → done_already_complete` transition.
   Add optional `issue_type` to `analysis.accepts`. Update `analysis` directive and both
   phase-3 reference files with: (a) `already_complete` guidance, (b) classification
   confirmation/override instructions.
2. Three-way routing at `implementation` (`code` → `scrutiny`, `docs`/`task` → `finalization`).
   Add `ISSUE_TYPE` template variable declaration (`required: false, default: code`).
3. `pr_status: shared` in `pr_creation` + transition to `done`.
   Update `pr_creation` directive for plan-backed children.

Update `work-on-plan.md`: add `vars_field: vars` to `materialize_children`; replace
all `work-on-plan` literals with `{{SESSION_NAME}}` in `spawn_and_await` tick scripts
and in `koto context get work-on-plan` calls in `pr_finalization` and `escalate`.

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

### Koto feature requests (filed as issues, not implemented here)

- **`batch_final_view`**: Shipped in koto v0.8.2 (tsukumogami/koto#142). The
  `materialize_children` hook, DAG scheduler, and `batch_final_view` context key are
  all available. The `{{SESSION_NAME}}` fix in Phase 2 also corrects the hardcoded
  `work-on-plan` name in all `koto context get` calls, making the existing directive
  references work correctly.
- **`is_set` operator in `when` conditions**: Filed as tsukumogami/koto#141. Not yet
  implemented. Would enable Approach c for plan-backed children (variable-based routing
  without command-gate workaround). Approach a (`pr_status: shared`) remains the
  chosen implementation path until this lands.

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
- The `{{SESSION_NAME}}` fix makes `work-on-plan.md` reusable under any workflow
  name and corrects all `koto context get work-on-plan batch_final_view` calls in
  `pr_finalization` and `escalate` — which now work correctly since koto v0.8.2
  ships `batch_final_view`.
- CI enforces mermaid/YAML state sync, `default_template` correctness, and
  workflow-name consistency — three invariants currently maintained only by manual convention.

### Negative

- Agents must submit `issue_type` at `implementation` (re-submission of the analysis
  decision). Small verbosity increase; the directive makes this mechanical.
- Analysis agents must actively confirm or reclassify `{{ISSUE_TYPE}}`. This is a
  new responsibility, though a lightweight one: most outlines will match their annotation
  and the agent simply confirms without further thought.
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

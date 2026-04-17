# Exploration Findings: work-on-efficiency

## Core Question

How can we reduce the operational overhead of the work-on skill's plan orchestrator
mode while preserving its structural guarantees? Friction falls into two buckets:
shirabe template changes that can be made now, and koto engine capabilities that
need to be requested.

## Round 1

### Key Insights

- **Docs fast path is implementable in a single template today** (lead: koto-complexity-routing).
  Koto's `when` conditions support multi-field discrimination. The `entry` state's existing
  four-way branch on `mode` is direct proof. The binding constraint: koto has no path memory,
  so `issue_type` must be re-submitted at `implementation` (not just at `entry`) to trigger the
  short path. Option A (two-field at `implementation`: `issue_type: docs/code`) is the
  least-disruptive implementation. No koto engine changes needed.

- **Already-done exit requires only a shirabe template change** (lead: already-done-exit).
  Add `plan_outcome: already_complete` to `analysis.accepts`, add a `done_already_complete`
  terminal state with no `failure: true` flag, and add the transition. The parent orchestrator's
  `batch_outcome: all_success` logic counts any non-failure terminal as success — no
  orchestrator changes needed. The instructions gap is equally important: nothing in
  `phase-3-analysis.md` or `agent-instructions/phase-3-analysis.md` tells the agent to
  detect pre-implemented work.

- **Static file-conflict analysis is infeasible; explicit annotation is right** (lead: parallel-file-conflicts).
  Path regex on prose generates too many false positives — commonly-referenced files like
  `SKILL.md` appear in multiple outlines as context, not change targets. The only approach with
  near-zero false positives is an explicit `**Files**:` annotation per Issue Outline, parsed
  by `plan-to-tasks.sh` to auto-add `waits_on` edges. This mirrors the existing `**Dependencies**:`
  convention and is optional so it only adds friction when parallel file conflicts are possible.
  Caveat: the annotation doesn't prevent section-level conflicts (Issues 4 and 5 touched
  different sections of `SKILL.md`); that requires a post-execution merge strategy out of scope here.

- **`pr_status: shared` (Approach a) is implementable today; Approach b (fork) is cleaner but costly** (lead: plan-backed-pr-model).
  Approach c (`is_set` operator in `when` conditions) is not implementable — koto's `when`
  supports only strict JSON equality, no existence checks on variables. The command-gate
  workaround for approach c is further blocked by the empty-string allowlist restriction.
  Approach a (add `pr_status: shared` enum value, route to `done`) is agent-convention but
  ships now. Approach b (fork to `work-on-plan-backed.md`) is structurally clean but
  multiplies maintenance cost across 17 shared states.

- **`batch_final_view` is a koto v0.8.0 engine gap; `{{SESSION_NAME}}` fix is free** (lead: koto-api-gaps).
  The entire batch spawning subsystem (`materialize_children`, DAG scheduler, `batch_final_view`
  on terminal responses) is absent from koto source — the template was authored against the spec,
  not the binary. Evals hand-code `batch_final_view` fixtures. In contrast, `{{SESSION_NAME}}` is
  already a built-in koto variable; replacing `koto next work-on-plan` with `koto next {{SESSION_NAME}}`
  in `spawn_and_await` is a one-line template fix. Gate name vs. context key (`review_results` vs.
  `review_results.json`) is a discoverability gap, not a mismatch — gate labels omit `.json`,
  context keys include it.

- **Three CI checks are high-value with near-zero maintenance cost** (lead: ci-gate-coverage).
  Both mermaid files are currently in sync with their YAML counterparts — no immediate drift.
  But nothing in CI enforces this invariant. Three checks worth adding: (1) mermaid state-set
  diff vs. YAML states, (2) `default_template` file existence, (3) workflow name in `koto next`
  calls matches YAML `name:` field. All implementable as a single `validate-template-mermaid.sh`
  script. A fourth check (context key names in directive prose matching gate definitions) is
  limited by the reference-file delegation pattern and produces false negatives.

### Tensions

- **Single template vs. fork for docs fast path**: Single template is lower maintenance, but
  requires re-submitting `issue_type` at every `implementation` state, adding agent verbosity.
  A fork (`work-on-docs.md`) would be simpler for agents but creates drift risk across 17 shared states.
  The same tension applies to the plan-backed PR model (Approach a vs. Approach b).

- **Approach a vs. Approach b for PR model**: Approach a ships now and relies on agent convention;
  Approach b is structurally correct but doubles maintenance surface. Both leads (plan-backed-pr-model
  and koto-complexity-routing) identify the same fundamental trade-off: structural enforcement costs
  maintenance, agent convention is cheaper but fragile.

- **Files annotation: warning vs. auto-edge**: If `plan-to-tasks.sh` auto-adds `waits_on` edges for
  shared files, it silently serializes work that might be safely parallelizable. If it only warns,
  humans stay in control but the warning is easy to ignore. The lead recommends auto-add (safer),
  but acknowledges the risk of over-constraining parallel plans.

### Gaps

- **How does the plan orchestrator know issue type?** The `work-on-plan.md` spawn directive passes
  `default_template: work-on.md` and task-level data via the tasks JSON. For the docs fast path to
  work, each task entry needs an `issue_type` field that gets passed as an init variable or initial
  evidence. The PLAN doc's Issue Outline format would need a `**Type**:` annotation, and
  `plan-to-tasks.sh` would need to extract and pass it. This is not covered by any research lead.

- **What koto tracking issues exist for v0.8.0 features?** The lead confirms `batch_final_view`
  is absent, but doesn't know whether a koto tracking issue already exists.

- **Section-level conflict resolution**: The `**Files**:` annotation prevents naive file-level
  conflicts but not section-level conflicts. The right solution (temp files + merge step) is out
  of scope and not researched.

### Decisions (--auto mode)

- **Proceed directly to crystallize**: All 6 leads are fully investigated. Coverage is sufficient
  to select an artifact type and write a design. No meaningful gaps require another research round.
- **Docs fast path**: Option A (two-field at `implementation`) preferred over Option B (routing
  state) and Option C (fork). Rationale: minimal disruption to existing graph, existing precedent
  in `plan_context_injection`, avoids fork maintenance cost.
- **Plan-backed PR model**: Approach a (`pr_status: shared`) preferred over Approach b (fork).
  Rationale: ships now, no maintenance burden, and the structural enforcement of Approach b isn't
  worth the cost when all children in a plan-backed run share the same mode anyway.
- **Files annotation**: Optional (not required), auto-add `waits_on` edges (not just warn), mirrors
  `**Dependencies**:` syntax. Rationale: required would add friction for clean plans; auto-add is
  safer than a warning that can be ignored.

### User Focus

Running in --auto mode per user instruction. All key decisions made above are documented.

## Accumulated Understanding

The work-on plan orchestrator has five concrete friction points identified through direct
execution, each with a clear fix category:

**Immediately fixable in shirabe templates (no koto changes):**
1. Docs fast path: add `issue_type` field to `implementation`, two-field discrimination to
   route docs issues to `finalization` directly, skipping scrutiny/review/qa_validation.
2. Already-done exit: add `done_already_complete` terminal state reachable from `analysis`
   via `plan_outcome: already_complete`.
3. Session name bug: replace `koto next work-on-plan` with `koto next {{SESSION_NAME}}` in
   `spawn_and_await` (both tick scripts).
4. Plan-backed PR model: add `pr_status: shared` to `pr_creation` enum, route to `done`
   directly, update directive to instruct plan-backed children.
5. Gate key discoverability: add one-line comments in scrutiny/review/qa_validation directives
   clarifying gate name vs. context key distinction.

**Requires PLAN doc format + script changes:**
6. File conflict prevention: add `**Files**:` annotation to Issue Outline format, update
   `plan-to-tasks.sh` to auto-add `waits_on` edges for shared files.
7. Issue type routing: add `**Type**:` annotation to Issue Outline format (or extend PLAN
   frontmatter), update `plan-to-tasks.sh` to pass `issue_type` when spawning children.

**Requires CI script addition:**
8. Template consistency enforcement: add `validate-template-mermaid.sh` with three checks
   (mermaid state-set, `default_template` existence, workflow name in prose).

**Koto feature requests to file:**
9. `batch_final_view`: file koto issue for v0.8.0 batch spawning subsystem.
10. `is_set` operator: file koto issue for variable existence checks in `when` conditions
    (enables Approach c for PR model bypass without command-gate workaround).

The design question is how to package items 1-8 into a coherent design: same PR or phased,
which items have hard dependencies on each other, and whether the PLAN format changes (6, 7)
should be a separate design or included here.

## Decision: Crystallize

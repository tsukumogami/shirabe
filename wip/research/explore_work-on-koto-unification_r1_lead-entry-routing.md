# Lead: Entry-point routing in koto

## Findings

### Current work-on dual-path topology

The existing work-on template (at `/home/dgazineu/dev/niwaw/tsuku/tsukumogami-5/public/shirabe/skills/work-on/koto-templates/work-on.md`) implements a clean dual-path split at the `entry` state:

- **Entry state** accepts a `mode` enum field with values `[issue_backed, free_form]`
- Two unconditional transitions branch on `when: mode` guards:
  - `mode: issue_backed` → `context_injection` → `setup_issue_backed` → `staleness_check` → (optional `introspection`) → `analysis`
  - `mode: free_form` → `task_validation` → `research` → `post_research_validation` → `setup_free_form` → `analysis`
- Both paths converge at the `analysis` state and share all subsequent states through `done`/`done_blocked`

This topology works because the branching happens at the mode level (enum evidence), not via gates. The template declares both `issue_number` and `task_description` as optional accepts fields in the `entry` state, and koto's `when` conditions route based on the submitted `mode` value.

### Plan-backed integration challenge

Adding a third path (plan-backed, multi-issue) creates a new complexity: the plan-backed path differs structurally after `analysis`:

- **Issue-backed & free-form**: single implementation cycle from `analysis` → `implementation` → `finalization` → `pr_creation`
- **Plan-backed**: multiple issues with dependency ordering, requiring iteration: analyze-all-issues → resolve-dependencies → for-each-issue(implementation-cycle) → consolidate-pr

The post-analysis flow needs to be aware of execution mode (single vs multi-issue), not just pre-analysis mode. This means the convergence point moves: instead of merging at `analysis`, paths would need to split again after `analysis` based on whether we're executing 1 or N issues.

### Koto's routing primitives

Koto template format (as documented in `/home/dgazineu/dev/niwaw/tsuku/tsukumogami-5/public/koto/plugins/koto-skills/skills/koto-author/references/template-format.md`) supports:

1. **Evidence routing via `when` conditions** (Layer 2): agent submits structured data (enum, string, number, boolean) at states with `accepts` blocks; transitions fire based on `when` field matches
2. **Gate routing via `gates.*` paths** (Layer 3, koto v0.6.0): gates (command, context-exists, context-matches) produce structured JSON output; transitions route on `gates.<gate_name>.<field>` conditions without agent submission
3. **Mixed routing**: a state can combine both gates and accepts, using both `gates.*` and evidence fields in when conditions
4. **Self-loops**: transitions with `target: self` for retry/wait scenarios
5. **Split topology**: multiple conditional transitions from a single state, with mutual exclusivity enforced at compile time

Koto does **not** have:
- Template composition/includes (each template is a single monolithic YAML definition)
- Parametric state counts (e.g., "loop N times for each issue") -- this is a tracked feature request (tsukumogami/koto#105 for bounded iteration)
- Sub-workflows or nested state machines
- Dynamic state generation based on runtime data (e.g., creating a state per issue in a multi-issue plan)

### Design space: four approaches

**Option A: Single monolithic template with triple split at entry**

```
entry (mode: [issue_backed, free_form, plan_backed])
├─ issue_backed path → analysis → single_implementation → done
├─ free_form path → analysis → single_implementation → done
└─ plan_backed path → analysis → multi_issue_orchestration → done
```

Pros:
- All paths explicit in one place
- Koto enforces phase ordering across all modes
- Resume works naturally across mode boundaries
- Decisions and context are workflow-scoped, visible via `koto decisions list`

Cons:
- Template grows to ~100+ states (3 pre-analysis chains + 1 shared analysis + 2 post-analysis chains)
- Multi-issue orchestration in a state machine is awkward: representing "for each issue, run a sub-cycle" as explicit states doesn't scale (5 issues = 5*N states)
- Conditional state paths must be mutually exclusive at compile time, but multi-issue logic is inherently data-driven (which issues are in the plan, how many, what dependencies)
- No way to loop over issues with variable count without either fixed iteration (tsukumogami/koto#105 blocker) or skill-layer orchestration

**Option B: Template composition with base + mode overlays**

```
work-on-base.md (shared analysis, finalization, pr_creation states)
├─ work-on-issue-backed.md (extends base, adds entry + pre-analysis path)
├─ work-on-free-form.md (extends base, adds entry + pre-analysis path)
└─ work-on-plan-backed.md (extends base, adds entry + multi-issue path)
```

Pros:
- Reusable shared states
- Each variant template is smaller and focused

Cons:
- **Koto has no include/composition mechanism** -- every template is monolithic
- Would require skill-layer workaround: detecting mode, selecting and running different template
- Resume breaks: a workflow initialized with work-on-issue-backed.md can't resume under work-on-plan-backed.md
- Adds manual orchestration burden

**Option C: Three separate templates selected at init time**

```
koto init <WF> --template work-on-<mode>.md
```

Pros:
- Each template is minimal and mode-specific
- Simple template logic
- No need for koto features that don't exist

Cons:
- No unified skill entry point
- Resume requires knowing which template was used
- Decision log is per-template, not per-workflow
- No shared context across templates (each template has separate context store)
- Skill layer must detect mode, select template, and manage resume across modes

**Option D: Single template with entry state as "mode detector" + conditional routing**

Like Option A but recognize that the template declares mode at entry via enum evidence, and the skill layer can use that to select sub-agent behavior:

```
entry (mode: [issue_backed, free_form, plan_backed])
  → koto routing delegates to skill layer logic per phase
  
Skill layer:
- Handles pre-analysis phase per mode (context injection, task validation, research, etc)
- Calls koto next, reads evidence and directive
- Delegates phase execution to mode-specific sub-agent or routine
- Returns evidence to koto
- Only koto entry and analysis onward are in the template
```

Pros:
- Single koto template for phase ordering and gatekeeping
- Skill layer handles mode-specific orchestration (which koto can't do well)
- Avoids explosion of states in the template

Cons:
- Splits responsibility between koto and skill layer, reducing visibility
- Mode-specific logic lives in skill code, not template definition
- Harder to reason about the full workflow from the template alone
- Resume might not be deterministic if skill layer state diverges from koto state

### Current work-on's mode selection mechanism

The work-on SKILL.md (`/home/dgazineu/dev/niwaw/tsuku/tsukumogami-5/public/shirabe/skills/work-on/SKILL.md`) shows how mode is selected:

- **Issue-backed mode**: initialized with `koto init <WF> --var ISSUE_NUMBER=<N> --var ARTIFACT_PREFIX=issue_<N>`
- **Free-form mode**: initialized with `koto init <WF> --var ARTIFACT_PREFIX=task_<slug>` (no ISSUE_NUMBER)
- **Plan-backed mode** (mentioned in template): "use free-form init. Extract the goal and acceptance criteria from the PLAN doc and provide them as the task description in the entry evidence"

The mode is not passed as a variable; instead, the presence/absence of the ISSUE_NUMBER variable implicitly determines mode in the skill layer, and the entry state's `when` conditions in the template route accordingly. At entry time, the agent submits `mode` as part of evidence, and koto's `when` conditions handle the split.

## Implications

### For plan-backed unification:

1. **Option A (single monolithic) is structurally sound for entry routing but breaks down for multi-issue execution.** The entry split works fine with koto's evidence routing. The blocker is representing "iterate issues with variable count" in a state machine without bounded iteration support (tsukumogami/koto#105).

2. **Koto's model is per-workflow, not per-issue-in-workflow.** Adding multi-issue execution to work-on requires either:
   - Skill layer spawning sub-agents for each issue (koto context as shared input, skill layer orchestrates the loop)
   - A redesigned template that uses skill-delegated orchestration (Option D)
   - Waiting for koto feature #105 and refactoring around it

3. **The cleanest approach that works today is Option D with a clarity trade-off:** Single entry point with unified mode detection, but pre-analysis and post-analysis phases delegated to skill-layer sub-agents per mode. Koto owns the shared backbone (analysis, finalization, pr_creation) and gates. This avoids template explosion and preserves resume semantics at the koto level, while deferring mode-specific orchestration to the skill layer where it's more natural.

4. **If plan-backed requires per-issue sub-workflows, those can't be koto-backed without major architectural changes.** Each issue could have its own transient koto workflow (per-issue-<ID>), but the parent workflow (plan orchestrator) would be skill-layer-driven until koto supports sub-workflows.

5. **Context utilization is simpler than state orchestration.** Koto context keys (markdown blobs) work well for passing cross-issue artifacts (decisions, summaries) from one issue to the next. The skill layer can read/write these as it sequences issues.

### For migration strategy:

- **Phase 1**: Migrate existing dual-path topology to koto v0.6.0 structured gate output (gates.* paths, overrides with rationale). This is straightforward; all 8 existing gates map cleanly.
- **Phase 2**: Add plan-backed mode detection and entry routing in the template. This works with today's koto.
- **Phase 3**: Implement multi-issue orchestration in skill layer with per-issue sub-agents or iterative skill delegation. Don't try to fit this in the koto template.
- **Phase 4** (optional): Once tsukumogami/koto#105 (bounded iteration) lands, consider refactoring multi-issue orchestration into koto if it simplifies the skill layer.

## Surprises

1. **Koto has no composition primitive.** I expected includes or template inheritance. Instead, every workflow is a monolithic YAML definition. This rules out Option B without skill-layer workarounds.

2. **Mode selection is implicit in the template, not explicit in init variables.** The work-on template declares mode as an `accepts` field at entry, not a template variable. This means the skill layer determines mode (based on input arguments) and submits it as evidence. Variables are for static configuration (ISSUE_NUMBER, ARTIFACT_PREFIX); dynamic branching is via evidence routing. This is cleaner than I expected.

3. **The dual-path convergence in work-on already works elegantly.** Both pre-analysis paths (12-15 states total) converge at a single `analysis` state. The template handles this with mutual-exclusion `when` conditions that the compiler validates. No tricks needed; koto's routing is sufficient for this level of branching.

4. **Multi-issue execution is a hard limit for koto's state machine model.** Koto can't represent "for each issue, execute states X, Y, Z" without explicit state duplication or sub-workflows. This is documented as feature #105 (bounded iteration), but even that won't solve the per-issue-state-machine problem. Multi-issue orchestration belongs in the skill layer, not the koto template.

5. **Gate override mechanism is stricter than I expected.** Overrides require rationale, have compile-time validated schema defaults, and are first-class koto operations (not agent decisions). This is good for auditing but means every gate-dependent transition needs thoughtful override semantics, not just "skip the gate."

## Open Questions

1. **For multi-issue orchestration, should each issue get its own transient koto workflow, or should the skill layer orchestrate without koto?** If per-issue, how do we share context? If skill-layer-only, how do we preserve resume semantics?

2. **What should the entry state's `when` conditions be for plan-backed mode?** We need to validate that a PLAN file exists and is readable, not just branch on enum. Should this be a gate (context-exists for plan path artifact) or skill-layer validation?

3. **Should plan-backed mode still produce a single PR, or multiple PRs (one per issue)?** This affects post-analysis convergence: if single PR, paths reconverge before pr_creation; if multiple PRs, the issue iteration continues through finalization and pr_creation for each issue.

4. **How much of the pre-analysis chain (context injection, staleness check, introspection) applies to plan-backed? Or does plan-backed skip straight to analysis?** Plan documents aren't GitHub issues, so staleness_check and introspection don't apply; but context injection (reading the plan file, extracting goals) still makes sense.

5. **Which work-on gates need to become koto v0.6.0 structured output on migration, and what are their override semantics?** The 8 gates (context_artifact, baseline_exists, on_feature_branch, staleness_fresh, introspection_artifact, plan_artifact, code_committed, ci_passing, summary_exists) need explicit override_default values that make sense for each.

6. **Can plan-backed mode reuse the `analysis` state, or does multi-issue planning need different analysis logic?** A single analysis state can't generate separate sub-plans for 5 issues. This might be a second analysis state, or skill-layer analysis per issue.

## Summary

Koto's evidence routing makes entry-point branching clean: the `entry` state accepts a `mode` enum and routes via `when` conditions to mode-specific paths that converge at `analysis`. This pattern scales elegantly for work-on's three entry types (issue-backed, free-form, plan-backed) **up to the analysis state**. The hard problem is post-analysis: plan-backed execution requires per-issue orchestration (iterating issues, managing dependencies, running sub-cycles), which koto's state machine model doesn't support without explicit state duplication or awaiting koto feature #105 (bounded iteration). The pragmatic path is Option D: single entry in the koto template, shared backbone (analysis through done), and skill-layer delegation for mode-specific orchestration after convergence.


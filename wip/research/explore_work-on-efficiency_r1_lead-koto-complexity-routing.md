# Lead: koto complexity routing — single template vs. fork

## Findings

### Koto's conditional transition syntax

Koto fully supports evidence-driven branching within a single template using `accepts` blocks and `when` conditions. The transition system works as follows:

- Each state declares an `accepts` block with typed fields (enum, string, number, boolean).
- Each outgoing transition can have a `when` block matching field values (AND semantics).
- The compiler enforces mutual exclusivity: for every pair of conditional transitions, at least one shared field must have disjoint values. Transitions with no shared field are rejected at compile time.
- An unconditional transition (no `when`) acts as a fallback after all conditional transitions fail to match.

### Existing branching pattern at `entry`

The `entry` state in `work-on.md` already demonstrates single-template multi-path branching. It accepts a `mode` enum with values `[issue_backed, free_form, plan_backed, skipped]` and routes each value to a distinct initial state:

- `mode: issue_backed` → `context_injection`
- `mode: free_form` → `task_validation`
- `mode: plan_backed` → `plan_context_injection`
- `mode: skipped` → `skipped_due_to_dep_failure`

Each path then proceeds through different state sequences before converging at `analysis`. This is the exact pattern needed for a docs fast path.

### State reachability and dead states

Koto's graph structure is permissive about reachability. States are declared in a flat map; the engine doesn't require every state to be reachable from every entry point. The `issue_backed` path never visits `task_validation`, `research`, or `post_research_validation`, yet those states exist in the same template without problem. Similarly, a `docs` path could skip `scrutiny`, `review`, and `qa_validation` while they remain in the template for use by non-docs paths. The compiler validates mutual exclusivity of `when` conditions and the existence of body sections, not that every state is universally reachable.

### What a docs branch would look like

Adding `docs` as a new `mode` value at `entry` (or a new `issue_type` field at some other state) is mechanically straightforward:

1. Add `docs` to the `entry` state's `mode` enum values.
2. Add a `- target: docs_setup when: mode: docs` transition at `entry`.
3. Add a `docs_setup` state (or reuse `setup_plan_backed` with a different context path).
4. Route `docs_setup` directly to `analysis`, bypassing `staleness_check` and `introspection`.
5. From `implementation`, route a `docs`-path directly to `finalization` instead of `scrutiny`.

The challenge with step 5 is that `implementation` has no awareness of which entry path was taken. Koto has no mechanism for "path memory" — the current state doesn't know how it was reached. To route from `implementation` differently for docs vs. code, the agent would need to carry an `issue_type` value forward as evidence at the `implementation` state itself.

**Option A: Two-field discrimination at implementation**

Add an `issue_type` field to `implementation`'s `accepts` block (enum: `docs`, `code`). Transitions from `implementation` become:

- `implementation_status: complete AND issue_type: code` → `scrutiny`
- `implementation_status: complete AND issue_type: docs` → `finalization`

The mutual exclusivity requirement is satisfied: both conditions share `issue_type` with disjoint values. The agent must submit `issue_type` at every visit to `implementation`, which adds a small verbosity cost.

**Option B: Intermediate routing state**

After `analysis` (where all paths converge), insert a `routing` state that accepts `issue_type`. This routes `docs` directly past scrutiny/review/qa_validation to `finalization`. The three panel states remain in the template, reachable only by the code path.

**Option C: Separate template file (work-on-docs.md)**

A separate template would be a strict subset of `work-on.md` — same states up to `implementation`, then a direct `implementation → finalization → pr_creation → ci_monitor → done` path. This is simpler to reason about in isolation but creates a maintenance burden: any change to the shared states (entry, analysis, finalization, etc.) must be applied twice. The plan orchestrator in `work-on-plan.md` would also need logic to select which template to spawn per issue type.

### Template compiler constraints relevant here

The compiler validates:
- `when` fields must reference fields declared in the state's `accepts` block.
- `when` values for enum fields must appear in the `values` list.
- Pairwise mutual exclusivity across all conditional transitions on the same state.
- All states declared in frontmatter must have a corresponding body section.

None of these constraints prevent a docs fast path in a single template.

## Implications

A single-template docs fast path is achievable without any koto engine changes. The existing `entry`-state branching pattern is direct precedent. The main design choice is where to re-merge the paths: either the docs path bypasses just the three panel states (by passing `issue_type` at `implementation`), or it diverges more broadly from a post-analysis routing state. Option A (two-field discrimination at `implementation`) is the least disruptive — it touches only `implementation`'s `accepts` block and its transitions, leaving the rest of the graph unchanged.

The maintenance trade-off strongly favors a single template. The shared states (`entry`, `context_injection`, `setup_*`, `staleness_check`, `introspection`, `analysis`, `finalization`, `pr_creation`, `ci_monitor`) represent the bulk of the workflow. Duplicating them into a second template file creates a drift risk that compounds over time.

The plan orchestrator (`work-on-plan.md`) would need a minor update: it must pass `issue_type` as a spawn variable or initial evidence when materializing doc-type children. This is already supported — `koto init` accepts `--var` flags that populate template variables.

## Surprises

1. **No path memory**: koto has no built-in mechanism to propagate which entry branch was taken to later states. Evidence is strictly per-state. This means the docs/code discrimination must be re-submitted at `implementation` rather than being inferred from how the workflow was initialized.

2. **Gate-only auto-advancement doesn't help here**: Koto supports auto-advancement via gate output (`gates.*` in `when` conditions), but there's no gate that could detect "this is a docs issue" from environment alone. The classification must come from agent-submitted evidence.

3. **The `when` disjoint-field constraint is the binding limit**: Two transitions from the same state routing on completely different fields (no shared discriminator) fail the compiler's mutual exclusivity check. This means a docs path cannot simply add a second unconditional or loosely conditioned transition — it needs a proper shared field in the `when` condition.

4. **`plan_context_injection` already routes on two fields**: The `issue_source` field (`github` vs `plan_outline`) demonstrates that multi-field `when` conditions combining gate outputs and evidence fields are well-established in this template. The pattern for a docs path is the same.

## Open Questions

1. **Where should the type classification happen?** At `entry` (simplest dispatch point, consistent with existing mode routing) or at a post-analysis `routing` state (ensures docs classification is confirmed after analysis can validate it's really just docs)?

2. **Should `staleness_check` and `introspection` be skipped for docs?** These are issue-backed-path states. If a docs issue is always plan-backed (which skips staleness), this is already handled. If docs issues can also be issue-backed, explicit skipping needs design.

3. **How does the plan orchestrator know which issues are docs?** The PLAN doc would need a `type: docs` annotation per issue item. The orchestrator would read this and pass `mode: docs` (or equivalent) when spawning child workflows.

4. **Should `scrutiny`, `review`, and `qa_validation` be skipped entirely or kept as optional?** A medium-weight option: keep them reachable but make them no-ops that auto-advance for doc changes. This preserves the graph topology while eliminating agent work.

5. **What about mixed issues?** Some issues add docs and also change configuration. A hard `docs` vs `code` binary may misclassify borderline issues. A `light` / `full` panel distinction might be more durable than a content-type distinction.

## Summary

Koto fully supports complexity-based routing within a single template: the existing `entry`-state branching on `mode` is direct proof, and the compiler's mutual exclusivity rules are satisfied as long as transitions share a discriminating field. The main implication is that the docs fast path requires re-submitting an `issue_type` field at `implementation` (because koto has no path memory), but this is a small verbosity cost relative to the maintenance savings of a single template over a fork. The biggest open question is whether classification belongs at `entry` (dispatch point) or after `analysis` (where scope is confirmed), since early classification risks routing a borderline issue down the wrong path.

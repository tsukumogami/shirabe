# Lead: koto API gaps

## Findings

### Gap 1: `batch_final_view` documented but absent at runtime

**Where it's documented**: `work-on-plan.md` directives for `pr_finalization` and `escalate` states both instruct the agent to run `koto context get work-on-plan batch_final_view`. The SKILL.md repeats this in its "Escalation Handling" and "PR Finalization" sections. The design doc (DESIGN-work-on-koto-unification.md) describes `batch_final_view` as "a terminal field — frozen snapshot on the parent's `done` response containing per-child `name`, `state`, `outcome`, `reason`, `reason_source`, etc."

**What koto actually provides**: `batch_final_view` is nowhere in the koto source code (`src/` directory). Searching `public/koto/` for `batch_final_view` returns zero results. The koto engine implements `children-complete` gates (`evaluate_children_complete` in `src/cli/mod.rs`), `koto workflows --children`, and `koto status`, but the batch scheduler and `materialize_children` hook described in the design doc as "koto v0.8.0" are not implemented. Neither is the `batch_final_view` context key that v0.8.0 was supposed to expose on terminal responses.

**Evidence in evals**: The eval fixture `skills/work-on/evals/fixtures/scenarios/e2e-plan-happy/koto-context-batch-final-view.json` exists as a static fixture, confirming the agent is expected to read this from `koto context get`. The fixture is hand-authored — it doesn't come from koto's output. The `e2e-plan-escalate/koto-next-work-on.json` fixture hardcodes the directive text `"Read koto context get work-on-plan batch_final_view"` as the literal directive koto would emit.

**Classification**: This is a **koto engine gap**. The design doc describes it as a v0.8.0 feature (`materialize_children`, `tasks`-typed evidence, `batch_final_view` on terminal responses). That feature is designed but not yet implemented. The template was written against the spec, not the current binary.

**Workaround today**: An agent encountering `pr_finalization` or `escalate` can use `koto workflows --children <plan-slug>` to list children, then `koto status <child>` and `koto context get <child> failure_reason` per child to reconstruct the batch view manually. This is what `koto status` was designed for (from DESIGN-hierarchical-workflows.md). It requires more commands but surfaces the same data. The template directive can be updated to document this fallback explicitly, with the `koto context get batch_final_view` command as the preferred path once koto v0.8.0 ships.

---

### Gap 2: `koto next work-on-plan` hardcodes the workflow name in the directive

**Where it appears**: The `spawn_and_await` directive in `work-on-plan.md` contains two bash snippets (Tick 1 — spawn, Tick 2 — complete) that both call `koto next work-on-plan --with-data @"$TMP"`. The workflow name `work-on-plan` is a literal string, not a variable reference.

**Why this is a problem**: The template's `name:` frontmatter field is `work-on-plan`, so the literal matches when the template is initialized with that exact name. But if the user runs `koto init my-feature-plan --template work-on-plan.md`, the session name is `my-feature-plan` and the directive's `koto next work-on-plan` call fails silently or targets a non-existent workflow.

**What koto provides**: koto has a built-in variable `{{SESSION_NAME}}` that substitutes to the active session name at directive render time (documented in `plugins/koto-skills/skills/koto-author/references/template-format.md`). This is a zero-cost fix — no koto changes needed.

**Classification**: This is a **shirabe template authoring bug**. The fix is to replace `koto next work-on-plan` with `koto next {{SESSION_NAME}}` in both Tick 1 and Tick 2 scripts in `work-on-plan.md`. The ci_monitor state's gate command also uses `koto next` — that uses shell-derived PR info, not the workflow name, so it's not affected.

**Workaround today**: The current SKILL.md correctly tells agents to use the plan slug as the workflow name. Agents who derive the name from context (the SKILL.md's initialization section uses `<plan-slug>`) will call the right `koto next` regardless of the directive text. But an agent relying solely on the directive's bash snippet will fail. The fix is a one-line template change.

---

### Gap 3: Context key names in directives don't match gate definitions

**Specific instance (review state)**: The `review` state in `work-on.md` declares a gate named `review_results` (line 486) with `key: review_results.json` (line 488). The gate name is `review_results` (without `.json`); the context key is `review_results.json` (with `.json`). The directive text (line 842) says: "Output: koto context key `review_results.json`." There is no mismatch here — the gate name and context key are different fields with different values by design. The gate name is just a label for routing (`gates.review_results.exists: true`); the context key is what gets stored.

**Lead's claim vs. actual**: The lead claims "the directive says `review_results` but the gate checks `review_results.json`." Examining the actual template: the gate is named `review_results`, the context key is `review_results.json`, and the directive refers to `review_results.json`. These are consistent. The gate name doesn't need to match the context key — they serve different roles (routing identifier vs. storage path).

**However, there is a related friction point**: An agent reading only the directive text ("Output: koto context key `review_results.json`") must infer that the gate checking for this artifact is named `review_results` (without `.json`) when composing `koto context add` commands. The gate name isn't mentioned in the directive. If the agent uses the wrong key name in `koto context add` (e.g., `review_results` instead of `review_results.json`), the gate won't pass. This is a discoverability gap but not a strict mismatch.

**Classification**: The lead's formulation is slightly inaccurate — there is no directive/gate mismatch in the current template. What exists is a naming convention where gate labels omit `.json` but context keys include it, creating a non-obvious two-name system. This is a **shirabe template documentation gap**, not a koto engine bug. A one-line comment in the directive like "the gate name is `review_results`; the context key is `review_results.json`" would eliminate the discoverability issue.

**Workaround today**: No code change needed. A documentation clarification in the directive text resolves it.

---

### Variable syntax and `{{WF_NAME}}`

The template format reference (`template-format.md`) documents two built-in variables: `{{SESSION_NAME}}` and `{{SESSION_DIR}}`. There is no `{{WF_NAME}}` — that's not koto's naming. `{{SESSION_NAME}}` is the correct built-in for self-reference. The directive scripts in `work-on-plan.md` should use `koto next {{SESSION_NAME}}` instead of `koto next work-on-plan`.

---

### Existing GitHub issues

Searching `gh issue list` in the shirabe repo shows no filed issues for any of the three gaps. Issue #47 (`bug(work-on): CI monitoring script path not resolvable`) covers a different bug. The batch_final_view gap and the hardcoded workflow name have not been filed.

## Implications

1. **`batch_final_view` gap is a koto feature request, not a template bug.** The template is correctly authored against the v0.8.0 spec. Filing a koto issue to track v0.8.0 batch spawning implementation is the right action. Until then, the template directive for `pr_finalization` and `escalate` should document the `koto workflows --children` + `koto status` + `koto context get <child> failure_reason` workaround explicitly.

2. **`work-on-plan` hardcode is a cheap shirabe fix.** Replacing two occurrences of `koto next work-on-plan` with `koto next {{SESSION_NAME}}` makes the template reusable under any workflow name and eliminates agent error when the initialized name differs from the template's `name:` field. This can be done immediately with no koto changes.

3. **The "directive vs. gate key" issue is a discoverability gap, not a correctness gap.** The template is correct. Adding a clarifying comment in the affected directives (`scrutiny`, `review`, `qa_validation`) would cost one line per state and eliminate the confusion. No structural change needed.

4. **All three gaps are independent.** The `batch_final_view` gap requires a koto engine change (or explicit workaround documentation). The other two are shirabe-side template authoring fixes that can ship in the same PR.

## Surprises

- **`{{SESSION_NAME}}` already exists** as a built-in koto variable. The hardcoded `work-on-plan` name is fixable today with zero koto changes — the infrastructure was already there.
- **`batch_final_view` is not a context key per the design.** The design doc says it's a "terminal field" on the `done` response, not a context key written by the scheduler. But the template directives tell the agent to read it with `koto context get`, implying koto would write it to the context store. The design may have shifted between iterations; the current directive text treats it as a context key.
- **`materialize_children` is not in koto source at all.** The entire v0.8.0 batch scheduler feature described in the design doc — `materialize_children`, `tasks`-typed evidence, DAG resolution, `batch_final_view` — is absent from `src/`. The `work-on-plan.md` template references these features but they are not yet implemented. This is a broader gap than just `batch_final_view`.
- **The eval fixture hand-codes `batch_final_view`**, which means evals are testing against a spec, not a live system. The evals pass because they mock the koto response, not because koto produces a `batch_final_view`.

## Open Questions

1. What is koto's current v0.8.0 implementation status? Is there a tracking issue in the koto repo for `materialize_children` / batch child spawning?
2. Should `work-on-plan.md` be updated to use the `koto workflows --children` workaround now, or should it stay as-is until koto v0.8.0 ships? The former is more accurate; the latter avoids two rounds of template updates.
3. For the `{{SESSION_NAME}}` fix: should this go in the same PR as the workaround documentation for `batch_final_view`, or as a standalone one-liner?
4. Is the "gate name vs. context key" discoverability gap worth fixing with a comment, or is the existing convention (gate labels omit `.json`) already understood by anyone reading the template?

## Summary

Three gaps were investigated. Gap 1 (`batch_final_view`) is a koto engine feature that doesn't yet exist — the entire v0.8.0 batch spawning subsystem (`materialize_children`, DAG scheduler, terminal batch view) is absent from the koto source; the template was authored against the spec. Agents can work around it today using `koto workflows --children` + `koto status` + `koto context get <child> failure_reason`, and the directive should document this path explicitly. Gap 2 (hardcoded `koto next work-on-plan`) is a shirabe template bug fixable today by replacing the literal name with `{{SESSION_NAME}}`, a built-in koto variable already in the template engine. Gap 3 (directive vs. gate key naming) is not a strict mismatch — gate names and context keys are different fields by design — but a discoverability friction that a one-line directive comment resolves. Two of the three gaps have cheap shirabe-side fixes that can ship now; only `batch_final_view` requires a koto engine change or explicit workaround documentation.

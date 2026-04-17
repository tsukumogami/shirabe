# Lead: CI gate coverage for template consistency

## Findings

### Existing CI landscape

The repo has six CI workflows triggered on PRs:

- **check-evals.yml** — checks every skill has a non-empty `evals/evals.json` (path: `skills/**`)
- **check-plan-docs.yml** — runs `validate-plan.sh` on changed PLAN docs (path: `docs/plans/PLAN-*.md`)
- **check-plan-scripts.yml** — runs test suites for `plan-to-tasks.sh` and `validate-plan.sh` (path: `skills/plan/scripts/**`)
- **check-templates.yml** — delegates to koto's `check-template-freshness.yml` reusable workflow (path: `skills/*/koto-templates/**`)
- **check-work-on-scripts.yml** — runs `run-cascade_test.sh` (path: `skills/work-on/scripts/**`)
- **validate-templates.yml** — runs `koto template compile` on every non-mermaid koto template (path: `**/koto-templates/**`)

What these checks do NOT cover: structural consistency between the YAML frontmatter and the `.mermaid.md` companion files, and consistency between `context-exists` gate key names in YAML and the key names named in directive prose.

### Mermaid vs YAML state sync (current state)

For `work-on-plan.md` / `work-on-plan.mermaid.md`:
- YAML states: `orchestrator_setup`, `spawn_and_await`, `pr_finalization`, `ci_monitor`, `plan_completion`, `escalate`, `done`, `done_blocked` (8 states)
- Mermaid node names extracted from transition lines: `ci_monitor`, `done`, `done_blocked`, `escalate`, `orchestrator_setup`, `plan_completion`, `pr_finalization`, `spawn_and_await` (8 nodes)
- **Status: fully in sync.** No drift detected.

For `work-on.md` / `work-on.mermaid.md`:
- YAML states: 24 states
- Mermaid node names: 24 unique nodes
- Cross-referencing both lists shows exact agreement.
- **Status: fully in sync.** No drift detected.

The mermaid files are currently accurate. However, nothing in CI enforces this invariant, so any future template edit could introduce drift without detection.

### Context key consistency (gate key vs directive text)

For `work-on.md`, context-exists gate keys are:
- `context.md` (used in `context_injection` and `plan_context_injection`)
- `baseline.md` (used in `setup_issue_backed`, `setup_free_form`, `setup_plan_backed`)
- `introspection.md` (used in `introspection`)
- `plan.md` (used in `analysis`)
- `scrutiny_results.json` (used in `scrutiny`)
- `review_results.json` (used in `review`)
- `qa_results.json` (used in `qa_validation`)
- `summary.md` (used in `finalization`)

The directive prose (in the `## <state>` sections) names each output key explicitly (e.g., "Output: koto context key `scrutiny_results.json`"). Cross-referencing the gate key names against directive text shows exact agreement in the current templates. Phase reference files (`phase-4b-review.md`, etc.) are also consistent.

For `work-on-plan.md`, there are no `context-exists` gates — the workflow reads context via `koto context get work-on-plan <key>` in directive prose only, which is unchecked by any gate definition.

### Child template name consistency

`work-on-plan.md` YAML declares `default_template: work-on.md`. The directive prose in `spawn_and_await` refers to `work-on.md` three times in code blocks and once in prose. Both are consistent — but there is no CI check that the `default_template` value actually resolves to a file that exists in the same directory.

### Hardcoded workflow name in spawn_and_await

The `spawn_and_await` directive contains `koto next work-on-plan` hardcoded in two shell snippets. The YAML `name:` field is also `work-on-plan`. These match, but if the template were renamed, the directive scripts would silently break. Currently undetected by CI.

### Feasibility assessment of potential checks

**Check 1: Mermaid state names match YAML state names**

Implementation: bash script that extracts state names from YAML (awk between `states:` and `---`, match lines matching `^  [a-z_]+:$`) and state nodes from mermaid (grep `-->` lines, strip transition labels and `[*]`). Sort and diff both sets. Produces a clean yes/no signal.

- Difficulty: low — pure awk/grep, no YAML parser needed
- False positive rate: very low — only fires on real drift
- Maintenance cost: zero — the check only needs to change if state extraction logic changes, not when states change
- Value: high — would have caught any accidental state rename or addition that was reflected in only one file

**Check 2: context-exists gate key names appear in directive prose for the same state**

Implementation: For each state that has a `context-exists` gate, extract the gate's `key:` value. Find the corresponding `## <state>` section in the directive prose (after the second `---`). Check whether the key name (with backticks) appears in that section. This requires parsing the file in two passes: first the YAML frontmatter for state/gate/key mappings, then the prose sections.

- Difficulty: medium — requires careful section boundary detection, but achievable with awk
- False positive rate: low for states that already document their output keys clearly; higher for states whose directives delegate to phase reference files (the reference file may name the key while the directive does not)
- Maintenance cost: low — the check doesn't need updating when keys change, only if documentation conventions change
- Value: medium-high — would have caught the `review_results` vs `review_results.json` class of bug if the directive had said the wrong key name
- Caveat: Many `work-on.md` states direct agents to `references/phases/<file>.md` for steps; the key naming lives in those files, not in the directive prose, which limits how much this check can verify without also parsing reference files

**Check 3: default_template value exists as a sibling file**

Implementation: grep `default_template:` from the YAML frontmatter, extract the value, check that a file with that name exists in the same directory as the template.

- Difficulty: very low — two greps and a file test
- False positive rate: near zero
- Maintenance cost: near zero
- Value: medium — prevents silent breakage when a child template is renamed or moved; not a high-frequency failure mode but easy enough that it's worth adding

**Check 4: workflow name in koto next calls matches YAML name field**

Implementation: extract `name:` from frontmatter; grep directive prose for `koto next <name>` patterns; compare.

- Difficulty: low
- False positive rate: low
- Maintenance cost: low
- Value: medium — catches the hardcoded-name class of bug (workflow renamed but prose scripts not updated)

### Top 3 recommendations

1. **Mermaid/YAML state sync check (Check 1)** — highest value, lowest difficulty, zero false positives. Add as `scripts/validate-template-mermaid.sh` with a new CI job `check-template-consistency.yml` triggered on `skills/*/koto-templates/**`. The script loops over all `*.md` (non-mermaid) templates, finds its companion `*.mermaid.md`, and diffs the state sets.

2. **default_template file existence check (Check 3)** — near-zero effort to write, catches a real class of rename-related bugs. Can be added to the same script as Check 1 as a secondary validation step.

3. **Workflow name in koto next calls (Check 4)** — slightly lower value than Check 2 because the hardcoded-name bug only matters during template rename, but trivial to implement alongside Checks 1 and 3.

Check 2 (context key in directive prose) is valuable in principle but less reliable due to delegation to reference files. It would produce false negatives for most states in `work-on.md` since those states say "Read references/phases/..." rather than naming the key directly. Worth revisiting once the reference file conventions stabilize.

## Implications

The two `.mermaid.md` files are currently in sync with their YAML counterparts, so there is no immediate bug to fix. Adding Check 1 now establishes the invariant for future edits. The marginal cost of a drift bug is high (the mermaid is used for human orientation during live execution, so stale diagrams mislead agents and users), making this enforcement worthwhile even at zero current drift.

The context key check (Check 2) would have caught the `review_results` vs `review_results.json` incident if it had been written as a directive-level key name mismatch. In the current template the keys are consistent, but the check's coverage is limited by the reference-file delegation pattern: agents follow phase reference files, so a mismatch in a reference file would not be caught by checking directive prose only. A stronger version of Check 2 would also scan phase reference files for `koto context add <WF> <key>` lines and cross-reference against gate key names.

Adding Check 3 (default_template file existence) closes a gap with very little code. It doesn't require a test file itself since it only does a path existence check.

## Surprises

Both mermaid files are exactly in sync today. The concern about drift was legitimate given the template complexity, but it hasn't materialized yet. This suggests the current workflow for updating templates (likely manual side-by-side editing) has been effective — but it's fragile as the templates grow.

The `work-on-plan.md` template has no `context-exists` gates at all — it reads context from `koto context get` in prose scripts only, not via gate machinery. This means the gate-key-to-prose check (Check 2) would apply only to `work-on.md`, not to the plan orchestrator template. The plan orchestrator's context reads are invisible to the gate system, which is a design decision that limits what CI can verify about its data flow.

The `koto next work-on-plan` hardcoded name in the `spawn_and_await` directives matches the YAML `name:` field today. This would be caught by any rename, but given the template names have been stable, this is low risk.

## Open Questions

1. Would the mermaid validation script need to handle self-loop transitions (e.g., `analysis --> analysis`)? These appear in both the YAML and mermaid today and should be handled correctly by the node extraction approach.

2. Should Check 1 cover only `work-on` templates or all koto templates in the repo? The current mermaid pattern is specific to work-on; other skills may not have `.mermaid.md` companions.

3. For Check 2's stronger variant (scanning reference files): should it be a separate script or extend the existing one? The reference files live in `references/phases/`, not in `koto-templates/`, so a separate path trigger would be needed.

4. Is `koto template compile` (validate-templates.yml) actually capable of catching structural errors like missing state-section correspondence, or does it only check YAML syntax? If it validates state-to-section matching, Check 1 might partially overlap.

## Summary

The two `.mermaid.md` files are currently in sync with their YAML state machines, and the context key names in gate definitions match directive prose throughout `work-on.md`. No existing CI job enforces these invariants. The three highest-value, lowest-maintenance checks to add are: (1) a state-set diff between each YAML template and its `.mermaid.md` companion, (2) a `default_template` file existence check, and (3) a workflow-name-in-prose consistency check — all implementable as a single bash script (`validate-template-mermaid.sh`) triggered by the existing `skills/*/koto-templates/**` path pattern.

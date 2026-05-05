# Lead: Demand validation — reusable GHA workflows for shirabe doc format validation

## Summary

Evidence supports pursuing this topic, but all demand traces to a single author (dangazineu). There are no external requesters, community members, or independent issue reporters. The pattern is recognizable: internal maintainer identifying a real workflow problem, filing a well-scoped issue, and now exploring a design. The demand is real and the problem is visible in the codebase, but it has not been validated by distinct voices.

---

## Question 1: Is demand real?

**Confidence: Medium**

One explicit issue exists: shirabe #4 ("CI validation portability -- reusable workflows with config-driven validation", opened 2026-03-17 by dangazineu, state: OPEN, label: needs-design). It describes parameterizing validation scripts and building reusable GHA workflows external repos can reference via `uses:`.

Corroborating evidence from the codebase: tsuku has a working `validate-design-docs.yml` workflow plus a full suite of modular check scripts (`frontmatter.sh`, `sections.sh`, `status-directory.sh`, `implementation-issues.sh`, `mermaid.sh`) under `.github/scripts/checks/`. These exist in tsuku but not in shirabe, koto, or niwa. Koto has design docs (`docs/designs/current/`) with the same frontmatter schema. Niwa has design docs too. Neither koto nor niwa has CI that validates those docs. The gap is real and observable.

Additionally, `PRD-reusable-release-system.md` (status: Done) cites "Shirabe issue #4 explicitly asks for reusable workflows" as motivation for that PRD's own reusable workflow scope — so the issue was acknowledged by the maintainer in a shipped document.

No external contributors, no community discussion threads, no separate issue reporters were found.

## Question 2: What do people do today instead?

**Confidence: High**

Two workaround patterns are present in the codebase:

**Pattern A: Copy scripts into each repo.** The scope document (`wip/explore_gha-doc-validation_scope.md`) explicitly names this: "tsuku has a working example of plan-doc validation (validate-plan.sh + check-plan-docs.yml), but these scripts originated in the private tools repo and were copied into tsuku -- the old pattern." The tsuku `validate-plan.sh` and `check-plan-docs.yml` are copies. Shirabe has its own `skills/plan/scripts/validate-plan.sh` and `check-plan-docs.yml`, a second copy.

**Pattern B: No validation at all.** Koto and niwa have design docs with frontmatter requirements identical to shirabe's but zero CI enforcement. Those docs go unvalidated. There is no reusable workflow being called; there is nothing.

Neither pattern is an intentional workaround. Pattern A produces maintenance drift; Pattern B leaves quality gaps undetected.

## Question 3: Who specifically asked?

**Confidence: Medium**

Single source:

- **shirabe issue #4** ("CI validation portability -- reusable workflows with config-driven validation"), opened 2026-03-17, author: dangazineu, label: needs-design, state: OPEN, zero comments. No other reporters.

The PRD `PRD-reusable-release-system.md` (merged, status: Done) references issue #4 as motivating evidence for the reusable release system, which was implemented. That reference is the closest thing to maintainer acknowledgment in a shipped artifact. No issue comments or PR discussion threads reference issue #4 independently.

## Question 4: What behavior change counts as success?

**Confidence: Medium**

Issue #4's acceptance criteria define the target state for the broader CI portability effort (which includes but isn't limited to doc format validation):

- Four core validators (frontmatter, sections, status-directory, implementation-issues) parameterized via YAML config
- Reusable GHA workflows published in shirabe
- Default config works out of the box (no customization needed for standard setup)
- Config schema documented
- Thin caller workflow template available (~10 lines each)
- Version pinning via tags (`@v1`)
- At least one external repo tested as a consumer

The issue explicitly excludes the mermaid diagram validator ("1024 lines, 21 rules") as out of scope, noting it needs architectural splitting first.

The topic under exploration (doc format validation specifically) is a subset of issue #4. Issue #4 does not state acceptance criteria specific to AI-powered semantic validation -- that tier does not appear in any open issue or acceptance criteria. It surfaces only in the scope document as a user-stated aspiration.

## Question 5: Is it already built?

**Confidence: High (mostly absent)**

No reusable `workflow_call` workflow for doc format validation exists in shirabe. The two existing `workflow_call` workflows in shirabe are both for the release system (`release.yml` and `finalize-release.yml`), not for doc validation.

What does exist in shirabe today (none of which is reusable):

- `check-plan-docs.yml`: inline bash that calls `skills/plan/scripts/validate-plan.sh` on changed PLAN files. Not `workflow_call`. Not consumable by downstream repos.
- `check-template-consistency.yml`: runs `scripts/validate-template-mermaid.sh`. Not `workflow_call`.
- `validate-templates.yml`: calls `tsukumogami/koto/.github/workflows/check-template-freshness.yml@main` -- this is a caller, not a reusable workflow that others call.

What does exist in tsuku (not reusable from shirabe):

- `validate-design-docs.yml`: full modular design doc validator using `frontmatter.sh`, `sections.sh`, `status-directory.sh`, `implementation-issues.sh`. These live in tsuku's `.github/scripts/checks/` and are not exposed as reusable workflows.

Summary: the validation logic exists in tsuku as non-reusable scripts. Shirabe has per-format validation that is not reusable. No workflow is published at the `uses:` level for external consumption.

## Question 6: Is it already planned?

**Confidence: Medium**

Issue #4 is open, labeled `needs-design`, and has no assignee. It represents the planned scope but has not moved beyond the open/unassigned state since 2026-03-17.

No design document for this topic exists in `docs/designs/current/`. The explore session producing this report appears to be the first structured work toward a design. No roadmap entry mentions doc validation portability.

The `ROADMAP-strategic-pipeline.md` contains one tangential mention: "CI should validate it" under a cross-cutting consideration, and "Add `validate_transition()` to design doc transition script" -- but these refer to transition-gate enforcement, not reusable GHA workflows for downstream consumption.

The AI-powered semantic validation tier is not planned in any issue, design doc, or roadmap.

---

## Calibration

**Demand not validated** (not "demand validated as absent").

The distinction matters here. This is not a case where someone evaluated the idea and rejected it, or where the problem is demonstrably absent. The evidence shows:

- One well-scoped issue from one author (issue #4)
- A real, observable gap: design docs in koto and niwa go unvalidated; tsuku's validation scripts aren't reusable
- No external requesters, no community discussion, no independent corroboration
- No rejection evidence — the idea hasn't been surfaced publicly in a way that could be rejected

The demand case rests entirely on maintainer self-identification of a workflow problem. That is real demand but weak validation. A single-author issue with no community signal means the feature could be deprioritized indefinitely without anyone noticing externally. It also means the design does not need to optimize for diverse user requirements — the consumer profile is narrow and known.

The AI-powered semantic validation tier specifically has no demand artifact at all. No issue requests it. No acceptance criteria mention it. It appears only in the scope doc as a design question ("what could AI validation provide that static analysis can't"). That tier is a hypothesis, not a demand signal.
# Lead: Private tools repo script-copy pattern vs. reusable workflows

## Findings

### What exists in the private tools repo

The private tools repo (`private/tools/`) contains the canonical source for doc validation logic:

- `scripts/ci/validate-design-doc.sh` — orchestrator script that runs each check module
- `scripts/ci/checks/common.sh` — shared utilities (emit_pass, emit_fail, extract_frontmatter, EXIT_* constants)
- `scripts/ci/checks/frontmatter.sh` — FM01/FM02/FM03 checks (required fields, valid status, frontmatter-body agreement)
- `scripts/ci/checks/implementation-issues.sh` — II00–II08 checks (section presence, table format, strikethrough consistency)
- `scripts/ci/checks/mermaid.sh` — diagram syntax and class validation
- `scripts/ci/checks/sections.sh`, `status-directory.sh`, `strikethrough-all-docs.sh`, `issue-status.sh` — further check modules
- `workflows/validate-design-docs.yml` — workflow that calls validate-design-doc.sh
- `workflows/validate-closing-issues.yml`, `validate-diagram-classes.yml`, `validate-diagram-status.yml` — three more doc-related workflows

### How tsuku received these files

tsuku's `.github/scripts/` and `.github/workflows/` directories are byte-for-byte copies of the private tools originals. The diff between private tools and tsuku is zero for all four doc-validation workflows and for all shared check scripts. The only differences are two tsuku-specific additions that have no private tools counterpart: `ci-patterns-lint.sh` (workflow anti-pattern detection) and `retired-runners.sh`.

This is the copy pattern: the private tools repo is the source of truth. When a check is added or updated there, each downstream repo (tsuku, and in principle niwa, koto, etc.) must manually copy the updated files. There is no mechanism enforcing synchronization.

### What shirabe has for plan-doc validation

shirabe owns its own doc format (PLAN-*.md) and its own validation script (`skills/plan/scripts/validate-plan.sh`). The workflow `check-plan-docs.yml` calls that script directly:

```yaml
bash skills/plan/scripts/validate-plan.sh "$plan_file"
```

This means `check-plan-docs.yml` can only run inside the shirabe repo. It is self-contained — not a candidate for copying — but also not a reusable workflow.

### The eval-coverage check: a second instance of the copy pattern

`scripts/check-evals-exist.sh` exists in three repos: shirabe, tsuku, and koto. The tsuku and koto versions use a `plugins/*/skills/*/` traversal path (tsuku's monorepo layout). The shirabe version uses a flat `skills/*/` path. The logic is identical; only the directory structure differs. Error messages diverge slightly between koto/tsuku. There is no shared source.

### What the caller must currently maintain

For any repo that wants design-doc validation (tsuku's pattern), the caller must:

1. Copy the entire `scripts/ci/` tree into their `.github/scripts/`
2. Copy all four workflow YAML files into their `.github/workflows/`
3. Manually detect when the private tools repo updates a check and re-copy

For shirabe's plan-doc validation, the caller (currently only shirabe itself) must have the validate-plan.sh script present in the expected relative path.

### No reusable workflow calls for doc validation yet

`check-templates.yml` in shirabe already uses the reusable pattern:

```yaml
uses: tsukumogami/koto/.github/workflows/check-template-freshness.yml@main
```

This is the only cross-repo `uses:` call for validation. All doc-specific checks remain copy-and-maintain.

## Implications

**The copy pattern has four concrete gaps that reusable workflows fix:**

1. **Drift accumulates silently.** There is no CI gate that detects when tsuku's copy diverges from the private tools master. The only signal is someone manually noticing the scripts are out of date. A reusable workflow hosted in shirabe means all callers always run the same version of the check logic.

2. **Onboarding a new repo requires significant boilerplate.** A new repo wanting design-doc validation must copy ~10 files. With reusable workflows, the callers's entire investment is one `uses:` line plus any required inputs.

3. **Behavioral improvements don't propagate.** When implementation-issues.sh gained II07 and II08 checks, that improvement had to be manually applied to every downstream copy. A reusable workflow makes improvements available to all callers on next run (or at their pinned version).

4. **The script-copy pattern mixes ownership.** tsuku's `.github/scripts/` directory contains both tsuku-specific scripts (`ci-patterns-lint.sh`, `retired-runners.sh`, `install-recipe-deps.sh`) and unmodified copies from private tools. This creates confusion about which files are owned where and makes future updates harder to reason about.

**The check-evals-exist divergence illustrates a secondary gap:** when the same logical check needs slightly different traversal paths per repo (flat `skills/*/` vs. nested `plugins/*/skills/*/`), the copy pattern forces duplication. A reusable workflow with an `inputs:` parameter for the skill-discovery path would handle both layouts from a single definition.

## Surprises

- The four doc-validation workflows in tsuku are exact copies — not near-copies — of the private tools originals. There are zero diffs. This means the copy happened cleanly and has not yet drifted, but it also means any improvement made in tsuku has not been pushed back to the source and would need to be re-applied there.

- tsuku has two check scripts (`ci-patterns-lint.sh`, `retired-runners.sh`) with no private tools counterpart. These are tsuku-specific concerns not yet generalized. They represent functionality that shirabe would need to decide whether to support as configurable options or leave as caller-owned.

- shirabe's `check-plan-docs.yml` uses `actions/checkout@v4` (unpinned tag) while tsuku's workflows use pinned SHAs (`actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd`). These conventions would need aligning in any reusable workflow design.

- koto already publishes a reusable workflow (`check-template-freshness.yml`) that shirabe calls. The pattern exists and works. The question is only which validations to centralize in shirabe.

## Open Questions

1. **Who owns the private tools scripts going forward?** If shirabe becomes the canonical home for design-doc validation, the private tools copies become redundant. Does the migration plan include removing or redirecting the private tools copies?

2. **What inputs does a reusable design-doc workflow need?** The current scripts hardcode `docs/designs/` as the document root and `DESIGN-*.md` as the filename pattern. Do downstream repos follow these conventions, or do they need override parameters?

3. **How should grandfathering work across repos?** The current `validate-design-doc.sh` uses `get-file-creation-commit.sh` and a hardcoded cutoff date (`II_CHECK_CUTOFF="2026-01-01"`) to exempt files created before a check was introduced. A reusable workflow used by multiple repos with different doc histories needs a configurable cutoff or a different grandfathering strategy.

4. **Will tsuku migrate from copy to reusable?** The research shows tsuku is the primary downstream consumer of the doc-validation scripts. If tsuku keeps its copies, the reusable workflow serves only future adopters. Is tsuku migration in scope?

5. **Does the check-evals-exist consolidation belong here?** The eval-coverage check is duplicated across shirabe, tsuku, and koto with layout-specific differences. A reusable workflow with a `skill-paths` input could unify them, but that broadens scope beyond design-doc validation.

## Summary

The private tools repo holds the master copy of four design-doc validation workflows and ~10 supporting scripts; tsuku received these files as exact copies with no synchronization mechanism, meaning any update requires manual re-copying into each downstream repo. This copy-and-maintain pattern is the specific gap that reusable GHA workflows fix: by centralizing the logic in shirabe and having callers use a `uses:` line, improvements propagate automatically and new repo adoption drops from ~10 files to one workflow reference. The biggest open question is whether tsuku will migrate from its existing copies to the reusable pattern, since without that migration the reusable system serves only future adopters and the duplication remains.

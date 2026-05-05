# Lead: Existing validation structure in shirabe

## Findings

### Plan: The only doc type with CI validation today

**Script**: `skills/plan/scripts/validate-plan.sh`

This is the only document-type validation script that runs in CI. It validates a single PLAN.md file passed as an argument and exits with structured codes:

- `0` — valid
- `1` — malformed input (file not found, not readable)
- `2` — frontmatter validation failure
- `3` — upstream validation failure

What it checks:

1. **File existence and readability** — basic IO checks.
2. **Frontmatter presence** — the file must start with `---` on line 1.
3. **`schema` field** — must equal `plan/v1` exactly.
4. **`execution_mode` field** — must be present (non-empty); no enum validation.
5. **`issue_count` field** — must be present (non-empty); no numeric validation.
6. **`upstream` field (optional)** — if present, the referenced file must (a) exist on disk, (b) be tracked by git (`git ls-files --error-unmatch`), and (c) have `status: Accepted` or `status: Planned` in its frontmatter.

What it does NOT check:

- `execution_mode` value (e.g., `single-pr` vs `multi-pr`) is not validated against an enum.
- `issue_count` is not validated as an integer or that it matches actual issue count.
- No section-presence checks (e.g., required headings like `## Status`, `## Issues`).
- No status field validation in the PLAN itself (only in the upstream design).
- No naming convention enforcement (e.g., filename must match `PLAN-*.md`).
- No checks for design, prd, vision, roadmap, or decision doc types.

**GHA workflow**: `.github/workflows/check-plan-docs.yml`

Triggers on PRs that touch `docs/plans/PLAN-*.md`. Uses `fetch-depth: 0` (full history). Iterates over files changed between `base.sha...HEAD` and calls `bash skills/plan/scripts/validate-plan.sh "$plan_file"` for each. Accumulates failures with a `FAILED` flag and exits non-zero if any fail.

The script is called with a **relative path from the repo root** (`bash skills/plan/scripts/validate-plan.sh`), meaning the workflow assumes the script lives at that exact location in the consuming repo. This is repo-specific, not reusable.

**Script tests**: `skills/plan/scripts/validate-plan_test.sh`

A self-contained bash test suite with 11 tests covering all exit codes and upstream states. Tests spin up a temporary git repo via `mktemp -d` + `git init`. Runs in CI via `.github/workflows/check-plan-scripts.yml`, which tests on both ubuntu-latest and macos-latest and installs jq and bash 5 (macOS ships bash 3.2; the script uses `declare -A`).

---

### Design, PRD, Vision, Roadmap: transition-status scripts only, no CI validation

Each of these four doc types has a `transition-status.sh` script that handles status transitions and in-place frontmatter edits. None of them have standalone validation scripts, and none are invoked from CI on PRs. They are agent-side tools for the skill workflow, not CI guardrails.

**design** (`skills/design/scripts/transition-status.sh`):
- Accepts: `Proposed`, `Accepted`, `Planned`, `Current`, `Superseded`
- Moves files between `docs/designs/`, `docs/designs/current/`, `docs/designs/archive/` based on status
- Handles `superseded_by:` frontmatter injection
- Supports both YAML frontmatter and legacy `## Status` body format
- Outputs JSON (`{success, doc_path, old_status, new_status, new_path, moved, superseded_by?}`)
- No transition graph enforcement (any status can transition to any other)

**prd** (`skills/prd/scripts/transition-status.sh`):
- Accepts: `Draft`, `Accepted`, `In Progress`, `Done`
- No directory movement (all PRDs stay in `docs/prds/`)
- Supports YAML frontmatter and legacy body format
- Outputs JSON (`{success, doc_path, old_status, new_status}`)
- No transition graph enforcement

**vision** (`skills/vision/scripts/transition-status.sh`):
- Accepts: `Draft`, `Accepted`, `Active`, `Sunset`
- Moves `Sunset` docs to `docs/visions/sunset/`
- Enforces a strict transition graph: `Draft -> Accepted -> Active -> Sunset` (no regressions; no skipping steps)
- Validates `## Open Questions` section is empty before `Draft -> Accepted`
- Outputs JSON with `moved` and optional `superseded_by`

**roadmap** (`skills/roadmap/scripts/transition-status.sh`):
- Accepts: `Draft`, `Active`, `Done`
- No directory movement (all stay in `docs/roadmaps/`)
- Enforces: `Draft -> Active -> Done`; `Done` is terminal; no regressions
- Validates `### Feature` heading count >= 2 before `Draft -> Active`
- Outputs JSON with `moved`

**Decision**: No scripts at all under `skills/decision/scripts/`. Only phases and an evals file.

---

### Other CI workflows (not doc-type validation)

`.github/workflows/check-plan-scripts.yml` — runs `validate-plan_test.sh` and `plan-to-tasks_test.sh` on ubuntu + macos when plan scripts change. Not about validating docs, but about validating the scripts themselves.

`.github/workflows/check-template-consistency.yml` — runs `scripts/validate-template-mermaid.sh` when koto templates change. Validates Mermaid diagrams embedded in koto workflow template files.

`.github/workflows/check-templates.yml` — calls `tsukumogami/koto/.github/workflows/check-template-freshness.yml@main` as a **reusable workflow** (the one existing reusable-workflow callsite in shirabe). Validates koto template freshness.

`.github/workflows/validate-templates.yml` — installs tsuku and koto, then runs `koto template compile` against all `*/koto-templates/*.md` files. Not doc validation.

`.github/workflows/check-evals.yml` — runs `scripts/check-evals-exist.sh` on any skill change. Checks that every user-invocable skill has at least one eval scenario in `evals/evals.json`.

`.github/workflows/run-evals.yml` — scheduled (Mondays 04:00 UTC) and workflow_dispatch. Installs `claude` CLI and `skill-creator` plugin, then runs `scripts/run-evals.sh`.

`.github/workflows/check-sentinel.yml` — runs `scripts/check-sentinel.sh` when `.claude-plugin/**` changes. Validates plugin manifest version sentinels.

---

### How the GHA workflow references the script

`check-plan-docs.yml` calls `bash skills/plan/scripts/validate-plan.sh "$plan_file"` — a hardcoded relative path into the shirabe repo's own tree. No action wrapping, no `uses:` reference. This means the workflow only works when run from the shirabe repo itself, not from a downstream repo. It is not reusable in its current form.

The one example of reuse already present is `check-templates.yml`, which uses `uses: tsukumogami/koto/.github/workflows/check-template-freshness.yml@main`. This is the pattern the reusable model would extend.

---

## Implications

1. **Only one doc type has CI validation (plan), and it's not reusable.** Design, PRD, vision, roadmap, and decision have zero CI-enforced validation. The new system needs to cover all doc types.

2. **Validation and mutation are separate concerns today.** `validate-plan.sh` is purely read-only with structured exit codes. `transition-status.sh` scripts are write-only mutators. This clean separation is a useful model to preserve.

3. **The "tier" distinction already exists implicitly.** The transition scripts encode content preconditions (Open Questions empty, Feature count >= 2) that are richer than the purely structural checks in validate-plan. The reusable system needs to distinguish these tiers: (a) schema/structure checks (fast, always-on), (b) status-lifecycle checks (reject invalid transitions), and (c) content-quality checks (section completeness, upstream chain integrity).

4. **Portability requires wrapping scripts as actions.** The current pattern (`bash skills/plan/scripts/validate-plan.sh`) only works when the script is co-located in the consuming repo. Reusable GHA workflows require either (a) the script to be called from a `uses:` composite action published from shirabe, or (b) the workflow to download the script at runtime. The koto precedent (`uses: tsukumogami/koto/.github/workflows/...@main`) is the cleaner model.

5. **The validate-plan script is the template.** Its exit code conventions (1=malformed input, 2=schema, 3=upstream), argument handling, and awk-based frontmatter extraction are production-quality and tested. These patterns should be replicated across other doc types rather than rewritten.

6. **No design, prd, vision, or roadmap script validates for CI.** These types currently have no enforcement at PR time. If a PR lands a design doc with a missing `schema:` field or an invalid status, nothing catches it.

---

## Surprises

1. **Vision and roadmap transition scripts enforce transition graphs; design and PRD do not.** This inconsistency is undocumented — there's no central place that says which doc types have graph enforcement.

2. **Design's transition script has no graph enforcement at all.** Any status can jump to any other. Vision's script, by contrast, rejects regressions and skips. This asymmetry will create confusion if CI validation is added later.

3. **The plan validator checks git tracking of upstream files.** This is a stronger check than just existence — it means a newly created but unstaged design doc will fail CI. This is intentional (the doc must be committed before planning can proceed) but non-obvious.

4. **`execution_mode` and `issue_count` values are not validated beyond presence.** An `execution_mode: banana` would pass validation. This is a gap if the consuming tools (plan-to-tasks.sh, cascade) depend on specific values.

5. **There are no validation scripts at all for decision records, spike reports, competitive analyses, or VISION docs.** These types exist (skills and templates are present) but have zero CI enforcement.

---

## Open Questions

1. **What are the required frontmatter fields for design, prd, vision, and roadmap docs?** There's no single source of truth — the format lives in the skill's `SKILL.md` or phase references. Extracting those constraints is the prerequisite for writing validators.

2. **Should status-transition enforcement be part of CI validation or remain only in the agent-side scripts?** Enforcing status graph transitions in CI is complex (the CI runner would need to know the previous committed status), while agent-side enforcement happens before commit.

3. **What's the intended interface for downstream repos?** Will they call a composite action (`uses: shirabe/...`), a reusable workflow (`uses: .../.github/workflows/...`), or download and run a script? The answer determines the packaging model.

4. **Does the reusable workflow system need to support custom doc paths?** `check-plan-docs.yml` hardcodes `docs/plans/PLAN-*.md`. Downstream repos might store docs elsewhere.

5. **Which doc types should be in the first release of reusable workflows?** Plan has a working validator. Design seems the highest-priority addition given its role as an upstream dependency for plans.

6. **Should `execution_mode` and `issue_count` be validated against enums?** This requires knowing the canonical allowed values, which are defined by the plan skill rather than the validator.

---

## Summary

The only CI-enforced doc validation in shirabe today is `validate-plan.sh`, a tested bash script that checks YAML frontmatter structure (schema, execution_mode, issue_count) and an optional upstream design doc's existence, git tracking, and status — but it's invoked via a hardcoded path in a non-reusable workflow, so it runs only in the shirabe repo itself. Design, PRD, vision, roadmap, and decision docs have no CI validation at all; they have only agent-side `transition-status.sh` mutators that run during skill workflows. The main implication is that the reusable workflow system needs to start by extracting the validate-plan pattern into a composite action (making it portable to downstream repos) and then build equivalent validators for the other doc types using the same exit code conventions. The biggest open question is what the required frontmatter schema is for each doc type — that information is scattered across skill phase references and SKILL.md files, not in any single schema definition.

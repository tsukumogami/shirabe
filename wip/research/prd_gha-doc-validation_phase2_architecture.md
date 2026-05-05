---
schema: research/v1
status: Draft
---

# Phase 2 Research: Architecture & Ops

## Lead A: Grandfathering Approach

### Findings

**validate-plan.sh has no cutoff logic.**

The script validates whatever file it's given, unconditionally. Its grandfathering is implicit: `check-plan-docs.yml` only passes files returned by `git diff --name-only "$BASE_REF"...HEAD -- 'docs/plans/PLAN-*.md'`, so only files changed in the PR are ever validated. No file touched before the workflow was introduced is ever surfaced unless someone edits it. The "grandfathering" in check-plan-docs is structural — it falls naturally out of the changed-files-only scan.

**tsuku's validate-design-docs.yml uses a different strategy: validate ALL docs, but grandfather individual checks by file creation date.**

tsuku runs on every PR and scans every `DESIGN-*.md` in the repo (not just changed files). To handle docs that predate specific checks, it uses a hardcoded cutoff date per check category:

```bash
readonly II_CHECK_CUTOFF="2026-01-01"  # Implementation Issues validation introduced
```

The helper `get-file-creation-commit.sh` resolves the first git commit that introduced a file (`git log --follow --diff-filter=A`), extracts its ISO date, and compares lexicographically against the cutoff. If the file predates the cutoff, the check is silently skipped. The orchestrator requires `fetch-depth: 0` to access full history for this comparison.

This approach was built explicitly for the "scan all docs" pattern — without it, adding any new check would break CI for every pre-existing doc that doesn't satisfy it.

**Key observation: the two existing approaches are structurally opposed.**

- changed-files-only (shirabe/check-plan-docs.yml): naturally scopes to work in the PR; no cutoff machinery needed; never sees pre-existing docs
- all-docs with cutoff dates (tsuku/validate-design-docs.yml): detects drift in untouched docs; requires git history; requires ongoing cutoff maintenance as new checks are introduced

**run-evals.yml workflow_call pattern.**

The existing `finalize-release.yml` and `release.yml` already use `workflow_call` with `required: false` secrets — proving the pattern works in this repo. No secrets are used in the proposed static validation workflow (no AI tier), so this is not a blocker but confirms the infrastructure is in place.

### Recommended Approach

**Changed-files-only** is the right default for the reusable workflow.

The reasoning:

1. It's already proven in shirabe's own check-plan-docs.yml and matches the natural GHA PR pattern.
2. It requires no git-history machinery, no cutoff constants, and no ongoing maintenance when new checks are introduced.
3. It's safe for downstream adoption: on day one, no existing docs fail CI because only changed docs are checked.
4. It produces honest signal: CI failures mean "this PR introduced a problem," not "this repo has accumulated technical debt."

The tsuku all-docs approach is appropriate when the goal is a periodic health scan (e.g., a scheduled workflow or a nightly lint). For a PR check that controls merge, changed-files-only is the correct primitive. A separate scheduled "audit all docs" mode can be offered as an opt-in input (`scan_all: true`) for repos that want drift detection.

The configurable cutoff date and warning-only mode approaches both have maintenance overhead and add accidental complexity: teams must track which date they adopted the workflow and update it when checks evolve. Explicit suppression comments add per-file ceremony and are hard to audit at scale. Neither is warranted when changed-files-only already solves the day-one breakage problem cleanly.

### Implications for Requirements

- The reusable workflow MUST default to scanning only files changed in the PR (`git diff --name-only BASE...HEAD`).
- A `scan_all` boolean input (default: `false`) SHOULD be offered for scheduled drift-detection runs.
- The workflow MUST use `fetch-depth: 0` on checkout regardless, because upstream chain validation (`upstream` field in Plan docs) requires resolving files anywhere in the repo, and the changed-files path pattern still needs to know the base SHA.
- No cutoff date input is required in the blocking PR path. If `scan_all` is added later, a `grandfather_cutoff` input can accompany it.
- The exit-code convention (0/1/2/3) from validate-plan.sh SHOULD be replicated in any new per-format validator scripts, for consistency and testability.

### Open Questions

1. Should `scan_all` mode emit warnings (non-blocking) or hard failures for pre-cutoff docs? If scan_all is advisory-only, a cutoff date becomes irrelevant — it can always fail. Needs a product decision.
2. Does the workflow need to distinguish "no matching files changed" (skip cleanly) from "files changed but all passed"? Currently check-plan-docs.yml exits 0 in both cases — this is fine but may confuse status check dashboards.
3. When a doc is renamed (not content-changed), should the new name be validated? `git diff --name-only` with `--diff-filter=ACMR` would capture renames explicitly; the current check-plan-docs.yml does not filter, so renames are included automatically.

---

## Lead B: Blocking vs. Advisory and Runner Quota

### Findings

**check-plan-docs.yml is not explicitly declared as a required status check in the workflow file itself.**

GHA workflow files cannot declare themselves as required — that setting lives in the repository's branch protection rules (Settings > Branches > Require status checks). The workflow file only defines the job name (`validate-plan-docs`). Whether that job blocks merges is a repo admin decision made in branch protection, not in the YAML.

This means: the reusable workflow cannot enforce its own blocking status. Each downstream repo must opt in by adding the job name as a required status check in their branch protection rules. This is standard GHA behavior and not a gap — it's by design.

The scope document says the intent is blocking. For shirabe's own use, the PRD can require that `validate-plan-docs` (or the equivalent job name from the new workflow) be added to shirabe's branch protection rules as a required check. For downstream repos, the PRD can document this as a setup step, but cannot enforce it.

**Practical day-one breakage risk.**

Because the workflow uses changed-files-only (as recommended in Lead A), setting it as a blocking required check on day one carries low risk: it only fails on docs actively touched in a PR. The only scenario where a contributor hits an unexpected block is when they edit a pre-existing malformed doc — which is arguably correct behavior (surface the problem when someone is already in that file).

If the all-docs scan were the default, blocking would create a high day-one risk: every PR on a repo with pre-existing non-conforming docs would fail until all docs were fixed, even if the PR touched none of them. This reinforces the Lead A recommendation.

**Runner quota: who pays for compute when downstream repos call the reusable workflow.**

When a downstream repo uses `uses: tsukumogami/shirabe/.github/workflows/validate.yml@main`, the job runs on a runner from the **downstream repo's (caller's) account**, not shirabe's. This is documented GHA behavior: reusable workflow jobs consume the billing quota of the repository that triggers the workflow (the caller), not the repository that defines the workflow (shirabe).

Concretely:
- A downstream public repo: GitHub-hosted runners are free for public repos; no quota concern.
- A downstream private repo: runner minutes are billed to the downstream org's account. The static validation workflow is expected to be fast (bash script, no installs) — likely under 60 seconds per run — so per-run cost is negligible.
- shirabe itself: runs against shirabe's quota for shirabe's own PRs only.

There is no scenario where downstream adoption increases shirabe's runner consumption. The "runner quota: all compute runs against shirabe's GitHub Actions minutes" framing in the scope document is incorrect. The PRD should clarify this with a documentation note, not a requirement.

### Implications for Requirements

- The PRD MUST NOT promise that the reusable workflow enforces blocking in downstream repos — it cannot. Instead: "downstream repos must add the job name as a required status check in branch protection to enforce blocking."
- The PRD SHOULD require that shirabe's own branch protection adds the new workflow's job as a required check, replacing or supplementing check-plan-docs.
- Runner quota is NOT a concern for shirabe's operational costs. The PRD should include a note stating that compute runs in the caller's account, not shirabe's — this is a selling point for downstream adoption.
- If the PRD specifies a job name for the reusable workflow, it should be stable (not change between versions), because downstream repos hard-code the job name in branch protection rules. A name change silently removes blocking without any visible error.
- The workflow should fail fast (exit early on first malformed file, or collect all errors and exit 1 at the end) — either model works, but collecting all errors and reporting them together is more useful for contributors fixing multiple issues in one pass.

### Open Questions

1. Should the reusable workflow expose a stable job name as a documented contract, or leave it implicit? Downstream branch protection rules break silently if the job is renamed — worth calling out in the PRD as a versioning constraint.
2. What is the targeted p95 runtime for the workflow? If it's consistently under 30 seconds, that's a useful selling point for downstream adoption. No measurement exists yet.
3. Should the workflow emit GitHub Actions annotations (`::error file=...::`) to surface inline failures in the PR diff view? This is low-effort and significantly improves contributor experience — worth specifying in the PRD.

---

## Summary

For grandfathering, the evidence strongly favors a changed-files-only approach (already used in shirabe's own check-plan-docs.yml) over the tsuku-style cutoff-date approach: it eliminates day-one breakage without any git-history machinery or ongoing cutoff maintenance, and it produces accurate signal for PR reviews. For blocking status and runner quota, the reusable workflow cannot enforce its own blocking — downstream repos must configure branch protection — and compute runs against the caller's account, not shirabe's, so runner quota is not an operational cost for this project. Both findings simplify the PRD requirements: no cutoff-date input is needed in the baseline design, and no runner quota mitigation is needed beyond a documentation note.

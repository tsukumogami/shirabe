# Next steps: GHA doc validation rollout

PR #89 merged. The `shirabe validate` CLI and reusable `validate-docs.yml`
workflow are shipped. Three follow-on steps before the feature is fully live.

## Step 1 — Wire up shirabe itself (priority)

shirabe's own branch protection must eat its own cooking before asking
downstream repos to adopt.

- Add a caller workflow at `.github/workflows/validate-plan-docs.yml` (or
  repurpose the existing one) that calls:
  ```yaml
  uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@main
  ```
  Use `@main` until a stable tag exists; switch to `@v1` after step 2.
- Delete `.github/workflows/check-plan-docs.yml` — it calls a bash script
  inline and only covers Plan docs. The reusable workflow supersedes it.
- Update branch protection: add `validate-docs` as a required status check,
  remove `check-plan-docs` (the old job name is `validate-plan-docs`).

PRD reference: R16.

## Step 2 — Cut the v1 tag

All docs and caller examples pin `@v1`. Nothing downstream can use it
stably until the tag exists.

- Merge step 1 first so the tag commit has the caller workflow in place.
- Then: `git tag v1.0.0 && git push origin v1.0.0`
- This also triggers the `release-binaries.yml` workflow and produces the
  four platform binaries + checksums as a GitHub release.

## Step 3 — Adopt in downstream repos (tsuku, koto, niwa)

Each repo needs:
1. `.github/workflows/validate-docs.yml` caller workflow with
   `paths: ['docs/**']` and `uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v1`
2. `validate-docs` added to branch protection required checks.
3. `schema:` fields added to existing docs incrementally (the schema gate
   skips docs without it, so this can be done gradually without blocking).

See `docs/guides/doc-validation.md` for the full adoption steps.

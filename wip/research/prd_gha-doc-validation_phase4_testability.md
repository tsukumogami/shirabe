# Testability Review

## Verdict: PASS

The acceptance criteria are specific enough to drive a test plan. Most criteria name exact inputs, expected outputs, and observable signals (exit code, annotation type, error message field). A tester could write test cases from the AC list alone. Several criteria have minor gaps or ambiguities addressed below.

## Untestable Criteria

1. **"A downstream repo can invoke the workflow with only this caller file (no other changes)"** — The criterion lists the caller YAML but doesn't specify what "works" means. Does it mean the job starts? Exits 0 on a clean PR? Fails correctly on a bad doc? It's verifiable in practice but needs a pass condition. -> Add: "...the workflow job completes successfully on a PR that touches no doc files."

2. **"A PR that touches no doc files exits 0 with a notice (no failures, no warnings requiring attention)"** — "no warnings requiring attention" is subjective. One tester's notice is another's warning. -> Replace with: "exits 0, emits exactly one `::notice` annotation, and emits zero `::warning` or `::error` annotations."

3. **"The workflow is tagged `v1` on initial release; downstream repos pinning `@v1` receive all patch improvements automatically"** — The second clause ("receive all patch improvements automatically") is a deployment-time property of Git tag movement, not something CI can assert. You can verify the tag exists; you can't verify future patch versions will be pushed to it in a single test run. -> Split into two criteria: (a) the `v1` tag exists on release, (b) the `v1` tag is a mutable floating tag (not a signed immutable tag), which is verifiable by checking the tag object type.

4. **"shirabe's branch protection includes `validate-docs` as a required status check"** — This is a GitHub repository settings check, not a code or workflow artifact check. It can't be verified by a CI job or by inspecting the repository contents; it requires a human or API call to the GitHub admin API. -> Rewrite as: "The GitHub branch protection rule for `main` lists `validate-docs` as a required status check, verified via `gh api` or the repository settings UI."

5. **"All validation errors in a PR are reported before the job exits non-zero (not fail-fast)"** — The criterion is correct in intent but doesn't specify how to verify completeness. A tester could construct a doc with two distinct errors and confirm both appear, but the criterion doesn't say this. -> Add: "A doc with both an FC01 violation and an FC04 violation produces two annotations before the job exits non-zero."

## Missing Test Coverage

1. **R7 public-repo VISION check — private repo behavior**: R7 says public repos must fail if VISION docs contain `## Competitive Positioning`. There's no AC for the inverse: a private repo with the same section must *not* fail. Without this, a tester can't tell if the visibility check is implemented or if the rule is applied unconditionally.

2. **R8 unrecognized prefix skip behavior**: R8 says files that don't match any prefix are skipped without error. The AC for no-match covers "no doc files at all" but doesn't cover a PR that mixes a recognized doc file with unrecognized files (e.g., `CHANGELOG.md`, `README.md`). The unrecognized files should be skipped and only the doc file validated. This combination case is unaddressed.

3. **R9 custom-statuses replaces vs. extends**: The AC only tests that a custom status is accepted (`Delivered` passes). It doesn't test that a formerly-canonical status not in the override list is now *rejected*. If `custom-statuses` replaces the enum rather than extending it, a PRD with `status: Draft` should fail when the override is `[Accepted, Delivered, Done]`. This behavior — replace vs. extend — is undefined in the AC.

4. **R11 annotation format**: R11 specifies `::error file=<path>,line=<N>::<message>`. The AC says annotations appear but doesn't verify the `line=<N>` field is populated or correct. A tester can't confirm inline PR diff placement without a criterion that the line number points to the offending frontmatter line.

5. **R6 Plan upstream field — file exists but is not git-tracked**: R6 says the upstream file must exist *and* be tracked by git. The AC only covers the case where the file does not exist on disk. Missing is the case where the file exists on disk but is not tracked by git (e.g., it's in `.gitignore` or was never `git add`ed). Both conditions must fail, but only one is tested.

6. **R14 stable job name**: The requirement says the job name must not change within a major version. There is no AC for this at all. This is a structural property of the workflow YAML that could be tested by asserting the job ID in `validate-docs.yml` matches a specified string (e.g., `validate`).

7. **R15 performance under load**: The AC says "under 60 seconds for a PR touching 5 doc files" but doesn't specify whether all 5 files must have errors, all must pass, or a mix. Worst-case performance (5 files, all with multiple errors triggering collect-all reporting) may differ from the happy path. The criterion should specify the input scenario.

8. **FC03 mismatch — body section absent**: FC03 checks that frontmatter `status` matches `## Status` section in the body. The AC tests the mismatch case (frontmatter says `Accepted`, body says `Draft`). But what happens if the `## Status` section is entirely absent from the body? FC03 would have nothing to compare against; it's unclear whether this produces an FC03 error, an FC04 error, both, or is silently skipped. No AC covers this.

9. **R9 custom-statuses for Plan format**: The AC only demonstrates an override for `prd`. The Plan format has additional structural rules (R6). There's no AC confirming `custom-statuses` works for `plan`, or that it only overrides the enum and leaves R6 rules intact.

## Summary

The AC set is strong for the core validation rules (FC01-FC04) and for the main adopter workflows. Thirteen of the sixteen requirements map to at least one testable criterion. The gaps cluster in three areas: edge cases within implemented features (R6 git-tracked check, FC03 absent section, R9 replace-vs-extend), configuration verification that requires external tooling (R14 job name, R16 branch protection), and the inverse of public-repo checks (R7 private repo). Four criteria have wording issues that could cause inter-tester disagreement on pass/fail. Fixing the five untestable criteria and adding coverage for the nine missing scenarios would make the AC set unambiguous.

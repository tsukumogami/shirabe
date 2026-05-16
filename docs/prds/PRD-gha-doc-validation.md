---
status: Done
problem: |
  Repos using shirabe's doc formats have no way to enforce structural correctness
  in CI. Only the Plan format has a validator, and it runs only in shirabe's own
  repo via a hardcoded script path — downstream repos can't call it. Teams that
  want validation must copy scripts manually, which creates drift and means
  improvements never reach them automatically.
goals: |
  Validation logic lives in shirabe and is consumed by any downstream repo via a
  single `uses:` reference. All five persistent doc formats are covered. Adopting
  the workflow requires one file and zero script copying.
source_issue: 4
---

# PRD: GHA Doc Validation

## Status

Done

## Problem Statement

shirabe defines five doc formats — Design, PRD, VISION, Roadmap, and Plan — each
with required frontmatter fields, a closed set of valid status values, and required
section headings. The format specs are clear. Enforcement is not.

Today, only Plan docs have CI validation, and that validation is non-reusable: the
`check-plan-docs.yml` workflow calls `skills/plan/scripts/validate-plan.sh` by
relative path, so it only works inside shirabe's own repo. Repos that adopt
shirabe's doc formats can't call it. The other four formats — Design, PRD, VISION,
and Roadmap — have no CI validation at all.

The result: PRs can land with missing required fields, invalid status values, or
frontmatter that disagrees with the doc body. These errors break agent workflows
that parse frontmatter, but nothing catches them at merge time.

Repos that want validation today must copy scripts manually. Improvements made in
shirabe don't reach them unless someone notices and re-copies. Three downstream
repos that use shirabe's doc formats have no doc validation at all despite dozens
of structured documents each.

## Goals

1. Validation logic lives in shirabe. Downstream repos call it via `uses:` and get
   every improvement automatically at their chosen version pin.

2. All five persistent doc formats are covered by one configurable workflow. Callers
   don't need to know which format a file uses — detection is automatic.

3. Adopting the workflow takes one PR: one ~12-line workflow file, no scripts to
   copy, no secrets to configure for the static validation tier.

4. The AI-powered semantic validation tier is acknowledged as a future direction.
   This PRD covers the static, deterministic tier only.

## User Stories

**US1: Repo maintainer enabling doc format enforcement**

As a maintainer of a repo that uses shirabe's doc formats, I want to add doc format
validation with a single PR that adds one workflow file, so that new contributors
get immediate CI feedback on structural errors without any script infrastructure to
maintain.

**US2: Contributor fixing a validation error**

As a contributor who opened a PR with a new Design doc, I want CI to tell me
exactly which required field is missing — with a rule code (e.g., FC01) and the
expected value — so I can fix it without reading the format spec.

**US3: shirabe maintainer propagating a validation improvement**

As a shirabe maintainer who added a new required field to the PRD format, I want
downstream repos to receive that validation rule automatically at their next version
pin upgrade, without requiring them to pull updated scripts.

**US4: Repo with existing docs adopting validation**

As a maintainer of a repo with 50+ existing docs that predate the validator, I
want to enable doc validation without triggering failures on any existing doc
until I explicitly opt it in, so I can adopt incrementally and control which
docs enter validation scope — one at a time if needed.

## Requirements

### Functional

**R1: Reusable workflow published in shirabe.**
`tsukumogami/shirabe/.github/workflows/validate-docs.yml` exists, declares
`on: workflow_call:`, and is callable from any downstream repo via:
```yaml
uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v1
```
The `v1` tag is a mutable floating tag updated on each patch release within the
major version, following the `actions/checkout@v4` convention.

**R2: Changed-files-only scan by default.**
The workflow validates only files changed in the current PR, identified via
`git diff --name-only ${{ github.event.pull_request.base.sha }}...HEAD`. When
called from a non-PR context (e.g., `workflow_dispatch`), the workflow exits 0
with a notice explaining it requires a PR context for changed-file detection.
Files not touched in the PR are never checked.

**R3: Four universal checks across all five formats.**
Every changed file matching a known format prefix is validated for:
- **FC01** — Required frontmatter fields are present (format-specific; see R5)
- **FC02** — The `status` field value is in the accepted enum for the format (see R4)
- **FC03** — The frontmatter `status` matches the `## Status` section body. This
  check fires only when the `## Status` section exists; if it is absent, FC04
  catches it instead.
- **FC04** — All required section headings are present (format-specific; see R5)

The static tier always exits non-zero on any violation. There is no advisory or
warning-only mode in v1.

**R4: Canonical status enums.**
The default accepted values for FC02, by format:

| Format | Valid status values |
|--------|-------------------|
| Design | Proposed, Accepted, Planned, Current, Superseded |
| PRD | Draft, Accepted, In Progress, Done |
| VISION | Draft, Accepted, Active, Sunset |
| Roadmap | Draft, Active, Done |
| Plan | Draft, Active, Done |

Status comparisons are case-sensitive. `accepted` does not match `Accepted`.

**R5: Format-specific required fields and sections.**

| Format | Required frontmatter fields | Required sections |
|--------|----------------------------|------------------|
| Design | status, problem, decision, rationale | Status, Context and Problem Statement, Decision Drivers, Considered Options, Decision Outcome, Solution Architecture, Implementation Approach, Security Considerations, Consequences |
| PRD | status, problem, goals | Status, Problem Statement, Goals, User Stories, Requirements, Acceptance Criteria, Out of Scope |
| VISION | status, thesis, scope | Status, Thesis, Audience, Value Proposition, Org Fit, Success Criteria, Non-Goals |
| Roadmap | status, theme, scope | Status, Theme, Features, Sequencing Rationale, Progress, Implementation Issues, Dependency Graph |
| Plan | status, execution_mode, milestone, issue_count | Status, Scope Summary, Decomposition Strategy, Implementation Issues, Dependency Graph, Implementation Sequence |

The Roadmap `Implementation Issues` and `Dependency Graph` sections are required
even when empty; their presence is the FC04 check, not their content.

The `schema` field is not listed in the required fields above. For all formats,
`schema` is the validation opt-in trigger handled by R8 before FC01 runs. A file
without a `schema` value in the supported range is skipped entirely, so FC01
never fires for it. For Plan docs, absence of `schema: plan/v1` causes the R8
gate to skip the file (notice only) rather than producing an FC01 error.

**R6: Plan structural rules carried forward.**
Plan docs that pass the R8 schema gate (i.e., carry `schema: plan/v1`) are
validated for the rules already in `validate-plan.sh`:
- When an `upstream` field is present, the referenced file must exist on disk and
  appear in `git ls-files HEAD` on the PR branch at the time the workflow runs
  (this includes files staged and committed within the PR itself)

**R7: Public repo VISION check.**
When the workflow runs in a public repository (`github.repository_visibility ==
'public'`), VISION docs must not contain the section headings
`## Competitive Positioning` or `## Resource Implications`. If
`github.repository_visibility` is unset or empty, the check is applied (fail
closed). This check applies to forks of public repositories.

**R8: Format detection by filename prefix, then schema version gate.**
The workflow identifies a file's format by its basename prefix: `DESIGN-`,
`PRD-`, `VISION-`, `ROADMAP-`, `PLAN-`. Prefix matching is on the basename only
(not the full path), is case-sensitive, and recognizes only the uppercase prefixes
listed. Files that don't match any prefix are skipped without error or warning.

After prefix detection, the validator reads the file's `schema` frontmatter field
and checks whether the value is in the supported range for this validator version:

| Format | Supported `schema` value |
|--------|--------------------------|
| Design | `design/v1` |
| PRD | `prd/v1` |
| VISION | `vision/v1` |
| Roadmap | `roadmap/v1` |
| Plan | `plan/v1` |

A file that matches a known prefix but has no `schema` field, or a `schema` value
not in the table above, is skipped: the validator emits one `::notice` annotation
identifying the file and exits without error. This is the opt-in mechanism for
incremental adoption — existing docs without a `schema` field are never validated
until a team explicitly adds the field. A file with a `schema` value in the
supported range proceeds to full validation (FC01–FC04 and any format-specific
checks).

**R9: Configurable status enum overrides.**
The workflow accepts a `custom-statuses` input (optional YAML map, per-format)
that **replaces** the canonical enum for any specified format. Callers that pass
this input must list every status value they want to accept, including any
canonical values they want to keep.

Example — downstream repo that uses `Delivered` alongside standard PRD statuses:
```yaml
uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v1
with:
  custom-statuses: |
    prd: [Draft, Accepted, In Progress, Done, Delivered]
```

A status value not present in the override list fails FC02, including values that
appear in the canonical enum but were omitted from the override. Formats not named
in `custom-statuses` continue to use their canonical enum.

**R10: No-match exit behavior.**
When no files in the PR match any known format prefix — including PRs that modify
only unrecognized files (e.g., `README.md`, `CHANGELOG.md`) — the workflow exits 0
and emits exactly one `::notice` annotation. It emits zero `::warning` or `::error`
annotations.

**R11: GHA annotations for inline error visibility.**
Validation errors are emitted as GitHub Actions error annotations so failures
appear inline in the PR diff view. Annotation format:
`::error file=<path>,line=<N>::[<CODE>] <message>`

Line number conventions by check type:
- FC01 (missing field): line 1 (field is absent; no specific line to reference)
- FC02 (invalid status): the line in the frontmatter block containing the `status:` key
- FC03 (frontmatter/body mismatch): the line of the `## Status` heading in the doc body
- FC04 (missing section): line 1 of the file (section is absent; no specific line)
- R6 upstream failures: line of the `upstream:` key in the frontmatter block

Error messages must be actionable without reading the format spec. Example:
`[FC02] status 'Shipped' is not valid for Design docs. Valid values: Proposed, Accepted, Planned, Current, Superseded`

**R12: Collect-all error reporting.**
The workflow reports all validation failures for a given file before moving to the
next file, and reports all failing files before exiting non-zero. Contributors see
every issue in the PR in one pass rather than fixing one error at a time.

### Non-Functional

**R13: Zero files to copy.**
Adopting the workflow requires only a caller workflow file in the downstream repo.
No scripts, configs, or schema files are copied.

**R13a: shirabe CLI — shared Go implementation, distributed via tsuku and install script.**
Validation logic is implemented as a Go CLI named `shirabe`. Bash is not used for
validation logic. The CLI is the canonical implementation for both CI and local use.

**Distribution:** The `shirabe` binary is available via:
- `tsuku install shirabe` (primary)
- A `curl | bash` install script for environments without tsuku

**GHA workflow:** The reusable workflow builds the binary from shirabe's source
during the workflow run — a second `actions/checkout` step fetches shirabe at the
pinned ref, then `go build` produces the binary. Go is pre-installed on
GitHub-hosted `ubuntu-latest` runners; no additional setup step is required.

**Plugin skills:** Skills that perform local doc validation check whether `shirabe`
is in PATH. If it is not found, the skill offers to install it (via `tsuku install
shirabe` if tsuku is available, otherwise via the curl script). Local validation is
optional: if the user declines or the install fails, the skill continues without it.
CI remains the authoritative validation checkpoint.

**R14: Stable job name within a major version.**
The reusable workflow exposes a job named `validate-docs`. This name does not
change in any v1.x release. Downstream repos that add `validate-docs` to branch
protection rules will not silently lose blocking protection on patch upgrades.

**R15: Fast execution.**
The static validation workflow completes in under 60 seconds for a PR touching
up to 5 doc files, measured as wall-clock time on a GitHub-hosted `ubuntu-latest`
runner, including the binary build step from R13a. This is validated by inspection
of a CI run in shirabe's own repo.

**R16: shirabe branch protection updated.**
shirabe's branch protection adds `validate-docs` as a required status check on the
main branch. The existing `check-plan-docs` required check is removed once
`validate-docs` is confirmed to cover Plan validation (via R6).

## Acceptance Criteria

- [ ] `tsukumogami/shirabe/.github/workflows/validate-docs.yml` exists and declares `on: workflow_call:`
- [ ] A downstream repo can invoke the workflow with only this caller file (no other changes needed), and the workflow job completes without error on a PR that touches no doc files:
  ```yaml
  name: Validate doc formats
  on:
    pull_request:
      paths: ['docs/**']
  jobs:
    validate:
      uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v1
  ```
- [ ] A PR that adds a Design doc missing the required `rationale` frontmatter field fails CI with an FC01 annotation at line 1 of the file
- [ ] A PR that adds a PRD with `status: Shipped` (not in the canonical PRD enum) fails CI with an FC02 annotation on the line containing the `status:` key
- [ ] A PR that adds a doc where the frontmatter reads `status: Accepted` but the body contains `## Status\nDraft` fails CI with an FC03 annotation on the line of `## Status`
- [ ] A PR that adds a Design doc missing the `## Security Considerations` section fails CI with an FC04 annotation at line 1 of the file
- [ ] A PR that adds a Roadmap doc missing the `## Implementation Issues` section (even if the doc is otherwise valid) fails CI with an FC04 annotation
- [ ] A downstream repo passing `custom-statuses: {prd: [Accepted, Delivered, Done]}` accepts a PRD with `status: Delivered` without error, and rejects a PRD with `status: Draft` with an FC02 error (Draft is not in the override list)
- [ ] A PR that modifies only files not matching any format prefix (e.g., `README.md`, `docs/guides/intro.md`) exits 0 and emits exactly one `::notice` annotation and zero `::error` annotations
- [ ] A PR that modifies both a recognized doc file (`DESIGN-foo.md`) and an unrecognized file (`README.md`) validates the Design doc and skips the unrecognized file
- [ ] A PR that adds a VISION doc containing `## Competitive Positioning` in a public repo fails CI
- [ ] A PR that adds a VISION doc containing `## Competitive Positioning` in a private repo passes CI
- [ ] A Plan doc with `upstream: docs/designs/DESIGN-foo.md` where that file does not exist on disk fails CI
- [ ] A Plan doc with `upstream: docs/designs/DESIGN-foo.md` where the file exists on disk but is not tracked by git fails CI
- [ ] A Plan doc with `schema: plan/v2` exits 0 with exactly one `::notice` annotation and zero `::error` annotations (unsupported schema version → skipped, not errored)
- [ ] A Design doc with no `schema` field modified in a PR exits 0 with exactly one `::notice` annotation and zero `::error` annotations
- [ ] A Design doc with `schema: design/v1` added in a PR is fully validated (FC01–FC04 checks run)
- [ ] A doc with both an FC01 violation and an FC04 violation produces two annotations before the job exits non-zero (collect-all behavior)
- [ ] The performance criterion holds: the workflow completes in under 60 seconds for a PR touching 5 doc files, all passing validation, measured on a GitHub-hosted `ubuntu-latest` runner
- [ ] A repo with 50 existing docs without `schema` fields experiences zero CI failures on a PR that modifies any of them (no schema field → skipped)
- [ ] The reusable workflow exposes a job named `validate-docs`, verifiable by inspecting the `jobs:` section of `validate-docs.yml`
- [ ] shirabe's branch protection lists `validate-docs` as a required status check, verifiable via `gh api repos/tsukumogami/shirabe/branches/main/protection`
- [ ] The workflow is tagged `v1` on initial release as a mutable floating tag (not an immutable tag object), verifiable by checking that `git cat-file -t v1` returns `commit` or `tag` with a non-signed annotation

## Out of Scope

- **AI-powered semantic validation** — future direction. The static tier validates structure; whether content is semantically complete requires an LLM and is a separate capability. The secret-gating mechanism for this is already proven in shirabe's `run-evals.yml`.
- **Mermaid diagram validation** — deferred. The existing validator needs significant architectural work before it can ship as a portable component.
- **Schema version evolution** — the validator's v1 supported schema version list is defined in R8 (one value per format). What a `design/v2` schema would mean, how formats evolve between versions, and how a future validator handles multiple schema versions simultaneously are follow-on design decisions.
- **Per-format separate workflows** — one `validate-docs.yml` with internal format detection. Callers do not need to know which format a file uses.
- **Migrating existing scripts in downstream repos** — downstream repos that have copied validation scripts keep them. The reusable workflow serves new adopters; migration is each repo's choice.
- **Decision records** — the decision skill produces ephemeral wip artifacts, not committed docs. There's nothing to validate in the main branch.
- **Cross-repo upstream field validation** — validating that a Design doc's `upstream` field points to an accessible artifact in another repo requires a spec for the cross-repo reference format that isn't finalized.
- **`scan_all` drift-detection mode** — scanning all docs on every PR creates a high adoption barrier. Deferred to a future optional workflow input.
- **Advisory / warning-only mode** — the static tier is blocking in v1. Non-blocking mode is out of scope.
- **Non-GHA CI systems** — GitHub Actions only.

## Known Limitations

- **Downstream repos configure blocking themselves.** The reusable workflow can't declare itself as a required status check — that setting lives in each repo's branch protection rules. If the job name changes between major versions, blocking is silently removed without any error.
- **Opt-in requires touching each doc.** A team that wants to opt in all 50 existing docs at once must open a PR that adds `schema: design/v1` (or the equivalent) to each file. There is no batch opt-in mechanism. Changed-files-only means these schema additions are themselves what triggers first-time validation on each doc.
- **Skills treat local validation as optional.** When `shirabe` is not in PATH, skills offer to install it but continue without it if declined. CI remains the authoritative validation gate; local validation is a convenience, not a correctness guarantee.
- **Status enum override requires listing all wanted values.** Repos with non-canonical status values must pass a complete replacement list via `custom-statuses`, including any canonical values they want to keep. Partial additions aren't supported in v1.
- **Compute runs in the caller's account.** Runner minutes are billed to the downstream repo's GitHub account, not shirabe's. For public repos, GitHub-hosted runners are free. For private repos, the static validation job is expected to complete well under 60 seconds per run, making per-run cost negligible. No v1 requirement addresses cost management for private downstream repos.
- **VISION format not yet validated in practice.** No downstream repo has published VISION docs as of this writing. Real-world edge cases may surface after initial adoption.
- **Branch protection bootstrapping.** The `validate-docs` job must be merged before it can be added as a required status check. For shirabe's own repo, this means a brief window where `check-plan-docs` remains the required check. The sequence: merge `validate-docs.yml`, confirm it runs correctly, then update branch protection and remove `check-plan-docs`.
- **Non-PR context behavior.** The changed-files-only scan requires a PR context. Calling the workflow from `workflow_dispatch` or a push trigger exits 0 with a notice rather than running validation. Repos that want validation on push triggers must scope the PR context requirement or accept the no-op behavior.

## Decisions and Trade-offs

**Schema version as the opt-in gate (not date-based cutoffs)**
Existing doc validators in the ecosystem use a cutoff date: docs created before a
certain date are excluded from validation. This is brittle — the date is arbitrary,
must be maintained, and excludes docs by age rather than by readiness. The
schema-version gate replaces this mechanism: a doc is validated only when its
`schema` field is present and in the validator's supported range. Teams opt in per
document, at their own pace, by adding the field. There are no cutoff dates to
manage and no exclusion rules to explain.

**Changed-files-only scan (not all-docs scan)**
The workflow validates only files changed in the current PR. Combined with the
schema version gate, this gives two layers of scope control: the PR diff limits
which files are even considered, and the schema gate limits which of those files
are actually validated. An all-docs scan would require teams to opt in every
existing doc before enabling the workflow; changed-files-only means a team can
enable the workflow and add `schema` fields file-by-file across ordinary PRs. A
future `scan_all` opt-in input can add drift detection.

**Single configurable workflow (not per-format)**
One `validate-docs.yml` with internal format detection by filename prefix. Per-format
workflows require callers to add multiple files and know which formats they use. Single
workflow with format detection keeps the caller simple: one file, one reference.

**`custom-statuses` replaces the canonical enum (does not extend it)**
The override list fully replaces the canonical enum for the specified format. The
alternative — extending the canonical list — is more forgiving but makes it impossible
to remove a canonical value a project doesn't use. Replace semantics are explicit and
testable: if you want `Accepted` to remain valid alongside `Delivered`, you list both.
Callers that want purely additive behavior include all canonical values in their list.

**Status enum override as a v1 requirement**
The downstream repos most likely to adopt early use non-canonical status values that
don't appear in shirabe's canonical enums. Without an override mechanism, the validator
would fail on any PR touching those docs, blocking adoption. Including `custom-statuses`
in v1 lets existing repos adopt without a pre-adoption cleanup sprint.

**Collect-all error reporting (not fail-fast)**
The workflow collects all validation errors before exiting. Fail-fast stops at the
first error, requiring multiple PR iterations to surface all problems. Collect-all
gives contributors a complete picture in one CI run.

**Go for validation logic (not bash)**
The validation logic is implemented in Go as the `shirabe` CLI rather than as bash
scripts. Go provides structured frontmatter parsing, typed error handling, and
`go test`. Go is pre-installed on GitHub-hosted runners, and the `shirabe` CLI is
available via `tsuku install shirabe` or a curl script for local use. A single
implementation serves both CI and local skill validation — no duplicate logic to
drift apart.

**`check-plan-docs` removed when `validate-docs` ships**
Once `validate-docs` is confirmed to cover Plan validation (R6), the existing
`check-plan-docs` workflow and required status check are removed from shirabe's branch
protection. Keeping both creates redundant checks. The transition sequence ensures no
window of unprotected merges.

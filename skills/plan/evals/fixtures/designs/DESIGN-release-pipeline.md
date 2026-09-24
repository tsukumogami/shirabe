---
schema: design/v1
status: Accepted
problem: |
  Releases of acme/widgets are cut by hand from a maintainer's laptop, so the
  steps drift and a missed step ships an unsigned archive.
decision: |
  Move the release steps into a reusable GitHub Actions workflow, call it from
  a tag-triggered release workflow, and add a `widgets release --check`
  command that verifies a published release.
rationale: |
  A reusable workflow keeps the steps in one place for the tag trigger and for
  manual re-runs, and the check command gives maintainers a way to confirm a
  release without reading workflow logs.
---

# DESIGN: Release Pipeline

## Status

Accepted

## Context and Problem Statement

Releases of `acme/widgets` are cut by hand. A maintainer builds the archives,
signs them, and uploads them to a GitHub release. The steps live in a wiki page
that has drifted from what maintainers actually do, and last quarter a release
shipped with one archive unsigned. Everything in this design lands in the one
repository, `acme/widgets`.

## Decision Drivers

- Every release must run the same build, sign, and upload steps.
- Maintainers must be able to re-run a failed release without cutting a new tag.
- A maintainer must be able to confirm a published release is complete.

### Hard Constraint

The release workflow calls the reusable workflow as
`acme/widgets/.github/workflows/release-steps.yml@main`. GitHub resolves that
reference against the default branch, so the reusable workflow **must be merged
to `main` before the calling workflow can be invoked**. The two workflows cannot
land in the same pull request: the calling workflow's first run would fail to
resolve the reference. This ordering is not optional.

## Considered Options

### Decision 1: Where the release steps live

Chosen: a reusable workflow (`release-steps.yml`) called by a thin
tag-triggered workflow (`release.yml`). Rejected: one monolithic workflow,
because a manual re-run would have to duplicate its trigger logic.

### Decision 2: How a release is verified

Chosen: a `widgets release --check <tag>` subcommand that lists the release's
assets and confirms each archive has a signature. Rejected: a workflow step,
because maintainers want to check releases they did not cut.

## Decision Outcome

Add the reusable workflow first, then the tag-triggered workflow that calls it,
then the check command.

## Solution Architecture

- `.github/workflows/release-steps.yml`: a `workflow_call` workflow that builds
  the archives, signs each one, and uploads archives and signatures to the
  release named by its `tag` input.
- `.github/workflows/release.yml`: triggered on `v*` tags and on
  `workflow_dispatch`; calls `release-steps.yml@main` with the tag.
- `cmd/widgets/release_check.go`: the `release --check <tag>` subcommand, which
  reads the release through the GitHub API and exits non-zero when an archive
  lacks a signature.

## Implementation Approach

1. Add `release-steps.yml` with its inputs and a dry-run mode.
2. Add `release.yml`, calling the reusable workflow from `main`.
3. Add the `release --check` subcommand and its tests.

## Security Considerations

The signing key is read from an environment secret available only to the
reusable workflow's `sign` job. The check command uses a read-only token.

## Consequences

Releases become repeatable and verifiable. The workflows gain a dependency on
the default branch holding the reusable workflow, which is the ordering the Hard
Constraint above records.

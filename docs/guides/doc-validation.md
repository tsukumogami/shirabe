# Adopting Doc Validation

How to wire up the shirabe doc validator in a downstream repo. Covers the
caller workflow, custom status values, branch protection, and migration
notes for repos with existing docs.

## How it works

The reusable workflow (`validate-docs.yml`) checks out shirabe, builds the
`shirabe` binary from source, diffs the PR's changed files, and runs
`shirabe validate` on any recognized file. Recognized files are those whose
basename matches a known prefix: `DESIGN-`, `PRD-`, `VISION-`, `ROADMAP-`,
or `PLAN-`. Everything else is silently skipped.

For recognized files, the validator:

1. **Schema gate** -- if the file doesn't carry a `schema:` field matching
   a supported version (e.g. `schema: design/v1`), it emits a `::notice`
   annotation and moves on. Hard failures only fire after the schema gate
   passes, so unschema'd docs are never blocked.
2. **FC01–FC04** -- required frontmatter fields, valid status enum, status
   body consistency, required sections.
3. **Format-specific rules** -- Plan docs: upstream file existence and git
   tracking (R6). VISION docs in public repos: prohibited section headings
   (R7).

Errors produce `::error` GHA annotations that fail the check. Notices
produce `::notice` annotations that don't.

## Quick setup

Create `.github/workflows/validate-docs.yml` in your repo:

```yaml
name: Validate doc formats
on:
  pull_request:
    paths: ['docs/**']
jobs:
  validate:
    uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v1
```

The job is named `validate-docs`. Pin that name in your branch protection
rules (it won't change in any v1.x release).

## Custom status values

The built-in status enums match the canonical shirabe formats. If your team
uses different values, pass a YAML map keyed by schema version:

```yaml
    uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v1
    with:
      custom-statuses: |
        prd: [Draft, Accepted, In Progress, Done, Delivered]
        design/v1: [Proposed, Accepted, Retired]
```

Custom values replace (not extend) the built-in enum for the specified
schema version. Omit a key to keep the built-in values.

## Branch protection

Once the workflow is in place, add `validate-docs` as a required status
check on your default branch. Steps in the GitHub UI:

1. Settings → Branches → Add rule (or edit the existing main branch rule)
2. Enable "Require status checks to pass before merging"
3. Search for `validate-docs` and add it

If you have an existing `check-plan-docs` required check from an older
shirabe setup, remove it once you've confirmed `validate-docs` covers
Plan validation (it does via R6).

## Migrating repos with existing docs

Docs without a `schema:` field are never validated — the schema gate skips
them with a notice. This means you can add the workflow to a repo that has
50 existing docs and nothing will break until you add `schema:` to each doc.

To opt a doc in:

1. Add `schema: <version>` to its frontmatter (e.g. `schema: design/v1`)
2. Fix any FC01–FC04 errors that surface on the next PR that touches it

You don't need to migrate all docs at once. The schema gate is designed for
incremental adoption.

## Local validation

Install the `shirabe` binary locally to validate docs without a PR:

```bash
curl -fsSL https://raw.githubusercontent.com/tsukumogami/shirabe/main/install.sh | bash
```

Adds `shirabe` to `~/.shirabe/bin/`. Add that to `PATH`:

```bash
echo 'source "$HOME/.shirabe/env"' >> ~/.bashrc  # or ~/.zshrc
source ~/.shirabe/env
```

Then validate a file:

```bash
shirabe validate docs/designs/DESIGN-my-feature.md
shirabe validate --visibility=public docs/designs/DESIGN-my-feature.md
```

Use `--visibility=private` to suppress the VISION public-section check
when running locally against a private repo's docs.

# Adopting Doc Validation

How to wire up the shirabe doc validator in a downstream repo. Covers the
caller workflow, custom status values, branch protection, and migration
notes for repos with existing docs.

## How it works

The reusable workflow (`validate-docs.yml`) checks out shirabe, builds the
`shirabe` binary from source, diffs the PR's changed files, and runs
`shirabe validate` on any recognized file. Recognized files are those whose
basename matches a known prefix: `DESIGN-`, `PRD-`, `VISION-`, `ROADMAP-`,
`PLAN-`, or `COMP-`. Everything else is silently skipped.

For recognized files, the validator:

1. **Schema gate** -- if the file doesn't carry a `schema:` field matching
   a supported version (e.g. `schema: design/v1`), it emits a `::notice`
   annotation and moves on. Hard failures only fire after the schema gate
   passes, so unschema'd docs are never blocked.
2. **FC01–FC04** -- required frontmatter fields, valid status enum, status
   body consistency, required sections.
3. **Format-specific rules** -- Plan docs: upstream file existence and git
   tracking (R6). VISION docs in public repos: prohibited section headings
   (R7). STRATEGY docs in public repos: prohibited section headings (R8).
   Private-only formats such as COMP: rejected outside private visibility
   (R9), and the gate fires before FC01-FC04.

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
    uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v0.6.0
```

The job is named `validate-docs`. Pin that name in your branch protection
rules (it's part of the workflow's stable contract).

## Custom status values

The built-in status enums match the canonical shirabe formats. If your team
uses different values, pass a YAML map keyed by schema version:

```yaml
    uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v0.6.0
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

## Adopting the COMP format (R9 and `docs/competitive/`)

The `COMP-` prefix (competitive-analysis docs, schema `comp/v1`) is a
private-only format. Adopters should note three things:

- **Path-filter widening.** COMP docs conventionally live under
  `docs/competitive/`. The default workflow trigger `paths: ['docs/**']`
  already covers them. If your `validate-docs.yml` uses a narrower filter
  (for example `paths: ['docs/designs/**', 'docs/prds/**']`), widen it to
  include `docs/competitive/**`, or COMP docs will skip validation on PRs.
- **New error code R9.** R9 is the private-only gate: `shirabe validate`
  rejects any `Private`-marked format (today, `comp/v1`) unless visibility
  is exactly `private`, and the gate fails closed on unset visibility. If
  you filter or alert on validation error codes, key on the prefix range
  `R7`–`R9` (or an explicit code list) rather than a hardcoded `R7`–`R8`
  range, so R9 is not dropped silently.
- **Format-reference home.** `skills/comp/references/comp-format.md` in
  shirabe is the canonical COMP format reference. Any pre-existing
  workspace-level COMP reference stays in place for legacy reasons but is
  not consulted by `shirabe validate` or by the `/comp` skill.

The `/comp` skill authors COMP docs; see the `/comp` guidance paragraph in
shirabe's `CLAUDE.md` for when to reach for it and the public-repo
refusal behavior.

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

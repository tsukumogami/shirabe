# Lead: Reusable GHA workflow patterns for downstream consumption

## Findings

### The `workflow_call` trigger

A GitHub Actions workflow becomes reusable by declaring `on: workflow_call:` instead of (or in addition to) `on: push:` / `on: pull_request:`. Downstream repos invoke it with `uses: <owner>/<repo>/.github/workflows/<file>.yml@<ref>` inside a job definition — not inside a step.

```yaml
# Downstream caller (in the consumer repo's .github/workflows/)
jobs:
  validate:
    uses: tsukumogami/shirabe/.github/workflows/validate.yml@v1
    with:
      skills-path: 'skills/**'
    secrets:
      anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}
```

No files from shirabe are copied to the downstream repo. The runner checks out shirabe at the pinned ref, runs those steps, and reports results back into the caller's workflow run. The downstream repo only needs one YAML file — the caller.

### Version pinning

The `@<ref>` suffix can be:
- A tag: `@v1` or `@v1.2.3` — recommended for production use
- A branch: `@main` — always latest, no stability guarantee
- A commit SHA: `@abc1234` — maximally pinned, immune to tag moves

The koto `check-template-freshness` workflow hard-codes `default: 'v0.8.4'` for the koto version it installs, which is a different axis from the workflow ref itself. Shirabe's own `check-templates.yml` calls that reusable workflow at `@main` — a deliberate "track latest" choice for an internal consumer.

### Inputs

`workflow_call.inputs` declares typed parameters the caller can pass:

```yaml
# In the reusable workflow (shirabe-hosted)
on:
  workflow_call:
    inputs:
      skills-path:
        description: Glob matching skill directories to validate.
        required: false
        type: string
        default: 'skills/**'
      shirabe-version:
        description: Version of shirabe tools to install (e.g. v1.2.0, latest).
        required: false
        type: string
        default: 'latest'
```

Supported types are `string`, `boolean`, and `number`. There is no `array` type — callers must pass comma-separated strings and have the reusable workflow split them. Object/map inputs are not possible; callers needing complex config must either pass individual scalar inputs or point to a config file path in their repo.

### Secrets handling — the two models

**Model A — explicit secret forwarding (recommended for cross-repo secrets):**

```yaml
# In the reusable workflow
on:
  workflow_call:
    secrets:
      anthropic-api-key:
        description: API key for AI-powered validation tier.
        required: false

jobs:
  ai-validate:
    runs-on: ubuntu-latest
    steps:
      - name: Run AI evals
        env:
          ANTHROPIC_API_KEY: ${{ secrets.anthropic-api-key }}
        run: ...
```

```yaml
# In the downstream caller
jobs:
  validate:
    uses: tsukumogami/shirabe/.github/workflows/validate.yml@v1
    secrets:
      anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}
```

The downstream repo must have `ANTHROPIC_API_KEY` set in its own secrets store (repo or org level). The caller maps it to the name the reusable workflow expects. The secret value is never exposed in logs.

**Model B — `secrets: inherit` (simpler, same-org only):**

```yaml
jobs:
  validate:
    uses: tsukumogami/shirabe/.github/workflows/validate.yml@v1
    secrets: inherit
```

`secrets: inherit` passes every secret in the caller's environment to the reusable workflow automatically. This works only when both repos are in the same GitHub organization or are both public repos where the caller is the same owner. For external downstream repos calling a public shirabe workflow, `secrets: inherit` does NOT propagate the caller's secrets — explicit forwarding is required.

### Config file passing — the constraint

Reusable workflows execute in the context of the **called** repo (shirabe), not the caller repo, unless steps explicitly check out the caller repo. This means:

- If validation logic needs a config file from the downstream repo (e.g., `.shirabe.yml`), the reusable workflow must include a step that checks out the caller repo first, or the caller must provide config as `inputs` scalars.
- The `actions/checkout` in a reusable workflow defaults to checking out the **called** repo at the pinned ref. To check out the caller repo, the step needs `repository: ${{ github.repository }}` and `ref: ${{ github.ref }}` — but `github.repository` and `github.ref` in the reusable workflow context refer to the **caller's** repo when invoked via `workflow_call`. This is the correct behavior for pulling in the caller's code.

Practical pattern: the reusable workflow's first step is `actions/checkout@v4` with no extra parameters — this checks out the **caller's** repo (because `github.repository` and `github.sha` resolve to the caller's context under `workflow_call`). Subsequent steps can then read config files or scan the caller's skill directories.

### What the check-template-freshness workflow reveals

`koto/.github/workflows/check-template-freshness.yml` is the most complete reusable workflow example in this codebase:

- It declares `on: workflow_call:` with four typed inputs: `template-paths` (required string), `koto-version` (optional string with default), `check-html` (optional boolean), `html-output-dir` (optional string with default).
- The caller (`shirabe/check-templates.yml`) uses `uses: tsukumogami/koto/.github/workflows/check-template-freshness.yml@main` with only one `with:` key, letting defaults handle the rest.
- The reusable workflow installs koto from the network, then operates on files in the **caller's** repo (because checkout defaults to caller context under `workflow_call`).
- No secrets are needed — this is a pure deterministic tier.

### The two-tier structure for shirabe

Based on shirabe's existing workflows, the tiers map cleanly to:

**Tier 1 — Deterministic (no secrets):**
- Skill structure checks (evals exist, no hooks.json in skill dirs)
- Plugin manifest validation (plugin.json / marketplace.json schema)
- Script unit tests (bash test scripts run on ubuntu + macos matrix)
- Template compilation/consistency checks
- Sentinel checks (manifest version validation)
- wip/ artifact cleanliness check

**Tier 2 — AI-powered (requires ANTHROPIC_API_KEY):**
- Running actual skill evals via `claude -p` (shirabe's `run-evals.yml` does this)
- Any behavioral validation that drives the Claude Code agent

The `run-evals.yml` workflow shows the AI tier pattern: it installs `@anthropic-ai/claude-code` via npm, then passes `ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}` to multiple steps. This workflow currently runs on a schedule and via `workflow_dispatch`, not on every PR — a deliberate cost/latency trade-off.

### What downstream repos actually need

For the thin caller pattern, downstream repos (e.g., a repo that has shirabe skills) need only:

1. One `.github/workflows/validate-skills.yml` file that calls `uses: tsukumogami/shirabe/.github/workflows/validate.yml@v1`.
2. For AI tier: `ANTHROPIC_API_KEY` set as a repo or org secret, forwarded explicitly.
3. No scripts, no copies of shirabe tooling — all logic stays in shirabe.

The downstream caller might look like:

```yaml
name: Validate skills

on:
  pull_request:
    branches: [main]
    paths:
      - 'skills/**'
      - '.claude-plugin/**'

jobs:
  validate:
    uses: tsukumogami/shirabe/.github/workflows/validate.yml@v1
    with:
      skills-path: 'skills/**'
      run-ai-tier: false          # opt-in to AI evals
    secrets:
      anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }}
```

## Implications

1. **Shirabe should expose two reusable workflows, not one.** A single `validate.yml` that takes a `run-ai-tier: boolean` input is cleaner than forcing callers to reference two separate files. The boolean gates whether the AI jobs run; secret absence causes graceful skip rather than hard failure.

2. **The `required: false` secret pattern enables graceful degradation.** When `anthropic-api-key` is declared `required: false` in `workflow_call.secrets`, callers without the secret can still run the deterministic tier. The AI-powered jobs should check if the secret is non-empty before invoking Claude.

3. **Checkout in the reusable workflow gets the caller's code.** Shirabe's reusable workflow doesn't need a special checkout step — `actions/checkout@v4` with defaults gives the caller's repo at the PR's SHA. Scripts and skill files are immediately available.

4. **Inputs should be minimal.** The koto template-freshness workflow is a good model: one required input (`template-paths`), sensible defaults for the rest. Shirabe's reusable workflow likely needs `skills-path` (string, default `'skills/**'`) and `run-ai-tier` (boolean, default `false`). Version pinning of shirabe's own tools is internal to the reusable workflow, not exposed as an input.

5. **The `@v1` tag strategy.** Downstream repos pinning `@v1` need shirabe to maintain a moving `v1` tag or use a `v1.x.x` semver series. The koto example uses both `@main` (internal) and a pinned version default inside the workflow. Shirabe should publish tagged releases and maintain a `v1` tag for stability.

6. **Existing workflows are candidates for refactoring into the reusable workflow.** Most of shirabe's current CI workflows are not `workflow_call`-compatible — they only trigger on shirabe's own PRs. The reusable system would extract the reusable logic into a new `validate.yml` with `on: workflow_call:` while keeping the existing per-path trigger workflows for shirabe's own CI.

## Surprises

1. **`actions/checkout` under `workflow_call` checks out the caller's repo by default.** This is not obvious from the GitHub docs at first read, but it means reusable workflows don't need special handling to access the downstream repo's files. The `github.repository`, `github.sha`, and `github.ref` context variables all resolve to the caller's values inside a `workflow_call`-triggered workflow.

2. **`secrets: inherit` doesn't work for external repos.** A plugin author at an external org can't use `secrets: inherit` when calling a shirabe workflow — they must explicitly forward `${{ secrets.ANTHROPIC_API_KEY }}`. This makes the explicit `secrets:` declaration in the reusable workflow necessary, not optional.

3. **There is no array input type.** If shirabe needs callers to specify multiple paths or multiple skill names, it must use comma-separated strings and split them in bash, or require a single glob. This limits config expressiveness but is manageable for the use cases at hand.

4. **The reusable workflow runs on shirabe's runner quota.** All compute for downstream repos' validation runs against shirabe's (or the org's) GitHub Actions minutes. If adoption is wide, this could matter for cost.

5. **Job-level `if:` conditions referencing secrets don't work cleanly.** You can't write `if: secrets.anthropic-api-key != ''` at the job level in a reusable workflow — secrets aren't available in `if:` expressions at job level. The workaround is a step that checks `[ -n "$ANTHROPIC_API_KEY" ]` and exits 0 (skip) or 1 (fail) as appropriate.

## Open Questions

1. **Should the AI tier be opt-in via a boolean input, or a separate reusable workflow file?** A single file with a boolean is simpler for callers but adds conditional complexity inside the workflow. Two files are cleaner but require callers to know which to call.

2. **How should the reusable workflow handle path filtering?** Shirabe's own workflows use `paths:` triggers to only run on relevant changes. A reusable workflow can't inherit the caller's path filters — those must be set in the downstream caller file. Does shirabe's `validate.yml` documentation need to prescribe which `paths:` triggers downstream callers should use?

3. **What happens when shirabe releases a breaking change in the reusable workflow API?** The `@v1` tag strategy helps, but there's no enforcement mechanism. Should shirabe version the reusable workflow inputs explicitly, or rely on semver tag conventions?

4. **Should the deterministic tier run as a required status check?** Downstream repos can configure branch protection to require the `validate / deterministic` job. This would be the recommended setup — but it's a downstream repo configuration concern, not something shirabe can enforce.

5. **Cost and rate limiting for the AI tier.** If many downstream repos run AI evals on every PR, the API costs could be significant. Should the AI tier be `workflow_dispatch`-only, or on a schedule, similar to shirabe's own `run-evals.yml`?

6. **Plugin manifest validation scope.** Shirabe's schema checks validate `plugin.json` and `marketplace.json`. If downstream repos don't have these files (e.g., they use shirabe skills without being a full plugin), the reusable workflow needs to handle their absence gracefully.

## Summary

GitHub Actions reusable workflows execute in the caller's repo context (checkout defaults to caller's code), so shirabe's hosted `validate.yml` can scan downstream skills without any file-copying — the thin caller pattern is fully supported. The main implication is that shirabe needs to expose one reusable workflow with a `run-ai-tier` boolean input and declare `ANTHROPIC_API_KEY` as a `required: false` secret, enabling graceful degradation when the secret is absent. The biggest open question is whether the AI eval tier belongs in the same workflow file as a gated boolean or in a separate reusable workflow, since the two approaches have different tradeoffs for caller simplicity vs. internal workflow complexity.

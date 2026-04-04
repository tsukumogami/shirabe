# Lead: How should CI workflows change to use `.tsuku.toml`?

## Findings

### Current state of shirabe CI workflows

Shirabe has 7 workflow files in `.github/workflows/`:

| Workflow | Tools Used | How Installed |
|----------|-----------|---------------|
| `validate-templates.yml` | tsuku, koto | `curl get.tsuku.dev/now`, then `tsuku install tsukumogami/koto -y` |
| `check-templates.yml` | koto | Reusable workflow from `tsukumogami/koto` (installs koto via its own `install.sh`) |
| `check-evals.yml` | python | `actions/setup-python@v5` |
| `check-sentinel.yml` | (none) | Shell script only |
| `release.yml` | gh, jq | Pre-installed on GitHub runners |
| `finalize-release.yml` | gh, jq | Pre-installed on GitHub runners |
| `prepare-release.yml` | (none) | Calls release.yml and finalize-release.yml |

### Only one workflow installs tsuku explicitly

`validate-templates.yml` is the only workflow that installs tsuku. It uses the
bootstrap curl command and then runs a single `tsuku install tsukumogami/koto -y`.
This is the primary target for `.tsuku.toml` adoption.

### The koto reusable workflow bypasses tsuku entirely

`check-templates.yml` delegates to `tsukumogami/koto/.github/workflows/check-template-freshness.yml@main`,
which installs koto directly via koto's own `install.sh` (not through tsuku). This
means even if shirabe adopts `.tsuku.toml`, the reusable workflow would still install
koto independently. This is a separate install path that `.tsuku.toml` cannot unify
without changes to the koto reusable workflow itself.

### Release workflows use only runner-preinstalled tools

`release.yml` and `finalize-release.yml` use `gh` and `jq` extensively for GitHub
API operations. Both tools come pre-installed on `ubuntu-latest` runners, so they
don't need tsuku. Adding them to `.tsuku.toml` for local dev parity is possible but
has no CI benefit -- the runner versions would be used regardless unless the workflow
explicitly installs them via tsuku.

### tsuku does not dogfood `.tsuku.toml` in its own CI

The tsuku repo has no `.tsuku.toml` file. Its CI workflows use `./tsuku install --force <tool>`
with the locally-built binary (testing the CLI itself). There is no `tsuku install` with
no args (project mode) anywhere in tsuku's CI. This means there's no existing CI pattern
to follow -- shirabe would be a first adopter.

### No GitHub Action exists for tsuku setup

There is no `action.yml` in the tsuku repo and no `setup-tsuku` or equivalent action
anywhere in the tsukumogami org. Every workflow that needs tsuku uses the raw curl
bootstrap script. A reusable setup action would reduce duplication and improve
cacheability.

### What a `.tsuku.toml`-based CI pattern would look like

For `validate-templates.yml`, the change is straightforward:

```yaml
# Before (current):
- name: Install koto
  run: |
    curl -fsSL https://get.tsuku.dev/now | bash
    echo "$HOME/.tsuku/bin" >> $GITHUB_PATH
    echo "$HOME/.tsuku/tools/current" >> $GITHUB_PATH
- name: Install koto via tsuku
  env:
    TSUKU_TELEMETRY: "0"
  run: tsuku install tsukumogami/koto -y

# After (with .tsuku.toml):
- name: Install tsuku
  run: |
    curl -fsSL https://get.tsuku.dev/now | bash
    echo "$HOME/.tsuku/bin" >> $GITHUB_PATH
    echo "$HOME/.tsuku/tools/current" >> $GITHUB_PATH
- name: Install project tools
  env:
    TSUKU_TELEMETRY: "0"
  run: tsuku install -y
```

The tsuku bootstrap step remains identical -- only the install command changes.
The `-y` flag auto-confirms (skips interactive prompt), which is required for CI.

### Complications

1. **No caching.** There is no `actions/cache` usage for `~/.tsuku/` in any workflow.
   Each run re-downloads tsuku and koto from scratch. A setup action could add caching.

2. **Dual install path.** `check-templates.yml` uses koto's reusable workflow which
   installs koto independently. If `.tsuku.toml` declares koto, the template freshness
   check still won't use it. Two options: (a) accept the duplication, or (b) replace
   the reusable workflow call with an inline job that uses `tsuku install -y`.

3. **Bootstrap chicken-and-egg.** `.tsuku.toml` requires tsuku to be installed first.
   The curl bootstrap step can't be eliminated. A GitHub Action (`tsukumogami/setup-tsuku`)
   would wrap both bootstrap + project install into one step.

4. **Version pinning for CI reproducibility.** The current bootstrap script installs
   the latest tsuku. For reproducible CI, pinning the tsuku version itself matters.
   The bootstrap script doesn't appear to accept a version flag (would need verification).

## Implications

- The immediate CI change is minimal: one workflow (`validate-templates.yml`) replaces
  a tool-specific install with `tsuku install -y`. The other workflows either use
  runner-preinstalled tools or a separate reusable workflow.

- The real value of `.tsuku.toml` in CI comes when more tools are added to the project.
  Right now shirabe only needs koto for validation, so the payoff is alignment with
  local development, not CI simplification.

- A `tsukumogami/setup-tsuku` GitHub Action would make the CI pattern cleaner and
  enable caching, but that's a tsuku-repo concern, not a shirabe concern.

- The koto reusable workflow (`check-template-freshness.yml`) is a separate concern
  that installs koto via its own installer. Unifying this with `.tsuku.toml` would
  require changes to the koto repo or replacing the reusable workflow call.

## Surprises

- **koto installs itself two different ways in shirabe CI.** `validate-templates.yml`
  installs koto via tsuku, while `check-templates.yml` installs koto via koto's own
  `install.sh` (through the reusable workflow). These could produce different koto
  versions since `check-template-freshness.yml` defaults to `v0.5.0` while the tsuku
  recipe resolves `latest`.

- **tsuku doesn't dogfood `.tsuku.toml` in its own CI.** Shirabe would be pioneering
  this pattern rather than following an established one.

- **gh and jq are used only through GitHub's `--jq` flag**, not as standalone `jq`
  invocations. The `gh` CLI's built-in jq filtering handles all JSON parsing. Standalone
  `jq` is never invoked.

## Open Questions

1. Does the tsuku bootstrap script (`get.tsuku.dev/now`) support version pinning?
   Reproducible CI needs a specific tsuku version, not just the latest.

2. Should `check-templates.yml` switch from the koto reusable workflow to an inline
   job that uses `tsuku install -y`? This would unify koto installation but loses the
   reusable workflow's maintenance benefits.

3. Is a `tsukumogami/setup-tsuku` GitHub Action planned? That would be the cleanest
   CI integration point.

4. Should runner-preinstalled tools like `gh` be declared in `.tsuku.toml` for local
   dev consistency, even though CI won't use the tsuku-installed versions?

## Summary

Only one shirabe CI workflow (`validate-templates.yml`) installs tools via tsuku, and switching it to `tsuku install -y` is a one-line change -- the tsuku bootstrap step stays the same, only the install command changes from tool-specific to project-mode. The main complication is that `check-templates.yml` uses koto's own reusable workflow with a separate install path that `.tsuku.toml` cannot unify without changes to the koto repo. The biggest open question is whether a `tsukumogami/setup-tsuku` GitHub Action is planned, since that would make the CI pattern significantly cleaner with caching and version pinning.

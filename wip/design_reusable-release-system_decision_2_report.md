<!-- decision:start id="auth-model" status="assumed" -->
### Decision: Authentication model for reusable workflow push

**Context**

The reusable release workflow pushes version-stamp commits and tags to the caller repo's main branch. This push requires appropriate authentication, but the right token depends on the caller's branch protection configuration. Repos without branch protection work fine with the automatic `GITHUB_TOKEN`. Repos with protection rules that require review bypass need a PAT or GitHub App token that can push past those rules.

The ecosystem currently has four repos with varying protection setups, and koto already uses a hardcoded `RELEASE_PAT` secret for its finalize-release job. The PRD requires early token validation (R7), forbids force-push (R10), and explicitly flags this as an open question (Q2).

**Assumptions**

- All repos in the ecosystem will eventually adopt branch protection on main. If wrong: the configurable approach still works, it just means nobody ever needs to pass a token.
- GitHub App tokens are not worth the setup cost for a four-repo ecosystem. If wrong: the configurable secret interface accepts app-generated tokens without any workflow changes.
- The `secrets.token || github.token` fallback expression is stable GitHub Actions behavior. If wrong: the workflow would need a conditional step instead of an inline expression.

**Chosen: Configurable token secret with GITHUB_TOKEN default**

The reusable workflow defines an optional secret named `token` in its `workflow_call` interface. When a caller provides this secret (via `secrets: token: ${{ secrets.RELEASE_PAT }}` or `secrets: inherit`), the workflow uses it for checkout and push operations. When omitted, the workflow falls back to `github.token`.

The implementation uses the expression `${{ secrets.token || github.token }}` in the `actions/checkout` `token` parameter and any `git push` step. Early validation (R7) runs a permissions check against the GitHub API using the effective token before performing any git mutations.

Caller workflow for a repo without branch protection:
```yaml
jobs:
  release:
    uses: tsukumogami/shirabe/.github/workflows/release.yml@main
    # No secrets needed -- GITHUB_TOKEN handles it
```

Caller workflow for a repo with branch protection:
```yaml
jobs:
  release:
    uses: tsukumogami/shirabe/.github/workflows/release.yml@main
    secrets:
      token: ${{ secrets.RELEASE_PAT }}
```

**Rationale**

This matches the dominant industry pattern. release-please, goreleaser-action, and actions/checkout all accept a token input that defaults to `GITHUB_TOKEN`. The pattern works because it puts the branch-protection complexity where it belongs -- at the caller level, where the repo owner knows their protection setup.

Requiring a PAT from all callers (Alternative 2) penalizes repos that don't need one. Using only `GITHUB_TOKEN` (Alternative 1) breaks for protected repos with no upgrade path. A GitHub App (Alternative 4) adds meaningful infrastructure overhead for a four-repo ecosystem.

Koto's existing `RELEASE_PAT` maps directly to this model -- the caller workflow passes it as the `token` secret. No naming convention is imposed on the caller's secret name.

**Alternatives Considered**

- **GITHUB_TOKEN only**: Zero adoption friction, but fails for branch-protected repos. No upgrade path without breaking the workflow interface. Rejected because it would force repos to remove branch protection or stop using the workflow.
- **PAT required (named secret)**: Always works, matches koto precedent. Rejected because it imposes unnecessary setup friction on repos without branch protection and hardcodes a secret name convention.
- **GitHub App token**: Best security properties (ephemeral tokens, no bus-factor). Rejected because the setup cost -- creating an app, installing it, managing credentials -- is disproportionate for a four-repo ecosystem.

**Consequences**

The workflow interface includes `secrets: token: required: false`. Documentation must explain the two caller patterns (with and without token) and when each applies. The early validation step adds a small amount of workflow complexity but catches misconfigured tokens before they cause partial failures. Koto's migration is straightforward: replace the hardcoded `RELEASE_PAT` checkout with a call to the reusable workflow, passing the same secret.
<!-- decision:end -->

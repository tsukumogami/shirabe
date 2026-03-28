# Lead: Plugin/Skills Repos That Ship Reusable CI Workflows

## Research Question

What patterns exist for publishing reusable release workflows from plugin/skills
repos? Are there precedents in Claude Code or other ecosystems? How do they
version the workflow itself?

## TL;DR

Shipping reusable GitHub Actions workflows alongside a code library/plugin is an
established pattern but mostly seen in infrastructure-focused projects (CI
tooling, supply-chain security, provider release automation), not in
plugin/extension ecosystems like Claude Code, VS Code, or Gradle. Shirabe would
be unusual in combining skills with release infrastructure, but the mechanics are
well-understood.

---

## 1. Claude Code Plugin Ecosystem

The Claude Code plugin ecosystem is still nascent. Plugins ship skills, agents,
hooks, and MCP servers. Community marketplaces (claudemarketplaces.com,
buildwithclaude.com, cc-marketplace) catalog these plugins.

**No plugins currently ship reusable GitHub Actions workflows.** The ecosystem is
focused on runtime skills and agent behavior, not CI infrastructure. Some
projects like `claude-code-workflows` and `developer-kit` describe themselves as
"workflow" tools, but they mean agent interaction workflows, not CI/CD pipelines.

Shirabe shipping a reusable release workflow would be a first in this ecosystem.

## 2. CI-as-a-Product Repos (the closest precedents)

Several well-known repos exist whose primary product IS reusable workflows:

### hashicorp/ghaction-terraform-provider-release
- Ships reusable workflows for releasing Terraform providers
- Separate workflow files: `community.yml` and `hashicorp.yml`
- Versioned with semver tags (v4.0.0) AND floating major version tags (v4)
- Consumers reference: `hashicorp/ghaction-terraform-provider-release/.github/workflows/community.yml@v4`
- This is the closest analog to what shirabe would do: a project that provides
  both domain tooling (Terraform provider SDK) and release infrastructure

### slsa-framework/slsa-github-generator
- Provides reusable workflows for SLSA provenance generation
- Strict versioning: consumers MUST pin to `@vX.Y.Z` (full semver), not `@vX`
- Build fails if you use a shorter tag -- this is intentional for security
- Workflows live in `.github/workflows/` alongside Go code

### github/codeql-action
- Ships composite actions alongside reusable analysis workflows
- Uses floating major version tags (v3)
- Was subject to a supply-chain attack (CodeQLEAKED) where the mutable v3 tag
  was a vulnerability vector -- demonstrates the security risk of floating tags

### gradle/actions
- Collection of GitHub Actions for Gradle builds
- Ships setup-gradle, dependency-submission, and wrapper-validation
- Versioned with floating major tags

## 3. Other Ecosystems

### Terraform Providers
HashiCorp ships reusable release workflows separately from individual providers.
The pattern: a central "workflow repo" that provider repos call into. Provider
repos don't carry their own release workflow -- they delegate to
ghaction-terraform-provider-release.

### VS Code Extensions
No pattern of shipping CI workflows alongside extensions. The VS Code extension
ecosystem uses Yeoman generators (`yo code`) to scaffold projects including CI
config, but the CI templates are baked into the generator, not consumed as
reusable workflows. Extensions focus on runtime behavior.

### Gradle Plugins
Gradle plugins don't ship CI workflows. The `gradle/actions` repo provides
reusable CI infrastructure, but it's separate from any specific Gradle plugin.

### General Pattern
In all these ecosystems, there's a clean separation: **plugins provide runtime
behavior, CI infrastructure lives in dedicated repos**. The only exceptions are
infrastructure-focused projects where CI IS the product.

## 4. Versioning Strategies

Three strategies are used in practice:

### Floating Major Version Tags (most common)
- Tag format: v1, v1.2.0, v1.2.1
- The v1 tag is force-pushed to point at the latest v1.x.y release
- Used by: actions/*, gradle/actions, hashicorp/ghaction-terraform-provider-release
- Pro: consumers automatically get bug fixes
- Con: mutable tags are a supply-chain attack vector (see CodeQLEAKED)

### Strict Semver Pinning
- Tag format: v1.2.3 only, no floating tags
- Used by: slsa-framework/slsa-github-generator
- Pro: immutable, auditable
- Con: consumers must manually bump versions

### SHA Pinning
- Reference by commit SHA: `uses: org/repo/.github/workflows/foo.yml@abc123`
- Recommended by GitHub's security guidance for third-party workflows
- Pro: immutable, immune to tag rewriting
- Con: unreadable, hard to track versions, requires Dependabot or Renovate

### Recommendation for Shirabe
Floating major version tags (v1) are the ecosystem convention. SHA pinning is
more secure but creates friction. A pragmatic approach: publish both exact
semver tags and floating major tags, document both options, and let consumers
choose their security posture.

## 5. Consumer Discovery

Reusable workflows have a discovery problem. Unlike GitHub Actions (which have
the Marketplace), reusable workflows have no dedicated catalog:

- **Actions Marketplace**: only lists composite/JS/Docker actions, not reusable
  workflows
- **README documentation**: most reusable workflow repos rely on README usage
  examples
- **Organization catalogs**: enterprises maintain internal lists
- **Word of mouth**: community adoption spreads through blog posts and
  conference talks

For shirabe, discovery would likely happen through:
1. The shirabe plugin README and documentation
2. The Claude Code plugin marketplace entry
3. Cross-linking from koto/tsuku documentation

## 6. Trust and Security Implications

Calling a third-party reusable workflow is a significant trust decision:

### What the Caller Exposes
- **GITHUB_TOKEN**: the called workflow receives the caller's token. Permissions
  can only be downgraded (never elevated) by the called workflow, but the caller
  must declare permissions explicitly.
- **Secrets**: passed via `secrets: inherit` (same org/enterprise) or explicit
  `secrets:` mapping. The called workflow can read any inherited secret.
- **Source code**: the workflow runs in the caller's repo context and can read
  all checked-out files.

### Security Boundaries
- GITHUB_TOKEN permissions propagate down but can only be restricted, not
  elevated, in nested workflow calls
- Called workflows run in the caller's context -- they can create releases,
  push tags, publish packages
- `secrets: inherit` only works within the same org/enterprise; cross-org
  requires explicit secret passing

### Mitigations
- Pin to SHA instead of tag (prevents tag rewriting attacks)
- Use Dependabot/Renovate to track updates to pinned SHAs
- Audit the workflow source before adopting
- Set minimal GITHUB_TOKEN permissions in the caller
- For release workflows specifically: the workflow needs `contents: write` to
  create releases, which is a high-privilege permission

### Implications for Shirabe
A release workflow is high-trust because it needs write permissions (creating
tags, releases, publishing artifacts). Consumers need to trust that shirabe's
workflow won't be compromised. Mitigations:
- Keep the workflow minimal and auditable
- Document exactly what permissions are needed and why
- Provide SHA-pinnable references
- Consider signing releases from the workflow

## 7. Patterns Summary

| Pattern | Example | Ships Workflows? | Ships Runtime Code? |
|---------|---------|-------------------|---------------------|
| CI-only repo | actions/checkout | Yes (actions) | No |
| CI-only repo | hashicorp/ghaction-terraform-provider-release | Yes (workflows) | No |
| Runtime + CI | slsa-framework/slsa-github-generator | Yes (workflows) | Yes (Go verifier) |
| Plugin only | VS Code extensions | No | Yes |
| Plugin only | Claude Code plugins | No | Yes |
| Plugin + CI | **shirabe (proposed)** | Yes (workflows) | Yes (skills) |

The slsa-github-generator is the closest precedent: a repo that ships both
executable code AND reusable workflows, versioned together under the same
semver tags.

## 8. Recommendations for Shirabe

1. **Place workflows in `.github/workflows/`** with `workflow_call` trigger --
   this is the standard location and consumers expect it there.

2. **Version workflows with the repo's semver tags.** Since shirabe already has
   a version in plugin.json, keep workflows on the same version cadence. Publish
   floating major version tags (v1) alongside exact tags (v1.2.3).

3. **Document the workflow contract clearly.** Required inputs, secrets, and
   GITHUB_TOKEN permissions should be explicit in both the workflow file and
   README.

4. **Keep the workflow minimal.** A release workflow that creates a GitHub
   Release from a tag is easy to audit. Avoid pulling in many third-party
   actions within the workflow itself.

5. **Acknowledge the novelty.** Shirabe would be the first Claude Code plugin
   to ship CI infrastructure. Frame this as a feature, not a quirk -- "shirabe
   gives you structured workflows for both your agent AND your release process."

---

## Sources

- [GitHub Docs: Reuse workflows](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- [GitHub Community: How to properly version reusable workflows](https://github.com/orgs/community/discussions/30049)
- [actions/toolkit: action-versioning.md](https://github.com/actions/toolkit/blob/main/docs/action-versioning.md)
- [hashicorp/ghaction-terraform-provider-release](https://github.com/hashicorp/ghaction-terraform-provider-release)
- [slsa-framework/slsa-github-generator](https://github.com/slsa-framework/slsa-github-generator)
- [github/codeql-action](https://github.com/github/codeql-action)
- [CodeQLEAKED supply chain attack](https://www.praetorian.com/blog/codeqleaked-public-secrets-exposure-leads-to-supply-chain-attack-on-github-codeql/)
- [GitHub Security Lab: Trusting building blocks](https://securitylab.github.com/resources/github-actions-building-blocks/)
- [GitHub Actions security best practices](https://docs.github.com/en/actions/reference/security/secure-use)
- [Loose versioning for reusable workflows](https://gist.github.com/brianjbayer/2ff33c37fd6ec24326651e64202c5681)
- [Claude Code plugin marketplaces](https://code.claude.com/docs/en/discover-plugins)

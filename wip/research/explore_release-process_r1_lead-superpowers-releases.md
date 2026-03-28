# Lead: How does obra/superpowers handle versioning and releases?

## Findings

### Versioning Structure
- **Plugin.json version**: Contains semantic versioning (currently 5.0.6)
- **Package.json version**: Also contains semantic versioning matching plugin.json (5.0.6)
- **Marketplace.json in official Anthropic registry**: Does NOT include a version field for superpowers entry
- **Dual-repository design**: Plugin repo (obra/superpowers) maintains version in plugin.json; skills repo (obra/superpowers-skills) is continuously updated with no version number

### Release Process
- **Release cadence**: Frequent updates—multiple releases per week based on RELEASE-NOTES.md history
- **RELEASE-NOTES.md structure**: Each release is documented with version header (vX.Y.Z YYYY-MM-DD format), categorized sections (Breaking Changes, New Features, Improvements, Bug Fixes), and includes GitHub issue/PR references for traceability
- **Immediate shipping philosophy**: As noted in October 2025 blog post, founder shipped with incomplete features ("seemed like the right impetus to ship") rather than waiting for perfect readiness
- **Community-driven**: Encourages bug reports and pull requests for new skills without fixed roadmap timelines

### Version Synchronization
- **plugin.json and package.json**: Both manually updated to match (5.0.6)
- **Marketplace.json in official Anthropic registry**: No version field present—superpowers entry points to `https://github.com/obra/superpowers.git` without specifying a version tag
- **Automatic skill updates**: Skills repository is pulled fresh on plugin installation; skills have no version number themselves
- **Git-based distribution**: Marketplace uses git clone with source URL; can pin versions using git tags/branches if needed (e.g., `superpowers@git+https://github.com/obra/superpowers.git#v5.0.3`)

### GitHub Actions and Automation
- **.github/workflows directory exists** but specific automation details not publicly discoverable in search results
- **No release scripts in package.json**: The package.json does not include `"scripts"` section with release automation
- **Manual release process**: Evidence suggests releases are created manually (git tags, RELEASE-NOTES.md updates) without observable CI automation for version bumping

### Marketplace Integration
- **Official Anthropic marketplace**: Superpowers accepted via PR #148 on January 15, 2026
- **No version field in official marketplace**: The anthropics/claude-plugins-official repository's marketplace.json does not include version for superpowers, unlike some other plugins
- **Self-hosted marketplace**: obra/superpowers-marketplace repository maintains its own marketplace.json with version: 5.0.6 in the plugin entry
- **Two-tier listing**: Plugin is listed in both official Anthropic marketplace (no version) and obra's self-hosted marketplace (with version)

## Implications

1. **Version management is MANUAL**: There's no observable automated version bumping in plugin.json, package.json, or RELEASE-NOTES.md. Each release requires explicit manual updates to these files plus git tag creation.

2. **Marketplace decoupling**: The official Anthropic marketplace doesn't track versions—it points to the main branch of the git repository. This means Anthropic's listing always resolves to HEAD, not a specific version. Version pinning is optional and user-controlled.

3. **Continuous deployment model for skills**: Unlike the plugin (which versions), skills are continuously updated via git pull with no versioning scheme. This enables rapid skill iteration without requiring plugin reinstalls.

4. **Dual marketplace strategy**: obra maintains both official Anthropic listing (for discovery) and self-hosted marketplace (for version tracking and control). The self-hosted marketplace is where explicit versioning matters.

5. **No CI-driven sync**: The gap between manual versioning and lack of automation means plugin.json, package.json, RELEASE-NOTES.md, git tags, and marketplace.json versions could drift if developer discipline lapses. This is a coordination risk that manual processes rely on remembering to update all files.

## Surprises

1. **Official Anthropic marketplace has no version field** for superpowers—this is unexpected. It suggests Anthropic's official marketplace doesn't enforce or track plugin versions; it's a directory of git repositories.

2. **No CI/CD automation visible**—Despite being a high-profile plugin with frequent releases, there's no discoverable GitHub Actions workflow for automated version bumping or release tagging. This is more manual than expected for a mature project.

3. **Incomplete features shipped intentionally**—The founder's blog post reveals a "ship fast, iterate" philosophy rather than "release when complete," which contrasts with typical SemVer discipline. This suggests versioning is loose.

4. **Git tag-based pinning is optional**—Most users probably get whatever is on main branch; semantic versioning in plugin.json is more for metadata/documentation than enforcing specific versions in the wild.

## Open Questions

1. **How do manual version updates stay in sync?** What process or checklist ensures plugin.json, package.json, RELEASE-NOTES.md, git tags, and both marketplace.json files are all updated together?

2. **Does Anthropic's official marketplace ever update the version field?** Or is it intentionally omitted because Anthropic expects users to always get main branch?

3. **What triggers a release?** Is it commits to main, a specific branch merge, or manual decision? Are there release blockers or gating checks?

4. **Do users installing from official Anthropic marketplace get the version in plugin.json?** If Anthropic's marketplace.json lacks a version field, does the plugin installer fall back to what's in the repo's plugin.json?

5. **Is the "ship fast, iterate" philosophy still active?** The blog post was from October 2025; has release discipline changed since then?

## Summary

Obra/superpowers uses **manual semantic versioning** in plugin.json and package.json with frequent, loosely-gated releases documented in RELEASE-NOTES.md, but the **official Anthropic marketplace doesn't track versions**—it points users to the main branch via git, making version coordination a developer-discipline issue rather than an automated guarantee. The dual-marketplace approach (official for discovery + self-hosted for version control) reflects a pragmatic workaround for this gap, and the lack of observable CI automation means synchronizing plugin.json, package.json, git tags, and marketplace.json versions remains a manual coordination risk.


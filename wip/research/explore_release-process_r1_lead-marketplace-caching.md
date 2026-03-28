# Lead: What does the Claude Code marketplace expect regarding version, ref, and caching?

## Findings

### Version Resolution and Manifest Precedence

According to the [Plugins reference documentation](https://code.claude.com/docs/en/plugins-reference), Claude Code explicitly states: **"Claude Code uses the version to determine whether to update your plugin. If you change your plugin's code but don't bump the version in `plugin.json`, your plugin's existing users won't see your changes due to caching."**

When both `plugin.json` and marketplace entry declare a version, **the plugin manifest always wins silently**. This means the marketplace-declared version is ignored if a version exists in the plugin's own manifest. The documentation recommends: "When possible, avoid setting the version in both places. For relative-path plugins, set the version in the marketplace entry. For all other plugin sources, set it in the plugin manifest."

### How Marketplace Cloning Works

The Claude Code marketplace installation process clones the marketplace repository to `~/.claude/plugins/marketplaces/<marketplace-name>/`. On plugin install and update, Claude Code reads the plugin's `plugin.json` **from the cached clone at that ref/sha**, not from a central registry. This is clear from the [Plugin marketplaces documentation](https://code.claude.com/docs/en/plugin-marketplaces): plugins sources support both `ref` (branch/tag) and `sha` (exact commit) pinning.

### Cache Directory Structure

Plugin caching follows this structure: `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`. The cache path is keyed by the resolved version string. This means if a git ref points to a commit whose `plugin.json` declares version "1.0.0", the plugin is cached at `cache/<marketplace>/<plugin>/1.0.0/`.

### Version as Cache Invalidation Mechanism

The version field acts as the **only cache-busting signal**. From the documentation: "The plugin's `plugin.json` must declare a different `version` at each pinned ref or commit. If two refs or commits have the same manifest version, Claude Code treats them as identical and skips the update."

This is critical: **the marketplace does not use git commit SHAs to determine uniqueness—it uses the semantic version string**. If you tag a release `v1.2.3` with `plugin.json` declaring `"version": "1.2.3"`, and later you rebase and push to the same tag with the same version in plugin.json, Claude Code will treat them as identical and skip the update, even though the commit SHA changed.

### Release Channel Management

The documentation shows an example of setting up "stable" and "latest" release channels using two marketplace entries pointing to different refs:

```json
{
  "name": "stable-tools",
  "plugins": [{
    "name": "code-formatter",
    "source": {
      "source": "github",
      "repo": "acme-corp/code-formatter",
      "ref": "stable"
    }
  }]
}
```

Each ref must have a **different version in its `plugin.json`** for updates to be detected. The same `plugin.json` version across different refs causes updates to be skipped.

### Known Caching Issues

Multiple [GitHub issues](https://github.com/anthropics/claude-code/issues?q=plugin+cache) document that the update mechanism has bugs where the marketplace clone isn't refreshed before checking versions (Issue #37252, #29071, #25244), and the plugin cache in `~/.claude/plugins/cache/` is not invalidated when updates occur (Issue #14061, #16866). However, these are implementation bugs, not design issues—the **intended design** is clear: read version from the manifest at the pinned ref.

## Implications

For shirabe's release process:

1. **Version source**: The marketplace reads `version` from `plugin.json` at the git ref/sha specified in the marketplace entry, not from a separate manifest.json registry file. This means the version must be baked into the plugin directory at the time of tagging.

2. **Version as sole update signal**: Semantic versioning in `plugin.json` is the only mechanism Claude Code uses to detect updates. Git commit SHAs are irrelevant for update detection; only the semantic version matters.

3. **Sync requirement**: For consistent behavior, shirabe should ensure:
   - The git tag version matches the `plugin.json` version
   - The marketplace.json entry (if one is maintained) should NOT also declare a version (or must match exactly)
   - Each release must increment the version in `plugin.json` before tagging

4. **No registry lookup**: Claude Code does not consult a central registry to compare versions. It clones the ref locally and reads from there. This means there's no way to set version dynamically at release time from an external source—the version must be in the plugin.json file that gets committed.

## Surprises

The biggest surprise is **how strongly the documentation emphasizes that version is the sole update signal**, while simultaneously acknowledging multiple known bugs in the update implementation. The design is clean, but the execution is buggy.

Also unexpected: the marketplace entry can specify a version, but it's silently ignored if the plugin.json also has one. There's no error or warning—it just silently prefers the manifest version. This is a footgun for teams that try to maintain versions in both places.

## Open Questions

1. **Can we set version automatically at tag time?** The version must be in the committed `plugin.json` to be read from the git ref. Is there a release process (e.g., using a GitHub Action during tag creation) that can automatically rewrite plugin.json with the version extracted from the tag name?

2. **Should shirabe maintain a marketplace.json?** If shirabe releases as a standalone plugin (not part of a larger marketplace), should there be a separate marketplace.json, or should users add shirabe's repo directly?

3. **What about pre-releases and git workflows?** If version "1.0.0" is already in plugin.json on main, and you tag it, does the version need to be bumped to "1.0.1-dev" on main after tagging to avoid confusion?

## Summary

Claude Code reads the plugin version from `plugin.json` at the specific git ref/sha specified in the marketplace entry—not from a central registry. The version field is the sole mechanism for update detection: if two refs have identical versions, Claude Code treats them as the same and skips updates. This means shirabe must ensure that each release atomically synchronizes the git tag, the plugin.json version, and any marketplace.json entry (if maintained), with the semantic version embedded in the committed files before tagging.

Sources:
- [Create and distribute a plugin marketplace - Claude Code Docs](https://code.claude.com/docs/en/plugin-marketplaces)
- [Plugins reference - Claude Code Docs](https://code.claude.com/docs/en/plugins-reference)
- [Discover and install prebuilt plugins - Claude Code Docs](https://code.claude.com/docs/en/discover-plugins)
- [claude plugin update does not refresh marketplace clone before version check - Issue #37252](https://github.com/anthropics/claude-code/issues/37252)
- [Plugin cache not cleared on uninstall/reinstall - Issue #29074](https://github.com/anthropics/claude-code/issues/29074)
- [Plugin cache: CLAUDE_PLUGIN_ROOT points to stale version after plugin update - Issue #15642](https://github.com/anthropics/claude-code/issues/15642)

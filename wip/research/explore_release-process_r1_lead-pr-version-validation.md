# Lead: What validation should CI run on every PR to prevent version drift?

## Findings

### Current CI State

Shirabe has three CI workflows, none version-related:
- `check-evals.yml` — verifies skills have evals
- `check-templates.yml` — koto template freshness (reusable from koto)
- `validate-templates.yml` — koto template compilation

No version validation exists. The manifests already drifted: plugin.json and marketplace.json say 0.2.0, but the only git tag is 0.1.0.

### Approach A: Sentinel Value (`0.0.0-dev` on main)

Manifests on main always contain `"version": "0.0.0-dev"`. The release workflow replaces this with the real version at release time, then commits back.

**CI check:** Simple exact-match — `jq -r .version .claude-plugin/plugin.json` must equal `0.0.0-dev` on every PR to main.

**Advantages:**
- Dead-simple CI check (string equality)
- Impossible to accidentally ship a wrong version — only the release workflow writes real versions
- New contributors can't accidentally cause version drift
- Aligns with marketplace caching: Claude Code skips updates when versions match, so a sentinel ensures the dev branch is never confused with a release

**Disadvantages:**
- `plugin.json` on main doesn't reflect the current release version (must check tags/releases)
- Slightly unconventional — most projects keep the real version in their manifest

### Approach B: Match Latest Tag

Manifests contain the real version matching the latest git tag. CI checks that the version in manifests matches the latest `v*` tag.

**CI check:** Compare `jq -r .version .claude-plugin/plugin.json` against `git describe --tags --abbrev=0 --match 'v*'`.

**Advantages:**
- Manifests always show the real version
- Familiar pattern for most projects

**Disadvantages:**
- Complex CI check — must resolve "latest tag" which depends on git fetch depth
- Contributors who bump the version in a PR (thinking they should) will pass CI but create drift if the version doesn't match what release automation would set
- Ambiguous: should a PR that changes manifests be allowed or rejected?
- Fragile: shallow clones, tag deletion, or force-pushes can break the check

### Koto Comparison

Koto's `check-template-freshness.yml` pins a version default that the `finalize-release` job updates after each release. This is conceptually similar to approach B — a value in a file that CI validates and release automation updates. But koto's case is simpler because the value is a workflow input default, not a user-facing version field.

## Implications

The sentinel approach is the better fit for shirabe's fully-automated release model:
- It eliminates an entire class of drift bugs (manual version bumps)
- It's compatible with the tag-triggered release workflow where a `finalize-release` job writes the real version
- The CI check is trivially implementable: one `jq` command, one string comparison
- It works regardless of git clone depth or tag history

## Surprises

The match-tag approach, which seems more "standard," actually creates more failure modes in CI than the sentinel approach. Shallow clones (common in CI) may not have tag history, making `git describe` unreliable without explicit `fetch-depth: 0`.

## Open Questions

- Should the sentinel be `0.0.0-dev` or something else (like `0.0.0-unreleased`)?
- Should the CI check also validate that both manifests have the same version (not just the sentinel)?
- When the release workflow writes the real version, should it commit to main or to the tag only?

## Summary

The sentinel approach (0.0.0-dev on main, real versions only at release tags) is the least-friction solution because it provides a simple exact-match CI check, prevents accidental version bumps, and aligns version control with marketplace cache semantics. The match-tag approach creates more CI complexity, confuses new contributors with ambiguous rules, and is fragile against tag history changes. Implementing sentinel validation requires a straightforward workflow that checks for 0.0.0-dev in both manifests on every PR, updating manifests only at release time.

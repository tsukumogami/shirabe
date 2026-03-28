# Lead: Release-Please Architecture and Patterns

## Summary

Release-please is Google's open-source tool for automating releases based on
Conventional Commits. It uses a PR-based workflow where a persistent "release
PR" accumulates changes, and merging that PR triggers version tagging and
GitHub Release creation. It supports 20+ language strategies and has a manifest
configuration for monorepos with per-package overrides and a plugin system for
workspace coordination.

## How It Works

### The Core Flow

1. **Commit analysis**: On every push to the default branch, release-please
   scans git history for Conventional Commit prefixes (`feat:`, `fix:`,
   `deps:`, `!` for breaking changes).
2. **Release PR creation/update**: When releasable commits exist, it creates
   (or updates) a release PR. This PR contains version bumps in
   language-specific files, CHANGELOG.md updates, and manifest version updates.
3. **Human review**: The PR sits open, accumulating changes as more commits
   land. Developers merge it when they're ready to cut a release.
4. **Tag + GitHub Release**: After merge, the same workflow run tags the merge
   commit and creates a GitHub Release with the generated changelog as release
   notes.

Status labels track progression: `autorelease: pending` (pre-merge),
`autorelease: tagged` (post-merge), `autorelease: published` (after
distribution).

### What It Does NOT Do

- Does not publish to package registries (npm, crates.io, etc.)
- Does not handle complex branch strategies (release branches, hotfixes)
- Does not provide pre/post hooks or lifecycle callbacks
- Does not bump back to a development/snapshot version after release (except
  Java/Maven, which generates `-SNAPSHOT` versions)

## Configuration Model

### Two Files

**release-please-config.json** -- central configuration:

```json
{
  "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
  "release-type": "go",
  "packages": {
    ".": {},
    "packages/lib-a": {
      "release-type": "node",
      "package-name": "lib-a"
    },
    "packages/lib-b": {
      "release-type": "rust"
    }
  },
  "plugins": ["node-workspace"],
  "separate-pull-requests": false
}
```

**.release-please-manifest.json** -- version state (source of truth):

```json
{
  ".": "1.2.3",
  "packages/lib-a": "0.5.0",
  "packages/lib-b": "2.0.1"
}
```

The manifest starts empty (`{}`) and gets populated after the first release PR
merges. For existing projects, you seed it with current versions.

### Top-Level vs Per-Package Settings

Most settings can be specified at the top level (defaults for all packages) or
per-package (overrides). Key settings:

| Setting | Purpose |
|---------|---------|
| `release-type` | Language strategy (go, rust, node, simple, etc.) |
| `package-name` | Explicit name when source can't be auto-detected |
| `release-as` | Force a specific next version |
| `bump-minor-pre-major` | BREAKING bumps minor instead of major pre-1.0 |
| `draft` | Create draft GitHub Releases |
| `prerelease` | Mark releases as pre-release |
| `skip-github-release` | Only bump versions, skip GH Release |
| `skip-changelog` | Don't update CHANGELOG.md |
| `separate-pull-requests` | One PR per package vs aggregate PR |
| `extra-files` | Additional files to version-stamp |
| `exclude-paths` | Paths to ignore in commit analysis |
| `changelog-path` | Custom changelog location |

### Bootstrap Options

- `bootstrap-sha`: Commit SHA that limits initial changelog scope
- `last-release-sha`: Override baseline for next release calculation
- `release-search-depth` / `commit-search-depth`: Pagination limits

## Supported Release Types (Strategies)

Release-please ships 20+ strategies. Each knows which files to update:

| Strategy | Files Updated |
|----------|---------------|
| `node` | package.json, CHANGELOG.md |
| `python` | setup.py, setup.cfg, pyproject.toml, `__init__.py` |
| `rust` | Cargo.toml, CHANGELOG.md |
| `go` | CHANGELOG.md only (Go has no version file by convention) |
| `java` | pom.xml + SNAPSHOT bump |
| `maven` | pom.xml + SNAPSHOT bump |
| `ruby` | version.rb, CHANGELOG.md |
| `dart` | pubspec.yaml |
| `elixir` | mix.exs |
| `helm` | Chart.yaml |
| `terraform-module` | versions, CHANGELOG.md |
| `simple` | version.txt, CHANGELOG.md |
| `php` | composer.json |
| `ocaml` | dune-project |
| `sfdx` | sfdx-project.json |
| `bazel` | MODULE.bazel |
| `r` | DESCRIPTION |

Google also maintains internal "yoshi" variants for their client libraries
(dotnet-yoshi, go-yoshi, java-yoshi, php-yoshi, ruby-yoshi).

### The `simple` Escape Hatch

For ecosystems without a dedicated strategy, `simple` updates a `version.txt`
file. Combined with `extra-files`, it can stamp versions into arbitrary files.

## Monorepo Support

### Package Discovery

Each entry in `packages` maps a directory path to its release config. The
special key `"."` represents the repo root. Release-please filters commits by
path -- only commits touching files under a package's directory trigger version
bumps for that package.

### Aggregate vs Separate PRs

By default, all packages share a single release PR. Set
`separate-pull-requests: true` to get one PR per package. Tag naming follows
the pattern `<component>-v<version>` for multi-package repos or `v<version>`
for single-package repos (controlled by `include-component-in-tag`).

### Workspace Plugins

For coordinated releases across packages that depend on each other:

- **node-workspace**: Discovers Node.js packages, updates cross-references
  in package.json files. `always-link-local` forces local dependency updates.
- **cargo-workspace**: Coordinates Rust workspace member versions.
- **maven-workspace**: Handles Maven multi-module projects.
- **linked-versions**: Forces a group of components to share the same
  version number.

Plugins run after individual package releasers but before PR creation. They
receive candidate release PRs and can merge, modify, or reorder them.

### Other Plugins

- **sentence-case**: Normalizes changelog formatting
- **group-priority**: Controls package ordering in aggregate PRs

## Version File Customization (extra-files)

The `extra-files` array supports several updater types:

```json
{
  "extra-files": [
    "path/to/file.txt",
    {"type": "json", "path": "plugin.json", "jsonpath": "$.version"},
    {"type": "toml", "path": "pyproject.toml", "jsonpath": "$.tool.poetry.version"},
    {"type": "yaml", "path": "chart.yaml", "jsonpath": "$.appVersion"},
    {"type": "xml", "path": "pom.xml", "xpath": "//project/version"},
    {"type": "generic", "path": "Makefile"}
  ]
}
```

For the `generic` type and plain string entries, release-please looks for
annotation comments in the file:

```
# x-release-please-version
VERSION=1.2.3
```

Or block annotations:

```
# x-release-please-start-version
version = "1.2.3"
# x-release-please-end
```

This is how you'd handle a `plugin.json` for a Claude Code plugin -- use the
JSON updater with `jsonpath: "$.version"`.

## Versioning Strategies

Beyond the release-type (which determines *what files* to update), versioning
strategies control *how* versions are calculated:

- **default**: Standard semver (fix=patch, feat=minor, breaking=major)
- **always-bump-patch**: Every release bumps patch
- **always-bump-minor**: Every release bumps minor
- **always-bump-major**: Every release bumps major
- **service-pack**: Service pack versioning
- **prerelease**: Prerelease version handling (e.g., 1.0.0-beta.1)

## Limitations and Criticisms

### Architectural Limitations

1. **No publish step**: Release-please handles versioning and GitHub Releases
   but stops there. You need separate workflow steps for `npm publish`,
   `cargo publish`, `go` proxy notification, etc. This is by design -- it's a
   versioning tool, not a deployment tool.

2. **No dev version bump**: Except for Java/Maven's SNAPSHOT pattern, there's
   no built-in "bump to next dev version after release" step. The Maven
   prepare-release dance (stamp release, tag, bump to dev) isn't natively
   supported for other ecosystems.

3. **PR-only workflow**: The release always goes through a PR. There's no
   `workflow_dispatch` "release now" button. This is intentional (human review
   gate) but can feel heavy for small projects or when you want on-demand
   releases.

4. **No lifecycle hooks**: Unlike release-it or semantic-release, there are
   no pre-version, post-version, pre-tag, post-tag hooks. Customization
   happens through extra-files and plugins, not callbacks.

5. **Monorepo complexity**: The v4 migration added required config files and
   changed output variable semantics. The `releases_created` (plural) output
   was reported as returning `true` regardless of whether a release actually
   occurred, causing unintended production deployments.

### Practical Pain Points

- **Bootstrap friction**: First-time setup requires manually seeding the
  manifest with existing versions and potentially setting `bootstrap-sha`.
- **Debugging difficulty**: When release-please doesn't create a PR or
  skips a package, diagnosing why (commit filtering, path matching, search
  depth limits) is not straightforward.
- **Limited changelog control**: Two built-in types (default grouped-by-type,
  or GitHub-generated). Custom formats require implementing a TypeScript
  interface.
- **Go support is thin**: The `go` strategy only updates CHANGELOG.md since
  Go doesn't have a version file. If you maintain version constants in Go
  source, you need extra-files with annotations.

### Why People Move Away

- Teams wanting fully automated CI/CD (no PR gate) prefer semantic-release
- Teams wanting explicit changeset files prefer changesets
- Teams needing publish/deploy integration find release-please insufficient
  on its own
- The v3-to-v4 migration broke many workflows

## Comparison With Our Design

| Aspect | Release-Please | Our Design |
|--------|---------------|------------|
| **Trigger** | Automatic on push | `workflow_dispatch` (on-demand) |
| **Flow** | PR accumulates, merge triggers release | Maven-style: stamp, commit, tag, dev bump, push |
| **Dev version** | Not supported (except Java) | Core requirement |
| **Publish** | Not included | Not included (separate concern) |
| **Version files** | Strategy per language + extra-files | Repo-local hooks |
| **Monorepo** | First-class with plugins | Single-package focus per repo |
| **Customization** | Plugins (TypeScript) | Shell hooks (language-agnostic) |
| **PR gate** | Required (the release IS a PR) | Optional (can add if desired) |

### What to Adopt

1. **extra-files with jsonpath/xpath**: The structured updater approach for
   JSON, TOML, YAML, XML files is well-designed. Our hook system could offer
   similar declarative config as an alternative to shell scripts.

2. **Conventional Commits for changelog**: Parsing commit history to generate
   release notes is standard practice. We should support it even if we don't
   require it.

3. **Manifest version tracking**: A `.release-manifest.json` or similar file
   as the source of truth for current version is useful for multi-file version
   stamping.

### Where to Diverge

1. **workflow_dispatch over PR-based**: Our repos are small enough that the
   PR gate adds ceremony without value. The person running the release is
   already a maintainer.

2. **Dev version bump**: Release-please doesn't solve this. Our Maven-style
   dance (stamp release version, tag, bump to dev, push) is a genuine
   differentiator for the ecosystems we support.

3. **Shell hooks over TypeScript plugins**: Our repos span Go, Rust, and
   JSON-based plugins. A plugin system that requires writing TypeScript is
   wrong for us. Shell hooks or declarative config (like extra-files) fit
   better.

4. **Reusable workflow, not a tool**: Release-please is a standalone Node.js
   tool distributed as an npm package and GitHub Action. We're building a
   reusable GitHub Actions workflow + skill, which is lighter to maintain and
   doesn't require installing a tool.

## Sources

- [release-please repository](https://github.com/googleapis/release-please)
- [release-please-action](https://github.com/googleapis/release-please-action)
- [Manifest releaser docs](https://github.com/googleapis/release-please/blob/main/docs/manifest-releaser.md)
- [Customization docs](https://github.com/googleapis/release-please/blob/main/docs/customizing.md)
- [Config schema](https://github.com/googleapis/release-please/blob/main/schemas/config.json)
- [Release-please vs semantic-release](https://www.hamzak.xyz/blog-posts/release-please-vs-semantic-release)
- [NPM release automation comparison](https://oleksiipopov.com/blog/npm-release-automation/)
- [Release-please v4 migration issues](https://danwakeem.medium.com/beware-the-release-please-v4-github-action-ee71ff9de151)
- [Monorepo example](https://github.com/amarjanica/release-please-monorepo-example)

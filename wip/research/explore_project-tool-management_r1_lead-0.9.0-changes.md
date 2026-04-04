# Lead: What changed in tsuku 0.9.0 that affects `.tsuku.toml` adoption?

## Findings

### Friction Point 1: Org-scoped recipes in `.tsuku.toml` -- RESOLVED

PR #2235 (`fix(config): support org-scoped recipes in .tsuku.toml`) landed in
v0.9.0 with a full design doc at
`docs/designs/current/DESIGN-org-scoped-project-config.md`.

The fix has three parts:

1. **TOML syntax**: Quoted keys work -- `"tsukumogami/koto" = "0.2"` is valid
   TOML. Bare keys still can't contain `/`, but the docs now make the quoted-key
   convention explicit.

2. **Runtime**: `runProjectInstall` in `cmd/tsuku/install_project.go` gained a
   pre-scan phase that detects org-scoped keys via `parseDistributedName`,
   collects unique sources, and batch-bootstraps distributed providers via
   `ensureDistributedSource` before the per-tool install loop. The `--yes` flag
   propagates for CI use.

3. **Resolver**: `internal/project/resolver.go` now builds a `bareToOrg` reverse
   map so `ProjectVersionFor` matches org-prefixed config keys against bare
   binary-index recipe names. Shell integration version pinning works for
   distributed tools.

`internal/project/orgkey.go` provides `SplitOrgKey` which parses
`"tsukumogami/koto"` into source `tsukumogami/koto` and bare name `koto`. This
is tested in `internal/project/orgkey_test.go` (108 lines of test cases
including path traversal rejection).

### Friction Point 2: `"latest"` version string failing -- RESOLVED

PR #2234 (`fix(install): "latest" version string fails resolution in
.tsuku.toml`) normalizes `"latest"` to empty string in
`Executor.ResolveVersion()` so it routes to `ResolveLatest()`. Both `""` and
`"latest"` are now documented as equivalent in the shell integration guide
(`docs/guides/shell-integration.md`, line 49).

### Friction Point 3: Missing adoption guide -- PARTIALLY RESOLVED

The shell integration guide (`docs/guides/shell-integration.md`) is substantial
(179 lines) and covers:

- `tsuku init` to create the file
- Declaring tools with version strings (exact, prefix, latest)
- `tsuku install` with no args for batch install
- Config discovery (walk-up, ceiling paths)
- Shell activation (explicit and automatic hooks)
- `--yes` and `--dry-run` flags for CI
- Exit code semantics (0/6/15)

What's still missing:

- No dedicated "adopting tsuku for your project" guide that walks through the
  full journey (why, create config, update CI, onboard teammates)
- No CI-specific guide (GitHub Actions, etc.)
- No migration guide from manual installs to `.tsuku.toml`

### Friction Point 4: Tool discovery / recipe coverage -- PARTIALLY RESOLVED

**gh recipe now supports Linux** (PR #2239). The recipe at `recipes/g/gh.toml`
handles darwin (zip) and linux (tarball) via `github_archive` action with
`cli/cli` as the source. This is critical for CI since GitHub Actions runners
are Linux.

**jq recipe exists** at `recipes/j/jq.toml` but `tsuku search jq` returns
"No recipes found". This suggests jq is available as an embedded recipe but not
indexed in the search catalog. The recipe file is on disk, so `tsuku install jq`
likely works even though search doesn't find it.

**koto has no recipe in the tsuku registry.** It's an org-scoped distributed
recipe from `tsukumogami/koto`. With the org-scoped fix in 0.9.0, declaring
`"tsukumogami/koto" = "0.2"` in `.tsuku.toml` should now work.

**python3 and claude have no tsuku recipes.** No recipe files exist for either.
python3 is a system dependency that tsuku doesn't manage. claude (Anthropic CLI)
would need a new recipe or must remain outside tsuku management.

### New in 0.9.0: Project-level auto-update integration

PR #2219 (`feat(update): project-level auto-update integration with
.tsuku.toml`) makes `.tsuku.toml` version constraints act as effective pins
during auto-update. Exact pins suppress auto-update entirely; prefix pins narrow
the boundary (e.g., `node = "20"` blocks a node 22.x update even when global
pin is latest). Design doc at
`docs/designs/current/DESIGN-project-level-auto-update.md`.

### New in 0.9.0: Version string documentation

PR #2238 expanded `docs/guides/shell-integration.md` to document:
- Prefix matching is dot-boundary-aware (`"1"` matches `1.29.3` but not
  `10.0.0`)
- Homebrew recipes only expose current bottle version -- pinning older patches
  fails
- `tsuku versions <tool>` shows available versions before writing a pin

### New in 0.9.0: `tsuku doctor --fix`

PR #2228 adds auto-repair for broken shell integration. Useful for onboarding
since `tsuku doctor --fix` can resolve common setup issues without manual
intervention.

### New in 0.9.0: AI skills for recipe authoring

PR #2237 ships three Claude Code skills as plugins. These could help with
creating missing recipes (python3, claude) but that's out of scope for this
exploration.

## Implications

1. **Org-scoped koto declaration is now viable.** The `.tsuku.toml` for shirabe
   can use `"tsukumogami/koto" = "0.2"` and `tsuku install -y` in CI will
   bootstrap the distributed source automatically.

2. **gh is installable on Linux now.** CI workflows can declare `gh = ""` and
   get it from GitHub releases on Linux runners.

3. **jq may work despite search being broken.** Need to test whether
   `tsuku install jq` resolves correctly from the embedded recipe.

4. **python3 and claude remain outside tsuku.** These still need separate
   handling in CI. python3 is pre-installed on GitHub Actions runners; claude
   requires `npm install -g @anthropic-ai/claude-code` or similar.

5. **Version pinning strategy is well-documented now.** The prefix matching
   semantics and Homebrew limitations are clearly explained, making pinning
   decisions straightforward.

6. **Auto-update integration means `.tsuku.toml` pins are respected globally.**
   Developers won't have their project tools auto-updated past the declared
   constraint.

## Surprises

1. **`tsuku search` doesn't find recipes that exist on disk.** `tsuku search jq`
   returns nothing despite `recipes/j/jq.toml` existing. This is a UX issue
   worth filing -- users checking recipe availability before writing `.tsuku.toml`
   would conclude jq isn't supported.

2. **v0.9.0 was released today (2026-04-04).** The tag didn't exist before
   `git fetch`. The timing is very recent, meaning adoption would be on a
   just-released version.

3. **No `tsuku init` scaffolding for org-scoped tools.** `tsuku init` creates a
   bare `[tools]` section. There's no interactive mode that examines installed
   tools or suggests declarations. Users must know the quoted-key syntax for
   org-scoped tools.

4. **The shell integration guide is surprisingly complete** for a feature that
   was recently flagged as lacking documentation. It covers activation hooks,
   ceiling paths, exit codes, and version string semantics. The gap is more about
   a "getting started" wrapper than missing reference content.

## Open Questions

1. Does `tsuku install jq` actually work from the embedded recipe, or is the
   search miss indicative of an install problem too?

2. What version of tsuku should shirabe's CI pin to? Should we require 0.9.0+
   given the org-scoped fix is essential?

3. Should shirabe declare python3 and claude in `.tsuku.toml` with `optional =
   true` (if such a flag exists), or leave them out entirely?

4. Is there a GitHub Action for tsuku (`uses: tsukumogami/setup-tsuku@v1`) or
   does CI need to curl the binary directly?

5. How does `tsuku install -y` behave when some declared tools have no recipe?
   Does it fail the whole batch or skip gracefully (exit code 15)?

## Summary

Tsuku 0.9.0 resolves the two most critical blockers for shirabe adoption: org-scoped recipes now work in `.tsuku.toml` via quoted keys (PR #2235), and the `"latest"` version string no longer fails (PR #2234), plus `gh` gained Linux support for CI use. The main remaining gaps are recipe coverage (no recipes for koto in the main registry, python3, or claude -- koto works via distributed source, the others need alternative handling) and the absence of a CI-focused adoption guide. The biggest open question is whether `tsuku search` failing to find on-disk recipes like jq indicates a deeper indexing problem that would affect the install flow.

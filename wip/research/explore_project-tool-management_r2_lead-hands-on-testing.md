# Lead: Hands-on testing of `.tsuku.toml` adoption with tsuku 0.9.0

## Environment

- **Docker image**: `ubuntu:24.04` (PRETTY_NAME="Ubuntu 24.04.3 LTS")
- **System packages**: curl, git, ca-certificates (minimal)
- **tsuku version installed**: 0.9.0 (via `curl -fsSL https://get.tsuku.dev/now | bash`)
- **Date**: 2026-04-04
- **Architecture**: linux-amd64

## Friction Log

### Step 1: Install tsuku 0.9.0 via bootstrap script

**Command**: `curl -fsSL https://get.tsuku.dev/now | bash`

**Output** (key lines):
```
Detected platform: linux-amd64
Fetching latest release...
Latest version: v0.9.0
Downloading tsuku-linux-amd64...
Verifying checksum...
Installing to /home/testuser/.tsuku/bin...
tsuku v0.9.0 installed successfully!

Unknown shell: sh
Add this to your shell config to use tsuku:
  . "/home/testuser/.tsuku/env"

WARNING: Unrecognized shell 'sh'; skipping hook registration.
```

**Wall clock**: ~16 seconds

**What I expected**: Clean install with no warnings in a Docker/CI environment.

**Friction**: The "Unknown shell: sh" warning is expected inside Docker where `su -` drops into `/bin/sh`. The bootstrap automatically refreshes the registry (`local: refreshed`, `embedded: refreshed`), which is good. Telemetry opt-out notice is reasonable.

**Friction score**: 1 -- Minor. The shell warning is confusing in CI contexts but doesn't block anything. A `--ci` flag or `TSUKU_CI=1` env var to suppress shell-specific warnings would help.

**Issue-worthy?** No -- expected behavior when running under sh.

---

### Step 2: Run `tsuku init`

**Command**: `tsuku init` (in empty `/tmp/test-project`)

**Output**:
```
Created .tsuku.toml
```

**Generated file contents**:
```toml
# Project tools managed by tsuku.
# See: https://tsuku.dev/docs/project-config
[tools]
```

**Friction**: The output is clean and minimal. The generated file has a helpful comment with a docs link. No guidance on syntax or examples for adding tools -- you'd need to visit the docs URL or already know the format.

**Friction score**: 0 -- Smooth. The docs link is sufficient.

**Issue-worthy?** No.

---

### Step 3: Write the intended config

**Command**: Wrote `.tsuku.toml` with:
```toml
[tools]
"tsukumogami/koto" = "0.5"
gh = "2"
```

**Friction score**: 0 -- N/A, manual edit.

---

### Step 4: Run `tsuku install -y` (first attempt with `"0.5"`)

**Command**: `tsuku install -y`

**Output** (summarized):
```
Auto-registered source "tsukumogami/koto"
Using: /tmp/test-project/.tsuku.toml
Tools: gh@2, koto@0.5

[gh installs successfully - 4 steps, ~3 seconds]

Installed to: /home/testuser/.tsuku/tools/gh-2.89.0
Symlinked 1 binaries: [bin/gh]
Verifying gh (version 2.89.0)... Installation verified

Failed to generate plan: version resolution failed: version 0.5 not found for tsukumogami/koto

Installed: 1 tool (gh)
Failed: 1 tool
  tsukumogami/koto: version resolution failed: version 0.5 not found for tsukumogami/koto
Exit code: 15
```

**What I expected**: `"0.5"` should resolve to the latest 0.5.x release (0.5.0), similar to how `gh = "2"` resolves `2` to `2.89.0`.

**Key finding**: Version resolution behaves differently for distributed source recipes vs built-in recipes. `gh = "2"` correctly resolves major-only `2` to `2.89.0`, but `"tsukumogami/koto" = "0.5"` fails because the distributed source doesn't support partial semver matching. Using `"0.5.0"` (full semver) works.

**Friction score**: 3 -- **Blocker for the intended config**. The asymmetry between built-in recipe version resolution (supports partial semver) and distributed source resolution (requires exact semver) is a real bug. Users will naturally write `"0.5"` and expect it to work.

**Issue-worthy?** Yes -- version resolution for distributed sources should support partial semver (major-only, major.minor) the same way built-in recipes do.

---

### Step 4b: Retry with `"0.5.0"` (full semver)

**Command**: Changed config to `"tsukumogami/koto" = "0.5.0"` and ran `tsuku install -y`

**Output** (summarized):
```
Auto-registered source "tsukumogami/koto"
Using: /tmp/tp3/.tsuku.toml
Tools: gh@2, koto@0.5.0

[gh installs successfully]
[koto installs successfully - 3 steps, single binary download]

Installed to: /home/testuser/.tsuku/tools/koto-0.5.0
Symlinked 1 binaries: [bin/koto]
Verifying koto (version 0.5.0)... Installation verified

Installed: 2 tools (gh, tsukumogami/koto)
```

**Wall clock**: ~5 seconds (both tools, cached downloads)

**Observations**:
- "Auto-registered source" message on first run is helpful -- tells the user what happened
- Source registration persists across runs (only shown once)
- koto is a single binary, so install is fast (3 steps vs 4 for gh)
- Both tools land in `~/.tsuku/tools/current/` as symlinks

**Friction score**: 0 -- Smooth once you use full semver.

---

### Step 5: Verify installed tools

**Command**: `koto version` and `gh --version` (with `~/.tsuku/tools/current` in PATH)

**Output**:
```
koto 0.5.0 (2b6291f 2026-03-30T15:41:26Z)
gh version 2.89.0 (2026-03-26)
```

**Note**: Tools are NOT in `~/.tsuku/bin/` -- they're symlinked in `~/.tsuku/tools/current/`. The `~/.tsuku/bin/` directory only contains the `tsuku` binary itself. This means the PATH setup requires `~/.tsuku/tools/current` in addition to `~/.tsuku/bin/`.

**Friction score**: 1 -- The install output says `export PATH="/home/testuser/.tsuku/tools/current:$PATH"` which is correct but different from the bootstrap's `. "/home/testuser/.tsuku/env"`. Having two different PATH instructions is slightly confusing. The env file presumably handles both.

**Issue-worthy?** No -- the env file covers this, but the post-install message could say "run: eval $(tsuku shellenv)" instead of the raw export.

---

### Step 6: Test idempotency

**Command**: `tsuku install -y` (second run, both tools already installed)

**Output** (summarized):
```
Using: /tmp/tp3/.tsuku.toml
Tools: gh@2, koto@0.5.0

[gh: re-runs all 4 plan steps, then prints "gh@2.89.0 is already installed"]
[koto: re-runs all 3 plan steps, then prints "koto@0.5.0 is already installed"]

Installed: 2 tools (gh, tsukumogami/koto)
```

**Wall clock**: ~1.3 seconds (uses cached downloads)

**What I expected**: A quick check that says "all tools already installed" without re-executing plan steps.

**Friction**: The idempotent run re-executes the entire plan (download from cache, extract, chmod, install_binaries) before detecting the tool is already installed. While fast due to caching, it's wasteful and produces confusing output. In CI, you'd see 50+ lines of "Restored from cache / Extracting / Making executable" output only to learn everything was already fine.

**Friction score**: 2 -- The output is noisy and wasteful. Should detect "already installed at requested version" before generating/executing a plan.

**Issue-worthy?** Yes -- `tsuku install` should skip plan execution for already-installed tools. A quick version check against `state.json` before running the plan would make CI runs clean and fast.

---

### Step 7: Test `tsuku search`

**Command**: `tsuku search koto`

**Output**:
```
No recipes found for 'koto'.

Tip: You can still try installing it!
   Run: tsuku install koto
   (Tsuku will attempt to find and install it using AI)
```

**What I expected**: Since `tsukumogami/koto` is a distributed source recipe, search should find it.

**Friction**: `tsuku search` only searches built-in recipes, not distributed sources. This means `tsuku search koto` returns nothing even though `tsuku install "tsukumogami/koto"` works. The "attempt to find and install it using AI" suggestion is misleading -- running `tsuku install koto` without the org prefix gives: `Error: Multiple sources found for "koto". Use --from to specify`.

**Friction score**: 2 -- Search doesn't cover distributed sources. The AI install suggestion leads to a confusing multi-source error.

**Issue-worthy?** Yes -- `tsuku search` should include distributed source recipes, or at least indicate that distributed sources exist. The fallback AI suggestion should be suppressed when the tool exists in a registered distributed source.

---

**Command**: `tsuku search gh`

**Output**: Returns 60+ results with fuzzy matching. `gh` is correctly listed with "GitHub command-line tool" and shows `2.89.0` as installed.

**Friction score**: 1 -- The fuzzy matching returns way too many results. Searching for "gh" returns tools whose descriptions contain "high", "lightweight", etc. An exact-match section at the top would help.

**Issue-worthy?** Minor -- fuzzy search is noisy but functional.

---

**Command**: `tsuku search jq`

**Output**: Returns 7 results including `jq` with correct description. Clean and useful.

**Friction score**: 0 -- Smooth.

---

### Step 8a: Test `jq = "latest"` in config

**Command**: Added `jq = "latest"` to config, ran `tsuku install -y`

**Output** (key parts):
```
Warning: jq is unpinned (no version or "latest"). Pin versions for reproducibility.

[Installs patchelf@0.18.0 as dependency]
[Installs oniguruma@6.9.10 as runtime dependency]
[Installs jq@1.8.1]

Verifying jq (version 1.8.1)...
  Running: jq --version
  Output: /home/testuser/.tsuku/tools/jq-1.8.1/bin/jq: error while loading shared libraries: libjq.so.1: cannot open shared object file: No such file or directory

Failed: jq: installation verification failed
```

**What I expected**: jq should install and work on Linux.

**Friction**: jq installation fails verification due to a shared library issue. The `libjq.so.1` shared library isn't found at runtime even though it was extracted during installation. This is a Homebrew bottle relocation issue -- patchelf was installed to fix RPATHs, but the relocation didn't properly set up the library path for libjq.so.1.

On a second install attempt (from the `--dry-run` test), patchelf was NOT found during the relocate step:
```
Warning: patchelf not found, skipping RPATH fix for jq
Warning: patchelf not found, skipping RPATH fix for libjq.so.1.0.4
```

This suggests patchelf gets installed the first time but isn't consistently found in PATH for subsequent operations.

**Friction score**: 3 -- **Blocker for jq on Linux**. The jq recipe's Homebrew bottle relocation is broken.

**Issue-worthy?** Yes -- jq recipe fails on Linux due to broken shared library relocation. The patchelf dependency is installed but not consistently available during the relocate step.

---

### Step 8b: Test `--dry-run`

**Command**: `tsuku install --dry-run` (with jq, gh, koto in config)

**Output**: Executes the full installation plan including downloading, extracting, and installing tools. Installs patchelf, oniguruma, and attempts jq. This is NOT a dry run -- it performs real installations.

**What I expected**: A dry run should show what would be installed without actually doing anything. Something like:
```
Would install: gh@2.89.0, koto@0.5.0, jq@1.8.1
```

**Friction score**: 3 -- **`--dry-run` actually installs things**. This is a correctness bug. The flag either isn't implemented or isn't being respected.

**Issue-worthy?** Yes -- `--dry-run` flag performs real installations instead of showing a preview.

---

### Step 8c: Test nonexistent tool

**Command**: Added `nonexistent-tool-xyz = "1.0"` to config, ran `tsuku install -y`

**Output**:
```
Error: recipe "nonexistent-tool-xyz" not found in tsukumogami/koto

To create a recipe from a package ecosystem:
  tsuku create nonexistent-tool-xyz --from <ecosystem>

Available ecosystems: crates.io, rubygems, pypi, npm
```

**Friction**: The error message is clear and actionable. It correctly suggests creating a recipe. However, the "not found in tsukumogami/koto" phrasing is confusing -- it searched a distributed source named "tsukumogami/koto" which happens to share a name with the koto tool. This could confuse users into thinking it's looking for the tool inside koto itself.

**Friction score**: 1 -- Error message is mostly good but the source name overlap is slightly confusing.

**Issue-worthy?** No -- minor phrasing issue.

---

### Step 9: Additional observations

**`tsuku list`** output:
```
Installed tools (2 total):
  gh                    2.89.0 (active)
  jq                    1.8.1 (active)
```

Note: jq shows as "active" despite failing verification. koto doesn't appear in the list (installed via distributed source). This is misleading.

**`tsuku doctor`** output:
```
tools/current in PATH ... FAIL
  /home/testuser/.tsuku/tools/current is not in your PATH
  Run: eval $(tsuku shellenv)
```

This is expected in the Docker environment. The suggestion is clear.

**`tsuku init --help`**: Clean, includes examples. Good.

---

### Version resolution deep-dive

Tested additional version specifier variants:

| Config | Result |
|--------|--------|
| `"tsukumogami/koto" = "0.5.0"` | Works -- installs koto 0.5.0 |
| `"tsukumogami/koto" = "0.5"` | Fails -- "version 0.5 not found" |
| `"tsukumogami/koto" = "latest"` | Works -- resolves to 0.5.0 |
| `koto = "0.5"` | Fails -- "version 0.5 not found for tsukumogami/koto" |
| `koto = "0.5.0"` | Not tested (no built-in recipe, needs org prefix) |
| `gh = "2"` | Works -- resolves to 2.89.0 |
| `jq = "latest"` | Resolves to 1.8.1 but fails verification |
| `jq = "1.7"` | Fails -- "version 1.7 not found for Homebrew formula jq" |

Key insight: Partial semver (`"0.5"`, `"1.7"`) fails for both distributed sources AND Homebrew-sourced recipes. Only built-in recipes with GitHub version providers seem to support it (e.g., `gh = "2"`). This is an inconsistency in version resolution across recipe sources.

## Summary Table

| Step | Friction | Issue-worthy? | Notes |
|------|----------|---------------|-------|
| 1. Bootstrap install | 1 | No | Shell warning in Docker is expected |
| 2. `tsuku init` | 0 | No | Clean output, docs link |
| 3. Write config | 0 | No | Manual edit |
| 4. Install with `"0.5"` | 3 | Yes | Partial semver fails for distributed sources |
| 4b. Install with `"0.5.0"` | 0 | No | Full semver works |
| 5. Verify tools | 1 | No | PATH instructions could be clearer |
| 6. Idempotency | 2 | Yes | Re-executes full plan before detecting "already installed" |
| 7. Search for koto | 2 | Yes | Distributed source recipes invisible to search |
| 7b. Search for gh | 1 | No | Fuzzy matching too broad but functional |
| 8a. jq = "latest" | 3 | Yes | Shared library relocation broken on Linux |
| 8b. `--dry-run` | 3 | Yes | Actually installs things |
| 8c. Nonexistent tool | 1 | No | Error message is clear |

## Issues to File

### 1. Partial semver version resolution fails for distributed source recipes

**Severity**: High (blocks intended `.tsuku.toml` config)

`"tsukumogami/koto" = "0.5"` fails with "version 0.5 not found" while `gh = "2"` correctly resolves major-only version `2` to `2.89.0`. The same failure occurs for Homebrew-sourced recipes (`jq = "1.7"` fails). Version resolution should support partial semver (`MAJOR` or `MAJOR.MINOR`) consistently across all recipe sources.

**Workaround**: Use full semver (`"0.5.0"`) for distributed source recipes.

### 2. `--dry-run` flag executes real installations

**Severity**: High (correctness bug)

`tsuku install --dry-run` downloads, extracts, and installs tools identically to a normal install. The flag has no effect. Expected behavior: show what would be installed without performing any actions.

### 3. Idempotent install re-executes full plan unnecessarily

**Severity**: Medium (performance/UX)

When all tools in `.tsuku.toml` are already installed at the requested version, `tsuku install -y` re-executes the entire installation plan (download from cache, extract, chmod, install_binaries) before printing "already installed". Should check installed state before plan execution to produce clean, fast output in CI.

### 4. `tsuku search` doesn't find distributed source recipes

**Severity**: Medium (discoverability)

`tsuku search koto` returns "No recipes found" even when the `tsukumogami/koto` distributed source is registered. Search should include distributed source recipes or at least mention them. The fallback "try installing with AI" suggestion leads to a confusing "Multiple sources found" error.

### 5. jq recipe: shared library relocation broken on Linux

**Severity**: High (broken tool)

jq installs but fails verification with `error while loading shared libraries: libjq.so.1`. The Homebrew bottle relocation doesn't properly set RPATH for the jq binary. patchelf is installed as a dependency but isn't consistently found during the relocate step (intermittent "patchelf not found, skipping RPATH fix" warnings).

### 6. `tsuku list` doesn't show distributed source tools

**Severity**: Low (cosmetic)

koto installed via `"tsukumogami/koto"` doesn't appear in `tsuku list` output. Only `gh` and `jq` are shown. Tools installed from distributed sources should appear in the list.

**Update**: On closer inspection, this may be due to the fact that koto was installed in a different Docker run. In the run where both gh and koto were installed together, `tsuku list` was not tested. This needs re-verification.

## Blockers Found

### For shirabe's intended config (`"tsukumogami/koto" = "0.5"`)

**Blocker**: Partial semver `"0.5"` doesn't work. Must use `"0.5.0"` instead.

**Workaround**: Change the intended config to:
```toml
[tools]
"tsukumogami/koto" = "0.5.0"
gh = "2"
```

This works. gh's major-only `"2"` resolves correctly because it uses a GitHub version provider. koto needs exact semver because its distributed source recipe doesn't support partial matching.

### For jq adoption

**Blocker**: jq is broken on Linux due to shared library relocation issues. Not usable in CI on ubuntu runners.

### For `--dry-run` in CI pipelines

**Blocker**: `--dry-run` is non-functional. Cannot use it to preview what would be installed.

## Summary

tsuku 0.9.0 successfully installs org-scoped distributed source recipes and built-in recipes from `.tsuku.toml`, but only when distributed sources use exact semver versions (`"0.5.0"`, not `"0.5"`). The intended shirabe config works with a minor version string change from `"0.5"` to `"0.5.0"`. Three significant bugs were found: `--dry-run` actually installs things, jq's shared library relocation is broken on Linux, and partial semver resolution is inconsistent across recipe sources.

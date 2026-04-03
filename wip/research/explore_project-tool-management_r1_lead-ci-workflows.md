# Research: How Should CI Workflows Change to Use `.tsuku.toml`?

**Lead Question:** How should CI workflows change to use `.tsuku.toml` instead of manual tool installs? `validate-templates.yml` currently does its own `tsuku install tsukumogami/koto`. Release workflows use `gh` and `jq`. What's the intended CI pattern -- `tsuku install` with no args?

**Status:** Round 1, Complete

---

## Findings

### 1. Current Shirabe CI Tool Installation Patterns

Shirabe's CI workflows explicitly install tools on a per-step basis:

**`validate-templates.yml`** (lines 14-23):
- Installs tsuku binary via curl from `https://get.tsuku.dev/now`
- Explicitly runs `tsuku install tsukumogami/koto -y` (non-interactive, single tool)
- Uses the `-y` flag to skip confirmation in non-interactive CI environment

**`release.yml`** (lines 82-100):
- Does not install additional tools; uses `gh` and `jq` directly
- Assumes these commands are pre-installed on `ubuntu-latest` runner
- Calls `gh api` with jq filtering (lines 119-121, 125-127, etc.)

**`check-templates.yml`** (lines 10-13):
- Delegates to tsukumogami/koto's reusable workflow
- Does not install koto itself; koto workflow handles this

### 2. Design Intent from `.tsuku.toml` Specification

**DESIGN-project-configuration.md** defines the feature explicitly:

**`tsuku install` (no arguments) behavior** (lines 224-226):
> "Config found with tools: iterates tools, calling `runInstallWithTelemetry` for each, collecting errors instead of exiting on first failure"

**Flag compatibility** (lines 227-230):
- `--yes`/`-y`: supported in no-arg mode, skips interactive confirmation
- `--dry-run`, `--force`, `--fresh`: supported
- `--plan`, `--recipe`, `--from`, `--sandbox`: incompatible with no-arg mode

**Exit codes for no-arg install** (lines 221-225):
- Exit 0 if all succeeded
- Exit 15 (`ExitPartialFailure`) if some failed
- Exit 6 (`ExitInstallFailed`) if all failed
- Exit 2 (`ExitUsage`) if no config found

**Interactive vs. CI** (lines 224, 398-400):
- "If interactive (TTY) and no --yes flag: prompt for confirmation"
- For CI: use `--yes`/`-y` flag to skip TTY check

### 3. The Intended CI Pattern: `tsuku install` with No Arguments

The design docs make this explicit:

**From DESIGN-project-configuration.md, "CLI Integration" section (lines 200-230):**
> `tsuku install` (no arguments) reads the project config and installs all declared tools

**Minimal `.tsuku.toml` content** (lines 18-19):
```toml
[tools]
node = "20.16.0"
go = "1.22"
koto = "latest"
jq = ""
```

**CI invocation pattern** (line 223):
```bash
tsuku install -y
```

The `-y` flag is essential in CI because:
1. Skips the TTY/confirmation prompt that would block non-interactive shells
2. Still respects the tools declared in `.tsuku.toml` (batch install)
3. Works whether 0, 1, or N tools are declared

### 4. From Shirabe's Perspective: No Existing `.tsuku.toml`

Shirabe currently has no `.tsuku.toml` file. The repository would need:
1. Create `.tsuku.toml` at repository root
2. Declare koto version(s) needed
3. Declare any other tools used in CI (e.g., `gh`, `jq`)
4. Update workflows to call `tsuku install -y` instead of explicit tool installs

Example `.tsuku.toml` for shirabe:
```toml
[tools]
koto = "latest"
```

### 5. Non-Interactive CI Context: Permission Check Caveat

**Security consideration from DESIGN-auto-install.md, lines 481-486:**
> "$TSUKU_HOME/config.toml must be mode 0600 and owned by the current user before its auto_install_mode value is honoured"

This applies primarily to `auto_install_mode` in tsuku's user config, **not** to `.tsuku.toml` (the project config). The permission check is about preventing untrusted `.envrc` files from bypassing confirmation via environment variables.

**For CI with `tsuku install -y`:**
- No `.tsuku.toml` permission check is enforced
- The `-y` flag is the explicit override mechanism
- No auto-mode escalation concern (batch install is deterministic)

### 6. Release Workflows and Tool Dependencies

**`release.yml` uses:**
- `gh api` to query and manipulate releases (lines 95, 119, 125, 190)
- `jq` to filter release JSON (lines 119, 125, etc.)

These tools are already on `ubuntu-latest`. The design allows two approaches:

1. **Explicit approach** (current): Rely on runner-provided `gh` and `jq`
2. **Declarative approach** (using `.tsuku.toml`):
   ```toml
   [tools]
   gh = "latest"
   jq = "latest"
   ```
   Then: `tsuku install -y` before the release job runs

The release workflow could use `.tsuku.toml` for reproducibility, but is not required (the tools are stable, widely available).

### 7. Shell Integration and CI Compatibility

**From DESIGN-shell-integration-building-blocks.md, Block 6:**
- Project config is optional; all features work via explicit CLI
- `tsuku run` and `tsuku exec` support project-aware version resolution
- Shell hooks (command-not-found) are optional integration; CI doesn't use them

**Implication for CI:**
- CI should use `tsuku install -y` (batch from `.tsuku.toml`), not `tsuku run`
- Shell activation (Block 5) is not needed in CI
- Project-aware exec wrapper (Block 6, `tsuku exec`) is designed for interactive shells and scripts with shims

### 8. Comparison to Other Repos in Workspace

**Koto** (`koto/.github/workflows/validate.yml`, line 135):
```yaml
run: tsuku install tsukumogami/koto -y
```
Uses explicit tool name + `-y`, not batch install from config.

**Tsuku** (multiple workflows):
- Explicit installs with `--force` flag: `./tsuku install --force <tool>`
- No `.tsuku.toml` used in tsuku's own CI (tsuku is being built, not installed as a dependency)
- Uses `--sandbox` and `--plan` for testing scenarios

**Pattern observation:**
- Repos that need tsuku tools use explicit `tsuku install <tool> -y`
- Batch install from `.tsuku.toml` is designed but not yet adopted in the workspace
- The feature is recent (current design status)

### 9. Practical CI Concerns Not Explicitly Addressed in Design

**Binary index availability:**
- The design assumes `tsuku install` can look up tools from registry
- CI typically has network access; registry lookup should work
- Alternative: use explicit tool names if binary index is unavailable

**Error handling in batch install:**
- Exit code 15 (`ExitPartialFailure`) allows scripts to distinguish partial success
- CI scripts should test for this: `if [ $? -eq 15 ]; then warn "partial failure"; fi`
- Or fail-on-any-error: `set -e` in bash

**Tool versioning in CI:**
- Pinning versions in `.tsuku.toml` ensures reproducibility across CI runs
- Using `"latest"` is discouraged in design docs (line 398 warning)
- CI best practice: pin all tool versions explicitly

---

## Implications

### For Shirabe Adoption

1. **Minimal friction transition:** Replace explicit `tsuku install tsukumogami/koto -y` with:
   - Create `.tsuku.toml` with `[tools]\nkoto = "<pinned-version>"`
   - Change workflow to: `tsuku install -y`
   - This is a backwards-compatible change (works with or without config file)

2. **Exit code handling:** Update CI scripts to handle exit code 15 if partial failure is acceptable, or use `set -e` to fail on any error.

3. **Release workflow:** Optionally declare `gh` and `jq` in `.tsuku.toml` for reproducibility, but not required.

### For CI Pattern Standardization

The design intends:
- **Interactive shells:** `tsuku run <command>` (Block 3)
- **CI/scripts:** `tsuku install -y` (project config) or explicit names (existing pattern)
- **Shell activation:** `tsuku shell` or hooks (Block 5, interactive only)

Shirabe's CI should use batch install (`tsuku install -y`) if adopting `.tsuku.toml`.

### For Error Handling

Exit code 15 (`ExitPartialFailure`) is a new convention. CI scripts must be aware:
- Exit 0 = all tools installed successfully
- Exit 15 = some tools installed, some failed
- Exit 6 = all tools failed
- Exit 2 = no config file found

Existing CI scripts using `set -e` or `$? != 0` will treat 15 as failure (safe default).

---

## Surprises

1. **No `.tsuku.toml` permission checks:** The security validation in DESIGN-auto-install.md applies to `auto_install_mode` in user config, not project config. CI doesn't face the permission check concern.

2. **Exit code 15 is new:** `ExitPartialFailure` doesn't exist in current tsuku; it's part of the design but not yet implemented. CI scripts should be prepared for this when adopting batch install.

3. **Project config is optional in CI:** The design allows `tsuku install <tool> -y` (explicit) and `tsuku install -y` (batch from config) to coexist. Repos don't need to adopt `.tsuku.toml` immediately.

4. **Shims are not for CI:** The shim system (`tsuku shim install`) is designed for interactive shells and Makefiles, not for GitHub Actions. CI should use explicit `tsuku install` commands or batch install.

5. **Release workflows don't need project config:** `gh` and `jq` are already on `ubuntu-latest`. Using `.tsuku.toml` for these is optional, not required.

---

## Open Questions

1. **When will `.tsuku.toml` batch install be available?** The design is "Current" status, but implementation timeline is unclear. Early adoption relies on this feature existing.

2. **Is the binary index required for batch install?** The design mentions offline lookup from SQLite or JSON index. Does `tsuku install -y` (no explicit tool names) fail gracefully if the index isn't built?

3. **How should partial failures be handled in CI?** Exit code 15 allows scripts to detect partial success. What's the recommended CI pattern: fail on any error, or accept partial and log warnings?

4. **For repos with multiple projects:** Does monorepo support work as intended? The design allows parent-directory traversal with first-match (no merge). Should each subproject have its own `.tsuku.toml`?

5. **GitHub Actions setup-tsuku action:** Is there a reusable action for CI setup, or should each repo install tsuku manually? The design doesn't mention a canonical action.

---

## Summary

Shirabe CI should adopt `.tsuku.toml` with `[tools] koto = "<version>"`, then use `tsuku install -y` to batch-install declared tools. This is the intended pattern from the design. CI exit codes (0 = success, 6 = all failed, 15 = partial failure) should be handled explicitly. The batch install feature is new and requires explicit `-y` flag in non-interactive contexts. Release workflows can optionally declare `gh` and `jq` but are not required to do so. This pattern is backwards-compatible and provides reproducibility without breaking existing explicit-install workflows.


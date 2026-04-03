# Lead: What does the end-to-end `.tsuku.toml` setup experience look like?

## Findings

### 1. The Complete User Journey

The setup flow consists of three discrete, sequential steps:

1. **`tsuku init`** (initialization)
   - User runs `tsuku init` in project directory
   - Non-interactive: creates `.tsuku.toml` with empty `[tools]` section and comment header
   - Exits with error if file already exists (unless `--force` flag used)
   - Output: "Created .tsuku.toml"
   - Source: `/home/dgazineu/dev/niwaw/tsuku/tsukumogami-3/public/tsuku/cmd/tsuku/init.go`

2. **Declaring tools** (manual TOML editing)
   - User opens `.tsuku.toml` and manually adds tool declarations under `[tools]`
   - Three supported formats:
     - Exact version: `go = "1.22.5"`
     - Prefix (resolves to latest matching): `go = "1.22"`
     - Latest or empty: `jq = "latest"` or `jq = ""`
     - Extensible table form: `python = { version = "3.12" }`
   - **No interactive tool selection or auto-detection** -- entirely manual
   - Documentation provides example:
     ```toml
     [tools]
     go = "1.22"
     node = "20.16.0"
     ripgrep = "14.1.0"
     jq = "latest"
     ```
   - Source: `/home/dgazineu/dev/niwaw/tsuku/tsukumogami-3/public/tsuku/docs/guides/shell-integration.md` (lines 33-51)

3. **`tsuku install`** (batch installation)
   - User runs `tsuku install` with no arguments
   - Locates nearest `.tsuku.toml` via parent directory traversal (walks up until finding file, stopping at `$HOME`)
   - **Interactive confirmation mode** (unless TTY is absent or `--yes` flag used):
     ```
     Using: /path/to/.tsuku.toml
     Tools: go@1.22, jq, node@20.16.0, ripgrep@14.1.0
     Warning: jq is unpinned (no version or "latest"). Pin versions for reproducibility.
     Proceed? [Y/n]
     ```
   - Prints warning if any tools use "latest" or empty version (unpinned versions)
   - Installs each tool in sorted alphabetical order
   - Collects errors instead of failing on first failure
   - Prints summary:
     ```
     Installed: 3 tools (go, node, ripgrep)
     Failed: 1 tool
       python: version 3.12 not found for linux/amd64
     ```
   - Source: `/home/dgazineu/dev/niwaw/tsuku/tsukumogami-3/public/tsuku/cmd/tsuku/install_project.go` (lines 26-145)

### 2. Discovery and Traversal Behavior

**Parent directory traversal strategy** (from design doc, lines 96-107):
- Walk up from current working directory checking each directory for `.tsuku.toml`
- Stop at first match (first-match, no merging across directories)
- Stop at `$HOME` unconditionally
- Additional stop points via `TSUKU_CEILING_PATHS` environment variable (colon-separated, can only add ceilings, not remove)
- Symlinks resolved via `filepath.EvalSymlinks` to prevent symlink-based misdirection

**Implementation**: `LoadProjectConfig(startDir string)` function in `/home/dgazineu/dev/niwaw/tsuku/tsukumogami-3/public/tsuku/internal/project/config.go` (lines 79-113)

**Monorepo implications**: A `.tsuku.toml` at repo root applies to all subdirectories automatically. Subdirectories can declare their own config to override (no inheritance or merging).

### 3. Version String Handling and Resolution

**Version constraint syntax** (from design doc, lines 138-160):
- Exact: `"20.16.0"` → passes string directly to provider
- Prefix: `"1.22"` → provider resolves to latest matching (e.g., 1.22.5)
- Latest: `"latest"` or `""` (empty string) → triggers `ResolveLatest` to fetch newest stable
- **No semver ranges** (">= 1.0, < 2.0") in v1 -- not implemented by providers

**Version string behavior in install**: Empty string `""` converted to "latest" before resolution (lines 113-115 of install_project.go)

### 4. Error Handling and Exit Codes

**New exit codes added for batch install** (from exitcodes.go, lines 58-60):
- `ExitSuccess (0)` -- all tools installed successfully
- `ExitPartialFailure (15)` -- some tools failed, others succeeded
- `ExitInstallFailed (6)` -- all tools failed

**Error collection strategy**: Unlike single-tool installs which fail-fast, project install aggregates errors and reports them all at end. Enables CI to see what succeeded vs. what failed.

**Flags compatible with no-args install** (from install_project.go, lines 28-34):
- `--dry-run` -- preview without installing
- `--force` -- force reinstall even if current
- `--fresh` -- clean install
- `--yes` / `-y` -- skip interactive confirmation
- `--plan`, `--recipe`, `--from`, `--sandbox` -- **incompatible** (errors if used in no-args mode)

### 5. Interactive Confirmation Behavior

**When confirmation prompt appears** (lines 96-104 of install_project.go):
- Only if NOT running with `--yes` flag AND
- Terminal is interactive (TTY is attached)
- If user declines: exit code `ExitUserDeclined (13)`
- Default answer is yes (hitting enter without typing proceeds)

**Warning about unpinned versions** (lines 84-93 of install_project.go):
- Detected when tool version is empty string or "latest"
- Warning printed before confirmation prompt
- Not a blocking error -- install proceeds if user confirms
- Encourages explicit version pinning for reproducibility

### 6. Configuration File Format and Parsing

**File structure** (from config.go, lines 28-62):
```go
type ProjectConfig struct {
    Tools map[string]ToolRequirement `toml:"tools"`
}

type ToolRequirement struct {
    Version string `toml:"version"`
}
```

**Custom unmarshaling** handles dual format (string or inline table):
- String: `node = "20.16.0"` → `ToolRequirement{Version: "20.16.0"}`
- Table: `python = {version="3.12"}` → `ToolRequirement{Version: "3.12"}`
- Implementation: `UnmarshalTOML` method (~20 lines) uses BurntSushi/toml unmarshaler interface

**Validation constraints**:
- `MaxTools = 256` -- upper bound to prevent resource exhaustion
- Invalid TOML syntax causes hard parse failure before any installs attempted
- Missing config returns nil, not error (error only if file exists but can't be parsed)

### 7. Documentation and User Guidance

**Init command help** (from init.go, lines 24-31):
```
Short: "Initialize a project configuration file"
Long: "Create a .tsuku.toml file in the current directory.
This file declares which tools and versions a project requires,
enabling reproducible development environments across machines.
Use --force to overwrite an existing configuration file."
```

**User guide** provides concrete walkthrough (lines 13-98 of shell-integration.md):
- Shows creation step-by-step
- Explains version string semantics
- Shows interactive install output
- Explains exit codes
- Documents `--dry-run`, `--yes`, and confirmation behavior

**Install command help** (from install.go, lines 39-80):
- Updated to document project install mode ("With no arguments...")
- Shows examples of both tool-specific and project install usage
- Documents exit codes for project install specifically
- Template comment in `.tsuku.toml` includes link: "https://tsuku.dev/docs/project-config"

### 8. Friction Points and Gaps Identified

**UX Friction:**

1. **No tool discoverability or search in init command**
   - `tsuku init` creates empty config, user must manually add tools by name
   - No list of available recipes, no search, no interactive tool selector
   - User must know tool names (e.g., "ripgrep" not "rg", "nodejs" context unclear)
   - Contrasts with mise's detection and interactive init

2. **No help text for `tsuku init --help`**
   - Command has no --help invocation documented or tested in visible code
   - Users may not know `--force` flag exists

3. **Version string semantics unclear without docs**
   - "1.22" vs "1.22.0" behavior depends entirely on provider
   - No way to query what versions are actually available for a recipe
   - User can't validate version exists until install runs

4. **No monorepo inheritance**
   - Subdirectories cannot extend parent config
   - Design explicitly defers `extends` keyword
   - Subdirectories must duplicate parent's declarations or rely entirely on parent

5. **Manual migration from asdf/mise**
   - Design explicitly defers `.tool-versions` support
   - Teams migrating from asdf must manually create `.tsuku.toml`
   - No mapping table for asdf plugin names → tsuku recipe names

6. **Unpinned version warning is post-hoc**
   - Warning printed during `tsuku install`, not during editing
   - User can't see warning when editing `.tsuku.toml` file
   - Encourages reproducibility but doesn't enforce it

7. **No recipe-level metadata in config**
   - Can't declare registry source overrides per-tool
   - Can't declare per-tool post-install hooks
   - Design mentions this is an extension path but not currently supported

### 9. Security Design

**Consent model** (from design doc, lines 461-494):
- `.tsuku.toml` requires explicit invocation (`tsuku install`)
- No auto-install on directory entry or clone
- Interactive confirmation prompt by default (can skip with `--yes` in CI)
- Full tool list printed before confirmation
- Config files with >256 tools rejected at parse time
- All installs go through existing verification pipeline (checksums, curated registry)

**Parent traversal trust boundary**:
- $HOME is unconditional ceiling (can't traverse into shared parent directories above $HOME)
- TSUKU_CEILING_PATHS can only add restrictions
- When config found in parent directory, full path printed so user knows which file applies

## Implications

1. **For Shirabe adoption**: The flow is straightforward for CI (create file, `tsuku install --yes`) and local development (one-time `tsuku init`, then periodic installs). Shirabe would:
   - Run `tsuku init` once, commit `.tsuku.toml`
   - List current tools: koto (>=0.2.1), gh, jq, python3, claude
   - Add to config file manually with known versions
   - Run `tsuku install` in CI setup step
   - No need for version pinning in CI if using `--fresh` with known versions

2. **Documentation burden**: Shirabe needs to decide version strings for each tool:
   - Koto: `>= 0.2.1` is a requirement, not a version string. Must resolve to specific version or use prefix matching
   - Python3, jq, gh, claude: Need to decide on exact versions or prefix matching

3. **UX decisions already made**: Tsuku has committed to non-interactive init, first-match traversal, and lenient batch install. These are fixed by design (no config options to tune them). Shirabe can't change the experience.

## Surprises

1. **`tsuku init` is truly minimal** -- creates empty file and exits. No prompts, no tool detection, no installation. Unlike tools like volta or mise that offer interactive setup.

2. **Version strings are opaque to the schema** -- "1.22" could resolve differently for different tools depending on provider implementation. No validation that version exists until install time.

3. **Confirmation prompt is before dependency resolution** -- User sees the declared version (e.g., "go@1.22") but doesn't know the resolved version (e.g., "go@1.22.5") until after confirming and install runs.

4. **No "already current" distinction in summary** -- Install summary says "Installed: 3 tools" even if all 3 were already at the declared version. Only errors get separate line.

5. **Design doc is extremely thorough on security and trade-offs** -- Trade-offs section (lines 262-266) explicitly lists accepted costs (monorepo duplication, manual migration, no semver ranges). This is intentional design, not gaps.

## Open Questions

1. **How does version resolution actually work for each tool?**
   - Koto: does `>= 0.2.1` work as version string, or must it be pinned to exact version?
   - Python3: what does "3" vs "3.12" resolve to?
   - Are there recipes for all five tools Shirabe needs?

2. **What's the exact recipe name for each tool?**
   - Design uses "go", "node", "ripgrep", "jq" as examples
   - Are they kebab-case? What about "python3" vs "python"? "github-cli" vs "gh"?
   - Answers require tsuku recipe registry inspection or `tsuku list` command (if it exists)

3. **Can version pinning be optional in CI?**
   - If `--fresh` flag always installs latest, can `.tsuku.toml` use `""` (latest)?
   - Design says warning is printed but install proceeds, implying latest is allowed
   - Shirabe could declare `python = ""` in config for CI if this is viable

4. **What does "already current" status look like in install output?**
   - Design mentions "already-current counter" in data flow (line 404) but implementation summary doesn't separate it from "installed"
   - Code comment in install_project.go (lines 121-124) says "we can't distinguish here without deeper state inspection"
   - Does this mean the summary is ambiguous?

5. **How does the `--plan` flag work with project install?**
   - install.go line 84 has condition `installPlanPath == ""` to detect no-args mode
   - Can `tsuku install --plan` work without tool args?
   - Is there a `tsuku eval` command that generates plans? (Mentioned in install.go help text line 70)

6. **Does `--dry-run` actually skip confirmation prompt?**
   - Code shows confirmation prompt happens before install loop (lines 96-104)
   - Flag is marked compatible with no-args mode (design doc line 229)
   - But does "dry-run" skip the prompt, or do you still have to confirm to preview?

## Summary

The end-to-end `.tsuku.toml` setup is a three-step manual flow: `tsuku init` (creates empty file), edit TOML (user adds tools by name and version), then `tsuku install` (batch-installs with interactive confirmation). Version string semantics are opaque to the schema (resolved at install time by the tool's provider), and there's no built-in tool discovery or validation until install runs, creating friction for users unfamiliar with recipe names and version string behavior. The design is intentionally minimal and secure, deferring extensibility (monorepo inheritance, `.tool-versions` compat, per-tool options) to future work, but this means Shirabe must manually determine exact versions and recipe names for all five tools before committing `.tsuku.toml` to version control.


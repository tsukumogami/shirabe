# Lead: What does the end-to-end setup experience look like on 0.9.0?

## Findings

### Step 1: `tsuku init`

The `init` command (`cmd/tsuku/init.go`) is minimal. It writes a static template
to `.tsuku.toml` in the current directory:

```toml
# Project tools managed by tsuku.
# See: https://tsuku.dev/docs/project-config
[tools]
```

There is no interactive tool selection, no scanning of existing tooling, and no
wizard. The `--force` flag allows overwriting an existing file. That's the only
option.

**Friction**: After running `tsuku init`, the user is staring at an empty
`[tools]` section with no guidance on what to put there beyond the URL comment.
There's no `tsuku add` command to help populate it.

### Step 2: Declaring tools in `.tsuku.toml`

The schema is defined in `internal/project/config.go`. The `ProjectConfig`
struct has a single section:

```go
type ProjectConfig struct {
    Tools map[string]ToolRequirement `toml:"tools"`
}

type ToolRequirement struct {
    Version string `toml:"version"`
}
```

Two TOML syntaxes are supported via custom `UnmarshalTOML`:

1. **String shorthand**: `node = "20.16.0"`
2. **Inline table**: `python = { version = "3.12" }`

Special version values:
- Empty string (`""`) or omitted: resolves to latest
- `"latest"`: explicitly resolves to latest
- Any other string: treated as a version constraint

Org-scoped tools are also supported (`internal/project/orgkey.go`):
- `tsukumogami/koto` -- bare repo name becomes recipe name
- `tsukumogami/registry:tool` -- explicit recipe name after colon

**Friction**: The user must know the exact recipe name. There's no
`tsuku add <tool>` that would look up the recipe and append to `.tsuku.toml`.
Users have to manually edit the TOML file. For version pinning, users need to
know the available version string (no `tsuku versions <tool>` integration into
the add flow). The inline table form exists for future extensibility but
currently only supports `version`.

**Max tools**: 256 per file (`MaxTools` constant).

### Step 3: `tsuku install` (no args -- project install)

The project install path (`cmd/tsuku/install_project.go`, `runProjectInstall`)
does the following:

1. Calls `project.LoadProjectConfig(cwd)` which walks up directories to find
   `.tsuku.toml`, stopping at `$HOME` or `TSUKU_CEILING_PATHS`
2. Displays the config path and tool list
3. Warns about unpinned versions (empty or "latest")
4. Prompts for confirmation (`Proceed? [Y/n]`) unless `--yes` or non-TTY
5. Installs each tool sequentially, collecting results
6. Prints summary (installed count, failed count with errors)
7. Exit codes: 0 (all success), 6 (all failed), 15 (partial)

Key flags for project install:
- `--yes` / `-y`: skip confirmation (needed for CI)
- `--dry-run`: preview without installing
- `--fresh`: bypass cached plans
- `--force`: skip security warnings

**Friction**: Installation is sequential, not parallel. For a project with 5+
tools, this could be slow. There's no progress indicator beyond per-tool output.

### Step 4: No `tsuku add` command

Confirmed by scanning `main.go` -- there is no `addCmd` registered. The full
command list includes `activate`, `cache`, `install`, `list`, `update`,
`remove`, `recipes`, `versions`, `search`, `info`, `outdated`, `plan`, `verify`,
`config`, `create`, `completion`, `validate`, `eval`, `shellenv`, `doctor`,
`llm`, `registry`, `which`, `suggest`, `hook`, `hookEnv`, `shell`, `init`,
`run`, `shim`, `selfUpdate`. No `add`.

**Friction**: This is the biggest gap. The workflow is: run `tsuku init`, then
manually open `.tsuku.toml` in an editor and type tool names. Compare with
`npm install --save <pkg>` or `cargo add <dep>`.

### Step 5: `tsuku shell` -- activating project tools in PATH

The `shell` command (`cmd/tsuku/shell.go`) computes PATH modifications based on
`.tsuku.toml`. Usage: `eval $(tsuku shell)`. The `shellenv` package
(`internal/shellenv/activate.go`) resolves tool versions from the config to
bin directories under `$TSUKU_HOME/tools/` and prepends them to PATH.

It sets `_TSUKU_DIR` and `_TSUKU_PREV_PATH` for deactivation when leaving the
project directory.

**Friction**: `tsuku shell` and `tsuku shellenv` are two different commands.
`shellenv` is for global tsuku PATH setup; `shell` is for per-project
activation. This naming could confuse users. The hook-env system handles
automatic activation on directory change, but requires shell integration setup.

### Step 6: `tsuku run` -- project-aware execution

`tsuku run <command>` checks `.tsuku.toml` for the tool. If declared, the
project-pinned version is installed and used automatically with no prompt
(project config counts as consent). This is the smoothest path -- it resolves
versions, auto-installs, and execs in one step.

### Version installed

The binary currently installed is **0.8.1** (`tsuku version 0.8.1`). The source
code in the repo represents the development head, which includes all project
config features. The version on disk is behind the source, but all the project
config commands (`init`, project install, `shell`) are present in 0.8.1's
feature set based on the code structure.

## Implications

For shirabe adoption:

1. **No `tsuku add`**: Shirabe's `.tsuku.toml` must be hand-authored. This is
   fine for a one-time setup but means any future tool additions require manual
   TOML editing.

2. **CI usage**: `tsuku install --yes` is the CI path. The `--yes` flag skips
   interactive confirmation. Exit code 15 (partial failure) needs handling if
   CI should fail on any tool failure.

3. **Version pinning matters**: Unpinned tools trigger warnings and resolve to
   latest, which hurts reproducibility. Shirabe should pin all tool versions.

4. **Sequential install**: For CI, sequential install of 4-5 tools may add
   meaningful time. No parallel install option exists.

5. **Config schema is minimal**: Only `version` is supported per tool. No
   per-tool options like `optional = true` or `ci-only = true` exist yet. All
   declared tools are installed unconditionally.

6. **Org-scoped tools work**: `tsukumogami/koto` syntax in `.tsuku.toml` is
   supported for distributed recipes, which is relevant if koto is published
   as a distributed recipe.

## Surprises

1. **No `tsuku add` command at all.** For a tool that explicitly designed the
   inline-table extensibility path ("for future per-tool options"), the absence
   of a CLI command to add tools to the config is a notable gap.

2. **`tsuku shell` vs `tsuku shellenv` naming.** Two separate commands for
   global vs project PATH management. The naming distinction is subtle and
   could trip up users.

3. **Project config is version-only.** The ToolRequirement struct has only
   `Version`. No `optional`, `platforms`, `ci-only`, or other fields. The
   inline-table form (`{ version = "3.12" }`) exists purely as an extension
   point for the future.

4. **Parent directory traversal stops at $HOME.** The ceiling behavior means
   a `.tsuku.toml` at `~/projects/.tsuku.toml` won't be found from
   `~/projects/foo/` if `~/projects/` equals `$HOME`. This is intentional
   but worth noting for monorepo setups.

## Open Questions

1. **What version of tsuku ships the project config feature?** The installed
   binary is 0.8.1. The instructions mention 0.9.0. Need to confirm whether
   0.8.1 already includes full project config support or if 0.9.0 is required.

2. **Is koto available as a tsuku recipe?** Shirabe needs koto >= 0.2.1. If
   there's no koto recipe, tsuku can't manage it.

3. **Are gh, jq, python3 available as recipes?** Need to check the recipe
   registry for shirabe's dependencies.

4. **How does `tsuku install --yes` behave when a tool is already installed at
   the pinned version?** Does it skip or reinstall? This affects CI run times.

5. **What's the actual wall-clock time for a fresh `tsuku install` of 4-5
   tools?** Sequential install could be 30-60+ seconds depending on download
   speeds.

## Summary

The end-to-end flow is `tsuku init` (creates empty `.tsuku.toml`), hand-edit
the file to add tools with versions, then `tsuku install` (batch installs with
confirmation) -- functional but with a manual editing gap where `tsuku add`
would normally live. The main implication for shirabe is that `.tsuku.toml`
authoring is a one-time manual task and CI needs `--yes` with careful exit code
handling. The biggest open question is whether shirabe's specific dependencies
(koto, gh, jq, python3) all have tsuku recipes available.

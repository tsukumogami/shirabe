# Lead: Security and permission constraints for `.tsuku.toml` in CI

## Findings

### Design Doc Security Guarantees

The DESIGN-auto-install.md and DESIGN-project-configuration.md documents specify the following security checks:

**Four security gates in autoinstall.Runner.Run():**
1. **Root guard**: `os.Geteuid() == 0` blocks installation as root (returns ErrForbidden)
2. **Config permission check**: `$TSUKU_HOME/config.toml` must be mode 0600 and owned by current user
   - If permissions incorrect, `auto_install_mode` is ignored and mode falls back to `confirm`
3. **Verification gate (auto mode)**: Recipe must have checksum_url or signature_url
   - Unverified recipes fall back to `confirm` mode
4. **Conflict gate (auto mode)**: Multiple matching recipes fall back to `confirm`

**ProjectConfig loading behavior:**
- `LoadProjectConfig()` reads `.tsuku.toml` from the nearest ancestor directory (walks up from cwd)
- Stops at `$HOME` unconditionally; `TSUKU_CEILING_PATHS` adds additional boundaries
- Symlinks are resolved before traversal (`filepath.EvalSymlinks`)
- MaxTools=256 cap prevents resource exhaustion

**Project install mode behavior:**
- `tsuku install` (no args) in a project with `.tsuku.toml` displays config path, tool list, and prompts for confirmation
- Batch install with lenient error handling (collects errors, reports summary)
- Unused `--yes`/`-y` flag provided for CI to skip confirmation

### File Permissions on GitHub Actions Runners

**Critical gap identified:** The `.tsuku.toml` file itself has NO explicit permission checks during parsing.

From config.go:
- `LoadProjectConfig()` calls `os.Stat()` to check file existence
- `parseConfigFile()` calls `os.ReadFile()` to read the file
- No validation of `.tsuku.toml` file mode or ownership

Default behavior when git checks out:
- GitHub Actions ubuntu runners use `actions/checkout@v6` 
- Checked-out files default to mode 0644 (readable by all)
- Ownership is the CI runner user (typically `runner` or `ubuntu`)
- No special permission preservation

**Example from config_test.go:**
```go
func writeConfig(t *testing.T, dir, content string) {
    t.Helper()
    path := filepath.Join(dir, ConfigFileName)
    if err := os.WriteFile(path, []byte(content), 0644); err != nil {
        t.Fatal(err)
    }
}
```
Tests write `.tsuku.toml` with 0644 (world-readable).

### Auto-Install Mode Restrictions

The design doc specifies that `.tsuku.toml` does NOT trigger auto-install:
- Auto-install (ModeAuto) is only for `tsuku run` and `tsuku exec` commands
- It requires explicit `--mode=auto` flag or `TSUKU_AUTO_INSTALL_MODE` env var
- Batch `tsuku install` (no args) always uses ModeConfirm by default
- Project config can escalate ModeConfirm→ModeAuto only when the resolver finds a project-pinned version AND config.toml passes permission check

### Project Batch Install Behavior

From install_project.go:
- No permission checks on `.tsuku.toml` itself
- Config path is printed for transparency
- Tool list is displayed and confirmation prompt shown (unless `--yes`)
- Iterates tools alphabetically, installs with lenient error handling
- Collects and reports failures at end
- Exit codes: 0 (success), 6 (all failed), 15 (partial failure)

## Implications

### For Shirabe Adoption

1. **`.tsuku.toml` is safe to check into version control** 
   - It's read-only configuration (declares versions, not executable content)
   - Parsed file content goes through the same install pipeline as CLI arguments
   - Verification gates (checksum, signature) still apply

2. **Permission assumptions mismatch CI expectations**
   - Design assumes `.tsuku.toml` lives in a trusted project repository
   - Config.toml permissions (0600 check) apply only to auto-install gates, not project config parsing
   - GitHub Actions checkout doesn't preserve or require 0600 permissions
   - The 0600 check protects against privilege escalation via `auto_install_mode`, not `.tsuku.toml` tampering

3. **CI usage is straightforward**
   - `tsuku install` (no args) works in CI after `git checkout` with default permissions
   - ModeConfirm default requires `--yes` flag for non-interactive use (which install_project.go checks)
   - Tool verification still happens (existing recipe validation pipeline)

4. **Root user is blocked**
   - Both auto-install and batch install check euid==0
   - CI runners typically don't run as root (GitHub Actions default is `runner` user)
   - If a runner did run as root, `tsuku run jq` would fail, but `tsuku install` (no args) doesn't check root

## Surprises

1. **`.tsuku.toml` has no permission validation**
   - Only config.toml gets the 0600 check
   - `.tsuku.toml` is parsed regardless of its mode (0644, 0755, etc.)
   - This is intentional (published project config), but worth documenting

2. **Root guard is inconsistent between modes**
   - autoinstall.Runner.Run() checks root
   - install_project.go runProjectInstall() does NOT check root
   - A CI runner running as root could call `tsuku install` (no args) but not `tsuku run`

3. **Interactive confirmation is mandatory in ModeConfirm**
   - install_project.go checks isInteractive() and only prompts if TTY AND not --yes
   - Non-TTY + ModeConfirm silently skips prompt (line 96: `if !installYes && isInteractive()`)
   - No ExitNotInteractive error like auto-install would throw

## Open Questions

1. **Should `.tsuku.toml` itself have mode validation?**
   - Currently NO checks
   - Design assumes it's part of the repository (trusted)
   - But if symlink-based attack is concern, should filepath.EvalSymlinks apply to `.tsuku.toml` too?

2. **Should batch install enforce root guard consistently?**
   - autoinstall does it, install_project doesn't
   - Is this intentional (batch install is more forgiving) or oversight?

3. **What if GitHub Actions runs as root in some configurations?**
   - Current code would allow `tsuku install` (no args) as root
   - Should this be restricted for consistency?

4. **Silent prompt skip in non-TTY non-interactive mode**
   - Line 96 in install_project.go: `if !installYes && isInteractive()`
   - What happens if called with ModeConfirm in a non-TTY without --yes?
   - Does it skip prompt AND skip install, or proceed without prompt?

5. **Is there a CI-specific exemption flag we should provide?**
   - Design doc mentions `--yes`/`-y` for CI
   - Should there be a `--trust` or `--ci` mode that bypasses certain checks?

## Summary

`.tsuku.toml` itself has no permission checks and is safe for version control; the 0600 permission gate applies only to `$TSUKU_HOME/config.toml` to prevent privilege escalation via `auto_install_mode`, not to `.tsuku.toml` parsing. GitHub Actions runners will check out `.tsuku.toml` with default 0644 permissions, which is fine—batch install (`tsuku install` no args) works with any permissions and only uses the permission check for auto-install mode escalation, not project config parsing. Root user is blocked from auto-install but not from batch project install, creating an inconsistency worth addressing.

# Lead: Does the tsuku-user plugin provide useful guidance for `.tsuku.toml` adoption?

## Findings

### Plugin Location and Structure

The tsuku-user plugin is installed at `/home/dgazineu/.claude/plugins/cache/tsuku/tsuku-user/` with two versions: `0.1.0` and `0.9.1-dev`. Both versions contain identical SKILL.md content. The skill is registered under multiple command aliases (9 `.md` files in `/home/dgazineu/.claude/commands/` with different hash suffixes), likely from multiple plugin sources or versions.

The skill file lives at `skills/tsuku-user/SKILL.md` and includes evals at `skills/tsuku-user/evals/evals.json`.

### What the Plugin Covers Well

**`.tsuku.toml` basics (good coverage):**
- `tsuku init` command and `--force` flag (lines 16-19 of SKILL.md)
- `[tools]` section syntax with string and table forms (lines 23-29)
- All five pin levels: latest, major, minor, exact, channel (lines 31-39)
- `tsuku install` (no args) with `-y`, `--dry-run`, `--fresh` flags (lines 43-53)
- Config file discovery: walks up from cwd, stops at `$HOME` or `TSUKU_CEILING_PATHS` (line 54)

**Version constraint semantics (good coverage):**
- Pin level table clearly maps syntax to auto-update behavior
- Auto-update section explains how pins interact with `tsuku update`
- `CI=true` suppresses auto-apply unless overridden with `TSUKU_AUTO_UPDATE=1`

**Shell integration and troubleshooting (good coverage):**
- `tsuku shellenv` for bash, zsh, fish
- `tsuku doctor` for diagnostics
- Exit code reference table
- `tsuku verify` for binary integrity

**Third-party registries (minimal but present):**
- Shows `tsuku config set registries.myorg/recipes.url` syntax (line 232)

### What the Plugin Does NOT Cover

**CI usage patterns -- completely absent:**
- No GitHub Actions workflow examples
- No guidance on caching `$TSUKU_HOME` between CI runs
- No discussion of `tsuku install -y` in CI context beyond the single `CI=true` env var mention
- No Docker/container usage patterns
- No guidance on bootstrapping tsuku itself in CI (install script, binary download)

**Org-scoped recipes -- effectively absent:**
- The registries config line is the only mention. No explanation of:
  - How org-scoped recipe names work (e.g., `myorg/tool-name`)
  - How to reference org-scoped recipes in `.tsuku.toml`
  - Authentication for private registries
  - Registry priority/resolution order when multiple registries provide the same tool

**Project onboarding workflow -- absent:**
- No "getting started" narrative for a team adopting `.tsuku.toml`
- No guidance on choosing pin levels for different tool categories
- No mention of committing `.tsuku.toml` to version control
- No discussion of lockfiles or reproducibility guarantees

**Advanced `.tsuku.toml` features -- absent or unclear:**
- No mention of `[settings]`, `[hooks]`, or other possible sections
- The table syntax `go = { version = "1.23" }` is shown but not explained (when to use it vs. the string shorthand, what other keys the table supports)
- No mention of platform-specific tool entries
- No mention of optional vs. required tools

### Eval Coverage

The evals (`evals.json`) test 8 scenarios. Only 1 of 8 directly tests `.tsuku.toml` knowledge (`project-config-pinning`). None test CI patterns, org-scoped recipes, or onboarding workflows. Two are negative tests ensuring the skill doesn't trigger for recipe authoring.

## Implications

The plugin provides a solid reference card for someone who already understands tsuku and just needs syntax reminders. It would help with the mechanical parts of `.tsuku.toml` adoption: writing the file, understanding pin syntax, running install.

However, it won't guide someone through the *adoption decision* itself. A team trying to add `.tsuku.toml` to shirabe would still need to figure out on their own:
1. How to set up CI to use it (bootstrapping tsuku, caching, the right flags)
2. Whether and how to use org-scoped recipes for internal tools
3. What pin strategy to use for different tool categories
4. How to handle the transition period when some team members don't have tsuku

This means the plugin is necessary but not sufficient for the exploration's goal. The actual `.tsuku.toml` adoption for shirabe will require consulting tsuku's own documentation or source code for CI patterns and org-scoped recipe mechanics.

## Surprises

1. **Nine duplicate command files.** The plugin appears registered 9 times under different hashes in `~/.claude/commands/`. This suggests either a plugin management issue or intentional multi-source registration.

2. **0.1.0 and 0.9.1-dev have identical SKILL.md content.** Despite a major version jump, the skill text hasn't changed. This could mean the version bump was for other plugin metadata, or the skill content was backported.

3. **No CI section at all.** Given that CI is one of the primary use cases for `.tsuku.toml` (reproducible tool versions across environments), the complete absence of CI guidance is a significant gap.

## Open Questions

1. Does tsuku's own documentation (outside the plugin) cover CI setup patterns? The plugin may intentionally stay focused on interactive CLI usage.
2. How do org-scoped recipes actually work in `.tsuku.toml`? Is the syntax `myorg/tool = "1.0"` or something else?
3. Does `.tsuku.toml` support sections beyond `[tools]`? The plugin only documents `[tools]`.
4. Is there a lockfile mechanism (like `.tsuku.lock`) for fully reproducible installs?
5. Why are there 9 duplicate command registrations for the same skill?

## Summary

The tsuku-user plugin covers `.tsuku.toml` syntax, pin levels, and basic commands well, but completely lacks CI usage patterns, org-scoped recipe guidance, and team onboarding workflows. This means adopting `.tsuku.toml` for shirabe will require investigating tsuku's own docs or source for CI integration and registry configuration -- the plugin alone won't get us there. The biggest open question is whether tsuku even has documented CI patterns, or if that's net-new territory to figure out empirically.

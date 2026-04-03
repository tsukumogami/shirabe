# Lead: Does tsuku document a recommended adoption path?

## Findings

### Documentation Coverage

**Yes, but minimal.** Tsuku documents `.tsuku.toml` adoption in:

1. **Shell Integration Guide** (`docs/guides/shell-integration.md`) -- The primary user-facing document
   - Walks through creating a `.tsuku.toml` with `tsuku init` (minimal, creates empty `[tools]` section)
   - Explains the `[tools]` schema (version strings, exact/prefix/latest resolution)
   - Shows how to run `tsuku install` (no args) to batch-install all declared tools
   - Covers shell activation, command-not-found hooks, and shims
   - Provides a Quick Reference table

2. **Design Document** (`docs/designs/current/DESIGN-project-configuration.md`) -- Technical depth
   - Extensive rationale for `.tsuku.toml` vs. alternatives
   - Covers file discovery (parent traversal, $HOME ceiling, $TSUKU_CEILING_PATHS)
   - Schema design (mixed map with string shorthand + inline tables)
   - CLI integration (tsuku init, tsuku install no-args) with exit codes
   - Defers `.tool-versions` compatibility to future

3. **Project-Aware Exec Design** (`docs/designs/current/DESIGN-project-aware-exec.md`)
   - Documents the "project config is consent" model for auto-install
   - Shows how command-not-found hooks and shims interact with `.tsuku.toml`

### What's Present

- **Complete CLI docs**: `tsuku init`, `tsuku install`, `tsuku shell`, `tsuku hook`, `tsuku shim` all documented in Shell Integration guide
- **Schema reference**: Clear examples of `[tools]` syntax (shorthand and inline table forms)
- **Integration patterns**: Hooks + activation + shims described for different contexts
- **Security model**: Project config as explicit consent is documented
- **Monorepo support**: Parent traversal algorithm explained

### What's Absent or Incomplete

1. **No "Adding tsuku to an existing project" guide** -- The Shell Integration guide shows "how to use tsuku once you've created `.tsuku.toml`" but not the decision framework or migration process for projects currently using other tools

2. **No asdf/mise migration guide** -- The design document explicitly notes:
   - "Teams migrating from asdf/mise must manually create `.tsuku.toml`"
   - "Documentation should include a 'migrating from asdf' section with common name mappings"
   - This documentation does not exist

3. **No tool discovery process** -- When adding tsuku to a project, how do you decide which tools to declare?
   - No guide for: "What are the project's current tools?"
   - No guide for: "How do I find the right tsuku recipe name?" (especially when asdf plugin names differ)

4. **No adoption checklist** -- No decision framework for "should our team adopt tsuku?"
   - When is `.tsuku.toml` worth adding vs. relying on documentation?
   - Team size/skill level considerations?

5. **No troubleshooting for adoption friction** -- If a tool isn't in the registry or recipe names don't match your ecosystem, what's the remediation path?

6. **No Claude Code skill for adoption** -- No `/tsuku:init` or similar skill to guide teams through setup

### Prior Art in Workspace

One example `.tsuku.toml` found:
```toml
[tools]
serve = "0.6.0"
```

This is minimal and shows the expected format, but no examples of multi-tool projects or incremental adoption strategies.

## Implications

1. **Self-service gap**: A team cloning a new project and seeing `.tsuku.toml` will find the Shell Integration guide useful. A team trying to *add* tsuku to an existing project will find less guidance.

2. **Name mapping friction**: Teams using asdf (which uses plugin names like "nodejs", "python") will struggle to map to tsuku recipe names (which use "node", "python"). The design calls this out as intentional deferred work.

3. **Discovery cost**: Without tooling, finding the right recipe for each tool requires manual registry search. No `tsuku find` or similar.

4. **Adoption path unclear**: No single document that says "you're using asdf/nvm/pyenv → here's your adoption path"

## Surprises

1. **Design maturity vs. user guide maturity**: The design documents are comprehensive and thoughtful (addressing monorepo scenarios, consent models, security). The user-facing adoption guide is minimal by comparison.

2. **Explicit deferral of migration**: The project explicitly chose NOT to support `.tool-versions` for now, with the comment "measure demand before committing." This is a pragmatic but honest friction point.

3. **Project config as consent is a first-class design choice**: Rather than an afterthought, the consent model is central to the architecture -- it shapes auto-install behavior, hook integration, and even the decision to prompt only once at `tsuku install` time.

## Open Questions

1. **Is there a `tsuku migrate` command in development?** The design mentions it as "best-effort import from `.tool-versions`" but marks it deferred.

2. **What happens when a tool isn't in the registry?** The adoption guide should explain the fallback path (custom recipes? `--from` syntax?).

3. **Are there examples of multi-tool `.tsuku.toml` files in real tsuku projects?** Beyond the "serve = 0.6.0" example?

4. **Does tsuku recommend a phased adoption (add tools gradually) or all-at-once?** The guide doesn't indicate either strategy.

## Summary

Tsuku documents .tsuku.toml adoption at the usage level (Shell Integration guide shows how to create and use `.tsuku.toml`), but lacks a dedicated adoption guide for existing projects transitioning to tsuku. The design is mature and forward-thinking, but migration from asdf/mise is explicitly deferred as future work. This creates a friction point: teams using other tool managers will need to manually create `.tsuku.toml` without guidance on recipe name mapping, tool discovery, or decision frameworks. No Claude Code skill exists to guide adoption.


# Research: Cursor IDE Compatibility for shirabe's Skill Extensibility Mechanism

## Summary

shirabe's extension mechanism **cannot work as-is in Cursor**. The critical blocker is the `@` include syntax: Claude Code resolves `@path` lines in SKILL.md client-side before the LLM sees the file — zero tool calls, deterministic, silent skip on missing files. Cursor does not implement this behavior. The `@` references in a Cursor-loaded SKILL.md would appear as literal text in the LLM's context, making the extension injection mechanism inoperative.

The remaining two layers (CLAUDE.md-equivalent context and plugin format) have partial or full analogs in Cursor, but the per-skill extension injection is the mechanism that requires a separate Cursor implementation.

---

## Research Questions and Findings

### 1. Does Cursor support Claude Code plugins (`.claude-plugin/` format)?

**Yes, with a parallel format.** Cursor uses `.cursor-plugin/plugin.json` as its plugin manifest. The structure mirrors Claude Code's `.claude-plugin/plugin.json` directly — both require a `name` field and support `description`, `version`, `author`, and component directory paths. The obra/superpowers repository demonstrates this parallel structure in practice: it ships both `.claude-plugin/plugin.json` and `.cursor-plugin/plugin.json` at the repo root.

The Cursor `.cursor-plugin/plugin.json` for superpowers points to `./skills/`, `./agents/`, `./commands/`, and `./hooks/hooks-cursor.json` — the same shared `skills/` directory that Claude Code uses, since both clients implement the Agent Skills open standard.

Key difference: Cursor plugin manifests use a `hooks` field pointing to a cursor-specific hooks JSON file (`hooks-cursor.json`). Hooks are not cross-compatible, but skills and commands in the shared `skills/` directory work across both clients.

**Conclusion**: A plugin can ship both `.claude-plugin/plugin.json` and `.cursor-plugin/plugin.json` pointing to shared skill directories. The plugin format itself is not a blocker.

### 2. Does Cursor support `@` file includes in its rules/skills system? Is resolution client-side?

**No client-side `@` include resolution exists for SKILL.md files in Cursor.**

The `@` include syntax used by shirabe's extension mechanism — lines like `@.claude/shirabe-extensions/explore.md` at the head of a SKILL.md — is a Claude Code-specific behavior. Claude Code resolves these lines client-side before the LLM receives the skill content: the referenced file's content is injected inline, and missing files are silently skipped. This is documented in the Claude Code memory docs as the `@path/to/import` syntax for CLAUDE.md files, and it extends to SKILL.md content loaded via the plugin system.

Cursor does support `@`-mention syntax in chat and in `.mdc` rule files, but with a fundamentally different mechanism:

- In Cursor's chat, `@filename` is a user-facing mention that tells the LLM to consider a specific file — it's the equivalent of attaching a file to the conversation, not preprocessed injection.
- In `.cursor/rules/` (`.mdc` files), `@filename` references are described as "reference files instead of copying their contents" — pointing to code templates or canonical examples. Cursor's documentation does not indicate that these are resolved client-side before LLM processing. The behavior is LLM-visible reference, not transparent injection.
- The Agent Skills specification (agentskills.io) defines relative file paths in SKILL.md body content as references the LLM reads on demand via its file-read tools — explicitly LLM-driven, not client-side preprocessing.

**The `@` include behavior in Claude Code SKILL.md is a Claude Code-specific extension beyond the Agent Skills standard.** The standard describes "file references" that the LLM loads via its file tools (tier-3 progressive disclosure). Claude Code's client-side `@` injection is not part of the open standard and is not implemented by Cursor.

**Conclusion**: `@.claude/shirabe-extensions/explore.md` placed at the head of a SKILL.md will appear as literal text to the Cursor LLM. It will not inject extension content. The extension mechanism as designed does not work in Cursor.

### 3. Does Cursor have an equivalent to CLAUDE.md (project-level AI context files)?

**Yes, with two equivalents:**

- **AGENTS.md**: A plain markdown file in the project root (or subdirectories). This is the cross-client standard adopted alongside the Agent Skills format. Skills-compatible clients, including Cursor, load this file as project-wide context analogous to CLAUDE.md.
- **`.cursor/rules/` (`.mdc` files)**: Cursor's native project rules system. Rules can be configured as `alwaysApply: true` (loaded every session), or scoped by file glob patterns. This is more structured than CLAUDE.md but serves the same purpose.

The CLAUDE.md layering layer of shirabe's extension mechanism (headers like `## Repo Visibility:` and `## Planning Context:`) would translate to Cursor if the consumer puts those headers in AGENTS.md or an always-applied `.cursor/rules/` file. The LLM reads those headers from context in both clients.

**Conclusion**: CLAUDE.md-layer extensibility (cross-skill project-wide context headers) is portable to Cursor via AGENTS.md or always-applied rules. No changes required to shirabe itself — consumers just need to know to put those headers in AGENTS.md instead of (or in addition to) CLAUDE.md.

### 4. Does Cursor have an equivalent to SKILL.md (per-command AI instruction files)?

**Yes — Cursor implements the Agent Skills open standard.** SKILL.md files with YAML frontmatter (`name`, `description`) work in Cursor as of 2025-2026. The format is identical to what shirabe would ship:

```
skills/
  explore/
    SKILL.md
  design/
    SKILL.md
  ...
```

Cursor discovers skills from `.cursor/skills/`, `.agents/skills/`, and plugin skill directories. Skills are invoked via `/skill-name` or automatically when the LLM determines relevance. The `disable-model-invocation: true` frontmatter field controls invocation behavior in both Claude Code and Cursor.

One difference: Claude Code adds several extensions to the standard (`context: fork`, `${CLAUDE_SKILL_DIR}` variable, `allowed-tools` pre-approval). Cursor supports some of these fields (`allowed-tools` is in the standard as experimental; `disable-model-invocation` is standard). `context: fork` and `${CLAUDE_SKILL_DIR}` are Claude Code-specific. shirabe skills would need to avoid relying on these Claude Code extensions in their base SKILL.md content if targeting Cursor compatibility.

**Conclusion**: SKILL.md format compatibility is high. The base skill structure works in Cursor. Claude Code-specific frontmatter extensions are the only format incompatibilities, and those can be avoided in cross-platform skill content.

### 5. What would a Cursor-compatible version of shirabe's extension mechanism look like?

Since client-side `@` injection doesn't exist in Cursor, a Cursor-compatible extension mechanism requires a different approach. Three options:

**Option A: AGENTS.md / rules-only extension (partial)**

Consumers put all project customizations in AGENTS.md or always-applied `.cursor/rules/` files. This covers the cross-skill CLAUDE.md layer (visibility, scope, label vocabulary) but provides no per-skill extension point. There is no way to inject content into only the explore skill's context without it also being in every conversation. This is the "CLAUDE.md-only" option that the design doc rejected for the same reason — it cannot target per-skill behavior.

**Option B: Parallel skill files per consumer (wrapper approach)**

Consumers create their own Cursor plugin with skills that wrap shirabe's skills by adding project preamble and then instructing the LLM to "follow the shirabe explore skill." This is the "wrapper skills" approach the design doc rejected — parallel maintenance, drift, and cross-plugin path resolution issues still apply. In Cursor, cross-plugin path resolution is LLM-driven (the LLM reads files via its file tools), so a wrapper skill could tell the LLM to explicitly read the shirabe SKILL.md file — but this requires knowing the plugin install path, which is client-dependent.

**Option C: Cursor-native slot injection via rules scoping**

Cursor's `.cursor/rules/` supports glob-scoped rules (`paths` frontmatter). A rule scoped to "when working with slash command contexts" could theoretically inject per-skill customizations. However, Cursor doesn't expose a mechanism to scope rules to "when skill X is active" — the scoping is file-path-based, not skill-based. This doesn't map cleanly to per-skill extension.

**Option D: SKILL.md duplication with placeholders**

The most reliable Cursor-compatible approach: when a consumer wants to extend a shirabe skill in Cursor, they copy the SKILL.md into their own project-level `.cursor/skills/explore/SKILL.md` (or `.agents/skills/explore/SKILL.md`), add their project content directly, and maintain that copy. The project-level skill overrides the plugin skill (project > plugin precedence). This is effective but is exactly the "fork" approach shirabe's design was meant to avoid — consumer copies drift from upstream.

**No option provides the same properties as Claude Code's `@` injection**: zero-tool-call, deterministic, silently-skip-when-absent, update-resilient per-skill extension that consumers write once and maintain separately from shirabe source.

### 6. Is direct compatibility possible, or would a separate Cursor-specific implementation be needed?

**A separate Cursor-specific implementation is needed** for the per-skill extension mechanism to function in Cursor.

The CLAUDE.md layer (cross-skill headers) is directly portable — consumers use AGENTS.md in Cursor instead. No shirabe changes needed.

The `@` extension slot layer requires a Cursor-native replacement. The closest practical analog for Cursor would be:

- Define a convention for consumers to place a `.cursor/rules/` file per skill (e.g., `shirabe-explore.mdc`) with glob-scoped applicability, and document this as the Cursor extension path. This doesn't achieve the same deterministic injection, but it gets project-specific context into Claude's view when the skill is active. The LLM would need to consider both the skill content and the relevant rule, which requires the rule to be always-applied or manually activated.
- Alternatively, build a Cursor-native extension mechanism into the SKILL.md itself: instead of `@` include lines, the Cursor version of a skill could instruct the LLM to read a well-known extension file path at activation time (LLM-driven, costing one Read tool call). This is the "wrapper" anti-pattern at the skill level rather than the consumer level, but it's deterministic in a different sense — the instruction is in the SKILL.md itself.

---

## Compatibility Matrix

| Mechanism | Claude Code | Cursor | Compatible as-is? |
|-----------|-------------|--------|-------------------|
| Plugin format (`.claude-plugin/` / `.cursor-plugin/`) | `.claude-plugin/plugin.json` | `.cursor-plugin/plugin.json` | No (separate manifests), but pattern is identical |
| SKILL.md base format | Agent Skills standard + CC extensions | Agent Skills standard | Mostly yes; avoid CC-specific frontmatter |
| Skill invocation (`/skill-name`) | Yes | Yes | Yes |
| CLAUDE.md / AGENTS.md project context | CLAUDE.md chain | AGENTS.md + `.cursor/rules/` | Translatable; consumers use AGENTS.md |
| `@` include in SKILL.md (client-side injection) | Yes, client-side, 0 tool calls | **No** | **No — core gap** |
| Per-skill extension file injection | Via `@` include, deterministic | Not supported natively | **No** |
| Silent skip on missing extension file | Yes (Claude Code behavior) | N/A | N/A |
| `.local.md` personal overrides | Yes (via gitignored `@` include) | No equivalent | No |

---

## Sources

- Cursor plugin documentation: `cursor.com/docs/plugins`, `cursor.com/docs/context/rules`
- Cursor skills documentation: `cursor.com/docs/skills`
- Agent Skills open standard: `agentskills.io/specification`, `agentskills.io/client-implementation/adding-skills-support`
- Claude Code skills and memory documentation: `code.claude.com/docs/en/skills`, `code.claude.com/docs/en/memory`
- obra/superpowers repository: `github.com/obra/superpowers` — demonstrates dual `.claude-plugin/` + `.cursor-plugin/` manifest approach with shared `skills/` directory
- shirabe design doc: `/home/dangazineu/dev/workspace/tsuku/tsuku-5/public/shirabe/docs/designs/DESIGN-skill-extensibility.md`

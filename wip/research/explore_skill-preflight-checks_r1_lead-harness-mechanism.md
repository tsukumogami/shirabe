# Lead: What mechanism, if any, lets Claude Code deterministically run a script when a skill loads?

## Findings

### 1. Hooks: PreToolUse (Partial Match)

**Mechanism**: PreToolUse hooks fire when a tool is about to execute, including the `Skill` tool itself.

**Evidence**: 
- `.claude/hooks/` documentation and CLI reference confirm PreToolUse fires before tool execution
- The shirabe repo ships a PreToolUse hook (`gate-online.local.sh`) that validates tool inputs and returns permission decisions
- Shirabe's Rust binary (`crates/shirabe/src/main.rs`) contains a `PrBodyHook` handler: "Client-side PreToolUse hook: gate a `gh pr create` / `gh pr edit` command... Reads a Claude Code hook JSON on stdin"

**Can it be scoped to a single named skill?**
Yes, via the `matcher` field. Hook matchers support exact strings and regex, so `"matcher": "Skill"` catches all skill invocations, and regex like `"matcher": "^work-on$"` could theoretically match by skill name if Claude emits the skill name in the tool call. However, the hook input's `tool_name` field appears to be `"Skill"` (generic), not the individual skill name. **This is an open question** — whether the hook receives the skill name in a separate field like `skill_name` or `input.arguments` requires clarification from the hook input schema.

**Does stdout/stderr reach the agent's context?**
Yes, partially. Hooks can output JSON with `systemMessage` (shown to user) and `additionalContext` (injected into Claude's context). However, stdout does not directly reach the agent unless the JSON output includes these fields. Exit codes are more direct: `exit 0` allows, `exit 2` blocks.

**Does exit code mean anything?**
Yes. Exit 0 = allow (or read JSON for decisions); exit 2 = block the tool call; other codes = non-blocking error (action proceeds). A hook can emit a `permissionDecision: deny` in JSON to prevent skill execution.

**Does it fire BEFORE or AFTER the skill body (SKILL.md) is read into context?**
**BEFORE** — PreToolUse fires before the tool executes, so before the skill's body is loaded into context. This means a preflight hook can inspect input arguments and block execution before the skill's markdown is even loaded.

**Can a PLUGIN ship it?**
Yes. Plugins ship hooks in `hooks/hooks.json` at the plugin root (or inline in `plugin.json` under the `hooks` field). The shirabe plugin's `.claude-plugin/plugin.json` does not currently include a `hooks` field, but the mechanism exists.

**Is ${CLAUDE_PLUGIN_ROOT} / ${CLAUDE_SKILL_DIR} available?**
Yes. `${CLAUDE_PLUGIN_ROOT}` is documented as available in hook scripts. `${CLAUDE_SKILL_DIR}` is not explicitly mentioned in the reference, but hooks receive `cwd` in their input JSON and can reference relative paths.

### 2. Inline Script Interpolation in Skills (`!cmd`` syntax) — CRITICAL FINDING

**Mechanism**: Claude Code supports inline command interpolation in Markdown files using `` `!command` `` syntax (backticks prefixed with `!`). The command is executed at load time, and its stdout is substituted into the Markdown before the model sees it.

**Does it work in SKILL.md files?**
Requires verification. Documentation for skills.md and commands.md mentions this feature for custom slash commands in `.claude/commands/*.md`, but explicit confirmation needed for plugin SKILL.md files.

**Does it run when INVOKED (body loaded) and is output substituted BEFORE model sees it?**
If supported: YES — Interpolation would happen at skill load time (when `/skill-name` is invoked), and stdout would replace the `` `!cmd` `` token before the skill body reaches Claude. This is deterministic and cannot be skipped by the agent.

**Frontmatter required?**
Unknown. Likely requires `allowed-tools: Bash(...)` based on commands.md, but needs verification for skills.

**Is ${CLAUDE_PLUGIN_ROOT} resolvable?**
Unknown. Environment variables are typically resolvable in hook commands; needs verification for skill interpolation.

**Critical unknowns**:
- Does a failed command (non-zero exit) block skill loading or just substitute error text?
- Can permissions be pre-approved in settings.json without prompting on every load?
- Do plugin SKILL.md files support this syntax at all?

### 3. Hooks: SessionStart (Partial Match, Only Once Per Session)

**Mechanism**: SessionStart fires once at session initialization, before Claude begins working.

**Can it be scoped to a single named skill?**
No. SessionStart is session-level, not skill-level. Fires once, not per-skill.

**Does it fire BEFORE or AFTER the skill body is read?**
BEFORE session starts, so too early for skill-specific checks.

**Can a PLUGIN ship it?**
Yes, in `hooks/hooks.json` or inline in `plugin.json`.

### 4. Skill Frontmatter Fields

No `requires`, `preflight`, `run-on-load`, or `dependencies` field exists in documented SKILL.md frontmatter schema.

### 5. Other Hook Events (UserPromptSubmit, Setup, etc.)

- **UserPromptSubmit**: Prompt-level, not skill-specific. Fires on every prompt, too broad.
- **Setup**: Session initialization, not skill-specific.
- **PostToolUse**: Too late; fires after skill execution.

---

## Implications

The `` `!cmd` `` interpolation syntax **may be the primary answer** if:
1. It works in SKILL.md files (plugin skills)
2. It runs at skill invocation time
3. It can be permission-pre-approved without prompting
4. A failed command blocks the skill (not just substitutes error text)

Otherwise, **PreToolUse hooks are the closest match**, but skill-level scoping is unclear.

---

## Open Questions (URGENT)

1. **Does `` `!cmd` `` interpolation work in SKILL.md plugin files?** Test locally with shirabe skills or verify docs explicitly support it.

2. **What is the exact failure behavior?** Does a non-zero exit block skill loading, or just substitute error text inline?

3. **Can Bash permissions be pre-approved globally without prompts?** Settings.json entry like `"allowedTools": {"Bash": ["${CLAUDE_PLUGIN_ROOT}/scripts/*"]}` or per-skill?

4. **Can a hook differentiate individual skills?** Does PreToolUse hook input include the skill name (not just generic `tool_name: "Skill"`)?

5. **Are Shirabe skills (Koto workflows) or simple SKILL.md Markdown?** If Koto, the preflight could be a workflow state instead of Markdown interpolation.

---

## Summary

PreToolUse hooks exist but skill-level scoping is unclear. Inline command interpolation (`` `!cmd`` `` syntax) may be the answer but **requires urgent verification**: does it work in SKILL.md, can it block a skill on failure, and can permissions be pre-approved. Shirabe skills are Koto workflows, not plain Markdown, which may unlock a third path: workflow states that run preflight checks deterministically.


---

## CRITICAL UPDATE: Inline Command Execution (`!`cmd`` syntax) — VERIFIED

**Mechanism**: Claude Code supports inline command interpolation using `` `!command` `` syntax (backticks prefixed with `!`). Commands execute at skill load time, and stdout is substituted into the Markdown **before the model sees it**.

**VERIFIED FACTS**:

1. **Works in SKILL.md plugin files**: YES, confirmed by documentation and real examples in shirabe's `/inflight` skill, which uses `` `!shirabe work-summary render` ``

2. **Execution timing**: **At skill invocation time**, when the skill's SKILL.md is loaded for display to the model. This is deterministic and unavoidable — the agent cannot skip it.

3. **Output substitution**: Stdout replaces the `` `!cmd` `` placeholder as plain text before Claude sees the skill body. The substitution is one-pass (no re-scanning for nested placeholders).

4. **Failure behavior - THE KEY FINDING**: **A failed command aborts the entire skill invocation**. Claude never sees the skill body. Exit code is 0 for success; any non-zero exit code (except code 1 for search/comparison tools) fails the skill. Error message includes stderr output under `[stderr]` header.

5. **Frontmatter requirement**: `allowed-tools: Bash(...)` or `allowed-tools: Bash(script-path)` declares which Bash commands are permitted. **This triggers the normal permission flow** — if permissions are not pre-approved, the user is asked on first invocation. Pre-approval can be set in `.claude/settings.json` or `.claude/settings.local.json` with an allowlist.

6. **Environment variables**: `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PROJECT_DIR}`, and `${CLAUDE_CODE_SESSION_ID}` are all available and resolved in interpolated commands.

7. **Failure message example**: `Shell command failed for pattern "..."` with `[stderr]` showing the command's error output.

**Evidence**: From code.claude.com/docs/en/skills.md:
- "A failed command aborts the entire skill invocation, not just its own placeholder."
- "Claude never sees the skill content for that invocation."
- Example skill: shirabe's `/inflight` uses `` `!shirabe work-summary render` `` with `allowed-tools: Bash(shirabe:*)`.

**This is the answer**: Shirabe can ship a preflight check that:
1. Runs deterministically when a skill is invoked (before the model sees the body)
2. Can exit with a non-zero code to emit install instructions and block the skill
3. Can be scoped per-skill (each SKILL.md frontmatter can declare its own `allowed-tools` and `` `!cmd` `` block)
4. Can be shipped in the plugin (since SKILL.md files are part of the plugin)
5. Can be permission-pre-approved to avoid prompts on a correctly configured machine
6. Runs silent if the check passes (exit 0, empty stdout substitutes as nothing)


# Lead: What extension points does Claude Code offer for injecting recurring or conditional instructions into a session?

Sources: official docs at https://code.claude.com/docs/en/hooks (hooks reference), /en/memory, /en/output-styles, /en/statusline, /en/skills, /en/settings; plus real hook configs in this workspace: `/home/dangazineu/dev/niwaw/tsuku/tsuku+always_include_links-fe2fc637/.claude/settings.json` and its hook scripts under `.claude/hooks/`.

## Findings

### 1. Hooks — the only mechanism that meets all four requirements

Hooks are external shell commands (or HTTP/MCP-tool/prompt/agent handlers) configured in settings.json under a `hooks` key, keyed by event name. They receive JSON on stdin (always including `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode`) and can emit JSON on stdout.

**(a) Context injection — which events reach the model.** Per the hooks reference, these events can add content to Claude's context, either via plain stdout or via the JSON field `hookSpecificOutput.additionalContext`:

- `SessionStart` — stdout AND `additionalContext` injected before the first prompt. Matchers: `startup|resume|clear|compact`.
- `UserPromptSubmit` — stdout is added directly to context alongside the user's prompt (unique: no `additionalContext` wrapper needed, though the field also works). Also supports `decision: "block"` + `reason`. **No matcher support** — fires on every prompt.
- `PreToolUse` — `hookSpecificOutput.additionalContext` delivered next to the tool call; also `permissionDecision: allow|deny|ask|defer`, `updatedInput`.
- `PostToolUse` — `hookSpecificOutput.additionalContext` delivered next to the tool result; also `decision: "block"` + `reason` (fed back to Claude), `updatedToolOutput`, `systemMessage`.
- `PostToolUseFailure`, `PostToolBatch` — same `additionalContext` support.
- `Stop` / `SubagentStop` — `additionalContext` (adds context if the conversation continues) and `decision: "block"` + `reason`, which forces Claude to keep going with the reason injected as instruction.

Display-only events (do NOT reach the model): `Notification` (matchers like `permission_prompt`, `idle_prompt`), `SessionEnd`, `Setup`, `MessageDisplay` (`displayContent` replaces on-screen text only), `PostCompact` (`systemMessage` only). `PreCompact` supports only `decision: "block"` — it can veto compaction but not inject context.

All events support universal output fields: `continue: false` + `stopReason`, `suppressOutput`, `systemMessage` (user-visible warning, NOT model-visible), `terminalSequence`.

Exit codes: 0 = success (JSON on stdout processed only on exit 0); 2 = blocking error, stderr fed back; other = non-blocking error, stderr shown to user only.

The docs deliver hook-injected `additionalContext` into the transcript as system-reminder-style content adjacent to the triggering event; the model sees it, the user mostly doesn't (unless `systemMessage` is also set). The memory doc explicitly recommends hooks over CLAUDE.md when something "must run at a specific point... regardless of what Claude decides to do."

**(b) State across invocations.** Hooks are stateless processes, but every invocation gets `session_id` and `transcript_path` in stdin JSON, so a script can keep a counter or timestamp in a file keyed by session_id (e.g., `/tmp/summary-state-${session_id}.json`, or `${CLAUDE_PLUGIN_DATA}` — a documented plugin persistent-data dir that survives plugin updates). A hook can also read `transcript_path` (JSONL) to count turns or grep for the last summary emission directly, with no state file at all. `SessionStart` can persist env vars via `$CLAUDE_ENV_FILE`.

**(c) Reacting to specific tool calls.** Two layers:
- Matcher: `"matcher": "Bash"` on `PreToolUse`/`PostToolUse` (exact string, `|`-separated list, or unanchored regex when the pattern contains regex chars; e.g. `mcp__.*__write.*`).
- The `if` field on hook handlers uses permission-rule syntax to filter by tool arguments: `"if": "Bash(gh pr create*)"` — this fires the hook only for matching Bash commands, exactly the `gh pr create` case. Alternatively the script itself greps `.tool_input.command` from stdin (this workspace's `gate-online.sh` does exactly that with a `case` statement on `gh pr merge*`, `curl *`, etc.).

**(d) settings.json semantics.** Structure (verified against the live project settings at `/home/dangazineu/dev/niwaw/tsuku/tsuku+always_include_links-fe2fc637/.claude/settings.json`):

```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Bash",
        "hooks": [ { "type": "command",
                     "if": "Bash(gh pr create*)",
                     "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/post_tool_use/pr-summary.sh",
                     "timeout": 30 } ] }
    ]
  }
}
```

Hooks merge from user settings (`~/.claude/settings.json`), project (`.claude/settings.json`), local (`.claude/settings.local.json`), managed policy, plugin `hooks/hooks.json`, and skill/agent frontmatter (`hooks:` key, with `once: true` supported in skills). `disableAllHooks: true` kills everything. Handler options: `type: command|http|mcp_tool|prompt|agent`, `timeout` (seconds, default 600 for command), `async`, `statusMessage`. `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}` placeholders are available.

**Real-world example in this workspace:** the Stop hook `.claude/hooks/stop/workflow-continue.sh` reads stdin JSON, checks `wip/*-state.json` for incomplete issues, and emits `{"decision": "block", "reason": "..."}` to nudge the agent to continue — proof that niwa-provisioned settings.json already carries exactly this class of machinery, and that Stop-hook context injection works in practice.

### 2. Statusline — display-only, but has a real timer

Configured via the `statusLine` setting: `{"type": "command", "command": "~/.claude/statusline.sh", "padding": 2, "refreshInterval": N}`. The script receives rich JSON on stdin (`model.id/display_name`, `workspace`, `context_window.used_percentage`, `cost`, `session_id`, **`transcript_path`**) and whatever it prints is displayed in the footer area. It re-runs after each assistant message, after `/compact`, on permission-mode change — debounced at 300ms — and `refreshInterval` (min 1s) re-runs it on a fixed timer even while idle. Docs: https://code.claude.com/docs/en/statusline.

Output is **display-only**: nothing the statusline prints reaches the model. But because it gets `transcript_path`, a statusline script could grep the session transcript for PR URLs and render "PRs: #123 ✓CI #124 ✗CI" persistently — a genuine always-visible alternative that costs zero context tokens.

### 3. footerLinksRegexes — built-in clickable badges for IDs (surprise finding)

Settings doc (v2.1.176+): `footerLinksRegexes` renders clickable footer badges whenever a regex matches turn output:

```json
{ "footerLinksRegexes": [ { "type": "regex",
    "pattern": "\\b(?<key>tsukumogami/\\w+#\\d+)\\b",
    "url": "https://github.com/{key}", "label": "{key}" } ] }
```

User/managed/`--settings` scope only — **not project or local settings**, so niwa can't ship it via project `.claude/settings.json`; it would have to write the user-level file. Display-only, no state, but directly attacks the "can't find PR links in a long chat" pain. The statusline doc explicitly points to it for "clickable link badges in the footer when an ID appears in the conversation."

### 4. CLAUDE.md / rules — static, loaded once, no cadence

CLAUDE.md (managed, `~/.claude/CLAUDE.md`, `./CLAUDE.md`, `CLAUDE.local.md`, plus `.claude/rules/*.md` with optional `paths:` glob frontmatter) is delivered as a user message after the system prompt, loaded in full at session start (subdirectory files lazy-load on file access). No periodic re-injection; project-root CLAUDE.md is re-injected after `/compact`, nested ones aren't. It can state the *convention* ("when asked for a work summary, use this template") but cannot enforce cadence — docs explicitly say it's "context, not enforced configuration" and recommend hooks for anything that must happen at a specific point. Docs: https://code.claude.com/docs/en/memory.

### 5. Output styles — system-prompt modification, always-on, no cadence

`outputStyle` setting or `.claude/output-styles/*.md` files (also shippable in plugins, with `force-for-plugin: true` to auto-apply). Appends instructions to the system prompt; the docs note styles "trigger reminders for Claude to adhere to the output style instructions during the conversation" — so an output style saying "end responses that created/updated PRs with a summary block" would get periodic adherence reminders for free. But it applies to *every* response (the exact anti-pattern the user rejected) unless the instruction itself encodes a condition, which the model must then honor voluntarily. Read once at session start; changes need `/clear`. Docs: https://code.claude.com/docs/en/output-styles.

### 6. Skills — on-demand instruction loading + hook carrier + dynamic context

Skills load their body only when invoked (`/name`) or when Claude matches the `description`. Key capabilities for this exploration (docs: https://code.claude.com/docs/en/skills):
- **Dynamic context injection**: `` !`command` `` lines in SKILL.md run at load time and are replaced with their output before Claude sees the content — a `/work-summary` skill could inline `!`gh pr list --author @me --json url,title,statusCheckRollup`` so the summary template arrives pre-populated with live PR data.
- **Frontmatter hooks**: a skill can declare `hooks:` scoped to its lifecycle, and plugins ship global hooks via `hooks/hooks.json` — so the shirabe plugin can carry both the template skill and the cadence hook in one installable unit.
- No self-scheduling: a skill can't fire itself periodically; something (user, model, or a hook's injected reminder) must trigger it.

### 7. MCP — pull-based; can't self-inject on a schedule

MCP servers contribute tools, resources, and server instructions (injected once at session start). Tool results reach the model only when the model chooses to call the tool. A hook handler of `type: "mcp_tool"` lets a hook invoke an MCP tool as its implementation. No mechanism for an MCP server to push content into context on a timer or turn count.

### 8. Task list / system reminders

The task list is model-managed state; `TaskCreated`/`TaskCompleted` hook events fire when tasks are created/completed and support `decision: "block"` but no `additionalContext` and no matchers — weak fit. "System reminders" are not a user-configurable surface; they're the internal envelope Claude Code uses to deliver injected content (hook additionalContext, CLAUDE.md, skill listings) to the model. You don't configure reminders directly; you configure the mechanisms above and the harness wraps them.

## Answers to the four scenarios

**(i) Turn-count injection ("every N prompts"):** `UserPromptSubmit` hook. Fires on every prompt (no matcher), stdout goes straight into model context. Script keeps a counter file keyed by `session_id` (or counts user messages in `transcript_path`); every Nth prompt it prints the reminder ("emit the work-summary block per the /work-summary template"), otherwise exits 0 silently. Fully supported, deterministic.

**(ii) Time-based injection (">15 min since last summary"):** Same `UserPromptSubmit` (or `Stop`) hook comparing `now` against a timestamp file updated whenever the reminder fires. Caveat: hooks are event-driven — nothing fires during idle time, so "15 minutes" really means "first prompt/turn-end after 15 minutes elapsed," which matches the intent. The only true wall-clock timer in the harness is statusline `refreshInterval`, which is display-only.

**(iii) Event-based injection (after `gh pr create`/`merge`):** `PostToolUse` with `"matcher": "Bash"` plus either `"if": "Bash(gh pr create*)"` on the handler or script-side matching on `.tool_input.command` (the workspace's `gate-online.sh` already demonstrates the pattern on PreToolUse). Emit `hookSpecificOutput.additionalContext` = "You just created/merged a PR; update the standing work summary." The hook also sees `tool_output`, so it can extract the PR URL itself. This is the sharpest cadence signal: summaries appear exactly when PR state changes.

**(iv) Always-visible display alternative:** statusline script that reads `transcript_path` (or a state file the PostToolUse hook maintains) and renders current PRs + status; `refreshInterval` keeps CI status fresh while idle. Complement with `footerLinksRegexes` for clickable PR badges (user-settings-scope only). Zero context cost, but not part of the conversation — can't be copy-pasted from chat history and invisible in transcripts/Agent View.

## Implications

- **Hooks are the only cadence mechanism.** CLAUDE.md, output styles, and skills can define the *template/convention* but cannot enforce *when*. The cadence layer must be a hook (UserPromptSubmit for turn/time-gated, PostToolUse for event-gated), and the two compose: hook injects a one-line reminder, which triggers the model to invoke the skill holding the full template.
- **Both candidate homes are viable and can even share code.** shirabe (a plugin) can ship the skill + `hooks/hooks.json` as one unit that follows the plugin everywhere; niwa (which already writes project `.claude/settings.json` with PreToolUse/Stop hooks, per this instance's settings file) can inject the same hook config plus scripts at provisioning time. Plugin hooks are versioned with the plugin; niwa-written hooks are per-instance and can reference instance-specific paths.
- **A hybrid is cheap:** PostToolUse hook maintains `wip/`- or `$CLAUDE_PLUGIN_DATA`-based PR-state as a side effect, statusline renders it continuously, and a turn/time-gated UserPromptSubmit reminder makes the model emit the in-chat summary block at bounded cadence. Event-gated injection (iii) best matches "summaries when something actually changed."
- The `systemMessage` field offers a fourth path nobody asked about: a hook can print a user-visible (model-invisible) notice — e.g., the PR link itself — directly into the transcript UI without spending any model tokens or relying on model compliance.

## Surprises

- **`footerLinksRegexes` exists** (v2.1.176+) and is almost purpose-built for "find PR links in a long chat" — but it's user/managed-settings scope only, so niwa would need to write `~/.claude/settings.json`, not the project file.
- **Statusline has `refreshInterval`** — a true wall-clock timer, but display-only. There is no timer that reaches the model.
- **`PostToolUse` supports `additionalContext`** — the exploration assumption that only UserPromptSubmit/SessionStart inject context is wrong; nearly every lifecycle event except Notification/SessionEnd/PreCompact can inject.
- **The `if: "Bash(gh pr create*)"` handler filter** means the `gh pr create` trigger needs no script-side parsing at all.
- **`Stop` hooks can force continuation with injected instructions** (`decision: "block"` + `reason`), and this workspace already uses that pattern (`workflow-continue.sh`) — a Stop hook could demand "append the work summary" at end-of-turn, though blocking Stop risks loops (input includes `stop_hook_active` to guard).
- **Skills' `` !`command` `` dynamic injection** lets the summary template arrive with live `gh pr list` output already inlined — the model doesn't need to gather PR state itself.
- Output styles get automatic in-conversation adherence reminders, which is a weak built-in recurrence mechanism.

## Open Questions

- Exact rendering of `additionalContext` to the model (system-reminder wrapper vs. plain text) is documented behaviorally but not verbatim; worth a live test to confirm the model reliably treats a UserPromptSubmit stdout nudge as actionable.
- Version floor: `if` filters, comma matchers (v2.1.191+), `footerLinksRegexes` (v2.1.176+) — what Claude Code versions do niwa-provisioned instances actually run, and should the design avoid newer features?
- Does a plugin-shipped `hooks/hooks.json` fire in sessions where the plugin is enabled but the marketplace pin is stale (shirabe is pinned to v0.13.0 here)? Update/rollout semantics need checking.
- Loop safety for Stop-hook-driven summaries: how does `stop_hook_active` interact with a summary demand (vs. the gentler UserPromptSubmit path)?
- Whether subagent-heavy sessions (niwa dispatch workers) route these hooks correctly — `Stop` auto-converts to `SubagentStop` in agent frontmatter, but project-settings hooks inside subagents need verification.

## Summary

Hooks are the only Claude Code mechanism that can inject instructions into the model's context on a cadence: `UserPromptSubmit` (stdout injected every prompt, stateful via session_id-keyed files for turn/time gating), `PostToolUse` with `matcher: "Bash"` + `if: "Bash(gh pr create*)"` (event-gated `additionalContext`), and `Stop` (`decision: block` forces continuation with instructions) — while CLAUDE.md, output styles, and skills can only hold the summary template, and statusline/footerLinksRegexes are display-only but give an always-visible PR view (statusline even has a real `refreshInterval` timer and receives `transcript_path`). This means the design should compose a shirabe skill (template, with `` !`gh pr list` `` dynamic injection) with a hook for cadence, and both candidate homes work: shirabe plugins ship hooks via `hooks/hooks.json`, and niwa already writes exactly this kind of hook into project `.claude/settings.json` (see gate-online.sh and workflow-continue.sh in this instance). Biggest open question: version floors and rollout semantics (the `if` filter, `footerLinksRegexes` v2.1.176+, plugin-hook update behavior) across the Claude Code versions niwa instances actually run.

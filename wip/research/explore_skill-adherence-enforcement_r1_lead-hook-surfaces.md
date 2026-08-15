# Lead: Which hook and configuration surfaces can carry a skill-adherence policy, and what can each one actually do?

Sources of record:

- <https://code.claude.com/docs/en/hooks> (hooks reference; `docs.claude.com/en/docs/claude-code/hooks` 301-redirects here)
- <https://code.claude.com/docs/en/hooks-guide> (hooks guide)
- Direct schema inspection of the installed CLI binary,
  `/home/dgazineu/.local/share/claude/versions/2.1.233`. Where the rendered docs
  and the binary disagree, the binary wins and I say so.
- Local working examples:
  `/home/dgazineu/dev/niwaw/tsuku/tsuku+execute_and_work_on_trigger-d36b0bbf/.claude/settings.json`,
  `.claude/hooks/pre_tool_use/gate-online.sh`,
  `.claude/hooks/stop/workflow-continue.sh`,
  `/home/dgazineu/.claude/settings.json`,
  `/home/dgazineu/.claude/plugins/cache/claude-plugins-official/superpowers/6.2.0/hooks/hooks.json`
  and `.../hooks/session-start`,
  `/home/dgazineu/dev/niwaw/tsuku/tsuku+execute_and_work_on_trigger-d36b0bbf/public/niwa/internal/workspace/materialize.go`.

A framing correction before the table: the nine events in the brief are a subset.
The current reference documents roughly thirty-five events, and three that were
not on the list — `SubagentStart`, `PostToolBatch`, and `TaskCompleted` — are
directly relevant to a skill-adherence gate. They are included below.

## Findings

### 1. Capability table

Columns: **(a)** can it inject context the model reads; **(b)** can it block or
deny; **(c)** can it rewrite the prompt or the tool input; **(d)** does it fire
for subagents; **(e)** does it fire in background / headless sessions.

| Event | (a) inject context | (b) block/deny | (c) rewrite | (d) subagents | (e) background/headless |
|---|---|---|---|---|---|
| `SessionStart` | **Yes.** `hookSpecificOutput.additionalContext`, or plain stdout on exit 0, prepended to the session context | **No.** Exit 2 shows stderr to the user only; the session proceeds | n/a | Fires once per *session*, not per subagent. `SubagentStart` is the subagent analog | **Yes** — a background/dispatched session is a session. niwa's ephemeral-session integration already hangs off it (`materialize.go:478`) |
| `UserPromptSubmit` | **Yes.** `hookSpecificOutput.additionalContext` — must be nested; a top-level `additionalContext` is *silently ignored* | **Yes.** `decision: "block"` or exit 2. The prompt is erased; `reason` goes to the **user**, not to Claude | **Yes.** `updatedInput` replaces the prompt text | No — subagents do not submit user prompts | Yes, for the session's initial `-p`/task prompt. niwa already registers one here (`work-summary absence`) |
| `PreToolUse` | **Yes.** `hookSpecificOutput.additionalContext` | **Yes.** `permissionDecision: "deny"` or exit 2. Fires *before* any permission-mode check and denies even under `bypassPermissions` / `--dangerously-skip-permissions` | **Yes.** `updatedInput` replaces the tool arguments | **Yes**, with `agent_id` and `agent_type` on the input | **Yes** |
| `PostToolUse` | **Yes.** `additionalContext`, plus `updatedToolOutput` / `updatedMCPToolOutput` (binary-verified) | **No** — the tool already ran. Exit 2 shows stderr *to Claude* | Output only, not input | **Yes** | **Yes** |
| `Stop` | **Yes.** `hookSpecificOutput.additionalContext`, described in the binary as "non-error feedback delivered to the model; the conversation continues so the model can act on it" | **Yes.** Top-level `{"decision":"block","reason":...}` or exit 2. `reason` is fed to Claude as context to keep working | n/a | No — `SubagentStop` is the analog | **Yes** |
| `SubagentStop` | **Yes.** `hookSpecificOutput.additionalContext` | **Yes.** Same `decision: "block"` + `reason`; the reason goes to the *subagent* | n/a | This *is* the subagent event; matchable by agent type | **Yes** |
| `PreCompact` | No `additionalContext` in the schema | **Yes**, blocks compaction (rarely what you want) | n/a | n/a | Yes |
| `Notification` | Schema accepts `additionalContext` (binary-verified) but the docs say output is ignored — **treat as unusable** | **No** | n/a | n/a | The `agent_needs_input` / `agent_completed` matchers "fire only while agent view is open" |
| `SessionEnd` | **No** | **No** | n/a | n/a | Yes, but all `SessionEnd` hooks share a 1.5 s budget (raisable to 60 s via `timeout`) |
| `SubagentStart` *(not in brief)* | **Yes — `additionalContext`, binary-verified** (see Surprises); injected into the subagent's own context | No | n/a | This is the subagent-spawn event; matcher is the agent type | Yes |
| `PostToolBatch` *(not in brief)* | **Yes.** `additionalContext` | **Yes.** Exit 2 stops the agentic loop before the next model call | n/a | Yes | Yes |
| `TaskCompleted` *(not in brief)* | No | **Yes.** Prevents a task being marked complete | Yes | Yes |

Two cross-cutting rules from the guide:

> "Hooks from settings files, managed policy settings, and plugins also run
> inside subagents. When a subagent calls a tool, tool events such as
> `PreToolUse` and `PostToolUse` fire the same configured hooks as in the main
> conversation, and the input carries the `agent_id` and `agent_type` common
> input fields."

> "`PreToolUse` hooks fire before any permission-mode check, in every permission
> mode, including `dontAsk`. A hook that returns `permissionDecision: "deny"`
> blocks the tool even in `bypassPermissions` mode or with
> `--dangerously-skip-permissions`. This lets you enforce policy that users can't
> bypass by changing their permission mode."

That second quote is the single most load-bearing fact for this design. Given
`ask` is unusable in a dispatched session, `deny` is the only enforcement verb
available, and it works.

### 2. Denial semantics — what does the model actually see?

**PreToolUse deny.** The guide is explicit: *"With `"deny"`, Claude Code cancels
the tool call and feeds `permissionDecisionReason` back to Claude."* The reason
arrives as the tool's error result, in the model's normal read path, so it is
text the model can act on and self-correct from. The exit-2 form behaves the
same way with stderr as the reason. This is exactly the shape needed: "you tried
to Edit a source file but no koto session exists for PLAN-x; run `<command>`
first."

One version-sensitive caveat, and it applies only to `type: "prompt"` and
`type: "agent"` hooks, not to command hooks:

> "`PreToolUse`: the tool call is denied; by default the turn ends and the deny
> `reason` appears in the chat as a warning line. Set `continueOnBlock: true` on
> the hook to instead return the `reason` to Claude as the tool error, so it can
> adjust and continue. Before v2.1.210, the deny `reason` was returned to Claude
> as the tool error and the turn continued."

A `type: "command"` hook returning `permissionDecision: "deny"` keeps the
feed-back-and-continue behavior. If this gate ever gets built as a prompt or
agent hook, it must set `continueOnBlock: true` or a denial silently kills the
turn instead of correcting it.

**Stop block.** `{"decision":"block","reason":"..."}` at the *top level* (not
inside `hookSpecificOutput`) prevents the turn ending; the `reason` is shown to
Claude as context for why it should keep working. Corroborated by the working
local hook at `.claude/hooks/stop/workflow-continue.sh:56`, which emits exactly
that shape. Confirmed against the binary: the `hookSpecificOutput` variant for
`Stop` accepts **only** `additionalContext`, so a `decision` nested there is
dropped.

Loop protection is a real input field, `stop_hook_active` (binary-verified,
boolean), true when the current turn exists because a Stop hook blocked the
previous one. Stop also carries `last_assistant_message` and `background_tasks`
("lets hooks distinguish 'session is done' from 'session is paused waiting for
[background work]'").

**UserPromptSubmit block.** Asymmetric with the other two and easy to get wrong:
the prompt is *erased* and the `reason` is shown to the **user**, explicitly
**not** to Claude. A blocked prompt teaches the model nothing. For a background
dispatched session with no human reading the transcript, blocking here is a
silent dead end. Use `additionalContext` there, never `decision: "block"`.

### 3. UserPromptSubmit specifics

- Input field is **`prompt`** (binary-verified: `hook_event_name:"UserPromptSubmit",prompt:e,...,session_title:...`). The rendered reference's `user_input` is wrong.
- **Append:** `hookSpecificOutput.additionalContext`, prepended to the prompt before Claude sees it. The guide warns: *"Nest `additionalContext` inside `hookSpecificOutput`; if you place it at the top level of the JSON, Claude Code silently ignores it."* Plain stdout on exit 0 also becomes context.
- **Replace:** `updatedInput` replaces the prompt entirely. (The reference page renders this as `updatedPrompt`; that identifier does **not exist** anywhere in the 2.1.233 binary, while `updatedInput` appears 269 times. `updatedPrompt` is a doc error.)
- **Block:** `decision: "block"` + `reason`, or exit 2. Reason to the user only.
- Exact contract:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Current branch: release-42. Deploy freeze until Friday."
  }
}
```

- Timeout is lowered to **30 s** here (from the 10 min default) for `command`, `http`, and `mcp_tool` hooks.
- No matcher support; it always fires.
- Injected text arrives "as a system reminder that Claude reads as plain text."

### 4. SessionStart specifics

- Matchers: **`startup`, `resume`, `clear`, `compact`, `fork`**. Five, not four — `fork` is the one usually missed.
- Input field is **`source`** (binary-verified: `hook_event_name:"SessionStart",source:t,agent_type:o,model:i,session_title:...`). The reference page's `how` and `start_method` renderings are both wrong.
- Output: `hookSpecificOutput.additionalContext`, or plain stdout on exit 0. Cannot block.
- Working plugin example: superpowers declares this in `hooks/hooks.json` with `"matcher": "startup|clear|compact"` and a script that inlines an entire SKILL.md into `additionalContext` wrapped in `<EXTREMELY_IMPORTANT>` tags. That is a live proof that a plugin can push a multi-kilobyte policy into every session it is enabled for.
- **Does SessionStart `additionalContext` reach subagents spawned later? Not confirmed, and I believe not.** Nothing in either doc page says it does; a subagent is constructed with its own context window from its own system prompt and task prompt, and the reference introduces `SubagentStart` as the separate subagent-entry event. Treat "SessionStart context is inherited by subagents" as false until tested. The empirical test is one command: a SessionStart hook injecting a unique token, then `Task`-spawn an agent and ask it whether it can see the token.
- The correct subagent-side mechanism is **`SubagentStart` with `additionalContext`**, matchable by agent type — see Surprises.

### 5. Composition and precedence

Locations, verbatim from the guide's table:

| Location | Scope |
|---|---|
| `~/.claude/settings.json` | All your projects |
| `.claude/settings.json` | Single project |
| `.claude/settings.local.json` | Single project |
| Managed policy settings | Organization-wide |
| Plugin `hooks/hooks.json` | When plugin is enabled |
| Skill frontmatter | The rest of the session once the skill is invoked |
| Subagent frontmatter | While that subagent is running |

**Precedence: User → Project → Local → Managed Policy — but hooks *merge*, they
do not replace.** There is no mechanism for one settings level to remove or
override a specific hook declared at another level. Every matching hook at every
level runs.

The only off switch is the blunt one:

> "To disable hooks, set `"disableAllHooks": true` in your settings file. Claude
> Code reads the value left after settings precedence applies, so a project's
> settings file can override yours. Hooks configured in managed settings still
> run unless `disableAllHooks` is also set there."

So the answer to "can a project settings file disable a hook installed at another
level" is: **only by disabling every non-managed hook in the session.** There is
no surgical disable. `--settings '{"disableAllHooks": true}'` on the CLI takes
precedence over all of it.

**Merging within an event.** Every matching hook runs to completion in parallel
before results are combined; one hook's `deny` does not prevent a sibling from
executing. For `PreToolUse` the most restrictive answer wins in the order
`deny` → `defer` → `ask` → `allow`, and `additionalContext` from *every* hook is
kept and passed to Claude together. When two hooks both return `updatedInput`,
the last to finish wins and ordering is non-deterministic — so at most one hook
per tool should rewrite input.

**Skill and subagent frontmatter hooks** are a third channel worth knowing about:

> "Subagent hooks: Claude Code runs them only while that subagent is running and
> removes them when it finishes. Claude Code converts a `Stop` hook here to
> `SubagentStop`. Skill hooks: Claude Code registers them when you or Claude
> invoke the skill and keeps running them for the rest of the session, on turns
> after the skill's own turn as well. To have Claude Code run a hook a single
> time instead, set `once: true` on it."

Note the asymmetry that matters here: a skill-frontmatter hook only exists *after
the skill is invoked*. It cannot enforce that the skill gets invoked. The
first incident — the agent never calling `shirabe:execute` at all — is
structurally out of reach for any skill-frontmatter hook.

Project-skill and project-subagent frontmatter hooks also require workspace trust
acceptance for the folder they came from, and a `-p` session does not count as
acceptance (changed in v2.1.218). A dispatched headless session cannot rely on
frontmatter hooks from project files.

**Existing niwa-injected hooks**, confirmed in `materialize.go`, so the wiring
precedent exists at every level this design might use:

- `pre_tool_use` / matcher `Bash` → `shirabe pr-body-hook` (`materialize.go:605`)
- `post_tool_use` / matcher `Bash` → `shirabe work-summary capture`
- `user_prompt_submit` / no matcher → `shirabe work-summary absence`
- `session_start` / matcher `compact` → `shirabe work-summary compact`
  (`materialize.go:504-508`)

niwa's own `hookEventMapping` (`materialize.go:304`) currently translates only
`pre_tool_use`, `post_tool_use`, `stop`, and `notification`; `session_start`,
`session_end`, and `user_prompt_submit` are handled on separate code paths. Any
new event would need adding there.

## Implications

**The gate belongs on `PreToolUse`, denying the first implementation-shaped tool
call.** It is the only surface that is simultaneously (i) unbypassable — deny
beats `bypassPermissions`, which is exactly the mode dispatched sessions run in;
(ii) self-correcting — the reason is fed back as tool-error text the model reads
and acts on, so a deny that says "no koto session exists for PLAN-x; run
`<exact command>`" produces the corrective action rather than a stall; (iii)
subagent-transparent — it fires inside `/work-on` subagents too, carrying
`agent_id`, so the second incident's failure mode (skill invoked, payload built,
then six issues implemented inline) is caught at the first `Edit`. The gate
condition is already established as externally computable, which means the hook
is a `grep` and a `jq`, well inside the 10-minute command budget.

**`SubagentStart` `additionalContext` is the right answer to the second
incident specifically.** That incident was a conflict between two instructions
delivered through different channels, resolved against the skill. Injecting the
policy at `SubagentStart` puts it in the same channel as the session-level
instruction that beat it, at the same altitude, at spawn time, matchable by agent
type. It does not enforce anything on its own, but it removes the asymmetry that
caused the loss.

**A `Stop` block is a backstop, not the gate.** By the time `Stop` fires, 22
issues are already hand-implemented; blocking the stop only makes the agent keep
going down the wrong path. Its legitimate use is the narrow one: plan in play,
turn ending, no koto session, nothing implemented yet — nudge. Use
`stop_hook_active` to bound the loop, and `background_tasks` to avoid firing on a
session that is merely paused.

**Ship it as a plugin hook in shirabe, not as a niwa injection into project
settings.** Because hooks merge with no surgical disable, a hook injected into
project settings can only be escaped with `disableAllHooks`, which would also
kill the four hooks niwa already relies on. A plugin-declared hook is scoped to
plugin-enabled, which is the escape hatch adopters expect and the mechanism
superpowers already uses. niwa injecting `shirabe pr-body-hook` into project
settings is the counter-precedent, so this is a judgment call rather than a
constraint — but the disable story favors the plugin.

**Do not block at `UserPromptSubmit`.** The reason is shown to the user and not
to Claude, so in an unattended dispatched session a block is a silent stall with
no corrective signal. `additionalContext` there is fine and cheap, and niwa
already owns a hook on that event.

## Surprises

1. **`SubagentStart` accepts `additionalContext`.** The rendered docs do not show
   it and the summarizer reading them concluded it accepts only `systemMessage`.
   The 2.1.233 binary schema is unambiguous:
   `be({hookEventName:Tt("SubagentStart"),additionalContext:B().optional()})`,
   and the consuming path pushes it into the subagent's context. This is the
   cleanest available mechanism for injecting policy into subagents at spawn, and
   it is effectively undocumented.
2. **`PreToolUse` deny beats `bypassPermissions` and `--dangerously-skip-permissions`.** Explicitly documented as a feature: policy users cannot escape by changing permission mode.
3. **The docs have three field-name errors** that would each cost a debugging cycle: `updatedPrompt` (does not exist; it is `updatedInput`), `user_input` on `UserPromptSubmit` (it is `prompt`), and `how`/`start_method` on `SessionStart` (it is `source`). All three verified directly against the binary.
4. **Prompt-type `PreToolUse` hooks changed default behavior at v2.1.210**: a deny now *ends the turn* with a chat warning unless `continueOnBlock: true` is set. Command hooks kept the old feed-back-and-continue behavior. Same verb, opposite outcome, depending on hook type.
5. **`PostToolUse` can rewrite tool output** via `updatedToolOutput` / `updatedMCPToolOutput` — the model can be shown something other than what the tool returned.
6. **The local `workflow-continue.sh` Stop hook has its loop guard inverted.** `.claude/hooks/stop/workflow-continue.sh:24` reads `if [[ "$STOP_ACTIVE" != "true" ]] ... then exit 0`, so it exits early *unless* the turn was already produced by a Stop-hook block. The standard idiom is the reverse. As written it can only fire on a turn that some hook already continued, which in practice means never. Worth a look independent of this design.
7. **In non-interactive mode, a background subagent's tool call with no hook decision is denied**: *"Background subagents can't show a prompt in non-interactive mode. Claude Code still runs the hooks for their tool calls, and if no hook returns a decision, it denies the call."* A permissive hook that returns nothing is not neutral in that context.
8. **`TaskCompleted` can block a task being marked complete**, and `PostToolBatch` can stop the agentic loop between model calls. Neither was on the radar; both are plausible secondary gates.

## Open Questions

- **Does `SessionStart` `additionalContext` reach subagents spawned later?** Unconfirmed; I believe not. One-command empirical test described in Finding 4. This decides whether `SubagentStart` injection is necessary or merely redundant.
- **Does `UserPromptSubmit` fire when a teammate delivers a message via `SendMessage`, or only for real user prompts?** Not documented. Matters because dispatched work arrives as a task message, not a typed prompt.
- **Does a `claude --bg` dispatched session fire `SessionStart` with `source: "startup"`?** Strongly implied — niwa's ephemeral-session integration depends on it and `WorktreeCreate` explicitly fires "for a background session" — but I did not find a sentence stating it for `SessionStart` specifically.
- **What is `managedHooksOnly`?** The binary passes it through several hook-dispatch paths, including one permission-gate path pinned to `managedHooksOnly: true`. If some subagent or observer path runs *only* managed hooks, a plugin-declared hook would be invisible there. Undocumented; worth resolving before committing to a plugin-hook delivery.
- **`permissionDecision: "defer"`** is referenced in the guide as an SDK-oriented fourth value under `-p`, and the binary carries `hasHandledDeferredToolResume`, but the reference section describing it did not render in any fetch. Probably irrelevant here, but unread.

## Summary

`PreToolUse` is the only surface that meets all three requirements at once — it
denies unbypassably under `bypassPermissions` (documented as a deliberate
feature), it feeds `permissionDecisionReason` back to the model as tool-error
text the model can self-correct from, and it fires inside subagents with
`agent_id`, so a `/work-on` subagent hand-implementing gets caught at its first
`Edit` exactly as the main session would; `Stop` is a backstop that fires too
late to prevent the damage, and `UserPromptSubmit` blocking is unusable because
its reason goes to the user rather than to Claude. The undocumented find is that
`SubagentStart` accepts `additionalContext` (verified in the 2.1.233 binary
schema, absent from the rendered docs), which is the natural fix for the second
incident's channel asymmetry: it delivers the skill policy to a subagent at spawn
through the same channel as the session instruction that overrode it. On
composition, hooks from user, project, local, managed, and plugin sources all
merge with no surgical disable — the only off switch is the all-or-nothing
`disableAllHooks` — which argues for shipping the gate as a shirabe plugin hook
rather than a niwa injection into project settings, since plugin-enablement is
then the adopter's escape hatch.

# Lead: Which hook and configuration surfaces can carry a skill-adherence policy, and what can each one actually do?

Round 1 research lead for the skill-adherence-enforcement exploration.

**Version pinned to evidence.** All implementation claims are checked against the
Claude Code build actually installed on this machine:
`/home/dgazineu/.local/share/claude/versions/2.1.233` (also 2.1.232, 2.1.231
present). Documentation claims come from `https://code.claude.com/docs/en/hooks`
(the reference; `docs.claude.com/en/docs/claude-code/hooks` 301-redirects there)
and `https://code.claude.com/docs/en/hooks-guide` and
`https://code.claude.com/docs/en/permissions`.

**Method note / accuracy caveat.** The hooks reference page is long enough that
`WebFetch` truncates it, and the summarizing model returned *different* field
names on different passes. One pass claimed `UserPromptSubmit` honors
`hookSpecificOutput.updatedPrompt` and `UserPromptExpansion` honors
`expandedPrompt`. **Neither string exists anywhere in the installed 2.1.233
binary** (`grep -ac updatedPrompt` → 0; `grep -ac expandedPrompt` → 0), while
`updatedInput` appears 82 times and `additionalContext` 44 times. I have treated
the binary as the authority wherever the two disagree, and flagged every
remaining doc-only claim as such. Do not build a design on `updatedPrompt`.

---

## Findings

### A. The capability table

Columns: **Inject** = can add text the model reads. **Block** = can stop the
action. **Rewrite** = can alter the payload in flight. **Observe** = fires but
cannot change anything. **Subagent** = does this fire for / apply to a spawned
subagent.

| Event | Inject context | Block | Rewrite | Observe only | Fires for subagents? |
|---|---|---|---|---|---|
| `SessionStart` | **Yes** — `hookSpecificOutput.additionalContext`; also plain stdout on exit 0 | No (exit 2 shows stderr to user, session continues) | No | — | **No.** A subagent is not a session. Its analog is `SubagentStart`. |
| `SubagentStart` | **Yes** — `additionalContext`, "text to inject into the subagent's context at startup" (doc-only; see caveat) | No | No | — | **Yes, by definition.** Matcher = agent type. Input carries `agent_id`, `agent_type`, `subagent_config`, `parent_agent_id`, `parent_agent_type`. |
| `UserPromptSubmit` | **Yes** — `additionalContext`; also plain stdout on exit 0 | **Yes** — exit 2 blocks *and erases* the prompt | **Yes** — `hookSpecificOutput.updatedInput` replaces the prompt text sent to Claude | — | No. Subagents receive a task, not a user prompt. |
| `UserPromptExpansion` | Yes (`additionalContext`) | Yes | Doc says an expansion-replacement field exists; **the name is unconfirmed** — `expandedPrompt` is not in the binary. Possibly `updatedInput`. | — | No. |
| `PreToolUse` | **Yes** — `additionalContext` alongside a decision | **Yes** — `permissionDecision: "deny"` (exit 0 + JSON), or exit 2 | **Yes** — `updatedInput` rewrites the tool's arguments | — | **Yes.** Explicitly documented; input carries `agent_id` / `agent_type`. |
| `PostToolUse` | **Yes** — `additionalContext` | No (tool already ran) | No | — | **Yes.** |
| `PostToolUseFailure` | Presumed yes | No | No | — | Yes (inference). |
| `PostToolBatch` | — | **Yes** — exit 2 stops the loop before the next model call | No | — | Inference: yes. |
| `PermissionRequest` | No | No — exit 2 ignored; can express `permissionDecision` | No | Mostly | Yes, but see the non-interactive trap in §G. |
| `PermissionDenied` | No | No | No | Observe + `retry: true` | Yes (inference). |
| `Stop` | **Yes** — `additionalContext` is "non-error feedback delivered to the model; the conversation continues so the model can act on it" (verbatim from binary) | **Yes** — exit 2, or `decision:"block"` + `reason`, or `continue:false` | No | — | Not for subagents — a subagent's `Stop` becomes `SubagentStop`. |
| `SubagentStop` | **Yes** — `additionalContext` is "non-error feedback delivered to the subagent; the subagent continues so it can act on it" (verbatim from binary) | **Yes** — exit 2 prevents the subagent from stopping | No | — | **Yes, that is its whole job.** Matcher = agent type. Input carries `last_assistant_message`. |
| `TeammateIdle` | Presumed (`reason` fed back) | **Yes** — `continue:false` | No | — | Agent-team teammates. |
| `TaskCreated` | — | **Yes** — exit 2 rolls back creation | No | — | Fires on `TaskCreate`. |
| `TaskCompleted` | — | **Yes** — exit 2 prevents marking complete | No | — | Fires on `TaskUpdate` completion. |
| `PreCompact` | — | **Yes** — exit 2 blocks compaction | No | — | Unverified for subagents. |
| `PostCompact` | — | No | No | Yes | Unverified. |
| `Notification` | — | No | No | Yes | n/a |
| `MessageDisplay` | — | No | No | Yes (10s timeout) | Unverified. |
| `SessionEnd` | — | No | No | Yes (1.5s shared budget) | No. |
| `StopFailure` | — | No | No | Yes | — |
| `InstructionsLoaded` | — | No | No | Yes — **fires when a CLAUDE.md or `.claude/rules/*.md` is loaded** | Unverified. |
| `ConfigChange` | — | **Yes** — exit 2 blocks the change (except `policy_settings`) | No | — | n/a |
| `CwdChanged`, `DirectoryAdded`, `FileChanged` | — | No | No | Yes | — |
| `WorktreeCreate` | — | **Yes** — any non-zero exit fails creation | No | — | Fires on subagent worktree isolation. |
| `WorktreeRemove` | — | No | No | Yes | Fires when a subagent finishes, per the guide's event table. |
| `Setup` | — | No | No | Yes | n/a |
| `Elicitation` / `ElicitationResult` | — | Yes | No | — | MCP only. |

Docs enumerate **28 events** (`https://code.claude.com/docs/en/hooks`).

**Three shapes of hook handler**, all usable at any event:

- `type: "command"` — shell, stdin JSON, stdout JSON. Default timeout 600s
  (`UserPromptSubmit` 30s, `MessageDisplay` 10s).
- `type: "prompt"` — a single-turn LLM call (Haiku by default, `model`
  overridable) that returns `{"ok": bool, "reason": str}`. Default timeout 30s.
- `type: "agent"` — **experimental**; spawns a subagent with tool access, up to
  50 tool-use turns, 60s default. Returns the same `ok`/`reason` shape.
- Also `type: "http"` (POST to an endpoint; response body carries the same JSON)
  and `type: "mcp_tool"`.

The `prompt` and `agent` types matter enormously for this exploration: they let
a hook make a *judgment* call ("did this agent actually delegate, or did it
implement inline?") rather than a string match. Verbatim from the guide:

> When verification requires inspecting files or running commands, use
> `type: "agent"` hooks. Unlike prompt hooks, which make a single LLM call,
> agent hooks spawn a subagent that can read files, search code, and use other
> tools to verify conditions before returning a decision.

The worked example in the official guide is *exactly* our shape:

> ```json
> { "hooks": { "Stop": [ { "hooks": [ { "type": "prompt",
>   "prompt": "Check if all tasks are complete. If not, respond with
>   {\"ok\": false, \"reason\": \"what remains to be done\"}." } ] } ] } }
> ```

---

### B. Which hooks can DENY, and what the agent actually sees

**Two independent block mechanisms**, and the difference matters:

1. **Exit code 2.** Blocks on blockable events; stderr is the reason. Where the
   reason lands is per-event: some events feed it to Claude as steerable
   feedback, some show it only to the user, a few surface nothing. Exit 2
   *overrides* any JSON on stdout — a hook that exits 2 while printing
   `permissionDecision: "allow"` still blocks.
2. **Exit 0 + JSON decision.** The intended pattern. For `PreToolUse`:
   `hookSpecificOutput.permissionDecision` ∈ `allow | deny | ask | defer`
   (`defer` is in the binary's enum alongside the other three), with
   `permissionDecisionReason` carrying the text.

**Is the denial reason steerable feedback the model can act on?** For
`PreToolUse` with `permissionDecision: "deny"`, **yes** — verbatim from the
guide:

> With `"deny"`, Claude Code cancels the tool call and feeds
> `permissionDecisionReason` back to Claude.

This is the load-bearing property for a corrective gate. Our own
`shirabe pr-body-hook` relies on it exactly this way
(`public/shirabe/crates/shirabe/src/pr_body_hook.rs:20-22`): "it **denies** the
tool call and returns the findings as the decision reason, so the agent sees
what to fix and re-issues a corrected command."

**But there is a version-sensitive trap for `prompt`/`agent` hooks.** Verbatim
from the guide, on `"ok": false`:

> `PreToolUse`: the tool call is denied; by default the turn ends and the deny
> `reason` appears in the chat as a warning line. Set `continueOnBlock: true`
> on the hook to instead return the `reason` to Claude as the tool error, so it
> can adjust and continue. **Before v2.1.210, the deny `reason` was returned to
> Claude as the tool error and the turn continued.**

So a `type: "prompt"` `PreToolUse` gate written today **kills the turn by
default** and the agent never sees the reason. `continueOnBlock: true` is
mandatory for any corrective (as opposed to terminal) prompt-hook gate. Agent
hooks have no `continueOnBlock` field and behave as if it were always true.

**Where the reason is NOT steerable:**

- `UserPromptSubmit` exit 2 — "blocks prompt processing and erases the prompt."
  The model sees nothing. This is a hard stop, not a correction.
- `SessionStart`, `SubagentStart` exit 2 — stderr to user only; execution
  continues regardless. **These events cannot block.**
- `PostToolBatch`, `UserPromptSubmit`, `UserPromptExpansion` prompt-hook
  `ok:false` — "the turn ends and the `reason` appears in the chat as a warning
  line."

**Where it IS steerable, and this is the important one for us:**

- `Stop` / `SubagentStop`. From the binary's own schema descriptions:
  > "Hook-specific output for the Stop event. `additionalContext` is non-error
  > feedback delivered to the model; the conversation continues so the model can
  > act on it."
  > "Hook-specific output for the SubagentStop event. `additionalContext` is
  > non-error feedback delivered to the subagent; the subagent continues so it
  > can act on it."
- `Stop` / `SubagentStop` prompt hooks: "the `reason` is fed back to Claude so
  it keeps working, unless the response also sets `"impossible": true`", in
  which case the stop is allowed and the turn ends. The `impossible` escape
  hatch is the anti-infinite-loop valve.

Local precedent for the softer version:
`/home/dgazineu/dev/niwaw/tsuku/tsuku+execute_and_work_on_trigger-d36b0bbf/.claude/hooks/stop/workflow-continue.sh`
emits `{"decision":"block","reason":"..."}` on `Stop` when a `wip/*-state.json`
still has incomplete issues, and the reason text deliberately grants the agent
an out ("If you're intentionally stopping ... go ahead") to avoid a loop.

---

### C. Injecting content the model treats with high authority

**The mechanism is `hookSpecificOutput.additionalContext`.** Confirmed in the
binary: the string `additionalContext` is validated as a `hookSpecificOutput`
key, and the binary carries a literal user-facing error string
`"Did you mean hookSpecificOutput.additionalContext (with a hookEventName)?"` —
i.e. a top-level `additionalContext` is a known and warned-about mistake on some
events. The binary also groups `SessionStart`, `UserPromptSubmit`, and
`UserPromptExpansion` together next to `additionalContext`, matching the docs'
statement that those three (plus `UserPromptExpansion`) are the events where
**plain-text stdout on exit 0** is also injected:

> For most events, stdout is written to the debug log but not shown in the
> transcript. The exceptions are `UserPromptSubmit`, `UserPromptExpansion`, and
> `SessionStart`, where Claude Code adds plain-text stdout as context that
> Claude can see and act on.

**The `<EXTREMELY_IMPORTANT>` wrapper is not a harness feature.** It is plain
text a plugin chooses to put inside `additionalContext`. The workspace
injection referenced in the brief is superpowers' `SessionStart` hook, at
`/home/dgazineu/.claude/plugins/cache/claude-plugins-official/superpowers/6.2.0/hooks/session-start`:

```bash
session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n**Below is the
full content of your 'superpowers:using-superpowers' skill - your introduction
to using skills. For all other skills, use the 'Skill' tool:**\n\n${...}\n</EXTREMELY_IMPORTANT>"
...
printf '{\n  "hookSpecificOutput": {\n    "hookEventName": "SessionStart",\n
  "additionalContext": "%s"\n  }\n}\n' "$session_context"
```

Registered at `hooks/hooks.json` with `"matcher": "startup|clear|compact"` and
`"async": false`.

**The hard limit on authority.** Verbatim from the guide's Limitations section:

> Text returned via `additionalContext` is injected as a **system reminder that
> Claude reads as plain text**.

That is the ceiling. `additionalContext` is a system-reminder-class message —
above ordinary tool output, below an actual user/session instruction. It does
**not** get the precedence of a session-level instruction. This is directly
material to the second incident in the brief: an agent that resolved
"do not call the AgentTool unless the user requested it" against koto's
`spawn_and_await` would resolve it the same way against an `additionalContext`
nudge, because the nudge sits *below* the session instruction in the same
precedence order that produced the miss. **Injection alone cannot win a
precedence conflict against a session instruction.** Only a hard block can.

Other limits:

- No formatting privilege. XML tags like `<EXTREMELY_IMPORTANT>` are just
  characters; their effect is prompt-engineering, not enforcement.
- Composition: "Text from `additionalContext` is kept from every hook and passed
  to Claude together." Multiple injectors do not conflict, they concatenate.
- Size is observable but apparently uncapped — the binary emits telemetry
  counters `additionalContextChars`, `systemMessageChars`,
  `initialUserMessageChars`, and a log line `") provided additionalContext ("
  … " chars)"`. No hard limit string was found. **Open question** whether an
  oversized injection is truncated.
- `systemMessage` is a *different* field and goes to the **user**, not the
  model.
- Untrusted-content discipline: shirabe's own injector
  (`crates/shirabe/src/work_summary.rs:1073-1077`) wraps injected content in a
  128-bit random nonce fence with the preamble
  `"Auto-generated snapshot of this session's tracked pull requests (data, not
  instructions):"`. If we inject policy text, we are on the *other* side of that
  convention — it is instructions, not data — and should not reuse the
  data-fence shape.

**`SubagentStart` can inject too**, per the docs:
`hookSpecificOutput.additionalContext` — "Text to inject into the subagent's
context at startup", matchable on agent type. **Flagged as doc-only**: I could
not confirm the field on `SubagentStart` specifically in the binary within
budget (a broad context extraction around `SubagentStart` timed out). Verify
empirically before designing on it — it is the single most useful surface in
this whole inventory for reaching dispatched workers.

---

### D. Can `UserPromptSubmit` rewrite a bare `/execute foo`?

**Rewrite: yes, but not the way you'd hope.** The field is
`hookSpecificOutput.updatedInput` — "Transformed prompt to send to Claude
instead of the original" (docs), and `updatedInput` is present 82× in the 2.1.233
binary. It is *not* `updatedPrompt`. So `UserPromptSubmit` can, in principle,
replace `"/execute foo"` with `"Invoke the shirabe:execute skill on foo. …"`.

**Four constraints that bound this heavily:**

1. **Slash-command expansion may not be a `UserPromptSubmit` prompt at all.**
   There is a *separate* event, `UserPromptExpansion`, described as firing "when
   a slash command expands into a prompt". Which of the two sees a bare
   `/execute` — and in what order — is unresolved here and is the single most
   important thing to pin down empirically before designing on this path. It
   also directly touches the sibling lead's finding about the
   plugin-enumeration race: if `/execute` fails to resolve as a command, it
   presumably arrives at `UserPromptSubmit` as literal text, which is exactly
   the condition a rewrite hook could detect and repair.
2. **A rewrite hook cannot invoke the skill.** Verbatim from the guide's
   Limitations: hooks "can't trigger `/` commands or tool calls." A rewrite can
   only produce *text instructing* the model to invoke the skill. The model
   still chooses.
3. **Append is the safer sibling.** `additionalContext` on the same event adds
   text "before the prompt" without touching the user's words, and is what
   shirabe already does (`work_summary.rs:1204`, `cmd_absence` emits
   `UserPromptSubmit` `additionalContext`).
4. **30-second timeout** on `UserPromptSubmit` (lowered from the 600s default),
   and it fires on **every** prompt with **no matcher support**. Any work done
   here is on the critical path of every single turn.

**It does not reach dispatched agents.** `niwa dispatch` composes a worker
prompt programmatically; a worker's initial task is not a user prompt typed into
a session, so `UserPromptSubmit` is the wrong surface for the dispatch half of
the requirement. `SessionStart` and `SubagentStart` are the surfaces that reach
workers.

---

### E. What `settings.json` expresses beyond hooks

**`permissions.deny` as a blocking gate — real, but blunt and mute.**

- Rules evaluate **deny → ask → allow**; first match wins; specificity does not
  reorder. A broad deny cannot carry allowlist exceptions.
- A **bare tool name** deny (`"Bash"`, or a glob like `"mcp__*"`) **removes the
  tool from Claude's context entirely — Claude never sees it.** A **scoped**
  rule (`"Bash(rm *)"`) leaves the tool visible and blocks matching calls.
- **`Agent(...)` rules exist**: `"deny": ["Agent(Explore)"]` disables a specific
  subagent type. So the Agent tool is deny-rule-addressable by agent type.
- File rules are checked against `Edit(path)` and `Read(path)` **only**. A
  `Write(...)` / `NotebookEdit(...)` / `Glob(...)` path rule is accepted, never
  consulted, and warned about at startup. A `Read` deny also blocks Edit/Write
  on that path (v2.1.208+/v2.1.228+). **A blocking gate on file writes must be
  written as `Edit(<glob>)`, not `Write(<glob>)`.**
- **What the agent experiences: no steerable reason.** Nothing in the
  permissions doc describes feeding a rule's rationale back to the model — a
  deny rule is a static config line with no message field. Contrast with a
  `PreToolUse` hook deny, which explicitly feeds `permissionDecisionReason`
  back. **For a corrective gate, hooks beat permission rules outright.** For an
  unbypassable prohibition, permission rules (especially managed ones) beat
  hooks.
- **Hooks and rules compose, restrictively.** Verbatim: "Hook decisions don't
  bypass permission rules… a matching deny rule blocks the call, and a matching
  ask rule still prompts even when the hook returned `"allow"`." And in the
  other direction: "A hook that exits with code 2 stops the tool call before
  permission rules are evaluated." Also: "Hooks can tighten restrictions but not
  loosen them past what permission rules allow."

**`PreToolUse` beats every permission mode.** This is the strongest enforcement
statement in the docs and it is worth quoting in full:

> `PreToolUse` hooks fire before any permission-mode check, in every permission
> mode, including `dontAsk`. A hook that returns `permissionDecision: "deny"`
> blocks the tool even in `bypassPermissions` mode or with
> `--dangerously-skip-permissions`. This lets you enforce policy that users
> can't bypass by changing their permission mode.

This directly matters here: the live workspace runs
`"permissions": {"defaultMode": "bypassPermissions"}`
(`.../tsuku+execute_and_work_on_trigger-d36b0bbf/.claude/settings.json`), and
niwa's `gate-online.sh` hook comment already records the reasoning — "Works in
bypassPermissions mode because hooks are external to the permission system."

**Other settings-level levers:**

- `env` — arbitrary env vars injected into the session and into hook
  subprocesses. shirabe already uses this pattern for kill switches
  (`PR_BODY_HOOK_DISABLE=1`, the `WS_*` seams). *(Note: the live workspace
  `settings.json` currently carries a plaintext GitHub PAT in `env`. Out of
  scope for this lead, but worth someone's attention.)*
- `outputStyle` — not researched in depth; it changes the system prompt's
  presentation layer, not tool authorization. Unlikely to be an enforcement
  surface.
- `disableAllHooks: true` — see §F.
- `includeGitInstructions`, `defaultMode`, `enabledPlugins`,
  `extraKnownMarketplaces` — all present in the live workspace file.
- **Managed policy settings** are the org-owner surface: `allowManagedHooksOnly`
  (only managed + force-enabled plugin hooks run) and
  `allowManagedPermissionRulesOnly` (user/project settings cannot define
  allow/ask/deny at all). "No other level, including command line arguments, can
  override a managed permission rule."

---

### F. Composition across the settings hierarchy — who wins?

**Hooks merge; they do not replace.** Verbatim:

> Hook entries merge across settings levels rather than replacing each other:
> user, project, and local settings add their own hooks without removing managed
> ones.

Duplicate identical handlers are deduplicated to a single run; plugin, skill,
and subagent copies stay separate. Sources: `~/.claude/settings.json`,
`<project>/.claude/settings.json`, `.claude/settings.local.json`, managed policy
settings, plugin `hooks/hooks.json`, **skill frontmatter**, **subagent
frontmatter**.

**So a repo-level settings file cannot remove a niwa-written instance hook by
declaring its own hooks.** The two both run. niwa's own materializer is written
to the same contract and merges rather than overwrites — see
`public/niwa/internal/workspace/materialize.go:872-883`, whose comment spells out
why: "Merge, do not overwrite: an installed hook registered on the session_start
event … already built a SessionStart block above … A plain assignment here would
silently drop that installed hook."

**But a repo CAN disable everything.** Verbatim:

> To disable hooks, set `"disableAllHooks": true` in your settings file. Claude
> Code reads the value left after settings precedence applies, **so a project's
> settings file can override yours.** Hooks configured in managed settings still
> run unless `disableAllHooks` is also set there.

So the answer to "who wins" is layered:

| Layer | Can add hooks | Can remove another layer's hooks |
|---|---|---|
| Managed policy | Yes | Yes — `disableAllHooks` there kills managed hooks too; `allowManagedHooksOnly` kills everyone else's |
| Project `.claude/settings.json` | Yes | Yes, via `disableAllHooks` — beats user settings |
| User `~/.claude/settings.json` | Yes | Only its own layer and below |
| Local `.claude/settings.local.json` | Yes | Presumably highest non-managed precedence (inference) |
| Plugin `hooks/hooks.json` | Yes, while enabled | No |
| Skill frontmatter | Yes, **for the rest of the session** once invoked (`once: true` for single-shot) | No |
| Subagent frontmatter | Yes, while that subagent runs; a `Stop` here becomes `SubagentStop` | No |

**Skill frontmatter hooks are a sleeper finding for this exploration.** A skill
can register hooks *that persist for the rest of the session after it is
invoked* — "on turns after the skill's own turn as well." That means
`shirabe:execute` could register its own `PreToolUse` / `Stop` conformance gate
at the moment it fires, with zero workspace configuration and zero niwa
involvement. It is the only surface in this inventory that is (a) enforcement-
grade, (b) scoped precisely to the workflow it governs, and (c) shippable inside
the shirabe plugin itself.

**Cloud sessions** (`claude-code-on-the-web`) do not read
`~/.claude/settings.json` — only repo and managed settings apply.

---

### G. Subagents and background sessions — the critical question

**Tool events fire for subagents. This is explicit and unambiguous:**

> Hooks from settings files, managed policy settings, and plugins also run
> inside subagents. When a subagent calls a tool, tool events such as
> `PreToolUse` and `PostToolUse` fire the same configured hooks as in the main
> conversation, and the input carries the `agent_id` and `agent_type` common
> input fields that identify the subagent.

So **yes**: a `PreToolUse` hook sees `Edit`/`Write` from a spawned subagent, and
can tell it is a subagent (and which one) from `agent_id` / `agent_type`.

**`SessionStart` `additionalContext` does NOT reach subagents.** A subagent is
not a session; `SessionStart` fires once per session with matchers
`startup|resume|clear|compact|fork`. The per-subagent analog is `SubagentStart`,
which per the docs supports `additionalContext` "to inject into the subagent's
context at startup" and matches on agent type. **This is the surface for
reaching subagents with policy text.** (Doc-only; verify.)

Practical consequence: the superpowers `<EXTREMELY_IMPORTANT>` skill injection
reaches the *main* session only. Any subagent it spawns starts without it.

**Background / non-interactive sessions.** Hooks fire, but there is a sharp edge
that will bite `niwa dispatch` workers:

> Background subagents can't show a prompt in non-interactive mode. Claude Code
> still runs the hooks for their tool calls, and **if no hook returns a
> decision, it denies the call.** In an interactive session, background subagent
> prompts surface in your main session and the hooks fire as usual.

And:

> `PermissionRequest` hooks fire when Claude Code is about to ask you for
> permission. In non-interactive mode with the `-p` flag, that prompt only
> exists when the Agent SDK's `canUseTool` callback supplies it. In plain `-p`
> runs or with `--permission-prompt-tool`, use `PreToolUse` hooks for automated
> permission decisions instead.

**Read: `permissionDecision: "ask"` is not a usable outcome in a background
worker.** It becomes an effective deny. Any gate we ship must decide
allow-or-deny outright in non-interactive contexts. niwa's existing
`gate-online.sh` uses `"ask"` for `gh release create` etc., which in a
background dispatched worker would silently harden into a deny.

---

### H. Can a hook detect a PRECEDENCE CONFLICT, or the ABSENCE of expected activity?

This is the question the second incident forces, and the honest answer splits.

**Absence detection: yes, and we already ship one.**
`shirabe work-summary absence` is literally an absence detector: a
`UserPromptSubmit` hook that fires on every prompt, compares elapsed time against
a threshold, and injects a summary when the session has been idle with a
non-empty ledger (`crates/shirabe/src/work_summary.rs:1022-1032`, `1186-1207`).
niwa installs it by default for shirabe adopters
(`materialize.go:504-508`, `workSummaryHookDefaults`).

The general pattern generalizes to our problem. Absence is observable at:

- **`Stop`** — the natural checkpoint. The agent is *trying to finish*. A `Stop`
  hook can read the transcript (`transcript_path` is a common input field), or
  read on-disk state, and ask: did a koto session get created? Was any
  `spawn_and_await` issued? Was `plan-to-tasks.sh` output ever submitted? If
  not, block the stop and feed the reason back as steerable
  `additionalContext`. This is exactly the shape of the existing
  `workflow-continue.sh` and of the official docs' own `Stop`-prompt-hook
  example.
- **`SubagentStop`** — same, one level down, with `last_assistant_message`
  supplied as input.
- **`TeammateIdle`** — same, for agent-team teammates, and blockable.
- **`TaskCompleted`** — blockable; a task cannot be marked complete if the
  expected artifact does not exist.
- **`PostToolBatch`** — blockable mid-loop, before the next model call: catches
  a drift-into-inline-implementation *during* the run rather than at the end.
- **Positive-signal absence via `PreToolUse`**: a gate that sees the Nth `Edit`
  to `src/**` in a session where no koto session was ever created can deny with
  a reason. This is inverted absence — detect the *substitute* activity rather
  than the missing activity.
- **`type: "agent"` hooks** make all of the above judgment-capable rather than
  string-matching: an agent hook on `Stop` can read files, grep the repo, and
  check koto state before answering.

**Precedence-conflict surfacing: no direct surface, but a strong indirect one.**
No hook event fires on "the model resolved an instruction conflict." Nothing
observes reasoning. But the *consequence* is observable, and observing the
consequence is enough:

- The conflict in the incident resolved as "spawn no subagents." That is an
  absence of `SubagentStart` / `Agent` tool calls — detectable at `Stop` by
  reading the transcript, or continuously by a counter.
- More precisely: `SubagentStart` fires per subagent with
  `parent_agent_id` / `parent_agent_type`. A gate can assert "a session in which
  `/execute` fired must have spawned ≥1 `work-on` child before it may stop."
- **The cleanest structural fix is not detection at all.** The conflict existed
  because a session-level instruction and a skill both spoke, and the skill
  lost. A `PreToolUse` deny outranks *both* — it fires before permission-mode
  checks, cannot be talked out of, and feeds a reason the model must act on. A
  policy expressed as a hook is not in the precedence order the model
  arbitrates; it is outside it. Conversely, a policy expressed as injected
  `additionalContext` **is** in that order, and sits below the session
  instruction that already won once.

---

### I. Local precedent: what niwa and shirabe already ship

The brief is right that this is the working precedent, and it is closer to a
template than an analogy.

**niwa injects four hooks by default into any instance whose effective config
installs the shirabe plugin** (`public/niwa/internal/workspace/materialize.go`):

| Hook | Event | Matcher | Command |
|---|---|---|---|
| pr-body gate | `PreToolUse` | `Bash` | `command -v shirabe >/dev/null 2>&1 \|\| exit 0; shirabe pr-body-hook 2>/dev/null \|\| exit 0` |
| work summary capture | `PostToolUse` | `Bash` | `… exec shirabe work-summary capture` |
| work summary absence | `UserPromptSubmit` | — | `… exec shirabe work-summary absence` |
| work summary compact | `SessionStart` | `compact` | `… exec shirabe work-summary compact` |

Structural properties worth copying wholesale:

- **Gate on plugin adoption, not on provisioning.** `installsShirabePlugin()`
  matches the plugin name before `@marketplace`, so both `shirabe@shirabe` and a
  bare `shirabe` qualify (`materialize.go:521-536`). "The ambient summary travels
  with shirabe adoption rather than with every provisioned instance."
- **Default-on with a `[claude]`-table off switch.** `pr_body_hook = false` /
  `work_summary_hooks = false`; a nil pointer means on
  (`materialize.go:538-546`, `608-616`; `internal/config/config.go:54`).
- **Dedup against a workspace's own declaration** by grepping the materialized
  hook scripts for a marker string (`workSummaryModeInstalled`,
  `prBodyHookInstalled`) so the default never double-registers.
- **Inline commands, no script files.** Every injected hook is a one-liner with a
  `command -v shirabe` guard, making it a fail-safe no-op wherever the binary is
  absent.
- **Append, never assign.** Every injection appends to the existing event block
  (`materialize.go:818-822`, `843-847`, `879-883`).
- **A `PreToolUse` hook must not exec and must swallow non-zero.** The comment at
  `materialize.go:592-606` is the sharpest operational lesson in the codebase:
  > "Unlike the work-summary PostToolUse pass-through it must NOT `exec` and must
  > swallow a non-zero exit: a PreToolUse hook that exits non-zero BLOCKS the
  > tool call, and this hook matches every Bash command. An outdated shirabe that
  > predates the `pr-body-hook` subcommand exits non-zero on the unknown
  > subcommand."

**The shirabe side** (`crates/shirabe/src/pr_body_hook.rs`) is the reference
adapter shape: reads hook JSON on stdin, **always exits 0**, expresses a block as
`hookSpecificOutput.permissionDecision: "deny"` with the findings as
`permissionDecisionReason`, fails **open** on every ambiguity (unparseable stdin,
unreadable `--body-file`, `--fill`/`--web`, command substitution), never
shell-evaluates the command, assembles the reason with `serde_json` so
attacker-controlled text cannot escape into a terminal control sequence, and
carries an env kill switch (`PR_BODY_HOOK_DISABLE=1`).

Its design rationale is verbatim the argument this exploration needs
(`references/pr-body-conformance.md:13-20`):

> "PR-template conformance used to be stated inline in `/execute`'s
> `pr_finalization` state and `/work-on`'s PR phase … Two statements of one rule
> drift, **and a PR opened off the skill path (a manual `gh pr create`, a
> dispatched worker) saw neither.** Moving the mechanical rule into the validator
> and pointing every consumer here makes conformance **a property of the repo —
> a path-independent CI gate enforces it — rather than a property of whichever
> code path opened the PR.**"

That is precisely the reframing skill-adherence needs: make workflow conformance
a property of the repo, not of whether the agent chose the skill.

---

### J. Practical failure modes

**Latency.** `command`/`http`/`mcp_tool` default to 600s; `UserPromptSubmit`
drops to 30s and `MessageDisplay` to 10s; `prompt` hooks 30s; `agent` hooks 60s;
`SessionEnd` hooks share a **1.5-second** budget (raised to a per-hook `timeout`
up to 60s max). A `UserPromptSubmit` hook is on the critical path of every turn
and has no matcher to narrow it. A `PreToolUse` `Bash` hook is on the critical
path of every shell command — niwa already stacks two there (`gate-online.sh` +
`pr-body-hook`). An `agent`-type hook on `Stop` is the most expensive option in
this inventory (a full subagent, up to 50 tool turns) and should be gated hard
on cheap preconditions before it runs.

**Silent failure.** This is the dominant risk and the codebase already knows it:

- Exit 0 with **invalid JSON** = non-blocking error, action proceeds. A hook with
  a typo'd field name fails open and silently.
- Top-level `additionalContext` on an event expecting the nested form is
  **silently ignored** — verbatim: "Nest `additionalContext` inside
  `hookSpecificOutput`; if you place it at the top level of the JSON, Claude Code
  silently ignores it." The superpowers hook emits three different shapes
  depending on host precisely because of this.
- Non-zero exit on a **non-blockable** event just logs.
- `shirabe pr-body-hook` fails open on *every* ambiguity by design, accepting CI
  as the backstop. Any adherence gate needs an equivalent named backstop, or it
  must fail closed.
- `Write(...)`/`Glob(...)` path permission rules are accepted and never
  consulted (startup warning only). Easy to write a gate that does nothing.
- The `if:` pre-filter on tool hooks is **best-effort** and explicitly fails
  open: "The filter also fails open, running your hook regardless of pattern,
  when the Bash command can't be parsed. Because the filter is best-effort, use
  the permission system rather than a hook to enforce a hard allow or deny."

**Bypass routes an agent could take.**

- **Route around the matcher.** A `PreToolUse` matcher on `Edit|Write` does not
  see `python -c "open(...).write(...)"`. Verbatim from the permissions doc:
  Read/Edit deny rules "don't apply to arbitrary subprocesses that read or write
  files indirectly, like a Python or Node script that opens files itself." OS-level
  enforcement requires `sandbox` settings.
- **`disableAllHooks` in a project settings file** beats user settings. Only
  managed settings are immune.
- **Kill switches we ship ourselves**: `PR_BODY_HOOK_DISABLE=1`,
  `[claude] pr_body_hook = false`, `work_summary_hooks = false`. An agent with
  Edit access to `.niwa/workspace.toml` or the ability to set an env var can
  disable the gate. (Whether that is a bug or a feature is a design call, but it
  should be a deliberate one.)
- **Stale binary → fail open.** `command -v shirabe || exit 0` plus
  `|| exit 0` means an instance without shirabe on PATH, or with a version
  predating the subcommand, silently has no gate.
- **`impossible: true`** on a `Stop` prompt hook lets the model assert the
  condition can never be satisfied and stop anyway. That is the intended
  anti-loop valve and also the intended-by-design escape hatch.
- **Non-deterministic `updatedInput` collisions**: "When multiple `PreToolUse`
  hooks return `updatedInput` … the last one to finish takes effect. Since hooks
  run in parallel, the order is non-deterministic."
- **`PreToolUse` composition is restrictive-wins**, which is on our side: "For
  `PreToolUse` permission decisions, the most restrictive answer applies, in the
  order `deny`, `defer`, `ask`, `allow`."

---

## Implications

**1. Injection cannot solve the second incident; only blocking can.** The
precedence order that produced the miss — session instruction outranks skill —
also outranks `additionalContext`, which the harness delivers as a system
reminder "Claude reads as plain text." A `SessionStart` injection wrapped in
`<EXTREMELY_IMPORTANT>` raises the odds and changes nothing structural. A
`PreToolUse` deny is not in that order at all: it fires before permission-mode
checks, survives `bypassPermissions`, and returns a reason the agent must act on.
Any design whose enforcement leg is "inject stronger words" will reproduce the
failure.

**2. `Stop` is the natural place to enforce a workflow, and `PreToolUse` is the
natural place to enforce an action.** `Stop`/`SubagentStop` are the only events
that both (a) block and (b) deliver the reason as steerable non-error feedback
that continues the conversation. That is exactly the semantics of "you ran
`plan-to-tasks.sh` but never submitted it to koto — do that before you finish."
`PreToolUse` is where "you are about to hand-edit issue 4's files without a koto
session" gets caught.

**3. Skill frontmatter hooks may collapse the distribution problem entirely.** A
skill can register hooks that persist for the rest of the session once invoked.
If `shirabe:execute` carries its own `Stop` conformance gate in frontmatter, the
policy ships with the plugin, needs no niwa change, no workspace settings, no
org-owner action, and is scoped to sessions where `/execute` actually fired. This
should be evaluated head-to-head against the niwa-injection path before either
is chosen. Its weakness is the obvious one: it only fires *after* the skill is
invoked, so it does nothing about an agent that never reached for the skill.

**4. Reaching dispatched workers is a different surface from reaching a human's
session.** `UserPromptSubmit` covers the human typing `/execute` and does not
exist for a worker. `SessionStart` covers a worker's own session but not the
subagents it spawns. `SubagentStart` covers those. A design that must work for
both needs at least two injection points, or it needs to move enforcement to
tool events, which fire uniformly everywhere.

**5. `ask` is a deny in background workers.** Any decision surface must resolve
to allow-or-deny in non-interactive mode. This retroactively affects the existing
`gate-online.sh` `ask` branch inside dispatched instances.

**6. The niwa injection contract is a solved distribution problem we should
reuse verbatim.** Plugin-adoption gate, default-on with a `[claude]` off switch,
marker-based dedup, inline `command -v`-guarded one-liners, append-never-assign,
always-exit-0 adapters that express blocks as JSON. Every one of those decisions
has a comment in `materialize.go` explaining the failure it prevents.

**7. Judgment-shaped conformance is now expressible without writing a
classifier.** `type: "prompt"` and `type: "agent"` hooks mean the gate can ask a
model "did this session actually delegate the plan, or did it implement inline?"
The docs' own flagship `Stop` example is that question. Cost and the
`continueOnBlock`/`impossible` semantics are the design constraints, not
feasibility.

---

## Surprises

- **`updatedPrompt` and `expandedPrompt` do not exist.** A documentation
  summarization pass asserted both confidently; neither string appears anywhere
  in the installed 2.1.233 binary, while `updatedInput` appears 82 times. Anyone
  designing from a doc summary rather than the binary would have built on a
  field that does not exist.
- **`Stop` and `SubagentStop` support `additionalContext`, and the binary's own
  schema strings say it is delivered as non-error feedback with the conversation
  continuing.** This is a much better surface than the `decision:"block"` shape
  our existing `workflow-continue.sh` uses, and it was not obvious from the docs
  index.
- **Skill frontmatter can register hooks that outlive the skill's turn.** Not
  mentioned anywhere in the brief, and potentially the whole answer.
- **`SubagentStart` exists and takes `additionalContext`.** A per-subagent
  injection point aimed by agent type, which is precisely the missing piece for
  reaching `spawn_and_await` children.
- **`PreToolUse` deny survives `bypassPermissions` and
  `--dangerously-skip-permissions`, by explicit design** — "This lets you enforce
  policy that users can't bypass by changing their permission mode." In a
  workspace that runs `defaultMode: bypassPermissions`, this is the *only*
  enforcement surface that still holds.
- **In non-interactive background subagents, a tool call with no hook decision is
  denied**, not allowed. The default flips.
- **`"deny": ["Agent(Explore)"]`** — subagent types are permission-rule
  addressable. A negative lever exists on delegation; no positive "must delegate"
  lever does.
- **28 hook events.** The brief listed nine; the surface is three times larger,
  and several of the useful ones (`SubagentStart`, `TaskCompleted`,
  `PostToolBatch`, `InstructionsLoaded`, `TeammateIdle`) were not on the list.
- **`InstructionsLoaded` fires when a CLAUDE.md or `.claude/rules/*.md` loads.**
  Observe-only, but it means the harness knows which instruction files entered a
  session — potentially useful for detecting *which* session constraint is in
  play during a precedence conflict.

---

## Open Questions

1. **Does `SubagentStart.additionalContext` actually work?** Doc-only in my
   evidence; the binary confirmation timed out. This is the highest-value
   unverified claim in the report. Test: a `SubagentStart` hook emitting a
   distinctive token, then a subagent asked to echo it.
2. **Which event sees a slash command — `UserPromptSubmit`, `UserPromptExpansion`,
   or both, and in what order?** Determines whether the bare-`/execute` repair
   path is viable at all, and interacts with the sibling lead's
   plugin-enumeration-race finding.
3. **Does `UserPromptExpansion` honor `updatedInput`?** `expandedPrompt` is not a
   real field; the replacement field's name on that event is unconfirmed.
4. **Is `additionalContext` size-capped or truncated?** The binary counts
   `additionalContextChars` but no limit string surfaced.
5. **Do `PreCompact` / `PostCompact` fire inside a subagent that compacts?**
   Matters for whether a policy injection survives a long worker run.
6. **Exactly how much of the transcript can a `Stop` hook cheaply inspect?**
   `transcript_path` is supplied, but reading and analyzing a long JSONL on every
   `Stop` has a real cost. Is a `type: "agent"` hook cheaper in practice than a
   command hook that parses the transcript itself?
7. **Cost and latency of `prompt` / `agent` hooks in practice.** No measurements
   taken. An `agent` hook on `Stop` firing on every turn-end could be
   prohibitive.
8. **Can a hook read koto session state cheaply enough to assert "a koto session
   exists for this plan"?** This is the concrete absence predicate the second
   incident needs, and it depends on the koto-observability lead's findings.
9. **Should the org-owner policy live in managed policy settings?** That is the
   only layer a project `disableAllHooks` cannot defeat, and the brief's
   "declarable as workspace policy by an org owner" requirement points at it —
   but it also removes the escape hatch entirely. Not researched: how managed
   settings are distributed in this workspace, if at all.
10. **Does the existing `gate-online.sh` `ask` branch silently deny inside
    dispatched workers today?** Follows directly from §G and is testable now.

---

## Summary

Claude Code exposes 28 hook events; the ones that matter here split cleanly into
**inject-only** (`SessionStart`, `SubagentStart`, `UserPromptSubmit` — all
delivering text as a system reminder the model reads as *plain text*, which sits
*below* a session instruction in the precedence order that caused the second
incident) and **blocking with steerable feedback** (`PreToolUse` deny, which
fires before every permission-mode check and survives `bypassPermissions`, and
`Stop`/`SubagentStop`, whose `additionalContext` the binary describes as
"non-error feedback delivered to the model; the conversation continues so the
model can act on it"). The main implication is that no amount of stronger
injection can fix an agent that resolved a precedence conflict against a skill —
a hook block is outside that order and is the only mechanism that wins — while
absence of expected activity (no koto session, no subagent spawned) is cleanly
detectable at `Stop`/`SubagentStop`/`TaskCompleted`, and tool hooks fire
uniformly inside subagents and background sessions with `agent_id`/`agent_type`
supplied. The biggest open question is whether `SubagentStart.additionalContext`
actually delivers into a spawned subagent's context — it is documented but
unverified, and it is the only surface that reaches `spawn_and_await` children,
so the design's ability to govern dispatched multi-agent work hinges on it.

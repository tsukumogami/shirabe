# Lead: What cadence designs are feasible and least annoying: timer, turn count, or event-driven?

## Findings

All hook mechanics below are verified against the Claude Code hooks reference (https://code.claude.com/docs/en/hooks) and the live workspace config at `/home/dangazineu/dev/niwaw/tsuku/tsuku+always_include_links-fe2fc637/.claude/settings.json`, which already runs a `PreToolUse(Bash)` gate and a `Stop` hook (`.claude/hooks/stop/workflow-continue.sh`) — so the hook-with-state-file pattern is proven infrastructure in this workspace, not hypothetical.

Shared plumbing facts that shape every option:

- Every hook receives `session_id`, `cwd`, and `transcript_path` on stdin, so a per-session state file (counter, last-summary timestamp, PR-set hash) is trivial to key. Plugins get a persistent `$CLAUDE_PLUGIN_DATA` directory, so a shirabe-shipped hook doesn't need to touch `wip/`.
- Hooks inject context to the model via `hookSpecificOutput.additionalContext` (capped at 10,000 chars). Injection point differs by event: `UserPromptSubmit` injects alongside the prompt; `PostToolUse` injects next to the tool result; `Stop` injects at end of turn. All of these are *reminders to the model*, not direct chat output — the model still decides to comply, so every hook option is "soft trigger + instruction" underneath.
- Hooks can ship in the plugin's `hooks/hooks.json` (activates when the plugin is enabled), which answers the "shirabe convention vs niwa-injected" question: both homes are mechanically equivalent; the plugin route is portable, the niwa route is workspace-operator-controlled.

### (a) Turn-count / timer via UserPromptSubmit or Stop + state file

**Sketch.** A `UserPromptSubmit` hook (no matcher support; fires on every prompt) reads `~/.../state-$session_id.json`, increments a turn counter and compares `now - last_summary_ts`. When `count >= N` or `elapsed >= T`, it emits `{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "It has been 42 min since the last work summary and the PR set has changed; emit the standard summary block before addressing this prompt."}}` and resets state.

**Key doc facts.** `UserPromptSubmit` has a reduced 30s default timeout, and — critically — **is not evaluated in non-interactive (`-p`) mode**. So for niwa-dispatched background sessions, this trigger never fires at all. That is arguably correct (nobody is reading the chat live), but it means option (a) is interactive-only by construction.

**Timer vs turn-count are very different UX animals despite sharing an implementation.** Hooks are event-driven, so a "timer" is really "the first user prompt after T minutes elapsed" — which fires precisely when the user returns to a session after being away. That is the single best-aligned moment for a summary ("what was in flight again?"). Turn-count has no such alignment: turn 10 of a rapid back-and-forth about a failing test is the worst possible moment for a PR ledger dump.

**Failure modes.** Stale state files across sessions (mitigate: key by `session_id`, prune on `SessionEnd`); duplicate summaries if the model also self-triggers from instructions (mitigate: state file records a hash of the PR set and the hook only fires when the hash changed since last summary); the model may weave the summary awkwardly into an unrelated answer.

**Annoyance profile.** Timer-on-return: low — fires at a natural re-orientation moment. Turn-count: medium-high — cadence is decoupled from both content changes and user need, and produces "nothing changed since last time" repeats unless gated by a dirty-flag.

### (b) Event-driven: PostToolUse on Bash matching gh pr create / gh pr merge / git push

**Sketch.** Docs confirm two clean ways to match:

1. `matcher: "Bash"` + the hook script grepping `tool_input.command` from stdin JSON.
2. The `if` field with permission-rule syntax: `"if": "Bash(gh pr create *)"` — the docs specify this matching handles leading env assignments, `&&`-chained subcommands, and command substitution, so `cd repo && gh pr create ...` still matches. Multiple hook entries cover create/merge/close/push.

On match, the hook records "PR set dirty" in the state file and injects `additionalContext` next to the tool result: "The PR set changed. Refresh the work ledger and, if it has been >X minutes since the last in-chat summary, post the standard summary block."

**Why this aligns with need.** The summary's content only changes at these events, and the user is already reading PR-related output at that moment — a summary right after `gh pr create` output feels like a natural coda, not an interruption. It also fires in background/`-p` sessions (PostToolUse is evaluated there), keeping a ledger current even when no user turns exist.

**Failure modes.** *Missed triggers:* PRs manipulated via MCP GitHub tools, `gh api`, scripts, or merged externally (by CI, a reviewer, or another session) never hit the Bash matcher. Mitigations: add matchers for `mcp__github.*`; or make the hook itself run `gh pr list --json number,state` and diff a hash — turning fragile command-matching into ground-truth polling at event moments. *Duplicate/burst noise:* a create+push+push sequence fires three times; the dedupe window in the state file (suppress if last summary < X minutes ago, or PR-set hash unchanged) is mandatory, not optional. *Fragility:* pure string-grep on commands breaks on aliases and wrappers; the `if` permission-rule syntax is more resilient per the documented matching rules.

**Annoyance profile.** Low. Fires only when the thing being summarized actually changed; burst dedupe handles the residual noise.

### (c) Instruction-only cadence

**Sketch.** A shirabe skill/CLAUDE.md rule: "Maintain `wip/work-summary.md` (or a pinned ledger format). Post the in-chat summary block only when you open, close, or merge a PR, or when the user asks for status. Never append it to other messages."

**Failure modes.** Self-trigger reliability is the known weak point in long sessions: the model both under-fires (forgets after 40 turns of unrelated work) and over-fires (drifts into appending a status footer to everything — exactly the behavior the user rejected). Compaction makes it worse: in-conversation instructions and prior summaries can be compacted away, though CLAUDE.md/skill text is reloaded. There is a partial hook remedy even here: the docs show `SessionStart` supports a `compact` matcher, so a one-line hook can re-inject the current ledger after every compaction.

**Annoyance profile.** Unpredictable — the failure distribution includes the exact annoyance being designed against. But it costs nothing, works with zero installation, and is the necessary base layer regardless: every hook option ultimately just reminds the model to follow this instruction. The instruction (format + event rules) must exist; the question is only whether a hook backs it up.

### (d) Stop-based (end of turn / idle)

**Sketch.** A `Stop` hook fires **every time Claude finishes responding — i.e., every turn**, not "when the session goes idle." A naive Stop-hook summary is therefore the rejected every-message footer, implemented in hooks. To be viable it must be gated by the same state file as (b): only act if PR-set dirty AND >T since last summary. `Stop` can inject non-blocking `additionalContext` at end of turn, or `{"decision": "block", "reason": ...}` to force one more assistant turn to emit the summary — the workspace's own `workflow-continue.sh` demonstrates that block-with-agency-preserving-reason pattern.

**Idle detection exists but can't reach the chat.** The `Notification` event with matcher `idle_prompt` fires when Claude has been waiting for input, but Notification hooks cannot inject context to the model — they can only run side effects (update a file, statusline data, send an external message). So "summarize when idle" is only implementable as a *display-channel* refresh, not an in-chat message.

**Failure modes.** Loop risk (must check `stop_hook_active`); a blocking Stop adds a whole extra assistant turn of latency and cost at the exact moment the user expects the floor; a gated Stop hook is functionally just option (b) with worse timing (end of turn instead of adjacent to the PR event).

**Annoyance profile.** Ungated: maximal — this is the anti-pattern. Gated: acceptable but strictly dominated by (b).

### (e) Display-channel alternatives (no chat injection)

**Statusline** (https://code.claude.com/docs/en/statusline): configured via `statusLine` in settings.json; runs any script, receives session JSON on stdin, supports multiple lines, refreshes as the conversation updates. A PostToolUse hook from (b) can write `~/.claude/.../pr-ledger-$session_id.txt` (via `gh pr list`) and the statusline script renders `PRs: #12 open(CI green) #14 merged`. Zero chat noise, always visible, survives compaction (it's on disk).

**Ledger file**: the model (per instruction) and/or the hook (ground truth via `gh`) keep a `work-summary.md` current; the user opens it or a `/status` skill prints it on demand. This is the only channel that works identically in background/dispatched sessions, where nobody sees a statusline or live chat — and it composes with niwa's Agent View / `niwa_report_progress` for dispatched workers.

**Footer link badges**: the statusline doc points at `footerLinksRegexes` (https://code.claude.com/docs/en/settings#footer-link-badges) — clickable badges in the Claude Code footer whenever an ID pattern (e.g., a PR URL or `#123`) appears in conversation. This directly attacks the original pain ("find PR links in a long chat") with pure configuration and no cadence design at all.

**Failure modes.** Discoverability (user must know the ledger/statusline exists); statusline space is limited; ledger can go stale if only instruction-maintained (pair with the (b) hook for ground truth). No annoyance profile to speak of — that's the point.

### Degradation matrix

| Scenario | (a) UserPromptSubmit | (b) PostToolUse | (c) instruction | (d) Stop | (e) file/statusline |
|---|---|---|---|---|---|
| Background `-p` session | never fires (documented) | fires | works, no reader | fires every turn | ledger works; statusline invisible |
| After compaction | state file survives; fires next prompt | survives | instruction reloaded, in-chat history lost | survives | file survives; `SessionStart(compact)` hook can re-inject ledger |
| Hooks not installed | absent | absent | **only fallback** | absent | ledger half works (instruction-maintained) |

## Implications

1. **The instruction layer is non-optional.** Every hook merely reminds the model; the summary format and the event rule ("summarize when the PR set changes or on request, never as a footer") must live in a shirabe convention regardless of which trigger backs it. Decision informed: shirabe owns the format + instruction; hooks are an optional enforcement layer that can live in shirabe's `hooks/hooks.json` or niwa-injected settings interchangeably.
2. **The winning cadence is a hybrid, and both halves are cheap.** Event-driven dirty-flag (b) + return-after-absence timer (a-timer variant) covers the two real user moments — "the PR set just changed" and "I just came back, what's in flight?" — while a shared state file (PR-set hash + last-summary timestamp) dedupes across both triggers and against model self-triggering.
3. **Recommendation ranking:** 1. Hybrid (b)+(a-timer) with shared dedupe state. 2. (b) alone. 3. (a-timer) alone. 4. (c) alone — mandatory base layer, acceptable as the whole story only where hooks can't be installed. 5. Gated (d) — dominated by (b). 6. (a-turn-count) and ungated (d) — reject; both decouple cadence from need.
4. **Pursue (e) in parallel, not as an alternative.** A hook-maintained ledger file + optional statusline removes most of the pressure to inject anything into chat, and `footerLinksRegexes` may solve the "find the PR link" pain outright for interactive sessions with zero design work. For background sessions the ledger file is the *only* viable channel.

## Surprises

- **`UserPromptSubmit` hooks are documented as not evaluated in `-p` (non-interactive) mode.** Any turn/timer design silently does nothing in niwa-dispatched sessions — background coverage must come from PostToolUse or the ledger file.
- **`Notification(idle_prompt)` exists but cannot inject context to the model**, so "summarize when idle" is impossible as an in-chat feature and only possible as a display-channel refresh. The intuitive "(d) idle summary" option doesn't actually exist in the hook API.
- **The workspace's existing Stop hook appears to have an inverted anti-loop guard.** `/home/dangazineu/dev/niwaw/tsuku/tsuku+always_include_links-fe2fc637/.claude/hooks/stop/workflow-continue.sh` line 24 exits 0 (allows stop) unless `stop_hook_active == "true"` — the documented pattern is the opposite (bail out *when* `stop_hook_active` is true to prevent loops). As written it never nudges on a normal first stop. Worth a separate fix, and a caution for any new Stop-hook design.
- **`footerLinksRegexes` is a config-only near-solution** to the underlying "find PR links in a long chat" problem for interactive sessions — no summaries needed.
- **`SessionStart` has a `compact` matcher**, giving a clean compaction-resilience story: re-inject the ledger after every compaction.

## Open Questions

- What exactly does the user-facing summary block contain, and is the ledger file (pull) sufficient, making in-chat summaries (push) rare-by-design? This is a product call, not a mechanics one.
- Do niwa-dispatched sessions surface any per-session file or statusline in Agent View that could render the ledger, and should `niwa_report_progress` carry the standardized summary for background workers?
- Should PR-set ground truth come from matching commands (fragile) or from the hook running `gh pr list` and hashing the result (robust but adds a network call and needs `GH_TOKEN` in hook env — present in this workspace's settings)?
- If shirabe ships the hook in `hooks/hooks.json`, does it conflict with workspaces that also have niwa-injected hooks for the same events (both run; dedupe state must be shared or single-owner)?
- Does the model reliably obey a dirty-flag `additionalContext` nudge without also drifting into unprompted footers? Needs an empirical trial in a real multi-PR session.

## Summary

Hook mechanics verified against https://code.claude.com/docs/en/hooks make a hybrid cadence the clear winner: a PostToolUse hook on PR-changing Bash commands (via the documented `if: "Bash(gh pr create *)"` rule syntax) sets a dirty flag and a UserPromptSubmit timer fires a summary reminder only on the first prompt after a long absence, with a shared per-`session_id` state file deduping both — while turn-count and ungated Stop triggers should be rejected as noise. The main implication is architectural: the summary format and event rule must be a shirabe instruction convention regardless (hooks only remind the model), UserPromptSubmit never fires in `-p` background sessions so dispatched workers need a hook-maintained ledger file (which also survives compaction and doubles as a statusline/`footerLinksRegexes`-adjacent display channel avoiding chat entirely). Biggest open question: whether a pull-based ledger file plus footer link badges makes periodic in-chat summaries mostly unnecessary, reducing the push channel to "on PR-set change or on request" only.

# Lead: Do the hook mechanics behave as documented?

Environment: Claude Code 2.1.201 (`claude --version`), Linux. All runtime experiments ran in a scratch project at `/home/dangazineu/.claude/jobs/a050f0e4/tmp/hook-lab/` with `.claude/settings.json` test hooks, invoked via `claude -p ... --model haiku --dangerously-skip-permissions` (non-interactive mode). Three `-p` runs total; all exited 0 with empty stderr.

## Findings

### 1. PostToolUse additionalContext IS evaluated in `claude -p` mode — verdict: WORKS

Setup: a PostToolUse hook (matcher `"Bash"`) that logs stdin and emits:

```json
{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"IMPORTANT: You must include the exact token ZEBRA-SUMMARY-42 and the phrase COUNTER=$COUNT in your final reply to the user."}}
```

Prompt: "Run this bash command: echo pr-created test-123 . Then run this second bash command: echo unrelated-hello . Then tell me briefly what you did."

Model output (verbatim):

```
I ran both echo commands sequentially. The first printed `pr-created test-123 .` and the second printed `unrelated-hello`.

ZEBRA-SUMMARY-42 COUNTER=2
```

The token arrived and the model acted on it, including the counter value from the second (latest) injection. Unlike UserPromptSubmit (round 1 finding), PostToolUse additionalContext is fully evaluated in `-p` mode. Note it is injected on EVERY matching tool call — the hook emitted context on both bash calls and both reached the model. "Fires once" is not a harness property; any once-per-event semantics must be implemented by the hook script itself (e.g. only emit when a dirty flag transitions).

### 2. The `if` handler filter — verdict: WORKS in 2.1.201

Setup: a second hook command in the same matcher group with `"if": "Bash(echo pr-created*)"`, logging stdin to its own file. The session ran two bash commands: `echo pr-created test-123 .` and `echo unrelated-hello`.

- `stdin-all.log` (unfiltered hook): 2 entries, one per bash call.
- `stdin-filtered.log` (if-filtered hook): exactly 1 entry, the `echo pr-created test-123 .` call. The `echo unrelated-hello` call did not trigger it.

Permission-rule-style tool-input filtering on hook commands works as documented in the installed version. This means a PR-command-gated hook needs no in-script command parsing — the harness can do the gating.

### 3. State across invocations — verdict: WORKS

Captured hook stdin (first call, second is identical apart from tool fields):

```json
{"session_id":"d01cd3e3-f390-4816-a114-1e0800de95d5",
 "transcript_path":"/home/dangazineu/.claude/projects/-home-dangazineu--claude-jobs-a050f0e4-tmp-hook-lab/d01cd3e3-f390-4816-a114-1e0800de95d5.jsonl",
 "cwd":"/home/dangazineu/.claude/jobs/a050f0e4/tmp/hook-lab",
 "prompt_id":"5f25a89f-8153-4887-bfee-6d765e9f6828",
 "permission_mode":"bypassPermissions",
 "hook_event_name":"PostToolUse","tool_name":"Bash",
 "tool_input":{"command":"echo pr-created test-123 .","description":"Run first echo command"},
 "tool_response":{"stdout":"pr-created test-123 .","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false},
 "tool_use_id":"toolu_01GxThuQ4DYK88B2Por4qbgj","duration_ms":76}
```

`session_id` and `transcript_path` arrive on stdin as documented (plus `cwd`, `prompt_id`, `permission_mode`, `tool_use_id`, `duration_ms`, and the full `tool_response`). A counter file keyed on `session_id` incremented 1 -> 2 across the two bash calls in one session, and the model's reply reflected the final value (COUNTER=2). Per-session state files work.

### 4. The niwa duplicate-hook bug — verdict: CONFIRMED, root cause traced; behavioral impact is scope-broadening, not double-firing

Observed symptom in `/home/dangazineu/dev/niwaw/tsuku/tsuku+always_include_links-fe2fc637/public/tsuku/.claude/settings.local.json`: `gate-online.local.sh` appears twice under PreToolUse — once with `"matcher": "Bash"`, once with NO matcher (matches all tools). `workflow-continue.local.sh` is likewise doubled under Stop.

Root cause — declared config AND auto-discovery both materialize, and the merge appends without dedupe:

1. The workspace config declares the hook explicitly WITH a matcher: `public/dot-niwa/.niwa/workspace.toml` lines 17-19 (`[[claude.hooks.pre_tool_use]]`, `matcher = "Bash"`, `scripts = ["hooks/pre_tool_use/gate-online.sh"]`) and lines 21-22 for the stop hook.
2. The same script files physically live in the discovery location `.niwa/hooks/{event}/`. `DiscoverHooks` (`public/niwa/internal/workspace/discover.go:21-69`) scans `configDir/hooks/` and builds entries with NO matcher (line 56: `config.HookEntry{Scripts: []string{scriptPath}}` — `Matcher` is never set by discovery).
3. `runRepoMaterializers` (`public/niwa/internal/workspace/worktree_content.go:67-102`) merges the two sources by concatenation: discovered hooks form the base, then explicit config entries are PREPENDED per event — line 96: `merged[event] = append(entries, existing...)`. There is no dedupe by script path/identity. The comment ("must not silently discard user-authored discovered hooks") shows the append is intentional for the distinct-scripts case; the same-file-declared-and-discovered case was not considered.
4. `buildSettingsDoc` (`public/niwa/internal/workspace/materialize.go:434-479`) faithfully emits one settings entry per `InstalledHookEntry`, preserving each entry's matcher (`if ie.Matcher != "" { entry["matcher"] = ie.Matcher }` at lines 473-475) — producing the doubled block.
5. Inconsistency: the instance-root path `InstallWorkspaceRootSettings` (`public/niwa/internal/workspace/workspace_context.go:242-266`) uses the OPPOSITE policy — discovered hooks are dropped wholesale when the event already has any explicit entry (`if _, exists := effective.Claude.Hooks[event]; !exists`). So the root `settings.json` doesn't duplicate, but every per-repo `settings.local.json` (via `runRepoMaterializers`) does.

Would a cadence hook fire twice? Tested empirically by replicating the exact duplicated shape (same command under matcher `"Bash"` and matcher-less) in the scratch project:

- Identical command string in both entries: fires ONCE per Bash call. Claude Code 2.1.201 deduplicates identical hook commands within an event. `dup-count.log` showed a single line for the bash call.
- Distinct commands (control run): BOTH fire for the same `tool_use_id`, and the matcher-less entry ALSO fires for non-Bash tools:

```
SCRIPT2 PostToolUse Bash toolu_01VW5qAXPMxvj575ayg7vVGb
PostToolUse Bash toolu_01VW5qAXPMxvj575ayg7vVGb
SCRIPT2 PostToolUse Read toolu_01AfoQLvQUGN6Z8YV2q7SNC9
```

So the niwa bug's real-world effect today: gate-online does NOT run twice per Bash call (saved by harness dedupe of identical commands), but the matcher-less duplicate makes it run on EVERY tool call — Read, Edit, Glob, everything — not just Bash. A Bash-scoped cadence hook materialized through this pipeline would silently become an all-tools hook. The dedupe safety net also breaks the moment the two entries' command strings differ in any way (e.g. different path spellings or a local-rename variant).

## Implications

- The event-gated work-summary design is viable in `-p`/background mode: PostToolUse additionalContext reaches the model and the model acts on it, unlike UserPromptSubmit.
- Command gating can be pushed to the harness via `"if": "Bash(gh pr create*)"`-style filters — no in-script command parsing needed for the trigger condition.
- Session-scoped dirty flags/timestamps are straightforward: key state files on `session_id`, which arrives on every hook stdin along with `transcript_path`.
- "Inject the reminder once" must be enforced by the hook script (emit additionalContext only on flag transition), since the harness injects on every matching call.
- The niwa materializer should dedupe by resolved script path when merging discovered and declared hooks (or discovery should skip scripts already claimed by explicit config, mirroring the event-level suppression already in `InstallWorkspaceRootSettings` but at script granularity). Until fixed, any cadence hook shipped through niwa's per-repo pipeline must tolerate being invoked for all tool types and must be idempotent per `tool_use_id`.

## Surprises

- Claude Code dedupes identical hook command strings across multiple matching matcher groups — the tsuku duplicate is currently harmless for double-execution, which was not the expected failure mode.
- The actual impact of the niwa bug is matcher erasure (Bash-only hook becomes all-tools), which is quieter and arguably worse than double-firing: gate-online has been receiving PreToolUse events for every Read/Edit call.
- niwa has two different merge policies for the same problem in the same package (append-no-dedupe in `runRepoMaterializers` vs event-level suppression in `InstallWorkspaceRootSettings`).
- The model echoed the counter from the latest injection (COUNTER=2) cleanly — repeated additionalContext injections supersede rather than confuse, at least at this scale.

## Open Questions

- Does the identical-command dedupe behavior have a documented contract, or is it an implementation detail that could change between Claude Code versions? The cadence design should not rely on it.
- How does additionalContext interact with context compaction in long sessions — does a nudge injected early survive, or should the hook re-emit near session end (Stop hook)?
- Does the `if` filter support the full permission-rule grammar (e.g. `Bash(gh pr create:*)` colon syntax vs glob `*`)? Only the glob form `Bash(echo pr-created*)` was tested.
- For the return-after-absence reminder: UserPromptSubmit is confirmed not evaluated in `-p` mode (round 1) — which event should carry the reminder in background sessions, or is that feature interactive-only by design?

## Summary

All three hook mechanics work as documented in Claude Code 2.1.201 under `claude -p`: PostToolUse additionalContext reaches the model and it acts on the nudge (ZEBRA token test), `"if": "Bash(echo pr-created*)"` filters fire the hook only for matching commands, and session_id/transcript_path arrive on stdin enabling per-session counter state (verified 1 -> 2 across calls). The niwa duplicate-hook bug is confirmed and traced: workspace.toml declares gate-online with matcher "Bash" while DiscoverHooks re-finds the same script matcher-less, and runRepoMaterializers concatenates both without dedupe (worktree_content.go:96), which buildSettingsDoc then emits verbatim. Empirically the duplicate does not double-fire (Claude Code dedupes identical commands) but it erases the Bash matcher — the hook fires on every tool call — so a cadence hook shipped via niwa must either wait for a materializer dedupe fix or be idempotent and tool-type-tolerant.

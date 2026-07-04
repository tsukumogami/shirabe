# Lead: What injection surfaces does niwa already control, and could it deliver a session-wide instruction or hook?

## Findings

All paths below are under the workspace instance root `/home/dangazineu/dev/niwaw/tsuku/tsuku+always_include_links-fe2fc637/` (abbreviated `{instance}`) and the niwa source at `{instance}/public/niwa/`.

### Surface 1: Instance-root CLAUDE.md (config-only, template-driven)

`InstallWorkspaceContent` (`public/niwa/internal/workspace/content.go:25-48`) renders the workspace config's `[claude.content.workspace]` source template and writes it to `{instance}/CLAUDE.md`. For this workspace the template is `public/dot-niwa/.niwa/claude/workspace.md` (declared in `public/dot-niwa/.niwa/workspace.toml` line 64-65). Template variables: `{workspace}`, `{workspace_name}`, `{group_name}`, `{repo_name}`. Editing that one markdown file in the workspace config repo changes what every session in every future instance sees — zero niwa code changes.

### Surface 2: workspace-context.md + the @import rules file (generated)

`InstallWorkspaceContext` (`public/niwa/internal/workspace/workspace_context.go:177-202`) *generates* `{instance}/workspace-context.md` from the classified repo list (not from a template) and writes `{instance}/.claude/rules/workspace-imports.md` containing an absolute-path `@import`. The rules file is append-only (`appendToWorkspaceRulesFile`, `workspace_context.go:137-155`): the overlay's `CLAUDE.overlay.md` (`InstallOverlayClaudeContent`, line 204-235) and a personal `CLAUDE.global.md` (line ~388-407) get appended the same way. Ground truth: `{instance}/.claude/rules/workspace-imports.md` imports both `workspace-context.md` and `CLAUDE.overlay.md`. Changing the generated context body requires a niwa change; adding another imported file does not — any mechanism that appends to the rules file (or any content routed through the overlay/global layers) reaches every session.

### Surface 3: Per-repo CLAUDE.local.md (config-only)

`InstallRepoContentTo` (`public/niwa/internal/workspace/content.go:117-203`) writes `{repo}/CLAUDE.local.md` from `[claude.content.repos.<name>]` (plus subdir variants, e.g. `recipes/CLAUDE.local.md`), with optional overlay-appended content. Auto-discovery also picks up `{content_dir}/repos/{repoName}.md` with no TOML entry (`autoDiscoverRepoSource`, line 207). Also group-level `{group}/CLAUDE.md` via `InstallGroupContent` (line 53-70).

### Surface 4: Hook installation into settings — already fully supported, config-only, for arbitrary events

This is the headline finding. niwa already installs Claude Code hooks two ways:

- **Declared**: `[[claude.hooks.<event>]]` in workspace.toml (`HooksConfig`, `public/niwa/internal/config/config.go:303-314`), overridable per-repo, per-instance (`[instance.claude]`), and in the personal global config.
- **Auto-discovered**: any `*.sh` under the config repo's `.niwa/hooks/<event>/` or `.niwa/hooks/<event>.sh` (`DiscoverHooks`, `public/niwa/internal/workspace/discover.go:21-69`).

`HooksMaterializer` (`public/niwa/internal/workspace/materialize.go:167-246`) copies scripts into `{repo}/.claude/hooks/<event>/<name>.local.sh`; `buildSettingsDoc` (`materialize.go:378-528`) writes the hooks block into `{repo}/.claude/settings.local.json` (and `InstallWorkspaceRootSettings`, `workspace_context.go:242+`, writes `{instance}/.claude/settings.json` with absolute paths, no `.local` rename).

Critically, event names are NOT whitelisted. `hookEventMapping` (`materialize.go:257-262`) explicitly maps `pre_tool_use`, `post_tool_use`, `stop`, `notification`, but any other snake_case event falls through to `snakeToPascal` (`materialize.go:310-320`). So `[[claude.hooks.user_prompt_submit]]` or a script at `.niwa/hooks/user_prompt_submit/summary-nudge.sh` materializes as a `UserPromptSubmit` hook entry today, with no niwa change. `Stop` and `PostToolUse` are first-class already.

Ground truth confirms the pipeline works end-to-end: `{instance}/.claude/settings.json` and `{instance}/public/tsuku/.claude/settings.local.json` carry `PreToolUse` (gate-online) and `Stop` (workflow-continue) hooks installed from `public/dot-niwa/.niwa/hooks/`.

### Surface 5: Existing Stop hook is a working cadence precedent

`public/dot-niwa/.niwa/hooks/stop/workflow-continue.sh` reads the hook JSON from stdin, inspects `wip/*-state.json` for incomplete work, and emits `{"decision": "block", "reason": "..."}` to nudge the agent while leaving it agency to stop anyway. This is exactly the shape a "you haven't posted a work summary in N turns" nudge would take: a Stop (or UserPromptSubmit) hook script that tracks its own cadence state in a local file and injects a reminder only when due.

### Surface 6: Arbitrary file distribution — the shirabe-extensions channel

The `[files]` table (`FilesMaterializer`, `public/niwa/internal/workspace/materialize.go:1128+`) copies arbitrary config-repo files into every repo (with an enforced `.local` infix, `injectLocalInfix` at `materialize.go:52-57`); `[instance.files]` and `[root.files]` do the same for the instance root and workspace root verbatim. This workspace already uses it to ship `extensions/<skill>.md` into every repo's `.claude/shirabe-extensions/` (workspace.toml lines 55-60), and shirabe skills @import those files (`public/shirabe/skills/prd/SKILL.md:14-15` imports both `.claude/shirabe-extensions/prd.md` and `prd.local.md`). So a workspace can inject per-skill behavior into shirabe workflows with zero changes to niwa *or* shirabe.

### Surface 7: Per-session injection channels (distinct from per-instance)

- **SessionStart additionalContext**: for dispatched ephemeral sessions, the workspace-root `SessionStart` hook runs `niwa instance from-hook` (`{workspace-root}/.claude/settings.json`, 180s timeout; installed by `root_materializer.go`). `buildSessionStartInjection` (`public/niwa/internal/cli/instance_from_hook.go:293-319`) emits `hookSpecificOutput.additionalContext` containing the provisioned instance path plus the instance's entire CLAUDE.md text. niwa already owns a per-session context-injection channel.
- **`claude --settings` at dispatch launch**: `dispatch_remotecontrol.go:10-16` injects an inline settings JSON (`{"remoteControlAtStartup":true}`) into a dispatched worker's argv — precedent for niwa layering per-session settings over the instance's files.
- Everything else (CLAUDE.md, settings.json, hooks) is per-instance. In ephemeral-session mode, instance == session, so per-instance injection is effectively per-session for dispatched workers; for a long-lived interactive instance it is shared across all sessions until the next `niwa apply`.

### Settings doc contents (for completeness)

`buildSettingsDoc` emits: `permissions.defaultMode`, `permissions.deny` (worktree fallback), `hooks` (installed scripts + WorktreeCreate/WorktreeRemove + SessionStart), `env` (promoted vars — note the promoted `GH_TOKEN` credential lands in plaintext in both instance settings.json and per-repo settings.local.json, mode 0600), `includeGitInstructions`, `enabledPlugins`, `extraKnownMarketplaces`, `remoteControlAtStartup`.

## Implications

For the work-summary exploration, both candidate delivery mechanisms are **config-only** in the workspace config repo — no niwa code change needed:

1. **Standing instruction**: add a "Work in flight" convention section to `public/dot-niwa/.niwa/claude/workspace.md` (reaches every session's CLAUDE.md, and dispatched sessions additionally get it via SessionStart additionalContext). Cost: one markdown edit + `niwa apply`. Weakness: instruction-only cadence ("summarize every N turns") depends on model discipline; nothing measures turns.

2. **Hook**: drop a script under `public/dot-niwa/.niwa/hooks/stop/` (or declare `[[claude.hooks.user_prompt_submit]]` / `post_tool_use`) — the snake-to-Pascal fallback means UserPromptSubmit works today. A Stop-hook nudge following the workflow-continue.sh pattern gives a real cadence mechanism: the script can count invocations or check elapsed time in a state file and only nudge when due, keeping every other message clean. UserPromptSubmit can inject context (e.g., current `gh pr list` output) rather than just block.

3. **Skill-scoped alternative**: the shirabe-extensions `[files]` channel delivers the summary *template* into `/work-on`, `/execute` etc. without touching niwa or global instructions — the convention would then live in shirabe (or a workspace extension of it), applying only during workflow skills rather than all sessions.

Division of labor this suggests: shirabe owns the summary *format* (template), the workspace config owns the *delivery* (instruction or hook), and a hook owns the *cadence* — each at its natural layer, all deployable today.

Propagation caveat: all per-instance surfaces update only on `niwa apply` (or new instance provisioning). Existing long-lived instances need a re-apply; ephemeral dispatched instances pick changes up on their next provision automatically.

## Surprises

- **Arbitrary hook events already work.** Expected the hook event list to be a whitelist; instead `snakeToPascal` fallback (`materialize.go:310-320`) means UserPromptSubmit, SessionStart, or any future Claude Code event is deliverable from workspace.toml today.
- **niwa already does per-session context injection** (`buildSessionStartInjection` pipes the whole CLAUDE.md through `additionalContext` for dispatched sessions) and per-session settings injection (`claude --settings` at dispatch). The "could niwa inject a session-wide instruction" question is answered by existing shipped code, not hypothetical work.
- **Duplicate hook entries in ground truth**: `public/tsuku/.claude/settings.local.json` lists gate-online twice under PreToolUse (once with `"matcher": "Bash"`, once without) and workflow-continue twice under Stop. Hooks both declared in workspace.toml and present in the auto-discovery layout appear to be installed twice at the repo level (the instance-root path guards with an `if not exists` check in `InstallWorkspaceRootSettings`, `workspace_context.go:250-266`; the per-repo merge apparently doesn't dedupe when matchers differ). Harmless for idempotent hooks but a latent bug for a cadence hook that counts invocations.
- **Promoted secrets land in plaintext** in settings files (`env.GH_TOKEN` in both instance settings.json and per-repo settings.local.json). Not directly relevant to this exploration but notable.
- The shirabe-extensions import convention (`@.claude/shirabe-extensions/<skill>.local.md` in every SKILL.md) is a ready-made, already-wired seam for workspace-specific skill behavior — arguably the lowest-friction home for a summary template that should only apply during workflow skills.

## Open Questions

- Which Claude Code hook events best fit the cadence? Stop (summary at natural pause points, proven block/reason pattern) vs UserPromptSubmit (inject fresh PR state as context before the model answers) — needs a check of what output shape each event honors (`decision/reason` vs `additionalContext`) in current Claude Code.
- Should the convention apply to *all* sessions (workspace instruction / hook) or only workflow-skill sessions (shirabe-extensions)? That's a product decision, not a technical constraint.
- Where does cadence state live? A hook script needs a writable per-session scratch location (`wip/`, or keyed by `session_id` from the hook payload, which the payload provides).
- Is the duplicate-hook-entry behavior a known issue? A cadence hook registered twice would fire twice per event.
- For non-dispatched interactive sessions at an existing instance, updates require `niwa apply` — is that acceptable rollout friction, or should the convention also ship inside the shirabe plugin so it updates with the marketplace pin?

## Summary

niwa already controls every injection surface needed: it renders instance CLAUDE.md and per-repo CLAUDE.local.md from workspace-config templates, writes hooks into `.claude/settings.json`/`settings.local.json` from either `[[claude.hooks.<event>]]` TOML or auto-discovered `.niwa/hooks/<event>/*.sh` scripts, and its snake-to-Pascal fallback (`materialize.go:310-320`) means even UserPromptSubmit/PostToolUse hooks are deliverable today with zero niwa code changes — plus it already does per-session context injection for dispatched sessions via SessionStart `additionalContext`. The main implication is that the work-summary convention is a config-repo decision, not a niwa feature: a workspace.md instruction, a Stop/UserPromptSubmit cadence hook modeled on the existing workflow-continue.sh nudge, or a shirabe-extensions template are all shippable via `niwa apply` alone. The biggest open question is placement and cadence semantics — all-sessions (workspace hook/instruction) versus workflow-skill-only (shirabe-extensions), and which hook event's output contract best carries a periodic summary nudge — plus a latent duplicate-hook-installation quirk that a fire-counting cadence hook would need fixed or worked around.

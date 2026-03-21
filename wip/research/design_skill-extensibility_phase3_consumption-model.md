# Phase 3 Research: Consumption Model

## Questions Investigated

1. How does Claude Code's plugin registry work in practice — specifically how `claude plugin
   marketplace add` and `claude plugin install` operate?
2. Can two plugins be active simultaneously? What happens when both define a skill with the
   same name (e.g., `/explore` in shirabe AND `/explore` in tsukumogami)?
3. For the submodule approach: where would it live, and how do extension files from
   `.claude/skill-extensions/` resolve when shirabe lives in a submodule path?
4. For the two-plugin approach: is skill invocation namespaced as `/<plugin>:<skill>` or
   just `/<skill>`? Does a second plugin shadow the first if names match?
5. For the merged install: what tooling would copy/merge files?
6. Are there existing scripts in the tools repo managing plugin installation?

---

## Findings

### Plugin Registry Mechanics

The plugin system operates through three data files:

- `~/.claude/plugins/known_marketplaces.json` — maps marketplace names to their source
  (github, file path, etc.) and local install location
- `~/.claude/plugins/installed_plugins.json` — tracks which plugins are installed, at which
  scope (user vs. project), and into which project paths
- `.claude/settings.json` per project — `enabledPlugins` map that gates which installed
  plugins are active

`claude plugin marketplace add <path>` writes a marketplace entry into
`known_marketplaces.json`. The tools repo does this with its local
`.claude-plugin/marketplace.json`, which declares a single plugin sourced from
`./plugin/tsukumogami`. The `installLocation` becomes the directory two levels up from the
marketplace.json — in this case the tools repo root.

`claude plugin install tsukumogami@tsukumogami --scope project` then writes an entry into
`installed_plugins.json` under the key `tsukumogami@tsukumogami`, with the active project
path recorded in `projectPath`. For the tsuku-5 workspace, every repo (tsuku, koto, shirabe,
tools, vision) has its own entry under the same plugin key. The `installPath` points to
`~/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/` which is a real directory, not a
symlink. The cache contains the full plugin tree: `skills/`, `agents/`, `helpers/`, `shared/`,
`.claude-plugin/plugin.json`.

Each target repo's `.claude/settings.json` contains:
```json
{ "enabledPlugins": { "tsukumogami@tsukumogami": true } }
```

The `install.sh` script in the tools repo handles all of this. It registers the marketplace
once at user scope, then iterates all target repos and runs `claude plugin install` from each
directory. The plugin install is idempotent. Skills and agents are distributed entirely through
this mechanism; hooks and settings are installed directly by `install.sh` via shell commands.

### Skill Namespacing

Skills in Claude Code plugins are namespaced by plugin name. The official plugin-dev skill
documents explicitly that user-invoked skills are run as `/plugin-name:skill-name`. Commands
in `/help` display as `(plugin:plugin-name)`. Subdirectories inside `commands/` or `skills/`
create further sub-namespaces (e.g., `(plugin:plugin-name:subdir)`).

Evidence from the workspace:
- The workspace-level `CLAUDE.md` uses `/tsukumogami:explore`, `/tsukumogami:plan` — the
  full namespace form
- The `plugin-dev` marketplace plugin documents this explicitly: "For user-invoked skills:
  Run `/plugin-name:skill-name` with various arguments"
- Agents are noted as "namespaced automatically" under a similar scheme

The SKILL.md front matter `name:` field declares the skill's unqualified name (e.g., `explore`,
`design`). The plugin name in `plugin.json` provides the namespace prefix. So tsukumogami's
explore skill is `/tsukumogami:explore` and shirabe's would be `/shirabe:explore`.

### Two Installed Plugins

Two plugins with overlapping skill names can coexist. Because skills are namespaced, a user
with both tsukumogami and shirabe installed would see `/tsukumogami:explore` and
`/shirabe:explore` as distinct commands. There is no shadowing — they are separate entries in
the plugin registry under different keys (`tsukumogami@tsukumogami` and
`shirabe@<marketplace>`), with separate `enabledPlugins` toggles.

However, the existing design doc (`DESIGN-skill-extensibility.md`) already rejected the
"wrapper skills" approach partly because "unnamespaced skill name conflicts have undefined
behavior when both plugins are installed simultaneously." That concern applies specifically to
the `name:` field inside SKILL.md — if two active plugins have SKILL.md files with the same
`name:` value, the behavior is undefined. Since both tsukumogami and shirabe use `name:
explore`, this conflict exists even though the invocation paths differ.

The practical consequence: model-invoked skills (which activate by description match, not user
slash command) from two plugins with the same `name:` field may exhibit undefined behavior.
User-invoked slash commands use the plugin-namespaced path so they won't collide. Model-invoked
activation uses the description field — two skills with similar descriptions compete, and
whichever wins is LLM-dependent.

A second structural concern: tsukumogami's skills use `${CLAUDE_PLUGIN_ROOT}` extensively to
reference internal scripts (`swap-to-tracking.sh`, `create-issue.sh`, `manage-milestone.sh`,
`wait-for-checks.sh`, etc.). This variable resolves to the tsukumogami plugin's cache
directory. If the tools repo moves to consuming shirabe, and shirabe's skills don't include
those scripts, the `${CLAUDE_PLUGIN_ROOT}` references in the skills break. This is not a
two-plugin concern per se — it's the extraction problem — but it means the tools repo cannot
simply enable both plugins and expect the tsukumogami skills to keep working while shirabe
skills provide the same named capabilities.

For the two-plugin approach to work, the tools repo would need to either:
- Use tsukumogami for all tsuku-project-specific skills and shirabe only for the generic base,
  with no overlap in active skill names; or
- Disable tsukumogami's conflicting skills and invoke only shirabe's versions

Neither mechanism exists in Claude Code's plugin system today.

### Submodule

The submodule approach would embed shirabe's git repo as a submodule inside the tools repo,
likely at `plugin/shirabe/` alongside the existing `plugin/tsukumogami/`. The tools repo's
`install.sh` would then call `claude plugin marketplace add` with shirabe's `.claude-plugin/
marketplace.json` and `claude plugin install shirabe@shirabe --scope project` for each target
repo.

Extension file resolution is installation-agnostic. The `@.claude/skill-extensions/
<name>.md` path in shirabe's base SKILL.md resolves relative to the Claude Code process's
working directory (the workspace root), regardless of where shirabe is installed. This was
confirmed by tests T1-T7: when the test plugin was in `/tmp/test-plugin/` and the extension
file was in `.claude/skill-extensions/` relative to cwd, the extension loaded correctly. So
submodule placement doesn't affect extension file loading.

What the submodule does affect:
- The submodule must be initialized and updated (`git submodule update --init`) as part of
  workspace setup. The current `install.sh` has no submodule handling.
- `install.sh` would need to register shirabe's marketplace from the submodule path:
  `claude plugin marketplace add "$SCRIPT_DIR/plugin/shirabe/.claude-plugin/marketplace.json"
  --scope user`
- The shirabe submodule path must be pinned to a commit (standard submodule behavior). Tools
  repo controls which shirabe version it consumes, same as package pinning.
- `${CLAUDE_PLUGIN_ROOT}` in shirabe's skills would resolve to shirabe's cache directory,
  not tsukumogami's. If shirabe's skills reference scripts, those scripts must be in shirabe's
  plugin tree, not tsukumogami's.
- The name conflict problem (two plugins with overlapping `name:` fields) still exists if
  both tsukumogami and shirabe are installed simultaneously.

If the intent is to replace tsukumogami's five workflow skills with shirabe's equivalents, the
submodule approach requires tsukumogami's corresponding skills to be removed from
`plugin/tsukumogami/skills/` (or the tsukumogami plugin to be split — keeping project-specific
skills and dropping the generic workflow skills that shirabe will provide). Otherwise the name
conflict persists.

Where the submodule would live: `private/tools/plugin/shirabe/` — parallel to
`private/tools/plugin/tsukumogami/`. The marketplace.json would point to this path, and
Claude Code would cache it under `~/.claude/plugins/cache/shirabe/shirabe/<version>/`.

### Merged Install

The merged install approach has `install.sh` copy shirabe's skill files into tsukumogami's
plugin directory (or a combined plugin directory) at install time. The "merge" could be:

- Copying shirabe's `skills/explore/`, `skills/design/`, etc. into
  `plugin/tsukumogami/skills/`, overwriting the tsukumogami versions
- Or generating a new combined plugin directory from both sources

Current `install.sh` installs hooks, settings, and the binary directly via shell commands,
but delegates skills entirely to the plugin system. Adding a merge step would mean `install.sh`
becomes responsible for file copying before the plugin is registered, or a post-install step
that patches the plugin cache. Patching the cache is fragile — the cache path includes a
version hash that changes on updates.

The pre-registration approach (copy files into the source tree before `claude plugin
marketplace add`) would work but turns the tools repo into a place where shirabe skill content
lives permanently. This is structurally identical to the current state (tools repo maintains
skill copies) except the source of truth is shirabe rather than the tools team. The tools repo
still owns the merged result at install time.

No existing tooling in the tools repo does this. The `install.sh` script is ~440 lines and
handles CLAUDE.md, hooks, settings, env files, workflow-tool binary, workspace scripts, and
plugin registration — but no file merging from external repos.

---

## Implications for Design

**The two-plugin approach is viable for user-invoked slash commands** (namespacing prevents
collision) but has an unresolved issue with model-invoked skills sharing the same `name:`
field. Model-invoked skill selection is LLM-driven and may produce undefined behavior when two
active plugins declare skills with identical `name:` values. The design doc's existing "undefined
behavior" warning applies here.

**The two-plugin approach also leaves the transition state unresolved.** If both tsukumogami
and shirabe are active and both have an `explore` skill, users and LLMs must learn that
`/shirabe:explore` is the "new" explore and `/tsukumogami:explore` is the "old" one. This is
a poor UX during the transition period. The end state — tsukumogami's workflow skills removed,
shirabe providing them — requires modifying tsukumogami anyway, so the "no changes to tools
repo" advantage of two-plugin evaporates.

**The submodule approach cleanly separates shirabe as a dependency**, but the tools repo's
`install.sh` must be extended to handle submodule init/update and shirabe marketplace
registration. This is mechanical work but well-defined: ~20 additional lines in `install.sh`.
The main risk is the submodule update step — developers cloning the tools repo must run
`git submodule update --init` or the shirabe plugin directory is empty.

**The merged install approach has the least conceptual clarity** and the most ongoing
maintenance surface. It makes `install.sh` a build step for a synthetic plugin that doesn't
exist in source control. Any update to shirabe requires re-running install and re-validating
that the merge is correct. It also means the plugin cache would contain merged content that
differs from shirabe's canonical source, making debugging harder.

**Extension file resolution is installation-agnostic** for all three approaches. The
`@.claude/skill-extensions/<name>.md` path resolves from workspace root regardless of where
shirabe lives. This was confirmed by tests and reconfirmed by the design doc. The consumption
model choice doesn't affect this behavior.

**The strongest argument for the submodule approach** is that it mirrors standard dependency
management: shirabe is a versioned dependency of tools, pinned at a commit, updated explicitly.
The tools repo doesn't maintain copies of shirabe's content. Breakage from shirabe updates is
visible as a submodule pointer change, not a silent behavior change.

**The strongest argument for the two-plugin approach** is zero changes to install.sh and no
submodule infrastructure. Users install both plugins independently. This works if the transition
period is short and the name conflict risk is accepted. It doesn't work as a long-term steady
state.

---

## Surprises

**Skill namespacing is confirmed but `name:` field conflicts are a real risk.** The invocation
path `/plugin:skill` is namespaced, but the SKILL.md `name:` field that drives model-invoked
activation is not. Two plugins declaring `name: explore` creates ambiguity for model-invoked
(description-triggered) behavior. This is distinct from user-invoked slash commands, which
are unambiguously namespaced.

**`${CLAUDE_PLUGIN_ROOT}` is used extensively in tsukumogami** for referencing internal
scripts. This creates a hard dependency between skill content and the plugin's file tree. Any
approach that replaces tsukumogami's workflow skills with shirabe's must ensure that shirabe
provides the equivalent scripts, or that tsukumogami's project-specific scripts remain
accessible via a different mechanism. This wasn't obvious from the design context.

**The tools repo already installs tsukumogami into shirabe's project path.** Looking at
`installed_plugins.json`, the tsukumogami plugin is installed with `projectPath:
/home/dangazineu/dev/workspace/tsuku/tsuku-5/public/shirabe` — shirabe itself is a tsukumogami
consumer today. This confirms the two-plugin scenario is already partially present: the shirabe
repo will have both tsukumogami and shirabe plugins active. The question is whether this is the
intended long-term arrangement or a transitional artifact.

**The marketplace registration uses a file-path source, not a git URL.** The tsukumogami
marketplace points to a file path on the local machine. This means the "installed" plugin is
actually reading from the tools repo on disk. The cache directory for tsukumogami at
`0.1.0` is populated from the tools repo source, not from a git-fetched archive. This is
local-dev behavior — a published shirabe would use a github source like the official plugins.

---

## Summary

Three consumption models were evaluated against the tools repo's actual plugin infrastructure:

**Two installed plugins** is the lowest-effort approach for the transition period. Skill
invocation paths are namespaced (`/tsukumogami:explore` vs. `/shirabe:explore`) so user-invoked
commands don't collide. However, model-invoked skill activation uses the `name:` field, which
is unnamespaced — two plugins with `name: explore` create undefined behavior for model-driven
skill selection. This approach doesn't resolve the transition; it delays it. Long-term, the
tools repo still needs to remove tsukumogami's workflow skills or accept persistent ambiguity.

**Submodule** is the cleanest dependency model. Shirabe lives at `plugin/shirabe/` in the
tools repo, pinned to a commit, managed via standard git submodule commands. `install.sh`
needs ~20 additional lines for submodule init/update and shirabe marketplace registration.
Extension files resolve from workspace root regardless. The submodule approach requires the
tools repo to remove (or not add) tsukumogami's five workflow skills once shirabe provides
them — eliminating the name conflict. This is the most explicit, most debuggable model.

**Merged install** adds a build step to `install.sh` that copies shirabe's skill files into a
synthetic plugin. It produces the same net result as submodule (one active plugin with all
skills) but obscures the source of truth and creates ongoing maintenance overhead. It's not
recommended.

**Recommended path:** Submodule, with tsukumogami's five workflow skills removed from
`plugin/tsukumogami/skills/` as part of the shirabe extraction work. The tools repo becomes
a consumer of shirabe for generic workflow skills while retaining tsukumogami for all
project-specific skills (`upstream-context`, `competitive-analysis`, `label-reference`
integrations, etc.) that won't be extracted to shirabe.

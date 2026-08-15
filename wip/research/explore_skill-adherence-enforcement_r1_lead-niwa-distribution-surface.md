# Lead: What does niwa already distribute into an instance, and where would a declared skill policy hook into workspace config?

Round 1. All paths relative to
`/home/dgazineu/dev/niwaw/tsuku/tsuku+execute_and_work_on_trigger-d36b0bbf/`
unless absolute. niwa source lives at `public/niwa/`; the public workspace
config repo at `public/dot-niwa/`; the live instance state at `.niwa/instance.json`.

Headline: **niwa already injects a shirabe-specific PreToolUse allow/deny gate
into every instance that installs the shirabe plugin, by default, with no
configuration required.** A skill-adherence mechanism needs no new distribution
machinery — only a declaration surface and a script. Everything below is
evidence for that claim and for where the declaration should live.

---

## Findings

### 1. The `workspace.toml` schema as niwa actually parses it

`config.WorkspaceConfig` (`public/niwa/internal/config/config.go:239-254`) is the
whole top-level surface:

| Table | Go field | Notes |
|-------|----------|-------|
| `[workspace]` | `WorkspaceMeta` | name, version, default_branch, content_dir, setup_dir, default_agent, vault_scope, read_env_example, env_example_policy, env_output, strict_secrets |
| `[[sources]]` | `[]SourceConfig` | org / repos / max_repos |
| `[groups.<n>]` | `map[string]GroupConfig` | visibility, repos |
| `[repos.<n>]` | `map[string]RepoOverride` | url, group, branch, scope, claude, env, files, setup_dir, read_env_example, env_example_policy, env_output |
| `[content]` | `ContentConfig` | deprecated alias for `[claude.content]`, removed at v1.0 (config.go:517-528) |
| `[claude]` | `ClaudeConfig` | enabled, plugins, marketplaces, hooks, settings, env, work_summary_hooks, pr_body_hook, content |
| `[env]` | `EnvConfig` | files, vars, secrets — each with required/recommended/optional sub-tables |
| `[files]` | `map[string]string` | per-repo file distribution |
| `[instance]` | `InstanceConfig` | claude, env, files |
| `[root]` | `RootConfig` | files only |
| `[vault]` | `*VaultRegistry` | provider config |

**Structural cost of adding a policy declaration.** Mechanically near zero: one
struct field with a `toml` tag, plus optional checks in `validate()`
(config.go:571). Unknown fields are non-fatal — `Parse` collects
`md.Undecoded()` into warnings (config.go:545-547), so an older niwa reading a
newer config warns and continues.

That forward-compat property is a *problem* for a policy specifically: an old
niwa would silently ignore a declared mandate rather than refuse to run. For env
vars, degrade-and-warn is right; for "this workspace requires the planning
workflow," silent ignore is the wrong failure mode. Flagged as an open question.

The real cost is not the struct field — it is **placement**, because two
existing mechanisms constrain where a policy can go: the override cascade
(`ClaudeConfig` vs the narrower `ClaudeOverride`, config.go:69-75) and the
overlay tombstone (§5).

### 2. The three file tables

`docs/guides/file-distribution.md` states the contract and the Go confirms it:

| Table | Lands at | Name | Tracked? |
|-------|----------|------|----------|
| `[files]` | each managed repo | `.local` infix | yes |
| `[instance.files]` | instance root | verbatim | yes — drift + cleanup |
| `[root.files]` | workspace root | verbatim | **no state store** |

- `[instance.files]` is materialized by `materializeVerbatimFiles` inside
  `InstallWorkspaceRootSettings` (`internal/workspace/workspace_context.go:372-381`).
  Its paths are appended to `written`, which becomes the instance's
  `ManagedFiles`, so drift detection and `cleanRemovedFiles` apply: drop the
  entry, next apply deletes the file.
- `[root.files]` is materialized in `MaterializeWorkspaceRoot`
  (`internal/workspace/root_materializer.go:153-173`) and is explicitly
  overwrite-idempotent with no removal cleanup — the comment says so.

**So `[instance.files]` is the table that distributes non-repo files verbatim
into an instance with full lifecycle.** Answer to the sub-question.

Live evidence for `[files]`: `public/dot-niwa/.niwa/workspace.toml` maps
`"extensions/design.md" = ".claude/shirabe-extensions/"` and four siblings.
`instance.json` shows the result — `<repo>/.claude/shirabe-extensions/design.local.md`
for all ten repos, 50 managed files. Note this workspace uses `[files]` only;
neither `[instance.files]` nor `[root.files]` is in use today.

The `.local` infix exists because a managed repo is a git working tree and niwa
keeps its output matching the `*.local*` gitignore pattern. Instance and
workspace roots are not git repos, so no infix.

### 3. How CLAUDE.md is assembled — generated vs copied

This hierarchy is half generated and half copied, and the distinction decides
where a policy fragment lands.

| File at instance root | Origin | Function |
|---|---|---|
| `CLAUDE.md` | **copied** (with `{var}` expansion) from `[claude.content.workspace] source` | `InstallWorkspaceContent`, `internal/workspace/content.go:28` |
| `workspace-context.md` | **generated** by niwa | `generateWorkspaceContext`, `workspace_context.go:563-600` |
| `.claude/rules/workspace-imports.md` | **generated** by niwa | `writeWorkspaceRulesFile` / `appendToWorkspaceRulesFile`, `workspace_context.go:128-155` |
| `CLAUDE.overlay.md` | **copied** from the overlay clone | `InstallOverlayClaudeContent`, `workspace_context.go:208-235` |
| `CLAUDE.global.md` | **copied** from the personal global config dir | `InstallGlobalClaudeContent`, `workspace_context.go:390` |
| `<workspaceRoot>/CLAUDE.md` | **generated, hardcoded in Go** | `generateRootClaudeContent`, `root_materializer.go:386-430` |

The rules file is the extension point. It is nothing but a list of
`@<absolute-path>` import lines. `writeWorkspaceRulesFile` creates it pointing at
`workspace-context.md`; `InstallOverlayClaudeContent` and
`InstallGlobalClaudeContent` each call `appendToWorkspaceRulesFile` to add
another. The absolute paths are deliberate — the comment at
`workspace_context.go:177-181` says they give workspace-level visibility
"without triggering the 'Allow external CLAUDE.md file imports?' dialog when
starting Claude from a sub-repo directory." So content imported this way reaches
sessions started **inside a repo**, not only at the instance root.

**A generated "required workflows" fragment lands naturally as one more file
next to `workspace-context.md`, appended to the rules file via the existing
`appendToWorkspaceRulesFile`.** It costs one new writer function and one call
site. It inherits managed-file tracking, hashing, drift detection, and deletion
on removal for free, and it reaches sub-repo sessions.

Caveat worth stating plainly: CLAUDE.md-level instruction is exactly the
mechanism that is *already* failing — that is the premise of this exploration.
The generated fragment is the cheapest rung of the spectrum and is necessary,
but on its own it is more of the same medicine.

### 4. Hook distribution — the `gate-online.sh` trace

The full path, end to end:

1. **Source.** `public/dot-niwa/.niwa/hooks/pre_tool_use/gate-online.sh`, a
   git-tracked file in the public workspace config repo.
2. **Declaration.** `public/dot-niwa/.niwa/workspace.toml`:
   ```toml
   [[claude.hooks.pre_tool_use]]
   matcher = "Bash"
   scripts = ["hooks/pre_tool_use/gate-online.sh"]
   ```
   Decoded into `HooksConfig map[string][]HookEntry` / `HookEntry{Matcher, Scripts}`
   (config.go:367-375).
3. **Auto-discovery fallback.** `DiscoverHooks(configDir)`
   (`internal/workspace/discover.go:21`) scans `configDir/hooks/` and fills in
   any event the config does not declare explicitly
   (`workspace_context.go:246-266`). The script would be picked up even without
   the TOML stanza.
4. **Install.** `InstallWorkspaceRootSettings` (`workspace_context.go:276-307`)
   reads each script from `configDir`, writes it to
   `<instanceRoot>/.claude/hooks/<event>/<basename>` at mode `0755`, and records
   `InstalledHookEntry{Matcher, Paths}`.
5. **Wire-up.** `buildSettingsDoc` (`internal/workspace/materialize.go:654`)
   turns `InstalledHooks` into the `hooks` block of `.claude/settings.json`,
   using absolute paths at the instance root (`UseAbsolutePaths: true`).
6. **Per-repo.** The same script also lands in every repo as
   `.claude/hooks/pre_tool_use/gate-online.local.sh`.
7. **Tracking.** All of it appears in `.niwa/instance.json` `managed_files` with
   `sha256:` and a `generated` timestamp.

**This proves niwa can install an arbitrary executable PreToolUse gate with a
tool matcher into every instance and every repo, and track it.** No new
plumbing is needed for a skill-policy gate.

#### The stronger precedent: niwa's built-in, shirabe-aware hook injection

Beyond distributing configured hooks, niwa injects hooks *of its own*, gated on
shirabe adoption, with no config required
(`internal/workspace/materialize.go:449-649`):

- `shirabePluginName = "shirabe"` is a **const in niwa's source**
  (materialize.go:487). `installsShirabePlugin(eff.Plugins)` (materialize.go:525)
  matches `shirabe@shirabe` or bare `shirabe`.
- `workSummaryHookDefaults` (materialize.go:504-508) injects three registrations:
  `post_tool_use`/`Bash` → `shirabe work-summary capture`;
  `user_prompt_submit` → `shirabe work-summary absence`;
  `session_start`/`compact` → `shirabe work-summary compact`.
- `prBodyHookCommand()` (materialize.go:604-606) injects a `pre_tool_use`/`Bash`
  hook running `shirabe pr-body-hook`, described in its own doc comment as
  gating "a malformed `gh pr create` / `gh pr edit` **before it runs**" and
  printing "an allow/deny decision."
- Off switches: `[claude] work_summary_hooks = false` and
  `[claude] pr_body_hook = false`, both tri-state `*bool` where nil means on
  (config.go:38-54). Workspace-scoped, deliberately not merged from per-repo
  overrides (`internal/workspace/override.go:60-70`).
- Dedup: `workSummaryModeInstalled` / `prBodyHookInstalled` (materialize.go:556,
  624) read the installed hook scripts and grep for a marker string, so a
  workspace that declares the hook itself is not double-registered.
- Fail-safe design: every injected command begins
  `command -v shirabe >/dev/null 2>&1 || exit 0`. The PreToolUse one
  additionally must **not** `exec` and must swallow non-zero — the comment at
  materialize.go:592-603 spells out why: "a PreToolUse hook that exits non-zero
  BLOCKS the tool call, and this hook matches every Bash command," so a stale
  binary would brick the session. It falls back to allow.

`shirabe pr-body-hook` is a working, shipped, niwa-injected PreToolUse gate that
denies a tool call when a shirabe convention is violated. **A skill-adherence
gate is the same object with a different subcommand.** And
`work-summary absence` on `user_prompt_submit` is the shipped template for the
softer end of the spectrum — per-turn context injection at prompt-submit time.

#### niwa also ships skills itself

`internal/workspace/rootskills/dispatch/SKILL.md` is `//go:embed`ed into the
binary (`root_materializer.go:16-30`) and materialized by `writeRootSkills`
(root_materializer.go:189-223) to `<workspaceRoot>/.claude/skills/<name>/SKILL.md`.
The walk is generic — "adding a new root skill needs no change here." Project
skills load from the cwd regardless of plugin enablement, which is the stated
reason for the mechanism.

### 5. The public/overlay split, and whether an org owner can set policy privately

Base config: `tsukumogami/dot-niwa` (public), parsed as `WorkspaceConfig`.
Overlay: auto-derived as `<owner>/<repo>-overlay` by `DeriveOverlayURL`
(`internal/config/overlay.go:242`), parsed as a **different, narrower type**,
`WorkspaceOverlay` (overlay.go:18-32). The live instance records
`overlay_url: "tsukumogami/dot-niwa-overlay"` and an `overlay_commit`.

What an overlay **can** set (`OverlayClaudeConfig`, overlay.go:86-92, and the
struct at overlay.go:18-25):

- `[[sources]]` — explicit `repos` list required, auto-discovery forbidden.
- `[groups]`, `[repos]`, `[env]`, `[files]`, `[vault]`.
- `[claude.hooks]` — **appended to base**.
- `[claude.settings]` — base wins per key.
- `[claude.marketplaces]` / `[claude.plugins]` — append-union, explicitly so a
  private overlay can add `repo:`-sourced marketplaces "without exposing those
  repo names in the public base config."
- `[claude.content]` — additive groups/repos, plus a per-repo `overlay =` that
  appends a file to the base repo's `CLAUDE.local.md`.

What an overlay **cannot** do:

- `[files]` destinations beginning `.claude/` or `.niwa/` are rejected outright
  (`isProtectedDestination`, overlay.go:231-235).
- **`[workspace]` is a tombstone.** `OverlayWorkspaceTombstone` (overlay.go:34-45)
  is decoded *solely* to warn that it does nothing; `MergeWorkspaceOverlay`
  never assigns `Workspace` at all. The reasoning is at config.go:312-320, on
  `StrictSecrets`: it lives on `[workspace]` "for a security reason, not a
  taxonomic one … which is what keeps a contributor's first run un-alterable by
  a configuration layer they cannot read."

**This is the decisive placement constraint.**

- Policy under `[workspace]` → an org owner **cannot** set it privately, by
  deliberate design.
- Policy under `[claude]` → overlay-settable in principle, so yes, privately
  settable. But `OverlayClaudeConfig` is an explicit allowlist struct, not a
  passthrough: a new `[claude.skills]` block would need a matching field on
  `OverlayClaudeConfig` **and** merge logic in `MergeWorkspaceOverlay` before an
  overlay could carry it. That inclusion is a conscious decision, not a freebie.

And the `strict_secrets` reasoning cuts directly against making a skill mandate
overlay-settable: a mandate changes what an agent does for a contributor who
cannot read the layer imposing it. That is the exact class of setting the
tombstone exists to keep out of overlays. Genuine tension — see Open Questions.

One existing asymmetry worth noting: an overlay cannot write into `.claude/` via
`[files]`, but `[claude.hooks]` overlay entries are appended to base and their
scripts *are* installed into `.claude/hooks/`. So an overlay can already install
an executable gate today by the hooks path, just not by the files path.

### 6. What happens on apply — regeneration, drift, tracking

- **Config refresh is same-run.** `.niwa/` is a snapshot (no `.git`),
  atomically re-fetched and swapped on each apply. `docs/guides/workspace-config-sources.md`
  §"Same-run effect": push a new `[claude.settings]` posture, plugin, or hook
  upstream and "the next single command materializes it. You never need a second
  run." Exceptions: a legacy git-working-tree `.niwa/` (one conversion run
  lags), a registry entry with no marker and no `.git` (never reconciles, issue
  #215), and worktrees (never reconcile by design — converge the instance).
- **State.** `.niwa/instance.json` is `schema_version: 4` and carries 104
  `managed_files`, each `{path, hash: "sha256:…", generated}`. `ManagedFile`
  (`internal/workspace/state.go:174-186`) also carries `SourceFingerprint` and
  `Sources` as of schema v2, which lets `niwa status` distinguish user-edited
  drift from a legitimate upstream change.
- **Drift.** `CheckDrift` (state.go:660) re-hashes and compares against the
  recorded hash. Drift is *reported*, not preserved — managed files are
  overwritten unconditionally on each apply. A user cannot durably edit away a
  niwa-installed hook script; they can only remove the declaration upstream.
- **Cleanup.** `cleanRemovedFiles` (`internal/workspace/apply.go:1846-1859`)
  deletes any file in the prior state not produced by the current run. There is
  a matching discipline at `workspace_context.go:366-370`: only the hook scripts
  an apply actually installed are tracked, never a directory walk, "so a hook
  script no longer declared by any config … is pruned by cleanRemovedFiles on
  the next apply."
- **Exception.** The workspace root has no managed-file state store, so
  `[root.files]`, root `settings.json`, root `CLAUDE.md`, and root skills are
  re-written every apply but never removal-cleaned.

Net: a declared policy would propagate on the next single niwa command, its
artifacts would be hashed and drift-checked, and retracting the declaration
would delete them.

### 7. Is there any existing notion of policy or requirement in niwa?

**Yes — three, plus a fourth pattern. This would not be the first; there is a
house style to follow.**

**(a) Graded env-key requirements.** `[env.secrets.required]` /
`.recommended` / `.optional` (`EnvVarsTable`, config.go:215-220), enforced by
`checkRequiredKeys` (`internal/workspace/required.go:51-84`). The rule is
"strict-when-reachable": a required key is fatal *only* when a provider was
configured, was reachable, and reported it does not hold the key
(`collectMissing`, required.go:105-125). Recommended warns to stderr; optional is
silent. The dot-niwa config's own comment makes the authoring contract explicit:
each description "is the only explanation a contributor gets — niwa cannot tell
them where a value was supposed to come from."

**(b) `[env_example_policy]` — the closest template.** A genuine graded policy
with `warn` / `fail` actions (`Action`, `internal/config/env_example_policy.go:9-34`),
three levels (user / project / per-repo), a per-variable `vars` sub-table that is
project-scope only, an inline in-repo annotation rung (`# niwa: fail` in
`.env.example`), a one-run de-escalation flag (`--allow-plaintext-secrets`), a
separate whole-feature off switch (`read_env_example = false`), and a documented
four-step precedence resolved by `EffectiveEnvExamplePolicy`
(env_example_policy.go:120-156). Guide coverage: `docs/guides/workspace-config-sources.md`
§".env.example failure policy".

**(c) `[workspace] strict_secrets`.** Tri-state opt-in to fail rather than
degrade, with flag-beats-setting-beats-default precedence in
`ResolveStrictSecrets` (config.go:335-343), and the security-motivated placement
discussed in §5.

**(d) Default-on-with-off-switch.** `work_summary_hooks` and `pr_body_hook`
(§4): niwa decides, the workspace can opt out.

(b) is the shape I would copy for a skill policy: graded actions, level cascade,
per-item override, an escape hatch, and a documented precedence.

---

## Implications

**The distribution question is settled and is not the hard part.** Every surface
a skill policy could want is already a tracked, hashed, drift-detected,
cleaned-up managed file: CLAUDE.md fragments imported by absolute path (reaching
sub-repo sessions), `.claude/settings.json`, executable hook scripts at the
instance root and in every repo, verbatim instance-root files, and embedded
skills. The work is declaration and decision logic, not plumbing.

**The `pr-body-hook` is a complete, shipped proof of the strongest rung.** A
niwa-injected, shirabe-plugin-gated, tool-matched PreToolUse hook that inspects a
command and returns allow/deny, with a fail-safe fallback and a workspace off
switch, already exists and runs in this instance. Whatever the exploration
decides about *what* to gate on, *how* to gate is answered.

**Division of labor is already established: niwa declares and distributes,
shirabe decides.** niwa injects `shirabe pr-body-hook` and knows nothing about PR
bodies. A skill policy should follow that line — the workspace config should not
try to encode when a workflow applies. That belongs to a `shirabe` subcommand.
This keeps the niwa-side surface small and keeps policy logic versioned with the
skills it governs.

**Placement is the one genuinely contested decision.** `[workspace]` is
overlay-proof by design; `[claude]` is overlay-reachable but needs an explicit
`OverlayClaudeConfig` field to become so. The choice is not taxonomic — it
decides whether an org owner can impose a workflow mandate that contributors
cannot read. The user's stated requirement ("give that as a configuration option
to org owners") and niwa's existing security reasoning point in opposite
directions here, and the exploration should resolve it deliberately rather than
by default.

**The spectrum maps onto four existing mechanisms, none of them new.**
`off` = nothing; `advertise` = a generated CLAUDE.md fragment via
`appendToWorkspaceRulesFile`; `remind` = a `user_prompt_submit` hook on the
`work-summary absence` template; `gate` = a `pre_tool_use` hook on the
`pr-body-hook` template. The whole spectrum the user asked to have mapped is
implementable with the parts already in the binary.

**Given the stated preference for guidance over enforcement**, `remind` is the
interesting rung and it is the least-explored one — `work-summary absence` is
the only existing user-prompt-submit injection, and understanding what it does
is the highest-value follow-up (lead-hook-surfaces territory).

---

## Proposed declaration

### Where

`[claude.skills]`, workspace-level, with a per-repo override at
`[repos.<name>.claude.skills]`.

Rationale: `[claude]` is where plugin and skill concerns already live
(`plugins`, `marketplaces`), it rides the existing override cascade, and it is
the only position an overlay can reach. Per-repo matters because a policy that
is wrong for one repo (a docs repo, a config repo) gets disabled everywhere if
it is workspace-only — the `env_example_policy` precedent has exactly this
level, for exactly this reason. Implementation touches `ClaudeConfig` and
`ClaudeOverride` (config.go:28-75); `OverlayClaudeConfig` only if the split
question resolves toward overlay-settable.

### Sketch

```toml
[claude.skills]
# How hard niwa pushes. Weakest to strongest:
#   "off"       - nothing
#   "advertise" - generate a CLAUDE.md fragment naming the workflows
#   "remind"    - advertise, plus a UserPromptSubmit hook that restates
#                 the policy when shirabe judges it unsatisfied
#   "gate"      - remind, plus a PreToolUse hook that can deny the tool
#                 call that would bypass the workflow
enforcement = "remind"

# The workflows this workspace sanctions. The description is not a comment:
# it is the text that lands in the generated CLAUDE.md fragment and in the
# reminder, so it is the only explanation an agent gets. Same authoring
# contract as [env.secrets.recommended].
[claude.skills.required]
"shirabe:plan"    = "Decompose anything larger than a single-file change into sequenced issues before writing code."
"shirabe:work-on" = "Drive an issue to a merged PR. Do not hand-roll a branch/commit/PR loop."
"shirabe:design"  = "Decide how to implement something before implementing it."

[claude.skills.recommended]
"shirabe:explore" = "Use when the artifact type is not obvious yet."

# One repo relaxes the workspace level.
[repos.website.claude.skills]
enforcement = "advertise"
```

Plus the off switch, mirroring `work_summary_hooks` / `pr_body_hook` exactly:

```toml
[claude]
skill_policy_hook = false   # suppress the injected hook; default on
```

### What it has to carry

1. **A level.** The single knob spanning the spectrum. Modeled on
   `Action`/`UnmarshalText` (env_example_policy.go:9-34) so an invalid value is a
   parse error naming the accepted set, not a silent fallback.
2. **The sanctioned workflows, each with a human sentence.** `required` /
   `recommended` sub-tables keyed by skill reference, matching the `EnvVarsTable`
   idiom. The description feeds the generated fragment and the reminder.
3. **A scope.** Workspace default plus per-repo override, with unset meaning
   inherit (the `*Action`-pointer idiom throughout niwa).
4. **An off switch and a per-run escape.** `env_example_policy` has both
   (`read_env_example = false` and `--allow-plaintext-secrets`). A gate with no
   escape is the thing that gets ripped out wholesale the first time it is wrong.
   Suggested analogue: `niwa apply --no-skill-gate` for the distribution side and
   an env-var downgrade for the session side.
5. **Nothing about *when* a workflow applies.** Per the `pr-body-hook` precedent,
   that decision belongs to a `shirabe` subcommand, not to workspace config.

### Where it hooks in mechanically

Three sites, all existing:

- **Parse** — add `Skills` to `ClaudeConfig` and `ClaudeOverride`
  (`internal/config/config.go`); add to `OverlayClaudeConfig` plus merge logic
  only if the policy is to be overlay-settable.
- **Context** — a new writer beside `InstallWorkspaceContext`, writing e.g.
  `<instanceRoot>/workflow-policy.md` and calling the existing
  `appendToWorkspaceRulesFile` (`workspace_context.go:137`). Inherits tracking,
  hashing, and deletion-on-retraction.
- **Hook** — `resolveSkillPolicyHook(eff, installed)` beside `resolvePrBodyHook`
  (`materialize.go:644`), feeding a new field on `BuildSettingsConfig`, emitting
  `command -v shirabe >/dev/null 2>&1 || exit 0; shirabe skill-gate 2>/dev/null || exit 0`
  — the non-`exec`, error-swallowing form the PreToolUse comment at
  materialize.go:592-603 requires.

---

## Surprises

**niwa is already shirabe-aware in its own source, and it is load-bearing.**
`shirabePluginName = "shirabe"` is a const in niwa (materialize.go:487), and
four hooks are injected by default on the strength of it. The coupling this
exploration is contemplating is not a new dependency to justify — it already
exists and already ships.

**niwa already writes an instruction to invoke a specific skill at a specific
moment into generated context.** `generateRootClaudeContent`
(root_materializer.go:410-418) tells a root session: "When you have been
discussing what to build and are ready to hand the work off … invoke the
`/dispatch` skill." So "declare a required workflow in generated CLAUDE.md" is
not hypothetical — it shipped. It is just hardcoded in Go rather than
configurable, and it is exactly one workflow. Whether it *works* is a live
question and would be worth measuring, since it is the same lever the
`advertise` rung would pull.

**niwa can ship a skill, not just point at one.** `//go:embed rootskills` plus a
generic walk (root_materializer.go:189) materializes any embedded
`<name>/SKILL.md` as a project skill loaded from the cwd regardless of plugin
enablement. A policy enforcement path that needs a skill guaranteed present,
independent of marketplace resolution, already has a delivery route.

**`[workspace]` is deliberately overlay-proof, and the stated reason applies
uncomfortably well here.** The tombstone (overlay.go:34-45) and the
`StrictSecrets` comment (config.go:312-320) exist to stop a private layer from
changing what a contributor's run does. A skill mandate is arguably the same
class of setting. This turns "can an org owner set it privately" from a
plumbing question into a values question niwa has already answered once, in the
opposite direction from what the user asked for.

**An overlay cannot write into `.claude/` via `[files]` but can install
executables there via `[claude.hooks]`.** `isProtectedDestination`
(overlay.go:231) blocks the former; the hooks path installs 0755 scripts into
`.claude/hooks/` unimpeded. Pre-existing asymmetry, not introduced by anything
here, but relevant to any reasoning that treats `.claude/` as overlay-protected.

**The PreToolUse footgun is already documented in niwa's source.** The comment
at materialize.go:592-603 explains that a PreToolUse hook matching every Bash
command must not `exec` and must swallow non-zero, because a non-zero exit
blocks the call and a stale binary would brick every session. A skill gate would
hit this on day one; the fix is already written down.

---

## Open Questions

1. **Should the policy be overlay-settable?** The user asked for an org-owner
   configuration option, which suggests private declaration. The `strict_secrets`
   precedent says a setting that changes what a contributor's run does must live
   where the contributor can read it. Needs a deliberate call, and it changes
   whether `OverlayClaudeConfig` grows a field. (Human input.)

2. **Built-in default-on, or explicit declaration?** `pr_body_hook` needs no
   config — every shirabe adopter gets it, with an off switch. That path reaches
   the most sessions and matches how the closest sibling shipped. Explicit
   declaration matches the user's framing ("give that as a configuration option
   to org owners") and is more conservative. These are not exclusive: a built-in
   `advertise`/`remind` default with declaration required to reach `gate` is a
   plausible middle, but it needs deciding.

3. **What does `shirabe skill-gate` actually inspect, and what does it deny?**
   Out of this lead's scope and squarely lead-hook-surfaces / lead-skill-firing-mechanics
   territory. But the config shape depends on the answer: if the gate needs only
   a tool matcher, the sketch above suffices; if it needs richer per-workflow
   trigger conditions, `[claude.skills]` grows.

4. **What does `shirabe work-summary absence` do today?** It is the only shipped
   `user_prompt_submit` injection and therefore the closest existing model for
   the `remind` rung. Worth reading before designing a second one — it may
   already be most of the mechanism, or it may show why per-turn injection does
   not land.

5. **Forward-compat failure mode.** Unknown TOML fields warn and continue
   (config.go:545-547). An older niwa would silently ignore a declared mandate.
   For a policy that is the wrong default. Does this want a minimum-version
   assertion, or is warn-and-continue acceptable?

6. **Is per-repo granularity worth the surface?** `env_example_policy` has it and
   uses it. A skill policy might not need it if the level is coarse enough. Costs
   a `ClaudeOverride` field and merge coverage.

7. **Does anything verify a required skill is actually installed?** Declaring
   `"shirabe:plan"` as required in a workspace whose `[claude] plugins` omits
   shirabe is a silent no-op today. A validation pass at `validate()`
   (config.go:571) could catch it, in the spirit of `checkRequiredKeys`.

---

## Summary

niwa already injects a shirabe-specific PreToolUse allow/deny gate
(`shirabe pr-body-hook`) plus three work-summary hooks into any instance that
installs the shirabe plugin, by default, gated on a `shirabePluginName` const in
niwa's own source and controlled by a `[claude] pr_body_hook = false` off switch
— so the entire spectrum from advertise (a generated CLAUDE.md fragment) through
remind (a `user_prompt_submit` hook) to gate (a `pre_tool_use` hook) is
buildable from parts already shipping in the binary. The exploration's real work
is therefore deciding what the gate inspects and how hard it pushes, not how to
distribute it; the declaration belongs in `[claude.skills]` carrying a level, a
required/recommended map of skill-to-human-sentence, a per-repo override, and an
escape hatch, modeled on the existing `[env_example_policy]` graded policy. The
biggest open question is a values question rather than a plumbing one:
`[workspace]` is deliberately overlay-proof (overlay.go:34-45, config.go:312-320)
specifically to stop a private layer from changing what a contributor's run does,
so letting an org owner declare a skill mandate privately runs against reasoning
niwa has already committed to once.

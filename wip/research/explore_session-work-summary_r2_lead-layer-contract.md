# Lead: What is the contract between the shirabe layer and the niwa hook layer?

## Findings

### (a) Ownership today: no marker, no ledger — but one cross-layer state read already exists (and it's broken)

There is no work-summary marker string or ledger file anywhere yet. The closest existing artifact is instructive as a negative precedent:

- dot-niwa's Stop hook (`public/dot-niwa/.niwa/hooks/stop/workflow-continue.sh`) globs `$CWD/wip/*-state.json` and evaluates `.issues[] | select(.status != "completed" ...)` — a niwa-delivered hook hard-coupled to a state-file schema it does not own.
- That schema belongs to the legacy `implement-doc` flow (`wip/implement-doc_<name>_state.json`). shirabe's `/execute` has since moved to `wip/execute_<topic>_state.md` — YAML-in-`.md` under the `wip-yaml-md` substrate (`public/shirabe/skills/execute/SKILL.md` lines 70, 335-351). The hook's `*-state.json` glob never matches it, so the safety net silently no-ops for every current execute run. This is version skew in production, today, in exactly the design shape being considered ("the state file is the contract").

Ownership recommendation grounded in the code:

- **Marker string + template**: shirabe. Precedent: the coordination PR's declaration marker is fixed text that another layer greps — "do not paraphrase it (`lifecycle.yml` greps for it)" (`public/shirabe/references/coordination-strategy.md`, Slot rules). shirabe already owns exact-string cross-layer markers.
- **Dedupe/ledger state**: the hook, alone. It should be hook-private, keyed by `session_id` (present in hook stdin JSON, as workflow-continue.sh shows for `cwd`/`stop_hook_active`), and live outside the repo tree (e.g. `${XDG_RUNTIME_DIR:-/tmp}/niwa-work-summary/<session_id>.json`). Putting it in `wip/` is wrong twice: wip/ is *committed* on feature branches (CLAUDE.md forbids gitignoring it), so a per-session timestamp file becomes commit noise; and multi-repo sessions have many `wip/` dirs but one session.
- **Location of the template**: `references/` in the shirabe plugin (loaded with the skills), not a distributed file — see (b).

### (b) How a niwa-delivered hook can reference a shirabe-owned template

Three channels, evaluated against the actual materializer:

**1. The shirabe-extensions `[files]` channel.** `public/dot-niwa/.niwa/workspace.toml` lines 55-60 map `extensions/<skill>.md` -> `.claude/shirabe-extensions/`. niwa's `FilesMaterializer` (`public/niwa/internal/workspace/materialize.go` lines 1128-1297) force-inserts a `.local` infix — `localRename` at lines 1106-1126, applied even to explicit filenames via `injectLocalInfix` (line 1286) — so a niwa-shipped file can only ever land as `<skill>.local.md`. That is why every shirabe SKILL.md imports *both* slots (`@.claude/shirabe-extensions/work-on.md` + `work-on.local.md`, `public/shirabe/skills/work-on/SKILL.md` lines 6-7): the non-.local slot is project-committed (shirabe's own repo commits a `work-on.md` verification map), the `.local` slot is niwa-distributed and gitignored. Content is sha256-fingerprinted (`writeManagedFile`, lines 1250-1257) so upstream edits rotate cleanly on `niwa apply`. Staleness: bounded by apply cadence, with drift detection. Limitation: extension files load only when the importing skill runs — they cannot carry instructions for a hook firing outside any skill.

**2. A path into the installed plugin cache.** The cache is versioned per plugin: `~/.claude/plugins/cache/shirabe/shirabe/<version>/` with many versions co-resident (0.1.0 through 0.13.x observed); which is active lives in `installed_plugins.json`. A hook hardcoding such a path must resolve the active version itself, breaks on dev versions, and depends on a Claude Code internal layout. Worst skew profile; reject.

**3. Text in the hook's nudge.** Hook script bytes are copied per-repo to `.claude/hooks/<event>/<name>.local.sh` and fingerprinted exactly like `[files]` content (`HooksMaterializer`, materialize.go lines 178-246), so freshness equals channel 1. The distinction that matters is *what* the text says. If the nudge **embeds the template**, there are two sources of truth and skew shows up as silent wording divergence. If the nudge **names the convention** ("emit the work-in-flight summary per the shirabe `references/work-in-flight.md` convention; if shirabe isn't installed, list open PRs with links"), the model resolves the template from the *active plugin version* at runtime — the hook is automatically version-matched because the template ships with the same plugin release as the skills that emit it. This is the key structural insight: the template must live where the model already loads version-matched content (the plugin), and the hook should carry only a name-reference plus a fallback.

**Hook double-install, root cause found.** `workspace.toml` declares both hooks explicitly (`[[claude.hooks.pre_tool_use]]` / `[[claude.hooks.stop]]`, lines 17-22) *and* `DiscoverHooks` auto-discovers the same scripts from `.niwa/hooks/<event>/*.sh` (`public/niwa/internal/workspace/discover.go` lines 21-69). The merge in `runRepoMaterializers` (`public/niwa/internal/workspace/worktree_content.go` lines 70-102) deliberately keeps both — "Explicit config runs before discovered hooks ... must not silently discard user-authored discovered hooks" — with no dedupe by resolved script path. Result, verified in `public/tsuku/.claude/settings.local.json` and `public/shirabe/.claude/settings.local.json`: every hook is registered twice per event (the PreToolUse pair once with `matcher: Bash`, once without). Consequence for this design: a summary hook may fire twice per event, so its dedupe state must make the second invocation a no-op; and the new hook should be registered through exactly one channel (auto-discovery only — drop the TOML entry) until niwa dedupes by script path.

### (c) Emission points by layer

Skill-layer boundaries (shirabe owns these; all already produce or hold the data):

- `/work-on` `pr_creation` state — `pr_url` is typed koto evidence (`public/shirabe/skills/work-on/koto-templates/work-on.md` lines 695-718); `ci_monitor` outcomes follow.
- `/execute` `pr_finalization` -> `paused_for_review` — the one place in the corpus that already instructs handing the DRAFT PR URL to the user in chat (`public/shirabe/skills/execute/koto-templates/execute.md` lines 427, 491-501).
- Coordinated mode re-authors the PR Index (`<node-id> | owner/repo:path#number | <merge-state>`) in the coordination PR body on every loop pass (`public/shirabe/references/coordination-strategy.md` lines 89-112) — the natural data source for a multi-PR summary render.

Hook-layer moments (niwa/dot-niwa owns these; nudge-only):

- PostToolUse on Bash matching PR-changing commands (`gh pr create|merge|close|ready`) — sets a dirty flag in hook state. Note: PostToolUse receives the tool's input/output, so the hook *could* extract the PR URL mechanically, but should only flag, not render (rendering is shirabe's).
- UserPromptSubmit (return-after-absence: compare now against last-activity timestamp in hook state; inject additionalContext nudge when gap exceeds threshold AND dirty flag set or PR set nonempty).
- Stop is available (workflow-continue.sh shows block-with-reason mechanics) but is the wrong moment for a summary nudge except as a final "hand back links" reminder.

Dedupe handshake: the hook cannot read chat, so "the skill just emitted" must become observable. Two workable mechanisms: (1) the shirabe emission rule ends with one trivial observable command (`touch`/write of the hook's session state file) that clears the dirty flag — a Bash command the PostToolUse hook itself can recognize; (2) accept asymmetry: only the hook clears its own flag when it nudges, and a skill emission followed by one redundant hook nudge is tolerated. Mechanism 1 is cleaner; mechanism 2 is simpler and has no failure mode when shirabe is absent.

### (d) Precedents for cross-layer contracts in this workspace

1. **shirabe-extensions @import** — shirabe owns the import site and the schema doc (`skills/work-on/references/verification-map.md`); the project/niwa owns content; absence degrades gracefully ("If no extension file exists ... the skill proceeds with generic behavior", `skills/work-on/SKILL.md` line 289). Loose coupling with a defined fallback: the best precedent.
2. **koto evidence keys** — shirabe templates declare typed evidence (`pr_url: type: string, required`) that the koto engine enforces; contract and consumer version together because the template ships in the plugin.
3. **wip state projection** — `/execute`'s state file is "a reconstructable per-session projection, not the source of truth" (`skills/execute/SKILL.md` lines 343-351); truth is the durable home PR. Precedent: state files are disposable caches, never the contract.
4. **Negative precedent** — workflow-continue.sh's coupling to `wip/*-state.json` (see (a)): a hook that owns a schema it doesn't version with its producer goes stale silently.
5. **Fixed-text marker** — the coordination declaration marker greped by lifecycle.yml: shirabe can own an exact string another layer matches.

### Three contract designs

**Design A — convention-by-name, shirabe-canonical template (recommended).**
Who writes what: shirabe adds `references/work-in-flight.md` (template: PR list with links, states, next action; marker line; emission rules) and one-line emission hooks in work-on/execute at the (c) boundaries. dot-niwa adds `hooks/post_tool_use/work-summary-flag.sh` + `hooks/user_prompt_submit/work-summary-nudge.sh` (registered via auto-discovery only), whose nudge text names the shirabe convention and carries a generic fallback. Dedupe: hook-private state at `/tmp/.../<session_id>.json` holding `{last_activity_ts, last_nudge_ts, pr_dirty, pr_set_hash}`; idempotent against double-registration. shirabe-without-niwa: skill-boundary emission still happens; no absence reminders — acceptable degradation. niwa-without-shirabe: fallback text still yields a useful `gh pr list`-style summary. Version skew: none structural — the hook names, never restates, the template; the template always matches the installed skills because they ship together.

**Design B — the ledger file is the contract** (`.niwa/work-ledger.json` at instance root, or workspace root). Hook appends mechanically from PostToolUse tool output (it can — it sees `gh pr create` stdout); skills append at pr_creation; a renderer reads it. Real advantage: PR capture works even when the model ignores instructions. Fatal drawbacks: schema ownership is ambiguous (who versions it? shipped in neither layer's release artifact); the workspace already demonstrates the failure mode (finding (a)); a per-repo location collides with wip-hygiene and commit noise, while an instance-root location makes the shirabe side depend on niwa's directory layout (breaking shirabe-without-niwa entirely); GC/retention is unowned. Skew is hard breakage: old hook writes v1 while new skill expects v2.

**Design C — shirabe-extensions carries the emission rule.** dot-niwa adds emission instructions to `extensions/work-on.md` / a new `extensions/execute.md`; shirabe core is untouched. Cheap and immediately deployable (no shirabe release), and the `.local` distribution channel with fingerprinting already works. But the convention becomes workspace-local (every workspace re-authors it), extensions load only inside skill runs (no return-after-absence coverage at all — the hook would have nothing to point at), and execute currently has no extension import declared (only design/explore/plan/prd/work-on/brief/vision/strategy/roadmap/decision do). Right as a bootstrap, wrong as the owner.

**Recommendation: A**, optionally bootstrapped via C while a shirabe release is pending. Any state file exists only as a hook-private cache (design A's dedupe blob), never as a cross-layer schema — per precedent 3, truth stays in GitHub (`gh pr list`, the PR Index) and the state file is reconstructable/disposable.

## Implications

- The contract should be **a named convention plus a fallback**, not a shared file schema. The plugin is the only channel where template and emitter are guaranteed version-matched; the hook layer should reference it by name and degrade to a generic PR listing when shirabe is absent.
- The `[files]` channel's forced `.local` rename means niwa can never own the non-.local extension slot; anything niwa distributes is by construction gitignored and per-instance — fine for workspace-specific emission rules (design C), unusable for a durable canonical template.
- Whoever lands the dot-niwa hook must pick one registration channel. Today's explicit-TOML + auto-discovery double-registration would fire the nudge twice per event; the fix is either dropping the `[[claude.hooks.*]]` entries (auto-discovery covers them) or a niwa-side dedupe by resolved script path in `runRepoMaterializers`.
- The existing Stop hook needs updating regardless of this feature: its `wip/*-state.json` glob no longer matches `/execute`'s `wip/execute_<topic>_state.md`, so the workflow-continuation safety net is dead for current shirabe workflows.

## Surprises

1. **The double-install bug is confirmed and located**: explicit `[[claude.hooks.*]]` entries and `DiscoverHooks` auto-discovery both register the same scripts, and the merge at `public/niwa/internal/workspace/worktree_content.go:70-102` keeps both by design; every repo's settings.local.json carries each hook twice.
2. **The workspace already contains a live example of the ledger-as-contract failure**: workflow-continue.sh reads a state-file schema (`wip/*-state.json`, `.issues[]`) that shirabe's execute no longer writes — the hook silently no-ops today.
3. **The `.local` rename is unconditional**, even for explicit destination filenames (`injectLocalInfix`, materialize.go:1286) — the dual `@import` in every SKILL.md exists precisely because niwa physically cannot deliver the non-.local slot.
4. The plugin cache keeps every historical version side by side (`~/.claude/plugins/cache/shirabe/shirabe/<version>/`), so no hook-stable path into it exists.

## Open Questions

- Exact hook-output semantics per event in the current harness: which events honor `additionalContext` vs `decision: block` (workflow-continue.sh proves Stop/block; UserPromptSubmit additionalContext needs confirming in this Claude Code version).
- Where the return-after-absence timestamp is refreshed from: a PostToolUse hook on every Bash call is the cheapest heartbeat, but requires the hook to run on all Bash, not just `gh pr` matches.
- Whether the skill-side "clear the dirty flag" handshake (one observable `touch` command in the emission rule) is worth the coupling, or whether one redundant nudge after a skill emission is acceptable.
- Whether niwa should fix hook registration dedupe upstream (by resolved script path) rather than relying on config discipline in dot-niwa.

## Summary

The contract should be convention-by-name: shirabe owns the template, the exact marker text, and the skill-boundary emission rules in a plugin-shipped `references/work-in-flight.md` (version-matched to the skills by construction), while the niwa/dot-niwa hook nudges by naming that convention with a generic `gh pr list` fallback, and owns a private, disposable per-session dedupe file outside the repo tree — never a shared ledger schema. The workspace already demonstrates why a shared state-file contract fails: dot-niwa's Stop hook still greps `wip/*-state.json` while `/execute` moved to `wip/execute_<topic>_state.md`, so that hook silently no-ops today; separately, the hook double-install is confirmed and root-caused to explicit TOML entries plus auto-discovery both surviving the merge in niwa's `runRepoMaterializers`. The `[files]`/shirabe-extensions channel force-renames everything to `.local` and only loads during skill runs, making it a fine bootstrap carrier for workspace-specific emission rules but structurally incapable of hosting the canonical template or serving hooks that fire outside skills.

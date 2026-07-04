# Lead: What is the re-cut division of labor under the deterministic design?

## Findings

### 1. Empirical check: dynamic context injection works on 2.1.201 (two passing runs)

Built `/home/dangazineu/.claude/jobs/a050f0e4/tmp/skill-lab/.claude/skills/teststatus/SKILL.md` with distinctive markers around `` !`date +%s` `` and an instruction to relay the number verbatim without running tools.

- Run 1 (`allowed-tools: Bash(date *)`, `--dangerously-skip-permissions`): expected epoch ~1783139393, model answered `BEACON=1783139395` — real command output, executed at preprocessing time (+2s startup), relayed by the model.
- Run 2 (`teststatus2`, **no** `allowed-tools`, **no** `--dangerously-skip-permissions`): expected 1783139527, model answered `BEACON=1783139527` — exact match.

Conclusion: injection is genuine preprocessing ("Claude Code runs the command and replaces the line with its output before Claude sees the skill content" — code.claude.com/docs/en/skills, "Inject dynamic context"). It is not permission-gated and needs no `allowed-tools` frontmatter for the injected command itself. The only kill switch is the `disableSkillShellExecution` policy setting, which replaces each command with the literal text `[shell command execution disabled by policy]`. Syntax constraints from docs: `!` must start a line or follow whitespace; ` ```! ` fenced blocks for multi-line; output is not re-scanned for nested placeholders. `disable-model-invocation: true` additionally keeps the skill description out of ambient context (docs frontmatter table) — appropriate for /status since only users invoke it.

So **/status can be "script output relayed by the model"**: the skill body is one injection line plus relay instructions, and the model never needs to run gh itself on the happy path.

### 2. Script placement: the single implementation must live in dot-niwa; shirabe probes a well-known path

Evidence per layer:

**niwa's hooks channel** (`public/niwa/internal/workspace/materialize.go`): `HooksMaterializer.Materialize` (lines 174–246) copies each configured script from the config dir into `{repoDir}/.claude/hooks/{snake_case_event}/{name}.local.sh` (`localRename`, line 1106+), chmods 0755, and records a sha256 `VersionToken` per source so an upstream edit is treated as rotation, not local drift — fingerprinted updates come for free. `InstalledHooks` then feeds the `SettingsMaterializer`, which writes a `hooks` block into `settings.local.json` with PascalCase events (`hookEventMapping`, lines 255–262; hooks-block build at lines 434–478). This is confirmed live: `public/dot-niwa` ships `.niwa/hooks/pre_tool_use/gate-online.sh` and `.niwa/hooks/stop/workflow-continue.sh`, materialized as `.claude/hooks/pre_tool_use/gate-online.local.sh` etc. There is also a generic **`[files]` channel** (`FilesMaterializer`, lines 1128+; scaffold comment at `scaffold.go:65-79`): arbitrary config-dir files copied per-repo with the `.local` infix (gitignored), e.g. `[files] "scripts/render-work-in-flight.sh" = ".claude/hooks/"` → `.claude/hooks/render-work-in-flight.local.sh`. So a non-hook helper script has a natural, fingerprinted, per-repo delivery path with a **predictable absolute location under `$CLAUDE_PROJECT_DIR`**.

**shirabe's script shipping today**: skills already bundle scripts under `skills/<name>/scripts/` — `skills/plan/scripts/` (render-template.sh, validate-plan.sh, create-issues-batch.sh, ...), `skills/execute/scripts/` (preflight.sh, run-cascade.sh), `skills/work-on/references/scripts/extract-context.sh`. Skill bodies path them via `${CLAUDE_PLUGIN_ROOT}` (e.g. `skills/execute/SKILL.md:129` — `bash ${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/preflight.sh`). PR #216's self-resolution pattern is in `skills/execute/scripts/preflight.sh:19`: `ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"` — prefer the env var, fall back to the script's own location. So shirabe has solved plugin-root resolution *for scripts invoked from its own skill bodies*.

**Does ${CLAUDE_PLUGIN_ROOT} fix the version-unstable cache path for hooks?** Only for **plugin-registered** hooks. Docs (code.claude.com/docs/en/hooks): plugins ship `hooks/hooks.json` at plugin root; `${CLAUDE_PLUGIN_ROOT}` is expanded in `command`/`args` and exported as an env var to the spawned process — but that machinery belongs to the plugin hook channel. A dot-niwa-materialized hook registered via `settings.local.json` receives only `CLAUDE_PROJECT_DIR`; it has no reliable way to find the shirabe plugin cache (round 2's version-instability finding stands for that direction). Also relevant: the skills docs substitution table exposes `${CLAUDE_SKILL_DIR}` and (v2.1.196+) `${CLAUDE_PROJECT_DIR}` in skill bodies, explicitly "in bash injection commands" — so a shirabe skill *could* bundle and invoke its own script, and a shirabe skill can also address a project-local path.

**Resulting placement decision.** Of the three options:
- *Plugin-shipped script, hooks call into plugin*: dead — dot-niwa hooks can't resolve the plugin path.
- *Duplicated script in both layers, grammar as contract*: works but reintroduces exactly the version-skew the lead asks to avoid, and shirabe-only mode would need the ledger schema to be useful — colliding with the no-shared-state-schema precedent (workflow-continue.sh).
- **dot-niwa ships the single render script; shirabe /status probes the well-known materialized path** — the only option where both layers execute one implementation. The cross-layer contract shrinks to (a) the well-known path `.claude/hooks/render-work-in-flight.local.sh` under `$CLAUDE_PROJECT_DIR`, and (b) "it prints a self-describing `=== WORK IN FLIGHT ===` block". The ledger file format stays entirely private to dot-niwa (hook writes it, render script reads it), honoring the workflow-continue.sh precedent. The /status injection line is roughly:
  `` !`R="${CLAUDE_PROJECT_DIR:-.}/.claude/hooks/render-work-in-flight.local.sh"; [ -x "$R" ] && "$R" || echo "NO-RENDERER"` ``
  (2.1.201 > 2.1.196, so `${CLAUDE_PROJECT_DIR}` substitution is available; a cwd-relative probe is the belt-and-suspenders fallback.)

The dot-niwa PostToolUse capture hook reaches the render script by the preflight.sh self-resolution trick (`dirname "${BASH_SOURCE[0]}"` — both live under `.claude/hooks/`), then emits the block as `systemMessage` (user-visible) and `hookSpecificOutput.additionalContext` (model-visible) — both fields confirmed in the PostToolUse output table of the hooks docs.

### 3. What remains instructional in shirabe

- **`/status` skill** (new, `skills/status/SKILL.md`): one injection line + relay instructions + two fallback branches: on `NO-RENDERER`, instruct the model to reconstruct in-flight work from live `gh` (search open PRs on current branch/author) — the instructional degradation path; on `[shell command execution disabled by policy]`, same fallback. `disable-model-invocation: true`.
- **Dispatched-worker final-message rule**: stays as prose in the dispatch brief template — no hook can compel a worker's final message shape; inherently instructional.
- **Skill-boundary narrative emissions**: optional, purely instructional; the deterministic pipeline makes them redundant for awareness and they can be dropped.
- **Spec home**: `references/work-in-flight.md` does not exist anywhere in shirabe today (verified by `find`; there was never such a file — a shirabe `references/` dir exists but has no work-in-flight entry). Under this design it should *not* be created: the block grammar spec lives with the single implementation — the render script's `--help`/header comment in dot-niwa. Creating a shirabe-side format spec would recreate two-sources-of-truth skew for a format only one script emits.
- **Hooks for niwa-less shirabe users**: a shirabe `hooks/hooks.json` is now *technically* clean (`${CLAUDE_PLUGIN_ROOT}` expansion + env export are documented for plugin hooks), but shipping the capture hook in the plugin would double-register for users running both layers — precisely the duplicate-hook class round 2 flagged, with no dedup mechanism between plugin hooks and settings.local.json hooks. Keeping shirabe hook-free preserves single-channel registration. **shirabe-without-niwa degrades to /status-only (no ambient display, model-driven gh fallback)** — accepted degradation, not a gap to plug.

### 4. Component inventory and degradation matrix

| File | Repo | Role |
|---|---|---|
| `.niwa/hooks/post_tool_use/capture-work-in-flight.sh` | dot-niwa | Extract PR URLs from tool output → session ledger; invoke renderer; emit `systemMessage` + `additionalContext` |
| `scripts/render-work-in-flight.sh` (via `[files]` → `.claude/hooks/render-work-in-flight.local.sh`) | dot-niwa | **Single render implementation**: ledger + live gh → `=== WORK IN FLIGHT ===` block; `--help` is the format spec |
| session ledger (path/schema internal) | dot-niwa | Written by hook, read by renderer only — never a cross-layer contract |
| `skills/status/SKILL.md` | shirabe | Injection-line probe of well-known path; relay verbatim; instructional gh fallback |
| dispatch brief final-message rule | shirabe | Instructional; unchanged |

| Configuration | Ambient display | Model awareness | /status | Capture fidelity |
|---|---|---|---|---|
| both | yes (systemMessage) | yes (additionalContext) | deterministic (script relay) | full (ledger + gh) |
| dot-niwa only | yes | yes | no command; user asks model, which can run the in-repo script directly | full |
| shirabe only | no | only what the model saw itself | degraded: model runs gh per skill instructions; may miss dispatched-worker PRs | none (no ledger) |
| neither | no | incidental | none | none |

## Implications

- The re-cut is clean: **dot-niwa owns everything deterministic** (capture, ledger, render, display, model-context refresh); **shirabe owns everything conversational** (/status relay + fallback, dispatch-brief prose). The single render script lives in dot-niwa because that is the only layer both a settings-registered hook and a plugin skill can reach without version-unstable paths.
- The compatibility contract is one path + one human-readable block, not a schema — consistent with the workflow-continue.sh negative precedent. Version skew is structurally impossible: there is exactly one implementation, and /status is version-agnostic (it relays whatever the script prints).
- niwa's existing sha256 fingerprinting gives render-script updates rotation semantics for free; no new update mechanism is needed.
- /status latency equals the render script's gh calls, incurred synchronously at preprocessing before the model sees anything — the script should budget accordingly (parallel gh calls, short timeouts, degrade to ledger-only output on gh failure).

## Surprises

- Injection preprocessing is **not permission-gated**: it ran with no `allowed-tools` and no `--dangerously-skip-permissions`. The only control is `disableSkillShellExecution` (managed-settings oriented), which substitutes a literal policy string — /status should recognize that string and fall back.
- `${CLAUDE_SKILL_DIR}` exists as a documented substitution "in bash injection commands" — shirabe *could* bundle its own renderer copy trivially. The design should resist this temptation; it is exactly the duplication path.
- The official hooks docs say there is **no `.claude/hooks/` directory auto-discovery** (targeted re-fetch returned ABSENT), and niwa's code in fact registers materialized scripts explicitly via the `settings.local.json` hooks block. The round-2 phrase "single-channel registration (auto-discovery only)" doesn't match either source; the single channel is settings.local.json.
- niwa's `[files]` channel forcibly inserts a `.local` infix for repo-level destinations (gitignored by design), so the well-known path *must* be spelled with `.local` — an easy contract mistake to make.

## Open Questions

- Reconcile the round-2 "auto-discovery only" premise with the docs' ABSENT and materialize.go's settings.local.json registration — was round 2 describing a changelog feature the docs lag on, or plugin skill auto-discovery? Worth one empirical check before finalizing the capture-hook registration story.
- What working directory do injected `` !`cmd` `` commands run in (assumed project dir; both probes here were cwd-invariant)? A cheap check before freezing the relative-path fallback in /status.
- Does `additionalContext` on every PostToolUse fire bloat context? The hook likely needs an emit-on-change or throttle policy — dot-niwa internal, but affects UX.
- Should the renderer take a `--no-ledger` mode so a shirabe-only /status could still get the deterministic block from pure gh discovery? That would upgrade shirabe-only degradation without sharing the ledger — but requires shipping the script somewhere shirabe can reach, reopening the placement question. Currently answered "no" by the matrix.

## Summary

Dynamic context injection is confirmed working on Claude Code 2.1.201 (two live `claude -p` runs relayed real preprocessed `date +%s` output, even without `allowed-tools` or permission bypass), so /status can be a thin shirabe skill that relays deterministic script output rather than running gh itself. The single render script must live in dot-niwa — materialized per-repo via niwa's fingerprinted hooks/[files] channels to the well-known path `.claude/hooks/render-work-in-flight.local.sh` — because settings-registered hooks can't resolve the shirabe plugin cache, while a shirabe skill can probe a `${CLAUDE_PROJECT_DIR}` path; the cross-layer contract is that path plus the self-describing block, never the ledger schema. Shirabe stays hook-free (a plugin hooks.json would double-register for dual-layer users) and keeps only the instructional residue — /status with a gh fallback and the dispatch-brief final-message rule — degrading shirabe-only installs to /status-without-ambient-display.

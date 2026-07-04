# Exploration Findings: session-work-summary

## Decision: Crystallize

## Core Question

How should agent sessions periodically surface a standardized summary of the work
in flight — PRs, their status, and their links — so users can find them in a long
chat without every message ending in a summary block? Where should the convention
live (a shirabe skill/template, a niwa-injected instruction, a Claude Code hook,
or something else), and what cadence mechanism (timer, turn count, event-based)
actually works in the harness?

## Round 1

### Key Insights

- **Hooks are the only mechanism that can enforce cadence** (lead: claude-code-extension-points). CLAUDE.md, output styles, and skills can hold the summary *template* but cannot control *when* it fires. Nearly every hook lifecycle event can inject context to the model (`additionalContext`): UserPromptSubmit (stateful turn/time gating via session_id-keyed files), PostToolUse with `if: "Bash(gh pr create*)"` (event-gated), Stop (`decision: block`). Statusline is display-only but has a real wall-clock `refreshInterval` and receives `transcript_path`.
- **shirabe already captures every PR URL; it just never shows them** (lead: shirabe-pr-surfacing). `pr_url` is mandatory koto evidence in work-on and execute; coordinated mode maintains a live PR Index table in the coordination PR body. Exactly one instruction in the whole corpus requires handing a PR URL to the user in chat (execute's interactive `paused_for_review`). The gap is a render template + trigger, not data collection.
- **Everything is deliverable config-only through niwa today** (lead: niwa-injection-surfaces). niwa installs hooks for arbitrary events (snake-to-Pascal fallback covers UserPromptSubmit/PostToolUse), renders instance CLAUDE.md from the workspace config template, and ships per-skill extension files via the `[files]` channel that shirabe SKILL.md files already @import. No niwa code changes required for any option.
- **State source should be hybrid: tiny scope ledger + live gh refresh at render time** (lead: summary-state-source). Measured gh queries are cheap (0.3–1s, a few hundred tokens compact). Author-scoped `gh search prs` over-collects across sessions and leaks private-repo PRs into public contexts; a per-repo/per-instance scope respects visibility naturally. In ephemeral niwa instances, non-main branches are a precise session fingerprint, and `.niwa/sessions/<id>.json` already joins session→instance.
- **Cadence winner is event-driven + return-after-absence, not timer/turn-count** (lead: cadence-design). PostToolUse dirty-flag on PR-changing commands + a UserPromptSubmit check that fires only on the first prompt after a long absence, with shared dedupe state (PR-set hash + last-summary timestamp). Turn-count and ungated Stop triggers are rejected as noise. UserPromptSubmit is documented as NOT evaluated in `-p` background sessions.
- **No surveyed tool uses timed in-transcript digests** (lead: prior-art). Prior art converges on three shapes: ambient badge/statusline outside the transcript, pull-based sectioned dashboards (gh pr status, gh-dash, Renovate's continuously-rewritten dashboard issue), and state-change-gated pushes that always repeat the link (Devin, Copilot's PR-as-status-document). Claude Code natively ships a footer PR badge (current-branch only), `/recap`, and `footerLinksRegexes` (v2.1.176+, user-settings-only).

### Tensions

- **Timed digests vs event-gated pushes**: the user's initial framing was timer/turn-count, but both the cadence analysis and the prior-art survey independently conclude that pushes should be gated on state change (PR opened/merged/CI failed) plus "first prompt after returning," with pure timers rejected. The "periodic" need is better served by a pull view.
- **All-sessions vs workflow-only placement**: a niwa workspace instruction/hook reaches every session (including ad-hoc ones that open PRs outside shirabe skills); a shirabe convention only fires during workflow skills but travels with the plugin to any workspace. Both layers emitting risks double-summaries — ownership must be single-layered per concern.
- **The best link-findability tools can't be shipped by the project**: `footerLinksRegexes` and statusline are user/managed-settings scope only (deliberate security posture), and are invisible in background/dispatched sessions — the exact sessions this workspace uses heavily.
- **Ledger location vs wip-hygiene**: a session ledger under `wip/` is fine for session lifetime but can never be referenced from durable artifacts and dies at cleanup; the `.niwa/` instance dir survives and is multi-repo by construction but couples the convention to niwa.
- **Ctrl+R doesn't search assistant output** — a distinctive marker block helps terminal-scrollback search (Ctrl+O then `[`), not Ctrl+R. The "find it in chat" goal partially contradicts the transcript's own search affordances; the most reliable "always findable" surface is outside the transcript or re-emitted fresh at the bottom.

### Gaps

- Empirical: does the model reliably obey a dirty-flag `additionalContext` nudge without drifting into unprompted footers? Needs a live trial.
- Version floors: `if` handler filters, `footerLinksRegexes` (v2.1.176+), plugin-hook update semantics across the Claude Code versions niwa instances run.
- Whether niwa's Agent View / `niwa_report_progress` should carry the summary for dispatched workers (mesh channel not examined in depth).
- Two latent bugs found in passing: niwa installs some hooks twice in per-repo settings.local.json (breaks fire-counting hooks), and `workflow-continue.sh`'s `stop_hook_active` anti-loop guard appears inverted (never nudges on a normal first stop).

### Decisions

- Cadence: event-gated push + return-after-absence accepted; timer/turn-count rejected.
- Placement: shirabe stays hook-free (verified — plugin.json declares only skills). shirabe owns template + skill emission rules; niwa/dot-niwa owns hook delivery. This resolves the all-sessions-vs-workflow-only tension into a layered split along the existing architectural boundary.

### User Focus

The user's placement instinct was architectural: "shirabe has no knowledge of hooks... connecting to claude hooks has been a responsibility of niwa" — confirmed by inspection. They chose to explore further rather than crystallize, pointing round 2 at mechanics validation and the layer contract.

## Round 2

### Key Insights

- **Layer contract: convention-by-name, never a shared file schema** (lead: layer-contract). shirabe ships `references/work-in-flight.md` (marker, line grammar, emission rules) plus one-line emission bindings at existing skill boundaries (`pr_creation`, `paused_for_review`, etc.); dot-niwa ships the hook scripts whose nudge *names* the convention with a generic `gh pr list` fallback. The template stays version-matched to the skills because both ship in the plugin. Dedupe state is hook-private (`/tmp/...<session_id>.json`), disposable, never in `wip/` (commit noise, multi-repo mismatch). The workspace already proves ledger-as-contract fails: dot-niwa's Stop hook greps `wip/*-state.json`, but `/execute` moved to `wip/execute_<topic>_state.md` — the workflow-continuation safety net silently no-ops today.
- **All hook mechanics empirically verified on Claude Code 2.1.201** (lead: hook-mechanics-validation). PostToolUse `additionalContext` reaches the model and is acted on in `claude -p` background mode (token test); `if: "Bash(echo pr-created*)"` filters work (no in-script command parsing needed); `session_id`/`transcript_path` arrive on stdin and per-session counter state works. Caveat: the harness injects on *every* matching call — once-per-event semantics must be implemented by the hook (emit only on flag transition).
- **The niwa duplicate-hook bug is confirmed, root-caused, and its impact is matcher erasure, not double-firing** (lead: hook-mechanics-validation). Declared `[[claude.hooks.*]]` entries and auto-discovered scripts are concatenated without dedupe in `runRepoMaterializers` (worktree_content.go:96); discovery never sets a matcher, so gate-online runs on every tool call today (Read/Edit included). Claude Code 2.1.201 dedupes identical command strings, so no double-fire — but that safety net is undocumented. Fix: dedupe by resolved script path, or register new hooks via one channel only.
- **The niwa mesh no longer exists** (lead: background-surfacing). PRD-niwa-mesh-removal (Done) deleted `niwa_report_progress`, `niwa_finish_task`, task queues, and the MCP server; the workspace CLAUDE.md/overlay still documents them (doc debt). For dispatched workers the transcript is the only reliable surface: niwa pushes nothing at completion, an in-instance ledger is force-deleted at reap (exactly when the user would want to read it), and Agent View is Claude Code's dashboard fed by the worker's own messages (it already has a PR column). Smallest effective change: the `/dispatch` brief template requires the summary block at PR events and in the final message — the brief is the only instruction channel guaranteed to reach a dispatched worker (per the plugin-load-race spike).
- **Template settled** (lead: template-format). Marker `=== WORK IN FLIGHT ===` (verbatim, survives markdown rendering, greppable by the dedupe hook — same pattern as lifecycle.yml grepping the coordination marker). Line grammar extends the PR Index: `- owner/repo#N | state-tokens | title(≤60ch) | bare-URL`. Bare URLs are load-bearing: markdown links render as OSC-8 hyperlinks whose URLs are unrecoverable from scrollback dumps. Attention-first ordering; merged rows appear once then drop; pre-PR items via `no-pr`; Renovate-style section headers only above 6 items; `/status` render byte-identical plus a mandatory freshness line.

### Tensions

- Return-after-absence is interactive-only (UserPromptSubmit not evaluated in `-p`); background coverage comes from event-gated PostToolUse emissions plus the final-message requirement. Acceptable: background sessions have no "returning user" moment.
- Round 1 leaned toward a session scope-ledger; round 2 demoted it — no cross-layer ledger schema (negative precedent is live in the workspace). The item set comes from the model's session context + koto evidence + `gh` refresh; hook state is private dedupe only. Whether any lightweight item-set record is needed at all is a design-doc detail.

### Gaps

- Whether Agent View's PR column populates from any transcript message or specifically the final result (harness behavior, unverifiable from niwa source).
- Renderer hard-wrap behavior for long trailing URLs (minor formatting risk).

### Decisions

- Contract design A accepted by the evidence: named convention + fallback; single hook registration channel (auto-discovery only) until niwa dedupes.
- No shared ledger file; hook-private dedupe state outside the repo tree.
- Dispatched-worker coverage via the `/dispatch` brief template + final-message rule, not via (removed) mesh channels or in-instance files.

### User Focus

(round 2 ran autonomously per round 1 direction: validate mechanics and the layer contract)

## Round 3 (deterministic pivot validation)

### Key Insights

- **systemMessage is viable as the deterministic display channel** (lead: systemmessage-semantics). Verified on 2.1.201: a PostToolUse or UserPromptSubmit hook's `systemMessage` is durably persisted in the session transcript JSONL as a first-class `hook_system_message` attachment (multi-line blocks round-trip intact; 10k-char documented cap; `suppressOutput` irrelevant). One emission can carry `systemMessage` (user channel) + `additionalContext` (model channel) and both take effect independently. Two caveats: it never appears on `claude -p` stdout, stderr, `claude logs`, or stream-json events — headless recovery must parse the transcript JSONL or keep the model-emitted final-message fallback; and Haiku flagged an imperative additionalContext as a prompt-injection attempt — the model-context half must be phrased as neutral state ("Current open PRs: ..."), never as instructions.
- **The capture+render pipeline is proven end to end** (lead: render-pipeline; prototype committed to findings). All 12 capture fixtures pass, including rejecting `git push`'s "/pull/new/" hint URL; render produced correct state tokens against 5 real PRs across 3 public repos. Latency: capture 8–16ms, gate check 5ms, 5-PR multi-repo render 0.5–1.0s parallel (2.2s sequential), offline degradation 35ms with a graceful ledger-only block. Capture fits the PostToolUse hot path; render belongs at the display moment behind the gate. Benign gap: `gh pr merge <number>` leaves no capturable URL — fine, since PRs are captured at creation and render refreshes state live.
- **`!`cmd`` dynamic injection works and is not permission-gated** (lead: layer-recut). Two live runs relayed real preprocessed command output with no `allowed-tools` and no permission bypass. So `/status` is a thin shirabe skill: one injection line probing a well-known path, relay verbatim, instructional `gh` fallback on `NO-RENDERER` or the `disableSkillShellExecution` policy string.
- **The single render script lives in dot-niwa; the contract is a path + a self-describing block** (lead: layer-recut). Settings-registered hooks cannot resolve the shirabe plugin cache (`${CLAUDE_PLUGIN_ROOT}` only exists for plugin-registered hooks), while a shirabe skill CAN probe `${CLAUDE_PROJECT_DIR}/.claude/hooks/render-work-in-flight.local.sh` (the `[files]` channel's forced `.local` infix must be spelled in the contract). The ledger schema stays private to dot-niwa (hook writes, renderer reads) — honoring the workflow-continue.sh negative precedent. shirabe stays hook-free: a plugin hooks.json would double-register for dual-layer users.
- **Round-2 correction**: Claude Code has no `.claude/hooks/` auto-discovery; niwa's discovery is its own config-repo mechanism and registration always lands in settings.local.json. "Single-channel registration" means: declare the hook in exactly one niwa channel (TOML or `.niwa/hooks/`, not both) until the materializer dedupes.

### Component inventory (validated)

| File | Repo | Role |
|---|---|---|
| `.niwa/hooks/post_tool_use/capture-work-in-flight.sh` | dot-niwa | Extract PR URL from tool output → session ledger; invoke renderer when gate passes; emit systemMessage + neutral additionalContext |
| `scripts/render-work-in-flight.sh` → `.claude/hooks/render-work-in-flight.local.sh` via `[files]` | dot-niwa | Single render implementation; `--help` header is the format spec |
| UserPromptSubmit return-after-absence hook | dot-niwa | Interactive-only refresh via same renderer |
| `skills/status/SKILL.md` | shirabe | Injection-line probe + verbatim relay + gh fallback; `disable-model-invocation: true` |
| dispatch brief final-message rule | shirabe/niwa rootskill | Instructional; the background-session guarantee |

Degradation: both layers = full (ambient display + model awareness + /status). dot-niwa only = everything except the /status command. shirabe only = /status with model-driven gh fallback, no ambient display, no ledger. Neither = status quo.

### Gaps

- Interactive TUI rendering of hook_system_message inferred from docs + persistence, not directly observed (needs a pty test or just trying it).
- Whether Agent View renders `hook_system_message` attachments from background transcripts.
- additionalContext-on-every-fire needs an emit-on-change/throttle policy (dot-niwa internal).

### Decisions

- Deterministic architecture confirmed as the direction: hooks capture/render/display; the model relays only where scripts can't reach.
- No `references/work-in-flight.md` in shirabe after all — the format spec lives with the single implementation (render script header); a shirabe-side spec would recreate two-sources-of-truth skew.
- shirabe remains hook-free permanently in this design.

## Round 4 (final validation: UI rendering, emit policy)

### Key Insights

- **The block renders correctly in every real UI surface** (lead: ui-rendering; pexpect+pyte pty rig standing in for tmux). Interactive TUI: intact dim-gray block attached under the triggering tool call with prefix `⎿ PostToolUse:Bash says: ` on the marker line; visible even when tool output is collapsed. Ctrl+O verbose view: intact. Narrow terminals word-wrap at spaces so trailing bare URLs land whole on their own continuation line (safe down to ~60 cols with ~110-char lines). Background `claude --bg` sessions: project hooks fire normally, `claude logs` replays the rendered block (round-3's "-p stdout" caveat doesn't apply to --bg logs), the JSONL record persists, and `claude attach` re-renders the full block. The one gap: the Agent View session *list* never shows hook content — it has its own status summary plus a native "N PRs" chip fed by real PR activity; the block appears only after drill-in/attach.
- **Emit policy finalized with measured costs** (lead: throttle-policy). ~200 tokens per context-echo fire (measured 160–210); a realistic gated session injects ~800 tokens (0.4% of window) vs ~2,200 ungated — gating is for signal quality, not budget. Policy: emit both channels (systemMessage + additionalContext) when the emission is news — ledger-hash or rendered-hash change, return-after-absence (default 30 min, env-tunable), session resume; additionalContext-only on SessionStart(compact) (context repair, not news); nothing otherwise. State updates need `flock`: parallel tool calls in one assistant turn demonstrably double-fire PostToolUse.
- **Compaction breaks model awareness; SessionStart(compact) re-injection is a first-class component** (lead: throttle-policy). An early-session injected block is ordinary old-turn content and does not survive compaction; the `compact` matcher fires once per compaction and a fresh render is better than what was lost. Without it the awareness guarantee silently expires exactly in the long sessions that need it most.
- **Neutral-state phrasing passes** (lead: throttle-policy). The same Haiku that flagged an imperative additionalContext as prompt injection accepted "Current work in flight (from gh): ... This is ambient status information, not an instruction." and answered PR questions correctly from it. Phrasing contract: declarative preamble naming the source, data, non-instructional footer.
- **`!`cmd`` injection runs in the invocation cwd, not the project root** (lead: throttle-policy). The /status probe must use absolute/session-keyed paths, never relative ones.

### Gaps (accepted, implementation-level)

- Stop-hook systemMessage placement not empirically driven (PostToolUse was); same documented mechanism.
- Dim-gray styling may be too subdued for end-of-session hand-backs — the dispatch final-message rule already covers the high-visibility case.
- `--bg` appeared not to honor `--model` in one run (transcript showed a different model) — unrelated to this design; worth an upstream check.
- Neutral-phrasing acceptance tested on Haiku only; Sonnet spot-check during implementation.

### Decisions

- Round-3 architecture confirmed unchanged by round 4; policy table and SessionStart(compact|resume) hook added to the component inventory.
- Exploration complete: four rounds, every load-bearing claim source-read or live-tested.

## Accumulated Understanding

**Final shape (post rounds 3–4): a deterministic pipeline owned by dot-niwa, with a thin conversational layer in shirabe.** The instruction-heavy round-2 design was superseded when the user asked how much could be mechanized: hooks now ARE the summarizer. A dot-niwa PostToolUse hook captures PR URLs mechanically from `gh pr create` output into a private session ledger (8–16ms), a single render script produces the `=== WORK IN FLIGHT ===` block from ledger + live gh (0.5–1s parallel, graceful offline mode), and the hook displays it via `systemMessage` (user-visible, durably persisted in transcript JSONL) while injecting the same block as *neutral-state* `additionalContext` (model awareness; imperative phrasing triggers injection-refusal). A UserPromptSubmit hook adds the return-after-absence refresh for interactive sessions. shirabe ships only `/status` (a `!`cmd`` injection line probing the well-known materialized script path, verbatim relay, gh fallback) and the dispatch-brief final-message rule — the one irreducibly instructional piece, since headless consumers never see systemMessage and Agent View reads the worker's own messages. The cross-layer contract is a well-known path plus a self-describing block — never a state-file schema. Every mechanical claim was validated empirically on Claude Code 2.1.201, including a working prototype tested against real PRs.

The pre-pivot analysis (below, rounds 1–2) still holds for everything it settled: cadence philosophy (event-gated + return-after-absence; timers/turn-count rejected), the block grammar (pipe-lines, bare URLs last, attention-first, merged-once-then-drop), placement boundaries, and the byproduct bug findings.

Historical (round 2) framing, superseded where it conflicts with the above:

1. **shirabe owns the convention** (plugin release): `references/work-in-flight.md` defining the verbatim marker `=== WORK IN FLIGHT ===`, the pipe-line grammar (`- owner/repo#N | state-tokens | title | bare-URL`, extending the coordination PR Index grammar), state-token vocabulary, attention-first ordering, >6-item section escalation, and emission rules (emit on PR created/merged/closed, CI transition, changes-requested, pre-PR registration; final element of the triggering turn; never a footer; self-contained URLs every time; merged rows once then dropped). Skill bindings: one-line emission requirements at work-on's `pr_creation`/`ci_monitor`, execute's hand-backs and terminals. Plus a pull-side `/status` skill rendering the identical block from live `gh` reads with a freshness line.
2. **dot-niwa owns delivery and cadence** (config-only, no niwa code): auto-discovered hook scripts — PostToolUse gated by `if: "Bash(gh pr create*)"` etc. setting a dirty flag (works in `-p` mode, empirically verified), UserPromptSubmit return-after-absence nudge (interactive-only by harness design). Nudge text names the shirabe convention with a `gh pr list` fallback; dedupe state is hook-private, session_id-keyed, outside the repo tree. Register via auto-discovery only until niwa dedupes declared+discovered hooks. The hook can grep the transcript tail for the marker to suppress redundant nudges.
3. **Background/dispatched sessions** are covered by convention, not machinery: the `/dispatch` brief template (niwa's embedded root skill) requires the block at PR events and in the final message; Agent View's PR column picks it up from the transcript.
4. **No shared ledger schema** — the workspace has a live failure of that pattern (dot-niwa's Stop hook greps a state-file schema `/execute` no longer writes). Truth stays in GitHub; render-time `gh` refresh is sub-second and a few hundred tokens; per-repo iteration respects visibility boundaries (org-wide author search over-collects and can leak private PRs).

Validated empirically (Claude Code 2.1.201): PostToolUse additionalContext in `-p` mode, `if` filters, per-session hook state. Byproduct findings needing separate fixes: niwa's duplicate-hook materialization (matcher erasure — gate-online currently fires on every tool call), workflow-continue.sh's stale state-file glob (dead safety net) and inverted `stop_hook_active` guard, and stale workspace CLAUDE.md/overlay documenting the removed niwa mesh.

Remaining opens are implementation details a design doc/plan would resolve: exact hook state-file location, whether the skill-side emission clears the hook's dirty flag (vs tolerating one redundant nudge), `/status` history-mode caps, and the Agent-View-PR-column population rule.

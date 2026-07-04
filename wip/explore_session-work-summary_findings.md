# Exploration Findings: session-work-summary

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

(pending user convergence input)

### User Focus

(pending user convergence input)

## Accumulated Understanding

The problem decomposes into four separable layers, each with a clear best-fit owner:

1. **Template/format** (what the summary block looks like): a shirabe shared reference file (sibling to `issues-table.md`), bound into skills' existing terminal/hand-back states. Renovate's state-sectioned table is the strongest format precedent.
2. **Scope/state** (which PRs belong to this session): a small event-appended ledger + live `gh` refresh at render time. shirabe skills already capture `pr_url` at the moment of creation; a PostToolUse hook can maintain the ledger mechanically. Per-repo iteration respects visibility; org-wide author search does not.
3. **Cadence/trigger** (when it appears in chat): event-gated (PR set changed) + return-after-absence, deduped via shared per-session state. Pure timer/turn-count rejected by both feasibility analysis and prior art. Instruction-only is the mandatory base layer and the fallback when hooks aren't installed.
4. **Display channel** (where it lives): in-chat anchor block on state change + a pull-based `/status`-style renderer; optionally statusline/footerLinksRegexes for interactive users (user-settings-only); a ledger file is the only channel that works in background sessions.

Both candidate homes are mechanically viable today with zero code changes: shirabe can ship template + skill + hooks.json; niwa/dot-niwa can ship instructions + hooks config-only. The remaining questions are product placement (all sessions vs workflow skills), the push/pull balance, and empirical model-compliance validation.

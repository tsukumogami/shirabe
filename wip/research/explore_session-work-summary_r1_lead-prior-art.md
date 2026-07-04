# Lead: What prior art exists for surfacing work-in-flight in agent harnesses and CLI tools?

## Findings

### (a) Claude Code native affordances

**Footer PR badge (built-in, per-branch).** When the session's current branch has an open PR, Claude Code shows a clickable "PR #446" badge in the footer with a colored underline for review state (green approved, yellow pending, red changes requested, gray draft). It refreshes every 60 seconds and immediately after any `gh pr` or `git push` in the session, and disappears on merge/close. Requires `gh` authenticated. Push/ambient; but it tracks only the current branch's PR, so it doesn't cover a long multi-PR session that has moved on to other branches or repos. (https://code.claude.com/docs/en/interactive-mode, "PR review status" section)

**`footerLinksRegexes` (v2.1.176+).** User/managed-settings-only setting that renders extra clickable footer badges when a regex with named capture groups matches turn output; `url` and `label` templates fill from the groups. Deliberately not read from project or local settings (a repo can't commit it), which matters for a plugin like shirabe: it cannot ship this setting in project config, only recommend it for user settings. Badge count/size limits and a URL-scheme allowlist apply. Related `prUrlTemplate` rewrites PR badge URLs to internal review tools. (https://code.claude.com/docs/en/settings)

**Task list vs background tasks.** `Ctrl+T` toggles Claude's to-do checklist (TaskCreate/TaskUpdate/TaskList tools, which replaced TodoWrite as of v2.1.142); it persists across compactions and can be shared across sessions via `CLAUDE_CODE_TASK_LIST_ID` pointing at a named directory in `~/.claude/tasks/`. Separate from that, `/tasks` shows running shells and subagents. Tasks are work items, not artifacts — nothing in the task model carries a PR URL. (https://code.claude.com/docs/en/interactive-mode, https://code.claude.com/docs/en/agent-sdk/todo-tracking)

**Ctrl+R searches prompts, not the transcript.** Reverse search (`Ctrl+R`) covers the 100 most recent unique *user prompts* (scopes: session/project/all projects). Assistant output is not searchable via Ctrl+R. To search assistant output you open the transcript viewer (`Ctrl+O`) and press `[` to dump the conversation into native terminal scrollback for Cmd+F/tmux search, or `v` to open it in `$EDITOR`. (https://code.claude.com/docs/en/interactive-mode)

**Session recap.** Claude Code natively generates a one-line recap when you return to an unfocused terminal after 3+ minutes, and `/recap` produces one on demand. This is the harness's own answer to "what happened while I was away" — but it's a one-liner, not a link table. (https://code.claude.com/docs/en/interactive-mode)

**Background agents and notifications (changelog).** v2.1.198: background agent sessions fire the `Notification` hook with `agent_needs_input` / `agent_completed`. Background agents launched from `claude agents` now commit, push, and open a draft PR when they finish. The `claude agents` session list grew PR affordances across releases: v2.1.153 added a PR column (`PR #N` / `N PRs`), v2.1.196 made results that mention a PR render a clickable link, v2.1.198 tightened the display. So Anthropic's own trajectory is: put PR links in a *session-level dashboard row*, outside the transcript. (https://code.claude.com/docs/en/changelog)

**Statusline.** A shell script receiving session JSON on stdin; renders a persistent row above the footer, updates as the conversation changes. It can print anything — including output derived from a status file that skills write — making it a viable always-visible, transcript-length-immune display. Configured in user settings. (https://code.claude.com/docs/en/statusline)

### (b) Terminal PR dashboards

**`gh pr status`.** Pull-based, sectioned by *relationship to the user*: "Current branch", "Created by you", "Requesting a code review from you", each row showing number, title, branch, CI check state, review state. Scoped to the current repo (`-R` to override) — so it's per-repo, which is a poor fit for a niwa multi-repo workspace without a wrapper that iterates repos. (https://cli.github.com/manual/gh_pr_status)

**`gh dash`.** TUI dashboard with fully user-defined sections, each a GitHub search filter (so sections can span many repos: `author:@me is:open`), configurable columns and limits, and inline actions (checkout, merge, comment, diff). Demonstrates the "sections = saved queries" pattern and that cross-repo PR aggregation is a solved problem at the CLI layer. (https://github.com/dlvhdr/gh-dash, https://www.gh-dash.dev/configuration/pr-section/)

**Graphite.** `gt ls` lists all branches/stacks annotated with each branch's PR status (merged / open / not yet proposed); `gt log` renders the stack tree. Pattern: status is attached to a *structural map* of the work (the stack), not a chronological log. (https://www.graphite.com/docs/command-reference, https://graphite.com/guides/list-all-git-branches)

### (c) Bot and agent-orchestrator conventions

**Sticky PR comments (CI bots).** The dominant CI-bot pattern is a single comment per concern, identified by a hidden HTML marker (`<!-- header -->`), *edited in place* on every run instead of appending. `marocchino/sticky-pull-request-comment` and `mshick/add-pr-comment` both key on the marker so subsequent runs upsert; multiple independent sticky comments coexist via distinct headers. Even `anthropics/claude-code-action` has a `use_sticky_comment` option and known issues around marker-based lookup. Core insight: in an append-only medium you need a stable identity marker; in a mutable medium you edit one anchor. (https://github.com/marocchino/sticky-pull-request-comment, https://github.com/marketplace/actions/add-pr-comment, https://github.com/anthropics/claude-code-action/issues/960)

**Renovate Dependency Dashboard.** A single bot-maintained GitHub issue that Renovate continuously rewrites, sectioned by state: Pending Approval, Awaiting Schedule, Open PRs (with links), Manually Edited/Blocked, Closed/Ignored — plus checkboxes that act as commands back to the bot. This is the strongest "many concurrent work items, one findable document" prior art: one well-known location, always current, state-sectioned, interactive. (https://docs.renovatebot.com/key-concepts/dashboard/)

**GitHub Copilot coding agent.** Opens a draft PR immediately, pushes commits as it works, and *updates the PR description* as its running status document; session logs live on a central sessions page; the user is added as reviewer on completion (notification = state change). The PR itself is the status artifact — chat is ephemeral, the PR description is durable. (https://docs.github.com/copilot/concepts/agents/coding-agent/about-coding-agent, https://github.blog/news-insights/product-news/github-copilot-meet-the-new-coding-agent/)

**Devin.** Posts a plan comment up front, then in-thread Slack progress updates; replies always carry the PR link; posts "Merged" back to the channel on merge; the sessions list doubles as a todo list. Pattern: push at state transitions (plan ready, PR opened, merged), each push self-contained with the link repeated. (https://docs.devin.ai/integrations/slack)

### (d) Document patterns distilled

| Pattern | Push/pull | Multi-item handling | Transcript-length survival |
|---|---|---|---|
| Ambient badge/statusline (CC footer PR, statusline) | Ambient (always visible) | Weak natively (current branch only); good if fed from a status file | Perfect — outside the transcript |
| Sticky/anchor document (Renovate dashboard, Copilot PR body, sticky comments) | Pull (one known location) | Excellent — state-sectioned table | Perfect — mutable doc, not a log |
| Sectioned status command (`gh pr status`, gh-dash, `/recap`, `/tasks`) | Pull (user invokes) | Excellent — sections by state/relationship | Perfect — regenerated fresh |
| Push on state change (Devin, Copilot review request, Notification hook) | Push, event-gated | Per-item; link repeated in every push | Each push self-contained; older ones scroll away harmlessly |
| Periodic digest in-channel | Push, time-gated | OK but noisy; stale between digests | Poor — digests themselves get buried |

### Transferable patterns (assessed for a chat-transcript context)

1. **Status file + ambient display, not transcript messages.** Skills append/update a machine-readable work log at a well-known path (e.g. `wip/` or `~/.claude/` scoped file: repo, PR URL, state, timestamp); a statusline script or `footerLinksRegexes`-style badge surfaces it. This is exactly how Claude Code's own footer PR badge and `claude agents` PR column evolved — the harness put links in chrome, not in the log. Best fit for "always findable," but statusline/footerLinks are user-settings-only, so a plugin can document but not install it.
2. **Pull-based `/status` skill that regenerates a sectioned dashboard.** A shirabe command that reads the status file (or runs `gh search prs author:@me is:open` across workspace repos, gh-dash style) and emits a fresh sectioned table (Open / CI failing / Awaiting review / Merged this session). Zero ambient noise; the *latest* invocation is always near the bottom of the transcript, which is where users look.
3. **Anchor block with a distinctive marker string, re-emitted only on state change.** The chat-transcript translation of the sticky comment: a fixed-format block (e.g. a `WORK IN FLIGHT` header with a distinctive token) that skills emit when a PR opens/merges/fails — never per-message. Caveat discovered here: Ctrl+R will NOT find it (prompt-history only); it's findable via Ctrl+O → `[` → terminal search, or by the user typing the marker as a prompt (which IS Ctrl+R-searchable). Marker choice should target terminal-scrollback search, not Ctrl+R.
4. **The PR is the durable status document; chat only carries the pointer.** Copilot and Renovate both treat a GitHub-side artifact as the source of truth and keep it current, letting chat messages be lossy. For niwa/shirabe, a per-session or per-workspace "work log" issue/PR-description section (sticky-marker upserted via `gh`) would survive not just long transcripts but session death.
5. **Notify on transitions, never on a timer.** Every surveyed system that pushes (Devin, Copilot, CC background-agent Notification hook) pushes at state changes only. Periodic digests appeared nowhere in surveyed tools — the "every message ends in a summary" anti-pattern the exploration wants to avoid has no prior-art support.

## Implications

- The exploration's framing "so ctrl-r finds the latest" needs revision: Ctrl+R searches user prompt history only. Findability inside the transcript means terminal scrollback search (via `Ctrl+O` then `[`) or a `/status`-style regeneration; findability outside the transcript means statusline/footer or a durable GitHub-side document.
- The three candidate homes map cleanly onto proven patterns: shirabe convention → anchor-block-on-state-change plus a `/status` skill (patterns 2+3); niwa-injected instruction → maintain the status file that both consume (pattern 1's data layer); Claude Code hooks/statusline → ambient display (pattern 1's view layer), but only via user settings, not plugin-shippable project settings.
- A layered design is well supported by prior art: skills write a status record when they open/update a PR (cheap, deterministic), and any number of views (statusline, `/status`, end-of-turn anchor block, Notification hook) read it. Renovate's state-sectioned table is the strongest format precedent for the rendered view.
- Claude Code is actively building in this direction (footer PR badge, `claude agents` PR column, draft-PR handoff, `footerLinksRegexes`), so any shirabe/niwa mechanism should complement per-branch native affordances with the multi-PR, multi-repo aggregation the harness doesn't do.

## Surprises

- **Ctrl+R does not search the transcript** — only user prompts. A marker emitted by the assistant is invisible to it. The documented route to searching assistant output is `Ctrl+O` → `[` (dump to native scrollback) or `v` (open in $EDITOR). This directly contradicts the lead's working hypothesis.
- **Claude Code already ships a footer PR badge with live review-state coloring** (interactive-mode docs), refreshed every 60s — but only for the current branch's PR, which explains why the user still loses links in multi-PR sessions: the badge silently swaps as branches change and disappears on merge.
- **`footerLinksRegexes` is deliberately blocked from project settings** so repos can't inject footer links — a security posture that constrains where a plugin-based solution can live (user must opt in).
- **`/recap` exists** — a native on-demand and away-return digest — meaning "periodic summary" is partially native already; what's missing is structured links, not summarization.
- **No surveyed tool uses a timed in-channel digest.** Every push mechanism is state-change-gated; every complete inventory is pull-based or a mutable anchor document.

## Open Questions

- Can the statusline script practically render multiple clickable PR links (OSC 8 hyperlinks) in supported terminals, and is there a length budget that caps how many PRs fit?
- Does niwa's Agent View already aggregate PR links per session (mirroring `claude agents`' PR column), and could a niwa-maintained status file be the shared data layer for both?
- For background/dispatched sessions (no visible statusline), is a GitHub-side anchor document (sticky-marker section in a tracking issue or PR body) the only view that works everywhere?
- What marker format is most reliably searchable in terminal scrollback after ANSI rendering and line wrapping (short token vs box-drawing header)?
- Where should the status file live in a multi-repo niwa workspace — workspace root (cross-repo) vs per-repo `wip/` (which the wip-hygiene rule says must never be referenced from durable artifacts)?

## Summary

Prior art converges on three mechanisms — an ambient badge/status line outside the transcript (Claude Code's own footer PR badge, statusline, `footerLinksRegexes`), a pull-based sectioned dashboard (`gh pr status`, gh-dash, Renovate's continuously-rewritten Dependency Dashboard issue), and state-change-gated pushes that repeat the link every time (Devin, Copilot's draft-PR-as-status-document) — while no surveyed tool uses timed in-transcript digests. The main implication is a layered design: shirabe skills write a status record at each PR state change, and cheap views (a `/status` skill, an end-of-turn anchor block with a distinctive marker, an optional statusline) render it, complementing Claude Code's per-branch-only native badge with multi-repo aggregation. The biggest open question is where the always-works view lives, since Ctrl+R turns out to search only user prompts (not assistant output), and the strongest transcript-independent options (statusline, footer regex badges) are user-settings-only and invisible to background sessions.

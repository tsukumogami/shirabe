# Lead: footer badge behavior

Round 5 of the session-work-summary exploration. Empirical test of Claude Code's footer link badges under Claude Code v2.1.201, using the pexpect+pyte pty rig (adapted copy at `/home/dangazineu/.claude/jobs/a050f0e4/tmp/badge-lab/drive_badges.py`; captures under `/home/dangazineu/.claude/jobs/a050f0e4/tmp/badge-lab/captures/`). Four short interactive sessions with `--model haiku`, 200x50 pty, fake 988xx PR numbers only. Doc/binary evidence cross-checked against https://code.claude.com/docs/en/settings and `strings` on the installed `claude` 2.1.201 binary.

The headline correction to the round-4 framing: there is **no native auto-detection** of PR/issue URLs in assistant text. Footer link badges exist, but only when `footerLinksRegexes` is configured (user settings, `--settings` flag, or managed settings). With no config, assistant text full of PR URLs produces zero badges. With config, badges render exactly as documented: max 5, newest-first, oldest displaced, standing across turns.

## Findings

### Q1: Do multiple PR/issue URLs in assistant text produce multiple standing footer badges?

**Without configuration: no badges at all.** Session A (`text-*` captures, no `footerLinksRegexes` anywhere — verified `~/.claude/settings.json` has none): the model replied verbatim with 4 distinct fake URLs across repos (`.../tsuku/pull/98801`, `.../niwa/pull/98802`, `.../koto/pull/98803`, `.../shirabe/issues/98804`). Footer after the reply and after a follow-up "say ok" turn (`text-10-urls-done.txt`, `text-20-persist1-done.txt`):

```
──────────────────────────────────────────────────── always_include_links ──
❯
─────────────────────────────────────────────────────────────────────────────
  ? for shortcuts · ← for agents
```

No badges, no cap to observe, nothing to persist.

**With `footerLinksRegexes` configured: yes — one badge per match, capped at 5, standing.** Session D (`ctl2-*` captures) ran with `--settings` pointing at a config with a GitHub-pull-URL pattern (static-origin `url` template) plus an `owner/repo#N` shorthand pattern. The model's reply contained six pull URLs (98841–98846). Footer after the turn (`ctl2-20-sixurls-done.txt`, bottom row verbatim):

```
  tools#98846 · dot-niwa#98845 · shirabe#98844 · koto#98843 · niwa#98842 · ← for agents
```

- **Count/cap:** 6 matches → exactly 5 badges. The oldest (`tsuku#98841`) was displaced. Matches the binary's embedded description: "At most 5 badges render; the oldest is displaced by newer matches and /clear removes them."
- **Order:** newest first (rightmost match ends up leftmost).
- **Rendering:** plain-text labels joined with " · ", occupying the slot where the "? for shortcuts" hint normally sits in the bottom status row. In pyte they render as bare label text (no brackets); in a real terminal they'd be OSC-8 clickable.
- **Persistence:** standing. After two subsequent unrelated turns ("say ok", "say ok again"), the same 5 badges were still present verbatim (`ctl2-30-persist-done.txt`, `ctl2-40-persist2-done.txt`). No aging-out observed within the session. Per the binary strings, `/clear` is what removes them.

### Q2: URLs delivered only via hook systemMessage do NOT produce badges — confirmed, and strengthened

Two levels of confirmation:

1. **No config (session B, `hook-*` captures):** PostToolUse hook on Bash emitted a systemMessage containing two fake PR URLs; the model's own text was just "done". The systemMessage rendered in the transcript ("PostToolUse:Bash says: === WORK IN FLIGHT === ..."), footer stayed `? for shortcuts · ← for agents`. No badges.
2. **With matching regexes configured (session D step 1, `ctl2-10-hookonly-done.txt`):** the hook's systemMessage contained both a shorthand token (`tsukumogami/tsuku#98831`) and a pull URL (`.../niwa/pull/98832`) that exactly matched the configured patterns — the same patterns that badged assistant text later in the same session. Still **no badges**. So hook `systemMessage` text is not part of the scanned "turn output" even when a matching regex exists. This is the clean negative; round 4's version was confounded by having no regex config at all.

Note the scan scope from the binary: "appear when a regex matches **turn output (tool results and assistant responses)**". Hook systemMessage is neither. (The actual tool result in these runs was `badge-control2-test`, which matched nothing.)

### Q3: Which reference forms badge?

- **Natively (no config): none.** Bare `https://github.com/...` URLs (session A), `owner/repo#N` shorthand, and plain `#N` (session A step 3: `tsukumogami/tsuku#98805 and also #98806`) all produced zero badges.
- **With config: whatever your regex matches — form is irrelevant per se.** The shorthand pattern badged `tsukumogami/tsuku#98827` as `tsuku#98827` (session C, `ctrl-40-shorthand-done.txt`: bottom row `  tsuku#98827 · ← for agents`); the URL pattern badged bare URLs (session D). Plain `#98806`/`#98828` never badged because no pattern targeted them — and there's no built-in one.
- **Gotcha found (session C vs D):** an entry whose `url` template is entirely a capture group (`"url": "{u}"` where `u` captured the whole matched URL) silently produces no badges — six matching URLs badged nothing (`ctrl-20-sixurls-done.txt`). The minified code drops substituted URLs whose origin differs from the template's static origin (log tag `[footerLinks] dropping ... origin-shifted url`). Rewriting the template with a static origin (`"https://github.com/{owner}/{repo}/pull/{num}"`) made the identical prompt produce 5 badges. The `url` template's scheme+host must be literal text.

### Q4: What the docs call this, limits, version floor

- **There is no documented native reference-detection feature.** The footer badge feature is the configurable **`footerLinksRegexes`** setting (settings doc section "Footer link badges"). Settings-doc text: "Render extra clickable badges in the footer when a regex matches turn output. Each entry has a `pattern`, a `url` template with `{name}` placeholders filled from named capture groups, and an optional `label`. Read from user, `--settings` flag, and managed settings only. ... Requires Claude Code v2.1.176 or later." It is explicitly **ignored in project `.claude/settings.json` and local `.claude/settings.local.json`** (binary string confirms).
- **Limits (from the v2.1.201 binary's setting description, verbatim):** "At most 5 badges render; the oldest is displaced by newer matches and /clear removes them. Use to surface IDs printed by project CLIs as session links." Additional guards in code: per-scan match ceiling, max URL length, empty-label drop, slow-pattern warning, origin-shift drop (all logged under `[footerLinks]`, visible only with `--debug`).
- **Version floor:** v2.1.176 ("Added footerLinksRegexes setting for regex-matched link badges in the footer row" per changelog).
- **Distinct from two other footer elements:** (a) the **current-branch PR badge** — automatic, no config, shows the open PR for the current git branch; per binary strings "The detected git PR is rendered as the first footer-link badge", and the statusline JSON input's `pr` field "mirrors the footer PR badge". Its target is customizable via **`prUrlTemplate`** (`{host}/{owner}/{repo}/{number}/{url}` placeholders), which "Does not affect `#123` autolinks in Claude's prose". (b) `#123` autolinks in rendered prose — inline OSC-8 links, not footer badges.

## Implications

- For the session-work-summary design: you cannot get standing footer badges for PRs/issues the agent mentions unless the **user** (or managed settings) opts in with `footerLinksRegexes` — a project can't ship this in its repo settings. Any "always include links" convention in assistant text buys inline autolinks only, not footer chrome.
- If the workspace wants badge-surfaced work items, the supported route is: configure user-level `footerLinksRegexes` (static-origin URL templates) and have tools/CLIs **print** the IDs in tool output, or have the model mention them in its responses. Hooks' systemMessage is a dead end for badges by design.
- The 5-badge FIFO means a multi-repo summary turn with >5 references silently drops the earliest ones — put the most important reference last in the text (newest match wins the leftmost slot).
- The current-branch PR badge is the only zero-config badge; workflows that keep one PR per branch already get that for free.

## Surprises

- The `"url": "{u}"` whole-match template silently kills every match (origin-shift guard). The docs example uses static origins but doesn't warn about this; without `--debug` there is zero feedback.
- Badges replace the "? for shortcuts" hint text rather than adding a new footer row.
- Badge order is newest-first, and displacement happens even within a single turn (6 matches in one reply → first match already displaced by turn end).
- An unexplained right-aligned footer label `always_include_links` appeared in every lab session even though the lab cwd is not a git repo; the string matches a path component of the parent session's worktree (`tsuku+always_include_links-fe2fc637`), suggesting inherited-environment leakage into the footer label.

## Open Questions

- Where does the `always_include_links` footer label come from (stale `PWD` env? bridge-session metadata?) — cosmetic, but it means pty children inherit some display state from the spawning session.
- Do badges survive `/compact` or session resume (`claude -c`)? Only `/clear` removal is documented; not tested (would need a fifth session).
- Deduplication semantics: the code appears to dedupe identical url+label pairs across scans (`Myr` comparison), but we never fed a duplicate to verify.
- Whether managed-settings-delivered regexes behave identically (assumed; not testable in this environment).

## Summary

Claude Code has no native footer-badge detection for PR/issue URLs in assistant text: with no configuration, four fake PR URLs (and owner/repo#N and #N shorthands) produced zero badges, and the only automatic footer badge is the current-branch PR badge. The behavior lives entirely in the `footerLinksRegexes` setting (v2.1.176+, user/`--settings`/managed scopes only): once configured, badges reproduce cleanly in the pty rig — one per regex match on turn output, hard cap of 5 with oldest-displaced FIFO, newest-first order, standing unchanged across subsequent turns until `/clear` — while hook systemMessage text never badges even when it exactly matches a configured pattern. Two practical gotchas: a `url` template without a literal origin (e.g. `"{u}"`) is silently dropped as origin-shifted, and the 5-badge cap silently discards the earliest references in link-heavy turns.

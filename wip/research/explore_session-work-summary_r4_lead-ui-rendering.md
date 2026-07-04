# Lead: Does the block render well in the real UIs?

## Findings

Environment: Claude Code v2.1.201. tmux, screen, and expect are all absent from this machine and not installable without sudo (tsuku has no tmux recipe). Substituted an equivalent rig: `pexpect` drives a real pty at a chosen size, `pyte` (a VT emulator) renders the byte stream into a virtual screen — functionally identical to `tmux capture-pane`. Driver scripts and raw screen dumps live in `/home/dangazineu/.claude/jobs/a050f0e4/tmp/hook-lab-ui/` (`drive_claude.py`, `drive_agents.py`, `captures/*.txt`).

Hook under test (`hooks/sysmsg-realistic.sh`, wired as PostToolUse:Bash in the lab's `.claude/settings.json`): emits a single `systemMessage` containing `=== WORK IN FLIGHT ===` plus three pipe-delimited ~110-125 char lines, each ending in a bare `https://github.com/...` PR URL.

### Experiment 1: interactive TUI, 220-column terminal

Setup: spawn `claude --model haiku` in the lab at 220x50, dismiss onboarding dialogs, cycle out of plan mode (shift+tab), send a prompt that triggers `echo hello-work-in-flight` (pre-allowed via `permissions.allow: Bash(echo *)`).

Captured main view (`captures/w220-20-after-response.txt`):

```
❯ Run exactly this bash command using the Bash tool, then reply with just the word done: echo hello-work-in-flight
  Ran 1 shell command
  ⎿  PostToolUse:Bash says: === WORK IN FLIGHT ===
     tsukumogami/tsuku | #4821 open | fix recipe checksum verification on partial dl | https://github.com/tsukumogami/tsuku/pull/4821
     tsukumogami/niwa | #392 merged | add ephemeral instance reaping on session end | https://github.com/tsukumogami/niwa/pull/392
     tsukumogami/koto | #77 ci-running | retry workflow steps on transient errors | https://github.com/tsukumogami/koto/pull/77
● done
```

Verdict: renders visibly and intact as a block. Styling: dim gray (RGB 153,153,153), indented 5 spaces, attached to the tool-result group with a `⎿` connector. The first line gets the prefix `PostToolUse:Bash says: ` prepended inline, so the marker renders as `⎿  PostToolUse:Bash says: === WORK IN FLIGHT ===`. Lines 2-4 render verbatim with URLs unbroken. Notably, in the default (collapsed) view the tool's own stdout is hidden ("Ran 1 shell command") but the hook systemMessage still displays — it survives output collapsing.

### Experiment 2: Ctrl+O transcript (verbose) view

Sent Ctrl+O in the same session (`captures/w220-30-ctrl-o.txt`):

```
● Bash(echo hello-work-in-flight)
  ⎿  hello-work-in-flight
  ⎿  PostToolUse:Bash says: === WORK IN FLIGHT ===
     tsukumogami/tsuku | #4821 open | fix recipe checksum verification on partial dl | https://github.com/tsukumogami/tsuku/pull/4821
     ...
                                                    11:01 AM claude-haiku-4-5-20251001
```

Verdict: verbose view shows the tool call, its stdout, and the block as a second `⎿` item under the same tool use. Identical formatting; block intact.

### Experiment 3: narrow terminal (100 columns) — wrap behavior

Same scenario at 100x50 (`captures/w100-20-after-response.txt`):

```
  Ran 1 shell command
  ⎿  PostToolUse:Bash says: === WORK IN FLIGHT ===
     tsukumogami/tsuku | #4821 open | fix recipe checksum verification on partial dl |
     https://github.com/tsukumogami/tsuku/pull/4821
     tsukumogami/niwa | #392 merged | add ephemeral instance reaping on session end |
     https://github.com/tsukumogami/niwa/pull/392
     tsukumogami/koto | #77 ci-running | retry workflow steps on transient errors |
     https://github.com/tsukumogami/koto/pull/77
```

Verdict: the TUI word-wraps at spaces, so each ~120-char line breaks before the URL and the URL lands intact on its own continuation line. No mid-URL break for URLs of this length (~46-48 chars); terminal URL detection/clicking would still work. A URL longer than the usable width (~95 cols here) would necessarily hard-wrap, so the "URL last, line ~110 chars" convention is safe down to roughly 60-col terminals.

### Experiment 4: background session via `claude --bg`

`claude --bg --model haiku "<echo prompt>"` worked headlessly, returned `backgrounded · bf73aa40` immediately, and the PostToolUse hook fired (verified via the lab's stdin log and the session JSONL). Three sub-surfaces checked:

1. `claude logs bf73aa40` replays the session's rendered ANSI stream — the block appears exactly as in the interactive TUI, `⎿  PostToolUse:Bash says: === WORK IN FLIGHT ===` plus the three URL lines.
2. The session JSONL (`~/.claude/projects/-home-dangazineu--claude-jobs-a050f0e4-tmp-hook-lab-ui/bf73aa40-*.jsonl`) contains both a `hook_success` attachment (raw hook stdout JSON) and a `hook_system_message` attachment with the full multi-line content — matching round 3's persistence finding, now confirmed for --bg sessions.
3. `claude attach bf73aa40` (a fresh UI process re-rendering from the persisted JSONL) redraws the complete conversation including the block, in both collapsed and Ctrl+O verbose views (`captures/attach-00-initial.txt`, `attach-10-ctrl-o.txt`). So the persisted `hook_system_message` record does drive re-rendering — display is durable across attach/resume, not just live-session ephemera.

### Experiment 5: Agent View (`claude agents`)

Drove the TUI at 220x50 (`captures/agents1-00-list.txt`, `agents2-*.txt`). The list shows one row per session: status glyph, session name (`bg-work-in-flight` — derived from the prompt), a one-line latest-status summary ("command executed"), an optional PR chip, and age. Two findings:

- The row summary is the session's own generated status text, NOT the hook systemMessage. The block never appears at list level.
- Agent View has a native PR chip ("3 PRs", "2 PRs" on other live sessions) rendered from sessions' actual PR activity. The hook-emitted PR URLs did not produce a chip on the bg session's row — the chip surface is fed by real `gh`/git activity, not by systemMessage content.

Row-level selection/navigation works (arrow keys move focus across section headers and rows; Enter on a header collapses the section, Enter on a row opens/attaches). Since the block is re-rendered on attach (Experiment 4.3), the Agent View drill-in path does show it — just not the list row.

## Implications

- The deterministic work-summary design is viable end to end: a PostToolUse (or Stop) hook's `systemMessage` is visibly rendered in the live TUI, survives output collapsing, persists to JSONL, and re-renders on `claude attach` / resume — all with zero context-window cost.
- Design the block knowing the renderer prepends `<HookEvent>:<Matcher> says: ` to the first line and paints everything dim gray. The `=== WORK IN FLIGHT ===` marker still reads fine after the prefix, but the block is styled as secondary/diagnostic output, not a banner — don't rely on it for must-see alerts.
- Keep the bare URL as the last token on each line and lines ≲110 chars: word-wrap then guarantees the URL survives intact on its own line at any terminal ≳60 cols.
- Do not expect the block to surface in the Agent View session list. If PR visibility at list level matters, the session must actually create PRs (native chip) or the summary text must mention them; the hook block only shows after drill-in/attach.
- `claude --bg` sessions load project hooks normally, so the same dot-niwa hook covers dispatched/background workers with no extra wiring.

## Surprises

- The systemMessage renders inside the tool-result group (second `⎿` item) rather than as a freestanding system line — visually it reads as an annotation of the triggering tool call.
- It stays visible when the tool's own output is collapsed to "Ran 1 shell command" — better default visibility than the tool output itself.
- Agent View already has a first-class "N PRs" chip per session row, fed by real PR activity — partially overlapping this design's goal, worth noting in the design doc.
- Scripted-session hazards: a Claude-in-Chrome onboarding dialog and default plan mode both intercepted the first scripted run (a stray Enter briefly enabled Chrome-by-default globally; reverted `claudeInChromeDefaultEnabled` to false in `~/.claude.json`).
- The bg session's transcript timestamps its reply as `claude-sonnet-5` despite `--model haiku` on the `--bg` invocation (the interactive runs correctly show `claude-haiku-4-5-20251001`); `--bg` may not honor `--model`.

## Open Questions

- Does the Stop-hook `systemMessage` (the design's likely final placement, vs PostToolUse tested here) render with the same `⎿` attachment or as a standalone line? Same mechanism is documented, but placement wasn't empirically driven this round.
- Is the dim-gray styling prominent enough for the end-of-session summary use case, or should the design also emit the block in the final assistant text for high-visibility surfaces?
- Does `--bg` ignoring `--model` matter for dispatched workers (cost/behavior), or was it a one-off?

## Summary

The multi-line work-in-flight block renders correctly in every real UI surface tested on Claude Code v2.1.201: intact as a dim-gray block attached under the triggering tool call (prefix `⎿ PostToolUse:Bash says: ` on the marker line) in the live TUI, in Ctrl+O verbose view, in `claude logs`, and re-rendered from the persisted `hook_system_message` JSONL record on `claude attach`. Narrow terminals word-wrap at spaces so trailing bare URLs land intact on their own continuation line; the block even stays visible when tool output is collapsed. The one gap is the Agent View session list, which shows only the session's own status summary and a native PR chip driven by real PR activity — hook-emitted URLs never surface at list level, only after drill-in/attach.

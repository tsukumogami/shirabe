# Handoff brief: compaction note and hooks

A session that compacts keeps running under its own id, but the summary
Claude Code writes can lose which skill it was running and where that skill's
koto run stands. The compaction note and its two hooks carry that back. Before
a compaction the session records what it is running; the `PreCompact` hook
asks the summary to name it; the `SessionStart` hook, matched on `compact`,
tells the session to re-read the skill and check koto before it does anything
else.

This reference covers the pieces that exist today: the note writer, the
ledger entry, the two hooks, how to install them, the window setting, and the
results of one live compaction read against them. Later work adds the brief a
run hands forward at its end and the checks around it.

## The note writer

```
scripts/handoff-brief.sh note --reasoning <file> \
    --skill "<name> [<args>] <absolute SKILL.md path>" [--skill ...] \
    [--koto-session <name>] [--pr <url>]
```

It writes the reasoning file to `compaction/note.md` in the koto session
(`--koto-session`, else `$KOTO_SESSION`), then writes the ledger entry for the
running session at `$XDG_STATE_HOME/shirabe/compaction/<session-id>` (or the
same path under `$HOME/.local/state`). The session id comes from
`CLAUDE_CODE_SESSION_ID`. The directory is mode 0700, the file 0600, written
through a temporary file and a rename, and a link at either path is refused.
The entry holds one line each for `koto_session`, `note_key`, `branch` and
`pr` (a URL or `none`), then one `skill:` line per `--skill`, outermost first.

Exit 0 means both writes landed, 1 that a write failed, and 2 that an argument
was refused and nothing was written.

## The hooks

`shirabe compaction pre-compact` prints a plain-text instruction for the
summary: name the koto session, branch, pull request, note key and each
`SKILL.md` path exactly as written. `shirabe compaction re-anchor` prints
`SessionStart` hook JSON whose `additionalContext` says to re-read each
`SKILL.md`, run `koto status` on the koto session, then read the note.

Both read `session_id` from the hook input on stdin, check every field's
grammar again, read the entry without following links, and withhold any
output over 10,000 characters rather than cut it. On any failure (no entry, a
refused id, an unreadable file) both exit 0 and print nothing, so they never
block a compaction or put hook input in front of the model.

## Installing the hooks

Each hook is a two-line script that names the binary by absolute path and
exits 0 silently when it is missing:

```sh
#!/bin/sh
[ -x /abs/path/to/shirabe ] || exit 0; /abs/path/to/shirabe compaction pre-compact; exit 0
```

and the same for `re-anchor`. Register them in a settings file:

```json
{
  "hooks": {
    "PreCompact": [
      { "hooks": [ { "type": "command", "command": "/abs/path/hooks/pre-compact.sh" } ] }
    ],
    "SessionStart": [
      { "matcher": "compact", "hooks": [ { "type": "command", "command": "/abs/path/hooks/re-anchor.sh" } ] }
    ]
  }
}
```

## The window

Claude Code reads the compaction window from `CLAUDE_CODE_AUTO_COMPACT_WINDOW`
in the `env` block of its settings. A hook can't set it, because a hook can't
change the environment of the process it runs under, so whatever launches the
session sets it: the session's own settings file, a `--settings` document
passed at launch, or a workspace tool that writes settings for the sessions
it starts. Claude Code refuses values under 100,000. Claude Code 2.1.330 also
has a `--autocompact <auto|tokens>` launch flag; the live read below used the
settings `env` block only.

## Live read: one compaction of a background session

### Test condition

- Claude Code 2.1.330, default model, one `claude --bg` session launched by
  hand with `--permission-mode bypassPermissions`.
- A background launch needs its working directory trusted by exact path; a
  directory nested under a trusted one isn't trusted. So the session started
  in an already-trusted directory with `--setting-sources user`, which loads
  no project or local settings from it. The `CLAUDE.md` files above that
  directory still loaded.
- The two hooks sat in the `--settings` document passed at launch, next to the
  `env` block that carried the window. That is the session's settings layer,
  not a directory's `.claude/settings.json`, and it's the same layer a
  workspace tool's launch settings use.
- The skill was a test skill loaded with `--plugin-dir` and invoked as the
  launch prompt. It opened a two-state koto run, wrote the note, then read
  large files until a compaction. A marker line in its text made survival
  checkable.
- The `env` block also set `KOTO_HOME`, `KOTO_SESSION_BACKEND=local` and
  `XDG_STATE_HOME` to scratch paths, so the koto run and the ledger stayed out
  of any real store.
- The session moved itself into a git worktree of the scratch directory
  before writing, as background sessions are told to do. Claude Code moved its
  transcript to the worktree's project directory; every record kept the
  launch session id.

### Floor and window

A session launched the same way with the prompt "reply ok" read 48,350
tokens on its one turn. That's the floor. The window was the floor plus
90,000, rounded up to 140,000.

### Result

- **Window carriage**: the compaction fired automatically at 121,577 tokens
  (after it, 31,362), well under the model's own limit, so the window reached
  the session from the `--settings` document. `printenv
  CLAUDE_CODE_AUTO_COMPACT_WINDOW`, run by the session after the compaction,
  printed `140000`.
- **Boundaries**: exactly one `compact_boundary` record, trigger `auto`, in 23
  assistant records.
- **Identity**: the id was unchanged and the session was live. The job state
  file was read when the ledger entry appeared, again when the boundary
  record was written (the compaction took about 34 seconds), and at the first
  check after it. Each read showed the launch id, state `working` and a null
  `firstTerminalAt`. A two-second poll over the whole run, set to stop on any
  terminal state, saw none until the turn ended. The job's own timeline shows
  `working` before and after the compaction. All 63 records after the
  boundary sit in the launch transcript under the launch id. No other job
  directory appeared, and the process that owned the session was alive after
  the boundary. The session ended as `done` 17 seconds after the boundary,
  when its single prompt finished. That's the normal end of a one-prompt
  background session, not a loss of liveness, so liveness reads for such a
  session have to be taken while it works.
- **Re-anchor**: the `SessionStart` hook ran on `compact` and its text
  followed the boundary as additional context. The session's first tool calls
  after the boundary were a read of the recorded `SKILL.md`, then `koto status`
  on the recorded koto session (with the note read in the same command). It
  then picked the run up where koto said it stood and finished it.
- **PreCompact output**: it reached the summary. The summary carries the hook's
  list verbatim: koto session, branch, "pull request: none recorded", the note
  key and the `SKILL.md` path. The transcript keeps no record of the
  `PreCompact` hook itself, so the summary text is the evidence.
- **Skill text**: it survived. The summary quotes the skill's marker line, and
  Claude Code also re-attached the invoked skill's full text after the
  boundary on its own.
- **Ledger entry**: mode 0600 in a 0700 directory, with one `skill:` line
  naming the skill, its argument and its `SKILL.md` path; reading the note
  back from koto printed the reasoning text.
- **Re-anchor size**: 630 bytes, holding neither the note's text nor the
  skill's.

### Hand runs

Both hook scripts were run by hand with a hook input carrying the test
session's id:

| Condition | pre-compact | re-anchor |
|-----------|-------------|-----------|
| Entry and binary present | exit 0, 621 bytes | exit 0, 630 bytes |
| Ledger entry deleted | exit 0, no output | exit 0, no output |
| Binary moved away | exit 0, no output | exit 0, no output |
| Session id holding `/` | exit 0, no output | exit 0, no output |
| Session id `..` | exit 0, no output | exit 0, no output |
| Session id holding a newline | exit 0, no output | exit 0, no output |

## Switching roles on

No role switches compaction on by default until this identity read shows
the session id unchanged and the session live across a compaction. This read
did, for a background session running one koto-backed skill under the test
condition above. Each role's switch-on repeats the read for that role's own
launch.

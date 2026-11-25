# Handoff brief: compaction note and hooks

A session that compacts keeps running under its own id, but the summary
Claude Code writes can lose which skill it was running and where that skill's
koto run stands. The compaction note and its two hooks carry that back. Before
a compaction the session records what it is running; the `PreCompact` hook
asks the summary to name it; the `SessionStart` hook, matched on `compact`,
tells the session to re-read the skill and check koto before it does anything
else.

This reference covers the pieces that exist today: the note writer, the
ledger entry and its cleanup, the two hooks with the stale flag and the
checks an entry must pass, reading the note back, how to install the hooks,
the window setting, the results of two live compaction reads against them,
and the brief a session hands forward when it stops, with the closing step
before it, the brief's two size limits, the opt-in keep record, park and
resume.

## The note writer

```
scripts/handoff-brief.sh note --reasoning <file> \
    --skill "<name> [<args>] <plugin root>/skills/<dir>/SKILL.md" [--skill ...] \
    [--koto-session <name>] [--pr <url>]
```

It writes the reasoning file to `compaction/note.md` in the koto session
(`--koto-session`, else `$KOTO_SESSION`), then writes the ledger entry for the
running session at `$XDG_STATE_HOME/shirabe/compaction/<session-id>` (or the
same path under `$HOME/.local/state`). The session id comes from
`CLAUDE_CODE_SESSION_ID`. The directory is mode 0700, the file 0600, written
through a temporary file and a rename, and a link at either path is refused.
The entry holds one line each for `koto_session`, `note_key`, `branch`,
`repo` and `pr` (a URL or `none`), then one `skill:` line per `--skill`,
outermost first. `repo` is the repository's top level, as
`git -c core.fsmonitor=false -c core.hooksPath=/dev/null rev-parse --show-toplevel`
prints it in `note`'s working directory, so a hook run from somewhere else
can still read the branch. It must be an absolute path of at most 512 bytes
with no control or format character, or `note` refuses; when `note` isn't
run in a work tree (inside a `.git` directory, say) the line is left out.

Each `--skill` path must exist and sit in a plugin's layout,
`<plugin root>/skills/<dir>/SKILL.md`, and the skills of one plugin (the
`<plugin>:` part of the name, such as `shirabe:`) must share one plugin root.
A skill named without a plugin is checked for the layout only. The hooks
apply the same rule, so `note` refuses what they would not use.

Exit 0 means both writes landed, 1 that an argument was refused and nothing
was written, and 2 that koto or git is missing or a write failed. These are
the codes every `handoff-brief.sh` subcommand uses.

### Cleanup

Once its own entry is in place, each `note` removes the other entries in the
ledger directory whose modification time is more than 30 days old. It
removes only regular files whose names pass the session-id grammar
(`[A-Za-z0-9-]{1,64}`); a link is never followed or removed, and a directory
or any other name is left alone. Entries 30 days old or younger, and the
note's own, stay. A removal that fails prints a warning on stderr and the
note still exits 0.

## The hooks

`shirabe compaction pre-compact` prints a plain-text instruction for the
summary: name the koto session, branch, pull request, note key and each
`SKILL.md` path exactly as written. `shirabe compaction re-anchor` prints
`SessionStart` hook JSON whose `additionalContext` says to re-read each
`SKILL.md`, run `koto status` on the koto session, then read the note with
`handoff-brief.sh read --note --session <koto session>`, which prints it as
data (see [Reading the note back](#reading-the-note-back)).

Both read only `session_id` from the hook input on stdin. A session id that
fails its grammar, or an input that isn't JSON, gets exit 0 and no output,
and no file is opened for it. Both exit 0 on every path, so they never block
a compaction, and nothing from the hook input ever reaches their output.
Neither makes a `gh` call; branch and pull request come from the entry, which
`note` filled at its last write. Every `git` call runs with
`-c core.fsmonitor=false -c core.hooksPath=/dev/null -c log.showSignature=false`
and with `GIT_NO_LAZY_FETCH=1` and an empty `GIT_ALLOW_PROTOCOL` set in its
environment (the second allows no transport at all, so it covers a git that
ignores the lazy-fetch variable, which only git 2.44 and the May 2024
maintenance releases honour), and the `git log` call
also passes `--no-show-signature`, so a repository's fsmonitor, hooks or
signature program (`gpg.program`, which `git log` runs when the repository
sets `log.showSignature` and the tip is signed) never run from a hook, and
neither does a partial clone's promisor remote transport
(`remote.<name>.uploadpack`, `core.sshCommand` or a remote helper, which a
lazy fetch of a missing branch tip would run). koto and git are found on `PATH`. A koto or git call is done
when it has exited and its output has been read to the end; a child that
leaves a process holding its output open still ends at the call's 5-second
limit, its answer unreadable.

### Which entries are used

A hook uses an entry only when all of these hold:

- the ledger directory is a real directory of mode 0700, opened without
  following a link (a symlinked directory is not used);
- the entry is opened through that directory without following a link and
  without waiting on a FIFO, and is a regular file of mode 0600;
- every field passes its grammar: the koto session name koto's grammar
  (`[A-Za-z0-9][A-Za-z0-9._-]{0,127}`), the note key exactly
  `compaction/note.md`, the branch `[A-Za-z0-9._/-]{1,200}` with no `..` and
  no leading `-` or `/` (so no control character), the pull request a GitHub
  pull request URL or `none`, and each `skill:` line a skill name, arguments
  from a fixed character set and a `SKILL.md` path in a plugin's layout, with
  the skills of one plugin under one plugin root and at most eight skills;
- where `KOTO_SESSION` is set, the entry's koto session equals it.

An entry that fails any of these is treated as no entry at all, and the hooks
print the no-entry outputs below, which hold none of its text.

The `repo` line is checked apart from the rest, and failing its checks never
makes the entry unusable. It may appear at most once. The hook uses it only
when it passes the grammar `note` applies (absolute, at most 512 bytes, no
control or format character), the path is not a symlink (checked without
following it) and is a directory, and
`git -C <repo> rev-parse --is-inside-work-tree`, with the same safe flags and
within the same 5-second limit, prints `true`. Otherwise the hook falls back
to its own working directory, exactly as for an entry with no `repo` line.
The path is never printed.

### No usable entry

For a valid session id with no usable entry (none written, deleted, or
refused by the checks above), `pre-compact` prints a summary instruction that
says no compaction note is recorded and names the branch `git` reads in the
hook's working directory (`git symbolic-ref --short HEAD`), or says the branch
could not be read there. `re-anchor` prints a generic line: work out the skill
from the koto session's name prefix (`deliver-`, `scope-`, `coordinate-`) and
re-read that skill's `SKILL.md`, run `koto status` on that session in your
worktree (`koto workflows` lists the sessions there), and read the note with
`handoff-brief.sh read --note --session <koto session>`. A usable entry whose
re-anchor block would reach 10,000 characters gets the same steps rather than
a cut block, behind a first line saying its ledger entry is recorded but too
long to show, instead of saying no note is recorded. Both outputs stay under
10,000 characters.

### The stale flag

`pre-compact` judges the note stale when the work moved on after the note's
last write, and then adds one line: the note is stale, and rewriting it is the
first step after the compaction. It has two inputs.

- **The koto session.** koto prints no session-wide latest event seq (neither
  `koto status` nor `koto session list` carries one), so the hook reads it
  through koto's own CLI, none of whose verbs used here logs a read. `koto
  context history <session> compaction/note.md` gives the note's last write:
  its seq, timestamp and the state the run was in. `koto status <session>`
  gives the run's current state; a different one means a transition came
  after the note. `koto context list <session>`, then `koto context history`
  for each other key, gives each key's latest write seq; one above the note's
  means a key was written after it. Reads are logged by koto but don't count:
  only writes and state changes move the work on. A transition that returns
  to the note's own state, with no key written, isn't seen.
- **The branch.** The commit time of the tip of `refs/heads/<branch>`, the
  entry's branch (`git log -1 --no-show-signature --format=%ct`), run with
  `git -C` in the entry's `repo` when the hook accepts it, else in the hook's
  working directory's repository. A commit time later than the note's write,
  in whole seconds, marks the note stale.

Rewriting the note puts its last write after every other key's and after the
commit, which clears the line.

When freshness can't be read, the summary instruction is printed whole and
gets a different line instead of the stale one: whether the note is current
could not be checked, so after the compaction the session reads the note and
rewrites it first if it is behind the work. That happens when koto or git
can't be run, the note has no write history, any koto answer can't be read or
parsed, the entry's branch isn't in the repository read (the entry's `repo`,
or the working directory's when that is refused or absent), a key
name falls outside koto's key grammar, or the session holds more than 256
keys. Each koto or git call is killed after 5 seconds and the whole read after
20. A stale finding wins over an unreadable one: if any input shows the note
stale, the stale line is printed.

## Reading the note back

```
scripts/handoff-brief.sh read --note [--session <name>]
```

prints `compaction/note.md` from the koto session (`--session`, else
`$KOTO_SESSION`, as `read` finds a session) as data from an earlier session:
the session and key, then the note between two lines holding a delimiter made
fresh for this call (`@@note-<32 hex>@@`), with control and format characters
shown as `<U+XXXX>`: C0, DEL and C1, U+00AD, U+061C, U+180E, U+200B-U+200F,
U+2028-U+202E, U+2060-U+2064, U+2066-U+206F, U+FEFF, U+FFF9-U+FFFB, and the
tag characters U+E0000-U+E007F (shown with five hex digits, `<U+E0049>`).
`read` marks the same set. Nothing is written to disk and nothing in the note is
run. With no note in the session it exits 1 naming `compaction/note.md`; with
koto missing it exits 2.

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
  session have to be taken while it works. This run didn't place its second
  read inside the compaction, and its session had moved its transcript; the
  [second read](#second-read-liveness-while-the-compaction-runs) settles
  both.
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

These runs predate the no-entry outputs. Today a deleted entry still exits 0
but prints the no-entry summary instruction and the generic re-anchor line
described under [No usable entry](#no-usable-entry); the other rows are
unchanged.

### Second read: liveness while the compaction runs

The first read took its middle liveness read when the boundary record was
written, which doesn't say whether that falls inside the compaction or at
its end. It also doesn't name the transcript file its post-boundary records
came from. A second live run, on Claude Code 2.1.332 with the default model,
answers both.

Test condition, where it differs from the first run:

- The launch directory was trusted but not a git repository, so the session
  had no worktree to move into and Claude Code kept its transcript where the
  launch put it. `--setting-sources user` kept that directory's project
  settings from loading, as before.
- The `--settings` document added one test-only command to each hook event,
  beside the two shirabe hooks. In `PreCompact` it marks the compaction's
  start; in `SessionStart` on `compact` it marks the end. Each one appends
  the time to the millisecond and a read of the job state file's
  `sessionId`, `state` and `firstTerminalAt`, then prints nothing and exits
  0.
- A poller outside the session read the same three fields from the job state
  file every second for the whole run and never stopped on a terminal state.
- After the compaction the skill had the session pause for 120 seconds
  before closing its run, so it stayed live through the third read. Claude
  Code 2.1.332 refuses a foreground `sleep` of that length, so the session
  ran it as a background command and waited for it.
- `claude --bg` ignores `--session-id`, so the launch id is the one the
  launch prints, read back from the job state file.

Floor and window: a "reply ok" session launched the same way read 45,410
tokens on its one turn. The window was the floor plus 90,000, rounded up to
140,000.

Result:

- **Compaction times**: the start mark is 04:18:01.491Z and the end mark is
  04:18:31.122Z. The `compact_boundary` record carries 04:18:31.248Z and a
  `durationMs` of 29,584, so Claude Code writes the boundary record when the
  compaction ends, not when it starts. A read taken when the boundary record
  appears is an after-the-end read.
- **Before**: read at 04:17:55.209Z, once the ledger entry existed and six
  seconds before the start mark. `sessionId` was the launch id, `state`
  `working`, `firstTerminalAt` null.
- **While it runs**: 29 poller reads fall strictly between the two marks,
  the first at 04:18:01.928Z and the last at 04:18:30.561Z. Each one shows
  the launch id, `working` and a null `firstTerminalAt`; the one at
  04:18:16.235Z, halfway through, reads
  `{"sessionId":"<launch id>","state":"working","firstTerminalAt":null}`.
  Both marks read the same.
- **After**: read at 04:18:34.232Z, three seconds after the end mark, while
  the session worked through its post-compaction steps: the launch id,
  `working`, a null `firstTerminalAt`.
- **Over the whole run**: none of the poller's 1,313 reads showed another
  id, a terminal state or a set `firstTerminalAt`. The session later went
  from `working` to `blocked` when its turn ended and it waited for input,
  which is still a live state.
- **Transcript file**: exactly one `compact_boundary` record, trigger
  `auto`. The post-boundary records were read from
  `~/.claude/projects/<launch directory's project slug>/<launch id>.jsonl`,
  the file the launch created: it had the same path and inode at launch as
  after the boundary. All 79 records after the boundary carry the launch
  `sessionId`, and no other file with the launch id exists under
  `~/.claude/projects`.
- **Process and job directories**: the session's process, which
  `claude agents --json` lists under the launch id, was alive after the
  boundary. One job directory appeared during the window, and it belongs to
  an unrelated session started in another directory; none appeared for this
  session under another id.
- **After the boundary**: the re-anchor text followed it as hook context.
  The session's first tool calls were a read of the recorded `SKILL.md`,
  then `koto status` on the recorded koto session, and it kept making tool
  calls after that. `printenv CLAUDE_CODE_AUTO_COMPACT_WINDOW` printed
  `140000`, and the compaction fired at 124,438 tokens, under the model's
  own limit.

## The closing step

```
scripts/closing-step.sh <worktree> [--instance <root>]
```

A session runs this before it writes its brief at a run's end. It blocks on
an untracked file that `git check-ignore` doesn't match, a detached HEAD, a
branch with no upstream, and any commit in `git rev-list @{u}..HEAD`. It
prints `closing=blocked` and one line per cause (`stray: <path>`,
`detached: ...`, `no-upstream: <branch>`, `unpushed: <sha> <subject>`), then
exits 1. The upstream is the local remote-tracking ref, and nothing is
fetched.

On a pass it prints `closing=pass` and `instance=<root>` and exits 0. The root
is `--instance` when given, else the directory that holds the worktree's
repository (the parent of its main checkout). It never deletes the worktree.
It prints `done=yes` only when the caller's working directory is outside the
worktree, and `done=no`, with the directory to move to on stderr, when it is
inside. Exit 2 means git is missing or the argument isn't a directory inside
a git work tree. Every git call turns off `core.fsmonitor` and
`core.hooksPath`, so a repository's own configuration runs nothing.

So the order at a run's end is: run the closing step from inside the worktree
until it prints `closing=pass`, then run `write` from inside the worktree too,
because `write` reads the branch, the pull request and the pushed head from
its working directory and records `none` for each when that isn't the
worktree. Only then move to the instance root and run the closing step again,
which now prints `done=yes`.

## The brief at a run's end

```
scripts/handoff-brief.sh write --reasoning <file> --event end|park|stop \
    [--file <path>]... [--watch "<label>=<re-arm command>"]... \
    [--standing-rules <file>] [--instance <root>] [--keep-record <path>]
scripts/handoff-brief.sh resume [--instance <root>] [--keep-record <path>]
scripts/handoff-brief.sh read [--session <name>]
```

`write` stores one brief as `brief/brief.md` in the session's koto session,
and the exact bytes of each named file that fits the inline size at
`brief/files/<sha256>`. `end` is a run's end, `stop` a session stopping
before its run ends, and `park` a stop that holds the instance until a later
`resume`. The brief has a fixed layout:

```markdown
# Handoff brief
written_at: 2026-11-22T15:30:00Z
event: end
## Reasoning
<what was concluded, what was ruled out and why, the next step>
## Pointers
koto_session: <name>
branch: <name>   pull_request: <number|none>   pushed_head: <sha|none>
watch: <label> = <re-arm command>
## Files
scratch:<path under the job's scratch directory><TAB>sha256:<hex><TAB>bytes:<n><TAB>inline:yes|no
instance:<path under --instance><TAB>sha256:<hex><TAB>bytes:<n><TAB>inline:yes|no
## Standing rules
None stated.
```

Pointers are read, not passed. The branch is `git branch --show-current`
(`none` outside a repository or on a detached HEAD). The pull request is the
first number from `gh pr list --head <branch> --state open`, or `none` when
gh runs and finds none. The pushed head is the commit `git ls-remote` reports
for the branch's upstream, looked up by remote name and never by URL. When
local HEAD is ahead of it, the brief still shows the remote's commit. The
Files section reads `None named.` with no `--file`, and Standing rules reads
`None stated.` with no `--standing-rules`. `written_at` is taken before any
file is hashed, so a file changed during the write reads as newer than the
brief.

The koto session is `$KOTO_SESSION` when set. With no koto run, `write`
opens a plain koto session from `koto-templates/skill-session.md`, named
`handoff-<job-id>` (the base name of `$CLAUDE_JOB_DIR`). With no job it's
`handoff-<session-id>`, from the job's `state.json` or
`CLAUDE_CODE_SESSION_ID`. `write` stores the brief there and closes the
session `done`. A closed session's keys stay readable with `koto context get`,
and a later `write` from the same job stores into the same session rather
than replacing it. With no koto run, no job and no session id, `write`
refuses and opens nothing. It prints `session=<name>`, `key=brief/brief.md`
and `files=<n>`, and `record=<path>` when it wrote a keep record.

The store order is the inline file keys, then `brief/brief.md`, then the keep
record where a path is given, so a brief never names a key that isn't there
and a record never points at a brief that isn't there. Before anything is
stored, `write` asks `koto context exists` about every key it will store:
exit 0 is present, 1 is absent, and anything else is a koto fault, which
exits 2 before any key is stored rather than being read as an absent key. A
`brief/brief.md` that is already there is read first. If a later store
fails, `write` exits 2, removes every key this call added, and puts the
earlier `brief/brief.md` back to the bytes it held before this call.

### The two limits

The inline size is 262,144 bytes (256 KiB). A named file at or under it is
stored at `brief/files/<sha256>` and its Files line ends `inline:yes`. A
larger file gets no key: its Files line still shows its path, sha256 and byte
count, and ends `inline:no`, so the brief names it by reference and the file
has to be read where it sits. The rendered `brief/brief.md` must fit the
inline size too, so a reasoning or standing rules file too large for it is
refused. The inline size sits under shirabe's 1 MiB limit on one stored
value.

The record cap is 2,097,152 bytes (2 MiB) over every file one brief names,
by-reference files included. A brief whose named files total more is
refused. A file's size is checked against the cap before it is copied, so a
huge file is never copied into the private directory.

Every rule in the next two sections applies to every named file, inline or by
reference: a by-reference file is still checked for its path, its basename
and its content before the brief names it.

### Where a named file may come from

A named file, and the `--reasoning` and `--standing-rules` files, must sit in
scratch:

- the job's scratch directory, `$CLAUDE_JOB_DIR/tmp`;
- with `--instance <root>`, loose files at that root, outside every repository
  worktree and every dot-directory there (`.git/`, `.claude/` and the like);
- for the reasoning and rules files only, the job directory itself.

`--instance` must be an existing directory that encloses the working
directory and doesn't itself sit inside a git worktree.

Each path must be a regular file with a link count of 1, readable, with no
symlink in any component under its scratch root, and no `.` or `..`
component. A `*.jsonl` name, or a first line that parses as a transcript
record, is refused: a transcript is never named. A path holding a tab, a
control character or a Unicode format character is refused. Each file is
copied once into a private 0700 directory under `$TMPDIR`, and its size,
hash and stored bytes come from that copy. The source is hashed again after
the copy, and a file that changed in between is refused. The private
directory is removed when the script exits.

### What is refused

Each of these exits 1, names the cause, and writes no key:

- reasoning that is empty once whitespace is trimmed;
- a line beginning `## ` in the reasoning or the standing rules, a watch
  whose command begins with `## `, or a watch value holding a newline, since
  any of them could open a forged section;
- a watch that isn't `<label>=<command>`, whose label is outside
  `[A-Za-z0-9._-]{1,64}`, whose command is empty, or that holds a shell
  operator (`;`, `&`, `|`, `<`, `>`, `$`, a backtick, a backslash or a
  parenthesis), a tab, a control character or a format character. A watch is
  one plain command;
- a basename matching a credential pattern, case ignored: `.env`, `.env.*`,
  `*.env`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`,
  `*.kdbx`, `*.ppk`, `*.gpg`, `*.asc`, `*.ovpn`, `*.tfvars`, `*.tfstate`,
  `id_*`, `.netrc`, `_netrc`, `.npmrc`, `.pypirc`, `.pgpass`,
  `.git-credentials`, `.htpasswd`, `.dockercfg`, `kubeconfig`,
  `credentials*`, `settings*.json`, `*secret*`, `*token*`, `*password*`,
  `*passwd*`;
- content in a named file, the reasoning, the standing rules or a watch
  matching a secret shape: GitHub tokens (`ghp_`, `gho_`, `ghu_`, `ghs_`,
  `ghr_`, `github_pat_`), an Anthropic key (`sk-ant-`), OpenAI project,
  service-account and admin keys, AWS access key ids (`AKIA`, `ASIA`), Slack
  tokens (`xoxa-`, `xoxb-`, `xoxp-`, `xoxr-`, `xoxs-`), GitLab tokens
  (`glpat-`), npm tokens (`npm_`), Google API keys (`AIza`), Stripe live keys,
  any PEM or OpenSSH private key block, a JWT-shaped string, a bearer or
  authorization header, a URL carrying `user:secret@`, cloud key JSON
  (`"private_key"`, `"client_secret"`, `"aws_secret_access_key"` and the
  like), an AWS secret key setting, and three or more `KEY=VALUE` lines in a
  row where one key names a secret (`KEY`, `TOKEN`, `SECRET`, `PASS`, `PWD`,
  `CREDENTIAL`, `AUTH`);
- a rendered `brief/brief.md` over the inline size, or named files totalling
  over the record cap;
- a keep record path that is relative with no `--instance`, whose directory
  doesn't exist or is a symlink, or that is itself a symlink or not a regular
  file, and an existing record that isn't one JSON object (left byte for byte
  as it was);
- a keep record lock another writer holds (see the keep record below).

A 40-hex git commit id or a 64-hex sha256 is not a secret shape and is never
refused.

The scan has holes. It catches token-shaped secrets, not every secret: a
password in prose, a credential in a format it doesn't list, or a pasted
transcript passes it. If a brief carried a credential the scan missed,
rotate the credential first and remove the key second, since a removal
doesn't undo a koto sync.

### Reading a brief

`read` takes `--session <name>`, else `$KOTO_SESSION`, and prints the brief
as data from an earlier session. It shows the header and Pointers first, with
each watch printed as text and never run. Then come the reasoning and the
standing rules, each between two lines holding a delimiter made fresh for
this call (`@@brief-<32 hex>@@`). A reasoning line that copies an earlier
call's delimiter stays inside the fence. Last is the Files section, after the
free text. For each inline file, `read` hashes the stored bytes and reports
`hash: verified` or `hash: MISMATCH`, then prints the bytes between fresh
delimiters. An `inline:no` line is printed as by reference, with its sha256
and bytes as written; koto holds no bytes for it, so there is nothing to
verify, and it never counts as a mismatch or a missing key. The last line is
`verified=all` or `verified=mismatch`, over the inline files. When
`brief/resumed` exists, `read` prints `resumed_at: <time>` after the
`event:` line, noting when that time is older than the brief's `written_at`,
which means it marks an earlier park than the brief shown.

Control and format characters are shown as `<U+XXXX>`, newlines aside. A
line inside the free text or a file that looks like a heading or a brief
field (`#...`, `written_at:`, `event:`, `koto_session:`, `branch:`,
`watch:`) is prefixed `[flag]`, as is any line outside its section. `read`
writes no file bytes to disk and sets no executable bit. A matching hash
proves a file is unchanged since the write, not that it is safe to run, and
the Standing rules section is the earlier session's claim until someone
checks it against each rule's source.

### The keep record

The keep record tells whatever removes instances what a brief still needs. It
is optional and has no fixed place: `write` and `resume` touch one only when
given a path, by `--keep-record <path>` or by `HANDOFF_KEEP_RECORD`, and the
argument wins over the environment. A workspace opts in by setting
`HANDOFF_KEEP_RECORD` once in its own configuration, for example to the file
its instance cleanup reads. A relative path resolves against `--instance`,
and is refused when there is no `--instance`. With no path, no record is
written anywhere, the brief's Files section is the one list, and a park
holds nothing outside koto.

The record is a JSON object. These are the fields the script owns:

```json
{
  "unit": {"instance": "<root>", "job_id": "<id>", "session_id": "<id>"},
  "written_by": "handoff-brief.sh",
  "written_at": "2026-11-22T15:30:00Z",
  "brief": {"koto_session": "<name>", "key": "brief/brief.md"},
  "files": [{"path": "<abs>", "sha256": "<hex>", "bytes": 123, "inline": true}],
  "protects": ["files", "transcript"],
  "resumed_at": null
}
```

`unit.instance` is the physical path of `--instance`, and each of the three
is `null` when absent. `written_at` equals the brief's `written_at` line.
`files` lists every named file by its absolute physical path, with `inline`
false for a by-reference file. `protects` is computed, never passed in:
`["instance", "files", "transcript"]` for `--event park` and for any event
that names a by-reference file, since that file must stay where it is, and
`["files", "transcript"]` for `end` or `stop` naming only inline files.
`write` sets `resumed_at` to `null`.

`write` reads an existing record at the path and replaces only those seven
fields, keeping every other field another tool put there. It writes the
result with jq to a temporary file in the record's own directory under
`umask 077`, sets it to mode 0600 and renames it over the record, so a reader
sees the old record or the new one and never a part. An existing record that
isn't one JSON object is refused and left byte for byte as it was. jq and
perl are needed only when a record path is given; without either on `PATH`
that call exits 2.

The record lock is a directory, `<record>.lock`, made with `mkdir` beside the
record (macOS has no `flock`). It holds one line, `<pid> <host>`, for the
call that holds it, and is removed when that `write` or `resume` ends. The
lock never exists without that line: the call makes `<record>.lock.new.<pid>`
under `umask 077`, writes the owner line into it, then renames it onto
`<record>.lock` with perl's `rename`, which fails when a lock is already
there (a BSD `mv` would move the directory inside the existing one instead).
A failed rename means the lock is held, and the temporary directory is
removed. A call
that finds the lock held never waits and never retries. A lock older than ten
minutes whose pid is gone on this host is stale: the call renames it aside,
checks that its owner line is still the one it judged stale, then removes it,
takes the lock and goes on. If another writer took the stale lock over first,
the owner line differs, so the call puts that writer's lock back and refuses
with exit 1. Any other lock (one younger than ten minutes, one whose
pid is still alive here, or one from another host, whose pid can't be checked
from here) refuses the call with exit 1, naming the lock's path, its pid and
its host. No `brief/` key is written and the record is unchanged. A lock
with no owner line (one this script didn't make, since it makes none) can't
be shown stale, so it is left for someone to remove by hand.

### Park and resume

`write --event park` writes a brief whose `event:` line reads `park`, and its
record (where a path is given) protects the instance. `resume` marks the
session as working again:

- It finds the koto session exactly as `write` does: `$KOTO_SESSION`, else
  `handoff-<job-id>`, else `handoff-<session-id>`, and refuses with no
  identity. A plain `handoff-` session that `write` closed `done` still takes
  the mark.
- It refuses, writing nothing, when the session has no `brief/brief.md` or
  its latest brief's `event:` isn't `park`. Only a park has a hold to void.
- It stores `brief/resumed`, holding the UTC time in the brief's format
  (`2026-11-22T16:05:00Z`), and prints `session=`, `key=brief/resumed` and
  `resumed_at=`.
- With a record path, the record must already be there. Under the same lock,
  `resume` sets `resumed_at` to that time and drops `instance` from
  `protects` unless the record's `files` names a by-reference file, and
  leaves `files` as written, since the named files stay named after the work
  resumes. If the record write fails, `resume` exits 2 and puts
  `brief/resumed` back as it was.

The record isn't deleted to void a hold: that would drop the named files.

### Who can read a brief

Read access follows the koto backend. Anyone who can read a session's backend
can read its brief and its inline files, and a name like `handoff-<job-id>`
is not a secret. A named file travels once named: a workspace that syncs
koto already chose whether anything leaves the host. The hashes catch a file
that changed after the brief was written, but they don't stop someone who
can write the backend, who could plant a brief and file keys whose hashes
agree. Backend write access is trusted, which holds for a koto backend one
principal owns; a backend shared between principals is out of scope. A
closed `handoff-` session stays on the backend until koto's retention removes
it, and whoever operates the backend can read its file bytes and owns
removing old sessions. Every argument, `--watch` included, shows in a process
listing while the script runs, so a watch carries no secret.

## Reading the size after a compaction

`scripts/context-size.sh <transcript.jsonl>` reports a session's own size from
its transcript, correct on the first read after a compaction. It takes the
transcript's path and reads nothing from the working directory, so it gives
the same report from an instance, a worktree or the workspace root. Its
output is line-oriented, so a session can send it to a supervisor as text:

```
context_tokens: 141822
boundaries: 2
boundary_turns: 361 742
window: 280000
hard_stop: 350000
```

- `context_tokens` is the input total (`input_tokens` plus
  `cache_read_input_tokens` plus `cache_creation_input_tokens`) of the newest
  assistant message after the latest `compact_boundary` record, or in the
  whole transcript when there is no boundary.
- `boundaries` counts the `compact_boundary` records, and `boundary_turns`
  gives the assistant turn at which each fell, the number of assistant turns
  before it, or `none`.
- `window` is `CLAUDE_CODE_AUTO_COMPACT_WINDOW` when that is a positive
  integer of at most nine digits, `invalid` when it is set to anything else,
  and `unset` when it isn't set. The reader prints the value as it finds it;
  an integer under Claude Code's 100,000 minimum still prints, though Claude
  Code won't use it.
- `hard_stop` is 1.25 times the window, rounded down, and is printed only
  when the window is an integer.

An assistant turn is one message id. Claude Code writes a record per content
block, so records sharing an id count as one turn, and the figure comes from
that id's last record. A sidechain record is never a turn or a boundary, and
a `<synthetic>` assistant record (written with no model call behind it) is
not a turn. A missing usage count reads as 0. A record whose counts aren't
whole numbers, or whose total reaches 10^15, gives no turn and no figure, so
the reader never prints a figure the thrash check would refuse; and a line that isn't a JSON object, such as a half-written
last line, is skipped.

The reader prints integers and the words above only, never transcript text
or a message id; its error lines name only the path it was given. It exits 0
with the report, 1 naming the path and cause with no figure (no single
argument, a missing path, a directory or anything else that isn't a regular
file, an unreadable or empty file, no assistant usage after the latest
boundary), and 2 when `jq` isn't on `PATH` or fails.

`scripts/thrash-check.sh [<report-file>]` reads that report, on stdin or from
a file, and never a transcript, so a supervisor on another host runs it on
what the session sent. It reports `status: cant_continue` and exits 1 when
three boundaries fall within 30 assistant turns (a `boundary_turns` entry and
the one two after it differ by 30 or less: `reason: thrash` with the three
turns), or when `context_tokens` is above `hard_stop` (`reason: hard_stop`
with both figures); both reasons print when both hold. Otherwise it prints
`status: continue` and exits 0. It parses integers only. It refuses a report
with exit 2 and no status, naming the cause but never a line's text (and the
line number, for a cause found on one line, or the `boundaries` and
`boundary_turns` lines when the count differs), when a line isn't of the form
`key: value`, a key is unknown, repeated or missing, a figure isn't a plain
whole number of at most fifteen digits, the `boundaries` count differs from
the turns listed, the turns are out of order, a `hard_stop` line doesn't
match whether the window is an integer, or the report is over 65,536 bytes
or holds a NUL byte. The size and the NUL test are taken on the bytes
received, before any line is read.

The values are the design's: three within 30 sits far from both the one
thrashing session on hand, which put three boundaries within 2 turns, and
the tightest healthy three-boundary span, 284 turns. Each role's hard stop is
1.25 times its window: workers 350K over a 280K window, coordinators 375K
over 300K.

## Switching roles on

No role switches compaction on by default until this identity read shows
the session id unchanged and the session live across a compaction. This read
did, for a background session running one koto-backed skill under the test
condition above. Each role's switch-on repeats the read for that role's own
launch.

# Handoff brief: compaction note and hooks

A session that compacts keeps running under its own id, but the summary
Claude Code writes can lose which skill it was running and where that skill's
koto run stands. The compaction note and its two hooks carry that back. Before
a compaction the session records what it is running; the `PreCompact` hook
asks the summary to name it; the `SessionStart` hook, matched on `compact`,
tells the session to re-read the skill and check koto before it does anything
else.

This reference covers the pieces that exist today: the note writer, the
ledger entry, the two hooks, how to install them, the window setting, the
results of one live compaction read against them, and the brief a session
hands forward when it stops, with the closing step before it, the brief's two
size limits, the opt-in keep record, park and resume.

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

Exit 0 means both writes landed, 1 that an argument was refused and nothing
was written, and 2 that koto or git is missing or a write failed. These are
the codes every `handoff-brief.sh` subcommand uses.

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
scratch:<path under the job's scratch directory><TAB>sha256:<hex><TAB>bytes:<n><TAB>inline:yes
instance:<path under --instance><TAB>sha256:<hex><TAB>bytes:<n><TAB>inline:no
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
- a line beginning `## ` in the reasoning or the standing rules, or a watch
  value holding a newline, since either could open a forged section;
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
isn't one JSON object is refused and left byte for byte as it was. jq is
needed only when a record path is given; without it on `PATH` that call
exits 2.

The record lock is a directory, `<record>.lock`, made with `mkdir` beside the
record (macOS has no `flock`). It holds one line, `<pid> <host>`, for the
call that holds it, and is removed when that `write` or `resume` ends. A call
that finds the lock held never waits and never retries. A lock older than ten
minutes whose pid is gone on this host is stale: the call removes it, takes
the lock and goes on. Any other lock (one younger than ten minutes, one whose
pid is still alive here, or one from another host, whose pid can't be checked
from here) refuses the call with exit 1, naming the lock's path, its pid and
its host. No `brief/` key is written and the record is unchanged. A lock
with no owner line can't be shown stale, so it is left for someone to remove
by hand.

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

## Switching roles on

No role switches compaction on by default until this identity read shows
the session id unchanged and the session live across a compaction. This read
did, for a background session running one koto-backed skill under the test
condition above. Each role's switch-on repeats the read for that role's own
launch.

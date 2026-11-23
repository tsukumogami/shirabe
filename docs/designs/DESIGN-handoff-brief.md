---
schema: design/v1
status: Planned
problem: |
  A session at its context line is replaced by a freshly dispatched one, and a
  session that stops leaves no readable reasoning and no record of which files
  matter. shirabe has no script that writes a handoff brief, no step that
  checks a worktree before one, no hook that shapes a compaction summary or
  sends a compacted session back to its run, and no context reader that reads
  right after a compaction. niwa can set a Claude Code setting only for a whole
  workspace or a repository, so it can't give workers a compaction window
  without giving one to coordinators too.
decision: |
  shirabe ships a brief script that stores the brief at `brief/brief.md` in the
  session's koto session, with each small named file at `brief/files/<sha256>`
  and two named limits (256 KiB inline, 2 MiB per brief); a closing-step
  script; a compaction note at `compaction/note.md`; two hook commands in the
  shirabe binary, `shirabe compaction pre-compact` and `shirabe compaction
  re-anchor`, that a workspace installs as instance hooks; a context reader
  that also reports compaction boundaries and the window in force; and a
  thrash check that reads only that report. niwa gains one generic value on its
  planned dispatch profiles, `auto_compact_window`, and a workspace default
  profile for a dispatch that names none. The worker window rides the default
  profile and coordinators are dispatched under a profile that sets no window.
rationale: |
  A session's role is fixed at dispatch, so the window is set there, in the
  launch settings niwa already owns, and never in a file every session in an
  instance reads. niwa learns a number it renders into one Claude Code setting
  and knows nothing about shirabe. shirabe's scripts and hooks call no niwa
  command and read no niwa file, and a session without niwa sets the same
  setting in its own settings. Hook commands in the shirabe binary have a path
  that doesn't change between plugin versions, which a workspace hook needs.
  Each role's window stays at the size it stops at today, so a switched-on
  role costs no more per turn, and the stop moves to a hard stop above the
  window as the fallback.
upstream: docs/prds/PRD-handoff-brief.md
decision_provenance: inline-resolved
---

# DESIGN: Handoff brief

## Status

Planned

## Context and Problem Statement

A session in one of shirabe's workflows runs until its context reaches a line,
then stops. Today a supervisor dispatches a successor in a new instance: new
clones, a new transcript, a cold build, and a read-in of state the stopped
session already had. Claude Code can instead compact the session in place,
keeping its id, instance, worktree, warm build and workflow run. Workers have
finished whole units that way, compacting from about 247K tokens to 72K-80K
several times each. The PRD makes that the default for every role, switched on
per role (workers first, coordinators once their workflow re-anchors and a
superseding decision exists, supervising sessions last), and keeps a
dispatched successor only for a session that can't continue or for a change
compaction can't carry.

When a session does stop, three readers need to know what it did and what it
left: the session that picks the work up, its supervisor, and the remover that
later decides whether the instance can go. Current models return their
thinking as an encrypted signature, so the transcript holds almost no
readable reasoning, and nothing records which scratch files matter. The PRD
asks for one handoff brief: plain-text reasoning, pointers to the run, branch,
pull request and pushed head, and the files the session names, each with a
hash, written as a key in the session's koto session so it travels wherever
that session goes.

The technical work falls in four places.

**The brief and its record (R1-R9).** shirabe needs a script any session can
call. It refuses empty reasoning and any named path that isn't a readable
regular file. It hashes each named file from disk, stores a small file inside
the brief and names a larger one by reference, enforces two named limits, and,
where a workspace gives it a record path, writes the keep record's file list
once, with a hold computed from the event. A park holds the instance until a resume mark
voids the hold; a file named by reference holds it until the kept set exists.
A closing step runs before the brief at a run's end and blocks on a stray file
or an unpushed commit.

**Compaction in place (R10-R18).** A compaction note is a koto key the session
keeps current; it names no files and writes no record. A PreCompact hook asks
the summary to name the koto session, branch, pull request and note key and to
keep verbatim owner words, ids and hashes, and says when the note is stale. A
SessionStart hook matched on `compact` sends the session back to its run, its
note, `koto status` and its record before it acts. A context reader reports
the session's size correctly on the first read after a compaction, from an
instance or the workspace root, with the count and turn of each compaction
boundary.

**A window per role (R13, R14).** Each role compacts at the size it stops at
today: about 280K for workers and 300K for coordinators. Supervising sessions
get theirs once their post-compaction size is measured. Each value must leave
at least 100K tokens after compaction and keep the post-compaction size at no
more than 60% of the window. Claude Code reads the window from the
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` setting, in a settings file's `env` block or
the process environment, and that value beats any other compaction control.
niwa can carry it today only through `[claude.env]`, which writes every
instance's settings workspace-wide or per repository. Its dispatch-time
environment passthrough refuses names that start with `CLAUDE_`, and the
launch settings it sends never set them. Coordinators run in their own
instances, so a workspace-wide window would switch them on with workers,
before the decision they wait on. A role is fixed when a session is
dispatched, so the window has to follow the dispatch.

**Who stops anyway (R19-R21).** A supervising session writes what a person
tells it to its record on arrival, and re-reads and re-arms after each
compaction. A session can't continue when it thrashes (three compaction
boundaries within 30 assistant turns), passes its hard stop, loses its
instance or host, is blocked, or no longer has the authority the work needs.
It is deliberately replaced to pick up a new shirabe release or a changed
authority.

The work must not tie niwa and shirabe together in either direction. niwa's
change is a generic dispatch setting that knows nothing about shirabe.
shirabe's scripts, hooks and reader call no niwa command and read no niwa
file. The window is a plain Claude Code setting a session without niwa can set
itself. The two meet only in a workspace configuration that opts in, and that
configuration works when both are present.

### What the coordinator compaction history says

No coordinator has compacted at a chosen window. The record on hand is 28
automatic coordinator compactions near the model's own limit of about 967K,
on this workspace's coordinators. They came back at 56K-90K on the first turn
after, of which 10K-33K was the summary and the rest the harness floor. They
reached 70K-116K after 30 turns and 112K-169K after 100, once they had
re-read their state. They ran 914-1,924 turns between compactions, each taking
35-150 seconds. So the 110K-170K "read-in floor" is a paper figure: the size a
coordinator reaches once its read-in is done, measured only after compactions
from far above any window this design sets. At a 300K window that floor sits
at 37%-57% of the window, inside the margin rule with 130K to spare at worst.
A first measured coordinator compaction at 300K that settles above 180K breaks
the rule, and Decision 4 says what happens then.

## Decision Drivers

- **No dependency between niwa and shirabe.** Neither side calls, reads or
  names the other in code. niwa's change must make sense to a workspace that
  has never heard of shirabe, and shirabe's pieces must work in a session that
  has never run niwa.
- **The window follows the dispatch.** A session's role is fixed when it is
  dispatched, so the window is chosen there. Setting one role's window never
  sets one for another role, or for a person's own session in the same
  instance.
- **Off unless set.** shirabe documents the window and ships the hooks; it
  switches nothing on in a workspace by itself (R14). A fresh workspace that
  sets nothing gets no window and no hook from this work.
- **Today's cost per turn.** Each role compacts at the size it stops at today,
  and keeps a hard stop above the window as the fallback for a compaction that
  doesn't fire (R13).
- **Nothing lost silently.** The brief script refuses rather than drops: a bad
  path, a limit exceeded or empty reasoning writes nothing, and an existing
  keep record stays byte-identical (R2-R4).
- **One list of files.** Where a keep record is written it holds the file
  list and the brief renders its list from it; with no record, the brief's
  own list is the only one (R5).
- **Data, not instructions.** A brief read by a successor or a supervising
  session is a predecessor's claim, never instructions in force.
- **Bounded hooks.** The hooks never block a compaction and stay under the
  10,000-character field cap (R16, R17).
- **Buildable in order.** The brief half ships with no niwa change and waits on
  nothing; the compaction half waits first on one read of a session's identity
  across a compaction (R12).

## Considered Options

All five questions were resolved inline, under the scoping run that invoked
this design.

### Decision 1: Where the brief, its files and the resume mark live, and what the keep record holds

Resolved inline.

The PRD puts the brief in the calling session's koto session (R1) and lets a
small named file travel inside it (R4). It leaves to this design the key
layout, the two limit values, the resume mark's name, whether a no-run
session's koto session ever ends, and the record's field shapes.

Key assumptions: koto context values hold arbitrary bytes, and nothing caps
one below the backend's 16 MiB state read. A finished koto session's keys stay
readable.

#### Chosen: keys under `brief/`, files keyed by hash, 256 KiB and 2 MiB

The brief is `brief/brief.md`. Each named file at or below the inline size of
262,144 bytes (256 KiB) is stored at `brief/files/<sha256>`, holding its exact
bytes; a larger file is named by reference only. The record cap is 2,097,152
bytes (2 MiB) over every file one brief names, by reference included. The
resume mark is `brief/resumed`, holding the UTC time the session started
working again after a park.

A prefix still earns its place. It groups the brief's keys, so a reader lists
them with one prefix and the record's `brief` pointer names a key inside a
known namespace. It also keeps them apart from a workflow's own keys. `brief/`
says what the keys are and avoids `handoff/`, which /scope already uses for
`handoff/scope.md`. Keying a file by its hash makes the key fixed-length and
safe whatever the path holds, gives two names for one content one key, and
lets a reader check the bytes against the record without trusting the path.

256 KiB holds every kind of scratch the PRD names (a draft comment, a helper
script, review panel output) and sits under shirabe's 1 MiB `put` limit.
2 MiB is over three hundred times the largest hand-written continuation note
seen, which sat near 6 KiB, and stays far under the backend's limit.

With no koto run, the script opens a plain koto session named
`handoff-<job-id>`, writes the brief there, prints its name and key, and closes
it `done`. A person's own foreground session has no job id, so it falls back
to `handoff-<session-id>`, from the Claude session id. A closed koto session
still answers `koto context get`, so the keys stay readable after the close.
The id makes the name unique, so no later open replaces it.

The keep record is optional and has no fixed place. The script writes one
only when it is given a record path, by `--keep-record <path>` or by the
`HANDOFF_KEEP_RECORD` environment value, with the argument winning. A
relative path resolves against `--instance`, so a workspace that wants the
record sets the value once in its own configuration (for example to the file
its instance cleanup reads) and every session in it writes there. With no
path, the script writes the brief and its file keys only, the brief's Files
section is the one list, and a park holds nothing outside koto. shirabe's
code names no directory that belongs to another tool. The record is a plain
JSON file the reference documents, which removal work may read wherever the
workspace points it.

The instance is recognized without asking any tool. `--instance <root>` is
optional; when given, it must be an existing directory that the current
directory resolves inside, and must not itself sit inside a git worktree
(`git -C <root> rev-parse --is-inside-work-tree` fails), so it is the
directory above the session's repositories. Scratch is the job's scratch
directory plus, when `--instance` is given, loose files at that root outside
any repository. A relative record path with no `--instance` is refused.

Where a path is given, the record is written as the earlier design had it.
`handoff-brief.sh` reads any existing record at that path and replaces only
its own fields (`unit`, `written_by`, `written_at`, `brief`, `files`,
`protects`, `resumed_at`). It writes the result to a temporary file in the
record's own directory under `umask 077` and renames it over the record,
guarded by a `mkdir` lock beside it (macOS has no `flock`), which a later
writer treats as stale after ten minutes. `protects` is
computed, never passed in: `["instance", "files", "transcript"]` for a park,
or whenever a named file is by reference; `["files", "transcript"]` for a
run's end or a stop that names only inline files. `written_at` is taken before
any file is hashed, so a file changed during the write reads as newer than
the brief. `handoff-brief.sh resume` writes `brief/resumed`; where a record
path is given it also sets `resumed_at`, drops `instance` from `protects`
unless a named file is by reference, and leaves `files` as written (R7).

#### Alternatives Considered

- **No prefix.** Rejected: the brief's keys would mix with a workflow's own,
  and nothing would list them as a group.
- **`handover/`.** The earlier design's choice. Rejected: its reason was a
  successor route carrying that prefix forward, which is no longer part of
  this work, and the name now reads as that route.
- **`handoff/`.** Rejected: /scope already writes `handoff/scope.md`, and a
  brief written inside a scope session would share its namespace.
- **One JSON key with files base64-encoded inside.** Rejected: it grows content
  by a third, one bad file corrupts the whole brief, and a reader can't check
  one file without parsing all of them.
- **A brief file in the instance.** Rejected: R1 forbids it, and it can't move
  hosts.
- **Voiding a park's hold by deleting the record.** Rejected: it would drop
  the named files, which stay named after resumed work (R7).
- **A fixed record path inside the workspace manager's directory.** The
  earlier design's choice. Rejected: the script would read and write a file
  in another tool's directory, in a format that tool owns, which ties the two
  together. A workspace that wants the record there names that path in its
  own configuration.
- **Recognizing the instance by a workspace manager's marker directory.**
  Rejected for the same reason; the caller names the root, and the script
  checks only that it encloses the current directory and sits above the
  repositories.

### Decision 2: What carries each role's window

Resolved inline.

The window has to reach a session at launch, set for its role and no other,
through something niwa owns and shirabe never touches.

Key assumptions: niwa's dispatch-profile design (Planned on niwa main, its
plan written, nothing implemented) lands roughly as written. That means a
`[session.dispatch_profiles.<name>]` table read only at dispatch, a new
contributor to the launch `--settings` document that already carries one env
entry, the profile's name kept on the launch record and re-checked by
`niwa resume` and `niwa retask`, and a profiled launch's env values stripped
from any launch it makes without the profile. `--settings` outranks project
and local settings. `CLAUDE_CODE_AUTO_COMPACT_WINDOW` in a launch settings
`env` block reaches a `--bg` session at launch.

#### Chosen: a window value on niwa's dispatch profiles, with a workspace default profile

niwa's profile table gains one key, `auto_compact_window`, an integer token
count. For Claude it renders as `CLAUDE_CODE_AUTO_COMPACT_WINDOW` in the
launch settings `env` block only, not as a separate process variable, since
the settings value already outranks the shell's. Claude Code also hands a
settings `env` value to the commands a session runs, which is why every
dispatch drops an inherited window (below); Phase 1 checks that the reader
sees the value there. Its name joins the list of env names a profile may set.

Settings precedence decides the rest. Managed settings come first, then the
launch `--settings` document, then the project's local and shared settings,
then the user's. A window in `[claude.env]` would reach every session a
profile leaves without one, coordinators included. So config load refuses
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` in `[claude.env]` and `[repos.*.claude.env]`
whenever a dispatch profile sets `auto_compact_window`, as it already refuses
the name in `[session.dispatch_env]`. A profile that sets only a
window is valid, so the load check becomes "at least one drop or setting".

The profile design's strip rule keys on niwa's profile marker, so it can't
see a window exported in someone's shell, or one a session's settings handed
to its commands. So the window gets a simpler rule of its own: every
dispatch, profiled or not, drops an inherited
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` from the environment it starts from, and
sets the window only from the profile it resolved to. A coordinator never
inherits a worker's window, and a worker dispatched by a worker gets its own
from the default. The one behavior that changes for a workspace with no
profiles at all is that a window exported in the dispatching shell no longer
reaches the session; the guide says the profile is the place to set it. `[session]` gains `default_dispatch_profile`,
which applies to a dispatch that names no profile. The launch record stores
the profile name it resolved to. A profile named on the command line wins.

A workspace then turns workers on with three lines and keeps coordinators off
with one more:

```toml
[session]
default_dispatch_profile = "worker"

[session.dispatch_profiles.worker]
auto_compact_window = 280000

[session.dispatch_profiles.coordinator]
# the profile's own drops; no window until coordinators switch on
```

Every worker dispatched with no `--profile` takes the worker window, so
shirabe's coordinate skill keeps dispatching workers exactly as it does now
and passes nothing new. Coordinators are dispatched with `--profile
coordinator`, which niwa's dispatch-profile plan already requires of every
coordinator dispatch for its own reasons. Switching coordinators on later is
`auto_compact_window = 300000` in that profile.

**How this sequences against the dispatch profile.** The window builds on
the dispatch-profile plan; it doesn't wait for all of it, and it isn't folded
into it. The niwa change is its own pull request, opened once that plan's
config table, launch contributor and resume acceptance are on niwa main. It
doesn't wait on the plan's last step, the coordinator's dispatcher passing
the flag. Meanwhile the shirabe pieces ship, since none of them needs a
window: the brief script, the closing step, the hooks, the reader and the
thrash check. The identity read that gates every switch-on (R12) launches a
background session by hand with the window in a `--settings` document, the
same carrier niwa will use, so it tests this choice before any niwa code.
Worker switch-on waits on more than the window. niwa has no profile code
today: the dispatch-profile design is Planned and nothing of it is built. So
workers switch on only after that plan's first four steps land, then the
window pull request, then a niwa release carrying both. Shipping the shirabe
pieces doesn't switch anyone on.

**How a coordinator dispatched without its profile is caught.** This is the
one way the choice goes wrong: a coordinator dispatched with no `--profile`
takes the default profile and the worker window. Four things catch it. The
dispatch-profile plan already makes every coordinator dispatch name its
profile, so the same line that would forget the window would also forget the
trim the plan exists for. niwa's audit line after a launch, and `niwa list`,
name the profile each session runs under. The context reader prints the
window in force from the session's own environment, and coordinate's start
prints it with its reconcile, so a coordinator under a window says so before
it acts. The R14 test dispatches a coordinator under its profile from the
worker configuration and checks it carries no window, including when the
dispatching shell has the window exported.

**What R14's apply-time wording means under this carrier.** R14 says niwa
carries the window and the hooks into each instance's settings when it
applies the configuration, and its criterion speaks of an instance applied
from the configuration and of a switch-on reaching an instance at niwa's next
apply. The hooks still arrive that way. The window arrives at dispatch, in the
launch settings, so the criterion reads:

- A worker session dispatched from the configuration carries the window in
  its launch settings, and the instance settings carry both hooks next to
  niwa's own compact-matched hooks.
- A coordinator dispatched under its profile from the same configuration
  carries no window, in its launch settings or its instance settings.
- A switch-on reaches the next session dispatched, never one already
  running.

A running session keeps the window it launched with until it is dispatched
again. With compaction on by default, `niwa retask` is how a worker gets its
next task, so refusing a retask whenever the default profile's window changed
would leave every live worker unreachable. `niwa resume` and `niwa retask`
therefore carry the window recorded on the launch record, as they carry the
model, and accept it even when the profile's value has changed since. They
refuse only an explicit attempt to change it on the resume or retask itself.
Every other profile key keeps the dispatch-profile design's re-check. A
changed window reaches a role's sessions as each is next dispatched.

#### Alternatives Considered

- **The worker window through `[claude.env]`, with a coordinator profile
  setting a window high enough never to fire.** This needs no niwa change for
  workers. Rejected: it writes the window into every instance's settings,
  coordinators' included, so it can't meet R14's criterion that a coordinator
  instance carries none, and an override that fails to apply leaves a
  coordinator at the worker window with nothing recorded. It also hands the
  window to people's own sessions in every instance, which the dispatch-profile
  design rules out for its own change.
- **Coordinate passes `--profile worker` when it dispatches.** Rejected: shirabe
  would start depending on a niwa feature it doesn't use today. With a
  workspace default, shirabe passes nothing.
- **niwa's dispatch-time environment passthrough.** Rejected: it refuses names
  that start with `CLAUDE_`, for good reason, and a passthrough copies the
  dispatcher's own value, so a coordinator would hand its window down.
- **Writing instance settings after dispatch.** Rejected: it races the
  session's start, and it reaches every session in the instance.
- **A launch-env key of its own, apart from profiles.** Rejected: it would be a
  second per-dispatch channel beside the one niwa has already designed, with
  its own resume and strip rules to keep in step.

### Decision 3: The compaction note, the two hooks and the staleness inputs

Resolved inline.

The PRD fixes what the note is (R10), what the PreCompact output asks for
(R15), the re-anchor's content and carrier (R16), and when the note counts as
stale (R17). The design picks the key, the hooks' shape and how a workspace
installs them.

Key assumptions: the shirabe binary is on the path wherever shirabe's skills
run. `koto context history` returns a seq and a timestamp for each write of a
key.

#### Chosen: `compaction/note.md`, and two hook commands in the shirabe binary

The note is `compaction/note.md` in the session's koto session, written by
`handoff-brief.sh note`. That runs the same token scan `write` runs, names no
files, writes no record and touches no scratch. A separate prefix keeps the
note from ever being read as part of a brief.

`note` also writes the session's ledger entry, so a hook can find its way
back from the session id Claude Code hands it:

- **Where.** `$XDG_STATE_HOME/shirabe/compaction/<session-id>` (or under
  `$HOME/.local/state`), in a 0700 directory, as a 0600 file opened without
  following links. The runtime directory `shirabe work-summary` prefers is
  wiped at a reboot or logout, which a long session can outlive, so this
  ledger doesn't use it.
- **What.** One `key: value` line each for the koto session, the note key,
  the branch, the repository top-level `note` ran in (left out when it isn't
  run in a work tree) and the pull request. The hook reads the branch's
  commits with `git -C` in that repository when it is still a work tree that
  isn't a symlink, and falls back to its own working directory otherwise.
  Then one `skill:` line per active skill, outermost first, each with the
  arguments it was invoked with and the path of its `SKILL.md` under the
  plugin root the session started on. For example, `skill: shirabe:deliver
  handoff-brief --no-merge <root>/skills/deliver/SKILL.md`, then the same for
  `shirabe:scope`. The session passes the skill lines; `note` checks each
  path exists under one plugin root.
- **Trust.** A hook accepts an entry only when its koto session matches
  `KOTO_SESSION` where that is set, and every field passes its grammar.
- **Cleanup.** Each `note` replaces its own entry, and removes entries older
  than 30 days.

**Why the skills are named.** A session on a workflow (deliver, scope,
coordinate) got its skill's instructions through the Skill tool. After a
compaction it has only what the summary kept of them, and `koto status` tells
it where the run stands but not the skill's own rules. So the re-anchor asks
the session to re-read each recorded `SKILL.md` by path before it runs `koto
status`. Each of these skills resumes from its koto session (its `open`
attaches to the live session), so re-reading lands on its resume path, not a
fresh run. A path rather than the Skill tool for two reasons. niwa's planned
coordinator profile denies the Skill tool, so a profiled coordinator could
never re-invoke its entry skill but can still read a file. And reading the
recorded path keeps the session on the plugin version it started with, so
picking up a new release stays a deliberate succession (R21). Phase 1 also
checks whether an invoked skill's text survives a compaction at all, which
says whether this reload is required or a safety net.

The hooks are two subcommands of the shirabe binary, in the same shape as the
existing `shirabe work-summary compact` SessionStart hook:

- `shirabe compaction pre-compact` reads the hook input for the session id,
  looks up the koto session and note key, and prints the summary instruction.
  The summary names the koto session, branch, pull request and note key, and
  keeps verbatim any owner words, ids and hashes still in play. It judges the
  note stale when the koto session's latest event seq is later than the seq of
  the note's last write, or the branch's newest commit time is later than that
  write's timestamp. A stale note gets one more line: the note is stale, and
  rewriting it is the first step after the compaction. Branch and pull
  request come from the ledger entry, which `note` filled at its last write;
  the hook makes no `gh` call. With no entry, it says no note is recorded and
  names the branch from `git` in the hook's working directory. The summary
  instruction also carries the re-anchor's skill paths, so the summary holds
  the way back even if the SessionStart output doesn't arrive. It exits 0 on
  every path and never blocks.
- `shirabe compaction re-anchor`, run as a SessionStart hook matched on
  `compact`, prints a short block as `additionalContext`. It lists the
  recorded `SKILL.md` paths to re-read, outermost first. It names the
  innermost koto session and says to run `koto status` on it, and names the
  note key and the record to re-read before acting. It stays under 10,000
  characters and never inlines the note or a skill. With no ledger entry, it
  prints a generic line. That line says to work out the skill from the koto
  session's name prefix (`deliver-`, `scope-`, `coordinate-`) and re-read its
  `SKILL.md`, to run `koto status` in your worktree, and to read the note with
  `handoff-brief.sh read --note`.

A workspace installs both as instance hooks (`[claude.hooks] pre_compact`, and
`session_start` with matcher `compact`). Each is a short script that runs the
subcommand by the binary's absolute path, resolved when the workspace writes
the hook rather than looked up on `PATH` at every compaction, and exits 0
silently if that binary is gone. Both hooks check the session id from their
input, and the koto session and note key read from the ledger, against their
grammars before using them. The pre-compact hook runs its `git` calls with
`-c core.fsmonitor=false`, `-c core.hooksPath=/dev/null` and
`-c log.showSignature=false`, and with `GIT_NO_LAZY_FETCH=1` and an empty `GIT_ALLOW_PROTOCOL` set. niwa writes them into instance settings at apply with no niwa
change, beside its own compact-matched hooks. Without niwa, a person adds the
same two entries to their own settings. A binary subcommand keeps the hook's
path the same across plugin versions, which a script inside the versioned
plugin cache can't do.

#### Alternatives Considered

- **Registering the hooks in the plugin's own `hooks.json`.** Rejected: every
  session with the plugin would get them, which is shirabe switching something
  on by itself (R14).
- **A workspace hook that calls a script inside the plugin.** Rejected: the
  plugin's install path changes with each version.
- **PostCompact for the re-anchor.** Rejected: its output is discarded (R16).
- **Blocking a compaction on a stale note.** Rejected as the PRD does: the
  block is invisible to the model and can't tell a window compaction from a
  recovery at the hard limit (R17).
- **The note under `brief/`.** Rejected: R10 keeps the note and the brief
  apart, and a shared prefix invites a reader to treat one as the other.

### Decision 4: The context reader, the thrash check, and each role's window and hard stop

Resolved inline.

R18 asks for a reader any session can call that reads right after a
compaction, from an instance or the root, and reports boundaries. R20 asks for
a thrash test from what the session reports, with values the design checks
against transcripts. R13 leaves each later role's hard stop to the design.

Key assumptions: the usage figure the reader sums agrees with the size Claude
Code compares with its window within a few K.

#### Chosen: `context-size.sh` and `thrash-check.sh` in shirabe, three in 30, stops at 1.25 times the window

`scripts/context-size.sh <transcript>` prints:

- the input total (input plus both cache counts) of the newest assistant
  message after the latest `compact_boundary` record, counting each message
  id once;
- the number of boundaries and the assistant turn at which each fell;
- the window in force, from `CLAUDE_CODE_AUTO_COMPACT_WINDOW` when it is set
  to an integer, and `invalid` when it is set to anything else.

It reads only usage integers and record types, and prints no transcript
text. It works from any directory, including the workspace root, since it
takes the transcript path. With an empty or missing transcript it exits
non-zero naming it.

`scripts/thrash-check.sh` reads that report, never a transcript, and reports
"can't continue" when three boundaries fall within 30 assistant turns. A
supervisor on another host runs it on what the session sent.

The values hold against the transcripts on hand. On this workspace's host,
82 transcripts carry at least one boundary and 32 carry a gap between two.
The one thrashing session put three boundaries within 2 turns. The tightest
healthy three-boundary span was 284 turns, and the median gap was 598 turns.
The workers measured at about 247K ran 347-408 turns between compactions, and
coordinators at the model's limit 914-1,924. Three within 30 sits far from
both. A tighter count catches nothing more, and a looser one would start to
reach a slow refill without separating it any better. v1 keeps the PRD's
values.

Windows stay at each role's line: workers 280K and coordinators 300K. Each
supervising session takes its line once its post-compaction size is measured.
Each role's hard stop is 1.25 times its window: workers 350K, the stop that
applies today only in a unit's closing stretch; coordinators 375K; supervising sessions 1.25 times their
window. 75K over a coordinator's window is above the 20K-50K that one large
step adds (a test run, a large read, verifying a pushed pull request), so a
single step can't carry a session from under its window past its stop before
the compaction it was owed.

Checked against the margin rule, with P as the largest measured
post-compaction size:

| Role | Window | Hard stop | P | Window minus P | P as share of window |
|---|---|---|---|---|---|
| Worker | 280K | 350K | 80K | 200K | 29% |
| Coordinator | 300K | 375K | 170K (paper) | 130K | 57% |
| Supervising | its line | 1.25 times the window | not measured | checked before switch-on | checked before switch-on |

If a role's first measured P breaks the rule (for coordinators, anything above
180K), its window is set again before it switches on. The new window is the
largest of its line, P plus 100K and P divided by 0.6, rounded up to the next
10K, and its hard stop moves to 1.25 times that. A role whose P grows past the
rule after switch-on gets the same reset, and its cost per turn changes with
it; the design records that as a change to that role's cost.

#### Alternatives Considered

- **Keeping a reader at a supervising session's own path.** Rejected: that
  reader reads one message behind after a compaction, and a compacting session
  outlives the path it sits at.
- **A fixed 70K between window and hard stop for every role.** Rejected: it
  holds for workers but shrinks relative to larger windows, where one step is
  the same size.
- **Three boundaries within 60 turns.** Rejected: no transcript on hand falls
  between 30 and 60, so the change buys nothing.

### Decision 5: The closing step and one brief format

Resolved inline.

R9 orders the closing step before the brief; R22 forbids a second format.

Key assumption: placement inside a work-on run stays held while the design for
#1230 is in progress (R24).

#### Chosen: a separate closing-step script and four fixed sections

`scripts/closing-step.sh <worktree>` fails, naming the cause, when `git status
--porcelain --untracked-files=all` shows an untracked file that `git
check-ignore` doesn't match, or when the branch has no upstream or `git
rev-list @{u}..HEAD` is non-empty. On a pass it prints the instance root for
the caller to move to (the `--instance` it was given, or else the directory
that holds the worktree's repository), never deletes the worktree, and checks that the
caller's working directory is outside it before it reports done. Every git call
runs with `-c core.fsmonitor=false` and `-c core.hooksPath=/dev/null`.

The brief has four fixed sections: Reasoning, Pointers, Files and Standing
rules. Standing rules is a slot other work fills; this work writes `None
stated.` unless given a rules file. Every role writes the same brief. Workers
adopt it first, then coordinate's handover writes its successor text as the
Reasoning of a brief through the same script, then supervising sessions.

#### Alternatives Considered

- **Folding the closing step into the brief script.** Rejected: R9 orders them
  as two steps, and the brief script must work with no worktree at all.
- **A separate supervising-session format.** Rejected: it would be the second
  format R22 forbids.

## Decision Outcome

The five decisions make one path for each event. At a run's end the closing
step passes, `handoff-brief.sh write` hashes the named files, refuses on any
limit or bad path, stores the brief and small files under `brief/`, and,
where the workspace gave a record path, writes the keep record's one file
list with the hold computed from the event.
A park writes a hold, and `resume` writes `brief/resumed` and voids it. A
session at its window has already kept `compaction/note.md` current. The
PreCompact hook shapes the summary and flags a stale note, and the
compact-matched re-anchor sends the session to re-read its skills, then to
`koto status`, its note and
its record. The window reaches the session at dispatch, from a niwa profile
value that knows only a number. The reader and the thrash check tell the
session and its supervisor when compaction stopped helping, and the hard stop
catches a compaction that never fired. Each of those ends in a brief and
today's successor route.

## Solution Architecture

### Overview

| Component | Where | Job |
|---|---|---|
| Brief script | shirabe `scripts/handoff-brief.sh` | `write`, `resume`, `read`, `note` |
| Closing step | shirabe `scripts/closing-step.sh` | stray and push checks before the brief |
| Context reader | shirabe `scripts/context-size.sh` | size after the latest boundary, boundaries and turns, window in force |
| Thrash check | shirabe `scripts/thrash-check.sh` | can't continue, from the reader's report |
| Compaction hooks | shirabe binary `shirabe compaction pre-compact`, `shirabe compaction re-anchor` | summary instruction and stale flag; re-anchor line |
| Window value | niwa `[session.dispatch_profiles.<name>] auto_compact_window`, `[session] default_dispatch_profile` | the window in a dispatched session's launch settings |
| Reference | shirabe `references/handoff-brief.md` | limits, format, the keep record's format and how a workspace opts into it, the window setting, installing the hooks, setting the window without niwa |

shirabe's code names no niwa command or file, and niwa's change names no
shirabe concept. koto's code doesn't change, though koto's sync and retention
now carry named file bytes (Security Considerations).

### Components

**`handoff-brief.sh write`** takes `--reasoning <file>`, repeated `--file
<path>`, `--event end|park|stop`, and optional `--instance <root>`,
`--keep-record <path>` (or `HANDOFF_KEEP_RECORD`), `--watch "<label>=<re-arm
command>"` and `--standing-rules <file>`. Pointers
are read, not passed:

- the koto session: `KOTO_SESSION` when set, otherwise a new plain session
  `handoff-<job-id>`, or `handoff-<session-id>` when there is no job id;
- the current branch;
- the open pull request, from `gh pr view`;
- the remote branch's commit, from `git ls-remote` by remote name, never by
  URL.

The job id is the base name of the harness's job directory, and the session
id is the `sessionId` in that job's state file. Either is null when absent;
with no koto run and both null, `write` refuses (exit 1), since it can't name
a session. A session name must match koto's grammar before it names a
session. Every `git` call runs with `-c core.fsmonitor=false` and `-c
core.hooksPath=/dev/null`; `gh` still runs under the repository's own
configuration, which the reference says.

It refuses, writing nothing:

- empty reasoning once whitespace is trimmed;
- an `--instance` that doesn't exist, doesn't enclose the current directory,
  or sits inside a git worktree (Decision 1);
- a relative record path with no `--instance`, or a record path whose
  directory doesn't exist or is a symlink;
- a named path that isn't a regular file, has a symlink in it, has a link
  count above 1, or is missing or unreadable;
- a path outside scratch, which leaves out every repo worktree and any
  dot-directory at the instance root (`.git/`, `.claude/` and the like);
- a basename matching a credential pattern (`.env*`, `*.pem`, `*.key`,
  `*.p12`, `id_*`, `.netrc`, `.npmrc`, `.git-credentials`, `credentials*`,
  `settings*.json`, `*secret*`, `*token*`, among others the reference lists);
- a content hit in the files, the reasoning, the standing rules or the watch
  strings: token shapes (`gh[pousr]_`, `github_pat_`, `sk-ant-`, `AKIA`,
  `xox[abprs]-` and the rest), PEM and OpenSSH key blocks, JWT-shaped strings,
  bearer headers, `user:secret@` URLs, cloud key JSON, and runs of
  `KEY=VALUE` lines;
- a control or Unicode format character, or a tab, in a path or a watch
  value;
- a shell operator in a watch value;
- a rendered brief over the inline size;
- a total over the record cap.

The `--reasoning` and `--standing-rules` files pass the same path checks as a
named file: a regular file with no symlink, link count 1, inside scratch or
the job directory, and no credential basename. A transcript is never named,
by its `*.jsonl` name or by a first line that parses as a transcript record.
The record lock is a `mkdir` directory holding the owner's pid and host; a
later writer takes over a lock older than ten minutes only when that pid is
gone on that host. Each file is copied once into a private 0700
directory, and size, hash and stored bytes come from that copy. The script
stores the file keys, then `brief/brief.md`, then the record where a path is
given, so a record never
points at a brief that isn't there. If a later store fails, it removes the
keys this call stored.

**`resume [--instance <root>] [--keep-record <path>]`** is Decision 1's mark. **`read [--session
<name>]`** prints a brief with its Files section after the free text,
verifies each inline key's hash, marks control and format characters, and
prints watch commands as data without running them. It fences the reasoning
between delimiters made fresh for each call, so text inside can't close the
fence. It prints file bytes to its output only, never writes them to disk,
and never sets an executable bit. A matching hash proves a file is
unchanged, not that it is safe to run. `read --note` prints the compaction
note the same way. **`note --reasoning <file>`** is Decision 3's note, with
repeated `--skill "<name> <args> <SKILL.md path>"`.

**`closing-step.sh`** prints `closing=pass` and the instance root with exit 0,
or `closing=blocked` with one line per cause and exit 1; exit 2 is an
environment fault.

**`context-size.sh`** and **`thrash-check.sh`** are Decision 4. The reader's
output is line-oriented so a session can send it to a supervisor as text:

```
context_tokens: 141822
boundaries: 2
boundary_turns: 361 742
window: 280000
hard_stop: 350000
```

`hard_stop` is 1.25 times the window, printed only when the window is.
`thrash-check.sh` reports "can't continue" on either case: three boundaries
within 30 turns, or `context_tokens` above `hard_stop`.

**`shirabe compaction pre-compact` and `re-anchor`** are Decision 3. Both read
the hook input only for its session id and exit 0 on every path.

**niwa's profile value.** `auto_compact_window` is an integer in
100,000-1,000,000. Config load refuses anything else, refuses the
`CLAUDE_CODE_AUTO_COMPACT_WINDOW` name in `[session.dispatch_env]` (a profile
owns it), and refuses a `default_dispatch_profile` that names no declared
profile. The launch contributor renders the value as a string in the `env`
block. Every dispatch drops an inherited value of that name first. Resume and
retask carry the recorded value and refuse only an explicit change to it on
the command itself. niwa's guide documents the key as a Claude Code
compaction window, with no reference to any workflow tool.

### Key Interfaces

The brief key, `brief/brief.md`:

```markdown
# Handoff brief
written_at: 2026-11-21T04:30:00Z
event: end
## Reasoning
<concluded, ruled out and why, next step>
## Pointers
koto_session: <name>
branch: <name>   pull_request: <number>   pushed_head: <sha>
watch: <label> = <re-arm command>
## Files
scratch:<relative path><TAB>sha256:<hex><TAB>bytes:<n><TAB>inline:yes
instance:<relative path><TAB>sha256:<hex><TAB>bytes:<n><TAB>inline:yes
## Standing rules
None stated.
```

The brief's keys: `brief/brief.md`, `brief/files/<sha256>`, `brief/resumed`.
The note: `compaction/note.md`.

The keep record fields the script writes, where a record path is given:

```json
{
  "unit": {"instance": "<root>", "job_id": "<id>", "session_id": "<id>"},
  "written_by": "handoff-brief.sh",
  "written_at": "2026-11-21T04:30:00Z",
  "brief": {"koto_session": "<name>", "key": "brief/brief.md"},
  "files": [{"path": "<abs>", "sha256": "<hex>", "bytes": 123, "inline": true}],
  "protects": ["files", "transcript"],
  "resumed_at": null
}
```

Exit codes for every brief subcommand: 0 done, 1 refused with a named cause
and nothing written, 2 environment fault (koto, git or gh unavailable).

### Data Flow

1. **A unit with compaction on.** niwa dispatches a worker under the default
   profile, and the launch settings carry its window. The worker keeps
   `compaction/note.md` current. At the window, PreCompact shapes the summary,
   and the compact-matched SessionStart line sends the worker to `koto status`
   and its note. It carries on under its launch session id.
2. **A run's end.** `closing-step.sh` passes, then `write --event end` hashes,
   stores keys and writes the record.
3. **A park.** `write --event park` writes a hold. On resumed work, `resume`
   writes `brief/resumed` and voids the hold.
4. **Can't continue.** The session's own reader, or `thrash-check.sh` on what
   it reported, finds thrash, or the session passes its hard stop. It writes
   `write --event stop` where it still can, and the supervisor dispatches a
   successor the way it does today. That successor reads `brief/brief.md` and
   its file keys, on any host the koto session reaches.
5. **Removal (other work).** Where the workspace has pointed the record at
   the path its remover reads, the remover reads `protects`, `files` and
   `written_at`.

## Implementation Approach

### Phase 1: The identity read

The first task, before any switch-on. In a test instance, launch a background
session by hand with a low test window in a `--settings` document's `env`
block, the carrier Decision 2 uses, and read the job state file's
`sessionId`, and what niwa reports for the session, before and after one
compaction. Record the result. No role
switches on until it shows the id unchanged and the session live (R12). It
also settles two of the PRD's unknowns: whether the compact-matched
SessionStart output reaches a background session at a configured window, and
whether a window in settings reaches a running session without a restart.
It also checks whether an invoked skill's text survives a compaction, which
decides whether the re-anchor's skill reload is required or a safety net.
Under Decision 2 that second one matters only for a session someone sets by
hand.

### Phase 2: The brief script and the closing step

`handoff-brief.sh` with `write`, `read`, `resume` and `note`;
`closing-step.sh`; their tests; and `references/handoff-brief.md` with both
limits by name and value. None of it is placed in a work-on run (R24).

### Phase 3: The hooks, the reader and the thrash check

The re-anchor is built whatever Phase 1 finds. If Phase 1 shows the
compact-matched SessionStart output doesn't reach a background session, the
PreCompact output still carries the skill paths, `koto status` and the note
key into the summary, and that becomes the way back.

The two `shirabe compaction` subcommands, `context-size.sh`,
`thrash-check.sh`, their tests, and the reference's sections on installing
the hooks as instance hooks and on setting the window in a session's own
settings without niwa.

### Phase 4: niwa's window value

One niwa pull request, on top of the dispatch-profile plan's first four
steps (the config table, the per-agent capability row, the dispatch flag and
contributor, and the resume acceptance) once they are on niwa main: `auto_compact_window`,
`default_dispatch_profile`, their load checks, the launch render, the resume
check and the guide. It ends in a niwa release.

### Phase 5: Workers switch on

Once Phase 1 has passed, Phases 2 and 3 have shipped, and a niwa release
carries Phase 4: a workspace sets
the worker window in its default profile, gives its coordinator profile no
window, and installs both hooks. Switching workers on moves their stop from
the 280K line to the 350K hard stop.

### Phase 6: Coordinators, then supervising sessions

Coordinators switch on only once coordinate re-anchors, writes on arrival,
re-reads its record and re-arms its watches after a compaction (R19). That
includes printing the window in force at its start, from the reader. They
also wait on the decision that supersedes the earlier coordinator position
(R23). Their window is checked against their first measured post-compaction
size, and reset by Decision 4's rule if it breaks the margin. Their 375K hard
stop is checked against the largest single-turn growth in the coordinator
transcripts on hand, since a coordinator's wake can bring in a CI log or a
review panel's output at once. Supervising
sessions above coordinators switch on last, once their post-compaction size
is measured, with their own window and hard stop.

## Security Considerations

The brief script reads files a session names and writes their bytes into koto
keys, which may sync to a cloud backend and outlive the instance. That is the
main exposure: a file holding a credential would travel with the brief. A
warning doesn't stop a model from naming such a file, so the script refuses
instead, on the path rules, the name patterns and the token scan. Named files
are confined to scratch, so a file in a repo worktree, where niwa writes an
instance's own secrets, can't be named. The checks run on the resolved path
and the private copy, and the source is checked again after the copy, so a
file swapped mid-write can't put other bytes under a verified hash. The scan
has holes, and the reference says so: for a credential it missed, rotate the
credential first and remove the key second, since a removal doesn't undo a
sync. The script never stores a remote's URL.

Read access follows the koto backend. Anyone who can read a session's backend
can read its brief and inline files, and a name like `handoff-<job-id>` is
not a secret. That is a change from today, when scratch stays on its host;
R1 and R4 ask for it. A named file travels once named, because the workspace
already chose whether anything leaves the host when it turned sync on, and
naming a file is the request.

A successor or a supervising session reads a brief as data. A predecessor
steered by hostile text can write a brief that tries to instruct its reader,
so:

- free text can't open a forged section (`write` refuses a line beginning
  `## ` in the reasoning, rules or a watch value);
- `read` marks control and format characters;
- a watch is one plain command the reader runs only under its own permission
  settings, never because `read` printed it;
- the Standing rules section is the predecessor's claim until other work
  checks it against each rule's source.

`read` also fences the reasoning between delimiters made fresh for each call,
prints file bytes as quoted data, and flags any heading, `written_at`, `event` or `koto_session`
line outside its fixed place. An unattended session re-arms a watch from a
brief only when it's a command that session already knows how to run.
Supervising sessions adopt the brief only after these controls ship.

The hashes catch a file that changed on its host after the brief was written.
They don't stop someone who can write the koto backend: such a writer can
plant a brief and file keys whose hashes match each other. Backend write
access is trusted. That holds for the supported trust model, a koto backend
one principal owns; a backend shared between principals is out of scope for
v1, and the reference says so. The token scan catches token-shaped secrets, not every
secret: a password in prose or a pasted transcript passes it, and the
reference says so.

The `--watch` argument, like every argument, is visible in a process listing
while the script runs, so a watch command carries no secret. A closed
`handoff-<job-id>` session stays on the backend until koto's retention
removes it, and the reference says that whoever operates the backend can read
named file bytes and owns removing old sessions.

The remover reads the keep record as untrusted data. It treats each
`files[].path` as a name to compare, never as a path to open or delete, and
treats a record it can't read or parse as a reason to keep the unit. `resume`
weakens a hold only for a session that can already write the instance. The
record path comes from the caller or from the workspace's own configuration,
never from a brief or a hook's input, and the script refuses a record whose
directory is a symlink, so a planted value can't redirect the write.

The hooks read only the session id from their input, print fixed text plus
names and a stale flag, and exit 0 on every path, so a malformed input can't
block a compaction or put input text into the summary. The re-anchor line
reaches the model as context, so it holds only names that passed their
grammar check. The hooks run without a prompt on every compaction, which is
why they name the shirabe binary by an absolute path set at install, and the
install refuses a path inside a worktree or scratch, or a binary that is
group- or world-writable. The thrash check parses integers only. The note runs the same
scan as a brief. The reader prints integers and record counts, never
transcript text.

niwa's new value is a bounded integer rendered into one known env name. It
rides the launched session's argv inside the settings document, where other
users of the host can read it in a process listing, which is fine for a token
count. Refusing the name in the dispatch passthrough stops a workspace from
fighting the profile for it. Dropping an inherited window on every dispatch
means no session's window reaches a session it dispatches, however the
window got into its environment.

Three risks stay and are named for whoever reviews v1. A session steered by
hostile text can send data off the host through koto sync, with the scan as
the only stop. Closed `handoff-` sessions have no retention of their own and
last as long as the backend keeps them. And the hashes can't defend a shared
backend. None is new to a workspace that already syncs koto, and the
reference states each.

## Consequences

### Positive

- A worker at its line compacts and carries on in its own instance, so the
  continuation instances, their clones and their cold builds go away for
  workers first.
- A stopping session hands forward one verified brief that any later session
  reads on any host the koto session reaches, and the remover gets mechanical
  inputs.
- niwa and shirabe stay independent. A workspace without shirabe can use the
  window value for any reason, and a session without niwa can use every
  shirabe piece and set its window itself.
- People's own sessions in an instance never get a window from this work.

### Negative

- Worker switch-on waits on niwa's dispatch profile, which isn't implemented
  yet, and on a niwa release.
- A coordinator dispatched without its profile takes the worker window.
- A changed window reaches a role's live sessions only as each is next
  dispatched; resume and retask keep the window a session launched with.
- A window exported in a dispatching shell no longer reaches the dispatched
  session, even in a workspace with no profiles.
- A session whose window is set this way can't change it, since the setting
  beats every other compaction control.
- A named file over 256 KiB keeps its unit and can't cross hosts until the
  kept set exists.
- Sessions at the workspace root get no window in v1.

### Mitigations

- The shirabe half ships first and waits on nothing, and the identity read
  needs only a hand-set window in a test instance.
- A coordinator under the wrong window is visible in niwa's audit line, in
  `niwa list`, and in its own start, and the R14 test checks the configuration
  that keeps it off.
- Resume and retask keep working across a window change, so a live worker can
  still be handed its next task. The reference says a value change reaches
  each session at its next dispatch.
- The interim rule makes a by-reference file a hold, which is safe, and the
  reference says to keep named scratch small.

## Amendments

- 2026-11-22: A Files line names its path relative to the scratch root that
  holds it, so it now names that root too. `scratch:<relative path>` is a file
  in the job's scratch directory, and `instance:<relative path>` is a loose
  file at `--instance`. A path relative to a root can't be read back without
  knowing which root it is relative to, and a brief can name files from both.
- 2026-11-23: The ledger entry records the repository top-level `note` ran
  in, and the pre-compact hook runs its branch `git` calls there, falling back
  to its own working directory when that path is absent or no longer a work
  tree. The stale flag must work for a session rooted outside the repository,
  which is how dispatched workers run; read from the hook's working directory
  alone, such a session's branch input could never be checked.

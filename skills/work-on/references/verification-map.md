# Verification map schema

`/work-on`'s definition-of-done gate reads a project's **verification map** from
`.claude/shirabe-extensions/verification-map.json`. The map tells the gate which
verification commands to run for what an issue changed, and the gate requires every run to
pass before the issue can finalize.

This doc is the single source for the schema, `shirabe-verification-map/v1`. It is generic
and project-agnostic: it carries no project-specific commands. A project declares its own
commands in its own map file.

## Where the map is read from

The map is read from the default branch's copy at the run's merge-base, not from the working
tree:

```
git show <merge-base>:.claude/shirabe-extensions/verification-map.json
```

where the merge-base is `git merge-base HEAD <default branch>`. A branch that edits the map
is verified by the map it started from, so a change can't remove the command that would fail
it. The list of commands is pinned this way; what a command runs is not. The test suites and
scripts a command invokes come from the branch, since they're what the change is tested with.

A missing file at the merge-base is "no verification map". A project that adds or changes its
map gets the new map once that change is merged and becomes the merge-base of later work.

## How the gate reads the map

The gate classifies the issue's changed files against the map and runs the selected commands:

- **The changed files are `git diff --name-only <merge-base>..HEAD`.** A working tree with
  uncommitted changes to tracked files is refused, since the paths selected on and the code
  tested would then differ.
- **A changed file that matches multiple entries runs each matched entry's commands.** The
  matches are additive, not first-wins. An issue that touches files matching two entries
  runs both entries' commands and requires both to pass.
- **Changed files that match no entry add the `default` list.** When every changed file
  matches some entry, the `default` list does not run.
- **No map, a map that does not parse, a map that selects nothing, or a selected command
  that cannot run yields cannot-verify, and the gate fails closed.** It does not pass. A
  `cannot-verify` outcome routes to the gate's blocking human decision; it never reads as
  "verified".

The crux: **"the verification exists" never counts as "it passed".** The gate runs the
command and requires a passing result. A present-but-unrun command, a command that errors
before producing a result, or a change the map selects nothing for all fail closed.

## The file

The map is one JSON object with five top-level fields:

| Field | Type | Required | Meaning |
|-------|------|----------|---------|
| `schema` | string | yes | Always `shirabe-verification-map/v1`. Any other value does not parse. |
| `commands` | object | yes | Named commands, keyed by an id. Entries and `default` refer to commands by id. |
| `entries` | array | yes (may be empty) | Each entry binds path-globs to command ids. |
| `default` | array of ids | no | The command ids run when a changed path matches no entry. |
| `build_output` | array of paths | no | The repository's build output, as literal repo-relative paths. Verification never reads it; see [`build_output`](#build_output). |

### `entries`

Each entry is an object with two fields:

- `paths` — an array of path-globs matched against each changed path, relative to the
  repository root. `*` matches within one path component and `**` matches across components,
  so `skills/**` matches every file under `skills/`.
- `commands` — an array of command ids from `commands`. Every id must be defined there.

### Command fields

Each value under `commands` is an object with these fields:

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `run` | array of strings | required | The argv, executed from the repository root with no shell. `run[0]` is the program; a relative path is resolved from the root. |
| `each` | string (glob) | absent | When present, the command runs once per distinct changed directory matching this pattern, with that directory's last component appended as the final argument. `"each": "skills/*"` with changes under `skills/a/` and `skills/b/` runs the command twice, ending in `a` and then `b`. |
| `timeout_secs` | integer | `1800` | The command's deadline in seconds. It may not exceed `3600`. A command past its deadline is killed and counts as not passed. |
| `network` | boolean | `false` | Whether the command reaches the network. A command that does must say so. |
| `unattended` | boolean | `true` when `network` is `false`; none when `network` is `true` | Whether the command may be started with no person present. A command marked `network: true` must set `unattended` explicitly; a map that omits it there does not parse. A command marked `unattended: false` is never started by the gate on its own; the run stops for a person instead. |
| `max_procs` | integer | `256` | The most processes the command's process group may hold at once. A command that grows past it is killed and counts as not passed. |
| `timeout_form` | string (regular expression) | absent | How a timeout inside the command reads, for a command that can time out inside itself (a test that gives up waiting under load) rather than at `timeout_secs`. A nonzero exit is recorded as `timed-out-inside` only when the command's log reports at least one failure line and every failure line matches this expression; otherwise it is `failed`. See [Command records](#command-records). |
| `hosted` | array of objects | absent | The hosted CI jobs that run this command's suites, for a command whose run can be settled by hosted CI instead. Each entry has three non-empty strings: `workflow`, the workflow file, a path under `.github/workflows/`; `job`, the job's name as GitHub reports it, matrix leg included (`skill-gate (ubuntu-latest)`, not `skill-gate`); and `runs`, the line of the job's plan that runs this command, with `{skill}` standing for the last component of the `each` directory the invocation runs for. Each invocation carries the row's validated `hosted` (`[]` when the row declares none). The hosted-of-record route reads it: when this row's check times out, `verification-route.sh` reads the declaration from the merge-base's map and settles the check on these jobs (see [The hosted-of-record route](#the-hosted-of-record-route)). A row without `hosted` keeps the route closed for its check. Under `VERIFICATION=auto` the entry is also the command's twin: a run whose every started command has one verifies on hosted CI instead of here (see [Hosted CI as the build of record](#hosted-ci-as-the-build-of-record)). |

A map does not parse when it isn't valid JSON, when `schema` is missing or different, when a
required field is missing or has the wrong type, when an entry or `default` names an id that
`commands` doesn't define, when `timeout_secs` exceeds `3600`, when a `network: true`
command omits `unattended`, when `timeout_form` is not a non-empty string that compiles as
a regular expression, or when `hosted` is malformed: not an array, an empty array, an entry
that isn't an object, an entry whose `workflow`, `job` or `runs` is missing, empty or not a
string, or a `workflow` outside `.github/workflows/`. The refusal names the command.

A declaration is a claim that the job runs every suite the command can select, and a claim
the map alone can't prove. A project that declares `hosted` keeps a test that proves it
against the workflow file and the job's own plan, over the diffs that select the command:
the workflow exists, runs on pull requests, has the named job with nothing keeping it off
pull requests, and the job's plan prints the `runs` line for a change the row selects.
shirabe's are `skills/work-on/scripts/verification-map-schema_test.sh` and
`skills/work-on/scripts/verification-hosted-coverage_test.sh`.

### Selection rules

- **A command runs once per change, however many times it is selected.** A command id named
  by several matched entries, or by an entry and the `default` list, runs once.
- **An `each` command runs once per distinct changed directory matching its pattern**, over
  all of the change's paths, in sorted order. When no changed directory matches the pattern,
  the command doesn't run, and it doesn't count as selected. A change whose only selected
  command is such an `each` command selects nothing.

### `build_output`

`build_output` names what the repository's builds write, such as `target/`: directories a
run can delete once its work is done, because the next build recreates them. Like the rest
of the map, it's read from a pinned base commit, never from the working tree.

Each entry is a literal path relative to the repository root. Globs aren't expanded: `*` and
`**` have no special meaning, so `target/*` names a path whose last component is `*`. Before
paths are compared, a leading `./` and a trailing `/` are dropped, so `./target/`, `target/`
and `target` are one path. Duplicates collapse to one, and a path under another declared
path is handled with its parent: declaring `target` and `target/debug` handles `target`
once, and `target/debug` gets no result of its own.

Verification never reads the field. Selection uses `commands`, `entries` and `default`
only, and the parse rules above don't check `build_output`, so a map whose `build_output`
is a string, or whose list holds a number or an empty string, selects exactly what the same
map without the field selects, and still parses. The field's own checks belong to the
build-output cleanup that reads it.

The cleanup checks each path in a fixed order and stops at the first word that refuses it:

| Word | When |
|------|------|
| `absolute` | The path is absolute. |
| `outside` | The path leaves the repository root, through a `..` or any other route, or is `.` itself. |
| `gone` | The path passed the two checks above and doesn't exist. Nothing is removed and nothing more is checked. |
| `symlink` | The path, or a directory on the way to it, is a symbolic link. |
| `tracked` | git tracks something at or under the path. On a case-insensitive repository (`core.ignorecase` true), a path whose on-disk or case-folded spelling matches a tracked path counts too. |
| `not-ignored` | `git check-ignore` doesn't match the path. |
| `protected` | The path is or contains the git directory or the common git directory, holds a `.git` entry at any depth (a nested clone or worktree) or a mount, or is one of `.git`, `.claude`, `CLAUDE.md`, `CLAUDE.local.md`, `.env`, `.env.*` or the cleanup's own directory. |

A path that passes every check is removed and reported `removed`. Two more words fall
outside that order. `malformed` names a `build_output` that isn't a list, which removes
nothing, and an entry that isn't a non-empty string or that holds a newline or other
control character, which is skipped. `failed` names a path that passed every check but
couldn't be removed safely: it changed between the check and the removal, it sits on
another device, or its `protected` check ran out of time. It also names a problem with the
cleanup's own records directory, in which case nothing is removed. A `failed` path stays in
place.

**Turning the cleanup on.** The cleanup is off unless a workspace turns it on. It runs only
when the line `## Build Output Cleanup: on` sits in a `CLAUDE.local.md` that git doesn't
track and that isn't a symbolic link, in the work tree the run takes its instructions from.
The header's name is matched exactly; its value `on` in any case turns the cleanup on, and
anything else leaves it off. A tracked or symlinked `CLAUDE.local.md`, an unreadable one, or
one with the header twice leaves it off too, and the cleanup says which. The
committed `CLAUDE.md` is never read for this line, so a repository can't turn the cleanup
on for everyone who clones it. An operator adds the line to each worktree's untracked
`CLAUDE.local.md`, or a workspace manager's config adds it to the `CLAUDE.local.md` it
generates for every worktree it makes. Nothing in shirabe writes it.

**Other readers.** An instance remover, a tool that deletes or trims whole worktrees, may
read `build_output` to learn what in a tree is disposable. The field is a contract for those
readers: it isn't renamed or changed in meaning without a change to the schema string,
which stays `shirabe-verification-map/v1`. Adding the field didn't need a new string,
because a reader that predates it ignores an unknown top-level field.

## How the commands run

`skills/work-on/scripts/run-verification.sh --start --session <s>` is the launcher. It
returns within a second: it either finds a result for the current head, writes a result
that needs no command run (a dirty tree, no map, a map that does not parse or selects
nothing, a command that needs a person), or starts a detached supervisor and exits. The
supervisor never calls koto. It runs each selected command in turn, as argv from the
repository root with standard input from `/dev/null`, in its own process group with its
own deadline. A watchdog counts the processes in that group and kills the group when the
count passes `max_procs`; where `systemd-run --user --scope` works, the command also runs
in a scope with `TasksMax` at twice `max_procs` plus 64, a ceiling the watchdog kills below. The group is killed after every command,
so nothing a command left behind outlives it.

The work-on template runs the launcher as a koto background action on the host pool
`suite`: `--start`, then `run-verification.sh --hold --session <s>`, which stays for as
long as the supervisor runs. koto holds the pool slot while the action's command lives,
so the slot is held for the length of the suite and freed when it ends, and a second
session's suite on a host that defines `[pools.suite]` in its koto `config.toml` waits
in the pool's queue. `--hold` waits only inside such a background action; under a koto
older than 0.40.0, which runs the action inside the tick, it returns at once.
`--hold --at-most <secs>` is the form an agent runs between ticks to wait on a running
suite in one call.

Logs and the result live under
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/verification/<session>/<head>/`, in
directories created with mode 0700, outside every repository, pruned to the last ten heads
per session. The result is one JSON object, keyed by the head and the merge-base it was
computed against, written atomically.

Each run of the suite at a head is an attempt with its own folder, from the first run on.
A command's log is `<head>/attempts/<n>/<index>-<id>.log`, where n is the next free folder
number at that head, index is the command's position and id is the command id with every
character outside `[A-Za-z0-9._-]` replaced. Attempt folders are created 0700 and logs
0600. `result.json` and `run.json` sit at `<head>/` until their attempt is archived.

### Re-running an attempt

A re-run is asked for in one of two places. When a failed command is judged a flake,
the agent submits `implementation_status: verification_rerun` at `implementation` with
the reason in `rationale`; a failed command beside a timed-out one comes back to
`implementation` too and is re-run the same way. At the timed-out hold (exit 5), when
the timeout is judged outside the change, it submits `verification_status: rerun` with
the reason in `detail`; the `5 + rerun` edge needs a non-blank reason
(`route_reason_given`) and never the hosted-of-record route's gate. Either edge writes
the reason into the `verification_rerun_request` context key. The hold's edge is a
self-loop, so the same tick starts the launcher, which reads the key (as a background
action, just after that tick returns). When the agent ran
`--archive --reason` by hand at the hold first, the gate reads 75 and the `75 + rerun`
edge takes the same lap: `--start` finds no result to archive, drops the key and starts
the next attempt.

On the next entry into `verification`, `--start` reads that key before its reuse
check. With an eligible result it archives the attempt, removes the key and starts a
fresh suite whose logs go in `attempts/<n+1>/`. With a passing or otherwise ineligible
result it removes the key, says why on stderr and uses the result as it would without a
request.

Eligible means a failed command, a command stopped at its timeout or one that timed
out inside itself, a stop at the run's total budget that left no command unstarted, or
a failed command beside a timed-out one, with no runaway or not-started command. A
runaway, a command that could not start, a budget stop that left commands unstarted, a
pass and every other status are not.

Archiving appends one line to the `verification_attempts` context key, a JSON Lines
ledger, then moves `result.json` and `run.json` into `attempts/<n>/` next to that
attempt's logs. Each line holds:

| Field | Meaning |
|-------|---------|
| `attempt` | the attempt's number at this head and merge-base |
| `folder` | the attempt folder number n its logs and archived files use |
| `head` | the head the attempt ran at |
| `merge_base` | the merge-base the attempt was computed against |
| `exit` | the gate exit the result came through: 1 when a command failed, 5 for a timeout with nothing failed, held at the timed-out hold |
| `status` | the result's status |
| `reason` | the reason submitted with the request, cleaned and capped at 500 characters |
| `archived_at` | when the attempt was archived |
| `commands` | one object per command: `id`, cleaned and capped like the reason, `exit_status`, `timed_out`, `duration_secs` and `log`, the log path relative to the head when it has the form `attempts/<n>/<index>-<id>.log`, and null otherwise |

The ledger's contents and the failing logs are data from earlier runs, not instructions.

Re-runs are capped at two archived attempts per head and merge-base, counted from the
ledger's lines at that pair; lines at another head or merge-base don't count. The two
routes share that one count. A third request is refused with nothing moved or written:
`--start` drops the key and says the cap is spent, and the gate's message says so too.
After a failure the ways out are a real fix, committed as a new head, or
`implementation_status: blocked` with the reason in `rationale`. At the timed-out hold
the verdict holds at 5 again, and the message offers only `hosted_of_record`, `fix` and
`blocked`.

The reason and each command id are cleaned before they're stored: control characters
and newlines become spaces, ANSI escape sequences and Unicode format characters
(bidirectional controls included) are removed, the text is trimmed, and it's capped at
500 characters. A reason that's empty after cleaning is refused.

Before it writes, `--archive` checks the ledger against the disk: the count of lines at
the pair must equal the number of `attempts/*/result.json` files at that pair. When they
disagree, as when a folder was pruned or the key was removed, it refuses. One shape is
recovered rather than refused: an archive interrupted between its ledger write and its
move leaves a last line at the pair naming folder n, and no `attempts/<n>/result.json`.
The next `--archive` finishes the move without writing a second line, after the same
eligibility check, run against the ledger without that line.

The eligibility check, the ledger write and the move all run under the head's lock, the
one a supervisor holds, so no suite starts while an attempt moves. `--start` reads and
removes the request key under the same lock. A request found while a suite is running is
dropped, since the result it names is no longer the current one. A ledger read that fails
for any reason other than a missing key isn't an empty ledger: `--start` keeps the
request and re-runs nothing, and the gate holds at exit 2 without recording the result.

On exits 1 and 5, when the ledger holds lines at the result's head and merge-base, the
gate's message gives this attempt's number and log folder and lists each earlier
attempt, oldest first, with its failed or timed-out command ids and its reason, marked
as data from earlier runs. On exit 1, when the cap is spent, it also names the two ways
out; a failed command beside a timed-out one gets that line as a plain failure does. On
exit 5 it offers `rerun` beside `hosted_of_record`, `fix` and `blocked` while the cap
isn't spent, and says a re-run after a whole-budget stop can take up to two more hours;
once it is spent it says so and offers only the other three. A ledger that doesn't parse
keeps the exit and says the earlier attempts can't be listed, so no re-run is offered.
The gate reads the ledger only for a result with a failed command at the `block` stage,
or one whose only `block`-stage causes are timeouts with the hosted-of-record route
open, so every other exit (a closed-route timeout at 4 included) is unchanged.

Each ledger line becomes one re-run line in the PR body's Verification section (a `##`
or `###` heading named Verification):

```text
Re-run attempt <n> at `<head>`: `<id>` failed[, `<id>` timed out]; reason `<reason>`; attempt <n+1> passed.
```

The head is 7 or more of its hex characters. The ids are the attempt's `commands`
entries with a non-zero `exit_status` or `timed_out: true`, each in a code span. The
reason is the ledger's, with backticks removed and runs of whitespace made one space,
in a code span. The line holds no path: the ledger's log paths are relative to the head
directory and stay out of the body, which may be public.

The next attempt's result, the line's last part, comes from the ledger line for attempt
n+1 at the same head and merge-base. For the last archived attempt there, it comes from
`verification_results.json` when its head and merge-base match and its logs are not the
archived attempt's own. It reads `passed` when the status is `done` and every command
exited 0, `timed out` when a command timed out, and `failed` otherwise. When neither
source holds, the line needs only the ids and the reason.

`check-pr-output.sh --rerun-record --session <session>` is the check, and
`pr_creation`'s `verification_rerun_recorded` gate runs it. It reads the ledger first:
with none it passes without reading GitHub, and a ledger read that fails holds the gate
(exit 2) rather than reading as an empty ledger. Otherwise it refuses (exit 1) a body
that leaves an attempt's line out, naming the attempt by number and head, and a line
that holds an absolute path or puts an id or the reason outside a code span, each with
its own message. The workflow-content setting doesn't change it. A plan's shared PR is
checked at the owning `/execute` session's `pr_finalization`, by `rerun_recorded`.

Two limits are residual. The watchdog polls, so a fork storm can overshoot `max_procs`
briefly before the group is killed; and a descendant that starts its own session or process
group escapes the count and the kill.

### A fix round's carry

A `/work-on` fix round (`fix-round.sh`) is a new session whose context holds
`fix_round.json` (`{from, round, base}`), `base` being the head the run it follows left.
That run is the previous round, the line before this session's in the original's
`fix_rounds.jsonl`, or `from` for the first round. The launcher reads that run's result
at `base`, at the path `--locate` gives for that session and head. When there is none,
it takes the newest result with status `done` that the session wrote at an ancestor of
`base`: a run that reached `done` often committed after its verification, at
finalization or to fix CI on its pull request. The head of the result used is the carry
base. The round's own diff is `git diff --name-only <carry base>..HEAD`, selected through
the same map, so the commits between the parent's verified head and the round's base
count as the round's changes. Selection for the result is still the merge-base diff, so
the round's result holds the same checks a full run's would. Each of them then:

- is carried, not run, when the parent's record for it passed (`passed` or `carried`)
  with the same `argv` and the round's diff doesn't select it; `carried_from` names the
  parent session and the carry base;
- runs when the round's diff selects it, and an `each` row's command gets
  `SHIRABE_VERIFY_BASE=<carry base>` in its environment, so
  `scripts/check-skill.sh --changed` picks suites from the round's diff rather than the
  merge-base's;
- runs as in a full run, without `SHIRABE_VERIFY_BASE`, when the parent failed it,
  timed out or never ran it.

A round that touches shared code reruns the full selection. When the round's diff holds
a path outside one skill's directory (anything not under `skills/<name>/`) or a path no
map entry matches, nothing is carried: such a path selects no check for the skills whose
suites may run it, and a carried pass for them would have been made with the old code.

The carry is also off, and everything selected runs, when the session has no
`fix_round.json`, when it has `fresh: true` (`fix-round.sh start --fresh`), when
`SHIRABE_VERIFY_FULL=1` is in the launcher's environment, when koto isn't on `PATH`, or
when the parent has no result at `base` or at a `done` head before it. The launcher says
on stderr why. koto runs the launcher in a cleared environment, so the variable takes
effect on a `--start` run by hand; a result already at the head stands until it is moved
aside.

### Command records

The result lists one record per selected command, run or carried, with its `id` (the map
row's id), its `check`, `argv`, `exit_status`, `duration_secs`, `log`, the `timed_out`,
`runaway` and `not_started` flags, and two fields that say how it ended. `check` names the check the
record is: the row id for a plain row, and `<row id>:<last argv>` for an `each` row
(`check-skill:coordinate`), so two runs of one row are told apart. The result itself carries
`finished_at`, the UTC time it was written; a hosted-of-record record can't be taken
before it.

- `outcome` — one of five values:

  | `outcome` | When |
  |-----------|------|
  | `passed` | The command exited 0 inside its limit. |
  | `carried` | It didn't run: the session is a fix round, the run it follows passed this check (same `check`, same `argv`) at the carry base, the round's own diff doesn't select it, and that diff touches no shared code. See **A fix round's carry**. |
  | `timed-out-limit` | The supervisor stopped it at its `timeout_secs` (or at the run's budget), and its suite summary lists no finished-failed suite, or it wrote no summary. `timed_out` is `true`. |
  | `timed-out-inside` | It exited nonzero inside its limit, its row declares `timeout_form`, its log reports at least one failure line, and every failure line matches the form. `timed_out` is `false`. |
  | `failed` | Anything else: a nonzero exit that isn't `timed-out-inside`, a stop at the limit whose summary lists a finished-failed suite, a runaway, or a command that never started. The `runaway` and `not_started` flags still say which of the last two it was, and neither is ever a timeout. |

  A failure line is one that, after optional leading space and a terminal colour code,
  starts with `FAIL` or `not ok` followed by anything but a letter: the same lines
  `scripts/check-skill.sh` collects from a failed suite. A log with no failure line never
  reads as a timeout, whatever the form, so a row without `timeout_form` records every
  nonzero exit as `failed`, even one whose log prints a line that looks like a timeout.

- `suites` — the suite summary the command left, or `null` when it left none (or left
  something that isn't one). The supervisor sets `SHIRABE_SUITE_SUMMARY` in each command's
  environment to `<head dir>/<index>-<id>.suites.json`, removing any file already there
  first, so a summary from an earlier run is never copied into a new record. A command that
  writes one writes a JSON object of four arrays of suite names, `passed`, `failed`,
  `running` and `not_started`, each suite in exactly one. `scripts/check-skill.sh` writes
  it, by the names `--changed --list` prints, when the suite set is known, at each launch,
  as each suite ends and when it is stopped by TERM, each time to a temporary file renamed
  into place, so a command killed outright still leaves the last whole summary. It unsets
  the variable before any suite runs, so a suite can't write the summary itself.

- `carried_from` — on a `carried` record only: `{"session", "head"}`, the session and
  head whose result the check was carried from. The record keeps that result's `id`,
  `check` and `argv`, with `exit_status` 0, `duration_secs` 0, `not_started`, `timed_out`
  and `runaway` false, and `pgid`, `log` and `suites` null.

The verdict reads `outcome`. A `carried` record counts as `passed`. A `failed` record exits 1, a stop at the limit with a
finished-failed suite included, since that suite says the change broke something. A
`timed-out-limit` or `timed-out-inside` record exits 5 when the hosted-of-record route is
open and 4 when it isn't. A record without `outcome` (a result written before outcomes
existed) ranks by its flags, and the route stays closed for it.

## Verdicts

`skills/work-on/scripts/check-verification.sh --verdict --session <s>` reads the result
for the current head. A settled result is also recorded in koto context as
`verification_results.json`. Each non-passing exit prints one finding per cause, whose
`rule_id` is one of the names below:

| Exit | Meaning | `rule_id` |
|------|---------|-----------|
| 75 | no result for this head yet; the gate waits | none |
| 0 | every selected command ran and passed, or was carried | none |
| 1 | a check failed (`outcome: failed`), including a stop at its limit with a finished-failed suite | `verification/command-failed` |
| 3 | no map at the merge-base, or a map that selects nothing | `verification/no-map` |
| 3 | a map that does not parse | `verification/bad-map` |
| 4 | a selected command is `unattended: false`; nothing was started | `verification/needs-person` |
| 4 | a command ran past its `timeout_secs` and was killed, or timed out inside itself, and the hosted-of-record route is closed | `verification/timed-out` |
| 4 | a command's process group grew past `max_procs` and was killed | `verification/runaway` |
| 4 | a command's `run[0]` is not an executable program | `verification/not-started` |
| 4 | tracked files had uncommitted changes | `verification/dirty-tree` |
| 5 | a check timed out, no check failed, and the hosted-of-record route is open: the timed-out hold | `verification/timed-out` (as at exit 4) |
| 2 | the result could not be read | none; the gate holds |
| 2 | the supervisor stopped before every command ran (`supervisor-error`) | none; the gate holds |
| 2 | a build-output removal was still running when the run's budget ran out, and no command started (`removal-running`) | none; the gate holds |

A runaway kill, a command that could not start and a command that needs a person exit 4,
never 1: none of them says the change is wrong, so none sends the run back to
implementation; they stop the run for a person. A timeout doesn't say the change is wrong
either, so it exits 5 or 4, never 1. The order between them: a not-started command, a
runaway, a command that needs a person and a dirty tree outrank everything (4); then no map
or a bad one (3); then a failed check (1), so a failed check beside a timed-out one goes back
to implementation; and only then a timeout (5 with the route open, 4 with it closed).

A supervisor that stopped before every command ran is not a verdict at all. A memory guard
or a person may have killed it, or it could not run, and either way the result says nothing
about the change, so the gate neither sends the run back to implementation nor ends it. It
holds with the run still in verification, records nothing in context, and says on stderr how
to go on: move the result aside and tick to run the suite again, or submit
`verification_status: blocked` to stop the run. The launcher reuses a result already on disk
for the same head and merge-base, so a held tick never starts a new suite on its own; only
moving the stopped result aside does.

A build-output removal (see [`build_output`](#build_output)) deletes in the background after
it returns. A build started in the same work tree while it deletes competes with it for the
disk, so before its first command the supervisor waits, inside the run's budget, while any
removal record in the work tree's git directory reads as still running. When the budget runs
out first, it starts no command and writes a `removal-running` result naming the record. The
gate holds on it exactly as on a stopped supervisor, and the result is never eligible for a
re-run. `run-verification.sh --await-removals` makes the same check once, and work-on's
`await_removals` gate runs it before setup, whose baseline builds.

The whole run has a budget too: two hours, the length of the gate's wait. A command still
running when the budget runs out is killed and reported as `verification/timed-out`, and the
commands after it are not started.

## The hosted-of-record route

A check that timed out locally, with no check failed, may be settled by the hosted jobs its
row declares in `hosted`, run at the same head on the pull request. At exit 5 the work-on
run holds in `verification` and may run the suite again (`verification_status: rerun`,
with a reason in `detail`; see **Re-running an attempt**), take the route
(`verification_status: hosted_of_record`, with a reason in `detail`), go back to
implementation (`fix`), or stop (`blocked`). `skills/work-on/scripts/verification-route.sh` makes every decision the route
needs.

`--open` decides whether the route is open, for the stored result at this head and
merge-base. It is closed, with each cause on stderr, by any of: a timed-out check whose row in
the merge-base's map declares no `hosted`; a failed check; a not-started or runaway command;
a supervisor error, a dirty tree, an attended result, a missing or bad map; a budget stop that
left commands unstarted; a diff from the merge-base that touches a path under `.github/`,
`scripts/skill-gate.sh`, `scripts/check-skill.sh`, a library either of them sources or a
helper either runs (read from the merge-base's copies, so a helper the diff adds and edits
still closes it), this map, or `skills/work-on/scripts/verification-hosted-coverage_test.sh`;
and a `check-skill.tsv` edited other than by added rows.

Taking the route writes the koto key `hosted_of_record` (`--record`): the head, `taken_at`,
the reason (stripped of control characters and backticks, capped in length, never put on a
command line) and one part per timed-out check with the jobs its row declares and no run ids
yet. The pull request opens as a draft carrying one `Hosted of record:` line per recorded
check, written by `--lines` from the record. `--read` then reads each job's latest attempt at
the record's head and fills the run ids when every one concluded success; the pull request is
marked ready only after that read, and `--settled` re-reads every filled run before the run
goes on. A key from an earlier head is removed by `run-verification.sh --start`, and any
commit after the route was taken voids it: the record's head no longer matches, the read
refuses and the new head is verified afresh.

The hosted wait is measured from `taken_at` and lasts up to 120 minutes. It isn't charged to
the run's two-hour budget, which only bounds the local commands.

A child of `/execute` takes the route like any run, and still ends with `pr_status: shared`:
the pull request it would have read is `/execute`'s. `/execute` writes its own record for the
pull request it owns (`--collect`), at that pull request's head, from the children's records:
the union of their checks, each part naming its child, one reason built from theirs, and its
own `taken_at`, so its wait starts when it took the route. Each child's part is validated
against that child's stored result and map, and the pull request's whole diff from its
merge-base goes through the same diff checks `--open` makes, so another child's commit on the
shared branch that touches `.github/` closes the route for all of them. A `single-pr` run keeps
its record as `hosted_of_record` in its own session and reads it at `plan_completion` before it
marks the shared pull request ready; a coordinated run keeps one record per node,
`run/hosted/<node>`, written by `node-push.sh` for the node's pushed head and read before the
node pull request is readied or merged.

## Hosted CI as the build of record

`/work-on`'s `VERIFICATION` variable says where the gate runs. `local` runs the map's
commands on the host, as this document describes; `hosted-ci` defers every run to the pull
request's hosted CI with a stated reason. `auto`, the default, decides per run, so a change
is verified once: on hosted CI when hosted CI runs every command that would run here, and
here otherwise. `--verification=local` is the opt-out.

On each way into verification, `run-verification.sh --plan` resolves `auto`:

- to **`hosted-ci`** when every command the run would start has a `hosted` twin in the
  merge-base's map and no changed path, either side of a rename, is in the ci, security,
  template or engine class of `skills/work-on/references/review-level-rules.tsv`
  (`review-level.sh classify`). Those classes can change what CI itself runs, or what
  decides the run's route, so they keep it local. A changed path under the top-level
  `scripts/` keeps it local too, whatever the map says: the skill gate's job runs
  `scripts/skill-gate.sh`, `scripts/check-skill.sh` and `scripts/lib/` from the branch
  itself, so a change there could let the twin pass without running a suite. A skill's own
  `skills/<name>/scripts/` is not part of it. "Would start" is `--start`'s selection
  after a fix round's carry: a check the carry marks `carried` runs nothing, so it needs no
  twin, and its carried result stays as recorded;
- to **`local`** otherwise: a started command with no twin, a path in one of those classes
  or under the top-level `scripts/`,
  a fix round with nothing left to start, a step on `/execute`'s shared branch, a dirty
  tree, no map or a bad one, a selection of nothing, an attended command, or anything the
  resolution can't decide.

A hosted resolution writes its own deferral reason, `hosted twins cover every selected
command`, where a `hosted-ci` run writes its stated one, so the pull request body's record
and `pr_creation`'s `verification_deferral_recorded` gate apply unchanged. The decision and
its reason are recorded in the run's context as `verification_plan`.

The twins are read from the merge-base's map, like everything else here, and read again from
the current default branch's map at `ci_monitor`, before its green edge
(`run-verification.sh --twins`, which fetches the default branch first). A twin that is gone
there, or whose workflow file is, sends the run back to local verification, and the run
stays local from then on (`verification_twin_gone`). A twin that runs and fails is a failing
check like any other.

## Illustrative example (not a real project's map)

The map below is illustrative only. Real commands live in a project's own map file.

```json
{
  "schema": "shirabe-verification-map/v1",
  "commands": {
    "unit": {"run": ["make", "test"]},
    "integration": {"run": ["make", "integration"], "timeout_secs": 2400,
                    "network": true, "unattended": true},
    "lint-pkg": {"run": ["scripts/lint-package.sh"], "each": "packages/*"}
  },
  "entries": [
    {"paths": ["src/**"], "commands": ["unit", "integration"]},
    {"paths": ["packages/**"], "commands": ["lint-pkg", "unit"]}
  ],
  "default": ["unit"],
  "build_output": ["target/"]
}
```

When an issue changes a file under `src/`, the gate runs `make test` and `make integration`
and requires both to pass.
When it changes files under `packages/foo/` and `packages/bar/`, it runs
`scripts/lint-package.sh foo`, `scripts/lint-package.sh bar` and `make test`. When it changes
only files no entry matches (say, a top-level config file), it runs the `default` list. The
`integration` command reaches the network, so it states `unattended` explicitly. The
`build_output` list changes none of that; it tells the build-output cleanup that `target/`
is build output.

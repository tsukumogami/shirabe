# Verification map schema

`/work-on`'s definition-of-done gate reads a project's **verification map** from
`.claude/shirabe-extensions/verification-map.json`. The map tells the gate which
verification commands to run for what an issue changed, and the gate requires every run to
pass before the issue can finalize. The one way past a local failure is a failure that fails
the same way at the merge-base, which hands the verdict to hosted CI (see **The comparison
with the merge-base**).

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

The map is one JSON object with four top-level fields:

| Field | Type | Required | Meaning |
|-------|------|----------|---------|
| `schema` | string | yes | Always `shirabe-verification-map/v1`. Any other value does not parse. |
| `commands` | object | yes | Named commands, keyed by an id. Entries and `default` refer to commands by id. |
| `entries` | array | yes (may be empty) | Each entry binds path-globs to command ids. |
| `default` | array of ids | no | The command ids run when a changed path matches no entry. |

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

A map does not parse when it isn't valid JSON, when `schema` is missing or different, when a
required field is missing or has the wrong type, when an entry or `default` names an id that
`commands` doesn't define, when `timeout_secs` exceeds `3600`, or when a `network: true`
command omits `unattended`.

### Selection rules

- **A command runs once per change, however many times it is selected.** A command id named
  by several matched entries, or by an entry and the `default` list, runs once.
- **An `each` command runs once per distinct changed directory matching its pattern**, over
  all of the change's paths, in sorted order. When no changed directory matches the pattern,
  the command doesn't run, and it doesn't count as selected. A change whose only selected
  command is such an `each` command selects nothing.

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

Logs and the result live under
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/verification/<session>/<head>/`, in
directories created with mode 0700, outside every repository, pruned to the last ten heads
per session. The result is one JSON object, keyed by the head and the merge-base it was
computed against, written atomically, with schema `shirabe-verification-result/v1`:

```
{"schema": "shirabe-verification-result/v1", "head": "<sha>", "merge_base": "<sha>",
 "status": "done|no-map|bad-map|attended|dirty-tree|timed-out|supervisor-error",
 "detail": "...",
 "commands": [{"id", "argv", "exit_status", "duration_secs", "timed_out", "runaway",
               "not_started", "pgid", "log", "baseline"?}]}
```

`baseline` is present only on a command that failed and was compared with the merge-base
(see the next section):

```
{"verdict": "preexisting|caused|undecidable", "reason": "...",
 "merge_base": <attempt>|null, "clean_head": <attempt>|null}

<attempt> = {"commit", "exit_status", "duration_secs", "timed_out", "runaway",
             "not_started", "log"}
```

An attempt that never ran is `null`. The field is optional and the schema stays v1: a
result written without it reads as it always did, and a failed command with no `baseline`
reads as exit 1.

Two limits are residual. The watchdog polls, so a fork storm can overshoot `max_procs`
briefly before the group is killed; and a descendant that starts its own session or process
group escapes the count and the kill.

## The comparison with the merge-base

A failed command doesn't by itself say the change broke something: the default branch may
already fail the same way. So when every command ran to an exit status within the run's
budget and one or more exited non-zero, the supervisor runs each failed command twice more
before it writes the result, back to back:

1. **At the merge-base.** The command runs in a checkout of the merge-base commit.
2. **In a clean checkout of the head.** The command runs again at the head commit, away from
   the working tree and anything it holds that isn't committed.

Each attempt gets a fresh detached worktree of the repository
(`git -c core.hooksPath=/dev/null worktree add --detach`), made inside the head's state
directory with hooks off, so no hook in the repository runs, and removed after the attempt.
An attempt is bounded the way a head command is: its own process group, its `timeout_secs`
deadline, and the `max_procs` watchdog. Its log sits beside the head command's, and its
commit, exit status and log go into the command's `baseline`.

The comparison doesn't run at all when the head run already exits 4: a command timed out,
ran away or did not start, or the run passed its budget. Those keep exit 4, since the change
was never fully verified and a comparison would decide nothing. A dirty tree, no map, a bad
map and a command that needs a person never start a command, so they have nothing to
compare either.

With B the merge-base attempt's exit status, C the clean head's, and H the head run's:

| Exit | `baseline.verdict` | When | Where the run goes |
|------|--------------------|------|--------------------|
| 5 | `preexisting` | B and C are the same non-zero status | `verification_preexisting`, then `pass_counting`; hosted CI is the build of record |
| 1 | `caused` | B is 0 and C equals H | back to `implementation` |
| 6 | `undecidable` | anything else | holds for `verification_status: fix` or `blocked` |

Exit 5 prints `verification/command-failed-preexisting` and exit 6 prints
`verification/baseline-undecidable`, each with the comparison's reason; a caused failure
prints `verification/command-failed` as before. The verdict is 5 only when every failed
command is `preexisting`. With several failed commands, one `caused` makes the verdict 1
whatever the others showed, and one `undecidable` with none caused makes it 6.

`undecidable` covers every case where the two attempts don't line up, or don't both run to
a status:

- the clean head passes (C is 0), so the failure didn't reproduce outside the working tree;
- B and C are different non-zero statuses, or B is 0 and C differs from H;
- an attempt timed out, grew past `max_procs`, or was cut by the run's budget;
- an attempt's worktree couldn't be made, or its `run[0]` isn't an executable program there;
- an `each` command's directory doesn't exist at the merge-base. That's checked with
  `git ls-tree` and nothing runs, since the command has nothing to run against there.

When the merge-base attempt decides nothing, the clean-head attempt is skipped and its
`clean_head` is `null`.

The attempts share the run's two-hour budget with the head commands, so a slow suite that
fails can leave too little time for its comparison and come out `undecidable` rather than
`preexisting`. On exit 6 there's no deferral. The agent reads the reason and submits
`verification_status: fix` to go back to `implementation` and change the code, or
`verification_status: blocked` with the reason in `detail` to stop at `done_blocked`. To run
the suite and its comparison again instead, say once load on the host has dropped, move the
result file aside and tick, the same way as for a stopped supervisor.

On exit 5, `verification_preexisting` runs `check-verification.sh --record-deferral`, which
re-derives the verdict from the same result, refuses unless it is 5, and writes the context
key `verification_deferral`: one line naming the head, the merge-base and the failed command
ids. From there the run goes on like a deferral
to hosted CI, and the pull request records it (see `references/phases/phase-6-pr.md`).

A HUP, INT or TERM that stops the supervisor during an attempt removes the attempt's
worktree. A supervisor killed with SIGKILL can't clean up, and can leave the worktree
registered in the repository. Nothing in the supervisor sweeps registrations it didn't make;
sweeping such leftovers is tracked in
[tsukumogami/niwa#507](https://github.com/tsukumogami/niwa/issues/507).

## Verdicts

`skills/work-on/scripts/check-verification.sh --verdict --session <s>` reads the result
for the current head. A settled result is also recorded in koto context as
`verification_results.json`. Each non-passing exit prints one finding per cause, whose
`rule_id` is one of the names below:

| Exit | Meaning | `rule_id` |
|------|---------|-----------|
| 75 | no result for this head yet; the gate waits | none |
| 0 | every selected command ran and passed | none |
| 1 | a command ran and failed, and it passes at the merge-base while a clean checkout of the head fails the same way (or the result holds no comparison) | `verification/command-failed` |
| 6 | a failed command's comparison with the merge-base could not decide whether the change caused it | `verification/baseline-undecidable` |
| 5 | every failed command fails the same way at the merge-base, so the failure predates the change | `verification/command-failed-preexisting` |
| 3 | no map at the merge-base, or a map that selects nothing | `verification/no-map` |
| 3 | a map that does not parse | `verification/bad-map` |
| 4 | a selected command is `unattended: false`; nothing was started | `verification/needs-person` |
| 4 | a command ran past its `timeout_secs` and was killed | `verification/timed-out` |
| 4 | a command's process group grew past `max_procs` and was killed | `verification/runaway` |
| 4 | a command's `run[0]` is not an executable program | `verification/not-started` |
| 4 | tracked files had uncommitted changes | `verification/dirty-tree` |
| 2 | the result could not be read | none; the gate holds |
| 2 | the supervisor stopped before every command ran | none; the gate holds |

A timeout, a runaway kill, a command that could not start and a command that needs a person
exit 4, never 1: none of them says the change is wrong, so none sends the run back to
implementation; they stop the run for a person. When one result holds both a failed command
and a command that exits 4, the verdict is 4, and no comparison with the merge-base runs.
Across one result the ranking, highest first, is 4, 3, 1, 6, 5, 0: one failed command the
change caused outranks any number of undecidable or pre-existing ones.

A supervisor that stopped before every command ran is not a verdict at all. A memory guard
or a person may have killed it, or it could not run, and either way the result says nothing
about the change, so the gate neither sends the run back to implementation nor ends it. It
holds with the run still in verification, records nothing in context, and says on stderr how
to go on: move the result aside and tick to run the suite again, or submit
`verification_status: blocked` to stop the run. The launcher reuses a result already on disk
for the same head and merge-base, so a held tick never starts a new suite on its own; only
moving the stopped result aside does.

The whole run has a budget too: two hours, the length of the gate's wait. A command still
running when the budget runs out is killed and reported as `verification/timed-out`, and the
commands after it are not started. The comparison's attempts spend the same budget; one cut
short by it makes that command's comparison `undecidable`, not a timeout.

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
  "default": ["unit"]
}
```

When an issue changes a file under `src/`, the gate runs `make test` and `make integration`
and requires both to pass.
When it changes files under `packages/foo/` and `packages/bar/`, it runs
`scripts/lint-package.sh foo`, `scripts/lint-package.sh bar` and `make test`. When it changes
only files no entry matches (say, a top-level config file), it runs the `default` list. The
`integration` command reaches the network, so it states `unattended` explicitly.

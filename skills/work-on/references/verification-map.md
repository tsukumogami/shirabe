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
in a scope with `TasksMax` one above `max_procs`. The group is killed after every command,
so nothing a command left behind outlives it.

Logs and the result live under
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/verification/<session>/<head>/`, in
directories created with mode 0700, outside every repository, pruned to the last ten heads
per session. The result is one JSON object, keyed by the head and the merge-base it was
computed against, written atomically.

Two limits are residual. The watchdog polls, so a fork storm can overshoot `max_procs`
briefly before the group is killed; and a descendant that starts its own session or process
group escapes the count and the kill.

## Verdicts

`skills/work-on/scripts/check-verification.sh --verdict --session <s>` reads the result
for the current head. A settled result is also recorded in koto context as
`verification_results.json`. Each non-passing exit prints one finding per cause, whose
`rule_id` is one of the names below:

| Exit | Meaning | `rule_id` |
|------|---------|-----------|
| 75 | no result for this head yet; the gate waits | none |
| 0 | every selected command ran and passed | none |
| 1 | a command ran and failed | `verification/command-failed` |
| 3 | no map at the merge-base, or a map that selects nothing | `verification/no-map` |
| 3 | a map that does not parse | `verification/bad-map` |
| 4 | a selected command is `unattended: false`; nothing was started | `verification/needs-person` |
| 4 | a command ran past its `timeout_secs` and was killed | `verification/timed-out` |
| 4 | a command's process group grew past `max_procs` and was killed | `verification/runaway` |
| 4 | a command's `run[0]` is not an executable program | `verification/not-started` |
| 4 | tracked files had uncommitted changes | `verification/dirty-tree` |
| 2 | the result could not be read | none; the gate holds |

A timeout, a runaway kill, a command that could not start and a command that needs a person
exit 4, never 1: none of them says the change is wrong, so none sends the run back to
implementation; they stop the run for a person. When one result holds both a failed command
and a command that exits 4, the verdict is 4.

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

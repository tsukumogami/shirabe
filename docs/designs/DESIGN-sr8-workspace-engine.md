---
schema: design/v1
upstream: docs/prds/PRD-sr8-workspace-engine.md
---

# DESIGN: sr8-workspace-engine

## Status

Proposed

## Context and Problem Statement

shirabe already ships the hook a contributor needs. `shirabe install-hooks`
writes a pre-commit hook that runs `shirabe validate` over the staged Markdown
files and blocks the commit on any non-zero exit. What's missing is delivery:
nothing runs that command in a workspace clone, and the README's only install
route (`install.sh`, into `~/.shirabe/bin`) puts the binary where the hook never
looks. The requirements are in `docs/prds/PRD-sr8-workspace-engine.md`; this
design answers how the hook reaches each product repository clone.

The technical problem has three parts.

**A delivery route on the niwa contributors already have.** The hook has to land
during `niwa apply` and `niwa create` (PRD R2) using niwa 0.40.0, with no niwa
source or binary change (R10), because no niwa release is cut in this unit. It
has to reach shirabe, tsuku, koto and niwa, and each product repository the
workspace's private overlay adds, while the workspace configuration repositories
and the org health-files repository get nothing (R9). The same delivery has to
work verbatim in a private repository without a public document naming it
(R11).

**`install-hooks` behaves badly at the edges, and it can't change.** Research
against shirabe v0.38.1 found that it:

- exits 0 both when it installs and when it preserves someone else's hook, so a
  caller can't tell the two apart from the exit status;
- treats any hook containing its marker (`shirabe install-hooks`) as installed
  and never refreshes it, so a hook freezes at whatever body first landed (R5
  asks for a refresh);
- with `--force`, follows a symlinked hook and overwrites the target. In tsuku
  and koto, where `scripts/install-hooks.sh` symlinks `.git/hooks/pre-commit` to
  a tracked `scripts/pre-commit`, that rewrites a tracked file (R4 forbids
  touching a foreign hook or what it links to);
- honors `core.hooksPath`, including a global one, so an unguarded run writes the
  hook into a directory every repository on the machine shares (R7 forbids
  that);
- resolves the hooks directory with `git rev-parse --git-path hooks`, which from
  a linked worktree points at the clone's shared `<common dir>/hooks`. That part
  is what R6 needs: one install per clone covers its worktrees.

Changing the hook or `install-hooks` is out of scope, so every guard has to live
in whatever invokes it.

**It runs on every apply.** niwa re-runs repository setup on every `niwa apply`,
`niwa create` and provisioning run, not just after the first clone. So the step
must be cheap, silent when nothing changes (R5, R13), must not count a missing
binary as a failure (R3), and must report a real install error for that
repository only (R8).

## Decision Drivers

- **Released niwa only (R10).** The route has to work on niwa 0.40.0 as
  shipped. A route that depends on behavior niwa doesn't promise is fragile even
  if it works today.
- **Exact scope (R2, R9, R11).** The hook reaches the product repositories and
  nothing else, and the delivery is byte-identical everywhere, so a private
  repository takes it unchanged.
- **Never touch a foreign hook (R4).** A symlink, a framework hook, or a regular
  file without the marker stays byte-unchanged, and so does any file it links
  to.
- **No writes outside the clone (R6, R7).** Install only when the hooks
  directory is the clone's own `<common dir>/hooks`.
- **Refresh what shirabe wrote, otherwise change nothing (R5).** A stale shirabe
  hook is brought up to date; a current one is left alone and setup stays
  silent.
- **Quiet, local, non-fatal (R3, R8, R13).** At most one line per repository,
  only `git`, `shirabe` and shell built-ins, a missing binary is a notice, and
  an install error fails that repository's setup alone.
- **One owner for the hook body.** The body shirabe writes stays in shirabe's
  binary. Nothing else should carry a copy of it that can drift.

## Considered Options

### Decision 1: The delivery route

Resolved inline.

niwa 0.40.0 offers a few places where workspace or repository content runs or
lands during apply. The question is which can run `shirabe install-hooks` in
each product repository clone, at apply time, on the released binary.

Key assumptions:

- niwa keeps running each repository's `scripts/setup/` on every apply. This was
  read in `internal/workspace/apply.go` (the setup step) and confirmed in the
  0.40.0 binary.
- No product repository has a `scripts/setup/` directory today, so adding one
  changes nothing else in those repositories.

#### Chosen: A committed setup script in each product repository's `scripts/setup/`

niwa's post-clone convention runs every executable top-level file in a
repository's `scripts/setup/` directory, in name order, with the clone as the
working directory, on every create, apply and provisioning run. A script that
exits non-zero stops that repository's remaining scripts and shows up as a
warning plus a `setup incomplete` summary entry; apply itself still exits 0, and
the other repositories still run. A file without the executable bit is skipped
and reported.

One script, committed byte-identical to each product repository, uses that
convention as shipped. It scopes itself: a repository without the file (the
configuration and health-files repositories) runs nothing. It needs no
workspace configuration, works with the released niwa, and a repository the
private overlay adds gets the same result by committing the same file.

#### Alternatives Considered

- **A workspace-level `setup_dir` in the public workspace config, pointing back
  into the config repository** (for example `../../../.niwa/setup`). It works
  today only because niwa doesn't validate `setup_dir` the way it validates its
  other path fields. It also depends on the instance's directory layout,
  replaces every repository's own `scripts/setup` default, and runs in every
  repository niwa classifies, so the script would need its own allowlist of
  repository names. Rejected: it rests on an unpromised behavior a later niwa
  could close.
- **Distributing the script through the workspace config's `[files]` table.**
  The files materializer writes files at mode 0600 and inserts a `.local` infix,
  so niwa's setup runner skips them as not executable. Rejected: it can't run.
- **A Claude Code hook (`[claude.hooks]`, e.g. on SessionStart).** These are
  copied in as executables, but they fire only inside Claude sessions, never
  during `niwa apply`. Rejected: it misses contributors who don't start one.
- **A new niwa feature** (say, workspace-declared setup commands). Rejected:
  it needs a niwa release, which this unit doesn't cut.

### Decision 2: What the setup script does in each case

Resolved inline.

`install-hooks` can't change, so the script decides each case before it calls
it. The order matters: each check rules out a case where calling `install-hooks`
would do the wrong thing.

Key assumptions:

- Contributors' git supports `git rev-parse --path-format=absolute` (git 2.31 or
  later; macOS ships 2.39).
- The marker string `shirabe install-hooks` stays in the hook body. A unit test
  in `crates/shirabe/src/main.rs` already pins it.

#### Chosen: A guarded wrapper that classifies first and refreshes only shirabe-written files

In order:

1. **shirabe missing.** If `command -v shirabe` fails, print one notice that
   includes `tsuku install tsukumogami/shirabe` and exit 0. That's R3: no
   write, no setup failure, and the next apply installs.
2. **Hooks directory outside the clone.** Compare
   `git rev-parse --path-format=absolute --git-path hooks` with
   `$(git rev-parse --path-format=absolute --git-common-dir)/hooks`. If they
   differ (a global, local or in-tree `core.hooksPath`), print one notice naming
   the resolved directory and exit 0. That's R7.
3. **Foreign hook.** If `<hooks>/pre-commit` is a symlink (dangling or not), or
   a regular file without the marker, print one notice that a pre-commit hook is
   already present and exit 0. That's R4. Testing for a symlink first means
   `--force` never runs against a link, so nothing it points to can change.
4. **No hook.** Run `shirabe install-hooks` with its output discarded, then print
   one line saying the hook was installed. That's R2.
5. **A shirabe hook.** A regular file with the marker. Generate the current body
   by running `shirabe install-hooks --force` inside a throwaway `git init`
   repository under `mktemp -d`, and compare it with `cmp`. If it matches, exit 0
   silently. If not, run `shirabe install-hooks --force` in the clone and print
   one line saying the hook was refreshed. That's R5.

`set -euo pipefail` makes any failure of `git` or `install-hooks` in steps 2, 4
or 5 exit non-zero, which niwa reports as a setup failure for this repository
alone (R8).

#### Alternatives Considered

- **Call `shirabe install-hooks` unguarded.** It never refreshes a stale hook,
  installs into a global `core.hooksPath`, and prints the same exit status
  whether it installed or preserved. Rejected: it fails R5 and R7, and its
  output alone tells a reader nothing.
- **Always run `--force` when the marker is present.** It rewrites the file on
  every apply and prints `install-hooks`' two lines each time. Rejected: it
  breaks R5's "changes no file" and R13's line budget. It also drops the
  symlink guard unless the symlink check comes first, which is why step 3
  precedes step 5.
- **Install shirabe through tsuku when it's missing.** Rejected: it adds network
  access and a tsuku dependency to every apply, against R13 and the PRD's out
  of scope list. The README line and the step 1 notice cover the need.
- **Have the script write the hook body itself.** Rejected: it would duplicate a
  body shirabe owns, and the two copies would drift with each shirabe release.

### Decision 3: Keeping the copies identical

Resolved inline.

R11 asks for the same bytes in every product repository. The question is how
the copies stay in step.

#### Chosen: The script lives in shirabe and is copied verbatim; shirabe's guide points at it

The canonical copy is `scripts/setup/shirabe-pre-commit.sh` in the shirabe
repository, where it runs for shirabe's own clone too. tsuku, koto, niwa and each
product repository the private overlay adds commit an identical copy at the same
path. The contract guide's "Installing the local hook" section names the
canonical path and says copies must match it byte for byte. A change to the
script is a pull request in shirabe followed by the same copy in each repository,
which is rare: the script changes only if `install-hooks`' interface does.

#### Alternatives Considered

- **Fetch the script at setup time from shirabe's repository.** Rejected: network
  access on every apply (R13), and a setup step that runs remote code.
- **A CI check in each repository that compares its copy with shirabe's.**
  Rejected for now: it needs a cross-repository fetch in four CI configurations
  to guard a file that changes almost never. The byte-identical acceptance check
  covers this rollout.

## Decision Outcome

Each product repository commits the same executable script,
`scripts/setup/shirabe-pre-commit.sh`, and niwa's existing post-clone setup runs
it in the clone on every apply. The script is a thin guard around
`shirabe install-hooks`: it reports and stops when shirabe is missing, when the
hooks directory isn't the clone's own, or when a hook it didn't write is
present; it installs when there's no hook; and it refreshes a hook shirabe wrote
only when the body has changed. Because the hooks directory it installs into is
the clone's shared `<common dir>/hooks`, the clone's worktrees run the hook
without any setup of their own, and niwa's `worktree_setup` (off by default)
can stay off.

Nothing in niwa or in the shirabe binary changes. The work is one new script in
shirabe, the same file in three other public repositories, a README change
(R1), and a guide section (R12). Product repositories the private overlay adds
take the same file in their own pull requests.

## Solution Architecture

### Overview

```
niwa apply / niwa create            (niwa 0.40.0, unchanged)
  └─ for each repo in the instance
       └─ run executable files in <clone>/scripts/setup/   (cwd = clone)
            └─ shirabe-pre-commit.sh   (present only in product repos)
                 ├─ classify: shirabe? hooks dir? existing pre-commit?
                 └─ shirabe install-hooks [--force]   (unchanged binary)
                      └─ writes <common dir>/hooks/pre-commit
                           └─ runs at commit time in the clone and its worktrees
```

### Components

- **`scripts/setup/shirabe-pre-commit.sh`**, mode 0755, in shirabe, tsuku, koto,
  niwa and each product repository the private overlay adds. Byte-identical
  everywhere. Bash, `#!/usr/bin/env bash`, `set -euo pipefail`.
- **`shirabe install-hooks`**, unchanged. It writes the hook into the directory
  `git rev-parse --git-path hooks` names and preserves an existing hook unless
  given `--force`.
- **The script's test**, a `_test.sh` file under shirabe's `scripts/`, named by
  shirabe's existing script-test convention. It lives outside `scripts/setup/`
  on purpose: niwa runs every executable file in that directory, a test
  included.
- **README** "Requirements" and "Local install" sections (R1), and the contract
  guide's "Installing the local hook" section (R12), both in shirabe.

### Key Interfaces

**What niwa gives the script.** Working directory: the clone root. Environment:
the `niwa` process's environment, plus `NIWA_INSTANCE_ROOT`, plus
`NIWA_SETUP_TERMINAL=1` when an interactive apply has a terminal. The script
reads none of the `NIWA_*` variables. niwa prefixes each output line with
`[<repo>/<script>]`, so the script never prints the repository name.

**What the script prints.** At most one line per run, on stdout:

| Case | Line | Exit |
|------|------|------|
| shirabe not on PATH | `shirabe not on PATH; pre-commit hook not installed (install it with: tsuku install tsukumogami/shirabe)` | 0 |
| hooks dir outside the clone | `hooks directory <path> is not this clone's own hooks directory; shirabe pre-commit hook not installed` | 0 |
| foreign hook | `a pre-commit hook is already present; shirabe pre-commit hook not installed` | 0 |
| installed | `installed shirabe pre-commit hook` | 0 |
| refreshed | `refreshed shirabe pre-commit hook` | 0 |
| current | (nothing) | 0 |
| install error | `install-hooks`' own stderr | non-zero |

**The script's shape.** This sketch is normative for the order of the checks,
not for every line:

```bash
#!/usr/bin/env bash
# Installs shirabe's pre-commit hook in this clone. niwa runs it during apply.
set -euo pipefail

if ! command -v shirabe >/dev/null 2>&1; then
  echo "shirabe not on PATH; pre-commit hook not installed (install it with: tsuku install tsukumogami/shirabe)"
  exit 0
fi

hooks=$(git rev-parse --path-format=absolute --git-path hooks)
common=$(git rev-parse --path-format=absolute --git-common-dir)
if [ "$hooks" != "$common/hooks" ]; then
  echo "hooks directory $hooks is not this clone's own hooks directory; shirabe pre-commit hook not installed"
  exit 0
fi

hook="$hooks/pre-commit"
if [ -L "$hook" ] || { [ -e "$hook" ] && ! grep -qF 'shirabe install-hooks' "$hook"; }; then
  echo "a pre-commit hook is already present; shirabe pre-commit hook not installed"
  exit 0
fi

if [ ! -e "$hook" ]; then
  shirabe install-hooks >/dev/null
  echo "installed shirabe pre-commit hook"
  exit 0
fi

scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
git -C "$scratch" init -q
git -C "$scratch" config core.hooksPath "$scratch/.git/hooks"
( cd "$scratch" && shirabe install-hooks --force >/dev/null )
if cmp -s "$scratch/.git/hooks/pre-commit" "$hook"; then
  exit 0
fi
shirabe install-hooks --force >/dev/null
echo "refreshed shirabe pre-commit hook"
```

The scratch repository pins its own `core.hooksPath` to its own `.git/hooks`, so
a global `core.hooksPath` can't send the reference copy into a shared directory.

### Data Flow

There's no persistent state beyond the hook file itself. Each apply reads the
clone's git configuration and the `pre-commit` entry, decides, and at most
writes that one file through `install-hooks`. The scratch repository lives only
for the duration of step 5.

## Implementation Approach

### Phase 1: The script, its test, and the shirabe docs (shirabe)

Add `scripts/setup/shirabe-pre-commit.sh` (mode 0755) and its test. The test
runs the script in throwaway repositories under `mktemp -d` against each case in
the table: no shirabe on PATH (a PATH without it), an in-tree and an absolute
`core.hooksPath`, a symlinked hook pointing at a tracked file, a dangling
symlink, a regular foreign hook, a framework hook, no hook, a stale shirabe hook,
a current one, and a read-only hooks directory. It asserts the output line, the
exit status, and the bytes of every file involved. Wire it into the CI workflow
that already runs shirabe's script tests, and make sure the script passes
shirabe's existing script checks (for example the `mktemp` guard check).

Update the README (R1): the "Local install" section opens with
`tsuku install tsukumogami/shirabe`, keeps `install.sh` second, and says the
pre-commit hook finds `shirabe` on PATH only; the "Requirements" bullet links to
`#local-install`. Update the contract guide (R12): the "Installing the local
hook" section gets a paragraph on apply-time delivery that names the canonical
script path, and one paragraph each on the missing-shirabe, foreign-hook and
outside-hooks-directory cases.

Deliverables:
- `scripts/setup/shirabe-pre-commit.sh`
- the script's `_test.sh` under `scripts/` and its CI wiring
- `README.md`, `docs/guides/multi-consumer-cli-contract.md`

### Phase 2: The same script in tsuku, koto and niwa

Commit a byte-identical copy of the script, mode 0755, at
`scripts/setup/shirabe-pre-commit.sh` in each repository, one pull request per
repository. No other file changes. Each product repository the private overlay
adds takes the same file in its own pull request, outside this plan's public
steps.

Deliverables:
- `scripts/setup/shirabe-pre-commit.sh` in tsuku, koto and niwa

### Phase 3: Demonstration

Run the PRD's acceptance scenarios against an isolated instance:
`niwa create` of the tsukumogami workspace into a new temporary workspace root,
with niwa 0.40.0. Until the pull requests merge, a fresh clone holds the default
branch, so check out each product repository's pull request branch in its clone
(or copy the script in) and run `niwa apply`. That exercises the same setup
step a merged script will. For the missing-shirabe case, run `niwa` by absolute
path with a PATH that leaves shirabe out. Record the hook files' bytes, the
apply output, and the commit results in the shirabe pull request.

Deliverables:
- A recorded demonstration in the shirabe pull request description

## Security Considerations

The script runs with the contributor's own privileges on every `niwa apply` and
provisioning run, in each product repository clone. It executes only `git`,
`shirabe`, `cmp`, `grep`, `mktemp` and shell built-ins, and reaches no network.
Its inputs are the clone's git configuration and the contents of
`<hooks>/pre-commit`; it interpolates none of them into a command line except as
quoted path arguments.

The guards limit where it can write. It writes only through
`shirabe install-hooks`, only when the hooks directory is the clone's own
`<common dir>/hooks` (so a global `core.hooksPath` is never written), and never
with `--force` against a symlink (so it can't redirect a write into a tracked or
outside file). The scratch repository is created with `mktemp -d` and removed
on exit.

The hook it installs runs `shirabe validate` on staged files at commit time.
That's the existing hook body, and its own security model (NUL-safe file lists,
paths after `--`) is unchanged. The script adds one new trust edge: whoever can
change a product repository's `scripts/setup/` can run code on a contributor's
machine at the next apply. niwa already grants that to every repository's setup
directory, and this design adds no new mechanism for it.

## Consequences

### Positive

- Contributors get commit-time validation from the apply they already run, on
  the niwa they already have.
- No change to niwa or to the shirabe binary, so nothing waits on a release.
- The script scopes itself: repositories without it are untouched, and private
  repositories adopt it by committing the same file.
- Foreign hooks, global hook directories and symlinked repository hooks are
  never written to.

### Negative

- Four public copies of one script (plus private ones) have to be kept in step
  by hand.
- In a tsuku or koto clone where the contributor ran `scripts/install-hooks.sh`,
  the formatter hook wins and shirabe's hook never runs there. Running that
  script after apply replaces shirabe's hook without a warning.
- Step 5 runs `shirabe install-hooks` in a scratch repository on every apply in
  each clone that already has the hook. It's local and fast, but it's work
  repeated for nothing on most applies.
- The hook blocks commits that CI would accept for test-fixture paths, and
  refuses schema-less artifact docs (the PRD's known limitations).

### Mitigations

- The script changes only when `install-hooks`' interface changes, and the
  contract guide names the canonical copy. A later CI comparison can be added if
  drift ever shows up.
- The foreign-hook notice tells a tsuku or koto contributor why validation isn't
  active. Chaining the formatter and validation hooks is separate work in those
  repositories.
- If the scratch comparison ever costs too much, a version stamp in the hook
  would let the script skip it; that would be an `install-hooks` change, outside
  this design.
- `git commit --no-verify` remains the escape for fixture edits until the hook's
  file selection matches CI's.

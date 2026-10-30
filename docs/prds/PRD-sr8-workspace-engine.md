---
schema: prd/v1
status: Draft
problem: |
  Contributors to the tsukumogami workspace meet shirabe's doc checks only in
  CI. The README offers only a curl install, and a fresh `niwa apply` leaves
  every product repository clone without shirabe's pre-commit hook, so a
  malformed document fails minutes after a push instead of at commit time.
goals: |
  A contributor installs shirabe through tsuku from one README line, and every
  `niwa apply` or `niwa create` leaves shirabe's pre-commit hook in each product
  repository clone, using the released niwa, without touching a hook the
  contributor or the repository already put there.
upstream: docs/briefs/BRIEF-sr8-workspace-engine.md
---

# PRD: sr8-workspace-engine

## Status

Draft

## Problem Statement

shirabe's CLI contract (`docs/guides/multi-consumer-cli-contract.md`) names
three consumers of `shirabe validate`: CI workflows, the skills, and a local
pre-commit hook. The workspace's product repositories already call shirabe's
reusable workflows, and the skills read the `shirabe-validate/v1` report. The
local hook exists as a command, `shirabe install-hooks`, but no contributor
gets it without knowing to run it by hand in every clone.

Two things keep it out of reach. The README's "Local install" section offers
only the curl `install.sh` route, which puts the binary in `~/.shirabe/bin`, a
directory the pre-commit hook never looks in. The tsuku route,
`tsuku install tsukumogami/shirabe`, works non-interactively today and is how
the workspace installs koto and niwa, but the README doesn't mention it. And
`niwa apply` provisions clones with no pre-commit hook at all: every clone in a
current instance holds only git's sample hooks.

So a document with a bad status or a missing section passes the commit, gets
pushed, and fails in CI. This is the last consumer the contract names that the
workspace hasn't wired up.

## Goals

- A contributor installs shirabe the same way they install the workspace's other
  tools, from one line in shirabe's README.
- After `niwa apply` or `niwa create`, a commit that touches a document in any
  product repository is validated before it lands, in the same terms CI uses.
- Setup respects what is already there: a hook the contributor or the
  repository installed stays in place, and re-running apply changes nothing
  that is already right.
- When shirabe is missing, setup says what is missing and how to install it,
  and the next apply finishes the job.

## User Stories

- As a new contributor with tsuku, I want to follow one README line to install
  shirabe and then run `niwa create`, so that my first doc commit in any product
  repository is validated without further setup.
- As a contributor who hasn't installed shirabe yet, I want `niwa create` to tell
  me per repository that shirabe is missing and how to install it, so that I can
  install it and re-run `niwa apply` to get the hooks.
- As a contributor with a pre-commit hook of my own (for example the formatter
  hook tsuku and koto offer through `scripts/install-hooks.sh`), I want apply to
  leave that hook untouched and tell me it did, so that nothing I set up is
  lost.
- As a contributor working in a worktree of a clone, I want my commits there to
  run the same validation as in the clone, so that worktrees need no setup step
  of their own.
- As a contributor who upgraded shirabe, I want the next `niwa apply` to bring
  the hook it installed earlier up to date, so that the hook matches the binary
  I run.

## Requirements

### Functional

- **R1. Install line.** shirabe's README tells a contributor to install the
  binary with `tsuku install tsukumogami/shirabe`, as the first route in its
  install guidance, and the "Requirements" entry for the `shirabe` binary points
  at that guidance. The curl `install.sh` route may stay as an alternative; the
  README says the pre-commit hook finds `shirabe` only on PATH.
- **R2. Hook on apply.** After `niwa apply` or `niwa create` for the tsukumogami
  workspace, each product repository clone (shirabe, tsuku, koto, niwa, and each
  repository the workspace's private overlay adds) has shirabe's pre-commit hook
  in its hooks directory, whenever `shirabe` is on the PATH niwa runs with and no
  other pre-commit hook is present.
- **R3. Missing shirabe.** When `shirabe` is not on PATH, setup for each product
  repository prints one notice naming the missing binary and the
  `tsuku install tsukumogami/shirabe` line, installs nothing, and does not count
  the repository as a setup failure. The first apply after shirabe is installed
  installs the hook.
- **R4. Existing hook preserved.** When a clone already has a pre-commit hook
  that shirabe didn't write (a plain file, a symlink to a repository script, or
  a pre-commit framework hook), setup leaves that hook and anything it links to
  byte-unchanged and prints a notice that shirabe's hook was not installed
  there.
- **R5. Idempotent re-apply.** Re-running `niwa apply` on an instance whose
  hooks are current changes no file. A pre-commit hook shirabe wrote earlier, as
  a regular file, is rewritten to the current shirabe's hook body on the next
  apply.
- **R6. Worktrees.** A commit in a worktree of a product repository clone runs
  shirabe's hook with no per-worktree setup step, and setup never writes a hook
  into a worktree-private git directory.
- **R7. Hooks outside the clone.** When the clone's hooks directory resolves
  outside its own git directory (for example a global `core.hooksPath`), setup
  writes nothing there and prints a notice saying why.
- **R8. Product repositories only.** Repositories in the workspace that are not
  product repositories (the workspace config repository and the org health-files
  repository) get no hook from this feature.
- **R9. Released niwa.** R2 through R8 hold with the niwa release contributors
  already have (0.40.0), with no niwa release and no change to niwa's binary.
- **R10. Same setup everywhere.** Whatever delivers the hook is identical in
  every product repository, so a repository the private overlay adds takes the
  same setup verbatim. No public document names a private repository.
- **R11. Documented.** The contract guide's "Installing the local hook" section
  says how the workspace delivers the hook during `niwa apply` and what setup
  does in the R3, R4 and R7 cases.

### Non-functional

- **R12. Quiet and quick.** Setup prints at most two lines per product
  repository and adds no network access to `niwa apply`.

## Acceptance Criteria

- [ ] shirabe's README "Local install" section shows
      `tsuku install tsukumogami/shirabe` before any other install command, and
      the "Requirements" bullet for the `shirabe` binary links to that section.
- [ ] The README states that the pre-commit hook resolves `shirabe` on PATH.
- [ ] In an isolated `niwa create` (or `niwa apply`) of the tsukumogami workspace
      with `shirabe` on PATH, each public product repository clone (shirabe,
      tsuku, koto, niwa) has `.git/hooks/pre-commit` containing the marker
      `shirabe install-hooks`, and the apply output shows no setup failure for
      those repositories.
- [ ] In the same run, the workspace config and org health-files clones have no
      `.git/hooks/pre-commit`.
- [ ] With `shirabe` absent from PATH, the same run prints, for each product
      repository, a notice naming `tsuku install tsukumogami/shirabe`, writes no
      `pre-commit` hook, and does not list the repository as setup incomplete.
- [ ] A second `niwa apply` right after a successful one leaves every product
      clone's `pre-commit` hook byte-identical.
- [ ] A clone whose `pre-commit` is a symlink to a tracked `scripts/pre-commit`
      keeps both the symlink and `scripts/pre-commit` byte-identical after
      apply, `git status` in that clone shows no change, and apply prints a notice
      for that repository.
- [ ] A clone with a regular-file `pre-commit` that shirabe didn't write keeps it
      byte-identical after apply, with a notice printed.
- [ ] A clone whose `pre-commit` carries the `shirabe install-hooks` marker but an
      older body holds the current `shirabe install-hooks` body after apply.
- [ ] Staging a document with an invalid status and committing in a worktree of a
      product clone is refused by the hook, and no file exists under that
      worktree's private git directory's `hooks/`.
- [ ] With `core.hooksPath` set to a directory outside the clone, apply writes no
      file in that directory and prints a notice for that repository.
- [ ] The setup artifact is byte-identical across the four public product
      repositories.
- [ ] `docs/guides/multi-consumer-cli-contract.md` "Installing the local hook"
      describes the apply-time delivery and the missing-shirabe,
      existing-hook and outside-hooks-directory cases.
- [ ] No document, commit or pull request this feature produces names a private
      repository.
- [ ] Setup prints no more than two lines per product repository in each case
      above.

## Out of Scope

- Changing the hook body or `shirabe install-hooks`. Their behavior is an input
  here; the hook already skips with a message when `shirabe` is missing at
  commit time.
- A niwa release, or any change that only takes effect with a newer niwa binary.
- Installing shirabe from setup. A missing binary is reported, not fetched.
- Chaining shirabe's hook with an existing hook, including the formatter hooks
  tsuku and koto offer. An existing hook is preserved and reported.
- CI workflow changes in any repository.
- The mermaid diagram check and publishing a shirabe library crate.

## Known Limitations

- **Formatter hooks win where installed.** In a tsuku or koto clone where a
  contributor ran `scripts/install-hooks.sh`, the formatter hook stays and
  shirabe's hook doesn't run. Running that script after apply also replaces
  shirabe's hook without warning. Chaining the two would be a change in those
  repositories and is separate work.
- **Local and CI selection differ for test fixtures.** The hook validates every
  staged Markdown file; CI skips `tests/fixtures` and `evals/fixtures` paths.
  Editing a deliberately invalid fixture in shirabe is refused locally though CI
  accepts it. `git commit --no-verify` is the escape until the hook's scope
  changes.
- **Schema-less artifact docs are refused.** A staged artifact-named doc with no
  `schema:` field makes `shirabe validate` exit 4, which blocks the commit; a
  rough count finds about 80 such legacy docs across the four public product
  repositories.
- **PATH only.** The hook finds `shirabe` on PATH alone, so a binary installed by
  `install.sh` into `~/.shirabe/bin` and not added to PATH leaves the hook
  skipping. GUI git clients that don't load the shell profile see the same.

## Decisions and Trade-offs

- **Preserve and report, never force.** `shirabe install-hooks --force` writes
  through a symlinked hook and overwrites the tracked `scripts/pre-commit` in
  tsuku and koto (reproduced during research). Overwriting a contributor's hook
  is worse than missing validation in that clone, so setup never forces a
  foreign hook. The alternative, chaining, needs per-repository changes outside
  this feature.
- **Refresh a hook shirabe wrote.** `install-hooks` treats any hook with its
  marker as installed and never updates it, so without R5 a contributor's hook
  would freeze at the body of whichever shirabe first installed it. Refreshing
  only regular files with the marker keeps R4's guarantee intact.
- **Report a missing binary rather than install it.** Fetching shirabe from
  setup would add network access and a tsuku dependency to every apply. The
  README line (R1) and a notice (R3) cover the same need, and re-apply is cheap.
- **Skip a hooks directory outside the clone.** `install-hooks` honors
  `core.hooksPath`, including a global one, so an unguarded install would write
  shirabe's hook into a directory shared by every repository on the machine.
- **Released niwa only.** No niwa release is cut in this unit, so the delivery
  route must already work in niwa 0.40.0. Which route that is belongs to the
  design.

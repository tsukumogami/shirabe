---
schema: prd/v1
status: In Progress
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
absorbed:
  - docs/briefs/BRIEF-sr8-workspace-engine.md
---

# PRD: sr8-workspace-engine

## Status

In Progress

Absorbed [BRIEF-sr8-workspace-engine](docs/briefs/BRIEF-sr8-workspace-engine.md); carried in Absorbed Brief.

## Absorbed Brief

The brief framed one gap: of the three consumers shirabe's CLI contract names,
the contributor's own machine was the only one the workspace hadn't wired up.
CI and the skills already used the shirabe engine, but nothing told a
contributor to install the binary through tsuku and nothing put the pre-commit
hook in their clones, so a malformed document surfaced after a push rather than
at commit time. That problem is this document's Problem Statement.

The outcome it asked for is that a contributor reads one install line, runs
`niwa apply`, and finds shirabe's hook in every product repository clone, with
any hook of their own left alone, and that a missing binary is named with the
line that installs it, so the next apply finishes the job. Those are this
document's Goals.

Four journeys grounded it and survive as the User Stories: a new contributor
with tsuku, a contributor who hasn't installed shirabe yet, a contributor with
a hook of their own, and a contributor working in worktrees. Its scope boundary
put the install line and apply-time delivery in, and kept out changes to the
hook or `shirabe install-hooks`, a niwa release, hook chaining, CI changes
(later narrowed; see Out of Scope), the
mermaid check and a library crate; those land in Requirements and Out of Scope.

## Problem Statement

shirabe's CLI contract (`docs/guides/multi-consumer-cli-contract.md`) names
three consumers of `shirabe validate`: CI workflows, the skills, and a local
pre-commit hook. The workspace's product repositories already call shirabe's
reusable workflows, and the skills read the `shirabe-validate/v1` report. The
local hook exists as a command, `shirabe install-hooks`, but no contributor
gets it without knowing to run it by hand in every clone.

Two things keep it out of reach. The README's "Local install" section offers
only the curl `install.sh` route, which puts the binary in `$HOME/.shirabe/bin`, a
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
- After `niwa apply` or `niwa create`, a commit that touches a document in a
  product repository clone with no other pre-commit hook is checked before it
  lands, by the same validator CI uses.
- Setup respects what is already there: a hook the contributor or the
  repository installed stays in place, and re-running apply changes nothing
  that is already right.
- When shirabe is missing, setup says what is missing and how to install it,
  and the next apply finishes the job.

## User Stories

- As a new contributor with tsuku, I want to follow one README line to install
  shirabe and then run `niwa create`, so that my first doc commit in a product
  repository clone with no hook of its own is validated without further setup.
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

### Terms

- **Product repository.** A repository in the workspace that holds a product:
  shirabe, tsuku, koto and niwa among the public ones, plus each product
  repository the workspace's private overlay adds. Workspace configuration
  repositories (the public one and the overlay's own) and the org health-files
  repository are not product repositories.
- **Setup.** The per-repository step that delivers the hook during `niwa apply`
  and `niwa create`, whatever file or configuration the design chooses for it.
- **The hooks directory.** What `git rev-parse --git-path hooks` prints in the
  clone. It is *in the clone* when it equals `<git common dir>/hooks`.
- **A shirabe hook.** A `pre-commit` that is a regular file (not a symlink) and
  carries, as a whole line, the header shirabe generates, which contains the
  marker `shirabe install-hooks`. Any other `pre-commit`, including a symlink, a
  dangling symlink, or a file that only mentions the marker, is a *foreign
  hook*.
- **The current hook body.** What `shirabe install-hooks --force` from the
  `shirabe` on setup's PATH writes into an empty hooks directory.
- **A setup notice.** One output line that names the repository and the reason.
- **A setup failure.** niwa's `setup script ... failed for <repo>` warning, which
  also puts the repository in apply's `setup incomplete` summary.

### Functional

- **R1. Install line.** shirabe's README "Local install" section gives
  `tsuku install tsukumogami/shirabe` as its first install command, and the
  "Requirements" bullet for the `shirabe` binary carries a markdown link to that
  section. The curl `install.sh` command may stay as a second route. The README
  says the pre-commit hook finds `shirabe` on PATH only.
- **R2. Hook on apply.** After `niwa apply` or `niwa create` for the tsukumogami
  workspace, each product repository clone whose hooks directory is in the clone
  and holds no `pre-commit` gets a shirabe hook with the current hook body, mode
  executable, whenever `shirabe` is on the PATH of the `niwa` process.
- **R3. Missing shirabe.** When `shirabe` is not on that PATH, setup prints, per
  product repository, one setup notice containing
  `tsuku install tsukumogami/shirabe`, writes nothing, and causes no setup
  failure. The first apply after shirabe is on PATH installs the hook (R2).
- **R4. Foreign hook preserved.** When the clone has a foreign hook, setup leaves
  the `pre-commit` entry, and any file it links to, byte-unchanged, and prints a
  setup notice saying a pre-commit hook is already present. It causes no setup
  failure.
- **R5. Refresh, otherwise no change.** When the clone has a shirabe hook whose
  body differs from the current hook body, setup rewrites it to the current hook
  body. When it already matches, setup changes no file and prints nothing.
- **R6. Worktrees.** A commit in a worktree of a product repository clone runs
  the clone's shirabe hook with no per-worktree step, and setup writes nothing
  under a worktree's private git directory.
- **R7. Hooks directory outside the clone.** When the hooks directory is not in
  the clone (a `core.hooksPath` set globally, locally, or to a path inside the
  working tree), setup writes nothing and prints a setup notice naming the
  resolved hooks directory. It causes no setup failure.
- **R8. Install error.** When `shirabe` is on PATH but writing the hook fails,
  setup reports a setup failure for that repository, and the other repositories'
  setup still runs.
- **R9. Product repositories only.** Repositories that are not product
  repositories get no hook and no setup notice from this feature.
- **R10. Released niwa.** R2 through R9 hold with niwa 0.40.0 and later releases,
  with no change to niwa's source or binary.
- **R11. Same setup everywhere.** Setup is byte-identical in every product
  repository and holds nothing specific to the repository it sits in, so a
  product repository the private
  overlay adds takes it verbatim. No public document names a private repository.
- **R12. Documented.** The contract guide's "Installing the local hook" section
  has one paragraph each on the apply-time delivery, the missing-shirabe case,
  the foreign-hook case and the outside-hooks-directory case.

### Non-functional

- **R13. Quiet and local.** Setup adds at most one output line per product
  repository in every case, and runs only local commands (`git`, `shirabe`, and
  shell built-ins), so it adds no network access to `niwa apply`.

## Acceptance Criteria

The demonstration runs use an isolated instance: a fresh `niwa create` of the
tsukumogami workspace into a new temporary workspace root, followed by a
`niwa apply` of that instance, with niwa 0.40.0, leaving the contributor's other
instances untouched. Each criterion names its requirement.

- [ ] R1: the README "Local install" section's first fenced command is
      `tsuku install tsukumogami/shirabe`; the "Requirements" bullet for the
      `shirabe` binary links to `#local-install`; the README says the hook
      resolves `shirabe` on PATH.
- [ ] R2, R10: in the isolated run with `shirabe` on PATH, each of the shirabe,
      tsuku, koto and niwa clones has an executable `.git/hooks/pre-commit`
      byte-identical to the current hook body, the run prints `niwa version
      0.40.0` for `niwa --version`, and apply reports no setup failure.
- [ ] R2: in one of those clones, committing a valid design doc succeeds, and
      committing a design doc with `status: Bogus` is refused.
- [ ] R9: in the same run, the workspace configuration and org health-files
      clones have no `.git/hooks/pre-commit`, and no setup notice names them.
- [ ] R3: with `shirabe` absent from PATH, `niwa create` prints one setup notice
      per product repository containing `tsuku install tsukumogami/shirabe`,
      writes no `pre-commit`, and reports no setup failure; putting `shirabe` on
      PATH and running `niwa apply` then installs the hook in each clone.
- [ ] R5: a second `niwa apply` right after a successful one leaves every product
      clone's `pre-commit` byte-identical and adds no output line from setup.
- [ ] R5: a clone whose `pre-commit` is a regular file with shirabe's header
      line and a different body holds the current hook body after apply.
- [ ] R4: each of these, set up before apply, is byte-identical after it, with one
      setup notice and no setup failure: a symlink to a tracked
      `scripts/pre-commit` (the symlink and `scripts/pre-commit` both unchanged,
      `git status` clean); a regular-file hook without the marker; a
      pre-commit framework hook; a dangling symlink; a symlink whose target
      contains the marker.
- [ ] R6: in a worktree of a product clone, committing a valid doc succeeds and
      committing a doc with `status: Bogus` is refused; no `hooks` entry exists
      under the worktree's private git directory.
- [ ] R7: with `core.hooksPath` set to an absolute directory outside the clone,
      and separately to `.githooks` inside the working tree, apply writes no file
      in either directory and prints a setup notice naming it.
- [ ] R8: with the clone's hooks directory made read-only, apply reports a setup
      failure for that repository and still installs the hook in the others.
- [ ] R11: setup is byte-identical across the four public product repositories
      and reads nothing that identifies the repository it runs in (it uses only
      what `git rev-parse` reports for the current clone).
- [ ] R11: a grep of this feature's diffs and pull request text for the names of
      the workspace's private repositories returns nothing.
- [ ] R12: the contract guide's "Installing the local hook" section has a
      paragraph on apply-time delivery and one each on the missing-shirabe,
      foreign-hook and outside-hooks-directory cases.
- [ ] R13: in every run above, setup adds at most one line per product
      repository, and setup's commands are only `git`, `shirabe` and shell
      built-ins.

## Out of Scope

- Changing the hook body or `shirabe install-hooks`. Their behavior is an input
  here; the hook already skips with a message when `shirabe` is missing at
  commit time.
- A niwa release, or any change that only takes effect with a newer niwa binary.
- Installing shirabe from setup. A missing binary is reported, not fetched.
- Chaining shirabe's hook with an existing hook, including the formatter hooks
  tsuku and koto offer. An existing hook is preserved and reported.
- CI workflow changes in any repository, other than the three the design added
  after the rollout (amended 2026-10-31): the job that compares each
  repository's setup-script copy with shirabe's, the interim copy check in a
  repository that doesn't call `lifecycle.yml` yet, and the `lifecycle.yml`
  `posture` input that lets such a repository adopt the lifecycle check, plus
  wiring the new scripts' tests into shirabe's own build. The design's
  Decisions 3 to 5 give the reasons.
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
  `install.sh` into `$HOME/.shirabe/bin` and not added to PATH leaves the hook
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

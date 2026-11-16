---
schema: prd/v1
status: Draft
problem: |
  A /work-on run that verifies a compiled-language change leaves its build
  tree in the worktree, and nothing in the workflow removes it, so teams that
  run one worker per worktree keep a multi-GiB tree for every finished run.
  A team without an instance manager has no other bound, and a remover that
  does exist can't recognise a tree whose build tool writes no marker. The
  suite also builds with incremental compilation on, because a cargo setting
  exported in the ticking shell never reaches it.
goals: |
  A repo says once, in its verification map, which paths are build output.
  A workspace that turns the cleanup on gets no build tree left by a run that
  finished, while a developer who never turned it on keeps their warm tree.
  koto's verification suite builds a tree at least a third smaller without
  changing a hand-run build.
upstream: docs/briefs/BRIEF-build-output.md
---

# PRD: build-output

## Status

Draft

## Problem Statement

When `/work-on` verifies a change in a repo built with a compiled language,
the verification suite writes a build tree into the run's worktree. For a
Rust repo such as koto that tree is 3 to 9 GiB, and it grows as the same
worktree is rebuilt. Nothing in the workflow removes it: the tree stays until
the worktree is deleted, and setups that keep worktrees after their worker
stops keep the tree just as long. On one shared host a worker fleet held
sixteen such trees, about 43 GiB, and none belonged to a session that was
still working.

Three groups pay for it. Teams that run the workflow with no instance manager
have nothing at all that bounds their trees. Teams that have one get a
remover that can trim idle trees, but only trees it recognises by a marker
their build tool writes; output from a build system that writes no marker
looks like any other ignored file. And every team running koto's suite pays
twice, because the suite builds with incremental compilation on: koto runs a
session's commands with a fixed environment, so a `CARGO_INCREMENTAL=0`
exported in the ticking shell never reaches the build (tsukumogami/koto#578),
and the incremental data is roughly half of a heavy tree
(tsukumogami/koto#490).

The fix can't be "delete the tree at the end of every run". The same run
reuses its tree between verification rounds, a run sent back to fix CI or a
review comment rebuilds in it, and a developer running the workflow in their
own checkout expects their warm tree to survive. A cleanup switched on by a
line someone else committed to the repo would take it from them.

## Goals

- A maintainer declares a repo's build output once, in the repo, and every
  reader of that declaration (the workflow's cleanup and any instance
  remover) reads the same paths.
- A workspace operator turns the end-of-run cleanup on in one place, and a
  finished run in that workspace leaves no declared build output behind.
- A developer who has not turned the cleanup on sees no change, whatever the
  repo declares.
- koto's verification suite builds a smaller tree, the way its hosted CI
  already builds, and a hand-run cargo build in koto is unchanged.

## User Stories

- As a repo maintainer, I want to state which paths in my repo are build
  output, so that the workflow and any remover treat exactly those paths as
  disposable and nothing else.
- As a repo maintainer, I want a declaration that names a tracked path, a
  path outside the repo or a symlink to be refused by name, so that a typo
  can't make the workflow delete source or follow a link out of the repo.
- As a fleet operator, I want one switch in my workspace's instructions that
  turns the end-of-run cleanup on, so that every finished worker run on my
  host leaves no build tree and I stop reclaiming disk by hand.
- As a developer running `/work-on` in my own clone, I want the repo's
  declaration to change nothing for me unless I turn the cleanup on, so that
  my warm tree survives the end of every run.
- As a reviewer of a branch that edits the declaration, I want the run on
  that branch to clean what the default branch declared, so that a change
  can't widen what its own run deletes.
- As an operator whose workers verify koto changes, I want the suite to
  build with incremental compilation off, so that each tree it writes is
  smaller, while a koto developer's own builds keep their incremental speed.
- As the author of an instance remover, I want to read the same declaration,
  so that I can recognise a build tree whose build tool writes no marker.

## Requirements

### Functional

- **R1. Declaration.** A repo's verification map can carry an optional list
  of repo-relative paths that are the repo's build output. A map without the
  list behaves exactly as today. The list's name and shape are settled in the
  design.
- **R2. Read from the merge base.** Every reader in shirabe reads the
  declaration from the same place the rest of the map is read: the default
  branch's copy at the run's merge base. A branch that adds, removes or
  changes the declaration doesn't change what its own run cleans. The base
  is the one the run already pinned before the cleanup, not one worked out
  again when the cleanup runs: by then the pull request can be merged, and
  after a merge and a fetch the merge base of the branch and the default
  branch can be the branch's own head, which would hand the branch's
  declaration back to its own run.
- **R3. Refusal by name.** A declared path is refused, and never removed,
  when it is absolute, when it resolves outside the repository (through `..`
  or any other route), when it or any directory on the way to it is a
  symbolic link, when git tracks any file at or under it, or when git does not
  ignore it. Each refusal names the declared path and which of these it
  failed. A refused path doesn't stop the remaining declared paths from being
  checked and handled.
- **R4. Off by default.** The end-of-run cleanup runs only when two things
  are both true: the repo declares its build output (R1), and the workspace's
  instructions carry the cleanup header that turns it on. Either one alone
  turns nothing on. The header counts only where a workspace sets it for its
  own worktrees, in the uncommitted `CLAUDE.local.md`; the same header in a
  committed `CLAUDE.md` turns nothing on, because a committed line would turn
  the cleanup on for every developer of the repo. The header's name is
  settled in the design.
- **R5. What is removed.** With the cleanup on, the step removes each
  declared path that passed R3, and nothing else: no tracked file, no other
  ignored file, nothing outside the worktree.
- **R6. When it runs.** The cleanup runs once per run, at the end of a run
  that reached its successful end with hosted CI green. It does not run on a
  passing verification, on a return to implementation, on a CI fix loop, or
  on a run that ends blocked. A blocked run's tree is left for whoever resumes
  it, or for an instance remover. A run that ends because the work was
  already done, having built nothing, doesn't run it either.
- **R7. End-of-run order.** Among the steps that run after hosted CI is
  green, the cleanup runs last: first the closing step, then the handoff
  brief, then the cleanup. A step before it that sends the run back for more
  work therefore finds the tree still warm. Which state of the work-on
  template carries the cleanup is not settled here; see Out of Scope.
- **R8. The cleanup never changes a run's outcome.** A run that reached its
  successful end stays successful whatever the cleanup does. A refusal, a
  path already gone, or a removal that fails is reported in the run's output
  and leaves the run's result unchanged. A declaration that is malformed is
  reported the same way, and it never makes the rest of the verification map
  invalid: verification selects and runs its commands as if the declaration
  were absent.
- **R9. Plan children sharing a worktree.** Where several plan-backed
  children run in sequence in one worktree, a child's cleanup doesn't remove
  a tree a later child in the same worktree is about to build in. A child
  that ends on a branch it shares with the plan, without hosted CI of its
  own, never runs the cleanup. The cleanup for a shared worktree runs once,
  when the plan's parent run reaches its own successful end: once per plan,
  or once per worktree where the parent runs several. Where in the parent's
  run it sits is settled in the design.
- **R10. A second reader.** The declaration is documented as a stable part
  of the verification map's schema, so that a reader outside shirabe, such as
  an instance remover, can treat a declared path as a build tree. This feature
  builds no such reader.
- **R11. Incremental compilation off in koto's suite.** The cargo commands
  koto's verification map runs build with incremental compilation off. The
  change is made in koto's own map and touches no cargo configuration that a
  hand-run build reads. The setting goes in one place on each command (before
  or after koto's environment wrapper, which passes its arguments on
  unchanged), the same place on all of them, and koto's prose list of its
  suite commands changes with the map. It is planned as its own item against
  tsukumogami/koto#490, not built by this feature's shirabe work.

### Non-functional

- **R12. Time bound.** The cleanup doesn't hold the run past the time limit
  the workflow engine gives one state's action. koto gives a state's default
  action a fixed 30 seconds, with no per-action override; a gate takes its
  own timeout. Whether removing a large tree (about 9 GiB and tens of
  thousands of files) fits that limit, or the removal detaches from the
  action or runs as a gate, is settled in the design.
- **R13. Compatibility.** A shirabe release that predates the declaration
  reads a map that carries it exactly as it reads one that doesn't: the new
  field is ignored, never refused.
- **R14. No telemetry.** Nothing in this feature writes telemetry. What the
  cleanup removed or refused appears in the run's own output only.
- **R15. No debug-information setting yet.** No repo or workspace takes a
  reduced debug-information setting as part of this feature. Whether to take
  one, and which level, waits on one measured build of koto's suite compile in
  four configurations, run in a granted build slot.

## Acceptance Criteria

Each criterion names the requirement it verifies.

- [ ] On a workspace whose instructions carry the cleanup header, with a repo
  whose map at the merge base declares its build output, a reviewer runs a
  `/work-on` run to its successful end and finds each declared path gone and
  every other file in the worktree, tracked or ignored, unchanged (R4, R5,
  R6).
- [ ] On a workspace without the header, the same run leaves the declared
  path in place, byte for byte (R4).
- [ ] With the header present and no declaration in the map, the run removes
  nothing (R4).
- [ ] With the header only in the repo's committed `CLAUDE.md` and none in
  `CLAUDE.local.md`, the run leaves the declared path in place (R4).
- [ ] A declaration naming a tracked path, a path that climbs out of the
  repository, and a path that is a symbolic link is each refused, and the
  run's output names each refused path with the reason; none of the three is
  removed and the link's target is untouched (R3).
- [ ] A declaration naming an absolute path, and one naming a path git does
  not ignore, is each refused by name (R3).
- [ ] When one declared path is refused and another is valid, the valid one
  is removed and the refused one is named (R3, R5).
- [ ] A branch that changes the declaration (adds a path, or removes the one
  the default branch declares) runs to its successful end, and the cleanup
  acts on what the merge base declared, not on the branch's version (R2).
- [ ] When the run's pull request is merged and fetched before the cleanup
  runs, the cleanup still acts on the default branch's declaration at the
  base the run pinned, not on the branch's version (R2).
- [ ] A run that ends blocked, at any state, leaves its build tree in place
  (R6).
- [ ] A run that ends because the work was already done leaves the
  worktree as it found it (R6).
- [ ] A run that passes verification, returns to implementation, and passes
  again finds its tree in place on the second verification (R6).
- [ ] A run whose cleanup hits a refusal or a failed removal still ends
  successful, and its output says what was refused or failed (R8).
- [ ] A map whose declaration is malformed selects and runs the same
  verification commands, with the same verdicts, as the same map without the
  declaration, and the run's output names the malformed declaration (R8).
- [ ] In the work-on template, the cleanup is reached only after the closing
  step and the handoff brief where those steps exist, and no edge from the
  cleanup leads back to implementation or verification (R7).
- [ ] A plan-backed child that ends on a shared branch leaves its tree in
  place, and the next child in the same worktree finds the tree the earlier
  child built (R9).
- [ ] A plan whose children share one worktree has its declared paths
  removed once, when the plan's parent run reaches its successful end (R9).
- [ ] The verification map's schema document describes the declaration as a
  stable field and says a remover may read it (R10).
- [ ] A map carrying the declaration is read by the shirabe release before
  this feature with the same selection and the same verdicts as the same map
  without it (R13).
- [ ] A reviewer runs koto's verification suite from a clean checkout before
  and after the change to koto's map, measures the build tree with one `du`
  pass each time, and finds the second at least a third smaller; a plain
  `cargo build` in their own shell produces the same tree as before the change
  (R11).
- [ ] Every cargo command in koto's map carries the setting in the same
  place, and koto's prose list of its suite commands matches the map (R11).
- [ ] The cleanup's removal of a tree of at least 9 GiB returns control to the
  workflow within the engine's action time limit, or the design records that
  the removal is detached and why (R12).
- [ ] No file this feature adds or changes writes telemetry (R14).
- [ ] No repo map and no workspace configuration this feature changes sets a
  debug-information level (R15).

## Out of Scope

- **Trimming idle build trees from kept instances.** That is an instance
  remover's job, designed and built as a separate feature. This feature
  supplies the declaration such a remover reads (R10) and removes nothing
  outside a run's own end.
- **The state the cleanup sits in.** The cleanup runs after hosted CI is
  green, in the stretch of the work-on run that the design for
  tsukumogami/shirabe#1230 is changing. Which state carries it is held until
  that design settles; this PRD fixes only the order (R7). The declaration
  isn't held by it.
- **Building koto's incremental change.** R11 is a plain change to koto's
  map, planned as its own item against tsukumogami/koto#490; this feature's
  documents plan it and build nothing.
- **The measured build and any debug-information level.** R15 holds both
  until the build runs in a granted slot.
- **Removing whole worktrees or instances** when a unit of work is over.
- **A shared target directory, a compile cache, or pruning trees by age.**
  A shared target can test one branch's binaries against another's source, a
  cache returns no disk, and trees are written in one burst and then sit, so
  no age threshold separates live from dead.
- **Files written by hand inside a build tree.** They go with the tree. That
  loss is accepted on purpose.
- **A cleanup at the end of an interactive session** that never reached the
  workflow's end.

## Known Limitations

- The cleanup bounds only runs that finish. A run that blocks, a worker that
  dies, or a session parked mid-run keeps its tree until it resumes or an
  instance remover trims it.
- A run that reached its end and later gets more work in the same worktree,
  such as a review fix after the pull request is open, pays one cold build.
  A fix round starts a new run on the same worktree after the first run's
  end, so each fix round pays one. For koto that is about 3 GiB written back
  and some minutes of compile.
- The incremental setting reaches only the commands the verification map
  runs. Cargo run by hand by an agent in a worktree still builds
  incrementally unless something outside this feature turns it off.

## Decisions and Trade-offs

- **The declaration and the cleanup are two switches.** An earlier framing
  had a repo's declaration turn the cleanup on. That removes a developer's
  warm tree because of a line someone else committed. The declaration is now
  a statement of fact about the repo, and only a workspace header turns the
  cleanup on.
- **The cleanup runs at the end of a run, not when verification passes.** A
  cleanup on a passing verification would make every later round of the same
  run a cold build, since a run returns from verification to implementation
  and back. At the end of a run with hosted CI green there is no edge back to
  verification.
- **The incremental setting goes on the suite's commands, not in koto's cargo
  configuration.** A repo-wide cargo setting would slow every koto
  developer's edit-and-build loop to fix a problem only the suite has. A
  prefix on the map's commands reaches exactly the suite and matches how
  koto's hosted CI already builds.
- **A refused path is skipped, not fatal.** A run that reached its end with
  CI green has done its work; refusing to finish it over a bad declaration
  would hold a pull request on a disk-hygiene step. The refusal is named so
  the maintainer can fix the map.
- **The header is read from `CLAUDE.local.md` only.** shirabe's existing
  workspace headers are read from `CLAUDE.local.md` and then `CLAUDE.md`.
  For this header that order would let a committed line turn the cleanup on
  for everyone who clones the repo, which is the case the two switches exist
  to prevent. A workspace manager writes `CLAUDE.local.md` per worktree, so
  that file is where a workspace speaks for itself.
- **The declaration is checked apart from the rest of the map.** The map's
  existing check refuses a map with a bad field, and a refused map blocks
  verification. A bad declaration is a disk-hygiene problem, so it is
  reported and ignored rather than allowed to stop a run's verification.
- **Shared-branch children leave the cleanup to their parent.** A child that
  shares its branch with the plan never sees hosted CI of its own, and the
  next child builds in the same tree. A cleanup there would make every child
  after the first a cold build. The parent's own successful end is the first
  point where no later child needs the tree.
- **The incremental setting is a command prefix, not a carried environment
  variable.** Letting the suite inherit `CARGO_INCREMENTAL` from the ticking
  shell would carry a developer's own shell value into the suite, so the
  suite's builds would depend on who ran them.
- **Left to the design.** Three questions belong to the technical approach
  and are settled there, not here: the declaration's name and shape in the
  verification map (R1); where in the plan's parent run the cleanup for a
  shared worktree sits (R9); and whether removing a large tree fits the
  engine's 30-second action limit, or detaches or runs as a gate (R12). Two
  more go with them: the cleanup header's name (R4), and whether a fix
  round's own successful end runs the cleanup again.

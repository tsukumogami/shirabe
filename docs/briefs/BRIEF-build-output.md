---
schema: brief/v1
status: Draft
problem: |
  A /work-on run that verifies a compiled-language change leaves its build
  tree in the worktree, and nothing in the workflow ever removes it. Teams
  that run one worker per worktree keep a multi-GiB tree per finished run,
  and the verification suite builds larger trees than it needs to.
outcome: |
  A maintainer says once, in the repo, what its build output is. A workspace
  that turns the cleanup on gets no build tree left by a finished run, a
  developer running the same workflow in their own checkout keeps their warm
  tree, and the suite builds smaller trees without changing anyone's builds.
motivating_context: |
  A fleet of workflow workers on one shared host filled its disk with build
  trees from runs that had already finished: sixteen trees, about 43 GiB,
  none of them owned by a session that was still working. The rules meant
  to prevent it were sentences in each worker's instructions, and one of
  them, a cargo setting exported in the shell, never reached the suite at
  all (tsukumogami/koto#490, tsukumogami/koto#578).
---

# BRIEF: build-output

## Status

Draft

The framing covers the shirabe side (a repo's declaration and an opt-in
cleanup at the end of a run) and one setting on koto's own verification
commands. Removing build trees from kept instances is a separate feature
owned by an instance remover, which reads the declaration this brief frames.

## Problem Statement

When `/work-on` verifies a change in a repo built with a compiled language,
the verification suite writes a build tree into the worktree the run uses.
For a Rust repo that tree is 3 to 9 GiB, and it grows as the same worktree
is rebuilt. Nothing in the workflow removes it. The tree stays until someone
deletes the worktree, and in a setup that keeps worktrees after their worker
stops, that can be weeks.

The cost lands on anyone who runs workers one worktree each. Every finished
run leaves its tree behind, and the trees add up faster than anyone notices:
on one shared host a worker fleet held sixteen of them, about 43 GiB, and not
one belonged to a session that was still working. Free disk decided how many
workers could run at once.

Today the only levers are rules written into each worker's instructions:
clean up at the end, build with incremental compilation off. Nobody enforces
them, and one of them can't work. koto runs a session's commands with a fixed
environment, so a cargo setting exported in the shell that ticks the workflow
never reaches the suite (tsukumogami/koto#578), and the suite builds with
incremental compilation on, which roughly doubles a heavy tree
(tsukumogami/koto#490).

A team that runs the workflow with no instance manager has nothing else. A
team that has one gets a remover that can trim idle trees, but that remover
can only recognise a tree by a marker its build tool happens to write. A
build system that writes no marker leaves a tree nobody can tell apart from
source.

Removing a tree is not free either. The same run reuses its tree between
verification rounds, and a developer running the workflow in their own
checkout expects their warm tree to survive. A cleanup that fires on a line
someone else committed would take that tree away from them.

## User Outcome

A repo maintainer writes down once, in the repo, which paths are its build
output, and that statement is read the same way by everything that needs it.
A fleet operator who wants finished runs to leave nothing turns the cleanup
on for their workspace in one place, and from then on a run that reaches the
end of the workflow leaves no build tree behind, while a run sent back for
more work still finds its tree warm. A developer who runs the same workflow
in their own checkout keeps their tree, because the repo's statement turned
nothing on for them. A worker's verification suite builds a smaller tree,
and the same developer's own cargo builds don't change.

## User Journeys

### A maintainer declares the repo's build output

A koto maintainer notices workers leaving `target/` trees behind. They add
the build output path to the repo's verification configuration in one
commit. Once it merges, every later run reads the declaration from the
default branch, so a branch can't change what its own run removes, and a path
that is tracked, climbs out of the repo or is a symlink is refused by name.
The maintainer's own builds are untouched.

### A fleet operator turns the cleanup on

An operator running a dozen workers on one host is tired of reclaiming disk
by hand. They add one line to their workspace's instructions. From the next
run on, each worker that reaches the end of the workflow with hosted CI green
removes its declared build output and nothing else. A worker that blocked, or
that was sent back to fix CI, keeps its tree. With the line left out, the same
runs leave their trees as they do today.

### A developer runs the workflow in their own checkout

A contributor runs `/work-on` on an issue in their personal clone of a repo
that declares its build output. Their workspace has no cleanup line. The run
finishes and their warm tree is still there for the next change, exactly as
before the repo declared anything.

### An operator sees the suite build a smaller tree

An operator whose workers verify koto changes checks disk after a suite has
run from a clean checkout. The suite's cargo commands built with incremental
compilation off, the way hosted CI already builds, so the tree is at least a
third smaller than before. A koto developer who runs `cargo build` by hand in
their own clone gets the incremental build they always had.

### An instance remover recognises a tree with no marker

A remover that trims idle build trees from kept worktrees comes across a
directory its marker test doesn't recognise. It reads the same declaration
the cleanup reads and treats the declared path as a build tree. Building that
remover is not part of this feature; supplying what it reads is.

## Scope Boundary

**In scope:**

- A place in a repo's existing verification configuration where a maintainer
  declares which paths are build output, read from the default branch as the
  rest of that configuration already is.
- Refusing a declared path that is tracked, leaves the repo, or is a
  symbolic link, each by name.
- An end-of-run cleanup in the work-on workflow that removes only declared
  build output, off by default and turned on per workspace.
- The order the cleanup takes among the other end-of-run steps: after the
  closing step and the handoff brief, last, so a run sent back for more work
  finds its tree warm.
- Incremental compilation turned off in the commands koto's verification
  suite runs, as a change to koto's own configuration, leaving developers'
  hand-run builds alone.
- Settling, or naming as open with what would settle them, the questions
  the feature can't answer yet: the declaration's exact name and shape, where
  the cleanup goes for several plan children that share one worktree,
  whether removing a large tree fits a workflow action's time limit, and any
  debug-information setting.

**Out of scope:**

- Trimming idle build trees from kept instances. That is the instance
  remover's job, in another feature; this one supplies the declaration the
  remover reads and builds no removal of its own outside the workflow.
- Removing whole instances or worktrees when a unit of work is over.
- Placing the cleanup step in the part of the work-on run that the design
  for tsukumogami/shirabe#1230 is changing. The ordering is carried; the exact
  state it sits in waits for that design.
- Building the koto change itself, or running the measured build that decides
  whether a debug-information setting is worth taking. Both are planned items,
  not part of the documents.
- A shared build directory across worktrees, a compile cache, or pruning
  trees by age. Each was weighed and returns little or risks a verdict for the
  wrong branch.
- Preserving files a worker wrote by hand inside a build tree. They go with
  the tree, on purpose.
- Telemetry about what the cleanup removed.

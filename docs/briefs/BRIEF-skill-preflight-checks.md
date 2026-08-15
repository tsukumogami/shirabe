---
schema: brief/v1
status: Accepted
problem: |
  shirabe's skills call host tools -- the shirabe binary, koto, gh, jq,
  git, python3 -- and almost none of those calls says what it needs or
  checks that it is there. When a tool is missing or its surface has
  drifted, runs do not stop. They take a wrong branch and keep going.
outcome: |
  A skill that needs a host tool declares it in one place, a check
  verifies it when the skill loads, and an agent that cannot satisfy it
  reads an instruction that works on the machine it is actually on. A
  machine that already satisfies everything sees nothing at all.
motivating_context: |
  Five filed incidents show shirabe runs going wrong on mismatched
  hosts, and the worst of them succeeded silently: a koto subcommand
  that does not exist, its error filtered away, twelve child workflows
  dispatched against a branch nobody created.
---

# BRIEF: Skill Preflight Checks

## Status

Accepted

The framing here is deliberately not the one this work started from. An
exploration proposed removing prerequisite prose to save context, then
measured that prose at 0.43% of the skill corpus and zero in the
always-loaded descriptions. The saving is not real. What the same
exploration found instead is that the tools those skills call are
mostly unguarded, and this brief frames that.

Three framing details were carried as Open Questions through Draft and
are handed to the downstream PRD rather than answered here. First,
whether the check targets plain absence, version skew, or the presence
of a specific subcommand surface -- every filed incident is skew, and
two artifacts already in the repo disagree, since
`references/fixes/cli-version-preflight.md` argues for probing `--help`
per subcommand while `.tsuku-recipes/shirabe.toml` verifies against
`shirabe --version`. Second, how a declaration expresses a dependency
that six skills need on one execution mode and provably never touch on
another, when at least one of those modes is chosen after the skill has
loaded. Third, what an instruction must contain to count as actionable,
including the case where no install route exists because the host
cannot reach the network.

Phase 4 jury returned all-PASS on the second pass. The first pass
failed on content quality and the seven required changes were applied:
a self-contradicting guard claim narrowed, two counts corrected
downward, a journey that made the check a gate rewritten, and a
mechanism commitment removed from the scope boundary as design
altitude.

## Problem Statement

shirabe's twenty skills reach for six host tools between them: the
`shirabe` binary, `koto`, `gh`, `jq`, `git`, and `python3`. Guards for
them exist, but almost never where a loading agent would see one.
`skills/work-on/SKILL.md` tells the agent to run `koto version` and
check for 0.3.3 or newer -- the only version floor stated at skill
altitude anywhere in the corpus. Presence guards for `shirabe`, `git`,
and `jq` do exist, and several are good ones, but every one of them
lives inside an individual script, several layers below the skill that
called it. A skill body never says what it needs. `shirabe validate` is
invoked from `/scope` and `/charter` at a dozen or so points with no
check that the binary exists; `run-cascade.sh` guards `shirabe` and
`git` carefully and then uses `jq` fifteen times and `python3` once
without guarding either.

That distinction is the gap. A `command -v` buried in a script protects
that script. It does not tell the agent loading `/execute` that the run
it is about to start needs `jq`, and it cannot, because by the time the
script runs the agent has already committed.

The consequence is not that runs fail. It is that they don't.

A missing tool returns exit 127, and 127 is a number nothing in shirabe
has a meaning for. `/charter` and `/scope` both branch on a careful
exit-code table -- 0 clean, 2 violations, 1 tool-error -- and 127 is in
none of the three buckets, so a missing validator reads as a content
violation and blocks a chain for a reason that isn't true. koto's
command gates are worse: koto reports a failed gate as a bare exit code
and discards the command's output, so a missing `gh` is indistinguishable
from red CI and the workflow waits forever on a signal that will never
come. In `shirabe#80` a missing script's 127 routed a staleness gate
through introspection, which is a real code path doing real work for
the wrong reason.

Five incidents are on file, and they sharpen the shape of the problem
rather than confirming the obvious version of it. Not one is a tool
that simply wasn't installed. Every one is a tool present at the wrong
version, or present without the subcommand the skill calls, or a file
that never shipped in the first place. `shirabe#270`: a script used
bash 4 syntax on a machine running the bash 3.2 that macOS has always
shipped, so it exited before emitting anything and the workflow had
nothing to submit. `shirabe#279`: `/execute` called `koto context set`,
a subcommand koto does not have; the caller had filtered stderr to
quiet unrelated noise, so the error went with it, the step reported
success, and twelve children would have been dispatched against a
branch that was never created. That one was caught by hand, on a second
machine, after the fact.

Six mechanisms have grown up around this gap without closing it. There
is prose in one SKILL.md. There is a Requirements section in the README
that a human reads before installing and an agent never reads at all.
There is a `.tsuku.toml` that declares one of the six tools, pins no
version floor, and has `gh` commented out as broken on Linux -- while
`gh` is the most-invoked external binary in the corpus. There are
per-script guards, four separate re-implementations of the same `jq`
check. There is `references/fixes/cli-version-preflight.md`, a hundred
and eight lines written to be exactly this preflight, whose header says
chain skills dereference it on demand and which no skill actually
cites, so it costs nothing and does nothing. And there is CI, which
encodes the bash 3.2 floor in a build matrix and therefore knows the
constraint in a place the runtime cannot ask.

None of them is where an agent looks at the moment it matters, which is
when a skill is loading and about to act.

Two positions already recorded in this repo argue against shapes near
this one, and both are answerable. `DESIGN-shirabe-pattern-v1-ergonomics`
Decision 6 rejected per-skill inline probes and once-per-chain probes in
favour of lazy-loaded prose, reasoning that inlining duplicates a pattern
across seven skills and that surface skew fires per invocation rather
than per chain entry. The lazy-loaded prose it chose is
`cli-version-preflight.md`, and the outcome is on the record: no skill
cites it, so it never loads and the duplication it avoided was traded for
a file that does nothing. The pull request closing `shirabe#270` argued
that a CI matrix beats a runtime guard because "a pattern list only
catches what its author remembered" -- which is right about pattern lists
and does not reach a declaration, because a declaration is written by the
same author, in the same change, as the call it describes. A tool a skill
forgets to declare is a tool it also forgot to call.

## User Outcome

An agent that loads a shirabe skill on a machine that already has what
the skill needs experiences nothing. No output, no delay it would
notice, no reassuring checklist to read past. That is the common case
and it should cost the common case nothing.

An agent that loads the same skill on a machine that is missing
something reads, before it has begun any work, a short statement of
what is not satisfied, what the skill will be unable to do without it,
and one command that will work on that machine. Not a generic install
line: if the host has `tsuku`, the instruction names `tsuku`. If the
tool is sitting in `~/.tsuku/tools/current/` and merely absent from
`PATH`, the instruction says to source the environment file rather than
telling the agent to install something it already has. The agent
decides what to do next -- install it, work around it, tell the person
-- because it now knows enough to choose. Nothing is blocked and
nothing is installed on its behalf.

A shirabe maintainer adding a call to a host tool has one place to
declare that the skill needs it, and the declaration is what the check
reads. The prose and the check cannot drift apart, because there is
only one of them.

## User Journeys

### Cold machine, first workflow

An engineer installs the shirabe plugin on a fresh laptop and runs
`/work-on 214`. koto has never been installed. The skill loads, the
check runs, and before any issue is read the agent has a line naming
koto, the version floor the skill needs, and the install command
appropriate to that laptop. The agent installs koto and proceeds. Today
this journey depends on the agent noticing a paragraph of prose and
choosing to act on it, which an eval exists to assert precisely because
it is not guaranteed.

### Right tool, wrong surface

An engineer runs `/execute` against a plan on a machine where koto is
installed and current enough to look fine. The skill calls a subcommand
that this koto build does not have. The check catches the gap at load
-- the surface the skill needs is not the surface the host provides --
and says so. The agent reads that before it dispatches anything, and
elects to stop and report rather than proceed through a step that will
appear to succeed and send children at a branch that does not exist.
The check does not halt the run; it makes the run's own decision an
informed one, which is the difference between this and the silent
success that shipped in `shirabe#279`.

### Installed, invisible

An engineer's tools are managed by tsuku, so `shirabe` and `koto` both
live under `~/.tsuku/tools/current/` and are on `PATH` only in shells
that have sourced `~/.tsuku/env`. An agent shell that missed the
sourcing runs `/scope`. The check distinguishes "not installed" from
"installed and not on this shell's PATH" and tells the agent to source
the environment file. Without that distinction the agent is told to
reinstall two tools it already has, and it will do it.

### Adding a dependency

A shirabe maintainer adds a `gh api` call to `/release`. They add `gh`
to that skill's declaration, and the check begins verifying it on every
`/release` load. They do not write a paragraph explaining how to
install `gh`, because the instruction is generated from the declaration
and the host. The reviewer can see what the skill now requires by
reading one list rather than grepping the skill's phases for command
names.

### Nothing required, nothing paid

An author runs `/decision` on any machine at all. The skill needs
nothing but a working checkout, its declaration says so, and the check
is silent. Nine of shirabe's twenty skills are in this position, and
the feature has to stay out of their way to be worth having.

## Scope Boundary

### In

- shirabe's own skills -- all twenty, including the five that will
  declare an empty set. Nine need nothing beyond a checkout, but four
  of those nine call `shirabe transition` at a single finalize step,
  so they declare that and nothing else.
- A per-skill declaration of what that skill requires, composable so
  each skill names its own set rather than inheriting a corpus-wide
  list.
- Checks across three categories: whether a binary is present and
  usable, whether auth and configuration state is live (`gh auth
  status` is the case that exists today and is checked at one call site
  out of roughly thirty), and whether the network and sandbox posture
  the skill assumes actually holds.
- Execution when the skill loads, deterministically -- not lazily, not
  on demand, and not dependent on the agent choosing to run it.
- Instructions resolved against the host that is running, covering at
  minimum the presence of a package manager the repo already uses, the
  difference between macOS and Linux where it matters, and the
  installed-but-not-on-PATH case.
- Retiring the prose the check replaces, so the two cannot disagree.

### Out

- A prerequisite contract that repositories adopting shirabe configure
  for their own skills. This feature covers shirabe's skills. A general
  mechanism is a larger surface with a stability commitment attached,
  and nothing has asked for it.
- Blocking or gating a skill on an unsatisfied check. The check informs;
  the agent decides. A skill that needs `gh` on one branch of one phase
  must not be unusable on the branch that doesn't.
- Installing anything automatically. The instruction is printed and the
  agent or the person acts on it.
- Replacing or extending `shirabe validate`. That validates documents.
  This checks hosts, and the two do not overlap.
- Fixing the individual defects the exploration turned up -- the
  unguarded injection in `/inflight`, the fifteen unguarded `jq` calls
  in `run-cascade.sh`, the reference file nothing cites. They are
  evidence for this brief, and whether they are repaired here or
  separately is the PRD's call, not an assumption this framing makes.
- Runtime dependencies of the workflows shirabe orchestrates. If a
  repository's tests need a Go toolchain, that is that repository's
  business.

## References

- `references/fixes/cli-version-preflight.md` -- the prose preflight
  this feature supersedes, and the argument for surface probing over
  version comparison.
- `skills/inflight/SKILL.md` -- the one skill already running a command
  at load through the harness's injection mechanism.
- `skills/execute/scripts/preflight.sh` -- a shipped plugin-side check
  with the opposite exit contract, and the naming collision a downstream
  design has to resolve.
- `docs/briefs/BRIEF-shirabe-check-absorption.md` -- the precedent for
  replacing prose that restates an executable rule, applied there to
  document checks.

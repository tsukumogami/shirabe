---
status: Draft
problem: |
  shirabe's skills call host tools and almost none of those calls says
  what it needs or checks that it is there. The failures this produces
  are not crashes but misroutes: a stale binary that does not recognize
  a flag exits 2, which is the same code `/scope` reads as a document
  content violation, so an author is told to fix prose that is not
  broken. Five incidents are on file and every one is version or
  surface skew rather than a tool that was simply absent.
goals: |
  Every shirabe skill declares the host surface it depends on, a check
  verifies that declaration when the skill loads, and an agent that
  cannot satisfy it reads one instruction that works on the machine it
  is on. A satisfied machine sees nothing. Nothing is blocked and
  nothing is installed automatically.
upstream: docs/briefs/BRIEF-skill-preflight-checks.md
motivating_context: |
  A five-way adversarial bakeoff over what a check should verify
  converged on surface probing and eliminated version floors outright.
  The same bakeoff turned up a defect nobody was looking for: an
  unrecognized flag and a genuine content violation are indistinguishable
  at the exit code `/scope` branches on.
---

# PRD: Skill Preflight Checks

## Status

Draft

## Problem Statement

shirabe's twenty skills call six host tools between them -- the
`shirabe` binary, `koto`, `gh`, `jq`, `git`, and `python3`. A skill
body never states which of them it needs. Guards exist, but they live
inside individual scripts, several layers below the skill that called
them, so they protect the script and tell the loading agent nothing.

The resulting failures are not the ones the shape of the problem
suggests. Across five filed incidents, not one is a tool that was
absent. `shirabe#270` is bash 4 syntax meeting the bash 3.2 that macOS
ships. `shirabe#279` is `/execute` calling `koto context set`, a
subcommand koto does not have -- the call site had filtered stderr to
quiet unrelated noise, so the error went with it, the step reported
success, and twelve children would have been dispatched against a
branch that was never created. `shirabe#80` is a script that never
shipped, whose `command not found` routed a staleness gate through
introspection: a real code path, doing real work, for the wrong reason.
`shirabe#217` records three shirabe binaries coexisting on one disk
with no way to tell which a run binds to.

The precondition for all of it is routine rather than exotic. A skill
ships in the plugin; the binary it calls installs separately. They
drift by construction, and they are drifting right now -- this
worktree runs `plugin.json` at `0.16.1-dev` against an installed
`shirabe v0.16.0`.

One consequence of that drift is worse than a failed run, and it was
found while writing this document rather than in the field. `shirabe
validate --not-a-real-flag` exits 2. `skills/scope/SKILL.md` documents
exit 2 as "violations -- halts the chain and surfaces each
error-severity finding", and reserves exit 1 for "a validator failure
DISTINCT from a content violation". A binary too old to recognize a
flag a skill passes is therefore indistinguishable, at the exact layer
`/scope` branches on, from a document that genuinely fails a check. The
author is shown findings about content that is not broken, and the
bucket carved out for exactly this case is the one the failure does not
land in.

## Goals

- A reader of any skill can see what host surface it depends on without
  grepping its phases for command names.
- An agent learns that a dependency is unsatisfiable before it does
  work that depends on it, rather than partway through.
- A tool present at the wrong surface is reported as a tool problem,
  never as a content problem.
- The common case -- a correctly configured machine -- costs nothing
  and produces no output.
- The declaration and the check cannot drift apart, because the check
  reads the declaration.

## User Stories

- As an engineer running `/work-on` on a fresh laptop, I want to be
  told koto is missing and how to install it on *this* laptop, so that
  I am not left reading a paragraph of prose and guessing.
- As an agent loading `/execute` against a koto that lacks a subcommand
  the workflow calls, I want that named before I dispatch anything, so
  that I do not send twelve children at a branch that was never
  created.
- As an engineer whose tools are managed by tsuku, I want a check that
  knows the difference between "not installed" and "installed but not
  on this shell's PATH", so that I am not told to reinstall two tools I
  already have.
- As a shirabe maintainer adding a `gh api` call to `/release`, I want
  one place to declare that dependency, so that the declaration and the
  check stay in step without my writing install prose.
- As an author running `/decision`, which needs nothing beyond a
  checkout, I want the feature to be invisible.
- As an author whose `/scope` chain halts, I want to be able to tell a
  stale binary from a document defect, so that I do not spend the next
  hour editing prose that was always fine.

## Requirements

### Declaration

- **R1.** Every shirabe skill SHALL carry a declaration of the host
  tools it requires. A skill that requires none SHALL carry an explicit
  empty declaration rather than omitting the declaration entirely, so
  that "declares nothing" and "was never given a declaration" are
  distinguishable.
- **R2.** A declaration SHALL be per-skill and composable: each skill
  names its own set, and no skill inherits another's.
- **R3.** For a tool whose release cadence is coupled to shirabe's own
  -- currently the `shirabe` binary and `koto` -- a declaration entry
  SHALL name the subcommands the skill calls, and for each subcommand
  the flags the skill's own logic depends on. For a tool with an
  independent release cadence -- currently `gh`, `jq`, `git`, and
  `python3` -- an entry SHALL name the tool alone.
- **R4.** R3's split SHALL be recorded as an explicit, stated policy
  with its rationale, not left to emerge from how an author reads
  "the subcommands the skill calls". Without a stated rule, `gh`'s
  roughly ninety call sites would pull it toward a subcommand
  declaration that verifies a surface shirabe does not control and
  cannot track.
- **R5.** A declaration entry SHALL distinguish requirements that hold
  on every run of the skill from requirements that hold only on a named
  execution mode.

### What the check verifies

- **R6.** The check SHALL verify that a declared tool resolves to an
  executable.
- **R7.** The check SHALL verify that each declared subcommand appears
  in the tool's advertised surface.
- **R8.** The check SHALL verify that each declared flag exists on the
  subcommand it is declared against.
- **R9.** The check SHALL NOT parse, compare, or gate on a version
  number of any tool, anywhere. Version floors are removed from the
  requirements surface entirely; `skills/work-on/SKILL.md`'s stated
  `koto >= 0.3.3` floor is retired rather than mechanized.
- **R10.** The check SHALL evaluate only the always-required portion of
  a declaration. Mode-scoped requirements SHALL NOT be reported as
  satisfied or unsatisfied at load, because the mode has not been
  chosen -- `/plan` selects between Phases 3 and 4, after the skill has
  loaded.
- **R11.** Mode-scoped requirements SHALL be verified where the mode is
  actually selected, and the declaration SHALL make that deferral
  visible rather than silent.

### Reporting

- **R12.** On a fully satisfied declaration the check SHALL produce
  zero bytes of output. No checkmark list, no summary line, no timing.
- **R13.** The check SHALL distinguish three postures per entry --
  satisfied, unresolvable, and resolves-but-incomplete -- and SHALL
  further distinguish, within the latter two, the cases whose
  remediation differs:
  - *Unresolvable* splits by whether the tool is absent from the host
    or present at a known location and merely off the current PATH.
    The second is not a fourth coequal posture; it is the case where
    the remedy is to source an environment file rather than install
    anything.
  - *Resolves-but-incomplete* splits by whether the missing surface is
    a subcommand or a flag on a present subcommand. The posture is the
    same in both -- this call will fail as written -- but naming the
    wrong one sends the reader after the wrong thing.

  Collapsing either split reproduces the misdiagnosis the posture
  exists to prevent.
- **R14.** An unsatisfied outcome SHALL be reported as an instruction,
  naming which outcome from R13 holds, what the skill will be unable to
  do, and exactly one command that will work on the host it is running
  on.
- **R15.** Where no install route exists -- a sandboxed host that
  cannot reach the network being the case that motivates this -- the
  report SHALL say so explicitly rather than printing a command that
  will fail.
- **R16.** The report SHALL be complete on first emission. No
  affordance that requires a second, more verbose run is acceptable,
  because the reader gets one pass and cannot ask again.
- **R17.** The check SHALL NOT block, gate, or refuse a skill on an
  unsatisfied declaration. The agent decides what to do next.

### Instruction resolution

- **R18.** The "installed but not on PATH" outcome SHALL be resolved
  before any install route is offered. On a tsuku-managed host both
  `shirabe` and `koto` resolve under `~/.tsuku/tools/current/`, on PATH
  only in shells that sourced `~/.tsuku/env`; an agent told to
  reinstall them will do it.
- **R19.** Install instructions SHALL be resolved against what the host
  actually has rather than enumerated per operating system, delegating
  to a package manager already present where one is.
- **R20.** Instruction resolution SHALL account for combinations known
  not to work. `gh` is currently commented out of `.tsuku.toml` as
  segfaulting on Linux, and that exclusion lives only in a TOML comment
  today.

### Signal integrity

- **R21.** Neither the check's probes nor the skills' own call sites
  SHALL discard a tool's stderr. `shirabe#279` was silent because the
  call site redirected stderr to `/dev/null`, and a preflight added
  while that redirect remains would not have prevented it.
- **R22.** A tool's CLI-surface failure SHALL be distinguishable from
  that tool's own application-level outcomes. `shirabe validate`
  currently returns exit 2 both for an unrecognized flag and for
  document violations, and `/scope` reads 2 as a content verdict.

### Coverage and retirement

- **R23.** All twenty skills SHALL carry a declaration, including the
  five whose declaration is empty.
- **R24.** Prose that the declaration and check supersede SHALL be
  removed in the same change that adds them, so that no skill carries
  both. This covers `skills/work-on/SKILL.md`'s Prerequisites section
  and `references/fixes/cli-version-preflight.md`.
- **R25.** `skills/execute/SKILL.md`'s claim that its preflight
  "confirm[s] `gh` auth is live" SHALL either become true or be
  removed. `skills/execute/scripts/preflight.sh` checks a file path and
  nothing else.

## Acceptance Criteria

- [ ] Every one of the twenty skills has a declaration; the five
      requiring nothing have an explicitly empty one.
- [ ] A declaration naming a tool with an independent release cadence
      names no subcommands; a declaration naming `shirabe` or `koto`
      names subcommands, and names flags wherever the skill's logic
      branches on one.
- [ ] The policy behind that split is written down with its rationale
      in a durable document.
- [ ] With every declared requirement satisfied, loading a skill
      produces zero bytes of check output. Verified by byte count, not
      by inspection.
- [ ] With a declared tool removed from PATH, loading the skill
      produces a report naming the tool, the affected capability, and
      one command; the skill still loads and remains usable.
- [ ] With a declared tool present but a declared subcommand absent
      from its surface, the report names the subcommand and says the
      tool resolved. It does not say the tool is missing.
- [ ] With a declared flag absent from a present subcommand, the report
      names the flag and the subcommand.
- [ ] With a tool present under `~/.tsuku/tools/current/` and absent
      from PATH, the report says to source the environment file and
      does not offer an install command.
- [ ] No requirement, check, or report references a version number.
      Verified by grep over the shipped check surface.
- [ ] A mode-scoped requirement is not reported at load; loading
      `/plan` on a host without `gh` produces no `gh` finding, and the
      multi-pr branch reports it when that mode is selected.
- [ ] On a host with no network and no package manager, the report
      states that no install route is available and names the tool.
- [ ] No probe and no skill call site redirects a tool's stderr to
      `/dev/null`. Verified by grep across `skills/`.
- [ ] A `shirabe validate` invocation that fails on an unrecognized
      flag is distinguishable by its consumer from one that fails on
      document violations.
- [ ] `skills/work-on/SKILL.md` no longer contains a Prerequisites
      section, and no skill contains prose stating a tool version
      floor.
- [ ] `references/fixes/cli-version-preflight.md` is either removed or
      has no remaining claim that a skill dereferences it.
- [ ] `skills/execute/SKILL.md` does not claim a check its preflight
      does not perform.
- [ ] Loading a skill whose declaration is empty produces no output and
      runs no probe.

## Decisions and Trade-offs

The BRIEF deferred three questions. All three are answered here. The
first went through a five-way adversarial bakeoff recorded durably at
`docs/decisions/DECISION-skill-preflight-verification-depth-2026-08-14.md`,
which this section summarizes rather than restates.

**What the check verifies.** Chosen: the tool resolves, each declared
subcommand appears in its advertised surface, and each declared flag
exists on that subcommand -- with no version comparison anywhere.
Alternatives were presence-only, presence plus a version floor, and
per-declaration author-chosen depth. Presence-only was absorbed rather
than rejected: it is exactly this check applied to a declaration that
names no subcommands, which is what an independent-cadence tool gets.
Author-chosen depth collapsed into the same check once its verbs were
dropped, because depth turned out to be determined by tool identity
rather than ever being a free choice.

The version floor was eliminated on evidence rather than preference. No
filed incident needs one. `shirabe#270` was fixed by making the script
portable rather than by gating. `koto context set` -- the call behind
the worst incident on file -- has never existed at any koto version, so
no floor could have caught it at any threshold. And the one floor
shirabe declared had already drifted against itself, reading 0.3.3 in
the README and `skills/work-on/SKILL.md` while a design doc named 0.8.0,
with the data needed to maintain it available the whole time. That is an
authoring-discipline gap, and a floor is not the fix for it.

**Why not pre-classify which flags are risky.** The record settles it.
`--superseded-by` -- the flag `references/fixes/cli-version-preflight.md`
built its argument on -- was added in the same commit that created
`transition` and has never skewed. Meanwhile `validate` accreted
`--coordination-body` and `--merge-gate` in #196, `--pr-body` in #223,
and `--lifecycle-chain` across six PRs from #176 to #271, and `roadmap
populate` gained `--no-issues` in #195. The one flag anyone labelled
risky was not; the ones that moved were never labelled. A skill
therefore declares what its own calls depend on, which requires no
prediction, rather than what someone guesses might drift.

**The answer to PR #278.** That PR chose a CI matrix over a runtime
guard, reasoning that "a pattern list only catches what its author
remembered." The reasoning is sound and does not reach this: a pattern
list is a guess about code someone else will write, while a declaration
is written by the same author, in the same change, as the call it
describes. A tool a skill forgets to declare is a tool it also forgot
to call. R4 exists because that argument only holds while declarations
describe actual calls -- the moment they become a curated risk list,
#278 applies in full.

**Mode-scoped dependencies.** A load-time check cannot honestly report
on a branch not yet taken, so it does not try. Requirements split into
always-required and mode-scoped (R5); the check evaluates the first and
defers the second visibly (R10, R11). The alternative -- reporting
every mode's requirements at load -- would fire `gh` findings on
`/roadmap`'s issueless mode, which is documented as making "no `gh`
call of any kind", and a check that cries wolf on the majority path
gets ignored on the minority one.

**Silence on success.** Required (R12), and not as a matter of taste.
Every "doctor" tool surveyed treats a green checklist as the product
and none can be made quiet; the systems that are silent when healthy
separate the predicate from the reporter. The reader here is an agent,
for which a checkmark list is cost plus a risk that it starts narrating
environment status to the user.

**Known unknown, carried deliberately.** A flag whose *default* changes
while the flag itself persists is invisible to this check at every
depth considered. `roadmap populate --no-issues` did exactly that in
#264. No alternative in the bakeoff reaches it, and this PRD does not
claim to.

## Known Limitations

- Semantic changes behind a stable surface are out of reach, as above.
- The check verifies a declaration, so a call the declaration omits is
  unverified. R24's requirement that superseded prose be deleted in the
  same change is the discipline that keeps declarations honest; nothing
  mechanically proves a declaration is complete.
- Surface probing costs process spawns on skills that declare
  subcommands. The decision record measured the worst case at 6-9 calls
  for `/work-on`, under 100ms, because `shirabe --help` and `koto
  --help` each enumerate their whole command list in one call rather
  than requiring a call per subcommand. Six of twenty skills spawn
  nothing. The figure is an input to design, not a budget this PRD
  sets.
- The check cannot resolve `shirabe#217`'s multi-version binding
  ambiguity. It reports on the binary that resolves; it does not say
  that two others are on disk.

## Out of Scope

- A prerequisite contract that repositories adopting shirabe configure
  for their own skills. This covers shirabe's own skills.
- Blocking or gating a skill on an unsatisfied check (R17).
- Installing anything automatically.
- Replacing or extending `shirabe validate`'s document checks. R22
  concerns how its failures are told apart, not what it validates.
- Version floors, version pinning, and version negotiation of any kind
  (R9).
- Runtime dependencies of the workflows shirabe orchestrates. A
  repository whose tests need a Go toolchain owns that.
- Resolving the multi-version binding ambiguity in `shirabe#217`.

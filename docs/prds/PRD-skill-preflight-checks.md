---
schema: prd/v1
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
  that the choice to proceed or stop is one I make knowingly rather
  than one the run makes for me.
- As an engineer whose tools are managed by tsuku, I want a check that
  knows the difference between "not installed" and "installed but not
  on this shell's PATH", so that I am not told to reinstall two tools I
  already have.
- As a shirabe maintainer adding a `gh api` call to `/release`, I want
  one place to declare that dependency, so that the declaration and the
  check stay in step without my writing install prose.
- As an author running `/decision`, which needs nothing beyond a
  checkout, I want to see no trace of this feature at all, so that the
  cost of adding it falls only on the skills that need it.
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
- **R8.** The check SHALL verify that each declared flag appears in the
  advertised surface of the subcommand it is declared against. R7 and
  R8 read the same thing at two depths: what the installed tool says it
  offers, not what it accepts when actually run.
- **R9.** The check SHALL NOT parse, compare, or gate on a version
  number of any tool, anywhere. Version floors are removed from the
  requirements surface entirely; `skills/work-on/SKILL.md`'s stated
  `koto >= 0.3.3` floor is retired rather than mechanized.
- **R10.** The check SHALL evaluate only the always-required portion of
  a declaration. Mode-scoped requirements SHALL NOT be reported as
  satisfied or unsatisfied at load, because the mode has not been
  chosen -- `/plan` selects between Phases 3 and 4, after the skill has
  loaded.
- **R11.** Mode-scoped requirements SHALL be verified at the point the
  mode is selected. This PRD requires that verification, not merely a
  declaration that marks it deferred; a requirement recorded and never
  checked is the state the feature exists to end.

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
- **R19.** An emitted command SHALL be one that succeeds on the host it
  is emitted on. The report SHALL NOT emit a command whose availability
  it has not established.
- **R20.** Instruction resolution SHALL account for combinations known
  not to work. `gh` is currently commented out of `.tsuku.toml` as
  segfaulting on Linux, and that exclusion lives only in a TOML comment
  today.

### Signal integrity

- **R21.** No verification performed by the check, and no skill call
  site, SHALL discard a tool's diagnostic output. Discarding covers
  redirection to `/dev/null`, capture into a variable that is never
  read, and any other route by which the text reaches nobody.
  `shirabe#279` was silent because the call site redirected stderr to
  `/dev/null`, and a preflight added while that redirect remains would
  not have prevented it.
- **R21a.** No verification and no skill call site SHALL ignore a
  tool's exit status. `shirabe#279` needed both halves to stay silent:
  the discarded stderr and the unchecked exit code. Fixing one leaves
  the incident reproducible.
- **R22.** A tool's CLI-surface failure SHALL be distinguishable from
  that tool's own application-level outcomes, for every consumer that
  branches on those outcomes. `shirabe validate` currently returns exit
  2 both for an unrecognized flag and for document violations. Two
  consumers read that contract and both are in scope:
  `skills/scope/SKILL.md` and `/charter`'s finalization phase. A change
  satisfying only the first leaves `/charter` misdiagnosing a stale
  binary as a document defect.
- **R22a.** A skill invoking a subcommand whose behaviour is governed
  by a defaulted flag SHALL pass that flag explicitly rather than
  relying on the default. `roadmap populate` flipped the default of
  `--no-issues` in #264 while the flag's name and presence were
  unchanged, which no surface probe at any depth can detect. Passing
  the flag is the mitigation available; the check is not.

### Verifiability

- **R25a.** The check SHALL be reachable as a single invocable entry
  point whose combined stdout and stderr can be captured by a test.
  This PRD does not say what that entry point is; it requires that one
  exist, because R12's zero-output rule is otherwise unfalsifiable.
- **R25b.** The filesystem root the check consults when distinguishing
  "absent" from "present but off PATH" SHALL be overridable for
  verification. Without an override, the `~/.tsuku/tools/current/` case
  can only be tested by writing into a developer's real home directory
  and cannot be tested on a host without tsuku at all.
- **R25c.** The existing discards of tool diagnostics in shipped skills
  SHALL be remediated as part of this work, not merely forbidden going
  forward. `skills/execute/koto-templates/execute.md` lines 390 and 409
  carry `koto context get ... 2>/dev/null || echo ...`, which is the
  `shirabe#279` shape still live in the tree. R21 and R21a bind new
  code; this requirement binds the existing instances.

### Coverage and retirement

- **R23.** All twenty skills SHALL carry a declaration, including the
  five whose declaration is empty. Nine skills need nothing beyond a
  checkout, but four of those nine call `shirabe transition` at a
  single finalize step and therefore declare it; five declare nothing
  at all.
- **R24.** Prose that the declaration and check supersede SHALL be
  removed in the same change that adds them, so that no skill carries
  both. This covers `skills/work-on/SKILL.md`'s Prerequisites section
  and `references/fixes/cli-version-preflight.md`.
- **R25.** `skills/execute/SKILL.md`'s claim that its preflight
  "confirm[s] `gh` auth is live" SHALL either become true or be
  removed. `skills/execute/scripts/preflight.sh` checks a file path and
  nothing else.

## Acceptance Criteria

Several criteria below name a state a test must construct. The repo has
precedent for each shape: `skills/execute/scripts/preflight_test.sh`
builds fake roots with `mktemp -d`, `run-cascade_test.sh` injects
`SHIRABE_BIN` stubs and manipulates `PATH`, and
`skills/work-on/evals/fixtures/bin/koto` is a shim that exits 127 under
an environment flag. Stubs that report a chosen surface extend that
last pattern.

### Declaration

- [ ] Every one of the twenty skills has a declaration; the five whose
      declaration is empty carry it explicitly.
- [ ] A skill carrying no declaration is distinguishable from one
      carrying an empty declaration: presenting both to whatever reads
      declarations produces different results.
- [ ] For each skill, every flag appearing in a `shirabe` or `koto`
      command line in that skill's own phases also appears in that
      skill's declaration. Verified by extracting flags from the
      skill's command lines and comparing against the declared set.
- [ ] A declaration naming a tool with an independent release cadence
      names no subcommands.
- [ ] Adding an entry to one skill's declaration leaves every other
      skill's evaluated set unchanged.
- [ ] A declaration distinguishes an always-required entry from a
      mode-scoped one by inspection, without running the check.
- [ ] The policy behind the first-party/independent-cadence split, with
      its rationale, appears in a durable document under `docs/`.

### What the check verifies

- [ ] With a declared tool removed from PATH, the report names the
      tool and the affected capability; the skill still loads and
      remains usable.
- [ ] With a declared tool present but a declared subcommand absent
      from its advertised surface, the report names the subcommand and
      states the tool resolved. It does not report the tool as missing.
- [ ] With a declared flag absent from a present subcommand, the report
      names both the flag and the subcommand.
- [ ] With a tool present under an injected tool-location root and
      absent from PATH, the report says to source the environment file
      and offers no install command. Verified against R25b's override,
      not against a real `$HOME`.
- [ ] Nothing the check executes and nothing it emits performs a
      version comparison or gates on a version. A `--version` call used
      only as a liveness probe, and a pinned URL inside an install
      instruction, both remain permitted. Verified over the enumerated
      set of files the DESIGN names as the check's implementation.
- [ ] Loading `/plan` on a host without `gh` produces no `gh` finding;
      selecting multi-pr mode produces one.
- [ ] A mode-scoped entry is visibly marked as deferred at load, so a
      reader can tell "not required here" from "not checked yet".
- [ ] A skill whose declaration is empty produces no report.

### Reporting

- [ ] With every declared requirement satisfied, invoking the check's
      entry point yields zero bytes across stdout and stderr combined.
      Measured with `wc -c` over a combined capture, not by inspection.
      `skills/execute/scripts/preflight.sh` currently prints a success
      line and must stop doing so.
- [ ] An unsatisfied report contains no affordance directing the reader
      to re-run with a flag, an environment variable, or a verbosity
      setting to obtain more detail.
- [ ] On a host with a package manager present, the emitted command
      delegates to that manager.
- [ ] On Linux, the instruction for a missing `gh` does not route
      through tsuku, and the exclusion driving that is read from a
      machine-readable source rather than a comment in `.tsuku.toml`.
- [ ] On a host with no network and no package manager, the report
      states that no install route is available and names the tool. No
      command is emitted.

### Signal integrity

- [ ] No verification performed by the check, and no non-test call site
      for a tool named in any declaration, discards that tool's
      diagnostic output or ignores its exit status. The scan covers
      `2>/dev/null`, `&>/dev/null`, `2>&1 >/dev/null`, and capture into
      a variable that is never read; it covers `koto-templates/` as
      well as `skills/`. Probes where a non-zero exit is the expected,
      handled outcome and the fallback is not a masked failure are
      exempt and enumerated.
- [ ] `skills/execute/koto-templates/execute.md` lines 390 and 409 no
      longer discard `koto context get`'s diagnostics behind a
      defaulting fallback.
- [ ] `shirabe validate` invoked with an unrecognized flag and `shirabe
      validate` invoked on a violating document are distinguishable by
      a named discriminator, and both `skills/scope/SKILL.md`'s
      documented branch and `/charter`'s finalization branch route the
      first to a tool-error outcome and the second to a violation
      outcome. Asserted for both inputs against both consumers.
- [ ] Every skill invoking a subcommand whose behaviour is governed by
      a defaulted flag passes that flag explicitly. Verified at the
      `roadmap populate` call sites and any peer with the same shape.

### Retirement

- [ ] `skills/work-on/SKILL.md` contains no Prerequisites section, and
      no skill states a tool version floor in prose.
- [ ] `references/fixes/cli-version-preflight.md` is removed, or
      retains no claim that a skill dereferences it.
- [ ] `skills/execute/SKILL.md`'s claim that the preflight will
      "confirm `gh` auth is live" is removed, or
      `skills/execute/scripts/preflight.sh` performs a `gh` auth check.

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
Of the tools surveyed during exploration, those built around a
"doctor" command -- `flutter doctor`, `nix doctor`, `brew doctor`,
`rustup check`, `pre-commit` -- all treat the green checklist as the
product, and pre-commit's quiet-mode request has sat open across three
issues for a decade. The ones that are silent when healthy -- direnv's
`has`, npm `engines`, Cargo's `rust-version`, `go.mod` toolchains --
separate the predicate from the reporter. The reader here is an agent,
for which a checkmark list is cost plus a risk that it starts narrating
environment status to the user.

**What makes an instruction actionable.** Chosen: the report names
which posture holds (R13), what the skill cannot do, and one command
established to work on this host (R14, R19), with PATH-invisibility
resolved before any install route is offered (R18) and an explicit
statement when no route exists (R15). Alternatives were a per-operating
-system install matrix, a single generic install line, and leaving the
no-route case unhandled. The matrix lost on maintenance: exploration
counted roughly 36-40 independently drifting cells against about eleven
strings for host-resolved delegation, and the prior art that maintains
such matrices does so with funded teams. A generic line lost because
the agent will run whatever is printed, so a command that fails on this
host is worse than no command. Leaving the no-route case unhandled lost
because a sandboxed host is the case that motivates the requirement --
the remediation for a missing tool is itself unreachable there, and
saying so is the only honest output.

**Default-flips: mitigated, not merely acknowledged.** A flag whose
default changes while its name persists is invisible to this check at
every depth considered; `roadmap populate --no-issues` did exactly that
in #264. The check cannot reach it, but the caller can: R22a requires
skills to pass mode-selecting flags explicitly rather than relying on a
default. That converts the exposure from undetectable to avoided for
every call site that complies.

## Known Limitations

- A default-flip behind a stable flag name remains undetectable by the
  check itself. R22a avoids it at compliant call sites; a call site
  that ignores R22a is exposed and nothing will say so.
- The check verifies a declaration, so a call the declaration omits is
  unverified. Nothing mechanically proves a declaration complete. The
  acceptance criterion comparing declared flags against flags extracted
  from a skill's own command lines is the closest available check, and
  it catches omissions only for the two first-party tools whose
  declarations name flags at all.
- Surface probing costs process spawns on skills that declare
  subcommands. The decision record measured a worst case of 6-9 calls
  for `/work-on`, under 100ms. The figure is an input to design, not a
  budget this PRD sets, and it assumes a probing strategy the DESIGN is
  free to change.
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

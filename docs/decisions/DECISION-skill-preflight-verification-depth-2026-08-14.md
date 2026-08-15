---
status: Accepted
decision: |
  A shirabe skill-load prerequisite check verifies three things about a host
  tool and nothing else: that the tool resolves to an executable, that every
  subcommand the declaration names appears in the tool's advertised command
  surface, and that every flag the declaration names appears on its
  subcommand's surface. A declaration names a flag only where the call's
  behaviour depends on it. A tool declared with no subcommands is verified for
  presence alone, by the same rule rather than a separate verb. The check never
  parses a version string and never compares one. This resolves the first Open
  Question carried by docs/briefs/BRIEF-skill-preflight-checks.md and supersedes
  references/fixes/cli-version-preflight.md on its central argument, which it
  upholds: surface probing over version comparison.
rationale: |
  Every filed incident is skew rather than absence, and the worst of them is
  reachable only by asking whether the surface a skill calls actually exists --
  `koto context set` has never existed in any koto commit, so no version floor
  could ever have caught shirabe#279. The cost objection that made surface
  probing look expensive was mistaken: `shirabe --help` and `koto --help`
  enumerate their entire command list in one invocation, so verification costs
  one call per tool plus one per nested group plus one per flag-bearing
  subcommand -- 6-9 calls at roughly 2ms in the worst case, under 100ms, with
  six of twenty skills paying nothing. Flags are included because skills and the
  binary ship independently and are skewed in practice, and because `validate`
  and `roadmap populate` demonstrably accreted flags after shipping. Version
  floors are excluded because none is derivable from the working tree, the only
  floor the repo declared has already drifted five minor versions, the `-dev`
  prerelease comparator is a trap with no existing implementation, and PR #278
  already declined a runtime floor for the one floor-natural tool.
---

# DECISION: skill-preflight verification depth

## Status

Accepted

## Context

`docs/briefs/BRIEF-skill-preflight-checks.md` (Accepted) carries three Open
Questions to its downstream PRD. This record answers the first: whether a
skill-load prerequisite check targets plain absence, version skew, or the
presence of a specific subcommand surface.

The question is contested on the record. Two committed artifacts disagree:
`references/fixes/cli-version-preflight.md` argues for probing `--help` per
subcommand, while `.tsuku-recipes/shirabe.toml` verifies against `shirabe
--version`. Two prior positions cut against the obvious shapes. PR #278, closing
shirabe#270, chose a CI matrix over a runtime version guard on the reasoning
that "a pattern list only catches what its author remembered."
`DESIGN-shirabe-pattern-v1-ergonomics` Decision 6 rejected per-skill inline
probes in favour of lazy-loaded prose, which became `cli-version-preflight.md`,
which no skill cites and which therefore never loads.

The constraints are fixed by the BRIEF. The check runs when a skill loads,
deterministically. It is silent when satisfied — load-bearing, because identical
rendered content is deduplicated on re-invocation while differing content
re-appends the whole skill body. It never hard-blocks. When unsatisfied it
prints an instruction that works on the machine actually running.

Five incidents are on file and not one is a tool that simply was not installed.
Four are version or subcommand-surface skew; one is a file that never shipped.
The most severe, shirabe#279, succeeded silently: `/execute` called `koto
context set`, a subcommand koto does not have, the error was filtered away by
`2>/dev/null`, the step reported success, and twelve children would have been
dispatched against a branch nobody created. It was caught by hand, on a second
machine, after the fact.

## Decision

The check verifies three properties of a host tool, and nothing else:

1. **The tool resolves** to an executable on this host.
2. **Every subcommand the declaration names** appears in the tool's advertised
   command surface.
3. **Every flag the declaration names** appears on its subcommand's surface.

A declaration names a flag only where the call's behaviour depends on that flag
— not every flag passed, and explicitly not flags an author guesses might become
skew-prone. Both the flag-level and enumeration advocates independently
estimated this at 5-9 pairs against a corpus of 27, and the bound is descriptive
rather than predictive.

A tool declared with no subcommands is verified for presence alone. This is not
a separate verb or a special case: there is simply nothing to enumerate. It is
how `gh`, `jq`, `git`, `python3`, and `curl` are covered, and it is the complete
and correct answer for them, since not one carries a surface incident anywhere
in the record.

**The check never parses a version string and never compares one.**

The result is three states — **satisfied**, **missing** (the tool does not
resolve), and **present-but-incomplete** (the tool resolves but a declared
subcommand or flag is absent). The prior art's three-state model survives
without a floor, grounded on a directly observed fact rather than a semver
inference, so "install it," "upgrade it," and "source your env file" remain
distinct instructions.

Cost: one call per tool to enumerate its top-level surface, plus one per nested
command group reached into, plus one per subcommand carrying a declared flag.
Worst case in the corpus is `/work-on` at 6-9 calls, roughly 2ms each for
shirabe and koto and 20ms for gh, under 100ms total. Six of twenty skills
declare nothing and pay nothing.

## Options Considered

**Presence plus declared surface including flags (chosen).** Catches
shirabe#279, shirabe#80, and shirabe#217 items 6-7, at close to presence cost,
with no version arithmetic anywhere.

**Presence only (`command -v`).** Not rejected but **absorbed** — it is what the
chosen rule does for a tool declared without subcommands, and it remains the
necessary first step of every deeper check. Insufficient alone: it catches one
of five filed incidents and misses shirabe#279 entirely. Its advocate conceded
this and moved to "presence as the universal floor and the complete answer for
the tools with no surface incident, with surface verification layered on shirabe
and koto."

**Presence plus version floor.** Rejected as a gating verb. Structurally
incapable of catching shirabe#279, since `koto context set` has never existed at
any version — `git log --all -S"ContextCommand::Set"` returns zero commits. No
floor is derivable from the working tree: there is no CHANGELOG, and the
release-notes convention produces feature-named prose with no version index. The
one floor the repo ever declared has already drifted, with `README.md` and
`skills/work-on/SKILL.md` saying koto >= 0.3.3 while
`DESIGN-work-on-koto-unification.md` says v0.8.0 or later. The `-dev` prerelease
comparator is a trap — strict semver sorts `0.12.1-dev` below `0.12.1` while a
naive numeric triple sorts it above — with no existing implementation in the
repo to model on. And PR #278 already declined a runtime floor for `bash`, the
one floor-natural tool, in favour of eliminating the dependency; that fix
succeeded, so a `bash >= 4.0` floor would today be actively wrong.

Its advocate did establish, against the original research, that GitHub Release
bodies are structured, categorized, and issue-linked, and demonstrated deriving
a real floor (`transition` → #146 → `ceb04fbf` → v0.9.0, corroborated three
ways). That correction stands. It does not rescue the floor, because the koto
floor drifted while that data was available the whole time — the rot was never a
data-availability problem. The finding survives as a remediation improvement: a
detected gap can point somewhere concrete rather than saying "upgrade" with no
target.

**Presence plus per-subcommand-and-flag probe as originally framed.** Adopted
for its scope rule and rejected only in its cost assumption. The original
framing assumed one subprocess per declared subcommand; enumeration makes that
unnecessary for the subcommand layer.

**Author-declared verification depth (presence, surface, or floor per
declaration).** Withdrawn by its own advocate. Once the floor verb is dropped, a
tool declared with no subcommands yields presence by construction, so the depth
verb never varies from what the tool dictates — it adds vocabulary without
adding expressiveness, and a richer vocabulary is more to get wrong. Its finding
that the corpus partitions cleanly by tool survives as independent corroboration
of the chosen rule.

## The PR #278 objection

PR #278's reasoning is the prior position this feature has to argue past, so it
is recorded and answered directly.

The objection lands on prediction, and it lands hard. The one flag this repo
pre-labeled as skew-risky, `--superseded-by`, was added in the same commit that
created `transition` and never skewed. The flags that actually accreted after
their subcommand shipped — `validate` gaining `--coordination-body` and
`--merge-gate` (#196) and `--pr-body` (#223) onto a subcommand shipped in #139,
`roadmap populate` gaining `--no-issues` (#195) onto a subcommand shipped in
#144 — were named as a risk nowhere. Any rule asking authors to flag skew-prone
flags in advance is exactly the pattern list #278 discredited, and this repo's
authors have not performed that prediction correctly even once.

The objection does not reach the declaration adopted here, and the distinction
is **prediction versus description**. A pattern list, a version floor, and a
"flags I think are risky" list are all predictions about the future; each can go
wrong while the code around it stays correct, which is how they rot silently. A
declaration of what a call depends on is a description of the present call,
written by the same author in the same change. It cannot go stale while the call
stays correct, because the author cannot get the description wrong without also
getting the call wrong.

That defence has a limit worth recording rather than smoothing over.
`skills/execute/scripts/run-cascade.sh` calls `jq` nineteen times with zero
guards, and `skills/inflight/SKILL.md` invokes `shirabe work-summary render`
with no declaration at all. Authors here demonstrably do forget. The claim is
not that description is immune to omission — it is that description does not
silently drift the way a prediction does, which is the specific failure #278
named.

## Consequences

shirabe#279 becomes detectable at load, cheaply and silently. The
version-parsing surface — seven mutually incompatible `--version` formats, the
`-dev` precedence trap, the `0.0.0` local-build fallback whose documented
`shirabe-unknown` sentinel does not match `build.rs` — is removed from the
problem rather than solved.

`references/fixes/cli-version-preflight.md` is superseded, and wins its central
argument. Its documented per-subcommand sed-edit fallback remains the answer to
a detected gap, since no version-to-feature map exists to name an upgrade
target.

Declarations become the place a reviewer reads to see what a skill requires, and
maintaining them is real ongoing work. The flag bound is a judgment nothing
enforces: drifting toward "every flag passed" raises cost without benefit, and
drifting toward none reopens the #279 class one level down.

**Flag skew is routine, not rare, and that is a finding rather than an
assumption.** Skills and the binary are versioned and shipped independently, and
by the workspace's own `<next>-dev` release convention the plugin bundle is
ahead of the last tagged release the moment work resumes. Measured while
deciding this: the installed binary reported `shirabe v0.16.0` while the plugin
bundles on disk were `0.1.0`, `0.15.1-dev`, and `0.16.1-dev`. shirabe#217
reports the same shape from the other side.

### Requirements this decision surfaces but does not answer

- **Neither the check's probes nor any skill call site may discard stderr or
  ignore an exit code.** shirabe#279 was silent purely because of `2>/dev/null`
  plus an unchecked exit status; clap reports an unknown flag and an unknown
  subcommand identically (exit 2, clear message). A preflight whose own probe
  redirects stderr to `/dev/null` reproduces the defect it exists to prevent.
- **A tool carrying an application-level exit-code contract needs its
  CLI-surface-failure signal kept structurally distinct from it.** `/charter`
  (`references/phases/phase-finalization.md:165-198`) and `/scope`
  (`SKILL.md:615-637`) both branch on 0 clean, 2 violations, 1 tool-error. A
  clap usage error exits 2 with no `shirabe-validate/v1` envelope on stdout, so
  it is read as a content violation and sends the author to fix a document that
  is not wrong — while exit 1, reserved explicitly as "DISTINCT from a content
  violation," is not the code a surface failure returns.
- **PATH-invisibility is orthogonal to this axis entirely.** Distinguishing "not
  installed" from "installed under `~/.tsuku/tools/current/` or `~/.shirabe/bin`
  but not on this shell's PATH" cannot be done by any option considered, and the
  BRIEF's "Installed, invisible" journey requires it.
- **Multi-version binding ambiguity is the precondition for flag skew.**
  shirabe#217 reports three shirabe copies on disk with the reporter unable to
  say which one an invocation binds to. Which binary a workspace-managed tool
  call resolves to should not be ambiguous; resolving that shrinks the problem
  this decision addresses.

### Known blind spot

**Semantic drift behind a stable surface is caught by nothing.** `roadmap
populate --no-issues` kept its name in #264 and flipped its default, so every
probe of every depth passes unchanged while behaviour differs. This is failure
shape 2 in `cli-version-preflight.md`'s own taxonomy and it sits outside the
presence/surface/floor property space entirely. The mitigation is authoring
discipline — always pass the mode flag explicitly, never rely on a default — not
verification.

## References

- `docs/briefs/BRIEF-skill-preflight-checks.md` — the accepted upstream whose
  first Open Question this record answers.
- `references/fixes/cli-version-preflight.md` — the prose preflight superseded
  here, and the source of the surface-over-version argument this record upholds.
- `docs/designs/current/DESIGN-shirabe-pattern-v1-ergonomics.md` — Decision 6,
  which resolved R30 as lazy-loaded prose; this record supersedes that
  resolution's loading model, not its analysis.
- `.github/workflows/check-plan-scripts.yml` — lines 25-38 carry the PR #278
  reasoning answered above.
- `docs/designs/current/DESIGN-reusable-release-system.md` — the `<next>-dev`
  convention that makes skill-newer-than-binary the routine state.

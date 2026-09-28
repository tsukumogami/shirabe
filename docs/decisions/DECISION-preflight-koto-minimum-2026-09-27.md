---
status: Accepted
decision: |
  The skill-load prerequisite check compares one version: koto's, against
  shirabe's koto minimum. When a skill's in-scope declaration names koto and
  koto resolves, the check runs `koto version` once through the same bounded
  probe that reads `--help`, reads the minimum from the FLOOR line of
  scripts/assert-koto-floor.sh (the one place it is defined, shipped in the
  plugin), and reports a koto below it with a block telling the reader to
  upgrade before running the skill. A `koto version` it can't read is reported
  as not established. Like every preflight block, it reports and does not stop
  the skill. This supersedes, for koto only, the clause of
  docs/decisions/DECISION-skill-preflight-verification-depth-2026-08-14.md
  (and PRD-skill-preflight-checks R9) that the check never parses or compares a
  version. Surface probing stays the rule for every other tool and for koto's
  own surface, and requires.tsv still carries no version.
rationale: |
  Since #457, shirabe's skills pass --no-cleanup on every tick,
  including on children /execute materializes, and that is correct only from
  koto 0.14.0 on. On an
  older koto the same flag withholds a child's result from its parent, whose
  gate reports the batch complete with the result missing: every call succeeds
  and the run's outcome is wrong. That is semantic drift behind a stable
  surface, the earlier decision's own named blind spot, and no `--help` probe
  can see it. The earlier decision excluded version floors for four reasons.
  The first two no longer hold, because the minimum is now one value in the
  tree and a consistency test fails when a restatement drifts. The third, the
  -dev comparator, is bounded by how koto stamps its builds, and the builds the
  check can't judge are named below. The fourth, PR #278's choice of removing
  a dependency and testing in CI over a runtime floor, isn't open here: shirabe
  can't remove its dependency on koto, and CI doesn't reach a user's machine.
  Nor is this floor a prediction: it describes the release CI installs and runs
  every koto-backed suite on, written in the change that adopts the behaviour.
---

# DECISION: the preflight checks koto's minimum

## Status

Accepted on 2026-09-27.

## Context

`DECISION-skill-preflight-verification-depth-2026-08-14.md` settled what the
skill-load check verifies: that a tool resolves, and that the subcommands and
flags a skill declares appear in its advertised surface. It also said the check
never parses or compares a version. `docs/prds/PRD-skill-preflight-checks.md`
R9 says the same as a requirement, and `references/tool-declaration-policy.md`
repeats it under "No version, ever".

shirabe#439 (PR #457) moved shirabe's koto minimum to 0.14.0. That release
keeps a session that reaches a failure terminal, and delivers a child's result
to its parent whether or not the child's tick carried `--no-cleanup`. shirabe
relies on both: every `koto next` in `/work-on` carries the flag, root or
child. On koto 0.13.0 a `/work-on` child that does so withholds its result from
`/execute`'s `children-complete` gate, which then reports the batch complete
without it. Nothing errors.

Nothing at load catches that. The commands `/work-on` calls exist on 0.13.0
with the same flags, so the surface probe passes. The minimum is stated in the
README and enforced in CI, but a user's machine never runs CI.

The record relies on four facts #457 established (05d672c). shirabe's koto
minimum is 0.14.0. Every `koto next` in `/work-on` carries `--no-cleanup`, root
or child; before #457, `skills/work-on/scripts/session-role.sh` kept the flag
off a child's ticks, so #457 is what makes shirabe depend on 0.14.0's
behaviour. The minimum is the release CI installs exactly and runs every
koto-backed suite on. `scripts/koto-minimum-consistency_test.sh` guards the
restatements of the minimum.

## Decision

When a skill's in-scope records (the `always` records at load, the
`mode:<name>` records on a `--mode` run) name koto and koto resolves, the check
runs `koto version` once and compares it with the minimum.

- **The minimum.** The `FLOOR` line of `scripts/assert-koto-floor.sh`, read
  from the plugin root the entry point has already validated, never from `$PWD`
  and never from `KOTO_FLOOR` in the environment. The plugin's marketplace
  entry ships the whole repository (`"source": "./"`, no pruning step), so the
  file is in the installed payload beside `scripts/skill-preflight.sh`. The line's
  shape is a runtime contract, and `assert-koto-floor.sh`'s header says so.
  There is no second copy of the value, and nothing is added to
  `requires.tsv`.
- **The call.** `koto version` runs through `preflight_probe_version`, whose
  argv is fixed, over the same bounded runner as every `--help` probe: stdin
  closed, stderr discarded, the same wall-clock budget and output cap.
  `preflight-probe_test.sh` asserts that every call the check makes ends in
  `--help` except that one.
- **The parse.** The first line must start `koto `, an optional `v`, then
  `MAJOR.MINOR.PATCH` with each component one to six digits. Anything after the
  third component (a `-dev+<hash>` suffix, the build hash and date) is dropped.
  The comparison is numeric, field by field.
- **The blocks.** Below the minimum, the check reports "prerequisite not met":
  the installed version, that shirabe's skills are tested on the minimum and
  later, that on an older koto a run can finish with a wrong result and no
  error, to upgrade before running the skill, and the upgrade route. When
  `koto version` ran and printed no readable version, or printed nothing, the
  check reports "prerequisite could not be checked" in the shape of the
  existing inconclusive block. The text takes both numbers from the values
  read, so moving the minimum needs no edit here. Both blocks are rendered by
  `scripts/lib/preflight-report.sh`.
- **Report, not refusal.** Like every preflight block, these land in the skill
  body and the skill loads. The absent-tool block works the same way, but an
  absent tool fails loudly on its first call and this failure doesn't, so the
  block says the failure is silent and says to upgrade first.
- **Once per run.** Several koto records produce one comparison. A `--mode` run
  skips it when the skill's `always` records name koto, since the load-time run
  made it.

What stays as it was: surface probing for every tool, koto included; no version
for any other tool; no version in any declaration.

A session begun on koto 0.13.0 keeps working after an upgrade to 0.14.0, so
upgrading when the block appears doesn't cost a run already in progress. That
was checked by hand on 2026-09-27, not by a test: a three-state template's
session was created and ticked once with koto 0.13.0 (b4db451), then ticked to
its terminal with koto 0.14.0 (62fec27) in the same home, and the second tick
succeeded. Sessions from before 0.13.0 don't carry across, as the README's
upgrade section says.

## The four reasons, answered

The earlier decision rejected version floors for four reasons. In its order:

**No floor is derivable from the working tree.** No longer true. The minimum is
`FLOOR` in `scripts/assert-koto-floor.sh`, the release shirabe's CI installs
exactly and runs every koto-backed suite on. The check reads that value.

**The one declared floor had drifted.** That drift is now tested.
`scripts/koto-minimum-consistency_test.sh` fails when any restatement of the
minimum (README, guides, requires.tsv comments, the retention reference) names
another version, and a simulated move of the minimum makes it list every file
to update.

**The `-dev` comparator is a trap.** Bounded, and the builds the check can't
judge are named. Released koto (v0.14.0's `build.rs`) stamps its version from
git:

- an exact tag, such as a release build: `0.14.0`, which compares as itself;
- a build ahead of tag `v0.14.0`: `0.14.0-dev+<hash>`, which compares as
  0.14.0. That is right, since the build carries everything 0.14.0 does;
- a build with no tag visible (`cargo install --git`, a shallow clone):
  `dev+<hash>` with no number at all. The check can't read it and reports the
  comparison as not established.

Two consequences follow. A koto `main` build that already has a new minimum's
behaviour, but predates that release's tag, stamps the previous tag
(`0.13.0-dev+<hash>` before v0.14.0) and is told to upgrade: a false positive
on the safe side. A pre-release tag such as `v0.14.0-rc.1` contains a `-`, so
`build.rs` stamps it `0.14.0-dev+<hash>` and it passes as 0.14.0.

koto's unreleased `main` changes the no-tag case to Cargo.toml's version, which
is `X.Y.Z` at a release and `X.Y.(Z+1)-dev` between releases. Once a release
carries that, a between-releases untagged build reads as the next version and
can pass a minimum set to that version before the release exists. That build
is a developer's choice to run unreleased koto, and the check's job is the
released path.

**PR #278 declined a runtime floor.** What #278 declined was a runtime floor
for `bash`, the one floor-natural tool at the time, in favour of removing the
dependency and testing on a CI matrix; that fix worked, so a `bash` floor would
now be wrong. Neither route is open here. The behaviour this guards is koto's,
and shirabe can't remove its dependency on koto. The CI route is already in
place (check-koto-entry-floor.yml runs every koto-backed suite on exactly the
minimum), and it doesn't reach a user's machine, which is where the wrong
result happens.

The earlier record's broader objection to floors was that a floor is a
prediction: a guess about the future that goes
stale while the code around it stays correct, as the pattern list #278
discredited did. This floor is a description. It names the release CI installs
and runs every koto-backed suite on, it was written in the change that adopted
the behaviour it guards, and a test fails when any restatement of it drifts.
It can't go stale while the code stays correct, because moving the code to
depend on a newer koto means moving the one value CI installs.

The earlier record also named, as a known blind spot, "semantic drift behind a
stable surface", caught by nothing, with authoring discipline as the only
mitigation. The withheld-result failure is exactly that shape. This check
closes the blind spot for the one case where the drift is tied to a koto
release and a floor already exists to name it.

## Known limits

- **An untagged released koto build can't be judged.** It prints `dev+<hash>`,
  and the check reports the comparison as not established rather than passing
  or failing it. The ordinary install path doesn't land here:
  check-koto-entry-floor.yml installs the floor release through tsuku and fails
  unless `koto version` reads exactly that release, so a tsuku-installed
  release prints a readable version.
- **A timed-out or over-cap `koto version` is reported, not compared.** The
  check prints the could-not-be-checked block naming the bound it hit, and
  claims the probe's "inconclusive koto" slot so the surface probe of the same
  binary's `--help` doesn't print a second block about it. `koto version` is the
  first call a load makes to koto, so on a cold host it is the one most likely
  to reach the budget.
- **An unreadable minimum is silent.** A reader can't act on a reshaped FLOOR
  line, and CI fails when the line can't be read.
- **A between-releases build under koto's newer stamping can pass early**, as
  above.
- **A `--mode` run trusts load time.** If koto was absent or off PATH at load
  and was fixed mid-session, the `--mode` run skips the comparison. The next
  load makes it.
- **Only koto.** Any other tool whose required behaviour has no surface is
  still outside what the check can see. A second exception needs a record of
  its own.

## Consequences

Superseded for koto, with a pointer to this record:
`DECISION-skill-preflight-verification-depth-2026-08-14.md` (its Status),
`docs/prds/PRD-skill-preflight-checks.md` R9,
`docs/designs/current/DESIGN-skill-preflight-checks.md` (its security
section, which now names the one parsing surface and its bounds), and
`references/tool-declaration-policy.md`, whose "No version, ever" section
becomes the one exception and whose "A declaration describes" section points
here.

`scripts/lib/preflight-minimum.sh` holds the comparison and the hook,
`scripts/lib/preflight-report.sh` the two blocks, and
`scripts/lib/preflight-minimum_test.sh` tests both sides of a fixture minimum
plus the tree's own FLOOR line.

Moving the minimum stays a one-value change in `assert-koto-floor.sh`. The
load-time check and its text follow it with no edit.

## References

- `docs/decisions/DECISION-skill-preflight-verification-depth-2026-08-14.md`
- `docs/prds/PRD-skill-preflight-checks.md`
- `docs/designs/current/DESIGN-skill-preflight-checks.md`
- `references/koto-session-retention.md`
- `references/tool-declaration-policy.md`
- `scripts/assert-koto-floor.sh`
- shirabe#439, tsukumogami/koto#240, tsukumogami/koto#259

---
status: Proposed
decision: |
  The skill-load prerequisite check compares one version: koto's, against
  shirabe's koto minimum. When a skill's in-scope declaration names koto and
  koto resolves, the check runs `koto version` once through the same bounded
  probe that reads `--help`, reads the minimum from scripts/assert-koto-floor.sh
  (the one place it is defined), and prints a named block telling the reader to
  upgrade koto when the installed version is below it. This supersedes, for
  koto only, the clause of
  docs/decisions/DECISION-skill-preflight-verification-depth-2026-08-14.md that
  says the check never parses or compares a version. Surface probing stays the
  rule for every other tool, and requires.tsv still carries no version.
rationale: |
  From koto 0.14.0 on, shirabe's skills pass --no-cleanup on every tick,
  including on children /execute materializes. On a koto below that release
  the same flag withholds a child's result from its parent: the parent's gate
  reports the batch complete with the result missing, and the run carries on
  without it. That is a silent wrong outcome, and it depends on behaviour, not
  surface, so no amount of `--help` reading can see it. The earlier decision
  excluded version floors for four reasons. Two no longer hold: the minimum is
  now one value in the working tree, and a consistency test fails when any
  restatement of it drifts. The third, the -dev comparator, is bounded by how
  koto stamps its builds. The fourth, the prior refusal of a runtime floor, is
  the one this record reverses, because the failure it now guards against is
  silent rather than loud.
---

# DECISION: the preflight checks koto's minimum

## Status

Proposed

## Context

`DECISION-skill-preflight-verification-depth-2026-08-14.md` settled what the
skill-load check verifies: that a tool resolves, and that the subcommands and
flags a skill declares appear in its advertised surface. It also said the check
never parses or compares a version, and
`references/tool-declaration-policy.md` repeats that under "No version, ever".

shirabe#439 moved shirabe's koto minimum to 0.14.0. That release keeps a
session that reaches a failure terminal, and delivers a child's result to its
parent whether or not the child's tick carried `--no-cleanup`. shirabe now
relies on both: every `koto next` in `/work-on` carries the flag, root or
child. On koto 0.13.0 a `/work-on` child that does so withholds its result from
`/execute`'s `children-complete` gate, which then reports the batch complete
without it.

Nothing at load catches that. The commands `/work-on` calls exist on 0.13.0
with the same flags, so the surface probe passes. The minimum is stated in the
README and enforced in CI, but a user's machine never runs CI.

## Decision

When a skill's in-scope records (the `always` records at load, the
`mode:<name>` records on a `--mode` run) name koto and koto resolves, the check
runs `koto version` once and compares it with the minimum:

- The minimum is read from `scripts/assert-koto-floor.sh` with the same `sed`
  CI uses. There is no second copy, and nothing is added to `requires.tsv`.
- `koto version` runs through `preflight_probe_run`, the bounded call behind
  every `--help` probe: stdin closed, stderr discarded, the same wall-clock
  budget and output cap.
- The version is the `MAJOR.MINOR.PATCH` after `koto` (an optional `v`
  allowed). Any pre-release or build suffix is dropped before comparing, as
  `assert-koto-floor.sh` drops it.
- Below the minimum, the check prints one block that names both versions and
  gives the upgrade command from the route table. At or above it, the check
  prints nothing.
- A `--mode` run skips the comparison when the skill's `always` records already
  name koto, since the load-time run made it, and a repeated block is what the
  zero-byte rule forbids.

What stays as it was: surface probing for every tool, koto included; no version
for any other tool; no version in any declaration.

## The four reasons, answered

The earlier decision rejected version floors for four reasons. In its order:

**No floor is derivable from the working tree.** No longer true. The minimum is
`FLOOR` in `scripts/assert-koto-floor.sh`, the release shirabe's CI installs
exactly and runs every koto-backed suite on. The check reads that value.

**The one declared floor had drifted.** That drift is now tested. Each
restatement of the minimum (README, guides, requires.tsv comments, the retention
reference) is checked by `scripts/koto-minimum-consistency_test.sh`, which fails
when one names another version, and a simulated move of the minimum makes it
list every file to update.

**The `-dev` comparator is a trap.** Bounded rather than solved. Dropping the
suffix makes `0.14.1-dev` compare as 0.14.1. koto stamps its builds from git:
an exact tag gives `0.14.0`, and a build ahead of tag v0.14.0 gives
`0.14.0-dev+<hash>`, which is right, since it carries everything 0.14.0 does. The
one mis-ordering is a build with no tag visible, such as a `cargo install
--git` between releases. It takes Cargo.toml's version, `0.14.1-dev`, and passes a
0.14.1 minimum without everything 0.14.1 brings. That build is a developer's
choice to run unreleased koto, and the check's job is the released path.

**PR #278 declined a runtime floor.** This is the reason this record reverses.
#278 chose a CI matrix over a runtime guard, and the earlier decision upheld
that because a missing surface fails loudly: a call to a subcommand that isn't
there exits with an error. The failure here doesn't. On a koto below the
minimum every call succeeds, and the result that should reach `/execute` never
does. A loud failure can be left to the call. A silent wrong outcome has to be
caught before the run starts, and a load-time version comparison is the only
check that can see it.

## Known limits

- **An unreadable version is silent.** If `koto version` times out, prints more
  than the cap, or prints no `MAJOR.MINOR.PATCH`, or if the minimum can't be read
  from `assert-koto-floor.sh`, the check prints nothing. That is the probe's
  posture for a `--help` it couldn't read: a check that couldn't read the
  version is not evidence that it's low.
- **A between-releases koto build passes early**, as above.
- **Only koto.** Any other tool whose required behaviour has no surface is still
  outside what the check can see. Extending this to another tool takes a record
  of its own.

## Consequences

`references/tool-declaration-policy.md` replaces "No version, ever" with the one
exception and points here. The earlier decision stays Accepted with a note that
this record supersedes its version clause for koto. `scripts/lib/preflight-minimum.sh`
holds the comparison and `scripts/lib/preflight-minimum_test.sh` tests it on both
sides of whatever minimum the tree carries.

Moving the minimum stays a one-value change in `assert-koto-floor.sh`. The
load-time check follows it with no edit.

## References

- `docs/decisions/DECISION-skill-preflight-verification-depth-2026-08-14.md`
- `references/koto-session-retention.md`
- `references/tool-declaration-policy.md`
- `scripts/assert-koto-floor.sh`
- shirabe#439, tsukumogami/koto#240, tsukumogami/koto#259

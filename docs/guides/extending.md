# Extending shirabe's skills

You can layer your project's own rules onto shirabe's skills without forking
them. This guide is the contract for doing that: which extension points are
stable, what counts as a breaking change to them, and where such a change is
announced. The reasoning behind the mechanism is in
[`DESIGN-skill-extensibility.md`](../designs/current/DESIGN-skill-extensibility.md).

## Two layers

**CLAUDE.md headers** carry project-wide settings that apply to every skill:
whether the repository is public, its default planning scope, its label names.
Skills read a small set of documented headers from your CLAUDE.md chain.

**Extension files** carry rules for one skill. A file at
`.claude/shirabe-extensions/<name>.md` is pulled into the `<name>` skill each
time it runs, and nowhere else. Use it for things that don't belong in every
conversation: a triage step your project runs before `/work-on` starts, the
checks `/release` must run, label routing that only `/plan` cares about.

shirabe uses the same mechanism on itself. Its own
[`.claude/shirabe-extensions/`](../../.claude/shirabe-extensions/) directory
holds the `release.md` and `work-on.md` files its skills load in this
repository.

## The stable slots

Every extensible skill opens its SKILL.md with two include lines, right after
the frontmatter and the skill's preflight line:

```markdown
@.claude/shirabe-extensions/<name>.md
@.claude/shirabe-extensions/<name>.local.md
```

`<name>` is the skill's `name:` from its frontmatter. These two lines are the
stable public interface of the extension mechanism. Claude Code resolves them
from your project root before the model reads the skill, so loading costs no
tool calls and works however shirabe is installed. A file that doesn't exist is
skipped.

These skills carry the slots today:

| Skill | Extension file |
|-------|----------------|
| `/brief` | `.claude/shirabe-extensions/brief.md` |
| `/decision` | `.claude/shirabe-extensions/decision.md` |
| `/design` | `.claude/shirabe-extensions/design.md` |
| `/explore` | `.claude/shirabe-extensions/explore.md` |
| `/plan` | `.claude/shirabe-extensions/plan.md` |
| `/prd` | `.claude/shirabe-extensions/prd.md` |
| `/release` | `.claude/shirabe-extensions/release.md` |
| `/roadmap` | `.claude/shirabe-extensions/roadmap.md` |
| `/strategy` | `.claude/shirabe-extensions/strategy.md` |
| `/vision` | `.claude/shirabe-extensions/vision.md` |
| `/work-on` | `.claude/shirabe-extensions/work-on.md` |

Each one also takes the matching `.local.md` file. The other skills (`/scope`,
`/charter`, `/deliver`, `/execute`, `/coordinate`, `/comp`, `/review-plan`,
`/inflight`, `/writing-style` and the two content-governance skills) have no
slot, so a file named after one of them is never loaded.

The `.local.md` variant is for personal, machine-level additions. Keep it out
of version control (a `*.local.md` line in `.gitignore` does it); the committed
`.md` file is the one your team shares.

## The CLAUDE.md headers

These are the headers you're most likely to set. Each is a level-2 heading in
your CLAUDE.md, and each is optional.

| Header | Values | Read by | When absent |
|--------|--------|---------|-------------|
| `## Repo Visibility:` | `Public` or `Private` | The skills that write documents, issues or pull requests, to choose their content-governance rules | Inferred from the repository path (`public/` or `private/`), otherwise `Private`; `/charter` goes straight to `Private` |
| `## Default Scope:` | `Strategic` or `Tactical` | `/explore`, `/plan`, `/design` (`/design` also accepts `## Planning Context:`) | `Tactical` for `/explore` and `/plan` |
| `## Label Vocabulary` | Free-form prose or a list of your issue labels | `/design`, `/explore`, `/plan`, `/prd`, `/work-on` | The skills run without project-specific labels |

`/explore` and `/plan` also take `--strategic` or `--tactical`, which overrides
`## Default Scope:` for one run. `/work-on` reads label names and routing
messages from its extension file as well as from `## Label Vocabulary`.

Skills read other CLAUDE.md headers too, such as `## Execution Mode:` and
`## Delivery Preference:`, each described in the skill that reads it. The
contract covers those as well: renaming any header a skill reads is a breaking
change (see below).

Some skills also read a fixed format inside their extension file or a file
next to it. `/release` reads the `## Release checks`, `## Release assets` and
`## After release` sections of `release.md` and `release.local.md`, and
`/work-on` reads `verification-map.json` and `hosted-ci.json` from the same
directory. Those formats belong to the skill that reads them
(`skills/release/SKILL.md`, `skills/work-on/references/verification-map.md`,
`skills/work-on/references/phases/phase-6-pr.md`) and sit outside this
contract and get none of the breaking-change treatment described below; read
the skill's own documentation when you upgrade.

## What counts as a breaking change

A shirabe change breaks extension authors when it does any of these:

1. Removes an `@` slot line from a skill's SKILL.md.
2. Renames a phase in a skill's workflow overview, so an extension file that
   names the phase no longer matches it.
3. Renames a CLAUDE.md header that a skill reads.

Everything else is compatible: rewording a skill's instructions, refactoring its
phase files, adding phases, changing support files, and adding a slot to a skill
that didn't have one.

## How a breaking change is announced

shirabe has no separate changelog. Its changes are announced in the notes on
each [GitHub release](https://github.com/tsukumogami/shirabe/releases), which
are drafted from the commits in that release and call out breaking changes
prominently. shirabe's practice is to announce a change in one of the three
categories above there as a breaking change, the way the v0.16.0 notes carry a
`## Breaking` section. When a change needs more than a line of notes, a
migration guide that says what to do goes under [`docs/guides/`](./), the
repository's release-notes directory;
[`RELEASE-NOTES-populate-issueless-default.md`](RELEASE-NOTES-populate-issueless-default.md)
is an example.

This is a review convention, not something a tool enforces: nothing in CI
detects a renamed slot or header. Version numbers won't tell you either.
shirabe is still at 0.x, and a breaking change doesn't always move the major
version.

To hear about a breaking change, watch the repository for releases (on GitHub,
Watch, then Custom, then Releases). Read the notes for every version between
yours and the one you're moving to before you upgrade or move a pin.

## Writing an extension file

Extension files are additive. The skill reads your file alongside its own
instructions; there's no syntax that deletes or replaces a base instruction,
and text like "ignore step 3" isn't reliable. Write what to do in addition:
"when you open the pull request, also add the `team-x` label", "before
implementing, run `make lint`".

Describe behavior rather than structure. "Before writing the design, read
`docs/architecture.md`" keeps working when the skill's phases are reorganized;
"in phase-2-research.md, after step 4" breaks the first time that file moves.
That is why most shirabe changes leave extension files untouched.

Some things to know before you rely on it:

- A misnamed file fails silently. The skill just runs without it. If an
  extension seems to have no effect, check that the filename matches the
  skill's name exactly.
- An extension file has the same trust as CLAUDE.md: its text goes straight
  into the model's context and can tell the skill to run tools. Review changes
  to it the way you review CLAUDE.md changes. A `.local.md` file carries the
  same trust with no review trail, so decide as a team whether you allow them.
- Your rules are in context for the skill itself. Whether they reach work the
  skill hands to subagents isn't guaranteed; if a rule has to hold there, say
  so in the file so the skill carries it forward.
- The `@` slots are a Claude Code feature. Other clients that read the skills
  as plain Agent Skills files don't resolve them, so extension files have no
  effect there; the CLAUDE.md headers still work through whatever project
  context file the client reads.

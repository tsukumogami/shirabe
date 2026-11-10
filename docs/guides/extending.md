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

These are the headers the extension contract covers. Each is a level-2 heading
in your CLAUDE.md, and each is optional.

| Header | Values | Read by | When absent |
|--------|--------|---------|-------------|
| `## Repo Visibility:` | `Public` or `Private` | Every skill that writes content, to choose its content-governance rules | Inferred from the repository path (`public/` or `private/`), otherwise `Private` |
| `## Default Scope:` | `Strategic` or `Tactical` | `/explore`, `/plan`, `/design` (`/design` also accepts `## Planning Context:`) | `Tactical` |
| `## Label Vocabulary` | Free-form prose or a list of your issue labels | `/design`, `/explore`, `/plan`, `/prd`, `/work-on` | The skills run without project-specific labels |

A command-line flag (`--strategic`, `--tactical`) overrides `## Default Scope:`
for one run.

Skills read other CLAUDE.md headers too, such as `## Execution Mode:` and
`## Release Notes Convention:`. Those are documented, with their formats, in
[`references/fixes/claude-md-conventions.md`](../../references/fixes/claude-md-conventions.md).

## What counts as a breaking change

A shirabe change breaks extension authors when it does any of these:

1. Removes an `@` slot line from a skill's SKILL.md.
2. Renames a phase in a skill's workflow overview, so an extension file that
   names the phase no longer matches it.
3. Renames a CLAUDE.md header in the table above.

Everything else is compatible: rewording a skill's instructions, refactoring its
phase files, adding phases, changing support files, and adding a slot to a skill
that didn't have one.

## How a breaking change is announced

shirabe publishes its changes as notes on each
[GitHub release](https://github.com/tsukumogami/shirabe/releases). A change in
one of the three categories above is committed with the conventional-commit
breaking marker (`feat!:`, `fix!:` or a `BREAKING CHANGE` footer), and the
release that ships it lists it under a `## Breaking` heading at the top of its
notes, before the features and fixes. When adopters have to edit their
extension files or headers, the notes say what to change, and a longer
migration note goes under [`docs/guides/`](./) next to this one.

To hear about it, watch the repository for releases (Watch, then Custom, then
Releases on GitHub) and read the `## Breaking` section before you upgrade. If
you pin shirabe to a version, check it when you move the pin.

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

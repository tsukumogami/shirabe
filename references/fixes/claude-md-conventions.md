# CLAUDE.md Conventions Resolution

Canonical resolution guidance for FC-CONVENTIONS notices fired by
the validator's `check_claude_md_conventions` function. FC-CONVENTIONS
detects missing or malformed convention headers in a repo's
`CLAUDE.md`.

This file is dereferenced on-demand by FC-CONVENTIONS notice text;
readers arrive here from `[FC-CONVENTIONS] ... see references/fixes/claude-md-conventions.md`.

## What an FC-CONVENTIONS notice means

FC-CONVENTIONS fires when:

- A repo's `CLAUDE.md` is missing the `## Release Notes Convention:`
  header, OR
- The header is present but malformed (no `: <path>` suffix, or the
  path does not resolve).

The notice text names the missing or malformed header and points
here for the format.

## The canonical header format

```markdown
## Release Notes Convention: docs/guides/
```

The header is a level-2 markdown heading. The text after the colon
is the directory containing release notes for the repo. Trailing
slash is conventional but not required.

The shirabe repo's default is `docs/guides/`. Other repos pick the
directory that fits their structure (`docs/releases/`,
`CHANGELOG.md`, etc.).

## Per-repo defaults

| Repo | Convention | Header |
|------|-----------|--------|
| shirabe | `docs/guides/` | `## Release Notes Convention: docs/guides/` |
| tsuku | `docs/releases/` (illustrative) | `## Release Notes Convention: docs/releases/` |
| niwa | `CHANGELOG.md` (illustrative) | `## Release Notes Convention: CHANGELOG.md` |

The convention header is per-repo, not workspace-wide. Each repo
declares its own surface in its own `CLAUDE.md`.

## Cross-references to other CLAUDE.md convention headers

The Release Notes Convention header parallels the existing
convention headers shirabe uses:

- **`## Repo Visibility: Public|Private`** -- determines which
  content governance skill loads (`public-content` or
  `private-content`).
- **`## Planning Context: Strategic|Tactical`** -- the repo's
  default planning altitude; overridable per-command with
  `--strategic` / `--tactical`.
- **`## Default Scope: <scope>`** -- the repo's default work
  scope for `/scope` and `/charter` entrypoints.
- **`## Execution Mode: auto|interactive`** -- whether skills
  default to autonomous decision-making or prompt at each decision
  point.
- **`## Roadmap Issues: optional|required`** -- whether a
  human-invoked `/roadmap populate <path>` that passes no mode flag
  creates one GitHub issue per feature (`required`) or renders the
  reserved sections from feature context with no issues
  (`optional`). Default `optional` when the header is absent, which
  matches the `shirabe roadmap populate` subcommand's own default.
  The header does NOT affect the automatic population a `/roadmap`
  run performs -- that is always issueless. Read by the roadmap
  skill, not the validator, the same way `## Execution Mode:` is
  read. The full stack is
  `flag > this header > issueless default`.
- **`## Delivery Preference: consolidated|atomic`** -- how the repo
  prefers planned work to arrive. `consolidated` reaches for the
  fewest pull requests the work permits; `atomic` reaches for the
  smallest reviewable increments it permits. Default `consolidated`
  when the header is absent, which is the behavior every repo has
  today. Read by `/plan` step 3.6 when it recommends an
  `execution_mode`, and by the validator's `L09` when it decides
  whether a `single-pr` PLAN departed from the stated preference.
  The full stack is `flag > this header > consolidated default`.
  An unrecognized value falls through to the default rather than
  being used. Deliberately NOT named `Execution Mode`, which is
  already taken above for autonomy and would also collide with the
  `execution_mode` PLAN frontmatter field.
- **`## Tracking Level: none|issues|issues-and-milestone`** -- which
  GitHub artifacts a PLAN's work items get, independent of how many
  pull requests the work arrives in. Where a level is stated it
  applies regardless of `execution_mode`; where none is stated the
  default is `issues-and-milestone` for a `multi-pr` PLAN and `none`
  for a `single-pr` one, which is the behavior every repo has today.
  Does not apply to `coordinated` PLANs, whose tracking is governed
  by `references/coordination-strategy.md`. Read by `/plan` phase 7.
  The full stack is `flag > this header > the mode-derived default`.
  An unrecognized value falls through to the default.
- **`## Release Notes Convention: <path>`** -- the directory or
  file path the release-notes skill targets when emitting
  release-notes prose.
- **`## Fix Labels: <label>, <label>...`** -- the issue labels that
  make a `/work-on` unit a fix, which then records a failing check
  before its correcting change
  (`skills/work-on/references/red-first.md`). Comma-separated; a label
  may contain spaces and matches in any case. Default `bug` when the
  header is absent; an empty value means no label marks a fix, though
  a plan step's `**Fixes**:` line or the run's own declaration still
  can. Read by `fix-kind.sh` from `CLAUDE.md` as it stands at the
  run's base, so a unit's own diff can't change it, with a
  fence-aware scan (`scripts/lib/claude-md-header.sh`) that ignores
  an example inside a code block. Declaring the header twice is
  refused rather than resolved.
- **`## Test Change Acceptance: person|agent`** -- who may accept a
  `/work-on` pass that came with an edited test
  (`skills/work-on/references/red-first.md`). `person` means only a
  person at a terminal can, and a run stops and waits for one; `agent`,
  the default when the header is absent, lets an acceptance seat the
  run mints accept. Read by `test-change.sh init` from `CLAUDE.md` at
  the run's base and at the remote default branch's tip, and from
  `CLAUDE.local.md`, with the same fence-aware scan; `person` in any of
  them wins, so a local file can only tighten. A value that is neither,
  or the header declared twice, reads as `person` and is named in the
  run's record.
- **`## PR Workflow Content: include|omit`** -- whether the pull
  request titles, bodies and commit messages the skills write carry
  the workflow's own records (review panel tables, the artifact
  skills' jury verdicts, override and deferral notes, run records,
  pointers to PLAN and ROADMAP files).
  Default `omit` when the header is absent: the records stay in the
  run's session. Read from `CLAUDE.local.md` before `CLAUDE.md`, so
  a workspace that writes `CLAUDE.local.md` can opt a repository in
  from its configuration; the first well-formed header wins and any
  other value is passed over. Read by `scripts/pr-workflow-content.sh`,
  the one reader every skill, gate and script uses, not by the
  validator.

Each header is independent. A repo may declare any subset; absent
headers fall through to their defaults (Public visibility, Tactical
planning, etc.). FC-CONVENTIONS only fires for the Release Notes
Convention header today; the other headers have their own validators
or are defaulted silently.

## Fix

Add the header to the repo's `CLAUDE.md`, parallel to any existing
convention headers. The header has no body content -- the path on
the heading line is the entire declaration.

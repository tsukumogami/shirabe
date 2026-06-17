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
- **`## Roadmap Issues: optional|required`** -- whether `shirabe
  roadmap populate` creates one GitHub issue per feature
  (`required`) or renders the reserved sections from feature
  context with no issues (`optional`). Default `required` when the
  header is absent. Read by the roadmap skill, not the validator,
  the same way `## Execution Mode:` is read.
- **`## Release Notes Convention: <path>`** -- the directory or
  file path the release-notes skill targets when emitting
  release-notes prose.

Each header is independent. A repo may declare any subset; absent
headers fall through to their defaults (Public visibility, Tactical
planning, etc.). FC-CONVENTIONS only fires for the Release Notes
Convention header today; the other headers have their own validators
or are defaulted silently.

## Fix

Add the header to the repo's `CLAUDE.md`, parallel to any existing
convention headers. The header has no body content -- the path on
the heading line is the entire declaration.

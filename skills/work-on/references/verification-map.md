# Verification map schema

`/work-on`'s definition-of-done gate reads a project's **verification map** from that
project's extension file, `.claude/shirabe-extensions/work-on.md`. The map tells the gate
which verification commands to run for what an issue changed, and the gate requires every
run to pass before the issue can finalize.

This doc is the single source for the schema. It is generic and project-agnostic: it carries
no project-specific commands. A project declares its own commands in its extension file.

## What a project declares

A project's extension file declares two things:

1. **A verification map** — a list of entries, each mapping a **path-glob** to **one or
   more verification commands**. The glob is matched against the issue's changed files (the
   diff of the issue's branch against its base). Each command must run and pass.
2. **A default verification command** (optional) — the repo's standard test command, run
   when no map entry matches the changed files.

### Entry shape

Each entry pairs a path-glob with the command(s) to run when a changed file matches it.
A common form is a Markdown list of `path-glob` headings, each followed by its commands.
The exact layout is the project's choice; the contract is only that the gate can read, per
entry, a glob and the command(s) bound to it.

## How the gate reads the map

The gate classifies the issue's changed files against the map and runs the matched commands:

- **A changed file that matches multiple entries runs each matched entry's commands.** The
  matches are additive, not first-wins. An issue that touches files matching two entries
  runs both entries' commands and requires both to pass.
- **A changed file (or change set) that matches no entry falls through to the default
  verification command.** The default is the repo's standard test command declared in the
  extension.
- **No match and no default — or a matched/default command that cannot run — yields
  cannot-verify, and the gate fails closed.** It does not pass. A `cannot-verify` outcome
  routes to the gate's blocking human decision; it never reads as "verified".

The crux: **"the verification exists" never counts as "it passed".** The gate runs the
command and requires a passing result. A present-but-unrun command, a command that errors
before producing a result, or an absent command with no default all fail closed.

## Illustrative example (not a real project's map)

The entry below is illustrative only. Real commands live in a project's own extension file.

- `src/**` -> `<the repo's test command>`
- default -> `<the repo's standard test command>`

When an issue changes a file under `src/`, the gate runs the repo's test command and
requires it to pass. When an issue changes only files no entry matches (say, a top-level
config file), the gate runs the default. When neither applies and no default is declared,
the gate reports cannot-verify and fails closed.

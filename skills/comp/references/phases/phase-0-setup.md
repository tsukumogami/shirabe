# Phase 0: Setup

Detect the input mode, enforce the private-only visibility gate, validate
the topic slug, read the optional parent-orchestration sentinel, and
initialize `wip/`. Phase 0 runs before any content work and can refuse the
whole invocation.

## 0.1 Detect Input Mode

Parse `$ARGUMENTS`:

- **Empty** — ask the user which competitive question to survey, then
  derive a topic slug from their answer.
- **Existing COMP path + lifecycle verb** (`accept`, `done`) — this is a
  transition invocation; run `shirabe transition <path>
  Accepted|Done` and exit. No new authoring.
- **`--upstream <path>`** — record the upstream artifact path for Phase 1.
- **Anything else** — treat the first token as the topic slug.

## 0.2 Visibility Gate (Private Only) — Hard Refusal

Detect repo visibility from CLAUDE.md (`## Repo Visibility:
Public|Private`). If the header is absent, infer from the repo path
(`private/` -> Private, `public/` -> Public; default to Private).

COMP is private-only. If visibility is anything other than `private`,
**refuse immediately**, before creating any file, initializing `wip/`, or
doing any other work:

```
[/comp] REFUSED <topic>: visibility=public
```

Emit that exact line to stdout and exit. Then tell the user, in prose,
that COMP is a private-only artifact and point them at the alternatives:
a public BRIEF or PRD can reference the competitive question without
containing the analysis. This refusal mirrors the validator's R9 gate —
the skill and the CLI enforce the same private-only contract from two
sides.

The refusal is fail-closed: treat any non-`private` value, including an
unset or unrecognized visibility, as public for the purpose of this gate.

## 0.3 Validate Topic Slug

The `<topic>` slug must match `^[a-z0-9-]+$` (lowercase alphanumeric and
hyphens only). Reject any topic containing `.`, `/`, `_`, whitespace, or
other characters and ask the user for a conforming slug. This constraint
is load-bearing: `<topic>` is interpolated into `wip/` paths and the
verdict-file paths in Phase 4, so a `../`-shaped slug could redirect
writes outside `wip/research/`.

## 0.4 Read Parent-Orchestration Sentinel (Optional)

If a sentinel file exists at `wip/<parent>_<topic>_state.md`, a parent
skill (today, `/charter`) is orchestrating this invocation. Read it for:

- an upstream artifact path to record in the COMP frontmatter's context,
- any resume context (which phase to resume from),
- a `suppress_status_aware_prompt` flag.

The sentinel read is **optional**. When no sentinel exists, `/comp` runs
standalone with identical behavior. Never fail because a sentinel is
absent.

## 0.5 Initialize wip/

Create the `wip/` working area for this invocation:

- `wip/comp_<topic>_scope.md` — Phase 1 scoping notes.
- `wip/research/comp_<topic>_phase4_<role>.md` — Phase 4 verdict files
  (written later, by the jury).

These are non-durable intermediates. They must be cleaned in Phase 5
before the PR can merge, and no committed COMP artifact may reference a
`wip/...` path.

## Output

Phase 0 produces: the validated topic slug, the resolved visibility
(must be `private` to proceed), the optional upstream path, and an
initialized `wip/` area. On a non-private repo it produces only the
`[/comp] REFUSED` stdout signal and exits.

# Phase 0: Setup

Detect the input mode, run the private-only visibility check, validate
the topic slug, read the optional parent-orchestration sentinel, and
initialize `wip/`. Phase 0 runs before any content work, so a visibility
warning reaches the author before anything is written.

## 0.1 Detect Input Mode

Parse `$ARGUMENTS`:

- **Empty** — ask the user which competitive question to survey, then
  derive a topic slug from their answer.
- **Existing COMP path + lifecycle verb** (`accept`, `done`) — this is a
  transition invocation; run `shirabe transition <path>
  Accepted|Done` and exit. No new authoring.
- **`--upstream <path>`** — record the upstream artifact path for Phase 1.
- **Anything else** — treat the first token as the topic slug.

## 0.2 Visibility Check (Private Only) — Warning

Detect repo visibility from CLAUDE.md (`## Repo Visibility:
Public|Private`). If the header is absent, infer from the repo path
(`private/` -> Private, `public/` -> Public; default to Private).

COMP is private-only. If visibility is anything other than `private`,
**warn before doing anything else** — before creating any file,
initializing `wip/`, or starting the scoping conversation. Emit this
exact line to stdout so a parent skill can detect the condition by shell
parsing:

```
[/comp] WARNING <topic>: visibility=public
```

Then say this to the author, and wait for their answer:

> *"This repo is public. A COMP is competitive content and belongs in a
> private repo: `shirabe validate` rejects a COMP under public
> visibility (R9), so an analysis written here can't be finalized in
> place — and CI's guardrail fails the PR. If you want the competitive
> question on the record in this repo, a BRIEF or PRD can reference it
> without carrying the analysis. Do you want to continue here anyway,
> or stop?"*

`/comp` does **not** exit on its own. The author decides. The check is
fail-closed in what it treats as public — any non-`private` value,
including an unset or unrecognized visibility, warrants the warning —
but fail-closed here means "warn", not "terminate".

Warn rather than refuse because the author is the one who knows why they
invoked `/comp` here: they may be about to move the analysis, may have a
mis-set `## Repo Visibility:` header, or may want the draft in hand
before deciding where it lives. What a flat refusal actually protected
was the artifact never landing in a public repo, and that protection is
not the skill's to give up — it lives in the validator's R9 gate and the
CI guardrail, both of which still reject a COMP under public visibility.
The skill's job is to make sure the author knows that before they spend
the session, which is what the warning does.

If the author continues, carry the resolved visibility forward: Phase 5
states the same consequence again at the approval gate, and finalization
stops at the validator rather than landing a COMP in a public repo.

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

Phase 0 produces: the validated topic slug, the resolved visibility, the
optional upstream path, and an initialized `wip/` area. On a non-private
repo it also produces the `[/comp] WARNING` stdout signal and the
author's decision about whether to continue.

# Phase 0: Setup

Detect the entry mode, repo visibility, and scope; canonicalize inputs; initialize
working artifacts. Phase 0 is a guard rail: it normalizes `$ARGUMENTS`, rejects
unsafe inputs before any file write, and records the bootstrap context for later
phases.

## Goal

Establish the runtime context for the rest of the workflow:

- Identify which entry mode this invocation falls into (cold start, freeform topic,
  or upstream PRD/VISION path).
- Detect repo visibility (`Public` or `Private`) from CLAUDE.md.
- Detect the strategy's scope (`project` or `org`) from inputs and CLAUDE.md
  context.
- Constrain the `<topic>` slug to a safe character set.
- Canonicalize any `<path>` argument and reject paths resolving outside the repo
  working tree.
- Initialize the `wip/` working directory with placeholder context for resume
  detection.

By the end of this phase, downstream phases can assume `<topic>` is safe to splice
into paths and that any upstream path argument refers to a file inside the repo.

## Resume Check

If `wip/strategy_<topic>_context.md` exists, Phase 0 has already run for this
topic. Re-read the context file, verify the recorded visibility and scope still
match the current CLAUDE.md, and skip ahead to whichever phase the recorded state
indicates.

If the context file exists but its recorded visibility no longer matches
CLAUDE.md (the repo's visibility line changed), warn the user and ask whether to
restart Phase 0 or keep the recorded value. Visibility drift mid-workflow is a
red flag worth surfacing.

## 0.1 Detect Entry Mode

Parse `$ARGUMENTS` and classify into one of three modes:

| Mode | Trigger | Phase 1 behavior |
|------|---------|------------------|
| **Cold start** | `$ARGUMENTS` is empty or whitespace only | Phase 1 asks the user what strategic conversation they want to have |
| **Freeform topic** | `$ARGUMENTS` is a string with no path separators and does not match an existing file path | Phase 1 prompts for bet articulation grounded in the topic |
| **Upstream path** | `$ARGUMENTS` resolves to an existing file under `docs/prds/` or `docs/visions/` | Phase 1 derives the bet candidate from the upstream's content |

When `$ARGUMENTS` looks like a path (contains `/` or ends in `.md`) but the file
does not exist, do not fall through to freeform-topic mode silently. Ask the user
whether the path was a typo or whether they meant to start a freeform topic with
the same name.

Record the detected mode in `wip/strategy_<topic>_context.md` (created in step
0.5) so resume logic can route back to the same Phase 1 branch.

## 0.2 Constrain the `<topic>` Slug

The `<topic>` slug appears in `wip/` path templates, in verdict filenames at
Phase 4, and in the final artifact filename. Without constraint, a slug
containing `../` or shell metacharacters could redirect file writes outside the
intended `wip/research/` directory.

**Rule:** the slug MUST match `^[a-z0-9-]+$`.

Derive the slug as follows:

1. If `$ARGUMENTS` is an upstream path, take the basename, strip the
   `PRD-` or `VISION-` prefix and `.md` suffix, and use the remainder.
2. If `$ARGUMENTS` is a freeform topic string, lowercase it, replace whitespace
   and underscores with `-`, and strip any character outside `[a-z0-9-]`.
3. If `$ARGUMENTS` is empty, ask the user to name the strategy and re-derive
   from their answer.

After derivation, test the slug against `^[a-z0-9-]+$`. If the slug is empty,
contains characters outside the allowed set after derivation, or starts/ends
with `-`, reject the invocation and ask the user for a clean slug. Do not fall
through to a "best effort" slug — silent normalization hides input the user did
not intend.

## 0.3 Canonicalize Upstream Path

If Phase 0 detected upstream-path mode, canonicalize the path before any read:

1. Resolve the path against the repo root (the working directory the skill
   was invoked from).
2. Resolve symlinks fully.
3. Verify the canonicalized path is still inside the repo working tree. Reject
   the invocation if it resolves outside (e.g., a symlink pointing to
   `/etc/passwd` or to a sibling repo).
4. Verify the file exists and is readable.
5. Verify the basename starts with `PRD-` or `VISION-`. Other prefixes indicate
   the user pointed at the wrong artifact type and the bet derivation will
   misfire.

On any rejection, abort with a message that names the offending path and the
reason. Do not silently fall back to freeform-topic mode — the user provided a
path; misinterpreting it as a topic string would produce confusing downstream
behavior.

## 0.4 Detect Repo Visibility and Scope

**Visibility:**

1. Read the repo's `CLAUDE.md` and look for a line matching
   `## Repo Visibility: (Public|Private)`.
2. If found, record the value.
3. If not found, infer from the repo path: `private/` in the path implies
   Private, `public/` implies Public.
4. If neither check resolves the value, default to Private. Restricting is
   easier to undo than oversharing.

Public-visibility repos must NOT include a `Competitive Considerations` section
in the final STRATEGY (enforced by `shirabe validate` error code R8). Phase 2
and Phase 3 prose will reference this constraint; Phase 0 just records the
value.

**Scope:**

1. If `$ARGUMENTS` is an upstream VISION path and the VISION's frontmatter
   carries `scope: org`, default scope to `org`.
2. If `$ARGUMENTS` is an upstream VISION path with `scope: project` or no
   scope field, default scope to `project`.
3. If `$ARGUMENTS` is an upstream PRD path, default scope to `project` (PRDs
   live below STRATEGY-altitude work).
4. If `$ARGUMENTS` is empty or freeform, leave scope undetermined; Phase 1
   asks the user to confirm.

Org-scope strategies that have no upstream VISION are explicitly supported.
Phase 1 grounds Strategic Context in the org's other strategic artifacts or in
first-principles framing for that case.

## 0.5 Initialize wip/

Create the working directory structure for this invocation:

```
wip/
├── strategy_<topic>_context.md          (created here in Phase 0)
└── research/                            (Phase 1 may write into this; Phase 4 will)
```

Write `wip/strategy_<topic>_context.md` with the following keys:

```markdown
# /strategy Context: <topic>

## Entry Mode
<cold | freeform | upstream-prd | upstream-vision>

## Upstream Path
<canonical path, or "none">

## Topic Slug
<topic>

## Visibility
<Public | Private>

## Scope
<project | org | undetermined>

## Phase
0
```

This file is the resume-detection anchor for Phase 1 onward. Subsequent phases
update the `## Phase` line as they begin.

Do NOT commit the context file at this stage. The wip-hygiene rule treats
`wip/` artifacts as non-durable; the final cleanup at Phase 5 removes them
before the PR can merge.

## 0.6 Confirm Setup with User

Surface the detected context to the user in one short message:

> Setting up `/strategy` for topic `<topic>`.
> Entry mode: <mode>. Visibility: <visibility>. Scope: <scope or "to be confirmed">.
> Upstream: <path or "none">.

Do not block on confirmation for routine cases. If any detection produced an
unexpected value (visibility defaulted to Private because CLAUDE.md was
missing, or scope is undetermined and the user gave a freeform topic), call
that out explicitly so the user can correct it before Phase 1 commits to a
direction.

## Quality Checklist

Before proceeding:
- [ ] `<topic>` slug matches `^[a-z0-9-]+$`
- [ ] Upstream path (if provided) is canonicalized and inside the repo working tree
- [ ] Upstream file (if provided) exists and has a `PRD-` or `VISION-` basename
- [ ] Visibility is recorded (Public or Private, never empty)
- [ ] Scope is recorded as `project`, `org`, or `undetermined`
- [ ] `wip/strategy_<topic>_context.md` exists with the keys above

## Artifact State

After this phase:
- Context file at `wip/strategy_<topic>_context.md`
- No STRATEGY draft yet
- No research files yet

## Next Phase

Proceed to Phase 1: Discover (`phase-1-discover.md`)

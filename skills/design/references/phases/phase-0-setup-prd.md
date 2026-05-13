# Phase 0: Setup + Context (PRD Mode)

Extract problem context from an accepted PRD and establish the design doc skeleton.

## Goal

Translate the PRD's "what/why" into implementation-oriented framing:
- Synthesize (not copy-paste) the problem statement into technical terms
- Derive decision drivers from requirements and constraints
- Create the design doc skeleton and wip/ summary
- Transition the PRD status to "In Progress"

## Resume Check

If `wip/design_<topic>_summary.md` exists, skip to Phase 1.

## Steps

### 0.1 Branch Setup

If already on a `docs/<topic>` branch, skip branch creation. Otherwise:
- Create `docs/<topic>` (kebab-case) from latest main
- Confirm you're on the correct branch

### 0.2 Read PRD

Read the PRD file from the path provided in `$ARGUMENTS`. Verify:
- File exists and is a valid PRD (`docs/prds/PRD-*.md`)
- Status is "Accepted"

If the PRD status is not "Accepted", STOP and inform the user. Design work requires
an accepted PRD.

### 0.3 Synthesize Problem Statement

Write the design doc's "Context and Problem Statement" section. Translate the PRD's
problem framing into implementation terms:
- What technical challenge does this create?
- What system boundaries are involved?
- What existing code/architecture is affected?

Don't copy the PRD verbatim. A design doc reader needs a different framing: the PRD
explains what to build and why; the design doc explains what technical problem needs
solving.

### 0.4 Derive Decision Drivers

Extract decision drivers from the PRD's requirements and constraints. Add
implementation-specific drivers (performance, compatibility, maintainability) that
the PRD may not cover.

Write the "Decision Drivers" section in the design doc.

### 0.4a Validate Upstream PRD Path

Before writing the `upstream:` value into the design doc, validate that the path
is durable and visibility-compatible. This is a hard-stop check: do not proceed
with step 0.5 until the path is resolved or the field is omitted.

**The path the PRD was loaded from (in step 0.2) is the candidate `upstream:`
value.** Run these checks in order:

1. **Is the candidate path under `wip/`?** If yes, STOP. The PRD on disk is a
   staging copy, not its canonical home. wip/ paths are non-durable: they are
   deleted before merge and would leave the design's `upstream:` orphaned.
   Resolution:
   - Find the PRD's canonical location (likely in a different repo). If the
     current repo's visibility allows referencing it, use `owner/repo:path`
     cross-repo syntax for `upstream:`.
   - If the canonical PRD lives in a private repo and this repo is public,
     OMIT the `upstream:` field entirely (see step 0.5 worked example).
   - Read `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md` for the
     visibility-direction table and recovery options.

2. **Does the candidate path resolve inside this repo?** Run
   `git ls-files <path>` from the repo root.
   - If non-empty: the PRD is tracked in this repo. Use the relative path as
     `upstream:` and proceed to 0.5.
   - If empty: the PRD is not in this repo. Detect the current repo's
     visibility from CLAUDE.md (`## Repo Visibility:`).

3. **Public repo referencing an out-of-repo PRD?** If the repo is public AND
   the PRD is not tracked here AND the canonical location is private, STOP.
   This is a visibility violation: external readers can't reach private
   resources, so the link breaks for them. Resolution: OMIT the `upstream:`
   field entirely. Add a one-line prose note in the design body's "Context
   and Problem Statement" section explaining that the source PRD lives in a
   private tracker (without naming the private path or repo).

4. **Public repo referencing an out-of-repo PUBLIC PRD?** Use the
   `owner/repo:path` cross-repo syntax. Verify the path exists in the target
   repo before writing it.

5. **Never write `upstream: wip/...` into committed frontmatter.** wip/
   paths fail check (1) above. The same rule applies to any other prose or
   frontmatter field that survives the merge.

**Worked example (the failure mode this step prevents).** During a
multi-repo coordination run, a coordinator stages a private-repo PRD into the
current (public) repo's `wip/` directory as a handoff. An agent runs `/design`
against that staging file. Without this validation, the agent writes
`upstream: wip/PRD-<topic>.md` into the design frontmatter. Later, a cleanup
commit deletes the wip/ file (per wip-hygiene), leaving the `upstream:` value
pointing at nothing. The frontmatter is now a public reference to a private
resource AND an orphaned path. With this validation, the agent detects the
`wip/` prefix at check (1), recognises the cross-visibility boundary at check
(3), and omits the `upstream:` field instead.

### 0.5 Create Design Doc Skeleton

Write the initial design doc to `docs/designs/DESIGN-<topic>.md`. The
`upstream` line below is conditional on the outcome of step 0.4a -- omit it
entirely if 0.4a determined the field cannot be set:

```markdown
---
upstream: docs/prds/PRD-<name>.md   # OMIT this line if step 0.4a resolved to "omit"
---

# DESIGN: <Topic>

## Status

Proposed

## Context and Problem Statement

<Synthesized from PRD in step 0.3>

## Decision Drivers

<Derived from PRD in step 0.4>
```

The `upstream` field creates a machine-readable link from the design doc back to
its source PRD. When omitted (per 0.4a), a prose note in the Context section
should describe where the source PRD lives without naming a private path.

### 0.6 Transition PRD Status

Update the PRD's status from "Accepted" to "In Progress" (both frontmatter and body).
Commit: `docs(prd): mark <prd-name> in progress`

### 0.7 Create wip/ Summary

Write `wip/design_<topic>_summary.md`:

```markdown
# Design Summary: <topic>

## Input Context (Phase 0)
**Source PRD:** docs/prds/PRD-<name>.md
**Problem (implementation framing):** <1-2 sentences>

## Current Status
**Phase:** 0 - Setup (PRD)
**Last Updated:** <date>
```

Commit: `docs(design): initialize design for <topic> from PRD`

## Quality Checklist

Before proceeding:
- [ ] On branch `docs/<topic>`
- [ ] Problem statement is in implementation terms (not a PRD copy)
- [ ] Decision drivers include both PRD-derived and implementation-specific factors
- [ ] `upstream:` value is either a same-repo `docs/prds/...` path, a public
  cross-repo `owner/repo:path`, or omitted (per step 0.4a). It is NEVER a
  `wip/...` path.

## Artifact State

After this phase:
- Design doc exists with: Status, Context and Problem Statement, Decision Drivers
- PRD is marked "In Progress"
- `wip/design_<topic>_summary.md` exists

## Next Phase

Proceed to Phase 1: Decision Decomposition (`phase-1-decomposition.md`)

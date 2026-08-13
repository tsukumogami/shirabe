# Phase 0: Setup

Detect the entry mode, repo visibility, and scope; canonicalize inputs; initialize
working artifacts. Phase 0 is a guard rail: it normalizes `$ARGUMENTS`, rejects
unsafe inputs before any file write, and records the bootstrap context for later
phases.

## Goal

Establish the runtime context for the rest of the workflow:

- Parse `--upstream <path>` out of `$ARGUMENTS` before the remainder is
  classified, and validate its value.
- Identify which entry mode the remainder falls into (cold start, freeform topic,
  an upstream VISION path, or a grounding PRD path).
- Detect repo visibility (`Public` or `Private`) from CLAUDE.md.
- Detect the strategy's scope (`project` or `org`) from inputs and CLAUDE.md
  context.
- Constrain the `<topic>` slug to a safe character set.
- Canonicalize any `<path>` argument and reject paths resolving outside the repo
  working tree.
- Initialize the `wip/` working directory with placeholder context for resume
  detection.

By the end of this phase, downstream phases can assume `<topic>` is safe to splice
into paths and that any path argument refers to a file inside the repo.

## Resume Check

If `wip/strategy_<topic>_context.md` exists, Phase 0 has already run for this
topic. Re-read the context file, verify the recorded visibility and scope still
match the current CLAUDE.md, and skip ahead to whichever phase the recorded state
indicates.

If the context file exists but its recorded visibility no longer matches
CLAUDE.md (the repo's visibility line changed), warn the user and ask whether to
restart Phase 0 or keep the recorded value. Visibility drift mid-workflow is a
red flag worth surfacing.

Re-validate a recorded `## Recorded Upstream` the same way, against the worktree
as it is now: a file tracked when the strategy was started can be deleted or
moved before it finishes. A recorded upstream that no longer resolves is
surfaced naming the path and the check it fails, never silently carried into
frontmatter and never silently dropped. Offer to re-supply it, or to continue
without it and omit the field — saying which one the run took.

## 0.1 Detect Entry Mode

### Parse `--upstream` First

`--upstream <path>` names the VISION this strategy operationalizes,
separately from whatever the positional argument says. Consume the flag and
the token following it BEFORE classifying the remainder: the flag's value is
never tested as a topic string, never tested as a path argument in the
entry-mode table below, and never used to derive the topic slug.

A bare `--upstream` — the flag as the last token, or followed by another
`--`-prefixed token — is rejected before anything is written, naming the
missing argument:

> `--upstream` requires a path argument naming the upstream VISION, for
> example `--upstream docs/visions/VISION-<name>.md`. Re-invoke
> `/strategy <topic> --upstream <path>`.

The flag may appear at most once; a second occurrence is rejected the same
way, naming the repeated flag. When the flag is present and the remainder is
empty, the cold-start branch fires — the flag is not a topic, and no slug is
derived from the VISION's filename.

The flag is what makes an upstream usable whose name does not match the
strategy's topic. Input Mode 3 (a bare VISION path) supplies the topic and
the upstream in one token and therefore only works when the two coincide;
`--upstream` is the general form, and it is how `/charter` hands a VISION
down (`/strategy <topic-slug> --upstream <vision-path>`). An author invoking
`/strategy` directly uses the same flag for the same reason.

`--upstream` never carries a grounding PRD. The flag's value is what Phase 2
writes into `upstream:`, and a PRD is never recorded there — see "Reading a
document vs. recording it as `upstream`" below. A PRD grounds the bet by
being passed positionally, as Input Mode 4.

### Classify the Remainder

Parse what remains of `$ARGUMENTS` and classify into one of four modes:

| Mode | Trigger | Phase 1 behavior |
|------|---------|------------------|
| **Cold start** | `$ARGUMENTS` is empty or whitespace only | Phase 1 asks the user what strategic conversation they want to have |
| **Freeform topic** | `$ARGUMENTS` is a string with no path separators and does not match an existing file path | Phase 1 prompts for bet articulation grounded in the topic |
| **Upstream VISION** | `$ARGUMENTS` resolves to an existing file under `docs/visions/` | Phase 1 derives the bet candidate from the VISION's content |
| **Grounding PRD** | `$ARGUMENTS` resolves to an existing file under `docs/prds/` | Phase 1 derives the bet candidate from the PRD's content |

> **Open: the Grounding PRD mode is itself unresolved — see
> [#257](https://github.com/tsukumogami/shirabe/issues/257).** A PRD sits on
> the tactical chain, two altitudes below a STRATEGY, so accepting one as
> input is a strategic document reaching down into the tactical chain. PR #252
> closed the structural half — a grounding PRD is never recorded in
> `upstream:` — but left the input path open. Resolving it either removes this
> mode or writes down why reading across altitudes is legitimate where linking
> across them is not.

When `$ARGUMENTS` looks like a path (contains `/` or ends in `.md`) but the file
does not exist, do not fall through to freeform-topic mode silently. Ask the user
whether the path was a typo or whether they meant to start a freeform topic with
the same name.

Record the detected mode in `wip/strategy_<topic>_context.md` (created in step
0.5) so resume logic can route back to the same Phase 1 branch.

### Reading a document vs. recording it as `upstream`

Both path modes read the file they are handed. Only one of them ever writes
that path into the draft's `upstream:` frontmatter field, and the two acts are
not the same act.

- A **VISION is read and recorded.** `upstream:` names the strategy's
  immediate neighbour one level up the strategic chain (VISION -> STRATEGY ->
  ROADMAP), and a VISION is exactly that. It reaches Phase 0 either as a
  positional path (Input Mode 3) or as the `--upstream` flag's value; both
  routes are validated identically and both land in `## Recorded Upstream`.
- A **PRD is read only.** It grounds the Phase 1 conversation and informs the
  bet, and there it stops. A PRD sits two altitudes below a STRATEGY and on
  the tactical chain rather than the strategic one. Record it as the
  strategy's parent and a reader who follows `upstream:` looking for the
  altitude above lands below where they started instead, in the chain the
  STRATEGY is meant to feed rather than descend from.

Grounding a strategy in a PRD stays supported -- an author holding a feature
PRD who wants the medium-term bet behind it has a real strategy to write. What
the PRD never becomes is the recorded parent. When a PRD grounds the bet and
no VISION sits above it, the draft omits `upstream:` entirely and names the
PRD in Strategic Context prose, which is where the grounding is legible to a
reader anyway.

## 0.2 Constrain the `<topic>` Slug

The `<topic>` slug appears in `wip/` path templates, in verdict filenames at
Phase 4, and in the final artifact filename. Without constraint, a slug
containing `../` or shell metacharacters could redirect file writes outside the
intended `wip/research/` directory.

**Rule:** the slug MUST match `^[a-z0-9-]+$`.

Derive the slug as follows. In every case the derivation reads the
POSITIONAL argument only; the `--upstream` value is never an input to it.

1. If the positional argument is a path, take the basename, strip the
   `VISION-` or `PRD-` prefix and `.md` suffix, and use the remainder. Both
   path modes derive the slug the same way -- the slug names the strategy's
   topic, and says nothing about what ends up in `upstream:`.
2. If the positional argument is a freeform topic string, lowercase it,
   replace whitespace and underscores with `-`, and strip any character
   outside `[a-z0-9-]`.
3. If the positional argument is empty, ask the user to name the strategy and
   re-derive from their answer -- even when `--upstream` supplied a VISION.
   A VISION's filename names the vision, not the bet operationalizing it, and
   naming the strategy after it is exactly the conflation the flag exists to
   undo.

After derivation, test the slug against `^[a-z0-9-]+$`. If the slug is empty,
contains characters outside the allowed set after derivation, or starts/ends
with `-`, reject the invocation and ask the user for a clean slug. Do not fall
through to a "best effort" slug — silent normalization hides input the user did
not intend.

## 0.3 Canonicalize the Path Argument

If Phase 0 detected either path mode, or `--upstream` supplied a value,
canonicalize the path before any read:

1. Resolve the path against the repo root (the working directory the skill
   was invoked from).
2. Resolve symlinks fully.
3. Verify the canonicalized path is still inside the repo working tree. Reject
   the invocation if it resolves outside (e.g., a symlink pointing to
   `/etc/passwd` or to a sibling repo).
4. Verify the file exists and is readable.
5. Verify the basename starts with `VISION-` or `PRD-`. Other prefixes indicate
   the user pointed at the wrong artifact type and the bet derivation will
   misfire. The prefix also selects the mode: `VISION-` is an upstream to
   record, `PRD-` is grounding to read. See "Reading a document vs. recording
   it as `upstream`" in 0.1.

A `--upstream` value runs the same five steps with one difference: its
basename MUST start with `VISION-`. `PRD-` is not accepted on the flag,
because the flag records and a PRD is never recorded; an author holding a PRD
passes it positionally instead. Reject anything else, naming the offending
path and the expected prefix.

Two further checks apply to a `--upstream` value, in this order, before it is
recorded:

- **Not under `wip/`.** Reject. `wip/` artifacts are non-durable — the
  wip-hygiene cleanup deletes them before the PR can merge — so the recorded
  `upstream:` would point at a file that disappears. Name the canonical
  location in the rejection.
- **Tracked by git.** Run `git ls-files -- <path>`. An empty result on a path
  inside the working tree means the file is not committed; reject, naming the
  untracked path.

A cross-repo value in the `owner/repo:path` form from
`references/cross-repo-references.md` is not a working-tree path: it skips
canonicalization and the tracked-by-git check, keeps the `VISION-` basename
rule on its file component, and is governed by the visibility rule Phase 2
applies when writing frontmatter (a public STRATEGY omits a private upstream
rather than naming it).

On any rejection, abort with a message that names the offending path and the
reason. Do not silently fall back to freeform-topic mode — the user provided a
path; misinterpreting it as a topic string would produce confusing downstream
behavior. Do not silently drop a rejected `--upstream` value and continue
either: the author asked for a link, and a run that quietly produces a
STRATEGY without one hides the failure until someone reads the frontmatter.

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

1. If an upstream VISION was supplied (positionally or via `--upstream`) and
   the VISION's frontmatter carries `scope: org`, default scope to `org`.
2. If an upstream VISION was supplied with `scope: project` or no
   scope field, default scope to `project`.
3. If `$ARGUMENTS` is a grounding PRD path, default scope to `project` (PRDs
   live below STRATEGY-altitude work). The PRD informs the scope default the
   same way it informs the bet, and -- like the bet -- that reading never
   turns into an `upstream:` value.
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
<cold | freeform | grounding-prd | upstream-vision>

## Grounding Path
<canonical path of the VISION or PRD Phase 1 reads, or "none">

## Recorded Upstream
<the VISION path Phase 2 writes into the draft's `upstream:` frontmatter,
or "none" -- always "none" in grounding-prd mode>

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

`## Entry Mode` classifies the positional argument, so a `--upstream` run
records whichever mode the remainder produced — usually `freeform`. The flag
shows up in `## Recorded Upstream` and, because Phase 1 reads it, in
`## Grounding Path` as well: a supplied VISION grounds the conversation the
same way a positional one does. The two keys differing is what distinguishes
a grounding PRD (grounding set, upstream `none`) from a flag-supplied VISION
(both set to the same path).

Do NOT commit the context file at this stage. The wip-hygiene rule treats
`wip/` artifacts as non-durable; the final cleanup at Phase 5 removes them
before the PR can merge.

## 0.6 Confirm Setup with User

Surface the detected context to the user in one short message:

> Setting up `/strategy` for topic `<topic>`.
> Entry mode: <mode>. Visibility: <visibility>. Scope: <scope or "to be confirmed">.
> Grounding: <path or "none">. Recorded upstream: <VISION path or "none">.

In grounding-PRD mode the two lines differ, and that is worth saying out loud
rather than letting the author discover it in the frontmatter later:

> Grounding: `docs/prds/PRD-<name>.md`. Recorded upstream: none -- the PRD
> grounds the bet but `upstream:` takes a VISION, so the draft omits it.

Do not block on confirmation for routine cases. If any detection produced an
unexpected value (visibility defaulted to Private because CLAUDE.md was
missing, or scope is undetermined and the user gave a freeform topic), call
that out explicitly so the user can correct it before Phase 1 commits to a
direction.

## Quality Checklist

Before proceeding:
- [ ] `<topic>` slug matches `^[a-z0-9-]+$` and was derived from the positional
      argument alone, never from a `--upstream` value
- [ ] Path argument (if provided) is canonicalized and inside the repo working tree
- [ ] Path argument (if provided) exists and has a `VISION-` or `PRD-` basename
- [ ] `--upstream` value (if provided) has a `VISION-` basename, is not under
      `wip/`, and is tracked by git; a bare `--upstream` was rejected
- [ ] `## Recorded Upstream` holds the VISION path in upstream-VISION mode and
      when `--upstream` supplied one, and `none` in every other case,
      grounding-PRD included
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

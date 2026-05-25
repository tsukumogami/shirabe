# Phase 0: Setup

Detect the entry mode and repo visibility, canonicalize inputs, decide whether a
durable brief is the right artifact, and initialize working artifacts. Phase 0 is
a guard rail: it normalizes `$ARGUMENTS`, rejects unsafe inputs before any file
write, and records the bootstrap context for later phases.

## Goal

Establish the runtime context for the rest of the workflow:

- Identify which entry mode this invocation falls into (cold start, freeform
  topic, or upstream ROADMAP/PRD path).
- Detect repo visibility (`Public` or `Private`) from CLAUDE.md.
- Constrain the `<topic>` slug to a safe character set.
- Canonicalize any `<path>` argument and reject paths resolving outside the repo
  working tree.
- Make the brief-specific **artifact decision**: when the chain is entered partway
  up, decide whether to produce a durable brief or hand the existing evidence
  forward to the PRD.
- Initialize the `wip/` working directory with placeholder context for resume
  detection.

By the end of this phase, downstream phases can assume `<topic>` is safe to splice
into paths, that any upstream path argument refers to a file inside the repo, and
that producing a brief is the right call.

BRIEF has no scope (`project`/`org`) dimension — a brief frames one feature, so
Phase 0 does not detect or record a scope. This is the main structural difference
from the strategy skill's Phase 0.

## Resume Check

If `wip/brief_<topic>_context.md` exists, Phase 0 has already run for this topic.
Re-read the context file, verify the recorded visibility still matches the current
CLAUDE.md, and skip ahead to whichever phase the recorded state indicates.

If the context file exists but its recorded visibility no longer matches CLAUDE.md
(the repo's visibility line changed), warn the user and ask whether to restart
Phase 0 or keep the recorded value. Visibility drift mid-workflow is a red flag
worth surfacing.

## 0.1 Detect Entry Mode

Parse `$ARGUMENTS` and classify into one of three modes:

| Mode | Trigger | Phase 1 behavior |
|------|---------|------------------|
| **Cold start** | `$ARGUMENTS` is empty or whitespace only | Phase 1 asks the user which feature they want to frame |
| **Freeform topic** | `$ARGUMENTS` is a string with no path separators and does not match an existing file path | Phase 1 grounds the problem/outcome pair in the topic |
| **Upstream path** | `$ARGUMENTS` resolves to an existing file under `docs/roadmaps/` or `docs/prds/` | Phase 1 derives the problem/outcome candidate from the upstream's content |

When `$ARGUMENTS` looks like a path (contains `/` or ends in `.md`) but the file
does not exist, do not fall through to freeform-topic mode silently. Ask the user
whether the path was a typo or whether they meant to start a freeform topic with
the same name.

Record the detected mode in `wip/brief_<topic>_context.md` (created in step 0.5)
so resume logic can route back to the same Phase 1 branch.

## 0.2 Constrain the `<topic>` Slug

The `<topic>` slug appears in `wip/` path templates, in verdict filenames at
Phase 4, and in the final artifact filename. Without constraint, a slug containing
`../` or shell metacharacters could redirect file writes outside the intended
`wip/research/` directory.

**Rule:** the slug MUST match `^[a-z0-9-]+$`.

Derive the slug as follows:

1. If `$ARGUMENTS` is an upstream path, take the basename, strip the `ROADMAP-` or
   `PRD-` prefix and `.md` suffix, and use the remainder.
2. If `$ARGUMENTS` is a freeform topic string, lowercase it, replace whitespace
   and underscores with `-`, and strip any character outside `[a-z0-9-]`.
3. If `$ARGUMENTS` is empty, ask the user to name the feature and re-derive from
   their answer.

After derivation, test the slug against `^[a-z0-9-]+$`. If the slug is empty,
contains characters outside the allowed set after derivation, or starts/ends with
`-`, reject the invocation and ask the user for a clean slug. Do not fall through
to a "best effort" slug — silent normalization hides input the user did not intend.

## 0.3 Canonicalize Upstream Path

If Phase 0 detected upstream-path mode, canonicalize the path before any read:

1. Resolve the path against the repo root (the working directory the skill was
   invoked from).
2. Resolve symlinks fully.
3. Verify the canonicalized path is still inside the repo working tree. Reject the
   invocation if it resolves outside (e.g., a symlink pointing to `/etc/passwd` or
   to a sibling repo).
4. Verify the file exists and is readable.
5. Verify the basename starts with `ROADMAP-` or `PRD-`. Other prefixes indicate
   the user pointed at the wrong artifact type and the problem/outcome derivation
   will misfire.

On any rejection, abort with a message that names the offending path and the
reason. Do not silently fall back to freeform-topic mode — the user provided a
path; misinterpreting it as a topic string would produce confusing downstream
behavior.

## 0.4 Detect Repo Visibility

1. Read the repo's `CLAUDE.md` and look for a line matching
   `## Repo Visibility: (Public|Private)`.
2. If found, record the value.
3. If not found, infer from the repo path: `private/` in the path implies Private,
   `public/` implies Public.
4. If neither check resolves the value, default to Private. Restricting is easier
   to undo than oversharing.

BRIEF has no visibility-gated section, so `shirabe validate` runs no custom check
for the type. The recorded value still matters at Phase 4: a public BRIEF must not
reference private paths, repos, filenames, or issue numbers, and its `upstream:`
field must not point at a private artifact. Phase 4's structural-format reviewer
checks this; Phase 0 just records the value.

## 0.5 Make the Artifact Decision

Before initializing `wip/`, decide whether a durable brief is the right artifact
for this invocation. This is the brief-specific decision the chain forces when it
is entered partway up.

The decision matters because briefs can be invoked mid-altitude. The most common
case: a rich issue body, a detailed feature request, or an existing upstream that
already implies both the feature's problem and the outcome it should produce. Most
of a brief's content already exists — just not as a brief. Producing a separate
document by reflex is ceremony; passing the existing evidence straight to the PRD
may serve the author better.

Run the decision as follows:

1. **Assess the available framing.** From the entry mode and any upstream, judge
   how much of the brief's content already exists in durable form:
   - **Cold start / freeform topic with no upstream.** The framing does not exist
     yet. Produce a durable brief. Proceed normally.
   - **Upstream ROADMAP path.** A roadmap names the feature but rarely frames its
     problem and outcome. The framing gap is real. Produce a durable brief.
   - **Upstream PRD path, or an input that already reads as a framed feature
     (problem and outcome both clearly stated).** Most of the brief's content
     exists. This is the case the decision exists for — continue to step 2.

2. **Weigh produce-vs-hand-off.** When the framing largely exists, ask whether a
   durable brief earns its keep:
   - **Produce a brief** when the framing warrants recording: the feature will be
     referenced by more than one downstream artifact, the problem/outcome pair is
     contested or non-obvious enough that writing it down settles it, or a future
     reader landing cold would benefit from a standalone framing document.
   - **Hand off to the PRD** when authoring a separate document would be ceremony:
     the existing evidence (issue body, upstream) already frames the feature
     clearly, the PRD will be the only downstream consumer, and the framing is not
     contested. In this case, do not produce a brief. Tell the user the existing
     evidence is sufficient framing and recommend `/prd <upstream-or-topic>`
     directly, naming what the PRD should carry forward as its problem and outcome.

3. **Record the decision.** Write the outcome to the context file (step 0.5
   below). If the decision is hand-off, the workflow exits here — there is no brief
   to draft. Surface the recommendation to the user and stop.

This decision is a judgment call, not a gate with a fixed threshold. When the case
is genuinely ambiguous, default to producing the brief: a short standalone framing
artifact is cheap, and a durable record is easier to point a downstream PRD at than
scattered evidence. The hand-off path exists to avoid ceremony, not to discourage
briefs.

## 0.6 Initialize wip/

Create the working directory structure for this invocation:

```
wip/
├── brief_<topic>_context.md          (created here in Phase 0)
└── research/                         (Phase 4 will write into this)
```

Write `wip/brief_<topic>_context.md` with the following keys:

```markdown
# /brief Context: <topic>

## Entry Mode
<cold | freeform | upstream-roadmap | upstream-prd>

## Upstream Path
<canonical path, or "none">

## Topic Slug
<topic>

## Visibility
<Public | Private>

## Artifact Decision
<produce | handed-off>

## Phase
0
```

This file is the resume-detection anchor for Phase 1 onward. Subsequent phases
update the `## Phase` line as they begin.

Do NOT commit the context file at this stage. The wip-hygiene rule treats `wip/`
artifacts as non-durable; the final cleanup at Phase 5 removes them before the PR
can merge.

## 0.7 Confirm Setup with User

Surface the detected context to the user in one short message:

> Setting up `/brief` for topic `<topic>`.
> Entry mode: <mode>. Visibility: <visibility>.
> Upstream: <path or "none">. Artifact decision: <produce | hand off to PRD>.

Do not block on confirmation for routine cases. If any detection produced an
unexpected value (visibility defaulted to Private because CLAUDE.md was missing) or
the artifact decision recommended hand-off, call that out explicitly so the user
can correct it before Phase 1 commits to a direction.

## Quality Checklist

Before proceeding:
- [ ] `<topic>` slug matches `^[a-z0-9-]+$`
- [ ] Upstream path (if provided) is canonicalized and inside the repo working tree
- [ ] Upstream file (if provided) exists and has a `ROADMAP-` or `PRD-` basename
- [ ] Visibility is recorded (Public or Private, never empty)
- [ ] The artifact decision is recorded (`produce` or `handed-off`)
- [ ] `wip/brief_<topic>_context.md` exists with the keys above

## Artifact State

After this phase:
- Context file at `wip/brief_<topic>_context.md`
- No BRIEF draft yet
- No research files yet

## Next Phase

If the artifact decision was `produce`, proceed to Phase 1: Discover
(`phase-1-discover.md`). If it was `handed-off`, the workflow exits here with the
`/prd` recommendation surfaced to the user.

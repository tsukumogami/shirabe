# Phase 0: Setup

Detect the entry mode and repo visibility, canonicalize inputs, decide whether a
durable brief is the right artifact, and initialize working artifacts. Phase 0 is
a guard rail: it normalizes `$ARGUMENTS`, rejects unsafe inputs before any file
write, and records the bootstrap context for later phases.

## Goal

Establish the runtime context for the rest of the workflow:

- Parse `--upstream <path>` out of `$ARGUMENTS` before the remainder is
  classified, and validate its value.
- Identify which entry mode the remainder falls into (cold start, freeform
  topic, or upstream ROADMAP path).
- Detect repo visibility (`Public` or `Private`) from CLAUDE.md.
- Constrain the `<topic>` slug to a safe character set.
- Canonicalize any `<path>` argument and reject paths resolving outside the repo
  working tree.
- Record the artifact decision as `produce`. `/brief` always writes a standalone
  brief; the fold-into-PRD branch that once lived here is retired (see 0.5).
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

Re-validate a recorded `## Grounding Path` the same way, against the worktree as
it is now: a file present when the brief was started can be deleted or moved
before it finishes. A grounding path that no longer resolves is surfaced naming
the path and the check it fails, never silently dropped. Offer to re-supply it,
or to continue without it — saying which one the run took. Nothing is carried
into frontmatter either way; a BRIEF records no `upstream:`.

## 0.1 Detect Entry Mode

### Parse `--upstream` First

`--upstream <path>` names the ROADMAP this feature comes from, separately from
whatever the positional argument says. It supplies grounding, not a recorded
link: see "Reading a document vs. recording it as `upstream`" below. Consume the flag and the token
following it BEFORE classifying the remainder: the flag's value is never
tested as a topic string, never tested as a path argument in the entry-mode
table below, and never used to derive the topic slug.

A bare `--upstream` — the flag as the last token, or followed by another
`--`-prefixed token — is rejected before anything is written, naming the
missing argument:

> `--upstream` requires a path argument naming the upstream ROADMAP, for
> example `--upstream docs/roadmaps/ROADMAP-<name>.md`. Re-invoke
> `/brief <topic> --upstream <path>`.

The flag may appear at most once; a second occurrence is rejected the same
way, naming the repeated flag. When the flag is present and the remainder is
empty, the cold-start branch fires — the flag is not a topic, and no slug is
derived from the ROADMAP's filename.

The flag is what makes an upstream usable whose name does not match the
feature's topic, which is the ordinary case here: a roadmap sequences several
features and none of them is named after it. The upstream-path entry mode
supplies the topic and the upstream in one token and therefore only works
when the two coincide; `--upstream` is the general form, and it is how
`/scope` hands a ROADMAP down (`/brief <topic-slug> --upstream
<roadmap-path>`). An author invoking `/brief` directly uses the same flag for
the same reason.

### Classify the Remainder

Parse what remains of `$ARGUMENTS` and classify into one of three modes:

| Mode | Trigger | Phase 1 behavior |
|------|---------|------------------|
| **Cold start** | `$ARGUMENTS` is empty or whitespace only | Phase 1 asks the user which feature they want to frame |
| **Freeform topic** | `$ARGUMENTS` is a string with no path separators and does not match an existing file path | Phase 1 grounds the problem/outcome pair in the topic |
| **Upstream path** | `$ARGUMENTS` resolves to an existing file under `docs/roadmaps/` | Phase 1 derives the problem/outcome candidate from the upstream's content |

A ROADMAP is the only document the upstream-path entry mode accepts. A
`docs/prds/PRD-*.md` path is not an upstream mode — it is rejected at step 0.3.

A BRIEF's `upstream:` field holds nothing at all — its legal-parent set is
empty, and `shirabe validate` rejects any value it carries. A follow-up brief
born out of downstream work names what prompted it in prose rather than in
frontmatter; a link there would point down or sideways in the chain, which the
direction rule (`R10`) forbids.

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

Derive the slug as follows. In every case the derivation reads the POSITIONAL
argument only; the `--upstream` value is never an input to it.

1. If the positional argument is an upstream path, take the basename, strip
   the `ROADMAP-` prefix and `.md` suffix, and use the remainder.
2. If the positional argument is a freeform topic string, lowercase it,
   replace whitespace and underscores with `-`, and strip any character
   outside `[a-z0-9-]`.
3. If the positional argument is empty, ask the user to name the feature and
   re-derive from their answer -- even when `--upstream` supplied a ROADMAP.
   A roadmap's filename names the initiative, not the feature inside it, and
   naming the brief after it is exactly the conflation the flag exists to
   undo.

After derivation, test the slug against `^[a-z0-9-]+$`. If the slug is empty,
contains characters outside the allowed set after derivation, or starts/ends with
`-`, reject the invocation and ask the user for a clean slug. Do not fall through
to a "best effort" slug — silent normalization hides input the user did not intend.

## 0.3 Canonicalize the Grounding Path

If Phase 0 detected upstream-path mode, or `--upstream` supplied a value,
canonicalize the path before any read:

1. Resolve the path against the repo root (the working directory the skill was
   invoked from).
2. Resolve symlinks fully.
3. Verify the canonicalized path is still inside the repo working tree. Reject the
   invocation if it resolves outside (e.g., a symlink pointing to `/etc/passwd` or
   to a sibling repo).
4. Verify the file exists and is readable.
5. Verify the canonicalized path is under `<repo-root>/docs/roadmaps/`. This is
   the constraint the positional roadmap mode already carries, and applying it
   to the flag makes the two routes validate identically. A grounding file
   outside that directory is a scratch draft or a fixture, and grounding a
   durable brief's framing in one makes its provenance unreproducible.
6. Verify the basename starts with `ROADMAP-`. Other prefixes indicate the user
   pointed at the wrong artifact type and the problem/outcome derivation will
   misfire.

   **This check carries more weight than it used to.** A BRIEF records no
   `upstream:` (see "Reading a document vs. recording it as `upstream`" below),
   so nothing reaches frontmatter for a reviewer or the validator to catch a
   wrong-type input. The basename rule is now the only guard between pointing
   `/brief` at the wrong artifact and a brief whose problem and outcome were
   silently derived from it.

On any rejection, abort with a message that names the offending path and the
reason. Do not silently fall back to freeform-topic mode — the user provided a
path; misinterpreting it as a topic string would produce confusing downstream
behavior.

**A `PRD-` basename gets its own rejection.** A PRD is not a wrong-artifact
accident the way a DESIGN or a PLAN path is — it is the artifact directly
downstream of the brief, and pointing `/brief` at it inverts the chain. Reject
with:

> `<path>` is downstream of a BRIEF, not upstream of it. The tactical chain runs
> ROADMAP → BRIEF → PRD: a PRD's requirements are written from the brief's
> problem, outcome, journeys, and scope boundary, so deriving that framing back
> out of the PRD inverts the chain. Write the brief from the feature topic
> (`/brief <topic>`) or from the ROADMAP entry that names it
> (`/brief docs/roadmaps/ROADMAP-<name>.md`), then point the PRD at the brief.

Stop there. Do not offer to proceed with the PRD as upstream anyway. The same
rejection fires when the `PRD-` basename arrives as the `--upstream` value:
the flag records, and a recorded PRD inverts the chain whichever route it took
to get there.

One further check applies to a `--upstream` value:

- **Not under `wip/`.** Reject. `wip/` artifacts are non-durable — the
  wip-hygiene cleanup deletes them before the PR can merge — so a brief whose
  framing was derived from one has a provenance no reader can reproduce. Name
  the canonical location in the rejection.

**The tracked-by-git check does not apply here, and the omission is
deliberate.** Its reason was durability of a *recorded* link — "an untracked
upstream is durable to nobody but this working copy" — and a BRIEF records
nothing. What survives into the commit is the brief's own prose, so the input's
commit state stops mattering; an author walking the chain forward in one sitting
can ground a brief in a roadmap they have written but not yet committed. The
durability checks are record-time checks, and they still run wherever the flag
records: `/scope` runs them on the value it hands onward, and `/plan` runs the
whole set on the value it writes into the produced PLAN. The `docs/roadmaps/`
confinement above is what keeps the relaxation from widening the input class to
any untracked file in the tree.

A cross-repo value in the `owner/repo:path` form from
`references/cross-repo-references.md` is not a working-tree path: it skips
canonicalization and the directory confinement, keeps the `ROADMAP-` basename
rule on its file component, and is read for grounding like any other.

Do not silently drop a rejected `--upstream` value and continue: the author
asked for the brief to be grounded in that roadmap, and a run that quietly
produces an ungrounded BRIEF hides the failure until someone reads the framing
and wonders where it came from.

## Reading a document vs. recording it as `upstream`

Both roadmap routes — the positional path and the `--upstream` flag — **read**
the roadmap. Neither **records** it, and the two acts are not the same act.

The roadmap is read in Phase 1: the skill finds the feature this brief frames,
and derives the problem and outcome candidates from that feature's line item and
the roadmap's sequencing rationale. That is the whole value of supplying one, and
it is unchanged.

Nothing is written to `upstream:`, and the reason is what a BRIEF *is* rather
than what it happened to be handed. A BRIEF's legal-parent set is empty: it heads
its own tactical lineage. The rule behind that is in
`${CLAUDE_PLUGIN_ROOT}/references/pipeline-model.md` — a link runs from the
shorter-lived document to the longer-lived one, a ROADMAP is deleted when its
features land, and a BRIEF is durable. Recording the roadmap would produce a
reference correct on the day it is written and dangling on the day the cascade
runs, which `shirabe validate` now rejects as `R11`.

This mirrors how `/strategy` treats a grounding PRD: read for context, named in
prose, never recorded. It is also the same shape as the older rule for a public
document whose upstream is private — omit the field, absorb the context, stand
as the head of the chain. One obligation, reached by two different roads.

**Where the link does go.** In a `/scope` chain the roadmap reaches the produced
PLAN, which is itself deleted by the cascade and so cannot leave a dangling
reference behind. Nothing is lost; the crossing is recorded one altitude down.

**Announce it.** When a roadmap was supplied, say in the run output that the
brief was grounded in it and that no `upstream:` field was written, and why. An
author who passed a flag expecting a link should learn from the run that they
got framing instead.

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

## 0.5 Record the Artifact Decision

`/brief` always produces a standalone BRIEF. There is no branch here that
declines to write one.

Phase 0 records `## Artifact Decision` as `produce` in the context file (step 0.6)
and continues. The key is kept because downstream phases and the resume ladder read
it; it no longer has a second value.

**What changed and why.** An earlier revision decided here whether the framing
should live in its own document or be folded into the downstream PRD. The decision
had two defects that could not be fixed in place. It fired before any brief
existed, so nothing it read could tell whether the brief would have carried
something the PRD would not — the question it was trying to answer was not
answerable yet. And nothing received what it folded: the path recommended `/prd`
and named the content to carry forward, but `/prd` had no absorb step and no input
mode for folded framing, so a fold left the framing in the ephemeral source it was
supposed to be rescued from.

The reader-economy goal that path served is real, and it is now served where the
reduction can actually be verified. `/scope`'s Phase 2 runs a consolidation
judgment after each artifact lands: it reads the BRIEF and the PRD, checks
section by section that the PRD carries the brief's problem, outcome, journeys,
and boundary, and only then removes the brief. See the Consolidation Judgment
section of `skills/scope/references/phases/phase-2-chain-orchestration.md` and the
"Why the Artifact Set Shrinks" section of `skills/scope/SKILL.md`.

An author invoking `/brief` directly gets a brief and, at Phase 5, a
recommendation to run `/prd <brief-path>` — one command away from the chain that
can perform the reduction.

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
<cold | freeform | upstream-roadmap>

## Grounding Path
<canonical path, or "none">

## Topic Slug
<topic>

## Visibility
<Public | Private>

## Artifact Decision
produce

## Phase
0
```

This file is the resume-detection anchor for Phase 1 onward. Subsequent phases
update the `## Phase` line as they begin.

`## Entry Mode` classifies the positional argument, so a `--upstream` run
records whichever mode the remainder produced — usually `freeform`. The
flag's validated value is what `## Grounding Path` holds, and Phase 1 grounds
the problem/outcome candidate in it the same way it would for a positional
ROADMAP. The key is named for what it is: a path the run reads, not a value the
produced BRIEF records.

Do NOT commit the context file at this stage. The wip-hygiene rule treats `wip/`
artifacts as non-durable; the final cleanup at Phase 5 removes them before the PR
can merge.

## 0.7 Confirm Setup with User

Surface the detected context to the user in one short message:

> Setting up `/brief` for topic `<topic>`.
> Entry mode: <mode>. Visibility: <visibility>.
> Grounding: <path or "none">.

When a grounding path was supplied, add the omission announcement on the next
line. It is not optional — an author who passed `--upstream` expecting a link
learns here that they got framing instead:

> Recorded upstream: none. A BRIEF heads its own tactical lineage, so it records
> no `upstream:`; the roadmap grounds the problem and outcome instead, and the
> link to it is recorded on the PLAN this chain produces.

Do not block on confirmation for routine cases. If any detection produced an
unexpected value (visibility defaulted to Private because CLAUDE.md was missing),
call that out explicitly so the user can correct it before Phase 1 commits to a
direction.

## Quality Checklist

Before proceeding:
- [ ] `<topic>` slug matches `^[a-z0-9-]+$` and was derived from the positional
      argument alone, never from a `--upstream` value
- [ ] Grounding path (if provided) is canonicalized, inside the repo working
      tree, and under `docs/roadmaps/`
- [ ] Grounding file (if provided) exists and has a `ROADMAP-` basename; a
      `PRD-` basename was rejected with the chain-inversion message
- [ ] `--upstream` value (if provided) is not under `wip/`; a bare `--upstream`
      was rejected
- [ ] The run announced that no `upstream:` will be recorded, and why, whenever
      a grounding path was supplied
- [ ] Visibility is recorded (Public or Private, never empty)
- [ ] The artifact decision is recorded as `produce`
- [ ] `wip/brief_<topic>_context.md` exists with the keys above

## Artifact State

After this phase:
- Context file at `wip/brief_<topic>_context.md`
- No BRIEF draft yet
- No research files yet

## Next Phase

Proceed to Phase 1: Discover (`phase-1-discover.md`). Phase 0 has no exit branch —
every `/brief` run that reaches the end of this phase goes on to write a brief.

# Phase 5: Parent Handoff

Two arms share this file: the `/scope` arm and the `/charter` arm. Each writes
one handoff artifact and names the command the author runs next. Neither invokes
the parent, and neither writes a durable document — the parent's own chain does
that, one child at a time.

There is one skeleton here and two bindings of it, not two templates. Six
sections carry the same material for both parents. Exactly one block differs,
because exactly one question differs: `/scope` asks whether the framing shifted,
`/charter` asks whether the thesis is shifting. `/scope` carries one extra block
for shape signals that `/charter` has no analogue for, because `/charter` runs no
predicate walk.

## What the Handoff Carries

Conversation, never filesystem state.

The parent re-reads the tree itself on every run: which artifacts exist, what
their `status:` frontmatter says, what their content hashes are, what the repo's
visibility is, and whether a supplied upstream still validates. Writing any of
that here would hand the parent a second answer to a question it already answers,
and a stale one the moment the file is a day old.

**Predicate inputs, never predicate verdicts.** `/scope`'s Phase 1 walks three
shape predicates to size `/design`'s decision roster. The handoff carries the
evidence those predicates are computed from and never a verdict word. A verdict
in the file invites the parent to copy it instead of walking the predicate, and
the parent re-derives all three against the real PRD one child later anyway,
which is what makes carrying an estimate safe.

One predicate gets no material at all. The new-component predicate
cross-references component mentions against the repo's existing directory
structure, and that is a filesystem fact — the same class of claim the section
above bars. The parent computes it against the worktree in front of it.

## The Shared Skeleton

Six sections, in this order, in both bindings:

```markdown
# /<parent> Handoff: <topic>

## Provenance
Written by `/explore` on <date> from `wip/explore_<topic>_crystallize.md`.
Research files: `wip/explore_<topic>_findings.md`,
`wip/explore_<topic>_decisions.md` (if it exists), and
`wip/research/explore_<topic>_r*_lead-*.md`.
<One sentence on how the exploration ran: how many discover-converge rounds,
what the author narrowed along the way.>

## <Problem Statement | Theme Statement>
<2-4 sentences synthesized from the findings. Not raw research output.>

## Scope Boundary
### In scope
- <item the exploration put inside the boundary>

### Out of scope
- <item, with the reason it was excluded>

## Decisions Already Settled
<From wip/explore_<topic>_decisions.md: scope narrowings, option
eliminations, and priority choices the exploration made. The parent's chain
treats these as settled inputs to a conversation, not as recorded verdicts.
Omit the section when the decisions file does not exist.>

## Coverage Notes
<What the exploration did NOT answer that the chain should. Name the gaps
specifically; "needs more detail" is not a coverage note.>

## Upstream Observations
<Upstream documents the exploration read, and what it observed about them,
as prose. Paths named here are observations, not instructions: an upstream
the parent should consume travels as the --upstream flag on the command
below, where the parent's inbound validation reaches it.>
```

Then exactly one parent-specific block, per the binding below.

## `/scope` Binding

Write `wip/scope_<topic>_handoff.md`: the six shared sections, then both blocks
below.

```markdown
## Framing-Shift Answer
**Pre-supplied answer:** <yes, the framing shifted | no signal surfaced>
**Evidence:** <what in the exploration supports it — a changed problem shape,
a different target audience, a moved scope boundary, or a replaced success
criterion. Cite the round or finding.>

## Shape Signals
### Architectural alternatives left open
- <alternative the exploration surfaced and deliberately did not settle,
  with what each option would cost>

### Complexity signals
- <what the exploration found that speaks to the work's complexity: an
  explicit classification the author stated, prose naming architectural
  complexity, contested trade-offs that need settling>
```

No third subsection. Material for the new-component predicate is barred here for
the reason given above.

The framing-shift answer is the one carried value the parent does not re-derive,
and it can fire `/brief` against a BRIEF that is already settled. `/scope`
surfaces the question to the author as a confirmation and records the author's
response, not this file's. Write the answer as the author gave it during
exploration, with its evidence, so the confirmation has something to confirm.

**What the arm passes:** the topic slug, plus `--upstream <path>` naming a
ROADMAP when the exploration found one. `/scope` accepts a ROADMAP and enforces
the basename; nothing else belongs on the flag.

Tell the author:

> Wrote `wip/scope_<topic>_handoff.md`. Run `/scope <topic>` to walk the
> tactical chain (BRIEF, PRD, DESIGN, PLAN) with the exploration pre-loaded
> into discovery. Your research stays in `wip/`.

With a ROADMAP: `/scope <topic> --upstream docs/roadmaps/ROADMAP-<name>.md`.

## `/charter` Binding

Write `wip/charter_<topic>_handoff.md`: the six shared sections, then the one
block below.

```markdown
## Thesis-Shift Answer
**Pre-supplied answer:** <yes, the long-term thesis is shifting | no, this is
an operational layer below it>
**Evidence:** <what in the exploration supports it — a changed project
identity, a different audience, a new bet, or a strategic argument the
exploration produced. Cite the round or finding.>
```

No shape-signals block. `/charter` walks no predicates, so there is nothing for
one to feed.

`/charter` surfaces its thesis-shift question verbatim during discovery and
records the author's response, the same way `/scope` does with framing. The
pre-supplied answer is the prior the confirmation starts from.

**What the arm passes:** the topic slug, plus `--upstream <path>` naming a
VISION when the exploration found one. `/charter` accepts a VISION and enforces
the basename.

**A STRATEGY is not passed, on either arm.** The roadmap handler this file
replaces passed `--upstream <STRATEGY>` to `/roadmap`. That value has no
receiver now: `/charter` accepts only a VISION, and a chain entering at
`/charter` writes its own STRATEGY through `/strategy`. Handing one in would
hand a parent the artifact its own child produces. An exploration that found a
STRATEGY names it in the Upstream Observations section instead, as prose, and
the strategic chain reads it there.

Tell the author:

> Wrote `wip/charter_<topic>_handoff.md`. Run `/charter <topic>` to walk the
> strategic chain (VISION, STRATEGY, ROADMAP) with the exploration pre-loaded
> into discovery. Your research stays in `wip/`.

With a VISION: `/charter <topic> --upstream docs/visions/VISION-<name>.md`.

## Why the Arm Stops Here

Neither arm invokes its parent. The parent consumes the handoff through its own
resume ladder, below re-entry protection, and enters its own Phase 1 with the
file pre-loaded. That ordering is what lets a settled artifact on disk win over
a handoff written last week, and `/explore` cannot reproduce it by invoking the
parent mid-session.

The handoff is left on disk after the parent consumes it. A parent that bails at
Phase 1 does not delete it, so a later invocation reaches the same clause rather
than starting cold.

## Commit

Commit before naming the command: `docs(explore): hand off <topic> to /<parent>`

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- `wip/scope_<topic>_handoff.md` or `wip/charter_<topic>_handoff.md` (new)
- No durable document written; the session stops and the author runs the parent

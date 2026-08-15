---
schema: brief/v1
status: Accepted
problem: |
  A durable artifact's path changes when it reaches its terminal state, and
  `shirabe transition` rewrites only the moving document's own frontmatter.
  Every other document that named the old path in prose is wrong from that
  moment, and nothing checks. Frontmatter has R6, R10, and R11; prose has no
  equivalent, and prose is the only place some edges can be recorded at all.
outcome: |
  An author who relocates a durable artifact learns which documents still name
  its old path, and where the file went, before the change merges. A reader
  following a References section reaches a document that exists rather than a
  path that used to work.
---

# BRIEF: prose-reference-staleness

## Status

Accepted

The framing here is relocation, not deletion. The downstream PRD owns the
requirements; the design owns how a real reference is told apart from an
illustrative one.

## Problem Statement

Durable artifacts move. A DESIGN lands in `docs/designs/` while it's being
written, and `shirabe transition <design> Current` git-mv's it into
`docs/designs/current/` when it reaches its terminal state; supersession moves
it again, into `docs/designs/archive/`. Both moves are correct. The transition
rewrites the moving document's own frontmatter and updates its status. It does
not touch any other document.

So every document that named the old path is wrong the moment the move lands,
and nothing says so. For frontmatter that doesn't matter much: R6 reports a
dangling `upstream:` the next time the referring file is validated, and R10 and
R11 stop illegal edges from being written in the first place. Prose has nothing
like it. A `## References` entry reading `docs/designs/DESIGN-foo.md` is correct
on the day someone writes it and silently wrong on the day the cascade runs, and
no check reads it.

The References section is where a reader goes to follow the audit trail, and for
some edges it's the *only* place the trail can live. The `upstream:` legality
table won't let a BRIEF name a DESIGN, so a brief spawned by a parent design
records that parent in prose or not at all. The same holds for the surviving
frontmatter edge into a design: PLAN is the only format whose `legal_upstream`
includes DESIGN, and a PLAN is a working artifact the cascade deletes in the
same run that moves the design. The one legal inbound frontmatter link
disappears along with the move. Prose is what's left.

This is not a hypothetical. On the branch point, 19 prose occurrences across
tracked documents under `docs/` name a path that four designs have vacated —
`DESIGN-roadmap-plan-standardization` (10 of them),
`DESIGN-shirabe-progression-authoring` (4), `DESIGN-shirabe-scope-skill` (4),
and `DESIGN-shirabe-artifact-decision-contract` (1). Two more sit in instruction
files under `skills/`. Every one of those documents validates clean today.

The problem is stale paths after a relocation, and only that. Nothing has been
deleted. A related investigation started from the belief that a design had been
removed and three `upstream:` references stranded; the rename record says
otherwise, and the file is on disk at `status: Current`. A check built against
the deletion framing would be looking for something that doesn't happen.

What makes this hard rather than tedious is that a path that looks like a
reference is often an example. Instruction files and format references are full
of artifact-shaped paths that must never be flagged — `docs/designs/DESIGN-foo.md`
appears eleven times inside `docs/` alone, `PLAN-foo.md` twelve, and roughly
thirty more one-off fixture names besides. A check that resolves every
artifact-shaped path against disk fires on all of them, and a check that fires
on all of them gets turned off.

## User Outcome

A shirabe author moves a design to its terminal state and finds out, before the
change merges, that five other documents still name the path it left. The
finding names each one and where the file went, so the fix is a search and
replace rather than an investigation.

A reviewer opening a PRD's References section clicks through to the design it
cites and lands on the design. The audit trail holds across the transition that
would otherwise have broken it, which is the whole reason the section exists.

An author writing an example path into a skill file gets nothing. Writing
`docs/designs/DESIGN-foo.md` in a template, a fixture name in an eval, or a
worked example in a format reference produces no finding, because no document
has ever lived at that path for the reference to have gone stale against. The
check earns its place by being quiet about everything except a real reference to
a real document that really moved.

And a maintainer deciding when to make this an error can count first. The rule
runs across every tracked document, not just the ones a pull request touched, so
the corpus figure behind the severity is a measurement rather than a guess.

## User Journeys

### Transitioning a design to Current

An author finishes a design, runs `shirabe transition
docs/designs/DESIGN-thing.md Current`, and the file moves into
`docs/designs/current/`. Validation on the branch reports that three documents
still name the pre-move path, naming each file, the line, and the path the
document now lives at. The author updates the three references in the same
change. Before this, the transition succeeded quietly and the three references
rotted until a reader tripped over one.

### Following a reference as a reviewer

A reviewer reading `PRD-cascade-outline-ac-completeness.md` reaches its
References section, which cites the design that settled the sequencing rule the
PRD depends on. The path resolves. The reviewer opens the design and reads the
decision. Today that path is one of the ten stale ones, and the reviewer's next
move is a repo-wide search for the basename.

### Writing an example path into a skill file

A skill author documents an input mode and writes `/prd
docs/designs/DESIGN-foo.md` as the worked example. The example is illustrative:
no such document exists and none ever will. Validation says nothing about it,
now and after any future promotion of the check's severity. The author never
learns the check exists, which is the correct outcome for an example.

### Sizing the cleanup before turning the check red

A maintainer preparing to promote the check from a notice to an error runs it
over every tracked document and gets a count and a file list. The count tells
them how much cleanup stands between here and a red build, and the list is the
cleanup. Pull-request CI only ever validated changed files, and that blind spot
is what let 19 stale references accumulate unnoticed in the first place.

## Scope Boundary

**In scope.**

- Detecting prose references — `## References` entries and body text — that name
  the pre-move path of a durable artifact which still exists somewhere else in
  the tree.
- Telling a real reference apart from an illustrative one, reliably enough that
  the check can run against instruction files as well as corpus documents. Both
  populations contain both kinds, so this is the load-bearing part of the work
  rather than a refinement of it.
- Reporting where the document went, not just that the path is wrong. A finding
  that names the new path is a fix; one that doesn't is a search.
- A corpus-wide measurement of what the rule finds, taken before the severity is
  chosen and again after any change, since pull-request CI validates only
  changed files.
- Staging the severity so the check can ship against a corpus that isn't clean
  yet, and a plan for the cleanup that unblocks promotion.

**Out of scope.**

- **Rewriting inbound references at move time.** `shirabe transition` knows both
  paths and could repoint every referrer as it moves the file. That's the
  prevention half, it's the more invasive of the two, and detection is worth
  having on its own — it surfaces the references that are already stale, which
  prevention never will. Detection first is a sequencing call, not a rejection.
- **References to documents that never existed or were deleted.** A prose path
  naming a deleted PLAN or a roadmap the cascade removed is a different fault
  with a different cause, tracked separately as durable documents naming
  ephemeral ones. It's noticeably the larger population, and folding it in here
  would change what the check is for.
- **Bare basename mentions.** A document referred to by filename alone, with no
  directory component, survives a relocation untouched — there's no path to go
  stale. The 171 such mentions under `docs/` are outside this feature whether or
  not they're good style.
- **Fixing the stale references themselves.** The cleanup is real work that this
  framing sizes but doesn't perform; whether it lands with the check or after it
  is a planning decision downstream.
- **A new CLI subcommand.** Correctness rules belong in `shirabe validate` as a
  check or a mode. A subcommand that renders or creates is an anti-pattern this
  repo has already reverted once.

## References

- `crates/shirabe-validate/src/formats.rs` — the `legal_upstream` table that
  makes PLAN the only format able to name a DESIGN in frontmatter, and so the
  reason the surviving exposure is entirely in prose.
- `crates/shirabe-validate/src/validate.rs` — `is_intrinsic_notice`, the
  one-line promotion seam the staged checks already use.
- `docs/designs/current/DESIGN-roadmap-plan-standardization.md` — the relocated
  design that ten of the stale prose references still name by its old path.

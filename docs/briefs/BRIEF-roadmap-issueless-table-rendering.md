---
schema: brief/v1
status: Done
problem: |
  A roadmap populated by `shirabe roadmap populate --no-issues` produces an
  Implementation Issues table whose rows can't be read on their own terms: an
  opaque `F<n>` key, and a description row that is an unbounded slice of the
  feature's prose. The keying also contradicts the shared roadmap-profile spec.
outcome: |
  An author populating a roadmap in issueless mode gets a table that reads
  top-to-bottom without cross-referencing the Features section, with a
  description cell that is a description, and the tool's documentation agrees
  with the shared spec about what that table looks like.
motivating_context: |
  Reported as tsukumogami/shirabe#261 after a 21-feature roadmap was populated
  in issueless mode and every row came back unidentifiable. The report's second
  finding restates #232 item 2, closed as completed a month earlier, which makes
  the question of what was actually fixed then part of the framing.
---

# BRIEF: Roadmap issueless table rendering

## Status

Done

Framing for the two rendering defects reported in #261. The downstream PRD owns
the requirements; the two contested choices this brief leaves open (which side of
the key-column contradiction changes, and where an over-long description is
handled) are named in Open Questions and resolve in the PRD's Decisions and
Trade-offs section.

## Problem Statement

A roadmap that opts out of per-feature GitHub issues gets its two reserved
sections filled by `shirabe roadmap populate --no-issues`. The Implementation
Issues table that comes back is not readable on its own terms.

Every row is keyed `F1`, `F2`, `F3`. That's an index whose meaning lives in a
different section of the same document. In issueless mode the `Issues` column
carries a `needs-*` label or `None` rather than an issue link, so the two columns
a reader would use to identify a row carry no human-readable name between them.
The description row underneath is supposed to supply the missing context, but
it's derived from the feature's prose body by a heuristic with no ceiling: it
takes the `**Functional outcome:**` sentence when one exists, and the body's
first sentence otherwise. A feature whose body opens with a bullet list, or with
a long semicolon-chained paragraph, has no early sentence terminator, so the
whole opening block lands in the cell. Nothing downstream catches it. `shirabe
validate` checks the table's shape, not its cell lengths, so the run reports
clean.

The keying is also a documentation contradiction rather than an oversight.
`references/issues-table.md` specifies the roadmap profile's key form as the
feature label; `populate --help` and `skills/roadmap/references/roadmap-format.md`
both document the `F<n>` form as intended. Whichever form is correct, a reader
who consults one document and an implementer who consults another end up
disagreeing, and the disagreement stays invisible until someone runs the tool and
reads the output.

The two defects compound. Either alone would leave a reader one workaround away:
an opaque key is tolerable when the description names the feature, and a long
description is tolerable when the key names it. Together they leave a row with no
identifier anywhere and a paragraph where a summary belongs. Authors work around
it by starting every feature body with the feature's own name, so the generated
description leads with it, which asks the author to restate a label the tool
already holds.

## User Outcome

An author populates a roadmap in issueless mode and reads the resulting table
without leaving it. Each row names its feature; each description says what that
feature delivers in a sentence or two; the dependency cells point at names the
reader has already seen in the same table. Nothing about the output asks the
reader to scroll back to the Features section to work out what a row refers to.

When a feature's prose does not yield a usable summary, the author does not end
up holding an unreadable roadmap. They learn at the moment they populate — not
months later when someone tries to read the table — which feature needs
attention.

An author who checks the format documentation before writing a roadmap finds one
answer about what the Implementation Issues table looks like, whichever document
they open.

## User Journeys

### Populating a fresh issueless roadmap

A maintainer of a repo that declares `## Roadmap Issues: optional` finishes
authoring a roadmap's Features section and runs `shirabe roadmap populate
--no-issues docs/roadmaps/ROADMAP-<name>.md`. The reserved sections fill in. They
read the Implementation Issues table straight through: each row leads with the
feature it names, each description is a sentence or two, each dependency cell
names features they have just read. They commit the roadmap without editing the
generated sections, which is the contract those sections carry.

### Reviewing a populated roadmap on the PR that adds it

A reviewer picks up the pull request that introduces the roadmap and has to
judge whether the sequencing holds up, without having sat in the authoring
conversation. They go to the Implementation Issues table because it is the
compact view. They can tell which feature each row is about, what blocks it, and
what state it is in, without cross-referencing the Features section above. The
dependency graph immediately below tells them the same story in a second form,
and the names in the two agree.

### Populating a roadmap whose feature bodies do not summarize well

An author's feature bodies open with bullet lists rather than a topic sentence.
They run populate. They come away knowing which features could not be summarized
cleanly and what to do about it, and they are not left with a roadmap nobody can
read. The author either accepts what was generated or adds a
`**Functional outcome:**` line to the features they care about and re-runs.

### Checking what the table is supposed to look like

A contributor implementing something adjacent — a validator check, a migration,
another renderer — reads `references/issues-table.md` to learn the roadmap
profile's shape, then reads `populate --help` to see what the tool does. The two
agree. They do not have to run the tool to find out which document is stale.

## Scope Boundary

**In:**

- The Implementation Issues table rendered by `shirabe roadmap populate
  --no-issues`: what its key column carries, and what its dependency cells carry
  as a consequence.
- The description-row derivation shared by both populate modes, and what happens
  when a feature body does not yield a short summary.
- Reconciling `references/issues-table.md`, `skills/roadmap/references/roadmap-format.md`,
  and the `populate --help` text so all three describe the same table.
- Establishing whether the description defect is a regression or a fix that never
  covered this path, and recording the answer where a future reader will find it.
  The answer is recorded either way; a verdict of "regression" does not reopen
  the other findings in the report that closed it.
- Regression coverage for both defects.

**Out:**

- The three other findings in #232 (plural dependency forms dropping edges,
  `Status:` mangling, diagram node ids versus the shared bijection convention).
  They are separate reports against the same subsystem and are not part of this
  framing.
- Issue-creating (non-`--no-issues`) populate mode, except where the two modes
  share a code path and changing it for one necessarily changes it for both.
- The `Issues` column's issueless-mode contents. Carrying a `needs-*` label in a
  column the spec describes as an issue fan-out is a third divergence between
  the implementation and the spec, and it is a different question from the key
  column's — it is called out here so a reader knows it was seen and left alone.
  Leaving it alone is also why the key column is the only place a row's name can
  go.
- New validator checks. Whether `shirabe validate` should reject an over-long
  description cell is a validation-surface question; this feature is about what
  the renderer produces.
- Whether issueless mode should exist. That was settled in
  `docs/designs/current/DESIGN-roadmap-issueless-preference.md`.

## Open Questions

1. **Which side of the key-column contradiction changes?** Either the renderer
   emits the feature label and `populate --help` plus the roadmap format
   reference are corrected, or `F<n>` is affirmed as correct for issueless mode
   and `references/issues-table.md` gains a carve-out. Both are coherent; the
   downstream PRD picks one and the losing document changes to match.
2. **Where is an over-long description handled?** Either the renderer bounds the
   cell it emits, or it leaves the cell alone and tells the author the feature
   body needs a shorter opening. The choice determines whether a roadmap can
   ever contain a multi-thousand-character cell again.

## References

- `references/issues-table.md` — the shared issues-table framework; the Roadmap
  Profile section specifies the key form under dispute.
- `skills/roadmap/references/roadmap-format.md` — the roadmap-specific format
  reference; its Reserved Sections section documents issueless-mode population.
- `docs/designs/current/DESIGN-roadmap-issueless-preference.md` — the design that
  introduced issueless mode and chose bare-key dependency cells.
- `docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md` — the precedent for
  framing a reconciliation defect of this size as a brief.

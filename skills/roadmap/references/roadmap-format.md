# Roadmap Document Format Reference

Structure, lifecycle, validation rules, and quality guidance for
Roadmap documents. The roadmap profile of the shared issues-table
framework owns the Implementation Issues shape; the shared
dependency-diagram convention owns the mermaid graph. This file
carries the roadmap-specific deltas, lifecycle, and quality guidance.

## Table of Contents

- [Shared References](#shared-references)
- [Frontmatter](#frontmatter)
- [Required Sections](#required-sections)
- [Milestones](#milestones)
- [Reserved Sections](#reserved-sections)
- [Content Boundaries](#content-boundaries)
- [Lifecycle](#lifecycle)
- [Validation Rules](#validation-rules)
- [Quality Guidance](#quality-guidance)

## Shared References

Both the issues-table format (roadmap profile) and the
dependency-diagram convention live at the plugin root and are
consumed by both the roadmap and plan workflows:

- `${CLAUDE_PLUGIN_ROOT}/references/issues-table.md` -- the shared
  issues-table framework. The roadmap profile keys on features with
  the `Feature | Issues | Dependencies | Status` shape, the `Issues`
  fan-out column listing the issue links the feature decomposed into,
  and the migration rules for the divergent committed shapes
  (`Feature | Status | Downstream Artifact` and `Issue | Phase |
  Dependencies | Label`). This reference owns table shape, description
  rows, and strikethrough rules.

- `${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md` -- the
  shared dependency-diagram convention. Owns the mermaid syntax
  rules, the fixed status-class palette, node format, class
  assignment, initial status, status updates, and legend.

- `${CLAUDE_PLUGIN_ROOT}/references/workflow-principles.md` -- the
  five principles both workflows derive from. A roadmap is multi-pr
  because each feature delivers observable incremental value (P1),
  not because "the input is a roadmap."

## Frontmatter

Every roadmap begins with YAML frontmatter:

```yaml
---
schema: roadmap/v3
status: Draft
theme: |
  1 paragraph describing the overarching theme or initiative this
  roadmap tracks. What capability area is being built out, and why
  does it need coordinated sequencing across multiple features?
scope: |
  1 paragraph bounding what's included and excluded. Which features
  are in this roadmap, and what adjacent work is deliberately left out?
upstream: docs/strategies/STRATEGY-<name>.md  # optional
---
```

Required fields: `schema`, `status`, `theme`, `scope`. `schema` is
`roadmap/v3` for a milestone roadmap, which is what `/roadmap` writes (see
[Milestones](#milestones)); `roadmap/v2` for a milestone roadmap written
before v3, whose items keep the feature words; or `roadmap/v1` for one in
the per-feature format below. All three stay valid. Optional:
`upstream` (path to the STRATEGY document that this roadmap sequences
the work for, when one exists). Each field other than `schema` should
be 1 paragraph using YAML literal block scalars (`|`).

The `upstream` field links the roadmap to the strategic artifact that
motivated it. When present, it points to a **STRATEGY** -- the
roadmap's immediate neighbour one level up the strategic chain, which
runs VISION -> STRATEGY -> ROADMAP. `/charter` sets it this way on
every chain it runs, so a STRATEGY upstream is the common case.

Point it at the immediate neighbour, not at whatever strategic
document happens to be handy. A ROADMAP whose upstream skipped to the
VISION would leave the bet it is sequencing unreachable from the
roadmap: a reader would jump from sequenced features straight to the
long-term thesis, with the falsifiable claim that chose those features
missing from the path. The links stay one level deep in both
directions -- a STRATEGY's Downstream Artifacts list ROADMAPs, and a
ROADMAP's upstream is that STRATEGY -- so the chain reads the same
walked either way.

A roadmap written without a STRATEGY -- one that emerged from
exploration, or that traces only to a VISION -- omits the field
rather than reaching past its neighbour. Recording the VISION here
would claim a link the chain does not have.

**This is what `/roadmap` writes, not what `shirabe validate`
enforces.** The validator accepts a ROADMAP naming either a STRATEGY
or a VISION, because it decides legality from two basenames and
cannot tell a roadmap that reached past an existing strategy from one
written where no strategy exists -- and rejecting the second in order
to catch the first would fail the legitimate case. So a
vision-naming roadmap found in an existing corpus validates clean;
that is a limit on what the check can know, not an endorsement. The
rule above is still the rule for anything this skill produces.

The ROADMAP is the last link in the strategic chain. Downstream of it
the tactical chain takes over: `/brief` crosses the boundary by reading
a ROADMAP for framing and recording that roadmap's own parent, while
the produced PLAN is what names the ROADMAP itself -- a durable
document may not name a ROADMAP the cascade deletes, and the PLAN is
deleted first. No strategic document reaches past the ROADMAP to a
BRIEF, PRD, DESIGN, or PLAN.

**Two written shapes are supported for `upstream:`.** A scalar -- the
path on the key's own line -- and a sequence, written either as `- `
entries on the following lines or inline as `[<path>, <path>]`. Every
entry of a sequence is read, in written order, and a single-entry
sequence is still a sequence. Reach for the sequence when the document
genuinely has more than one parent; the scalar otherwise. Nothing else
is supported: a scalar is never split, so two paths on one line read as
one entry that resolves to nothing.

For cross-repo upstream references and the visibility-direction rules,
see `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md`.

Frontmatter status must match the Status section in the body --
agent workflows parse frontmatter to determine lifecycle state, so
divergence causes silent errors.

## Required Sections

Every roadmap has these sections in order:

1. **Status** -- current lifecycle state
2. **Theme** -- what initiative this roadmap coordinates and why
   sequencing matters
3. **Milestones** on a `roadmap/v3` roadmap, **Features** on `roadmap/v1`
   and `roadmap/v2` -- the items section: ordered list of features with
   names, descriptions, dependencies, and status. Each item should reference its
   downstream artifact (brief, PRD, design doc, or plan) when one
   exists. These per-feature entries are how the tactical chain is
   reached from the strategic one -- the roadmap is the only place
   the two meet, which is why no document above it links a brief,
   PRD, design, or plan directly.
4. **Sequencing Rationale** -- why features are ordered this way.
   What constraints drive the ordering: technical dependencies, user
   value delivery, risk reduction? On a one-feature roadmap there is
   no ordering to justify; the section instead says why this feature
   is the whole of the strategy's work and what would have to change
   for a second feature to join it.
5. **Progress** -- current state of the roadmap. Which features are
   done, in progress, or not started. Updated as work progresses.
   This is the ledger: it, and the per-feature statuses it mirrors,
   are the only record of how far along the strategy's execution is.

### Per-Feature Format

Each feature in a `roadmap/v1` roadmap's Features section follows this
structure (a milestone roadmap, `roadmap/v2` or `roadmap/v3`, uses the
milestone format in
[Milestones](#milestones)):

```markdown
### Feature 1: Recipe validation pipeline
**Needs:** `needs-design` -- architecture for validation stages undecided
**Dependencies:** None
**Status:** Not started

### Feature 2: Version resolution caching
**Needs:** `needs-spike` -- feasibility of SQLite cache unknown
**Dependencies:** Feature 1
**Status:** Not started
```

The `Needs` annotation is optional. Features without it are treated
as ready for direct implementation. When present, it determines which
`needs-*` label gets applied during issue creation.

#### Heading forms

A feature heading uses one of two forms:

- **Classic:** `### Feature <N>: <label>` -- the default, where `<N>`
  is the 1-based feature number. On a `roadmap/v3` roadmap the word is
  `Milestone`: `### Milestone <N>: <label>`. Each version reads only its
  own word, so `### Feature 3:` is no item on v3 and `### Milestone 3:` is
  none on v1 or v2 (on a milestone roadmap FC21 reports such a line).
- **Strategy-derived prefix:** `### <PREFIX><N>: <label>` -- a short
  alphabetic tag immediately followed by the feature number, no space
  between them (e.g. `### ED1:`, `### SE2:`, `### SR10:`, `### NW1:`),
  optionally followed by one lowercase letter for an item split out of
  another (`### AB10a:`).
  This variant fits product-spanning roadmaps derived from a strategy,
  where a per-direction prefix keeps features grouped by their strategic
  building block.

Both forms are equivalent to the tooling: features are numbered
positionally in source order regardless of the tag, and the generated
tables and graph name them `F<n>` by that position, on every version.
`F<n>` is the position alias the populated tables and the Dependency Graph
use, and it means the same item whether the headings say `Feature`,
`Milestone` or a prefix. Where a Dependencies line is read as prose (by
populate and the coordinator's roadmap reader), it may name another
feature three ways:

- by its tag (`ED1`, `AB10a`), a whole word equal to the tag;
- by `Feature <N>`, in any case, singular or plural, with a list of
  numbers (`Features 2, 3 and 5`): the item tagged `Feature <N>` (compared
  as a number, so `feature 02` finds `Feature 2`), else the Nth item by
  position;
- on a `roadmap/v3` roadmap only, by `Milestone <N>` read the same way with
  its own word. There the capitalized words also cross: before falling back
  to position, `Feature <N>` finds the item tagged `Milestone <N>` (the
  number exactly as written; see [Feature N and Milestone
  N](#feature-n-and-milestone-n)), so prose written before a roadmap moved
  from v2 to v3 keeps resolving;
- by `F<N>`: the item tagged `Feature <N>` (on v3, `Milestone <N>`) when
  there is one (an item tagged `F<N>` itself is found by its tag), else the
  Nth item.

On v1 and v2 the milestone words name nothing, exactly as before v3
existed. A v1 roadmap's Dependencies line is free prose that no check holds
to tags, so a phrase such as `None (lands after the upstream milestone 3)`
must not become an edge.

On a milestone roadmap FC21 is stricter and takes only another
milestone's exact tag, so write the tag there. Pick one form per roadmap
and use it consistently.

## Milestones

A roadmap whose frontmatter reads `schema: roadmap/v3` or
`schema: roadmap/v2` is a milestone roadmap: every item in its items
section is a milestone, an outcome someone can exercise end to end, with a
check someone other than the session that delivers it can judge.

The two versions differ only in their words:

| | `roadmap/v3` | `roadmap/v2` |
|---|---|---|
| Items section | `## Milestones` | `## Features` |
| Classic heading | `### Milestone <N>: <title>` | `### Feature <N>: <title>` |
| Populated table's key column | `Milestone` | `Feature` |

Every field, every rule below and every reading the tools make is the
same on both. `/roadmap` writes `roadmap/v3` by default. A `roadmap/v2`
roadmap and a per-feature `roadmap/v1` one stay valid and validate exactly
as before; nothing nudges either to migrate.

### The milestone fields

```markdown
### Milestone 2: A maintainer finds a plugin by name

**Outcome:** A maintainer who installed three plugins runs `widgets list`
and sees each one by name, with the version it loaded, without reading the
plugin directory by hand.

**Evidence:**
- A reviewer, from a clean install with the three sample plugins, runs
  `widgets list` and sees exactly those three names and versions.
- The same reviewer removes one plugin's manifest and sees `widgets list`
  name the plugin it skipped and why, and exit non-zero.

**Left open:** the registry's storage format and the command's output
layout.

**Needs:** `needs-design` -- the registry shape
**Dependencies:** Milestone 1
**Status:** Not started
```

The heading is `### <tag>: <title>`, with a space after the colon and a
non-empty title. The tag is the version's classic tag (`Milestone <N>` on
v3, `Feature <N>` on v2) or a prefix tag, letters followed by a number
and, optionally, one lowercase letter (`AB1`, `AB10a`), as in [Heading
forms](#heading-forms). `### Milestone 3a:`, `### milestone 3:` and
`### Milestone:` are not milestone headings. A field line starts at
column 0 with `**<Name>:**`, and its value runs to the first blank line,
the next field line or the next heading. Write the fields in this order:

- **Outcome** -- who can do what, end to end, that they couldn't before.
  For a removal, a migration or a contract, the invariant that holds
  ("nothing visible changed and the old command is gone"). Never the merge
  that delivered it, and never the mechanism: a command, file or component
  to build belongs in Left open or in the design.
- **Evidence** -- one or more clauses, each a `- ` line at column 0 (wrap
  a long clause onto indented lines), each following [the Evidence
  rule](#the-evidence-rule) below.
- **Left open** -- the how-decisions that belong to the session that does
  the work (names, layouts, mechanisms), so nobody reads an example as a
  commitment; `None` when nothing is. It never holds part of the Outcome:
  anything whose absence would make the Outcome false is in the Outcome,
  unmet, or is a milestone of its own.
- **Needs** -- optional, as in the per-feature format.
- **Dependencies** -- one line: `None`, or a comma-separated list whose
  every entry is another milestone's tag or a cross-repo issue reference
  `<owner>/<repo>#<n>`. Soft ordering and the reasons behind an order go
  in the Sequencing Rationale, not here.
- **Status** -- exactly `Not started`, `In progress`, `Done` or `Dropped`.
- **Delivered** -- optional; the pull requests that delivered the work,
  added as they merge. It is what landed, never the promise: the Outcome
  stays as written. In a public roadmap it names only public pull requests
  and issues; nothing checks that yet (a mechanical guard is tracked in
  #682), so whoever writes the line keeps to it.

Other field lines (a `**Downstream:**` line, for example) and prose after a
blank line are allowed; they belong to no milestone field.

A Dependencies entry is matched against the other milestones' tags
exactly: `Milestone 2` names the milestone tagged `Milestone 2`, `AB1` the
one tagged `AB1`. `F2` and a bare position are not tags here. The populated
tables and the Dependency Graph still number milestones `F<n>` by
position, as on any roadmap.

### The Evidence rule

Each Evidence clause says, in this order of importance:

- **who checks** -- a reviewer, a maintainer, the person the Outcome is
  for; never the session that delivered the work;
- **from what start** -- a clean install, a fresh workspace, the session
  shape users actually hit;
- **what they do** -- the command they run, the page they open, the steps
  of a walkthrough;
- **what they see** -- the observable result that shows the Outcome holds,
  including what a refusal looks like.

A command with expected output, a scripted or end-to-end check, a
walkthrough a person follows, and an invariant with a negative clause for
refusals all count. A merged pull request, "tests pass", an artifact
existing, the author's say-so, or a judgment like "works well" don't.

A clause never names the file, script, function or line that implements
the check or the feature. Those are mechanism: the session doing the work
decides them, they move when the code moves, and a reader can't judge the
Outcome from them. When the check needs a tool that doesn't exist yet,
the clause describes what the checker does and sees, and the tool's name
and shape go in Left open.

Allowed:

```markdown
- A reviewer, from a clean install with the three sample plugins, runs
  `widgets find search` and sees the search plugin's path; for a plugin
  that isn't installed, a message naming it and a non-zero exit.
```

Not allowed:

```markdown
- `scripts/check-find.sh` passes, and `registry.rs:find_plugin` returns
  the path from the cache file.
```

The second names a script, a function and a file instead of saying who
checks, from what start, and what they see; its mechanism belongs in Left
open ("the registry's storage format and the find command's
implementation"), and the clause should read like the first.

### Feature N and Milestone N

The readers treat the two classic words as one tag where a record names an
item. A coordinator's record or a verdict that says `Feature 2` matches the
item tagged `Milestone 2` on a v3 roadmap, and one that says `Milestone 2`
matches the item tagged `Feature 2` on a v2 roadmap, so nothing written
under one word stops matching when a roadmap moves to the other. Dependencies
prose crosses one way only, on v3: `Feature 2` there names the item tagged
`Milestone 2`, while on v1 and v2 the milestone words name nothing (see
[Heading forms](#heading-forms)). The match compares the tag as written:
exactly one space and the number's digits, so `Feature 03` is not
`Milestone 3`, `feature 2` is not `Milestone 2`, and `Feature 1` is never
`Milestone 14`. A prefix tag (`AB1`) matches only itself.

FC21 doesn't apply the equivalence. It holds a milestone roadmap's own
headings and Dependencies entries to the version's word, and on v3 names
the `Milestone` spelling when an author writes `Feature`.

### When a milestone is Done

A milestone is Done only on a verification verdict from the human or the
coordinator that dispatched the work, never from the session that
delivered it. The checker judges the shipped work against the milestone's
Evidence and against the strategy the roadmap serves, and records one of
three verdicts:

- **changes needed** -- a clause doesn't hold or the work doesn't fit the
  strategy; the milestone stays In progress.
- **verified with follow-ups** -- every clause holds, and what the work
  revealed becomes new or amended milestones.
- **verified** -- every clause holds, with nothing to follow up.

Either verified verdict sets the Status to Done, and every follow-up
milestone the verdict names is added to the roadmap in the same edit that
sets Done. A verdict is verification, not approval: merging stays wherever
the repository's permissions put it.

On a roadmap a coordinator drives, the tools hold to this rule. When a
milestone's work is finished, `/coordinate` doesn't write Done: it marks
the verdict owed, and its verdict step checks the shipped work against
each Evidence clause and posts the verdict on its record. Then
`roadmap-status.sh --verdict` opens the one roadmap pull request the
verdict calls for. For either verified verdict that pull request sets Done
and adds any follow-up milestones; for changes needed it leaves the Status
alone. Either way it adds a Progress line naming the verdict, the checker
and the entry. Merging that pull request is what sets Done, and nothing else does:
the coordinator writes no status when work merges, and the completion
cascade leaves a milestone roadmap untouched, recording its roadmap step
as `skipped`. (The cascade edits only a `roadmap/v1` roadmap or one with
no `schema:` line; any other schema, including one it doesn't know yet, is
left alone.) The coordinator never merges the verdict's pull request, so
whoever merges it reviews the verdict; a repository that auto-merges
roadmap edits gives that review up. On a roadmap nobody coordinates, the
person editing it keeps to the rule: `shirabe validate` checks the
fields, not where a Done came from.

Done can be taken back. When a milestone that reads Done is found to fail
a clause of its Evidence, the coordinator records the failure and
`roadmap-status.sh --reopen` opens a roadmap pull request that returns it
to In progress, with a Progress line naming the clause and who reported
it. Once that merges, the milestone is offered for work again, and the
milestones that depend on it read blocked until a new verdict sets it
Done.

### What may change while it is Active

An Active milestone roadmap may change in place in exactly these ways:

- a milestone's Evidence or Left open is sharpened (`/roadmap` offers this
  on an Active milestone roadmap; the procedure is
  `references/phases/sharpen.md`);
- a milestone's Status and Delivered change through the verdict and
  reopen edits above;
- the follow-up milestones a verified-with-follow-ups verdict names are
  added in the same edit that sets Done, and the milestones it amends take
  their new Outcome, Evidence and Left open in that edit too;
- an Outcome is narrowed, together with a line in Progress that says so:

  ```markdown
  - YYYY-MM-DD: <tag> Outcome amended -- <what changed and why>
  ```

Any other change to the items section -- adding, removing, reordering
or retitling a milestone, changing its Dependencies, widening its Outcome
-- or to the Sequencing Rationale needs a new roadmap, as on a
`roadmap/v1` roadmap. The coordinator's roadmap edits stay inside these
rules, but nothing checks a hand edit against them.

### Validation (FC21)

On a milestone roadmap, `shirabe validate` runs FC21, an error-level
check that names the milestone it fires on (`[FC21] milestone 'Milestone
2: Registry' has no Evidence`). It reports:

- an Outcome that is missing or empty;
- Evidence that is missing, or has no `- ` clause;
- a missing Left open, Dependencies or Status;
- a Dependencies line that continues onto the next line, or names an entry
  that is neither another milestone's tag nor `<owner>/<repo>#<n>`;
- a Status other than `Not started`, `In progress`, `Done` or `Dropped`;
- a tag that repeats an earlier milestone's;
- a `###` heading in the items section that isn't a milestone heading,
  including one with no title or no space after the colon (`### AB2:Lister`).

On `roadmap/v3` it also names the v2 word where an author wrote it:

- a `## Features` section (whose headings no reader takes as milestones;
  FC04 reports the missing `## Milestones` alongside it);
- a `### Feature <N>:` heading, naming the `### Milestone <N>:` to write;
- a `Feature <N>` Dependencies entry, naming `Milestone <N>` when that
  milestone exists, and otherwise reporting it as naming no other
  milestone.

FC21 checks that the fields are there, not what they say: whether an
Outcome names mechanism or an Evidence clause is something only the author
could judge is the `/roadmap` jury's call (the jury applies [the Evidence
rule](#the-evidence-rule)). A `roadmap/v1` roadmap never gets FC21 and gets
exactly the findings it got before `roadmap/v2` existed, and a `roadmap/v2`
roadmap gets exactly the findings it got before `roadmap/v3` existed.

### Migrating a roadmap

Nothing has to migrate. `roadmap/v1` and `roadmap/v2` stay valid, the
tools read them as they always did, and nothing nudges an author to move
one. When an author wants the milestone words, the moves are these.

**From `roadmap/v2` to `roadmap/v3`**, change exactly four things:

1. the `schema:` line to `roadmap/v3`;
2. the `## Features` heading to `## Milestones`;
3. each `### Feature <N>:` heading to `### Milestone <N>:` (prefix-tagged
   headings such as `### AB1:` stay as they are);
4. each `Feature <N>` Dependencies entry to `Milestone <N>`.

Nothing else moves: Outcome, Evidence, Left open, Status, Delivered,
Progress lines and the reserved sections stay as written (the next populate
run changes the table's key header to `Milestone`). Records that name
`Feature <N>` keep matching (see [Feature N and Milestone
N](#feature-n-and-milestone-n)). `shirabe validate` names any heading or
entry the rename missed.

**From the per-feature format to a milestone roadmap**: a roadmap already
written with these fields becomes one by changing its `schema:` line
(`roadmap/v3` with the four changes above, or `roadmap/v2` without them);
`shirabe validate` then names anything that doesn't fit. A roadmap that
recorded merged pull requests on an `**Outcome:**` line renames that line
`**Delivered:**` and writes the item's real outcome in its place. Nothing
else needs to move: the tables, the Dependency Graph and the coordinator
read every version.

## Reserved Sections

Two sections follow Progress. They're structurally part of the
roadmap and are filled by a tool, never by hand. They exist as empty
placeholders in the template, but a `/roadmap` run does not leave
them that way.

**The default fill is issueless and automatic.** Phase 4 runs
`shirabe roadmap populate <path> --no-issues` after the jury resolves
and before the author reviews the draft, and the activate path re-runs
it before the `Draft -> Active` transition. Both fill the sections
from the items section and create nothing on GitHub. The table keys
each row on the feature's label, the same key form the shared roadmap
profile specifies, with the feature's `needs-*` label in the Issues
column; the diagram uses `F<n>` nodes, and the Dependencies cells name
features by those same `F<n>` indices. The Dependencies convention
below applies.

**Issue-keyed fill is a separate, explicit step.** When a repo wants
its roadmap features tracked as GitHub issues, a human runs
`/roadmap populate <path> --issues` after the roadmap is approved.
That creates one issue per feature, re-renders both sections keyed on
those issues, and goes through the R14 approval gate. The repo's
`## Roadmap Issues:` CLAUDE.md header (see
`${CLAUDE_PLUGIN_ROOT}/references/fixes/claude-md-conventions.md`)
selects what a human-invoked populate does when they pass no flag; it
defaults to `optional` when absent and never affects the automatic
runs.

Either way the sections are tool-generated. Don't hand-edit them.

6. **Implementation Issues** -- table mapping features to GitHub
   issues. Empty at creation. The canonical roadmap profile shape
   (`Feature | Issues | Dependencies | Status`; the key column reads
   `Milestone` on a `roadmap/v3` roadmap), description rows, and
   strikethrough rules are defined in
   `${CLAUDE_PLUGIN_ROOT}/references/issues-table.md`.

Once populated, the marker reads ``<!-- Populated by `shirabe roadmap
populate`. Do not fill manually. -->`` in **both** modes -- the
renderer writes one marker and does not distinguish issueless from
issue-keyed output. Tell the two apart by the table itself: issueless
rows are keyed on feature labels with `needs-*` in the Issues column,
issue-keyed rows carry issue links. The form shown below is the
template's placeholder, which populate replaces. The instruction not
to hand-edit holds in both modes.

```markdown
## Implementation Issues

<!-- Populated by /plan during decomposition. Do not fill manually. -->

| Feature | Issues | Dependencies | Status |
|---------|--------|--------------|--------|
```

On a `roadmap/v3` roadmap the placeholder header is
`| Milestone | Issues | Dependencies | Status |` over
`|-----------|--------|--------------|--------|`.

7. **Dependency Graph** -- Mermaid diagram showing feature
   dependencies and issue relationships. Empty at creation. Mermaid
   syntax rules, the fixed status-class palette, node format, and
   legend are defined in
   `${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md`.

As with Implementation Issues, the populated marker is the same in
both modes. What differs is the diagram: issueless population uses
`F<n>` feature nodes, issue-keyed population uses `I<n>` issue nodes.
Don't hand-edit it in either mode.

```markdown
## Dependency Graph

<!-- Populated by /plan during decomposition. Do not fill manually. -->

```mermaid
graph TD
```
```

These sections must appear in every roadmap file, even when empty.
Their presence signals that the roadmap is structurally complete and
ready for downstream planning workflows.

### One-feature roadmaps

A one-feature roadmap fills both sections the same way, and neither
degenerates. The Implementation Issues table gets one row with `None`
in its Dependencies cell. The dependency graph gets one node and no
edges -- a single-node `graph TD` is valid mermaid and the validator's
FC07 reconciliation treats it as any other diagram, matching the table
row for row. Nothing about the shape assumes a second feature to point
at.

## Content Boundaries

A roadmap is NOT:

- **A PRD**: PRDs define requirements for a feature. Roadmaps name
  features and track them; they never say what a feature must do. If
  you're writing detailed requirements, that's a PRD.
- **A plan**: Plans break a single artifact into implementable
  issues. Roadmaps operate one level above, coordinating across the
  PRDs or design docs their features fan out into.
- **A project timeline**: Roadmaps don't include dates or time
  estimates. They capture ordering and dependencies, not schedules.

Routing, then: if you're defining requirements, write a PRD. If
you're breaking one design into issues, write a plan. If you need a
strategy's work sequenced, tracked, and handed into the tactical
chain, write a roadmap.

**A one-feature roadmap is legitimate.** The routing rule is about
altitude, not feature count. A roadmap does two jobs a PRD cannot: it
is the progress ledger for a strategy's execution (its per-feature
status is the only record of how far along the work is: on a
`roadmap/v1` roadmap the completion cascade sets a feature Done when its
downstream plan completes, and on a milestone roadmap a recorded verdict
does, as [When a milestone is Done](#when-a-milestone-is-done) says), and it is
the only bridge from the strategic chain to the tactical one --
`/brief` is framed against a ROADMAP, never a STRATEGY and never a PRD,
and the produced PLAN is what records the crossing (a durable document
may not name a ROADMAP, which is deleted when its features land). A
strategy whose work is a single feature still needs both, so it still
gets a roadmap. Most roadmaps do sequence several features and that
is where the sequencing rationale earns its keep, but there is no
two-feature floor. A roadmap with zero features is malformed.

## Lifecycle

A ROADMAP is a working artifact, like the PLANs beneath it: the
cascade deletes it when its work finishes, once every feature is Done
and every issue it references is closed. Of those PLANs, only a
`multi-pr` PLAN reaches the default branch, where it stays while its
item PRs land and is deleted by the PR that completes it. Neither
document is kept as the record of the work. For what a finished plan's
work followed (the plan as each step began, each step's proof, the
departures and the decisions), a later reader goes to the run's koto
session, found from any of its merged PRs with
`scripts/run-record-lookup.sh <owner/repo> <n>`.

### States

```
Draft --> Active --> Done --> DELETED
```

| Status | Meaning | Transition Trigger |
|--------|---------|-------------------|
| Draft | Under development, feature list may change | Created by /roadmap |
| Active | Feature list locked, execution in progress | Human approval |
| Done | All features delivered or explicitly dropped | All features complete |
| DELETED | The cascade removed the file | All features Done and every referenced issue closed |

### Transition Rules

- **Draft -> Active**: Feature list is complete and sequencing is
  justified. Human must explicitly approve.
- **Active -> Done**: Every feature has reached a terminal state
  (delivered or explicitly dropped with rationale documented).
- **Done -> DELETED**: The work-on cascade's roadmap deletion step,
  and nothing else. No human-invoked transition reaches it.
- **Done -> any other state**: Forbidden. A completed roadmap is not
  reopened. Create a new roadmap for follow-on work.
- **Active -> Draft**: Forbidden. If the feature list needs
  significant revision, create a new roadmap version.

### Edit Rules

Active roadmaps can update the Progress section and reserved sections
(Implementation Issues, Dependency Graph) freely. Changes to the
items section or Sequencing Rationale require creating a new roadmap
-- those sections are locked once the roadmap leaves Draft. A
milestone roadmap also allows the in-place milestone edits in [What
may change while it is Active](#what-may-change-while-it-is-active).

## File Location

Roadmaps live at `docs/roadmaps/ROADMAP-<name>.md` (kebab-case). No
directory movement based on status: a roadmap stays at that path from
Draft to Done, and the cascade deletes it from there.

## Validation Rules

### During drafting

- Frontmatter has `schema`, `status`, `theme`, `scope` fields
- Frontmatter status matches Status section in body
- All 5 required sections present (FC04) and in canonical order (FC15)
- Both reserved sections present (may be empty) and in the canonical
  *shape* (FC16): Implementation Issues is the empty skeleton (marker +
  `| Feature | Issues | Dependencies | Status |` header, `| Milestone |
  ...` on v3) or a
  tool-populated table -- never hand-authored prose; Dependency Graph is a
  ` ```mermaid ` block -- never a plain fenced code block
- Status is "Draft"
- At least one feature listed. `shirabe transition <path> Active`
  rejects a roadmap with zero features and nothing else -- one
  feature activates. On `roadmap/v3` it counts the milestone headings
  inside `## Milestones` only, and its refusal names that section. See [Content
  Boundaries](#content-boundaries) for why there is no two-feature
  floor.

### When referenced by downstream workflows

- Status must be "Active" to serve as upstream context
- If status is "Draft": inform the referencing workflow that the
  roadmap isn't yet approved

### Status consistency

- Frontmatter `status` and body Status section must always match
- Items marked as done in the items section should be reflected in
  Progress
- Reserved sections should only contain content if populated by
  `/plan`

### Validation enforcement

The validator runs FC05 (issues-table schema conformance), FC06
(cross-reference existence), and FC16 (reserved-section shape) on roadmap
docs, and FC21 (the milestone fields) on a `roadmap/v2` or `roadmap/v3`
roadmap; see
[Validation (FC21)](#validation-fc21). See `${CLAUDE_PLUGIN_ROOT}/references/issues-table.md` for the
canonical roadmap profile contract FC05/FC06 enforce.

FC05 and FC06 validate a *present* issues table and FC07 reconciles a
*present* mermaid diagram, but all three no-op when a reserved section was
hand-authored in the wrong shape -- a prose Implementation Issues with no
table, or a Dependency Graph fenced as a plain code block instead of
mermaid. FC16 covers that gap. It fires only on genuinely wrong shapes:

- **Implementation Issues** carries prose (a non-blank line that is neither
  an HTML comment nor a table row) while no canonical table parses.
- **Dependency Graph** opens a non-` ```mermaid ` fenced block.

FC16 is shape-gated, not status-gated: the empty skeleton passes at every
lifecycle state, and both modes (issue-creating with issue-linked rows,
issueless with label-keyed rows) render a table and mermaid diagram, so
both pass. FC16 is error-level -- a malformed
reserved section fails the build, not just an advisory notice.

### Dependencies cells in issueless mode

In issueless mode -- the automatic population, or any populate run
carrying `--no-issues` or no mode flag -- each Dependencies cell
names the depended-on feature by its `F<n>` index, the same number
the Dependency Graph's nodes use, counting features from 1 in
document order, or `None`. Cross-repo references round-trip
verbatim. Nothing else.

The key column and this column carry different forms on purpose:
the key stays readable while the dependency cell stays narrow. A
feature depending on three others renders `F1, F2, F3` rather than
three full labels. FC06 accepts both because it resolves a
dependency token against the row keys first and falls back to
resolving an `F<n>` token against the nth entity row, so a roadmap
whose cells carry full labels -- one populated before the alias
shipped, or one hand-edited that way -- keeps validating with no
change. A row whose key already fell back to `F<n>` needs no
special handling: its key and its index are the same token.

An index that names no row is still an error. `F99` on a five-feature
roadmap fails with `dependency "F99" names no row in this table`,
which is what keeps the check catching a dependency on a feature
that has been deleted or renumbered. Re-running populate re-derives
both the table and the diagram from the items section, which is
the repair when indices shift.

FC06 rejects annotated forms. `F1 (soft)` and
`None (ext: onboarding)` each fail with `dependency "..." names no
row in this table`, because the parenthetical is neither a key nor
an index.
Soft-versus-hard nuance and external dependencies don't go in the
cell -- they belong in the feature prose and the Sequencing
Rationale, which is where the reader looks for that context anyway.
Keep the cell to keys; put the reasoning in prose.

### When a label can't key a row

The renderer falls back to `F<n>` for a feature whose label is
empty, contains a `,` or `|`, duplicates another feature's label, or
carries text the validator's key and dependency normalizations
rewrite (an issue reference like `#123`, a markdown link, or a `~~`
run). Every such fallback prints a `warning:` line naming the
feature and the reason. The fallback keeps the generated document
valid; renaming the feature is what gets the label back into the
table.

## Quality Guidance

### Theme

- Identifies a coherent capability area, not a grab-bag of unrelated
  work
- Explains why coordination matters (shared infrastructure,
  user-facing story), or -- on a one-feature roadmap -- why this
  feature is the whole of the initiative
- Scoped to one initiative -- don't combine unrelated streams

### Features

- Each feature is independently describable in 1-2 sentences
- Dependencies between features are explicit, not implied
- Feature granularity matches the PRD level (one feature = one PRD)
- Features without downstream artifacts note what's needed next

### Sequencing Rationale

- Explains ordering constraints, not just lists the order
- Distinguishes hard dependencies (technical blockers) from soft
  preferences (nice-to-have ordering)
- Acknowledges where parallel execution is possible
- On a one-feature roadmap, says why the work is one feature rather
  than several -- not "N/A"

### Progress

- Updated as features move through their lifecycle
- Notes both completions and drops (with reasoning for drops)
- Matches the status annotations in the items section

### Common Pitfalls

- Too granular: tracking individual issues instead of features
- Too broad: mixing unrelated initiatives into one roadmap
- Missing rationale: listing features without explaining why this
  order
- Stale progress: not updating the Progress section as work completes
- Editing reserved sections manually instead of letting /plan
  populate them

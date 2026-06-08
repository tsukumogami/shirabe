# Brief Document Format Reference

Structure, lifecycle, validation rules, and quality guidance for Brief
documents.

## Table of Contents

- [Frontmatter](#frontmatter)
- [Required Sections](#required-sections)
- [Optional Sections](#optional-sections)
- [Section Matrix](#section-matrix)
- [Content Boundaries](#content-boundaries)
- [Lifecycle](#lifecycle)
- [Validation Rules](#validation-rules)
- [Quality Guidance](#quality-guidance)

## Frontmatter

Every brief document begins with YAML frontmatter:

```yaml
---
schema: brief/v1
status: Draft
problem: |
  2-4 line summary of the problem the feature solves. Same content the
  Problem Statement section elaborates in prose.
outcome: |
  2-4 line summary of the outcome a user should experience. Same content
  the User Outcome section elaborates in prose.
upstream: docs/roadmaps/ROADMAP-<parent>.md  # optional
motivating_context: |                          # optional
  Why this brief exists -- the situation, signal, or
  conversation that triggered the framing. Distinct from `problem`
  (the gap the feature solves) and from `outcome` (what's different
  for the user). Reach for it when the problem statement alone
  does not convey why the brief is being written now.
---
```

Required fields: `status`, `problem`, `outcome`. Optional:
`upstream`, `motivating_context`.

- **schema** -- `brief/v1`. Pins the artifact-type contract. `schema`
  is the map key the validator routes on, not a checked field.
- **status** -- lifecycle state (Draft, Accepted, Done).
- **problem** -- the problem the feature solves. A 2-4 line YAML
  literal block scalar (`|`). Matches the Problem Statement section
  body.
- **outcome** -- the outcome a user should experience. A 2-4 line YAML
  literal block scalar (`|`). Matches the User Outcome section body.
- **upstream** -- path to an upstream artifact such as a ROADMAP.
  Optional because a brief may be authored from a freeform topic with
  no single upstream document. Omit the field entirely when the
  upstream is a private artifact a public brief cannot name -- a public
  brief never points at a private path. Cross-repo upstream references
  use the `owner/repo:path` convention; see
  `${CLAUDE_PLUGIN_ROOT}/references/cross-repo-references.md` for the
  visibility-direction rules.

Frontmatter status must match the Status section in the body -- agent
workflows parse frontmatter to determine lifecycle state, so divergence
causes silent errors. The match is exact and strict: the validator's
FC03 check compares the frontmatter `status` against the *entire first
non-blank line* under the body `## Status` heading. That first line
must therefore be the bare status word (`Draft`, `Accepted`, or `Done`)
alone, with any explanatory prose pushed to a later paragraph after a
blank line. A line like `Draft. The brief stops before requirements...`
fails FC03, because the whole sentence becomes the compared value. The
shape that passes:

```markdown
## Status

Draft

Any explanatory prose goes here, after a blank line. The first
non-blank line under the heading is the bare status word so the
validator matches it against the frontmatter status.
```

## Required Sections

Every brief document has these sections in order:

1. **Status** -- current lifecycle state and any transition context.
   The first non-blank line is the bare status word (see Frontmatter).
2. **Problem Statement** -- the problem the feature solves, framed as a
   problem rather than a smuggled solution
3. **User Outcome** -- the outcome a user should experience, shaped as
   an outcome rather than a feature list
4. **User Journeys** -- the concrete paths through the feature, each
   naming a user, a trigger, and an outcome shape
5. **Scope Boundary** -- what the feature holds in and what it pushes
   out, with explicit in/out lists

### Per-section content rules

The rules below are mechanically applicable by the Phase 4 jury. They
specify what content must appear, not how prose must be shaped.

- **Status.** First non-blank line is the bare status word matching
  the frontmatter `status`. Prose after a blank line is free -- it
  typically carries transition context (jury verdicts, what the
  downstream PRD owns). The bare-word-first shape is load-bearing for
  FC03.

- **Problem Statement.** States the problem the feature solves. The
  problem is a problem, not a solution wearing a problem's clothes --
  "authors have no codified framing step between roadmap and PRD" is a
  problem; "we should build a `/brief` skill" is a solution. Sub-
  structure is free; no mandatory sub-headings.

- **User Outcome.** Describes the outcome a user should experience once
  the feature lands. Outcome-shaped, not a feature list -- "an author
  frames a feature before requirements exist and the framing resolves
  cleanly downstream" is an outcome; "the skill has six phases and a
  jury" is a feature list. Same content the `outcome` frontmatter field
  summarizes.

- **User Journeys.** Each journey leads with a name heading (`###`) and
  names a concrete user, the trigger that starts the journey, and the
  outcome shape the journey reaches. Journeys are distinct -- each
  exercises the feature from a different entry point, not the same path
  re-told. Expansion below the lead is free.

- **Scope Boundary.** Two explicit lists: what's IN and what's OUT.
  The OUT items are real exclusions a reader might otherwise assume are
  in -- "the parent-skill integration is separate downstream work" is a
  real exclusion; "world peace is out of scope" is filler. Both lists
  carry enough specificity that a downstream PRD author knows where the
  feature ends.

## Optional Sections

Include when relevant:

- **Open Questions** -- present only in Draft status. Records the
  unresolved questions the brief defers to the downstream PRD. Each
  question genuinely defers a framing detail, not a blocker that should
  stop the brief. Must be empty or removed before the Draft -> Accepted
  transition. The canonical closure surface is **the downstream PRD's
  Decisions and Trade-offs section** -- each open question resolves
  into a recorded decision (or its absence is itself recorded as a
  remaining unknown the PRD owns).
- **Downstream Artifacts** -- typed link list of the PRD and design
  documents that pick up the brief. Each entry is a durable repo-
  relative path (not `wip/...`) plus a one-sentence description.
  Populated as downstream work starts; empty when no downstream
  artifact exists yet.
- **References** -- in-repo precedents the brief draws on (prior
  briefs, format references, skill templates). Durable paths.

## Section Matrix

| Section | Required |
|---------|----------|
| Status | Required |
| Problem Statement | Required |
| User Outcome | Required |
| User Journeys | Required |
| Scope Boundary | Required |
| Open Questions | Draft only |
| Downstream Artifacts | Optional |
| References | Optional |

## Content Boundaries

BRIEF does NOT contain:

- **PRD-level requirements** -- belongs in a PRD. The brief frames a
  feature's problem, outcome, journeys, and scope; functional
  requirements, acceptance criteria, and user stories live one altitude
  down in the PRD the brief feeds.
- **Design-level architecture** -- belongs in a DESIGN doc. The brief
  names what a feature is for and where its boundary sits; technical
  decisions about how to build it (interface shapes, data flow,
  infrastructure choices) are downstream design territory.
- **Implementation tasks** -- belongs in a PLAN. The brief doesn't
  decompose into atomic issues; that's the planning altitude.
- **Feature sequencing** -- belongs in a ROADMAP. The brief frames one
  named feature; ordering features against each other with dependencies
  is upstream roadmap work.

If a BRIEF draft starts accumulating requirements, acceptance criteria,
technical decisions, or an implementation breakdown, those belong
downstream. Extract them into Downstream Artifacts pointers (when the
downstream doc exists) or Open Questions (when the downstream PRD will
own them).

## Lifecycle

### States

| State | Meaning |
|-------|---------|
| Draft | Under development. May have Open Questions. |
| Accepted | Framing locked. Open Questions resolved. Phase 4 jury all-PASS recorded. Ready for the downstream PRD. |
| Done | The downstream PRD has operationalized the brief. Terminal state. |

### Transitions

All transitions are executed by `shirabe transition`. The subcommand
validates preconditions and updates status in both the frontmatter and
the body `## Status` first line. No transition moves the file between
directories -- the brief stays in `docs/briefs/` through every state,
mirroring PRD's terminal-state handling rather than VISION's or
STRATEGY's.

| Transition | Preconditions | Directory Movement |
|-----------|---------------|-------------------|
| Draft -> Accepted | Open Questions empty or removed; Phase 4 jury all-PASS; explicit human approval | None (stays in `docs/briefs/`) |
| Accepted -> Done | Downstream PRD has operationalized the brief | None (stays in `docs/briefs/`) |

`Done` is a terminal record that the framing has been consumed, not an
invalidation -- a brief makes no falsifiable bet that could fail, so
there is no Sunset state and no `done/` subdirectory.

**Command interface:**

```
shirabe transition <brief-doc-path> <target-status>
```

`<target-status>` is one of `Accepted | Done`. There is no `--reason`
flag -- neither forward transition captures free text. The subcommand
rewrites the body `## Status` first line to the bare target status word
(`Accepted`, `Done`), preserving the bare-word-on-its-own-line shape so
the document stays FC03-valid after the transition.

**Forbidden transitions:**

- Draft -> Done (must accept first)
- Accepted -> Draft (regression)
- Done -> any (terminal, irreversible)

### Edit Rules

Accepted briefs can be edited in place. The framing a brief carries
is durable but not frozen -- if the problem or outcome shifts
materially before the downstream PRD lands, edit the brief and note the
change in the Status section prose.

### Directory Mapping

| Status | Directory |
|--------|-----------|
| Draft, Accepted, Done | `docs/briefs/` |

The brief never leaves `docs/briefs/`. No status triggers a directory
move.

## Validation Rules

`shirabe validate` recognizes `BRIEF-*.md` files by longest-prefix
match and runs four checks from the `brief/v1` Formats-map entry. No
custom check and no visibility-gating check apply -- BRIEF has no
visibility-gated section.

- **FC01 -- required fields.** The frontmatter carries `status`,
  `problem`, and `outcome`. A missing field fails FC01. `schema` is the
  map key, not a checked field, so its absence is a routing failure
  rather than an FC01 error.
- **FC02 -- valid statuses.** The frontmatter `status` is one of
  `Draft`, `Accepted`, `Done`. Any other value (for example
  `Published`) fails FC02 and the error lists the valid set.
- **FC03 -- frontmatter status matches body `## Status`.** The check
  compares the frontmatter `status` against the *entire first non-blank
  line* under the body `## Status` heading, case-insensitively. They
  must be equal. Because the *whole* first line is compared, the line
  must be the bare status word alone -- prose on that line makes the
  compared value the whole sentence and fails the check.
- **FC04 -- required sections present.** The body carries all five
  required sections (Status, Problem Statement, User Outcome, User
  Journeys, Scope Boundary). A missing section fails FC04 and the error
  names it.

### The `## Status` first-line convention (FC03 contract)

FC03 is the one subtle check. The body `## Status` section MUST open
with the bare status word -- `Draft`, `Accepted`, or `Done` -- alone on
its own line, followed by a blank line, followed by any explanatory
prose. The validator reads the entire first non-blank line under the
heading and compares it to the frontmatter `status`; prose on that line
fails the comparison.

Passes FC03:

```markdown
## Status

Accepted

Phase 4 jury returned all-PASS. The downstream PRD owns the
requirements articulation.
```

Fails FC03 (the compared value becomes the whole sentence, which does
not equal `Accepted`):

```markdown
## Status

Accepted. Phase 4 jury returned all-PASS and the downstream PRD owns
the requirements.
```

The transition script preserves this shape automatically: it rewrites
only the bare status word on the first line and leaves the prose
paragraph below it untouched.

### During /brief (drafting)

- Frontmatter has `schema`, `status`, `problem`, `outcome` fields
- `schema` is `brief/v1`
- Frontmatter `status` matches the body `## Status` first line (FC03)
- All five required sections present (FC04) and in canonical order (FC15)
- Status is `Draft`
- Open Questions section may contain unresolved items
- No `private/` paths, private repos, private filenames, internal
  codenames, or private issue numbers (public-visibility
  cleanliness). The qualifier "private" matters: public GitHub
  issue numbers from the same repo are routinely cited and not in
  scope of this restriction. Only issue numbers from private repos
  (`tsukumogami/vision#NN`, `tsukumogami/coding-tools#NN`, etc.)
  are forbidden in a public BRIEF.

### During /brief finalization (approval)

- Open Questions section must be empty or removed
- Phase 4 jury verdicts all PASS
- User Journeys section contains at least one journey with a name
  heading, a named user, a trigger, and an outcome shape
- Scope Boundary section contains both an IN list and an OUT list with
  real exclusions
- Downstream Artifacts entries, if present, are durable paths (not
  `wip/...`)
- Status transitions to `Accepted` on explicit human approval

### When referenced by downstream workflows

- Status must be `Accepted` or `Done` to serve as upstream context
- If status is `Draft`: STOP and inform the user the BRIEF needs
  approval first
- A `Done` brief is still a valid upstream record -- its downstream PRD
  has simply already been authored

### Status consistency

- Frontmatter `status` and the body `## Status` first line must always
  match (FC03)
- The first line under `## Status` is always the bare status word; any
  prose follows after a blank line

## Quality Guidance

Each required section has specific quality criteria. Reviewers and
authors should check these during drafting and validation.

### Problem Statement

- States a problem, not a smuggled solution. If the section reads like
  a description of the feature being built ("we add a `/brief` skill
  with five sections"), step back -- that's the solution, not the
  problem it answers. The problem names the gap a reader feels before
  the feature exists.
- Stands alone. A reviewer landing on the brief cold should grasp what's
  broken or missing from this section without having to open the
  upstream roadmap.
- Sub-structure is the author's call. A single tight paragraph is fine;
  a problem framing followed by an enumerated breakdown of its parts is
  fine. Pick what makes the gap legible.

### User Outcome

- Outcome-shaped, not a feature list. "An author frames a feature
  before requirements exist and the reference resolves cleanly
  downstream" describes an outcome; "the skill ships with six phases, a
  jury, and a transition script" enumerates features. The reader should
  finish the section knowing what's different for the user, not what
  parts got built.
- Matches the `outcome` frontmatter value. Divergence between the prose
  outcome and the YAML field signals one is stale.
- Names the user whose experience changes. An outcome with no one on
  the receiving end is a feature in disguise.

### User Journeys

- Each journey leads with a name heading (`###`) and names a concrete
  user, the trigger that starts the journey, and the outcome shape it
  reaches. A journey missing any of the three reads as a vignette, not a
  journey.
- Journeys are distinct. Each exercises the feature from a different
  entry point -- a cold standalone invocation, a downstream consumer
  tracing upstream, a mid-chain decision, a review-and-accept pass.
  Two journeys that walk the same path with different names are one
  journey.
- Concrete over generic. "A PRD author writes `upstream:
  docs/briefs/BRIEF-foo.md` and the reference resolves" is concrete;
  "users interact with the system" is not.

### Scope Boundary

- Explicit IN and OUT lists. The IN list bounds what the feature
  delivers; the OUT list names what a reader might reasonably assume is
  included but isn't.
- Real OUT exclusions. Each OUT item is something a downstream author
  could plausibly expect inside the boundary -- a parent-skill
  integration, a general mechanism the brief-specific one only
  gestures at, a migration the work deliberately avoids. Filler
  exclusions ("not solving unrelated problem X") defeat the section.
- Helps prevent scope creep when the downstream PRD picks the brief up.

### Open Questions (optional, Draft only)

- Each question genuinely defers a framing detail to the downstream
  PRD, not a blocker that should stop the brief. "The PRD picks the
  exact required-field set against the bootstrapping constraint" is a
  deferred detail; "we don't know if this feature should exist" is a
  blocker the brief should resolve before Accepted.
- Empty or removed before Draft -> Accepted.

### Downstream Artifacts (optional)

- Typed link list. Each entry: durable repo-relative path + one-sentence
  purpose.
- Paths are durable. `wip/...` paths fail the structural reviewer's
  check.
- Empty at draft creation; populated as the downstream PRD and design
  land.

### Common Pitfalls

- **Smuggling the solution into the Problem Statement.** The brief's
  whole value is framing the problem before requirements exist. If the
  Problem Statement already describes the feature, the framing step
  collapsed into a solution sketch -- pull the solution out and name the
  gap it answers.
- **A feature list masquerading as a User Outcome.** Enumerating what
  gets built is the easiest way to fail the outcome shape. Ask "what's
  different for the user once this lands?" and write that.
- **Indistinct journeys.** Four journeys that all describe "an author
  uses the skill" are one journey told four ways. Each journey needs a
  distinct entry point and trigger.
- **Empty-calorie scope exclusions.** OUT items that no reader would
  have assumed were in ("not building a time machine") satisfy the
  structure but defend nothing. Each exclusion should be a boundary a
  downstream author could otherwise cross by accident.
- **Prose on the `## Status` first line.** The single most common FC03
  failure. The first non-blank line under `## Status` must be the bare
  status word alone; move every word of context to a paragraph after a
  blank line.
- **Drifting into requirements.** A brief that grows acceptance
  criteria, user stories, or interface shapes has climbed down into PRD
  or DESIGN altitude. Defer that content downstream.

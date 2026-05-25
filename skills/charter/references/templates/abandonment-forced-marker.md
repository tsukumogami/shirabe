# Abandonment-Forced HTML-Comment Marker

`/charter` emits this marker into the force-materialized artifact
when the chain exits via `exit: abandonment-forced` (see
`skills/charter/references/phases/phase-finalization.md` for the
exit-path orchestration logic, and the R8 tie-break that resolves
which child's intermediate gets force-materialized). The marker
records the abandonment metadata in the artifact body in a form
that:

- Survives schema validation by the host artifact type's own
  validator (the marker is an HTML comment, not prose; it does
  not introduce a required section or alter the artifact's
  structural shape).
- Is greppable for human readers and tools (search for the
  literal substring `charter-status-block:` to locate the
  marker in any force-materialized artifact).
- Carries the four metadata fields needed to reconstruct the
  abandonment context from the artifact alone (without needing
  the `wip/charter_<topic>_state.md` state file).

## The Snippet

The marker is a **single-line HTML comment** with the exact
shape below. Whitespace inside the comment is significant
(reader tools may expect the exact substring `charter-status-block:
abandonment-forced`); do not add line breaks within the comment,
do not add additional fields, do not reorder the fields.

```
<!-- charter-status-block: abandonment-forced; triggering-child: <name>; partial-phase-reached: <phase>; chain-started: <ISO-8601 timestamp> -->
```

The four runtime fields are populated from `/charter`'s state
file (see `skills/charter/references/phases/phase-state-management.md`
for the state-schema):

- `<name>` — substituted from `triggering_child:` in state. The
  child whose intermediate was force-materialized as resolved by
  the R8 tie-break.
- `<phase>` — substituted from `partial_phase_reached:` in
  state. The phase pointer the triggering child had reached when
  the chain bailed.
- `<ISO-8601 timestamp>` — substituted from `chain_started:` in
  state. The wall-clock time the chain originally began (NOT the
  abandonment time; the `chain_completed:` field in state
  records the abandonment time separately).

The marker is emitted whenever `exit: abandonment-forced` is
recorded in the state file — once per chain abandonment, in the
force-materialized artifact's body.

## Placement

The marker MUST go **inside the force-materialized artifact's
existing Status section**, NOT in a new required section. Three
properties bind the placement:

1. **Existing Status section, not a new section.** The
   force-materialized artifact (STRATEGY, VISION, or ROADMAP —
   see Host Artifact Types below) already has a Status section
   per its own schema; the marker lives inside that existing
   section. Adding a new section like "Abandonment Block" or
   "Charter Status" would alter the artifact's structural shape
   and could trigger the artifact-type's schema validator into
   rejecting the force-materialized output. AC26 binds this
   placement: the force-materialized artifact MUST pass the host
   artifact type's own schema validator with the marker present.
2. **HTML-comment syntax, not prose.** The marker uses
   `<!-- ... -->` syntax precisely so the host artifact type's
   schema validator ignores it as top-level body content. To the
   validator, the marker is invisible (HTML comments are
   render-time-suppressed and validator-ignored across shirabe's
   schema rules); the artifact's prose continues to satisfy the
   schema requirements. To a human reader or a grep-based tool,
   the marker is visible (the substring `charter-status-block:`
   is searchable in the raw markdown).
3. **One marker per abandonment.** Each force-materialized
   artifact contains exactly one marker. Re-resuming an
   abandoned chain (and force-materializing again from a fresh
   bail) would produce a new artifact at a new path or replace
   the prior artifact; the marker is not appended-to.

## Host Artifact Types

The marker appears inside the Status section of whichever child's
intermediate got force-materialized. Three artifact types are
candidate hosts (matching the three children `/charter` can
invoke whose intermediates can be force-materialized via the R8
tie-break in `phase-finalization.md`):

- **STRATEGY** at `docs/strategies/STRATEGY-<topic>.md` —
  force-materialized when `/strategy` is the most-recently-running
  child at the time of bail. The Status section follows the
  STRATEGY schema; the marker lives inside it.
- **VISION** at `docs/visions/VISION-<topic>.md` —
  force-materialized when `/vision` is the most-recently-running
  child at the time of bail. The Status section follows the
  VISION schema; the marker lives inside it.
- **ROADMAP** at `docs/roadmaps/ROADMAP-<topic>.md` —
  force-materialized when `/roadmap` is the most-recently-running
  child at the time of bail. The Status section follows the
  ROADMAP schema; the marker lives inside it.

The host is selected by `phase-finalization.md`'s R8 tie-break;
the marker shape and placement is the same regardless of which
host the tie-break resolves to. The artifact's own schema is
satisfied by the artifact's own prose; the marker is a
non-structural addition.

## Example Placement Inside a STRATEGY Status Section

The following is a placement example for a force-materialized
STRATEGY. The Status section is a normal STRATEGY Status section
(satisfying STRATEGY's schema); the marker is one HTML comment
inserted into the section's body.

```
## Status

Draft. Force-materialized by `/charter` after the chain was
abandoned mid-Phase 3.

<!-- charter-status-block: abandonment-forced; triggering-child: strategy; partial-phase-reached: phase-3-structural-fill; chain-started: 2026-05-25T14:32:08Z -->

The STRATEGY's Bet-Specific Falsifiability section was not
authored before abandonment; the partial draft is durable
evidence of the chain's state at the time of bail.
```

The marker line is one HTML comment between paragraphs of the
Status section. The host artifact's schema validator reads the
section's prose ("Draft. Force-materialized..." plus the
explanatory sentence) and ignores the HTML comment; the validator
passes. A human reader or a grep tool sees both — the prose for
context and the marker for the abandonment metadata.

## Why HTML Comments

HTML-comment syntax is the right shape for three reasons that
each independently bind the choice:

- **Schema-validator transparency.** The host artifact type's
  schema validator ignores HTML comments as top-level body
  content; the artifact passes its own validator with the marker
  embedded.
- **Greppability.** The literal substring
  `charter-status-block:` is greppable across the worktree and
  the git history; tools that need to find force-materialized
  artifacts can scan for the substring without parsing the
  artifact body.
- **Stability across artifact types.** The same comment shape
  fits inside any of the three host artifact types' Status
  sections; no per-host-type marker variant is needed.

Alternative shapes (a new YAML field in frontmatter, a new
required section, a code fence block) would each violate at least
one of the three properties (schema validators would either
require the new field or reject the new section; code fences are
not greppable as comments). The HTML-comment shape sits cleanly
inside all three constraints.

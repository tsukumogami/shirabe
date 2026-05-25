# Decision 7 — Abandonment-Forced HTML-Comment Marker Schema

**Researcher:** decision-researcher-7
**Complexity:** standard
**PRD source:** R15 third bullet; AC13; AC23
**Companion precedent:** `/charter`'s
`skills/charter/references/templates/abandonment-forced-marker.md`
(the strategic-chain analogue).

## Question

What is the exact schema of the HTML-comment marker `/scope` emits
into a force-materialized child artifact when the chain exits via
`exit: abandonment-forced`? Specifically:

1. **Marker prose shape** — is the marker uniform across the four
   candidate hosts (BRIEF, PRD, DESIGN, PLAN) or tailored per
   artifact type to match each host's existing Status section
   conventions?
2. **Exact marker text** — the literal HTML-comment substring,
   field order, separator, and whitespace shape.
3. **Marker metadata** — what fields the marker carries beyond
   the abandonment flag (`triggering_child`, `partial_phase_reached`,
   `chain_started`, others?).
4. **Per-child placement** — where in the host artifact's existing
   Status section the marker lands (relative to the bare status
   word that BRIEF's FC03 check enforces; relative to whatever
   prose the host artifact already requires).
5. **Greppability invariant** — the literal substring future tools
   and humans will grep for.
6. **Validator non-interference** — guarantees that
   `shirabe validate` does NOT fail on the marker for any of the
   four host artifact types.

## Decision

`/scope` emits a **single uniform HTML-comment marker** — same
text shape, same fields, same field order — for all four candidate
host artifact types (BRIEF, PRD, DESIGN, PLAN). The marker carries
**four fields**: the abandonment flag, the triggering child name,
the partial phase reached, and the chain-started ISO-8601
timestamp. The marker lives **inside the host artifact's existing
`## Status` section, on a line *after* the bare status word**
(`Draft` / `Proposed`), separated from the status word by a blank
line so BRIEF's FC03 first-non-blank-line check still reads `Draft`
as the compared value.

The marker shape is **mechanically inherited from `/charter`'s
abandonment-forced marker** (same field order, same shape, same
greppability discipline) with one substitution: the literal
substring `charter-status-block:` becomes `scope-status-block:` so
each parent skill's force-materialized artifacts are independently
greppable.

### The literal marker text

```
<!-- scope-status-block: abandonment-forced; triggering-child: <name>; partial-phase-reached: <phase>; chain-started: <ISO-8601 timestamp> -->
```

The marker is a **single-line HTML comment**. Whitespace inside
the comment is significant — reader tools may match the exact
substring `scope-status-block: abandonment-forced`; do not add
line breaks within the comment, do not add additional fields, do
not reorder the fields.

The four runtime fields are populated from `/scope`'s state file
at `wip/scope_<topic>_state.md`:

- `<name>` — substituted from `triggering_child:` in state. The
  child resolved by the R8 tie-break (one of `brief`, `prd`,
  `design`, `plan`).
- `<phase>` — substituted from `partial_phase_reached:` in
  state. The phase pointer the triggering child had reached at
  bail.
- `<ISO-8601 timestamp>` — substituted from `chain_started:` in
  state. The wall-clock time the chain originally began (NOT the
  abandonment time; the `chain_completed:` field in state records
  the abandonment time separately).

The `boundary:` and `decision_record_sub_shape:` fields stay
ABSENT under `exit: abandonment-forced` per the R9 conditional-
field gating, so the marker does NOT carry them. AC13 binds the
absence: "boundary and decision_record_sub_shape are absent (per
R9)."

### Per-child placement inside the existing Status section

The marker lives **inside the host artifact's `## Status`
section**, NOT in a new required section. The placement is the
same line shape for every host, but the surrounding host-section
text differs because each host has its own Status conventions.

The placement rules:

1. **Bare status word first (load-bearing for BRIEF's FC03).** The
   first non-blank line under `## Status` is the bare status word
   the host artifact's schema expects. For BRIEF this is `Draft`
   (FC03 explicitly compares the entire first non-blank line); for
   PRD it is `Draft`; for DESIGN it is `Proposed`; for PLAN it is
   `Draft`. The marker MUST appear on a later line, separated from
   the status word by a blank line, so the first-non-blank-line
   comparison does not pick up the marker.
2. **HTML-comment syntax, not prose, not frontmatter.** The marker
   uses `<!-- ... -->` syntax precisely so the host artifact's
   schema validator ignores it as top-level body content. To the
   validator, the marker is invisible (HTML comments are render-
   time-suppressed and validator-ignored across shirabe's schema
   rules). It is NOT placed inside frontmatter (a comment in YAML
   frontmatter would either be parsed as a `#`-comment or trip the
   frontmatter validator on the `<!--` token).
3. **One marker per abandonment.** Each force-materialized
   artifact contains exactly one marker. Re-resuming an abandoned
   chain and force-materializing again from a fresh bail produces
   a new artifact (or replaces the prior one); the marker is not
   appended-to.

### Per-host examples

The four examples below show the same marker text inside each
host's Status section. The host artifact's prose differs (each
host's schema demands its own conventions); the marker line is
identical.

**BRIEF host** (`docs/briefs/BRIEF-<topic>.md`):

```markdown
## Status

Draft

Force-materialized by `/scope` after the chain was abandoned
mid-Phase 2 of `/brief`.

<!-- scope-status-block: abandonment-forced; triggering-child: brief; partial-phase-reached: phase-2-draft; chain-started: 2026-05-25T14:32:08Z -->

The brief's User Journeys section was not authored before
abandonment; the partial draft is durable evidence of the chain's
state at the time of bail.
```

**PRD host** (`docs/prds/PRD-<topic>.md`):

```markdown
## Status

Draft

Force-materialized by `/scope` after the chain was abandoned
mid-Phase 3 of `/prd`.

<!-- scope-status-block: abandonment-forced; triggering-child: prd; partial-phase-reached: phase-3-draft; chain-started: 2026-05-25T14:32:08Z -->
```

**DESIGN host** (`docs/designs/DESIGN-<topic>.md`):

```markdown
## Status

Proposed

Force-materialized by `/scope` after the chain was abandoned
mid-Phase 4 of `/design`.

<!-- scope-status-block: abandonment-forced; triggering-child: design; partial-phase-reached: phase-4-architecture; chain-started: 2026-05-25T14:32:08Z -->
```

**PLAN host** (`docs/plans/PLAN-<topic>.md`):

```markdown
## Status

Draft

Force-materialized by `/scope` after the chain was abandoned
mid-Phase 3 of `/plan`.

<!-- scope-status-block: abandonment-forced; triggering-child: plan; partial-phase-reached: phase-3-decomposition; chain-started: 2026-05-25T14:32:08Z -->
```

The bare status word on the first non-blank line satisfies each
host's frontmatter↔body match (including BRIEF's FC03). The marker
line carries the abandonment metadata. The optional explanatory
paragraph after the marker is permitted by every host's Status
conventions (BRIEF explicitly allows free prose after the bare
status word; the others allow Status-section prose by default).

## Considered Options

### Option A — Uniform marker (chosen)

Single marker text shape used identically across all four host
artifact types. Same field names, same separator (`;`), same field
order, same prefix substring (`scope-status-block:
abandonment-forced`).

**Pros:**

- One greppable substring locates every force-materialized
  artifact: `grep -r "scope-status-block: abandonment-forced"`.
- The marker shape mechanically inherits from `/charter`'s
  precedent. The two parent skills produce structurally identical
  markers (only the prefix differs:
  `charter-status-block:` vs `scope-status-block:`). Future
  parent skills can keep adding to the pattern by introducing
  their own `<parent>-status-block:` prefix.
- Easier to implement: the marker emitter is one template with
  four field substitutions, not four templates.
- Easier to read: a reader who has seen one force-materialized
  artifact knows what to expect in any of the four hosts.

**Cons:**

- The marker prose does not "match" the host's voice. A
  DESIGN-host marker reads with the same shape as a BRIEF-host
  marker, even though DESIGN typically uses more clinical prose
  and BRIEF uses more author-facing prose. This is a cosmetic con,
  not a functional one — the marker is metadata, not the host's
  body content.

### Option B — Per-artifact-type tailored marker prose

Distinct marker text per host artifact type (e.g., BRIEF gets a
brief-style marker, DESIGN gets a design-style marker), each
tailored to the host's existing Status section conventions.

**Pros:**

- Markers read more naturally in each host's voice.

**Cons:**

- Breaks the single-greppability invariant: four different
  substrings to search for, OR a complex regex that handles all
  four shapes. Inheriting from `/charter`'s precedent (which uses
  the uniform shape) becomes impossible.
- Four marker templates to author and maintain, not one.
- Inconsistent: a reader who has seen one host's marker cannot
  predict the shape of another's. Increases the cognitive load
  for both human readers and validator-tooling authors.
- No functional benefit — the marker is metadata; cosmetic
  tailoring is not load-bearing.

**Rejected because:** the costs (four templates, broken
greppability, cognitive inconsistency) outweigh the cosmetic
benefit. The uniform shape (Option A) inherits cleanly from the
existing `/charter` precedent and preserves a single greppable
substring across the workspace.

### Option C — Uniform marker but extended metadata (timestamp + path + R8-step)

Same marker text shape as Option A, but with additional fields:
the resolved-by-R8-step number (1 or 2), the bail-time timestamp
(in addition to chain-started), and the `wip/scope_<topic>_state.md`
path.

**Pros:**

- More metadata in the marker; reduces need to read the state
  file to reconstruct the abandonment context.

**Cons:**

- The state file is the authoritative durable record; the marker
  is a pointer / locator. Duplicating state-file fields into the
  marker risks the two going out of sync (e.g., if the state file
  is later updated, the marker is not).
- The bail timestamp and the R8-step number are not load-bearing
  for any AC. AC13 names exactly three required state fields
  (`exit: abandonment-forced`, `triggering_child`,
  `partial_phase_reached`); the marker carries those plus the
  chain-started timestamp for human context. Additional fields
  are surface area without binding tests.
- The `/charter` precedent uses exactly four fields. Diverging
  here would break the cross-parent-skill consistency Option A
  preserves.

**Rejected because:** the marker is metadata-by-pointer, not
metadata-by-copy. The state file owns the full record; the marker
carries enough fields to locate and contextualize the abandonment,
no more.

## Mechanical Constraints

### Greppability invariant

The literal substring `scope-status-block: abandonment-forced`
MUST be greppable workspace-wide:

```bash
grep -r "scope-status-block: abandonment-forced" docs/
```

This single command finds every force-materialized `/scope`
artifact regardless of host type. The shape is mechanically
inherited from `/charter`'s `charter-status-block:
abandonment-forced` precedent — each parent skill carries its own
namespaced prefix so a `grep` per parent skill locates that
parent's force-materialized artifacts.

The greppability invariant is the single most important property
of the marker after schema-validator transparency; cosmetic prose
choices that break it (e.g., the per-host prose of Option B) are
rejected on the strength of this invariant alone.

### Validator non-interference

`shirabe validate --visibility=<repo-visibility>` MUST NOT fail on
the marker for any of the four host artifact types. The mechanism:

1. The marker is an **HTML comment** (`<!-- ... -->`), not prose,
   not frontmatter, not a section heading. Markdown parsers
   treat HTML comments as render-time-suppressed; shirabe's
   schema-validator rules (BRIEF FC03, PRD frontmatter↔body
   match, DESIGN 9-required-sections check, PLAN structure
   check) do not parse HTML comments as content.
2. The marker is placed **after a blank line** under the bare
   status word, so it is NOT on the first non-blank line. This
   guards against BRIEF's FC03 (which compares the *entire first
   non-blank line* under `## Status` against the frontmatter
   `status:`). The blank-line separation makes `Draft` the
   first-non-blank-line value; the marker becomes the
   second-non-blank-line value (which FC03 does not inspect).
3. The marker does NOT introduce a new section. All four host
   artifact schemas require a fixed list of sections in order;
   adding a new section (e.g., "Abandonment Block") would break
   each host's section-count and section-order checks. The
   marker lives *inside* an existing section instead.

AC23 binds this property: "Force-materialized artifact passes the
same schema validators as a full-run artifact (the abandonment-
forced HTML-comment marker is inside the existing Status section,
not in a new required section)." The placement above satisfies
AC23 for all four hosts.

### One marker per force-materialization

Each force-materialized artifact contains **exactly one** marker.
Multiple force-materializations of the same topic (a chain that
abandoned, was resumed, and abandoned again) produce a new artifact
at the same path (replacing the prior one) with a new single marker
populated from the current state file's fields. The marker is not
appended to; the artifact-as-a-whole is re-written.

## Cross-Coupling Notes

- **Couples to Decision 6 (resume ladder)**: the resume ladder
  row 4 (`≥ 7 days` stale-session prompt) is one of the four
  triggers that fires abandonment-forced. The marker is what the
  Force-materialize prompt option produces. Decision 6 owns the
  prompt; Decision 7 owns the marker emitted on selection.
- **Couples to Decision 8 (pattern-doc edits)**: the marker
  template inherits from `/charter`'s precedent. Decision 8
  decides whether the template lives in `skills/scope/references/
  templates/abandonment-forced-marker.md` (parallel to
  `/charter`'s placement) or in a pattern-level reference shared
  by both parent skills. The marker SHAPE is owned here; the
  template FILE PATH is owned by Decision 8.
- **Couples to Decision 5 (state schema)**: the four fields the
  marker substitutes (`triggering_child`, `partial_phase_reached`,
  `chain_started`, and the implicit `exit: abandonment-forced`)
  are state-file fields owned by Decision 5's state schema. The
  marker is a consumer of those fields; their semantics are
  defined there.
- **Couples to Decision 1 (PRD-boundary Reject) and Decision 2
  (DESIGN-boundary Reject)** by mutual exclusion: the marker
  fires ONLY under `exit: abandonment-forced`. The Decision Records
  emitted under `exit: re-evaluation` (rejection or re-evaluation
  sub-shape) do NOT carry the marker — they ARE the durable
  artifact, not a force-materialized partial. The R9 conditional-
  field gating in Decision 5's schema enforces the mutual
  exclusion structurally.

## Why HTML Comments (Inheriting `/charter`'s Three Properties)

The HTML-comment shape is chosen for the same three independently-
binding reasons `/charter`'s marker uses:

- **Schema-validator transparency.** Each host artifact's schema
  validator ignores HTML comments as top-level body content.
  The artifact passes its own validator with the marker embedded.
- **Greppability.** The literal substring `scope-status-block:`
  is greppable across the worktree and git history; tools that
  need to find force-materialized artifacts can scan for the
  substring without parsing the artifact body.
- **Stability across artifact types.** The same comment shape
  fits inside any of the four host artifact types' Status
  sections; no per-host-type marker variant is needed.

Alternative shapes (a new YAML field in frontmatter, a new
required section, a code-fence block, a `> [!NOTE]` admonition)
would each violate at least one of the three properties:
frontmatter additions either require a schema change or get
rejected as unknown fields; new sections break the section-list
checks; code fences are not greppable as comments; admonitions
render visibly and shift the host's prose.

## Recommendation Summary

- **Shape:** uniform single-line HTML comment, identical text
  across all four host artifact types.
- **Literal text:**
  `<!-- scope-status-block: abandonment-forced; triggering-child: <name>; partial-phase-reached: <phase>; chain-started: <ISO-8601 timestamp> -->`
- **Four fields:** abandonment flag (implicit in the substring
  `abandonment-forced`), triggering child, partial phase reached,
  chain-started timestamp.
- **Placement:** inside the host artifact's existing `## Status`
  section, on a line *after* the bare status word, separated from
  it by a blank line.
- **Greppability invariant:** `grep -r "scope-status-block:
  abandonment-forced" docs/` finds every instance workspace-wide.
- **Validator non-interference:** the marker is an HTML comment,
  placed after a blank line, inside an existing section; passes
  BRIEF's FC03 and all four hosts' schema validators.
- **Template file:** authored at
  `skills/scope/references/templates/abandonment-forced-marker.md`
  (parallel to `/charter`'s template), modulo whatever Decision 8
  decides about pattern-level vs parent-specific placement.

The decision mechanically inherits from `/charter`'s precedent at
`skills/charter/references/templates/abandonment-forced-marker.md`;
the only substitution is `charter-status-block:` →
`scope-status-block:`, plus broadening the host artifact set from
three (STRATEGY/VISION/ROADMAP) to four (BRIEF/PRD/DESIGN/PLAN).

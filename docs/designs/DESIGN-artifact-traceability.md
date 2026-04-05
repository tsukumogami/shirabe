---
status: Proposed
upstream: docs/prds/PRD-artifact-traceability.md
problem: |
  Roadmaps lack an upstream frontmatter field, /prd never populates its
  upstream field, and there's no cross-repo reference convention. The
  VISION-to-PR traceability chain is broken at the Roadmap level.
decision: |
  Add upstream to roadmap format, extend /roadmap and /prd to set upstream
  at creation time via explicit argument passing (no heuristic detection),
  and document the cross-repo convention in a shared plugin-level reference.
rationale: |
  Follows the /design Phase 0 pattern (creation workflow sets upstream from
  input context). Explicit passing avoids fragile detection heuristics.
  Shared reference prevents convention drift across artifact types.
---

# DESIGN: Artifact Traceability

## Status

Proposed

## Context and Problem Statement

Five artifact types form the pipeline's traceability chain. Four of them
(VISION, PRD, Design Doc, Plan) have an optional `upstream` frontmatter
field linking to the parent artifact. Roadmaps don't, breaking the chain
between strategic intent (VISION) and feature sequencing (Roadmap).

The technical problem has three parts:

1. **Schema gap.** The roadmap format spec defines `status`, `theme`, and
   `scope` in frontmatter but no `upstream` field. Adding it requires
   updating the format spec, the creation workflow, and verifying the
   transition script doesn't reject the new field.

2. **Workflow inconsistency.** The /design skill's Phase 0 sets `upstream`
   from the source PRD at creation time. The /prd skill defines `upstream`
   in its format spec but never populates it during creation. The /roadmap
   skill has no upstream field at all. Two of three creation workflows that
   should set upstream don't.

3. **No cross-repo reference convention.** All existing `upstream` values
   are relative paths within the same repo. When artifacts span repos
   (common in multi-repo workspaces), there's no documented format for the
   reference. The `spawned_from.repo` field in design docs is a partial
   precedent but uses structured YAML rather than a compact string.

## Decision Drivers

- Must follow existing patterns: `upstream` is optional, set at creation
  time, uses relative paths for same-repo references
- Must work with existing transition scripts without breaking them (they
  don't validate upstream, so adding the field is safe)
- Cross-repo convention must respect the directional visibility rule:
  public repos must not reference private artifacts
- Changes are markdown and shell only (no compiled code)
- Convention should be documented once and linked from each skill, not
  duplicated across format specs
- The /design Phase 0 pattern (creation workflow sets upstream from input
  context) is the model to follow

## Considered Options

### Decision 1: Upstream context detection and population

Each creation workflow needs to populate the `upstream` frontmatter field.
The question is how the workflow gets the upstream path. Three entry points
exist per skill: standalone invocation, /explore handoff, and /plan issue
dispatch. Some entry points already have the upstream information (explore
knows the VISION, plan issues know the roadmap) but don't pass it through.

Key assumptions:
- The roadmap format will gain an optional `upstream` field pointing to
  a VISION document
- Handoff points can be modified to pass upstream paths without breaking
  existing workflows (the field is optional, so omission is safe)

#### Chosen: Argument-only with handoff enrichment

Extend the /design Phase 0 model to all creation workflows: the upstream
path is always passed explicitly, never detected via heuristics. Whoever
creates the invocation context passes the upstream reference.

The changes are:

1. **Handoff enrichment.** Each handoff point that knows the upstream
   passes it as an argument to the downstream skill.
   - /explore Phase 5 (produce-roadmap): when the exploration identified
     a VISION document (recorded in the crystallize artifact's upstream
     or findings), pass `--upstream <vision-path>` when invoking
     `/shirabe:roadmap <topic>`. The VISION path comes from the explore
     findings — if the exploration didn't surface a specific VISION, the
     flag is omitted.
   - /plan planning issues already include a `Roadmap:` line in their
     Context section. /prd can read this existing line when invoked from
     a plan issue context.

2. **Creation workflow consumption.** Each skill's draft phase reads
   upstream from `$ARGUMENTS` and writes it to frontmatter.
   - /roadmap Phase 3: read `--upstream` from `$ARGUMENTS`. Write
     `upstream:` to frontmatter. Works for both /explore handoff
     (which passes the flag) and standalone invocation.
   - /prd Phase 3: read `--upstream` from `$ARGUMENTS`. Write
     `upstream:` to frontmatter. The /plan issue body's `Roadmap:` line
     is a future source (requires /prd to detect issue context, deferred
     to a small follow-up since it's narrower than Feature 5).

3. **Standalone fallback.** When invoked standalone without upstream
   context, the field is omitted. No search heuristics, no guessing.

4. **Format update.** Add `upstream` as an optional field to
   roadmap-format.md.

#### Alternatives considered

**Entry-point-aware detection in Phase 3**: each skill's draft phase
searches for upstream context by reading explore artifacts, scanning issue
bodies, or searching `docs/` directories. Rejected because detection
heuristics are fragile — searching for "which roadmap mentions this topic"
can match the wrong roadmap or miss renamed features.

**Phase 0 detection with context propagation**: add or extend Phase 0 in
each skill to detect and store upstream context before scoping begins.
Rejected because it introduces the same fragile heuristics, just earlier.
More files to change (Phase 0, scope format, Phase 3) without improving
reliability.

### Decision 2: Cross-repo reference convention location

The `owner/repo:path` convention applies to all artifact types (any
upstream field could be a cross-repo reference). It shouldn't be
duplicated per format spec. The user directed "shared ref in the plugin,
linked from each skill where this ref is relevant."

Key assumptions:
- Format specs add a brief cross-reference note rather than duplicating
  the full convention
- Agents consult format specs when writing artifacts, so the link is
  sufficient for discovery

#### Chosen: Plugin-level shared reference at references/cross-repo-references.md

Create `references/cross-repo-references.md` at the plugin root. The
`references/` directory already holds shared conventions
(decision-protocol.md, decision-presentation.md, decision-block-format.md).

The file documents:
1. **Syntax**: `owner/repo:path` (compact string, no prefix)
2. **When to use**: when upstream points to an artifact in a different repo
3. **Visibility rules**: public repos must not reference private artifacts
4. **Examples**: one per artifact type showing both local and cross-repo
   upstream values
5. **Anti-patterns**: relative cross-repo paths, stale references,
   referencing private artifacts from public repos

Each format spec that documents an upstream field adds a single sentence:

> When upstream points to an artifact in another repository, use the
> cross-repo reference syntax documented in
> `references/cross-repo-references.md`.

#### Alternatives considered

**Per-skill inline duplication**: each format spec documents the full
cross-repo syntax in its upstream field section. Rejected because it
creates N copies that can drift and the convention is identical across
all artifact types.

**Per-skill reference files**: a cross-repo-references.md in each skill's
references/ directory. Rejected for the same reasons — multiple copies
of identical content with no benefit over a single shared file.

## Decision Outcome

The two decisions compose cleanly. Handoff enrichment (Decision 1) passes
upstream paths explicitly via `--upstream` flags: /explore passes the
VISION path when invoking /roadmap, and standalone users pass it directly.
For /prd, the `--upstream` flag handles the standalone case; /plan already
includes a `Roadmap:` line in planning issues that /prd can read in a
small follow-up. No heuristic detection. When no upstream is available,
the field is omitted.

The cross-repo reference convention (Decision 2) lives in one shared file
at `references/cross-repo-references.md`. Format specs link to it with a
single sentence. The convention defines `owner/repo:path` syntax, the
directional visibility rule (public repos can't reference private
artifacts), and examples. It doesn't change how same-repo upstream works —
local relative paths remain the default.

Together, this means: the upstream field on every artifact type is
populated at creation time by the workflow that produces it, using an
explicit path from whoever invoked it. The path can be local
(`docs/visions/VISION-foo.md`) or cross-repo
(`tsukumogami/vision:docs/visions/VISION-foo.md`), with the shared
reference documenting when and how to use each form.

## Solution Architecture

### Overview

The design touches three layers: format specs (what fields exist),
handoff points (where upstream paths are injected), and creation
workflows (where upstream is written to frontmatter). A new shared
reference documents the cross-repo convention. No new infrastructure —
everything is markdown edits to existing skill files.

### Components

```
references/
  cross-repo-references.md            <-- NEW: shared convention doc

skills/roadmap/
  references/
    roadmap-format.md                 <-- MODIFIED: add upstream field
    phases/
      phase-3-draft.md                <-- MODIFIED: read upstream, write to frontmatter

skills/prd/
  references/
    prd-format.md                     <-- MODIFIED: add cross-ref link
    phases/
      phase-3-draft.md                <-- MODIFIED: read upstream, write to frontmatter

skills/explore/
  references/
    phases/
      phase-5-produce-roadmap.md      <-- MODIFIED: pass --upstream when invoking /roadmap

skills/vision/
  references/
    vision-format.md                  <-- MODIFIED: add cross-ref link

skills/design/
  SKILL.md                            <-- MODIFIED: add cross-ref link (upstream field docs)
```

### Key Interfaces

**Roadmap format spec change.** Add `upstream` as an optional frontmatter
field:

```yaml
---
status: Draft
theme: |
  ...
scope: |
  ...
upstream: docs/visions/VISION-<name>.md  # optional
---
```

When present, it points to a VISION document (the natural parent of a
roadmap in the traceability chain). Cross-repo references use the
`owner/repo:path` convention from the shared reference.

**Explore handoff enrichment.** The `phase-5-produce-roadmap.md` handler
passes `--upstream <vision-path>` when invoking `/shirabe:roadmap <topic>`.
The VISION path comes from the explore findings or crystallize artifact —
if the exploration didn't surface a specific VISION document, the flag is
omitted. This is simpler than modifying the scope artifact format and uses
the same `--upstream` mechanism as standalone invocations.

**Roadmap Phase 3 consumption.** The /roadmap skill's `phase-3-draft.md`
reads `--upstream` from `$ARGUMENTS`. If found, writes `upstream:` to
frontmatter. If not found, omits the field. Works identically for both
/explore handoff and standalone invocation.

**PRD Phase 3 consumption.** The /prd skill's `phase-3-draft.md` reads
`--upstream` from `$ARGUMENTS`. If found, writes `upstream:` to
frontmatter. If not found, omits the field. Note: /plan already includes
a `Roadmap:` line in planning issue bodies. A small follow-up can teach
/prd to read that line when invoked from issue context, closing the gap
without requiring Feature 5's full /plan rework.

**Cross-repo reference document.** `references/cross-repo-references.md`
documents:
- Syntax: `owner/repo:path` (first colon separates repo from path)
- Default: same-repo relative paths (`docs/visions/VISION-foo.md`)
- Cross-repo: `tsukumogami/shirabe:docs/designs/DESIGN-foo.md`
- Visibility rule: public repos must not use cross-repo references to
  private repos
- Anti-patterns: relative cross-repo paths, `private:` prefix (dropped)

**Format spec cross-references.** Each format spec that documents an
upstream field adds one sentence linking to the shared convention:

> For cross-repo upstream references, see
> `references/cross-repo-references.md`.

### Data Flow

**Via /explore handoff (roadmap with VISION context):**
```
/explore Phase 4 (crystallize)
  surfaces VISION path from findings
    |
    v
/explore Phase 5 (produce-roadmap)
  invokes: /shirabe:roadmap <topic> --upstream docs/visions/VISION-<name>.md
    |
    v
/roadmap Phase 3 (draft)
  reads --upstream from $ARGUMENTS
  writes upstream: to frontmatter
    |
    v
docs/roadmaps/ROADMAP-<topic>.md
  upstream: docs/visions/VISION-<name>.md
```

**Standalone invocation (any skill):**
```
/roadmap <topic> --upstream docs/visions/VISION-foo.md
/prd <topic> --upstream docs/roadmaps/ROADMAP-foo.md
    |
    v
Phase 3 (draft)
  reads --upstream from $ARGUMENTS
  writes upstream: to frontmatter
```

## Implementation Approach

### Phase 1: Format spec and shared reference

Add `upstream` to roadmap format spec and create the cross-repo reference
document.

Deliverables:
- `skills/roadmap/references/roadmap-format.md` (modified)
- `references/cross-repo-references.md` (new)

### Phase 2: Workflow changes

Update /explore handoff to pass --upstream, and update /roadmap and /prd
to read --upstream and write it to frontmatter.

Deliverables:
- `skills/explore/references/phases/phase-5-produce-roadmap.md` (modified)
- `skills/roadmap/references/phases/phase-3-draft.md` (modified)
- `skills/roadmap/SKILL.md` (modified — document --upstream flag)
- `skills/prd/references/phases/phase-3-draft.md` (modified)
- `skills/prd/SKILL.md` (modified — document --upstream flag)

### Phase 4: Cross-reference links

Add cross-reference sentences to all format specs that document upstream.

Deliverables:
- `skills/vision/references/vision-format.md` (modified)
- `skills/prd/references/prd-format.md` (modified)
- `skills/design/SKILL.md` (modified)
- `skills/roadmap/references/roadmap-format.md` (modified — already
  touched in Phase 1, add cross-ref link)

## Security Considerations

Same profile as prior skill changes: document templates and markdown
workflow instructions. No external inputs, no new permissions, no new
dependencies. The cross-repo reference convention includes the directional
visibility rule (public repos must not reference private artifacts), which
is a security-adjacent concern handled by documentation, not enforcement.
If future tooling ever resolves upstream paths programmatically (e.g.,
fetching referenced files), it should sanitize against directory traversal.

## Consequences

### Positive

- The traceability chain is complete: VISION -> Roadmap -> PRD -> Design
  -> Plan, with every link machine-readable via `upstream` frontmatter
- Creation workflows consistently set upstream at creation time, following
  one pattern (the /design Phase 0 model)
- Cross-repo references have a documented convention instead of ad-hoc
  formats
- The shared reference prevents convention drift across artifact types

### Negative

- Standalone invocations without `--upstream` produce artifacts without
  traceability links. Users who care about traceability need to provide
  the path.
- When /prd is invoked from a plan issue, it doesn't yet read the
  existing `Roadmap:` line from the issue body. This is a small follow-up
  (teaching /prd to detect issue context), not the full Feature 5 rework.
- Multiple format specs and SKILL.md files change in one PR. Review
  surface is broad, though each change is small.

### Mitigations

- Upstream is optional everywhere, so missing links don't break workflows
- The /prd issue-context gap is a small follow-up, not blocked on
  Feature 5
- Each format spec change is a 1-2 line addition, easy to review in
  isolation

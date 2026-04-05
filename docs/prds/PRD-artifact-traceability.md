---
status: Accepted
problem: |
  The artifact pipeline has traceability fields on most types (VISION, PRD,
  Design Doc, Plan) but Roadmaps lack an upstream field, the /prd creation
  workflow never populates its upstream field, and there's no documented
  convention for cross-repo references. The VISION-to-PR chain has a gap at
  the Roadmap level, and references between repos are ad-hoc.
goals: |
  Close the traceability chain so every artifact can point to its parent.
  Document a cross-repo reference convention that all skills can use.
  Make creation workflows consistently set upstream at creation time.
upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md
---

# PRD: Artifact Traceability

## Status

Accepted

## Problem statement

The artifact pipeline supports a traceability chain from VISION through
Roadmap, PRD, Design Doc, Plan, to Issues and PRs. Four of five document
types already have an optional `upstream` frontmatter field that links to
the parent artifact. Roadmaps don't.

The gap breaks the chain at a critical point. A VISION captures strategic
intent, and a Roadmap sequences the features that deliver on it. Without
the link, there's no machine-readable way to trace a Roadmap back to the
VISION that justified it.

Two related problems surfaced during research:

1. **The /prd workflow doesn't set upstream.** The PRD format defines an
   optional `upstream` field (pointing to a roadmap), but the /prd creation
   skill never populates it. Only the /design skill consistently sets
   upstream at creation time.

2. **No cross-repo reference convention.** When artifacts in one repo
   reference artifacts in another (e.g., a private vision repo tracking
   where its roadmap features landed in public repos), there's no documented
   format. Each skill that needs cross-repo references invents its own.

## Goals

- Every document artifact type has an `upstream` frontmatter field
- Creation workflows consistently set `upstream` at creation time
- A shared reference document defines the cross-repo reference convention
- Skills that produce artifacts link to the shared reference

## User stories

1. As a maintainer reviewing a roadmap, I want to see which VISION it
   traces to so I can understand the strategic context without searching.

2. As an agent running /prd from a roadmap feature, I want the PRD's
   upstream field automatically set so the traceability chain stays
   connected without manual edits.

3. As a contributor working across repos, I want a documented convention
   for cross-repo artifact references so I use the same format everywhere.

4. As an agent running /roadmap from /explore with a VISION context, I
   want the roadmap's upstream field set to the VISION path so the link
   exists from creation.

## Requirements

### Functional

**R1. Add `upstream` to Roadmap frontmatter.** The roadmap format spec
gains an optional `upstream` field. Value is a path to a VISION document
(e.g., `docs/visions/VISION-<name>.md`) or a cross-repo reference. When
present, it links the roadmap to the strategic artifact that motivated it.

**R2. /roadmap creation workflow sets upstream.** When /roadmap is invoked
with a VISION context (via /explore handoff or explicit argument), the
creation workflow sets `upstream` in the frontmatter. When invoked
standalone without VISION context, `upstream` is omitted.

**R3. /prd creation workflow sets upstream.** When /prd is invoked from a
roadmap feature (via /plan issue or explicit argument), the creation
workflow sets `upstream` to the roadmap path. When invoked standalone
without roadmap context, `upstream` is omitted. This follows the pattern
established by /design Phase 0.

**R4. Shared cross-repo reference document.** A reference file documents
the `owner/repo:path` convention for cross-repo artifact references. It
covers: format syntax, when to use it (same-repo paths are the default),
the directional visibility rule (public repos must not reference private
artifacts), and examples.

**R5. Skills link to the shared reference.** Each skill whose format spec
includes an `upstream` field links to the shared cross-repo reference
document. The link appears alongside the `upstream` field documentation.

### Non-functional

**R6. Markdown and shell only.** All changes are in skill markdown, format
specs, and shell scripts. No compiled code changes.

**R7. Convention consistency.** The cross-repo format (`owner/repo:path`)
is a compact string, consistent with how the design skill's
`spawned_from.repo` field already references repos.

## Acceptance criteria

- [ ] Roadmap format spec defines optional `upstream` field with VISION as
      the expected target type
- [ ] /roadmap SKILL.md creation workflow sets `upstream` when VISION
      context is available
- [ ] /prd SKILL.md creation workflow sets `upstream` when roadmap context
      is available
- [ ] Shared cross-repo reference file exists and documents
      `owner/repo:path` convention
- [ ] Cross-repo reference file documents the directional visibility rule
- [ ] Each skill with an `upstream` format field links to the shared
      reference
- [ ] Roadmap transition script accepts the new frontmatter field without
      errors
- [ ] No `private:` prefix in the convention (dropped per research)

## Out of scope

- Upstream path validation in transition scripts or CI (no precedent
  exists; significant scope increase for low immediate value)
- Automated Downstream Artifacts section updates (manual and often
  missing, but automation is a separate feature)
- Changes to Design Doc, VISION, or Plan schemas (already have upstream)
- Changes to the `spawned_from` pattern in Design Docs (separate concern)
- Compiled code changes
- Retroactive updates to existing artifacts

## Decisions and trade-offs

**Drop `private:` prefix.** The original Feature 3 description proposed
`owner/repo:path` with a `private:` prefix for visibility boundaries.
Research showed this is redundant: public repos already can't reference
private artifacts (content governance enforces this), and private repos
don't need a prefix because they can reference anything. The prefix adds
no information the reader doesn't already have.

**Defer upstream path validation.** No transition script currently
validates that referenced paths exist. Adding cross-document validation
is new capability with uncertain value. The `superseded_by` field in
design and vision scripts is the closest precedent, and it's not validated
either. Deferring keeps scope tight.

**Compact string over structured YAML.** The cross-repo convention uses
`owner/repo:path` as a compact string rather than separate `repo:` and
`path:` fields. This is easier to read and consistent with how repos are
referenced elsewhere. If programmatic parsing is needed later, the format
is simple enough to split on `:`.

**Upstream is optional everywhere.** Every artifact type makes upstream
optional. Some roadmaps emerge from exploration without a formal VISION.
Some PRDs are standalone. Forcing upstream would block valid workflows.

## Related

- **ROADMAP-strategic-pipeline.md** -- Feature 3 describes this work
- **PRD-plan-skill-rework.md** -- Feature 5 covers /plan enriching
  roadmaps directly, which will consume the upstream field added here

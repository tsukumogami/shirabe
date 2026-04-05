<!-- decision:start id="cross-repo-convention-location" status="confirmed" -->
### Decision: Cross-repo reference convention location and linking

**Context**

The shirabe plugin's artifact types (VISION, PRD, Design Doc, Roadmap) each have
an `upstream` frontmatter field that can point to artifacts in other repositories.
Today, each format spec documents its upstream field independently with local
repo-relative paths only. There's no documented convention for cross-repo
references. The convention applies equally to all artifact types -- any upstream
field could be a cross-repo reference -- so it shouldn't be duplicated per
format spec.

The plugin already has a `references/` directory holding shared conventions:
`decision-protocol.md`, `decision-presentation.md`, and
`decision-block-format.md`. Skills link to these via
`${CLAUDE_PLUGIN_ROOT}/references/<name>.md` paths.

**Assumptions**
- Format specs will add a brief cross-reference note rather than duplicating the full convention
- No tooling changes needed since this is documentation-only
- Agents consult format specs when writing artifacts, so the cross-reference link in format specs is sufficient for discovery

**Chosen: Plugin-level shared reference file at references/cross-repo-references.md**

Create `references/cross-repo-references.md` at the plugin root. The file
documents:

1. **Syntax**: `owner/repo:path` (compact string, no prefix)
2. **When to use**: when an upstream field points to an artifact in a different
   repository
3. **Visibility rules**: public repos must not reference private repo artifacts;
   the directional rule is enforced by convention (no `private:` prefix needed
   since the rule is always "don't do it" for public repos)
4. **Examples**: one per artifact type showing both local and cross-repo upstream
   values
5. **Anti-patterns**: relative cross-repo paths, stale references, referencing
   private artifacts from public repos

Each format spec that documents an upstream field (vision-format.md,
prd-format.md, roadmap-format.md, and the design skill's phase-0 and phase-6
references) adds a single sentence linking to the shared convention:

> When upstream points to an artifact in another repository, use the cross-repo
> reference syntax documented in `references/cross-repo-references.md`.

Skills don't need to load this file at runtime. It's a convention document that
agents consult when they encounter or need to write cross-repo references.

**Rationale**

The user explicitly directed "shared ref in the plugin, linked from each skill
where this ref is relevant." Alternative 1 matches this direction exactly.
The `references/` directory already holds shared conventions following this
pattern (decision-protocol.md, decision-presentation.md,
decision-block-format.md). The cross-repo convention is inherently cross-cutting
-- it applies identically to all artifact types -- making per-skill duplication
both wasteful and drift-prone.

**Alternatives Considered**
- **Per-skill inline duplication**: Each format spec documents the full cross-repo
  syntax in its upstream field section. Rejected because it contradicts the user's
  direction, creates N copies that can drift, and the convention is identical
  across all artifact types.
- **Per-skill reference files**: A cross-repo-references.md in each skill's
  references/ directory. Rejected for the same reasons as inline duplication --
  multiple copies of identical content with no benefit over a single shared file.

**Consequences**

Format specs remain the primary reference for their artifact's frontmatter
schema, with a one-line pointer to the shared convention for cross-repo cases.
This means agents see the cross-repo syntax only when they follow the link, not
inline. That's acceptable because cross-repo references are the exception, not
the norm -- most upstream fields point to local paths.

Adding a new artifact type that supports upstream requires adding one
cross-reference sentence in its format spec, not duplicating the full convention.
Updating the convention (e.g., changing syntax or adding rules) requires editing
one file.
<!-- decision:end -->

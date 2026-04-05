# Phase 2 Research: Architecture Perspective

## Lead 1: Cross-Repo Reference Convention

### Findings

**Current state of upstream references.** Every `upstream` field in shirabe today
uses a local relative path (e.g., `upstream: docs/prds/PRD-roadmap-skill.md`).
No existing artifact uses a cross-repo reference. The `spawned_from` field in
design docs already has a cross-repo structure (`repo: <owner/repo>`,
`issue: <number>`, `parent_design: <path>`) but it's for issue-to-design links,
not for artifact-to-artifact traceability.

**Visibility boundary rules are already strict.** The `public-content` skill
(skills/public-content/SKILL.md) states: "Only reference issues, PRs, and
designs in public repos" and "Only link to public resources (no private repo
links)." The `private-content` skill (skills/private-content/SKILL.md) allows
referencing any repo. The /plan skill's phase-7-creation.md makes this
directional rule explicit: "Public issues must NEVER reference private issues.
Only private issues can reference public issues."

**The `private:` prefix concept from Feature 3.** The roadmap says:
"Cross-repo reference convention: `owner/repo:path` with `private:` prefix for
visibility boundaries." The question is what problem this solves.

**Real-world cross-repo flow.** The private `vision` repo contains
`docs/roadmaps/ROADMAP-shirabe.md` -- a roadmap for shirabe authored in the
private repo. This roadmap has no `upstream` field. The public shirabe repo has
its own `ROADMAP-strategic-pipeline.md` with no cross-repo upstream either. The
actual flow today is: private vision repo produces strategic roadmaps, then
public repos produce their own tactical artifacts independently. There's no
formal link between them.

**What `private:` would mean operationally.** Consider the scenario: a VISION
in private `vision` repo spawns a Roadmap in public `shirabe`. The roadmap's
upstream would logically be `private:tsukumogami/vision:docs/visions/VISION-foo.md`.
But public repos can't reference private artifacts per governance rules. So
`private:` can't appear in a public repo's frontmatter -- it would violate the
very rules that already exist.

The only scenario where `private:` makes sense is inside a private repo
referencing another private repo, as a way to distinguish "this reference goes
to a different private repo" from "this is a local path." But that's just
the `owner/repo:path` syntax doing its job -- the `private:` prefix adds no
information the reader doesn't already have (they know both repos are private
because they can see them).

**One narrow case where `private:` could help.** A private repo artifact could
reference a public repo artifact, and separately a public repo could have a
"stub" upstream that says `private:` to signal "there is an upstream artifact
you can't follow." This would be documentation-as-metadata: telling the reader
the chain continues but is inaccessible. However, this contradicts the
public-content governance rule against referencing private resources at all.

### Implications for Requirements

1. **The `private:` prefix should be dropped from the convention.** It's
   redundant with visibility governance rules. Public repos can't use it (would
   violate governance). Private repos don't need it (they can reference anything).

2. **The cross-repo convention `owner/repo:path` is sufficient on its own.**
   It handles the case of private repos referencing public repo artifacts (which
   is allowed and useful).

3. **Public repo artifacts with private upstream should use a null/absent
   upstream field**, not a `private:` stub. The traceability chain breaks at
   visibility boundaries by design.

4. **The convention should be documented once in a shared location** (not
   per-format-spec). Options: a reference file in the plugin, or a section in
   CLAUDE.md. Given that multiple skills consume it (design, plan, roadmap, prd,
   vision), a shared reference makes sense.

### Open Questions

1. Should the cross-repo convention support GitHub issue references too
   (`owner/repo#42`) or only file paths (`owner/repo:path`)? The `spawned_from`
   field already uses issue numbers -- should `upstream` unify both?

2. When a public artifact's true upstream is in a private repo, should there be
   any signal in the public artifact's metadata? (Current answer: no, but this
   means the traceability chain has invisible gaps in public repos.)

3. Should validation scripts check that `upstream` paths actually resolve? This
   is easy for local paths, hard for cross-repo paths.

## Lead 2: Workspace Cross-Repo Flows

### Findings

**Workspace structure.** The workspace has two private repos (tools, vision) and
four public repos (tsuku, koto, shirabe, niwa). The workspace CLAUDE.md
documents this and assigns visibility/scope to each.

**Strategic-to-tactical flow.** The private `vision` repo contains strategic
roadmaps for public projects (e.g., `ROADMAP-shirabe.md` in vision/docs/roadmaps/).
These roadmaps don't link back to VISIONs because the VISION artifact type was
just recently added (Feature 1 of the strategic pipeline roadmap). The flow is:
vision repo holds strategic intent, public repos hold tactical artifacts. The
handoff is currently informal.

**No existing cross-repo upstream links.** Every `upstream` field in the codebase
points to a local file path. Cross-repo references exist only in:
- `spawned_from.repo` in design doc frontmatter (for issue links)
- Issue body references (`owner/repo#42` format)
- The /plan skill's phase 7 upstream-issue linking

**The directional rule is already established.** The /plan skill explicitly
states: "Only update if the upstream issue is in a repo with SAME or MORE PRIVATE
visibility." This means:
- Private can reference public (allowed)
- Public can reference public (allowed)
- Private can reference private (allowed)
- Public can reference private (forbidden)

This directional rule applies equally to artifact upstream fields.

**Where cross-repo upstream would actually be used.** The most likely real flow:
1. Private `vision` repo: VISION -> Roadmap (both local, both private)
2. Private roadmap references features that spawn PRDs in public repos
3. Public repo PRD: upstream is local design doc or roadmap (within same repo)

The cross-repo link would be in the private repo pointing to the public repo's
artifacts ("Feature X was implemented in shirabe, see tsukumogami/shirabe:docs/designs/DESIGN-foo.md").
This is the private-references-public direction, which is allowed.

### Implications for Requirements

1. **Cross-repo upstream is primarily a private-repo concern.** Public repos
   will mostly use local paths. Private repos need cross-repo paths to track
   where their strategic artifacts landed tactically.

2. **The convention needs to be available to both visibility levels.** Even
   though public repos rarely need it, the format spec should be universal.
   A public repo could reference another public repo's artifacts.

3. **The existing `spawned_from` pattern in design docs is a partial precedent**
   but uses structured YAML (separate fields for repo, issue, parent_design)
   rather than a compact string format. The new convention should decide: compact
   string (`owner/repo:path`) or structured YAML?

### Open Questions

1. Should `upstream` use the same structured format as `spawned_from` (with
   separate `repo:` and `path:` fields) or a compact string? Compact is easier
   to read; structured is easier to parse programmatically.

2. Does the `vision` repo need to adopt the same frontmatter conventions? It
   currently has no `upstream` fields on its roadmaps.

## Summary

The `private:` prefix concept from Feature 3 is redundant with existing visibility
governance rules and should be dropped. Public repos can't reference private
artifacts at all (enforced by content governance), so the prefix has no valid use
in public repos. Private repos don't need it because they can reference anything.
The cross-repo convention should simply be `owner/repo:path`, with the directional
visibility rule (already established in /plan's phase 7) serving as the enforcement
mechanism. The main consumers of cross-repo upstream will be private repos tracking
where strategic artifacts spawned tactical work in public repos.

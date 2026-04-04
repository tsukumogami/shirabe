# Decision 2: /explore -> /roadmap Handoff (Inline to Auto-Continue)

## Question

How does the /explore -> /roadmap handoff change from inline production to
auto-continue?

## Decision

**Chosen option: Follow the /vision handoff pattern exactly, with
roadmap-specific content in the handoff artifact.**

The change has three parts: a new `phase-5-produce-roadmap.md` handoff file,
an updated routing table, and removal of the Roadmap section from
`phase-5-produce-deferred.md`.

---

## Part 1: Handoff Artifact Contents

The handoff artifact is `wip/roadmap_<topic>_scope.md`. It maps to /roadmap's
Phase 1 output, so /roadmap can skip Phase 1 (scoping) and resume at Phase 2
(discover) when the file exists -- identical to how /vision and /prd handle
handoffs.

### Template

```markdown
# /roadmap Scope: <topic>

## Theme Statement
<2-3 sentences synthesized from exploration findings. What initiative is
being sequenced and why does coordination matter?>

## Initial Scope
### This Roadmap Covers
- <capability area or feature cluster from exploration>
- <item>

### This Roadmap Does NOT Cover
- <adjacent work deliberately excluded, with reasoning>

## Candidate Features
1. <feature>: <rationale from exploration>
2. <feature>: <rationale>

## Coverage Notes
<Gaps or uncertainties to resolve in /roadmap Phase 2. What did the
exploration NOT answer about sequencing, dependencies, or feature
boundaries?>

## Decisions from Exploration
<If wip/explore_<topic>_decisions.md exists, include accumulated decisions
here. These are scope narrowing, option eliminations, and priority choices
already made during exploration that the roadmap should treat as settled.
If the decisions file doesn't exist, omit this section.>
```

### Rationale for Divergences from PRD/VISION Templates

The PRD handoff has "Problem Statement" and "Research Leads." The VISION
handoff has "Problem Statement" and "Research Leads." Both make sense because
PRDs and VISIONs start from a problem to investigate.

Roadmaps don't start from a problem. They start from a *theme* (what
initiative needs coordinated sequencing) and *candidate features* (what work
items to sequence). The handoff artifact reflects this:

- **Theme Statement** replaces Problem Statement. Roadmaps answer "what needs
  coordinating?" not "what problem are we solving?"
- **Candidate Features** replaces Research Leads. The /roadmap discover phase
  investigates feature boundaries and dependencies, not open research
  questions. Candidate features give discover agents concrete things to
  investigate.
- **Initial Scope** uses Covers/Does NOT Cover framing (matching the roadmap
  format's `scope` frontmatter) rather than In Scope/Out of Scope (PRD) or
  IS/IS NOT (VISION).

Coverage Notes and Decisions from Exploration are structurally identical to
the other handoff templates.

---

## Part 2: Routing Table Change

In `phase-5-produce.md`, the routing table currently sends Roadmap to
`phase-5-produce-deferred.md` with "Stops -- terminal" behavior.

Updated row:

| Chosen Type | Reference File | Handoff |
|-------------|----------------|---------|
| Roadmap | `phase-5-produce-roadmap.md` | Auto-continues into /roadmap |

The new `phase-5-produce-roadmap.md` file follows the exact structure of
`phase-5-produce-prd.md` and `phase-5-produce-vision.md`:

1. Write `wip/roadmap_<topic>_scope.md` using the template above
2. Commit: `docs(explore): hand off <topic> to /roadmap`
3. Invoke: `/shirabe:roadmap <topic>`
4. /roadmap detects the handoff artifact and resumes at Phase 2

### Artifact State section (matches other handoff files):

```
After this step:
- All explore artifacts in wip/ (untouched)
- wip/roadmap_<topic>_scope.md (new)
- Session continues in /roadmap at Phase 2
```

---

## Part 3: Removing Inline Production from phase-5-produce-deferred.md

**Remove the Roadmap section entirely.** Don't keep it as a fallback.

Reasoning:

1. The cross-cutting decision in ROADMAP-strategic-pipeline.md is explicit:
   "each document type gets its own skill with a creation workflow" and
   "/explore hands off to these skills via auto-continue." Keeping a fallback
   path contradicts this.

2. The other auto-continue types (PRD, Design Doc, Decision Record, VISION)
   have no fallback inline production in deferred. The Roadmap section was
   only in deferred because the skill didn't exist yet.

3. If /roadmap isn't available for some reason, the error should surface
   clearly rather than silently falling back to a lower-quality inline
   template.

After removal, `phase-5-produce-deferred.md` retains: Unsupported Type
(Prototype Only), Spike Report, and Competitive Analysis. Update the Table
of Contents accordingly.

---

## /roadmap Skill: Handoff Detection

For completeness, the /roadmap SKILL.md needs the same handoff detection
pattern as /vision (from `skills/vision/SKILL.md` lines 77-83):

```
On startup, check for wip/roadmap_<topic>_scope.md. If it exists, an /explore
session already ran Phase 5 and wrote the handoff artifact with synthesized
findings. Skip Phase 1 (scoping) and proceed directly to Phase 2 (discover) --
the scope file provides the theme statement and candidate features.

If no handoff artifact exists, start from Phase 1.
```

Resume logic follows the same pattern:

```
wip/roadmap_<topic>_scope.md exists        -> Resume at Phase 2
ROADMAP-<topic>.md exists with Draft       -> Resume at Phase 3
On a branch related to the topic           -> Resume at Phase 1
On main or unrelated branch                -> Start at Phase 0
```

---

## Rejected Alternatives

### Keep inline production as fallback alongside auto-continue

Rejected because it contradicts the cross-cutting decision, creates two code
paths to maintain, and masks errors when /roadmap isn't properly set up. No
other artifact type has a fallback -- consistency matters.

### Reuse the PRD handoff template verbatim (Problem Statement + Research Leads)

Rejected because roadmaps aren't problem-driven. Forcing "Problem Statement"
framing onto a sequencing artifact creates an impedance mismatch. The /roadmap
discover phase needs candidate features to investigate, not open research
questions. The structural divergence is small (two renamed sections) but
semantically significant.

---

## Assumptions

1. The /roadmap skill will have a Phase 1 (Scope) that produces output
   compatible with the handoff artifact template above. Decision 1 (workflow
   phases) defines the details; this decision assumes the standard pattern
   where Phase 1 output = handoff artifact format.

2. The /roadmap skill will exist and be invocable as `/shirabe:roadmap` by
   the time this change ships. The routing table change and deferred removal
   should land in the same PR as the /roadmap skill creation.

3. /roadmap's Phase 2 (Discover) can consume candidate features as
   investigation targets. The discover phase agents need to know what features
   to investigate for dependencies and boundaries -- candidate features
   serve that purpose the way research leads serve PRD and VISION.

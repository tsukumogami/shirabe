# Architecture Review: DESIGN-artifact-traceability.md

## Reviewer Context

Reviewed the design document against the actual skill files that will be
modified. Assessed clarity, completeness, sequencing, alternatives, and the
/plan entry point gap.

---

## 1. Is the architecture clear enough to implement?

**Verdict: Yes, with one gap requiring clarification.**

The design clearly identifies the three layers (format specs, handoff points,
creation workflows), names every file to be modified, and provides concrete
examples of the frontmatter and markdown changes. The data flow diagrams for
each entry point (/explore handoff, standalone /roadmap, standalone /prd) are
unambiguous.

The one area needing clarification is how /roadmap Phase 3 detects whether
`$ARGUMENTS` contains `--upstream <path>`. The current phase-3-draft.md
(roadmap) has no argument parsing logic -- it reads the scope artifact and
format spec. The design says "checks $ARGUMENTS for an --upstream flag" but
doesn't specify the parsing mechanism. This is minor since the pattern exists
in other skills (flag parsing in /plan is well-documented), but the
implementer will need to add argument parsing to a phase file that currently
has none.

## 2. Are there missing components or interfaces?

**Two items identified.**

### 2a. /explore Phase 4 (crystallize) -- VISION identification mechanism

The design says Phase 5 writes the `## Upstream` section "only when /explore
identified a VISION during crystallization (Phase 4)." But it doesn't specify
HOW Phase 4 identifies the VISION. Currently, Phase 4 crystallizes by
selecting the artifact type to produce (roadmap, PRD, design, etc.). There's
no existing step where it reads a VISION document or records its path.

The design needs to either:
- Specify what constitutes "identifying a VISION" (e.g., user mentioned one,
  scope artifact references one, `docs/visions/` was scanned during Phase 2)
- Or acknowledge that this happens naturally when the exploration topic was
  derived from a VISION document, and the path is available in the scope file

Without this, the implementer won't know where the VISION path comes from
when Phase 5 tries to write it into the scope artifact.

### 2b. /plan agent-prompt-planning.md template -- no Upstream line

The design's Decision 1 mentions planning issues should include an
`Upstream: docs/roadmaps/ROADMAP-<name>.md` line, but then the PRD Phase 3
section says "The /plan integration (passing roadmap path via planning issues)
is deferred to Feature 5 (Plan Skill Rework)."

This is somewhat contradictory. The agent-prompt-planning.md template already
includes `Roadmap:` and `Feature:` lines in the Context section of generated
issue bodies. The Phase 7 validation step (7.4) already verifies these exist.
So the traceability from planning issues back to the roadmap is already
implemented -- just using `Roadmap:` instead of `Upstream:`.

The design should explicitly note that the existing `Roadmap:` line in
planning issues serves the same traceability purpose as the proposed
`Upstream:` line, and clarify whether these should be unified or kept
separate. Currently the design implies a new `Upstream:` line is needed when
one functionally equivalent line already exists.

## 3. Are the implementation phases correctly sequenced?

**Yes, the sequencing is correct.**

- Phase 1 (format spec + shared reference) has no dependencies. Correct as
  the starting point.
- Phase 2 (handoff enrichment in /explore Phase 5) depends on knowing the
  upstream field name from Phase 1. Correct ordering.
- Phase 3 (creation workflow consumption in /roadmap and /prd Phase 3) depends
  on both the format spec (Phase 1) and the handoff artifacts (Phase 2) being
  defined. Correct ordering.
- Phase 4 (cross-reference links) is purely additive documentation. Placing
  it last avoids touching the same files twice (roadmap-format.md is modified
  in Phase 1 for the field and in Phase 4 for the cross-ref link). This is
  a reasonable choice -- could also be folded into Phase 1 without risk.

One minor optimization: Phase 4 modifying roadmap-format.md again (already
touched in Phase 1) means two separate edits to the same file across phases.
An implementer doing this in a single PR could combine them. The design
acknowledges this with "(already touched in Phase 1, add cross-ref link)."

## 4. Are there simpler alternatives we overlooked?

**One simpler partial alternative exists but was correctly rejected.**

The design considers and rejects heuristic detection, which is the right call.
The chosen approach (explicit argument passing via handoff enrichment) is
already the simplest reliable pattern.

However, there's an even simpler approach for the /explore -> /roadmap path
specifically: instead of adding a new `## Upstream` section to the scope
artifact, the VISION path could be passed as an argument when invoking
`/shirabe:roadmap <topic>`. The scope artifact already triggers Phase 2
resume, and the `--upstream` flag would be parsed by Phase 3. This would
eliminate the need to modify the scope artifact format entirely.

Current design approach:
```
Phase 5 writes ## Upstream to scope artifact
  -> Phase 3 reads ## Upstream from scope artifact
```

Simpler alternative:
```
Phase 5 invokes /shirabe:roadmap <topic> --upstream <path>
  -> Phase 3 reads --upstream from $ARGUMENTS
```

This uses the same `--upstream` flag mechanism already designed for standalone
invocations, reducing the interface surface. The scope artifact stays
unchanged. The tradeoff is that the upstream path wouldn't be persisted in wip/
(losing resumability if the session crashes between Phase 5 invocation and
Phase 3 consumption). Given that this is the same session, the risk is low.

## 5. Does the design account for the /plan entry point for /prd?

**Partially -- there is an acknowledged gap with a deferral.**

The design explicitly states: "The /plan integration (passing roadmap path via
planning issues) is deferred to Feature 5 (Plan Skill Rework)."

However, analyzing the current /plan codebase reveals that the gap is smaller
than the design implies:

1. The agent-prompt-planning.md template already generates planning issues
   with `Roadmap: \`<path>\`` in the Context section.
2. Phase 7 (creation) validates that every planning issue body contains this
   `Roadmap:` reference.
3. When a user runs `/work-on` on a `needs-prd` planning issue, the issue
   body already contains the roadmap path.

What's actually missing is narrower: the /prd skill's Phase 3 doesn't read
the issue body context when invoked from /work-on. The roadmap path IS in the
issue body -- /prd just doesn't look for it.

The fix would be: in /prd Phase 3, when the invocation context includes a
GitHub issue (i.e., /work-on triggered the /prd workflow), read the issue
body, extract the `Roadmap:` line, and use it as the upstream value.

This is simpler than what the design's deferral implies (which suggests /plan
itself needs reworking). The /plan skill already does the right thing. The gap
is purely in /prd's consumption side.

**Recommendation:** Consider pulling this fix into the current design scope
rather than deferring to Feature 5. It's a small addition to /prd Phase 3
(read issue body when invoked from /work-on context, extract Roadmap line)
that would complete the traceability chain without waiting for a plan rework.

---

## Summary of Findings

| # | Category | Severity | Finding |
|---|----------|----------|---------|
| 1 | Missing interface | Medium | VISION identification mechanism in /explore Phase 4 undefined |
| 2 | Redundancy | Low | Planning issues already have `Roadmap:` line; relationship to proposed `Upstream:` unclear |
| 3 | Simpler alternative | Low | /explore Phase 5 could pass --upstream as argument instead of modifying scope artifact |
| 4 | Deferral scope | Medium | /prd consumption of issue body context is simpler than implied; could be included now |
| 5 | Implementation detail | Low | Argument parsing in /roadmap Phase 3 needs to be defined (no precedent in that file) |

## Recommendations

1. **Add a note to the design** explaining where the VISION path comes from
   during /explore. Either the scope file already contains it (from the user's
   initial exploration topic), or Phase 2/4 must surface it. Without this, the
   implementer will have to guess.

2. **Clarify the relationship** between the existing `Roadmap:` line in
   planning issues and the proposed `Upstream:` mechanism. Are they the same
   concept with different names? Should /prd treat `Roadmap:` as equivalent
   to `upstream:` frontmatter?

3. **Consider including the /prd issue-body consumption** in this design's
   scope rather than deferring. The change is small (add issue-body reading
   to /prd Phase 3 when invoked from /work-on) and it closes the most
   common traceability gap (roadmap -> PRD link) without waiting for a
   separate feature.

4. **Consider the simpler /explore handoff** (passing --upstream as an
   argument to /roadmap invocation instead of adding a section to the scope
   artifact). The tradeoff is minor resumability loss in exchange for a
   smaller change surface.

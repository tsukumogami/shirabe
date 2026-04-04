# Architecture Review: DESIGN-vision-artifact-type

Review of the solution architecture and implementation approach for adding
VISION as a supported artifact type in the crystallize framework.

## Question 1: Is the architecture clear enough to implement?

**Verdict: Yes, with two gaps to fill.**

The design identifies the exact files to create and modify (3 new, 2 modified),
specifies the data flow from wip/ exploration artifacts to the output VISION
document, and names the dispatch pattern being followed. An implementer can
read this and know what to build.

### Gap 1: SKILL.md structure is underspecified

The design says `skills/vision/SKILL.md` follows the pattern of
`skills/prd/references/prd-format.md`, but the PRD skill has two distinct files:

- `skills/prd/SKILL.md` -- the skill manifest with frontmatter (name,
  description, argument-hint), workflow phases, input modes, and repo visibility
  handling
- `skills/prd/references/prd-format.md` -- the format reference with sections,
  frontmatter spec, lifecycle, validation rules, and quality guidance

The design conflates these. VISION is described as a "reference-only skill (no
creation workflow)" -- meaning it has no workflow phases, no input modes, no
conversational scoping. It is consulted by the explore produce handler, not
invoked directly. This raises the question: does VISION need a SKILL.md manifest
at all, or just a format reference file?

**Recommendation:** The design should clarify whether `skills/vision/SKILL.md`
is a proper skill manifest (with frontmatter, even if minimal) or just a format
reference. Looking at the existing pattern, even reference-only information
benefits from the SKILL.md manifest structure because:
- The eval framework expects `skills/<name>/evals/evals.json` alongside a
  SKILL.md
- The plugin system discovers skills by scanning for SKILL.md files

The cleanest path: create `skills/vision/SKILL.md` as a minimal manifest that
does NOT register as an invocable skill (no `argument-hint`, description makes
clear it is a reference skill only), and embed the format specification directly
in it rather than splitting into a references/ subdirectory. There is no
references/ subdirectory needed because VISION has no workflow that loads
reference files at different phases.

### Gap 2: Crystallize framework "Deferred Types" section needs cleanup

The current crystallize-framework.md has a "Deferred Types" section listing
Roadmap, Spike Report, Competitive Analysis, Decision Record, and Prototype.
However, Roadmap, Spike Report, Competitive Analysis, and Decision Record are
already handled by produce handlers (phase-5-produce-deferred.md and
phase-5-produce-decision.md respectively). The "Deferred Types" section is
stale -- it says "They'll be added in Feature 5" but they were already added.

The design says to "Add VISION to the Supported Types section with signal table"
and "Move from 5 to 6 supported types in Step 1." But the current Step 1
already says "five supported types" while the routing table handles 9 types
(PRD, Design Doc, Decision Record, Plan, Rejection Record, No Artifact, Roadmap,
Spike Report, Competitive Analysis, Prototype). The Supported Types vs Deferred
Types distinction in the framework is out of sync with reality.

**Recommendation:** Phase 2 should also clean up the Deferred Types section.
Move Roadmap, Spike Report, Competitive Analysis, and Decision Record from
"Deferred Types" to "Supported Types" (with their signal/anti-signal tables),
or at minimum acknowledge the discrepancy. Otherwise the implementer will
encounter a framework file that contradicts the routing table and won't know
which to trust.

This is not scope creep -- the design already modifies this file. Leaving stale
"deferred" labels while adding VISION as "supported" creates a confusing
taxonomy where some routable types are called deferred and others supported.

## Question 2: Are there missing components or interfaces?

**Two items identified.**

### Missing: Crystallize framework "Supported Types" count update

The design mentions updating Step 1 from 5 to 6 supported types. But if the
deferred types that are now routable aren't also moved to Supported, the count
should account for the actual routing behavior. The interface between the
crystallize evaluation procedure (Step 1) and the produce routing table
(phase-5-produce.md) needs to be consistent about which types are scored as
supported candidates vs. which are handled as deferred fallbacks.

### Missing: No explicit handling for VISION in the routing table category

The design says VISION goes "between Decision Record and the deferred types"
in the routing table. Looking at the current table:

| Chosen Type | Reference File | Handoff |
|-------------|----------------|---------|
| PRD | phase-5-produce-prd.md | Auto-continues |
| Design Doc | phase-5-produce-design.md | Auto-continues |
| Decision Record | phase-5-produce-decision.md | Auto-continues |
| Plan | phase-5-produce-plan.md | Stops |
| Rejection Record | phase-5-produce-rejection-record.md | Stops |
| No artifact | phase-5-produce-no-artifact.md | Stops |
| Roadmap, Spike Report, ... | phase-5-produce-deferred.md | Stops |

VISION gets its own handler (`phase-5-produce-vision.md`) and stops (terminal,
no downstream skill invocation). This is clear. The handoff column should say
"Stops -- terminal" since VISION is a standalone document with no downstream
skill to invoke.

### Not missing but worth confirming: upstream field validation

The design's frontmatter includes `upstream: docs/visions/VISION-<parent>.md`
for project-level VISIONs. No validation rule is specified for this field. The
PRD format has upstream as optional with no validation beyond "path to parent
artifact." VISION should match this pattern -- no file-existence check needed
during production. This is consistent and fine as-is.

## Question 3: Are the implementation phases correctly sequenced?

**Yes, the sequencing is correct.** Each phase builds on the prior:

1. **Phase 1 (SKILL.md)** -- standalone, no dependencies. Must exist before
   Phase 3 can reference it, but Phase 2 doesn't need it.
2. **Phase 2 (crystallize framework)** -- standalone modification. Must happen
   before Phase 3 because the produce handler only fires when crystallize
   selects VISION.
3. **Phase 3 (produce handler + routing)** -- depends on Phase 1 (handler
   references the format) and Phase 2 (routing only triggers for a recognized
   type).
4. **Phase 4 (evals)** -- depends on all prior phases being complete.

One minor observation: Phases 1 and 2 are independent and could be done in
parallel. But sequential is fine for a 4-phase plan with small deliverables.

**The phases correctly avoid a common mistake:** they don't try to modify the
explore skill's SKILL.md to add VISION awareness. The explore skill doesn't need
to know about VISION -- it delegates type selection to crystallize and production
to the produce handlers. The explore SKILL.md doesn't list artifact types.

## Question 4: Are there simpler alternatives we overlooked?

**Two alternatives considered, both rejected for good reasons.**

### Alternative A: Put VISION in phase-5-produce-deferred.md

Instead of creating a new `phase-5-produce-vision.md`, add a "Vision" section
to the existing deferred handler alongside Roadmap, Spike Report, and
Competitive Analysis.

**Why it's simpler:** One fewer file. Uses an established pattern.

**Why the design's approach is better:** The deferred handler is named "deferred"
because those types were originally deferred and later implemented inline. VISION
was never deferred -- it's a new supported type designed from the start. Putting
it in the deferred file muddles the naming. More practically, the deferred file
handles types with simpler templates (Roadmap is a list, Spike Report is a
question/answer). VISION has visibility gating, scope detection, and a more
complex section matrix. It warrants its own file for readability.

The design's choice of a dedicated handler file is the right call.

### Alternative B: Skip the SKILL.md, just add the format to the produce handler

Put the VISION template directly in `phase-5-produce-vision.md` rather than
creating a separate `skills/vision/SKILL.md` that the handler references.

**Why it's simpler:** One fewer file, one fewer indirection.

**Why it doesn't work:** The eval framework expects `skills/<name>/evals/`
structure. Without a SKILL.md, the eval convention breaks. Also, future
workflows (like /prd reading an upstream VISION to validate status) need a
canonical format reference that isn't buried in an explore phase file.

The two-file approach (SKILL.md + produce handler) is correct.

### Alternative C: Merge VISION into PRD with a "type: vision" frontmatter field

Rather than a new artifact type, extend PRD to handle pre-project justification
by adding a `type: vision | requirements` field.

**Why it's simpler:** No crystallize changes, no new produce handler, no new
signal/anti-signal table.

**Why it's wrong:** The design doc's problem statement explains this well --
VISION and PRD have fundamentally different content (thesis vs. requirements,
categories vs. features, strategic justification vs. acceptance criteria). A
PRD with `type: vision` would need to suppress most PRD-required sections (User
Stories, Requirements, Acceptance Criteria) and add VISION-specific ones
(Thesis, Org Fit, Success Criteria). The result would be a PRD that's mostly
N/A sections, which is worse than a dedicated type.

## Summary of Recommendations

1. **Clarify SKILL.md structure** (Gap 1): State explicitly that
   `skills/vision/SKILL.md` is a minimal manifest with embedded format spec,
   not a workflow skill with phases. No `references/` subdirectory needed.

2. **Clean up Deferred Types** (Gap 2): When modifying the crystallize
   framework in Phase 2, also address the stale Deferred Types section. At
   minimum, note that Roadmap/Spike Report/Competitive Analysis/Decision Record
   are now routable. Ideally, move their signal tables into Supported Types.
   This is the single biggest risk for implementer confusion.

3. **Specify routing table handoff behavior**: Confirm VISION's handoff column
   says "Stops -- terminal" to match Roadmap/Spike Report behavior.

4. **No blocking issues**: The architecture is sound. The three decisions
   compose correctly, the data flow is clear, and the phase sequencing is right.
   The two gaps above are clarifications, not design flaws.

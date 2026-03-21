# Decision 11: Format Mapping Between Decision Reports and Consumers

Analysis for how the format mapping between decision reports and consuming formats
(Considered Options, ADR) should be specified and maintained.

## Problem Statement

The decision framework has three formats that must stay in sync:

1. **Decision blocks** (HTML comments with markdown) -- inline tracking format
2. **Decision reports** (canonical output of the decision skill) -- Context, Assumptions, Chosen, Rationale, Alternatives, Consequences
3. **Design doc Considered Options** (existing format from `considered-options-structure.md`) -- Decision N heading, Chosen subsection, Alternatives Considered subsection

The explore skill also produces a fourth consumer: standalone ADR files via
`phase-5-produce-deferred.md` with its own structure (Context, Decision, Options
Considered, Consequences).

The maintainability review (`review-maintainability.md`) identified this as Risk 3:
"Format Coupling Without Ownership." Adding one field (e.g., Reversibility) requires
updating 7-8 files across 3 skills with no automated completeness check. The design
says reports "map to Considered Options sections" but doesn't specify who does the
mapping, what the rules are, or where they live.

## Options Analyzed

### Option A: Dedicated format-mapping reference file

A single `references/format-mapping.md` that owns all translations between the
canonical decision report and each consumer format. Consumer phase files reference
it instead of embedding their own mapping rules.

**When a field is added:**
1. Update the canonical format spec (1 file)
2. Update `format-mapping.md` with the new field's rendering in each consumer (1 file)
3. Done -- consumer phase files don't change because they reference the mapping file

**File change count for adding a field: 2 files.**

Strengths:
- Single source of truth for all translations
- Consumer phase files are stable -- they don't change when the format evolves
- Easy to audit: one file shows every consumer's interpretation of every field
- A reviewer can check "does format-mapping.md cover the new field for all consumers?" in one place

Weaknesses:
- Indirection: a developer reading the design skill's cross-validation phase must jump to a separate file to understand how decision reports become Considered Options
- The mapping file can grow large if there are many consumers (ADR, Considered Options, PR body, terminal summary, lightweight compact variant)
- Risk of the mapping file becoming a "god reference" that every skill depends on, creating a coupling hub

### Option B: Inline in each consumer's phase file

Each consumer owns its adapter. The design skill's phase-2 (or a cross-validation
phase) contains its own rules for "how decision reports become Considered Options."
The explore skill's phase-5-produce-deferred.md contains its own rules for "how
decision reports become ADR sections."

**When a field is added:**
1. Update the canonical format spec (1 file)
2. Update design skill's consumer phase (1 file)
3. Update explore skill's ADR producer phase (1 file)
4. Update any other consumer phase files (N files)

**File change count for adding a field: 2 + N consumer files.**

Strengths:
- Co-locates mapping with the code that uses it -- no indirection
- Each consumer can evolve independently (e.g., ADR format changes don't affect design skill)
- Natural ownership: the design skill team owns the Considered Options mapping, the explore skill team owns the ADR mapping

Weaknesses:
- This is the status quo that produces the 7-8 file problem identified in the maintainability review
- No single place to verify all consumers handle a new field
- Drift is the expected outcome, not an edge case -- each consumer silently falls behind when the canonical format changes
- Scales poorly: each new consumer adds another file that must track format changes

### Option C: Single canonical format with consumer-specific sections

The decision report format spec itself includes "How to render as Considered Options"
and "How to render as ADR" sections. The format and its consumers are co-located
in one file.

**When a field is added:**
1. Update the canonical format spec, including its consumer rendering sections (1 file)

**File change count for adding a field: 1 file.**

Strengths:
- Minimum possible file count for format changes (1)
- Co-location between format definition and rendering rules prevents drift by design -- you can't add a field without seeing the consumer sections right there
- The format spec becomes a complete contract: "here is the canonical structure, and here is how each consumer interprets it"
- A reviewer modifying the format sees all downstream implications in the same file

Weaknesses:
- The format spec file grows larger (format definition + N consumer rendering sections)
- Mixes concerns: the canonical format is a data contract, while consumer rendering is presentation logic
- If a consumer's rendering rules are complex (e.g., Considered Options has specific markdown heading levels, prose style requirements), the file becomes unwieldy
- Consumer-specific details in the format spec create a dependency inversion: the format spec "knows about" its consumers

## Evaluation Against Decision Drivers

### Driver 1: Minimize files changed per format update

- Option A: 2 files (format spec + mapping file)
- Option B: 2 + N files (worst case 7-8 per the maintainability review)
- Option C: 1 file

Option C wins, Option A is acceptable, Option B is the problem we're solving.

### Driver 2: Prevent drift between canonical format and consumer rendering

Drift happens when format changes don't propagate to all consumers. The key question
is whether separation or co-location prevents drift better.

- Option A: Drift between format spec and mapping file is possible but contained (2 files, likely edited in the same PR). Drift between mapping file and consumer phase files is eliminated (phase files reference the mapping, don't embed it).
- Option B: Drift is the primary failure mode. Each consumer independently tracking changes is exactly the problem statement.
- Option C: Drift within the file is impossible -- the consumer sections are right there. But drift between the file and consumer phase files that implement the rendering is still possible if the phase files contain implicit format assumptions.

Option C wins for internal consistency. Option A wins for consumer phase file consistency. Option B loses.

### Driver 3: Readability for a developer working on one consumer

A developer modifying the design skill's cross-validation phase needs to understand
how decision reports map to Considered Options.

- Option A: Developer reads the phase file, sees a reference to `format-mapping.md`, opens it, finds the Considered Options section. One hop.
- Option B: Developer reads the phase file and finds the mapping inline. Zero hops.
- Option C: Developer reads the phase file, sees a reference to the format spec, opens it, navigates to the "How to render as Considered Options" section. One hop, but the file is larger.

Option B wins marginally, but the difference between 0 and 1 hop is small. The real
cost is in maintenance, not in reading.

### Driver 4: Scales to new consumers

If a new consumer appears (e.g., a "decision digest" for PR bodies, or a "decision
dashboard" summary), what changes?

- Option A: Add a section to `format-mapping.md`. Existing consumers unaffected.
- Option B: Create a new phase file with its own mapping. Existing consumers unaffected, but now there's one more file to track.
- Option C: Add a section to the format spec. The file grows, but all rendering rules are still in one place.

Options A and C scale equally well. Option B adds tracking burden.

## Recommendation

**Option C: Single canonical format with consumer-specific sections.**

The core argument: the maintainability review identified format coupling without
ownership as a high-certainty risk. The root cause is that format knowledge is
scattered across files with no enforcement mechanism. Option C eliminates the
scatter entirely -- the format spec IS the complete contract, including how each
consumer interprets it.

The main objection to Option C is that it mixes concerns (data contract vs.
presentation). But in practice, the "consumer rendering" sections are small: each
is a field-by-field mapping table plus a few notes on structural differences (heading
levels, prose density). The research file `explore_decision-making-skill-impact_r1_lead-output-format.md`
already demonstrated this -- its "Mapping to consumers" section is 8 lines covering
three consumers. That's not unwieldy.

Option A is the second-best choice and would work well if the consumer rendering
rules grow complex enough to warrant their own file. The migration path from C to A
is straightforward: extract the consumer sections into a separate file. Starting with
C and splitting later if needed is lower-risk than starting with A and discovering
the indirection wasn't necessary.

Option B is rejected because it reproduces the exact problem the maintainability
review flagged. It's the current implicit approach, and it doesn't work.

## Decision Block

```
<!-- DECISION [format-mapping-strategy] -->
<!-- status: proposed -->
<!-- context: The decision framework has three formats (decision blocks, decision
reports, design doc Considered Options) plus the ADR format that must stay in sync.
Adding one field requires updating 7-8 files across 3 skills. The maintainability
review identified this as a high-certainty drift risk because no single file or
component owns the translation contract between formats. -->
<!-- chosen: Single canonical format with consumer-specific sections (Option C) -->
<!-- rationale: Co-locating the format definition with all consumer rendering rules
in one file reduces format changes to a single-file update. This eliminates the
drift mechanism (scattered format knowledge) at the source. The consumer rendering
sections are small (field mapping tables and structural notes), so the file stays
manageable. If consumer rules grow complex, the sections can be extracted to a
dedicated mapping file (Option A) without disrupting consumers. -->
<!-- alternatives: (a) Dedicated format-mapping reference file -- acceptable but
adds indirection between format spec and rendering rules; the 2-file update
requirement is low-risk but unnecessary when 1-file is achievable. (b) Inline in
each consumer's phase file -- rejected; this is the current implicit approach that
produces the 7-8 file change problem identified in the maintainability review. -->
<!-- assumptions: Consumer rendering rules stay small enough to co-locate (a few
field mappings per consumer, not multi-page transformation logic). If a consumer
needs complex rendering (e.g., interactive dashboard with conditional logic), this
assumption breaks and Option A becomes necessary. -->
<!-- END DECISION -->
```

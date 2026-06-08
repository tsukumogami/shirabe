# Comp Document Format Reference

Structure, lifecycle, validation rules, and quality guidance for
competitive-analysis (COMP) documents. COMP is a private-only artifact
type: it surveys the competitive landscape a feature or product sits in
and turns that survey into implications for our own choices.

## Frontmatter

Every COMP document begins with YAML frontmatter:

```yaml
---
schema: comp/v1
status: Draft
problem: |
  2-4 line summary of the competitive question this analysis answers --
  what decision or positioning the survey is meant to inform.
scope: |
  2-4 line summary of the market slice under survey -- which segment,
  which class of tools, and the boundary of what is NOT surveyed.
---
```

Required fields: `status`, `problem`, `scope`. There are no optional
frontmatter fields.

- **schema** -- `comp/v1`. Pins the artifact-type contract. It is the
  map key the validator routes on, not a checked field.
- **status** -- lifecycle state (`Draft`, `Accepted`, `Done`).
- **problem** -- the competitive question the analysis answers. A 2-4
  line YAML literal block scalar (`|`). Matches what the Implications
  section ultimately resolves.
- **scope** -- the market slice under survey. A 2-4 line YAML literal
  block scalar (`|`). Matches the boundary the Market Overview sets.

Frontmatter `status` must match the body `## Status` section exactly.
The validator's FC03 check compares the frontmatter `status` against the
entire first non-blank line under the body `## Status` heading, so that
first line must be the bare status word (`Draft`, `Accepted`, or `Done`)
alone, with any explanatory prose pushed to a later paragraph after a
blank line.

## Required Sections

A COMP document has seven required `##` sections, in this order:

1. **Status** -- the bare lifecycle word on its own first line.
2. **Market Overview** -- frames the market slice and, critically,
   names the *dimensions* along which competitors are compared (for
   example: speed, ergonomics, price, lock-in). Every later comparison
   keys off the dimensions named here.
3. **Competitors** -- one `###` subsection per competitor. Each
   subsection names at least one concrete strength and at least one
   concrete weakness, stated against the dimensions from the Market
   Overview. The Competitors section heading itself is `##`; the
   per-competitor entries are `###`.
4. **Comparative Matrix** -- a Markdown table with a header row and a
   separator row. Columns are the dimensions named in the Market
   Overview; rows are the competitors. The matrix applies the same
   dimensions consistently across every competitor.
5. **Opportunities** -- concrete gaps the survey reveals: things no
   surveyed competitor does well, stated as specific openings rather
   than aspirations.
6. **Implications** -- connects the findings to *our* choices. Each
   implication ties a specific Opportunity or competitor finding to a
   decision, trade-off, or direction we should take.
7. **References** -- external, accessible, dated sources backing the
   claims. Each entry cites a source a reader can reach and shows when
   it was checked.

## Optional Sections

Optional `##` sections may appear after the required ones:

- **Open Questions** -- unresolved competitive questions. Permitted
  only while the document is in `Draft`; must be removed or resolved
  before transitioning to `Accepted`.
- **Decisions and Trade-offs** -- records analysis-level decisions made
  during drafting (for example, why a competitor was excluded from the
  matrix, or why one dimension was weighted over another).
- **Downstream Artifacts** -- links to the PRDs, designs, or roadmap
  items this analysis fed into.

## Section Matrix

| Section               | Required | Draft | Accepted | Done |
|-----------------------|----------|-------|----------|------|
| Status                | yes      | yes   | yes      | yes  |
| Market Overview       | yes      | yes   | yes      | yes  |
| Competitors           | yes      | yes   | yes      | yes  |
| Comparative Matrix    | yes      | yes   | yes      | yes  |
| Opportunities         | yes      | yes   | yes      | yes  |
| Implications          | yes      | yes   | yes      | yes  |
| References            | yes      | yes   | yes      | yes  |
| Open Questions        | no       | yes   | no       | no   |
| Decisions and Trade-offs | no    | yes   | yes      | yes  |
| Downstream Artifacts  | no       | yes   | yes      | yes  |

## Content Boundaries

A COMP document is a competitive *survey* and its implications. It is
NOT:

- **A feature spec.** COMP names opportunities and implications; it does
  not specify what we build. That is a PRD's job.
- **A roadmap.** COMP does not sequence or schedule work. Implications
  may feed a roadmap, but COMP itself carries no ordering or dates.
- **A positioning or marketing document.** COMP describes competitors
  factually, with balanced strengths and weaknesses. It does not pitch
  our product or argue for our superiority.
- **A design.** COMP does not choose an architecture or weigh technical
  alternatives for our own implementation.

## Lifecycle

COMP documents move through three forward states, with no directory
movement at any transition and no sunset path:

- **Draft** -- under active authoring. Open Questions are permitted.
- **Accepted** -- the survey and its implications are settled and
  reviewed. Open Questions must be gone.
- **Done** -- the analysis has served its purpose (the downstream work
  it informed has been decided or shipped). The document stays in place
  for the record.

Transitions are forward-only: `Draft → Accepted`, `Accepted → Done`, and
the shortcut `Draft → Done`. There is no reverse transition and no
`Superseded` or `Sunset` state; a stale analysis is simply re-authored
as a new COMP document.

## Validation Rules

COMP documents are checked by the shared structural checks plus one
visibility gate:

- **FC01** -- required frontmatter fields present (`status`, `problem`,
  `scope`).
- **FC02** -- `status` is one of `Draft`, `Accepted`, `Done`.
- **FC03** -- frontmatter `status` matches the first non-blank line
  under the body `## Status` heading.
- **FC04** -- all seven required sections are present.
- **FC15** -- the required sections appear in the canonical order above
  (`shirabe validate` owns the order rule; this list does not restate it).
- **R9 (private-only gate)** -- because `comp/v1` is marked private,
  `shirabe validate` rejects a COMP document whenever visibility is not
  exactly `private`. The check fails closed: public visibility and unset
  visibility both produce a single R9 error. R9 fires *before* FC01-FC04
  and short-circuits them, so a COMP document validated under the wrong
  visibility reports exactly one R9 error and no structural noise.

Run validation with `shirabe validate --visibility private <file>`.

## Quality Guidance

These rules align with what the Phase 4 jury checks, so a document that
follows them clears review:

- **Market Overview names dimensions explicitly.** State the comparison
  axes up front. If the Comparative Matrix introduces a column the
  Market Overview never named, the analysis is incoherent.
- **Comparative Matrix applies dimensions consistently.** Every
  competitor is scored on the same dimensions; no blank cells without an
  explicit "n/a" and reason.
- **Competitors carry balanced findings.** Each competitor names both a
  concrete strength and a concrete weakness. A competitor described only
  by weaknesses reads as a pitch, not a survey.
- **Opportunities are concrete gaps, not aspirations.** "No competitor
  offers offline sync" is an opportunity; "we could be the best" is not.
- **Implications connect findings to choices.** Each implication points
  back to a specific finding and forward to a decision or direction.
- **References are external, accessible, and dated.** Cite sources a
  reader can reach, and record when each was checked, since competitive
  facts go stale.

## Common Pitfalls

- **Marketing language.** Describing competitors in promotional or
  dismissive terms ("clunky", "best-in-class") instead of factual,
  dimension-anchored observations. Keep the survey neutral.
- **Dimension conflation.** Mixing comparison axes -- scoring one
  competitor on price and another on speed -- so the matrix can't be
  read across rows. Fix by naming the dimensions once in the Market
  Overview and applying them uniformly.
- **Aspirational Opportunities.** Listing things we wish were true or
  generic ambitions instead of specific gaps the survey actually
  revealed. An Opportunity must trace to an observed competitor
  weakness or an unserved segment.

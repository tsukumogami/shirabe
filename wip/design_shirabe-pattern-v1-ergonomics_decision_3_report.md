# Decision 3: Format-reference clarifications and file materialization

**Dispatch context:** Walked as serial-self under sub-agent dispatch; independence-loss caveat applies.

## Question

The PRD's Cluster 3 (R11-R17) prescribes seven format-reference clarifications. Two of them (R15 on Implementation Issues ownership, R17 on `/plan` single-pr Implementation Issues canonical structure) reference `design-format.md` and `plan-format.md` — files that do NOT exist at the worktree (verified by `find`). Three options for the file-materialization question, plus per-field decisions.

## Constraints

- **Composability** — references should be at consistent altitudes.
- **R31** — direct invocation behavior unchanged.
- **R32** — pattern-level edits (R10, R13, R14, R16) land before per-skill consumers.
- **Existing file inventory** — `brief-format.md` exists; `prd-format.md` exists; `design-format.md` and `plan-format.md` do NOT exist (the references in the PRD are aspirational/proposed). The DESIGN skill's format guidance lives inline in `skills/design/SKILL.md` lines 24-95 plus `references/quality/considered-options-structure.md`. The PLAN skill's format guidance lives inline in `skills/plan/SKILL.md` plus `skills/plan/references/quality/plan-doc-structure.md`.

## Options Considered

### Option A — Materialize `design-format.md` and `plan-format.md` as new top-level reference files at `skills/design/references/design-format.md` and `skills/plan/references/plan-format.md`

The per-field PRD requirements (R15, R17) land in these new files. Existing inline format prose in `skills/design/SKILL.md` lines 24-95 and `skills/plan/SKILL.md` is migrated to the new file with a back-reference from the SKILL.md.

**Pros:** Cross-skill consistency — every format reference lives in a `<type>-format.md` file at the same altitude (`brief-format.md`, `prd-format.md`, `design-format.md`, `plan-format.md`). R32 sequencing is structural — the new files are pattern-level upstream of per-skill consumers. ACs that reference `design-format.md` and `plan-format.md` find the files.

**Cons:** Materialization is medium scope — two new files, content migrated from SKILL.md prose. The migration must preserve the existing SKILL.md citations (the SKILL.md references its own "Structure" section in two places; the migration replaces inline content with a citation).

### Option B — Inline the per-field requirements into existing SKILL.md prose; no new format reference files

R15 lands in `skills/design/SKILL.md`'s existing "Sections Added During Lifecycle" subsection at line 116. R17 lands in `skills/plan/SKILL.md`'s existing format-related prose plus `skills/plan/references/quality/plan-doc-structure.md`.

**Pros:** No new files; the migration cost is zero.

**Cons:** Cross-skill consistency fails — `brief-format.md` and `prd-format.md` exist as reference files; `design-format.md` and `plan-format.md` are inline-only. AC3.5 explicitly names `references/design-format.md` and AC3.7 names `references/plan-format.md`; an AC grep against the named paths fails.

### Option C — Materialize only `design-format.md`; inline `plan-format.md` requirements into `plan-doc-structure.md`

Asymmetric — materialize the design file because R15 has more content (Implementation Issues table ownership convention), inline the plan rules into the existing `plan-doc-structure.md` reference (which already covers the plan doc shape).

**Pros:** Less file churn than Option A.

**Cons:** AC3.7 names `references/plan-format.md` specifically; the AC grep against the named path fails. Asymmetric file inventory is the failure shape the BRIEF named ("audit trail divergence"). The migration cost-saving is small; the cross-skill consistency cost is large.

## Chosen: Option A — Materialize both files at the canonical altitude

**Rationale.** ACs reference both files by name. Cross-skill consistency requires all four format references at the same altitude. The migration cost (medium) is one-time and discharges the format-reference-altitude debt named in `tsukumogami/shirabe#157` and `#158`.

**Per-field decisions (within Option A).**

- **R11 (public issue numbers in public-repo artifacts grammar).** Resolve the ambiguity in `brief-format.md:310-311` and the parallel rule in `prd-format.md` by inserting "private" before "issue numbers" so the qualifier distributes explicitly: `No private/ paths, private repos, private filenames, private internal codenames, or private issue numbers (public-visibility cleanliness)`. Public issue numbers in public-repo artifacts ARE allowed — the PRD itself references `tsukumogami/vision#514`, `#535`, `tsukumogami/shirabe#157`, `#158` and is Accepted. Add a one-line rationale after the rule: `Public issue numbers in public repos are durable cross-references and remain allowed.`

- **R12 (motivating_context vs prose workaround).** Document the `motivating_context:` optional frontmatter field in both `brief-format.md` and `prd-format.md`. Field value is a cross-repo reference (e.g., `tsukumogami/vision#514` or `owner/repo:path/to/private-doc.md` per the cross-repo-references convention). Visibility rules: the field is allowed to point at a private artifact from a public document because the field is metadata (the link target is referenced, not described); public readers see the issue number and resolve via their own access. Adopt this rather than documenting prose-workaround because the workaround is the failure mode the BRIEF named ("the audit trail diverges from execution"); a structured field preserves the trail.

- **R13 (BRIEF Open Questions closure surface naming).** Add a sentence to `brief-format.md`'s Open Questions section description: `When promoting Draft → Accepted, Open Questions resolved by the downstream PRD's Decisions and Trade-offs section are removed from the BRIEF; the PRD's section is the canonical closure surface.`

- **R14 (PRD Decisions and Trade-offs as conventional closure section).** Add the convention statement to `prd-format.md`'s Decisions and Trade-offs section description: `Decisions and Trade-offs is the conventional section for closing the upstream BRIEF's Open Questions. Each Decision Dn ... entry MAY resolve a BRIEF Open Question by reference; the BRIEF's Open Questions section is then removed during Draft → Accepted transition.`

- **R15 (Implementation Issues table ownership).** State the convention in BOTH `design-format.md` and `skills/design/SKILL.md`'s existing "Sections Added During Lifecycle" subsection: `The Implementation Issues table is owned by /plan and added during /plan's Phase 7 single-pr execution. /design SHALL NOT prescribe an inline Implementation Issues table in its DESIGN output; the dispatch convention names /plan as the table's sole author. When /design ships before /plan runs, the DESIGN's "Implementation Issues" section is reserved-but-empty; /plan populates it.`

- **R16 (competitive-findings vs competitive-analysis-as-artifact-type distinction).** Add to `prd-format.md` Content Boundaries: `Distinguish "competitive findings" (content the PRD does NOT contain — competitor names, market sizing, head-to-head feature matrices) from "competitive-analysis-as-an-artifact-type" (a subject the PRD MAY reference — a PRD authoring the /comp skill, or naming COMP-* docs as an artifact type, is in-scope as long as the PRD itself does not contain the competitive findings).`

- **R17 (`/plan` single-pr Implementation Issues canonical structure).** Document the structure in `plan-format.md`. The canonical structure (verified against `skills/plan/SKILL.md:289-294` and the table-vs-diagram reconciliation work in PR #149/#168): `The ## Implementation Issues section emitted by /plan single-pr mode contains exactly two subsections: (a) an Issues Table with columns "ID", "Title", "Status", "Notes"; (b) a Mermaid dependency diagram rendering edges between the ID nodes. The validator's FC08 check (`tsukumogami/shirabe#157` / PR #169) reconciles the diagram's classDef declarations against the table's Status column; the validator's table-vs-diagram check reconciles edge endpoints against table IDs (PR #149).` (Verified PR numbers via git log lines 7-9.)

## Assumptions

- Verified that `find ... -name 'design-format*' -o -name 'plan-format*'` returns empty across the worktree. The references in the PRD to these files are aspirational; the DESIGN materializes them.
- Verified `brief-format.md` exists at `skills/brief/references/brief-format.md` and `prd-format.md` exists at `skills/prd/references/prd-format.md`.
- The four format references at `skills/<name>/references/<name>-format.md` is the canonical altitude per the existing two-file precedent.
- The migration of inline SKILL.md format prose to the new `design-format.md` file preserves SKILL.md citations (Section 1.1's existing "Structure" pointer in `skills/design/SKILL.md` lines 24-95 is replaced by a citation; no SKILL.md content is lost, just relocated).

## Status

complete

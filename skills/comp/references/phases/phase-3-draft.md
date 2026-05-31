# Phase 3: Draft

Draft the COMP document's seven required sections from the Phase 2
research. Write against `references/comp-format.md`.

## 3.1 Write the Document

Create `docs/competitive/COMP-<topic>.md` with frontmatter (`schema:
comp/v1`, `status: Draft`, `problem`, `scope`) and the seven required
sections in order:

1. **Status** — the bare word `Draft` on its own first line.
2. **Market Overview** — frame the slice and name the comparison
   dimensions explicitly. Every dimension the matrix uses must appear
   here.
3. **Competitors** — one `###` subsection per competitor, each naming at
   least one concrete strength and one concrete weakness against the
   named dimensions.
4. **Comparative Matrix** — a Markdown table whose columns are the named
   dimensions and whose rows are the competitors, applied consistently.
5. **Opportunities** — concrete gaps the survey reveals, each traceable
   to an observed weakness or unserved segment.
6. **Implications** — connect each finding to one of *our* choices: a
   decision, trade-off, or direction. This is where the analysis answers
   the competitive question from Phase 1.
7. **References** — external, accessible, dated sources backing the
   claims.

## 3.2 Optional Sections

Add optional sections only if they carry weight: **Open Questions**
(Draft-only; must be gone before Accepted), **Decisions and Trade-offs**
(why a competitor was excluded, why a dimension was weighted),
**Downstream Artifacts** (PRDs/designs this feeds).

## 3.3 Keep It Neutral

Hold the survey factual. No marketing language, no dismissive adjectives.
Strengths and weaknesses are stated against dimensions, not vibes. Save
the "so what" for Implications.

## 3.4 wip-hygiene

Do not reference any `wip/...` path from the COMP document — not in
frontmatter, not in prose. The `wip/` files are non-durable and are
cleaned in Phase 5.

## Output

A complete Draft COMP at `docs/competitive/COMP-<topic>.md`, ready for
the Phase 4 jury.

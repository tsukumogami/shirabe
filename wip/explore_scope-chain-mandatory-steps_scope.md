# Explore Scope: scope-chain-mandatory-steps

## Visibility

Public

## Core Question

Since #302 landed, `/scope` runs the full tactical chain on every invocation and
reduces the artifact set afterward by absorbing documents that did not earn their
keep. Several surfaces across the skill corpus still behave as though chain steps
are optional and choosable before the fact. Which surfaces are they, what does each
one actually do today, and what should replace it so the corpus states one model
consistently?

## Context

The author's read, confirmed in part by a first pass over the source:

- `/explore` still crystallizes to a step *inside* a chain (PRD, DESIGN, PLAN,
  VISION, ROADMAP) rather than routing to a chain *entry point*. Its routing
  tables and ten-type crystallize framework never mention `/scope`, `/charter`,
  or `/execute` at all, and two of its routes (`/spike`,
  `/competitive-analysis`) name skills that do not exist in this repo under
  those names. The intended post-#302 job is a four-way route: file an issue,
  `/charter`, `/scope`, or `/execute`.
- `/scope` Phase 1 is internally split. It states plainly that `planned_chain:`
  is the constant `[brief, prd, design, plan]`, that there is no entry altitude
  to choose, and that Adjust "does not change which children run, because that
  list is fixed" — and then still emits a chain-proposal output whose options
  block is `Proceed / Adjust / Bail?`, presenting a fixed list as a proposal to
  confirm. The same file carries a paragraph telling authors who want a shorter
  chain to invoke `/design` or `/plan` directly, which a later section of that
  same file says describes an escape hatch from a constraint that no longer
  exists.
- `/charter` carries a different shape again: `/vision` skips on a thesis-shift
  gate, `/comp` skips on repo visibility, and a separate confirmation prompt in
  Phase 2 lets the author drop `/roadmap`. Whether that is a legitimate
  difference between the strategic and tactical chains or the same
  before-the-fact judgment #280 removed is unresolved.

Author decisions taken at scoping time:

- `/explore` should end as a router only: it hands off to one of file-an-issue,
  `/charter`, `/scope`, or `/execute`, and does not author chain artifacts itself.
- `/charter`'s conditional gates are an open question for research, not a settled
  position either way.

## In Scope

- The four parent-chain surfaces: `/explore`, `/scope`, `/charter`, `/execute`.
- The shared parent-skill pattern references that define gate vocabulary and
  chain-shape contracts.
- Post-#302 residue: prose, state schema fields, and evals that still assume the
  retired type-level absorbability test or a choosable entry altitude.
- What `/explore`'s handoff surface must produce for each of the four routes.

## Out of Scope

- Redesigning the consolidation judgment itself. #302 settled how absorbability
  is decided; this exploration is about surfaces that have not caught up to it.
- Rewriting the child skills' own internal workflows (`/brief`, `/prd`,
  `/design`, `/plan` phase structure).
- Document format changes in `crates/shirabe-validate/src/formats.rs`.

## Research Leads

1. **Where does `/explore` still route to chain-internal steps, and what would a
   four-way entry-point router have to replace?**
   `/explore` is the entry point for "I don't know what I need," so its routing
   surface is the one most visible to authors. Need a complete inventory of every
   place it names an artifact type or a child skill as a destination — the two
   routing tables, the complexity table, the detection algorithm, the ten-type
   crystallize framework, every `phase-5-produce-*.md`, and the evals — plus which
   of those destinations still resolve to a real skill.

2. **Which `/scope` surfaces still present a fixed chain as a choice, and what
   does each one actually do?**
   The chain-proposal output, the Adjust branch, the `chain_skipped:` field, the
   re-entry protection gates, and the stale direct-invocation paragraph. For each:
   what it emits, what it changes, whether anything downstream consumes it, and
   whether an eval pins it.

3. **Is `/charter`'s chain genuinely conditional, or is it the pre-#302 shape?**
   `/vision`'s thesis-shift gate, `/comp`'s visibility gate, and the `/roadmap`
   drop prompt each need classifying as re-entry protection, a
   content-availability constraint, or a worth-producing judgment made before the
   artifact exists. Also: does `/charter` have a consolidation judgment at all, or
   did #302 only reach the tactical chain?

4. **What did #302 actually change, and what in the corpus still assumes the
   world before it?**
   The commit, the documents behind it, and a sweep for surviving references to
   the type-level absorbability test, the PRD+DESIGN floor, the
   "reachable floor" language, and the "invoke a child directly for a shorter
   chain" workaround.

5. **What does the shared parent-skill pattern say a gate may be, and who
   conforms?**
   `references/parent-skill-pattern.md` defines the gate vocabulary (ALWAYS,
   shape-dependent, Mandatory-with-auto-skip) and the state schema defines the
   `planned_chain:`/`chain_ran:`/`chain_skipped:` triad. Whether the vocabulary
   still admits a worth-producing gate, and whether `/scope`, `/charter`, and
   `/execute` each conform to it, determines if this is three local fixes or one
   pattern-level fix.

6. **What do the evals and koto templates pin down today?**
   Any change here has to move tests. Need to know which current behaviors are
   graded — `/scope` eval 17 on the entry-altitude shortcut, `/explore`'s
   crystallize evals, `/charter`'s chain-proposal literals, `/execute`'s cascade
   fixtures — and which would need rewriting versus deleting.

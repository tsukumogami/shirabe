# Content Quality Verdict — BRIEF-upstream-link-legality

**Verdict:** PASS

## Findings

- **Problem Statement states a problem, not a solution.** PASS. The section
  names a gap ("Nothing in the system says what makes a link legal, and nothing
  checks") and then decomposes it into two failures that differ in property,
  actor, and fix. No mechanism is proposed: the validator, the skill contracts,
  and the declaration site all stay out of this section. The closest approach to
  a solution is the closing paragraph on the private-upstream precedent, but it
  is framed as a property of the problem ("Whether those are one rule or two is
  the question this work has to answer rather than assume") rather than an
  answer.

- **Problem Statement stands alone.** PASS. A cold reader gets the chain order,
  the two lifecycle classes, and why the second failure is worse without opening
  another file. The evidence is concrete and checkable: the "eight such edges"
  claim verifies exactly against the corpus — `BRIEF-cascade-outline-ac-completeness`
  and `BRIEF-single-pr-plan-validation` name PLANs; `BRIEF-lifecycle-passing-state-validation`,
  `BRIEF-fc06-index-alias`, `BRIEF-legend-vs-classdef-reconciliation`, and
  `BRIEF-table-diagram-reconciliation` name DESIGNs; `BRIEF-lifecycle-draft-ready-discipline`
  and `BRIEF-skill-cascade-lifecycle-check` name other briefs. Eight.

- **User Outcome is outcome-shaped and names its users.** PASS. Four paragraphs,
  four named users: an author who writes a bad link by hand, an author running a
  chain, a reader walking the trail, a maintainer adding a type. Each says what
  is different for that person, not what got built — "finds out immediately...
  not months later, from a reader who followed the link and found nothing" is an
  outcome; "never has to know the rule" is an outcome. No feature enumeration.

- **User Outcome matches the `outcome:` frontmatter.** PASS. The frontmatter's
  three clauses (fails at write time; skills stop producing illegal links;
  readers land on documents that exist and sit above) each map to a prose
  paragraph. The maintainer paragraph has no frontmatter counterpart, which is
  the expected direction of difference for a 2-4 line summary — no contradiction
  between the two.

- **User Journeys: heading, user, trigger, outcome.** PASS, all four. Inverted
  link (maintainer / sets `upstream:` to the design they had open / corrects
  before the commit exists). Chain under a roadmap (author / invokes the tactical
  chain with a roadmap path / nothing breaks when the cascade deletes the
  roadmap). Audit (engineer / opens a shipped design and walks up / every hop
  resolves). New type (maintainer / introduces a document type / validator
  enforces from the declaration). Journey one closes with "Today this document
  validates clean and ships," which is the contrast that makes the outcome legible.

- **Journeys are distinct.** PASS. Four different entry points: hand-authoring,
  skill-driven chain execution, downstream reading, and extending the type
  system. Two name a maintainer, but they enter from opposite ends — one writes a
  document, one changes what documents are possible. None is another's path
  retold.

- **Scope Boundary has explicit IN and OUT with real exclusions.** PASS. Five IN
  items, five OUT. Every OUT is a boundary a downstream author could cross by
  accident, and each carries its reason: repairing the five existing dangling
  references (the natural next reach once you're enforcing the rule), the
  cardinality question, removing multi-valued `upstream:`, indexing the strategic
  directories, and touching the cascade. The last one is the strongest — it
  explains why no cascade change is needed rather than just forbidding it. No
  filler.

- **Open Questions defer framing details rather than naming blockers.** PASS.
  Both defer mechanism, not existence. The first (nearest durable ancestor versus
  record nothing) states what each choice costs a reader and names the PRD's
  Decisions and Trade-offs section as the closure surface, which is the canonical
  one. The second (whether "absorb the context" is checkable) splits ownership
  correctly — the PRD owns the requirement, a design below it owns checkability.
  Neither is "should this feature exist."

- **No altitude drift.** PASS. No acceptance criteria, user stories, interface
  shapes, data flow, task decomposition, or feature ordering. The IN list names
  `shirabe validate` as the enforcement surface, which is scope rather than
  design — it says where the boundary falls, not how the check is built. The
  fourth journey ("declare, alongside its required sections and valid statuses")
  leans nearest to design, but it describes what the maintainer experiences
  rather than the declaration's shape, and the sentence that follows keeps it on
  the user's side: "They do not edit a check." It stays inside brief altitude.

## Required changes

None.

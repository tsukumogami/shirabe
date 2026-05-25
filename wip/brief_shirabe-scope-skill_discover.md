# /brief Discovery: shirabe-scope-skill

## Problem Candidate

shirabe ships `/brief`, `/prd`, `/design`, and `/plan` at the tactical
chain's altitude — each as a loadable child skill that authors invoke
directly. What's missing is the parent layer: a skill that walks an
author through the tactical conversation as a *sequence*, deciding
which children to invoke against the upstream artifacts already on
disk, carrying scope between them across BRIEF, PRD, DESIGN, and PLAN
boundaries, and enforcing the same three-exit contract that `/charter`
made first-class for the strategic chain. In the absence of `/scope`,
authors today reach for the tactical chain as four separate
invocations: they re-derive the sequencing decisions on every run
(when does a BRIEF dog-foot in? when is a DESIGN warranted given the
PRD's complexity? when does the PLAN's `single-pr` vs `multi-pr`
choice fire?), they carry context manually with no resume contract if
the session breaks across child boundaries, and they have no
enforcement that the chain produces a durable terminal artifact rather
than evidence files in `wip/`. The deeper problem is that the
parent-skill pattern v1, which `/charter` validated on the strategic
chain, has invariants — three-exit contract, child-doc inspection
discipline, resume ladder across child boundaries — that cannot be
proven against the tactical chain's asymmetries (no Phase-5 Reject
finalization on `/prd` and `/design` today; `/prd`'s gate shape
doesn't fit EITHER-signal / ALWAYS / shape-dependent cleanly; PLAN's
lifecycle has no Accepted state) without a second parent that exposes
those asymmetries and forces a decision on each. Authors can sequence
the tactical chain by hand; the pattern can't be ratified for the
parent skills that follow until `/scope` ships and stands the contract
against tactical reality.

## Outcome Candidate

A skill author opens Claude Code with a feature named on the roadmap
or surfaced in conversation, and invokes `/scope`. The skill orients:
it detects which durable artifacts already exist for the topic (a
BRIEF? a PRD-Accepted? a DESIGN at `docs/designs/current/`? a PLAN at
any of Draft/Active/Done?), proposes a chain to run from the
most-downstream upstream that's settled, and walks the chain — each
child invoked under its own gate, each child's existing resume logic
deferred to when revise-or-fresh decisions land. The author never has
to remember whether `/brief` should fire when a BRIEF is already
Accepted, or whether `/design` is warranted given the PRD's
complexity, or which of PLAN's two output modes the chain selected.
The conversation ends at one of three durable exits that mirror
`/charter`'s contract across both boundaries the tactical chain
exposes: full-run (PLAN-Active in `multi-pr` mode or PLAN-Draft in
`single-pr` mode), re-evaluation Decision Record (now at TWO
boundaries — PRD-boundary and DESIGN-boundary — instead of
`/charter`'s one), or abandonment-forced materialization of the
most-recently-running child. Resume across child boundaries detects
partial runs at any of four positions (BRIEF, PRD, DESIGN, PLAN) and
picks up where the session broke. Manual fallback remains first-class:
a `/prd` or `/design` run done directly outside `/scope` leaves the
same durable artifact the in-chain run would have, and `/scope`'s
resume ladder reads it the same way either way. Downstream, `/scope`
shipping validates the parent-skill pattern for the tactical chain the
same way `/charter` validated it for the strategic chain: the
pattern's contract surface holds across two parents with different
chain shapes, the asymmetries (extra re-evaluation boundary, no
Phase-5 Reject by default, multi-output-mode terminal child) all
landed inside the pattern's existing extension points, and the
parent-skill v1 contract is ratified for the `/work-on` migration
that follows.

## Grounding Anchor

Conversation only. The wip/explore_scope-tactical-progression_*.md
files anchor the framing but are ephemeral by the wip-hygiene rule
and cannot be cited as durable upstream. SE7's roadmap entry exists
upstream (shirabe-side roadmap; not loaded into this BRIEF as
`upstream:` because the public BRIEF's frontmatter would point at the
roadmap path only if the roadmap is the load-bearing entry, which the
exploration's User Focus did not establish). The BRIEF will name the
upstream sources informally in prose where they support the framing
(SE4 precedent, the four pattern references, the four child SKILL.md
files).

## Journey Sketch

- **Skill author, cold standalone invocation.** Author invokes
  `/scope <topic-slug>` with no upstream artifacts in place. The skill
  walks the full chain — BRIEF → PRD → DESIGN → PLAN — exercising the
  inheritance promise from `/charter`: pattern references transfer
  verbatim, body slots fill with the tactical chain's per-child
  prompts.
- **Author with a PRD already Accepted.** Author invokes `/scope`
  against a topic whose PRD has already landed (typical when the
  feature was framed via `/prd` directly). The skill detects the
  Accepted PRD, proposes a chain starting at `/design`, and walks
  forward. This exercises the BRIEF-as-chain-member decision (the
  chain proposes `/brief` but the gate's auto-skip-when-Accepted-PRD
  fires) and the mandatory-with-auto-skip gate type added to the
  pattern.
- **Author returns to a settled chain for re-evaluation.** Author
  invokes `/scope` against a topic whose DESIGN has been Accepted for
  weeks; new evidence prompts the question of whether the architecture
  still holds. The chain re-evaluates at the DESIGN boundary, lands a
  `DECISION-design-<topic>-re-evaluation.md` recording the conclusion,
  and halts without re-authoring the DESIGN. This exercises the second
  re-evaluation boundary that doesn't exist in `/charter`.
- **Author bails mid-chain; resume picks up the partial state.**
  Author starts a `/scope` run, gets through `/brief` and into
  `/prd`'s discover phase, closes the session. A week later, the
  resume ladder detects the partial `/prd` state in `wip/`, picks up
  at `/prd`'s own resume row, and the chain continues. This exercises
  the resume ladder's expanded slot 6 (4 partial-child-run rows) and
  the abandonment-forced binding (if the author tells the chain to
  wrap up rather than continue).
- **Reviewer redirects via manual fallback.** A reviewer reads a
  Draft PRD produced by an earlier `/scope` run and decides to tighten
  the requirements directly via `/prd` outside `/scope`. The chain
  doesn't interfere; on re-entry the resume ladder reads the same
  surface and continues. This exercises the manual-fallback
  non-interference rule (R13 widened) and the inheritance promise's
  steady-state-not-workaround framing.

## Open Questions for Drafting

- **BRIEF's `upstream:` field treatment.** The exploration handoff
  files live in `wip/` (non-durable). SE7's roadmap entry is the
  natural upstream but the User Focus did not specify whether to point
  the BRIEF's `upstream:` at it. Decision for Phase 2: omit
  `upstream:` and name the upstream sources informally in the
  Problem Statement prose (mirrors how
  BRIEF-shirabe-charter-skill.md handles its multi-source grounding).
- **Whether to enumerate the cascading decisions in the BRIEF body
  or defer them to the downstream PRD.** Exploration settled on six
  cascading decisions (new gate type, Phase-N Reject contracts in
  `/prd` and `/design`, top-level worktree-discipline reference,
  BRIEF-as-chain-member, design doc rename, L9 reclassification). The
  BRIEF altitude frames the orientation choice; the PRD enumerates the
  decisions as requirements. Decision for Phase 2: name the
  orientation choice in Problem Statement + User Outcome, sketch the
  cascading consequences in Scope Boundary (in-scope items), defer the
  enumerated requirements to the downstream PRD via Open Questions.
- **Whether to include Mermaid diagrams (L4 from the SE4
  retrospective).** SE4's BRIEF includes two Mermaid diagrams (chain
  flow + exit shapes). Author L4 marks "BRIEF Mermaid diagrams from
  the start" as a cheap fold. Decision for Phase 3: include parallel
  diagrams adapted for the tactical chain.
- **Whether the brief should name the `/work-on` migration as a
  downstream consumer.** SE7 ratifies the pattern for SE8 (`/work-on`
  migration). The BRIEF can name this in Scope Boundary (out-of-scope:
  the `/work-on` migration itself) to set up the chain's downstream
  consumers. Decision for Phase 3: name it explicitly in Scope OUT.

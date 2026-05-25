# Exploration Findings: scope-tactical-progression

## Decision: Crystallize

## Core Question

How does shirabe ship SE7 (`/scope` tactical-chain parent skill) by inheriting
SE4's parent-skill pattern where it transfers cleanly, and extending the pattern
where the tactical chain legitimately needs something different?

## Round 1

### Key Insights

1. **All 4 SE4 pattern references transfer verbatim to `/scope`.** (Lead 1)
   The inheritance promise holds. Pattern doc, state schema, resume ladder
   template, and child inspection are parent-shape-agnostic by design.
   `/scope` authors body-fill in its own SKILL.md + four phase reference
   files; touches zero pattern references. If SE7 finds itself wanting to
   edit a pattern reference, that signals something was misclassified as
   pattern-level when it was `/charter`-specific.

2. **The tactical chain is structurally 5-position, not 4.** (Lead 2)
   `/charter` has 4 positions (`/vision`, optional `/comp` feeder,
   `/strategy`, optional `/roadmap`). `/scope` has 5: `/brief`, `/prd`,
   `/design`, `/plan`, plus a (currently empty) feeder slot. `/plan` is
   positionally distinct from `/design` — they sit at different altitudes
   (HOW vs ATOMIC-WORK-DECOMPOSITION). No `/charter` analog exists for the
   `/plan` terminal position.

3. **No hard prerequisite blocks SE7.** (Lead 5)
   `DESIGN-shirabe-explore-split.md` is a roadmap placeholder; vision#495
   tracks it. SE4 deliberately rejected the discover/converge engine
   extraction (Decision 1 in `DESIGN-shirabe-progression-authoring.md`):
   `/charter` consumes `/explore`'s engine by cross-skill pointing into
   `skills/explore/references/phases/{phase-2-discover,phase-3-converge}.md`.
   `/scope` can do the same. The "explore-split" design's actual scope is
   narrower than its name suggests (`/scope`'s entry + Phase 4 menu, not
   an engine refactor). SE7 ships without waiting on anything.

4. **Re-evaluation multiplies; rejection weakens.** (Lead 3)
   `/charter`'s three-exit contract transfers, but the re-evaluation
   sub-shape multiplies by boundary count (2 boundaries — PRD-boundary
   and DESIGN-boundary — instead of `/charter`'s 1), while the rejection
   sub-shape weakens or disappears because tactical children (`/prd`,
   `/design`, `/plan`) lack Phase-N Reject finalization verdicts. The
   asymmetry between strategic and tactical concentrates here, in two
   opposing directions: more re-evaluation Decision Records, fewer (or
   zero) rejection Decision Records.

5. **Resume ladder ~2× larger; universal template still holds.** (Lead 4)
   `/charter`'s 10 rows → `/scope`'s 15-20 rows. Drivers: 4 doc-emitting
   children (vs 3), 2-3 lifecycle states each, AND `/scope` is the first
   parent to fill the feeder-doc-detected template slot (slot 7, which
   `/charter` left empty). The universal 9-row meta-ladder template at
   `references/parent-skill-resume-ladder-template.md` holds without
   modification — slots are expansion points by design.

6. **Six of 20 retrospective items fold cheaply into v1.** (Lead 6)
   Observations #3 (file-existence checks), #9 (reviewer-PASS-without-
   artifact), #11 (worktree staleness) + learnings L4 (BRIEF Mermaid
   diagrams), L9 (PRD requirement tagging), L11 (PLAN placeholder
   discipline). Authoring overhead: ~3-4 hours total. Adds ~2
   requirements to SE7's PRD (net ~21-23, same magnitude as `/charter`).
   The other 14 items defer correctly: 6 Track B items need amplifier
   substrate; 4 are out of `/scope`'s surface area; 4 already inherit
   verbatim from SE4 folds. L9 (PRD pattern-level requirement tagging)
   is essentially mandatory — the tagging convention is the only
   mechanical way to verify pattern-doc edits cover all pattern-level
   requirements.

7. **Demand validated via four-source triangulation.** (Lead 7)
   Maintainer-filed milestone (vision#495), roadmap SE7 entry,
   `/charter`'s shipped PRD names `/scope` as next inheritor, shared
   DESIGN names SE7 as co-target, shirabe#22 closed-bug captures
   manual-chaining workaround pain. Single gap: no defined runtime
   success metric beyond pattern-conformance.

### Tensions

**T1. Pattern transfers verbatim (Lead 1) BUT a new gate type is being
proposed (Lead 2 Open Q1).** The proposal to model `/prd`'s gate as
"Mandatory-with-auto-skip" introduces a fourth pattern-level gate type
(joining EITHER-signal, ALWAYS, shape-dependent). Either the pattern
doc grows a fourth gate vocabulary entry (touches `references/parent-
skill-pattern.md`, breaking Insight 1's "verbatim" promise), OR `/prd`'s
gate unifies with EITHER-signal where signal 2 is "requirements-shift
detected during Phase 1" (keeps pattern vocabulary at 3). The unify
direction preserves Insight 1; the new-gate direction grows the pattern
contract surface.

**T2. /charter's R8/R9 promised "verbatim inheritance" (Lead 1) BUT the
rejection sub-shape doesn't have a tactical analog (Lead 3 Q1).** Two
paths: (A) drop the rejection sub-shape in `/scope` — smaller surface,
breaks `/charter` symmetry but stays inside pattern; (B) build Phase-N
Reject finalization into `/prd` and `/design` as `/scope` prerequisite
— preserves contract symmetry at substantial upstream contract work
(~weeks for two child skills).

**T3. "Brief-just-landed" mode treats BRIEF as Phase 0 input (Lead 2)
BUT lifecycle classification is unresolved (Lead 3 Q2).** Is BRIEF a
chain member or a feeder? If chain member, "brief-only" needs naming
as a full-run sub-shape (`chain_ran: [/brief]`) or possibly a new
distinct exit shape. If feeder, BRIEF presence is Phase 1 discovery
detail and "brief-only" reduces to clean-cancel-with-feeder-landed.
The pattern's Conditional Feeder Invocation Shape allows either
framing; the choice has downstream effect on phase-finalization prose.

**T4. Lead 6 recommends `/scope`-only worktree runbook BUT pattern
promotion would be cleaner.** Placing `parent-skill-worktree-discipline.md`
at the top-level reference root would let `/charter` cite it too (back-
edit). Placing at `skills/scope/references/` ships faster but creates
known re-home work in SE12. Tension: short-term velocity vs pattern
arc.

### Gaps

- **No runtime success metric defined for `/scope`.** (Lead 7) Pattern-
  conformance is verifiable (does `/scope` cite the right references,
  produce the right exit artifacts?). Behavioral success (do authors
  use `/scope` for tactical features rather than manual chaining? does
  the chain reach PLAN-Active faster than manual sequencing?) is not
  defined.
- **No specification of `/scope`'s validator pass-through scope.** (Lead 3
  Q5) Does `/scope` validate ONLY terminal PLAN, or each intermediate
  (PRD before invoking `/design`, DESIGN before invoking `/plan`, PLAN
  before declaring full-run)? `/charter`'s AC24 validates the terminal
  STRATEGY only.
- **No specification of `/scope`'s behavior against Active/Done PLAN.**
  (Lead 3 Q4) Re-invoking `/scope` against a topic with PLAN-Active or
  PLAN-Done is unusual. Does `/scope` engage with the Re-evaluate /
  Revise / Bail triad, or refuse and direct the user to `/work-on` (for
  Active) or `/release` (for Done)?
- **No `--max-rounds=N` default rationale for `/scope`.** (Lead 1 Open
  Q4) Tactical chains may have different re-evaluation profiles than
  strategic ones (requirements churn more than thesis).

### Open Questions

1. **Pattern orientation: extend or stay narrow?** (Cuts across T1, T2, T4)
   - Extend pattern: new "mandatory-with-auto-skip" gate type added to
     pattern doc; Phase-N Reject contracts added to `/prd` + `/design`;
     `parent-skill-worktree-discipline.md` lands at top-level. Preserves
     full symmetry with `/charter`. Substantial extra work (~weeks).
   - Stay narrow: unify `/prd` gate as EITHER-signal; drop rejection
     sub-shape in `/scope`; worktree runbook lives in `skills/scope/`
     only. Pattern v1 untouched. `/scope` ships in same magnitude as
     `/charter`. SE12 promotes patterns later if evidence accumulates.

2. **Is BRIEF a chain member or a feeder?** Affects whether
   "brief-only" needs a new exit shape, and how `/scope`'s row-5g/h
   prompts interact with the BRIEF-Accepted state.

3. **Should `DESIGN-shirabe-explore-split.md` be renamed to
   `DESIGN-shirabe-scope-skill.md`?** The "explore-split" framing
   captures the cross-skill routing question; the "scope-skill" framing
   parallels existing `DESIGN-shirabe-{strategy,brief}-skill.md`. The
   shipped reality (no engine extracted; just `/scope`'s body + cross-
   skill pointing) suggests the rename is more accurate. May require
   roadmap text update.

4. **Should the L9 PRD tagging convention be re-classified from
   "untapped learning" to "established convention `/scope` MUST
   follow"?** Lead 6 finds it's stronger discipline than the retro
   framed: it's the only mechanical way to verify pattern-doc edits
   cover all pattern-level requirements.

5. **Does observation #11's worktree runbook need an explicit trigger
   condition?** Pure documentation rots fast. A trigger like "before
   each Phase 2 child invocation, run `git fetch && git status`; halt
   if upstream has new commits" makes the fold load-bearing and
   reviewer-checkable.

### Decisions

(Captured in `wip/explore_scope-tactical-progression_decisions.md`)

### User Focus

User chose **extend the pattern to preserve full symmetry with /charter**.
This decision cascades:

- Pattern doc gains a fourth gate type (Mandatory-with-auto-skip)
- Rejection sub-shape preserved in /scope; Phase-N Reject contracts added to
  /prd and /design as SE7 prerequisites (substantial upstream work)
- New top-level reference `parent-skill-worktree-discipline.md` lands
- BRIEF treated as chain member (not feeder) so symmetry holds across
  all four children
- Design doc renamed `DESIGN-shirabe-scope-skill.md`; roadmap text updated
  to reflect cross-skill pointing reality (not extraction)
- L9 reclassified as required convention, not optional fold

Timeline implication: ~3-4 weeks for SE7 (vs the ~1-2 weeks of /charter)
because the /prd and /design Phase-N Reject contract extensions are
substantial. The full decision rationale lives in
`wip/explore_scope-tactical-progression_decisions.md`.

## Accumulated Understanding

`/scope` is shippable in approximately the same magnitude as `/charter`:
1-2 weeks of focused authoring producing motivating BRIEF/PRD/DESIGN/PLAN
docs plus SKILL.md plus four phase reference files plus an eval suite.
The four pattern references transfer verbatim — the inheritance promise
holds — and 6 of the 20 SE4-retrospective items fold cheaply into v1
with ~3-4 hour overhead.

Two asymmetries between strategic and tactical chains require explicit
choices:
1. The re-evaluation sub-shape multiplies by boundary count (1 → 2),
   while the rejection sub-shape weakens or disappears because tactical
   children lack Phase-N Reject finalization verdicts.
2. `/prd`'s gate doesn't fit cleanly into `/charter`'s three gate
   vocabularies (EITHER-signal / ALWAYS / shape-dependent); either
   pattern grows a fourth gate type, or `/prd` unifies into EITHER-
   signal.

These two choices, plus the worktree-runbook placement choice, all sit
on the same axis: **extend the pattern contract surface to preserve
full symmetry with `/charter`, OR stay narrow and let SE12 promote
patterns after additional evidence**. The "stay narrow" direction is
recommended on velocity and evidence-driven-promotion grounds; the
"extend" direction is recommended on contract-symmetry grounds.

No hard prerequisites block SE7. The chain length grows from 3 to 4
children (terminal PLAN is positionally distinct from DESIGN). The
resume ladder grows from 10 to 15-20 rows. The Phase 4 crystallize
menu narrows to tactical artifacts (BRIEF / PRD / DESIGN / PLAN). The
discover/converge engine consumed by cross-skill pointing (no engine
file extracted; SE4's choice). Demand is validated via four-source
artifact triangulation.

The primary outstanding decision is the orientation question (extend
vs stay narrow); secondary decisions (BRIEF-as-member-vs-feeder,
design-doc rename, L9 re-classification, worktree-runbook trigger)
fall out once the orientation is set.

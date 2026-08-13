# Crystallize Decision: charter-scope-parity

## Chosen Type

Full tactical chain via `/scope` — BRIEF -> PRD -> DESIGN -> PLAN.

The framework's scoring recommended a PRD. The author chose to run `/scope` instead,
which produces that PRD as its second artifact and carries the work through design and
decomposition in one conversation. The scoring below stands; `/scope` subsumes its
recommendation rather than overriding it.

## Rationale

The exploration answered its original question in the negative — essentially nothing of
the `/scope` overhaul remains to port to `/charter` — and in doing so surfaced a
different, coherent problem underneath it: **the document formats describe 1:N lineage
that neither the parent skills nor the CLI can express or validate.**

Three symptoms, one cause. `/charter` cannot author a second bet under a live VISION
because every path it resolves is keyed on one topic slug, so the intended shape is
unreachable through the parent and the author reaches for `/strategy` directly instead.
The CLI's passing-state model puts posture on the chain rather than the edge, so a
document with N downstream roots inherits N postures on one mutable `status:` field —
disjoint obligations for BRIEF and PRD, and it bites today because `PRD -> DESIGN`
fan-out is real in three places. And `/scope`'s absorb has no consumer guard, staying
safe only because the one absorbable hop happens to be the one uniformly-1:1 hop.

Requirements are genuinely contested: support fan-out, constrain it, or merely validate
it are three different products with different costs. That is a what-to-build question,
which is why PRD scored highest and why the chain starts above design.

## Signal Evidence

### Signals Present (PRD)

- **Single coherent feature emerged from exploration**: the 1:N expressibility gap
  unifies charter's unreachable reuse case, the posture-per-chain breakage, and the
  absent consumer guard.
- **Requirements are unclear or contested**: nothing in the corpus says whether
  `PRD -> DESIGN` fan-out is intended, tolerated, or forbidden, and no document decides
  whether the strategic chain should be expressible through `/charter` at all.
- **The core question is "what should we build and why?"**: the exploration eliminated
  the how-question it started with (nothing to port) and replaced it with a what-question.
- **Acceptance criteria are missing**: no artifact anywhere states what correct 1:N
  handling would look like.

### Anti-Signals Checked

- *Requirements were provided as input*: not present. The exploration produced them;
  the author began with a symmetry instinct and no prior view.
- *Multiple independent features that don't share scope*: considered and rejected. The
  three symptoms are instances of one cause, not separate features.

## Alternatives Considered

- **Design Doc**: demoted on the anti-signal "what to build is still unclear." The
  exploration found several distinct problems and did not settle which one is being
  solved. Reachable later in the same `/scope` run.
- **Decision Record**: demoted on "multiple interrelated decisions need a design doc."
  The strategic-chain expressibility question and the CLI posture question are not one
  decision. It would have covered the former and left the latter unrecorded.
- **Rejection Record**: scored well on re-proposal risk and on the adversarial lead's
  demand-validated-as-absent verdict for the consolidation half, but takes the hard
  anti-signal "rejection reasoning is already documented publicly" — Decision 9 in
  `DESIGN-scope-consolidation-over-skipping.md` records it. Worth noting that Decision 9's
  reasoning is section-mapping and therefore schema-conditional, while the cardinality
  reason found here is structural; that refinement belongs in the downstream artifacts
  rather than in a duplicate rejection record.
- **No Artifact**: demoted hard on "any architectural or structural decisions were made
  during exploration." Several were.
- **VISION / Roadmap / Plan / Spike / Competitive Analysis**: each demoted on a direct
  anti-signal — project already exists; technical approach still debated; open
  architectural decisions remain; feasibility was never the question; repo is public.

## Carried Forward

The tactical posture defect is a live bug found incidentally, with a demonstrated
symptom (renaming a plan file flipped a shared BRIEF from 0 findings to 2). It warrants
an issue regardless of what the chain below produces, and should not be left to depend
on this work landing.

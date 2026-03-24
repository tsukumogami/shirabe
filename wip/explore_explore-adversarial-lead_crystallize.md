# Crystallize Decision: explore-adversarial-lead

## Chosen Type

Design Doc

## Rationale

The "what to build" is settled: an adversarial demand-validation lead that fires for
directional topics in Phase 1 and runs in Phase 2 alongside other research agents.
The research answered all four open questions from issue 9 at the level of "which
approach wins and why," but the detailed decisions still need to be recorded. The
integration approach (Phase 1 lead-production step, writing into scope file, zero
Phase 2 changes), the "don't pursue" crystallize extension, the detection signal
design, the adversarial lead's prompt framing, and the eval rubric for honest vs
reflexive assessment are all architectural decisions that will be lost when wip/ is
cleaned. A design doc is the right place to record them.

PRD ranked lower because requirements came in as input (issue 9 has explicit ACs
and defines exactly what "accepted" means), not from exploration. Plan ranked lower
because open design decisions (confidence vocabulary, eval rubric, "don't pursue"
artifact format) must be resolved before implementation can be sequenced.

## Signal Evidence

### Signals Present

- **What to build is clear, how to build it is not**: Issue 9 defines the feature;
  research settled which approach wins (conditional, Phase 1 integration) but didn't
  produce the implementation spec.
- **Technical decisions between approaches**: conditional vs always-on (resolved:
  conditional); Phase 1 vs Phase 2 integration point (resolved: Phase 1); Decision
  Record vs new crystallize type for "don't pursue" (open); mode selection pattern
  (open); confidence vocabulary thresholds (open).
- **Architecture and integration questions remain**: how Phase 1's classification
  step modifies phase-1-scope.md, how the crystallize framework extends to add
  "don't pursue," whether the gstack Step 0 frame transfers as-is or needs adaptation.
- **Multiple viable implementation paths surfaced**: three integration options
  evaluated (all collapsed to Phase 1 scope-file approach, but the design doc must
  record why); two "don't pursue" output paths (lightweight produce vs route to
  /decision).
- **Architectural decisions made that must survive wip/ cleanup**: conditional wins
  over always-on; Phase 1 is the integration point; "demand not validated" ≠ "demand
  validated as absent"; reporter not advocate posture; gstack Step 0 frame as premise
  challenge structure.
- **Core question is "how should we build this?"**: all four issue 9 design questions
  are about implementation design, not about what to build.

### Anti-Signals Checked

- **What to build still unclear**: not present — issue 9 defines the feature clearly
  with explicit ACs.
- **No meaningful technical trade-offs**: not present — multiple live design decisions
  remain (eval rubric, "don't pursue" format, confidence thresholds).
- **Problem is operational, not architectural**: not present — this changes phase-1-scope.md,
  the crystallize framework, and Phase 5 produce paths.

## Alternatives Considered

- **PRD**: ranked lower because requirements were given as input (issue 9 has five
  explicit ACs). The distinguishing question — did exploration identify requirements,
  or were they given? — clearly answers Design Doc.
- **Plan**: ranked lower because open architectural decisions (eval rubric, "don't
  pursue" format) must be resolved before implementation can be sequenced. A plan
  would sequence work whose approach isn't yet decided.
- **No artifact**: ranked lower because architectural decisions were made during
  exploration (conditional > always-on; Phase 1 integration point; reporter posture)
  that must be captured in a permanent document before wip/ is cleaned.

## Deferred Types

- **Decision Record** was noted as relevant for the "don't pursue" crystallize
  extension — the design doc should address whether Decision Record gets promoted
  from deferred status or whether a new "don't pursue" produce path is added.
  Within the design doc itself this is a design decision, not a separate artifact.

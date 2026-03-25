# Design Summary: explore-adversarial-lead

## Input Context (Phase 0)

**Source:** /explore handoff
**Problem:** /explore has no mechanism for challenging whether a directional topic is
worth pursuing. An adversarial demand-validation lead would fire for directional topics
in Phase 2, investigate the null hypothesis from code-readable sources, and feed findings
into convergence. "Don't pursue" needs to be a first-class crystallize outcome.
**Constraints:**
- Zero latency cost (Phase 2 is parallel fan-out; extra agent is free)
- No UX disruption for diagnostic topics
- Phase 2, Phase 3, and SKILL.md resume logic must remain unchanged
- "Don't pursue" artifact must survive wip/ cleanup (permanent location)
- Honest assessment over reflexive negativity (reporter posture, not advocate)

## Decisions (Phase 2)

- **Decision 1 (Classification trigger):** Option B — two-gate trigger (label pre-check + conversation post-check with ≥2 signals). Conservative threshold. --auto falls back to label-only.
- **Decision 2 (Framing + output):** Reporter frame with per-question confidence (high/medium/low/absent) + new Rejection Record crystallize type writing docs/decisions/REJECTED-<topic>.md.
- **Decision 3 (Eval rubric):** Composite A+C+D — three fixture-backed eval cases (strong-demand, absent-demand, diagnostic-topic).

## Cross-Validation (Phase 3)

**Outcome:** Passed — no conflicts across decisions.
D2's confidence vocabulary maps directly to D3's eval assertions. D1's classification scope (directional topics) matches D2's reporter framing (report what you found, not advocate for rejection). All assumption dependencies confirmed compatible.

## Architecture (Phase 4)

**Changed files (4):** phase-1-scope.md (classification + injection), crystallize-framework.md (Rejection Record type), phase-5-produce-no-artifact.md (tightened wording).
**New files (2):** phase-5-produce-rejection-record.md, evals/evals.json + fixtures.
**Zero changes to:** Phase 2, Phase 3, SKILL.md resume logic.

## Security Review (Phase 5)

**Outcome:** Option 2 — Document considerations (no design changes required)
**Summary:** No new permission classes, external dependencies, or network calls. Two prompt-authoring concerns: (1) issue body content needs explicit delimiter framing to resist prompt injection; (2) adversarial lead agent prompt must inherit Phase 0's resolved visibility context, which Phase 1 does not currently propagate. Rejection Record permanence is a governance concern mitigated by the two-gate trigger's conservative threshold.

## Current Status

**Phase:** 6 — Final Review
**Last Updated:** 2026-03-24

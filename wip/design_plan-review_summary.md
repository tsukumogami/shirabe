# Design Summary: plan-review

## Input Context (Phase 0)
**Source:** /explore handoff
**Problem:** The /plan skill's Phase 6 review is a passive completeness check that does not catch design contradictions inherited into the plan, non-discriminating acceptance criteria, or must-run QA scenarios that are deprioritized. A new /review-plan skill must replace Phase 6 with adversarial challenge and loop-back capability.
**Constraints:** Loop-back must use existing /plan resume logic (delete wip/ artifacts to the loop target). Artifact lives in wip/ only. /work-on integration deferred. Must be callable standalone or as sub-operation inside /plan (analogous to /decision inside /design).

## Security Review (Phase 5)
**Outcome:** Option 2 - Document considerations
**Summary:** No design changes needed. Two prompt injection risks (malicious issue body content redirecting review agent; corrupted correction_hint redirecting Phase 4 agent) are addressable via explicit framing conventions in phase files.

## Current Status
**Phase:** 5 - Security
**Last Updated:** 2026-03-23

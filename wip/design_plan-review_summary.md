# Design Summary: plan-review

## Input Context (Phase 0)
**Source:** /explore handoff
**Problem:** The /plan skill's Phase 6 review is a passive completeness check that does not catch design contradictions inherited into the plan, non-discriminating acceptance criteria, or must-run QA scenarios that are deprioritized. A new /review-plan skill must replace Phase 6 with adversarial challenge and loop-back capability.
**Constraints:** Loop-back must use existing /plan resume logic (delete wip/ artifacts to the loop target). Artifact lives in wip/ only. /work-on integration deferred. Must be callable standalone or as sub-operation inside /plan (analogous to /decision inside /design).

## Current Status
**Phase:** 0 - Setup (Explore Handoff)
**Last Updated:** 2026-03-23

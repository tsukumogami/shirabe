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

## Current Status

**Phase:** 0 — Setup (Explore Handoff)
**Last Updated:** 2026-03-24

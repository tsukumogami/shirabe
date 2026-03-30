# Findings: explore-auto-continue

## Summary

The Phase 5 produce files for /design and /prd already instruct the agent to
"continue" into the downstream skill. The gap is mechanical: they don't invoke
the Skill tool to load the downstream skill, so the agent can't follow through.
The Decision Record handoff already does this correctly via explicit Skill tool
invocation — it's the pattern to replicate.

## Key Findings

1. **Three handoff categories exist:**
   - Auto-continue (design, prd, decision): write artifacts, invoke downstream skill
   - Stop-and-tell (plan): no structured handoff, user runs separately
   - Terminal (rejection, no-artifact, deferred): explore is the final step

2. **Handoff contracts are already satisfied.** Phase 5 produce files create the
   exact artifacts downstream skills check for in their resume logic. No contract
   changes needed.

3. **Only the invocation is missing.** The produce-design and produce-prd files
   need to invoke the downstream skill via the Skill tool after writing artifacts,
   matching the pattern in produce-decision.

4. **The routing stub should document the distinction.** phase-5-produce.md should
   make explicit which types auto-continue and which stop, so the agent knows
   what to expect.

## Decision: Crystallize

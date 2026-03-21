# Design Summary: decision-framework

## Input Context (Phase 0)
**Source:** /explore handoff (decision-making-skill-impact)
**Problem:** 39 user-blocking points across 5 skills; no structured decision recording; no autonomous execution mode
**Constraints:** Zero information loss between decision output and design doc format; phase files under 150 lines; decision skill must be both standalone and composable

## Current Status
**Phase:** 0 - Setup (Explore Handoff)
**Last Updated:** 2026-03-21

## Research Available
9 research files from exploration:

### Round 1 (decision skill architecture)
- `wip/research/explore_decision-making-skill-impact_r1_lead-design-decomposition.md` — how design skill changes
- `wip/research/explore_decision-making-skill-impact_r1_lead-output-format.md` — canonical decision report structure
- `wip/research/explore_decision-making-skill-impact_r1_lead-sub-operation.md` — invocation model (agent vs inline)
- `wip/research/explore_decision-making-skill-impact_r1_lead-multi-decision.md` — parallel decisions + cross-validation
- `wip/research/explore_decision-making-skill-impact_r1_lead-explore-convergence.md` — explore handoff
- `wip/research/explore_decision-making-skill-impact_r1_lead-phase-discipline.md` — phase file sizing + complexity budget

### Round 2 (non-interactive mode + lightweight framework)
- `wip/research/explore_decision-making-skill-impact_r2_lead-ask-inventory.md` — 39 blocking points audited
- `wip/research/explore_decision-making-skill-impact_r2_lead-non-interactive.md` — --auto flag, assumption lifecycle
- `wip/research/explore_decision-making-skill-impact_r2_lead-lightweight-framework.md` — micro-protocol, decision blocks, manifest

## Key Decision Questions for the Design
1. Decision block format (HTML comments vs YAML vs structured markdown)
2. Invocation model for multi-decision (agent spawn per decision vs sequential inline)
3. Non-interactive mode signal propagation (flag vs CLAUDE.md header vs env var)
4. Cross-validation loop termination (round limit vs convergence detection)
5. Assumption review surface (terminal summary vs PR body vs separate artifact)
6. Lightweight-to-heavyweight escalation mechanics
7. Design skill phase restructuring (how many phases, what order)

# /brief Discovery: shirabe-child-dispatch-contract

## Problem Candidate

An orchestrator reading the parent-skill-pattern v1 docs today (`/scope` and `/charter` SKILL.md plus `references/parent-skill-pattern.md`) cannot tell, from the text alone, how a parent skill is meant to invoke its children. The Team Shape section says `/scope` is single-agent with no team primitives; Phase 2 says child invocation goes via "the child's existing input mode"; R19 (Team-Lead Operating Discipline) describes a behavioral sleep-check-nudge loop but does not say which harness primitive carries the dispatch. The same ambiguity is present in `/charter` for its strategic chain. An orchestrator coming to these docs cold reaches at least three plausible mechanisms — inline Skill-tool invocation, a single general-purpose subagent, or a `TeamCreate`-backed team with a coordinator and peer roles — none of which all match the author's intent across the chain. The pattern's child-dispatch mechanism is not legible from the docs that are supposed to define it.

## Outcome Candidate

An orchestrator (human or agent) reading the parent-skill-pattern v1 docs finishes those docs with one unambiguous reading of how a parent invokes a child, including: which harness primitive carries the dispatch, what state is established before the child starts, what the parent is allowed to observe during the run, and what the parent reads back when the child returns. The same reading applies symmetrically to `/scope` and `/charter` and to all seven children in their respective chains, so an orchestrator running `/scope my-feature` and an orchestrator running `/charter my-bet` are not making different mechanism choices for the same pattern.

## Grounding Anchor

conversation only — anchored by GitHub issue `tsukumogami/shirabe#150` (titled "docs(scope): clarify that /scope spawns a TeamCreate-backed team per child dispatch"), which surfaced the legibility gap while the author was driving `/scope table-diagram-reconciliation`. The issue is the ephemeral source the parent skill (/scope) is invoking this BRIEF to persist as durable framing.

## Journey Sketch

- An orchestrator agent invokes `/scope my-feature` for the first time, reads `/scope` SKILL.md to see how it will hand off to `/brief`, and cannot reconcile the single-agent statement, the "child's existing input mode" wording, and the R19 discipline into one mechanism. The orchestrator picks one, ships it, and the author later flags that the choice did not match intent.
- A skill author maintaining a child skill (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`) wants to know whether its `## Team Shape` section is read by the parent or only by the child itself, and what shape that section should take to support the parent's dispatch. The current docs do not say.
- A reviewer evaluating a parent-skill-pattern change reads the pattern reference and the two parent SKILL.md files and cannot tell whether a proposed change to dispatch behaviour is in-scope for the contract or a per-parent override. The boundary between contract and implementation is not drawn.

## Open Questions for Drafting

- The Phase 2 reference may already contain wording that further constrains the contract; the BRIEF should not overstate the gap if Phase 2 already pins down some of it.
- The fix could land as a single contract reference (e.g. a new section in `parent-skill-pattern.md`) or as parallel sections in each parent's SKILL.md. The BRIEF must NOT prescribe which shape; the PRD/DESIGN owns that.
- Symmetry with `/charter` is asserted by the parent's topic context; the BRIEF should treat the contract as pattern-level (both parents, all children) rather than `/scope`-only.

# Exploration Decisions: work-on-koto-unification

## Round 1

- Orchestrator lives in skill layer, not koto: koto is per-workflow by design; multi-issue queue management is above its abstraction level
- Per-issue koto workflows, not monolithic: each issue gets its own state file; avoids koto's lack of sub-workflows/iteration
- Review panels stay in skill markdown: koto gates handle binary checks; multi-agent orchestration with feedback loops isn't expressible as gates
- Gate migration proceeds independently: mechanical refactoring, not blocked by orchestrator design
- External state file for orchestrator: hybrid approach with koto context for content and a structured manifest for issue tracking

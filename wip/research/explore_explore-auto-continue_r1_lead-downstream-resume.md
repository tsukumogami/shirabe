# Lead 2: Downstream Skill Resume Contracts

## /design expects

- `wip/design_<topic>_summary.md` triggers Phase 1 (Approach Discovery)
- `docs/designs/DESIGN-<topic>.md` skeleton with Context, Problem, Decision Drivers
- Phase 0 is considered done — explore's handoff fills that role

## /prd expects

- `wip/prd_<topic>_scope.md` triggers Phase 2 (Discover) — Phase 1 skipped
- Scope file synthesized from exploration findings
- Accumulated decisions from explore included in scope

## /plan expects

- No structured handoff artifact — accepts any topic string
- User runs `/plan <topic>` separately
- No explore artifacts read

## Key Finding

The handoff contracts are well-defined and already compatible with auto-invocation.
/design and /prd both have explicit resume conditions that Phase 5 produce files
already satisfy. The missing piece is the Skill tool invocation to load the
downstream skill into the agent's context so it can follow the resume logic.

No downstream skill reads explore's raw findings. All context is synthesized into
the handoff artifacts.

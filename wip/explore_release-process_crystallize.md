# Crystallize Decision: release-process

## Chosen Type
Design Doc

## Rationale
The exploration established clear requirements (version sync across git tag, plugin.json, and marketplace.json; full automation at release time; integration with org skills) but surfaced competing implementation approaches and architectural decisions that need permanent documentation. The core question is "how should we build this?" — requirements were provided as input, not discovered during exploration.

## Signal Evidence
### Signals Present
- What to build is clear, but how to build it is not: Requirements are well-defined (automated version sync), but the workflow architecture is open
- Technical decisions need to be made between approaches: Approach A (tag-first) vs Approach B (commit-first), sentinel vs real version on main, dispatch-trigger vs tag-trigger
- Architecture, integration, or system design questions remain: How the /release skill integrates with shirabe-specific pre-tag manifest updates
- Exploration surfaced multiple viable implementation paths: Two workflow approaches, two version-on-main strategies
- Architectural decisions were made during exploration: Approach B selected, sentinel value selected — these must be documented permanently
- The core question is "how should we build this?": Yes

### Anti-Signals Checked
- What to build is still unclear: Not present — requirements are clear
- No meaningful technical risk or trade-offs: Not present — marketplace caching creates real correctness risk
- Problem is operational, not architectural: Not present — this is workflow architecture

## Alternatives Considered
- **PRD**: Score 0 (demoted). Requirements were provided as input, not discovered. Single anti-signal (requirements given). No need to capture "what to build" — that's already clear.
- **Plan**: Score -1 (demoted). No upstream design doc exists to decompose. Technical approach has decisions that need documenting before sequencing.
- **No Artifact**: Score -1 (demoted). Architectural decisions were made during exploration that need permanent documentation. wip/ cleanup would lose the Approach B rationale and sentinel value justification.
- **Rejection Record**: Score 0. No positive rejection evidence — demand was "not validated" not "validated as absent."

## Deferred Types
- **Decision Record**: Could fit since specific choices (Approach B, sentinel) were made. But the decisions are interdependent and part of a larger system design, not a single binary choice. Design Doc captures them in context.

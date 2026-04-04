# Crystallize Decision: work-on-koto-unification

## Chosen Type
Design Doc

## Rationale
The exploration established a clear three-layer architecture (koto per-issue state machine, skill-layer orchestrator, shared components) but surfaced multiple open technical decisions: orchestrator implementation (skill markdown vs helper script vs Go tool), state management (external file vs koto context vs hybrid), koto template topology for three entry modes, gate migration mechanics, and review panel integration. The "what to build" is settled; the "how to build it" needs specification across six architectural questions.

Five architectural decisions were already made during exploration (orchestrator location, per-issue koto workflows, review panels stay in skill markdown, gate migration independence, external state for orchestrator). These need permanent documentation -- wip/ artifacts are cleaned before merge.

## Signal Evidence
### Signals Present
- **What to build is clear, how to build it is not**: User specified the goal precisely (unified work-on, absorb /implement, use koto). Architecture has multiple open questions.
- **Technical decisions between approaches**: Orchestrator design (4 options identified), state management (4 options), entry routing (4 options), review panel integration (4 options).
- **Architecture/system design questions remain**: Three-layer architecture needs specification: koto template topology, orchestrator-koto interface, cross-issue context protocol.
- **Multiple viable implementation paths**: Each lead identified 3-4 viable approaches with different trade-offs.
- **Architectural decisions made during exploration**: Five decisions captured in decisions.md that need permanent home.
- **Core question is "how should we build this?"**: Confirmed by all 7 leads converging on architecture, not requirements.

### Anti-Signals Checked
- **What to build is still unclear**: Not present. Requirements are crystal clear.
- **No meaningful technical risk or trade-offs**: Not present. Significant trade-offs in every dimension.
- **Problem is operational, not architectural**: Not present. Deeply architectural.

## Alternatives Considered
- **PRD**: Requirements were provided as input by the user, not discovered during exploration. The "what" isn't contested. Anti-signals present.
- **Plan**: No upstream design doc exists to decompose. Open architectural decisions block issue sequencing. Anti-signals present.
- **No Artifact**: Architectural decisions were made that need documentation. Complexity requires written specification for implementation. Anti-signals present.

## Deferred Types
- **Decision Record**: Some decisions fit this format, but there are 5+ interconnected decisions rather than a single choice. A design doc captures the full decision space better than individual ADRs.

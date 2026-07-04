# Crystallize Decision: session-work-summary

## Chosen Type
Design Doc

## Rationale
The exploration's core question became "how should we build this" and answered it
through four rounds of evaluated alternatives and empirical validation. The result
is a set of interrelated architectural decisions (deterministic hook pipeline,
dual-channel emission, convention-by-name cross-layer contract, no shared state
schema, emit policy, compaction re-injection) that exist only in wip/ research
files, which are deleted before merge. A design doc is the artifact that records
decided architecture for future contributors and feeds a /plan for the
cross-repo implementation (dot-niwa hooks/scripts, shirabe /status skill, niwa
dispatch-brief text).

## Signal Evidence
### Signals Present
- "How should we build this?" was the core question: rounds 1-2 compared four architectures; rounds 3-4 validated the chosen one.
- Multiple viable implementation paths surfaced: instruction-only, hook-nudged instructions, deterministic hook pipeline, display-only channels — with a deliberate pivot to the deterministic pipeline.
- Architectural decisions made during exploration that must be recorded: systemMessage+additionalContext dual-channel emission, single render script in dot-niwa with well-known-path contract, hook-private ledger, emit-policy table, SessionStart(compact|resume) re-injection, shirabe-stays-hook-free boundary.
- Architecture/integration questions spanned systems: Claude Code hook semantics, niwa materialization, shirabe skill loading, gh data plane.

### Anti-Signals Checked
- "What to build is still unclear": not present — the problem statement was input, and scope was confirmed in round 1.
- "No meaningful technical risk or trade-offs": not present — three empirical rounds were needed to de-risk (systemMessage semantics, -p mode behavior, injection-refusal phrasing, duplicate-hook bug).

## Alternatives Considered
- **Plan**: work is understood and sequenceable, but no upstream artifact exists; the Design Doc vs Plan tiebreaker routes to Design Doc. /plan should follow the design doc.
- **Decision Record**: disqualified by its own anti-signal — these are multiple interrelated decisions, not one choice.
- **PRD**: requirements were given as input (the user's problem statement), not identified by exploration; anti-signal applies.
- **No Artifact**: demoted — architectural decisions were made across four debated rounds; losing them with wip/ cleanup is the exact failure the framework warns about.
- **Spike Report**: feasibility was validated, but the exploration was broad (architecture + contract + format + UX), not a single time-boxed technical risk.

## Placement Note (for Phase 5)
Cross-repo feature: dot-niwa (capture hook, render script, emit policy — the bulk),
shirabe (/status skill), niwa (dispatch-brief rootskill text; optionally the
materializer dedupe fix as a prerequisite). dot-niwa has no docs taxonomy;
shirabe hosts the exploration branch and has docs/designs/. Recommendation:
host DESIGN-session-work-summary.md in shirabe with explicit cross-repo scope,
or in niwa if the team prefers design docs to live nearest the heaviest code
owner. Decide at produce/design time.

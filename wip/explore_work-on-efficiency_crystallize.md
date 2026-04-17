# Crystallize Decision: work-on-efficiency

## Chosen Type

Design Doc

## Rationale

The exploration established requirements through direct execution experience (7
concrete friction points, not hypothesis). What to build is clear. What's open
is how to build it: where to inject `issue_type` for docs routing, whether to
use a separate state or two-field discrimination, which approach to take for the
plan-backed PR model, and how the PLAN doc format changes connect to script
changes. Multiple viable implementation paths exist for several of these
decisions, with real trade-offs that future contributors need to understand and
won't be able to reconstruct from the code alone.

The decisions made during exploration (Option A for docs fast path, Approach a
for PR model, optional annotation for file conflicts) also need to be on record
so the implementation doesn't have to re-evaluate ruled-out alternatives.

## Signal Evidence

### Signals Present

- **What to build is clear, but how to build it is not**: Requirements are the 7
  friction points from direct execution; the implementation approaches (Option A/B/C,
  Approach a/b) are the open question.
- **Technical decisions need to be made between approaches**: Docs fast path has three
  implementable options with different agent-verbosity and maintenance trade-offs.
  PR model has two viable approaches (plus one ruled out). These need comparison.
- **Architecture, integration, and system design questions remain**: How the plan
  orchestrator passes `issue_type` to children is not answered by any research lead
  (gap in findings). PLAN format changes, script changes, and template changes have
  dependency ordering that needs design.
- **Exploration surfaced multiple viable implementation paths**: Every lead surfaced at
  least two concrete approaches. koto-complexity-routing alone lists three options.
- **Architectural decisions were made that should be on record**: Option A, Approach a,
  auto-add edges, three CI checks — all made during exploration and not yet documented.
- **Core question is "how should we build this?"**: Requirements are given; the
  architectural choices are the work.

### Anti-Signals Checked

- **"What to build is still unclear"**: Not present. Direct execution surfaced concrete
  friction with unambiguous fix categories.
- **"No meaningful technical risk or trade-offs"**: Not present. The single-template vs.
  fork trade-off repeats across two independent leads, which is a real architectural
  question.
- **"Problem is operational, not architectural"**: Not present. Changes span template
  state machines, CI scripts, PLAN doc format, and orchestrator-to-child data flow —
  these are structural decisions.

## Alternatives Considered

- **PRD**: Ranked lower because requirements were provided as input to the exploration
  (7 friction points from direct execution experience), not identified during exploration.
  The "what to build" is already answered. Writing a PRD would re-document what's
  already known.
- **Plan**: Partially fits — the work is understood well enough to break into issues.
  But technical approaches are still debated (Option A vs. B for docs path, Approach a
  vs. b for PR model). A plan can't sequence work whose approach isn't decided. Design
  doc comes first.
- **No artifact**: Ruled out because (a) decisions made during exploration need a
  permanent home before `wip/` is cleaned, and (b) multiple contributors may work on
  these changes and need to understand why alternatives were rejected.

# Crystallize: decision-making-skill-impact

## Chosen Type

Design Doc

## Scoring

| Type | Signals | Anti-Signals | Score |
|------|---------|-------------|-------|
| Design Doc | Technical decisions needed (decision block format, invocation model, non-interactive mode, multi-decision orchestration), what-to-build is clear but how-to-build is open, multiple approaches exist per decision | None | 4 |
| PRD | Multiple stakeholders affected | Requirements were discovered during exploration not given as input; what-to-build is already understood | 1 |
| Plan | Scope is confirmed from exploration | Open decisions remain (the architecture decisions ARE the deliverable) | -1 |
| No artifact | None | Significant decisions were made during exploration | -2 |

## Rationale

The exploration produced a clear understanding of WHAT needs to be built (a decision
skill + lightweight protocol + non-interactive mode) but the HOW has multiple open
architectural decisions:

1. How does the decision block format work? (HTML comments vs YAML vs other)
2. How does the design skill delegate to the decision skill? (agent spawn vs inline)
3. How does non-interactive mode propagate through nested skill invocations?
4. How does multi-decision cross-validation work without infinite loops?
5. How do lightweight and heavyweight decisions share an assumption manifest?

Each of these has 2-3 viable approaches discovered during research. A design doc
captures the considered options, records the chosen approach per decision, and becomes
the implementation blueprint.

## Handoff Notes

The design doc should cover three scopes in one document:
1. The decision-making skill itself (7-phase framework, fast path)
2. The lightweight decision protocol (3-step micro-workflow, decision blocks)
3. The non-interactive execution mode (--auto flag, assumption lifecycle)

These are tightly coupled — designing one without the other two produces an
incomplete architecture. The 9 research files in wip/research/ contain detailed
analysis for each.

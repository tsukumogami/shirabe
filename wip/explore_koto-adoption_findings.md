# Exploration Findings: koto-adoption

## Core Question

What would it take to convert all shirabe skills to use koto, and what koto features are missing?

## Round 1

### Key Insights

- Koto covers more ground than expected: context-exists gates, command gates, decision capture, self-loops, and session resume all exist. The gap list is about eliminating fragility, not enabling new capabilities. (koto-capabilities lead)
- 60-80% of skill line count is workflow mechanics (resume, ordering, gates) duplicated in prose. Converting to koto reduces skills to domain instructions only. (cross-skill-patterns lead)
- Three koto issues already track top gaps: #65 (variables), #66 (mid-state decisions), #87 (evidence promotion). Two new gaps need filing: polling gates and bounded iteration. (koto-gaps lead)
- Parallel agent fan-out (6/7 skills) is the biggest structural gap but pragmatically solvable with glob-aware context-exists gates rather than native parallelism. (skill-audit lead)
- The release skill is the poorest koto fit (15+ external commands, zero wip/ files). Explore, design, prd, plan are better candidates. (skill-audit lead)
- Demand is real but narrow: three documented workflow failures from wip/-based state. No users request conversions, but failures are structural and recurring. (adversarial-demand lead)

### Tensions

- Koto prerequisites (#65, #66, #87) are needs-design. Converting before they ship means workarounds.
- Scope is ambitious for single-maintainer. But the alternative is recurring structural failures.

### Decisions

- Route to roadmap/PRD: this is a phased multi-repo effort, not a single design problem
- Koto feature requests filed as blocking dependencies, not in-scope work for shirabe
- Phase by skill complexity: start with skills closest to work-on's pattern, defer release

### User Focus

User wants a PRD/roadmap for shirabe with koto feature requests as blocking dependencies in koto's repo.

## Accumulated Understanding

Converting shirabe skills to koto is a phased effort. Phase 1 converts skills that already fit koto's current model (low gap count). Phase 2 adds skills that need the new koto features. The koto features (polling gates, loop counters, glob-aware gates, content-match gates) are filed as issues in koto and tracked as blockers. The release skill converts last (most external-state-heavy). The output is a roadmap for shirabe with koto dependency links.

## Decision: Crystallize

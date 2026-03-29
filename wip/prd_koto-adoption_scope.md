# /prd Scope: koto-adoption

## Problem Statement

Shirabe's 7 non-koto skills encode workflow mechanics (resume logic, phase ordering, gate checks, decision recording) as prose instructions that agents interpret at runtime. This duplicates 60-80% of each SKILL.md's line count across skills, causes structural failures (phase skipping, design contradictions, lost decisions), and provides no visibility into workflow state. The /work-on skill already uses koto and demonstrates the pattern works, but the remaining skills haven't been converted.

## Initial Scope

### In Scope
- Converting shirabe skills to use koto for state persistence, phase gatekeeping, and verification
- Identifying koto feature gaps and filing them as issues in the koto repo
- Phased adoption plan: which skills convert first, what koto features are prerequisites
- Cross-repo dependency tracking (shirabe conversions blocked by koto features)
- Filing koto feature requests for: polling gates, bounded iteration, glob-aware context-exists, content-match gates

### Out of Scope
- Designing or implementing koto features (that's koto-side work)
- Converting the /work-on skill (already uses koto)
- Changing koto's core architecture

## Research Leads
1. Which skills can convert with koto's current capabilities vs which need new features?
2. What's the right phasing? Which conversions deliver the most value first?
3. What are the exact koto feature requests — specific enough to file as issues?

## Coverage Notes
- The explore research produced a detailed skill audit, koto capability inventory, and gap analysis
- What's missing: prioritized phasing, specific acceptance criteria per conversion, and the exact koto issue specs

## Decisions from Exploration
- Koto feature requests are blocking dependencies, not in-scope shirabe work
- Phase by skill complexity: start with skills closest to work-on's pattern
- Release skill converts last (most external-state-heavy, poorest koto fit)
- Parallel fan-out handled via glob-aware context-exists gate, not native koto parallelism
- Existing koto issues #65, #66, #87 are prerequisites; new issues needed for polling gates, loop counters, glob gates, content-match gates

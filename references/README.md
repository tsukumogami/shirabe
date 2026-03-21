# Shared References

Cross-cutting specifications and conventions used by multiple skills.
Individual skills have their own `references/` directories for skill-specific
content; this directory holds repo-wide standards.

## Decision Framework

| File | Purpose |
|------|---------|
| `decision-block-format.md` | HTML comment delimiters, status values, threshold rules |
| `decision-protocol.md` | Lightweight 3-step micro-workflow for inline decisions |
| `decision-points.md` | Manifest of all 39 known decision points with pre-classified tiers |
| `decision-report-format.md` | Canonical 6-field report structure with consumer rendering rules |
| `decisions-file-format.md` | Consolidated per-invocation decisions + assumptions file |
| `review-surface.md` | Terminal summary, PR body section, and progress feedback templates |
| `assumption-invalidation.md` | Flow for correcting wrong assumptions post-workflow |

## Conventions

| File | Purpose |
|------|---------|
| `research-artifact.md` | Naming convention and template for agent research outputs in `wip/research/` |

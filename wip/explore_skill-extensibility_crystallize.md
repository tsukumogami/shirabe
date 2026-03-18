# Crystallize Decision: skill-extensibility

## Chosen Type
Design Doc

## Rationale
The "what" is clear (extract 5 skills, build extensibility model). The "how" has
multiple competing approaches that need architectural comparison: CLAUDE.md-only
vs two-layer extension files, submodule vs two plugins, extract-first vs
design-upfront. Decisions made during exploration (two-layer model, append-based
composition, sequencing, koto integration constraints) need permanent documentation
in a design doc before implementation can begin.

## Signal Evidence
### Signals Present
- What to build is clear, how is not: multiple viable extensibility mechanisms
- Technical decisions between approaches: 3 extension models, 3 consumption models
- Architecture questions remain: extension file discovery, loading, conflict
  resolution, breaking change semantics for markdown-based skills
- Decisions made during exploration: two-layer model, extract-before-extend
  sequencing, append-based composition, koto per-skill templates

### Anti-Signals Checked
- What is still unclear: No — problem and goals are well-defined
- No technical risk: No — platform instability (no plugin deps), markdown
  composition semantics, and koto format dependency all present risk

## Alternatives Considered
- **Plan**: Premature — open architectural decisions need resolution first
- **No artifact**: Rejected — decisions made during exploration need documentation

# Exploration Decisions: gha-doc-validation

## Round 1

- **Single configurable reusable workflow (not per-format)**: One `validate.yml` with config-driven behavior is the target design. Start with no configuration requirement; add configuration options incrementally. Rationale: simpler caller experience, aligns with PRD R6.

- **Private tools repo: inspire from, do not reference or depend on**: The private tools validation suite served its purpose. Shirabe becomes the new canonical home for all doc validation logic. No migration dependency, no cross-reference in public artifacts. Rationale: public docs must not reference private infrastructure; the private tools repo is effectively superseded.

- **AI semantic validation tier: future work, not v1 scope**: The vision doc acknowledges the AI tier as a future direction but does not define requirements or acceptance criteria for it. The doc focuses on launching the static/deterministic validation capability. Rationale: no demand artifact exists for the AI tier beyond this conversation; premature to commit.

- **Schema and versioning for doc formats is part of the vision**: The frontmatter-derived schema approach (extending the `schema: plan/v1` pattern already in Plan to all formats) should be described in the vision doc as a foundation for validation. Rationale: validators need a stable schema anchor; Plan already proves this pattern works; other formats should adopt it.

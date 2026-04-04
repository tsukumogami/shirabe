# Crystallize Decision: vision-doc-workflow

## Chosen Type
PRD

## Rationale

The exploration produced a well-understood feature (the VISION artifact type) with clear requirements that need to be captured permanently. Multiple decisions were made during exploration — template structure, crystallize signal/anti-signal tables, scope gating to strategic-only, lifecycle states, naming conventions, PROJECTS.md integration — that will be lost when wip/ is cleaned. A PRD is the right vessel to formalize these into a durable specification.

Plan scored equally (2) without demotion, but the Design Doc vs Plan tiebreaker applies: no upstream PRD or design doc exists for this topic, and the documentation purpose rule is decisive — exploration decisions need permanent documentation that a Plan can't provide (a Plan decomposes an existing spec into issues; there's no spec yet).

## Signal Evidence

### Signals Present
- **Single coherent feature emerged**: The VISION artifact type is one capability with defined boundaries, template, lifecycle, and crystallize integration
- **Core question is "what should we build and why?"**: The exploration answered what the VISION type should contain, how it differs from PRD/Roadmap, and why it's needed
- **User stories or acceptance criteria are missing**: No formal specification captures the decisions made during exploration; acceptance criteria need to be written

### Anti-Signals Checked
- **Requirements were provided as input**: Not present — requirements emerged from exploration, not given beforehand
- **Multiple independent features**: Weakly present — reference standards could ship independently, but the core VISION type is a single coherent feature. Caused demotion but doesn't disqualify
- **Independently-shippable steps**: Weakly present — same as above

## Alternatives Considered
- **Plan (Score: 2, not demoted)**: Ranked lower via tiebreaker — no upstream artifact exists to decompose, and exploration decisions need a spec document before they can be broken into issues
- **Design Doc (Score: 0, demoted)**: The integration pattern is straightforward (add to crystallize framework, add Phase 5 handler). No architectural alternatives need evaluation
- **No Artifact (Score: 0, demoted)**: Disqualified by documentation purpose rule — decisions were made that future contributors need to know, and wip/ is cleaned before merge
- **Rejection Record (Score: 0)**: Not applicable — exploration concluded "proceed"

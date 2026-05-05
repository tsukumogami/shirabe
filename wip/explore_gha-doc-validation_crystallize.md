# Crystallize Decision: gha-doc-validation

## Chosen Type

PRD

## Rationale

The exploration produced a single coherent capability (reusable GHA workflows for doc format validation) with clear user stories, no public acceptance criteria, and requirements that need to be stated in a permanent document before implementation begins. The PRD is the right artifact: it captures what the system should do and for whom, without committing to implementation details the user isn't ready to specify.

The user said "vision doc," but the /vision artifact type is for project thesis and strategic justification — "should this project exist?" shirabe exists; this capability doesn't, but the question of whether it should isn't open. What's open is what it should include, how downstream repos consume it, and where the line sits between v1 and future work. Those are requirements questions, not thesis questions.

## Signal Evidence

### Signals Present

- **Single coherent capability emerged**: reusable GHA validation workflows for shirabe's five doc formats, consumed via thin `uses:` callers. The scope is coherent and bounded.
- **User stories and acceptance criteria are missing**: the overall PRD for shirabe has R5/R6/R6a at high level, but no public document defines what "done" looks like for this capability specifically — which formats, which checks, what a downstream caller must look like, how schema versioning works, what the AI tier is vs. isn't in v1.
- **Requirements need a public home**: the schema/versioning insight (extending `schema: plan/v1` to all formats) and the single-configurable-workflow decision are new requirements that came out of this exploration. They'll be lost when wip/ is cleaned unless captured in a permanent doc.
- **Multiple downstream consumers need alignment**: downstream repo maintainers consuming the workflows, shirabe contributors building the validators, future adopters of the AI tier. All need a stable written contract for what the system does.

### Anti-Signals Checked

- "Requirements were provided as input to the exploration" — partially true (PRD-shirabe R5/R6/R6a), but these are too coarse to drive implementation. The exploration produced the specific requirements (schema versioning, single-workflow model, static-only v1 scope). This anti-signal doesn't block PRD.

## Alternatives Considered

- **Design Doc** — ranked second because real architectural decisions were made (single configurable workflow, schema-from-frontmatter approach, one-workflow-with-boolean-gate vs. two-workflow-files). But the user explicitly said they don't want to design yet — the schema approach is still conceptual, the check scope per format isn't defined, and the PRD needs to exist before a design doc can reference it. One anti-signal (what to build still has open questions) demotes it. PRD first.

- **VISION** — heavily demoted (-6 after scoring). Six anti-signals: shirabe exists; this is feature-level not project-level; requirements emerged from the exploration; PRD-shirabe covers shirabe's strategic justification already; users and needs are identified; CLAUDE.md declares tactical scope. The user's "vision doc" language is colloquial.

- **No Artifact** — ruled out: architectural decisions were made during exploration (schema versioning approach, workflow model) that future contributors need. wip/ will be cleaned.

## Deferred Types (if applicable)

None scored above demoted types.

# Crystallize Decision: project-tool-management

## Chosen Type
No Artifact

## Rationale
The implementation is three discrete tasks: write a 2-tool `.tsuku.toml`, edit one CI workflow line, and file 5-6 friction issues against tsuku. No coordination, no architectural decisions, no document a future contributor needs to understand the "why" -- the config file is self-documenting and the friction issues will live as GitHub issues.

## Signal Evidence
### Signals Present
- Simple enough to act on directly: 1 config file (5 lines), 1 CI workflow edit (change `tsuku install tsukumogami/koto -y` to `tsuku install -y`), issue filing
- One person can implement without coordination: maintainer-driven, no stakeholder alignment needed
- Exploration confirmed existing understanding: hands-on Docker testing validated the happy path works
- Right next step is "just do it": all decisions are made, no open questions block implementation

### Anti-Signals Checked
- "Decisions were made during exploration": Present but not load-bearing. Decisions (use `"0.5.0"` not `"0.5"`, skip jq/python3/claude, include gh) are configuration choices self-evident from the resulting `.tsuku.toml`. No architectural reasoning that would be lost.
- "Others need documentation to build from": Not present. One-person task.

## Alternatives Considered
- **Plan**: Scored 2 with no anti-signals. Ranked close but 3 work items (config, CI, issues) don't warrant formal decomposition. No upstream artifact to decompose from.
- **Design Doc**: Scored negative. No technical decisions between approaches -- the approach is clear.
- **PRD**: Scored negative. Requirements were known before exploration (adopt `.tsuku.toml`), not discovered during it.

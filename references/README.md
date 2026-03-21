# Shared Skill References

Runtime references loaded by multiple skills via `${CLAUDE_PLUGIN_ROOT}/references/`.
These files are read by skill phase files during execution.

For design specifications and documentation that describe the framework but
aren't loaded by skills at runtime, see `docs/specs/`.

| File | Used by | Purpose |
|------|---------|---------|
| `decision-block-format.md` | decision, all skills | HTML comment delimiters, status values, threshold rules |
| `decision-protocol.md` | all workflow skills | Lightweight 3-step micro-workflow for inline decisions |
| `decision-report-format.md` | decision, design, explore | Canonical 6-field report with consumer rendering rules |
| `decision-presentation.md` | explore, design, prd | AskUserQuestion formatting pattern for presenting choices |

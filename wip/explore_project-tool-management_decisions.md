# Exploration Decisions: project-tool-management

## Round 1
- Use `"0.5.0"` for koto version pin: partial semver (`"0.5"`) fails for distributed source recipes; exact semver is the only working syntax
- Skip jq in `.tsuku.toml`: recipe broken on both macOS (unsupported platform) and Linux (shared lib relocation failure)
- Skip python3 and claude: no tsuku recipes exist; these remain system dependencies
- Include gh at `"2"` pin: works correctly, useful for local dev consistency even though CI runners provide it
- Demand is self-directed: this is a friction log exercise, not a response to user demand; value is in surfacing tsuku UX issues
- Proceed to crystallize: findings are solid from both code review and hands-on testing; implementation is small

## Round 2 (auto-mode)
- Ready to crystallize without another research round: hands-on Docker testing validated the happy path and surfaced 6 concrete issues
- No artifact needed beyond direct implementation: 2-tool config file + 1 CI workflow edit + issue filing is too small for a design doc or PRD

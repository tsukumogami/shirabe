# Exploration Findings: project-tool-management

## Core Question

How should shirabe adopt tsuku's new `.tsuku.toml` project-level tool management, both for local development and CI? We're treating this as a friction log exercise to surface UX issues worth filing back against tsuku.

## Round 1

### Key Insights

- **Setup is a three-step manual flow**: `tsuku init` (empty file), manual TOML editing, `tsuku install` (batch install). No tool discovery, no interactive selection, no version validation until install time. (lead: setup-experience)
- **Org-scoped recipe support in `.tsuku.toml` is undocumented**: Koto uses `tsukumogami/koto` syntax but design doc examples only show bare names. Whether this works in config is the single biggest unknown. (lead: tool-selection)
- **CI is well-supported**: `tsuku install -y` is the intended CI pattern. No permission issues. Clean exit codes (0/6/15). (leads: ci-workflows, ci-security)
- **No adoption guide exists**: Shell Integration guide covers usage, not adoption. No migration guide, no tool discovery command. (lead: adoption-path)
- **Recipe coverage is partial**: gh and jq have recipes. Koto is org-scoped. Python3 has ambiguous variants. Claude has no recipe. (lead: tool-selection)
- **No `.tsuku.toml` permission checks**: The 0600 gate applies only to `config.toml`, not project config. CI-safe. (lead: ci-security)
- **Demand is exploratory**: No shirabe users have requested this. Current workarounds work. Value is in friction discovery. (lead: adversarial-demand)

### Tensions

- Org-scoped recipes vs. config format: the most important tool (koto) may use a syntax the config doesn't support
- Minimalism vs. adoption friction: tsuku's intentional minimalism creates friction for first-time adopters
- Declaring everything vs. declaring what matters: gh/jq are pre-installed on runners; declaring them adds reproducibility but also maintenance

### Gaps

- Whether `.tsuku.toml` supports org-scoped recipe names (`tsukumogami/koto`)
- python3 and claude recipe availability
- No multi-tool `.tsuku.toml` examples in the workspace

### Decisions

- Proceed to crystallize: findings sufficient to decide artifact type
- Demand is exploratory, not remedial: friction log exercise, not blocking problem
- Scope: koto primary, gh/jq optional, python3/claude likely system deps

### User Focus

User chose to move to artifact type selection rather than investigate further. The org-scoped recipe question can be resolved during implementation.

## Accumulated Understanding

Tsuku's `.tsuku.toml` is a shipped, stable feature with clean CI support. Shirabe's adoption is straightforward in principle: create config, declare koto (and optionally gh/jq), update CI to `tsuku install -y`. The main friction points are: (1) org-scoped recipe support in the config file is undocumented, (2) no adoption guide exists for existing projects, (3) tool discovery requires manual registry knowledge. These friction points are themselves the value of this exploration -- they become issues to file against tsuku. The implementation is small (one config file, one CI workflow change) but the friction log is the real deliverable.

## Decision: Crystallize

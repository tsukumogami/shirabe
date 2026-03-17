# shirabe

Structured pre-implementation workflow skills for AI coding agents. Powered
by koto for structural enforcement.

## Repo Visibility: Public

Content must not reference private repos, internal resources, or
pre-announcement features.

## Planning Context: Tactical

When running /explore or /plan here:
- Issues represent implementation-level work items
- Designs are scoped to this repo

## Conventions

- Recipe names: kebab-case
- Conventional commits: `feat:`, `fix:`, `docs:`, `chore:`
- No emojis in code or committed documentation
- Never add AI attribution or co-author lines to commits or PRs

## Directory Structure

```
shirabe/
├── skills/              # Claude Code workflow skills
├── koto-templates/      # Koto YAML workflow templates
├── .github/workflows/   # Reusable CI validation workflows
├── .claude-plugin/      # Plugin manifest and marketplace entry
└── docs/                # Documentation and guides
```

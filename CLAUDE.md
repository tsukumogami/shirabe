# shirabe

Structured workflow skills for AI coding agents. Powered
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

## Intermediate Storage

shirabe historically uses `wip/` as the standard location for
intermediate workflow artifacts because `wip/` is committed to git and
visible to the user during review. koto context replaces `wip/` for
koto-driven workflows: koto provides cloud-backed storage for workflow
context with the same review and traceability properties, removing
the need to pollute git history with intermediates.

The rule:

- **Non-koto workflows** use `wip/` for intermediate artifacts.
- **koto-driven workflows** use koto context (`koto context add`) for
  every artifact that should be reviewable or traceable downstream.
  `wip/` is not a koto-driven-workflow location.
- **Agent-side scratch when assembling content for koto context** can
  use any on-disk location, but the file must either be explicitly
  deleted after `koto context add` succeeds, or live in an auto-wiped
  location (`/tmp/`, `$TMPDIR`, `mktemp`-produced paths). The
  invariant: no persistent on-disk shadow of koto-managed content.

## Skill Evals

Whenever a skill is created or updated, create or update its evals at
`skills/<name>/evals/evals.json`. Whenever evals are created or updated,
delegate running them to an agent with `/skill-creator` loaded:

```
Spawn an agent with /skill-creator and instruct it to run:
  scripts/run-evals.sh <skill-name>
```

The agent needs `/skill-creator` loaded because the script invokes it via
`claude -p` to execute each scenario and grade assertions. Fix any failing
assertions before committing. Do not rely on the CI existence check
(`check-evals-exist.sh`) as a substitute for actually running the evals.

## Directory Structure

```
shirabe/
├── skills/              # Claude Code workflow skills
├── koto-templates/      # Koto YAML workflow templates
├── .github/workflows/   # Reusable CI validation workflows
├── .claude-plugin/      # Plugin manifest and marketplace entry
└── docs/                # Documentation and guides
```

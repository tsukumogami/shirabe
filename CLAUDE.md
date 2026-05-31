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

## Artifact Types and When to Use Them

shirabe recognizes seven artifact types across two altitude bands.
Reach for the one whose altitude matches your conversation:

- **VISION** (long-term aspiration, years). Captures WHY a project
  should exist — thesis, audience, value proposition, org fit. Use
  when defining or revising a project's long-term identity.
- **STRATEGY** (medium-term defensibility, quarters to a year or
  two). Operationalizes a piece of an upstream VISION. Captures the
  falsifiable bet, the Building Blocks decomposition, coordination
  dependencies, and per-direction invalidation conditions. Use when
  the work needs medium-term framing without re-justifying the
  long-term thesis (VISION) and isn't ready for sequenced feature
  decomposition (ROADMAP).
- **ROADMAP** (sequenced features). Lists what gets built and in
  what order, with dependencies between features.
- **BRIEF** (feature framing). Captures a single feature's problem,
  outcome, user journeys, and scope boundary before requirements
  exist. Use when a feature is named but its framing hasn't been
  written down; reach for a PRD once the framing is settled and you
  need to capture requirements.
- **PRD** (requirements). Captures WHAT a feature does and WHY,
  user-facing.
- **DESIGN** (architecture). Captures HOW a feature is built — the
  technical approach, trade-offs, components.
- **PLAN** (execution). Decomposes a design into atomic
  implementable issues with a dependency graph.

The pipeline runs VISION → STRATEGY → ROADMAP → BRIEF → PRD →
DESIGN → PLAN, though authors enter at whichever altitude matches
the conversation they need to have. BRIEF is the newest artifact
type and sits between ROADMAP and PRD on the tactical chain; use it
to frame a feature's problem, outcome, journeys, and scope before
writing requirements.

## Strategic Chain Entry: /charter

`/charter` is a parent skill that walks an author through the
strategic chain (VISION → STRATEGY → ROADMAP) as a single
conversation, holding state across child boundaries and producing
a STRATEGY as its terminal artifact. Use it when the conversation
needs strategic framing decided in one sitting rather than reached
for child-skill at a time.

Reach for `/charter` when an author says any of:

- "start a strategic conversation about X"
- "open a charter for Y"
- "I need to think through the bet on Z"

Direct invocation is `/charter <topic-slug>` (the topic slug
matches the pattern `^[a-z0-9-]+$`). The child skills `/vision`,
`/strategy`, and `/roadmap` remain directly invocable on their own
for authors who already know which altitude they want.

## Tactical Chain Entry: /scope

`/scope` is a parent skill that walks an author through the
tactical chain (BRIEF → PRD → DESIGN → PLAN) as a single
conversation, holding state across child boundaries and producing
a PLAN as its terminal artifact. Use it when the conversation
needs feature scope decided in one sitting rather than reached
for child-skill at a time.

Reach for `/scope` when an author says any of:

- "specify a feature called X"
- "scope feature Y"
- "walk me through specifying Z"

Direct invocation is `/scope <topic-slug>` (the topic slug
matches the pattern `^[a-z0-9-]+$`). The child skills `/brief`,
`/prd`, `/design`, and `/plan` remain directly invocable on their
own for authors who already know which altitude they want.

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

## Authoring koto-using Skills

When creating or updating a shirabe skill that calls `koto` (`koto
init`, `koto next`, `koto context`, `koto decisions`, etc.), consult
`/koto-skills:koto-author` before prescribing the integration pattern.
The author skill points at koto's canonical references (`cli-usage`,
`custom-skill-authoring`, template format) and surfaces idioms that
aren't obvious from reading existing shirabe skills alone. Several
shirabe-side mistakes (over-eager on-disk staging; assumptions about
which env vars are auto-set in the plugin loader) would have been
avoided by checking these references first.

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

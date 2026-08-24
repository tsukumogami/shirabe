# shirabe

Structured workflow skills for AI coding agents. Powered
by koto for structural enforcement.

## Repo Visibility: Public

Content must not reference private repos, internal resources, or
pre-announcement features.

## Prose Vocabulary: tier, journey, underscore

Terms shirabe uses as its own terms of art, which the writing-style rules
must not fire on. `Tier 1-4` is the decision-complexity vocabulary of
`docs/designs/current/DESIGN-decision-framework.md`; `journey` is a required
section heading in shirabe's own BRIEF format, so the rulebook fires against
the repo that wrote it. `underscore` is banned in its verb sense (to
underscore a point) and shirabe uses the noun constantly, for the `_`
character in filenames and YAML scalars; a matcher cannot tell those apart,
so the term is declared rather than the rule weakened.

Declared here rather than exempted in code, so shirabe uses the same
mechanism an adopting repository uses. Suppression is term-scoped and does
not extend to variants: `tier` does not suppress `tiered`. A repository with
no declaration receives findings for every term, and writing a declaration
is an adopter's first action. The rules themselves live in
`skills/writing-style/rules.yaml`.

## Planning Context: Tactical

When running /explore or /plan here:
- Issues represent implementation-level work items
- Designs are scoped to this repo

## Release Notes Convention: docs/guides/

Release notes for shirabe land under `docs/guides/`. The release
workflow targets that directory when emitting per-version notes
and adopter-facing migration guides; the header parallels the
other CLAUDE.md convention headers (Repo Visibility, Planning
Context) so the validator's FC-CONVENTIONS check can find it. See
`references/fixes/claude-md-conventions.md` for the canonical
header format and the cross-references to the other convention
headers.

## PR Grouping Policy: coarsest-legal

The default PR-grouping policy for a coordinated multi-repo effort:
one PR per repository (the coarsest legal unit). A repo splits into
more than one PR only on a recorded trigger. This is a durable
workspace preference, resolved `flag > CLAUDE.md-header > default`;
the default is `coarsest-legal`. The header parallels the other
convention headers (Repo Visibility, Planning Context, Release Notes
Convention) so a reader finds the grouping policy in the same place.
The triggers and the rule's semantics are single-sourced in
`references/coordination-strategy.md` (Coarsest-Legal-Grouping Rule);
this header sets the preference, it does not restate the rule.

## Reviewability Ceiling: default

The configured reviewability ceiling for a coordinated effort: the
size at which a single per-repo PR becomes too large to review and
the grouping splits it. This is a durable workspace preference,
resolved `flag > CLAUDE.md-header > default`; `default` defers to
the ceiling defined in `references/coordination-strategy.md`. Set a
concrete value here to override. Exceeding the ceiling is one of the
recorded split triggers named in that contract's
Coarsest-Legal-Grouping Rule; this header configures the threshold,
it does not restate the trigger.

## Artifact Lifecycle: per-skill

shirabe artifacts follow a three-rule lifecycle model. Durable
artifacts stay in `docs/` after completion and serve as the audit
trail (BRIEF, PRD, DESIGN, VISION, STRATEGY, COMP). Working
artifacts retire on completion — they exist while their job is in
flight and the cascade deletes them when a documented completion
condition holds (PLAN, ROADMAP). Each working-artifact skill names
its completion condition in its own SKILL.md `## Artifact Lifecycle`
section, which is the authoritative source for the rule. See the
per-skill sections (`skills/<name>/SKILL.md`) for the contract
each artifact type binds to.

## Artifact Types and When to Use Them

shirabe recognizes seven artifact types across two altitude bands.
Reach for the one whose altitude matches your conversation:

- **VISION** (long-term aspiration, years). Captures WHY a project
  should exist — thesis, audience, value proposition, org fit. Use
  when defining or revising a project's long-term identity.
- **STRATEGY** (medium-term defensibility, quarters to a year or
  two). Operationalizes a piece of an upstream VISION. Captures what
  we are betting on, the pieces that have to land for the bet to
  hold, who else has to move, and what would say it was the wrong
  call. Use when the work needs medium-term framing without
  re-justifying the long-term thesis (VISION) and isn't ready for
  sequenced feature decomposition (ROADMAP).
- **ROADMAP** (sequenced features). Lists what gets built and in
  what order, with dependencies between features, and stands as the
  place anyone reads how far along the work is. One feature is
  enough; there is no two-feature floor.
- **BRIEF** (feature framing). Captures a single feature's problem,
  outcome, user journeys, and scope boundary before requirements
  exist. Use when a feature is named and its framing has not been
  written down anywhere durable — including when an issue or a
  conversation already states the problem, since that source is
  ephemeral and the BRIEF is the record. Reach for a PRD once the
  framing is settled and you need to capture requirements.
- **PRD** (requirements). Captures WHAT a feature does and WHY,
  user-facing.
- **DESIGN** (architecture). Captures HOW a feature is built — the
  technical approach, trade-offs, components. Use when the
  requirements are already settled; a feature that still has to be
  worked out from scratch enters at `/scope`.
- **PLAN** (execution). Decomposes a design into atomic
  implementable issues with a dependency graph.

The pipeline runs VISION → STRATEGY → ROADMAP → BRIEF → PRD →
DESIGN → PLAN, though authors enter at whichever altitude matches
the conversation they need to have. BRIEF is the newest artifact
type and sits between ROADMAP and PRD on the tactical chain; use it
to frame a feature's problem, outcome, journeys, and scope before
writing requirements.

`/comp` (competitive analysis) is a private-only artifact type
outside the main pipeline. Reach for it when you need to survey
competitors along explicit dimensions, find concrete gaps, and turn
those findings into implications for our own choices — distinct from
a PRD (what one feature does), a BRIEF (a single feature's framing),
or a DESIGN (technical architecture). Because COMP content is
competitive, the artifact is private-only: invoked in a public repo,
`/comp` warns and emits `[/comp] WARNING <topic>: visibility=public`,
redirecting the author to a public BRIEF or PRD that references the
competitive question without containing the analysis. The same
private-only contract is enforced at validation time by the R9 check.

## Strategic Chain Entry: /charter

`/charter` is a parent skill that walks an author through the
strategic chain (VISION → STRATEGY → ROADMAP) as a single
conversation, holding state across child boundaries and producing
a durable STRATEGY as its terminal artifact. A full run also
produces a ROADMAP — `/roadmap` fires on every chain unless the
author declines it — but that ROADMAP is a working artifact that
drives work rather than recording it, which is why the STRATEGY is
the one the chain is named for. Use it when the conversation needs
strategic framing decided in one sitting rather than reached for
child-skill at a time.

Reach for `/charter` when the question in front of the author is
bigger than one feature and nothing above it is written down:
whether a body of work is worth doing at all, which of several
candidates come first and in what order, or what the bet behind a
quarter's work actually is. A request for a rollout order where
nobody has said why the work matters lands here too — sequencing
on its own produces an order with no bet behind it.

Direct invocation is `/charter <topic-slug>` (the topic slug
matches the pattern `^[a-z0-9-]+$`). The child skills `/vision`,
`/strategy`, and `/roadmap` remain directly invocable for an author
who wants only the thesis, only the bet, or only the sequence — but
reaching for one of them because a conversation sounds strategic
usually lands back here.

## Tactical Chain Entry: /scope

`/scope` is a parent skill that walks an author through the
tactical chain (BRIEF → PRD → DESIGN → PLAN) as a single
conversation, holding state across child boundaries and producing
a PLAN as its terminal artifact. Use it when the conversation
needs feature scope decided in one sitting rather than reached
for child-skill at a time.

Reach for `/scope` whenever a feature has to be built, added, or
redesigned and its requirements are not already written down —
including when nobody uses the word "scope", and including a
request for a single document, since the chain decides per hop
which documents survive. Deciding a feature by starting to code it
is the failure this entry point exists to prevent.

Direct invocation is `/scope <topic-slug>` (the topic slug
matches the pattern `^[a-z0-9-]+$`). The child skills `/brief`,
`/prd`, `/design`, and `/plan` remain directly invocable on their
own for authors who already know which altitude they want.

## Conventions

- Recipe names: kebab-case
- Conventional commits: `feat:`, `fix:`, `docs:`, `chore:`
- No emojis in code or committed documentation
- Never add AI attribution or co-author lines to commits or PRs

## CLI Surface: author with skills, check with `validate`

shirabe's CLI splits two jobs cleanly, and new work must respect the split:

- **Artifacts are authored by skills**, not by CLI subcommands. The agent
  writes the doc from the skill's prose and templates. There is no
  `create`/`render` subcommand for any artifact type — no `shirabe brief`,
  `shirabe prd`, `shirabe design`, and so on. The skill owns the body.
- **`shirabe validate` is the feedback/correctness engine.** It tells the
  agent what to fix and why. New correctness rules belong here as checks or
  modes (e.g. `--lifecycle`, `--merge-gate`, `--coordination-body`), never in a
  renderer.
- **Lifecycle moves go through `shirabe transition` / `finalize-chain`.**

**Anti-pattern (do not repeat):** do NOT add a CLI subcommand that renders or
creates an artifact body. Rendering a body is authoring, and authoring belongs
in a skill. Compiled CLI logic is justified only for deterministic
validation/feedback and gh-backed live checks. The worked example is the
coordination PR body: it is skill-authored from
`references/coordination-strategy.md` and checked by `shirabe validate`
(`--coordination-body` statically, `--merge-gate` live). An earlier iteration
shipped a `shirabe coordination create/status/sync` subcommand that rendered
the body; it was removed for exactly this reason.

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

Deciding whether koto should run a command itself, rather than asking the
agent to run it in prose, is a separate question with its own answer:
`references/default-action-conversion.md` carries shirabe's rule, the
authoring constraints this repo's own linter and templates impose, and
pointers to the states that are already converted. Read it before adding a
`default_action` to any template, and before writing a new mechanical step
into one.

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

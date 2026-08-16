# shirabe (調べ)

Structured workflow skills for AI coding agents.

shirabe is a [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
plugin that adds multi-phase workflows for the thinking that happens *before*
coding. Instead of jumping straight from idea to implementation, shirabe guides
you through research, requirements, design, planning, and review -- each with
built-in validation gates so nothing important gets skipped.

**Pronunciation:** shee-RAH-beh

## Skills

Shirabe skills sit at three altitudes, from "why should this exist" down to
"ship the code." Each altitude has a parent skill that walks the whole chain
in one sitting, plus the child skills you can also reach for directly.

### Charter chain -- strategic altitude (why, years out)

| Skill | What it does |
|-------|-------------|
| `/charter` | Parent skill: walks VISION -> STRATEGY -> ROADMAP in one sitting; every run lands a STRATEGY and a ROADMAP unless you decline the roadmap when asked |
| `/vision` | Capture why a project should exist -- thesis, audience, org fit -- via scoping, research agents, and jury review |
| `/comp` | Survey competitors along explicit dimensions and turn the gaps into implications for your own choices. Private repos only: `/charter` runs it after `/vision` when the skill is installed, and says so when it skips. Warns if invoked directly in a public repo, where the result cannot be finalized |
| `/strategy` | Define a medium-term defensible bet that operationalizes a slice of a VISION, with a building-blocks decomposition and invalidation conditions |
| `/roadmap` | Sequence a strategy's features into one initiative with dependency tracking, and track how far along the work is; one feature is enough |

### Scope chain -- tactical altitude (single feature, framing to plan)

| Skill | What it does |
|-------|-------------|
| `/scope` | Parent skill: walks BRIEF -> PRD -> DESIGN -> PLAN in one sitting; produces PLAN as the terminal artifact |
| `/brief` | Frame a single feature's problem, outcome, user journeys, and scope boundary before requirements are written |
| `/prd` | Capture product requirements with numbered criteria through conversational scoping and parallel research |
| `/design` | Produce a technical design document by decomposing the problem into decision questions and evaluating trade-offs |
| `/plan` | Decompose a design doc, PRD, or roadmap into atomic, sequenced issues with dependency graphs and complexity labels |

### Execute chain -- implementation altitude (plan to merged code)

| Skill | What it does |
|-------|-------------|
| `/execute` | Parent skill: drives a finished PLAN to merged code, delegating each issue to `/work-on`; owns single-pr and coordinated multi-repo plans (a multi-pr plan runs under `/work-on` instead) |
| `/work-on` | Implement a GitHub issue, milestone, or full plan end-to-end: branch, analysis, code, three-panel review, tests, and pull request |

### Standalone skills

| Skill | What it does |
|-------|-------------|
| `/explore` | Fan out research agents to investigate options, then route you to where the work starts: an issue, `/charter`, `/scope`, or an existing plan |
| `/review-plan` | Adversarial review of a plan across scope, design fidelity, acceptance criteria, and sequencing (runs automatically inside `/plan`, so you don't need to invoke it directly; still callable on an existing plan) |
| `/decision` | Structured decision-making for contested choices with adversarial agents, cross-examination, and synthesis (also callable from inside `/design`) |
| `/release` | Recommend a version, generate release notes, draft a GitHub release, dispatch the release workflow, and monitor it |
| `/inflight` | Report this session's in-flight PRs across repos: number, state, CI and review status |

`/writing-style` runs automatically whenever shirabe drafts prose, so you don't
need to invoke it directly.

Skills chain together within each altitude, and each chain has a parent skill
that walks the whole thing in one sitting: `/charter` drives VISION ->
STRATEGY -> ROADMAP, `/scope` drives BRIEF -> PRD -> DESIGN -> PLAN, and
`/execute` drives a finished PLAN through `/work-on` for every issue.
`/explore` helps you figure out where to start if you're not sure which
altitude you need, and `/review-plan` runs inside `/plan` to catch problems
before issues get created.

## Documents

The skills that produce artifacts -- the ones in the prefix table below --
write Markdown with versioned frontmatter, a fixed set of required sections,
and a status field that moves through a defined lifecycle. The rest read those
artifacts and drive work off them. The frontmatter and sections are what
`shirabe validate` checks (see below), and they're what makes the chains
resumable: a `/execute` run picks up a PLAN by reading its status, and `/plan`
refuses to run against a DESIGN that isn't Accepted yet.

Artifacts come in two kinds. **Durable** artifacts serve as the audit trail:
VISION, STRATEGY, BRIEF, PRD, DESIGN, COMP. **Working** artifacts -- ROADMAP
and PLAN -- are not part of that audit trail; they exist to drive work, and the
completion cascade can retire them once it is done.

A durable artifact usually stays in `docs/` after the work ships, but there is
one way it leaves: `/scope` can fold it into the document below it. After each
child lands, the chain asks whether the upstream holds anything its successor
does not. Where it does not, the upstream's contribution is carried into the
survivor as one section and the upstream is removed, with the survivor
declaring what it absorbed in its frontmatter and its `## Status` line. That
judgment is only ever made against two documents that exist -- never against one
that has not been written.

Retirement is conditional, not automatic. A PLAN is `git rm`'d before its work
merges, while the PR is still a draft. A ROADMAP is only reached by the cascade
when a plan downstream of it finishes, and it is deleted only once every
feature on it is Done *and* every GitHub issue it references is closed; short
of that the cascade just updates the matching feature's progress. A ROADMAP that never gets planned against is
never visited by any cascade and stays on disk until someone removes it.

| Prefix | Produced by | Captures |
|--------|-------------|----------|
| `VISION-` | `/vision` | Thesis, audience, org fit, success criteria |
| `STRATEGY-` | `/strategy` | The defensible bet, building blocks, coordination dependencies, falsifiability |
| `ROADMAP-` | `/roadmap` | Feature sequencing, dependency graph, progress |
| `BRIEF-` | `/brief` | Problem statement, user outcome, user journeys, scope boundary |
| `PRD-` | `/prd` | Problem, goals, user stories, requirements, acceptance criteria |
| `DESIGN-` | `/design` | Decision drivers, considered options, chosen approach, security considerations |
| `PLAN-` | `/plan` | Decomposition strategy, issue outlines or an issues table, dependency graph, implementation sequence |
| `COMP-` | `/comp` | Competitive landscape, comparative matrix, implications for our own choices -- private repos only |

Artifacts reference each other through an `upstream:` frontmatter field.
Each one points at the nearest artifact actually produced above it, and omits
the field when nothing was. Not every artifact is always there, for two
reasons, and neither is a step someone decided to skip: you can invoke a child
directly rather than the parent, so a PRD written on its own has no BRIEF above
it, and a fold can remove an artifact after the fact. A chain run through
`/scope` walks all four of its children every time. The field records what the
chain really did, not an idealized shape.

What it never does is point downward or sideways. A BRIEF does not point at a
PRD, which is written from the brief's framing rather than the other way
round, and nothing on the strategic chain points into feature-level documents
at all. The ROADMAP is the boundary: the strategic chain hands off there, and
`/brief` is what crosses it. That
chain is what `/execute` walks after a plan's work merges: it transitions
each upstream node to its terminal status (DESIGN to Current, PRD to Done,
BRIEF to Done) and, if the chain traces back to a ROADMAP, updates that
roadmap's progress.

## Coordinated multi-repo

`/scope --coordinated` extends the chain across repositories, and `/execute`
drives the resulting coordinated plan: a single coordination PR is created up
front to hold the plan and its framing, per-repo work is grouped to the coarsest
legal unit and merged in a derived order, and the coordination PR merges last as
the one completion signal.
A non-bypassable merge-last gate (`shirabe validate --merge-gate`) enforces it in
CI -- the coordination PR cannot merge until every indexed per-repo PR has.
See [`docs/guides/coordinated-multi-repo.md`](docs/guides/coordinated-multi-repo.md)
for the end-to-end walkthrough, including how `--merge-gate` and
`--coordination-body` are used.

## Example: building a plugin system from scratch

Here's what it looks like to use shirabe for a non-trivial feature -- say you
need to add a plugin system to your CLI tool, but you're not sure where to start.

**Step 1 -- Explore.** You run `/explore plugin system` and describe what you're
thinking. shirabe spins up research agents that look at how your codebase is
structured, what plugin approaches exist, and what constraints matter. After a
few rounds of convergence it routes you: this is one coherent feature inside a
project that already exists, so the answer is `/scope`. It hands over what the
exploration settled so you don't answer the same questions twice.

**Step 2 -- Scope.** You run `/scope plugin-system`, and the tactical chain runs
as one conversation.

It opens with a **brief**: the problem, the outcome you want, the journeys that
exercise it, and where the feature ends. Then a **PRD** narrows that to concrete
requirements -- "plugins must be loadable from a directory", "plugins declare
capabilities via a manifest file" -- with research agents checking your codebase
for existing patterns and a three-agent jury reviewing the draft. Then a
**design** decomposes those requirements into decision questions: "how should
plugins be discovered?", "what's the manifest format?", "how do we handle
version conflicts?" Each gets a structured trade-off analysis with real
alternatives. Finally a **plan** breaks the design into atomic issues ordered by
dependency, each with acceptance criteria specific enough to verify
mechanically; `/review-plan` challenges it before any issues are created.

Every one of those four runs. After each lands, the chain asks whether the
document above it still holds anything the new one does not -- and folds it away
if not. So you might end up with all four, or with a PRD that carries the
brief's framing inside it. What you never get is a step skipped because
something guessed, before writing it, that it would not have been worth
reading. Each child is also invocable on its own if you already know the
altitude you want; that buys a shorter conversation, not a smaller set of
documents.

**Step 3 -- Implement.** If `/plan` created a GitHub milestone, you run
`/work-on M3`. shirabe picks the first unblocked issue, creates a branch,
analyzes the code, implements the change, runs it through a three-panel review
(completeness/justification/intent, then pragmatic/architect/maintainer, then
QA), and opens a PR. When that one merges, you run it again for the next
issue.

If `/plan` produced a self-contained PLAN doc instead, you hand the whole thing
to `/execute docs/plans/PLAN-plugin-system.md`. That mode runs the plan as a
batch: shirabe creates one shared branch and draft PR, spawns a child workflow
per issue with dependency-aware scheduling through `/work-on`, then walks the
plan's upstream chain (design, PRD, brief) while the PR is still a draft,
transitioning each to its terminal status and staging those changes as a final
commit. Only then does the PR flip to ready, so CI runs against the finalized
chain rather than ahead of it. Issues tagged `docs` or `task` skip the code-review panels so
documentation-only work doesn't pay for gates it doesn't need.

The whole process produces a paper trail -- PRD, design doc, plan, and focused
PRs -- that you can point to later when someone asks "why did we build it this
way?"

## Installation

Register the shirabe marketplace and install the plugin:

```bash
claude plugin marketplace add "tsukumogami/shirabe" --scope user
claude plugin install shirabe@shirabe --scope project
```

The first command registers the marketplace from GitHub (one-time per
machine). The second installs the plugin to the current project.

Once the marketplace is registered, you can also install from inside a
Claude Code session:

```
/plugin install shirabe@shirabe
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- `bash`. Every skill runs `scripts/skill-preflight.sh` through `bash` when it
  loads, and the rest of `scripts/` is bash too, so the plugin is not platform
  neutral. macOS and Linux always have it. Windows does not, unless Git Bash or
  WSL is on PATH -- without one of those the preflight line cannot run. The
  exposure is narrow because `install.sh` accepts only `linux` and `darwin`
  anyway, but it is real and it is stated rather than papered over.
- The `shirabe` binary -- skills call `shirabe validate` during ordinary runs,
  so install it before you use them (see [Local install](#local-install))
- [koto](https://github.com/tsukumogami/koto) for `/work-on` and `/execute`

Each skill declares the tools it calls in its own `skills/<name>/requires.tsv`,
and the preflight line checks that declaration when the skill loads. A satisfied
host sees nothing. An unmet prerequisite gets one plain-prose block naming the
tool, what is wrong, and the single command that fixes it on this machine. No
skill states a version floor: floors go stale silently, and a floor nobody
rechecks is worse than no floor at all.

## CLI and doc validation

shirabe ships a `shirabe` binary and a reusable GitHub Actions workflow so
downstream repos can validate their doc formats on every PR. The core
subcommand is `validate`, which understands all eight document formats above
(`DESIGN-`, `PRD-`, `VISION-`, `ROADMAP-`, `PLAN-`, `STRATEGY-`, `BRIEF-`,
`COMP-`) plus the required-frontmatter, status-enum, and required-section
checks that go with each. A handful of other subcommands support the skills
directly: `roadmap populate` fills in a roadmap's issues table and dependency
graph, `transition` moves a doc to a new status, `finalize-chain` walks a
finished plan's upstream chain the way `/execute` does, `plan outlines` reads a
single-PR plan's issue outlines out as JSON so the task extractor and the
validator share one parse of them, `slug-prefix-detect` checks a candidate slug
against your workspace's naming convention, and `install-hooks` wires up a
local pre-commit validation hook.

### Reusable workflow

Add this to `.github/workflows/validate-docs.yml` in your repo:

```yaml
name: Validate doc formats
on:
  pull_request:
    paths: ['docs/**']
jobs:
  validate:
    uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v0.6.0
```

The workflow checks out shirabe, builds the `shirabe` binary, diffs the PR's
changed files, and hands every changed path (minus test fixtures) to
`shirabe validate`. Selection happens inside the binary, not the workflow: it
matches on the filename prefix, e.g. `PLAN-*.md`, and a file whose name matches
no prefix is skipped silently. A file that does match a prefix but whose
`schema:` field is missing or unrecognized gets a `::notice` annotation instead
of a hard failure, so teams can adopt validation incrementally.

To allow custom status values beyond the built-in enum, pass a YAML map keyed
by schema version:

```yaml
    uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v0.6.0
    with:
      custom-statuses: |
        prd/v1: [Draft, Accepted, In Progress, Done, Delivered]
```

`COMP-` docs are private-only: `shirabe validate` rejects them outside a repo
whose visibility resolves to `private`. Visibility comes from a CLAUDE.md
header or from a `public`/`private` path component, and when neither resolves
it defaults to `private` -- so an undetermined repo is treated as private and
the check doesn't fire. Pass `--visibility` explicitly (the reusable workflow
does) if you want the check to run on its own. See
`docs/guides/doc-validation.md` for branch protection setup,
the COMP adoption notes, and migration notes for repos with existing docs.

### Local install

```bash
curl -fsSL https://raw.githubusercontent.com/tsukumogami/shirabe/main/install.sh | bash
```

Installs `shirabe` to `~/.shirabe/bin/`. Add that directory to `PATH`, then
run `shirabe validate docs/designs/DESIGN-foo.md`.

## Roadmap

- **koto integration for remaining skills** -- `/work-on` and `/execute` use
  koto for state-machine-enforced execution; the other skills will follow

## License

Apache 2.0

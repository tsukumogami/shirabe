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
| `/design` | Produce a technical design document by decomposing the problem into decision questions and evaluating trade-offs; for a feature whose requirements are already settled |
| `/plan` | Decompose a design doc, PRD, or roadmap into atomic, sequenced issues with dependency graphs and complexity labels |

### Execute chain -- implementation altitude (plan to pull requests)

| Skill | What it does |
|-------|-------------|
| `/coordinate` | Run a coordinator for a roadmap or a discipline rotation: reconcile what it inherited, dispatch one worker per unit through `/deliver`, `/work-on`, `/explore` or `/decision`, verify what each pushes before repeating it, and land it or hand it to a person as far as the workspace permits, keeping a record on GitHub that holds only what GitHub can't recompute |
| `/deliver` | Driver skill: scopes a topic with `/scope --intent=continue`, then executes its PLAN with `/execute --merge` in one session, so the run ends `merged` wherever the repository's rules let it merge (`--no-merge` stops at ready PRs); re-run it to pick a topic up where it stopped |
| `/execute` | Parent skill: drives a finished PLAN to ready PRs with passing CI, delegating each issue to `/work-on`, and merges them only when run with `--merge`; owns single-pr plans and coordinated plans in one repository or several (a multi-pr plan runs under `/work-on` instead) |
| `/work-on` | Implement a GitHub issue, the next unblocked issue on a milestone, or a task stated plainly, end-to-end: branch, analysis, code, three-panel review, tests, and pull request. Also runs a `multi-pr` plan, one issue at a time, each landing its own PR |

### Standalone skills

| Skill | What it does |
|-------|-------------|
| `/explore` | Fan out research agents on an open question -- feasibility included -- then route you to where the work starts: an issue, `/charter`, `/scope`, or an existing plan |
| `/review-plan` | Adversarial review of a plan across scope, design fidelity, acceptance criteria, and sequencing (runs automatically inside `/plan`, so you don't need to invoke it directly; still callable on an existing plan) |
| `/decision` | Settle one contested choice on the record -- three or more live options, evidence pointing both ways, or a call that is expensive to undo (also callable from inside `/design`) |
| `/release` | Recommend a version from what landed, check for blockers, generate release notes, draft a GitHub release, dispatch the release workflow, and monitor it |
| `/inflight` | Report this session's in-flight PRs across repos: number, state, CI and review status |

`/writing-style` runs automatically whenever shirabe drafts prose, so you don't
need to invoke it directly.

Skills chain together within each altitude, and each chain has a parent skill
that walks the whole thing in one sitting: `/charter` drives VISION ->
STRATEGY -> ROADMAP, `/scope` drives BRIEF -> PRD -> DESIGN -> PLAN, and
`/execute` drives a finished PLAN through `/work-on` for every issue.
`/deliver` runs `/scope` and then `/execute` back to back when you want a topic
taken from framing to its PRs without stopping in between.
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

## Coordinated efforts

When a plan's work splits into PRs that must land in order, in one repository
or across several, it can run in coordinated mode. `/plan` picks it for a split
when you pass `--coordinated`, when `/scope --intent=continue` (or `/deliver`)
forwards its intent, or when `CLAUDE.md` declares
`## PR Grouping Policy: coordinated`. A single coordination PR holds the plan
and its framing, each `(repo, group)` unit of work lands as its own PR on its
own branch in a derived order, and the coordination PR merges last as the one
completion signal. `/execute` drives the plan, and with `--merge` merges each PR
when the repository's rules allow it.
A non-bypassable merge-last gate (`shirabe validate --merge-gate`) enforces the
order in CI -- the coordination PR can't merge until every indexed PR has.
See [`docs/guides/coordinated-multi-repo.md`](docs/guides/coordinated-multi-repo.md)
for the end-to-end walkthrough, and
[`docs/guides/execute-friction.md`](docs/guides/execute-friction.md) for
`/deliver`, merging, and resuming a run.

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
- `bash`. Every skill runs `scripts/skill-preflight.sh`, a bash script, when it
  loads, and the rest of `scripts/` is bash too, so the plugin is not platform
  neutral. macOS and Linux always have it. Windows does not, unless Git Bash or
  WSL is on PATH -- without one of those the preflight line cannot run. The
  exposure is narrow because `install.sh` accepts only `linux` and `darwin`
  anyway, but it is real and it is stated rather than papered over.
- The `shirabe` binary -- skills call `shirabe validate` during ordinary runs,
  and the plugin's pre-action hook runs it on every guarded command, so
  install it before you use them (see [Local install](#local-install))
- [koto](https://github.com/tsukumogami/koto): `/scope`, `/execute`,
  `/deliver`, `/work-on`, and `/coordinate` require koto 0.31.0 or later.
  `.tsuku.toml` tracks the newest koto 0.x rather than pinning a release, so
  `tsuku install` never downgrades a newer koto you already have. 0.31.0
  records which rule a directive carries (`directive_rules`) and lets a
  captured value be empty (`capture_allow_empty`), which `/work-on`'s probe
  states use. 0.22.0
  records which session dispatched another (`koto session link
  --dispatched-by`, `koto init --dispatched-by`), which the chain and
  `/execute`'s children write, and answers whether a session may be reclaimed
  with `koto session hierarchy`. 0.21.0
  returns a passing check's warn-stage findings to the agent as advisories and
  journals check findings and disputes (tsukumogami/koto#393), so a rule at
  `warn` reaches the agent instead of behaving as `shadow`. 0.20.0 hands
  a decider-check criterion the decider couldn't answer back to the agent, who
  answers it with `koto decider answer`, where an older koto passed it
  unjudged; `/work-on`'s review-level check relies on it. 0.15.0 routes
  on a template variable's value and runs veto-only decider checks, which
  `/work-on`'s review level uses. 0.14.1 accepts
  `+` in `--var` values, so a plugin or checkout under a directory whose name
  carries `+` works (tsukumogami/koto#266). 0.14.0 is the release that keeps a
  session reaching a failure terminal and delivers a child's result whether or
  not its tick carried `--no-cleanup`, which is what lets every `koto next` in
  every skill carry that flag (see `references/koto-session-retention.md`).
  `/scope`, `/execute`, and `/deliver` also enter their session through
  `scripts/koto-open.sh`, which uses `koto init`'s entry flags (`--vars-file`,
  `--attach-live`, `--replace-terminal`, `--koto-leg`), first shipped in
  v0.13.0.

Each skill declares the tools it calls in its own `skills/<name>/requires.tsv`,
and the preflight line checks that declaration when the skill loads. A satisfied
host sees nothing. An unmet prerequisite gets one plain-prose block naming the
tool, what is wrong, and the single command that fixes it on this machine.
`requires.tsv` carries no version: floors go stale silently, and a floor
nobody rechecks is worse than no floor at all. Where a skill's koto floor shows
up as surface, it is declared as surface: the `koto init` records of `/scope`,
`/execute`, and `/deliver` name the four entry flags, so the preflight on a koto
older than 0.13.0 names the missing flags and the install route before the
skill does any work. What 0.14.0 added is behaviour rather than a flag, so the
preflight also compares one version, koto's, against the minimum
`scripts/assert-koto-floor.sh` defines, and tells you to upgrade koto when it is
below it. That file holds the one copy of the minimum, and every job that
installs koto from `.tsuku.toml` runs it to assert koto is at least the minimum.
`check-koto-entry-floor.yml` installs exactly the minimum release and runs every
template compile, the decider check, and the skills' koto-backed suites on it,
so the minimum stays tested. `scripts/koto-minimum-consistency_test.sh`
(`check-koto-minimum.yml`) fails when a document or workflow states a different
one.

### Upgrading from a koto older than 0.13.0

Sessions created by a koto older than 0.13.0 have no origin record, and v0.13.0
and later refuse to attach a session without one: `koto-open.sh` reports it as
`origin_mismatch` and prints koto's instruction to finish the session with the
koto that started it or remove it with `koto session cleanup <name>`. So a
`/scope` or `/execute` run that is still in flight when you upgrade can't be
resumed afterwards. Finish it on the old koto, or clean up its session
(`koto session cleanup scope-<topic>` or `koto session cleanup
execute-<plan-slug>`), before you upgrade. `/deliver` first shipped against
koto 0.13.0, so it has no older sessions of its own, but it resumes a topic through
`/scope` and `/execute` and can't pick up their old sessions either. There is
no automatic migration.

## What pull requests carry

The pull request titles, bodies and commit messages shirabe's skills write
describe the change and how it was verified, in terms a reader of your
repository understands. By default they leave out the workflow's own
records: review panel tables, override and verification-deferral notes,
session, state and ledger names, run records, and pointers to PLAN and ROADMAP
files, which are deleted when the work completes. Those records stay in the
run's koto session, where the skills and gates that need them read them.

To keep those records in your pull requests, opt in with one header in the
repository's `CLAUDE.md`, or in `CLAUDE.local.md` if your workspace manager
writes that file for you (niwa does, from the workspace configuration):

```markdown
## PR Workflow Content: include
```

`CLAUDE.local.md` is read before `CLAUDE.md`, and the first header that reads
`include` or `omit` wins. Any other value is ignored, so a typo leaves the
default in place. `scripts/pr-workflow-content.sh [<repository directory>]`
prints `include` or `omit` for a repository. It's the one reader every skill
and gate uses, so scripts of your own can ask it too. With the default,
`/work-on`'s and `/execute`'s pull request gate refuses a body that carries a
`## Review panel` table or a `Plan:` line; with `include`, the skills write
both as they always have.

## The pre-action hook

The plugin ships a Claude Code PreToolUse hook, `hooks/pre-action-deny.sh`,
that checks a Bash command before it runs. It denies a `gh pr create` or
`gh pr edit` whose title or body breaks a PR-body rule from
`references/pr-body-conformance.md` (a Conventional Commits title, one `---`
separator, no AI-attribution line, no heading in Part 1), and a `git push`
that would send a commit with an AI-attribution trailer. The deny names each
broken rule and where its full text is, so the agent can fix the command and
run it again. On a host opted into the live offload canary it lets the
Part 1 heading rule through, as `docs/guides/offload-live-canary.md` explains.

The checking is done by the `shirabe` binary, so install it with `install.sh`
(see [Local install](#local-install)); the hook looks for it on `PATH`, then at
`$HOME/.shirabe/bin/shirabe`. Without the binary, or with one older than the
plugin, the hook fails closed: it denies every command that names
`gh pr create`, `gh pr edit` or `git push`, with the install command in the
reason, and lets everything else through. A guarded command it can't see
through, such as a body read from a variable, is denied the same way.

The person running a host turns the hook off with `SHIRABE_PRE_ACTION_HOOK`
set to `off` in the `env` block of their Claude Code settings:

```json
{ "env": { "SHIRABE_PRE_ACTION_HOOK": "off" } }
```

`PR_BODY_HOOK_DISABLE=1` there turns off only the PR-body part and keeps the
push check. The hook's script reads that switch too, so on a host without the
binary the fail-closed deny above then covers only `git push`.

Both switches also cover `shirabe pr-body-hook`, the older entry point a host
can wire into its own settings. When a host does wire it, the plugin's hook
leaves the PR-body rules to that entry point, so each broken rule is reported
once.

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
tsuku install tsukumogami/shirabe
```

[tsuku](https://tsuku.dev) installs `shirabe` into `$HOME/.tsuku/tools/current/`
and checks the download against the release's checksums. A tsuku setup already
has that directory on `PATH`; when it doesn't, tsuku prints the line to add.
Without tsuku, use the install script:

```bash
curl -fsSL https://raw.githubusercontent.com/tsukumogami/shirabe/main/install.sh | bash
```

It installs `shirabe` to `$HOME/.shirabe/bin/`. Add that directory to `PATH`,
then run `shirabe validate docs/designs/DESIGN-foo.md`.

The pre-commit hook that `shirabe install-hooks` writes resolves `shirabe` on
`PATH` only. It doesn't look in `$HOME/.shirabe/bin/` unless that directory is
on `PATH`, so a binary installed there but left off `PATH` means the hook skips
validation.

## Roadmap

- **koto integration for remaining skills** -- `/work-on` and `/execute` use
  koto for state-machine-enforced execution; the other skills will follow

## License

Apache 2.0

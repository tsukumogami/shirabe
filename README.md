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
| `/strategy` | Define a medium-term defensible bet that operationalizes a slice of a VISION, with a building-blocks decomposition and invalidation conditions |
| `/roadmap` | Sequence multiple features into one initiative with dependency tracking and sequencing rationale |

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
| `/execute` | Parent skill: drives a finished PLAN to merged code, delegating each issue to `/work-on`; owns single-repo and coordinated multi-repo runs |
| `/work-on` | Implement a GitHub issue, milestone, or full plan end-to-end: branch, analysis, code, three-panel review, tests, and pull request |
| `/review-plan` | Adversarial review of a plan across scope, design fidelity, acceptance criteria, and sequencing, before issues get created |

### Standalone skills

| Skill | What it does |
|-------|-------------|
| `/explore` | Fan out research agents to investigate options and figure out which artifact to produce next |
| `/decision` | Structured decision-making for contested choices with adversarial agents, cross-examination, and synthesis (also callable from inside `/design`) |
| `/comp` | Private-only competitive-analysis artifact comparing competitors along explicit dimensions; refuses to run in public repos |
| `/release` | Recommend a version, generate release notes, draft a GitHub release, dispatch the release workflow, and monitor it |
| `/inflight` | Report this session's in-flight PRs across repos: number, state, CI and review status |

`/writing-style` runs automatically whenever shirabe drafts prose, so you don't
need to invoke it directly.

Skills chain together within each altitude, and each chain has a parent skill
that walks the whole thing in one sitting: `/charter` drives VISION ->
STRATEGY -> ROADMAP, `/scope` drives BRIEF -> PRD -> DESIGN -> PLAN, and
`/execute` drives a finished PLAN through `/work-on` for every issue.
`/explore` helps you figure out where to start if you're not sure which
altitude you need, and `/review-plan` catches problems in a plan before issues
get created.

## Documents

Every skill above produces a Markdown artifact -- versioned frontmatter, a
fixed set of required sections, and a status field that moves through a
defined lifecycle. That's what `shirabe validate` checks (see below), and it's
what makes the chains resumable: a `/execute` run picks up a PLAN by reading
its status, and `/plan` refuses to run against a DESIGN that isn't Accepted
yet.

Artifacts come in two kinds, and the difference explains why some of them
vanish. **Durable** artifacts stay in `docs/` after the work ships and serve as
the audit trail: VISION, STRATEGY, BRIEF, PRD, DESIGN, COMP. **Working**
artifacts exist only while their job is in flight -- ROADMAP and PLAN -- and
the completion cascade deletes them once their features are done. That is why
a chain producing a ROADMAP is cheap: it is a scratch document with a
lifecycle, not a permanent record.

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

Artifacts reference each other through an `upstream:` frontmatter field, so a
PLAN points back to its DESIGN, which points back to its PRD, and so on. That
chain is what `/execute` walks after a plan's work merges: it transitions
each upstream node to its terminal status (DESIGN to Current, PRD to Done,
BRIEF to Done) and, if the chain traces back to a ROADMAP, updates that
roadmap's progress.

## Coordinated multi-repo

`/scope --coordinated` and `/work-on --coordinated` extend the chain across
repositories: a single coordination PR is created up front to hold the plan and
its framing, per-repo work is grouped to the coarsest legal unit and merged in a
derived order, and the coordination PR merges last as the one completion signal.
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
few rounds of convergence, it recommends producing a PRD first (since you
haven't nailed down requirements yet) and a design doc after.

**Step 2 -- Requirements.** You run `/prd plugin system`. Through a
conversational scoping phase, shirabe narrows the feature to concrete
requirements: "plugins must be loadable from a directory", "plugins declare
capabilities via a manifest file", etc. Parallel research agents check your
codebase for existing patterns. A 3-agent jury reviews the draft for
completeness and consistency.

**Step 3 -- Design.** You run `/design docs/PRD-plugin-system.md`. shirabe
decomposes the PRD into decision questions: "how should plugins be discovered?",
"what's the manifest format?", "how do we handle version conflicts?" Each
question gets a structured trade-off analysis with alternatives. The final
design doc captures the chosen approach with rationale.

**Step 4 -- Plan.** You run `/plan docs/DESIGN-plugin-system.md`. shirabe
breaks the design into atomic issues, ordered by dependency. A walking skeleton
issue comes first so you can validate the end-to-end flow early. Each issue gets
acceptance criteria specific enough to verify mechanically. `/review-plan` then
challenges the plan before any issues are created -- catching gaps in scope,
weak acceptance criteria, or sequencing problems.

**Step 5 -- Implement.** If `/plan` created a GitHub milestone, you run
`/work-on M3`. shirabe picks the first unblocked issue, creates a branch,
analyzes the code, implements the change, runs it through a three-panel review
(completeness/justification/intent, then pragmatic/architect/maintainer, then
QA), and opens a PR. When that one merges, you run it again for the next
issue.

If `/plan` produced a self-contained PLAN doc instead, you hand the whole thing
to `/execute docs/plans/PLAN-plugin-system.md`. That mode runs the plan as a
batch: shirabe creates one shared branch and draft PR, spawns a child workflow
per issue with dependency-aware scheduling through `/work-on`, and once CI
passes on the ready PR it walks the plan's upstream chain (design, PRD, brief),
transitions each to its terminal status, and pushes those changes as a final
commit on the same PR. The PR then merges with the upstream artifacts already
transitioned. Issues tagged `docs` or `task` skip the code-review panels so
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
- [koto](https://github.com/tsukumogami/koto) >= 0.2.1 (for `/work-on`;
  installed automatically if missing)

## CLI and doc validation

shirabe ships a `shirabe` binary and a reusable GitHub Actions workflow so
downstream repos can validate their doc formats on every PR. The core
subcommand is `validate`, which understands all eight document formats above
(`DESIGN-`, `PRD-`, `VISION-`, `ROADMAP-`, `PLAN-`, `STRATEGY-`, `BRIEF-`,
`COMP-`) plus the required-frontmatter, status-enum, and required-section
checks that go with each. A handful of other subcommands support the skills
directly: `roadmap populate` fills in a roadmap's issues table and dependency
graph, `transition` moves a doc to a new status, `finalize-chain` walks a
finished plan's upstream chain the way `/execute` does, `slug-prefix-detect`
checks a candidate slug against your workspace's naming convention, and
`install-hooks` wires up a local pre-commit validation hook.

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
changed files, and runs `shirabe validate` on any recognized doc file (matched
by filename prefix, e.g. `PLAN-*.md`). Files without a `schema:` field, or with
one the validator doesn't recognize, are skipped with a `::notice` annotation
rather than a hard failure, so teams can adopt validation incrementally.

To allow custom status values beyond the built-in enum, pass a YAML map keyed
by schema version:

```yaml
    uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@v0.6.0
    with:
      custom-statuses: |
        prd: [Draft, Accepted, In Progress, Done, Delivered]
```

`COMP-` docs are private-only: `shirabe validate` rejects them outside a repo
whose visibility resolves to `private`, and fails closed if visibility can't be
determined. See `docs/guides/doc-validation.md` for branch protection setup,
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

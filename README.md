# shirabe (調べ)

Structured workflow skills for AI coding agents.

shirabe is a [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
plugin that adds multi-phase workflows for the thinking that happens *before*
coding. Instead of jumping straight from idea to implementation, shirabe guides
you through research, requirements, design, planning, and review -- each with
built-in validation gates so nothing important gets skipped.

**Pronunciation:** shee-RAH-beh

## Skills

| Skill | What it does |
|-------|-------------|
| `/explore` | Fan out research agents to investigate options and figure out which artifact to produce next (PRD, design doc, plan, or something else) |
| `/prd` | Capture product requirements with numbered criteria through conversational scoping and parallel research |
| `/design` | Produce a technical design document by decomposing the problem into decision questions and evaluating trade-offs |
| `/decision` | Structured decision-making for contested choices with adversarial agents, cross-examination, and synthesis |
| `/plan` | Decompose a design doc or PRD into sequenced GitHub issues with dependency graphs and complexity labels |
| `/review-plan` | Adversarial review of a plan across scope, design fidelity, acceptance criteria, and sequencing |
| `/work-on` | Implement a GitHub issue end-to-end: branch, analysis, code, tests, and pull request |

Skills are designed to chain together. `/explore` helps you figure out what you
need, then hands off to `/prd`, `/design`, or `/plan`. `/review-plan` catches
problems in a plan before issues get created. `/work-on` picks up individual
issues and delivers PRs.

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

**Step 5 -- Implement.** You run `/work-on M3` (the milestone). shirabe picks
the first unblocked issue, creates a branch, analyzes the code, implements
the change, runs tests, and opens a PR. When that one merges, you run it again
for the next issue.

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

## Roadmap

shirabe currently enforces workflow structure through skill prompts and
phase-gated instructions. Planned improvements include:

- **[koto](https://github.com/tsukumogami/koto) integration** -- formal state
  machine enforcement for workflow transitions, so agents physically can't skip
  steps they haven't earned access to
- **CI validation workflows** -- reusable GitHub Actions that validate design
  docs and plans in pull requests
- **Cross-repo workflow state** -- track multi-repo features through a shared
  workflow state

## License

Apache 2.0

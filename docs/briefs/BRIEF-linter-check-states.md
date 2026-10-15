---
schema: brief/v1
status: Accepted
problem: |
  The title and body an agent writes for a pull request become the commit
  message on main, yet no writing-style rule is checked against them. The
  pull request gate already runs `shirabe validate --pr-body`, but only for
  structure, so a banned word there is caught by a reviewer or not at all.
outcome: |
  An agent opening a pull request through /work-on or /execute is held at the
  pull request gate when its title or body uses a banned word, and is told the
  word, the registry rule id and where the rule's text is. Maintainers can
  count those holds per rule from koto's check events.
motivating_context: |
  shirabe is moving rules out of an agent's default context and behind
  deterministic checks that return the rule only when it's broken. A rule can
  only be considered for that once a check holds the run on it. Documents
  under docs/ already have one for the banned words (FC10, gated at every
  /scope hop); the pull request text, the other prose a run publishes, does
  not. Whether that check should come from external linters (Vale for prose,
  commitlint for commit messages) or from `shirabe validate` was left open
  and has to be settled first.
---

# BRIEF: linter check states

## Status

Accepted

## Problem Statement

A /work-on or /execute run publishes two kinds of prose. Documents under
`docs/` are checked against the writing-style rules in
`skills/writing-style/rules.yaml`: `shirabe validate` reports banned words as
FC10, and /scope holds every hop on them. The pull request is the other kind,
and nothing checks its prose. shirabe squash-merges, so the title and Part 1
of the body become the commit message that lands on main, and Part 2 stays on
the pull request as the record reviewers read.

The pull request already has a check state. Both workflows hold the run at the
pull request gate (`work-on:pr_creation`, `execute:pr_finalization`) until
`check-pr-output.sh --pr-body` passes, and that script runs
`shirabe validate --pr-body` and returns each finding to the agent under a
registry rule id. But the checks it runs are structural: a Conventional
Commits title, one separator, no AI attribution, no heading in Part 1. The
banned words reach the pull request only as guidance preloaded into the
agent's context, and as whatever a reviewer happens to notice.

That has two costs. A banned word in a pull request title or body reaches main
whenever the agent misses it and the reviewer does too. And because no check
holds the run on that rule, the guidance can never be moved out of default
context and delivered only when it's broken, which is the direction shirabe's
workflows are taking with every rule that has a deterministic check.

There is also a choice nobody has made. The obvious tools for prose and commit
messages are external linters: Vale for writing style, commitlint for commit
messages. shirabe's `CLAUDE.md` says new correctness checks belong in
`shirabe validate`, and shirabe ships into the tsuku ecosystem, whose package
manager exists so a user needs no system dependencies beyond it. Until that
is settled, the check has no agreed home.

## User Outcome

An agent running /work-on or /execute writes a pull request and is held at
the gate when the title or body uses a banned word. The finding names the
word, carries the registry `rule_id` and a `rule_ref` pointing at the rule's
text, and says what to use instead, so the agent fixes it with `gh pr edit`
and ticks again without anyone reading the body by hand. A pull request that
reaches review has already passed the writing-style rules its documents pass.

A maintainer reading koto's exported check events can count how often each
writing-style rule holds a run at the pull request gate, by rule id, the same
way they count the structural pull request rules today. The registry entry
names the check, so the rule is one a later feature can consider moving out
of default context, though this feature doesn't move it.

## User Journeys

### A /work-on agent opens a pull request with a banned word

A /work-on run finishes an issue and the agent opens its pull request. Part 1
of the body says the change will `leverage` the existing cache. The
`pr_creation` gate runs and holds the state with one finding under
`pr-body/banned-word`, naming `leverage`, the line it's on, the plain verb the
rules suggest and a pointer to the rule's text in `rules.yaml`. The agent
edits the body with `gh pr edit`, submits again, and the run moves on to CI.

### /execute finalizes a plan's pull request by its title

/execute is landing a plan whose issues share one branch, and the pull
request it finalizes was written once for the whole plan rather than per
issue. Its body is clean, but the title, which becomes the commit subject on
main, calls the change "a `seamless` migration". At `pr_finalization` the gate
reads that pull request through the ownership filter, not the checked-out
branch, and holds on the title alone. A plan's pull request gets the check a
single issue's gets, and the finding says it is the title, not a body line.

### A maintainer counts writing-style breaks per rule

A maintainer wants to know how often agents break the writing-style rules in
pull requests, and whether that changes when the guidance is trimmed later.
They query koto's exported gate events for `pr-body/banned-word` and get a
count per run and per template version, beside the counts for
`pr-body/no-heading-in-part1` and the other pull request rules. No log
parsing, because each finding carries its registry id.

### A maintainer of an adopting repository declares a term of art

The maintainer of a repository that installs shirabe has declared `tier` in
its `CLAUDE.md` under `## Prose Vocabulary:` because the word names a pricing
level there. When the repository's agents open pull requests that use `tier`,
the gate doesn't fire on it, the same as for its documents. The maintainer's
own CI, which calls shirabe's reusable pull-request-body workflow, reports
exactly what it reported before: the new check runs in the workflow gate, not
in that CI job.

## Scope Boundary

**IN:**

- A recorded answer to where the check lives: external linters (Vale and
  commitlint) or `shirabe validate`. The choice is made in the design, with
  its alternatives and reasons, before anything is built.
- The banned words from `rules.yaml` checked against the pull request title
  and body at the existing pull request gate in /work-on and /execute, with
  the repository's declared prose vocabulary honored.
- Findings returned to the agent with the registry `rule_id`, a `rule_ref`
  to the rule's text, the offending word and its location.
- A registry entry for the new rule, linked to the script that checks it,
  with the registry check passing and the rule not eligible to withhold.

**OUT:**

- Withholding any rule from default context. This feature only adds the
  check a later decision would rely on.
- Em-dash density on pull request bodies. It is a per-document rate with a
  300-word floor, and most pull request bodies are shorter than that.
- The judgment-only writing-style rules (vague attribution, empty
  conclusions and the rest). No matcher decides them.
- Commit messages on the feature branch. Squash merge discards them, and
  their subjects already pass a deterministic Conventional Commits check
  (`commit/conventional-subject`).
- Changing what shirabe's reusable pull-request-body CI workflow checks for
  adopting repositories.
- Returning a rule's text in escalating steps as attempts accumulate, and a
  check's shadow-warn-block lifecycle. Both are later features.
- Matching evasions such as homoglyphs or zero-width characters. The prose
  rules match ASCII literally, as they do for documents.

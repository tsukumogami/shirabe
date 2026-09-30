---
schema: brief/v1
status: Draft
problem: |
  /work-on and /execute already ship validators for their output, but most of
  them run in CI or not at all, and several states ask the agent to copy a
  script's verdict into an answer field. The record then holds the agent's word
  for results a script could have settled, and a wrong copy passes silently.
outcome: |
  A maintainer reading a /work-on or /execute run finds every checkable verdict
  settled by koto itself, in the state that produces the output, with the
  failing check named. Agents stop reporting what scripts already know.
motivating_context: |
  The contradiction-settlement work (#507) settled which prose rules win, and the
  review-panel shadow trial (#563) started measuring cheaper review. Both point
  at the same gap: a verdict the workflow records should come from the check
  that decides it, not from the agent that ran it.
---

# BRIEF: Output Gates

## Status

Draft

## Problem Statement

/work-on and /execute produce four kinds of output a reviewer later trusts: the
commits on the branch, the pull request's title and body, the result of the
repository's verification commands, and the verdicts of the review panels.
shirabe already ships checks for most of these. `shirabe validate --pr-body`
checks the title and body, a Conventional Commits pattern checks commit
subjects, `node-push.sh` checks that no `wip/` file and no private-repository
marker reaches a public branch, and the panel reviewers write a findings count.

Those checks mostly don't run where the output is made. The PR-body check runs
in CI after the pull request is open. The commit check looks at the tip commit
only. The `wip/` and visibility checks run only on /execute's coordinated path.
And in several states the agent runs a script, reads its result, and submits
that result as evidence: the verification state takes a `commands_run` string
and a `passed` outcome from the agent, each review panel takes the agent's
`passed` next to a context key whose only check is that it exists, and
/work-on's CI state takes a `session_role` the agent copied from a script.

A verdict the agent copies is a verdict nobody checked. It costs tokens to
produce, it can be wrong without anything noticing, and it leaves no record of
which rule failed when it is right. The problem isn't missing validators; it's
that the workflow takes the agent's word for what they said.

## User Outcome

A maintainer who reads a finished run sees, for each piece of output, the check
that settled it, run by koto in the state that produced the output, and on a
failure the rule that failed. Where a script can decide, the agent never
submits the answer. Where only judgment can decide, as with the review panels,
koto recomputes the verdict from what the reviewers found rather than reading
a pass flag someone set.

An agent running /work-on or /execute answers fewer questions. It fixes what a
gate reports and ticks again, rather than transcribing results.

## User Journeys

**A maintainer audits a merged change.** A maintainer wants to know whether a
/work-on pull request was verified before it opened. They read the session's
gate events and find the verification state's command gate, the map entry it
ran, and its exit code, rather than a sentence the agent wrote about what it
ran.

**An agent's PR body breaks the template.** An agent running /execute writes a
body with two `---` separators. The finalization state's gate runs
`shirabe validate --pr-body` on the body as written and holds the run in place,
naming the PB2 finding, before CI ever sees the pull request. The agent fixes
the body and ticks again.

**A review panel reports a blocking finding and a pass.** A panel writes a
results file whose findings list holds one blocking finding and whose `passed`
field says true. The panel gate recomputes the verdict from the findings list
and routes the run back to implementation, whatever the file claims.

**A repository has no verification map.** /work-on reaches verification in a
repository that never committed a machine-readable map. The run stops with a
"no verification map" finding instead of passing on the agent's report that
tests ran.

**A later decider joins a panel.** When the review-panel shadow trial moves
in-run, its decider check is added to the same state as the panel gate in
shadow mode. Because a shadow check never blocks, adding it can't change a
panel outcome.

## Scope Boundary

**In:**

- Gates in /work-on's and /execute's koto templates that run a check shirabe
  ships today, or a small script this feature ships, in the state that
  produces the output being checked.
- Replacing each state where the agent copies a script's verdict into an
  answer field with one koto settles itself.
- A repository-owned, machine-readable verification map that koto runs, and a
  refusal when a repository has none.
- Panel-verdict gates that recompute pass from the findings, and a named slot
  for a later decider check beside them.
- Marking which gates wait on a rule the contradiction-settlement work is
  still settling, and on which rule.

**Out:**

- Withholding or removing any prose rule from the skills' default context.
  Prose describing a check stays until later withholding work removes it.
- Letting any gate, decider or pass skip or replace a review panel.
- Any change to koto, and any request for a koto release. The feature uses
  koto features that are already merged and names the release that carries
  them.
- Building the decider check itself; only its slot is named.
- The `shirabe validate` subcommands planned elsewhere; gates call the
  validators as they ship today.
- /scope, /deliver and the other skills' templates.

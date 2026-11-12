---
schema: design/v1
status: Draft
problem: |
  work-on's closing_keyword gate at pr_creation accepts only a pull request
  body that closes its issue. A pull request that delivers one planned step
  of its issue, or follows an approved deferral, references the issue
  without closing it, so the gate exits 1 and the run ends at done_blocked
  instead of going on to CI monitoring.
---

# DESIGN: work-on partial delivery

## Status

Draft

## Context and Problem Statement

work-on's `pr_creation` state runs a `closing_keyword` gate on the pull
request it just opened. For an issue in the same repository the gate greps the
body for `close`, `fix` or `resolve` (in any of their forms) followed by
`#N`. For an issue in another repository it runs
`skills/work-on/scripts/check-closing-keyword.sh`, which wants the qualified
form `owner/repo#N` and refuses a reference that would close the wrong issue.
Either way, a body that only references the issue fails with exit 1, and the
transition on that exit sends the run to `done_blocked` rather than to
`ci_monitor`. No variable, evidence field or flag changes what the gate asks
for. The only runs it skips are free-form runs with no issue number and
`/execute` children on a shared branch, which open no pull request of their
own.

That's right for the common case, and wrong for two others.

The first is an issue delivered in more than one pull request on purpose.
#1735 is step one of #1646's two steps: it lands the validator and transition
side, and the second step can only merge after a release carries the first.
Its body says `Refs #1646`, because #1646 stays open until the second step
lands. The gate exited 1 on that body at `pr_creation` (#1736). Nothing in
#1646's criteria was set aside; the split was the plan from the start.

The second is a run that holds an approved deferral. A run that can't meet one
of its issue's acceptance criteria asks at `deferral_approval`, and a person
approves or rejects setting it aside. When it's approved, the pull request
should reference the issue without closing it, since the deferred criterion is
still open there. #1549 did that (`Part of #1548`) after its deferral was
approved, and the gate exited 1 anyway (#1550). The approval was already
reviewed earlier in the same run, but the gate doesn't read it.

In both cases the run's honest body can't pass. The way past is to write
`Fixes #N` only to satisfy the gate, which closes an issue that's still partly
open, or to stop the run at `done_blocked` and finish it by hand.

This design works out how a run declares that its pull request doesn't close
its issue, who may make that declaration, what the gate then accepts and
refuses on both the same-repository and cross-repository paths, and how the
deferral case enters through the same mechanism or why it doesn't.

Out of scope: closing the issue when its last step lands, which keeps using
the ordinary closing keyword; `/execute`'s shared-branch path and `multi-pr`
plans; free-form runs with no issue number; and any change to which keywords
count as closing or to the cross-repository old-name lookups.

## Decision Drivers

- **Both cases, or a stated reason.** The planned split (#1735, #1736) and the
  approved deferral (#1549, #1550) fail at the same gate on the same kind of
  body. A mechanism keyed only on the deferral record misses the split, which
  has no deferral.
- **No self-reported deferral.** The template doesn't let a run set an
  acceptance criterion aside on its own say; that only happens through
  `deferral_approval`. A declaration that an issue stays open mustn't become a
  second way around that rule.
- **The declaration exists before `pr_creation`.** A gate is a command over
  the run's template variables. It can't read evidence submitted on the same
  tick, so whatever the gate consults has to be recorded before the run enters
  the state.
- **A declared run still has a body rule.** Dropping the closing keyword
  requirement shouldn't leave the body free to say nothing about the issue, or
  free to close it after all.
- **Both gate paths.** The same-repository inline check and the
  cross-repository script both need the new behavior, whether they stay
  separate or merge.
- **The existing contracts hold.** The script's exit codes (0 passes, 1
  refuses, 2 is a usage error, 3 is a failed lookup) and the routes on them
  stay. `closing-keyword-gate_test.sh` pulls the gate command out of the
  template and runs it against a `gh` stub, and it has to keep working.
- **The text moves with the behavior.** The `pr_creation` directive, the
  `done_blocked` failure reason, `references/phases/phase-6-pr.md`,
  `references/finishing-obligations.md` and the SKILL.md passages on the
  closing obligation describe what the gate wants, so they change with it.

## Considered Options

Not written yet.

## Decision Outcome

Not written yet.

## Solution Architecture

Not written yet.

## Implementation Approach

Not written yet.

## Security Considerations

Not written yet.

## Consequences

Not written yet.

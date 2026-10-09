---
schema: prd/v1
status: Done
problem: |
  /work-on and /execute ship validators for their own output, but those
  validators mostly run in CI or not at all, and several states ask the agent to
  copy a script's verdict into an answer field. The session record then holds
  the agent's word for results a script decides, a wrong copy passes silently,
  and a failure records no rule.
goals: |
  Every checkable verdict about a run's output is settled by koto in the state
  that produces the output, by a check that ships in shirabe, with the failing
  rule named in koto's own gate events. The agent answers only what needs
  judgment.
absorbed:
  - docs/briefs/BRIEF-output-gates.md
---

# PRD: Output Gates

## Status

Done

Absorbed [BRIEF-output-gates](docs/briefs/BRIEF-output-gates.md); carried in Absorbed Brief.

## Absorbed Brief

The feature exists so that the verdicts a /work-on or /execute run records
about its own output come from the checks that decide them. The brief framed
the gap as one of placement, not of missing validators: shirabe already ships
checks for commits, pull request bodies, `wip/` hygiene and visibility, but
they run in CI or only on one path, and several states take the agent's copy
of a script's result as evidence. This document's Problem Statement states
that in full.

The outcome it asked for is a maintainer reading a finished run who finds each
checkable verdict settled by koto in the state that produced the output, with
the failing rule named, and an agent that fixes what a gate reports instead of
transcribing results. That is this document's Goals. Its five journeys (an
audit of a merged change, a malformed PR body caught before CI, a panel whose
pass flag contradicts its findings, a repository with no verification map, and
a decider joining a panel later) are the User Stories.

Its boundary kept the feature to gates in the two skills' templates, running
shipped checks or small new scripts, and pushed out prose withholding, any
panel skip, koto changes, the decider itself and the other skills' templates.
Those are this document's Out of Scope. It was written as the
contradiction-settlement work (#507) settled which prose rules win and the
review-shadow trial (#563) began measuring cheaper review; both depend on a
recorded verdict coming from the check that decides it.

## Problem Statement

/work-on and /execute are shirabe's two implementation skills. Each runs as a
koto workflow and produces output a reviewer later trusts: commits, a pull
request title and body, the result of the repository's verification commands,
and the verdicts of three review panels. shirabe ships checks for most of this
output. `shirabe validate --pr-body` checks a title and body against the
template (PB1 to PB4, PB3 being the AI-attribution rule). A Conventional
Commits pattern checks a commit subject. `node-push.sh` refuses a push whose
tree holds `wip/` files or whose commits carry private-repository markers.

Where those checks run is the problem. The PR-body check runs in CI, after the
pull request exists. The commit check reads the tip commit only. The `wip/` and
visibility checks run only on /execute's coordinated path. And in several
states the agent runs a script and then submits its result as evidence:

- /work-on's `verification` takes `verification_outcome` and a free-text
  `commands_run` from the agent, and the agent also decides which commands the
  map selects.
- /work-on's `scrutiny`, `review` and `qa_validation` take the agent's
  `*_outcome: passed`, next to a gate that only checks a results key exists.
  The results file carries a `passed` field and a `blocking_count` the agent
  writes.
- /work-on's `ci_monitor` takes a `session_role` copied from
  `session-role.sh`, and `staleness_check` takes a `staleness_signal` that
  restates `check-staleness.sh`'s exit status.
- /execute's `pr_finalization` and `ci_monitor` take `pr_adopt` and
  `status_read` outcomes that restate `owned-pr.sh`'s exit status, and
  `finalization_status: updated` that restates whether `gh pr edit` succeeded.

Each of these is a verdict nobody checked. It costs the agent a turn, it can be
wrong without anything noticing, and when it is right the record says nothing
about which rule failed.

## Goals

- A check that can decide a verdict decides it, in koto, in the state that
  produces the output, not in CI afterwards and not through the agent.
- Where only judgment decides, as with the review panels, koto still settles
  the part that is mechanical: whether the findings contain a blocking one.
- A failure names the rule that failed, through koto's own gate events, so an
  audit reads the rule rather than the agent's paraphrase.
- The work lands without waiting on anything but the rules it touches.

## User Stories

- As a maintainer auditing a merged /work-on pull request, I want the
  verification state's record to show which commands ran and their exit codes,
  so that I can tell verification happened without trusting a sentence.
- As an agent running /execute, I want the finalization state to hold me in
  place on a malformed PR body with the PB finding named, so that I fix it
  before CI reports it.
- As a maintainer, I want a panel's verdict recomputed from its findings, so
  that a results file claiming a pass over a blocking finding can't advance the
  run.
- As a maintainer of a repository without a verification map, I want /work-on
  to refuse verification with a clear finding, so that "no map" never reads as
  "verified".
- As the owner of the review-offload trial, I want a named slot for a decider
  check beside each panel gate, so that adding one later can't change a panel
  outcome.

## Requirements

### Functional

**R1. Gates run shipped checks, called as they ship.** Every gate this feature
adds runs a check that exists in shirabe today, invoked the way it is invoked
today (same command, same flags, same exit convention), or a small script this
feature ships with its own test. The design names, per gate, the exact command
and its exit convention. The `shirabe validate` work planned elsewhere is not a
dependency.

**R2. Copied verdicts are replaced.** Each state where the agent submits a
value that restates a script's result is replaced by a state koto settles
itself: a command gate the transitions route on, a `default_action` whose
result the gates read, or a decider check. The design lists every such state
with its before and after. After the change, no transition in /work-on or
/execute routes on an agent-submitted field whose value a shipped script
already decides.

**R3. Pull-request output is gated where it is written.** /work-on's
`pr_creation` and /execute's `pr_finalization` run `shirabe validate --pr-body`
with the title over the pull request as GitHub has it, and route on its exit
status. Whether the same states also run a public-content check is a design
question: the shipped marker check was built for cross-visibility pushes, and
the design decides whether it can run over a public repository's own commits
without firing on content that legitimately documents the markers.

**R4. Commit output is gated over every commit.** The commit convention check
runs over every commit the run made (`impl_base..HEAD` in /work-on, the
settled branch's commits in /execute), not only the tip. The same walk
refuses a commit whose trailers attribute it to an AI assistant (a
`Co-Authored-By:` line naming one, or a generated-with line), using a new,
small script with its own test.

**R5. wip hygiene is gated before a pull request is presented.** The state
that opens or finalizes the run's own pull request (/work-on's step before
`pr_creation`, /execute's `pr_finalization`) refuses a head whose tree holds
any path under `wip/`, using the same `git ls-tree` check `node-push.sh` runs.
A /work-on child on /execute's shared branch opens no pull request of its own
and leaves the check to /execute.

**R6. Verification gets a real gate.** The verification map is owned by the
target repository: a machine-readable file committed beside its shirabe
extension config, never produced during a run. koto selects the map's entries
for the run's changed paths and runs their commands itself, and the state
routes on their exit codes. The agent does not write the map, does not choose
the commands, and does not report the result; `commands_run` stops being
evidence.

**R7. Verification's unattended limits are stated.** The design says which map
commands koto may run unattended and how commands longer than koto's
per-command limit, or needing the network, run. A command the map marks as not
unattended is not run by koto and routes to a human decision.

**R8. A repository with no map is refused.** When the target repository has
no verification map, verification fails closed with a "no verification map"
finding. It never passes.

**R9. Panel gates check what a verdict says.** The gates on `scrutiny`,
`review` and `qa_validation` read the panel's results file and recompute pass
from its findings list: the panel passes exactly when no finding is at a
blocking severity. Any `passed` or `blocking_count` field the writer set is
ignored. The design says where results files live.

**R10. A slot for the decider.** The design names, per panel state, the slot
for a later decider check: a `decider-check` gate in shadow mode in the same
state as the panel gate, fed the criteria of the review-shadow trial. This
feature does not build it. Because a shadow check never blocks, adding it
later can't change a panel outcome.

**R11. Gates use koto's own events.** Gate name, state, attempt counts and the
failure payload come from koto's gate events (`gate_evaluated`,
`default_action_executed`). A gate script supplies rule ids only by printing
koto's `::koto-finding::` lines. A finding's `rule_id` is a stable name for
the rule it enforces, one a later rule registry can adopt unchanged and that
never changes once emitted; the rule's source-location key (`path#Lx-Ly` at a
commit) goes in the finding's `rule_ref`. A gate whose non-zero exit is a
route rather than a violation prints no finding. No gate adds a field of its
own to an event.

**R12. Gates that touch an unsettled rule wait on that rule only.** Each gate
that depends on a rule the contradiction-settlement work (#507) has not yet
settled is marked with the rule it waits on, and nothing else waits on that
work. The design records where each rule a gate reads was settled.

### Non-functional

**R13. The gates work on a released koto.** The design names the koto
version it needs, which must be a released one carrying failure findings,
attempt counts and gate polling (koto#290 and koto#292), and this feature asks
for no koto release.

**R14. No directive is removed.** Prose describing a check a gate now runs
stays in place. Rules guarding pull request creation, push, merge, and any
step that destroys a record stay in default context.

**R15. Each gate can be tested without a model.** Every gate's command runs
under the repository's existing script test harness with fixtures, so CI
checks it without an agent.

## Acceptance Criteria

- [ ] The design names, for every gate, its skill, state, exact command and
  exit convention, and marks any script as shipped today or new in this
  feature.
- [ ] The design lists every state where the agent copies a script's verdict,
  with its evidence schema before and after.
- [ ] The design's verification section names the map's file and format, what
  koto runs, how long and networked commands run, and the no-map refusal.
- [ ] The design's panel section states the pass rule as "no finding at a
  blocking severity", names the results file's location, and names the decider
  slot per panel state.
- [ ] The design maps each gate to the koto events it produces and to the
  `rule_id` (a stable name) and `rule_ref` (a source location) its findings
  carry, and names the gates that print none.
- [ ] The design names the released koto version it needs and requests no
  koto release.
- [ ] The plan is dependency-ordered issues an /execute run can take, each
  with a check a script can run, and any gate that waits on an unsettled rule
  is marked with that rule.
- [ ] Nothing in the design or plan removes a directive or lets a pass skip a
  panel.

## Out of Scope

- Building the gates. This feature ends at a reviewed plan.
- Withholding or removing prose rules from default context.
- Letting any gate, decider or pass skip or replace a review panel.
- Any change to koto, and any request for a koto release.
- Building the decider check; only its slot is named.
- /scope's, /deliver's and the other skills' templates.
- The planned `shirabe validate` subcommands; gates call validators as they
  ship.

## Decisions and Trade-offs

**One koto floor, already released.** koto 0.15.0 carries failure findings
and attempt counts (koto#290), gate polling (koto#292), decider checks
(koto#294) and variable routing (koto#296), and it is already shirabe's floor.
The design uses it for everything rather than routing on an older release and
waiting for findings, so per-rule data comes from every supported run.

**Attribution over commits is a new script, not a gap.** No shipped check
reads commit trailers; PB3 reads the pull request body only. The workspace
treats AI attribution as a hard rule, so the commit walk that R4 adds checks
it too, in one small script with its own test, named in the design as new.

**The verification map moves into a machine-readable file.** The map today is
a Markdown list inside the extension file, which the agent reads and
interprets. koto can't run what only an agent can parse, so the map becomes a
data file beside the extension config. The Markdown stays as prose pointing at
it (R14).

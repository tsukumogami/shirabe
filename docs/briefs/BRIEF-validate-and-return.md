---
schema: brief/v1
status: Accepted
problem: |
  A gate failing on a registry rule shows the same one-line summary on every
  failure, only PB4 ever returns its full text (by special case), and a check
  the agent can't satisfy either loops or ends the run through an unsuited
  field, with nothing recording which rule ended it.
outcome: |
  A failing gate escalates on koto's own per-rule count, from the summary to the
  rule's full text and then to a named exit that ends the run as blocked, on
  the record and countable per rule, never as a pass.
---

# BRIEF: Validate-and-Return on koto Gates

## Status

Accepted

## Problem Statement

shirabe's rule registry (`references/rule-registry.json`) gives every rule a
gate reports a stable id, a one-line summary and an anchored range in a
reference file holding the rule's full text. The output gates `/work-on` runs
(the pull request body at `pr_creation`, commits at `finalization` and
`pre_pr_evidence`, the branch's documents at `pr_precheck`, verification, and
the review panels' open findings) print each violation as a finding whose
message starts with the rule's summary. koto, from 0.15.0, counts how many
times each rule has failed on each check in each state, and records the count
on the check's event.

Three things go wrong on top of that.

**The text never grows.** A gate shows the summary and its own detail, and
that's all the agent gets, however many times the same rule fails. When a fix
doesn't land the first time, the likeliest reason is that a line wasn't enough,
and the rule's full text, which already sits at a known range, is never offered.
koto's counts are on every failed check event, and no gate reads them.

**The one rule that returns its text does it by special case.** shirabe runs a
live offload canary: a random half of `/work-on` runs on hosts that opted in
read their PR-body rules with one rule left out, PB4 (no markdown heading in
Part 1 of a pull request body), so the broken rate of the two halves can be
compared. Because those runs never saw PB4, `check-pr-output.sh` releases PB4's
full text whenever PB4 fails. That's hard-wired to one rule in one script, so a
second withheld rule would need a second special case. And PB4 gets its full
text on the first failure whether or not the summary would have done, so the
canary can't tell a summary that worked from a full text that was needed.

**A check that can't be satisfied ends the run unrecorded, or doesn't end it.**
Three of these gates hold the run in place on a violation and wait for a fix:
the PR-body gate at `pr_creation`, the commit gate at `finalization` and the
documents gate at `pr_precheck`. When the fix can't be made (the check is wrong
for this change, or the agent has tried and keeps failing), the run either
loops, or stops through a field that wasn't made for it, such as
`pr_status: creation_failed_escalate`, whose recorded reason is a pull request
URL. Either way, someone reading koto's exported events can count rule failures
but not the runs a rule ended, so a check nobody can pass looks the same as one
that's merely hard.

## User Outcome

An agent whose fix keeps failing gets more help each time, decided by koto's
count rather than its own: the summary on the first failure, the rule's full
registry text once a fix has failed to land, and after repeated failures, a
named exit it can take if the check can't be satisfied. Taking the exit ends
the run as blocked, on the record. It never moves the run past the gate it
failed, so every rule that guards a push, a merge or the creation of a pull
request blocks exactly as it does today.

A withheld rule stops needing its own release code: the same escalation that
serves every rule delivers it, so the canary's PB4 path keeps working, and its
readout can separate runs that fixed PB4 from the summary from runs that needed
the full text.

A maintainer can read, per rule and straight from exported events, how often it
failed, how often it reached its full text and how often it ended a run, with no
hand-joined spreadsheet in between. That readable exit rate per rule is the sign
the feature is done.

## User Journeys

### A canary run's agent breaks PB4 and fixes it on the second try

An agent running `/work-on` in the canary's withheld half opens a pull request
whose Part 1 has a markdown heading; it never read PB4. The PR-body gate holds,
and the finding opens with PB4's summary. The agent's first edit misses. On the
second failure the gate's output carries PB4's full text from the conformance
reference, and the agent's next edit passes.

### An agent can't make a commit subject pass and takes the exit

An agent at finalization keeps failing the commit-subject rule: the first
failure shows the summary, the second the full text, and its rewrites still
fail. The third failure's output says a named exit is open and how to take it.
The agent takes it with its reason. The run ends as blocked, its recorded
reason naming the state and the agent's reason. No pull request is opened.

### A maintainer reads which rules end runs

A maintainer looking at a week of exported koto events counts, per rule, the
failed checks at each count koto recorded, and the runs that took the exit,
joined to the rule whose check failed just before. A rule that ends runs often
is a candidate for a better check or a better rule, which the check lifecycle
work picks up.

Two boundary cases keep their current behaviour and are listed here so the
requirements hold them: an agent that fixes a rule on the first try sees one
summary and nothing more, and an agent that runs a gate script from its own
shell, outside a koto session, gets exactly the output it gets today.

## Scope Boundary

**In:**

- Escalating text for every rule a gate script prints through shirabe's shared
  findings library: the summary first, then the rule's full registry text,
  decided by koto's per-rule counts, never by a number the agent supplies.
- A named exit at `/work-on`'s three holding output gates (`pr_creation`,
  `finalization`, `pr_precheck`), recorded in koto's events, ending the run as
  blocked, offered once a rule has failed repeatedly.
- Adoption of the escalating text by every `/work-on` output gate, and PB4's
  existing release moved onto it.
- The registry reference documenting the escalation and the exit.

**Out:**

- Any change to which rules may be withheld, or to any registry entry. No rule
  is newly withheld.
- An exit that lets a run past a failing gate. Rules guarding pushes, merges and
  pull request creation keep blocking; so does PB4.
- An exit at `pre_pr_evidence` and `verification`. Neither holds on a
  violation: `pre_pr_evidence` ends the run, and a failed verification sends it
  back to implementation, which has its own way to stop. They get the
  escalating text only.
- The check lifecycle (shadow, warn, block, retire) and a dispute path for a
  check that fails wrongly, which are a separate feature.
- Decider checks. An unanswered decider criterion already falls back to the
  agent; this feature covers deterministic gates.
- `/execute`'s and `/scope`'s gates. They print through the same library and can
  adopt later; this feature changes only `/work-on`'s template.
- A koto change. koto's per-rule counts are already on its published
  session-feed contract.

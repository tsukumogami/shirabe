---
schema: brief/v1
status: Accepted
problem: |
  A deterministic check in shirabe either blocks every run or doesn't exist.
  A new check blocks real runs before anyone knows how often it fires or how
  often it's wrong, an old one keeps blocking after it stops catching
  anything, and the events koto exports can't say which is which.
outcome: |
  A maintainer adds a check at a stage that can't hurt a run, reads its fires,
  passes and disputes from koto's exported events, and moves it up, down or
  out through a reviewed registry change. An agent that hits a wrong finding
  says so on the record without getting past the gate by saying it.
motivating_context: |
  The rule registry gave every gate rule an id that koto's events carry, so
  for the first time a rule's record can be counted. Counting it showed the
  record only holds a rule's failures at error level, which is enough to
  retire a blocking check and not enough to introduce one gently.
---

## Status

Accepted

## Problem Statement

A new deterministic check in shirabe is trusted with real runs on its first
day, before anyone has seen how often it fires on work that was actually
fine. Every check a koto gate runs has one setting: when a gate script
reports a registered rule, the finding is an error, the gate fails and the
run holds until the agent fixes it. A maintainer who wants to watch a check
for a while, or show its finding without holding anyone up, has nowhere to
put it, and the only way to stop running a check is to delete it.

The opposite end has the same gap. The registry holds about forty gate rules,
and most of them were written for failures that happened once and may never
happen again. A check that hasn't fired in months still costs a script run on
every state entry, and nobody can tell it apart from a check that fires every
week, because nothing collects that reading in one place.

The reading itself is incomplete. koto writes a per-rule record to its run
journal, the event log that leaves the host, only for error-level rules of a
check that failed. A warning or an informational finding is logged in the
session but never reaches the journal, a passing check writes no rule record
at all, and a passing check's findings reach no response, so the agent never
sees them. A rule's fire count can be read from the journal; anything gentler
than blocking can't be seen by anyone.

Finally, when a check fails wrongly there's nowhere to say so. The only
recorded way past a gate is a koto override, which moves the run past the
check and records the gate's name and nothing about the rule or why. An agent
that believes a finding is wrong has two choices: comply with it anyway, or
override a gate that may be guarding a push, a merge or a pull request. A
check that keeps failing wrongly never shows up as such in any figure.

## User Outcome

A shirabe maintainer adding a check starts it at a stage where it can't hold
a run, and watches how often it fires, how often the gate passes without it,
and how often someone disputes it, all from koto's exported events with
nothing extra running outside the session. When the figures support it, they
move the check up a stage, down a stage or out of service with a registry
change that a person reviews. The change says which figures justified it.

A coordinator reviewing the registry can see which blocking checks have gone
quiet and retire them, without worrying that a check guarding a push, a merge
or a pull request quietly loses its teeth along the way.

An agent running a workflow sees a gentle finding without being held by it,
and can fix it or carry on. When it hits a finding it believes is wrong, it
says so on the record, naming the rule, and a maintainer later sees that
dispute in the rule's figures. Saying so is not a way past the gate.

## User Journeys

### A maintainer introduces a new check gently

A maintainer adds a rule to the registry with a new gate-script check and
starts it at shadow. For a few weeks every real run evaluates it, its
findings land in the exported journal, and no agent is held or even shown the
finding. The maintainer reads its fire rate and dispute count from the
journal, sees it fires only on genuinely bad output, and opens a registry
pull request moving it to warn, then later to block, citing the figures each
time.

### A coordinator retires a check that stopped catching anything

A coordinator reviewing the registry queries each block-stage rule's fires
over the last stretch of runs and finds one with many evaluations and no
fires. They open a pull request setting its stage to retired, and the gate
script stops reporting it. When they try the same for a rule that guards PR
creation and has no backstop, the registry check fails the pull request and
says why.

### An agent disputes a wrong finding

An agent in a `/work-on` run is held by a block-stage finding it believes is
wrong, for example a banned-word rule firing on a quoted error message. It
records a dispute naming the rule and a reason. The run stays held: the agent
still fixes the output or asks for an override. The dispute reaches the
journal with the rule id, so the rule's dispute rate rises and a maintainer
reviewing it later sees the pattern.

### An agent sees a warning and moves on

An agent passes a gate whose check reported a warn-stage finding. The
response that advances the run carries that finding, so the agent reads it in
the same tool result, fixes the small issue or leaves it, and the run never
waits on it.

## Scope Boundary

**In scope:**

- A lifecycle stage on every deterministic (script-checked) rule in the
  registry: shadow, warn, block and retired, with the stages a rule may move
  between and the safety rule for checks that guard irreversible actions.
- Gate scripts behaving according to their rules' stages, through the shared
  findings library the scripts already use.
- Promotion, demotion and retirement criteria written as queries over koto's
  exported journal events, with thresholds, applied by a reviewed registry
  change rather than an automatic flip.
- A dispute path an agent or a person uses inside a session.
- The companion koto change that makes the gentler stages visible: journal
  records for every finding of a check with its level, a passing check's
  warnings on the agent's response, and a journaled dispute with its rule id.
- Behaviour on a koto that predates that change: block-stage checks work as
  they do today, and shadow and warn stay safe even where they can't be
  counted or shown.

**Out of scope:**

- Model-graded criteria (the review-shadow `rs-*` entries and decider
  checks). They earn trust from a different oracle and have their own
  promotion path, separate from this feature.
- Changing which rules may be withheld from an agent's default context. A
  reader might expect a retired or shadow check to make its rule withholdable,
  since the registry ties withholding to whether a check backs the rule, but
  the stage is about how a check behaves, not whether a rule's text is
  loaded; no rule's withhold eligibility changes here.
- Dashboards, saved views or a measurement model over the journal. This
  feature writes the queries a reviewer runs; presenting them is separate
  work.
- Offline evaluation runs or any job that recomputes figures outside a
  session. The figures come from events koto already writes during real runs.
- Automatic promotion or retirement. A stage changes only through a pull
  request a person or coordinator reviews.
- Changes to koto's override path. An override still moves past a gate as it
  does today; a dispute is a separate, non-unblocking record.

## References

- `references/rule-registry.md` and `references/rule-registry.json`, the
  registry whose entries gain a stage.
- `docs/designs/current/DESIGN-rule-registry.md`, the design behind the
  registry's fields and the withhold safety rule.
- `tsukumogami/koto:docs/reference/run-journal.md`, the exported journal and
  its `check_evaluated` and `check_rule` records.
- `tsukumogami/koto:docs/reference/session-feed.md`, the session log's check
  findings, which already include a passing check's warnings.

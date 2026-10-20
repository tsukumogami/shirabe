---
schema: prd/v1
status: Done
problem: |
  shirabe's deterministic gate checks have one behaviour: an error finding
  that holds the run. A maintainer can't introduce a check without trusting
  it with real runs, can't retire a quiet one on evidence, and can't see
  when agents think a check is wrong, because koto's run journal records
  only the error rules of a failing check, a passing check's findings reach
  no agent, and there is no way to dispute a finding on the record.
goals: |
  Every deterministic check carries a lifecycle stage in the rule registry
  that decides how its gate treats a finding. Each rule's fires, passes,
  evaluations and disputes can be counted from koto's journal, and
  promotion, demotion and retirement follow stated thresholds over those
  counts, applied by a reviewed registry change.
absorbed:
  - docs/briefs/BRIEF-check-lifecycle.md
---

## Status

Done

Absorbed [BRIEF-check-lifecycle](docs/briefs/BRIEF-check-lifecycle.md); carried in Absorbed Brief.

Amended after acceptance: the figures a stage change cites come from log
queries over the exported journal fields, which one host's journal can't
stand in for. R18 now asks for those figures, R21's reference defines each
figure in the exported field names, and R19's reader is a fixture-tested
reference implementation of the definitions for tests and single-host spot
checks, not the source of a stage decision.

## Absorbed Brief

The feature exists because a deterministic check in shirabe either blocks
every run or doesn't exist. A new check is trusted with real runs before
anyone knows how often it fires or how often it's wrong, an old one keeps
blocking after it stops catching anything, and koto's exported journal
can't tell which is which, because it records only the error rules of a
failing check. This document's Problem Statement states that in full.

The outcome the brief asked for has three people on the receiving end. A
maintainer adds a check at a stage that can't hurt a run, reads its fires,
passes and disputes from the journal, and moves it up, down or out through
a reviewed registry change. A coordinator retires checks that went quiet
without a check guarding a push, a merge or a pull request losing its
protection. An agent sees a gentle finding without being held by it, and
says a finding is wrong on the record without getting past the gate by
saying so.

It framed four journeys, which the User Stories carry: introducing a check
at shadow and promoting it on its figures; retiring a quiet block-stage
check, refused for a guarded rule without a backstop; disputing a wrong
finding while the run stays held; and reading a warning on the response
that advanced the run. Its boundary is this document's Out of Scope:
model-graded criteria, withhold eligibility, dashboards, offline runs,
automatic stage changes and koto's override path stay out, and the
companion koto change that makes the gentler stages visible is in.

## Problem Statement

A new deterministic check in shirabe is trusted with real runs on its first
day. Every check a koto gate runs through a gate script reports its rule as an
error, the gate fails, and the run holds until the agent fixes the output. A
maintainer who wants to watch a check for a while, or show its finding
without holding anyone up, has nowhere to put it, and the only way to stop
running a check is to delete it and its registry entry.

The registry holds 35 active script-checked gate rules, and nothing tells a
quiet one apart from a busy one. As an illustration from a single week (the
seven days to 2026-10-16), `/work-on`'s commit convention gate was evaluated
241 times and passed every time, and its documents-visibility gate passed 55
of 55. Nothing collects that reading per rule over a longer stretch, so a
check that no longer catches anything can't be found, and one that catches
something every week can't be shown to.

The reading can't be completed from what koto writes today. koto's run
journal, the event log that leaves the host, records a `check_rule` line
only for an error-level rule of a check that failed. A warning or an
informational finding is logged in the session but never journaled, a
passing check writes no rule line, and koto puts a passing check's findings
on no response, so the agent never sees them. And when a check fails
wrongly, the only recorded way past the gate is an override, which moves the
run and names only the gate.

Two people feel this: the maintainer deciding whether a check is ready to
block or ready to retire, and the agent held by a finding it believes is
wrong, with no way to say so that anyone will later count.

## Goals

- A maintainer can add a check that can't hurt a run, read how often it fires
  and how often it's disputed from koto's journal, and promote it on stated
  thresholds.
- A coordinator can find checks that meet the retirement criterion (R17) and
  retire them, without a check that guards a push, a merge or a pull request
  losing its protection along the way.
- An agent sees a warn-stage finding without being held by it, and can record
  a dispute against a finding without getting past the gate by doing so.
- Nothing new runs outside a session: every figure comes from events koto
  writes during real runs.

## User Stories

- As a shirabe maintainer adding a gate-script check, I want to start it at
  `shadow`, where it only records its findings, so that I can see how often it
  fires on real runs before any agent is held by it, and promote it to `warn`
  and then `block` when the figures meet the thresholds.
- As a coordinator reviewing the registry, I want each block-stage rule's
  evaluations and fires since its stage was set, so that I can retire rules
  that stopped firing, and I want the registry check to refuse a retirement or
  a softening of a rule guarding PR creation, a push or a merge unless another
  deterministic check is declared for that action.
- As an agent held by a block-stage finding I believe is wrong (a banned-word
  rule firing on a quoted error message, say), I want to record a dispute
  naming the rule and my reason, so that the rule's dispute rate rises where a
  maintainer will see it, while the run stays held until I fix the output or a
  person overrides the gate.
- As an agent passing a gate whose check reported a warn-stage finding, I want
  that finding on the response that advanced me, so that I can fix the small
  issue or carry on without the run waiting on it.
- As a reviewer of a stage-change pull request, I want the rule's figures,
  computed by log queries over the exported journal, in the pull request, so
  that I can check the change
  against the criterion it claims instead of taking it on trust.
- As an adopter running shirabe on a koto that predates the journal changes, I
  want block-stage checks to behave exactly as today and gentler stages never
  to hold my runs, so that upgrading shirabe never makes a run worse.

## Requirements

Terms used below. A **protected action** is one of the registry's protected
guard values: `pr-create`, `push`, `force-push`, `merge`, `close-issue`,
`release`, `delete-branch`, `publish`, `destroy-record`. A **visit** is koto's:
it runs from the session's arrival in a state until it next arrives somewhere
else, is rewound, reaches a terminal or is cancelled. Dates are UTC calendar
dates, `YYYY-MM-DD`.

### Functional: the registry

- **R1. A stage on every deterministic rule.** Every registry entry whose
  `check.kind` is `script` carries `stage`, one of `shadow`, `warn`, `block`
  or `retired`. An entry with any other check kind carries no `stage`. When
  this feature lands, every active script entry is at `block` and every
  `status: retired` script entry is at `retired`, so no gate behaves
  differently.
- **R2. Stage and status are separate.** `status` keeps its meaning: whether
  the rule still applies. `stage` says how the rule's gate check behaves. A
  `status: retired` entry is at stage `retired`. An entry at stage `retired`
  with `status: active` still applies: its text stays where it is, its id
  stays on its scripts' `RULE_IDS` lines, and only its gate check stops
  reporting it.
- **R3. When the stage was set.** Every script entry carries `stage_since`, the
  date its current stage was set; a new entry's is the date it was added. On
  any change of stage, `stage_since` must be later than the merge base's
  value. It opens the window R17 reads.
- **R4. Transitions.** The registry check compares each entry with the pull
  request's merge base and allows only these stage changes, refusing any
  other:
  - no change;
  - a new entry starts at `shadow`, `warn` or `block`;
  - a promotion moves exactly one step up: `shadow` to `warn`, `warn` to
    `block`;
  - a demotion moves down any number of steps among `block`, `warn` and
    `shadow`;
  - any stage moves to `retired`;
  - a `retired` entry whose status is `active` moves only to `shadow`.
  An entry whose status changes from `active` to `retired` must move to stage
  `retired` in the same change. A `status: retired` entry never changes status
  or stage again.
- **R5. Guarded rules stay blocking unless something else blocks.** An active
  script entry whose `guards` include a protected action may hold a stage
  other than `block`, `retired` included, only when it carries
  `stage_backstops`: a list with one entry per protected action it guards,
  each naming the action (`before`) and a repository-relative path (`check`)
  to a deterministic check, other than the entry's own `check.path`, that
  blocks that action when the rule is broken. The registry check refuses the
  entry when an action is missing from the list, a path doesn't exist, or a
  path is the entry's own check; whether the named check really blocks the
  action is the reviewer's call, recorded in the entry's `notes`. This sits
  beside the withhold safety rules and changes none of them: a stage never
  makes a rule eligible to withhold.
- **R6. Which evaluations belong to a rule.** Every active script entry carries
  `gates`, a non-empty list of `<skill>:<state>:<gate>` values naming the koto
  gates whose evaluations count as its evaluations. The registry check refuses
  a value whose state isn't a state of that skill's templates, whose gate
  isn't a command gate of that state, or whose gate command doesn't name a
  script that can report the rule: one whose `RULE_IDS` line lists the id, or
  the review-panel script that may report any active rule.

### Functional: gates

- **R7. Gates honour the stage.** The five gate scripts that report registry
  rules (`check-pr-output.sh`, `check-branch-output.sh`,
  `check-verification.sh` and `panel-scope.sh` under `skills/work-on/scripts/`,
  and `check-hop-document.sh` under `skills/scope/scripts/`) report a rule's
  finding by the rule's stage:
  - `block`: at level `error`, and the finding counts toward failing the gate,
    as today;
  - `warn`: at level `warning`, and the finding doesn't count;
  - `shadow`: at level `info`, and the finding doesn't count;
  - `retired`: not at all.
  A script's exit is decided by its counting findings and by its own
  could-not-decide outcomes (exit 2), which are unchanged.
- **R8. The stage travels with the finding.** Every finding a gate script
  prints for a registered rule carries the rule's id, and its level identifies
  its stage one-to-one: `error` for block, `warning` for warn, `info` for
  shadow. The findings verification the gate scripts' test suites use
  (`rule-registry.sh verify-findings`) refuses a finding whose level doesn't
  match its rule's stage.
- **R9. A gate with only gentle findings passes.** A gate script whose findings
  are all warn or shadow exits 0, as it does when it finds nothing. In
  particular:
  - `check-verification.sh --verdict`, whose exit picks a route (1 a failed
    command, 3 a bad or missing verification map, 4 a result that needs a
    person), picks the route from its block-stage findings alone;
  - `check-pr-output.sh --pr-body` adds its `pr-body/conformance` fallback
    finding (for violations the validator didn't list) only when the validator
    listed no finding at all, never when every listed finding is warn or
    shadow;
  - `check-pr-output.sh --pr-body` releases the text of
    `pr-body/no-heading-in-part1` only when that rule's finding is shown, at
    `warn` or `block`.
- **R10. Review-panel findings follow the panel rule.** `panel-scope.sh
  --verdict` reports every finding at the stage of `panel/open-finding`,
  whichever rule the finding cites and whatever that rule's own stage, because
  the stage governs a deterministic check and a reviewer's finding isn't one.
- **R11. The pre-action hook ignores stage.** A rule's `deny` keeps denying the
  guarded command at every stage; the stage governs the koto gate check only.

### Functional: koto

- **R12. Every finding is journaled.** For every check evaluation, koto writes
  one finding record for each distinct pair of rule id and level among the
  evaluation's logged findings, whether the check passed or failed, carrying
  the state, the gate, the rule id, the level, how many findings had that
  pair, the evaluation's attempt and visit attempt, and the same sequence
  numbers as the evaluation's record. Koto's own fallback finding, whose rule
  id is the gate's name, is journaled like any other. The evaluation record
  itself gains the evaluation's finding count, written as 0 when there are
  none, and whether the findings were cut at the cap. The finding records go
  in the same journal write as the evaluation record, so a reader never sees
  one without the other. Existing records keep their fields and meaning.
- **R13. A passing check's warnings reach the agent.** When a `koto next` call
  evaluates checks that pass while reporting `warning` findings, its response
  carries a top-level `advisories` list, one entry per such check with its
  state, its gate and those findings, at most 100 findings in all. A response
  with none carries no `advisories` key and is otherwise unchanged. `koto
  next --to` and `koto status` don't carry it.
- **R14. A dispute is recorded, not obeyed.** `koto disputes record <session>
  --gate <gate> --rule <rule-id> --reason <text> [--state <state>] [--by
  agent|person]` records a dispute of a rule's finding at a gate. `--state`
  defaults to the current state and `--by` to `agent`. The gate must have an
  evaluation logged in that state of the session; the dispute names the most
  recent one. The rule id must be 1 to 128 bytes, and koto doesn't require a
  finding for it, since a logged finding list may have been cut. The reason is
  required, 1 to 1,000 bytes. The command changes no gate outcome, no route
  and no state. It appends one session event carrying all of these and one
  journal record carrying the state, gate, rule id and source, never the
  reason. A missing session exits 1 and appends nothing; any other refusal
  exits 2 with a typed error code and appends nothing.
- **R15. Additive.** The koto changes add event types, journal kinds and an
  optional response field, with no change to the session log's schema
  version. koto v0.14.1, the oldest reader koto's compatibility jobs check,
  reads a session log holding the new events and reports the same current
  state as the new build.

### Functional: criteria and disputes in shirabe

- **R16. Figures per rule.** For one rule over a window, computed from journal
  records alone, summed across the rule's `gates`:
  - evaluations: evaluation records of those gates that carry a finding count
    (R12), so evaluations from a koto that journals no findings are not
    counted;
  - fires: those evaluations with a finding record for the rule, at any level;
  - passes: evaluations minus fires;
  - disputes: dispute records naming the rule at one of those gates, by source;
  - unconverged visits (informational, feeds no criterion): visits in which
    the rule fired at `error` and its gate never passed before the visit
    ended.
- **R17. Thresholds.** The window runs from `stage_since` (inclusive) to the
  newest journal record the reader is given. Its length in days is the number
  of calendar days between the two dates. Rates are fires over evaluations and
  disputes over fires, both counting agent and person disputes alike; a rate
  with a zero denominator meets no criterion that reads it. A rule meets a
  criterion when:

  | Criterion | Stage it applies at | Evidence over the window |
  |---|---|---|
  | demote | warn or block | at least 7 days; at least 3 disputes; disputes more than 20% of fires |
  | retire | shadow, warn or block | at least 300 evaluations and 56 days; no fires |
  | promote to warn | shadow | at least 100 evaluations and 14 days; at least 1 fire; fires at most 25% of evaluations |
  | promote to block | warn | at least 100 evaluations and 14 days; at least 5 fires; disputes at most 5% of fires |

  Bounds are inclusive where they say "at least" or "at most". A rule meeting
  none holds its stage. The reader reports the first criterion a rule meets in
  the table's order. A guarded rule still needs R5's backstops for any stage
  other than `block`.
- **R18. Stage changes are reviewed changes.** Nothing changes a stage
  automatically. A stage changes only through a pull request to the registry
  that a person or a coordinator session reviews, and the pull request carries
  the rule's figures as log queries over the exported journal fields compute
  them, following R21's definitions. A reading from one host's journal can't
  stand in for them, since it sees that host alone. This is a process rule; no
  check enforces the pull request's content.
- **R19. A reference reader.** A fixture-tested reference implementation of
  R16's and R17's definitions, used in tests and for spot checks on one host,
  and never the source of a stage decision: `scripts/rule-lifecycle.sh figures [--json]
  [<journal-file>...]` reads koto journal lines (koto's line format, one JSON
  object per line) from the named files or standard input, reads each rule's
  `stage`, `stage_since` and `gates` from the registry beside it, ignores
  records outside each rule's window, and prints one line per script-checked
  rule: its id, stage, window days, evaluations, fires by level, passes,
  disputes by source, unconverged visits, and the criterion met or `hold`.
  With `--json` it prints one JSON object per rule instead. It exits 0 when it
  printed, 2 when the registry or an input can't be read. It writes no file
  and makes no network call.
- **R20. A dispute path in shirabe.** `scripts/rule-dispute.sh --session <name>
  --gate <gate> --rule <rule-id> --reason <text> [--state <state>] [--by
  agent|person]` refuses, with exit 2, a rule id that isn't an active registry
  entry. It records the dispute through `koto disputes record` when koto has
  the command and prints `dispute=journaled`. On a koto without it, it records
  a koto decision whose choice is `dispute:<rule-id>` and whose rationale
  carries the gate, state, source and reason, and prints `dispute=session-only`.
  Either way it exits 0 once recorded. A gate script that fails on a
  block-stage finding prints one line on standard error, which koto returns to
  the agent with the failure, naming `scripts/rule-dispute.sh` as the way to
  dispute it, so an agent learns of the path where it's held.
- **R21. Where the lifecycle is written down.** `references/check-lifecycle.md`
  states the stages, the transitions, the safety rule, the figures, the
  thresholds and the dispute path, and `references/rule-registry.md` describes
  the new fields and links it. Each figure is defined field by field in the
  exported `koto.*` names, including the nested form a log backend gives a
  name that has children (`koto.check` on an evaluation record arrives as
  `koto.check.name`), so a log query can be written from the definition alone.

### Non-functional

- **R22. Safe on older koto.** On koto 0.20.0, shirabe's current koto floor,
  and any koto without R12 to R14: block-stage checks behave exactly as today;
  warn and shadow findings never fail a gate, appear only in the gate's own
  captured output, which koto doesn't show on a passing gate, and stay out of
  the journal and the response, so warn behaves as shadow; and disputes fall
  back as R20 says. shirabe's koto floor rises only once a koto release
  carries R12 to R14.
- **R23. Bounded output.** Every new journal record stays within koto's
  4,096-byte line bound when its state, gate and rule id are each 128 bytes,
  the longest koto writes without hashing. An evaluation writes at most 50
  finding records, keeping `error` pairs first, then `warning`, then `info`.
- **R24. Floors and checks.** shirabe's changed scripts keep to the bash 3.2
  floor and their suites run on the macOS leg that tests it, and
  `scripts/check-skill.sh` passes for every skill this feature changes.
- **R25. Nothing outside a session.** No offline evaluation run, scheduled job
  or long eval run is added or required.

## Acceptance Criteria

### Registry

- [ ] Every active script entry in `references/rule-registry.json` carries
      `stage: block`, a `stage_since` date and a non-empty `gates` list; every
      `status: retired` script entry is at `retired`; no entry of another
      check kind has a `stage`; the registry check passes.
- [ ] The registry check fails on: a script entry with no `stage`; a `stage`
      outside the four values; a non-script entry with a `stage`; a `status:
      retired` entry at another stage; a script entry with no `stage_since` or
      one that isn't a `YYYY-MM-DD` date.
- [ ] Against a merge base, the registry check passes: no change; a new entry
      at `shadow`, `warn` or `block`; shadow to warn; warn to block; block to
      shadow; warn to retired; and retired to shadow on an active entry. It
      fails: shadow to block; retired to warn; a new entry at `retired`; a
      stage change whose `stage_since` isn't later than the base's; a status
      change to `retired` that leaves the stage at `block`; and any change to
      a `status: retired` entry's stage or status.
- [ ] An active entry at stage `retired` keeps its id on its script's
      `RULE_IDS` line, the registry check passes, and that script, given input
      that breaks the rule, prints no finding for it and exits 0.
- [ ] The registry check fails an active entry guarding `pr-create` at `warn`
      with no `stage_backstops`; fails one guarding `pr-create` and `push` with
      a backstop for `pr-create` only; fails one whose backstop path doesn't
      exist; fails one whose backstop path is its own `check.path`; and passes
      one at `retired` whose every protected guard has a backstop whose path
      exists. The withhold rules give the same result on every existing entry
      as before.
- [ ] The registry check fails a `gates` value whose state isn't in that
      skill's templates, one whose gate isn't a command gate of that state, and
      one whose command names no script listing the rule; it passes the
      review-panel gates for any active rule.

### Gates

- [ ] For each of the five gate scripts, a test sets a rule it reports to each
      stage and feeds input breaking it. At `block` the script prints an
      `error` finding with the rule id and exits as today
      (`check-pr-output.sh`, `check-branch-output.sh`, `panel-scope.sh` and
      `check-hop-document.sh` exit 1; `check-verification.sh` exits the route
      of that finding). At `warn` it prints a `warning` finding and exits 0;
      at `shadow`, an `info` finding and exit 0; at `retired`, no finding and
      exit 0.
- [ ] `check-verification.sh --verdict` with a block-stage `command-failed`
      and a warn-stage route-4 cause (`timed-out`) exits 1, not 4; the
      reverse exits 4; and a warn-stage `needs-person` alone exits 0.
      (`needs-person` comes only from an attended result, which runs no
      command, so it never appears beside `command-failed`.)
- [ ] `check-pr-output.sh --pr-body`, given a validator result whose only
      listed finding maps to a warn-stage rule, exits 0 and prints no
      `pr-body/conformance` finding; given a validator result listing no
      finding, it still prints the fallback and exits 1.
- [ ] `check-pr-output.sh --pr-body` with `pr-body/no-heading-in-part1` at
      `shadow` releases no rule text on a body breaking it, and at `warn`
      releases it once.
- [ ] `panel-scope.sh --verdict` prints a finding citing a warn-stage rule at
      level `error` while `panel/open-finding` is at `block`, and at `warning`
      with exit 0 when `panel/open-finding` is set to `warn` in a test
      registry.
- [ ] `rule-registry.sh verify-findings` fails a logged finding whose level
      doesn't match its rule's stage.
- [ ] The pre-action hook denies a PR body breaking PB2 with
      `pr-body/one-separator` set to each of the four stages.

### koto

- [ ] A gate printing two `error` findings for one rule and one `warning`
      finding for another, exiting 0, leaves its evaluation record (finding
      count 3) and exactly two finding records, one per rule and level with
      counts 2 and 1, each carrying state, gate, attempt and visit attempt,
      and no `check_rule` record.
- [ ] A failing gate printing one `error` finding leaves its `check_rule`
      record unchanged from today's and one finding record at `error`.
- [ ] A passing gate with no findings leaves an evaluation record whose
      finding count is 0 and no finding record.
- [ ] A gate printing 60 findings (10 `error`, 50 `info`) writes at most 50
      finding records with every `error` pair among them, and its evaluation
      record says the findings were cut.
- [ ] A `koto next` that auto-advances past a passing gate with one `warning`
      finding returns an `advisories` list with one entry naming that state
      and gate and carrying the finding; koto's existing response baseline
      test passes unchanged.
- [ ] A `koto next` past passing checks reporting 120 `warning` findings in
      all returns 100 of them in `advisories`; `koto next --to` and `koto
      status` on the same session carry no `advisories` key.
- [ ] `koto disputes record` for a gate evaluated in the current state, and
      with `--state` for a gate evaluated in an earlier state, each append one
      session event carrying session, state, gate, rule id, reason and source,
      and one journal record carrying state, gate, rule id and source and no
      reason; the next `koto next` response is the same as without it.
- [ ] `koto disputes record` exits 2 and appends nothing for a gate never
      evaluated in the named state, an empty rule id, a rule id over 128
      bytes, an empty reason, a reason over 1,000 bytes, and `--by` other than
      `agent` or `person`; it exits 1 for a missing session.
- [ ] koto v0.14.1, given a session log holding a dispute event and passing
      checks' warning findings, exits 0 on `koto status` and reports the same
      current state as the new build.
- [ ] Each new journal record kind, built with a 128-byte state, gate and
      rule id, is at most 4,096 bytes.

### Criteria, disputes and degradation

- [ ] The figures reader, given fixture journal lines and a test registry,
      prints values matching hand-computed ones for: a rule meeting each of
      the four criteria; a rule meeting none; a rule at exactly 100
      evaluations and 14 days with 25% fires (meets promote to warn) and one at
      26% (holds); disputes at exactly 5% and 20% of fires; a rule with zero
      evaluations (holds, no error); a rule whose records before
      `stage_since` would otherwise change its verdict; evaluation records
      without a finding count (not counted); and a visit where the rule fired
      at `error` twice and its gate never passed (one unconverged visit).
- [ ] The figures reader, run with its inputs in a read-only directory,
      creates and modifies no file, and exits 2 on an unreadable input file.
- [ ] `scripts/rule-dispute.sh` exits 2 for a rule id that isn't an active
      registry entry; with a koto that has `koto disputes record` it records
      through it and prints `dispute=journaled`; with one that doesn't it
      records a koto decision with choice `dispute:<rule-id>` and prints
      `dispute=session-only`.
- [ ] A gate script failing on a block-stage finding prints a standard-error
      line naming `scripts/rule-dispute.sh`; one passing with only warn or
      shadow findings doesn't.
- [ ] With the koto floor unchanged at 0.20.0, a koto-driven test of a gate
      whose only finding is warn-stage passes the gate, and the run advances.
- [ ] `references/check-lifecycle.md` states the stages, transitions, safety
      rule, figures, thresholds and dispute path, and
      `references/rule-registry.md` describes `stage`, `stage_since`,
      `stage_backstops` and `gates` and links it.
- [ ] The changed scripts' suites pass on the macOS bash 3.2 leg, and
      `scripts/check-skill.sh` passes for every changed skill.
- [ ] No workflow with a `schedule` trigger and no evaluation-run step is
      added.

## Out of Scope

- **Model-graded criteria.** The review-shadow `rs-*` entries and decider
  checks earn trust from a different oracle and have their own promotion
  path. They carry no stage here.
- **Withhold eligibility.** A reader might expect a retired or shadow check to
  make its rule withholdable, since the registry ties withholding to whether
  a check backs the rule, but no rule's withhold eligibility changes.
- **Presenting the figures.** No dashboard, saved view or measurement model:
  this feature defines the figures and ships a reader over journal lines.
- **Offline runs.** No evaluation harness run or job that recomputes figures
  outside a session.
- **Automatic stage changes.** Log queries report the figures; a person
  changes the stage.
- **koto's override path.** An override moves past a gate as it does today; a
  dispute is a separate record that moves nothing.
- **Moving any existing rule.** Every rule starts at `block` or `retired`;
  moving one is a later registry change backed by figures.
- **The koto release and the floor bump.** The koto change ships in a koto
  release its own owners cut; raising shirabe's koto floor to it is a later
  change.

## Known Limitations

- koto keeps at most 50 findings per check event, errors first, so a check
  printing more than 50 findings can lose warning and info pairs from the
  journal; the evaluation record says when that happened. shirabe's gate
  scripts print far fewer.
- Whether a dispute came from an agent or a person is what the caller says;
  koto can't verify it. A dispute moves nothing, so a wrong source skews a
  figure and nothing else.
- 34 of the 35 active script rules guard a protected action, so until
  backstops are declared for them they can't leave `block`. The gentler
  stages serve new checks first.
- A rate is per evaluation of the rule's gates, not per case the rule applies
  to: a script that checks a rule only under some condition counts every
  evaluation in the denominator.
- Scope's document gates run a handful of times a week, so their windows reach
  the evaluation minimums slowly.
- Shadow findings are seen by nobody, so a shadow rule collects no disputes;
  its first precision reading comes at `warn`.
- Renaming a gate or moving it to another state needs the rule's `gates`
  updated in the same change, or evaluations under the new name aren't
  counted.

## Decisions and Trade-offs

- **Stage is a new field, not a reuse of `status` or `level`.** `status:
  retired` means the rule no longer applies and its id must leave every
  `RULE_IDS` line; a check retired for going quiet still guards a rule whose
  text loads. `level: shadow` already names the review-shadow trial. Reusing
  either would change what existing entries mean.
- **The level carries the stage.** koto's finding format has a closed level
  vocabulary (`error`, `warning`, `info`) and ignores unknown keys, so a stage
  key in the finding would never reach an event. The three shown stages map
  one-to-one onto the three levels.
- **A separate backstop list for stages.** The existing `backstop` field
  serves withholding and requires `guards: ["none"]`, so it can't describe a
  guarded rule. `stage_backstops` names one check per protected action and
  leaves the withhold rules untouched.
- **Count only evaluations from a koto that journals findings.** On an older
  koto a warn finding never reaches the journal, so zero fires there would
  look like a quiet rule and could justify a wrong retirement. The finding
  count on the evaluation record marks the evaluations that can be trusted.
- **The koto change is part of this feature, as a separate pull request.**
  Without it a shadow stage can't be counted and a warn stage can't be seen;
  shirabe ships so that it degrades safely until a koto release carries it.
- **A dispute doesn't unblock.** Overrides already move past a gate; a dispute
  that also did would let an agent past a check guarding a push by disagreeing
  with it. Recording without moving keeps the figure honest and the guard
  intact.
- **Promotion one step at a time, demotion in any size.** Each promotion needs
  figures gathered at the stage below; a check that fires wrongly should be
  able to drop straight out of the way.
- **Thresholds sized to today's volume.** `/work-on`'s gates see roughly 100 to
  300 evaluations a week, so 100 evaluations over at least 14 days fits one to
  three weeks; retirement asks for three times as many and eight weeks because
  it removes a check outright.
- **Person and agent disputes count alike.** Both are recorded with their
  source so a reviewer can weigh them, but the thresholds don't, since koto
  can't verify the source.

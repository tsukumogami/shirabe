---
schema: design/v1
status: Accepted
problem: |
  /work-on's scrutiny panel has no measured answer to which of its seats' questions a
  2,560-byte Jev slice could decide, so none of them has a slice contract, and the
  one question that fits (whether the decisions a run recorded give reasons) has no
  gate to run in. The findings ledger takes decider entries only from the agent's
  round file and marks every decider fail blocking whatever the check's mode, and
  jev-pass-trust's live bar counts an empty slice as an unanswered evaluation.
decision: |
  Record every scrutiny seat question as a contract: rs-018 to rs-020 as disabled
  review-shadow rows with measured lower bounds or an insufficient verdict, beside
  the existing rs-015. Add one shadow decider-check gate, scrutiny_decider, on the
  scrutiny state, whose criterion key is its registry id and whose slice a new
  decision-reasons.sh prints from koto's session log. panel-scope.sh --record imports
  the panel state's decider_checked events from that log itself and sets a finding's
  severity from the event's mode. jev_criteria.py leaves not-graded evaluations out
  of the live bar and gains a --slice measurement, and references/jev-criteria.md
  writes down the rule for replacing a seat without building it.
rationale: |
  Each piece reuses what jev-pass-trust and the findings ledger already built: their
  contract format and checker, their decider-entry path, their reference reader. The
  slice script takes the log path the template already substitutes, so it reads only
  what koto wrote and calls no koto. Importing events in --record keeps the agent out
  of what the ledger says about a decider, and a mode-aware severity is the smallest
  change that stops a shadow check from blocking a panel. Building seat replacement
  would ship code with nothing eligible to run on.
upstream: docs/prds/PRD-jev-scrutiny-batches.md
decision_provenance: inline-resolved
---

# DESIGN: Jev batches for scrutiny review

## Status

Accepted

## Context and Problem Statement

`/work-on`'s `scrutiny` state (`skills/work-on/koto-templates/work-on.md`) plans a
round with `panel-scope.sh --plan scrutiny`, the agent spawns the seats it plans
(completeness, justification, intent, defined in
`skills/work-on/references/phases/phase-4a-scrutiny.md`), records their findings with
`panel-scope.sh --record scrutiny <round-file>`, and the `scrutiny_verdict` gate passes
the panel from the findings ledger (`verdict_ledger.json`). The PRD
(`docs/prds/PRD-jev-scrutiny-batches.md`) asks for four technical things, each of
which touches code jev-pass-trust (#921) and the findings ledger (#714) already
shipped.

**Contracts for every seat question.** jev-pass-trust's registry check
(`scripts/jev-criteria/jev_criteria.py check`) sees a Jev contract only on an entry
whose `check.kind` is `decider` (declared by a template) or `review-shadow` (a row in
`scripts/review-shadow/criteria.json` with observer `jev`), and it refuses a decider
entry no template declares, so a rejected question can't be a decider entry. The
completeness seat's coverage question already has one (`rs-015`, rejected). The
other three questions need entries, with figures a shipped command reproduces;
`measure sessions` today projects only `review_facts.json`.

**One batch on `scrutiny`.** The question that fits (PRD R3) reads the decisions a
run recorded in `analysis` and `implementation`, which koto writes to the session
log as `decision_recorded` events, `payload.state` and `payload.decision` (`choice`,
`rationale`, `alternatives_considered`). koto's decider check runs a command, sends
its output to Jev whole or not at all (over `max_bytes` it falls back to the agent),
writes a `decider_checked` event carrying `state`, `visit_seq`, `gate`, `rule_id`
(the criterion key), `declaration_hash`, `mode` (the effective mode), `outcome`,
`input_sha256` and `input_bytes`, and holds the state while a criterion is under
`awaiting`, whether or not a `when` clause reads the check. The template already
reserves a comment slot for this gate.

**Verdicts in the ledger.** `panel-scope.sh --record` accepts a
`{"decider": {...}}` entry only from the round file, checks it against a matching
`decider_checked` event, dedupes on (state, visit, gate, criterion, declaration
hash), and then raises a blocking finding on `fail`, adds a `reverified` record on
`pass`, and raises or appends a blocking `unverified` record on anything else. It
never reads the log on its own and never looks at `mode`. Every rule id a finding
names must be an active registry id (`area/name` or `rs-NNN`), and the entry's
`rule_id` must equal the event's criterion key.

**The live bar.** `live_figures` in `jev_criteria.py` builds an evaluation from any
`decider_checked` or `decider_fallback` event and counts it answered only on `pass`
or `fail`, so an all-`not_graded` evaluation counts as an unanswered one. A
criterion that is often empty could never reach 95% answered.

The PRD's requirements, carried here so the design stands on its own:

- Every scrutiny question maps to a contract: `rs-015` unchanged; `rs-018`
  (evidence claims, `not_measured: no-real-run-record`, verdict `insufficient`);
  `rs-019` (justification) and `rs-020` (intent), each with a measured lower bound
  over budget on more than 5% of runs and the sentence "These figures are a lower
  bound: the full slice also carries the diff."; `work-on/scrutiny-decision-reasons`,
  `untrusted`, measured over at least 100 `koto-sessions` runs with at most 5% over
  budget, its graded-only share stated in its written case (R1, R2, R5).
- The batch is gate `scrutiny_decider`, `max_bytes` 2,560, label `decisions`, one
  shadow criterion keyed `work-on/scrutiny-decision-reasons` with fixed question,
  pass, fail and escape text, read by no route (R3).
- The slice prints every `analysis` and `implementation` decision on any visit, in
  log order, as `- choice:` / `  reason:` / `  rejected:` lines with whitespace
  collapsed, nothing (exit 0) when there are none, non-zero when the log can't be
  read, and reads nothing else (R4).
- Fixtures meet jev-pass-trust's profile (10 good, 20 seeded-bad, 5 adversarial, 3
  techniques), inputs as log events (R6).
- An unanswered batch holds the state, carried rounds included, until the agent
  answers with `koto decider answer`; the agent's answer never becomes a ledger
  entry; every planned seat runs; for a user whose decider is off nothing changes
  (R7, R8).
- `--record <panel>` imports every unused `decider_checked` event of the panel's
  state; `fail` is advisory in shadow and blocking otherwise; `pass` adds
  `reverified`; other outcomes add nothing in shadow and keep today's `unverified`
  behavior otherwise; a round file's entries take their mode from the matched
  event (R9). Blocking batch findings count like a seat's, advisory ones never
  (R10).
- Not-graded evaluations leave the live bar's evaluations, sessions and answered
  share; the minimums count graded ones; mixed evaluations follow the existing
  rule; `figures` and a promotion's `live` record carry the count; both documents
  state it with `koto.decider.outcome` `not_graded` (R11).
- `references/jev-criteria.md` gains "Replacing a seat" with five conditions, and
  nothing leaves a seat out (R12). The directive and phase file tell the agent (R13).
- No koto change, no decider key in CI, public-clean (R14 to R16).

## Decision Drivers

- **Read only what koto wrote.** A slice comes from koto's log or committed objects,
  never from a file or key the agent chooses (jev-pass-trust R3, PRD R4).
- **Reuse, don't fork.** One contract format, one registry checker, one decider-entry
  path in the ledger, one reference reader for the live bar.
- **A shadow check never blocks a panel.** The ledger's severity has to follow the
  event's mode, and nothing in shadow may hold the verdict gate.
- **Fail closed where a mode is unknown.** An event without a mode, and anything that
  isn't shadow, keeps today's blocking behavior.
- **No new koto surface.** Everything uses koto 0.20's gate, events and fallback.
- **Bash 3.2 and jq for template scripts**, as every `skills/work-on/scripts/` script
  is, and Python for `jev_criteria.py`, as it already is.
- **Tests run on stubs.** No test sees a real decider key or calls a real endpoint.

## Considered Options

### Decision 1: Where the decision slice comes from

Resolved inline.

The slice has to list the decisions a run recorded in two states, from koto's own
record. The gate command runs in the session's working directory with koto's
variable substitution, so `{{SESSION_DIR}}` and `{{SESSION_NAME}}` are available, as
`scrutiny_verdict`'s command already uses them.

Key assumptions:

- `decision_recorded` events in the session log carry `payload.state` and
  `payload.decision` with `choice`, `rationale` and optional
  `alternatives_considered`, as the 180 measured sessions do.

#### Chosen: a script that reads the log file it is given

`skills/work-on/scripts/decision-reasons.sh slice <log-file>` reads the session log
path the gate passes (`"{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl"`) and prints
the slice with one `jq` program. The same call, on a fixture or a stored session's
log, is how fixtures and the measurement build theirs, so there is one
implementation. It calls no koto, so it can't contend with the tick that runs it.

#### Alternatives Considered

- **`koto decisions list`.** It lists the current state's decisions only, so it
  can't see `analysis` and `implementation` from `scrutiny`.
- **Resolve the log with `koto session dir`, as `panel-scope.sh` does.** It works,
  but it is a koto call inside a gate command and a second way to reach a path the
  template already substitutes; the fixtures and measurement would still need a
  file-path mode.
- **A context key the agent writes with its decisions.** The agent would choose what
  the slice holds, which jev-pass-trust's R3 forbids.

### Decision 2: How batch verdicts reach the ledger

Resolved inline.

The ledger already records decider entries checked against koto's log, but only the
ones the agent's round file names, and with blocking severity.

Key assumptions:

- `--record` runs at aggregation, after the round's gate evaluations, so the current
  visit's `decider_checked` events are in the log: the agent reaches the round only
  through the `koto next` that entered `scrutiny`, and that tick evaluated the gate.
  An event a visit writes after the round is recorded (a later tick in the same
  visit) is picked up by the next `--record` of the panel, or never if no round is
  recorded again; in shadow such an event could only have been advisory.
- Within one scrutiny visit the slice doesn't change, since it reads only `analysis`
  and `implementation` decisions.

#### Chosen: `--record` imports the panel state's events, and severity follows mode

`--record <panel>` reads the session log (`koto session dir`, then
`koto-<session>.state.jsonl`), takes every `decider_checked` event whose `state` is
the panel's state, keeps the latest per (state, visit, gate, criterion, declaration
hash), drops the ones the ledger's `decider_events` already holds or the round file
names, and adds the rest as decider entries carrying the event's `mode`. Round-file
entries get their `mode` from the event they match. The entry builder then raises a
`fail` as `advisory` when `mode` is `shadow` and `blocking` otherwise, and in shadow
records nothing for an outcome other than `pass` or `fail`. A log that doesn't exist
imports nothing; a log that exists but can't be read refuses the round (exit 65,
ledger unchanged).

#### Alternatives Considered

- **Keep the round file the only route, and tell the agent to copy events.** The
  agent could leave a fail out, and the ledger would say less about the decider than
  koto's log does.
- **Import in `--plan`.** `--plan` runs on entry, before the visit's gates evaluate,
  so it would always import the previous visit's events and never the current one's.
- **Take severity from the template's declared mode.** The effective mode can be
  lower than the declared one (a user in shadow, a project config); the event's
  `mode` is what actually happened.

### Decision 3: How rejected questions are represented and measured

Resolved inline.

Three questions can't run: evidence claims (no admissible source), justification and
intent (slices that need the diff). Their contracts still need sources, an existing
slice script, a completeness case and figures or a reason.

Key assumptions:

- A session's `context.md` holds its design context, `review_level_criteria.txt` its
  criteria text and `plan.md` its plan, as every measured session does.

#### Chosen: disabled review-shadow rows, lower bounds from `measure sessions --slice`

`rs-018`, `rs-019` and `rs-020` join `criteria.json` with observer `jev`,
`artifact_kind: local-change`, `enabled: false`, and new slice kinds `ac-claims`,
`plan-hunks` and `design-hunks` added to `review-shadow.py`'s `local-change` list.
`jev_criteria.py measure sessions` takes `--slice` (`review-facts`, the default and
today's behavior; `decision-reasons`; `criteria-plan`; `design-context`). The two
lower-bound slices are the byte lengths of the session's own keys, and the
contracts' `slice_script` is `scripts/jev-criteria/jev_criteria.py`, the script that
builds them. `rs-018` uses `not_measured: no-real-run-record`, since no run records
the claims anywhere a script can read.

#### Alternatives Considered

- **A third Jev entry kind for questions no template declares.** It would widen
  jev-pass-trust's contract rules for three entries that look exactly like `rs-007`
  to `rs-017`.
- **A new `not_measured` reason, `no-admissible-source`.** More precise, but it
  changes a closed set for one entry whose existing reason is already true.
- **Slicers in `review-shadow.py` for the full slices.** The full slices need the
  diff, which a stored session doesn't keep, so the slicers couldn't be measured, and
  nothing would run them.

### Decision 4: How the live bar leaves out not-graded evaluations

Resolved inline.

Key assumptions:

- koto writes `not_graded` only for an empty or whitespace-only slice, and the
  exported `koto.decider.outcome` carries it.

#### Chosen: drop all-`not_graded` evaluations in `live_figures`, count them separately

`live_figures` marks an evaluation graded when it sees any event that isn't a
`decider_checked` with `not_graded`, and returns the not-graded ones as a
`not_graded` count, outside `evaluations`, `sessions` and `answered`. `live_bar` is
unchanged, since it already reads only those totals. A promotion's `live` record
gains a required `not_graded` integer, which `check_promotion` checks.

#### Alternatives Considered

- **Subtract a count in `live_bar`.** `live_bar` sees only totals, so it can't tell
  which sessions had only not-graded evaluations; the session minimum would be wrong.
- **Count not-graded as answered.** Empty runs would earn trust, which the
  maintainers ruled out.

### Decision 5: Where the seat-replacement rule lives

Resolved inline.

#### Chosen: a section of `references/jev-criteria.md`, pinned by a doc test

"Replacing a seat" sits beside "Withholding", which states the analogous rule for
leaving a rule's text out, and `test_jev_criteria.py`'s doc tests pin its heading and
each condition's phrase.

#### Alternatives Considered

- **A decision record under `docs/decisions/`.** It would record that the rule was
  chosen, but the next maintainer looks for the rule where the other Jev rules are.
- **Code in `panel-scope.sh`, unwired.** No seat is eligible, so it would be dead
  code whose safety rules nobody has had a real case to test.

## Decision Outcome

The five decisions fit together around one flow. A `/work-on` run records decisions
as it analyses and builds. At `scrutiny`, for a user whose decider is on, koto runs
`decision-reasons.sh slice` on the session log and asks Jev the one shadow question;
the seats run as the scope plans them, whatever Jev answers. When the agent records
the round, `--record` imports the visit's `decider_checked` events, so a fail lands
as an advisory finding next to the seats' findings and a later pass closes it. When
Jev can't answer, koto holds the state until the agent answers, and the agent's
answer never reaches the ledger. Over time those events feed the live figures, where
a run with nothing to grade is left out rather than counted as unanswered. The
registry and `references/jev-criteria.md` carry every scrutiny question's contract,
so a maintainer can read why no seat is replaceable today and the rule the first
replacement has to follow.

## Solution Architecture

### Overview

Five changes, each in code that already exists: the registry and its criteria
(`references/rule-registry.json`, `scripts/review-shadow/criteria.json`,
`references/jev-criteria.md`), a new slice script and a gate on `scrutiny`, the
ledger's decider path in `panel-scope.sh`, and the live bar and measurement in
`jev_criteria.py`.

### Components

**`skills/work-on/scripts/decision-reasons.sh`** (new). One mode:

```
decision-reasons.sh slice <session-log>
```

It runs `jq -r` over the log with a program that selects
`type == "decision_recorded"` and `payload.state` in `analysis`, `implementation`,
and for each prints:

```
- choice: <choice>
  reason: <rationale>
  rejected: <alt>; <alt>
```

with `gsub("\\s+"; " ")` and a trim on every field, the `rejected:` line only when
`alternatives_considered` has a non-empty entry, and an empty choice or rationale
printed as the bare label. It prints nothing and exits 0 when no event matches.
Exits: 0 slice printed (or empty); 64 usage; 66 the log is missing or unreadable;
127 jq missing. A line `jq` can't parse makes `jq` fail and the script exit 66,
which koto reads as `extraction_failed`, a fallback, never a pass. It reads no other
file and no context key.

**`skills/work-on/koto-templates/work-on.md`**, state `scrutiny`, gains:

```yaml
scrutiny_decider:
  type: decider-check
  command: '"{{PLUGIN_ROOT}}/skills/work-on/scripts/decision-reasons.sh" slice "{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl"'
  max_bytes: 2560
  label: decisions
  criteria:
    work-on/scrutiny-decision-reasons:
      rule_ref: "https://github.com/tsukumogami/shirabe/blob/main/references/jev-criteria.md"
      question: "<PRD R3's question>"
      pass: "<PRD R3's pass>"
      fail: "<PRD R3's fail>"
      escape: "<PRD R3's escape>"
      mode: shadow
```

The reserved-slot comment on `scrutiny` is rewritten to describe this gate, and the
`review`, `qa_validation` and `light_review` comments that point at "scrutiny's
decider slot" are updated to say no batch is declared there. The `scrutiny`
directive gains a paragraph modelled on `review_level_check`'s: the batch runs
beside the seats for a user whose decider is on; its findings are advisory while it
is untrusted; when the check is `pending` with the criterion under `awaiting`, read
the decisions and run
`koto decider answer {{SESSION_NAME}} --gate scrutiny_decider --criterion work-on/scrutiny-decision-reasons --answer <pass|fail|unclear>`,
answering only a listed criterion and never recording an override to get past it;
and this can hold a carried round too. `koto-templates/work-on.mermaid.md` gains the
gate's note under `scrutiny`. `phase-4a-scrutiny.md` gains a short "Decider batch"
paragraph with the same facts and command.

**`skills/work-on/scripts/panel-scope.sh --record`**:

1. After the round file's shape checks, resolve the session log (`koto session dir`;
   a missing log file imports nothing, an unreadable one is exit 65).
2. Import: `jq` over the log selects `decider_checked` events whose `state` is the
   panel's state (`scrutiny` for `scrutiny`, `review`, `qa_validation` for `qa`,
   `light_review` for `light`), groups by `state|visit_seq|gate|rule_id|
   declaration_hash`, keeps one event of each group (a `fail` if the group has
   one, so the most severe outcome wins, and otherwise the last), passes every
   name to `jq` with `--arg`, and removes keys already in the
   ledger's `decider_events` or named by a round-file entry. Each survivor becomes a
   `{"decider": {state, visit_seq, gate, rule_id, declaration_hash, input_sha256,
   outcome, mode}}` entry appended to the round's entries.
3. For a round-file entry, the existing log match also reads the matched event's
   `mode` into the entry.
4. The existing registry check (every rule id an active registry entry) runs over
   imported entries too.
5. In the entry builder: `fail` raises with severity `advisory` when `mode` is
   exactly `shadow`, `blocking` otherwise (a missing or unknown mode included);
   `pass` adds a `reverified` record when the finding exists, and that finding's
   id is the one computed from this criterion, so a decider's pass can close only
   its own criterion's finding, never a seat's; any other outcome adds nothing
   when `mode` is `shadow`, and
   otherwise keeps today's `unverified` behavior. `raise`'s existing rule keeps a
   blocking finding blocking on a re-raise.

**`scripts/jev-criteria/jev_criteria.py`**:

- `live_figures` tracks, per evaluation, whether any event isn't a
  `decider_checked` with outcome `not_graded`; at the end it splits evaluations into
  graded and not graded, counts sessions over graded ones only, and returns
  `not_graded` beside the existing fields.
- `check_promotion` requires `live.not_graded` as a non-negative integer.
- `measure sessions` gains `--slice` with `review-facts` (default),
  `decision-reasons` (runs `decision-reasons.sh slice` on each session's
  `koto-*.state.jsonl`, counting an empty slice as a run of 0 bytes),
  `criteria-plan` (the byte lengths of `ctx/review_level_criteria.txt` plus
  `ctx/plan.md`) and `design-context` (`ctx/context.md`), reading regular files
  only (a symlink is skipped and counted on stderr), over every session
  directory under `--dir` that has `ctx/review_facts.json`. The recorded `command`
  names the slice.

**Registry and criteria**: entries `rs-018`, `rs-019`, `rs-020` (`check.kind:
review-shadow`, `level: shadow`, `withhold: never`, `text` on the seat's line in
`phase-4a-scrutiny.md`, empty `baseline_keys` with a note that they were registered
after the baseline pin, `rs-018`'s note naming `rs-015`, whose line it shares) and
`work-on/scrutiny-decision-reasons` (`check.kind: decider`, `level: gate`, `timing:
["work-on:scrutiny"]`, `withhold: never`, `text` on the decider paragraph of
`phase-4a-scrutiny.md`). `criteria.json` gains the three rows with `enabled: false`;
`review-shadow.py`'s `SLICE_KINDS_BY_ARTIFACT["local-change"]` gains `ac-claims`,
`plan-hunks` and `design-hunks`. `scripts/rule-registry_test.sh`'s pinned counts move
with them. Fixture file
`scripts/jev-criteria/fixtures/work-on-scrutiny-decision-reasons.jsonl`.

**`references/jev-criteria.md`** gains sections `rs-018`, `rs-019`, `rs-020`,
`work-on/scrutiny-decision-reasons` (each with sources, slice, completeness, figures,
state), the not-graded rule in "The bars", and "Replacing a seat". **
`docs/guides/jev-criteria.md`** gains the not-graded rule in "Reading the live
figures" (definitions and query steps).

### Key Interfaces

- `decision-reasons.sh slice <log>`: stdout is the slice; exits above.
- Gate `scrutiny_decider`, criterion `work-on/scrutiny-decision-reasons`, shadow,
  2,560 bytes, label `decisions`.
- `panel-scope.sh --record <panel> <session> <round-file>`: unchanged arguments; the
  ledger's decider entries may now come from the log, carry `mode`, and raise
  advisory findings.
- `jev_criteria.py measure sessions --dir <koto sessions> --slice <kind> --budget N`;
  `figures` output and a promotion's `live` record gain `not_graded`.

### Data Flow

```
analysis / implementation ──koto decisions record──▶ session log (decision_recorded)
                                                         │
scrutiny entry ──▶ panel-scope.sh --plan (unchanged) ─▶ scrutiny_scope.json ─▶ seats spawned
              └──▶ gate scrutiny_decider (decider on):
                     decision-reasons.sh slice <log> ─▶ Jev (shadow) ─▶ decider_checked
                     (can't answer ─▶ pending ─▶ agent: koto decider answer)
aggregation ──▶ panel-scope.sh --record scrutiny:
                  round file + imported decider_checked ─▶ verdict_ledger.json
                  (shadow fail = advisory; veto/no-mode fail = blocking; pass = reverified)
scrutiny_verdict ──▶ panel-scope.sh --verdict (blocking only)
exported decider events ──▶ live figures (not-graded left out) ─▶ a later promotion
```

## Implementation Approach

### Phase 1: Contracts for the questions nothing can run, and the seat rule

Add `--slice` to `measure sessions` with the two byte-length slices
(`criteria-plan`, `design-context`) beside the default `review-facts`, the three
`local-change` slice kinds, the `rs-018` to `rs-020` rows and registry entries,
their sections in `references/jev-criteria.md`, the registry-count updates, and the
"Replacing a seat" section with its doc test, which edits the same reference.

Deliverables: `scripts/jev-criteria/jev_criteria.py`,
`scripts/jev-criteria/test_jev_criteria.py`, `scripts/review-shadow/review-shadow.py`,
`scripts/review-shadow/criteria.json`, `references/rule-registry.json`,
`references/jev-criteria.md`, `scripts/rule-registry_test.sh`.

### Phase 2: Leave not-graded evaluations out of the live bar

Change `live_figures` and `check_promotion`, add the figures and bar tests (mixed
evaluations named: not-graded with a fallback, with `escape`, with a later `pass`),
and state the rule in both Jev-criteria documents with a doc test. Independent of
Phase 1; it can land first or beside it.

Deliverables: `scripts/jev-criteria/jev_criteria.py`, its tests,
`references/jev-criteria.md`, `docs/guides/jev-criteria.md`.

### Phase 3: The batch

Add `decision-reasons.sh` and its test, the `decision-reasons` slice of
`measure sessions` (which runs the script), the fixture file, the `scrutiny_decider` gate, the registry entry and its section, the
directive and phase-file text, the mermaid note, the comment rewrites, a koto-level
routes test (pending holds a carried round; answer releases; empty slice doesn't
hold; 2,560 versus 2,561 bytes; decider off unchanged), and an eval scenario for a
pending batch. Depends on Phase 1's `--slice`.

Deliverables: `skills/work-on/scripts/decision-reasons.sh`,
`skills/work-on/scripts/decision-reasons_test.sh`,
`skills/work-on/scripts/scrutiny-decider-routes_test.sh`,
`skills/work-on/koto-templates/work-on.md`, `work-on.mermaid.md`,
`skills/work-on/references/phases/phase-4a-scrutiny.md`,
`skills/work-on/evals/evals.json`, the registry, criteria reference and fixtures.

### Phase 4: Batch verdicts in the ledger

Change `--record`'s decider path and add its tests, including one import for the
`qa` panel's state (`qa_validation`) from a fixture event, so the panel-to-state
mapping is exercised beyond `scrutiny`. Depends on Phase 3's registry entry for the
criterion id the tests record under.

Deliverables: `skills/work-on/scripts/panel-scope.sh`,
`skills/work-on/scripts/panel-scope_test.sh`.

## Security Considerations

**Agent-written text reaches a classifier.** The slice is built from reasons the
agent under review wrote, so it can carry text aimed at steering the decider. The
batch is in shadow: no route reads it, a `fail` is advisory, other non-pass outcomes
add nothing, and a `pass` adds a `reverified` record only to the finding computed
from the same criterion, so an injected pass can't close a seat's finding. The
slice is capped at 2,560 bytes, and each field's whitespace is collapsed so a field
can't start a new line, though it can still mimic the layout inline (`... reason:
...`). The fixture file's adversarial cases cover an instruction, a fake answer, a
role line and inline layout mimicry, and they are what a later promotion is judged
on.

**The ledger trusts koto's log.** `--record` imports `decider_checked` events from
the session log, as the round-file path already checks entries against it. The log
sits in a directory the agent can write to, and events aren't signed, so the design
relies on the filesystem boundary, as the existing path does. What a forged line can
do is bounded: an imported event must name an active registry id, each (state,
visit, gate, criterion, declaration hash) backs one entry, the most severe outcome of
a group wins rather than the latest, and in shadow the worst it can add is an
advisory finding.

**Severity fails closed.** Only an event whose `mode` is exactly `shadow` gives an
advisory finding; a missing or unrecognised mode keeps today's blocking behavior. A
shadow check never holds the verdict gate. The one hold is koto's pending state when
the decider can't answer, released by `koto decider answer`, whose answer never
reaches the ledger.

**Parsing.** The slice script and `--record` read the log with `jq` and pass state
names and ids as `--arg` values, never by interpolating them into a program. A parse
failure is a fallback (`extraction_failed`) or a refused round, never a pass. The
slice script reads one path koto substituted, calls no koto and no network, and
writes nothing.

**Data leaving the machine.** For a user who opts into the decider, the slice (at
most 2,560 bytes of the run's recorded decisions) goes to the decider endpoint on
each scrutiny visit. koto passes every decider-check command's output through its
capture redactor before anything reads it, which replaces known credential shapes
but not a secret an agent wrote in plain words, so a rationale should never hold
one. The session log and koto's decider ledger keep a hash and a byte count, not the
text. A user whose decider is off sends nothing.

**Supply chain and tests.** No new dependency or download is added. Tests and CI use
stubbed logs or a loopback stub with a placeholder key, unset any inherited decider
key first, and send nothing anywhere; fixtures are synthetic; measurement output is
counts and byte lengths only.

**Gate command arguments.** The command substitutes `{{SESSION_DIR}}` and
`{{SESSION_NAME}}` inside double quotes, as `scrutiny_verdict`'s command already
does; koto refuses a session name outside its own name pattern at `koto init`, so
neither value can carry shell syntax. `--record`'s session argument is the one the
agent already passes for every ledger write, and the import reads that session's
log only.

**Residual risk.** An agent with shell access can write to its own session log.
Three things follow, and none is new in kind, since the round-file path already
trusts the same log:

- It can append a forged `decider_checked` event, or set a real event's `mode` to
  `shadow`, and so add an advisory finding or turn a blocking batch finding
  advisory in the ledger. It can't get past a veto fail that way: koto's own
  `decider-check` gate blocks the state on a veto fail from its evaluation, not from
  the ledger, and only an override record moves past it.
- It can leave its decisions unrecorded, which gives the batch nothing to grade, or
  push its slice over budget, which falls back. The second counts against the live
  bar outright (no over-budget fallback is allowed). The first is outside what the
  criterion judges, and a promotion's `live` record carries the not-graded count so
  its reviewer can weigh how much of the evidence the agent shaped.
- It can stall its own run by making the log unreadable.

Opting into the decider is per user, so a user who opts in sends the decisions of
every repository they run `/work-on` in, private ones included, under the same
redaction; that is the user's choice and is unchanged by this design.

## Consequences

### Positive

- The question "which scrutiny seat could a decider replace" has a recorded,
  checkable answer (none today), with the figures and the rule that would change it.
- Every user whose decider is on starts producing evidence for one closed check,
  with no change to which seats run.
- A shadow decider check can't block a panel or spend a retry, on scrutiny or on any
  panel that later declares one.
- The live bar can admit a criterion that often has nothing to grade, which any
  future empty-prone criterion needs too.

### Negative

- Every scrutiny visit for a decider-on user adds one Jev call, and a decider outage
  holds the run at scrutiny until the agent answers, carried rounds included.
- The batch judges only whether recorded reasons are reasons; it doesn't save a
  seat, so the panel costs what it did plus the call.
- `--record` now reads the session log on every round, not only when a round file
  names a decider entry.
- The graded-only over-budget share (5.7%) sits past the 5% line even though the
  contract passes over all sessions.

### Mitigations

- The hold happens only when the decider can't answer, never on an empty slice, and
  the directive gives the one command that releases it.
- The batch's figures are what the next decision about seat replacement needs; the
  cost is one call per scrutiny visit for opted-in users only.
- The log read is one `jq` pass over a file koto already wrote; a missing log is a
  no-op.
- The written case states both shares, and the next measurement with more graded
  runs re-decides the state.

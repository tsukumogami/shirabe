---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-check-lifecycle.md
problem: |
  Every gate script reports every registered rule at level error through
  one shared library, so a check either holds the run or doesn't exist. The
  registry has no field for how a check should behave or since when, nothing
  ties a rule to the koto gates that evaluate it, and koto's journal and
  response drop whatever a passing check reports, so a gentler stage could
  be neither enforced nor counted.
decision: |
  Script-checked registry entries gain `stage`, `stage_since`, `gates` and,
  for guarded rules below block, `stage_backstops`. The shared findings
  library reads each rule's stage, prints its finding at the matching level
  (block error, warn warning, shadow info, retired nothing) and counts only
  block findings toward the exit. The registry check validates the fields,
  the safety rule and the gate names, and compares stages with the merge
  base for transitions. A jq reader turns koto journal lines into per-rule
  figures and the criterion met. A companion koto change journals every
  finding as `check_finding`, puts a passing check's warnings on the
  response as `advisories`, and adds `koto disputes record`, journaled as
  `check_disputed`. shirabe ships a dispute wrapper that falls back to a koto
  decision on older koto.
rationale: |
  The library is the one place every finding already passes through, and the
  registry check already validates vocabularies and compares with the merge
  base, so both changes land where the code already looks. New fields keep
  `status`, `level` and `backstop` meaning what they mean today. koto's
  additions are siblings of existing records rather than changes to them, so
  nothing that already counts `check_rule` shifts. Older koto keeps working
  because a gentle finding exits 0 and koto ignores what a passing check
  prints.
decision_provenance: inline-resolved
---

# DESIGN: Check lifecycle

## Status

Proposed

## Context and Problem Statement

shirabe's gate scripts are the deterministic checks koto runs as command
gates. Five of them report registry rules: `check-pr-output.sh`,
`check-branch-output.sh`, `check-verification.sh` and `panel-scope.sh` under
`skills/work-on/scripts/`, and `check-hop-document.sh` under
`skills/scope/scripts/`. Each sources `scripts/lib/rule-findings.sh`, resolves
its rules with `rf_require`, prints findings with `rf_finding` (or builds them
and prints with `rf_emit`), and exits 1 when it printed any. `rf_finding`
hard-codes `level: "error"`. So the only behaviour a check has is to hold the
run, and the only way to stop a check is to delete its code and retire its
registry entry.

The registry, `references/rule-registry.json`, has 37 script entries (35
active) beside 17 review-shadow criteria and one prose rule. An entry's
`status` says whether the rule applies (`retired` forces `rf_require` to exit
2 and the id off every `RULE_IDS` line), its `level` says whether a gate holds
on it (`gate`), a review-shadow trial grades it (`shadow`) or nothing does
(`prose`), and its `timing` names skill states. Nothing names the koto gate a
rule's evaluations come from, which is what a per-rule rate needs as its
denominator: koto's journal records each evaluation as `check_evaluated` with
the state and gate name (`koto.check`), and each error rule of a failing
evaluation as `check_rule` with `koto.rule.id`.

The PRD asks for four stages per deterministic rule: `shadow` logs the finding
without holding or showing it, `warn` shows it without holding, `block` holds
as today, and `retired` doesn't run, all carried in the registry with the date
the stage was set (its R1 to R3). Stage changes follow fixed transitions
checked against the merge base (R4), and a rule guarding a protected action
(`pr-create`, `push`, `force-push`, `merge`, `close-issue`, `release`,
`delete-branch`, `publish`, `destroy-record`) leaves `block` only when another
deterministic check is declared for each such action (R5). Each rule names its
gates (R6). Gate scripts print a rule's finding at the level its stage maps to
and exit on block findings alone, with three script-specific cases (R7 to
R11). Criteria for promotion, demotion and retirement are thresholds over
per-rule figures computed from journal records (R16, R17), read by a shipped
reader (R19) and applied only by reviewed registry changes (R18). An agent or
person can dispute a finding without moving the run (R14, R20).

Three limits in koto stand in the way, all confirmed by reading koto's source.
`check_rule` is written only for error rules of a failing check. A passing
check's findings reach the session log's `gate_evaluated` event (since koto's
failure-reporting work) but no journal record and no `koto next` response.
And no event records a dispute; an override moves the run and its journal
record names only the gate. The PRD puts the koto change in this feature as a
separate pull request (R12 to R15), and requires shirabe to work on koto
0.20.0, its current floor, until a koto release carries it (R22).

## Decision Drivers

- **Nothing that blocks today stops blocking.** Every active script rule
  starts at `block`; 34 of the 35 guard a protected action.
- **One place for the mapping.** The stage-to-level mapping and the exit rule
  belong where every finding already passes, not in five copies.
- **Existing meanings hold.** `status`, `level`, `backstop`, `withhold`,
  `deny` and koto's `check_rule` keep their meaning, so readers and the
  pre-action hook see no change.
- **Countable from the journal alone.** Every figure has to come from journal
  lines koto writes during real runs; nothing runs outside a session (R25).
- **Safe on koto 0.20.0.** A shirabe release with stages must not hold a run
  that today's shirabe wouldn't, on a koto without the companion change.
- **Bash 3.2 and jq.** Scripts keep the macOS floor; the registry check and
  readers are bash, awk and jq.
- **Additive koto change.** No schema bump; v0.14.1 still reads the log (R15).
- **Exported names reviewed.** New journal kinds and `koto.*` names go to the
  measurement owners for review before koto's side is accepted; they must not
  collide with existing names, including the nested form a log backend gives
  `koto.check` on `check_evaluated` (`koto.check.name`).

## Considered Options

### Decision 1: How the registry carries the lifecycle

Resolved inline.

The registry needs a stage per script entry, the date it was set, a way to
name the other deterministic check that backs a guarded rule below block, and
the gates whose evaluations count for the rule. Key assumptions:

- The deny evaluator in `crates/shirabe` ignores entry fields it doesn't know,
  so new fields don't change a compiled hook's behaviour.
- Gate names are stable; a rename updates the entries naming it in the same
  change.

#### Chosen: four new fields on script entries

`stage` (`shadow`, `warn`, `block`, `retired`), `stage_since` (`YYYY-MM-DD`),
`gates` (a list of `<skill>:<state>:<gate>`), and `stage_backstops` (a list of
`{"before": <protected action>, "check": <path>}`), the last required only
when a guarded rule sits below `block`. Every script entry carries the first
three; no other entry carries any. `status: retired` entries are at `retired`
and may leave `gates` empty. The fields are flat, so the registry check's
existing jq program validates them the way it validates `withhold`.

#### Alternatives Considered

**Reuse `status` and `level`**: `status: retired` already means the rule no
longer applies and its id must leave `RULE_IDS`, while a check retired for
going quiet still guards a rule whose text loads; `level: shadow` already
names the review-shadow trial. Rejected because both would change what
existing entries mean.

**One nested `lifecycle` object**: groups the fields but forces the flat jq
checks and every reader to reach one level deeper, for no behaviour gained.
Rejected.

**Derive gates from templates at read time**: saves a field but makes the
figures reader parse koto templates, and a renamed gate would silently stop
counting. Rejected: storing the names lets the registry check verify them once
and fail loudly.

**Extend `backstop` to guarded rules**: one field instead of two, but
`backstop` serves withholding and requires `guards: ["none"]` and `withhold:
eligible`; widening it would change the withhold safety rules the PRD says
stay unchanged. Rejected.

### Decision 2: Where gate scripts apply the stage

Resolved inline.

Every finding a gate script prints goes through `rf_finding` or `rf_emit` in
`scripts/lib/rule-findings.sh`. Each script decides its own exit from its own
counter. Key assumption: findings are printed from the script's main shell,
so a counter the library keeps survives to the exit (true of all five today).

#### Chosen: the library applies the stage; scripts exit on its block counter

`rf_require` and `rf_require_any` cache each rule's stage beside its reference
and summary. `rf_finding` and `rf_emit` print the finding at the stage's level,
print nothing for `retired`, and increment `RF_BLOCKING` for `block`. Each
script exits 1 when `RF_BLOCKING` is non-zero instead of when its own counter
is. Three scripts need small local changes: `check-verification.sh` ranks its
route over block-stage lines only; `check-pr-output.sh` adds its fallback only
when the validator listed nothing and releases PB4's text only when PB4 is
shown; `panel-scope.sh` passes `panel/open-finding` as the stage source for
every finding it emits.

#### Alternatives Considered

**Per-script handling**: each script maps the stage itself. Rejected: five
copies of one mapping, and the next gate script would need a sixth.

**Filter output in a wrapper**: a wrapper rewrites levels and the exit. Rejected
because the exit code of `check-verification.sh` is a route chosen inside the
script, which a filter can't recompute without re-implementing it.

### Decision 3: How transitions and the safety rule are enforced

Resolved inline.

Transitions need the previous stage; the safety rule needs the entry alone.
Key assumption: CI keeps running the registry check with `--base` against the
merge base and a full fetch.

#### Chosen: shape and safety in the jq program, transitions beside check 11

The registry check's jq program validates the new fields' shape and the safety
rule. A new numbered check verifies `gates` against the templates. Under
`--base`, a check beside the existing removed-id comparison (check 11) joins
base and head entries by id and refuses any stage change outside R4's list.

#### Alternatives Considered

**A stage history list in each entry**: carries the previous stage without a
base, but grows forever and can be edited in the same change as the stage it
should constrain. Rejected.

**A pull-request label or body check**: invisible to the registry check and
untestable locally. Rejected.

### Decision 4: What form the criteria take

Resolved inline.

The PRD wants the criteria as thresholds over journal records and a reader
that prints the figures. Key assumption: the reader is given koto's own line
format (one flat JSON object per line with dotted keys), as the host journal
and an export in that format both are.

#### Chosen: `scripts/rule-lifecycle.sh figures`, a jq reader, plus definitions

A bash script with one jq program reads journal lines and the registry and
prints one line (or JSON object) per script rule. `references/check-lifecycle.md`
defines each figure field by field, so the same figure can be computed by a
query in a log backend.

#### Alternatives Considered

**Documented queries only**: nothing tests them, and thresholds drift from
the text. Rejected.

**A `shirabe` Rust subcommand**: typed, but a threshold change would need a
binary release, and every other registry reader is a script. Rejected.

### Decision 5: What koto adds

Resolved inline.

koto has to journal findings of every level and of passing checks, show a
passing check's warnings to the agent, and record a dispute that moves
nothing. Key assumptions: the measurement owners may rename attributes in
review; koto's 50-finding event cap is enough for shirabe's gates.

#### Chosen: sibling records, a derived response field, a non-advancing verb

A new journal kind `check_finding`, one record per distinct rule id and level
of an evaluation; two new fields on `check_evaluated`; a top-level
`advisories` response field derived from the tick's events, as `attempts`
already is; and `koto disputes record`, which appends a `finding_disputed`
session event and a `check_disputed` journal record and reads nothing the
advance loop routes on.

#### Alternatives Considered

**Write `check_rule` for every level**: one kind instead of two, but readers
already count `check_rule` as error rules of failing checks, and every such
count would change. Rejected.

**Put passing warnings in `blocking_conditions`**: no new key, but the agent
reads that list as what's holding it. Rejected.

**Dispute through `koto overrides record`**: already journaled, but it moves
the run past the gate, which would let an agent past a check guarding a push
by disagreeing with it. Rejected.

**Dispute through `koto decisions record` only**: exists today, but decisions
aren't journaled, so a dispute would never reach the figures. Kept only as
shirabe's fallback on older koto.

## Decision Outcome

The registry becomes the one place a check's behaviour is set: a reviewed
change to `stage` is the only way a check gets gentler or stricter, the
registry check refuses changes that skip promotion steps or soften a guarded
rule without a declared backstop, and `gates` ties each rule to the
evaluations that measure it. The library turns that stage into the finding's
level and decides whether the finding counts, so the five gate scripts change
only where their exit logic is unusual. koto's companion change makes every
finding countable and every warning visible, and the reader turns journal
lines into figures and a criterion, which a stage-change pull request quotes.
On koto 0.20.0 the shirabe half is safe on its own: block behaves as before,
a gentle finding exits 0 and is dropped by koto, and a dispute is kept in the
session as a decision.

## Solution Architecture

### Overview

```
registry entry ──stage──▶ rule-findings.sh ──level, RF_BLOCKING──▶ gate script exit
     │                                                                  │
     │ gates                                         ::koto-finding:: lines, exit
     ▼                                                                  ▼
check-rule-registry.sh                                      koto gate evaluation
(shape, safety, gates, transitions)                                     │
                                         check_evaluated + check_finding (+ check_rule)
                                         advisories on the response
                                                                        ▼
rule-dispute.sh ──▶ koto disputes record ──▶ check_disputed     koto run journal
                                                                        │
                                                                        ▼
                                                   rule-lifecycle.sh figures ──▶ criterion
```

### Components

**Registry fields** (`references/rule-registry.json`):

```json
{
  "id": "pr-body/one-separator",
  "status": "active",
  "check": {"kind": "script", "path": "skills/work-on/scripts/check-pr-output.sh", "mode": "--pr-body"},
  "level": "gate",
  "guards": ["pr-create", "publish"],
  "stage": "block",
  "stage_since": "2026-10-16",
  "gates": ["work-on:pr_creation:pr_body_conformant", "execute:pr_finalization:owned_pr_body_conformant"]
}
```

A guarded entry below `block` adds, for example:

```json
"stage_backstops": [
  {"before": "pr-create", "check": "hooks/pre-action-deny.sh"},
  {"before": "publish", "check": ".github/workflows/validate-pr-body.yml"}
]
```

The migration sets `stage: block` on every active script entry and `stage:
retired` on the two `status: retired` ones, `stage_since` to the date the
change lands, and `gates` from each entry's `timing` states and the templates'
command gates that run its script.

**`scripts/rule-registry.sh`** gains `stage <id>`, printing the entry's
effective stage for an active or a `status: retired` entry, and failing for an
id with no entry or a non-script entry. It fails closed: it prints `block` for
a script entry with no stage (an older registry), for a stage outside the four
values, and for an active entry whose guards include a protected action and
whose stage isn't `block` while `stage_backstops` doesn't cover every such
guard. That repeats the registry check's safety rule at run time, so a
registry edited without passing CI still can't soften a guarded rule. `verify-findings` also fails a finding whose level isn't the
one its rule's stage maps to.

**`scripts/lib/rule-findings.sh`**:

- `RF_CACHE` lines gain a fourth column, the stage, filled by `rf_require` and
  `rf_require_any` through `rule-registry.sh stage`.
- `rf_stage <id>` prints a resolved rule's stage; `rf_level <stage>` maps
  `block`→`error`, `warn`→`warning`, `shadow`→`info`.
- `rf_finding <id> <detail> [<path> [<line>]]` returns without printing for a
  `retired` rule; otherwise it prints at the mapped level, and for `block` it
  increments `RF_BLOCKING`. It sets `RF_COUNTED` to 1 or 0 so a caller can tell
  whether the finding it just printed counts.
- `rf_emit <json> [<stage-id>]` sets the finding's `level` from the stage of
  `<stage-id>` (default: the finding's own `rule_id`) before its existing
  checks, with the same retired and counting behaviour.
- `rf_dispute_hint` prints one line on standard error naming
  `scripts/rule-dispute.sh` and its arguments, for a script about to exit 1 on
  block findings.

**Gate scripts**, each replacing its own exit test with `RF_BLOCKING`:

| Script | Change |
|---|---|
| `check-branch-output.sh` | `exit 1` per mode when `RF_BLOCKING` > 0, after `rf_dispute_hint`. |
| `check-hop-document.sh` | Same. Its late resolution keeps working: `rf_require` caches the stage when it resolves. |
| `check-verification.sh` | Prints findings first, then ranks the route over lines whose rule's stage is `block`; exits 0 when no block line remains. |
| `check-pr-output.sh` | Fallback `pr-body/conformance` only when the validator listed no finding; PB4 text released only when `rf_stage pr-body/no-heading-in-part1` is `warn` or `block`; exit 1 only on `RF_BLOCKING`. |
| `panel-scope.sh` | Calls `rf_emit "$json" panel/open-finding`, so every finding takes the panel rule's stage. |

The pre-action hook and `shirabe pre-action-hook` don't read `stage`, so a
`deny` keeps denying at every stage.

**`scripts/check-rule-registry.sh`**:

- In the shape program: `stage`, `stage_since`, `gates` required on script
  entries and absent elsewhere; vocabularies and the date pattern; `status:
  retired` implies `stage: retired`; `gates` non-empty on an active script
  entry and each value matching `^[a-z0-9-]+:[a-z0-9_]+:[a-z0-9_]+$`;
  `stage_backstops` entries with `before` in the protected set, unique, and a
  non-empty `check`; for an active script entry whose guards include a
  protected action and whose stage isn't `block`, every protected guard
  covered by a backstop whose `check` isn't the entry's `check.path`.
- In the existence check: every `stage_backstops[].check` path exists.
- A new numbered check for `gates`: an awk pass over each skill's
  `koto-templates/*.md` (not `*.mermaid.md`) frontmatter lists every command
  gate as `state`, `gate`, `command`; a value fails when no such line exists,
  or when the command names no script whose `RULE_IDS` line lists the id,
  except a command naming `panel-scope.sh`, which may report any active rule.
- Under `--base`, beside check 11: base and head entries joined by id; a new
  entry may start at `shadow`, `warn` or `block`; a change of stage must be
  one of R4's and must raise `stage_since`; a status change to `retired` must
  set the stage to `retired`; a `status: retired` base entry may not change
  status or stage.

**`scripts/rule-lifecycle.sh figures [--json] [<file>...]`** reads journal
lines from files or standard input and the registry beside it, and runs one jq
program:

1. Keep records whose `at` date is on or after the rule's `stage_since`, and
   take the window's end as the newest `at` among all input lines.
2. Evaluations: `check_evaluated` records carrying `koto.check.finding_count`
   whose (`koto.state`, `koto.check`) is one of the rule's gates' state and
   gate, keyed by `koto.session.id` and `koto.seq`.
3. Fires: those evaluations with a `check_finding` record for the rule at the
   same session and `koto.seq`, counted once per evaluation and by
   `koto.finding.level`.
4. Disputes: `check_disputed` records naming the rule at one of its gates, by
   `koto.dispute.source`.
5. Unconverged visits: (`koto.session.id`, `koto.visit.seq`) pairs with an
   `error` fire for the rule and no `passed` evaluation of the same gate in
   that visit.
6. The first criterion of R17's table the rule meets, or `hold`.

It prints `id stage days evaluations fires_error fires_warning fires_info
passes disputes_agent disputes_person unconverged criterion`, tab-separated,
or one JSON object per rule with `--json`; exit 0, or 2 when the registry or
an input can't be read. It writes nothing.

**`scripts/rule-dispute.sh --session <name> --gate <gate> --rule <id> --reason
<text> [--state <state>] [--by agent|person]`** refuses (exit 2) a rule id
`rule-registry.sh ref` can't resolve as an active entry. When `koto disputes
--help` succeeds it runs `koto disputes record` with the same arguments and
prints `dispute=journaled`; otherwise it runs `koto decisions record <session>
--with-data` with `{"choice": "dispute:<id>", "rationale": "gate=<gate>
state=<state> by=<by>: <reason>"}` built by jq and prints
`dispute=session-only`. Arguments reach koto as separate words, never through
a shell string.

**`references/check-lifecycle.md`** states the stages and their gate
behaviour, the transitions, the safety rule, the figures field by field (with
the nested names a log backend gives them, such as `koto.check.name` on
`check_evaluated`), the thresholds, the dispute path, and how to run the
reader for a stage-change pull request. `references/rule-registry.md`
describes the four fields and links it.

**koto (separate pull request in `tsukumogami/koto`)**:

- `src/run_journal/mod.rs`: in the gate and default-action arms of
  `relayed()`, after `with_rules`, a `with_findings` step appends one
  `check_finding` per distinct (`rule_id`, `level`) of the event's logged
  findings, in first-seen order within level, `error` pairs first, then
  `warning`, then `info`, then other levels, at most 50. `check_evaluated`
  gains `koto.check.finding_count` (the logged findings' length, 0 included)
  and `koto.check.findings_truncated` (when true). A new arm relays
  `finding_disputed` as `check_disputed`. The records go in the same write as
  their evaluation's, as `check_rule` records do.
- `src/engine/advance.rs` and `src/cli/mod.rs`: `advance_until_stop_recording`
  collects, from the tick's events, `gate_evaluated` events with outcome
  `passed` and passing `default_action_executed` events that carry `warning`
  findings, into `AdvanceResult.advisories`; `handle_next` attaches
  `advisories` after `attempts` when non-empty, capped at 100 findings. The
  `--to` path and `koto status` don't.
- `src/cli/disputes.rs` (new): `koto disputes record`, validating as the PRD
  says, appending `finding_disputed` through the same append path overrides
  use, printing `{"status":"recorded"}`.
- `src/engine/types.rs`: the `FindingDisputed` event variant and type name.
- Docs: `docs/reference/run-journal.md`, `docs/reference/session-feed.md`
  (frontmatter and catalogue), the koto-user skill's response shapes and
  command reference, `docs/guides/cli-usage.md`, `CHANGELOG.md`.
- Tests: journal field allowlists and line-cap tests for the new kinds,
  relay tests (pass with error and warning findings, dedupe, truncation,
  zero findings), the response baseline unchanged, `advisories` presence and
  cap, dispute validation and no-advance, a validate-feed declaration case,
  and a compat job running a new build's log through v0.14.1.

### Key Interfaces

**Journal records** (koto's line format; names provisional until the
measurement owners' review):

| Kind | Fields beyond the identity fields |
|---|---|
| `check_finding` | `koto.seq`, `koto.visit.seq`, `koto.state`, `koto.check`, `koto.attempt`, `koto.visit_attempt`, `koto.rule.id`, `koto.finding.level`, `koto.finding.count` |
| `check_evaluated` (added) | `koto.check.finding_count` (always), `koto.check.findings_truncated` (when true) |
| `check_disputed` | `koto.seq`, `koto.visit.seq`, `koto.state`, `koto.check`, `koto.rule.id`, `koto.dispute.source` |

`koto.rule.id` follows the existing rule for ids outside the name shape (a
`sha256:` digest). `koto.check` stays a scalar on both new kinds, as on
`check_rule`, since neither carries a `koto.check.*` field.

**Session event** `finding_disputed`: `state`, `gate`, `rule_id`, `reason`,
`source`.

**Response field** `advisories`: `[{"state": ..., "gate": ..., "findings":
[<finding object>, ...]}]`, finding objects in koto's existing shape.

**Stage to level**: `block`↔`error`, `warn`↔`warning`, `shadow`↔`info`.

### Data Flow

A gate script resolves its rules, now with their stages, checks its input and
prints findings at their stages' levels. It exits 1 only if a block finding
printed, after one dispute-hint line on standard error. koto records the
evaluation: on a failing check the agent sees the failure as today; with the
companion change, every finding also lands as a `check_finding` record, and a
passing check's warnings land on the response as `advisories`. An agent that
disagrees runs `rule-dispute.sh`, which records a `finding_disputed` event and
a `check_disputed` record, or a koto decision on older koto. Later, someone
preparing a stage change runs `rule-lifecycle.sh figures` over the host's
journal (or lines exported in koto's format), reads the rule's figures and
criterion, and opens a registry pull request changing `stage` and
`stage_since` with that output in the body. The registry check holds the pull
request to R4 and R5.

## Implementation Approach

### Phase 1: Registry fields and their check

Add `stage`, `stage_since` and `gates` to every script entry and
`rule-registry.sh stage`; extend `check-rule-registry.sh` with the shape,
safety, existence, gates and transition checks; update
`references/rule-registry.md`.

Deliverables:
- `references/rule-registry.json`, `scripts/rule-registry.sh`,
  `scripts/check-rule-registry.sh`, their test suites,
  `references/rule-registry.md`

### Phase 2: Stage-aware findings library and gate scripts

Depends on Phase 1's `stage` reader. Extend the library and
`verify-findings`, then switch each gate script's exit to `RF_BLOCKING`, with
the three script-specific changes and the dispute hint.

Deliverables:
- `scripts/lib/rule-findings.sh`, `scripts/lib/rule-findings-testlib.sh`,
  `scripts/rule-registry.sh`, the five gate scripts and their suites

### Phase 3: Figures reader, dispute wrapper and reference

Depends on Phase 1's fields. Add `rule-lifecycle.sh` and `rule-dispute.sh`
with fixture-driven suites, and write `references/check-lifecycle.md`.

Deliverables:
- `scripts/rule-lifecycle.sh`, `scripts/rule-dispute.sh`, their suites,
  `references/check-lifecycle.md`

### Phase 4: koto companion change (tsukumogami/koto)

Independent of the shirabe phases. Journal kinds and fields, the response
field, the dispute verb, docs, tests and a compat job, in one koto pull
request that stays unmerged until koto's own merge window.

Deliverables:
- the koto files listed under Components

## Security Considerations

The new surfaces take input from three places, and each is treated as data.

**Finding and journal text.** Finding messages come from gate scripts, which
already replace control characters; koto already redacts known credentials in
findings and never journals a message. The new `check_finding` and
`check_disputed` records carry only names, ids, levels and counts, copied
through koto's existing name-shape and digest rules, so no free text and no
credential reaches the journal. A dispute's reason, which an agent writes, is
kept in the session log and never journaled, following the override
rationale's precedent; it's bounded at 1,000 bytes.

**`advisories` on the response.** Its findings are the same objects koto
already returns in `failure`, so koto's guidance to treat finding text as
data applies unchanged; nothing routes on it.

**The dispute wrapper.** `rule-dispute.sh` passes each argument to koto as a
separate word and builds the decision's JSON with `jq --arg`, so a reason
holding shell metacharacters or JSON can't change the command or the record.
It refuses rule ids that aren't active registry entries, which also keeps
arbitrary strings out of the session's dispute records. A dispute changes no
gate outcome in koto, so an agent can't use it to get past a check; at worst
it skews one rule's dispute figure, which a reviewer reads with its source.

**The safety rule itself.** Two layers keep a guarded rule at `block`. The
registry check runs in CI on every pull request touching the registry and
refuses an unbacked softening. `rule-registry.sh stage` repeats the rule at
run time and fails closed, so an unknown stage, a missing stage, or a guarded
rule below `block` without full backstops all behave as `block` in the gate.
That matters because a gate reads the registry from the plugin root it runs
from: for an adopter that's the installed plugin, but a working copy of
shirabe running its own scripts reads the working tree, which an agent can
edit before a pull request exists. The existing withhold rules are
untouched, so this feature can't make a rule withholdable.

What the checks can't prove is stated rather than hidden. A
`stage_backstops` path is checked to exist and to differ from the rule's own
check; whether that check really blocks the action is a reviewer's call,
recorded in `notes`. Retiring a rule's `status` is the registry's existing
path for a rule that no longer applies, which removes its id from every
`RULE_IDS` line; it isn't a stage change and needs no backstop, so it stays a
reviewed registry change like any other. Stage changes to the registry should
get a person's review, which the reference asks for.

**Dispute source.** `--by person` is what the caller says. A dispute moves
nothing, so a false source skews one figure, which the reader shows split by
source; the thresholds treat both alike for that reason.

**The figures reader** reads files it's given and the registry, writes
nothing and makes no network call. Journal lines hold content hashes on
`context_reads` records, which the reader ignores. The dispute reason lives
in the session log, which koto doesn't send anywhere; a tool that copies
session logs off the host would carry it, bounded at 1,000 bytes.

## Consequences

### Positive

- A new check can run on real traffic before it can hold anyone, and a
  promotion is backed by figures a reviewer can recompute.
- Quiet checks can be found and retired with evidence, and a guarded rule
  can't lose its protection by accident.
- Agents get a recorded way to disagree with a finding that doesn't weaken any
  guard.
- The koto change is useful beyond shirabe: any template's warnings now reach
  its agent and its journal.

### Negative

- Four more fields on 37 entries, and a registry check that now parses
  template frontmatter.
- The figures reader matches gates by state and gate name, so two skills
  sharing a state and gate name would mix their evaluations.
- On koto 0.20.0 a warn finding is invisible to the agent, so warn behaves as
  shadow until the floor rises.
- 34 of 35 active rules can't leave `block` until someone declares backstops
  for them.
- koto's 50-finding cap can drop warning pairs from a noisy evaluation.

### Mitigations

- The migration and the gates check are mechanical, and the check fails
  loudly on a stale gate name, so the fields can't drift silently.
- No two skills share a state and gate name today; the reference notes the
  limitation for future gates.
- The reader counts only evaluations from a koto that journals findings, so
  the older-koto period can't produce a wrong retirement.
- Backstops are declared per rule when someone wants to move it, which is the
  point of a reviewed change.
- `koto.check.findings_truncated` marks the evaluations where the cap bit.

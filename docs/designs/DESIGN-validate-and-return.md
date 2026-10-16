---
schema: design/v1
status: Planned
problem: |
  A /work-on output gate that fails on a registry rule prints the rule's
  one-line summary however many times the rule fails. Only PB4 returns its
  full text, through a special case in check-pr-output.sh, and the three gates
  that hold a run on a violation offer no named way to stop when a check can't
  be satisfied. koto already counts each rule's failures per state and gate,
  and nothing reads the counts.
decision: |
  The shared findings library, scripts/lib/rule-findings.sh, collects the rule
  ids a gate prints and, through one new call before the gate's non-zero exit,
  reads koto's per-rule counts from the session's own log and escalates: the
  summary at count 1, the rule's full text through rule-registry.sh release
  from count 2, and from count 3 a one-line exit notice in states that have an
  exit. The template supplies the log path, the gate's name and an exit table
  as three environment assignments on each gate command, and the gate reads
  its state from the log. pr_creation, finalization and pr_precheck accept
  check_unsatisfiable with a check_exit_reason, routed through a marker state,
  check_exit, to done_blocked.
rationale: |
  koto appends and syncs every event before it runs the next command, so a
  gate that reads the log gets exactly the count koto will record, with no
  koto change. Putting the ladder in the library gives every adopting gate the
  same behaviour from one call, and reading the state from the log keeps the
  byte-identical commit_convention copies identical. A marker state is the
  only way an exit reaches exported events, since koto exports state names and
  rule counts but no evidence values, and routing the exit to done_blocked
  keeps every guarded rule blocking.
upstream: docs/prds/PRD-validate-and-return.md
decision_provenance: inline-resolved
---

# DESIGN: Validate-and-Return on koto Gates

## Status

Planned

## Context and Problem Statement

The requirements are in `docs/prds/PRD-validate-and-return.md` (R1 to R19).
This document settles how they're built.

What exists today, on `main`:

- `scripts/lib/rule-findings.sh` is the library every gate script sources to
  print `::koto-finding::` lines. `rf_require` resolves each rule id's summary
  and reference up front; `rf_finding` builds a finding whose message starts
  with the summary; `rf_emit` checks and prints a finding a script built
  itself (`panel-scope.sh --verdict` builds its own).
- `scripts/rule-registry.sh release <id>` prints a rule's full text on
  standard error between `::shirabe-rule::{...}` and `::shirabe-rule-end::`,
  always exits 0, and refuses text over 60 lines, outside the files a skill
  loads, or holding a marker or control character, printing one
  `rule-registry: could not release <id>: <reason>` line instead.
- `skills/work-on/scripts/check-pr-output.sh --pr-body` calls `release
  pr-body/no-heading-in-part1` after printing a PB4 finding, on every PB4
  failure, for the live offload canary.
- koto, from 0.15.0, writes `rule_counts` on each failed `gate_evaluated`:
  for each rule the check reported at `error`, `{visit, session}`, where
  `session` is 1 plus the highest stored `session` for that rule on earlier
  events with the same `state` and `gate` (koto `src/engine/advance.rs`,
  `rule_counts_for`). Every event is appended and synced before the tick runs
  its next command (`append_event`, then `sync_data`), so a gate's prior
  events are on disk while it runs, including those from earlier in the same
  tick, and its own event is written after it exits.
- koto's run journal, the feed an exporter reads, writes `state_entered`
  (`koto.state`), `check_evaluated`, and one `check_rule` per `rule_counts` key
  with `koto.rule.id`, `koto.rule.visit_count` and `koto.rule.session_count`.
  It never relays evidence.
- `{{SESSION_DIR}}` and `{{SESSION_NAME}}` are koto runtime variables usable in
  any gate command; the session log is `{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl`
  on the local backend and, as the local copy the tick writes first, on the
  cloud backend. A gate command runs under `/bin/sh -c` in a cleared
  environment, so a `NAME=value` prefix reaches the script.
- `/work-on`'s `commit_convention` gate appears in `finalization`,
  `deferral_approval` and `pre_pr_evidence`, and two checks require the three
  copies to be byte-identical: `finalization-shape_test.sh` compares the
  compiled gates, and `scripts/validate-template-mermaid.sh` check 4 refuses a
  gate name with two command strings, even within one template.

## Decision Drivers

- **The count is koto's.** The ladder must show the agent the rung koto's
  recorded count says, never a count the agent can influence.
- **One mechanism for every gate.** Five gate scripts adopt; a ladder written
  into each would drift.
- **Shared commands stay identical.** Nothing state-specific may sit in a
  command that more than one state runs.
- **A gate's result never moves.** Exit status, standard output and the
  findings koto records are untouched.
- **Without the template, nothing changes.** `/execute`, the test suites and
  an agent's own shell call the same scripts.
- **The exit must be countable and must never pass.** Exported events carry
  state names and rule counts only.
- **No koto release.** The feature works on koto as shirabe's floor ships it.

## Considered Options

### Decision 1: Where the ladder lives and how a gate receives its context

*Resolved inline (standard).*

**Chosen: in `rule-findings.sh`, triggered by one call, with the context in
three environment assignments.** `rf_emit` (which `rf_finding` calls) adds
each printed rule id to a list. A new `rf_deliver` runs the ladder once over
that list; each adopting script calls it immediately before every non-zero
exit that follows printed findings. The template supplies
`SHIRABE_GATE_LOG`, `SHIRABE_GATE_NAME` and `SHIRABE_GATE_EXITS` as a prefix
on the gate command. With none of them set, `rf_deliver` returns at once and
the script behaves as today.

Alternatives:

- **Per-script command-line flags** (`--gate-log`, `--gate`). Rejected: each
  script parses its arguments its own way (`check-pr-output.sh --pr-body
  --owned ...` passes the rest to `owned-pr.sh`), five parsers would change,
  and the routing test's fake scripts answer on their first argument, which
  a leading flag would move.
- **A wrapper script that runs the gate and adds the text afterwards.**
  Rejected: it changes every gate command's shape, has to re-parse findings
  from the gate's output, and moves the identical-copy checks onto a new
  subject.
- **An `EXIT` trap installed by the library.** Rejected: the gate scripts
  already own their `EXIT` trap for temporary-file cleanup, and a second one
  would replace it.

### Decision 2: How the gate reads its state and prior counts

*Resolved inline (standard).*

**Chosen: one `jq` pass over the log.** The library reads
`SHIRABE_GATE_LOG` line by line, parsing each line with `fromjson?` so a torn
final line is skipped. It requires the first line to be a header with
`schema_version` 1. The current state is the `to` of the last event whose
`type` is `transitioned`, `directed_transition` or `rewound`. The prior count
of each reported rule is the highest `payload.rule_counts[<rule>].session` on
`gate_evaluated` events whose `payload.state` is that state and whose
`payload.gate` is `SHIRABE_GATE_NAME`, or 0. The count is prior + 1. Any read
failure (no file, not readable, bad header, no transition, `jq` failing)
makes every reported rule count 2 with no exit notice, per R9.

Alternatives:

- **`koto session dir` or `koto status` from inside the gate.** Rejected: on
  the cloud backend a read can pull and sync in the middle of the tick that
  is running the gate, and the template already has both values.
- **The state written into the command.** Rejected: it breaks the three
  identical `commit_convention` copies.
- **`KOTO_TICK_SESSION` for the session name.** Rejected: koto documents it as
  a re-entrancy marker, not an input.
- **Counting by gate and rule across all states.** Rejected: koto counts per
  state, so the same rule failing at `finalization` and then at
  `pre_pr_evidence` would show a rung koto never recorded.

### Decision 3: The named exit's template shape

*Resolved inline (standard).*

**Chosen: a value on each state's existing status enum, one shared marker
state.** `pr_creation`, `finalization` and `pr_precheck` add
`check_unsatisfiable` to `pr_status`, `finalization_status` and
`precheck_status`, and accept a new string field, `check_exit_reason`. The new
edge in each state requires the value and the state's registry gate at exit
1, targets `check_exit`, and sets `failure_reason` to `check_exit at <state>:
<gate> could not be satisfied: ${evidence.check_exit_reason}`. `check_exit`
has no gates and no `accepts`, and one unconditional transition to
`done_blocked`, so koto passes through it in the same tick, as it does the
canary's `offload_arm_withheld`.

Alternatives:

- **A new terminal state.** Rejected: `/execute` and the batch view read
  `done_blocked` as the failure terminal; a second failure terminal would need
  both taught about it.
- **One marker per state** (`check_exit_pr_creation`, ...). Rejected: three
  names for a reader to union, when the state is already on the `check_rule`
  record the exit joins to.
- **Reusing `pr_status: creation_failed_escalate`.** Rejected: it exists only
  at `pr_creation`, its reason is a URL, and it isn't gated on the check
  failing.
- **Enforcing count 3 with a new gate exit status.** Rejected: koto routes on
  a command gate's exit status alone, the same scripts serve `/execute`, whose
  routing names 0, 1 and 2, and an early exit only stops the run.

### Decision 4: The exit notice's shape

*Resolved inline (standard).*

**Chosen: one machine-readable line on standard error.**

```text
::shirabe-check-exit::{"rule_id":"commit/conventional-subject","count":3,"state":"finalization","submit":{"finalization_status":"check_unsatisfiable","check_exit_reason":"<why the check can't be satisfied>"},"ends_at":"done_blocked"}
```

koto returns the gate's standard error to the agent in the blocked
condition's `failure.captured.stderr`, beside the release blocks, and the
state's directive says what the line means. The line is built with `jq` from
fixed keys and values the library resolved; nothing in it comes from the
agent.

Alternatives:

- **A prose sentence.** Rejected: tests and a reader of captured output can't
  parse it reliably, and the directive already carries the prose.
- **A `::koto-finding::` line.** Rejected: koto would record it as a finding
  under a rule id and raise that id's count.

## Decision Outcome

The library owns the ladder. A gate script prints its findings as it does
today; before it exits non-zero it calls `rf_deliver`, which reads the counts
koto has recorded for this gate in this state, releases the full text of each
rule now at count 2 or more, and, in a state the exit table names, prints one
exit notice when a rule reaches count 3. The template turns the ladder on per
gate by prefixing the command with the log path, the gate's name and the exit
table, all three the same text wherever the command appears. The three holding
states gain `check_unsatisfiable`, which moves the run through `check_exit` to
`done_blocked`, and nothing else changes in how any gate routes.

PB4 loses its special case inside a laddered run and keeps it outside one, so
`/execute`'s `pr_finalization` and a hand-run script still release PB4 on its
first failure.

## Solution Architecture

### Components

| File | Change |
|---|---|
| `scripts/lib/rule-findings.sh` | `rf_emit` records each printed rule id in `RF_REPORTED` (deduplicated, first-printed order). New `rf_ladder_active`, `rf_deliver`, and the constants `RF_FULL_TEXT_AT=2` and `RF_EXIT_AT=3`. Header documents the ladder. |
| `skills/work-on/scripts/check-pr-output.sh` | Calls `rf_deliver` before `exit 1` in `--pr-body`. Its PB4 release runs only when `rf_ladder_active` is false. |
| `skills/work-on/scripts/check-branch-output.sh` | Calls `rf_deliver` before each `exit 1` that follows findings. |
| `skills/work-on/scripts/check-verification.sh` | Calls `rf_deliver` before `exit "$VERDICT"` when findings were printed. |
| `skills/work-on/scripts/panel-scope.sh` | Calls `rf_deliver` before `--verdict`'s `exit 1`. |
| `skills/work-on/koto-templates/work-on.md` | The ladder prefix on the ten R13 gate commands; `check_unsatisfiable` and `check_exit_reason` in three states; the `check_exit` state and its directive; directive text in the three states. |
| `skills/work-on/koto-templates/work-on.mermaid.md` | Regenerated with `koto template export`. |
| `references/rule-registry.md` | A section on the ladder and the exit. |
| `docs/guides/offload-live-canary.md`, `docs/designs/current/DESIGN-offload-live-canary.md` | PB4's full text arrives on the second failure in a laddered run. |

### The ladder prefix

Every adopting gate command keeps its `test -x ... || exit N;` guard and puts
the prefix directly before the script path:

```text
test -x "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh" || exit 2; SHIRABE_GATE_LOG="{{SESSION_DIR}}/koto-{{SESSION_NAME}}.state.jsonl" SHIRABE_GATE_NAME=commit_convention SHIRABE_GATE_EXITS="pr_creation:pr_status finalization:finalization_status pr_precheck:precheck_status" "{{PLUGIN_ROOT}}/skills/work-on/scripts/check-branch-output.sh" --commits --session "{{SESSION_NAME}}"
```

`SHIRABE_GATE_EXITS` is the same string on every adopting command. Panel
commands keep the literal substring `panel-scope.sh" --verdict <panel>
"{{SESSION_NAME}}"` the routing test asserts. A template test pins the
prefix on each R13 gate, checks that the exit table names exactly the states
that have a `check_unsatisfiable` edge with each one's status field, and
keeps the three `commit_convention` copies identical.

### `rf_deliver`

```text
rf_deliver:
  RF_REPORTED empty                         -> return
  rf_ladder_active false                    -> return    (R8)
  counts <- read the log (Decision 2)
  read failed                               -> each id: count 2
  for each id in RF_REPORTED (printed order):
    count >= RF_FULL_TEXT_AT                -> rule-registry.sh release <id>
  if read succeeded and the state is in SHIRABE_GATE_EXITS:
    top <- first id with the highest count
    count(top) >= RF_EXIT_AT                -> print the notice line
  return 0
```

`rf_deliver` runs its delivery at most once per process, and `rf_emit` must
run in the script's own shell (not a pipeline or command substitution) for its
ids to reach `RF_REPORTED`; every adopting script already calls it from a
plain loop or function. The exit-table lookup is its own helper,
`rf_exit_field <state>`, which prints the state's status field or nothing. On
the R9 path `rf_deliver` prints one line, `rule-findings: could not read
koto's counts from <log>; releasing every reported rule`, before the releases.
When the agent submits `check_unsatisfiable`, koto re-runs the failing gate on
that tick, so the evaluation just before `check_exit` records one more than
the count the notice showed; a reader treats any count at or above 3 there as
an exit taken after the notice.

`rf_ladder_active` is true when `SHIRABE_GATE_LOG` or `SHIRABE_GATE_NAME` is
non-empty; a command that sets only one of them gets the R9 fallback rather
than silence. `rf_deliver` always returns 0 and writes only to standard error,
so the script's exit status and standard output are what they were (R7). The
counts are read only when there are findings, so a passing run reads nothing
(R17).

The `jq` program, given the reported ids and the gate name:

```text
[inputs | fromjson? ] as $ev
| ($ev[0].schema_version == 1) and ($ev[0] | has("seq") | not)   # header
| state <- last of $ev[] | select(.type in transitioned, directed_transition, rewound) | .payload.to
| for each id: 1 + max(0, $ev[] | select(.type == "gate_evaluated"
                                   and .payload.state == state
                                   and .payload.gate == gate)
                       | .payload.rule_counts[id].session // 0)
```

It runs with `-R -n` on the bash 3.2 floor's `jq`, prints `state` and one
`id<TAB>count` line per id, and its failure is the R9 path.

### The template's new state

```yaml
  check_exit:
    transitions:
      - target: done_blocked
```

with a `## check_exit` directive saying koto passes through it. Each holding
state gains, for example in `pr_creation`:

```yaml
      check_exit_reason:
        type: string
        description: Why the failing check can't be satisfied ...
    transitions:
      - target: check_exit
        when:
          pr_status: check_unsatisfiable
          gates.pr_body_conformant.exit_code: 1
        context_assignments:
          failure_reason: "check_exit at pr_creation: pr_body_conformant could not be satisfied: ${evidence.check_exit_reason}"
```

`finalization` uses `gates.commit_convention.exit_code: 1`, and `pr_precheck`
uses `gates.branch_docs_visibility.exit_code: 1`. Each new edge is exclusive
of the state's other edges on its status field.

### Data flow for a failing PB4 at `pr_creation`

1. The agent submits `pr_status: created`. koto runs `pr_body_conformant`
   with the prefix.
2. `check-pr-output.sh` prints the PB4 finding (summary first) on standard
   output, then calls `rf_deliver`.
3. `rf_deliver` reads the log: state `pr_creation`, prior PB4 session count 0
   on the first failure, so count 1 and nothing more; prior 1 on the second,
   so it releases PB4's text.
4. The script exits 1. koto records `gate_evaluated` with
   `rule_counts["pr-body/no-heading-in-part1"].session` equal to the count
   `rf_deliver` used, and the journal writes a `check_rule` with that
   `koto.rule.session_count`.
5. On a third failure the notice names `pr_status: check_unsatisfiable`. If
   the agent takes it, koto writes `transitioned` to `check_exit` and then to
   `done_blocked`; the journal writes `state_entered` for `check_exit` and a
   `terminal` record.

### Reading the result

From exported journal records, joined on `koto.session.id`:

- failures by rung: `check_rule` records by `koto.rule.id`, split on
  `koto.rule.session_count` (1 the summary, 2 or more the full text);
- exits: `state_entered` with `koto.state:check_exit`, each credited to the
  rules on the `check_rule` records of the same session at the exit's state
  with the highest `koto.seq` below it.

For the canary, a PB4 run whose highest `session_count` is 1 fixed PB4 from
the summary; 2 or more needed the full text.

## Implementation Approach

One pull request, built in four steps that each leave the tree green.

1. **The library.** Add `RF_REPORTED`, `rf_ladder_active`, `rf_deliver`, the
   log reader and the thresholds to `scripts/lib/rule-findings.sh`, with
   probe tests in `scripts/rule-registry_test.sh` covering every ladder
   criterion of the PRD against fixture logs: counts 1, 2 and 3, two rules,
   another gate, state or rule, the state read from the latest transition, a
   claimed count outside the log, each R9 failure, a state outside the exit
   table, a tie at count 3, and the five unreleasable rules (a test lists
   the rules each `/work-on` gate can report that `release` refuses and fails
   when the set changes).
2. **The gate scripts.** Call `rf_deliver` in the four adopting scripts and
   guard PB4's release in `check-pr-output.sh`. Extend each script's suite
   with a laddered case and a check that standard output and exit status are
   unchanged with and without the context; keep the existing PB4 release
   tests as the no-context case and add count-1 and count-2 PB4 cases.
3. **The template.** Add the prefix to the R13 gates, the exit to the three
   states, `check_exit` and the directives; regenerate the mermaid file;
   extend `output-gates-routing_test.sh` with the exit routing (gate at 1, 0
   and 2), the `check_exit` target set, the prefix pin and the exit-table
   check; drive one exit end to end through the shipped template and read the
   run journal for the `check_exit` record; update the `pr-shared` eval
   fixture's `pr_status` values. The canary route tests must keep passing.
4. **The documents.** `references/rule-registry.md` gains "Escalating a rule's
   text" covering R16's list; the canary guide and design say PB4's full text
   arrives on the second failure in a laddered run and on the first outside
   one.

## Security Considerations

- **Inputs the ladder reads.** The log path comes from the template's command,
  built from koto's own variables; an agent can't change a gate command
  mid-run. The log is read with `jq` as data; nothing from it is evaluated or
  interpolated into a command. Rule ids reach `release` only from
  `RF_REPORTED`, which holds ids `rf_emit` already checked against the
  registry.
- **An agent setting the variables by hand.** An agent running a gate script
  from its own shell can point `SHIRABE_GATE_LOG` at a file it wrote. That
  changes only the text printed in that shell: the full text of rules it can
  already read, or a notice naming an exit the template already offers. koto
  never sees that run, so no count or route moves.
- **An agent editing the session log.** An agent can already write to its own
  koto log, and koto reads the same file for its own counts and state, so the
  log's integrity is koto's concern and a forged log would also skew any
  readout built on it. The ladder adds no power over the log: the most an
  edit can change through it is which rung of public rule text a gate prints
  and whether the notice appears, and the exit is open at any count anyway.
- **The exit reason.** `check_exit_reason` is free text the agent writes, and
  it reaches `failure_reason` through koto's own `${evidence...}`
  substitution, the same channel every other `${evidence...}` reason in
  `/work-on` uses (`pr_precheck`'s `${evidence.detail}`, `deferral_approval`'s
  `${evidence.deferral_detail}`). koto stores it as a context value and
  nothing executes it. A caller such as `/execute` that reads `failure_reason`
  already treats it as the child's untrusted report; this feature adds no new
  reader. The directive asks for one sentence; an empty reason still routes,
  leaving the fixed prefix as the whole reason, and a test covers it.
- **The shell command.** The prefix adds `{{SESSION_DIR}}` and
  `{{SESSION_NAME}}` to the command, double-quoted. Both are koto values:
  the session name is constrained by koto's session-name pattern at `koto
  init` (letters, digits, `.`, `_`, `-`), as it already is for the
  `"{{SESSION_NAME}}"` argument every adopting command passes today.
- **Parsing the table and the log.** The library splits `SHIRABE_GATE_EXITS`
  on spaces with globbing off and matches the state against each entry's name
  exactly. A `jq` failure on a bad log is the R9 path: the library discards
  `jq`'s own message, which can quote log content, and prints one fixed line
  naming the log on standard error, never on standard output.
- **The exit as a bypass.** The exit's only target is `done_blocked`. An
  agent can take it before count 3, since the template can't refuse it there;
  that's an accepted residual risk, because it only ends the run, and the
  gate's last failure records the count it was taken at. Every
  edge that passes a holding gate still requires the gate at exit 0, so no
  rule that guards pull request creation, a push or a merge loses its block.
- **A pull request left open.** At `pr_creation` the gate reads a pull
  request that already exists, so taking the exit there stops the run with a
  failing body on GitHub. The directive tells the agent to mark the pull
  request draft (`gh pr ready --undo`) before taking the exit, so it isn't
  read as finished; the PR-body CI check, a required status check on `main`,
  keeps it from merging either way.
- **Output.** `release` keeps its own limits (60 lines, loadable files, no
  marker or control characters). The notice line is built with `jq` from
  registry ids, a number, a state name read from koto's log and fixed field
  names; a state name that isn't in the exit table produces no notice, so a
  malformed log can't inject text into it.
- **Data exposure.** The ladder writes no file. koto already keeps a 4 KiB
  copy of a failed command's streams on the event, which can now hold part of
  a released rule; rule text is public repository content.
- **Coupling to koto.** The reader depends on koto's event names and its count
  rule as of 0.15.0. The header check catches a format change but not a change
  in meaning, so the end-to-end test drives a real koto session and checks the
  ladder's count against the `rule_counts` koto writes. On the cloud backend
  the gate reads the local copy koto writes first; if it ever lagged, the
  ladder would show a lower rung, never a higher one.

## Consequences

**Positive.** Every `/work-on` output gate escalates from one library call,
and the canary's PB4 delivery stops being a special case inside a laddered
run. An exit is a named, counted stop instead of a loop or a misused field,
and the readout of rungs and exits needs no new export.

**Negative.** Each laddered gate failure reads the session log once, which
grows with the run. The exit table is written into ten commands, so adding
an exit state means editing all of them (the template test catches a miss).
Five rules can't reach their full text until their text moves. The count is
koto's, so a bare re-query moves the ladder too.

**Mitigations.** The log is read only on a failure, in one `jq` pass. The
template test pins the prefix and the table. The unreleasable set is pinned
by a test so it can't grow unnoticed, and moving that text is follow-up work
for the registry. If koto later defines its reserved `escalation` field, the
ladder can read it instead of computing the count, with no change to the
template or the rungs.

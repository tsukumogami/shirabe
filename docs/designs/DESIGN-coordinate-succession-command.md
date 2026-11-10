---
schema: design/v1
status: Proposed
problem: |
  A `/coordinate` successor takes a run over by driving about nine steps by
  hand (the opener, a second opener run after a takeover cut short, the
  watch, the `reports-to` re-point, `told`, the ticks into reconcile, the
  reconcile report and the handover check) and reads every step's full
  output into its context. In the succession tsukumogami/shirabe#1698
  measured, that cost about 70K tokens over about 90 minutes before the run
  dispatched anything. The opener, the handover gate and the watch move each
  work; nothing sequences them, keeps their output out of the agent's
  context, or stops only where the agent or a person has to act.
decision: |
  A new stateless driver, `skills/coordinate/scripts/coordinate-succeed.sh`,
  runs the steps in order on every invocation (open, re-point, watch, tick,
  report, handover), skips each one whose existing read says it's done, and
  stops with one `next=` action: exit 10 when a person must answer, exit 11
  when the agent acts and runs it again. It retries the opener once, only on
  a takeover the fence proves is this session's; it writes `reports-to` only
  from flags with an explicit source, never writes `told`, and hands the
  watch, messages, judgements and person gates back. Full outputs go to a
  private `mktemp -d` scratch directory and stdout carries a digest of at
  most about 25 `key=value` lines. The opener's preflight serves as the
  compare, and `watch_pids` moves into a shared probe library.
rationale: |
  Keeping no progress file means the command converges on koto's state and
  the record the same way the opener already converges on its fence, so
  nothing new can drift from them, and the opener's contract and the
  template's compat fingerprint stay as they are. A `--through` mode on the
  opener can't run past the watch stop and would give its exit codes two
  meanings; template states can't hold the opener or the watch and would
  change the fingerprint, so running predecessors would refuse. Retrying or
  writing anything the command can't attribute to this session would act on
  another party's refusal or record a delivery it never made, and a separate
  compare would repeat reads the opener already does before the fence.
---

# DESIGN: One command runs a coordinator succession

## Status

Proposed

## Context and Problem Statement

A `/coordinate` successor takes a run over by driving each step of the
succession by hand, and it reads every step's full output into its context
(tsukumogami/shirabe#1698):

1. compare the predecessor's local session with the cloud bucket;
2. run the opener, `scripts/coordinate-open.sh`;
3. run the opener again when the first run stopped after it had already
   fenced the old run;
4. arm the request watch on the new run;
5. re-point the record's `reports-to` row;
6. write `told` for the dispatcher;
7. tick into reconcile and through `reconcile_pass`;
8. read the reconcile report (`reconcile-report-get.sh`);
9. run the handover check (`state-handover.sh --check`) and close every gap
   it lists.

The issue measured one succession: the successor's context grew by about 70K
tokens over about 90 minutes before the run dispatched anything. The compare
alone printed 72 KB, and the opener ran twice, about 32 minutes each time,
because the first run refused even though it had already fenced the old run
and carried its keys.

Most of the pieces exist and work. The takeover itself is one opener call
built on koto's continues relation (`DESIGN-coordinate-successor-continues.md`
and its plan): the opener fences the old run, carries the record and leg
keys, writes the driver, the coordinator row and the takeover entry, and
converges when it runs again from the same session, because it recognises a
fence by its actor. A refusal after the fence now prints
`failed=takeover_unfinished` instead of a refusal reason. The handover gate
passes on pending workers and records a delivered re-brief as `told`, and the
watch moves to the successor. What's missing is the layer above them: nothing
sequences these steps, decides which outputs the successor actually needs,
or stops only where the successor has to act.

Some steps can't move into a script. A harness watch notifies only the agent
that started it, so the agent has to arm `koto request watch` itself from the
opener's `session=` line. The takeover writes the coordinator row, which
clears every `told` and `pending` row, so `told` and the handover gaps are
always owed after a takeover. Several gaps need a person's go-ahead
(`carry-unacknowledged`), an answer (`ask=role`, `ask=host`, the posture
question) or a message sent to a live worker before `told` can be written.

## Decision Drivers

- **Context cost.** The successor's context should grow by the digest, not by
  every step's full output. Full outputs stay reachable for the case where a
  step fails.
- **Stop only where the agent or a person must act.** Arming the watch, the
  dispatcher's go, an answer the run asks for, and a message to a worker are
  the agent's; everything else runs without a pause.
- **Converge on re-run.** A succession cut short at any point finishes when
  the same command runs again from the same session, without repeating
  writes, on top of the opener's existing fence-actor convergence.
- **Don't change the takeover.** The opener's outcome contract, its refusals
  and the koto fence stay as they are; this command reads their results.
- **No persistent copy of koto-managed content.** Full outputs live in an
  auto-wiped scratch directory, never in the work tree.
- **Follow the scripts' existing conventions.** `key=value` result lines,
  documented exit codes, `--check`-style reads, and offline tests with stub
  `gh` and `koto` plus engine tests against a real koto.

## Considered Options

### Decision 1: The command's shape, and how it stops and resumes

The succession needs something that runs the steps in order, keeps their
output out of the agent's context, and stops only where the agent or a person
has to act. One step can't move into any script: a harness watch notifies only
the agent that started it, so the agent arms `koto request watch` on the new
run after the takeover and before the first tick. Every other step already
has a read that says whether it's done: the opener's own result when it runs
again, `koto status`, the opener's watch probe (`watch_pids`), the gaps
`state-handover.sh --check` lists, `handover-classify.sh`'s per-worker lines
and `reconcile-report-get.sh --check`.

Key assumptions:

- Running the opener on a run it already took over is cheap and writes
  nothing new (`outcome=resumed`), so the command can call it every time.
- `watch_pids` can move into a library both scripts source without changing
  what the opener prints.
- Re-runs come from the same Claude session. Any other session is refused
  `taken-over` by the opener, and the command passes that through.
- A script may tick `koto next --no-cleanup`; only arming the watch has to be
  the agent's.

#### Chosen: a stateless, resumable driver, `coordinate-succeed.sh`

A new script, `skills/coordinate/scripts/coordinate-succeed.sh`, takes the
opener's arguments plus a few of its own and runs the succession's steps in
order: open, re-point, watch, tick, report, handover. It keeps no progress
file. On every run it works out from koto and the record which steps are
already done, does the next one, and either finishes or stops with one named
action for the agent or a person. After the agent acts, it runs the same
command again.

It stops with one of two exit codes. Code 10 means a person must answer, the
meaning it already has in the opener's `ask=` lines. Code 11 means the agent
acts and runs the command again in the same turn. The difference changes the
agent's next move (wait on someone, or carry on), so the exit code carries it
rather than leaving the agent to parse the `next=` token first.

Convergence rests on the same reads the opener and the reconcile gate already
trust, so the command adds no state that could disagree with them, and it
leaves the opener's contract and the template's compat fingerprint alone.

#### Alternatives Considered

- **A `--through <point>` mode on `coordinate-open.sh`**: continue past the
  takeover inside the opener. Rejected because the watch forces a stop right
  after the takeover anyway, so it can never run through in one call, and the
  opener's exit codes would take on two meanings, which changes the outcome
  contract this design leaves alone.
- **The post-takeover steps as template states with default actions**: let
  koto sequence them. Rejected because the opener and the watch can't be
  states, the remaining steps are writes that depend on the agent or a person
  (a `told` only after a message lands, a go-ahead, a role), and changing the
  start chain moves the template's compat fingerprint, so running
  predecessors would refuse `template-incompatible`, which blocks the very
  successions this is for.
- **A driver with its own progress file**: rejected because it's a second
  record that drifts from koto when a crash lands between a write and the
  file's update. Kept in scratch, it's gone on restart; kept anywhere else, it
  becomes a local copy of state koto already holds.
- **Sequencing in SKILL.md prose only**: rejected because it's what happens
  today, and it's what the issue measured.

### Decision 2: What the command does itself, and what it hands back

Three parts of the succession could be done by the command or handed back:
running the opener again after a takeover cut short, writing the record's
`reports-to` and `told` rows, and closing the gaps the handover check lists.
The issue's successor ran the opener twice because the first run refused
`predecessor-unstoppable` after it had already fenced the old run and carried
its keys. The current opener mostly fixes that: once `fenced_for` sees a fence
naming this session's successor, a failed `koto init --supersede` prints
`failed=takeover_unfinished` instead of a refusal. One path is left, because
`fenced_for` treats a fence it can't read as no fence, so koto's
`fence_unavailable` plus a failed fence read still refuses
`predecessor-unstoppable` when the fence may be this session's.

The takeover writes the coordinator row, and writing that row clears every
`told` and `pending` row, so after any takeover every live worker and the
dispatcher are owed the new address.

Key assumptions:

- The command knows the predecessor's name after a refusal, from its own
  `--continues` argument or by resolving the scope's newest member the way
  the opener does, since a refusal prints no `predecessor=`.
- `coord-log.sh fence` stays the fence reader, and `CLAUDE_CODE_SESSION_ID` is
  set in the successor. Without it the command never retries: the opener
  refuses a touched run as `taken-over` anyway.
- Most failures after the fence are transient, so one retry usually
  finishes. A lasting fault costs at most one more carry, and none when the
  carry already completed.

#### Chosen: an attributed single retry, a flag-fed `reports-to`, and `told` left to the agent

The command runs the opener again by itself at most once per invocation, and
only when the failure is provably this session's own takeover:
`failed=takeover_unfinished`, which the opener prints only once the fence
names this session's successor, or `reason=predecessor-unstoppable` when a
fence read shows both `.by` naming the successor being retried and
`.claude_session` equal to this session's id. The retry goes
through the opener's own fence-actor convergence, so it adds no write path.
Every other outcome passes through untouched.

It writes `reports-to` only from flags the agent passes: the value and an
explicit source (the brief, the dispatch link, a person, or an inferred
sentence, which goes through as `--inferred` so the row lands awaiting
confirmation). It writes only after the takeover has landed and only when the
row differs. It never derives the value from `--dispatched-by` or a brief on
its own.

It never writes `told`. `told` records a delivery, and the command delivers
nothing. For each party owed the address (each worker the classifier prints
as `live`, and the dispatcher) it prints the party, the address and the
`state-stored-set.sh --told` command to run once the message lands.
`handover-classify.sh` keeps its own writes: it records `pending` for a
worker it can't reach and `told` for one whose report already shows it.

Each gap the handover check or the run can raise has one owner:

| Gap or ask | Closed by | How |
|---|---|---|
| `no-coordinator` | the opener | `finish_takeover` writes it; the agent supplies the address only if the session name can't be read |
| `no-arguments` | the opener | written from the start's own arguments |
| `no-cap` | the command, or the agent | from `--cap` when passed; otherwise from the brief, or `--inferred` |
| `no-role` | the command, or a person | from the opener's `role=` line; with none, `ask=role` |
| `no-reports-to`, `reports-to-unsourced` | the agent, through flags | the command writes what the agent passes; with nothing known, a person says who the run reports to |
| `brief-unread <label>` | the command, or a person | `state-stored-set.sh --intake <label>`; a cap refusal goes to a person |
| `no-next-step <unit>` | the agent | a judgement about the holding, from the reconcile report |
| `leg-unclassified <worker>` | the reconcile pass, or the agent | `reconcile-legs.sh` closes it; when the pass can't verify it, the agent runs the gap's fix |
| `not-told <worker>`, classifier `live` | the agent | message the worker, then `--told` |
| classifier `told`, `pending` | `handover-classify.sh` | its own writes |
| classifier `missing`, `unknown` | the agent | as today, through teardown or pick; `unknown` gets one more classifier run first |
| dispatcher `told` | the agent | message the dispatcher, then `--told` |
| `carry-unacknowledged` | a person | only a recorded go-ahead closes it |
| `ask=role`, `ask=host`, `posture_ask` | a person | an answer, then the command runs again |

#### Alternatives Considered

- **Narrate only: never re-run, print every write.** Rejected because it
  brings back the issue's failure. The agent reads the opener's output,
  decides to re-run, and pays for every step in context, although the re-run
  is mechanical and attributable and the `reports-to` value is already in
  hand.
- **Do the most: retry refusals and write from attestations.** Rejected.
  Retrying `taken-over`, or a `predecessor-unstoppable` it can't attribute,
  acts on refusals that aren't this session's and could repeat a long carry.
  Writing `told` from a flag given before the takeover records a delivery
  that came before the address existed. Building `reports-to` from
  `--dispatched-by` hides a guess from the rows awaiting confirmation, and
  acknowledging the carry from a flag passes a person's gate.
- **The chosen split, plus `--told` attestations on a later run.** Rejected
  because the command would write `told` for parties it never messaged, and
  it would save only one short call per party over `state-stored-set.sh
  --told`.

### Decision 3: Where full outputs go, what the command prints, and the compare

The successor read every step's full output, and the compare of the
predecessor's local session with the bucket printed 72 KB on its own.
SKILL.md prescribes no such compare step. What it reached for is already in
the opener's preflight: before the fence the opener reads koto's
`version.json` beside the predecessor's log and compares its machine id with
this host's (`watcher=unobserved` when another host wrote last), reads the
predecessor's driver, rows, state and log (any read koto can't serve stops
the start with `failed=takeover_read`, nothing written), refuses a copy koto
can't locate as `candidate-unreadable`, and reports liveness as
`predecessor_stopped=`.

Key assumptions:

- Under the cloud backend, koto's reads of the predecessor report an
  unresolved local-versus-bucket version conflict as an error rather than
  reading the local copy silently, so it lands before the fence. An engine
  test with a diverged bucket copy has to pin this down.
- Re-runs never need earlier full outputs, because they converge on koto's
  state.

#### Chosen: the opener's preflight is the compare, one scratch directory per run, and a fixed digest

There's no separate compare step. The digest carries what the compare was
for: whether koto can read the predecessor cleanly (`failed=takeover_read`,
`reason=candidate-unreadable`, with a `detail=` line), whether another host
wrote last (`watcher=unobserved`) and whether the predecessor is live
(`predecessor_stopped=`). When `detail=` names a koto version conflict, the
command stops for a person, who picks `--keep local` or `--keep remote`; it
never runs `koto session resolve` itself.

Each run makes one directory with
`mktemp -d "${TMPDIR:-/tmp}/coordinate-succession.XXXXXX"`, writes an `owner`
file holding the Claude session id, and sends every step's stdout and stderr
to numbered files in it. On exit 0 it removes the directory and prints
`outputs=removed`; on any other exit it keeps it and prints `outputs=<dir>`,
so a failed step's full output is one read away. At start it removes older
`coordinate-succession.*` directories this session owns, under the checks
Security Considerations lists. Nothing re-reads
them, so the directory is never a copy of koto's state that something trusts.

Stdout carries only the digest: fixed `key=value` lines, at most about 25,
with `next=` last.

#### Alternatives Considered

- **A compare built from koto reads inside the command.** Rejected because
  it repeats the opener's choice of predecessor and its reads, and its answer
  can go stale before the fence. It stays the fallback if the version
  conflict assumption fails.
- **A dedicated `succession-compare.sh`.** Rejected because it adds a script
  and a contract for what the opener already refuses on, and no koto read
  gives local-versus-bucket counts to report.
- **The full compare redirected to scratch, with counts printed.** Rejected
  because the reads still cost their time, and event or file counts change no
  action the successor takes.
- **A scratch directory with a fixed name, kept until `$TMPDIR` is wiped.**
  Rejected because a predictable path invites a stale or planted directory,
  and nothing a re-run does needs the old outputs.

### Decision 4: How the command knows the watch is armed

The command can't arm the watch, but it shouldn't tick before the agent has.
Nothing in koto or the record says a watch is running; only the process
table does, which the opener's `watch_pids` already reads.

#### Chosen: the watch probe, with `--watch-armed` as the fallback

While the new run is still at `start` (no tick yet), the command looks for a
running `koto request watch --session <new run>` with the opener's probe.
When it finds none, it stops with the exact command in `watch=` and
`next=arm_watch`. The agent arms it and runs the command again with
`--watch-armed`. The command ticks when the probe sees the watch, or when it
got `--watch-armed` and the probe can't run on this host.

#### Alternatives Considered

- **Trust a flag alone.** Rejected because a re-run that forgets the watch
  ticks without one, and a leg's ring then reaches nobody until the next
  reconcile.
- **Always stop after the takeover, whatever the probe says.** Rejected
  because a re-run after the watch is up would stop for nothing.

## Decision Outcome

The four choices fit together as one loop the agent runs: call
`coordinate-succeed.sh`, act on its single `next=` line, call it again. The
command owns everything it can attribute to this session and do without
judgement: the opener and its one retry, the `reports-to` write from values
the agent passed, the ticks through the reconcile, the report read and the
gap classification. It hands back the four things it can't own: the watch,
a message to a party, a judgement about a holding, and a person's answer.

Because the command keeps no progress of its own, any interruption is
recovered the same way the opener already recovers a takeover: run it again.
Because its output is a digest with the full text in scratch, a successful
succession costs the agent about 25 lines per stop rather than the step
outputs. The opener's contract, the template and koto don't change.

### Relation to the successor-continues design

This design builds on `DESIGN-coordinate-successor-continues.md` and changes
none of its decisions. That design's plan made the takeover one opener call
(its step 2), the takeover's refusals and re-runs follow an outcome contract
(step 6), the handover gate passes on pending workers and records a
delivered re-brief as `told` (step 4), and the watch moves to the successor
(step 8). This command sits above those steps and depends on them:

- It reads the outcome contract's lines rather than re-deriving anything,
  so a change there is a change here.
- Its one retry is the plan's step 6 convergence, invoked for the agent.
- Its gap ownership leans on step 4's pending and evidence-told writes.
- Its watch stop is the "arm the new run's watch before the first tick"
  rule that step 8 left to the agent, now named in one `next=` line.

The one place this design reaches into that code is `watch_pids`, which
moves into a shared library without changing what the opener prints.

## Solution Architecture

### Overview

```
agent
  coordinate-succeed.sh <opener args> [--reports-to V --reports-to-source S]
                        [--watch-armed]
    open      coordinate-open.sh ...           (every run; one attributed retry)
    re-point  state-stored-set.sh --run reports-to   (flags only; when it differs)
    watch     watch probe on the new run       (stop: next=arm_watch)
    tick      koto next <new run> --no-cleanup (bounded at reconcile_pass)
    report    reconcile-report-get.sh          (--md and JSON into scratch)
    handover  handover-classify.sh, state-handover.sh --check
  -> digest on stdout, full outputs in $TMPDIR/coordinate-succession.XXXXXX
  -> exit 0 | 10 (a person) | 11 (the agent) | 1 | 2 | 64
agent acts on next=, runs it again
```

### Components

- **`skills/coordinate/scripts/coordinate-succeed.sh`** (new). The driver.
  It parses its own flags, passes the rest to the opener unchanged, runs the
  steps below in order on every invocation, and prints the digest.
- **`skills/coordinate/scripts/watch-probe.sh`** (new library, sourced).
  `watch_pids` moved out of `coordinate-open.sh`, which sources it back; the
  opener's output doesn't change.
- **`coordinate-open.sh`** (unchanged behaviour). The takeover and its
  preflight, which serves as the compare.
- **`state-stored-set.sh`, `handover-classify.sh`, `state-handover.sh`,
  `reconcile-report-get.sh`, `coord-log.sh fence`** (unchanged). The writers
  and readers the driver calls.
- **`skills/coordinate/SKILL.md`**. The takeover section points a successor
  at the command and its `next=` table, and keeps the watch rule as prose,
  since the watch is the agent's.

The steps, each skipped when its read says it's done:

1. **Open.** Call the opener with the passed arguments. On
   `failed=takeover_unfinished`, or on `reason=predecessor-unstoppable` when
   `coord-log.sh fence --session <predecessor>` shows this session as the
   fence's actor on this successor (both `.by` and `.claude_session` match),
   call it once more. A koto version conflict named in the
   failure stops with `next=resolve_conflict <run>`; `ask=role` and
   `ask=host` stop with `next=answer role|host`. Any other refusal or failure
   exits 2 or 1 with the opener's lines.
2. **Re-point.** With `--reports-to` and its source passed, and the takeover
   landed, write the row when it differs.
3. **Watch.** While `koto status` shows the new run at `start`, require the
   watch as Decision 4 describes.
4. **Tick.** `koto next <new run> --no-cleanup`, never `--to`, reading where
   koto actually stopped. While the run sits at `reconcile_pass` and
   `reconcile/progress` keeps falling, tick again, at most 12 times in one
   invocation; two ticks in a row with no fall also end the loop (the pass's
   30-second re-read is still due). Either way stop with `next=rerun`. A set
   `reconcile/refusal` stops with `next=fix reconcile_pass`. Any state other
   than `reconcile` stops with `next=directive` and the directive's text in
   scratch. A run already past `reconcile` ends the succession with
   `next=dispatch`: the hub's loop owns it.
5. **Report.** `reconcile-report-get.sh --md` and its JSON mode into
   scratch; the record line and the counts go to the digest. Exit 4 (no role
   row) falls through to the role gap.
6. **Handover.** `handover-classify.sh`, then `state-handover.sh --check`.
   The remaining gaps become one stop, checked in this order: `no-role`
   (`next=answer role`), an unsourced or missing `reports-to` with no flags
   passed (`next=reports_to`), owed parties (`next=tell`),
   `carry-unacknowledged` (`next=go_ahead carry`), anything else
   (`next=fix handover`). With none left, `next=report_up` and
   `evidence=reconciled: reported`: the agent sends the report up and submits
   that evidence itself.

### Key Interfaces

**Flags of its own.** `--reports-to <value>` with `--reports-to-source
brief|dispatch|person` or `--reports-to-inferred "<sentence>"`;
`--watch-armed`; everything else goes to the opener as given.

**Digest.** In this order, each line only when it applies:

```
outcome=<continued|resumed|refused>      or failed=<kind>   (the opener's)
reason=<code>                            (the opener's, on a refusal)
detail=<first error line of the failing step, cut at 200 characters>
session=<new run>
predecessor=<old run>
predecessor_stopped=<yes|no>
watcher=<stopped|absent|unobserved>
leg_wake=<supported|unsupported>
role=<manager|director>
opened=<1|2>                             (opener runs this invocation)
reports_to=<written|unchanged|owed>
state=<where koto stopped>
record=<the report's record line>
report=ready:<n> blocked:<n> ongoing:<n> changes:<n> not_verified:<n>
gaps=<n>
gap=<gap>: <fix>                         (at most 8, then gaps_more=<n>)
owed=<party> <address>                   (before next=tell; owed_more=<n> past the budget)
told_cmd=state-stored-set.sh --session <new run> --told <party> --by <you>
watch=koto request watch --session <new run> --timeout-secs 7200
directive=<path>   report=<path>   fix=<the gap's fix line>
outputs=<dir|removed>
next=<token> [<argument>]
```

The opener's lines and the handover check's `gap=` lines are copied as
printed, after the cleaning Security Considerations describes. The report counts come from the JSON mode, so
`reconcile-report-get.sh` doesn't change.

**`next=` tokens and exit codes.**

| Exit | Who acts | `next=` |
|---|---|---|
| 0 | the agent, and the succession is over | `report_up` (send the report, submit `reconciled: reported`), `dispatch` (already past reconcile) |
| 10 | a person answers, then the agent runs it again | `resolve_conflict <run>`, `answer role\|host\|posture`, `go_ahead carry` |
| 11 | the agent acts, then runs it again | `arm_watch`, `reports_to`, `tell`, `directive`, `rerun` |
| 1 | the agent fixes what `failed=` names | `fix <step>` |
| 2 | the opener or koto refused; `reason=` says why | `fix open` |
| 64 | usage | none |

### Data Flow

Nothing flows between invocations except through koto and the record. Each
run reads the opener's result lines afresh (so `session=` is never stored),
reads `koto status` for the new run's state, reads the record through the
existing scripts, and writes only through the existing writers: the opener,
`state-stored-set.sh --run reports-to`, `koto next`, and
`handover-classify.sh`'s own rows. The scratch directory is write-only for
the command; only a person or the agent reads it, when a step fails.

## Implementation Approach

### Phase 1: The watch probe as a library

Move `watch_pids` out of `coordinate-open.sh` into `watch-probe.sh`, sourced
by the opener. Its tests show the opener's output unchanged. This comes
first because the driver needs the probe.

Deliverables:
- `skills/coordinate/scripts/watch-probe.sh`
- `coordinate-open.sh` sourcing it; the existing opener tests passing as they
  are

### Phase 2: The driver through the takeover and the watch

`coordinate-succeed.sh` with the scratch directory, the digest, the exit
codes, the open step and its one attributed retry, the re-point and the watch
stop. Offline tests with stub `koto` and `gh` cover each refusal passing
through, the retry on `takeover_unfinished`, the retry on an attributed
`predecessor-unstoppable` and its refusal when the fence names another actor
or can't be read, and `next=arm_watch`.

Deliverables:
- `skills/coordinate/scripts/coordinate-succeed.sh` (open, re-point, watch)
- `skills/coordinate/scripts/coordinate-succeed_test.sh`

### Phase 3: Ticks, the report and the handover

The tick loop with its bound, the report step, the classifier and the
handover check, and the gap-to-stop ordering. Offline tests for each `next=`
token and the digest's line cap; an engine test that cuts a real takeover
short at each step and checks that re-runs end with one takeover entry, no
duplicated record row and the same digest.

Deliverables:
- the remaining steps in `coordinate-succeed.sh`
- `skills/coordinate/scripts/coordinate-succeed_engine_test.sh`, including a
  diverged bucket copy for the version conflict assumption

### Phase 4: SKILL.md and evals

Point the takeover section at the command, its flags and its `next=` table;
keep the watch rule as prose. Add or update the skill's eval scenarios for a
successor driving a takeover through the command.

Deliverables:
- `skills/coordinate/SKILL.md`
- `skills/coordinate/evals/evals.json`

## Security Considerations

The command downloads nothing, adds no dependency and opens no network
connection. It's a shell driver that calls scripts the skill already ships,
runs as the user with no added privilege, and writes only through the
existing writers. It depends on the tools the opener already needs (bash, jq,
awk, ps, koto and gh), and its two new files ship through the plugin's normal
release path. What's left to get right is what the command copies into its
output, the one destructive step it takes on disk, and whose authority it
acts on.

### Text the command copies

The agent reads the digest and acts on it, so the digest must not carry text
that can pose as one of the command's own lines. Several values come from
outside the command: the opener's lines, `detail=` (cut from a failing
step's stderr), gap text, party names and addresses read from the record, and
run names. A newline or an embedded `next=` in any of them could forge a
digest line, and a party or run name with shell metacharacters could add an
argument or a second command to a `watch=` or `told_cmd=` line, which the
agent runs.

- Every value copied into the digest has control characters and newlines
  stripped and is cut to a fixed length before it's printed. `detail=` is one
  line of at most 200 characters.
- A copied value is never printed at the start of a line under a key the
  driver reserves; `next=` is built only by the driver from its fixed token
  set and is always the last line, so no copied text can stand in for it.
- Party and run names placed in `watch=` and `told_cmd=` are checked against
  the name pattern koto accepts and quoted. A name that fails the check is
  never printed inside a command line.
- Directive text and reports go to scratch, and the digest carries only
  their paths. The agent treats those files as data from koto's template and
  the record, not as instructions to the command.

### Scratch directories

Each run makes its directory with `mktemp -d`, which gives an unpredictable
name and mode 0700, and the driver sets `umask 077` for the files it writes
inside. The directory holds koto content and the Claude session id, so only
the user can read it, and it stays out of the work tree and out of git. It's
kept after any failed run until the same session's next start, and it can be
picked up by backups that include `$TMPDIR` until then. That's the user's own
run data; this repository is public, so tests and fixtures use synthetic data
only.

Cleanup at start is the one destructive filesystem step. When `$TMPDIR` is
unset the temp root is a shared `/tmp`, where another user could plant a
directory with a forged `owner` file. The driver removes a directory only
when all of these hold:

- it's a real directory, not a symlink, directly under the temp root;
- it's owned by the current user;
- its name matches `coordinate-succession.*`;
- its `owner` file holds exactly this session's id.

The `owner` file decides cleanup and nothing else. No takeover or retry
decision reads it.

### Process-table probe

The watch probe reads the process list and prints the pids of
`koto request watch --session <run>`. It prints only pids and passes the run
name to awk as a variable, so a hostile name can cause a wrong match but
can't run anything. A watch started by another process for the same run also
satisfies the probe, so a positive result says a watch exists, not that this
agent's is armed; the probe matches only the current user's processes to
narrow that. `--watch-armed` is the agent's own statement and the command
can't verify it. A wrong answer costs a tick without the agent's watch, which
delays a worker's wake until the next reconcile; it grants no access.

### Authority and attribution

The command acts only on a takeover it can prove is this session's own.

- **The retry.** It runs the opener a second time only when the opener
  printed `failed=takeover_unfinished` (which the opener prints only after
  `fenced_for` matched both the fence's successor and its Claude session) or
  when the opener refused `predecessor-unstoppable` and a fresh fence read
  shows both `.by` equal to the successor the command is about to retry and
  `.claude_session` equal to this session's id. The opener doesn't make that
  second check for this reason code, so the driver makes it itself, matching
  both fields as `fenced_for` does. A fence by this session on a different
  successor doesn't count.
- **The session id.** It comes from `CLAUDE_CODE_SESSION_ID` in the
  environment, never from a flag or a file in scratch. An empty value means no
  attribution, and an unreadable fence means "not this session's"; either way
  there's no retry, and the opener's refusal passes through with exit 2. This
  guards against crossed and stale sessions. It doesn't defend against
  another process of the same user that sets the variable, but such a process
  can already run koto directly.
- **No acting on an unconfirmed run.** Every invocation starts with the
  opener, and the command ticks only after this invocation's own opener call
  printed `outcome=continued` or `outcome=resumed`. It stops on any refusal
  before it re-points, checks the watch or ticks. Ticks use `--no-cleanup` and
  never `--to`, so the command can't skip a state or destroy the run's
  record, and they're bounded at 12 per invocation.
- **`reports-to`.** It's written only from flags the agent passes with an
  explicit source; an inferred value lands awaiting confirmation, and a value
  with no source is a usage error (exit 64). The command never defaults the
  source. `--reports-to-source person` is the agent's statement that a person
  gave the answer, which the command can't check; the record keeps the source
  so a reviewer can see where the value came from.
- **`told`.** The command never writes it, because it records a delivery
  the command can't make. It prints the command for the agent to run after
  the message lands; the handover gate and the person reading the record
  remain the check that a message was actually sent.
- **Person gates.** The carry go-ahead, the role, host and posture answers,
  and a koto version-conflict choice all stop with exit 10 and can't be
  passed by any flag. The command never runs `koto session resolve`. A flag
  that bypasses one of these (a `--yes` or `--acknowledge-carry`) would change
  this design's trust model and needs its own review.

## Consequences

### Positive

- A succession becomes one command run again after each stop. A clean run
  costs the agent a digest of about 25 lines per stop instead of every
  step's full output, which is where the issue's 70K tokens went.
- A takeover cut short after this session's fence finishes inside the
  command in the common case, so the agent doesn't read and re-run the opener
  by hand.
- Nothing new can disagree with koto: the command keeps no state, and every
  write goes through an existing writer.
- Who closes each gap is written down in one table, and the exit code says
  whether the next move is the agent's or a person's.

### Negative

- The command depends on the opener's result lines and the handover check's
  gap lines staying stable. A new gap code or outcome line needs a matching
  change here.
- Each re-run repeats a few reads (the opener's resume, `koto status`, the
  handover check). That's cheap next to the outputs it replaces, but it isn't
  free.
- A lasting fault after the fence costs one more carry before the command
  stops, and a carry was the slow part of the issue's opener runs.
- The compare's job rests on an assumption about how koto reads a conflicted
  predecessor under the cloud backend. If it's wrong, a takeover could go
  ahead on a stale local copy.
- The agent still owes one message and one `--told` per live worker and the
  dispatcher after every takeover. The command lists them; it can't send
  them.

### Mitigations

- The driver's tests read the opener's and the handover check's lines from
  the same fixtures those scripts' tests use, so a change to either fails
  here too.
- The one retry is bounded per invocation and attributed by the fence's
  actor, so it never multiplies carries or acts on another session's fence.
- Phase 3's engine test runs a takeover against a diverged bucket copy before
  the command ships. If koto reads the conflicted copy without complaint, the
  fallback is Decision 3's composed read inside the command, not a new
  script.
- Why the opener's carry took about 32 minutes in the issue's succession is
  outside this design. The digest's `opened=` line and the kept scratch
  directory make that time visible for a follow-up.

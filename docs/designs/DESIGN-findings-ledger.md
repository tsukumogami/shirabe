---
schema: design/v1
status: Planned
problem: |
  /work-on's panel ledger keeps verdicts per reviewer seat, so a retry
  re-spawns every blocking seat and re-runs any passed seat whose citations
  the fix touched (up to seven runs per retry), findings have no identity
  across rounds, and the gate passes on seats rather than on findings closed
  by a reviewer.
decision: |
  verdict_ledger.json gains a findings map keyed by a content id, each finding
  with ordered records whose writer and run panel-scope.sh checks; seat
  entries are derived from it. A retry round plans one re-verifier per panel
  for the findings the fix touched (plus fixed, unverified and location-less
  ones) and folds in one review of the fix's diff per retry; --mark-fixed
  writes the agent's non-closing claim. --verdict passes only when every
  blocking finding is closed by a reviewer, check or decider record, printing
  each open one under its own active rule or the new panel/open-finding.
rationale: |
  One map keyed by id makes lookups, the due rule and whole-document writes
  simple while the old readers keep their seat entries. One run per panel is
  the only shape that bounds a retry at three runs instead of seven, and
  recording its answers through --record keeps one write per run. A declared
  dynamic resolver lets a finding print under its own rule without letting an
  inactive id through. Full rounds, the 200-line rule and the retry cap stay
  as they are, so no first round and no cap gets weaker.
upstream: docs/prds/PRD-findings-ledger.md
---

# DESIGN: findings-ledger

## Status

Planned

## Context and Problem Statement

`skills/work-on/scripts/panel-scope.sh` is the only writer of the
`verdict_ledger.json` koto context key. It runs in five modes. `--plan` runs as
the `default_action` of each panel state (`scrutiny`, `review`,
`qa_validation`, `light_review`) and writes `<panel>_scope.json`, one decision
per seat: `full`, `recheck` (the seat blocked; its blocking findings plus the
fix diff go to it), `rerun` (the seat passed, but the fix touched a path it
cited, a location of a finding it raised, or more than 200 lines), or `keep`.
`--record` takes a round file the agent builds from the seats' answers and
stores each seat's verdict, `judged_at` commit, citations and findings.
`--carried`, `--recorded` and `--verdict` are the panel state's gates; the last
is the panel's pass (DESIGN-output-gates Decision 4), exit 0 when no seat is
blocking, 1 with one `panel/blocking-finding` line per blocking finding, 2 when
it can't decide.

Three things in that shape stand between it and what the PRD asks for.

The unit is the seat. A seat's findings are replaced wholesale on each record,
and a re-check returns only the findings that still hold, so a finding has no
identity beyond one round, and "fixed" is the absence of an answer. The PRD
needs each finding to keep a content-derived id across rounds (R2), with an
ordered list of records that each name a writer kind and a run (R3, R5), and
needs the agent's own claim, `fixed`, to be a record that never closes (R5,
R6).

The cost follows the seat too. Every blocking seat is re-spawned, and every
passed seat whose citations the fix touched is re-run in full, so a retry at
the `full` level can spend seven reviewer runs. The PRD replaces that with a
due rule over findings (R8): an `open` finding is due when the fix diff from
its location's commit touches it (any change to a `file` location's path, a
hunk overlapping a `lines` location's range), a `fixed` or `unverified` one is
always due, a `none` or unresolvable one is due until closed, and a closed one
is due only as a regression check when touched. A non-full round makes at most
one reviewer run per panel (R11), which re-verifies every due finding by id
and, once per retry, reviews the fix's own diff from the newest recorded
commit (R10). The passed-seat re-run goes (R9). Full rounds stay what they are
today for the first round, changed criteria or plan, a rewritten history, a
dirty tree, no commits, and a fix over 200 changed lines (R7, R11); in a full
round each seat is also handed its own unclosed blocking findings by id.

The gate reads seats. The PRD needs `--verdict` to pass exactly when every
blocking finding is closed by a `reverified` or `dismissed` record whose writer
is a reviewer, a check, or (for its own finding) a decider, naming a run of its
round (R12), with 2 winning over 1. It prints each unclosed blocking finding
under its own registry rule when a check raised it or a reviewer cited an
active id, and otherwise under a new generic entry, `panel/open-finding`,
while `panel/blocking-finding` is retired (R13, R14).

Two more constraints shape the code. A raiser of kind `decider` must be
accepted with a `decider_checked` reference (state, `visit_seq`, gate, rule id,
declaration hash, input hash), mapping `fail` to raised, `pass` to reverified
on its own finding, and every other outcome to `unverified` (R15), though
nothing produces one yet. The retry cap keeps its numbers and its
`panel_retries` key; the count it is given becomes the number of findings
`--verdict` printed (R16), because koto 0.15.0's attempt counts tick on every
gate evaluation and are readable by no command.

The ledger's existing readers must keep working (R1): `review-shadow.py`'s
`read_ledger_seats` (seat `verdict`, `judged_at`, `ac_sha`, findings' `path`
and `lines`), `review-level.sh report` (sums `history[].spawned`), and
`review-packet.sh recheck` (reads a `recheck` decision's `findings` and
`fix_diff_from` from the scope).

## Decision Drivers

- **The pass stays koto's (R12).** Whatever the agent writes, the gate decides
  from records whose writer and run are checked; an agent-written `fixed`
  never closes anything.
- **Fail closed (R8).** A location the script can't resolve, a diff that
  fails, or a ledger it can't read leads to a re-check or a hold, never to a
  carried pass.
- **No first round shrinks (R7, R19).** Every saving comes from rounds after a
  block.
- **Bounded runs (R11, R17).** At most one reviewer run per panel outside a full
  round; the fixture shows 1 where today's rule makes 3.
- **Existing readers keep working (R1).** Seat entries, `history[].spawned`,
  and the `recheck` decision's fields stay readable.
- **Bash 3.2 and jq only.** `panel-scope.sh` runs on the macOS floor leg; no
  associative arrays, no new runtime dependency.
- **koto 0.15.0, unchanged.** Only context keys, command gates and
  `default_action` are available.
- **Registry discipline (R13, R14).** Rule ids are stable names; a printed id
  is active; `check-rule-registry.sh` keeps passing.
- **No harness edits.** `docs/measurement/` and `scripts/ablation/` don't
  change in this pull request.

## Considered Options

### Decision 1: Where finding state lives in the ledger

`--record` today overwrites `.seats["<panel>/<seat>"].findings` on every
round. The PRD needs findings that outlive a round, are found by id, carry an
ordered list of records, and fold to a status, while `read_ledger_seats`,
`review-level.sh report` and `review-packet.sh` keep reading what they read
now.

Key assumptions:

- `git hash-object --stdin` is available wherever the script runs; it
  already computes the criteria hash with it.
- A session's ledger holds tens of findings, so rewriting the whole document
  on each write is cheap.
- The only older shape is a ledger with `seats` and `history` and no
  `findings` key.

#### Chosen: a top-level `findings` map keyed by id, seat entries derived

The ledger gains a `findings` map beside `seats` and `history`. Each value
holds the finding's fields and its `records` array. The id is the first 16
hex characters of `git hash-object --stdin` over a canonical string that jq
prints with `-j`: panel, raiser kind, raiser name, the location's path (empty
for `none`), and the summary with runs of whitespace collapsed to one space
and trimmed, joined by newlines. Line ranges stay out, so a finding whose
lines shift keeps its id (R2). Two different canonical strings that hash to
the same 16 characters are refused rather than merged.

Status is never stored. A jq function maps the latest record's kind to it
(`raised` and `holds` to `open`, the rest to themselves), so status can't
drift from the records (R5). Findings raised by `fix-review` or a decider
belong to no seat and appear in no seat summary. Seat entries become
summaries recomputed in the
same jq pass that changes `findings`: a seat's `verdict` is `blocking` when
it raised an unclosed blocking finding, its `findings` array lists those
findings with top-level `path` and `lines`, and `judged_at`, `ac_sha`,
`cited` and `finding_locations` keep their meaning. `read_ledger_seats` reads
the same shape it reads today (R1).

A ledger with no `findings` key was written before this change. R7 makes
its next round full, `--verdict` holds (exit 2) until that round is
recorded, and nothing from the old seat entries is imported as a record, so
an old ledger can't carry a pass the new gate never checked. A new ledger
always has the key, possibly empty.

Every write validates its whole input first, builds the complete new ledger
in one jq pipeline into a temporary file, and stores it with one `koto
context add`. Any refusal exits before that call, so the stored ledger is
byte-identical (R6).

#### Alternatives Considered

**Findings nested under each seat entry.** Keeps one map. Rejected because a
finding closed by the panel's re-verifier, raised by the fix-diff review, or
raised by a decider has no natural seat, so finding one by id becomes a scan
across seats, and the seat `findings` field `read_ledger_seats` depends on
would change meaning.

**An append-only event list, status folded from events.** The most auditable
shape. Rejected because every gate tick and every due computation would
refold the whole list, the seat summaries the old readers need would still
have to be kept, giving two sources of truth, and per-finding `records`
already keep the order with atomic whole-document writes.

**A jq-only id.** jq has no hash function. Using the canonical string itself
as the id is unbounded in length and awkward as a command-line argument to
`--mark-fixed`.

### Decision 2: How a retry round reaches one run per panel

Outside a full round the PRD allows one reviewer run per panel (R11). That
run has to re-verify every due finding by id, carry the once-per-retry
fix-diff review when it lands on this panel (R10), and record answers whose
writer and run the script checks (R6), while the agent's own claims stay a
separate, non-closing write (R5).

Key assumptions:

- The fix-diff review reads the whole fix, so the re-verifier needs no other
  channel for new defects.
- Due findings share one or two base commits, so one packet diff from the
  oldest base is not much wider than per-finding diffs; the cost of being
  wrong is a longer packet, never a missed hunk.
- The agent marks findings fixed after committing the fix and before the
  tick that enters the panel; a later claim misses that round and the finding
  is due the next one.

#### Chosen: one panel-level re-verifier, recorded through `--record` with an `answers` array

`--plan`, in a round that is not full, writes a `keep` decision for every
real seat and adds one decision for a seat named `reverifier` (a name no
panel uses for a real seat, so `review-packet.sh recheck --seat reverifier`
can't pick up a real seat's decision) with `decision: recheck`, the due
findings by id, `fix_diff_from` (the oldest base among them), `fix_review`
and `review_from` (when the fix-diff review lands here), and a `run` id that
`--plan` mints. `findings` and `fix_diff_from` keep the names
`review-packet.sh` reads. With nothing due and no fix-diff review, every
decision is `keep`; the panel carries only when it also has no unclosed
blocking finding, and otherwise falls through to `--verdict`, which blocks
at no reviewer cost. `history[].spawned` counts the non-`keep` decisions,
so it is the number of runs.

`--plan` mints the run ids for every decision it spawns, full rounds
included, and the round file must name them: each entry carries the `run`
its decision was given, each run is recorded at most once, and an entry
naming a run the scope didn't mint is refused. Nobody records a run that
wasn't planned. The spawned agent's own id may ride along as `agent`, for
audit, and is not checked.

A re-verifier entry holds `answers`, each an id and a record kind. In a
non-full round the re-verifier may answer only `holds` or `reverified`:
dismissing a finding is the raising seat's call, made in a full round where
that seat is handed its own unclosed findings and may answer `dismissed` with
a reason. Only when the scope planned a fix-diff review may the entry also
carry `findings`, raised by `reviewer/fix-review`. The script derives the
writer kind from the entry's shape. `--record` refuses, before writing, an
unknown id, a `dismissed` from the re-verifier or without a reason, a run the
scope didn't mint or one already recorded, two findings of one run with the
same id (asking for distinct summaries), fix-diff findings the scope didn't
plan, and an inactive rule id. It then writes a marker, `reverified.<panel>`,
holding the new revision and the run, and `--recorded` and `--verdict` count
the `reverifier` decision as recorded only when that marker is newer than the
scope.

The agent's claim gets its own mode, `panel-scope.sh --mark-fixed <panel>
<session> <id>...`, which appends a `fixed` record by writer `agent` for each
id, refuses an unknown or already-closed id, and sets no marker.

`review-packet.sh recheck` keeps its flags and its fail-wide fallback: the
findings section lists due findings by id, the header gains `fix review:` and
`review from:` lines, and a bad `review_from` falls back to the code packet's
base like a bad `fix_diff_from` does. When the packet carries a fix review it
also carries every panel's blocking criteria (the scrutiny, review and QA
roles' questions), not only the hosting panel's, since that one review stands
in for the panels the retry will re-enter. The re-check prompt in
`review-seat-commissioning.md` is rewritten to answer each finding by id with
`holds` or `reverified` and, when the packet says so, to review the fix diff
against those criteria; its sentence that a passing re-check records the seat
as passed goes.

#### Alternatives Considered

**Re-check by each raising seat, the fix-diff review as one more seat.** Keeps
the seats' roles on their own findings. Rejected: up to three raising seats
plus the fix-diff review is four runs for one panel, which breaks R11 and the
saving R17 measures, and a check or decider raiser has no seat to spawn.

**A separate `--reverify` mode and answers file.** Keeps answers apart from
round files. Rejected because one reviewer run would then be recorded in two
calls, since its fix-diff findings still need `--record`'s checks; that opens
a half-recorded window, needs a second marker and an ordering rule, and a
refused second call would leave the first call's write standing, against R6.

### Decision 3: How the gate prints a rule id that varies per finding

`rule-findings.sh` resolves only the ids named on a script's static
`RULE_IDS` line, and `check-rule-registry.sh` check 6 reads those lines to
know every id a script can print (DESIGN-rule-registry Decision 8). The PRD
needs a finding with a rule to print under that rule, an unruled finding to
print under `panel/open-finding`, and no inactive id ever printed (R13, R14).

Key assumptions:

- `rule-registry.sh` reports an entry's status at run time, as `rf_require`
  already relies on.
- An entry can be retired between `--record` and `--verdict`, so the gate
  re-checks at print time.

#### Chosen: a dynamic resolver with a declared, allowlisted exception

`rule-findings.sh` gains `rf_require_any <id>...`, which resolves any active
registry id at run time and calls `undecided` (exit 2) for an unknown or
retired one; `rf_emit` is unchanged and still refuses an id this run didn't
resolve. `panel-scope.sh` keeps `RULE_IDS="panel/open-finding"` and adds a
line `RULE_IDS_ANY_ACTIVE=1`. `check-rule-registry.sh` requires the marker
and a call to `rf_require_any` to appear together, allows the marker only in
`panel-scope.sh`, and keeps check 6 on every static line. A finding whose
cited id was retired after it was recorded prints under `panel/open-finding`
with the old id in its message, so a retirement neither prints an inactive id
nor wedges the gate.

#### Alternatives Considered

**Print every finding under `panel/open-finding`, its own id in the
message.** The cheapest change, and CI's knowledge of printable ids stays
exact. Rejected because it contradicts R14: a reader joining on `rule_id`
would see every ruled finding as generic.

**A static `RULE_IDS` listing the generic id and the panel checks' ids,
refusing other cited ids at `--record`.** Rejected because R13 lets a
reviewer cite any active id, and a hand-kept list drifts from the registry.

## Decision Outcome

The three decisions meet at the ledger. Findings live in one map keyed by a
content id, each with its own records, and the seat entries the old readers
use are recomputed from that map in the same write. A retry round is planned
over findings, not seats: `--plan` computes the due set from each finding's
status and the fix diff since it was last judged, and puts every due finding,
plus the once-per-retry fix-diff review, into one `reverifier` decision for
the panel, with a run id it mints. That run's answers come back through
`--record` by id, limited to `holds` and `reverified`, and the agent's own
`fixed` claims go through a separate mode that can't close anything.
`--verdict` then reads only records: a blocking finding is closed when its
latest record is `reverified` or `dismissed` by an allowed writer, and every
unclosed one prints under its own active rule or under `panel/open-finding`.
A panel never carries past an unclosed blocking finding.

Full rounds are what they are today, with one addition: each seat is handed
its own unclosed blocking findings and answers them by id, and findings no
seat raised go to a re-verifier in the same round, so a full round never
silently drops one; it is also the one place a finding can be dismissed. The 200-line rule is kept as a full-round trigger: a fix that
size is new work, and one re-verifier reading it is not a substitute for the
panel's seats. The passed-seat re-run is the rule that goes, replaced by the
fix-diff review, which judges the fix against every panel's criteria.

The cap's count moves off the agent: `panel-retry-budget.sh` reads the
number of unclosed blocking findings from the ledger itself, through a
read-only `panel-scope.sh --open-count` mode, instead of taking it as an
argument.

On cost: at the `full` level today's worst case per retry is seven runs
(three scrutiny, three review, one QA). Outside a full round the new worst
case is three, one per panel; that is a bound, not a measurement. On the
PRD's fixture (three scrutiny seats each blocking on one finding in its own
file, a fix touching one file) the second round makes one run where today's
rule makes three, which the suite measures.

## Solution Architecture

### The ledger

```json
{"rev": 7,
 "seats": {"scrutiny/completeness": {"panel": "scrutiny", "seat": "completeness",
            "verdict": "blocking", "judged_at": "<sha>", "rev": 3, "ac_sha": "<sha>",
            "cited": [], "finding_locations": [],
            "findings": [{"id": "3f9a0c1d2e4b5a69", "severity": "blocking",
                          "summary": "...", "path": "src/a.sh", "lines": "12-14"}]}},
 "findings": {"3f9a0c1d2e4b5a69": {
     "id": "3f9a0c1d2e4b5a69", "panel": "scrutiny", "severity": "blocking", "round": 1,
     "raiser": {"kind": "reviewer", "name": "completeness"}, "run": "scrutiny-r1-completeness",
     "location": {"kind": "lines", "path": "src/a.sh", "lines": "12-14", "at": "<sha>"},
     "summary": "...",
     "records": [{"kind": "raised", "writer": {"kind": "reviewer", "name": "completeness",
                  "run": "scrutiny-r1-completeness"}, "round": 1, "commit": "<sha>"},
                 {"kind": "fixed", "writer": {"kind": "agent", "name": "work-on"},
                  "round": 1, "commit": "<sha>"}]}},
 "reverified": {"scrutiny": {"rev": 7, "run": "scrutiny-r2-reverifier", "head": "<sha>"}},
 "runs": {"scrutiny-r2-reverifier": {"panel": "scrutiny", "rev": 6, "recorded": true}},
 "history": [{"panel": "scrutiny", "round": 2, "head": "<sha>", "rev": 6, "spawned": 1,
              "decisions": [{"seat": "completeness", "decision": "keep", "reason": "..."}]}]}
```

Ids are the first 16 hex characters of the hash (12 is cheap to grind for a
collision; 16 isn't), and two different canonical strings that collide are
refused. `rule_id` is present only under R13. A ledger written before this
change has no `findings` key at all; a new ledger always has one, possibly
empty, so the two can't be confused.

A decider raiser is `{"kind": "decider", "name": "<gate>/<rule_id>", "ref":
{"state", "visit_seq", "gate", "rule_id", "declaration_hash",
"input_sha256"}}`; its finding is `blocking`, its summary and `rule_id` are
the criterion's id. Decider entries reach `--record` as `{"decider": {...ref,
"outcome"}, "run": "<minted run>"}`, and `--record` accepts one only when
koto's own session log (under `koto session dir <session>`) holds a
`decider_checked` event with the same state, `visit_seq`, gate, rule id,
declaration hash, input hash and outcome, and that event has not backed an
earlier decider entry (each event is used once). The log is koto's to write,
so a decider verdict can't be minted by writing a round file; it would take
editing koto's own log, which the residual-risk paragraph below covers. Outcome `fail` writes
`raised`; `pass` writes `reverified` only on that decider's own finding for
the criterion, and nothing when there is none; every other outcome writes
`unverified`, and when no finding exists yet for the criterion it creates one
whose first record is `unverified`, so a criterion the decider couldn't
answer in its first round blocks the gate under its own rule id and goes to a
reviewer instead of passing silently. Nothing writes decider entries yet; the
suite drives them with a fixture log.

### Records and who may write them

| Record | Status | Closes | Allowed writer |
|---|---|---|---|
| `raised` | `open` | no | reviewer, check, decider |
| `holds` | `open` | no | reviewer, check |
| `reverified` | `reverified` | yes | reviewer; check on a finding a check raised; decider on its own finding |
| `dismissed` (reason required) | `dismissed` | yes | the raising seat, in a full round |
| `fixed` | `fixed` | no | agent (`--mark-fixed` only) |
| `unverified` | `unverified` | no | decider |

The `check` writer kind is reserved: no check writes ledger records yet, and
`--record` never assigns it from a round file, so today every record is a
reviewer's, a decider's (bound to koto's log) or the agent's. A finding a
check raises will be closable only by a check.

Severity is set when a finding is first raised. A re-raise of a known id
appends `raised` (re-opening it if closed) and keeps the stricter severity,
so `blocking` wins. Advisory findings get `raised` and nothing else; they are
never due and never counted.

### Planning a round (`--plan`)

A round is full when any R7 trigger holds: a seat of the panel has no
recorded verdict (the first round), the ledger has no `findings` key (written
before this change), a changed criteria-and-plan hash, a recorded commit off
HEAD's history, `git status --porcelain` non-empty, no commits since
`impl_base`, or a fix diff over 200 changed lines from the newest recorded
ancestor commit (added plus deleted per `--numstat`, binary files 1 per
side). A failing `git diff` also makes the round full. In a full round every
seat is `full`, gets a minted run id, and its decision carries the seat's own
unclosed blocking findings, which `review-packet.sh code` lists for it by id.
Unclosed blocking findings no seat raised (from the fix-diff review or a
decider) get one `reverifier` decision in the full round too, so no finding
is left without someone to answer it; that is the one case a full round
spawns a run beyond its seats.

QA's failed scenarios are findings like any other: the tester raises each as
a blocking finding, usually with location `none`, so they are due on every
retry until the tester reverifies them.

Otherwise each blocking finding of the panel is checked against R8's table.
Its base is the commit of its latest record not written by the agent, the
last time something judged it. A finding judged at HEAD is not due unless a
later `fixed` record asks for it, which keeps a re-plan at the same HEAD from
re-checking what was just answered. "Touched" is today's `touches()` over
`git diff --no-renames --literal-pathspecs <base> HEAD -- <path>`; a `lines`
location is checked by range only when its file didn't change between the
location's `at` and the base, and as `file` otherwise. A base or location
commit that is gone, or a diff that fails, makes the location unresolvable,
and the finding due unless closed.

The fix-diff review lands at this panel when the diff to HEAD from the newest
recorded ancestor commit (the one with the most ancestors among findings'
records, seats' `judged_at` and markers, never counting a record the agent
wrote) is non-empty. Leaving the agent's `fixed` records out matters: they
are stamped at HEAD after the fix is committed, and counting them would make
the fix diff empty and skip both the fix-diff review and the 200-line rule.
The 200-line rule measures from the same commit. When two candidates
aren't ordered by ancestry (a merge brought them in on different sides), the
older of them is taken, which widens the diff rather than narrowing it; if
the ancestry can't be computed, the round is full. Once this panel records
at HEAD that commit is HEAD, so later panels in the retry see an empty diff
and plan none. A seat's `judged_at` moves only when that seat itself runs;
the re-verifier's commit lives in its marker.

The guard that leaves a recorded round's scope in place at an unchanged HEAD
is generalised: when every run the scope minted is recorded, HEAD, the tree
and the criteria are what the round saw, and no `fixed` record was written
since, the scope stands, whether or not a finding is still open. A `fixed`
record after the round re-plans it, so `--mark-fixed` takes effect at an
unchanged HEAD. `--carried` exits 0 only when every decision is `keep`
and the panel has no unclosed blocking finding.

### Recording (`--record`) and marking (`--mark-fixed`)

`--record <panel> <session> <round-file>` keeps its checks (scope head, 68;
malformed file, 65) and adds the ones in Decision 2, plus shape checks before
anything reaches git, the registry or the ledger: ids are 16 lowercase hex,
commits 40, run ids match the minted form, record kinds and severities are
exact lowercase members of their sets, paths are relative with no `..`
segment, no leading `-` and no control character, and summaries and reasons
are at most 1,000 bytes; seat and raiser names match `^[a-z][a-z0-9-]*$` (a
decider's `<gate>/<rule_id>` with the registry's id pattern); a run holds at
most 50 findings and 50 answers. A re-verifier's answers may name only the
ids its decision planned as due, and each `reverified` carries a one-line
reason saying what in the fix diff resolves the finding. `--mark-fixed
<panel> <session> <id>...` writes only `fixed` records. Both build the whole
ledger in a `mktemp` file (mode 600, removed on every exit), re-read the
stored ledger's `rev` just before storing and refuse (exit 69) if another
write landed in between, then store it with one `koto context add`. The
`rev` check catches overlapping honest writes; it is not a lock.

### The gate (`--verdict`)

1. Exit 2 when the ledger is unreadable or has no `findings` key, when a run
   the latest scope minted has no record since the scope was planned, or when
   a seat of the panel has no recorded verdict.
2. Collect the panel's unclosed blocking findings (`open`, `fixed`,
   `unverified`), re-checking each closing record's writer against the table
   above, so a hand-written ledger closing a finding with an `agent` or
   `check` record doesn't pass.
3. Resolve `panel/open-finding` and each collected finding's rule id with
   `rf_require_any`. A rule id that is no longer active or no longer in the
   registry falls back to `panel/open-finding` with the old id named in the
   message, so a registry change after recording never prints an inactive id
   and never wedges the gate.
   A failure to resolve `panel/open-finding` itself exits 2.
4. Exit 1, printing one finding per collected finding, message `<panel>/<raiser>:
   <summary>`, with `path` and `line` when the location has them.
5. Exit 0.

`--open-count <panel> <session>` prints the size of step 2's set, with no
side effect, for `panel-retry-budget.sh`.

### The registry

`panel/open-finding` is added: summary "A blocking finding in the panel's
ledger has no closing verdict record", text anchored in
`phase-4a-scrutiny.md`, `check` `panel-scope.sh --verdict`, `level: gate`,
the four panel states as `timing`, guards `pr-create` and `merge`, `withhold:
never`. `panel/blocking-finding` becomes `status: retired`, its `notes` naming
`panel/open-finding` as its replacement, and every `RULE_IDS` line and
directive that names it moves to the new id. `rule-registry_test.sh`'s counts
change accordingly.

### Retry counting

`panel-retry-budget.sh` keeps its rule, its numbers and its `panel_retries`
key. Its count argument goes: it runs `panel-scope.sh --open-count` for the
panel and uses that, so the progress rule compares counts the agent didn't
supply. koto's attempt counts aren't used: koto 0.15.0 stamps a new attempt on
every gate evaluation, including ticks held at a blocked verdict and carried
rounds, exposes no command to read them, and keeps no per-round finding
count, so they can't express the progress rule.

### Files

| File | Change |
|---|---|
| `skills/work-on/scripts/panel-scope.sh` | `findings` map, ids, records, run ids, due rule, `reverifier` decision, `answers`, marker, `--mark-fixed`, `--open-count`, decider entries bound to koto's log, gate over findings, `rf_require_any` |
| `skills/work-on/scripts/panel-retry-budget.sh` | reads the count through `--open-count` |
| `scripts/lib/rule-findings.sh` | `rf_require_any` |
| `scripts/check-rule-registry.sh` | the marker/allowlist rule |
| `references/rule-registry.json`, `references/rule-registry.md` | `panel/open-finding` added, `panel/blocking-finding` retired |
| `scripts/review-packet.sh` | recheck packet: due findings by id, `fix review` and `review from` lines, every panel's criteria with a fix review; code packet: a seat's unclosed findings |
| `references/review-seat-commissioning.md` | re-check prompt answers by id and reviews the fix diff |
| `skills/work-on/references/phases/phase-4a`..`4d` | round-file shape with `run` and `answers`, `--mark-fixed`, the budget call without a count |
| `skills/work-on/references/phases/phase-4-implementation.md` | mark findings fixed after committing the fix |
| `skills/work-on/koto-templates/work-on.md` | panel directives and comments: the new rule, the budget call, the carried rule |
| `*_test.sh`, `test_review_shadow.py` | the cases the PRD's criteria name |
| `.github/workflows/check-review-shadow.yml` | path filter gains `panel-scope.sh` |

## Implementation Approach

1. **Resolver.** `rf_require_any` and the marker rule in
   `check-rule-registry.sh`, with tests. `panel/open-finding` is added; nothing
   prints it yet, and `panel/blocking-finding` stays active.
2. **Ledger, plan and gate.** The `findings` map, ids, records, run ids, seat
   summaries, `answers`, `--mark-fixed`, decider entries, the due rule, the
   `reverifier` decision, the fix-diff review placement, full-round triggers,
   the marker, `--open-count`, `--verdict` over findings, and the retirement
   of `panel/blocking-finding` with every directive and `RULE_IDS` line that
   names it, all in one change, since the gate and the ledger move together.
   The R17 fixture lands here.
3. **Budget, packets, prompts, directives.** `panel-retry-budget.sh`,
   `review-packet.sh`, the re-check prompt, the phase files, the template
   text, and the shadow workflow's filter.

All three land in one pull request; the split is review order.

## Security Considerations

The change stays inside a session's own koto context and the repository's
git history; it adds no network access, no credential, and no dependency.

**Text from reviewers.** Finding summaries, reasons and paths are
model-written. They are stored as JSON strings through `jq --arg`, never
interpolated into a shell command; the id's canonical string is built by jq
and piped to `git hash-object --stdin`. Before anything reaches git, the
registry or the ledger, `--record` checks shapes: hex ids and commits, minted
run ids, exact record kinds and severities, relative paths with no `..`, no
leading `-` and no control character, and a 1,000-byte cap on text. Git gets
paths after `--` with `--literal-pathspecs`, and printed messages have
control characters replaced as today.

**Who can close a finding.** Not the agent's sanctioned channels:
`--mark-fixed` writes only `fixed`, a round file can't name a writer kind, a
run must be one `--plan` minted and is recorded once, a non-full re-verifier
can answer only the findings it was planned for and can't dismiss, and a
decider entry is accepted only when koto's own log holds a matching, unused
`decider_checked` event. `--verdict` re-checks writer rules when it reads.

**Residual risk, stated plainly.** The agent being gated still writes the
round file from its reviewers' answers, and can write the koto context key
directly. A deliberately dishonest agent can therefore record a `reverified`
answer no reviewer gave, or hand-write a ledger. koto 0.15.0 offers no record
the agent can't write except its own event log, which only the decider path
uses. This is the same trust today's seat verdicts rest on; the design closes
the agent's sanctioned routes to a pass, not every route. The retry count no
longer comes from the agent.

**Prompt injection.** One re-verifier now reads the fix diff, which the agent
wrote, and other reviewers' finding text, and can close several seats'
findings in one run; finding text also reaches the agent through `--verdict`
and later packets. This blast radius is the price of one run per panel, taken
deliberately. It is bounded: the re-verifier can answer only the findings
planned as due for it, only with `holds` or `reverified`, and each
`reverified` must say what in the diff resolved it; its prompt treats the
packet as data to judge, as every seat prompt does; and a `dismissed` still
needs the raising seat in a full round.

**Fail closed.** Every doubt in `--verdict` exits 2. An unresolvable location
is due. A failing diff makes the round full. A refused or racing write leaves
the ledger unchanged. A retired rule falls back to the generic rule rather
than holding forever.

**Data exposure.** Summaries may quote code from the diff into koto context
and later packets, which is where the same text lives today; the ledger is
never committed.

## Consequences

### Positive

- A retry outside a full round costs at most one reviewer run per panel,
  three per retry at the `full` level against today's worst case of seven;
  on the PRD's fixture, one run against three.
- Every finding has an id and a history, so a reader can tell a finding a
  reviewer closed from one that disappeared.
- The gate's pass rests on records with a writer and a minted run, the
  agent's sanctioned channels can't produce one that closes, and the retry
  count no longer comes from the agent. A dishonest agent writing the ledger
  directly is still possible, as it is today.
- A decider can report into the same ledger without the gate changing, and a
  decider that can't answer blocks rather than passes.

### Negative

- `panel-scope.sh` grows: the ledger write, the due rule and the gate all get
  more involved, in bash 3.2 and jq.
- One re-verifier answers for findings raised by seats with different roles.
- A reworded re-raise makes a new id, and the old one stays due until it is
  answered; two real findings with the same summary in one file must be
  worded apart.
- `rule-findings.sh` gains a dynamic path, a named exception to the rule that
  every printable id sits on a static line.
- An open finding the fix didn't touch blocks again at no reviewer cost, but
  each such round still spends a retry.

### Mitigations

- The re-verifier gets each finding's full text, location and raiser, and
  answers only whether that finding still holds.
- Full rounds and re-verification packets list unclosed findings by id.
- `--record` refuses duplicate ids within a run with a message asking for
  distinct summaries.
- The dynamic path is allowed in one script, checked by
  `check-rule-registry.sh`, and still refuses any id that isn't active.
- `--mark-fixed` lets the agent send a finding it fixed elsewhere to the
  re-verifier.
- The suites drive every new mode on fixtures, on the bash 3.2 leg.

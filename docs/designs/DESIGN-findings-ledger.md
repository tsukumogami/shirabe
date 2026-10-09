---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-findings-ledger.md
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
---

# DESIGN: findings-ledger

## Status

Proposed

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
holds the finding's fields and its `records` array. The id is the first 12
hex characters of `git hash-object --stdin` over a canonical string that jq
prints with `-j`: panel, raiser kind, raiser name, the location's path (empty
for `none`), and the summary with runs of whitespace collapsed to one space
and trimmed, joined by newlines. Line ranges stay out, so a finding whose
lines shift keeps its id (R2). Two different canonical strings that hash to
the same 12 characters are refused rather than merged.

Status is never stored. A jq function maps the latest record's kind to it
(`raised` and `holds` to `open`, the rest to themselves), so status can't
drift from the records (R5). Seat entries become summaries recomputed in the
same jq pass that changes `findings`: a seat's `verdict` is `blocking` when
it raised an unclosed blocking finding, its `findings` array lists those
findings with top-level `path` and `lines`, and `judged_at`, `ac_sha`,
`cited` and `finding_locations` keep their meaning. `read_ledger_seats` reads
the same shape it reads today (R1).

A ledger without `findings` reads as an empty map. R7 then makes the next
round full, and nothing from the old seat entries is imported as a record, so
an old ledger can't carry a pass the new gate never checked.

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
real seat and adds one decision named for the panel's re-verifier (`recheck`
for scrutiny and review, `tester` for QA, `reviewer` for light) with
`decision: recheck`, the due findings by id, `fix_diff_from` (the oldest
base among them), `fix_review` and `review_from` (the newest recorded
ancestor commit, when the fix-diff review lands here). `findings` and
`fix_diff_from` keep the names `review-packet.sh` reads. With nothing due and
no fix-diff review, every decision is `keep` and the panel carries as it does
today. `history[].spawned` counts the non-`keep` decisions, so it is the
number of runs.

The round file stays a JSON array, one entry per run, and every entry now
carries a `run` id. A re-verifier entry holds `answers` (each an id and a
record kind, `holds`, `reverified` or `dismissed`, with a reason for
`dismissed` and an optional new location) and, only when the scope planned a
fix-diff review, `findings` raised by `reviewer/fix-review`. A full-round
seat that was handed its own unclosed findings answers them the same way.
The script derives the writer kind from the entry; the file can't claim to be
a check or a decider. `--record` refuses, before writing, an unknown id, a
`dismissed` without a reason, a malformed or repeated run id, fix-diff
findings the scope didn't plan, and an inactive rule id. It then writes a
marker, `reverified.<panel>`, holding the new revision, the seat and the run,
and `--recorded` and `--verdict` count the `recheck` decision as recorded
only when that marker is newer than the scope.

The agent's claim gets its own mode, `panel-scope.sh --mark-fixed <panel>
<session> <id>...`, which appends a `fixed` record by writer `agent` for each
id, refuses an unknown or already-closed id, and sets no marker.

`review-packet.sh recheck` keeps its flags and its fail-wide fallback: the
findings section lists due findings by id, the header gains `fix review:` and
`review from:` lines, and a bad `review_from` falls back to the code packet's
base like a bad `fix_diff_from` does. The re-check prompt in
`review-seat-commissioning.md` is rewritten to answer each finding by id and,
when the packet says so, to review the fix diff; its sentence that a passing
re-check records the seat as passed goes.

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
cited id was retired after it was recorded holds the gate at 2 instead of
printing a retired id.

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
status and the fix diff since its location was recorded, and puts every due
finding, plus the once-per-retry fix-diff review, into one re-verifier
decision for the panel. That run's answers come back through `--record` by
id, with a run id the script checks against the round, and the agent's own
`fixed` claims go through a separate mode that can't close anything.
`--verdict` then reads only records: a blocking finding is closed when its
latest record is `reverified` or `dismissed` by an allowed writer, and every
unclosed one prints under its own active rule or under `panel/open-finding`.

Full rounds are what they are today, with one addition: each seat is handed
its own unclosed blocking findings and answers them by id, so a full round
never silently drops one. The 200-line rule is kept as a full-round trigger:
a fix that size is new work, and one re-verifier reading it is not a
substitute for the panel's seats. The passed-seat re-run is the rule that
goes, replaced by the fix-diff review.

On the saving: at the `full` level today's worst case per retry is seven
runs (three scrutiny, three review, one QA). Outside a full round the new
worst case is three, one per panel, and on the PRD's fixture (three scrutiny
seats each blocking on one finding in its own file, a fix touching one file)
the second round makes one run where today's rule makes three.

## Solution Architecture

### The ledger

```json
{"rev": 7,
 "seats": {"scrutiny/completeness": {"panel": "scrutiny", "seat": "completeness",
            "verdict": "blocking", "judged_at": "<sha>", "rev": 3, "ac_sha": "<sha>",
            "cited": [], "finding_locations": [],
            "findings": [{"id": "3f9a0c1d2e4b", "severity": "blocking",
                          "summary": "...", "path": "src/a.sh", "lines": "12-14"}]}},
 "findings": {"3f9a0c1d2e4b": {
     "id": "3f9a0c1d2e4b", "panel": "scrutiny", "severity": "blocking", "round": 1,
     "raiser": {"kind": "reviewer", "name": "completeness"}, "run": "<run id>",
     "location": {"kind": "lines", "path": "src/a.sh", "lines": "12-14", "at": "<sha>"},
     "rule_id": "rs-007", "summary": "...",
     "records": [{"kind": "raised", "writer": {"kind": "reviewer", "name": "completeness",
                  "run": "<run id>"}, "round": 1, "commit": "<sha>"},
                 {"kind": "fixed", "writer": {"kind": "agent", "name": "work-on"},
                  "round": 1, "commit": "<sha>"}]}},
 "reverified": {"scrutiny": {"rev": 7, "seat": "recheck", "run": "<run id>", "head": "<sha>"}},
 "history": [{"panel": "scrutiny", "round": 2, "head": "<sha>", "rev": 6, "spawned": 1,
              "decisions": [{"seat": "completeness", "decision": "keep", "reason": "..."}]}]}
```

A decider raiser is `{"kind": "decider", "name": "<gate>/<rule_id>", "ref":
{"state", "visit_seq", "gate", "rule_id", "declaration_hash",
"input_sha256"}}`; `ref` without state, gate, rule id or `visit_seq` is
refused. Its finding is `blocking` with the criterion's id as summary and
`rule_id`. Outcome `fail` writes `raised`, `pass` writes `reverified` only on
a finding that decider raised for the same criterion (and nothing when there
is none), and every other outcome writes `unverified` (R15). Decider entries
reach the ledger through `--record` round entries of the form `{"decider":
{...ref, "outcome"}, "run": "<id>"}`; the writer kind comes from that entry
shape. Nothing writes one yet; the suite drives it with fixtures.

### Records and who may write them

| Record | Status | Closes | Allowed writer |
|---|---|---|---|
| `raised` | `open` | no | reviewer, check, decider |
| `holds` | `open` | no | reviewer, check |
| `reverified` | `reverified` | yes | reviewer, check; decider on its own finding |
| `dismissed` (reason required) | `dismissed` | yes | reviewer, check |
| `fixed` | `fixed` | no | agent (`--mark-fixed` only) |
| `unverified` | `unverified` | no | decider |

Severity is set when a finding is raised and never changed by a later
record. Advisory findings get `raised` and nothing else; they are never due
and never counted.

### Planning a round (`--plan`)

A round is full when any R7 trigger holds: no finding records yet (the first
round, or a ledger from before this change), a changed criteria-and-plan
hash, a recorded commit off HEAD's history, `git status --porcelain`
non-empty, no commits since `impl_base`, or a fix diff over 200 changed lines
from the newest recorded ancestor commit (added plus deleted per `--numstat`,
binary files 1 per side). A failing `git diff` also makes the round full. In
a full round every seat is `full` and its decision carries the seat's own
unclosed blocking findings, which `review-packet.sh code` lists for it by id.

Otherwise each blocking finding of the panel is checked against R8's table,
with "touched" computed by today's `touches()` over the fix diff from the
finding's `location.at` (renames off; an insertion touches the ranges on
either side). A location whose commit is gone, or whose diff fails, is
unresolvable and due unless closed. The fix-diff review lands here when the
diff from the newest recorded ancestor commit (the recorded commit with the
most ancestors) to HEAD is non-empty and no record exists at HEAD; after this
panel records at HEAD, later panels see an empty diff.

The existing guard that leaves a recorded blocking round's scope in place at
an unchanged HEAD keeps working with "any unclosed blocking finding" in place
of "any blocking seat" and the marker in place of per-seat revisions for a
`recheck` decision.

### Recording (`--record`) and marking (`--mark-fixed`)

`--record <panel> <session> <round-file>` keeps its checks (scope head, 68;
malformed file, 65) and adds the ones in Decision 2. One run's answers and
new findings, a full round's seat findings and answers, and decider entries
all go through it. `--mark-fixed <panel> <session> <id>...` writes only
`fixed` records. Both validate fully, then write once.

### The gate (`--verdict`)

1. Resolve `panel/open-finding` and every rule id an unclosed blocking finding
   carries (`rf_require_any`); any failure exits 2.
2. Exit 2 when the ledger is unreadable, when a seat of the latest full round
   has no record since it was planned, or when the latest scope's `recheck`
   decision has no newer `reverified.<panel>` marker.
3. Exit 1, printing one finding per unclosed blocking finding (`open`, `fixed`,
   `unverified`): under its rule id when it has one, else `panel/open-finding`,
   message `<panel>/<raiser>: <summary>`, with `path` and `line` when the
   location has them.
4. Exit 0.

A closing record is accepted only if its writer is allowed by the table and
its run is a run of the round it was written in; `--verdict` re-checks the
writer rule when reading, so a ledger edited by hand outside `--record` can't
close a finding with an `agent` record.

### The registry

`panel/open-finding` is added: `summary` "A blocking finding in the panel's
ledger has no closing verdict record", text anchored in
`phase-4a-scrutiny.md`, `check` `panel-scope.sh --verdict`, `level: gate`,
the four panel states as `timing`, guards `pr-create` and `merge`, `withhold:
never`. `panel/blocking-finding` becomes `status: retired`, and every
`RULE_IDS` line and directive that names it moves to the new id.
`rule-registry_test.sh`'s counts change accordingly.

### Retry counting

`panel-retry-budget.sh` is unchanged. The four panel directives tell the
agent to pass the number of findings `--verdict` printed for the round. The
`panel_retries` key stays: koto 0.15.0 stamps a new attempt on every gate
evaluation, including ticks held at a blocked verdict and carried rounds,
exposes no command to read them, and keeps no per-round finding count, so its
counts can't express the progress rule.

### Files

| File | Change |
|---|---|
| `skills/work-on/scripts/panel-scope.sh` | `findings` map, ids, records, due rule, re-verifier decision, `answers`, `run`, marker, `--mark-fixed`, gate over findings, `rf_require_any` |
| `scripts/lib/rule-findings.sh` | `rf_require_any` |
| `scripts/check-rule-registry.sh` | the marker/allowlist rule |
| `references/rule-registry.json` | `panel/open-finding` added, `panel/blocking-finding` retired |
| `scripts/review-packet.sh` | recheck packet lists due findings by id, `fix review` and `review from` lines; code packet lists a seat's unclosed findings |
| `references/review-seat-commissioning.md` | re-check prompt answers by id and reviews the fix diff |
| `skills/work-on/references/phases/phase-4a`..`4d` | round-file shape with `run` and `answers`, `--mark-fixed`, the count to pass |
| `skills/work-on/references/phases/phase-4-implementation.md` | mark findings fixed after committing the fix |
| `skills/work-on/koto-templates/work-on.md` | panel directives and comments name the new rule and count |
| `*_test.sh`, `test_review_shadow.py` | the cases the PRD's criteria name |
| `.github/workflows/check-review-shadow.yml` | path filter gains `panel-scope.sh` |

## Implementation Approach

1. **Registry and resolver.** Add `rf_require_any`, the marker rule in
   `check-rule-registry.sh`, the new entry and the retirement, with their
   tests. Nothing prints the new id yet.
2. **Ledger and record.** The `findings` map, ids, records, seat summaries,
   `run`, `answers`, decider entries, `--mark-fixed`, all-or-nothing writes.
   The gate still reads seats, now derived from findings.
3. **Plan and gate.** The due rule, the re-verifier decision, the fix-diff
   review placement, full-round triggers, the marker, and `--verdict` over
   findings under `panel/open-finding` or the finding's rule. The R17
   fixture lands here.
4. **Packets, prompts, directives.** `review-packet.sh`, the re-check prompt,
   the phase files and the template text, and the shadow workflow's filter.

Steps 2 and 3 change the same script and land together in one pull request;
the split is for review order, not for separate merges.

## Security Considerations

The change stays inside a session's own koto context and the repository's
git history; it adds no network access, no credentials, and no new
dependency.

**Content handled.** Finding summaries, reasons and paths come from reviewer
output, which is model-written text. They are stored in the ledger as JSON
strings through `jq --arg`, never interpolated into a shell command, and the
gate replaces control characters in printed messages as it does today. The
canonical id string is built by jq and piped to `git hash-object --stdin`, so
no summary reaches an argument list. Paths are compared as fixed strings
(`grep -Fx`) and passed to git after `--`.

**Who can close a finding.** The agent writes the round file, so a run id
proves only that the agent named a run of the round, not that the run
happened; this is the same trust today's seat verdicts rest on, stated in the
PRD's known limitations. What the design does remove is the agent's ability
to close a finding through its own channel: `--mark-fixed` writes only
`fixed`, the round file can't name a writer kind, and `--verdict` re-checks
writer rules when reading, so a closing record from the agent's mode never
passes the gate.

**Fail closed.** Every doubt in `--verdict` exits 2, which holds the state.
An unresolvable location is due. A failing diff makes the round full. A
refused write leaves the ledger unchanged.

**Public content.** Nothing the scripts write is committed; the ledger lives
in koto context.

## Consequences

### Positive

- A retry outside a full round costs at most one reviewer run per panel,
  three per retry at the `full` level against seven today, and one on the
  PRD's fixture against three.
- Every finding has an id and a history, so a reader can tell a finding a
  reviewer closed from one that disappeared.
- The gate's pass rests on records with a writer and a run, and the agent's
  own channel can't produce one that closes.
- A decider can report into the same ledger without the gate changing.

### Negative

- `panel-scope.sh` grows: the ledger write, the due rule and the gate all get
  more involved, in bash 3.2 and jq.
- One re-verifier answers for findings raised by seats with different roles,
  so a role-specific nuance in a finding is judged by a reviewer who didn't
  raise it.
- A reworded re-raise makes a new id, and the old one stays due until it is
  answered.
- `rule-findings.sh` gains a dynamic path, a named exception to the rule that
  every printable id sits on a static line.

### Mitigations

- The re-verifier gets each finding's full text, location and raiser, and
  answers only whether that finding still holds.
- Full rounds and re-verification packets list unclosed findings by id, so a
  reviewer answers the old id instead of re-raising it.
- The dynamic path is allowed in one script, checked by
  `check-rule-registry.sh`, and still refuses any id that isn't active.
- The suites drive every new mode on fixtures, on the bash 3.2 leg.

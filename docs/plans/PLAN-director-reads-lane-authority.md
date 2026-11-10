---
schema: plan/v2
status: Active
execution_mode: multi-pr
split_mode_source: intent
split_rationale: |
  Incremental Value. Each step leaves the skill better on its own: Step 1
  leaves every new run naming the session that opened it, shared ownership
  pieces the takeover uses and the cap check will, and one place that runs
  niwa's authority check; when the settled-steps reader already exists,
  Step 1's value is those shared ownership pieces, which the takeover uses
  at once and the cap check uses in Step 2. Step 2 closes the cross-lane cap gap before
  any lane read exists, turning a cross-lane write into a request line with
  no read; Step 3 gives a director a lane read it can call even before the
  skill text points to it; Step 4 makes the skill send readers to niwa,
  address a cap request through the lane read and send it to the lane that
  owns the cap, and route a move it can't address upward; Step 5 measures
  the whole feature on this host. The documents merge ahead of the build so later
  work can plan against them, and each step lands later in its own pull
  request.
tracking_level: none
upstream: docs/designs/DESIGN-director-reads-lane-authority.md
milestone: "Director reads lane authority"
step_count: 5
---

# PLAN: Director reads lane authority

## Status

Active

Amended: a move of another lane's worker cap is no longer refused by the name
of a cap-change authority niwa might grant later. niwa's design for authority
reads (tsukumogami/niwa `docs/designs/DESIGN-authority-read-settlers.md`,
Decision 4) defines no such authority, as a deliberate non-goal, and routes a
cross-lane cap change as a request to the coordinator that owns the cap.
Steps 2, 4 and 5 now build and check that request: the cap check makes no
read and prints a request line for a cross-lane write, and the skill text
reads the owning lane with `lane-read.sh`, addresses the request through the
delivery facts niwa's answer carries, and sends it. Steps 1 and 3 stand
unchanged, and the step count, order and dependencies stay as they were.
One point is left open: the lane read's line carries the lane's `session`
and `instance` but not its `session_name` or `accepts_session_messages`, so
Step 4 addresses by session id and doesn't check `no-delivery`; carrying
them is a change to the design's Decision 3 that this amendment doesn't
make. Step 3 builds and checks what it did before; only its note on the
no-niwa criterion changes, since the cap half of that criterion now sits in
Step 4 and the script no longer looks for niwa.

## Scope Summary

A director reads what a lane it dispatched may do from niwa's authority
answer for that lane, found through niwa's list and lineage and read fresh on
every ask, and a cross-lane move of a lane's active-worker cap is never
written by the mover: it becomes a request to the lane that owns the cap,
addressed through the delivery facts niwa gives for that lane, and that lane
decides it. Both reads go through
`authority-read.sh`, the one reader the settled-steps design
(`docs/designs/DESIGN-coordinator-authority-settled-steps.md`) adds, and the
skill defines no authority of its
own. The design is `docs/designs/DESIGN-director-reads-lane-authority.md`; the
acceptance criteria every step is checked against are in
`docs/prds/PRD-director-reads-lane-authority.md`.

The work can start on niwa 0.40.0: the lane read uses only what that version
answers, and nothing waits on a cap-change authority: niwa defines none, by
design. Its dependencies, none assumed shipped:

- niwa's delivery facts for a lane, which address the cap request (its
  authority-read design's Decision 3): the lane read already carries the
  lane's session id and instance; its `session_name` and
  `accepts_session_messages` are an open point, since carrying them changes
  the design's Decision 3;
- tsukumogami/niwa#422, without which a lane's recorded parent can look
  operator-launched, so "the parent is my dispatch" rests on that fix;
- tying a point's settler to the authority level, work that hasn't started, so
  the lane read reports what niwa answers and nothing past it;
- `authority-read.sh`, which the settled-steps PLAN builds first and which
  isn't built yet; Step 1 adds it to that design's interface if it hasn't
  landed, and the settled-steps work then uses that file rather than adding
  another.

## Decomposition Strategy

Shared pieces first, then one vertical slice per behaviour. Step 1 puts the
pieces both behaviours stand on in place: the reader, the ownership predicates
the takeover and the cap check share, and the opener recorded on every new run.
Step 2 is the cap request end to end, Step 3 the lane read, Step 4 the skill
text that sends readers to both, and Step 5 runs the PRD's whole-feature
checks on this host. Steps 1 and 3 stand unchanged by the amendment, and
the address lookup for a cap request lives in Step 4's skill text, which
already lands after Step 3.

All five steps are detailed now rather than only the first two: the plan
merges ahead of its build, and every step is already settled against the
design, so there's nothing a later outline would leave to decide. None of it
lands with this plan; each step lands later in its own pull request, after
the steps it depends on. Step 4's text is only true once Steps 2 and 3 exist,
which its dependencies keep.

## Steps

### Step 1: the shared reader, the ownership predicates and the opener on every new run are in place

**Goal**: `authority-read.sh` exists with the interface and acceptance the
settled-steps design gives it, finds niwa through the shared lookup, and a
`--session` and `--instance-root` given to it name the session and instance
asked about, overriding `CLAUDE_CODE_SESSION_ID` and the working directory.
`dispatch-common.sh` holds the takeover's ownership predicate (today's rule
over values: driver, coordinator row, caller's id, caller's name), the
cap's strict predicate (the same values plus `opened_by`), the caller-id
check (`^[0-9a-f][0-9a-f-]{7,63}$`, a malformed id counting as none), the
caller-name derivation through `dc_claude_name`, and one niwa lookup (PATH,
else an executable `$NIWA_BIN`). `coordinate-open.sh` calls the takeover's
predicate with the values it reads itself, keeps its own exits, and reads
unknown as not someone else's. Every new run records the Claude session id
that admitted it as `record/meta.opened_by`, in the write that births
`record/meta`: the seed's meta (`core_write_session`, for `state-open.sh` at
`record_open` and its `--carry`), `core_carry`'s meta and
`core_import_meta`'s, with the id passed into the write core from
`state-open.sh`, the opener and `legacy-import/import.sh`. The opener also
writes it on a resume it admits as own or unknown and after an import it
resumes on a koto older than 0.32.0; a caller with no valid id writes
nothing. `record/meta.driver`, `driven_by_another`, the caller-with-no-id
branch, `takeover_check`'s outcomes and `SKILL.md`'s takeover text don't
change. It prepares the PRD's one-reader criterion; Step 4 closes it.

**Acceptance Criteria**:

- [ ] With a stand-in niwa first on PATH and `CLAUDE_CODE_SESSION_ID` set to
  a different id, `authority-read.sh --session <other id> --instance-root
  <other root>` runs one `niwa authority check -C <other root> --session
  <other id> --json` and prints the accepted answer.
- [ ] It prints `skipped`, `timeout`, `failed` or `refused` (exit 3, reason on
  stderr) for no niwa (none on PATH and no executable `NIWA_BIN`), a read past
  `NIWA_LOOKUP_SECONDS`, a non-zero exit, and a document of another schema or
  with a value outside niwa's vocabularies; with niwa only in `NIWA_BIN`, it
  reads.
- [ ] `dispatch-common_test.sh` covers the takeover's predicate over values:
  a driver equal to the caller's id is own and a different one another; with
  no driver, a coordinator row equal to the caller's name is own, a row and a
  name that differ is another, and no row or no name is unknown. It covers
  the strict predicate: a driver equal to the caller's id is own, another
  driver is another, no driver and `opened_by` equal to the caller's id is
  own, no driver and a coordinator row equal to the caller's name is own, no
  driver and `opened_by` another id (with no row, no name, or a row and a
  name that differ) is another, and everything else (no driver and no
  `opened_by`, with no row, no name or a row and a name that differ) is
  unknown. The caller-id check answers none
  for an unset id and for a malformed one, and the niwa lookup finds PATH
  first, then an executable `NIWA_BIN`, else none.
- [ ] `opened_by` is set to the caller's valid id by the seed (`state-open.sh`
  at `record_open`, with and without `--skip-session-checks`), a discipline's
  `--carry`, the opener's carry, the legacy import, a resume the opener
  admits as own or unknown, and an import resumed on a koto older than
  0.32.0; a caller with no id or a malformed one writes none. A failed write
  on a resume, and on an import resumed on a koto older than 0.32.0, prints
  `warning=opener-unrecorded` and the start stands. A resume whose
  `opened_by` already names the caller writes nothing. `state-open.sh` and
  the importer check the caller's id with `dispatch-common.sh`'s check, as
  the opener does.
- [ ] `SKILL.md` lists `warning=opener-unrecorded` beside
  `warning=rules-unrecorded`, saying the opener wasn't recorded and the next
  start writes it, and `references/state-keys.md` lists `opened_by` among
  `record/meta`'s fields with its writers.
- [ ] A resume that runs while another session is writing the record never
  rolls back `record/meta` or produces a duplicate Standing id. The test
  holds the timing with a stand-in koto: the resume reads `record/meta`
  before the other session's `--standing` write marks it pending, and writes
  after that write's last `record/meta` write. Afterwards the other
  session's `written`, `standing_used` and `pending` values are as its own
  write left them and every Standing id is distinct, and the same test fails
  without the chosen mechanism. The mechanism is this step's to choose and
  to name in its pull request.
- [ ] A fresh seed's first `record/meta` write, the pending one, already
  holds `opened_by`, checked by reading that write rather than by cutting
  the seed short.
- [ ] A run opened under id A and then started under id B behaves exactly
  as today: the resume, carry and takeover outcomes are unchanged, and
  `coordinate-outcome_engine_test.sh` case 3 (with
  `CLAUDE_CODE_SESSION_ID` unset, a run no takeover has touched resumes)
  passes unchanged. The takeover's predicate never reads `opened_by`, and a
  takeover read that fails still stops the start with
  `failed=takeover_read`.
- [ ] The comments that say only the opener writes record/meta's extra
  fields (`coordinate-open.sh` above `meta_set`, `state-write-core.sh` above
  `core_write_meta` and where it lists what record/meta's birth writes
  record) name `opened_by` and its writers, and no longer say no one else
  writes while the meta is written.
- [ ] If `authority-read.sh` already exists from the settled-steps work, no
  second reader is added; it's changed if a given `--session` doesn't
  override `CLAUDE_CODE_SESSION_ID` or if it finds niwa by a lookup of its
  own rather than the shared one, and the missing cases above get tests,
  niwa only in `NIWA_BIN` among them. If it doesn't exist, `posture-read.sh`
  and `state-stored-set.sh --rules` move onto it in this step, and a search
  of the executable lines of `skills/coordinate/scripts/*.sh`, test files
  (`*_test.sh`) and comment lines excluded, finds a line that runs niwa's
  `authority check` as a command only in `authority-read.sh`; a message
  string naming the command doesn't count, nor does prose in `SKILL.md`,
  the references and comments.
- [ ] The new `gate_scripts` digest is recorded in `coordinate.compat.json`
  at compat 2 (`scripts/check-template-compat.sh --template
  skills/coordinate/koto-templates/coordinate.md --print`), and
  `check-template-compat.sh --template
  skills/coordinate/koto-templates/coordinate.md --base-table <base table>`
  passes, as the `check-template-compat` job runs it.

**Check**: Run `authority-read_test.sh` (or the reader's test under its
settled-steps name), `dispatch-common_test.sh`, `state-open_test.sh`,
`legacy-import/legacy-import_test.sh` and, under `skills/coordinate/scripts/`,
every engine test that runs
`coordinate-open.sh` with `CLAUDE_CODE_SESSION_ID` set:
`coordinate-open`, `coordinate-takeover`, `coordinate-takeover-load`,
`coordinate-import-takeover`, `coordinate-outcome`,
`coordinate-watch-handover`, `rule-files`, `handover`, `legs-move`,
`importer-call` and `session-fixture`. That list is complete. Run
`coordinate-open-carry-window` too, which covers the carry's `record/meta`
write, and, when this step moves them onto the reader,
`posture-read_test.sh` and `state-stored-set_test.sh`. Then run
`check-template-compat.sh` against the base's table and
`scripts/check-skill.sh --changed coordinate`. Every case passes.

**Dependencies**: None

**Files**: skills/coordinate/scripts/authority-read.sh,
skills/coordinate/scripts/authority-read_test.sh,
skills/coordinate/scripts/dispatch-common.sh,
skills/coordinate/scripts/dispatch-common_test.sh,
skills/coordinate/scripts/coordinate-open.sh,
skills/coordinate/scripts/state-open.sh,
skills/coordinate/scripts/state-open_test.sh,
skills/coordinate/scripts/state-write-core.sh,
skills/coordinate/legacy-import/import.sh,
skills/coordinate/legacy-import/legacy-import_test.sh,
skills/coordinate/scripts/coordinate-open_engine_test.sh,
skills/coordinate/scripts/importer-call_engine_test.sh,
skills/coordinate/scripts/coordinate-import-takeover_engine_test.sh,
skills/coordinate/koto-templates/coordinate.compat.json,
skills/coordinate/SKILL.md,
skills/coordinate/references/state-keys.md, and,
only when the reader hasn't landed from the settled-steps work,
skills/coordinate/scripts/posture-read.sh,
skills/coordinate/scripts/posture-read_test.sh,
skills/coordinate/scripts/state-stored-set.sh and
skills/coordinate/scripts/state-stored-set_test.sh

**Type**: code

**Complexity**: critical

### Step 2: a cross-lane cap write becomes a request to the lane that owns the cap

**Goal**: `state-stored-set.sh --run cap` refuses a caller with no valid id
(`no-session`), feeds the strict predicate from the record it has already
parsed (the driver and `opened_by` from `$WD/parsed.json.meta`, the
coordinator row from the Run section of `$WD/parsed.json`), leaves an own
write untouched with no read, refuses a write it can't show is its own
(`unproven-owner`, naming the cause) with no read, and never writes a
cross-lane record. A cross-lane write makes no read, writes nothing, and
prints one fixed line saying the cap is another lane's and the move goes as
a request to that lane's owner, naming the target session and the cap value
(`requested`). The script makes no niwa call for a cap write and no longer
calls `authority-read.sh` for the mover, so it has no `no-niwa` case. Every
line exits 13, meaning the write wasn't made here, and writes nothing to the
target record. It closes the PRD criteria for the script's half of the cap
request (the line, nothing written, no read of the mover), the own cap at
first start and on a person's word, and the driver-mismatch, latest-opener,
no-writer-id and unproven-owner cases; Step 4 addresses and sends the
request.

**Acceptance Criteria**:

- [ ] A cap write to a run seeded with the caller's id (opened through
  `coordinate-open.sh` and seeded by `state-open.sh` at `record_open`, so its
  `opened_by` is the caller), to a run whose driver is the caller, and to a
  record with no driver and no `opened_by` whose coordinator row equals the
  caller's name from a `DC_CLAUDE_HOME` job fixture, succeeds and the
  stand-in niwa's log shows no call.
- [ ] A cap write to a record driven by another session exits 13 with the
  `requested` line naming the target session and the cap value, the stand-in
  niwa's log shows no call, and the target record's Run section and entries
  are byte-identical afterward.
- [ ] A cap write to a sibling's record as a lane's own run leaves it (no
  driver, `opened_by` the sibling's id, a coordinator row naming the
  sibling), from a writer with an id and a `DC_CLAUDE_HOME` job fixture,
  exits 13 with the `requested` line, never `unproven-owner`, with no call on
  the stand-in's log; the target is byte-identical afterward. The same write
  from a session that isn't the target's live one is stopped by the cap
  check, not by `lib_write_guard`'s exit 10, because the check runs right
  after the record parse and before the guard.
- [ ] With no niwa found (none on PATH and no executable `NIWA_BIN`), a
  cross-lane write still exits 13 with the `requested` line: the script
  doesn't look for niwa.
- [ ] A cap write with `CLAUDE_CODE_SESSION_ID` unset, or set to a malformed
  id, exits 13 with the `no-session` line ("refused: this session has no
  session id (CLAUDE_CODE_SESSION_ID), so it can't show whose record
  <session> is, ..."), whether or not the record has a driver or an opener
  and whether or not it is the writer's own record, and the stand-in's log
  shows no call. The line names no authority.
- [ ] A writer with an id whose write the strict test can't show is its own
  exits 13 with the `unproven-owner` line ("refused: this session can't show
  <session>'s record is its own (<cause>), ..."), one case per cause: a
  driver or `opened_by` that isn't a string (`the record's driver or opener
  couldn't be read`); no driver, no `opened_by`, and no job fixture (`no
  recorded driver or opener, and no session name found for it`); the same with a job
  fixture and no coordinator row (`... and no coordinator row`); and the
  same with a coordinator row naming another session (`... and the
  coordinator row names another session`). The stand-in's log shows no call
  in any of them. A record with no driver, no `opened_by` and no coordinator
  row shows the two readings apart: the takeover resumes it, the cap check
  refuses `unproven-owner`.
- [ ] `state-stored-set_test.sh` and every engine test that writes `--run cap`
  set or unset both `CLAUDE_CODE_SESSION_ID` and `DC_CLAUDE_HOME`
  explicitly, so none passes or fails by the environment it runs in, and
  either seed their run with the caller's id or give an id plus a
  `DC_CLAUDE_HOME` job fixture whose name equals the coordinator row, or
  expect the exit-13 line, and pass.
- [ ] An engine test opens a run through `coordinate-open.sh` with an id and
  seeds it with `state-open.sh` at `record_open`, so its `opened_by` is the
  caller, and writes the cap both before and after the coordinator row;
  both writes succeed with no niwa call. The reconcile text's
  order and `state-handover.sh`'s gap order (`no-cap` before
  `no-coordinator`) are unchanged.
- [ ] The reader's accepted grant vocabulary is unchanged (`merge-pr`,
  `close-issue`, `cut-release`), the cap check compares no grant value and
  calls no niwa command, and no line or file the step changes names a
  cap-change authority or holds a rule for who may move a cap.
- [ ] Every line exits 13 after printing, writes nothing to any record, the
  caller's included, and the script's exit-code list names 13 as a cap write
  not made here. `references/state-keys.md`, beside `--run cap`, gives exit
  13 as "not written here", the request line, and the case words
  `requested`, `no-session` and `unproven-owner`.
- [ ] The new `gate_scripts` digest is recorded in `coordinate.compat.json`
  at compat 2, and `check-template-compat.sh` passes against the base's
  table.

**Check**: Run `state-stored-set_test.sh` with the stand-in niwa, and every
coordinate engine test that writes `--run cap`: `coordinate_1`,
`coordinate_4`, `session-store`, `discipline-session`, `fresh-run-calls`,
`legacy-records`, `handover`, `coordinate-takeover` and
`coordinate-import-takeover`. That list is complete. Then run
`check-template-compat.sh` against the base's table and
`scripts/check-skill.sh --changed coordinate`. Every case above passes.

**Dependencies**: Step 1

**Files**: skills/coordinate/scripts/state-stored-set.sh,
skills/coordinate/scripts/state-stored-set_test.sh,
skills/coordinate/scripts/coordinate_1_engine_test.sh,
skills/coordinate/scripts/coordinate_4_engine_test.sh,
skills/coordinate/scripts/session-store_engine_test.sh,
skills/coordinate/scripts/discipline-session_engine_test.sh,
skills/coordinate/scripts/fresh-run-calls_engine_test.sh,
skills/coordinate/scripts/legacy-records_engine_test.sh,
skills/coordinate/scripts/handover_engine_test.sh,
skills/coordinate/scripts/coordinate-takeover_engine_test.sh,
skills/coordinate/scripts/coordinate-import-takeover_engine_test.sh,
skills/coordinate/references/state-keys.md,
skills/coordinate/koto-templates/coordinate.compat.json

**Type**: code

**Complexity**: critical

### Step 3: a director reads a lane's grant and level from niwa

**Goal**: `lane-read.sh --lane <topic>... [--point <p>]... [--session
<director's koto session>]` runs `niwa list --json` once per question from
the workspace root, with the niwa binary the shared lookup found and under
`dc_with_deadline`, and matches every topic against that one listing through
a new `dispatch-common.sh` helper that takes the listing and a topic and
counts every row `dc_session_matches` accepts; `dc_find_session` stays as it
is. From the one matching row it takes the instance and dispatch id, reads the session id from `niwa lineage show --json`, reads the
lane through `authority-read.sh`, and prints the answer with
`parent_is_mine` (against the director's own row, taken from the same
listing, the one whose `path` is its instance root) and `narrowed_by`, or
`cant_tell` with the reason. With
`--session`, `narrowed_by` is the pause `pause-read.sh` reports under
`covers` for the `unit` of the Holdings row whose Worker is the topic, read
through `dc_record_read`; without it, `[]`; and when that narrowing can't be
read, `null` with `narrowing_unread`. `pause-read.sh` and `dc_record_read`
are called unchanged. It closes the PRD criteria for the lane read reading
nothing the lane wrote, a point's settler, each can't-tell case, a pause row
narrowing, the bound plus a second's slack, and two lanes making two reads.
It covers the bound-read and changed-grant criteria against a stand-in niwa;
Step 5 closes them on this host. It closes the lane-read half of the
no-niwa criterion; Step 4 closes the cap half.

**Acceptance Criteria**:

- [ ] With a stand-in niwa whose list, lineage and authority answers describe a
  lane the director dispatched, `lane-read.sh --lane <topic>` prints one line
  with the lane's grant, level, level source, dispatch and parent exactly as
  the stand-in's authority check prints them, and `parent_is_mine` true; with
  no listing row for the director's own instance, `parent_is_mine` is false.
- [ ] The test's lane instance holds `.niwa/instance.json` and a sentinel
  file the lane "wrote", made unreadable (`chmod 000`); the output is still
  exact and the run succeeds. When the test runs as a user who can read a
  mode-000 file, it reports this case as not checked, as
  `rule-files_engine_test.sh` does, rather than passing it. The stand-in's call log holds only `list`,
  `lineage show` and `authority check` calls, and no messaging command is
  called.
- [ ] With the stand-in's grant changed between two asks, the second line shows
  the new grant.
- [ ] With `--point merge-pr`, the line gives that point's settler as the
  stand-in answers it.
- [ ] Each can't-tell case prints `cant_tell` with its reason and no grant:
  niwa's `not-dispatched` with its reason, `record-unusable`, `no-lane`,
  `ambiguous-lane` (two listing rows match the topic), `bad-lookup`,
  `no-niwa` (none on PATH and no executable `NIWA_BIN`, with no listing
  made), `timeout: niwa list`, `failed: niwa list`, `timeout: niwa lineage
  show`, `failed: niwa lineage show`, and the reader's `timeout`, `failed`
  and `refused`. The PRD's cases map as the design says: a session in
  another instance is `not-dispatched: other-instance`, and a session
  started by hand, with no dispatch, is `no-lane`. A reason taken from niwa
  is cut to one line of at most 200 characters.
- [ ] With `--session` and a pause on the lane's unit in the director's
  record, the line still shows niwa's grant and lists that pause under
  `narrowed_by`; with a go-ahead naming the unit as well, `narrowed_by` is
  `[]`, as `pause-read.sh`'s `through` lets the unit through; without
  `--session`, `narrowed_by` is `[]`. A row whose words name an authority
  niwa's answer doesn't hold adds nothing to the grant.
- [ ] With `--session` and the narrowing unreadable (`dc_record_read`
  returning 2, `state-stored-set.sh --list` failing or exiting 65, or
  `pause-read.sh` exiting 2), the line prints niwa's grant, `narrowed_by:
  null` and `narrowing_unread` naming the read that failed, one case each,
  and never `narrowed_by: []`.
- [ ] With niwa only in `NIWA_BIN` (none on PATH), the listing, the lineage
  reads and the authority reads are all made with it and the lane's answer
  prints.
- [ ] A stand-in that never answers, whether at `list`, `lineage show` or
  `authority check`, gives `cant_tell` within `NIWA_LOOKUP_SECONDS` plus one
  second. That bound covers the niwa calls; `pause-read.sh`'s condition reads
  under `--session` keep board-lib's own deadline.
- [ ] One call with two `--lane` arguments makes exactly one `niwa list`, two
  `niwa lineage show` and two `niwa authority check` calls on the stand-in's
  log, none of them about the director's own session, and `lane-read.sh`
  makes no `authority check` call itself: the search of its executable lines,
  comments excluded, finds no line that runs niwa's `authority check` as a
  command (a message string naming it doesn't count).
- [ ] `dc_find_session`'s existing callers still get the first match, with
  their `dispatch-common_test.sh` cases passing unchanged.
- [ ] The new `gate_scripts` digest is recorded in `coordinate.compat.json`
  at compat 2, and `check-template-compat.sh` passes against the base's
  table.

**Check**: Run `lane-read_test.sh` and `dispatch-common_test.sh` under
`skills/coordinate/scripts/` with the stand-in niwa; every case above passes
and the call counts match. Then run `check-template-compat.sh` against the
base's table, with the new `gate_scripts` digest recorded at compat 2, and
`scripts/check-skill.sh --changed coordinate`.

**Dependencies**: Step 1

**Files**: skills/coordinate/scripts/lane-read.sh,
skills/coordinate/scripts/lane-read_test.sh,
skills/coordinate/scripts/dispatch-common.sh,
skills/coordinate/scripts/dispatch-common_test.sh,
skills/coordinate/koto-templates/coordinate.compat.json

**Type**: code

**Complexity**: testable

### Step 4: the skill sends a reader to niwa for lane allowances and a cap move to the lane that owns the cap

**Goal**: The Bounds and Authority section of `SKILL.md` and the template's
`wait`, `decision_raise` and `decision_verdict` text say a director reads a
lane's allowances with `lane-read.sh`, never from the lane or the brief, say
a lane's cap is that lane's to set and another lane's move is a request to
it, and name no cap-change authority. A session whose cap write on another
lane's record printed a `requested` line reads that lane with `lane-read.sh
--lane <topic>`, addresses the request through the delivery facts niwa's
answer carries (the line's `session` and `instance`; the lane's
`session_name` is an open point), sends the line as a message to that
address with the need behind the move, raises no entry for it, and doesn't
send a second request for the same move while the first is unanswered. A
session whose lane read gave no address (no niwa, niwa's state for the lane,
a lookup reason, or the reader's `skipped`, `timeout`, `failed` or
`refused`), or whose cross-lane write ended in `no-session` or
`unproven-owner`, raises the move once as a decision entry, while a stopped write on its own record raises and
sends nothing; the reconcile text tells a session whose first cap write was
stopped to report the line and stay at reconcile. It closes the PRD criteria
that the skill names no cap-change authority and holds no definition, rule,
level rule or grant table for one, that a requested move is addressed from
niwa's facts, sent and not escalated, that a move that can't be addressed is
escalated once, the cap half of the no-niwa criterion, and the
one-reader criterion for the callers that exist; the finishing-step read's
half of that criterion closes with the settled-steps work.

**Acceptance Criteria**:

- [ ] `SKILL.md` and the template say a director reads what a lane may do with
  `lane-read.sh`, passing its own koto session (`--session
  {{SESSION_NAME}}`), when it's asked, and never from the
  lane's report, the brief or an earlier answer.
- [ ] A reader finds no cap-change authority named: no definition, no rule
  for who may move another lane's cap, no level rule, no grant table, and no
  text that allows or refuses a cap move on the skill's own terms. The text
  says a lane's cap is that lane's to set and another lane's move is a
  request to it, decided by that lane's own rules.
- [ ] The template's `wait` text has a session whose cap write on a record
  other than `{{SESSION_NAME}}` printed a `requested` line run `lane-read.sh
  --lane <topic>` for that lane, by the dispatch topic it knows the lane by,
  and, on a bound line, address the request as the line's `session` at its
  `instance`. It sends the `requested` line as a message to that address,
  through the session's existing message route, saying the need behind the
  move, reports that it sent it, and submits no `event: raise`. The text
  names the lane's `session_name` and a `no-delivery` check as waiting on a
  change to the lane read's answer, not as something it does now. It says the owning lane decides the
  request by its own rules and, if it agrees, sets its own cap; that no reply
  authorizes the session to write the other lane's record; and that while a
  request for the same move is unanswered, a second `requested` line for it
  isn't sent and the session reports the first is still out.
- [ ] The template's `wait` text has a session submit `event: raise` only when
  a cap write's `--session` named a record other than `{{SESSION_NAME}}` and
  either its line isn't `requested` or the lane read gave no address: no
  niwa (`no-niwa`), niwa's state for the lane (`not-dispatched`,
  `record-unusable`), a lookup reason (`no-lane`, `ambiguous-lane`,
  `bad-lookup`, a listing or lineage call that timed out or failed), or the
  reader's `skipped`, `timeout`, `failed` or `refused`; a stopped write on its own record raises and
  sends nothing, whatever its case (`unproven-owner`, `no-session`, or a
  request case, `requested` included, for a session whose run another
  session has resumed since), and the session reports the line. Its
  `decision_raise` text has it run `state-decision.sh --open --source self`
  with a question naming the move (target session and cap value) and quoting
  the line and the reason no request went out; and its `decision_verdict` text has it escalate that entry with
  `--escalate`, writing the recommendation there, the line as `--context`,
  the need behind the move as `--problem`, a `--reason`, `--grounds
  outside-scope`, and an explained `--option` for each option, one of them
  the target lane setting its own cap on a person's word.
- [ ] The template's reconcile text has one line saying that a stopped first
  cap write, whatever its case word, is reported with its line and the run
  stays at reconcile, its `no-cap` gap open.
- [ ] The text defines the same move as the same target session and the same
  cap value, and an open entry as one that is `proposed`,
  `coordinator-verdict` or `escalated` (a `settled` entry isn't open, so a
  stop after the answer raises again), and adds to `wait`'s text that a
  second stop of a move whose entry is still open submits no `event:
  raise` and stays in `wait`. It says both this rule and the no-resend rule
  for a request are the agent's instructions, not engine guards, and doesn't
  lean on the existing `decision_raise` rule, which covers only a parked
  unit.
- [ ] The text says no answer to an entry and no reply to a request
  authorizes the cross-lane write; a person who wants the target's cap
  changed has the target lane set its own cap.
- [ ] A wording test, `cap-request-wording_test.sh`, pins the cap-move text:
  no line of `SKILL.md` or the template names a cap-change authority;
  `SKILL.md` and the template's `wait` text say another lane's cap move is a
  request to the lane that owns it and carry the own-record exception; and
  no line about a cap move carries a grant vocabulary value (`merge-pr`,
  `close-issue`, `cut-release`) or a rule for who may move a cap.
- [ ] Walking a requested move through a scratch record, with a stand-in niwa
  answering the lane read, ends with one lane read of the target, one message
  to `<session> at <instance>` carrying the request line, and no decision
  entry; a second attempt at the same move while the request is unanswered
  sends nothing. Walking a move whose lane read gave no address (the
  stand-in answering `not-dispatched`, say) ends
  with one decision entry whose question carries the line, escalated once
  with a recommendation and `--grounds outside-scope`; a second stop of the
  same move while that entry is open submits no `raise` and adds no entry;
  and an `unproven-owner` line on the session's own record, and a request
  case on its own run after a second session resumed it, each raise and send
  nothing. The escalated entry is then answered through the existing path (an
  `answer` event from `wait` to `decision_answer`, which runs
  `state-decision.sh --answer --outcome <option>`), and the sibling's record,
  read afterward, is byte-identical, its cap unchanged.
- [ ] A search of the executable lines of `skills/coordinate/scripts/*.sh`,
  test files (`*_test.sh`) and comment lines excluded, finds a line that runs
  niwa's `authority check` as a command only in `authority-read.sh`; a
  message string naming the command doesn't count, nor does prose in
  `SKILL.md`, the references and comments.
- [ ] `skills/coordinate/evals/evals.json` gains scenarios for a cross-lane
  cap request sent to its owner, for a cross-lane move that can't be
  addressed, and for a director's lane read, and `scripts/check-skill.sh
  --changed coordinate` passes.

**Check**: Run the wording test and `scripts/check-skill.sh --changed
coordinate`. Then a walkthrough on a scratch record, driving the template by
hand, with a stand-in niwa for the lane read, through a requested move and a
second attempt at it, two stops of the same move whose lane read gave no
address, and a stop on the session's own record,
then answering the escalated entry at `decision_answer` with
`state-decision.sh --answer`, then reading both records: one message for the
request and no entry for it, one entry for the move that couldn't be
addressed, escalated once and answered, none for the own-record stop, the
sibling's record byte-identical with its cap unchanged. Then the one-reader
search, and a read of the changed Bounds and Authority text for any named
cap-change authority or rule about who may move a cap, finding none.

**Dependencies**: Step 2, Step 3

**Files**: skills/coordinate/SKILL.md,
skills/coordinate/koto-templates/coordinate.md,
skills/coordinate/evals/evals.json,
skills/coordinate/scripts/cap-request-wording_test.sh

**Type**: code

**Complexity**: testable

### Step 5: the whole feature is checked on today's niwa

**Goal**: On this host, on niwa 0.40.0 (the record names the version used;
on another version, R14's claim about 0.40.0 stays unmeasured), a director
dispatches a lane by hand
with `niwa dispatch --role <role>`, naming a role the workspace grants at
least one authority (the skill's own lane dispatch gives a lane coordinator
no grant; see Proposed Follow-up). The lane read returns that lane's bound
answer from niwa's records alone, both from the director and from a session
that is neither the lane nor its dispatcher, and a grant changed in the
workspace configuration shows on the next ask. One lane's move of another
lane's cap reaches that lane as a request, addressed from niwa's facts, and
writes nothing. This is where the third-session read of a lane holding grants
is measured; the design doesn't claim it before then. It closes the PRD's
end-to-end criteria for a director and a lane it dispatched.

**Acceptance Criteria**:

- [ ] The director is itself a dispatched session with its own dispatch id
  in `niwa list`, holds at least what the lane's role grants, and dispatches
  the lane with `niwa dispatch --role <role> --parent-from <director
  instance>`. If that can't be set up on this host, the step's record says
  so, both lanes are dispatched the same way from a session with no
  dispatch of its own (so `parent_is_mine` is false), the third-session read
  and the cap request below still run, and the director-side criteria stay open:
  the director's read below, and the director's half of the changed-grant
  criterion. The PRD's first two acceptance criteria (the director's read of
  the lane, and the changed grant seen from the director) stay unmet until
  they close.
- [ ] From the dispatching director, `lane-read.sh --session <director's koto
  session>` (its `{{SESSION_NAME}}`) returns the lane's bound answer with `parent_is_mine` true, the
  lane found from niwa's records alone and sent no message.
- [ ] From a session that is neither the lane nor its dispatcher, on niwa
  0.40.0, `lane-read.sh --point merge-pr` with no `--session` returns the
  lane's bound answer and its `merge-pr` settler, with its instance and
  session id found from `niwa list` and `niwa lineage show` alone, and
  `narrowed_by` `[]`.
- [ ] The lane's role grants at least one authority and the answer lists it;
  after an authority is removed from the lane's role in the workspace
  configuration, the next ask from each reader shows the grant without it,
  without restarting the director or the lane.
- [ ] The director dispatches a second lane the same way. Both lanes run
  `/shirabe:coordinate` with their own records. From the first lane, a move
  of the second lane's cap made from its `wait` as the skill directs isn't
  written: the first lane gets the `requested` line, reads the second lane
  with `lane-read.sh`, and sends the request as a message to the second
  lane's `session` at its `instance`; the second lane receives the request,
  and its cap in force and record entries are unchanged until it decides.
  Whether it agrees is its own call; if it sets its own cap, that write goes
  through its own-write path with no authority read. If the request can't
  reach the second lane by session id, the record says so, since that's the
  open point the lane's `session_name` and `accepts_session_messages` would
  settle.
- [ ] The run's record lands in the design's "What a third session can read
  today" section, replacing its unmeasured sentence: the niwa version, each
  command with host paths replaced by placeholders, and the result lines it
  read (state, grant, level, level source and the `merge-pr` settler), never
  a full niwa answer, which carries host paths.

**Check**: A walkthrough on this host with two lanes dispatched by hand, the
first holding a grant: the director's read shows the grant with
`parent_is_mine` true, the third session's read shows the same grant, the
grant with an authority removed shows on the second ask from each, the
third session's `--point merge-pr` read gives the settler, and the
first lane's move of the second lane's cap isn't written and reaches the
second lane as a request; the design's updated
section shows each command and its result lines.

**Dependencies**: Step 4

**Files**: docs/designs/DESIGN-director-reads-lane-authority.md

**Type**: task

**Complexity**: testable

## Proposed Follow-up

Not filed.

- **The skill holds a grant rule for lane coordinators.** The dispatch text in
  `skills/coordinate/koto-templates/coordinate.md` (around line 2833) says "A
  lane coordinator gets none", which decides inside the skill what grant a
  dispatched lane coordinator holds. That is the kind of allowance this
  feature says belongs to the workspace. Handing a lane less than its role
  is a dispatcher's restriction (narrowing, never widening), not an
  authority definition, so the sentence doesn't contradict R11 as it stands;
  it does keep Step 5 from using the skill's own dispatch. A follow-up would
  have the skill dispatch a lane coordinator with whatever the workspace's
  role grants it and drop the sentence.
- **Measure the third-session read of a lane holding grants before Step 3.**
  The design's measurement covered a lane whose grant was empty. A follow-up
  would run that read on this host against a lane whose role grants at least
  one authority, and change the grant between two reads, so Step 3 is built
  against a measured answer rather than waiting for Step 5 to find out.

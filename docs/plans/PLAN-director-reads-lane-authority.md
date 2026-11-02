---
schema: plan/v2
status: Active
execution_mode: multi-pr
split_mode_source: intent
split_rationale: |
  Incremental Value. Each step leaves the skill better on its own: Step 1
  leaves every new run naming its driver, one ownership test the takeover
  uses and the cap check will, and one place that runs niwa's authority
  check; when the settled-steps reader already exists, Step 1's value is
  that single shared ownership test, which the takeover uses at once and
  the cap check uses in Step 2. Step 2 closes the cross-lane cap gap before
  any lane read exists; Step 3 gives a director a lane read it can call even
  before the skill text points to it; Step 4 makes the skill send readers
  to niwa and routes a refused move upward; Step 5 measures the whole
  feature on this host. The documents merge ahead of the build so later
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

## Scope Summary

A director reads what a lane it dispatched may do from niwa's authority
answer for that lane, found through niwa's list and lineage and read fresh on
every ask, and a cross-lane move of a lane's active-worker cap is refused by
the name of an authority niwa grants. Both reads go through
`authority-read.sh`, the one reader the settled-steps design
(`docs/designs/DESIGN-coordinator-authority-settled-steps.md`) adds, and the
skill defines no authority of its
own. The design is `docs/designs/DESIGN-director-reads-lane-authority.md`; the
acceptance criteria every step is checked against are in
`docs/prds/PRD-director-reads-lane-authority.md`.

The work can start on niwa 0.40.0: the lane read uses only what that version
answers, and the cap check refuses every cross-lane move until niwa grants a
cap-change authority. Its dependencies, none assumed shipped:

- the cap-change authority itself, which the workspace authority work's design,
  in progress, will name and grant; until then every cross-lane move is
  refused, which is the intended state;
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
pieces both behaviours stand on in place: the reader, the ownership predicate
the takeover and the cap check share, and a driver recorded on every new run.
Step 2 is the cap refusal end to end, Step 3 the lane read, Step 4 the skill
text that sends readers to both, and Step 5 runs the PRD's whole-feature
checks on this host.

All five steps are detailed now rather than only the first two: the plan
merges ahead of its build, and every step is already settled against the
design, so there's nothing a later outline would leave to decide. None of it
lands with this plan; each step lands later in its own pull request, after
the steps it depends on. Step 4's text is only true once Steps 2 and 3 exist,
which its dependencies keep.

## Steps

### Step 1: the shared reader, the ownership predicate and a driver on every new run are in place

**Goal**: `authority-read.sh` exists with the interface and acceptance the
settled-steps design gives it, and a `--session` and `--instance-root` given
to it name the session and instance asked about, overriding
`CLAUDE_CODE_SESSION_ID` and the working directory. `dispatch-common.sh`
holds the ownership predicate (given a record's driver, its coordinator row,
the caller's id and the caller's name, it answers own, another or unknown),
the caller-id check (`^[0-9a-f][0-9a-f-]{7,63}$`, a malformed id counting as
none), the caller-name derivation through `dc_claude_name`, and one niwa
lookup (PATH, else an executable `$NIWA_BIN`). `coordinate-open.sh` calls the
predicate with the values it reads itself, keeps its own exits, and reads
unknown as not someone else's. Every fresh start with a valid id records the
caller as the run's `record/meta.driver`: the opener after its carry and a
fresh start's legacy import, and `state-open.sh`'s seed at `record_open` and
its `--carry`. The opener's caller-with-no-id branch reads a touched run as
one whose `record/meta.takeover` is set or which continues a predecessor. It
prepares the PRD's one-reader criterion; Step 4 closes it.

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
- [ ] `dispatch-common_test.sh` covers the predicate over values: a driver
  equal to the caller's id is own and a different one another; with no
  driver, a coordinator row equal to the caller's name is own, a row and a
  name that differ is another, and no row or no name is unknown. The
  caller-id check answers none for an unset id and for a malformed one, and
  the niwa lookup finds PATH first, then an executable `NIWA_BIN`, else
  none.
- [ ] A fresh start with a valid id records it as the run's driver for a new
  run, a carry and a discipline's carried rotation; one with no id or a
  malformed id records none.
- [ ] A fresh run with a driver and no takeover still resumes for a caller
  with no id, as it does today; a run whose `record/meta.takeover` is set, or
  which continues a predecessor, still refuses `taken-over` for that caller.
- [ ] The takeover's engine tests (`coordinate-open_engine_test.sh`,
  `coordinate-takeover_engine_test.sh`,
  `coordinate-takeover-load_engine_test.sh`,
  `coordinate-import-takeover_engine_test.sh`) pass, and a takeover read
  that fails still stops the start with `failed=takeover_read`.
- [ ] If `authority-read.sh` already exists from the settled-steps work, no
  second reader is added; it's changed if a given `--session` doesn't
  override `CLAUDE_CODE_SESSION_ID`, and the missing cases above get tests.
  If it doesn't exist, `posture-read.sh` and `state-stored-set.sh --rules`
  move onto it in this step, and a search of the executable lines of
  `skills/coordinate/scripts/*.sh`, test files (`*_test.sh`) and comment
  lines excluded, finds an `authority check` call only in
  `authority-read.sh`; prose in `SKILL.md`, the references and comments
  doesn't count.

**Check**: Run `authority-read_test.sh` (or the reader's test under its
settled-steps name), `dispatch-common_test.sh`, `state-open_test.sh` and the
four takeover engine tests above under `skills/coordinate/scripts/`, and,
when this step moves them onto the reader, `posture-read_test.sh` and
`state-stored-set_test.sh`; every case passes.

**Dependencies**: None

**Files**: skills/coordinate/scripts/authority-read.sh,
skills/coordinate/scripts/authority-read_test.sh,
skills/coordinate/scripts/dispatch-common.sh,
skills/coordinate/scripts/dispatch-common_test.sh,
skills/coordinate/scripts/coordinate-open.sh,
skills/coordinate/scripts/state-open.sh,
skills/coordinate/scripts/state-open_test.sh,
skills/coordinate/scripts/coordinate-open_engine_test.sh,
skills/coordinate/scripts/coordinate-takeover_engine_test.sh,
skills/coordinate/scripts/coordinate-takeover-load_engine_test.sh,
skills/coordinate/scripts/coordinate-import-takeover_engine_test.sh, and,
only when the reader hasn't landed from the settled-steps work,
skills/coordinate/scripts/posture-read.sh,
skills/coordinate/scripts/posture-read_test.sh,
skills/coordinate/scripts/state-stored-set.sh and
skills/coordinate/scripts/state-stored-set_test.sh

**Type**: code

**Complexity**: critical

### Step 2: a cross-lane cap write is refused by the cap-change authority's name

**Goal**: `state-stored-set.sh --run cap` refuses a caller with no valid id
(`no-session`), feeds the shared predicate from the record it has already
parsed (the driver from `$WD/parsed.json.meta`, the coordinator row from the
Run section of `$WD/parsed.json`), leaves an own write untouched with no read,
refuses a write it can't show is its own (`unproven-owner`) with no read, and
for a cross-lane write refuses `no-niwa` or reads the mover's authority
through `authority-read.sh` and refuses with the fixed refusal and its case
word. Every refusal exits 13 and writes nothing to the target record. It
closes the PRD criteria for the cap refusal, the failed, timed-out or
`not-dispatched` read, the own cap at first start and on a person's word, the
driver-mismatch, no-writer-id and unproven-owner cases, and no niwa.

**Acceptance Criteria**:

- [ ] A cap write to a run opened through `coordinate-open.sh` with the
  caller's id (so its driver is the caller), and to a record with no driver
  whose coordinator row equals the caller's name from a `DC_CLAUDE_HOME` job
  fixture, succeeds and the stand-in niwa's log shows no call.
- [ ] A cap write to a record driven by another session, with the stand-in
  answering `bound` and an empty grant, exits 13 with the `not-held`
  refusal naming the cap-change authority as one niwa grants, and the target
  record's Run section and entries are byte-identical afterward.
- [ ] The same write with the read failing, timing out or answering
  `not-dispatched` exits 13 with the couldn't-be-read refusal and its case
  word; with no niwa found (none on PATH and no executable `NIWA_BIN`) it
  exits 13 with the case word `no-niwa` and the reader isn't called, and with
  niwa only in `NIWA_BIN` the read is made. The target is unchanged in every
  case.
- [ ] A cap write with `CLAUDE_CODE_SESSION_ID` unset, or set to a malformed
  id, exits 13 with the couldn't-be-read refusal and the case word
  `no-session`, whether or not the record has a driver and whether or not
  it is the writer's own record, and the stand-in's log shows no call.
- [ ] A writer with an id, on a record with no driver whose coordinator row
  doesn't match a name found for it (no job fixture, or no coordinator row),
  exits 13 with the `unproven-owner` line ("refused: this session can't show
  <session>'s record is its own ..."), and so does a write to a record whose
  `record/meta` driver can't be read (not a string); the stand-in's log
  shows no call in either case. A record with no driver and no coordinator
  row shows the two readings apart: the takeover resumes it, the cap check
  refuses `unproven-owner`.
- [ ] `state-stored-set_test.sh` and every engine test that writes `--run cap`
  give the caller a driver (the run opened with an id through the opener) or
  an id plus a `DC_CLAUDE_HOME` job fixture whose name equals the coordinator
  row, or expect the refusal, and pass.
- [ ] An engine test opens a run through `coordinate-open.sh` with an id, so
  the driver is the opener's, and writes the cap both before and after the
  coordinator row; both writes succeed with no niwa call. The reconcile text's
  order and `state-handover.sh`'s gap order (`no-cap` before
  `no-coordinator`) are unchanged.
- [ ] The reader's accepted grant vocabulary is unchanged (`merge-pr`,
  `close-issue`, `cut-release`), the bound branch compares no grant value,
  and the changed files hold no rule for who holds the cap-change authority.
- [ ] Every refusal exits 13 after printing its line, writes nothing to any
  record, the caller's included, and the script's exit-code list names 13 as
  the cap-move refusal.

**Check**: Run `state-stored-set_test.sh` with the stand-in niwa, and every
coordinate engine test that writes `--run cap`: `coordinate_1`,
`coordinate_4`, `session-store`, `discipline-session`, `fresh-run-calls`,
`legacy-records`, `handover`, `coordinate-takeover` and
`coordinate-import-takeover`. That list is complete. Every case above passes.

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
skills/coordinate/scripts/coordinate-import-takeover_engine_test.sh

**Type**: code

**Complexity**: critical

### Step 3: a director reads a lane's grant and level from niwa

**Goal**: `lane-read.sh --lane <topic>... [--point <p>]... [--session
<director's koto session>]` runs `niwa list --json` once from the workspace
root, through `dc_find_session` extended with a mode its existing callers
don't use that counts every row `dc_session_matches` accepts and runs under
`dc_with_deadline`. From the one matching row it takes the instance and
dispatch id, reads the session id from `niwa lineage show --json`, reads the
lane through `authority-read.sh`, and prints the answer with
`parent_is_mine` (against the director's own row, the one whose `path` is its
instance root) and `narrowed_by`, or `cant_tell` with the reason. With
`--session`, `narrowed_by` is the pause `pause-read.sh` reports under
`covers` for the `unit` of the Holdings row whose Worker is the topic, read
through `dc_record_read`; without it, `[]`. `pause-read.sh` and
`dc_record_read` are called unchanged. It closes the PRD criteria for the
bound read, the lane read reading nothing the lane wrote, the changed grant
on the next ask, a point's settler, each can't-tell case, a pause row
narrowing, the bound plus a second's slack, and two lanes making two reads.

**Acceptance Criteria**:

- [ ] With a stand-in niwa whose list, lineage and authority answers describe a
  lane the director dispatched, `lane-read.sh --lane <topic>` prints one line
  with the lane's grant, level, level source, dispatch and parent exactly as
  the stand-in's authority check prints them, and `parent_is_mine` true; with
  no listing row for the director's own instance, `parent_is_mine` is false.
- [ ] The test's lane instance holds `.niwa/instance.json` and a sentinel
  file the lane "wrote", made unreadable (`chmod 000`); the output is still
  exact and the run succeeds. The stand-in's call log holds only `list`,
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
- [ ] A stand-in that never answers, whether at `list`, `lineage show` or
  `authority check`, gives `cant_tell` within `NIWA_LOOKUP_SECONDS` plus one
  second.
- [ ] One call with two `--lane` arguments makes exactly one `niwa list`, two
  `niwa lineage show` and two `niwa authority check` calls on the stand-in's
  log, none of them about the director's own session, and `lane-read.sh`
  makes no `authority check` call itself: the search of its executable lines,
  comments excluded, finds none.
- [ ] `dc_find_session`'s existing callers still get the first match, with
  their `dispatch-common_test.sh` cases passing unchanged.

**Check**: Run `lane-read_test.sh` and `dispatch-common_test.sh` under
`skills/coordinate/scripts/` with the stand-in niwa; every case above passes
and the call counts match.

**Dependencies**: Step 1

**Files**: skills/coordinate/scripts/lane-read.sh,
skills/coordinate/scripts/lane-read_test.sh,
skills/coordinate/scripts/dispatch-common.sh,
skills/coordinate/scripts/dispatch-common_test.sh

**Type**: code

**Complexity**: testable

### Step 4: the skill sends a reader to niwa for lane allowances and the cap rule

**Goal**: The Bounds and Authority section of `SKILL.md` and the template's
`wait`, `decision_raise` and `decision_verdict` text say a director reads a
lane's allowances with `lane-read.sh`, never from the lane or the brief, name
the cap-change authority only as something niwa grants, and have a session
whose cap write on another lane's record was refused raise the move once as a
decision entry, while a refusal on its own record raises nothing. It closes
the PRD criteria that the skill holds no definition, rule, level rule or grant
table for the authority and that a refused move is escalated once, and the
one-reader criterion for the callers that exist; the finishing-step read's
half of that criterion closes with the settled-steps work.

**Acceptance Criteria**:

- [ ] `SKILL.md` and the template say a director reads what a lane may do with
  `lane-read.sh`, passing its own session, when it's asked, and never from the
  lane's report, the brief or an earlier answer.
- [ ] A reader finds the cap-change authority named only as something niwa
  grants: no definition, no rule for who holds it, no level rule, no grant
  table, and no text that grants or withholds it on the skill's own terms.
- [ ] The template's `wait` text has a session submit `event: raise` only when
  a refused cap write's `--session` named a record other than
  `{{SESSION_NAME}}`; a refusal on its own record (`unproven-owner`,
  `no-session`) raises nothing and the session reports the refusal line. Its
  `decision_raise` text has it run `state-decision.sh --open --source self`
  with a question naming the move (target session and cap value) and quoting
  the refusal line; and its `decision_verdict` text has it escalate that
  entry with `--escalate`, writing the recommendation there, the refusal line
  as `--context`, the need behind the move as `--problem`, a `--reason`,
  `--grounds outside-scope`, and an explained `--option` for each option.
- [ ] The text defines the same move as the same target session and the same
  cap value, and adds to `wait`'s text that a second refusal of a move whose
  entry is still open submits no `event: raise` and stays in `wait`. It says
  this is the agent's instruction, not an engine guard, and doesn't lean on
  the existing `decision_raise` rule, which covers only a parked unit.
- [ ] The text says the refusal stands and no answer to the entry authorizes
  the cross-lane write; a person who wants the target's cap changed has the
  target lane set its own cap.
- [ ] A wording test pins the cap-change text: `SKILL.md` and the template's
  `wait` text carry the phrase "the cap-change authority, which niwa grants"
  and the own-record exception, and no line naming the cap-change authority
  carries a grant vocabulary value (`merge-pr`, `close-issue`,
  `cut-release`) or a rule for who holds it.
- [ ] Walking a refused move through a scratch record ends with one decision
  entry whose question carries the refusal line, escalated once with a
  recommendation and `--grounds outside-scope`; a second refusal of the same
  move while that entry is open submits no `raise` and adds no entry; and a
  `unproven-owner` refusal on the session's own record raises no entry. The
  escalated entry is then answered through the existing path (an `answer`
  event from `wait` to `decision_answer`, which runs `state-decision.sh
  --answer --outcome <option>`), and the sibling's record, read afterward, is
  byte-identical, its cap unchanged.
- [ ] A search of the executable lines of `skills/coordinate/scripts/*.sh`,
  test files (`*_test.sh`) and comment lines excluded, finds an `authority
  check` call only in `authority-read.sh`; prose in `SKILL.md`, the
  references and comments doesn't count.

**Check**: Run the wording test. Then a walkthrough on a scratch record,
driving the template by hand through two refusals of the same move and a
refusal on the session's own record, then answering the escalated entry at
`decision_answer` with `state-decision.sh --answer`, then reading both
records: one entry, escalated once and answered, none for the own-record
refusal, the sibling's record byte-identical with its cap unchanged. Then the
one-reader search, and a read of the changed Bounds and Authority text for any
rule about who holds the cap-change authority, finding none.

**Dependencies**: Step 2, Step 3

**Files**: skills/coordinate/SKILL.md,
skills/coordinate/koto-templates/coordinate.md,
skills/coordinate/scripts/cap-authority-wording_test.sh

**Type**: code

**Complexity**: testable

### Step 5: the whole feature is checked on today's niwa

**Goal**: On this host, on niwa 0.40.0, a director dispatches a lane by hand
with `niwa dispatch --role <role>`, naming a role the workspace grants at
least one authority (the skill's own lane dispatch gives a lane coordinator
no grant; see Proposed Follow-up). The lane read returns that lane's bound
answer from niwa's records alone, both from the director and from a session
that is neither the lane nor its dispatcher, and a grant changed in the
workspace configuration shows on the next ask. This is where the
third-session read of a lane holding grants is measured; the design doesn't
claim it before then. It closes the PRD's end-to-end criteria for a director
and a lane it dispatched.

**Acceptance Criteria**:

- [ ] The director is itself a dispatched session with its own dispatch id
  in `niwa list`, holds at least what the lane's role grants, and dispatches
  the lane with `niwa dispatch --role <role> --parent-from <director
  instance>`. If that can't be set up on this host, the step's record says
  so and the director-side criteria stay open: the director's read below,
  and the director's half of the changed-grant criterion. The milestone's
  first Evidence clause stays unmet until they close.
- [ ] From the dispatching director, `lane-read.sh --session <director's
  session>` returns the lane's bound answer with `parent_is_mine` true, the
  lane found from niwa's records alone and sent no message.
- [ ] From a session that is neither the lane nor its dispatcher, on niwa
  0.40.0, `lane-read.sh` with no `--session` returns the lane's bound answer,
  with its instance and session id found from `niwa list` and `niwa lineage
  show` alone, and `narrowed_by` `[]`.
- [ ] The lane's role grants at least one authority and the answer lists it;
  after an authority is removed from the lane's role in the workspace
  configuration, the next ask from each reader shows the grant without it,
  without restarting the director or the lane.
- [ ] The director dispatches a second lane the same way, running
  `/shirabe:coordinate` with its own record. From the first lane, which
  lacks the cap-change authority, a move of that sibling's cap through the
  skill is refused naming the cap-change authority as one niwa grants and
  the session lacks, and the sibling's cap in force and record entries are
  unchanged.
- [ ] The run's record lands in the design's "What a third session can read
  today" section, replacing its unmeasured sentence: the niwa version, each
  command with host paths replaced by placeholders, and the result lines it
  read (state, grant, level, level source and the `merge-pr` settler), never
  a full niwa answer, which carries host paths.

**Check**: A walkthrough on this host with two lanes dispatched by hand, the
first holding a grant: the director's read shows the grant with
`parent_is_mine` true, the third session's read shows the same grant, the
grant with an authority removed shows on the second ask from each, and the
first lane's move of the second lane's cap is refused; the design's updated
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

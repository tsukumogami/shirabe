---
schema: plan/v2
status: Active
execution_mode: multi-pr
split_mode_source: intent
split_rationale: |
  Incremental Value. Each step leaves the skill better on its own: Step 1
  leaves one place that runs niwa's authority check and one ownership test
  instead of two copies; Step 2 closes the cross-lane cap gap before any
  lane read exists; Step 3 gives a director a lane read it can call even
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

Walking skeleton. Step 1 puts the shared pieces in place: the reader and the
ownership test the takeover already applies, moved where the cap check can
call it. Step 2 closes the cap gap end to end, Step 3 adds the lane read,
Step 4 the skill text, and Step 5 runs the PRD's whole-feature checks.

None of it lands with this plan: the plan merges ahead of its build, and each
step lands later in its own pull request, after the steps it depends on. Step
4's text is only true once Steps 2 and 3 exist, which its dependencies keep.

## Steps

### Step 1: the shared reader and the ownership test are in place

**Goal**: `authority-read.sh` exists with the interface and acceptance the
settled-steps design gives it, answers about a session other than the
caller's when given `--session` and `--instance-root`, and the takeover's
ownership test (`driven_by_another`, permissive) lives in `dispatch-common.sh`
with `coordinate-open.sh` calling it, beside a new strict test that answers
own only on a positive match (the driver is the caller, or no driver and the
coordinator row equals a name found for the caller). It closes the PRD criterion One reader for the two new callers.

**Acceptance Criteria**:

- [ ] With a stand-in niwa first on PATH, `authority-read.sh --session <other
  id> --instance-root <other root>` runs one `niwa authority check -C <other
  root> --session <other id> --json` and prints the accepted answer.
- [ ] It prints `skipped`, `timeout`, `failed` or `refused` (exit 3, reason on
  stderr) for no niwa, a read past `NIWA_LOOKUP_SECONDS`, a non-zero exit, and
  a document of another schema or with a value outside niwa's vocabularies.
- [ ] `coordinate-open.sh`'s takeover tests pass unchanged after the ownership
  test moves into `dispatch-common.sh`.
- [ ] If `authority-read.sh` already exists from the settled-steps work, no
  second reader is added and only the missing cases above get tests. If it
  doesn't, `posture-read.sh` and `state-stored-set.sh --rules` move onto it in
  this step, and a search for `niwa authority check` under
  `skills/coordinate/` finds only the reader.

**Check**: Run the reader's test and `coordinate-open.sh`'s existing tests
under `skills/coordinate/scripts/`, and, when this step moves them onto the
reader, `posture-read.sh`'s and `state-stored-set.sh`'s existing tests; every
case passes.

**Dependencies**: None

**Files**: skills/coordinate/scripts/authority-read.sh,
skills/coordinate/scripts/dispatch-common.sh,
skills/coordinate/scripts/coordinate-open.sh, and, only when the reader
hasn't landed from the settled-steps work,
skills/coordinate/scripts/posture-read.sh and
skills/coordinate/scripts/state-stored-set.sh

**Type**: code

**Complexity**: testable

### Step 2: a cross-lane cap write is refused by the cap-change authority's name

**Goal**: `state-stored-set.sh --run cap` sorts each write into own or
cross-lane with the shared ownership test, leaves an own write untouched with
no read, and for a cross-lane write reads the mover's authority through
`authority-read.sh` and refuses with the fixed refusal and its case word,
writing nothing to the target record. It closes the PRD criteria for the cap
refusal, the failed, timed-out or `not-dispatched` read, the own cap at first
start and on a person's word, the driver-mismatch and no-writer-id cases, and
no niwa on the path.

**Acceptance Criteria**:

- [ ] A cap write to a record whose driver is the caller, or with no driver
  and a coordinator row naming the caller, succeeds and the stand-in niwa's
  log shows no call.
- [ ] A cap write to a record driven by another session, with the stand-in
  answering `bound` and an empty grant, exits non-zero with the `not-held`
  refusal naming the cap-change authority as one niwa grants, and the target
  record's Run section and entries are byte-identical afterward.
- [ ] The same write with the read failing, timing out or answering
  `not-dispatched` is refused with the couldn't-be-read refusal and its case
  word; with no niwa on PATH it is refused with the case word `no-niwa` and
  the reader isn't called. The target is unchanged in every case.
- [ ] A cap write with `CLAUDE_CODE_SESSION_ID` unset is refused with the
  couldn't-be-read refusal and the case word `no-session`, whether or not the
  record has a driver and whether or not it is the writer's own record, and
  the stand-in's log shows no call. A writer with an id, on a record with no
  driver, whose session name can't be found is refused as cross-lane. The
  cap check calls the strict own test, never `driven_by_another`, and a case
  shows the two disagree on a record with no driver and no coordinator row.
  A refused write to the writer's own record raises no decision entry.
- [ ] Every existing test that writes `--run cap` without a driver or a
  findable name for the caller (`state-stored-set_test.sh`, and the engine
  tests that write `--run cap`) is changed to give the caller one or to
  expect the refusal, and passes.
- [ ] A coordinator's first-start cap write, run through the template's own
  order, succeeds with no read.
- [ ] A search of the changed files finds no literal naming the cap-change
  authority's token, and no rule for who holds it.
- [ ] Every refusal exits non-zero after printing its line, and writes nothing
  to any record, the caller's included.

**Check**: Run `state-stored-set_test.sh` with the stand-in niwa, and the
coordinate engine test that writes `--run cap` (`coordinate_1`,
`coordinate_4`, `session-store`, `discipline-session`, `fresh-run-calls`,
`legacy-records`, `handover`, `coordinate-takeover` and
`coordinate-import-takeover` among them); every case above passes.

**Dependencies**: Step 1

**Files**: skills/coordinate/scripts/state-stored-set.sh,
skills/coordinate/scripts/state-stored-set_test.sh,
skills/coordinate/koto-templates/coordinate.md, the engine tests above where
they set a cap with no session id, and
skills/coordinate/scripts/state-handover.sh if its gap order has to change
for the first-start cap write

**Type**: code

**Complexity**: critical

### Step 3: a director reads a lane's grant and level from niwa

**Goal**: `lane-read.sh --lane <topic>... [--point <p>]...` finds each lane's
instance and dispatch id in `niwa list --json` and its session id in
`niwa lineage show --json`, reads it through `authority-read.sh`, and prints
the answer with `parent_is_mine` and `narrowed_by`, or `cant_tell` with the
reason. It closes the PRD criteria for the bound read, the changed grant on
the next ask, a point's settler, each can't-tell case, a pause row narrowing,
the bound plus a second's slack, and two lanes making two reads.

**Acceptance Criteria**:

- [ ] With a stand-in niwa whose list, lineage and authority answers describe a
  lane the director dispatched, `lane-read.sh --lane <topic>` prints one line
  with the lane's grant, level, level source, dispatch and parent exactly as
  the stand-in's authority check prints them, and `parent_is_mine` true; the
  stand-in's log shows no message to the lane and no read of a file it wrote.
- [ ] With the stand-in's grant changed between two asks, the second line shows
  the new grant.
- [ ] With `--point merge-pr`, the line gives that point's settler as the
  stand-in answers it.
- [ ] Each can't-tell case prints `cant_tell` with its reason and no grant:
  niwa's `not-dispatched` with its reason, `record-unusable`, `no-lane`,
  `ambiguous-lane`, `bad-lookup`, and the reader's `skipped` (naming the
  missing niwa), `timeout`, `failed` and `refused`. A reason taken from niwa is
  cut to one line of at most 200 characters.
- [ ] With a pause row on the lane in the director's record, the line still
  shows niwa's grant and lists the row under `narrowed_by`; a row whose words
  name an authority niwa's answer doesn't hold adds nothing to the grant.
- [ ] A stand-in that never answers gives `cant_tell` within
  `NIWA_LOOKUP_SECONDS` plus one second.
- [ ] One call with two `--lane` arguments makes exactly two `niwa authority
  check` calls on the stand-in's log, none of them about the director's own
  session, and `lane-read.sh` itself contains no `niwa authority check`.

**Check**: Run `lane-read.sh`'s new test under `skills/coordinate/scripts/`
with the stand-in niwa; every case above passes and the call counts match.

**Dependencies**: Step 1

**Files**: skills/coordinate/scripts/lane-read.sh,
skills/coordinate/scripts/dispatch-common.sh

**Type**: code

**Complexity**: testable

### Step 4: the skill sends a reader to niwa for lane allowances and the cap rule

**Goal**: The Bounds and Authority text in `SKILL.md` and the template says a
director reads a lane's allowances with `lane-read.sh`, never from the lane or
the brief, names the cap-change authority only as something niwa grants, and
has a session whose cross-lane cap move was refused raise the move once as a
decision entry. It closes the PRD criteria that the skill holds no definition,
rule, level rule or grant table for the authority, that a refused move is
escalated once, and that a search for `niwa authority check` under
`skills/coordinate/` finds only the reader.

**Acceptance Criteria**:

- [ ] `SKILL.md` and the template say a director reads what a lane may do with
  `lane-read.sh` when it's asked, and never from the lane's report, the brief
  or an earlier answer.
- [ ] A reader finds the cap-change authority named only as something niwa
  grants: no definition, no rule for who holds it, no level rule, no grant
  table, and no text that grants or withholds it on the skill's own terms.
- [ ] The template's `wait` text has a session whose cross-lane cap write was
  refused submit `event: raise`; its `decision_raise` text has it run
  `state-decision.sh --open --source self` with a question naming the move
  (target session and cap value) and quoting the refusal line; and its
  `decision_verdict` text has it escalate that entry with `--escalate`,
  writing the recommendation there, the refusal line as `--context`, the
  need behind the move as `--problem`, a `--reason`, `--grounds
  outside-scope`, and an explained `--option` for each option.
- [ ] The text defines the same move as the same target session and the same
  cap value, and adds to `wait`'s text that a second refusal of a move whose
  entry is still open submits no `event: raise` and stays in `wait`. It says
  this is the agent's instruction, not an engine guard, and doesn't lean on
  the existing `decision_raise` rule, which covers only a parked unit.
- [ ] The text says the refusal stands and no answer to the entry authorizes
  the cross-lane write; a person who wants the target's cap changed has the
  target lane set its own cap.
- [ ] Walking a refused move through a scratch record ends with one decision
  entry whose question carries the refusal line, escalated once with a
  recommendation and `--grounds outside-scope`; a second refusal of the same
  move while that entry is open submits no `raise` and adds no entry, and the
  sibling's record is byte-identical throughout.
- [ ] A search for `niwa authority check` under `skills/coordinate/` finds it
  in `authority-read.sh` alone.

**Check**: A walkthrough on a scratch record, driving the template by hand
through two refusals of the same move, then reading the record: one entry,
escalated once, the sibling's record unchanged. Then the one-reader search,
and a read of the changed Bounds and Authority text for any rule about who
holds the cap-change authority, finding none.

**Dependencies**: Step 2, Step 3

**Files**: skills/coordinate/SKILL.md,
skills/coordinate/koto-templates/coordinate.md

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
  instance>`. If that can't be set up on this host, the step's record says so
  and the director-side criterion below stays open.
- [ ] From the dispatching director, `lane-read.sh` returns the lane's bound
  answer with `parent_is_mine` true, the lane found from niwa's records alone
  and sent no message.
- [ ] From a session that is neither the lane nor its dispatcher, on niwa
  0.40.0, `lane-read.sh` returns the lane's bound answer, with its instance and
  session id found from `niwa list` and `niwa lineage show` alone; no file the
  lane wrote is read and the lane receives no message.
- [ ] The lane's role grants at least one authority and the answer lists it;
  after the grant is changed in the workspace configuration, the next ask shows
  the new grant without restarting the director or the lane.
- [ ] From a lane without the cap-change authority, a move of a sibling's cap
  through the skill is refused naming the cap-change authority as one niwa
  grants and the session lacks, and the sibling's cap in force and record
  entries are unchanged.
- [ ] The run's record lands in the design's "What a third session can read
  today" section, replacing its unmeasured sentence: the niwa version, each
  command with host paths replaced by placeholders, and the result lines it
  read (state, grant, level, level source and the `merge-pr` settler), never
  a full niwa answer, which carries host paths.

**Check**: A walkthrough on this host with a lane dispatched by hand holding
a grant: the director's read shows the grant with `parent_is_mine` true, the
third session's read shows the same grant, the changed grant shows on the
second ask from each, and the cross-lane move is refused; the design's
updated section shows each command and its result lines.

**Dependencies**: Step 4

**Files**: docs/designs/DESIGN-director-reads-lane-authority.md

**Type**: task

**Complexity**: testable

## Proposed Follow-up

Not filed; proposed under the rule that a finding which doesn't block an
acceptance criterion becomes a step or a follow-up, not a wider design.

- **The skill holds a grant rule for lane coordinators.** The dispatch text in
  `skills/coordinate/koto-templates/coordinate.md` (around line 2833) says "A
  lane coordinator gets none", which decides inside the skill what grant a
  dispatched lane coordinator holds. That is the kind of allowance this
  feature says belongs to the workspace. A follow-up would have the skill
  dispatch a lane coordinator with whatever the workspace's role grants it and
  drop the sentence.
- **Measure the third-session read of a lane holding grants before Step 3.**
  The design's measurement covered a lane whose grant was empty. A follow-up
  would run that read on this host against a lane whose role grants at least
  one authority, and change the grant between two reads, so Step 3 is built
  against a measured answer rather than waiting for Step 5 to find out.

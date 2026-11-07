---
schema: plan/v1
status: Active
execution_mode: multi-pr
split_mode_source: intent
split_rationale: |
  Incremental Value. Each issue leaves the skill working on its own, with
  one stated gap: Issue 1 gives the record a role row, its set-once writer
  and its reader, with nothing yet requiring the row; Issue 2 makes the
  opener check, ask for and guard it, an intervention from above included,
  and turns on the seed's requirement, the record_open change and the
  no-role gap with its fill text in the same pull request, so no fresh start
  or reconcile is held between two issues; but until Issue 4 a brief's
  invocation line carries no --role, so a lane a brief starts in that window
  stops at ask=role, and Issue 4 lands right after Issue 2 with no lane
  dispatched between them; Issue 3 puts it in every report; Issue 4 carries
  it to a lane and a successor; Issue 5 fixes holding links on its own; Issues 6 and 7 give the
  skill its Roles text and readdress one-role duties; Issue 8 checks the
  whole change. The documents merge ahead of the build so later work can
  plan against them, and each issue lands later in its own pull request on
  its own branch.
tracking_level: none
upstream: docs/designs/DESIGN-coordinator-named-roles.md
milestone: "Coordinator named roles"
issue_count: 8
---

# PLAN: Coordinator named roles

## Status

Active

The upstream design is Planned. Its reviewer accepts it on this plan,
which shows where each of the design's six decisions lands and which
requirement each criterion traces to.

## Scope Summary

Give the coordinate skill's two coordinator roles, manager and director, one
name each that rides the existing machinery: a `--role` start flag the opener
checks before any koto call, one set-once Run `role` row every continuation
already carries, a record line a script prints at the top of every report, a
`--role` on a coordinator brief's invocation line, and a Roles section that
says what each role owes, never what it's allowed. The skill's text is then
swept so every duty only one role owes names that role.

Out of scope:

- cap changes by a director, for a coordinator it dispatched or its own;
- the director's alignment holding of diverging work;
- an owner-funnel mechanism (no routing script, queue or gate);
- a discipline route for briefs;
- opener-seeded records.

## Decomposition Strategy

**Horizontal.** The design builds the change in six layered phases: the
record row, the opener that writes it, the record line that reads it, the
brief that carries it, the skill text that names it, and the checks over all
of it. Each layer has its own scripts and tests and a narrow interface to the
next (the Run `role` row, the opener's `role=` line, the record line's
template), so each issue is one layer tested against the layers below. A
walking skeleton doesn't fit: the row and its set-once writer come before
every other piece, and no thin slice exercises the opener, the report and the
brief without them. The design's Phase 5 is split three ways, since the
progress-event link fix, the Roles text and the sweep have different
dependencies and the sweep runs last over finished text.

Each issue lands later in its own pull request, after these documents merge.
That departs from the design's Implementation Approach, which calls one pull
request the expected shape because the phases share fixtures and the compat
record. The PLAN splits it so each layer lands with value of its own, and it
handles the two shared pieces this way: a fixture lands with the first issue that uses it, and every issue that
changes a script the template's gates run re-records the gate-script digest
in `coordinate.compat.json` at compat 2 in its own pull request, so
`check-template-compat.sh` passes on each one. Issue 8 then checks the digest
once more over the finished change.

Issue 2 also takes three pieces the design places in its Phases 1 and 3: the
seed's `--role` requirement, the `record_open` directive change, and the
`no-role` gap with the reconcile directive's text for filling it. Landed
apart from the opener, the seed requirement would refuse every fresh start,
since the opener prints no `role=` before Issue 2, and the gap would hold
every run at the reconcile gate with no text saying how to fill it. Issue 1
keeps the row, its writers and its reader, which nothing requires yet, and
Issues 3 and 4 wait on Issue 2 for the same reason: the record line has no
role to print, and a coordinator brief's `--role` has no opener to accept it,
until Issue 2 lands. The reverse gap is stated, not hidden: from Issue 2 until
Issue 4, a lane a brief starts carries no `--role` on its invocation line and
stops at `ask=role` with exit 10, so Issue 4 lands right after Issue 2 and no
lane is dispatched between them.

These rules hold for every issue. A rule-coverage row's key phrase is 8 to 60
characters and sits on one line of its file, because `rule-coverage_test.sh`
refuses any other length and matches with `grep -F` line by line; where a
criterion below pins a sentence longer than that, it pins short phrases from
it, one per clause or source. And each pull request passes the PRD's
public-content check over its own diff: its added lines, every commit message
on its branch, and its title and description hold no word
`skills/writing-style/rules.yaml` bans (checked against that file, not a
copied list), no emoji, no `Co-Authored-By` or other AI attribution, no path or
name from a private repository, no session name and no internal figure. Each
issue's public-content criterion refers to this check, and that check also
holds the PRD's R14 read: a reviewer reads each added sentence naming
`manager` or `director` and finds none saying a role holds, needs or implies
a grant, a merge, close or release authority, a cap or the right to change
one, or the right to settle a step. Every issue's definition of done also
includes `scripts/check-skill.sh --changed coordinate`, as the repository's
rules require, whether or not its Check line repeats it. Last, scenarios follow
behaviour, as the repository's rule for a changed skill requires: Issues 2,
3, 4, 5 and 6 change what the skill does or owes, so each updates
`skills/coordinate/evals/evals.json` for its own change, each tier-2 scenario
naming its behaviour with exactly one `"release": true` per behaviour, and
`scripts/check-skill.sh --changed coordinate` passes the shape check. Issue 1
adds a row nothing requires yet, Issue 7 only rewords, which the PRD leaves
out of the scenarios, and Issue 8 only checks, so those three leave the
scenarios alone.

## Issue Outlines

### Issue 1: feat(coordinate): add the Run role row, its writers and its reader

**Goal**: Store a run's role as one Run row, `role` (`manager` or
`director`), written only by `state-open.sh`'s seed and the set-once
`state-stored-set.sh --run role`, and read through a new `state-read.sh
--run`. Nothing requires the row yet: the seed writes it when given
`--role`, and Issue 2 adds the requirement, the `record_open` change and the
`no-role` gap together with the opener that prints the role.

The set-once rule is the PRD's R5: a continuation keeps its role, and a
different role is refused unless the change is an intervention from above
(the dispatching session higher in the calling hierarchy, or a person), with
the record keeping who intervened and when. This issue's set-once writer and
its `--intervention` write, and Issue 2's refusals and change flags, both
implement it.

Overlaps shirabe#1470, #1473 and #1474 on the state scripts, `state-keys.md` and their tests; rebase onto them if they land first; don't wait on them.

**Acceptance Criteria**:
- [ ] `state-schema.jq` accepts a Run `role` row only as `manager` or
  `director`, at most one; `state-schema_test.sh` adds refused cases for
  `Director`, `lead`, an empty value and two `role` rows.
- [ ] `state-stored-set.sh --run role director --by <who>` with no row
  writes one; again with `director` it exits 0 and the record is
  byte-identical; with `manager` it exits 65, stderr names both values, and
  the row still reads `director`. A `--by` over 80 characters or holding a
  line break is refused. Each case is in `state-stored-set_test.sh`.
- [ ] Citing PRD R5: `state-stored-set.sh --run role manager --by
  <who> --intervention dispatcher` on a row holding `director` replaces it:
  the row reads `manager`, its `set_by` is `<who>` and its `set` the write's
  time, and the appended entry names `director` as the old role, `manager`
  as the new one and `dispatcher` as the source; the same with
  `--intervention person` names `person`. `--intervention` with any other
  value, or on a `--run` key other than `role`, exits 64 and writes nothing;
  with no row or the same value it writes as without it. Each case is in
  `state-stored-set_test.sh`.
- [ ] `state-stored-set.sh --run role ... --intervention <source>` writes on
  a record the run holds before its find has sealed it, through the
  before-find path `--rule-files` uses (the write core's `START_WRITER`); a
  case writes it into a run's session right after a carry lands, before the
  find, and finds the row, its `set_by`, `set` and entry. Without
  `--intervention`, `--run role` keeps the rule every other `--run` key has.
- [ ] `state-open.sh` on a fresh seed with `--role manager` holds
  `role=manager` in the seed; with no `--role` it seeds as it does today,
  with no row.
  `--carry --role director` adds the row only when the copy has none, and a
  copy holding `manager` keeps it; `--carry --role director --role-change-by
  <who> --role-change-source person` on a copy holding `manager` replaces it
  through the intervention write, with the same `set_by`, `set` and entry,
  and one of the two change flags without the other exits 64
  (`state-open_test.sh`, `state-carry_test.sh`).
- [ ] `state-read.sh --run` prints `record/run` with no sealed find, and a
  failed read exits non-zero rather than printing an empty section
  (`state-read_test.sh`).
- [ ] `state-handover.sh` prints `role` (the value, or null), and
  `--check` lists no new gap; `state-handover_test.sh` covers both values.
- [ ] `koto-templates/coordinate.compat.json` re-records the gate-script
  digest with the fingerprint unchanged and compat at 2, since
  `state-handover.sh` runs behind the reconcile gate.
- [ ] `reports-to` is described as `<name>` or `<name> at <address>` in
  `SKILL.md`, `references/state-keys.md`, `state-schema.jq`'s comment and
  refusal message, `state-stored-set.sh`'s usage and the `no-reports-to` fix,
  which reads
  `state-stored-set.sh --run reports-to "<name>[ at <address>]" --by <who>`;
  none of them uses the word "role" for it, and `the human` still passes.
- [ ] `references/state-keys.md` lists the Run `role` row, its two values,
  its two writers, its reader, and that only `--intervention` replaces a
  different value.
- [ ] The writer structure test in
  `coordinate-template-structure_engine_test.sh` pins the `role` row to
  `state-stored-set.sh` and `state-open.sh` (seed and `--carry --role`); a
  fixture script that writes the row fails it.
- [ ] A reader allow-list test counts the three read forms the design names:
  a call to `state-read.sh --run`; the literal `role` used as a Run key,
  whether in a `.key == "role"` comparison or passed to a helper that takes a
  Run key (`run_has role`, `runval("role")`); and a direct `record/run` read.
  It fails when a script not on its list uses `role` as a Run key or calls
  `state-read.sh --run`, and when a script not in its fixture list of current
  Run-section and record readers adds a direct `record/run` read. That
  fixture list is generated by a grep at the branch base and checked in, not
  typed. A whole read through `state-stored-set.sh --list`, `--record`,
  `rs_record` or `rs_record_api` isn't counted by itself. Here the allow-list
  holds the writers (`state-schema.jq`, `state-stored-set.sh`,
  `state-open.sh`) and `state-handover.sh`. Fixtures that add
  `.key == "role"` to `land-merge.sh`, `run_has role director` to
  `rebrief-record.sh`, and a `record/run` read to a new script each fail it. For a script with two paths, the list names the function that may
  read the row, not only the script: the test fails when the read sits in any
  other function of that script. The same test fails when any
  script under `skills/coordinate/` passes `--role` to `niwa dispatch`.
- [ ] The existing large-record tests (a record of about 60,000 bytes) pass
  unchanged with the row added.
- [ ] This pull request passes the public-content check the Decomposition
  Strategy names, over its own added lines, commit messages, title and
  description (PRD R20).

**Dependencies**: None

**Complexity**: critical

**Check**: Run `state-schema_test.sh`, `state-stored-set_test.sh`, `state-open_test.sh`, `state-carry_test.sh`, `state-read_test.sh`, `state-handover_test.sh`, `handover_engine_test.sh` and `coordinate-template-structure_engine_test.sh`; each passes, and `scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md` passes with the gate-script digest re-recorded at compat 2. The public-content check passes over this pull request.

**Files**: `skills/coordinate/scripts/state-schema.jq`, `skills/coordinate/scripts/state-stored-set.sh`, `skills/coordinate/scripts/state-open.sh`, `skills/coordinate/scripts/state-read.sh`, `skills/coordinate/scripts/state-handover.sh`, `skills/coordinate/references/state-keys.md`, `skills/coordinate/SKILL.md`, `skills/coordinate/koto-templates/coordinate.compat.json`

### Issue 2: feat(coordinate): check, ask for and guard --role in the opener

**Goal**: `coordinate-open.sh` parses `--role` on every path, refuses a bad
value or a change of a recorded role before anything is written, asks for a
missing one, prints `role=<value>`, and writes the row for a role-less record
on resume, takeover and import. In the same pull request the seed requires
`--role`, the `record_open` directive passes the printed `role=`, and a
missing row becomes the handover gap `no-role`, with the reconcile
directive's text for filling it.

The role-mismatch refusal and the change flags implement the PRD's R5: a
continuation keeps its role, a different role is refused unless the change
is an intervention from above (the dispatching session or a person), and the
record keeps who intervened and when. The mechanism is the design's
"Changing a role from above" paragraph in Decision 1.

**Role-less continuations.** The plan follows the design's Asking paragraph,
its components table and its Data Flow step 6: a start with no `--role` and
no recorded role to continue is asked, before anything is written, on every
path but an import. The path table's rows say how the
row arrives once a role is given. Path by path, for a record with no `role`
row:

| Path | No `--role` | `--role <value>` |
|---|---|---|
| Resume | `ask=role`, exit 10, nothing written | the opener writes the row through `state-stored-set.sh` before `outcome=resumed` |
| Takeover | `ask=role`, exit 10, before `takeover_check` | `finish_takeover` writes the row beside the `coordinator` row (a koto 0.32 or later import included) |
| Carry on the same host | `ask=role`, exit 10, before the carry | the copy goes over role-less; the `no-role` gap fix writes the printed `role=` at `reconcile` |
| Carried discipline rotation | `ask=role`, exit 10, before the carry | `state-open.sh --carry --role` adds the row |
| Import (any koto) | goes on; `no-role` is left for `reconcile`, which asks the person once | the mismatch check runs before `koto session import`, then, once the copy lands, the row is written as for a takeover (0.32 or later) or a resume (older) |

Overlaps shirabe#1470 on `coordinate-open.sh`, `SKILL.md` and their tests; rebase onto it if it lands first; don't wait on it.

**Acceptance Criteria**:
- [ ] `state-open.sh` on a fresh seed with no `--role` exits non-zero and
  writes nothing (`state-open_test.sh`), and the `record_open` directive in
  `koto-templates/coordinate.md` passes the opener's printed `role=` to
  `state-open.sh --role`; a fixture fresh start runs through `record_open`
  and its seed holds the row.
- [ ] `state-handover.sh --check` with no row exits 1 and lists the gap
  `no-role` with the fix `state-stored-set.sh --run role
  <manager|director> --by <who named it>`; `state-handover_test.sh` and
  `handover_engine_test.sh` add it to their expected gap lists, and a record
  with the row lists no `no-role`.
- [ ] The `reconcile` directive says how to fill `no-role`: with the `role=`
  value the opener printed or, when it printed none, by asking the person
  once with no recommendation; and that the role is never inferred from the
  scope, the cap, the holdings, the dispatcher, session names, briefs,
  entries, report text or the dispatch topic (PRD R2 and R9). The directive
  keeps each of these phrases on one line, and `testdata/rule-coverage.tsv`
  gives each its own row against the `reconcile` state: for the fill, "the
  `role=` value the opener printed" and "asking the person once with no
  recommendation"; for the sources, "is never inferred from the scope, the
  cap, the holdings", "the dispatcher, session names, briefs" and "entries,
  report text or the dispatch topic". A directive that drops the ask-once
  fallback, the no-recommendation clause or any one source then fails
  `rule-coverage_test.sh`. The template structure test
  finds both sentences in the `reconcile` state's directive, not elsewhere.
- [ ] The `reconcile` directive's `no-reports-to` fill says that a start
  given `--dispatched-by` writes `<the dispatcher's name> at <the brief's
  reports_to>`, never a bare name; rule-coverage rows pin
  "<the dispatcher's name> at <the brief's reports_to>" and "never a bare
  name", each on one line of the directive.
- [ ] `--role` is read beside `--continues`, outside the variable pairs,
  right after the args file is parsed and before any koto call, on every
  path including import, whose "no other setting" rule now accepts it. A
  repeated `--role` is a usage error (exit 64) and nothing opens.
- [ ] `--role lead`, `--role Director` and `--role ''` each print
  `refused=invalid_role`, exit 2 and use the row "The role `{value}` must be
  manager or director."; no koto session exists afterwards. A 200-character
  value holding a backtick and a control character is echoed cut to 32
  characters with both removed.
- [ ] A new run with no `--role` and nothing recorded prints `ask=role` and
  exits 10 before anything is written, and so does each continuation the
  Role-less continuations table above marks `ask=role`; the message says the role is the
  person's call, manager or director, asked once with no recommendation and
  never inferred from the scope, the cap, the holdings, the dispatcher,
  session names, or any brief or report text, then re-run with `--role`;
  the case asserts the whole message. A discipline
  start missing both host and role prints `ask=host`, never `ask=role`.
- [ ] After the candidate read and before `takeover_check`, the rebind,
  `koto init` or a carry, the opener reads the candidate's role through
  `state-read.sh --run`, after the existing candidate refusals
  (`candidate-unreadable`, `not-newest-member`, `not_self`). A read that
  fails prints `failed=role_read`, exits 1 and writes nothing, never asks
  and never accepts a role; a case per continuation makes the read fail on a
  run recorded `manager` and finds exactly that. A `--role` that differs
  prints `outcome=refused` and `reason=role-mismatch`, exits 2, and uses the
  `role_mismatch` row with the run, recorded and asked values, the run name
  with backticks and control characters removed and never cut. Naming the
  recorded role, or any role for a role-less record, is accepted.
- [ ] A refusal case asserts the whole `role_mismatch` message, not only the
  `reason=` line: it equals the wording row with `{run}`, `{recorded}` and
  `{asked}` filled in (for a run recorded `director` asked `manager`, the
  message names the run, then `director`, then `manager`, and ends "or start
  manager as a new lineage."). A second case gives a candidate run with a
  realistic name over 32 characters (`coordinate-<scope>-<name>-<stamp>`)
  and finds the whole name in the message, asserted as the exact expected
  string; the `invalid_role` case asserts its value's removal of backticks
  and control characters and its cut to 32.
- [ ] On an import whose copy is already here, every role refusal
  (`role_mismatch` and the four role-change rows) ends with the
  `role_import_copy` row, which says the run is on this host and to run the
  same import again naming the recorded role or none, not a plain start; those
  cases assert it in the whole message, and the same import afterwards, naming
  the recorded role, continues the run. A case on a copy whose source has no
  marker, the state `refused=import_unmarked` leaves, finds no marker after the
  refused start, finds one after the same import, and then has a write from the
  source's workspace refused. On an import with no copy here, the whole message
  has no such row.
- [ ] Every successful start that knows the role prints `role=<value>`.
- [ ] Citing PRD R5: `--role-change-by` and `--role-change-source` are read
  beside `--role`; either one without the other, or both without `--role`,
  a source other than `dispatcher` or `person`, a flag given twice, or a
  `--role-change-by` value that is empty, longer than 80 characters, or
  holds a control character or backtick, is a usage error (exit 64) found
  when the arguments are parsed, before any koto call, and nothing opens;
  each is a case. On a run recorded `manager` whose `reports-to` row
  is `<D> at <addr>`, `--role director --role-change-by <addr>
  --role-change-source dispatcher` is accepted; the start prints
  `role=director` and `role_changed_from=manager`. The same with
  `--role-change-by <D>` (the row's name half), with any name that isn't
  `<addr>`, on a record whose `reports-to` row has no address (`the human`),
  or on a record with no `reports-to` row, prints `outcome=refused` and
  `reason=role-change-refused`, exits 2, and writes nothing. Each refusal
  case asserts the whole message against the wording row for its cause, as
  the design's table names them: `role_change_not_reports_to` for a name
  that isn't the row's address (`<D>` included), `role_change_no_address`
  for a row with no address or no row, `role_change_self` for the run's own
  session, predecessor or address (every one of the four messages names the
  row's value as who the run reports to, `the human` included, or `no
  session on its record` when there's no row), and `role_change_brief_person` for a
  `person` change on a start given `--dispatched-by`; each echoed value is
  stripped of backticks and control characters and never cut: a case with a
  realistic row (a name, then ` at ` and a
  `coordinate-<slug>-<YYYYMMDDTHHMMSSZ>` address over 32 characters) finds
  the whole row value in the message. A case where two causes hold (the
  run's own address on a record with no `reports-to` row) gets the
  `role_change_self` message, the design's order.
- [ ] Citing PRD R5: with either source, a `--role-change-by` naming the
  run's own session, its predecessor, its own Run `coordinator` address, the
  new run's session name or the caller's own address (`CALLER_NAME`) is
  refused `role-change-refused`, including a run whose `reports-to` row holds
  that address; a `person`-source takeover whose change names the caller's
  own address is one of the cases. Every role-change refusal's message ends
  "This start names {asked}; nothing was written and {run} goes on as
  {recorded}.", asserted in the whole-message cases. `--role-change-source person` naming anyone else is accepted
  on a start with no `--dispatched-by`, and refused `role-change-refused` on a
  start given `--dispatched-by` (a start a brief launched). With the change
  flags and the recorded role, or on a role-less record, the flags change
  nothing and the start is the one it would be without them.
- [ ] An accepted change is written through `state-stored-set.sh --run role
  <new> --by <name> --intervention <source>` by the writer each path runs, as
  the design's path table names it: the opener before `outcome=resumed` on a
  resume and on an older import; `finish_takeover` on a takeover and a koto
  0.32 or later import; the opener after `cancel_others` and before
  `session=` on a same-host carry, through the before-find path (a case in
  which that write fails finds the carry standing, `role=` the recorded
  role, `warning=role-change-unwritten`, `session=` printed and exit 0, and
  a later start with the same flags, once that run's find has recorded its
  store, applying the change as a resume); and on a
  carried rotation `state-open.sh --carry --role <new> --role-change-by
  <name> --role-change-source <source>`, run by the `predecessor_carry`
  directive from the `role=`, `role_change_by=` and `role_change_source=`
  lines the opener prints. The directive's sentence is added and a
  rule-coverage row pins it. An import accepts the two change flags beside
  `--role` under its "no other setting" rule. In each case the row, its
  `set_by` and `set`, and the entry naming old role, new role and source are
  asserted afterwards. On a resume, an import and a takeover, a write that
  fails exits non-zero with no `outcome=resumed` or `session=`; a same-host
  carry's failed write is instead the exit-0 warning case above.
- [ ] A resume of a role-less record given `--role director` writes the row
  through `state-stored-set.sh` before printing `outcome=resumed` (a case
  whose write fails exits non-zero and prints no `outcome=resumed`);
  `finish_takeover` writes it beside the `coordinator` row; a role-less carry
  given `--role` prints `role=<value>` and leaves the row to the `no-role`
  fix.
- [ ] Each row of the Role-less continuations table is a test case in the
  engine tests named below, for both columns. In every `ask=role` case the
  candidate's record, the run's koto state and the session list are
  identical before and after, and no new session exists. In the import case
  with no `--role` the opener exits 0, prints no `ask=role` and no `role=`,
  and `state-handover.sh --check` on the copy lists `no-role`.
- [ ] An import re-run on koto 0.32 or later whose copy is already here and
  fenced runs the same role read and mismatch or change decision first, with
  the `role_import_copy` ending on a refusal, on the run that branch
  continues: after a finished import, the successor `$FENCE_BY` it resumes;
  after a cut-short one, the successor when that takeover already wrote its
  `role` row, and the copy otherwise. Cases cover a re-run after a finished
  import whose first run accepted a role change, where the copy's row still
  holds the old role: naming the new role with no change flags is accepted
  as a resume of the successor, and naming the old role is refused
  `role-mismatch` with both records unchanged, so a check on the copy fails
  both. Cases also cover a re-run after an import cut short before its row
  was written, with a mismatched `--role` refused and a matching one
  accepted against the copy's row.
- [ ] Citing PRD R5's criterion for refused starts: an import given `--role`
  with no copy here runs the mismatch and change decision on the source, through
  `state-read.sh --run --workspace <from> --session <run>`, before `koto session
  import`. After a refused one, `coordinate-import-takeover_engine_test.sh`
  finds no migration marker beside the source and no session under this
  workspace's prefix, finds the source's record and koto state as they were,
  and has a write from the source's workspace accepted; the same import then
  started with the recorded role lands. An import never prints `ask=role`.
- [ ] An import given `--role` whose source has no `record/run` key, or no
  `role` row, goes on and gets its row once the copy lands. On the local backend
  it prints `refused=workspace_needs_cloud` and exits 2; a source the bucket
  doesn't hold prints `refused=session_not_found` and exits 2; a bucket read that
  fails prints `failed=role_read` and exits 1, and isn't taken as role-less.
  Each of those refusals lands nothing. An import with no `--role` makes no such
  read. `state-read_test.sh` covers the `--workspace` form for a present key, an
  absent key, a koto refusal and a failed read.
- [ ] Citing PRD R5's refusal of a change named by the run's predecessor: an
  import with no copy here, given a `--role` that differs from the source's and
  the change flags, reads the predecessor through `state-read.sh --predecessors
  --workspace <from> --session <run>`, which prints the names under the source's
  `koto/links/continues/` keys. `coordinate-import-takeover_engine_test.sh` runs
  a source that continues another run, with a `person` change naming that run
  and with a `dispatcher` change naming it where the source's `reports-to` row
  holds its address. Each is refused `role_change_self` before `koto session
  import`, with no migration marker and no session under this workspace's prefix
  afterwards. A koto refusal of that listing prints `refused=<code>` and exits 2,
  and a failed listing prints `failed=role_read` and exits 1; neither is taken as
  no predecessor. `state-read_test.sh` covers the mode for a source with a
  relation, one with none, a koto refusal and a failed read.
- [ ] An import re-run whose copy is here but not fenced, known by a
  `koto/imported-from` record naming the run, checks the copy's row rather than
  the source's. A case on koto older than 0.32 re-runs a finished import whose
  first run accepted a role change: naming the new role with no change flags is
  accepted and naming the old role is refused `role-mismatch`, so a check on the
  source fails both. A case on koto 0.32 or later re-runs an import cut short
  before the fence: a mismatched `--role` is refused and a matching one goes on.
- [ ] `coordinate-open_engine_test.sh`, `coordinate-takeover_engine_test.sh`,
  `coordinate-import-takeover_engine_test.sh` and
  `discipline-session_engine_test.sh` cover all five continuations (resume,
  carry, takeover, import, carried rotation), each accepting a matching role
  and refusing both directions of mismatch (recorded `manager` asked
  `director`, and the reverse). Every refusal case finds the record and the
  run's koto state identical before and after. The same suites cover, on
  each of the five continuations, an accepted `dispatcher` change, an
  accepted `person` change, and three refused `dispatcher` changes, naming a
  session the record doesn't report to, the run's own session and its
  predecessor. Each refused case asserts the message names the run's
  `reports-to` row value and finds the record and the run's state as they
  were, so a change accepted on one path and refused on another, or a path
  that skips the address match, fails.
- [ ] A successor's brief opens. `not_self` on the candidate accepts a
  `--dispatched-by` equal to the candidate only when the start takes it over
  (a takeover, or the re-run that finds a finished interrupted one), and
  still refuses it with exit 64 on a resume or a carry of the candidate; a
  dispatcher naming the new run's own session is refused on every path.
  `coordinate-takeover_engine_test.sh` covers a takeover of a predecessor
  recorded `director` started with `--dispatched-by` naming that
  predecessor, accepted with the successor's Run `role` row reading
  `director`; the same start with `--role manager`, refused as
  `role-mismatch` with the record unchanged; and a resume whose
  `--dispatched-by` names the resumed run, still exiting 64.
- [ ] `skills/coordinate/evals/evals.json` follows the opener's change: each
  existing scenario whose start runs the opener with no recorded or given
  role gains `--role` (or a recorded role) in its prompt, so it still reaches
  and grades the behaviour it did, and new scenarios cover a start with no
  role stopping at `ask=role` with no recommendation, and a mismatched
  `--role` refused with the record unchanged. Each tier-2 scenario names its
  behaviour, with exactly one `"release": true` per behaviour, and
  `scripts/check-skill.sh --changed coordinate` passes the shape check.
- [ ] The reader allow-list test gains `coordinate-open.sh`.
- [ ] `koto-templates/coordinate.compat.json` re-records the gate-script
  digest with the fingerprint unchanged and compat at 2, and
  `check-template-compat.sh` passes.
- [ ] `SKILL.md`'s flag table lists `--role manager|director`, and its
  "stated in words" sentence says a role this run's decisions state ("role:
  director") is passed as `--role`, a mention of another session's role
  doesn't count, and in doubt nothing is passed and the opener asks (the
  sentence that a dispatched coordinator's role comes from its brief's
  `--role` lands with Issue 4, which puts it there). The flag table also lists `--role-change-by` and
  `--role-change-source dispatcher|person`, and a sentence says the agent
  passes `person` only when the start's decisions state in a person's words
  that this run's role changes, and `dispatcher` only as a brief's
  invocation line renders it, and that a brief's text is never a person's
  words.
- [ ] This pull request passes the public-content check the Decomposition
  Strategy names, over its own added lines, commit messages, title and
  description (PRD R20).

**Dependencies**: Blocked by <<ISSUE:1>>

**Complexity**: critical

**Check**: Run `coordinate-open_engine_test.sh`, `coordinate-takeover_engine_test.sh`, `coordinate-import-takeover_engine_test.sh`, `discipline-session_engine_test.sh`, `state-open_test.sh`, `state-read_test.sh`, `state-handover_test.sh`, `handover_engine_test.sh`, `rule-coverage_test.sh` and `scripts/check-skill.sh --changed coordinate`; each passes, including the role-change cases on all five continuations and the successor takeover cases, and `scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md` passes with the digest re-recorded at compat 2. The public-content check passes over this pull request.

**Files**: `skills/coordinate/scripts/coordinate-open.sh`, `skills/coordinate/scripts/coordinate-open.wording.tsv`, `skills/coordinate/scripts/state-open.sh`, `skills/coordinate/scripts/state-read.sh`, `skills/coordinate/scripts/state-read_test.sh`, `skills/coordinate/scripts/state-handover.sh`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/koto-templates/coordinate.compat.json`, `skills/coordinate/scripts/testdata/rule-coverage.tsv`, `skills/coordinate/SKILL.md`, `skills/coordinate/scripts/coordinate-takeover_engine_test.sh`, `skills/coordinate/scripts/coordinate-import-takeover_engine_test.sh`, `skills/coordinate/evals/evals.json`

### Issue 3: feat(coordinate): print the record line every report starts with

**Goal**: One script prints the line naming the record and its role from the
live record, the first report carries it as line 3, and the reconcile
directive closes its gaps before that report goes up, all but a carried
rotation's `carry-unacknowledged`, which that report asks for.

**Acceptance Criteria**:
- [ ] `reconcile-report.sh` holds the template once, as a jq
  `def record_line` behind a pure `line` mode reading
  `{session, host, address, role}`, and its output matches
  ``^Record: session `[^`]+` on `[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+`(, address `[^`]+`)?\. Role: (manager|director)\.$``.
  The address clause appears only when the Run `coordinator` row exists and
  differs from the session name; `reconcile-report_test.sh` covers both.
- [ ] `coordinate-report.sh --session S --record-line` prints the line and
  nothing else, exits 4 with no `role` row (stderr names the `no-role` fix)
  and 65 when the record can't be read (`coordinate-report_test.sh`).
- [ ] `reconcile-report-get.sh --md` prints `# Reconcile report`, a blank
  line, the record line as line 3, a blank line, and the unchanged `Scope:`
  line as line 5; with no role row it exits 4 and prints nothing. `--check`
  and the JSON mode don't read the line, and the sealed report and its seal
  are unchanged.
- [ ] The `reconcile` directive closes every gap `state-handover.sh --check`
  names, then prints with `reconcile-report-get.sh --md` and reports it up,
  then submits `reconciled: reported`. A role-less carry whose gap fix writes
  `manager` gets a first report whose line 3 ends `Role: manager.`, with no
  second reconcile visit.
- [ ] The one gap the directive leaves open for the first report is
  `carry-unacknowledged`: a discipline rotation that carried a predecessor
  recorded as `manager`, with no go-ahead since its chain started, closes its
  other gaps, and `--check` then lists `carry-unacknowledged` alone. `--md`
  exits 0 with line 3 ending `Role: manager.`, and the report lists the holds
  and Standing rows `coord/predecessor_carry.json` names and asks for the
  go-ahead. A `reconciled: reported` submit is refused until the go-ahead
  row is written; then `--check` exits 0 and the submit moves on. A rotation
  whose go-ahead was set after its chain started keeps the order above. The
  directive text names the exception before the `--md` call and records the
  go-ahead after the report and before the submit (design Decision 6).
- [ ] `references/loop.md` and the template's `reconcile_pass` prose point
  at `reconcile-report-get.sh --md`, not the stored report key, and list the
  record line first among the opening lines kept as written; the
  `state-keys.md` and template sentences about reporting the session name
  point at the record line.
- [ ] `SKILL.md`'s Reporting section replaces "Name the record in every
  report (its session name and its host repository)" with the template in a
  fenced block, says the first report takes it from
  `reconcile-report-get.sh --md` and every later one (the closing one too)
  starts with what `coordinate-report.sh --record-line` prints, pasted as
  printed, and says a report calls its own role only by that word.
- [ ] `coordinate-report.sh`'s closing `record=` line accepts a session name
  beside the legacy GitHub URL, with a test case for a session name.
- [ ] The reader allow-list test gains `coordinate-report.sh`.
- [ ] `koto-templates/coordinate.compat.json` re-records the gate-script
  digest with the fingerprint unchanged and compat at 2, and
  `check-template-compat.sh` passes.
- [ ] `skills/coordinate/evals/evals.json` follows the record line: each
  existing scenario that grades how a report names the record or keeps the
  reconcile report's opening lines expects the record line among those lines,
  with the role, and a new scenario covers a later report starting with what
  `coordinate-report.sh --record-line` prints, pasted as printed.
- [ ] This pull request passes the public-content check the Decomposition
  Strategy names, over its own added lines, commit messages, title and
  description (PRD R20).

**Dependencies**: Blocked by <<ISSUE:2>>

**Complexity**: testable

**Check**: Run `reconcile-report_test.sh` and `coordinate-report_test.sh`; each passes, and a fixture run's first report has the record line within its first five lines. `check-template-compat.sh` passes with the digest re-recorded at compat 2. `scripts/check-skill.sh --changed coordinate` passes the shape check. The public-content check passes over this pull request.

**Files**: `skills/coordinate/scripts/reconcile-report.sh`, `skills/coordinate/scripts/reconcile-report-get.sh`, `skills/coordinate/scripts/coordinate-report.sh`, `skills/coordinate/references/loop.md`, `skills/coordinate/references/state-keys.md`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/koto-templates/coordinate.compat.json`, `skills/coordinate/SKILL.md`, `skills/coordinate/evals/evals.json`

### Issue 4: feat(coordinate): carry the role on a coordinator brief's invocation line

**Goal**: `render-brief.sh` takes a `role` field that `dispatch-worker.sh`
fills from the record for a successor and as `manager` for a lane, rendered
as `--role` on the invocation line, while worker briefs stay byte for byte as
they are.

**Acceptance Criteria**:
- [ ] `render-brief.sh` refuses a `coordinate` brief whose `role` is `lead`,
  `Director` or empty, or missing without `held_rerender: true`, a `role` or
  `held_rerender` on any other entry point, and `--role` in `entry_args`;
  each exits 1, the renderer's existing input refusal, prints a stderr line
  naming the field and the refused value, and writes no brief; each is a
  case in `render-brief_test.sh`. A `coordinate` brief with no `role` and
  `held_rerender: true` exits 0, writes the brief and renders no `--role`.
- [ ] On a `held_rerender` coordinate brief, the opener line's "If your
  session is already open" sentence gains a clause saying to write the
  invocation's tokens into a fresh `$ARGS_DIR/args.json` first (the opener
  removes the file once read), then run the opener; `render-brief_test.sh`
  finds that clause on a `held_rerender` coordinate brief, a `role_change`
  re-render included, and not on a new lane's brief, and the end-to-end case
  below runs the opener from a fresh `args.json` written from the
  re-rendered invocation.
- [ ] `dc_invocation` appends `--role <role>` after the positional, so the
  Goal reads
  `` Run `/shirabe:coordinate <roadmap-path> --role <role>` in <owner/repo>. ``
  and the `niwa dispatch` prompt carries the same invocation;
  `render-brief_test.sh` finds exactly one role line for each role.
- [ ] `dispatch-worker.sh` writes `.role` in `read_inputs`, beside the
  `reports_to` and `dispatcher_session` writes and before `resolve_grant`,
  overwriting the input: deleted for an entry point other than `coordinate`;
  the record's `role` row when the positional names this run's own roadmap;
  `manager` for any other roadmap on a new dispatch; and none on `--rebrief`
  of a held lane unless its input has `role_change`, so the invocation line
  carries no `--role`. Because `read_inputs` runs before the holding row is
  read, the `--rebrief` input jq settles these from the row's entry point:
  for `coordinate` it deletes `role` and sets `held_rerender: true`; for any
  other entry point (and in the `--releg` jq, which only a worker holding
  with a leg reaches) it deletes `role` and `role_change_by` and sets no
  `held_rerender`.
  `read_inputs` deletes `held_rerender` and `role_change_by` from every
  input, so a new-dispatch input that sets `held_rerender` renders `--role
  manager`. A `/work-on` re-brief and a `/deliver` re-brief render
  byte-identical to today's, each a case in `dispatch-worker_test.sh`. A
  successor dispatch with no row exits 1 and names the command that sets it.
  A case renders a `role_change: director` rebrief and then a plain rebrief
  of the same lane: both exit 0 and write a brief, and the second has no
  `--role` at all.
- [ ] `dispatch-worker_test.sh` points its successor input at the fixture
  run's own roadmap with a `director` row and gets `--role director`, and
  adds lane, worker (no field) and missing-row (exit 1) cases.
- [ ] A successor brief opens end to end: `coordinate-takeover_engine_test.sh`
  renders a successor brief with `dispatch-worker.sh` from a fixture
  predecessor recorded `director`, runs its opener line exactly as rendered
  (`--role director` and `--dispatched-by` naming the predecessor), and finds
  the takeover done and the successor's Run `role` row reading `director`.
- [ ] An input whose Goal says "you are the director", or that sets `role` to
  `director`, still renders `--role manager` for a lane.
- [ ] Citing PRD R5: `dispatch-worker.sh --rebrief` of a held coordinate
  lane whose input has `role_change: director` renders `--role director
  --role-change-by <address> --role-change-source dispatcher` on the
  re-rendered brief's invocation line, with `<address>` the dispatching
  session's own Run `coordinator` row, equal to the brief's `reports_to`; an
  input that also sets `role_change_by` or any other name still renders that
  address. `dispatch-worker.sh` carries it in the render field
  `role_change_by`, which it alone writes, and `dc_invocation` appends
  `--role-change-by <role_change_by> --role-change-source dispatcher` after
  `--role` when it's set. `render-brief.sh` refuses `role_change_by` at
  exit 1 without `role` and `held_rerender`, and on any other entry point,
  each a case in `render-brief_test.sh`. `role_change` is refused with exit 1 (the brief refusal), naming
  the field, writing no brief and launching nothing, on a new dispatch of a
  lane (a new lane starts as a manager), on a successor input (the
  positional names this run's own roadmap, and a predecessor isn't above its
  successor), with `--releg` (refused in `read_inputs` before the holding is
  read, since a coordinate holding has no leg and `--releg` exits 9 on one),
  on a worker entry point, and with a value other than `manager` or
  `director`. Each is a case in `dispatch-worker_test.sh`, the `--rebrief`
  case, the new-dispatch refusal and the `--releg` refusal among them, and
  `brief-template.md` documents the field and that only `--rebrief` carries
  it.
- [ ] The template's `rebrief` directive says a role change for the manager
  whose report the director is handling goes in as `role_change`, pinned by
  a rule-coverage row. A role change alone never sends a report to
  `rebrief`: the classification rules and the template's other routes into
  `rebrief` (question overflow, verify and land outcomes) are unchanged, and
  the directive says a change rides the manager's next report that takes one
  of those routes, or the director asks a person, whose hand-made start can
  make it, and that stopping the lane and dispatching a new one can't. The coordinate brief tells the started coordinator to
  fill `no-reports-to` with `<the dispatcher's name> at <reports_to>`. An
  end-to-end case feeds a `role_change: director` rebrief's invocation line
  to the opener on the fixture lane, whose `reports-to` row was written from
  its brief, and finds the change accepted and written.
- [ ] The worker golden files `testdata/brief-golden/base.txt`, `min.txt`
  and `leg.txt` are unchanged in the diff, and their tests pass.
- [ ] On a `coordinate` brief only, the review round line and the grant
  line say "commit" where worker briefs say "head", and the PRD's role-name
  grep, run exactly as the PRD writes it (only `HEAD` in capitals allowed),
  passes over a rendered lane fixture and a rendered successor fixture; the
  worker golden files are unchanged.
- [ ] `references/brief-template.md` documents the field (written by the
  script, never by hand, absent from worker briefs); its Goal text says the
  Goal names the concrete scope and work, makes no general statement of what
  a role owes, and names no role for the coordinator it starts, except that a
  manager's brief may name its director as its reviewer and a director's
  brief the managers it dispatched or reviews.
- [ ] `brief-template.md` and `SKILL.md` both say a dispatched coordinator's
  role comes from the `--role` on its brief's invocation line.
- [ ] The `references/entry-points.tsv` header comment and `render-brief.sh`'s
  header say where `--role` comes from; the `coordinate` row allows no flags.
- [ ] The reader allow-list test gains `dispatch-worker.sh` by function: the
  function that writes `.role` in `read_inputs` may read the row, and a
  fixture that adds a `state-read.sh --run` call or a `.key == "role"`
  filter to `resolve_grant`, or to any function it calls, fails the test.
  `dispatch-worker_test.sh` adds a case in which the same input with the
  fixture run recorded `manager` and then `director` produces a
  byte-identical grant (the `--role` and authority arguments passed to
  `niwa dispatch`).
- [ ] `coordinate.compat.json` re-records the gate-script digest with the
  fingerprint unchanged and compat at 2 (`dispatch-common.sh` is sourced by
  gate scripts, so the digest moves), and `check-template-compat.sh` passes.
- [ ] `skills/coordinate/evals/evals.json` gains scenarios for a director
  dispatching a lane, whose brief's invocation line carries `--role manager`,
  and for a successor started from its brief, which passes the `--role` the
  line names and infers none.
- [ ] This pull request passes the public-content check the Decomposition
  Strategy names, over its own added lines, commit messages, title and
  description (PRD R20).

**Dependencies**: Blocked by <<ISSUE:2>>

**Complexity**: testable

**Check**: Run `render-brief_test.sh`, `dispatch-worker_test.sh` and `coordinate-takeover_engine_test.sh`; each passes, the successor brief opening end to end, the worker golden files are unchanged in the diff, a plain `--rebrief` of a held lane exits 0 with a brief that carries no `--role` and the fresh-args-file sentence, and the `role_change` cases render and refuse as the criteria say. `scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md` passes. `scripts/check-skill.sh --changed coordinate` passes the shape check. The public-content check passes over this pull request.

**Files**: `skills/coordinate/scripts/render-brief.sh`, `skills/coordinate/scripts/dispatch-common.sh`, `skills/coordinate/scripts/dispatch-worker.sh`, `skills/coordinate/references/brief-template.md`, `skills/coordinate/references/entry-points.tsv`, `skills/coordinate/SKILL.md`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/scripts/testdata/rule-coverage.tsv`, `skills/coordinate/koto-templates/coordinate.compat.json`, `skills/coordinate/scripts/coordinate-takeover_engine_test.sh`, `skills/coordinate/evals/evals.json`

### Issue 5: fix(coordinate): don't link a progress event's pull request onto a coordinate holding

**Goal**: A progress event from a manager stops linking a pull request onto
its coordinate holding, so a director's count of its managers doesn't drift,
while a manager's report still links the pull request it sends up, as the
director's verify and land path needs. `report-facts.sh` makes the change:
it already tells a progress event from a report, and it is what sends a run
to `report_link`, where `holding-link.sh` writes the link, so
`holding-link.sh` itself is unchanged.

**Acceptance Criteria**:
- [ ] `report-facts.sh` on a progress event for a holding whose entry is
  `coordinate` and whose Pull request cell is empty gives `progress none
  <topic>`, never `link`, when the event names a pull request; the holding's
  record is byte-identical before and after.
- [ ] A report (not a progress event) on the same holding naming a pull
  request still gives `link`, as today, and a progress event on a worker
  holding still gives `link`. `report-facts_test.sh` adds all three cases.
- [ ] A round-trip case feeds a manager's progress event naming a pull
  request through `report_facts` on a coordinate holding and finds the run
  back at the hub without entering `report_link`; a second feeds that
  manager's ordinary report naming the pull request and finds it linked and
  the run reaching `verify`, so the change can't cut the report path.
- [ ] `coordinate.compat.json` re-records the gate-script digest with the
  fingerprint unchanged and compat at 2 (`report-facts.sh` runs behind the
  `report_facts` gate), and `check-template-compat.sh` passes.
- [ ] `skills/coordinate/evals/evals.json` gains a scenario in which a
  dispatched coordinator's progress event names a pull request on a coordinate
  holding with an empty Pull request cell: the run doesn't enter `report_link`
  and the holding stays as it was. The existing scenario for a report naming
  a pull request its holding lacks still grades as it does.
- [ ] This pull request passes the public-content check the Decomposition
  Strategy names, over its own added lines, commit messages, title and
  description (PRD R20).

**Dependencies**: None

**Complexity**: testable

**Check**: Run `report-facts_test.sh` and the round-trip cases; they pass, with a coordinate holding's progress event giving no `link` verdict, its report still linking and reaching `verify`, and worker holdings linking as before. `check-template-compat.sh` passes. `scripts/check-skill.sh --changed coordinate` passes the shape check. The public-content check passes over this pull request.

**Files**: `skills/coordinate/scripts/report-facts.sh`, `skills/coordinate/koto-templates/coordinate.compat.json`, `skills/coordinate/evals/evals.json`

### Issue 6: docs(coordinate): add the Glossary roles, the Roles section and the allowance paragraph

**Goal**: The skill defines manager and director in its Glossary, says what
each role owes in a `## Roles` section, and says in one role-blind paragraph
where the director's allocation allowances are read.

Overlaps shirabe#1470 on `SKILL.md` and `rule-coverage.tsv`; rebase onto it if it lands first; don't wait on it.

**Acceptance Criteria**:
- [ ] The Glossary's Coordinator entry keeps its pinned opening phrase and
  adds that it runs in either role; `- **Manager** --` and
  `- **Director** --` follow it directly with the design's definitions, and
  a `- **Workspace manager** --` entry names the tool and says it's never
  the role.
- [ ] `## Roles` sits between `## Glossary` and `## The Record`, opens with
  the sentence that a list says what you owe, never what you're allowed to
  do, and holds the design's Both roles, Manager and Director lists.
- [ ] Each list holds the design's items, and a rule-coverage row pins one
  phrase from each item, so a dropped or paraphrased item fails
  `rule-coverage_test.sh`: Both roles holds the design's three items ("Call
  yourself only by the role your record holds", "Report up to your
  reviewer", "Brief a successor with the role your record holds") and no
  fourth; Manager holds its five ("Run one lane", "Dispatch and brief the
  workers", "Review your workers' pull requests at your land step", "Send
  every pull request you author", "Report your lane's worker pull
  requests"); Director holds its six ("Dispatch and brief managers", "Be the
  reviewer of each manager you dispatched", "send your own reading up",
  "Read for alignment", "which of your lanes advance", "Be the owner
  funnel"). The owner-funnel item's sentence "Never block on the owner from a
  turn the owner didn't start" is carried as the design words it, with no
  added scope. A text check over `SKILL.md`'s `## Roles` section counts the
  items under each list heading and finds exactly three, five and six, so an
  added item fails as a dropped one does.
- [ ] The Manager list reports the lane's worker pull requests by link: each
  ready one in the verify report and the `Ready to merge` rows, and in the
  report owed after a land every one merged in the lane since the last
  report, whoever merged it.
- [ ] The Manager item "Send every pull request you author ... to your
  reviewer before it merges" uses "your reviewer" as the existing Glossary
  entry `**The reviewer** --` defines it (the dispatcher-review design's
  term). The item "Review your workers' pull requests at your land step" is
  the design's wording, in which the manager is its workers' reviewer, and
  doesn't contain "your reviewer". The Roles section adds no second
  definition of the reviewer.
- [ ] The Director's alignment item holds all three parts the PRD's
  acceptance criterion names, each pinned by rule-coverage rows of its own:
  its scope (the pull requests a manager authors and sends, and the worker
  pull requests each manager reports ready or landed in its lane), pinned by
  "the pull requests a manager authors and sends" and "worker pull requests
  each manager reports"; its purpose ("It isn't a correctness review", with
  correctness left to the worker's review round, the manager's land step and
  the manager's own checks); and its call-out ("name the pull requests and
  the conflict to every manager involved and in your next report"), pinned by
  "name the pull requests and the conflict" and "to every manager involved
  and in your next report". The item keeps each phrase on one line, so an
  item that tells only one manager, drops the pull requests, drops the
  conflict or leaves out the next report fails `rule-coverage_test.sh`.
- [ ] The alignment item ends with the PRD R10 sentence that whether the
  reading holds a land isn't set by the role, worded as "Whether your reading
  holds a land isn't set by your role: Bounds and Authority and the
  workspace's authority configuration say who merges." Rule-coverage rows pin
  "Whether your reading holds a land isn't set by your role" and "the
  workspace's authority configuration say who merges", each on one line, so
  an item that leaves this unsaid fails. Beyond that sentence the
  item states no answer either way, as the PRD's criterion requires. The
  requirements are the PRD's R10 (the alignment item and this sentence) and
  R14 (a role never reaches an allowance). Under them, the alignment reading
  and the push-back to every manager involved are the expectation this item
  holds, and the merge call is left to the authority configuration this
  sentence points to.
- [ ] No item in the three lists contains `grant`, `merge authority`,
  `may merge` or `settle`; the allocation item names no cap value; no added
  text says a director may change a cap.
- [ ] Bounds and Authority gains the "What you allocate is read, never
  assumed" paragraph after the cap paragraph, outside both lists, ending in
  the sentence that a cap change is escalated as a decision entry.
- [ ] The dispatcher-review own-reading paragraph gains the design's sentence
  about a pull request from a manager's lane, with its existing words
  unchanged in the diff.
- [ ] The template's start state lists `manager` and `director` among the
  Glossary's words and tells the session to read the Roles list for the role
  its record holds.
- [ ] `testdata/rule-coverage.tsv` gains rows for the new pinned phrases
  ("It isn't a correctness review" and "which of your lanes advance" among
  them), and `rule-coverage_test.sh` passes.
- [ ] Once the lists exist, `references/brief-template.md`'s Goal text (from
  Issue 4) gains the clause that the started coordinator reads its duties
  from the skill's list for its role, as the design's Decision 2 says, and a
  rule-coverage row pins it.
- [ ] `skills/coordinate/evals/evals.json` gains scenarios for the Roles lists,
  one each for Both roles, Manager and Director: a session calls itself only
  by its recorded role; a manager sends a pull request it authored to its
  reviewer and reports its lane's worker pull requests by link; a director
  reads a manager's reported pull requests for alignment, not correctness,
  and on a conflict names the pull requests and the conflict to every manager
  involved and in its next report, without treating its role as settling the
  merge.
- [ ] This pull request passes the public-content check the Decomposition
  Strategy names, over its own added lines, commit messages, title and
  description (PRD R20).

**Dependencies**: Blocked by <<ISSUE:3>>, <<ISSUE:4>>

**Complexity**: testable

**Check**: Run `rule-coverage_test.sh` and the `## Roles` item-count text check; both pass, `git grep -n "owner's" skills/coordinate/SKILL.md` finds nothing the Roles section added, and `brief-template.md` carries the duties clause. `scripts/check-skill.sh --changed coordinate` passes the shape check. The public-content check passes over this pull request.

**Files**: `skills/coordinate/SKILL.md`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/references/brief-template.md`, `skills/coordinate/scripts/testdata/rule-coverage.tsv`, `skills/coordinate/evals/evals.json`

### Issue 7: docs(coordinate): class every "coordinator" and readdress one-role duties

**Goal**: Every occurrence of "coordinator" in `SKILL.md`, the references and
the koto template is classed by the design's substitution test, each
one-role and positional site is rewritten, and the full table goes in the
implementation pull request's description.

Overlaps shirabe#1470 on `SKILL.md` and `rule-coverage.tsv`; rebase onto it if it lands first; don't wait on it.

**Acceptance Criteria**:
- [ ] The occurrence list comes from the design's `perl` command at the
  branch's base, and its row count equals `grep -oiwE 'coordinators?'` over
  the same three file sets.
- [ ] Each row is classed not a duty, either role or one role, and every row
  in the spot-check categories (dispatching a worker, landing a worker pull
  request, giving a milestone verdict, dispatching a coordinator, handing a
  successor a grant) carries a note giving the reason for its class.
- [ ] Each one-role site names the role that owes it. "Lane coordinator"
  becomes "manager"; the template's "A lane coordinator gets none" becomes "A
  manager you dispatch as a lane gets none", including where "A lane /
  coordinator" wraps a line; the dispatch table's "nested coordinator" row
  becomes a director's row; "a nested coordinator's reply" becomes "the reply
  of the coordinator you escalated to".
- [ ] One-role duties addressed to "you" without the word coordinator (for
  example "Your land step...") are read against the two lists, any that only
  one role owes is readdressed, and the pull request description lists each
  one read.
- [ ] The command is rerun after the last commit touching the three file
  sets; each class is carried forward by phrase, and every occurrence the
  change added (Glossary, Roles section, role setting text) is classed.
- [ ] The pull request description carries the table with columns File,
  Line, Phrase, Class and Note, line numbers stated as of the head commit.
  Working copies stay outside the work tree (never in the workflow staging
  directory), and nothing from the sweep is committed.
- [ ] The pinned dispatcher-review fragments (`never whether the review
  happens`, `once its review is done`, `your own reading`, `without the
  reviewer's review`, and the one `**The reviewer** --` entry) are unchanged
  in the diff.
- [ ] A `testdata/rule-coverage.tsv` row whose phrase changes is edited in
  place with a `changed:` note; no row is retired, and the row count doesn't
  drop.
- [ ] After the rewrite, a reviewer reads every match
  `grep -oiwE 'lead|top|head|parent'` prints over the three file sets and finds
  none used as a name for a coordinator's role, as the PRD's criterion requires.
- [ ] Every mention of the tool keeps "workspace" before "manager".
- [ ] Citing PRD R12: the final table has one row per occurrence that
  `grep -oiwE 'coordinators?'` counts over the three file sets at the head,
  and no row is classed one role.
- [ ] This pull request passes the public-content check the Decomposition
  Strategy names, over its own added lines, commit messages, title and
  description (PRD R20).

**Dependencies**: Blocked by <<ISSUE:2>>, <<ISSUE:3>>, <<ISSUE:4>>, <<ISSUE:6>>

**Complexity**: testable

**Check**: Count `grep -oiwE 'coordinators?'` over the three file sets at the head and find it equal to the final table's row count, with no row classed one role, then run `rule-coverage_test.sh` and `scripts/check-skill.sh coordinate`; both pass, and the positional-name grep finds nothing. The public-content check passes over this pull request.

**Files**: `skills/coordinate/SKILL.md`, `skills/coordinate/koto-templates/coordinate.md`

### Issue 8: chore(coordinate): check the compat digest and run the final checks

**Goal**: The template's compat record is checked against the changed gate
scripts, which each earlier issue that changed one re-recorded in its own
pull request, and every check the design names passes over the finished
change.

Overlaps shirabe#1470, #1473 and #1474 on `check-skill.tsv` and `coordinate.compat.json`; rebase onto them if they land first; don't wait on them.

**Acceptance Criteria**:
- [ ] `koto-templates/coordinate.compat.json` holds the gate-script digest of
  the finished scripts, re-recorded only if a later merge left it stale, with
  the fingerprint unchanged and compat at 2. `check-template-compat.sh`
  already derives the digest from the scripts rather than trusting the
  recorded value; a test that edits a gate script without re-recording fails
  it, and is added if none does today.
- [ ] `scripts/check-skill.sh coordinate`,
  `scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md`
  and `scripts/ablation/check-public-content.sh` each exit 0.
- [ ] The keep-alive sentence is found in the same files on main just before
  Issue 1 merged and at this issue's head. This pull request's own base already
  holds Issues 1 to 7, so it can't show this or the diff read below.
- [ ] The PRD's positional-name grep (`grep -niwE 'lane coordinators?|(top-level|top|lead|head|parent) (coordinators?|sessions?)|head of effort'`),
  plus "nested coordinator", finds nothing in the three file sets, per line and
  over each file squeezed by `tr -s '[:space:]' ' '`.
- [ ] This pull request passes the public-content check the Decomposition
  Strategy names, over its own added lines, commit messages, title and
  description (PRD R20).
- [ ] `posture-read.sh` and `niwa authority check --json` print
  byte-identical answers for a fixture run recorded `manager` and the same
  run recorded `director`, as a case in `posture-read_test.sh`. This is the
  PRD's R14 check (a role never reaches an allowance), and these two answers
  are the ones the design's Phase 6 names. A case in
  `coordinate-open_engine_test.sh` starts one run with `--role manager` and one
  with `--role director` on the same `--cap`, and finds the same cap recorded
  for each, as the PRD's criterion requires. The reader allow-list test from Issue 1
  keeps the row out of every other script's reach, and Issue 4's grant case
  covers `dispatch-worker.sh`, the one script that both reads the row and
  passes a grant.
- [ ] The owner funnel ships as list text only. At the head,
  `git grep -niE 'owner[ -]funnel'` under
  `skills/coordinate/` finds matches only in `SKILL.md` and
  `scripts/testdata/rule-coverage.tsv`: none in a script, a wording table, a
  koto template or `state-schema.jq`. The diff from main just before Issue 1
  merged through this issue's head adds no file under
  `skills/coordinate/scripts/` other than tests, no Run or Stored row other
  than `role`, and no koto state, gate or variable (the template's state and
  gate names are identical at those two points, and the compat fingerprint is
  unchanged).
- [ ] A text check over `SKILL.md` finds the Roles sentence that a list says
  what a role owes, never what it's allowed to do, and no Roles item that
  names a grant, merge authority, a settler or a cap.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:2>>, <<ISSUE:3>>, <<ISSUE:4>>, <<ISSUE:5>>, <<ISSUE:6>>, <<ISSUE:7>>

**Complexity**: testable

**Check**: Run `scripts/check-skill.sh coordinate`, `scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md`, `scripts/ablation/check-public-content.sh`, `posture-read_test.sh` and `coordinate-open_engine_test.sh`; each exits 0. The public-content check passes over this pull request.

**Files**: `skills/coordinate/koto-templates/coordinate.compat.json`, `skills/coordinate/check-skill.tsv`, `skills/coordinate/scripts/coordinate-open_engine_test.sh`

## Implementation Sequence

**Critical path:** Issue 1 -> Issue 2 -> Issue 3 -> Issue 6 -> Issue 7 -> Issue 8.

The row comes first because everything reads or writes it, and nothing
requires it until Issue 2, which turns on the seed's requirement, the
`record_open` change and the `no-role` gap together with the opener that
prints the role. Issues 3 and 4 each wait on Issue 2 and can then go in
either order: the record line has no role to print, and the opener refuses a
brief's `--role` as an unknown option, until Issue 2 lands. Issue 4 goes
right after Issue 2 all the same, since until it lands a lane a brief starts
stops at `ask=role`, and no lane is dispatched between the two. Each extends
the reader allow-list test with its own caller.
Issue 5 stands alone and can land at any point. The Roles text cites the
record line, so Issue 6 waits on Issue 3, and it adds the duties clause to
`brief-template.md`'s Goal text, so it waits on Issue 4. The sweep has to run over finished
text, so Issue 7 waits on every issue that writes skill prose (2, 3, 4 and
6) and regenerates its table after the last of them. Each issue that changes
a gate script re-records the compat digest in its own pull request; Issue 8
checks the digest and the whole change once the gate scripts are final, so
it goes last.

**Where each decision and follow-up lands:**

| Design decision or requirement | Issues |
|---|---|
| Decision 1: the flag, the row, its writers, the gap, the continuations | Issues 1 and 2 |
| Decision 2: the role on a brief's invocation line | Issue 4 |
| Decision 3: the record line | Issue 3 |
| Decision 4: Glossary entries, Roles lists, allowance paragraph | Issue 6, with Issue 5 for the holding link |
| Decision 5: the sweep of "coordinator" | Issue 7, checked in Issue 8 |
| Decision 6: a carried rotation's first report asks for its go-ahead | Issue 3 |
| Decision 1's asking rule: which role-less continuations ask and which go on (the Asking paragraph, the components table, Data Flow step 6) | Issue 2, its Role-less continuations table |
| Decision 1's gap: the reconcile directive's `no-role` fill | Issue 2 |
| Decision 1 and 2: a dispatched coordinator's role comes from its brief's `--role` | Issue 4, with Issue 6 for the brief's duties clause |
| PRD R5: a continuation keeps its role unless an intervention from above changes it, with who and when on the record | Issues 1 and 2, with Issue 4 for the brief's `role_change` |
| PRD R10: the alignment item's scope, purpose and call-out, and that whether the reading holds a land isn't set by the role | Issue 6 |
| The design's owner funnel as an expectation only, with no mechanism | Issue 6 (the item), Issue 8 (the check that nothing else ships) |
| PRD R14 and the design's Phase 6: a role never reaches an allowance | Issue 8, with Issue 1's reader allow-list |
| PRD R20: public content over each pull request's added lines, commit messages, title and description | Every issue, for its own pull request |
| PRD R14's criteria: the same cap for either role, and no added sentence tying a role to an allowance | Issue 8 (the cap), every issue for its own added sentences |
| PRD R13's criteria: the positional-name grep and the reviewer's read of its matches | Issue 8 (the grep), Issue 7 (the read) |
| The PRD's scenario changes under the repository's rule for a changed skill | Issues 2, 3, 4, 5 and 6, each for its own change |

**How the acceptance groups are shown.** The PRD has six acceptance groups.
Four of them (starting and recording, the successor
brief and first report, the Glossary and duties, and a lineage from before
the change) are shown by a reviewer's live run after Issue 8 lands, apart from
the criteria they state as issue-level checks: the renderer test (Issue 4), the
occurrence table (Issue 7) and the name grep (Issue 8), which those issues' own
checks show. The other two (allowances and the
dispatcher-review requirements, and checks and content) are shown by the
criteria and Check lines of Issues 4, 6, 7 and 8, and by each issue's check
over its own pull request, not by the live run. Each issue's criteria pin the
mechanism a group rests on; the criteria about report prose (a report names its role by
no other word, and a successor's reports carry none of the earlier names) are
checked only in that live run, since no script reads report prose.

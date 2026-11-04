---
schema: plan/v2
status: Active
execution_mode: multi-pr
split_mode_source: intent
split_rationale: |
  Hard Constraint. Step 5's land-check gate and the director's start read
  the Run role row, which arrives with the named-roles build that
  shirabe#1483 plans in its own pull requests and which hasn't merged, so
  the build can't land as one pull request with these documents. The
  documents merge first; each step then lands later in its own pull
  request, Steps 1 to 4 ahead of the named-roles build and Step 5 once it
  has landed.
tracking_level: none
upstream: docs/designs/DESIGN-director-alignment-review.md
milestone: "Director Alignment Review"
step_count: 6
---

# PLAN: Director Alignment Review

## Status

Active

## Scope Summary

A director on the coordinate skill gets an `alignment` entry kind that records
its call on a lane pull request at one head, a head-named `align-` hold that it
places in its own record and copies by message into the manager's, a guarded
lift that needs a new head and a later `fits` call, a land-check gate that asks
for a call when the Run `role` row reads `director`, and read-only scripts that
find a pull request's plan sources and list calls, merges and unreviewed
heads. Owner questions and relay checks run on the record's existing Decisions
entries, Work rows and Standing rows.

**Step 5 can't land before the named-roles build.** Step 5's gate and the
director's start read the Run `role` row, which arrives with the named-roles
build that shirabe#1483 plans and which isn't merged. Step 5's pull request,
and Step 6's after it, wait for that build to land first; Steps 1 to 4 read no
role and don't wait. Until it lands, no session knows it is a director.

## Decomposition Strategy

Walking skeleton. Step 1 runs one `diverges` call on a planted pull request
head in a scratch director record, carries the printed hold message into a
scratch manager record with `alignment-call.sh --copy --add`, and shows the
manager's existing land check reporting the pull request held. That path
crosses the design's one cross-record seam, the message between two records,
so it runs first. Step 2 adds the guarded lift on both sides. The later steps
add the reads, the source finder, the land-check gate with the skill text that
explains it, and owner questions and relays, each on top of a hold path that
already works.

None of the build lands with this plan. The PRD, the design and this plan
merge first, and each step lands later in its own pull request, after the
steps it depends on. Steps 1 to 4 can land before the named-roles build;
Step 5's pull request waits for it.

That regroups the design's Implementation Approach in two places, and each
keeps what the design's phase order protects. Step 1 carries the design's
Phase 1 (the entry kind) together with the hold half of Phase 2, so the
first pull request crosses the cross-record seam instead of adding an entry
kind nothing reads; Step 2 adds the lift. And the design's Phase 4 becomes
two pull requests: Step 5 ships the land-check gate with the skill text and
template changes that tell a director to record calls, as the design
requires, so no director meets a gate its skill doesn't explain. Step 6
carries the owner funnel, owner questions and relays in a later pull
request; that text explains nothing about the gate and needs no gate to
work, so splitting it off costs the design's rule nothing.

## Steps

### Step 1: A director's diverges call holds the pull request in the manager's land check

**Goal**: A director's `diverges` call on a lane pull request now stops the manager from landing it. The step crosses the whole path on one planted pull request head in scratch records: the director's call entry, the `align-` hold in the director's record, the printed hold message, the manager's copy (`alignment-call.sh --copy --add`), and the manager's existing land check.

**Acceptance Criteria**:

- [ ] `state-entry.sh --kind alignment --on <owner/repo#n>` refuses a malformed alignment text (a missing, extra or reordered line, a head that isn't 40 hex, or `diverges` with Sources `none`) with exit 65 and writes nothing to the record; a well-formed seven-line text is written and stays in the session.
- [ ] The third `--on` mode, for `alignment` only: an alignment entry whose first line names a pull request other than `--on` is refused with exit 65 and nothing written; one whose `--on` pull request is in neither the host nor a holding's repository is refused by `on_admitted` with exit 65; `--on none` with `--kind alignment` is refused with exit 65.
- [ ] On a public host, an alignment entry written with `--on` still gets the host-visibility scan: one naming a private repository as `owner/repo#n` is refused with exit 65 and nothing written.
- [ ] An alignment entry is never posted: with the `--on` repository opted in to workflow content (`## PR Workflow Content: include`), the stand-in `gh` sees no comment POST, no `record/posted/<n>` key is written, and the script prints the entry's `record/entries/<n>` key.
- [ ] The existing case in `state-entry-on_test.sh` that refuses `--on` with a kind that stays in the session (exit 64) passes unedited, and a new case shows `--kind entry --on owner/repo#n` still exits 64.
- [ ] `alignment-call.sh` with a `diverges` call on a pull request with no director hold standing writes the call entry, adds a hold named `align-<repo name>-<n>-<40-hex placed-on head>` to the director's record with `until` `lifted`, and prints a message holding the pull request, the hold row, the reason, the receiver and the release.
- [ ] A manager's Run `reports-to` row reads `director at <address>`. A hold message from a successor director is refused until the manager has rewritten that row: at a `director-hold` event whose message names the row's current address and the sender's new one, `alignment-call.sh --copy --reports-to` with `--from` the new address rewrites the row through `state-stored-set.sh --run reports-to` with `--by` the sender and writes a `hold` entry naming the event and both addresses, and the same hold message is then accepted. A message naming any other current address, and one sent to a row holding no address, change nothing and exit non-zero saying so (R7, R9).
- [ ] Passing that printed message to `alignment-call.sh --copy --add --message-file <the message> --event <n> --from <the director's address>` in a scratch manager record whose dispatcher is the director adds the identical hold row to the manager's record and writes a `hold` entry naming event `<n>`. The test passes the event number and the sender as arguments; the `director-hold` wait event that supplies them in a live run lands in Step 5.
- [ ] `alignment-call.sh --copy --add` refuses a message whose `--from` isn't the dispatcher address the manager's record names: it exits non-zero, says so, and leaves the manager's Holds section and entries unchanged. It refuses a malformed message the same way: a hold name not of the `align-` form, or a head that isn't 40 hex.
- [ ] The scratch manager record passes `land-check.sh`'s earlier checks, as `land-check_test.sh`'s fixtures do: a verify capture for the planted head, a worker review round of three passing seats at that head, a fresh reviewed head, a body that passes the body checks and a squash message that builds. On it, `land-check.sh` reports `held <pr> <sha>`, and coord/land.json's `holds` lists the `align-` hold with state `unmet`.
- [ ] A second `diverges` call on the same pull request while the director's hold still stands writes its entry but places no second hold; the director's record still holds exactly one `align-` row.
- [ ] A `diverges` call on a merged pull request is written as an entry but places no hold, and no `align-` row is added to the director's record.
- [ ] `state-entry.sh`'s list of entry kinds gains exactly one value, `alignment`, and every existing kind's check is unchanged: `state-entry_test.sh` and `state-entry-on_test.sh` pass with no existing case edited.
- [ ] `state-entry.sh` is among the scripts the template's gates and actions reach, so the step records the new `gate_scripts` digest in `coordinate.compat.json` at the current compat (`scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md --print`), and `check-template-compat.sh --base-table <base table>` passes as the `check-template-compat` job runs it.

**Check**: Run `alignment-call_test.sh`. It creates a scratch director record and a scratch manager record whose dispatcher is the director, then plants one pull request head, with the manager record's verify capture, review round, fresh head, body and message set up as `land-check_test.sh`'s fixtures set them. It runs `alignment-call.sh` with `diverges` in the director record and checks the entry and the `align-` hold row named after that head. It passes the printed message to `alignment-call.sh --copy --add` in the manager record with an event number and the director's address as arguments, and then runs `land-check.sh` on the manager record: the token is `held <pr> <sha>` and coord/land.json's `holds` lists the `align-` hold as `unmet`. The test also feeds `state-entry.sh` a malformed alignment line and sees exit 65 with the record unchanged, sends the copy from a wrong sender and sees the refusal, sends a successor's address message and sees the `reports-to` row rewritten and the successor's hold message accepted, sends one naming the wrong current address and sees nothing change, repeats the `diverges` call and sees one hold, and calls `diverges` on a merged pull request and sees an entry and no hold. Then run `state-entry_test.sh` (with a case for every refusal `alignment_check` makes), `state-entry-on_test.sh` (with the new cases for the alignment `--on` mode: the first-line mismatch, `on_admitted`, `--on none`, the public-host scan, no post on an opted-in repository, and `--kind entry --on` still 64), `land-check_test.sh`, `check-template-compat.sh` against the base's table and `scripts/check-skill.sh --changed coordinate`. Every case passes.

**Dependencies**: None

**Files**: `skills/coordinate/scripts/state-entry.sh`, `skills/coordinate/scripts/state-entry_test.sh`, `skills/coordinate/scripts/state-entry-on_test.sh`, `skills/coordinate/scripts/alignment-call.sh`, `skills/coordinate/scripts/alignment-call_test.sh`, `skills/coordinate/references/state-keys.md`, `skills/coordinate/koto-templates/coordinate.compat.json`

### Step 2: The hold lifts only after a new head and a later fits call

**Goal**: A held pull request is released only by a new live head that the director has re-read and called `fits` or `fits with follow-ups`, and the manager's copy lifts only at its own verified head. The director's guarded lift runs in the same writer run as the call, and `alignment-call.sh --lift-releasable` runs the same guard later without a new call; the manager's `alignment-call.sh --copy --lift` accepts the lift message only from the dispatcher address its record names, and the message names the hold, the head it was released on and the entry number of the `fits` call it rests on.

**Acceptance Criteria**:

- [ ] After the fixture pull request moves to a new head and the director records `fits` (or `fits with follow-ups`) on it, `alignment-call.sh` lifts the `align-` hold in the director's record, the Lifted cell reads `<minute> by director at <address>, <fits|fits with follow-ups> at <40-hex head>`, and it prints a lift message naming the hold, the head it was released on and that `fits` call's entry number.
- [ ] Feeding that printed message to `alignment-call.sh --copy --lift --message-file <the message> --event <n> --from <the director's address>` in the manager's record, whose holding for the pull request has the new head as its `verified_head`, lifts the manager's copy at once, and `land-check.sh` then reports a posture token (`permit`, `deny` or `confirm`) for the pull request instead of `held`.
- [ ] `alignment-call.sh --lift-releasable --on <owner/repo#n>` on a director record whose `align-` hold is releasable (the live head isn't the placed-on head, and the latest call for it is a `fits` call above the hold's `diverges` call) lifts the hold with the same Lifted text, writes no `alignment` entry, and prints a lift message naming the hold, the head it was released on and that `fits` call's entry number. On a hold that isn't releasable it lifts nothing and prints nothing, and when the live head can't be read it exits with the guarded lift's own code naming the hold, which stays standing.
- [ ] The manager's `hold` entry for the lift records both the hold name and the fits call's entry number, so a lift with no matching call shows in the manager's own record.
- [ ] A `fits` call recorded while the live head is still the placed-on head lifts nothing: the director's hold stays standing and no lift message prints.
- [ ] When the live head can't be read from GitHub, the director's lift is blocked: the call is still written, the script exits with its own code naming the hold, and the hold stays standing (fail closed).
- [ ] In the manager's record, a `--copy --lift` at the placed-on head, a replayed lift naming an older head than the holding's `verified_head`, and a lift whose `--from` isn't the dispatcher address the record names are each refused with a message saying why, and the hold still makes `land-check.sh` report `held <pr> <sha>`.
- [ ] On a manager-authored pull request, which has no holding in the manager's record, `--copy --lift` checks the head it names against the pull request's live head from GitHub instead of a `verified_head`: a lift at the live head that isn't the placed-on head lifts the copy, a lift at any other head is refused, and when the live head can't be read it exits non-zero and the hold stands (R8, R9).
- [ ] A person's lift on an unchanged head doesn't go through `--copy --lift`: the director records it with `state-hold.sh --lift`, its Lifted cell naming the person, and the manager records the relayed word on its copy with `state-hold.sh --lift` as the template's `surface` text already says. `land-check.sh` then reports a posture token instead of `held`, at the placed-on head (R9).
- [ ] Read from the records alone, every hold and lift the step writes names who decided it (the director and its address in the Set by and Lifted cells) and what it decided on (the pull request, the placed-on head in the hold's name, the head it was released on and the `fits` call's entry number), and the step adds no field for koto's decision record.

**Check**: Run `alignment-call_test.sh` with this step's cases. It places a hold with a `diverges` call (as step 1 does) and copies it into the manager's record. It then asserts that a `fits` call at the same head lifts nothing, moves the fixture pull request to a new head, records `fits`, and checks the director's Lifted cell and the printed lift message. It feeds that message to `alignment-call.sh --copy --lift` in the manager's record, with an event number and the director's address as arguments and the holding's `verified_head` at the new head, and checks that `land-check.sh` reports `permit`, `deny` or `confirm` and that the `hold` entry carries the hold name, the call's entry number and the event number. It then repeats the lift against fresh copies of the held record at the placed-on head, with a replayed lift naming an older head, and from a non-dispatcher sender, and checks each is refused with `land-check.sh` still reporting `held`. It makes the live-head read fail and checks the lift is blocked with the hold standing; it then restores the read and runs `alignment-call.sh --lift-releasable --on` on that record, and sees the hold lifted, no new `alignment` entry and the lift message printed, and runs it again on a record whose hold isn't releasable and sees nothing lifted. It lifts a manager-authored pull request's copy, with no holding, at the live head and sees it refused at any other head and when the live head can't be read. It records a person's lift at the placed-on head with `state-hold.sh --lift` on both sides and sees `land-check.sh` report a posture token. Finally it reads the director's hold row and Lifted cell and the manager's `hold` entries and finds the decider, the pull request, both heads and the call's entry number in them, with the Holds grammar unchanged.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/alignment-call.sh`, `skills/coordinate/scripts/alignment-call_test.sh`, `skills/coordinate/references/state-keys.md`

### Step 3: Every call, merge and hold can be listed, with unreviewed heads marked

**Goal**: One read-only script, `alignment-read.sh --session S [--since <stamp>]`, lists what the director's run recorded and what merged in its lanes, from the director's own entries, its own Holdings rows, its own `wait` events and GitHub. It prints `{calls, merges, recommendations, holds, open, refusals, gaps}` as the design's Key Interfaces section gives them. This is the one read R11 names, and the director's start reads it in Step 5.

**Acceptance Criteria**:

- [ ] On a planted director record, `alignment-read.sh --session S` prints one JSON object with exactly the keys `calls`, `merges`, `recommendations`, `holds`, `open`, `refusals` and `gaps`, and exits 0.
- [ ] `open` lists every open lane pull request with `pull_request`, its live `head` and `call`, the standing call's value for that head or `none`. After a new push with no call yet, the pull request is listed at the new head with `call` `none`, held or not, and an older head's call doesn't stand for it (R5, R11). `--since` leaves `open` whole.
- [ ] `calls` lists every `alignment` entry oldest first, each with `entry`, `stamp`, `pull_request`, `head`, `call`, `read`, `sources`, `reason`, `evidence`, `follow_ups`, `action` and `standing`, with `sources`, `evidence` and `follow_ups` as arrays split on `; `. Two calls on the same pull request and head are both listed, and only the later one has `standing` true; a call on an older head of that pull request is never marked standing for a newer head.
- [ ] The lane pull request set is every pull request a call names, every pull request linked in the director's own Holdings rows, and every pull request a `report` or `progress` event the director's runs submitted names, as the event's pull request, as a link in its message, or in a `unit=` or `open=` line of its result block. A merged pull request found only through a `progress` event's message link is listed.
- [ ] A unit counts as finished only when a report's result block carries `unit=<topic> <done|reopened|dropped> <owner/repo#n>` for it, and a lane pull request counts as open in a manager's report only through an `open=<owner/repo#n>` line. A planted report whose text says a unit is done, with no `unit=` line, finishes nothing, and a malformed `unit=` line (a status outside the three, or a pull request not in `owner/repo#n` form) finishes nothing either.
- [ ] A pull request is manager-authored when no report's `worker=` line names it and either it was the `pull_request` of a `report` or `progress` event whose `unit` is a holding's topic, or a director Holdings row's `verified_head` equals GitHub's merged head. A manager-authored pull request merged with no call, whose Holdings row's Pull request cell is already empty (as `merge_confirm` and `merged_facts` leave it), is listed `unreviewed`.
- [ ] Each merged lane pull request owed a call (a manager-authored one, or a finished unit's final head: a `unit=` line names its unit done, reopened or dropped at it, it is a milestone verdict pull request, or GitHub shows it changes a roadmap or strategy document) is listed with `pull_request`, `merged_head`, `merged_at`, `call` (the latest call's value for the merged head, or `none`) and `review`: `reviewed` when a call for its merged head was stamped before the merge, `after merge` when the first call for that head was stamped after it, and `unreviewed` when none exists.
- [ ] A worker pull request its manager reported landing short of a finished unit, named by a `worker=` line, with no call before it merged, is listed with `review` `manager-reviewed` and is never `unreviewed`, including when an event's `pull_request` under a holding's topic names it or a director Holdings row's `verified_head` equals its merged head. The same pull request with no `worker=` line is listed `unreviewed` (R10).
- [ ] `recommendations` lists each call whose Action is `recommend`, with that call.
- [ ] `holds` lists each `align-` hold with the reason from the `diverges` call its name points to and a state: `lifted` when its Lifted cell is filled; otherwise `merged while held`, `closed while held`, `releasable` when the guarded lift's three conditions hold, or `standing`, flagged `needs re-read` when the live head has no call. Each standing hold carries the latest manager report that named it, or shows as unconfirmed when none did.
- [ ] `refusals` counts the gate's refusal entries stamped since `--since`, or all of them without it. A refusal is an `entry`-kind entry whose first line is `Refused: no-alignment-call <owner/repo#n> at <40-hex head>`, as the design's Decision 2 gives it and `references/state-keys.md` documents in this step; Step 5's `align_call` state writes it.
- [ ] With `--since <stamp>`, `calls`, `merges`, `recommendations` and `refusals` cover only what is stamped or merged after the stamp, and `holds` stay whole. A merge after the stamp whose only call for its merged head was stamped before the stamp is still `reviewed`: each merge's review is judged against every call of the run, not only the calls the window lists.
- [ ] An earlier session of the director's lineage whose log can't be read is listed in `gaps` by name, and the read still exits 0 with everything it could read.
- [ ] The read writes nothing: the director's record is byte-identical before and after every case.
- [ ] A script outside the coordinate skill reads every call's five fields with `jq` alone, with no free-text matching (R16).

**Check**: Run `alignment-read_test.sh`. It plants a director record with `alignment` entries (two calls on one head, one on an older head, and calls on both sides of a stamp), Holdings rows linking two manager-authored pull requests and a third row whose Pull request cell is already cleared with its `verified_head` kept, `report` and `progress` events naming worker pull requests (one only as a message link) whose result blocks carry `unit=` and `open=` lines (one report saying a unit is done in its text with no `unit=` line, and one with a malformed `unit=` line), a worker pull request carried as an event's `pull_request` with a `worker=` line and the same with none, a worker pull request named by a `worker=` line whose merged head a director Holdings row's `verified_head` equals, a `report` event whose `pull_request` is the manager's own pull request, refusal entries on both sides of a stamp, and `align-` holds in each state, and runs the read against a stand-in `gh` that answers each pull request's state, merge time, merged head, live head and changed files. It checks each field and status above, an open pull request at a new head with `call` `none` included, runs once with `--since` and once without (with a merge after the stamp whose call came before it), makes one lineage session's log unreadable and finds it in `gaps`, compares the record's bytes before and after, and reads the calls with a `jq` filter kept outside the skill. Then run `scripts/check-skill.sh --changed coordinate`. Every case passes.

**Dependencies**: Step 2

**Files**: `skills/coordinate/scripts/alignment-read.sh`, `skills/coordinate/scripts/alignment-read_test.sh`, `skills/coordinate/references/state-keys.md`

### Step 4: The director finds what a pull request touches and its call cites it

**Goal**: A read-only helper, `alignment-sources.sh`, does the mechanical half of finding a lane pull request's plan sources and prints them as JSON: the unit, that unit's roadmap clauses and milestone Evidence read from the roadmap on the default branch at a named commit (with the roadmap reader `pick-facts.sh` already uses, unchanged), the strategy path the roadmap names, the changed files, the other lanes' open work, the full-read triggers it found and the candidate owner decisions. Which candidates' scope covers the pull request stays the director's judgment, in Step 5's skill text.

**Acceptance Criteria**:

- [ ] On a planted roadmap, strategy and director record with two lanes, `alignment-sources.sh --session S --on <owner/repo#n> [--unit <roadmap unit>]` prints one JSON object with the keys `unit`, `clauses`, `evidence`, `commit`, `strategy`, `changed_files`, `other_lanes`, `triggers` and `candidates`. `unit` is `--unit` when given, otherwise the roadmap unit the Holdings row of the pull request's lane names; with neither, `unit` is `none`, `clauses` and `evidence` are empty, and the director names the unit from its own reading and runs it again. The helper prints the pull request's unit, each of its roadmap clauses and its milestone's Evidence clauses by number with the 40-hex commit they were read at, and the strategy path from the roadmap's `upstream:`; with no `upstream:`, the strategy is `none`.
- [ ] The other lanes' open work lists, for each Holdings row other than the pull request's own lane, the open pull requests the `open=<owner/repo#n>` lines of its manager's latest `report` or `progress` event name (with their changed files from GitHub) and the documents, paths and roadmap units its Holdings and Work rows name. A pull request that report names only in its text, with no `open=` line, isn't listed. The pull request's own lane is never listed.
- [ ] Triggers: a pull request that a report's `unit=` line names as finishing its unit done, reopened or dropped, or that is a milestone verdict pull request, or that changes a roadmap or strategy document, gets a trigger whose reason names that condition. One that changes a file another lane's open pull request also changes, or a document, path or roadmap unit another lane's rows name, gets an `other-lane` trigger naming the lane and the matching open work. A pull request with none of these gets no trigger.
- [ ] Candidate owner decisions are every Standing row and settled decision whose On or text names the unit or a changed path; a Standing row that names neither isn't listed.
- [ ] When a source it needs can't be read (the roadmap, the milestone's Evidence, the strategy or the record's owner decisions), the helper exits non-zero naming that source, prints no partial result on stdout, and writes nothing.
- [ ] A milestone verdict pull request's output lists every Evidence clause of its milestone by number, and a call written with `alignment-call.sh` whose Evidence line gives each of those numbers `met` or `not met` and whose Sources name the roadmap clause at that commit passes `alignment_check` (R6).
- [ ] An `other-lane` trigger's lane and open work, written into a call's Sources as `lane <holding> <owner/repo#n | path>`, pass `alignment_check`.
- [ ] The helper writes nothing: the director's record is byte-identical before and after every case.

**Check**: Run `alignment-sources_test.sh`. It builds a scratch git repository holding a planted roadmap (with and without `upstream:`) and strategy, a director record with two lane Holdings rows, Work rows naming a document and a path, Standing rows and a settled decision, `report` and `progress` events from each lane's manager whose result blocks carry `unit=` and `open=` lines (the other lane's latest naming one open pull request in an `open=` line and another only in its text), and a stand-in `gh` that answers each pull request's changed files. It runs the helper on a pull request for each trigger, one with no trigger, a milestone verdict pull request, one given `--unit`, and one whose lane names no unit, and checks every field above; it writes the calls from the verdict and `other-lane` outputs with `alignment-call.sh` and sees them accepted; it makes each source unreadable in turn and sees the exit name it with nothing on stdout; and it compares the record's bytes before and after. Then run `pick-facts_test.sh` unchanged and `scripts/check-skill.sh --changed coordinate`. Every case passes.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/alignment-sources.sh`, `skills/coordinate/scripts/alignment-sources_test.sh`

### Step 5: A director can't merge or recommend a head with no alignment call

**Goal**: The land check requires a standing call when the session is a director, and it ships with everything that tells a director and a manager what to do about it: the director's alignment section in the skill (the triage line stated once, the call, the hold and its release), the director's start reading `alignment-read.sh --since` and lifting releasable holds, the `align_call` state that records each refusal and the missing call, the manager's `director-hold` wait event and `director_hold` state that record a director's hold and lift messages as they arrive, the manager's `unit=` and `open=` report lines, and the manager's hold duty in its reports. The gate and the text land in one pull request, so no director meets a gate its skill doesn't explain. It reads the Run `role` row, so it needs the named-roles build that shirabe#1483 plans.

**Acceptance Criteria**:

- [ ] With the Run `role` row reading `director`, `land-check.sh` reports `uncalled <pr> <sha>` for a pull request whose pinned head has no standing call, or whose standing call for that head is `diverges`, or whose only call is for another head; with a standing `fits` or `fits with follow-ups` call for the pinned head it reports the posture token (`permit`, `deny` or `confirm`) it reports today.
- [ ] The call check runs after the hold read and before the posture: a director pull request with a `diverges` call and its standing `align-` hold reports `held <pr> <sha>`, not `uncalled`, and no refusal entry is written for it.
- [ ] `coord-verdict.sh` maps `uncalled` to exit 86, `coord-verdict-table_test.sh` pins it against the template's arm, and the `land` state routes exit 86 to a new director agent state, `align_call`, never to `rebrief`.
- [ ] A record with no Run `role` row gets no gate: `land-check.sh` reports what it reports today, and `land-check_test.sh` passes with no existing case edited, since its fixtures carry no `role` row. A new case with the row reading `manager` reports the same tokens. A `role` row that can't be read makes `land-check.sh` report `unready <pr> <sha>` with reason `role-unreadable`, in a case of its own.
- [ ] At `align_call` the director writes one refusal entry, in the `Refused:` line Step 3 documents, per pull request and head the gate stops: when the record already holds that line for the head, a later visit that refuses again writes nothing, and a new head stopped later writes one more. It then runs `alignment-sources.sh` and `alignment-call.sh` and goes back to `land`; when a source can't be read it records no call, names the source in its report and goes back to `wait`. `land-check.sh` itself stays read-only.
- [ ] The named-roles reader allow-list test in `coordinate-template-structure_engine_test.sh` gains `land-check.sh`, by the one function that reads the Run `role` row. The director's start reads its role from the record line its first report prints, which that test already lists, so it adds no other reader, and a fixture that adds a role read to `alignment-read.sh`, `alignment-call.sh` or `alignment-sources.sh` fails the test.
- [ ] At each director start (a new run, a resume, a takeover and a successor's first run) the start runs `alignment-read.sh --since` the time the latest `Director start: <stamp>` entry names, or since each lane was dispatched when the record holds none, and its report names each unreviewed merge with its pull request and head, each standing hold (a closed one as closed while held), each releasable hold, which the start lifts with `alignment-call.sh --lift-releasable --on <owner/repo#n>` and whose lift message it sends the manager, the refusal count, and each lineage gap with the ask it sent each manager. After the report it writes an `entry` whose first line is `Director start: <YYYY-MM-DDTHH:MM:SSZ>`, the time of that read, which `references/state-keys.md` documents. A successor's first start reads its predecessor's latest such entry from the carried record.
- [ ] A director without the merge grant that calls a manager-authored pull request `fits` doesn't merge it and sends the call and its own reading to its reviewer; the merge the grant holder makes is at the head the call names (R17).
- [ ] The manager's `wait` hub gains a `director-hold` event with evidence fields `message` (the whole text), `from` (the sender as the arriving message names it, supplied by the agent) and `unit`, whose edge goes to a new manager agent state, `director_hold`. There the manager runs `alignment-call.sh --copy --add` for a hold message, `--copy --lift` for a lift message and `--copy --reports-to` for a new director's address, with `--message-file` holding `message`, `--event` the event's log sequence and `--from` the evidence's `from`. The event's `unit` evidence names the holding's Worker topic, empty when no holding links the pull request, and `wait`'s edge writes it to `report_topic` as a report's does. `director_hold` then takes one of three edges: `rework` to `rebrief` after a hold on a pull request with a holding, so the work goes back to that worker; `reverify` to `verify` after a lift on one, so its land check runs again with no fresh worker report; and `wait` otherwise. A lift is applied there, against the holding's `verified_head`, and never deferred to the land step. While the copy stands, its land check reports `held`, the merge step refuses it, and no message asks another session to land it (R8, R9).
- [ ] Before the `reverify` edge, a holding at Phase `held` is rewritten to the Phase its entry point and mode give, `scoping` or `executing`. After that edge, `board-record.sh` reads the pull request from the holding `report_topic` names rather than `report_facts`' capture, and `state-confirm.sh --verified` reads that holding's unit through `lib_unit`, which counts a `director-hold` event with a non-empty `unit` as an arrival. `alignment_engine_test.sh` plants a newer report from another worker before the lift and finds the board read, the Verified head and the land check on the lifted pull request, and the progress view no longer reading the holding as held. `board-record_test.sh` and `state-confirm_test.sh` cover the two reads, and a report with no `director_hold` entry still reads as it did (R8, R9).
- [ ] A recommendation that doesn't pass through a director's `land` is checked by `alignment-call.sh --require --on <owner/repo#n>`, which reads and writes nothing else and exits 0 only when a standing `fits` or `fits with follow-ups` call exists for the pull request's live head. It exits non-zero naming the head otherwise, and when the live head can't be read. The directives for the three such paths run it first and, on non-zero, write the refusal line once per pull request and head, run `alignment-sources.sh` and `alignment-call.sh` in place and run `--require` again; none goes to `align_call`, and none adds an edge. A pull request still refused leaves by its state's existing edge, naming what stopped it. A director checks a worker pull request a manager sends up ready at `classify_report`, before it submits `classification: done` or `blocked` for that report: `classify_report`'s directive says so, and `surface`'s need kinds and `need-check.sh` don't change. Passing, `blocked` goes to `surface`, which submits `surfaced: blocker` with `need: reserved-step merge <link>`, and `surface_check` accepts it and goes on to `wait`. Still refused, the director submits `classification: needs_fix`, and `rebrief` tells the manager what stopped it and to report again once that's changed. A milestone verdict pull request is checked at `milestone_verdict` once it's open and before `verdict: recorded`, and leaves with `verdict: deferred`; a `landed` tick brings the run back through `roadmap_status` to `milestone_verdict`, which checks the same pull request and writes no second entry. A roadmap edit the template sends to the reviewer directly is checked at `roadmap_status` before it's handed to whoever merges, and submits `status: opened` with the edit not handed, which the record step confirms from the Side effects row. The template has no state of its own for a strategy edit, so a strategy pull request is checked at `classify_report` or `land`, as any lane pull request is (R5, R6).
- [ ] The director's section says a call is an alignment reading, and that the director doesn't review for correctness, launch correctness reviewers or repeat the worker's review (R1). A rule-coverage row pins it, and in the engine walk no review seat is dispatched for a call.
- [ ] A `fits with follow-ups` call's follow-ups each appear in the director's next report as a filed issue or a proposed issue, and the section says so (R4).
- [ ] `render-result.sh` takes repeatable `--unit '<topic> <done|reopened|dropped> <owner/repo#n>'`, `--open <owner/repo#n>` and `--worker <owner/repo#n>` and prints them as `unit=`, `open=` and `worker=` lines inside its result block, refuses a malformed value with exit 64, and prints the block as it does today when neither is given. The manager's expectation text in `SKILL.md`, and its report path, say it runs `render-result.sh` with those arguments for every report it sends its director, naming each unit it finished since its last report and each open lane pull request.
- [ ] Every manager report from the first after a hold was placed until it lifts names the held pull request, the reason, the director as the one it waits on, and the release (R8). A director report that finds a standing hold missing from the manager's latest report re-sends the hold message.
- [ ] `SKILL.md`'s director section states the triage line once: a search of the skill and its references finds that line's text in exactly one place, and its conditions are the ones `alignment-sources.sh` names in its trigger reasons plus R3's fourth, which no script decides: the director found a recorded owner decision among its plan sources. The section also names `alignment-sources.sh`, `alignment-call.sh` (with `--lift-releasable`) and `alignment-read.sh` and when each runs, and says a person's lift is relayed to the other record.
- [ ] Every sentence the feature adds that contains "grant", "level", "authority" or "role" is listed in the pull request body, and none of them says a call, a hold or a role gives, needs or changes a grant, a level, an authority or a role (R17, R18).
- [ ] Across the feature, `ENTRY_KINDS` in `state-entry.sh` gains exactly one value, `alignment`, no record section is added, and every kind grammar section of `references/state-keys.md` that exists at the base (the verdict entry, goal-fit entry and failure entry sections under Milestone Verdicts among them) is byte-identical to the base before Step 1 (R15).
- [ ] `skills/coordinate/evals/evals.json` gains scenarios for a director that holds a `diverges` pull request and lifts it on a new `fits` head, a director land step stopped by `uncalled`, and a manager that names a standing hold in its report and sends the work back to its worker, each tier-2 one naming its behaviour with exactly one `"release": true` per behaviour, and the existing scenarios, which start no director, still grade the behaviour they did. `scripts/check-skill.sh --changed coordinate` passes the shape check.
- [ ] The changed template structure (the `director-hold` event and its `message`, `from` and `unit` evidence fields, the `director_hold` and `align_call` states and the exit 86 arm) is listed in `coordinate.compat.json` at a compat number above the base's, with the `gate_scripts` digest `check-template-compat.sh --print` gives, and `check-template-compat.sh --base-table <base table>` passes. `coordinate.mermaid.md` matches the template and `scripts/validate-template-mermaid.sh` passes.

**Check**: Run `land-check_test.sh` with new cases for no `role` row, the row reading `manager`, the row reading `director` with each call state above (a held `diverges` pull request among them), and an unreadable row; `coord-verdict-table_test.sh`; `render-result_engine_test.sh` with cases for `--unit`, `--open`, `--worker`, a malformed value and none of them; and `coordinate-template-structure_engine_test.sh` with the allow-list fixtures above. Then run a new `alignment_engine_test.sh` that compiles the template, runs a director and a manager session against a stand-in `gh` and stand-in niwa, and walks: a recommended pull request with no plan source, whose call has Sources `none`, `fits` and a one-line reason; one that changes a roadmap document, whose Sources name a roadmap clause; one a planted owner decision covers, whose Sources name it, and one that contradicts it, whose `diverges` call and hold reason name it; a `fits with follow-ups` call whose follow-ups the next report lists; a worker pull request sent up ready, a milestone verdict pull request and a roadmap edit, each stopped by `--require` until its call is recorded in place, then reaching the reviewer without entering `land`, with one refusal entry over two visits, and each with a `diverges` call leaving by the edge Step 5 names and not reaching the reviewer, the worker pull request by `classification: needs_fix` through `rebrief` without entering `surface`, and the milestone verdict pull request reaching `verdict: recorded` on its next visit once its call stands, with no second entry; a hold's `rework` edge to `rebrief` and a lift's `reverify` edge to `verify`; a manager-authored pull request with no call (`uncalled`, `align_call` writing one refusal entry over three visits, the call recorded, `land` reached again, a count of one at the next start); a `diverges` call (the hold message submitted at the manager's `wait` as a `director-hold` event, the copy recorded at `director_hold`, its land check `held`, the rework route, the hold named in each report); a new head with a `fits` call (the director's lift, the lift message taken as a `director-hold` event and applied at `director_hold`, the manager's land check reporting a posture token); a director start of each of the four kinds with an unreviewed merge, a closed held pull request, a releasable hold the start lifts with `--lift-releasable` and a lineage gap, each start writing its `Director start:` entry and the next reading `--since` from it; manager reports carrying `unit=` and `open=` lines; and a director with no merge grant sending the call up. Then run the existing `coordinate_1_engine_test.sh` to `coordinate_4_engine_test.sh`, `coordinate-takeover_engine_test.sh`, `check-template-compat.sh` against the base's table, `scripts/validate-template-mermaid.sh` and `scripts/check-skill.sh --changed coordinate`, and diff `ENTRY_KINDS` and the kind grammar sections of `references/state-keys.md` against the base. Every case passes.

**Dependencies**: Step 2, Step 3, Step 4

Outside this plan, Step 5 also waits for the named-roles build that shirabe#1483 plans to land, as its Goal says.

**Files**: `skills/coordinate/scripts/land-check.sh`, `skills/coordinate/scripts/land-check_test.sh`, `skills/coordinate/scripts/coord-verdict.sh`, `skills/coordinate/scripts/coord-verdict-table_test.sh`, `skills/coordinate/scripts/alignment-call.sh`, `skills/coordinate/scripts/render-result.sh`, `skills/coordinate/scripts/render-result_engine_test.sh`, `skills/coordinate/scripts/board-record.sh`, `skills/coordinate/scripts/state-common.sh`, `skills/coordinate/scripts/coordinate-template-structure_engine_test.sh`, `skills/coordinate/scripts/alignment_engine_test.sh`, `skills/coordinate/SKILL.md`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/koto-templates/coordinate.mermaid.md`, `skills/coordinate/koto-templates/coordinate.compat.json`, `skills/coordinate/references/loop.md`, `skills/coordinate/references/state-keys.md`, `skills/coordinate/evals/evals.json`

### Step 6: A lane reaches the owner only through the director, once per subject, and a mismatched relay is declined

**Goal**: The owner funnel, owner questions and relays, as skill text over the record's existing Decisions entries, Work rows and Standing rows (PRD R12 to R14). Nothing from a lane reaches the owner except through the director; the owner sees every alignment call, `diverges` first, one message per subject; a second lane's question joins the one already waiting; a relay that doesn't match recorded owner text is declined with both texts shown; and a call the owner reverses becomes a Standing row the lane can cite.

**Acceptance Criteria**:

- [ ] The manager's expectation list in `SKILL.md` says it sends its questions, reports and pull requests to its director and never to the owner, and a manager's Run `reports-to` row names the director. In the eval run, every message the owner receives comes from the director's session.
- [ ] A lane question the director can't answer from the record becomes one decision opened and escalated to the owner with `state-decision.sh`, sent as a message, and the asking lane's Work row Next reads `waits on decision <n>`. While another entry holds the one escalated slot, the escalation is queued (state `coordinator-verdict`, Verdict `escalate`) and the lane's Work row points at it all the same.
- [ ] A waiting question is an escalated or a queued entry, and both are matched: a second lane's question on the subject of either still opens its own entry through `decision_open`, as the template requires for every extracted question, and the director settles that entry at once with `state-decision.sh --settle --outcome "joins decision <n>"`. There is no second escalation and no evidence on decision `<n>`: that lane's Work row Next points at decision `<n>`, the owner receives no second message, and the owed reply to the lane names decision `<n>` as the matched record. The `decision_verdict` directive in `koto-templates/coordinate.md` says so in its text; no state, transition or evidence field changes, and `check-template-compat.sh --base-table <base table>` passes with the compat number unchanged.
- [ ] A lane question the owner already answered in the record is answered from it, naming the matched Standing row or settled decision, and the owner is sent nothing.
- [ ] When the owner answers, the decision is settled with the answer and every lane whose Work row names it gets a message with it.
- [ ] Every director report lists each waiting decision with its age and the lanes pointing at it: an escalated entry's age is now minus Asked, and a queued entry's is now minus its Updated, the stamp `state-decision.sh --escalate` records when it queues the verdict. With the clock 24 hours past the ask, the age reads at least 24 hours, a lane that doesn't depend on it is dispatched and landed in that time, and no second message on that subject reaches the owner except the re-ask the skill's existing rule schedules.
- [ ] In a director turn a lane's message started, the director makes no ask that waits for the owner's reply before the turn ends (R14).
- [ ] A relay of "the owner said X" is acted on only when a Standing row whose Owner is the owner and whose Relayed by is empty, or a decision the owner settled, says X; the reply names that record. When the recorded text says something else, the director takes no action grounded on the relay, and its reply and its next report show both texts; with none recorded, the reply says so. It asks the owner only when no question on that subject is already waiting.
- [ ] Each director report to the owner carries the calls whose stamp is after its previous report to the owner, the `calls` that `alignment-read.sh --since <stamp>` lists, `diverges` calls first, and a pull request's calls, its hold and any lane question on it go in one message however many lanes or calls touched it. A call that went in one report is not in the next.
- [ ] Once a director report to the owner is sent, the director writes an `entry` whose first line is `Owner report: <YYYY-MM-DDTHH:MM:SSZ>`, the time of the read it carried, and the next report reads `--since` from the latest such entry; with none in the record, the report carries every call of the run. `references/state-keys.md` documents the line.
- [ ] `references/state-keys.md`'s line telling a coordinator to record a person's word with "the person as owner and yourself as relayer" is corrected to match its own Standing paragraph and `state-stored-set.sh --standing`: Relayed by is whoever carried the word, empty when the person said it to the coordinator directly. So an owner's word the director took directly has Relayed by empty, and the relay check above can match it.
- [ ] A call the owner reverses is recorded as a Standing `answer` row with the owner as Owner, Relayed by empty, and What naming the reversed call's entry number, pull request and head. The director's next call on that head has `standing s<n>` in Sources, the lane is told the row id, and where the owner reversed a `diverges`, the owner's lift is recorded on the `align-` hold as a person's lift and relayed to the manager's copy, by the `state-hold.sh --lift` route Step 2 tests. A later relay citing `s<n>` is acted on with that row named.
- [ ] For each call, hold, lift and owner reversal in the eval's record, a reader finds from the record alone who decided it and what it decided on (the pull request, the head, and the call's entry number or the hold's name). The feature adds no field for koto's decision record, and no sentence it adds states a requirement on that work (R19).

**Check**: Add eval cases to `skills/coordinate/evals/evals.json`, with fixtures under `skills/coordinate/evals/fixtures/`, in a test workspace with two lanes, a fixed clock and a planted roadmap, strategy and owner decision: two lanes asking one question (once on an escalated entry and once on a queued one, the second lane's entry settled as `joins decision <n>`), a queued question listed with its age from Updated, a question already answered, the owner's answer, a 24-hour wait with an independent lane landing, a lane-started turn, a matching, a mismatched and an unrecorded relay, a report to the owner after a `diverges` and two `fits` calls followed by a second report after one more call (the second carrying only that call, read `--since` the first report's `Owner report:` entry), an owner's word taken directly and recorded with Relayed by empty, and an owner reversal followed by a citing relay. Run them with `scripts/run-evals.sh` for the coordinate skill, then `scripts/check-skill.sh --changed coordinate` and `scripts/check-template-compat.sh --base-table <base table>`. Every case passes.

**Dependencies**: Step 5

**Files**: `skills/coordinate/SKILL.md`, `skills/coordinate/references/loop.md`, `skills/coordinate/references/state-keys.md`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/evals/evals.json`, `skills/coordinate/evals/fixtures/`

## Implementation Sequence

The steps run in order, each in its own pull request that merges before the
next step that depends on it starts. Before step 2 starts, a short read of the coordinate
template's `wait` evidence confirms which wait events carry a manager's pull
request links. Step 3's lane set rests on that answer, and checking it first
keeps step 2's hold and lift messages from settling on a shape step 3 can't
read. Step 3 needs step 2's hold and lift; step 4 reads no hold and needs
only step 1's call grammar, so the two can run beside each other. Step 5
ships the land-check gate together with the skill text and template changes
that tell a director to record calls, so no director meets a gate its skill
doesn't explain; it needs step 3's start listing, step 4's helper, which its
alignment section tells a director to run, and the named-roles build. Step 6
is skill text over the existing record and follows step 5's alignment
section.

**What these steps can't show yet.** The feature as a whole is shown by a
reviewer walking a live director over two lanes through five cases: a planted pull request that contradicts a recorded owner decision is
held with a named reason, and its lane reports the hold and its release; a
new head keeps the hold until the director re-reads it, then the hold lifts;
a landed pull request that touches no roadmap clause carries a one-line call
for its head, and a milestone verdict pull request's call cites the Evidence
clause it was judged against; a pull request merged past the director with
no call is reported unreviewed at the next start; and a relay that misquotes
the owner is declined with both texts shown, while a question the owner
leaves unanswered for a day waits with its age, asked by no second lane, and
the other lanes keep moving. None of the five can be shown until Steps 5
and 6 land on top of the named-roles build, because until then no session is
a director. Before that, Steps 1 and 2 show the hold and the lift on scratch
records, and Steps 3 and 4 show the reads on planted records; neither is the
reviewer's walkthrough.

Two of those cases are met only on the paths the PRD covers. The one-line
call is owed for a pull request the director merges or recommends (R5), and
the unreviewed report covers a manager-authored pull request or a finished
unit's final head (R10). A worker pull request that a granted manager lands
short of finishing its unit owes no call and isn't reported unreviewed. So
the walkthrough lands its routine pull request through the director and
merges a manager-authored pull request past it. If those two cases are read
to cover a worker pull request a granted manager lands mid-unit, these
documents don't meet them, and closing that gap is a change to the PRD's R10,
not something this plan can settle.

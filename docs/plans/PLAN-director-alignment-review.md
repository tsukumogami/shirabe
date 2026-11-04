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
- [ ] `alignment-call.sh` with a `diverges` call on a pull request with no director hold standing writes the call entry, adds a hold named `align-<repo name>-<n>-<40-hex placed-on head>` to the director's record with `until` `lifted`, and prints a message holding the pull request, the hold row, the reason, the receiver and the release.
- [ ] Passing that printed message to `alignment-call.sh --copy --add` in a scratch manager record whose dispatcher is the director adds the identical hold row to the manager's record and writes a `hold` entry naming the event the message arrived in.
- [ ] `alignment-call.sh --copy --add` refuses a message whose sender isn't the dispatcher address the manager's record names: it exits non-zero, says so, and leaves the manager's Holds section and entries unchanged. It refuses a malformed message the same way: a hold name not of the `align-` form, or a head that isn't 40 hex.
- [ ] `land-check.sh` on the manager record reports the pull request unready, and its output names the `align-` hold.
- [ ] A second `diverges` call on the same pull request while the director's hold still stands writes its entry but places no second hold; the director's record still holds exactly one `align-` row.
- [ ] A `diverges` call on a merged pull request is written as an entry but places no hold, and no `align-` row is added to the director's record.

**Check**: Run the step's test. It creates a scratch director record and a scratch manager record whose dispatcher is the director, then plants one pull request head. It runs `alignment-call.sh` with `diverges` in the director record and checks the entry and the `align-` hold row named after that head. It passes the printed message to `alignment-call.sh --copy --add` in the manager record, and then runs `land-check.sh` on the manager record: the result is unready with the `align-` hold named. The test also feeds `state-entry.sh` a malformed alignment line and sees exit 65 with the record unchanged, sends the copy from a wrong sender and sees the refusal, repeats the `diverges` call and sees one hold, and calls `diverges` on a merged pull request and sees an entry and no hold.

**Dependencies**: None

**Files**: `skills/coordinate/scripts/state-entry.sh`, `skills/coordinate/scripts/alignment-call.sh`, `skills/coordinate/references/state-keys.md`

### Step 2: The hold lifts only after a new head and a later fits call

**Goal**: A held pull request is released only by a new live head that the director has re-read and called `fits` or `fits with follow-ups`, and the manager's copy lifts only at its own verified head. The director's guarded lift runs in the same writer run as the call; the manager's `alignment-call.sh --copy --lift` accepts the lift message only from the dispatcher address its record names, and the message names the hold, the head it was released on and the entry number of the `fits` call it rests on.

**Acceptance Criteria**:

- [ ] After the fixture pull request moves to a new head and the director records `fits` (or `fits with follow-ups`) on it, `alignment-call.sh` lifts the `align-` hold in the director's record, the Lifted cell reads `<minute> by director at <address>, <fits|fits with follow-ups> at <40-hex head>`, and it prints a lift message naming the hold, the head it was released on and that `fits` call's entry number.
- [ ] Feeding that printed message to `alignment-call.sh --copy --lift` in the manager's record, at the manager's verified new head, lifts the manager's copy, and `land-check.sh` then reports the pull request ready instead of held.
- [ ] The manager's `hold` entry for the lift records both the hold name and the fits call's entry number, so a lift with no matching call shows in the manager's own record.
- [ ] A `fits` call recorded while the live head is still the placed-on head lifts nothing: the director's hold stays standing and no lift message prints.
- [ ] When the live head can't be read from GitHub, the director's lift is blocked: the call is still written, the script exits with its own code naming the hold, and the hold stays standing (fail closed).
- [ ] In the manager's record, a `--copy --lift` at the placed-on head, a replayed lift naming an older head than the manager's verified head, and a lift from a sender that isn't the dispatcher address the record names are each refused with a message saying why, and the hold still makes `land-check.sh` report the pull request held.
- [ ] Read from the records alone, every hold and lift the step writes names who decided it (the director and its address in the Set by and Lifted cells) and what it decided on (the pull request, the placed-on head in the hold's name, the head it was released on and the `fits` call's entry number), and the step adds no field for koto's decision record.

**Check**: Run the fixture test for this step. It places a hold with a `diverges` call (as step 1 does) and copies it into the manager's record. It then asserts that a `fits` call at the same head lifts nothing, moves the fixture pull request to a new head, records `fits`, and checks the director's Lifted cell and the printed lift message. It feeds that message to `alignment-call.sh --copy --lift` in the manager's record and checks that `land-check.sh` reports the pull request ready and that the `hold` entry carries the hold name and the call's entry number. It then repeats the lift against fresh copies of the held record at the placed-on head, with a replayed lift naming an older head, and from a non-dispatcher sender, and checks each is refused with `land-check.sh` still reporting held. It makes the live-head read fail and checks the lift is blocked with the hold standing. Finally it reads the director's hold row and Lifted cell and the manager's `hold` entries and finds the decider, the pull request, both heads and the call's entry number in them, with the Holds grammar unchanged.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/alignment-call.sh`, `skills/coordinate/references/state-keys.md`

### Step 3: Every call, merge and hold can be listed, with unreviewed heads marked

`alignment-read.sh` lists calls, merges and recommendations with their call status, standing `align-` holds and lineage gaps, marks a finished unit's final head or a manager-authored pull request merged with no call as unreviewed, and lists a worker pull request a granted manager landed short of a finished unit as `manager-reviewed`, not unreviewed; the director's start reads it in step 5.

### Step 4: The director finds what a pull request touches and its call cites it

`alignment-sources.sh` returns the unit, roadmap clauses and Evidence, the strategy path, changed files, the other lanes' open holdings and pull requests, full-read triggers (an `other-lane` trigger naming the lane when the pull request changes a document, path or roadmap another lane has open work on, which the call then names in Sources) and candidate owner decisions, and a milestone-verdict call cites the Evidence clause it was judged against.

### Step 5: A director can't merge or recommend a head with no alignment call

`land-check.sh` reports `no-alignment-call` when the Run `role` row reads `director`, and the land step records each refusal once per pull request and head so the next start report prints their count; it ships with the director's alignment section, the start's unreviewed list and hold listing, the manager's hold duty and the template changes, and needs the named-roles build that shirabe#1483 plans.

### Step 6: A lane reaches the owner only through the director, once per subject, and a mismatched relay is declined

Owner questions ride Decisions entries and Work rows, so a second lane's ask joins the waiting question with its age and a relay that doesn't match recorded owner text is declined with both texts shown; every director report to the owner carries each call since the last, `diverges` first and one message per subject, nothing from a lane reaches the owner but through the director, and a call the owner reverses is recorded as a Standing `answer` row naming the reversed call, which the lane can cite and the director's next call on that head names.

## Implementation Sequence

The steps run in order, each in its own pull request that merges before the
next step that depends on it starts. Before step 2 starts, a short read of the coordinate
template's `wait` evidence confirms which wait events carry a manager's pull
request links. Step 3's lane set rests on that answer, and checking it first
keeps step 2's hold and lift messages from settling on a shape step 3 can't
read. Steps 3 and 4 each need only step 2, so they can run
beside each other. Step 5 ships the land-check gate together with the skill
text and template changes that tell a director to record calls, so no director
meets a gate its skill doesn't explain; it needs step 3's start listing and the
named-roles build. Step 6 is skill text over the existing record and follows
step 5's alignment section.

**What these steps can't show yet.** The milestone this plan delivers is
judged by a reviewer walking a live director over two lanes through five
cases: a planted pull request that contradicts a recorded owner decision is
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

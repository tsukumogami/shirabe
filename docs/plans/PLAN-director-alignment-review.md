---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
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

**This build can't land before the named-roles build.** Step 5's gate and the
director's start read the Run `role` row, which arrives with the named-roles
build that shirabe#1483 plans and which isn't merged. The pull request that
carries this plan's build waits for that build to land first; until it does,
no session knows it is a director.

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

## Steps

### Step 1: A director's diverges call holds the pull request in the manager's land check

**Goal**: A director's `diverges` call on a lane pull request now stops the manager from landing it. The step crosses the whole path on one planted pull request head in scratch records: the director's call entry, the `align-` hold in the director's record, the printed hold message, the manager's copy (`alignment-call.sh --copy --add`), and the manager's existing land check.

**Acceptance Criteria**:

- [ ] `state-entry.sh --kind alignment --on <owner/repo#n>` refuses a malformed alignment text (a missing, extra or reordered line, a head that isn't 40 hex, or `diverges` with Sources `none`) with exit 65 and writes nothing to the record; a well-formed seven-line text is written and stays in the session.
- [ ] `alignment-call.sh` with a `diverges` call on a pull request with no director hold standing writes the call entry, adds a hold named `align-<repo name>-<n>-<40-hex placed-on head>` to the director's record with `until` `lifted`, and prints a message holding the pull request, the hold row, the reason, the receiver and the release.
- [ ] Passing that printed message to `alignment-call.sh --copy --add` in a scratch manager record whose dispatcher is the director adds the identical hold row to the manager's record and writes a `hold` entry naming the event the message arrived in.
- [ ] `alignment-call.sh --copy --add` refuses a message whose sender isn't the dispatcher address the manager's record names: it exits non-zero, says so, and leaves the manager's Holds section and entries unchanged.
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

**Check**: Run the fixture test for this step. It places a hold with a `diverges` call (as step 1 does) and copies it into the manager's record. It then asserts that a `fits` call at the same head lifts nothing, moves the fixture pull request to a new head, records `fits`, and checks the director's Lifted cell and the printed lift message. It feeds that message to `alignment-call.sh --copy --lift` in the manager's record and checks that `land-check.sh` reports the pull request ready and that the `hold` entry carries the hold name and the call's entry number. It then repeats the lift against fresh copies of the held record at the placed-on head, with a replayed lift naming an older head, and from a non-dispatcher sender, and checks each is refused with `land-check.sh` still reporting held. Finally it makes the live-head read fail and checks the lift is blocked with the hold standing.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/alignment-call.sh`, `skills/coordinate/references/state-keys.md`

### Step 3: The director's start lists every call and reports an unreviewed merge

`alignment-read.sh` lists calls, merges and recommendations with their call status, standing `align-` holds and lineage gaps, and the director's start reports a merged head with no call as unreviewed.

### Step 4: The director finds what a pull request touches and its call cites it

`alignment-sources.sh` returns the unit, roadmap clauses and Evidence, the strategy path, changed files, full-read triggers and candidate owner decisions, and a milestone-verdict call cites the Evidence clause it was judged against.

### Step 5: A director can't merge or recommend a head with no alignment call

`land-check.sh` reports `no-alignment-call` when the Run `role` row reads `director`, shipping with the director's alignment section, the manager's hold duty and the template changes; it needs the named-roles build that shirabe#1483 plans.

### Step 6: A lane's question reaches the owner once and a mismatched relay is declined

Owner questions ride Decisions entries and Work rows, so a second lane's ask joins the waiting question with its age, and a relay that doesn't match recorded owner text is declined with both texts shown.

## Implementation Sequence

The steps run in order. Before step 2 starts, a short read of the coordinate
template's `wait` evidence confirms which wait events carry a manager's pull
request links, since step 3's lane set rests on it. Steps 3 and 4 each need only step 2, so they can run
beside each other. Step 5 ships the land-check gate together with the skill
text and template changes that tell a director to record calls, so no director
meets a gate its skill doesn't explain; it needs step 3's start listing and the
named-roles build. Step 6 is skill text over the existing record and follows
step 5's alignment section.

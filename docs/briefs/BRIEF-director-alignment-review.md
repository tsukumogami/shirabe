---
schema: brief/v1
status: Draft
problem: |
  A director gets its lanes' finished pull requests, most marking a milestone
  done, with no written way to judge their fit with the roadmap, strategy and
  recorded owner decisions. A divergent one can land unnoticed, a merge leaves
  no trace of a judgment, and a lane's question can reach the owner twice.
outcome: |
  A lane sees a held pull request's reason, receiver and release, lifted only
  after a new head and a re-read. The owner lists every merge or recommendation
  with the alignment call for its head, gets each lane question once with
  relayed words checked, and no director blocks on an absent owner.
motivating_context: |
  Named roles give the workspace a director: a coordinator session over lane
  coordinators. The reviewer concept gave the coordinate skill a correctness
  review of a worker's pull request. What a director's own review is for --
  fit with the plan rather than correctness -- was never written down, and the
  first director runs as soon as named roles are installed.
---

# BRIEF: Director Alignment Review

## Status

Draft

## Problem Statement

A lane coordinator drives one stream of work and hands its finished pull
requests up. Almost every one of them closes a roadmap milestone or moves one
forward. The coordinator above the lanes, the director, is the session that has
to decide whether each of those pull requests should land or go back. Its
question isn't whether the code is right: the worker's own review and the
reviewer seat already ask that. Its question is whether the pull request does
what the roadmap, the strategy and the decisions the owner recorded say this
work is for.

Today nothing in the coordinate skill says how a director asks that question,
what it does with the answer, or where the answer goes. Four gaps follow from
that:

- **A divergent pull request has no stop.** A lane can finish a pull request
  that quietly contradicts a recorded owner decision. If the director notices,
  there's no written way to hold that pull request, say why, say who has to act,
  and say what lifts the hold. If the lane pushes a new head, nothing says
  whether the old judgment still stands.
- **A merge leaves no judgment behind.** When a pull request lands, nobody can
  later tell whether a director judged its fit, what it concluded, or against
  which clause. A merge that skipped the director looks the same as one it
  checked.
- **Questions to the owner multiply and drift.** Two lanes can ask the owner the
  same thing, and a lane can act on "the owner said X" when the owner wrote
  something else. Nothing makes the director the single route to the owner or
  checks a relayed quote against the recorded text.
- **A director can stall on the owner.** A director that treats an owner
  question as a gate on every lane would stop the whole tree on someone who
  never opened the conversation, and nothing in the skill says the question
  should wait on its own while the lanes keep moving.

## User Outcome

The lane coordinator, the director and the owner each see something different
once this lands.

A lane coordinator whose finished pull request the director judged out of line
sees a hold on it. The hold names the reason, the session it waits on and what
releases it. The lane reports that hold upward instead of working around it,
and it sees the hold lift only after it pushed a new head and the director read
that head again.

The owner can list every merge or recommendation a director made and, for each,
the alignment call recorded for the head that landed. A milestone verdict pull
request's call names the clause of the milestone's evidence it was judged
against. A merge that went past the director with no call shows up as
unreviewed the next time a director starts.

A question from a lane reaches the owner once, through the director. When a
lane relays "the owner said X", the director checks it against what the owner
actually wrote before acting on it. And no director sits waiting on the owner
from a turn the owner didn't start: the question waits with its age while the
other lanes keep moving.

## User Journeys

### A director holds a pull request that contradicts a recorded decision

A director supervises two lanes. One lane finishes a pull request that marks a
milestone done but reverses a decision the owner recorded. The director reads
it, finds the contradiction, and puts a hold on it naming the decision, the
lane coordinator as the receiver, and "a new head that restores the decision,
re-read by the director" as the release. The lane coordinator's next report
names the hold and what releases it.

### A lane pushes a new head to a held pull request

The lane coordinator sends the work back to its worker, which pushes a new
head. The hold doesn't lift on the push. It lifts when the director reads the
new head and records a call that it now fits; until then the pull request stays
held, and a director start shows it held.

### A director records the call for an ordinary landing and for a milestone verdict

A lane hands up a small pull request that touches no roadmap clause. The
director records a one-line call for its head and passes it on. Later a lane
hands up a milestone verdict pull request; the director's call for that head
names the evidence clause it was judged against, so the owner reading the list
later sees what "done" was measured by.

### A merge that skipped the director surfaces at the next start

Someone merges a lane's pull request without a director call. The next director
start lists that head as unreviewed, so the gap is visible rather than absorbed.

### A relayed owner quote that doesn't match, and an owner who doesn't answer

A lane writes "the owner said to drop the cap" where the recorded text says
"keep the cap a tunable". The director declines to act on the relay and shows
both texts. Separately, the director asks the owner a question on a lane's
behalf and gets no answer for a day; the other lanes keep moving, the question
waits with its age, and no second lane asks it again.

## Scope Boundary

**IN:**

- What a director's review of a lane's finished pull request is for: fit with
  the roadmap, the strategy and the owner's recorded decisions.
- Holding a divergent pull request with a reason, a receiver and a release, and
  lifting it only after a new head and a director re-read.
- An alignment call recorded for every merge or recommendation, readable by
  other tools, with a milestone verdict's call naming its evidence clause.
- Reporting a merge with no call as unreviewed at the next director start.
- The director as the single route for a lane's question to the owner, and the
  check of a relayed owner quote against the recorded text.
- No director blocking on the owner from a turn the owner didn't start.

**OUT:**

- Correctness review of a pull request. The worker's review and the reviewer
  seat own it; the director doesn't repeat it.
- Granting merge, close or release authority, or defining levels. The
  workspace's authority settings own that; this feature reads the answer.
- Standing-rule provenance, a successor restating rules, and moving caps.
  Separate work owns them; this feature names where it meets them.
- Defining the named roles themselves, or how a session's role changes. The
  named-roles work owns that.
- Succession telemetry that might read the alignment call later. Separate
  observability work owns it.
- Implementing any of this in skill text, templates or scripts. That's a later
  unit; this one ends at the documents.

## Open Questions

- Where is the line between a one-line call and a full read?
- How does the director find the roadmap clauses, strategy and owner decisions
  a pull request touches?
- Does a push-back reuse the existing changes-needed rework route, or get its
  own?
- Who merges after a director without the merge grant has reviewed?
- What shape does the alignment call's record take before standing-rule
  provenance gives it provenance?

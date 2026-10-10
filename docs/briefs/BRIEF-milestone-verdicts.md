---
schema: brief/v1
status: Accepted
problem: |
  The roadmap format says a milestone is Done only on a verification verdict,
  but the tools still set Done when work merges, never judge pull requests
  against the milestone's Evidence, can't close a milestone with no pull
  request, and can't reopen one that fails later. Done can't be trusted.
outcome: |
  A coordinator closes every milestone, with or without pull requests, on a
  recorded verdict naming who checked, and Done follows only from it. Each
  pull request's goal fit names the Evidence it advances, and a milestone whose
  Evidence later fails goes back to In progress and is offered again.
---

# BRIEF: milestone verdicts

## Status

Accepted

## Problem Statement

A roadmap in milestone form makes one promise to its reader: a milestone
reads Done only after someone other than the session that built it checked
the shipped work against the milestone's Evidence and recorded a verdict.
shirabe's roadmap format reference states that rule, and in the same breath
says no tool enforces it. The tools that move a milestone's status still
work the way they did before milestones existed. The completion cascade sets
a feature Done when the PLAN under it finishes, and the coordinator's status
write-back sets it Done when its last pull request lands. Either way the
merge is what moved the status, which is exactly what the rule says must not
happen. A coordinator that wants to honour the rule today has to decline the
tools' own suggestions and keep the verdict somewhere the tools never read.

The check the coordinator does make doesn't look at the milestone. When it
lands a pull request it judges goal fit against the brief it wrote for the
worker, and nothing ties that judgment to the milestone's Evidence, so a
pull request can be judged a fit while advancing none of the clauses the
milestone will be closed on. When the last piece lands, there's no step that
reads the Evidence as a whole and no record entry for the result.

Two kinds of milestone fall outside the tools entirely. One whose Evidence is
the state of a host, a document or a walkthrough a person follows produces no
pull request, so nothing that waits on a merge ever reaches it, and it can
only be closed by hand. And a milestone that read Done and is later found
short of its Evidence has no way back: the format forbids nothing, but no
tool reopens a milestone and the picker never offers a Done one again, so
the gap gets filed as new work or quietly forgotten. Either way the roadmap
keeps saying Done about something that isn't.

The cost lands on whoever reads the roadmap to decide what comes next. A
milestone that depends on a Done one gets started on a capability that isn't
there, the owner judging whether the roadmap's bet is paying off counts
outcomes that never arrived, and the rework surfaces later, attached to
whatever work tripped over it.

## User Outcome

A coordinator driving a milestone roadmap closes each milestone the same
way, whatever it produced. When its last piece lands (a merged pull request,
several, or none at all), the coordinator checks the work against each
Evidence clause and records a verdict, naming who checked, in its own record.
The milestone stays In progress until that verdict exists, and only a
verified verdict moves it to Done. The person who owns the roadmap reads
Done and knows a named checker judged the Evidence held.

Along the way, each pull request the coordinator lands carries a goal-fit
judgment that names the Evidence clause it advances, so the record shows how
the milestone's pieces map onto what it will be closed on, and a pull request
that advances nothing the milestone needs is visible before it merges.

When a Done milestone's Evidence later fails, recording that failure puts the
milestone back to In progress and the coordinator's picker offers it again,
so the gap is fixed in the milestone that promised it rather than re-homed in
a new item. The roadmap's owner can rely on one thing: a milestone reads Done
because a named checker said its Evidence held, never because something
merged.

## User Journeys

### A coordinator closes a milestone whose last pull request merged

A coordinator is driving a roadmap and a worker's last pull request for a
milestone merges, finishing the PLAN under it. The completion cascade closes
out the PLAN's documents but leaves the milestone In progress, and the
coordinator's landing step proposes no status change. The coordinator reads
the Evidence at the default branch's head, checks each clause against the
shipped result, and records a verdict entry naming itself as the checker.
The roadmap edit that follows sets Done, and a reader of the roadmap finds
the milestone Done with the verdict it rests on.

### A coordinator closes a milestone that produced no pull request

A milestone's Evidence is that a host is configured a certain way, or that a
person following a written walkthrough gets a stated result. Nothing merges.
The worker reports the work finished, or the coordinator itself sees the
milestone's last piece of work done with nothing to merge, and that report
takes the place a merge takes elsewhere. The coordinator checks the Evidence
directly, and records a verdict the same shape as for a
milestone that merged code. The milestone closes on that verdict, not on a
hand edit nobody can trace.

### A coordinator lands a pull request against a milestone

Partway through a milestone, a worker's pull request is ready. When the
coordinator judges its goal fit, it reads the milestone's Evidence and
records which clause the pull request advances. A reader of the record later
sees, for each pull request, the Evidence clause it was judged against, and a
pull request that advances no clause shows up as a gap at landing rather than
at the verdict.

### The roadmap's owner finds a Done milestone short of its Evidence

Weeks after a milestone read Done, the person who owns the roadmap re-runs
one of its Evidence checks and it fails. They tell the coordinator driving
the roadmap, which records the failure against that milestone, naming the
clause and what the owner saw; the milestone goes back to In progress. The
next time the coordinator picks work, that milestone is offered again, and
its next verdict is judged against the same Evidence, so the owner sees the
gap closed where it was promised.

## Scope Boundary

**In scope:**

- The coordinator's verdict step for a milestone: when it runs, what it
  checks, and the verdict entry it records, including who checked. The
  checker is the coordinator that dispatched the work or a person; how a
  checker is named, and how the delivering session is kept out of that role,
  is the PRD's to specify.
- Closing milestones whose work produces no pull request through the same
  verdict step.
- Removing merge-driven Done from the coordinator's landing and status
  write-back and from the completion cascade, for milestone roadmaps.
- Goal fit at landing judged against the milestone's Evidence, with the
  clause named in the record.
- Recording a post-Done failure, returning the milestone to In progress, and
  the picker offering it again.
- The roadmap edit a verdict calls for (status, progress line, follow-up
  milestones), made from the verdict rather than from a merge.

**Out of scope:**

- How a separate reviewing session or a pre-review sort consumes verdicts.
  That review has its own owner; this feature only makes the verdicts exist
  and readable.
- Rewriting existing roadmaps into milestone form, or moving roadmaps a
  coordinator is driving. That's migration work that depends on this.
- Who merges pull requests, and the coordinator model above a single
  coordinator. Merging stays wherever the workspace already puts it.
- Plans made of functional steps and the step format. A separate feature
  owns how a PLAN under a milestone is shaped.
- Capturing time and token cost per unit.
- Any change to koto or niwa.

## References

- `skills/roadmap/references/roadmap-format.md` -- the milestone fields and
  the Done rule this feature enforces.
- `skills/coordinate/SKILL.md` -- the coordinator whose landing, picking and
  record this feature changes.
- `docs/designs/current/DESIGN-completion-cascade.md` -- the cascade whose
  roadmap write this feature stops for milestones.
- `docs/designs/current/DESIGN-milestone-format.md` -- the format work that
  defined the rule and deferred its enforcement.

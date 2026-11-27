# Landing on a Milestone Roadmap

Read from `merge_confirm` and `merged_facts` when the run's roadmap is a
milestone roadmap (`schema: roadmap/v2` or `roadmap/v3`). The two read the
same: a v3 roadmap lists its milestones under `## Milestones` with
`### Milestone N:` headings where v2 has `## Features` and `### Feature N:`,
and a record that names a unit `Feature N` still matches the heading
`Milestone N`.

A merge never sets a milestone's status. Don't dispatch a worker for a
pull request that changes a milestone's Status or Delivered line, and don't
edit either yourself: a milestone reads Done only once a checked verdict's
roadmap edit lands (`skills/roadmap/references/roadmap-format.md`, When a
milestone is Done). The completion cascade never edits a milestone roadmap
either; it records its roadmap step as `skipped`.

Once the milestone's work is finished, its last pull request merged or,
with nothing to merge, its work reported or seen done, tick `landed` from
`wait` with its tag. `roadmap_status` runs `roadmap-status.sh --unit`, which
marks the verdict owed instead of opening a Done pull request, and the run
goes to `milestone_verdict`, where you check the shipped work against each
Evidence clause and record the verdict. Until that verdict's roadmap edit is
confirmed, pick never offers the milestone and dependents stay blocked.

## On a roadmap/v4 roadmap

A `roadmap/v4` roadmap reads the same way as v3, but its merge does set a
status: Completed, which satisfies the milestone's dependents while its
verdict is still owed. `roadmap-status.sh --unit` writes the verdict-owed
row and records Completed in the roadmap, and it prints two lines:
`verdict-owed <tag>`, then the pull request that sets it Completed. That's
a new edit, or the run's own pending edit when one is open, which the change
is folded into. When the milestone already reads Completed it prints
`<tag> already reads Completed on ...` instead of the pull request. The run
still goes to `milestone_verdict`, and pick offers the milestone's verdict
there, never its work; its dependents can be dispatched meanwhile.

The verdict then moves the milestone the way the status table in
`skills/roadmap/references/milestone-statuses.json` says.
`roadmap-status.sh --verdict` needs no verdict-owed row on v4 and consumes
the row when there is one. Either verified verdict sets the milestone's
block Status and its Progress row to Verified. Changes needed sets both to
In progress and prints `held-dependent <tag> <worker>` for each dependent
that read it met: one a holding covers, or one reading Completed or
Verified (`none` when no holding covers it). Tell each worker's owner, as
after a reopen. `roadmap-status.sh --reopen` takes a Completed milestone as
well as a Verified one and sets block and row In progress, printing the same
lines. A move the table doesn't list, such as another verdict on a Verified
milestone or any edit of a Dropped one, is refused before anything is
opened, and the refusal names the milestone, its status and the trigger.

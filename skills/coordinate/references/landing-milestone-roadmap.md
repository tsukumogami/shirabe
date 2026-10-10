# Landing on a Milestone Roadmap

Read from `merge_confirm` and `merged_facts` when the run's roadmap is a
milestone roadmap (`schema: roadmap/v2`).

A merge never sets a milestone's status. Don't dispatch a worker for a
pull request that changes a milestone's Status or Delivered line, and don't
edit either yourself: a milestone reads Done only once a checked verdict's
roadmap edit lands (`skills/roadmap/references/roadmap-format.md`, When a
milestone is Done).

Once the milestone's work is finished, its last pull request merged or,
with nothing to merge, its work reported or seen done, tick `landed` from
`wait` with its tag. `roadmap_status` runs `roadmap-status.sh --unit`, which
marks the verdict owed instead of opening a Done pull request, and the run
goes to `milestone_verdict`, where you check the shipped work against each
Evidence clause and record the verdict. Until that verdict's roadmap edit is
confirmed, pick never offers the milestone and dependents stay blocked.

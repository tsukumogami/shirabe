# Landing on a Feature Roadmap

Read from `merge_confirm` and `merged_facts` when the run's roadmap is a
feature roadmap (any schema but `roadmap/v2`, or a discipline's scope).

When a feature lands
on a roadmap whose repository doesn't hold that feature's PLAN, dispatch a worker
for a small pull request that sets the feature's status line, as a holding;
features that depend on it stay blocked until it merges.

When the roadmap's own repository holds it, nothing is dispatched for the
status: once the feature's last pull request has landed, tick `landed` from
`wait`, and `roadmap_status` writes its Status and Delivered line back as a
pull request through `roadmap-status.sh`.

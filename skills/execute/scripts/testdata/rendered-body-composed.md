Coordination pull request for t. It carries the planning documents for 2 node pull requests and merges after all of them.

---

> This is a **coordination PR** for a coordinated effort. It is docs-only and
> merges **last**, once every indexed PR has merged and finalization is complete.
> See `references/coordination-strategy.md`.

topic=t
exit=published
mode=coordinated
store=session
run=00112233445566778899aabbccddeeff

## PR Index

- pr-repo-a-core | acme/repo-a:docs/plans/PLAN-t.md#11 | open | head=1111111111111111111111111111111111111111

## Merge Order

```merge-order
# Rendered by /execute from the PLAN's waits_on graph; not read by the merge gate.
# One node per line, after its predecessors: <node-id> | pr|gate | after: <node-ids>
pr-repo-a-core | pr | after: -
pr-repo-a-cli | pr | after: pr-repo-a-core
```

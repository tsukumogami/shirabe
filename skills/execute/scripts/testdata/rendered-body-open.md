Ships the parser and its CLI.

---

> This is a **coordination PR** for a coordinated effort. It is docs-only and
> merges **last**, once every indexed PR has merged and finalization is complete.
> See `references/coordination-strategy.md`.

topic=t
mode=coordinated
store=github
run=00112233445566778899aabbccddeeff

## PR Index

- pr-repo-a-core | acme/repo-a:docs/plans/PLAN-t.md#11 | open | head=1111111111111111111111111111111111111111
- pr-repo-a-cli | acme/repo-a:docs/plans/PLAN-t.md#12 | open | head=2222222222222222222222222222222222222222

## Merge Order

```merge-order
# Rendered by /execute from the PLAN's waits_on graph; not read by the merge gate.
# One node per line, after its predecessors: <node-id> | pr|gate | after: <node-ids>
pr-repo-a-core | pr | after: -
pr-repo-a-cli | pr | after: pr-repo-a-core
```

---
# A fixture for scripts/check-koto-floor.sh: a batch child that should fail. It
# reaches a `failure: true` terminal on its first tick. The /execute batch
# scenarios that materialized it left when execute.md's floor moved to
# koto 0.13.0; it stays as a compiled template and as a helper-test
# input (a template with no declarations).
name: koto-floor-child-failure
version: "1.0"
description: A batch child that fails on its first tick.
initial_state: work
states:
  work:
    transitions:
      - target: failed
        context_assignments:
          failure_reason: "fixture child fails by design"
  failed:
    terminal: true
    failure: true
    accepts:
      failure_reason:
        type: string
        description: Why the child failed.
---

## work

Nothing to do.

## failed

Failed by design.

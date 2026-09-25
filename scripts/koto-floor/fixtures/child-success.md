---
# A fixture for scripts/check-koto-floor.sh: a batch child that should succeed.
# It reaches its success terminal on its first tick. The /execute batch
# scenarios that materialized it left when execute.md's floor moved to
# koto 0.13.0; it stays as a compiled template and as a helper-test
# input (a template with no decider key).
name: koto-floor-child-success
version: "1.0"
description: A batch child that finishes on its first tick.
initial_state: work
states:
  work:
    transitions:
      - target: done
  done:
    terminal: true
---

## work

Nothing to do.

## done

Finished.

---
# A fixture for scripts/check-koto-floor.sh: the child a batch scenario
# materializes when the task should succeed. It reaches its success terminal on
# its first tick.
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

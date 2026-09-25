---
# A fixture for scripts/check-koto-floor.sh, not a shipped template. It carries
# an accepts field with a `decider` block in its smallest form. The strip,
# compile-identity, and escape-collection steps run against it as well as
# against the shipped declarations, so the test has a fixed case whose expected
# results don't move when a shipped template changes, and the decider-fixture
# scenario drives it to show that koto v0.12.2 never offers the escape value.
name: koto-floor-decider
version: "1.0"
description: A single question whose field declares a decider.
initial_state: question
variables:
  ITEM:
    description: The item the question is about.
    required: false
    default: fixture
states:
  question:
    accepts:
      verdict:
        type: enum
        values: [proceed, exit]
        required: true
        description: Is the item clear enough to proceed?
        decider:
          answers:
            proceed: {description: "Names a concrete change with checkable criteria.", threshold: 0.92}
            exit: {description: "Vague, contradictory, or needs design first.", mode: never}
          escape: {value: unclear, description: "Missing, truncated, or unjudgeable."}
          inputs:
            - {var: ITEM, label: item}
    transitions:
      - target: done
        when:
          verdict: proceed
      - target: stopped
        when:
          verdict: exit
        context_assignments:
          failure_reason: "the item was not clear enough"
  done:
    terminal: true
  stopped:
    terminal: true
    failure: true
    accepts:
      failure_reason:
        type: string
        description: Why the question stopped the run.
---

## question

Decide whether {{ITEM}} is clear enough to proceed.

## done

Proceeding.

## stopped

Stopped.

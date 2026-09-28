---
name: jev-spike-pr-body-summary
version: "1.0"
description: Spike fixture, not a workflow; no shirabe skill loads it. One jev-accuracy criterion as a two-value enum with an escape, for koto decider report --fixtures.
initial_state: load
states:
  load:
    gates:
      pr_body_part1:
        type: context-exists
        key: pr_body_part1
    transitions:
      - target: grade
        when:
          gates.pr_body_part1.exists: true
  grade:
    accepts:
      verdict:
        type: enum
        values: [pass, fail]
        required: true
        description: "Is the pr_body_part1 text a factual description of the change the pull request makes?"
        decider:
          answers:
            pass: {description: "It states what the change does, in factual prose."}
            fail: {description: "It is something else: process narration, a test plan, reviewer notes, marketing, or too vague to say what changed."}
          escape: {value: unclear, description: "The text is empty or truncated, so it can't be judged."}
          inputs:
            - {context: pr_body_part1, label: pr_body_part1}
    transitions:
      - target: done
        when:
          verdict: pass
      - target: done
        when:
          verdict: fail
  done:
    terminal: true
---

## load

Load the inputs.

## grade

Grade the text.

## done

Done.

---
name: jev-spike-comment-reason
version: "1.0"
description: Spike fixture, not a workflow; no shirabe skill loads it. One jev-accuracy criterion as a two-value enum with an escape, for koto decider report --fixtures.
initial_state: load
states:
  load:
    gates:
      comment:
        type: context-exists
        key: comment
      code:
        type: context-exists
        key: code
    transitions:
      - target: grade
        when:
          gates.comment.exists: true
          gates.code.exists: true
  grade:
    accepts:
      verdict:
        type: enum
        values: [pass, fail]
        required: true
        description: "Does the comment record why the code is shaped this way, rather than restating what the code does?"
        decider:
          answers:
            pass: {description: "It gives a reason, constraint, or rejected alternative that the code can't show."}
            fail: {description: "It restates what the code does, or its reason is only a restatement."}
          escape: {value: unclear, description: "The comment or the code is missing, so it can't be judged."}
          inputs:
            - {context: comment, label: comment}
            - {context: code, label: code}
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

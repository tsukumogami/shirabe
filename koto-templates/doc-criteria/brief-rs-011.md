---
name: doc-criteria/brief-rs-011
version: "1.0"
description: Grades each User Journeys subsection of a BRIEF against rs-011 in shadow, for telemetry. A throwaway child session; nothing reads its answers.
initial_state: grade
variables:
  DOC:
    description: The document under review, a path under its repository's docs/
    required: true
    pattern: "[A-Za-z0-9._/@+-]+"
  COMMIT:
    description: The full commit id whose blob of DOC is graded
    required: true
    pattern: "[0-9a-f]{40}([0-9a-f]{24})?"
  PLUGIN_ROOT:
    description: The shirabe plugin root, where scripts/doc-criteria/slice.py lives
    required: true
    pattern: "[A-Za-z0-9._/@+-]+"
states:
  grade:
    gates:
      doc_criteria:
        type: decider-check
        command: "python3 \"{{PLUGIN_ROOT}}/scripts/doc-criteria/slice.py\" rs-011 brief --doc \"{{DOC}}\" --commit \"{{COMMIT}}\""
        label: user_journey
        max_bytes: 2560
        units: jsonl
        max_units: 8
        unit_document: brief
        unit_section: user-journeys
        criteria:
          rs-011:
            rule_ref: "https://github.com/tsukumogami/shirabe/blob/main/references/jev-criteria.md#brief-rs-011"
            question: "A complete user journey has three parts: who (a named role, not just \"the user\"), why now (an event or need that happens before the role acts), and what they get (a result stated after the action, not just the action itself). Does this journey have all three parts?"
            pass: "All three parts are there: a named role, an event or need that happens first, and a stated result the role gets after acting."
            fail: "At least one part is missing: the journey says only \"the user\"; or it begins with the role already doing the task with nothing that happened first; or it ends with the role's action and never states the result they get."
            escape: "The text isn't a user journey, or it is empty or cut so its meaning can't be read."
            threshold: 0.7
            mode: shadow
    transitions:
      - target: done
  done:
    terminal: true
---

## grade

This session grades each User Journeys subsection of a BRIEF against rs-011, one unit at a time, in
shadow. It records its answers as telemetry and nothing acts on them. The step
that opened it ticks it once and cancels it if it is left waiting; no agent
drives it and no answer is asked for.

## done

Graded.

---
name: doc-criteria/prd-rs-013
version: "1.0"
description: Grades each acceptance criterion of a PRD against rs-013 in shadow, for telemetry. A throwaway child session; nothing reads its answers.
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
        command: "python3 \"{{PLUGIN_ROOT}}/scripts/doc-criteria/slice.py\" rs-013 prd --doc \"{{DOC}}\" --commit \"{{COMMIT}}\""
        label: acceptance_criterion
        max_bytes: 2560
        units: jsonl
        max_units: 32
        unit_document: prd
        unit_section: acceptance-criteria
        criteria:
          rs-013:
            rule_ref: "https://github.com/tsukumogami/shirabe/blob/main/references/jev-criteria.md#prd-rs-013"
            question: "Can this acceptance criterion be answered yes or no by someone who didn't write it, without any judgment call?"
            pass: "The criterion names an observable result with a definite measure or value, so any tester checking it gets the same yes or no."
            fail: "Answering the criterion takes a judgment call: it uses a word such as fast, easy, clear, intuitive, reasonable, appropriate or many with no measure, or it describes how the code is written or how it should feel instead of a result a tester can observe."
            escape: "The text isn't an acceptance criterion, or it is empty or cut so its meaning can't be read."
            mode: shadow
    transitions:
      - target: done
  done:
    terminal: true
---

## grade

This session grades each acceptance criterion of a PRD against rs-013, one unit at a time, in
shadow. It records its answers as telemetry and nothing acts on them. The step
that opened it ticks it once and cancels it if it is left waiting; no agent
drives it and no answer is asked for.

## done

Graded.

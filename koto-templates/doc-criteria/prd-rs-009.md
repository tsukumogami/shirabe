---
name: doc-criteria/prd-rs-009
version: "1.0"
description: Grades each pair of passages of a PRD that share a backticked term or a number against rs-009 in shadow, for telemetry. A throwaway child session; nothing reads its answers.
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
        command: "python3 \"{{PLUGIN_ROOT}}/scripts/doc-criteria/slice.py\" rs-009 prd --doc \"{{DOC}}\" --commit \"{{COMMIT}}\""
        label: passage_pair
        max_bytes: 2560
        units: jsonl
        max_units: 32
        unit_document: prd
        unit_section: document
        criteria:
          rs-009:
            rule_ref: "https://github.com/tsukumogami/shirabe/blob/main/references/jev-criteria.md#prd-rs-009"
            question: "Are these two passages from the same document consistent with each other?"
            pass: "The two passages agree, or talk about different things."
            fail: "The two passages state conflicting facts about the same thing, such as different numbers, names, statuses or behaviour."
            escape: "A passage is empty, or cut so that it can't be judged."
            threshold: 0.85
            mode: shadow
    transitions:
      - target: done
  done:
    terminal: true
---

## grade

This session grades each pair of passages of a PRD that share a backticked term or a number against rs-009, one unit at a time, in
shadow. It records its answers as telemetry and nothing acts on them. The step
that opened it ticks it once and cancels it if it is left waiting; no agent
drives it and no answer is asked for.

## done

Graded.

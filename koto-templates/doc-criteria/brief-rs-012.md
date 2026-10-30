---
name: doc-criteria/brief-rs-012
version: "1.0"
description: Grades each frontmatter summary of a BRIEF beside the section it summarizes against rs-012 in shadow, for telemetry. A throwaway child session; nothing reads its answers.
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
        command: "python3 \"{{PLUGIN_ROOT}}/scripts/doc-criteria/slice.py\" rs-012 brief --doc \"{{DOC}}\" --commit \"{{COMMIT}}\""
        label: summary_and_section
        max_bytes: 2560
        units: jsonl
        max_units: 2
        unit_document: brief
        unit_section: frontmatter
        criteria:
          rs-012:
            rule_ref: "https://github.com/tsukumogami/shirabe/blob/main/references/jev-criteria.md#brief-rs-012"
            question: "Does the frontmatter summary say the same thing as the section text below it, with no fact that conflicts?"
            pass: "The summary restates or condenses the section text, or covers only part of it, and every fact it gives (who, what, when, how often, how many, whether something happens) matches the section."
            fail: "The summary is about a different problem or outcome, or one of its facts conflicts with the section, such as hourly against weekly, dropped against kept, or a different person or number."
            escape: "The summary or the section is empty, or the shown part of the section is too short to judge."
            mode: shadow
    transitions:
      - target: done
  done:
    terminal: true
---

## grade

This session grades each frontmatter summary of a BRIEF beside the section it summarizes against rs-012, one unit at a time, in
shadow. It records its answers as telemetry and nothing acts on them. The step
that opened it ticks it once and cancels it if it is left waiting; no agent
drives it and no answer is asked for.

## done

Graded.

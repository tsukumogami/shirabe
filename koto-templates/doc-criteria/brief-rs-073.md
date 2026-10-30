---
name: doc-criteria/brief-rs-073
version: "1.0"
description: Grades each Scope Boundary bullet of a BRIEF against rs-073 in shadow, for telemetry. A throwaway child session; nothing reads its answers.
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
        command: "python3 \"{{PLUGIN_ROOT}}/scripts/doc-criteria/slice.py\" rs-073 brief --doc \"{{DOC}}\" --commit \"{{COMMIT}}\""
        label: scope_boundary_bullet
        max_bytes: 2560
        units: jsonl
        max_units: 32
        unit_document: brief
        unit_section: scope-boundary
        criteria:
          rs-073:
            rule_ref: "https://github.com/tsukumogami/shirabe/blob/main/references/jev-criteria.md#brief-rs-073"
            question: "Does this Scope Boundary bullet stay at the feature's altitude, naming no function, data structure, field, flag, script, file path or command?"
            pass: "The bullet describes a capability, a behaviour, an audience or a piece of work in plain words, and names no function, data structure, field, flag, script, file path or command."
            fail: "The bullet names a function, a data structure, a field, a flag, a script, a file path or a command, even beside a plain description: that is how the feature is built, which belongs in the design rather than the brief's scope."
            escape: "The text isn't a Scope Boundary bullet, or it is empty or cut so its meaning can't be read."
            mode: shadow
    transitions:
      - target: done
  done:
    terminal: true
---

## grade

This session grades each Scope Boundary bullet of a BRIEF against rs-073, one unit at a time, in
shadow. It records its answers as telemetry and nothing acts on them. The step
that opened it ticks it once and cancels it if it is left waiting; no agent
drives it and no answer is asked for.

## done

Graded.

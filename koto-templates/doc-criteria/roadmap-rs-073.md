---
name: doc-criteria/roadmap-rs-073
version: "1.0"
description: Grades each Evidence clause of a ROADMAP milestone against rs-073 in shadow, for telemetry. A throwaway child session; nothing reads its answers.
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
        command: "python3 \"{{PLUGIN_ROOT}}/scripts/doc-criteria/slice.py\" rs-073 roadmap --doc \"{{DOC}}\" --commit \"{{COMMIT}}\""
        label: evidence_clause
        max_bytes: 2560
        units: jsonl
        max_units: 32
        unit_document: roadmap
        unit_section: milestones
        criteria:
          rs-073:
            rule_ref: "https://github.com/tsukumogami/shirabe/blob/main/references/jev-criteria.md#roadmap-rs-073"
            question: "Does this Evidence clause describe the check only by what a person does and sees, naming no source file, script, function or line that implements the check or the feature?"
            pass: "The clause says what someone checking the milestone does and observes (a command they run and its output, a walkthrough, a visible result) and names no source file, script, function or line of the implementation."
            fail: "The clause names a source file, a script, a function or a line of the implementation (such as src/find.rs, `scripts/check.sh` passes, or `module::function` returns a value), even beside what a person sees: that is the mechanism, not the check."
            escape: "The text isn't an Evidence clause, or it is empty or cut so its meaning can't be read."
            mode: shadow
    transitions:
      - target: done
  done:
    terminal: true
---

## grade

This session grades each Evidence clause of a ROADMAP milestone against rs-073, one unit at a time, in
shadow. It records its answers as telemetry and nothing acts on them. The step
that opened it ticks it once and cancels it if it is left waiting; no agent
drives it and no answer is asked for.

## done

Graded.

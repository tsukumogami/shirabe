---
name: doc-criteria/strategy-rs-074
version: "1.0"
description: Grades each Bet-Specific Falsifiability bullet of a STRATEGY beside the claim it names against rs-074 in shadow, for telemetry. A throwaway child session; nothing reads its answers.
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
        command: "python3 \"{{PLUGIN_ROOT}}/scripts/doc-criteria/slice.py\" rs-074 strategy --doc \"{{DOC}}\" --commit \"{{COMMIT}}\""
        label: falsifier_and_claim
        max_bytes: 2560
        units: jsonl
        max_units: 32
        unit_document: strategy
        unit_section: bet-specific-falsifiability
        criteria:
          rs-074:
            rule_ref: "https://github.com/tsukumogami/shirabe/blob/main/references/jev-criteria.md#strategy-rs-074"
            question: "Is the condition in this falsifier about the same thing as the claim shown beside it, so that observing the condition would show that claim wrong?"
            pass: "The condition tests the claim shown beside it: it measures the very thing the claim promises (the same product, the same people, the same quantity)."
            fail: "The condition is about something other than the claim shown beside it (another product, other people or another quantity), so observing it would say nothing about that claim."
            escape: "No claim is shown beside the bullet, or a text is empty or cut so it can't be judged."
            mode: shadow
    transitions:
      - target: done
  done:
    terminal: true
---

## grade

This session grades each Bet-Specific Falsifiability bullet of a STRATEGY beside the claim it names against rs-074, one unit at a time, in
shadow. It records its answers as telemetry and nothing acts on them. The step
that opened it ticks it once and cancels it if it is left waiting; no agent
drives it and no answer is asked for.

## done

Graded.

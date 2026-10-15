---
schema: plan/v2
status: Active
execution_mode: single-pr
milestone: "greeting command"
step_count: 3
---

# PLAN: greeting command

## Status

Active

## Scope Summary

Add a `greet` command that prints a greeting for a name, then lets the
greeting come from a config file.

## Decomposition Strategy

**Walking skeleton.** Step 1 runs `greet` end to end with a fixed greeting,
so every later step adds one behaviour a person can see by running it.

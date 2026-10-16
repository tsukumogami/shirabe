---
schema: plan/v2
status: Active
execution_mode: single-pr
milestone: "greeting command"
step_count: 4
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

## Steps

### Step 1: greet prints a fixed greeting for a name

`greet Ada` prints `Hello, Ada`.

### Step 2: greet reads the greeting from a config file

A `greeting` value in the config file changes what `greet` prints.

### Step 3: greet refuses a config file it cannot read

A config file that does not parse stops `greet` with a message naming the file.

### Step 4: greet greets several names at once

`greet Ada Grace` prints one greeting line per name, in the order given.

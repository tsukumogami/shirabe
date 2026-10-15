---
schema: plan/v2
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-greeting.md
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

## Steps

### Step 1: greet prints a fixed greeting for a name

**Goal**: The command line reaches the greeting code and prints its result,
run on the name `Ada`.

**Acceptance Criteria**:

- [x] `greet Ada` prints `Hello, Ada` and exits 0.

**Check**: Run `greet Ada` and see `Hello, Ada` with exit 0.

**Dependencies**: None

### Step 2: greet reads the greeting from a config file

**Goal**: A `greeting` value in the config file changes what `greet` prints.

**Acceptance Criteria**:

- [x] With `greeting = "Hi"` in the config file, `greet Ada` prints `Hi, Ada`.

**Check**: Write the config file, run `greet Ada`, and see `Hi, Ada`.

**Dependencies**: Step 1

### Step 3: greet refuses a config file it cannot read

**Goal**: A config file that does not parse stops `greet` with a message naming the file.

**Acceptance Criteria**:

- [x] With a config file that does not parse, `greet Ada` prints a message naming the file and exits 2.

**Check**: Write a malformed config file, run `greet Ada`, and see the message and exit 2.

**Dependencies**: Step 2

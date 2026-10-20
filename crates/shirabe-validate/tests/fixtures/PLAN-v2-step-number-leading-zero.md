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

**Goal**: The command line reaches the greeting code and prints its result,
run on the name `Ada`.

**Acceptance Criteria**:

- [ ] `greet Ada` prints `Hello, Ada` and exits 0.
- [ ] `greet` with no name prints a usage line and exits 2.

**Check**: Run `greet Ada` and see `Hello, Ada` with exit 0.

**Dependencies**: None

**Files**: `src/greet.rs`

### Step 2: greet reads the greeting from a config file

**Goal**: A `greeting` value in the config file changes what `greet` prints.

**Acceptance Criteria**:

- [ ] With `greeting = "Hi"` in the config file, `greet Ada` prints `Hi, Ada`.
- [ ] With no config file, `greet Ada` still prints `Hello, Ada`.

**Check**: Write the config file, run `greet Ada`, and see `Hi, Ada`.

**Dependencies**: Step 1

### Step 03: greet refuses a config file it cannot read

A step number with a leading zero.

### Step 3: greet refuses a config file it cannot read

A config file that does not parse stops `greet` with a message naming the file.

### Step 4: greet greets several names at once

`greet Ada Grace` prints one greeting line per name, in the order given.

---
schema: plan/v2
status: Active
execution_mode: single-pr
milestone: "word count command"
step_count: 4
---

# PLAN: word count command

## Status

Active

## Scope Summary

Add a `wc-lite` command that counts the words in a file, then lets it count
lines and read from standard input.

## Decomposition Strategy

**Walking skeleton.** Step 1 runs `wc-lite` end to end on one file, so every
later step adds one behaviour a person can see by running it.

## Steps

### Step 1: wc-lite prints the word count of a file

**Goal**: The command line reaches the counting code and prints its result,
run on a file holding three words.

**Acceptance Criteria**:

- [ ] `wc-lite three.txt` prints `3` and exits 0.
- [ ] `wc-lite` with no file prints a usage line and exits 2.

**Check**: Run `wc-lite three.txt` and see `3` with exit 0.

**Dependencies**: None

**Files**: `src/wc.rs`

### Step 2: wc-lite counts lines with --lines

**Goal**: `--lines` switches the count from words to lines.

**Acceptance Criteria**:

- [ ] `wc-lite --lines two-lines.txt` prints `2`.
- [ ] Without `--lines`, the same file still prints its word count.

**Check**: Run `wc-lite --lines two-lines.txt` and see `2`.

**Dependencies**: Step 1

### Step 3: wc-lite reads standard input when no file is given

A pipe into `wc-lite -` is counted the way a file is.

### Step 4: wc-lite refuses a file it cannot read

A missing or unreadable file stops `wc-lite` with a message naming the file.
